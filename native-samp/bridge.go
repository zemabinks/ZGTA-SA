// SPDX-License-Identifier: AGPL-3.0-only
// Independent ZGTA SA C-bridge lifecycle; transport implementation is Apache-2.0.
package main

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"zgtasa.local/native-samp/internal/raknet"
)

const (
	maxHandles    = 64
	maxEvents     = 256
	maxEventBytes = 1 << 20
	maxQueueBytes = 4 << 20
	maxSendBytes  = 8191 // Legacy reliability payload length is an unsigned 16-bit bit count.
	maxSends      = 128
	errHandle     = -1
	errCapacity   = -2
	errInput      = -3
	errQueue      = -4
)

type transportConn interface {
	Read(context.Context) ([]byte, error)
	WriteChannel(context.Context, []byte, raknet.Reliability, uint8) error
	Close() error
}
type dialFunc func(context.Context, string, string) (transportConn, error)
type transportEvent struct {
	kind int
	data []byte
}
type sendRequest struct {
	data        []byte
	reliability raknet.Reliability
	channel     uint8
}
type bridgeSession struct {
	mu               sync.Mutex
	ctx              context.Context
	cancel           context.CancelFunc
	queue            []transportEvent
	queuedBytes      int
	accepted         []byte
	closed, terminal bool
	sends            chan sendRequest
	heartbeatEvery   time.Duration
}
type bridgeManager struct {
	mu             sync.Mutex
	next           uint64
	sessions       map[uint64]*bridgeSession
	dial           dialFunc
	heartbeatEvery time.Duration
}

func newBridgeManager(dial dialFunc) *bridgeManager {
	return &bridgeManager{sessions: make(map[uint64]*bridgeSession), dial: dial, heartbeatEvery: 5 * time.Second}
}

var bridge = newBridgeManager(func(ctx context.Context, address, password string) (transportConn, error) {
	return raknet.Dial(ctx, address, password)
})

