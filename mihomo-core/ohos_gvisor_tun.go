package main

import (
	"context"
	"fmt"
	"net/netip"
	"os"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/metacubex/gvisor/pkg/buffer"
	"github.com/metacubex/gvisor/pkg/tcpip"
	"github.com/metacubex/gvisor/pkg/tcpip/header"
	"github.com/metacubex/gvisor/pkg/tcpip/stack"
	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/component/resolver"
	CConst "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/listener/sing"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	tun "github.com/metacubex/sing-tun"
)

// ohosGVisorAdapter runs Mihomo's full userspace gVisor TCP/IP stack directly
// over HarmonyOS VpnExtensionAbility's TUN file descriptor using pure os.File
// Read/Write (avoiding Linux fdbased/eventfd/Getsockname incompatibilities and
// System-stack kernel loopback conflicts with protectProcessNet).
type ohosGVisorAdapter struct {
	tunIf       *ohosFileTun
	tunStack    tun.Stack
	dnsServerIp []string
}

func startOhosGVisorTun(rawFd int, mtu uint32, inet4Prefix netip.Prefix, enableIpv6 bool) (*ohosGVisorAdapter, error) {
	if rawFd <= 0 {
		return nil, fmt.Errorf("invalid tun fd: %d", rawFd)
	}
	if mtu == 0 {
		mtu = 1500
	}

	// Duplicate fd so closing ohosFileTun never races with HarmonyOS vpnConnection.destroy()
	dupFd, err := syscall.Dup(rawFd)
	if err != nil {
		return nil, fmt.Errorf("dup tun fd %d failed: %w", rawFd, err)
	}
	_ = syscall.SetNonblock(dupFd, true)

	file := os.NewFile(uintptr(dupFd), "vpn-tun")
	if file == nil {
		_ = syscall.Close(dupFd)
		return nil, fmt.Errorf("os.NewFile failed for fd %d", dupFd)
	}

	inet4List := []netip.Prefix{inet4Prefix}
	var inet6List []netip.Prefix
	if enableIpv6 {
		if p6, err := netip.ParsePrefix("fdfe:dcba:9876::1/126"); err == nil {
			inet6List = []netip.Prefix{p6}
		}
	}

	dnsAddrs := []netip.AddrPort{
		netip.AddrPortFrom(netip.IPv4Unspecified(), 53),
		netip.AddrPortFrom(inet4Prefix.Addr().Next(), 53),
	}
	dnsServerIp := []string{inet4Prefix.Addr().Next().String()}

	baseHandler, err := sing.NewListenerHandler(sing.ListenerConfig{
		Tunnel: tunnel.Tunnel,
		Type:   CConst.TUN,
		Additions: []inbound.Addition{
			inbound.WithInName("DEFAULT-TUN"),
			inbound.WithSpecialRules(""),
		},
	})
	if err != nil {
		_ = file.Close()
		return nil, fmt.Errorf("create sing listener handler failed: %w", err)
	}

	handler := &sing_tun.ListenerHandler{
		ListenerHandler:       baseHandler,
		DnsAddrPorts:          dnsAddrs,
		Inet4Address:          inet4List,
		Inet6Address:          inet6List,
		DisableICMPForwarding: true,
	}

	ohosTun := &ohosFileTun{
		file: file,
		mtu:  mtu,
	}

	tunOptions := tun.Options{
		Name:         "vpn-tun",
		MTU:          mtu,
		Inet4Address: inet4List,
		Inet6Address: inet6List,
	}

	resolver.AddSystemDnsBlacklist(dnsServerIp...)

	gStack, err := tun.NewGVisor(tun.StackOptions{
		Context:    context.Background(),
		Tun:        ohosTun,
		TunOptions: tunOptions,
		UDPTimeout: sing.UDPTimeout,
		Handler:    handler,
		Logger:     log.SingLogger,
	})
	if err != nil {
		resolver.RemoveSystemDnsBlacklist(dnsServerIp...)
		_ = file.Close()
		return nil, fmt.Errorf("tun.NewGVisor failed: %w", err)
	}

	if err := gStack.Start(); err != nil {
		resolver.RemoveSystemDnsBlacklist(dnsServerIp...)
		_ = gStack.Close()
		_ = file.Close()
		return nil, fmt.Errorf("gVisor stack Start failed: %w", err)
	}

	return &ohosGVisorAdapter{
		tunIf:       ohosTun,
		tunStack:    gStack,
		dnsServerIp: dnsServerIp,
	}, nil
}

func (a *ohosGVisorAdapter) Close() {
	if a == nil {
		return
	}
	resolver.RemoveSystemDnsBlacklist(a.dnsServerIp...)
	if a.tunStack != nil {
		_ = a.tunStack.Close()
	}
	if a.tunIf != nil {
		_ = a.tunIf.Close()
	}
}

// ohosFileTun implements tun.GVisorTun using pure Go os.File Read/Write.
type ohosFileTun struct {
	file   *os.File
	mtu    uint32
	closed atomic.Bool
	wMu    sync.Mutex
}

var _ tun.GVisorTun = (*ohosFileTun)(nil)

func (t *ohosFileTun) Read(p []byte) (int, error) {
	return t.file.Read(p)
}

