// SPDX-License-Identifier: AGPL-3.0-only
package main

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"zgtasa.local/native-samp/internal/raknet"
)

type testConn struct {
	packets   chan []byte
	sent      chan sendRequest
	closed    chan struct{}
	once      sync.Once
	write     func(context.Context, []byte, raknet.Reliability, uint8) error
	closeWait <-chan struct{}
}

func newTestConn() *testConn {
	return &testConn{packets: make(chan []byte, 16), sent: make(chan sendRequest, 16), closed: make(chan struct{})}
}
func (c *testConn) Read(ctx context.Context) ([]byte, error) {
	select {
	case p := <-c.packets:
		return p, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-c.closed:
		return nil, errors.New("test remote closed")
	}
}
func (c *testConn) WriteChannel(ctx context.Context, data []byte, r raknet.Reliability, ch uint8) error {
	if c.write != nil {
		return c.write(ctx, data, r, ch)
	}
	select {
	case c.sent <- sendRequest{append([]byte(nil), data...), r, ch}:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
func (c *testConn) Close() error {
	if c.closeWait != nil {
		<-c.closeWait
	}
	c.once.Do(func() { close(c.closed) })
	return nil
}
func testManager(c *testConn) *bridgeManager {
	return newBridgeManager(func(context.Context, string, string) (transportConn, error) { return c, nil })
}
func waitEvent(t *testing.T, m *bridgeManager, id uint64, want int) []byte {
	t.Helper()
	end := time.Now().Add(3 * time.Second)
	for time.Now().Before(end) {
		kind, data, _ := m.poll(id, maxEventBytes)
		if kind == want {
			return data
		}
		if kind != 0 {
			t.Fatalf("event=%d want%d data=%q", kind, want, data)
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("event timeout")
	return nil
}
func TestBridgePreAcceptAuthAndCopiedSend(t *testing.T) {
	c := newTestConn()
	m := testManager(c)
	id := m.open("127.0.0.1:7777", "", 1000)
	defer m.close(id)
	c.packets <- []byte{12, 3, 'A', 'B', 0}
	if p := waitEvent(t, m, id, 2); len(p) != 5 || p[0] != 12 {
		t.Fatal(p)
	}
	accepted := []byte{34, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
	c.packets <- accepted
	if p := waitEvent(t, m, id, 1); len(p) != 13 {
		t.Fatal(p)
	}
	if kind, _, required := m.accepted(id, 0); kind != errCapacity || required != 13 {
		t.Fatal(kind, required)
	}
	if kind, p, required := m.accepted(id, 13); kind != 1 || required != 13 || p[0] != 34 {
		t.Fatal(kind, p, required)
	}
	data := []byte{12, 1, 'X'}
	if m.send(id, data, 8, 0) != 0 {
		t.Fatal("send failed")
	}
	data[0] = 99
	select {
	case sent := <-c.sent:
		if sent.data[0] != 12 || sent.reliability != raknet.Reliable || sent.channel != 0 {
			t.Fatal(sent)
		}
	case <-time.After(time.Second):
		t.Fatal("send timeout")
	}
	// The accepted-handshake deadline must no longer close a live session.
	time.Sleep(1050 * time.Millisecond)
	c.packets <- []byte{220, 4}
	waitEvent(t, m, id, 2)
}
func TestBridgeBufferProbeRetainsEvent(t *testing.T) {
	c := newTestConn()
	m := testManager(c)
	id := m.open("127.0.0.1:7777", "", 1000)
	defer m.close(id)
	c.packets <- []byte{220, 4, 5}
	end := time.Now().Add(time.Second)
	for {
		kind, _, size := m.poll(id, 0)
		if kind == errCapacity {
			if size != 3 {
				t.Fatal(size)
			}
			break
		}
		if kind != 0 || time.Now().After(end) {
			t.Fatal(kind, size)
		}
		time.Sleep(time.Millisecond)
	}
	if kind, _, size := m.poll(id, 2); kind != errCapacity || size != 3 {
		t.Fatal(kind, size)
	}
	if p := waitEvent(t, m, id, 2); len(p) != 3 || p[2] != 5 {
		t.Fatal(p)
	}
	if kind, _, _ := m.poll(id, 3); kind != 0 {
		t.Fatal(kind)
	}
}
func TestBridgeCloseCancelsDialAndNeverReusesHandle(t *testing.T) {
	started := make(chan struct{})
	cancelled := make(chan struct{})
	m := newBridgeManager(func(ctx context.Context, _ string, _ string) (transportConn, error) {
		close(started)
		<-ctx.Done()
		close(cancelled)
		return nil, ctx.Err()
	})
	id := m.open("127.0.0.1:7777", "", 1000)
	<-started
	m.close(id)
	select {
	case <-cancelled:
	case <-time.After(time.Second):
		t.Fatal("dial not cancelled")
	}
	if kind, _, _ := m.poll(id, 10); kind != errHandle {
		t.Fatal(kind)
	}
	m.dial = func(ctx context.Context, _ string, _ string) (transportConn, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	}
	next := m.open("127.0.0.1:7777", "", 1000)
	if next <= id {
		t.Fatal(id, next)
	}
	m.close(next)
	m.close(id)
}
func TestBridgeCloseDoesNotWaitForSocketDrain(t *testing.T) {
	c := newTestConn()
	release := make(chan struct{})
	c.closeWait = release
	m := testManager(c)
	id := m.open("127.0.0.1:7777", "", 1000)
	c.packets <- []byte{34, 1}
	waitEvent(t, m, id, 1)
	now := time.Now()
	m.close(id)
	if time.Since(now) > 100*time.Millisecond {
		t.Fatal("close blocked UI")
	}
	close(release)
}
func TestBridgeTimeoutAndRemoteClose(t *testing.T) {
	for _, remote := range []bool{false, true} {
		t.Run(map[bool]string{false: "handshake timeout", true: "remote close"}[remote], func(t *testing.T) {
			c := newTestConn()
			m := testManager(c)
			id := m.open("127.0.0.1:7777", "", 100)
			defer m.close(id)
			if remote {
				c.Close()
			}
			if p := waitEvent(t, m, id, 3); len(p) == 0 {
				t.Fatal("no reason")
			}
			if m.send(id, []byte{1}, 6, 0) != errHandle {
				t.Fatal("terminal send accepted")
			}
		})
	}
}
func TestBridgeQueueBounds(t *testing.T) {
	for _, byBytes := range []bool{false, true} {
		ctx, cancel := context.WithCancel(context.Background())
		s := &bridgeSession{ctx: ctx, cancel: cancel}
		if byBytes {
			for i := 0; i < 4; i++ {
				if !s.enqueue(2, make([]byte, maxEventBytes)) {
					t.Fatal(i)
				}
			}
		} else {
			for i := 0; i < maxEvents; i++ {
				if !s.enqueue(2, []byte{1}) {
					t.Fatal(i)
				}
			}
		}
		if s.enqueue(2, []byte{1}) {
			t.Fatal("overflow accepted")
		}
		if len(s.queue) != 1 || s.queue[0].kind != 3 || !s.terminal {
			t.Fatal("terminal overflow not visible")
		}
		select {
		case <-ctx.Done():
		default:
			t.Fatal("overflow did not cancel")
		}
	}
}
func TestBridgeInputsSendQueueAndCapacity(t *testing.T) {
	m := newBridgeManager(func(ctx context.Context, _ string, _ string) (transportConn, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	})
	for _, address := range []string{"", "localhost", "127.0.0.1:0", "127.0.0.1:65536", " 127.0.0.1:1", "[::1]:7777", "127.0.0.1:1\x00"} {
		if id := m.open(address, "", 1000); id != 0 {
			m.close(id)
			t.Fatal(address)
		}
	}
	if m.open("127.0.0.1:7777", string(make([]byte, 129)), 1000) != 0 || m.open("127.0.0.1:7777", "", 99) != 0 {
		t.Fatal("bad limit accepted")
	}
	id := m.open("127.0.0.1:7777", "", 1000)
	defer m.close(id)
	for _, v := range []struct {
		data  []byte
		r, ch uint32
	}{{nil, 6, 0}, {make([]byte, 8192), 6, 0}, {[]byte{1}, 5, 0}, {[]byte{1}, 11, 0}, {[]byte{1}, 8, 32}} {
		if m.send(id, v.data, v.r, v.ch) != errInput {
			t.Fatal(v)
		}
	}
	for i := 0; i < maxSends; i++ {
		if m.send(id, []byte{1}, 8, 0) != 0 {
			t.Fatal(i)
		}
	}
	if m.send(id, []byte{1}, 8, 0) != errQueue {
		t.Fatal("unbounded send queue")
	}
	if kind, _, _ := m.poll(id, maxEventBytes+1); kind != errInput {
		t.Fatal(kind)
	}
	if kind, _, _ := m.accepted(999, 0); kind != errHandle {
		t.Fatal(kind)
	}
}
func TestBridgeMaximumHandles(t *testing.T) {
	m := newBridgeManager(func(ctx context.Context, _ string, _ string) (transportConn, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	})
	var ids []uint64
	defer func() {
		for _, id := range ids {
			m.close(id)
		}
	}()
	for i := 0; i < maxHandles; i++ {
		id := m.open("127.0.0.1:7777", "", 1000)
		if id == 0 {
			t.Fatal(i)
		}
		ids = append(ids, id)
	}
	if m.open("127.0.0.1:7777", "", 1000) != 0 {
		t.Fatal("unbounded handles")
	}
	m.close(ids[0])
	if id := m.open("127.0.0.1:7777", "", 1000); id <= ids[len(ids)-1] {
		t.Fatal("reused old handle")
	} else {
		ids = append(ids, id)
	}
}

func TestBridgeHeartbeatWaitsForAcceptanceAndUsesReliableTransport(t *testing.T) {
	c := newTestConn()
	m := testManager(c)
	m.heartbeatEvery = 10 * time.Millisecond
	id := m.open("127.0.0.1:7777", "", 1000)
	defer m.close(id)
	select {
	case p := <-c.sent:
		t.Fatal("pre-accept heartbeat", p)
	case <-time.After(40 * time.Millisecond):
	}
	c.packets <- []byte{34, 1}
	waitEvent(t, m, id, 1)
	select {
	case p := <-c.sent:
		if len(p.data) != 5 || p.data[0] != 6 || p.reliability != raknet.Reliable || p.channel != 0 {
			t.Fatal(p)
		}
	case <-time.After(time.Second):
		t.Fatal("missing reliable heartbeat")
	}
}
