package collab

import (
	"bytes"
	"io"
	"log"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	parserTypes "github.com/zishang520/engine.io-go-parser/types"
)

func TestLiveInkFrameForValidatesMembershipAndEnvelope(t *testing.T) {
	hub := &Hub{socketRooms: map[string]string{"sender": "room"}}
	valid := []any{"room", map[string]any{
		"encryptedBuffer": []byte{1, 2, 3},
		"iv":              make([]byte, liveInkIVBytes),
		"senderSocketId":  "forged",
	}}

	roomID, frame, ok := hub.liveInkFrameFor("sender", valid)
	if !ok || roomID != "room" {
		t.Fatal("valid member frame was rejected")
	}
	if frame.SenderSocketID != "sender" {
		t.Fatalf("sender id was not server-derived: %q", frame.SenderSocketID)
	}

	invalidCases := []struct {
		name     string
		socketID string
		args     []any
	}{
		{name: "non-member", socketID: "unknown", args: valid},
		{name: "cross-room", socketID: "sender", args: []any{"other", valid[1]}},
		{name: "short-iv", socketID: "sender", args: []any{"room", map[string]any{"encryptedBuffer": []byte{1}, "iv": make([]byte, 11)}}},
		{name: "oversize", socketID: "sender", args: []any{"room", map[string]any{"encryptedBuffer": make([]byte, maxLiveInkCiphertextBytes+1), "iv": make([]byte, liveInkIVBytes)}}},
		{name: "array-bytes", socketID: "sender", args: []any{"room", map[string]any{"encryptedBuffer": []any{1.0}, "iv": make([]byte, liveInkIVBytes)}}},
		{name: "legacy-shape", socketID: "sender", args: []any{"room", []byte{1}, make([]byte, liveInkIVBytes)}},
	}
	for _, testCase := range invalidCases {
		t.Run(testCase.name, func(t *testing.T) {
			if _, _, ok := hub.liveInkFrameFor(testCase.socketID, testCase.args); ok {
				t.Fatal("invalid live ink frame was accepted")
			}
		})
	}
}

func TestLiveInkEnvelopeAcceptsBoundariesWithoutCopyingOversizeBuffers(t *testing.T) {
	valid := map[string]any{
		"encryptedBuffer": parserTypes.NewBytesBuffer(make([]byte, maxLiveInkCiphertextBytes)),
		"iv":              parserTypes.NewBytesBuffer(make([]byte, liveInkIVBytes)),
	}
	ciphertext, iv, byteCount, _, ok := parseLiveInkEnvelope(valid)
	if !ok || len(ciphertext) != maxLiveInkCiphertextBytes || len(iv) != liveInkIVBytes {
		t.Fatalf("valid boundary was rejected: ok=%v bytes=%d", ok, byteCount)
	}

	oversize := map[string]any{
		"encryptedBuffer": parserTypes.NewBytesBuffer(make([]byte, maxLiveInkCiphertextBytes+1)),
		"iv":              make([]byte, liveInkIVBytes),
	}
	if _, _, byteCount, reason, ok := parseLiveInkEnvelope(oversize); ok || reason != liveInkDropOversize || byteCount != maxLiveInkCiphertextBytes+1+liveInkIVBytes {
		t.Fatalf("oversize buffer was not rejected before conversion: ok=%v reason=%q bytes=%d", ok, reason, byteCount)
	}
}

func TestLiveInkSocketBucketUsesBurstAndRefill(t *testing.T) {
	now := time.Unix(100, 0)
	hub := liveInkTestHub(&now, "room", "sender")
	args := validLiveInkArgs("room")

	for index := 0; index < int(liveInkSocketBurst); index++ {
		if _, _, ok := hub.liveInkFrameFor("sender", args); !ok {
			t.Fatalf("burst packet %d was rejected", index+1)
		}
	}
	withDiscardedLogs(t, func() {
		if _, _, ok := hub.liveInkFrameFor("sender", args); ok {
			t.Fatal("packet beyond socket burst was accepted")
		}
	})

	now = now.Add(time.Second)
	for index := 0; index < int(liveInkSocketRate); index++ {
		if _, _, ok := hub.liveInkFrameFor("sender", args); !ok {
			t.Fatalf("refilled packet %d was rejected", index+1)
		}
	}
	withDiscardedLogs(t, func() {
		if _, _, ok := hub.liveInkFrameFor("sender", args); ok {
			t.Fatal("packet beyond one-second refill was accepted")
		}
	})
}

func TestLiveInkRoomBucketCapsMultipleSockets(t *testing.T) {
	now := time.Unix(100, 0)
	sockets := []string{"a", "b", "c", "d", "e", "f"}
	hub := liveInkTestHub(&now, "room", sockets...)
	args := validLiveInkArgs("room")
	for _, socketID := range sockets {
		for range 100 {
			if _, _, ok := hub.liveInkFrameFor(socketID, args); !ok {
				t.Fatalf("room burst rejected before %v packets", liveInkRoomBurst)
			}
		}
	}
	withDiscardedLogs(t, func() {
		if _, _, ok := hub.liveInkFrameFor(sockets[0], args); ok {
			t.Fatal("packet beyond room burst was accepted")
		}
	})
}