func (t *ohosFileTun) Write(p []byte) (int, error) {
	t.wMu.Lock()
	defer t.wMu.Unlock()
	return t.file.Write(p)
}

func (t *ohosFileTun) Close() error {
	if t.closed.Swap(true) {
		return nil
	}
	return t.file.Close()
}

func (t *ohosFileTun) writeSlices(slices [][]byte) (int, error) {
	if t.closed.Load() {
		return 0, os.ErrClosed
	}
	total := 0
	for _, s := range slices {
		total += len(s)
	}
	if total == 0 {
		return 0, nil
	}
	if len(slices) == 1 {
		return t.Write(slices[0])
	}
	flat := make([]byte, total)
	off := 0
	for _, s := range slices {
		copy(flat[off:], s)
		off += len(s)
	}
	return t.Write(flat)
}

func (t *ohosFileTun) WritePacket(pkt *stack.PacketBuffer) (int, error) {
	return t.writeSlices(pkt.AsSlices())
}

func (t *ohosFileTun) NewEndpoint() (stack.LinkEndpoint, stack.NICOptions, error) {
	return &ohosGVisorEndpoint{tun: t}, stack.NICOptions{}, nil
}

// ohosGVisorEndpoint implements gVisor stack.LinkEndpoint using pure os.File Read/Write.
type ohosGVisorEndpoint struct {
	tun        *ohosFileTun
	mu         sync.RWMutex
	dispatcher stack.NetworkDispatcher
	wg         sync.WaitGroup
}

var _ stack.LinkEndpoint = (*ohosGVisorEndpoint)(nil)

func (e *ohosGVisorEndpoint) MTU() uint32 {
	return e.tun.mtu
}

func (e *ohosGVisorEndpoint) SetMTU(mtu uint32) {
	e.tun.mtu = mtu
}

func (e *ohosGVisorEndpoint) MaxHeaderLength() uint16 {
	return 0
}

func (e *ohosGVisorEndpoint) LinkAddress() tcpip.LinkAddress {
	return ""
}

func (e *ohosGVisorEndpoint) SetLinkAddress(addr tcpip.LinkAddress) {}

func (e *ohosGVisorEndpoint) Capabilities() stack.LinkEndpointCapabilities {
	return stack.CapabilityRXChecksumOffload
}

func (e *ohosGVisorEndpoint) Attach(dispatcher stack.NetworkDispatcher) {
	e.mu.Lock()
	if dispatcher == nil {
		e.dispatcher = nil
		e.mu.Unlock()
		_ = e.tun.Close()
		return
	}
	alreadyAttached := e.dispatcher != nil
	e.dispatcher = dispatcher
	e.mu.Unlock()

	if !alreadyAttached {
		e.wg.Add(1)
		go e.dispatchLoop()
	}
}

func (e *ohosGVisorEndpoint) dispatchLoop() {
	defer e.wg.Done()
	readBuf := make([]byte, int(e.tun.mtu)+256)
	for {
		n, err := e.tun.file.Read(readBuf)
		if err != nil {
			if e.tun.closed.Load() {
				return
			}
			// Transient non-blocking / interrupt errors: retry briefly
			time.Sleep(2 * time.Millisecond)
			if e.tun.closed.Load() {
				return
			}
			continue
		}
		if n <= 0 {
			continue
		}

		e.mu.RLock()
		dispatcher := e.dispatcher
		e.mu.RUnlock()
		if dispatcher == nil {
			return
		}

		var networkProtocol tcpip.NetworkProtocolNumber
		switch header.IPVersion(readBuf[:n]) {
		case header.IPv4Version:
			networkProtocol = header.IPv4ProtocolNumber
		case header.IPv6Version:
			networkProtocol = header.IPv6ProtocolNumber
		default:
			continue
		}

		payload := buffer.MakeWithData(readBuf[:n])
		pkt := stack.NewPacketBuffer(stack.PacketBufferOptions{
			Payload:           payload,
			IsForwardedPacket: true,
		})
		dispatcher.DeliverNetworkPacket(networkProtocol, pkt)
		pkt.DecRef()
	}
}

func (e *ohosGVisorEndpoint) IsAttached() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.dispatcher != nil
}

func (e *ohosGVisorEndpoint) Wait() {
	e.wg.Wait()
}

func (e *ohosGVisorEndpoint) ARPHardwareType() header.ARPHardwareType {
	return header.ARPHardwareNone
}

func (e *ohosGVisorEndpoint) AddHeader(_ *stack.PacketBuffer) {}

func (e *ohosGVisorEndpoint) ParseHeader(_ *stack.PacketBuffer) bool {
	return true
}

func (e *ohosGVisorEndpoint) WritePackets(packetBufferList stack.PacketBufferList) (int, tcpip.Error) {
	var count int
	for _, pkt := range packetBufferList.AsSlice() {
		if _, err := e.tun.writeSlices(pkt.AsSlices()); err != nil {
			return count, &tcpip.ErrAborted{}
		}
		count++
	}
	return count, nil
}

func (e *ohosGVisorEndpoint) Close() {
	_ = e.tun.Close()
}

func (e *ohosGVisorEndpoint) SetOnCloseAction(_ func()) {}
