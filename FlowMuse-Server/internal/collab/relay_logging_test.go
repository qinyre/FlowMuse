package collab

import (
	"bytes"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestForwardLogSamplesBurstAndReportsCumulativeFrames(t *testing.T) {
	previousWriter := log.Writer()
	t.Cleanup(func() { log.SetOutput(previousWriter) })
	var output bytes.Buffer
	log.SetOutput(&output)
	now := time.Unix(100, 0)
	hub := &Hub{now: func() time.Time { return now }}
	frame := EncryptedFrame{EncryptedBuffer: []byte{1, 2, 3}, IV: []byte{4}}
	for range 1000 {
		hub.logForward("socket", "room", frame, false)
	}
	if lines := strings.Count(output.String(), "\n"); lines != 1 {
		t.Fatalf("burst produced %d log writes, want one", lines)
	}
	for range 100 {
		hub.logForward("socket", "room", frame, true)
	}
	now = now.Add(999 * time.Millisecond)
	hub.logForward("socket", "room", frame, false)
	if lines := strings.Count(output.String(), "\n"); lines != 1 {
		t.Fatalf("sampling refilled early: %d writes", lines)
	}
	now = now.Add(time.Millisecond)
	hub.logForward("socket", "room", frame, false)
	if strings.Count(output.String(), "\n") != 2 || !strings.Contains(output.String(), "sampled=true totalFrames=1002") {
		t.Fatal("sample did not refill or count reliable frames across the window")
	}
}

func TestForwardLogConcurrentRoomsShareBoundedSampling(t *testing.T) {
	previousWriter := log.Writer()
	t.Cleanup(func() { log.SetOutput(previousWriter) })
	var output bytes.Buffer
	log.SetOutput(&output)
	now := time.Unix(100, 0)
	hub := &Hub{now: func() time.Time { return now }}
	var group sync.WaitGroup
	for index := range 20 {
		roomID := fmt.Sprintf("room-%d", index)
		group.Add(1)
		go func() {
			defer group.Done()
			for range 100 {
				hub.logForward("socket", roomID, EncryptedFrame{}, false)
			}
		}()
	}
	group.Wait()
	if strings.Count(output.String(), "\n") != 1 {
		t.Fatal("concurrent senders bypassed the instance-wide sampling budget")
	}
	now = now.Add(time.Second)
	hub.logForward("socket", "other-room", EncryptedFrame{}, false)
	if !strings.Contains(output.String(), "totalFrames=2001") {
		t.Fatal("concurrent reliable-frame count was lost")
	}
}

func BenchmarkForwardLogging(b *testing.B) {
	for _, sampled := range []bool{false, true} {
		name := "per-packet"
		if sampled {
			name = "sampled"
		}
		b.Run(name, func(b *testing.B) {
			output, err := os.CreateTemp(b.TempDir(), "relay-log")
			if err != nil {
				b.Fatal(err)
			}
			b.Cleanup(func() { output.Close() })
			previousWriter := log.Writer()
			b.Cleanup(func() { log.SetOutput(previousWriter) })
			log.SetOutput(output)
			hub := &Hub{}
			frame := EncryptedFrame{EncryptedBuffer: make([]byte, 16*1024), IV: make([]byte, 12)}
			b.ReportAllocs()
			b.ResetTimer()
			for range b.N {
				if sampled {
					hub.logForward("socket", "room", frame, false)
				} else {
					// Baseline is the deployed c8504b4 per-packet diagnostic.
					log.Printf("[FlowMuseCollab][server][broadcast_forward] socket=%s room=%s encryptedBytes=%d ivBytes=%d volatile=false", "socket", "room", len(frame.EncryptedBuffer), len(frame.IV))
				}
			}
		})
	}
}
