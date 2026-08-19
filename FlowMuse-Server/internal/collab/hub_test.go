package collab

import (
	"bytes"
	"log"
	"strings"
	"testing"
)

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