func validAddress(address string) bool {
	if len(address) == 0 || len(address) > 512 || !utf8.ValidString(address) || strings.TrimSpace(address) != address || strings.ContainsAny(address, "\x00\r\n\t") {
		return false
	}
	host, port, err := net.SplitHostPort(address)
	if err != nil || host == "" {
		return false
	}
	n, err := strconv.ParseUint(port, 10, 16)
	if err != nil || n == 0 {
		return false
	}
	if ip := net.ParseIP(host); ip != nil && ip.To4() == nil {
		return false
	}
	return true
}
func (m *bridgeManager) open(address, password string, timeoutMS uint32) uint64 {
	if !validAddress(address) || len(password) > 128 || (timeoutMS != 0 && (timeoutMS < 100 || timeoutMS > 60000)) {
		return 0
	}
	if timeoutMS == 0 {
		timeoutMS = 15000
	}
	ctx, cancel := context.WithCancel(context.Background())
	s := &bridgeSession{ctx: ctx, cancel: cancel, sends: make(chan sendRequest, maxSends), heartbeatEvery: m.heartbeatEvery}
	m.mu.Lock()
	if len(m.sessions) >= maxHandles || m.next == ^uint64(0) {
		m.mu.Unlock()
		cancel()
		return 0
	}
	m.next++
	id := m.next
	m.sessions[id] = s
	m.mu.Unlock()
	go m.run(s, address, password, time.Duration(timeoutMS)*time.Millisecond)
	return id
}
func (m *bridgeManager) lookup(id uint64) *bridgeSession {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.sessions[id]
}
func (m *bridgeManager) close(id uint64) {
	m.mu.Lock()
	s := m.sessions[id]
	delete(m.sessions, id)
	m.mu.Unlock()
	if s == nil {
		return
	}
	s.mu.Lock()
	s.closed = true
	s.queue = nil
	s.accepted = nil
	s.queuedBytes = 0
	s.mu.Unlock()
	s.cancel()
}
func (s *bridgeSession) enqueue(kind int, data []byte) bool {
	s.mu.Lock()
	if s.closed || s.terminal {
		s.mu.Unlock()
		return false
	}
	if len(data) > maxEventBytes || len(s.queue) >= maxEvents || s.queuedBytes+len(data) > maxQueueBytes {
		s.queue = []transportEvent{{3, []byte("legacy transport event queue exceeded")}}
		s.queuedBytes = len(s.queue[0].data)
		s.terminal = true
		s.mu.Unlock()
		s.cancel()
		return false
	}
	s.queue = append(s.queue, transportEvent{kind, append([]byte(nil), data...)})
	s.queuedBytes += len(data)
	s.mu.Unlock()
	return true
}
func (s *bridgeSession) finish(err error) {
	if err == nil {
		err = errors.New("legacy transport closed")
	}
	message := []byte(err.Error())
	if len(message) > 4096 {
		message = message[:4096]
	}
	s.mu.Lock()
	if !s.closed && !s.terminal {
		// A terminal result must remain visible even when the consumer is stalled.
		if len(s.queue) >= maxEvents || s.queuedBytes+len(message) > maxQueueBytes {
			s.queue = nil
			s.queuedBytes = 0
		}
		s.queue = append(s.queue, transportEvent{3, message})
		s.queuedBytes += len(message)
		s.terminal = true
	}
	s.mu.Unlock()
	s.cancel()
}
func resolveIPv4(ctx context.Context, address string) (string, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return "", err
	}
	if ip := net.ParseIP(host); ip != nil {
		return net.JoinHostPort(ip.String(), port), nil
	}
	ips, err := net.DefaultResolver.LookupIP(ctx, "ip4", host)
	if err != nil {
		return "", err
	}
	for _, ip := range ips {
		if v4 := ip.To4(); v4 != nil {
			return net.JoinHostPort(v4.String(), port), nil
		}
	}
	return "", fmt.Errorf("legacy server has no IPv4 address")
}
func (m *bridgeManager) run(s *bridgeSession, address, password string, timeout time.Duration) {
	connectCtx, cancel := context.WithTimeout(s.ctx, timeout)
	defer cancel()
	resolved, err := resolveIPv4(connectCtx, address)
	if err != nil {
		s.finish(err)
		return
	}
	conn, err := m.dial(connectCtx, resolved, password)
	if err != nil {
		s.finish(err)
		return
	}
	defer conn.Close()
	go s.writeLoop(conn)
	accepted := false
	for {
		readCtx := s.ctx
		if !accepted {
			readCtx = connectCtx
		}
		data, err := conn.Read(readCtx)
		if err != nil {
			s.finish(err)
			return
		}
		if len(data) == 0 {
			continue
		}
		kind := 2
		if data[0] == raknet.PacketConnectionAccepted && !accepted {
			accepted = true
			cancel()
			kind = 1
			s.mu.Lock()
			if !s.closed {
				s.accepted = append([]byte(nil), data...)
			}
			s.mu.Unlock()
		}
		if !s.enqueue(kind, data) {
			return
		}
	}
}
func (s *bridgeSession) writeLoop(conn transportConn) {
	ticker := time.NewTicker(s.heartbeatEvery)
	defer ticker.Stop()
	write := func(request sendRequest) bool {
		ctx, cancel := context.WithTimeout(s.ctx, time.Second)
		err := conn.WriteChannel(ctx, request.data, request.reliability, request.channel)
		cancel()
		if err != nil {
			s.finish(err)
			return false
		}
		return true
	}
	for {
		select {
		case <-s.ctx.Done():
			return
		case now := <-ticker.C:
			s.mu.Lock()
			accepted := len(s.accepted) > 0 && !s.closed && !s.terminal
			s.mu.Unlock()
			if !accepted {
				continue
			}
			// A reliable RakNet internal ping is acknowledged even when the
			// application's outgoing movement stream is entirely unreliable.
			// Lost peers therefore reach the transport's bounded retry limit.
			ping := make([]byte, 5)
			ping[0] = 6
			binary.LittleEndian.PutUint32(ping[1:], uint32(now.UnixMilli()))
			if !write(sendRequest{ping, raknet.Reliable, 0}) {
				return
			}
		case request := <-s.sends:
			if !write(request) {
				return
			}
		}
	}
}
func (m *bridgeManager) send(id uint64, data []byte, reliability, channel uint32) int {
	if len(data) == 0 || len(data) > maxSendBytes || reliability < 6 || reliability > 10 || channel > 31 {
		return errInput
	}
	s := m.lookup(id)
	if s == nil {
		return errHandle
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed || s.terminal {
		return errHandle
	}
	request := sendRequest{append([]byte(nil), data...), raknet.Reliability(reliability), uint8(channel)}
	select {
	case s.sends <- request:
		return 0
	default:
		return errQueue
	}
}
func (m *bridgeManager) poll(id uint64, capacity int) (int, []byte, int) {
	if capacity < 0 || capacity > maxEventBytes {
		return errInput, nil, 0
	}
	s := m.lookup(id)
	if s == nil {
		return errHandle, nil, 0
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return errHandle, nil, 0
	}
	if len(s.queue) == 0 {
		return 0, nil, 0
	}
	event := s.queue[0]
	if len(event.data) > capacity {
		return errCapacity, nil, len(event.data)
	}
	s.queue[0] = transportEvent{}
	s.queue = s.queue[1:]
	s.queuedBytes -= len(event.data)
	return event.kind, event.data, len(event.data)
}
func (m *bridgeManager) accepted(id uint64, capacity int) (int, []byte, int) {
	if capacity < 0 || capacity > maxEventBytes {
		return errInput, nil, 0
	}
	s := m.lookup(id)
	if s == nil {
		return errHandle, nil, 0
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return errHandle, nil, 0
	}
	if len(s.accepted) == 0 {
		return 0, nil, 0
	}
	if len(s.accepted) > capacity {
		return errCapacity, nil, len(s.accepted)
	}
	return 1, append([]byte(nil), s.accepted...), len(s.accepted)
}
