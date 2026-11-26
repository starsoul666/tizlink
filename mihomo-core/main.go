package main

/*
#include <stdlib.h>

typedef int (*protect_fn)(int fd);

static protect_fn g_protect_fn = NULL;

static inline void set_protect_func(protect_fn fn) {
    g_protect_fn = fn;
}

static inline int call_protect(int fd) {
    if (g_protect_fn != NULL) {
        return g_protect_fn(fd);
    }
    return 1;
}
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/iface"
	"github.com/metacubex/mihomo/component/resolver"
	CConst "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

var (
	mu         sync.Mutex
	running    atomic.Bool
	initialized atomic.Bool

	logMu      sync.Mutex
	logRing    []string
	maxLogSize = 400
	logSubOnce sync.Once
)

func appendLog(line string) {
	logMu.Lock()
	defer logMu.Unlock()
	logRing = append(logRing, line)
	if len(logRing) > maxLogSize {
		logRing = logRing[len(logRing)-maxLogSize:]
	}
}

func startLogCollector() {
	logSubOnce.Do(func() {
		sub := log.Subscribe()
		go func() {
			for ev := range sub {
				ts := time.Now().Format("15:04:05")
				appendLog(fmt.Sprintf("[%s][%s] %s", ts, ev.Type(), ev.Payload))
			}
		}()
	})
}

func setupProtectHook() {
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		var protectErr error
		err := conn.Control(func(fd uintptr) {
			ok := C.call_protect(C.int(fd))
			if ok == 0 {
				protectErr = fmt.Errorf("protect(%d) failed", fd)
			}
		})
		if err != nil {
			return err
		}
		return protectErr
	}
}

//export Setup
func Setup(homeDir *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()

	dir := C.GoString(homeDir)
	if dir == "" {
		return C.CString("homeDir is empty")
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return C.CString(fmt.Sprintf("mkdir homeDir failed: %v", err))
	}

	CConst.SetHomeDir(dir)
	CConst.SetConfig(filepath.Join(dir, "config.yaml"))
	startLogCollector()
	setupProtectHook()
	initialized.Store(true)
	appendLog(fmt.Sprintf("[libmihomo] Setup OK, homeDir=%s, version=%s", dir, CConst.Version))
	return C.CString("")
}

//export SetProtectCallback
func SetProtectCallback(fn C.protect_fn) {
	C.set_protect_func(fn)
	setupProtectHook()
}

//export StartTun
func StartTun(tunFd C.int, configYaml *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()

	yamlStr := C.GoString(configYaml)
	if strings.TrimSpace(yamlStr) == "" {
		return C.CString("config yaml is empty")
	}

	if running.Load() {
		executor.Shutdown()
		running.Store(false)
	}

	cfg, err := executor.ParseWithBytes([]byte(yamlStr))
	if err != nil {
		msg := fmt.Sprintf("parse config failed: %v", err)
		appendLog("[libmihomo] " + msg)
		return C.CString(msg)
	}

	// Bind HarmonyOS VpnExtensionAbility TUN fd into mihomo sing-tun
	fd := int(tunFd)
	if fd > 0 {
		cfg.General.Tun.Enable = true
		cfg.General.Tun.FileDescriptor = fd
		cfg.General.Tun.Device = "vpn-tun"
		cfg.General.Tun.Stack = CConst.TunGvisor
		cfg.General.Tun.AutoRoute = false
		cfg.General.Tun.AutoDetectInterface = false
		cfg.General.Tun.AutoRedirect = false
		if cfg.General.Tun.MTU == 0 {
			cfg.General.Tun.MTU = 1500
		}
		if len(cfg.General.Tun.Inet4Address) == 0 {
			if p, err := netip.ParsePrefix("172.19.0.1/30"); err == nil {
				cfg.General.Tun.Inet4Address = []netip.Prefix{p}
			}
		}
		if len(cfg.General.Tun.DNSHijack) == 0 {
			cfg.General.Tun.DNSHijack = []string{"any:53"}
		}
	}

	statistic.DefaultManager.ResetStatistic()
	hub.ApplyConfig(cfg)
	running.Store(true)
	appendLog(fmt.Sprintf("[libmihomo] StartTun OK (fd=%d, proxies=%d)", fd, len(cfg.Proxies)))
	return C.CString("")
}

//export Stop
func Stop() {
	mu.Lock()
	defer mu.Unlock()

	if !running.Load() {
		return
	}
	listener.Cleanup()
	executor.Shutdown()
	tunnel.UpdateProxies(nil, nil)
	running.Store(false)
	appendLog("[libmihomo] Stopped")
}

//export IsRunning
func IsRunning() C.int {
	if running.Load() {
		return 1
	}
	return 0
}

//export SetLogLevel
func SetLogLevel(level *C.char) {
	lv := strings.ToLower(strings.TrimSpace(C.GoString(level)))
	switch lv {
	case "debug":
		log.SetLevel(log.DEBUG)
	case "info":
		log.SetLevel(log.INFO)
	case "warning", "warn":
		log.SetLevel(log.WARNING)
	case "error":
		log.SetLevel(log.ERROR)
	case "silent":
		log.SetLevel(log.SILENT)
	default:
		log.SetLevel(log.INFO)
	}
}

//export NotifyNetworkChange
func NotifyNetworkChange() {
	iface.FlushCache()
	resolver.ClearCache()
	appendLog("[libmihomo] Network change notified, caches flushed")
}

type trafficSnapshot struct {
	Up        int64 `json:"up"`
	Down      int64 `json:"down"`
	UpTotal   int64 `json:"upTotal"`
	DownTotal int64 `json:"downTotal"`
}

//export GetTraffic
func GetTraffic() *C.char {
	up, down := statistic.DefaultManager.Now()
	upTotal, downTotal := statistic.DefaultManager.Total()
	data, _ := json.Marshal(trafficSnapshot{
		Up:        up,
		Down:      down,
		UpTotal:   upTotal,
		DownTotal: downTotal,
	})
	return C.CString(string(data))
}

//export GetVersion
func GetVersion() *C.char {
	return C.CString("mihomo " + CConst.Version + " (harmonyos-aegis-mux2)")
}

//export GetLogs
func GetLogs() *C.char {
	logMu.Lock()
	defer logMu.Unlock()
	joined := strings.Join(logRing, "\n")
	return C.CString(joined)
}

//export ClearLogs
func ClearLogs() {
	logMu.Lock()
	defer logMu.Unlock()
	logRing = nil
}

//export FreeString
func FreeString(ptr *C.char) {
	if ptr != nil {
		C.free(unsafe.Pointer(ptr))
	}
}

func main() {}