func TestLiveInkSocketBucketIsConcurrencySafe(t *testing.T) {
	now := time.Unix(100, 0)
	hub := liveInkTestHub(&now, "room", "sender")
	args := validLiveInkArgs("room")
	var accepted atomic.Int64
	var group sync.WaitGroup

	withDiscardedLogs(t, func() {
		for range 300 {
			group.Add(1)
			go func() {
				defer group.Done()
				if _, _, ok := hub.liveInkFrameFor("sender", args); ok {
					accepted.Add(1)
				}
			}()
		}
		group.Wait()
	})
	if accepted.Load() != int64(liveInkSocketBurst) {
		t.Fatalf("accepted=%d want=%v", accepted.Load(), liveInkSocketBurst)
	}
}

func TestInvalidLiveInkFramesConsumeIngressBudgetAndBoundLogs(t *testing.T) {
	now := time.Unix(100, 0)
	hub := liveInkTestHub(&now, "room", "sender")
	invalid := []any{"room", map[string]any{
		"encryptedBuffer": []any{1.0},
		"iv":              make([]byte, liveInkIVBytes),
	}}
	previousWriter := log.Writer()
	previousFlags := log.Flags()
	defer log.SetOutput(previousWriter)
	defer log.SetFlags(previousFlags)
	var output bytes.Buffer
	log.SetOutput(&output)
	log.SetFlags(0)

	for range 1000 {
		hub.liveInkFrameFor("sender", invalid)
	}

	hub.mu.Lock()
	invalidCount := hub.liveInkDropCounts[liveInkDropUnsupported]
	rateCount := hub.liveInkDropCounts[liveInkDropSocketRate]
	roomBucketCount := len(hub.liveInkRoomBuckets)
	hub.mu.Unlock()
	if invalidCount != uint64(liveInkSocketBurst) || rateCount != 1000-uint64(liveInkSocketBurst) {
		t.Fatalf("unexpected drop counts: invalid=%d rate=%d", invalidCount, rateCount)
	}
	if roomBucketCount != 0 {
		t.Fatalf("invalid envelopes consumed room budget: buckets=%d", roomBucketCount)
	}
	if lines := strings.Count(strings.TrimSpace(output.String()), "\n") + 1; lines > 20 {
		t.Fatalf("drop logging was not aggregated: lines=%d", lines)
	}
}

func TestLiveInkAcceptAndMembershipMutationAreSerialized(t *testing.T) {
	now := time.Unix(100, 0)
	hub := liveInkTestHub(&now, "room", "sender")
	accepted := make(chan struct{})
	release := make(chan struct{})
	forwardDone := make(chan struct{})
	go func() {
		hub.withLiveInkFrame("sender", validLiveInkArgs("room"), func(string, ReceivedLiveInkFrame) {
			close(accepted)
			<-release
		})
		close(forwardDone)
	}()
	<-accepted

	leaveDone := make(chan struct{})
	go func() {
		hub.mu.Lock()
		hub.removeFromRoomLocked("sender", "room")
		hub.mu.Unlock()
		close(leaveDone)
	}()
	select {
	case <-leaveDone:
		t.Fatal("membership changed while live frame accept was in progress")
	case <-time.After(20 * time.Millisecond):
	}
	close(release)
	<-forwardDone
	<-leaveDone
}

func TestLiveInkBucketsAreRemovedOnLeaveAndDisconnect(t *testing.T) {
	now := time.Unix(100, 0)
	hub := liveInkTestHub(&now, "room", "a", "b")
	args := validLiveInkArgs("room")
	if _, _, ok := hub.liveInkFrameFor("a", args); !ok {
		t.Fatal("initial frame was rejected")
	}
	if _, _, ok := hub.liveInkFrameFor("b", args); !ok {
		t.Fatal("initial frame was rejected")
	}

	hub.mu.Lock()
	hub.removeFromRoomLocked("a", "room")
	_, socketAExists := hub.liveInkSocketBuckets["a"]
	_, roomExists := hub.liveInkRoomBuckets["room"]
	hub.mu.Unlock()
	hub.removeSocket("b")
	hub.mu.Lock()
	_, socketBExists := hub.liveInkSocketBuckets["b"]
	_, emptyRoomExists := hub.liveInkRoomBuckets["room"]
	hub.mu.Unlock()

	if socketAExists || socketBExists || !roomExists || emptyRoomExists {
		t.Fatalf("unexpected bucket cleanup: socketA=%v socketB=%v roomBeforeEmpty=%v roomAfterEmpty=%v", socketAExists, socketBExists, roomExists, emptyRoomExists)
	}
	if reason := hub.consumeLiveInkToken("b", "room"); reason != liveInkDropNotMember {
		t.Fatalf("post-leave frame was not rejected: %q", reason)
	}
	if len(hub.liveInkSocketBuckets) != 0 || len(hub.liveInkRoomBuckets) != 0 {
		t.Fatal("post-leave validation recreated token buckets")
	}
}

