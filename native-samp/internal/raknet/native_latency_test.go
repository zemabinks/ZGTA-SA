// SPDX-License-Identifier: AGPL-3.0-only
// ZGTA SA integration regression for the modified transport polling cadence.
package raknet

import (
	"context"
	"fmt"
	"net"
	"testing"
	"time"
)

func TestNativeUplinkDoesNotStallOnQuietServer(t *testing.T) {
	server, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1")})
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	_ = server.SetReadDeadline(time.Now().Add(4 * time.Second))
	finished := make(chan error, 1)
	go func() {
		buffer := make([]byte, maxDatagramSize)
		port := uint16(server.LocalAddr().(*net.UDPAddr).Port)
		n, peer, e := server.ReadFromUDP(buffer)
		if e != nil {
			finished <- e
			return
		}
		if data := decodeTestDatagram(buffer[:n], port); len(data) != 3 || data[0] != packetOpenConnectionRequest {
			finished <- fmt.Errorf("offline request")
			return
		}
		_, _ = server.WriteToUDP([]byte{packetOpenConnectionReply, 0}, peer)
		n, peer, e = server.ReadFromUDP(buffer)
		if e != nil {
			finished <- e
			return
		}
		_, frames, e := DecodeDatagram(decodeTestDatagram(buffer[:n], port))
		if e != nil || len(frames) != 1 || frames[0].Payload[0] != packetConnectionRequest {
			finished <- fmt.Errorf("connection request")
			return
		}
		accepted := Frame{MessageNumber: 0, Reliability: Reliable, Payload: []byte{PacketConnectionAccepted}, PayloadBits: 8}
		response, _ := EncodeDatagram([]Range{{frames[0].MessageNumber, frames[0].MessageNumber}}, []Frame{accepted})
		_, _ = server.WriteToUDP(response, peer)
		next := 0
		for next < 50 {
			n, peer, e = server.ReadFromUDP(buffer)
			if e != nil {
				finished <- e
				return
			}
			_, frames, e = DecodeDatagram(decodeTestDatagram(buffer[:n], port))
			if e != nil {
				finished <- e
				return
			}
			for _, frame := range frames {
				if frame.Reliability.reliable() {
					ack, _ := EncodeDatagram([]Range{{frame.MessageNumber, frame.MessageNumber}}, nil)
					_, _ = server.WriteToUDP(ack, peer)
				}
				if len(frame.Payload) == 2 && frame.Payload[0] == 200 {
					if frame.Payload[1] != byte(next) {
						finished <- fmt.Errorf("out of order%d want%d", frame.Payload[1], next)
						return
					}
					next++
				}
			}
		}
		finished <- nil
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()
	conn, err := Dial(ctx, server.LocalAddr().String(), "")
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if p, e := conn.Read(ctx); e != nil || len(p) == 0 || p[0] != PacketConnectionAccepted {
		t.Fatal(p, e)
	}
	start := time.Now()
	for i := 0; i < 50; i++ {
		if err = conn.WriteChannel(ctx, []byte{200, byte(i)}, Unreliable, 0); err != nil {
			t.Fatal(err)
		}
	}
	if err = <-finished; err != nil {
		t.Fatal(err)
	}
	if elapsed := time.Since(start); elapsed > 2*time.Second {
		t.Fatalf("quiet server uplink took%v for50 input packets", elapsed)
	}
}
