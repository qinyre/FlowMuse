package collab

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/zishang520/engine.io-go-parser/packet"
	"github.com/zishang520/engine.io/v2/types"
	"github.com/zishang520/socket.io/v2/socket"
)

// A cached room broadcast can share a flush with ready, final and binary frames.
func TestWebSocketPreparedFrameDoesNotDiscardFollowingPackets(t *testing.T) {
	server := socket.NewServer(nil, nil)
	hub := NewHub(server, nil, nil, nil, nil)
	hub.Register()
	local := httptest.NewServer(server.ServeHandler(nil))
	defer local.Close()
	defer server.Close(nil)
	conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(local.URL, "http")+"/socket.io/?EIO=4&transport=websocket", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	_, opened, err := conn.ReadMessage()
	if err != nil || len(opened) < 2 || opened[0] != '0' {
		t.Fatal("missing Engine.IO handshake")
	}
	var info engineOpenPacket
	if err := json.Unmarshal(opened[1:], &info); err != nil {
		t.Fatal(err)
	}
	if err := conn.WriteMessage(websocket.TextMessage, []byte("40")); err != nil {
		t.Fatal(err)
	}
	for {
		_, data, err := conn.ReadMessage()
		if err != nil {
			t.Fatal("missing Socket.IO readiness")
		}
		if strings.Contains(string(data), EventInitRoom) {
			break
		}
	}
	engineSocket, ok := server.Engine().Clients().Load(info.SID)
	if !ok {
		t.Fatal("missing engine socket")
	}
	deadline := time.Now().Add(time.Second)
	for !engineSocket.Transport().Writable() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if !engineSocket.Transport().Writable() {
		t.Fatal("transport did not drain")
	}
	engineSocket.Transport().Send([]*packet.Packet{
		{Type: packet.MESSAGE, Data: types.NewStringBufferString(`2["fixture-prepared"]`), Options: &packet.Options{WsPreEncodedFrame: types.NewStringBufferString(`42["fixture-prepared"]`)}},
		{Type: packet.MESSAGE, Data: types.NewStringBufferString(`2["fixture-ready"]`)},
		{Type: packet.MESSAGE, Data: types.NewStringBufferString(`2["fixture-final"]`)},
		{Type: packet.MESSAGE, Data: types.NewBytesBuffer([]byte{1, 2, 3})},
	})
	for i := 0; i < 4; i++ {
		kind, data, err := conn.ReadMessage()
		if err != nil {
			t.Fatalf("batch lost packet %d of 4", i+1)
		}
		if i < 3 {
			want := []string{"fixture-prepared", "fixture-ready", "fixture-final"}[i]
			if kind != websocket.TextMessage || !strings.Contains(string(data), want) {
				t.Fatalf("wrong packet order at %d", i)
			}
		} else if kind != websocket.BinaryMessage || len(data) != 3 {
			t.Fatal("binary packet lost or changed")
		}
	}
}