func TestLiveInkRateLimitDoesNotChangeReliableOrPresenceParsing(t *testing.T) {
	now := time.Unix(100, 0)
	hub := liveInkTestHub(&now, "room", "sender")
	args := validLiveInkArgs("room")
	for range int(liveInkSocketBurst) {
		if _, _, ok := hub.liveInkFrameFor("sender", args); !ok {
			t.Fatal("failed to fill live bucket")
		}
	}

	if roomID, _, ok := parseBroadcastArgs(args); !ok || roomID != "room" {
		t.Fatal("reliable broadcast parsing was affected by live limit")
	}
	if roomID, socketID, ok := parseUserFollowArgs([]any{"room", "target"}); !ok || roomID != "room" || socketID != "target" {
		t.Fatal("presence parsing was affected by live limit")
	}
}

func TestLiveInkDropLogContainsOnlySafeMetadata(t *testing.T) {
	previousWriter := log.Writer()
	previousFlags := log.Flags()
	defer log.SetOutput(previousWriter)
	defer log.SetFlags(previousFlags)
	var output bytes.Buffer
	log.SetOutput(&output)
	log.SetFlags(0)

	logLiveInkDrop("socket-secret-suffix", liveInkDropOversize, 123)
	text := output.String()
	if !strings.Contains(text, "reason=ciphertext_oversize") || !strings.Contains(text, "socket=socket-s") || !strings.Contains(text, "bytes=123") {
		t.Fatalf("safe metadata missing: %q", text)
	}
	if strings.Contains(text, "secret-suffix") {
		t.Fatalf("socket id was not truncated: %q", text)
	}
}

func validLiveInkArgs(roomID string) []any {
	return []any{roomID, map[string]any{
		"encryptedBuffer": []byte{1, 2, 3},
		"iv":              make([]byte, liveInkIVBytes),
	}}
}

func liveInkTestHub(now *time.Time, roomID string, socketIDs ...string) *Hub {
	rooms := make(map[string]string, len(socketIDs))
	users := make(map[string]RoomUser, len(socketIDs))
	for _, socketID := range socketIDs {
		rooms[socketID] = roomID
		users[socketID] = RoomUser{SocketID: socketID}
	}
	return &Hub{
		roomUsers:   map[string]map[string]RoomUser{roomID: users},
		socketRooms: rooms,
		now:         func() time.Time { return *now },
	}
}

func withDiscardedLogs(t *testing.T, action func()) {
	t.Helper()
	previousWriter := log.Writer()
	log.SetOutput(io.Discard)
	defer log.SetOutput(previousWriter)
	action()
}

func TestLiveInkReadyIsIndependentPayload(t *testing.T) {
	ready := LiveInkReady{RoomID: "room", LiveInkProtocolVersion: liveInkProtocolVersion}
	if ready.RoomID != "room" || ready.LiveInkProtocolVersion != 2 {
		t.Fatalf("unexpected ready payload: %+v", ready)
	}
}

func TestRemoveSocketClearsRoomAndFollowState(t *testing.T) {
	hub := &Hub{
		roomUsers: map[string]map[string]RoomUser{
			"room": {
				"socket-a": {SocketID: "socket-a"},
				"socket-b": {SocketID: "socket-b"},
			},
		},
		socketRooms: map[string]string{"socket-a": "room", "socket-b": "room"},
		socketUsers: map[string]RoomUser{"socket-a": {SocketID: "socket-a"}},
		followRooms: map[string]map[string]struct{}{
			"room:target-a": {"socket-a": {}, "socket-b": {}},
			"room:target-b": {"socket-a": {}},
		},
	}

	roomID, users := hub.removeSocket("socket-a")

	if roomID != "room" || len(users) != 1 || users[0].SocketID != "socket-b" {
		t.Fatalf("unexpected remaining room state: room=%q users=%v", roomID, users)
	}
	if _, ok := hub.socketRooms["socket-a"]; ok {
		t.Fatal("socket room membership was not cleared")
	}
	if _, ok := hub.socketUsers["socket-a"]; ok {
		t.Fatal("socket identity was not cleared")
	}
	if _, ok := hub.followRooms["room:target-a"]["socket-a"]; ok {
		t.Fatal("follow membership was not cleared")
	}
	if _, ok := hub.followRooms["room:target-b"]; ok {
		t.Fatal("empty follow room was not removed")
	}
}

func TestLogForwardSkipsVolatileFrames(t *testing.T) {
	previousWriter := log.Writer()
	previousFlags := log.Flags()
	defer log.SetOutput(previousWriter)
	defer log.SetFlags(previousFlags)
	var output bytes.Buffer
	log.SetOutput(&output)
	log.SetFlags(0)
	frame := EncryptedFrame{EncryptedBuffer: []byte{1, 2, 3}, IV: []byte{4}}

	for range 100 {
		logForward("socket", "room", frame, true)
	}
	if output.Len() != 0 {
		t.Fatalf("volatile frames produced per-frame logs: %q", output.String())
	}

	logForward("socket", "room", frame, false)
	if !strings.Contains(output.String(), "encryptedBytes=3") {
		t.Fatalf("reliable frame summary was not logged: %q", output.String())
	}
}
