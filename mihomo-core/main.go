package main

/*
#include <stdlib.h>

typedef int (*protect_fn)(int fd);
typedef void (*log_fn)(const char* msg);

static protect_fn g_protect_fn = NULL;
static log_fn g_log_fn = NULL;

static inline void set_protect_func(protect_fn fn) {
    g_protect_fn = fn;
}

static inline int call_protect(int fd) {
    if (g_protect_fn != NULL) {
        return g_protect_fn(fd);
    }
    return 1;
}

static inline void set_log_func(log_fn fn) {
    g_log_fn = fn;
}

static inline void call_log(const char* msg) {
    if (g_log_fn != NULL && msg != NULL) {
        g_log_fn(msg);
    }
}
*/
import "C"

import (
	_ "embed"
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
	mdns "github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

//go:embed cacert.pem
var embeddedCACerts []byte

var (
	mu          sync.Mutex
	running     atomic.Bool
	initialized atomic.Bool

	logMu      sync.Mutex
	logRing    []string
	maxLogSize = 400
	logSubOnce sync.Once
)

func appendLog(line string) {
	logMu.Lock()
	logRing = append(logRing, line)
	if len(logRing) > maxLogSize {
		logRing = logRing[len(logRing)-maxLogSize:]
	}
	logMu.Unlock()

	cmsg := C.CString(line)
	C.call_log(cmsg)
	C.free(unsafe.Pointer(cmsg))
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

	// HarmonyOS sandbox blocks /etc/ssl/certs; provide embedded Mozilla CA bundle via SSL_CERT_FILE
	if len(embeddedCACerts) > 0 {
		certPath := filepath.Join(dir, "cacert.pem")
		needWrite := true
		if st, err := os.Stat(certPath); err == nil && st.Size() == int64(len(embeddedCACerts)) {
			needWrite = false
		}
		if needWrite {
			if err := os.WriteFile(certPath, embeddedCACerts, 0o644); err != nil {
				appendLog(fmt.Sprintf("[libmihomo] write cacert.pem failed: %v", err))
			}
		}
		_ = os.Setenv("SSL_CERT_FILE", certPath)
	}

	mdns.UpdateSystemDNS([]string{"223.5.5.5", "119.29.29.29"})

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

//export SetLogCallback
func SetLogCallback(fn C.log_fn) {
	C.set_log_func(fn)
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
		listener.Cleanup()
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
	var dupFd int
	if fd > 0 {
		var st syscall.Stat_t
		if stErr := syscall.Fstat(fd, &st); stErr != nil {
			appendLog(fmt.Sprintf("[libmihomo] Fstat(fd=%d) err: %v", fd, stErr))
		} else {
			appendLog(fmt.Sprintf("[libmihomo] Fstat(fd=%d) mode=0x%x, dev=%d, ino=%d", fd, st.Mode, st.Dev, st.Ino))
		}
		if nbErr := syscall.SetNonblock(fd, true); nbErr != nil {
			appendLog(fmt.Sprintf("[libmihomo] SetNonblock(%d) warn: %v", fd, nbErr))
		}
		if d, dErr := syscall.Dup(fd); dErr == nil {
			dupFd = d
		} else {
			dupFd = fd
		}
		cfg.General.Tun.Enable = true
		cfg.General.Tun.FileDescriptor = dupFd
		cfg.General.Tun.Device = "vpn-tun"
		cfg.General.Tun.Stack = CConst.TunGvisor
		cfg.General.Tun.AutoRoute = false
		cfg.General.Tun.AutoDetectInterface = false
		cfg.General.Tun.AutoRedirect = false
		cfg.General.Tun.MTU = 1500
		if p, err := netip.ParsePrefix("172.19.0.1/30"); err == nil {
			cfg.General.Tun.Inet4Address = []netip.Prefix{p}
		}
		cfg.General.Tun.DNSHijack = []string{"any:53"}
	}

	statistic.DefaultManager.ResetStatistic()
	hub.ApplyConfig(cfg)

	tunConf := listener.GetTunConf()
	if fd > 0 && !tunConf.Enable {
		gvisorErr := findLastTunError()
		appendLog(fmt.Sprintf("[libmihomo] gVisor TUN failed (%s), falling back to System stack...", gvisorErr))
		sysFd := fd
		if d, dErr := syscall.Dup(fd); dErr == nil {
			sysFd = d
		}
		sysTun := cfg.General.Tun
		sysTun.Enable = true
		sysTun.FileDescriptor = sysFd
		sysTun.Stack = CConst.TunSystem
		listener.ReCreateTun(sysTun, tunnel.Tunnel)
		tunConf = listener.GetTunConf()
		if !tunConf.Enable {
			sysErr := findLastTunError()
			msg := fmt.Sprintf("TUN 启动失败 (gVisor: %s | System: %s)", gvisorErr, sysErr)
			appendLog("[libmihomo] " + msg)
			return C.CString(msg)
		}
	}

	running.Store(true)
	appendLog(fmt.Sprintf("[libmihomo] StartTun OK (fd=%d, tunEnable=%v, stack=%s, addr=%v, proxies=%d)", fd, tunConf.Enable, tunConf.Stack.String(), tunConf.Inet4Address, len(cfg.Proxies)))
	return C.CString("")
}

func findLastTunError() string {
	// Wait briefly for async log subscriber to drain
	time.Sleep(50 * time.Millisecond)
	logMu.Lock()
	defer logMu.Unlock()
	for i := len(logRing) - 1; i >= 0; i-- {
		if strings.Contains(logRing[i], "Start TUN listening error") || strings.Contains(logRing[i], "[TUN]") {
			return logRing[i]
		}
	}
	if len(logRing) > 0 {
		return logRing[len(logRing)-1]
	}
	return "unknown"
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
