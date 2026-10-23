package collab

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"flowmuse/server/internal/auth"
	"flowmuse/server/internal/storage"
	"flowmuse/server/internal/testutil"
	"github.com/zishang520/socket.io/v2/socket"
)

func TestRoomCapacityAndOwnerRemoval(t *testing.T) {
	db := testutil.Postgres(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := auth.NewUserStore(db).EnsureSchema(ctx); err != nil {
		t.Fatal(err)
	}
	rooms := storage.NewRoomStore(db)
	for i := 0; i < 2; i++ {
		if err := rooms.EnsureSchema(ctx); err != nil {
			t.Fatal(err)
		}
	}
	const roomID, ownerKey = "limited-room", "synthetic-owner-key"
	if _, err := rooms.CreateRoom(ctx, roomID, "", hashOwnerKey(roomID, ownerKey), 2); err != nil {
		t.Fatal(err)
	}
	// Retry, including the legacy scene-create call, cannot change an existing limit.
	metadata, err := rooms.CreateRoom(ctx, roomID, "", "", 0)
	if err != nil || metadata.MaxParticipants != 2 {
		t.Fatal("room retry changed capacity")
	}
	if _, err := rooms.CreateRoom(ctx, "other-room", "", hashOwnerKey("other-room", ownerKey), 0); err != nil {
		t.Fatal(err)
	}
	ioServer := socket.NewServer(nil, nil)
	hub := NewHub(ioServer, nil, rooms, nil, nil)
	hub.roomExistsOverride = func(string) bool { return true }
	hub.Register()
	mux := http.NewServeMux()
	mux.Handle("/socket.io/", ioServer.ServeHandler(nil))
	NewHTTPAPI(nil, nil, rooms, hub, guestRoomIdentity{}, time.Second).Register(mux)
	server := httptest.NewServer(mux)
	defer server.Close()
	defer ioServer.Close(nil)
	makeClient := func() *pollingSocketClient {
		t.Helper()
		c, e := newPollingSocketClient(ctx, server.URL, "fixture")
		if e != nil {
			t.Fatal(e)
		}
		return c
	}
	waitAdmission := func(c *pollingSocketClient) (bool, error) {
		for {
			packets, e := c.poll(ctx)
			if e != nil {
				return false, e
			}
			for _, packet := range packets {
				if !strings.HasPrefix(packet, "42") {
					continue
				}
				var data []json.RawMessage
				if json.Unmarshal([]byte(packet[2:]), &data) != nil || len(data) == 0 {
					continue
				}
				var event string
				_ = json.Unmarshal(data[0], &event)
				if event == EventLiveInkReady {
					return true, nil
				}
				if event == EventRoomError {
					return false, nil
				}
			}
		}
	}
	owner := makeClient()
	if e := owner.emit(ctx, EventJoinRoom, roomID, map[string]any{"ownerKey": ownerKey}); e != nil {
		t.Fatal(e)
	}
	if accepted, e := waitAdmission(owner); e != nil || !accepted {
		t.Fatal("owner cannot join", e)
	}
	if e := owner.emit(ctx, EventJoinRoom, roomID, map[string]any{"ownerKey": ownerKey}); e != nil {
		t.Fatal(e)
	}
	if accepted, e := waitAdmission(owner); e != nil || !accepted {
		t.Fatal("duplicate join consumed capacity", e)
	}
	clients := make([]*pollingSocketClient, 8)
	for i := range clients {
		clients[i] = makeClient()
	}
	var wg sync.WaitGroup
	for _, c := range clients {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if e := c.emit(ctx, EventJoinRoom, roomID); e != nil {
				t.Error(e)
			}
		}()
	}
	wg.Wait()
	var admitted *pollingSocketClient
	for _, c := range clients {
		accepted, e := waitAdmission(c)
		if e != nil {
			t.Fatal(e)
		}
		if accepted {
			if admitted != nil {
				t.Fatal("last seat admitted multiple connections")
			}
			admitted = c
		}
	}
	if admitted == nil {
		t.Fatal("no participant admitted")
	}
	hub.mu.Lock()
	count := len(hub.roomUsers[roomID])
	hub.mu.Unlock()
	if count != 2 {
		t.Fatal("capacity does not include owner")
	}
	post := func(room, target, key string, want int) {
		t.Helper()
		body, _ := json.Marshal(map[string]string{"socketId": target, "ownerKey": key})
		response, e := http.Post(server.URL+"/api/rooms/"+room+"/remove-member", "application/json", strings.NewReader(string(body)))
		if e != nil {
			t.Fatal(e)
		}
		defer response.Body.Close()
		if response.StatusCode != want {
			t.Fatalf("remove-member status %d, want %d", response.StatusCode, want)
		}
	}
	post(roomID, admitted.socketSID, "", http.StatusForbidden)
	post(roomID, owner.socketSID, ownerKey, http.StatusConflict)
	post("other-room", admitted.socketSID, ownerKey, http.StatusConflict)
	if reason := hub.consumeLiveInkToken(admitted.socketSID, roomID); reason != "" {
		t.Fatal("unauthorized removal changed membership")
	}
	post(roomID, admitted.socketSID, ownerKey, http.StatusNoContent)
	if reason := hub.consumeLiveInkToken(admitted.socketSID, roomID); reason != liveInkDropNotMember {
		t.Fatal("removed member retains live ink permissions")
	}
	metadata, err = rooms.FindRoom(ctx, roomID, "")
	if err != nil || metadata.Ended {
		t.Fatal("removing member ended room")
	}
	next := makeClient()
	if e := next.emit(ctx, EventJoinRoom, roomID); e != nil {
		t.Fatal(e)
	}
	if accepted, e := waitAdmission(next); e != nil || !accepted {
		t.Fatal("removed seat was not released", e)
	}
	if e := next.emit(ctx, EventLeaveRoom, roomID); e != nil {
		t.Fatal(e)
	}
	if _, e := owner.waitEvent(ctx, EventRoomUserChange); e != nil {
		t.Fatal(e)
	}
	// A normal disconnect also releases its seat.
	deadline := time.Now().Add(time.Second)
	for {
		hub.mu.Lock()
		n := len(hub.roomUsers[roomID])
		hub.mu.Unlock()
		if n == 1 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("leave retained seat")
		}
		time.Sleep(time.Millisecond)
	}
	final := makeClient()
	if e := final.emit(ctx, EventJoinRoom, roomID); e != nil {
		t.Fatal(e)
	}
	if accepted, e := waitAdmission(final); e != nil || !accepted {
		t.Fatal("left seat was not released", e)
	}
}

func TestCreateRoomRejectsInvalidCapacityBeforeStorage(t *testing.T) {
	api := NewHTTPAPI(nil, nil, nil, nil, guestRoomIdentity{}, time.Second)
	for _, value := range []string{"-1", "1", "51", "2.5", "\"4\""} {
		request := httptest.NewRequest(http.MethodPost, "/api/rooms", strings.NewReader(`{"roomId":"fixture","maxParticipants":`+value+`}`))
		response := httptest.NewRecorder()
		api.roomsRoot(response, request)
		if response.Code != http.StatusBadRequest {
			t.Fatalf("invalid capacity status %d", response.Code)
		}
	}
}
