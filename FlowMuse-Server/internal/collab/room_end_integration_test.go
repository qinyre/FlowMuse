package collab

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"flowmuse/server/internal/auth"
	"flowmuse/server/internal/storage"
	"flowmuse/server/internal/testutil"

	"github.com/zishang520/socket.io/v2/socket"
)

type guestRoomIdentity struct{}

func (guestRoomIdentity) IdentityFromRequest(*http.Request) (auth.Identity, bool) {
	return auth.Identity{IsGuest: true}, false
}

func TestHTTPEndRoomRevokesLiveMembersWithoutClientEndEvent(t *testing.T) {
	db := testutil.Postgres(t)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := auth.NewUserStore(db).EnsureSchema(ctx); err != nil {
		t.Fatal(err)
	}
	rooms := storage.NewRoomStore(db)
	if err := rooms.EnsureSchema(ctx); err != nil {
		t.Fatal(err)
	}
	const roomID = "room-e2e"
	const ownerKey = "synthetic-owner-key"
	for _, id := range []string{roomID, "other-room"} {
		if _, err := rooms.CreateRoom(ctx, id, "", hashOwnerKey(id, ownerKey)); err != nil {
			t.Fatal(err)
		}
	}
	ioServer := socket.NewServer(nil, nil)
	hub := NewHub(ioServer, nil, rooms, nil, nil)
	// No scene is needed to exercise membership and room lifecycle.
	hub.roomExistsOverride = func(string) bool { return true }
	hub.Register()
	mux := http.NewServeMux()
	mux.Handle("/socket.io/", ioServer.ServeHandler(nil))
	NewHTTPAPI(nil, nil, rooms, hub, guestRoomIdentity{}, time.Second).Register(mux)
	server := httptest.NewServer(mux)
	defer server.Close()
	defer ioServer.Close(nil)

	clients := make([]*pollingSocketClient, 0, 3)
	for _, id := range []string{roomID, roomID, "other-room"} {
		client, err := newPollingSocketClient(ctx, server.URL, "fixture")
		if err != nil {
			t.Fatal(err)
		}
		if err := client.emit(ctx, EventJoinRoom, id); err != nil {
			t.Fatal(err)
		}
		if _, err := client.waitEvent(ctx, EventLiveInkReady); err != nil {
			t.Fatal(err)
		}
		clients = append(clients, client)
	}
	post := func(suffix, body string, want int) {
		t.Helper()
		request, err := http.NewRequestWithContext(ctx, http.MethodPost,
			server.URL+"/api/rooms/"+roomID+"/"+suffix, strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		if response.StatusCode != want {
			t.Fatalf("%s status = %d, want %d", suffix, response.StatusCode, want)
		}
	}
	post("end", `{"ownerKey":"wrong-fixture-key"}`, http.StatusForbidden)
	hub.mu.Lock()
	remaining := len(hub.roomUsers[roomID])
	hub.mu.Unlock()
	if remaining != 2 {
		t.Fatal("failed authorization removed members")
	}

	// Deliberately never emit end-room from either client.
	post("end", `{"ownerKey":"`+ownerKey+`"}`, http.StatusOK)
	for _, client := range clients[:2] {
		payload, err := client.waitEvent(ctx, EventRoomEnded)
		if err != nil {
			t.Fatal(err)
		}
		var ended storage.RoomMetadata
		if err := json.Unmarshal(payload, &ended); err != nil || !ended.Ended || ended.RoomID != roomID {
			t.Fatal("missing ended-room metadata")
		}
		hub.mu.Lock()
		membership := hub.socketRooms[client.socketSID]
		hub.mu.Unlock()
		if membership != "" {
			t.Fatal("ended member retains live permissions")
		}
		serverSocket, ok := ioServer.Sockets().Sockets().Load(socket.SocketId(client.socketSID))
		if !ok || serverSocket.Rooms().Has(socket.Room(roomID)) {
			t.Fatal("ended member remains in Socket.IO room")
		}
		if reason := hub.consumeLiveInkToken(client.socketSID, roomID); reason != liveInkDropNotMember {
			t.Fatal("ended member can still send live ink")
		}
		if err := client.emit(ctx, EventServerBroadcast, roomID,
			map[string]any{"encryptedBuffer": []int{1}, "iv": []int{2}}); err != nil {
			t.Fatal(err)
		}
		if _, err := client.waitEvent(ctx, EventRoomError); err != nil {
			t.Fatal("ended member broadcast was not rejected", err)
		}
	}
	post("end", `{"ownerKey":"`+ownerKey+`"}`, http.StatusOK)
	post("join", `{}`, http.StatusGone)
	if err := clients[1].emit(ctx, EventJoinRoom, roomID); err != nil {
		t.Fatal(err)
	}
	if _, err := clients[1].waitEvent(ctx, EventRoomError); err != nil {
		t.Fatal("ended room accepted rejoin", err)
	}
	if reason := hub.consumeLiveInkToken(clients[2].socketSID, "other-room"); reason != "" {
		t.Fatal("ending one room revoked another room")
	}
}
