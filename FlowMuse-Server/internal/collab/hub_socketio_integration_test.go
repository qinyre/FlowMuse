package collab

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/zishang520/socket.io/v2/socket"
)

const enginePacketSeparator = "\x1e"

type pollingSocketClient struct {
	baseURL   string
	engineSID string
	socketSID string
	http      *http.Client
	pending   []string
}

type engineOpenPacket struct {
	SID string `json:"sid"`
}

func newPollingSocketClient(ctx context.Context, baseURL, guestName string) (*pollingSocketClient, error) {
	client := &pollingSocketClient{
		baseURL: baseURL,
		http:    &http.Client{},
	}
	openURL := baseURL + "/socket.io/?EIO=4&transport=polling&guestName=" + url.QueryEscape(guestName)
	body, err := client.request(ctx, http.MethodGet, openURL, "")
	if err != nil {
		return nil, err
	}
	if !strings.HasPrefix(body, "0") {
		return nil, fmt.Errorf("unexpected Engine.IO open packet %q", body)
	}
	var open engineOpenPacket
	if err := json.Unmarshal([]byte(body[1:]), &open); err != nil || open.SID == "" {
		return nil, fmt.Errorf("decode Engine.IO open packet: %w", err)
	}
	client.engineSID = open.SID
	if err := client.post(ctx, "40"); err != nil {
		return nil, err
	}
	for client.socketSID == "" {
		packets, err := client.poll(ctx)
		if err != nil {
			return nil, err
		}
		for _, packet := range packets {
			if strings.HasPrefix(packet, "40") {
				var connected struct {
					SID string `json:"sid"`
				}
				if len(packet) > 2 {
					if err := json.Unmarshal([]byte(packet[2:]), &connected); err != nil {
						return nil, fmt.Errorf("decode Socket.IO connect packet: %w", err)
					}
				}
				client.socketSID = connected.SID
				continue
			}
			client.pending = append(client.pending, packet)
		}
	}
	if client.socketSID == "" {
		return nil, fmt.Errorf("Socket.IO connect packet omitted sid")
	}
	return client, nil
}

func (c *pollingSocketClient) pollingURL() string {
	return c.baseURL + "/socket.io/?EIO=4&transport=polling&sid=" + url.QueryEscape(c.engineSID)
}

func (c *pollingSocketClient) request(ctx context.Context, method, requestURL, payload string) (string, error) {
	request, err := http.NewRequestWithContext(ctx, method, requestURL, strings.NewReader(payload))
	if err != nil {
		return "", err
	}
	if method == http.MethodPost {
		request.Header.Set("Content-Type", "text/plain;charset=UTF-8")
	}
	response, err := c.http.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		return "", err
	}
	if response.StatusCode != http.StatusOK {
		return "", fmt.Errorf("%s %s returned %d: %s", method, requestURL, response.StatusCode, body)
	}
	return string(body), nil
}

func (c *pollingSocketClient) post(ctx context.Context, payload string) error {
	body, err := c.request(ctx, http.MethodPost, c.pollingURL(), payload)
	if err != nil {
		return err
	}
	if body != "ok" {
		return fmt.Errorf("unexpected polling POST response %q", body)
	}
	return nil
}

func (c *pollingSocketClient) poll(ctx context.Context) ([]string, error) {
	body, err := c.request(ctx, http.MethodGet, c.pollingURL(), "")
	if err != nil {
		return nil, err
	}
	packets := strings.Split(body, enginePacketSeparator)
	filtered := packets[:0]
	for _, packet := range packets {
		if packet == "" {
			continue
		}
		if packet == "2" {
			if err := c.post(ctx, "3"); err != nil {
				return nil, err
			}
			continue
		}
		filtered = append(filtered, packet)
	}
	return filtered, nil
}

func (c *pollingSocketClient) emit(ctx context.Context, event string, args ...any) error {
	payload := append([]any{event}, args...)
	encoded, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	return c.post(ctx, "42"+string(encoded))
}

func (c *pollingSocketClient) waitEvent(ctx context.Context, wanted string) (json.RawMessage, error) {
	for {
		packets := c.pending
		c.pending = nil
		if len(packets) == 0 {
			var err error
			packets, err = c.poll(ctx)
			if err != nil {
				return nil, err
			}
		}
		for _, packet := range packets {
			name, payload, ok, err := socketEvent(packet)
			if err != nil {
				return nil, err
			}
			if !ok || name != wanted {
				continue
			}
			return payload, nil
		}
	}
}

func socketEvent(packet string) (string, json.RawMessage, bool, error) {
	if !strings.HasPrefix(packet, "42") {
		return "", nil, false, nil
	}
	var values []json.RawMessage
	if err := json.Unmarshal([]byte(packet[2:]), &values); err != nil {
		return "", nil, false, err
	}
	if len(values) == 0 {
		return "", nil, false, nil
	}
	var name string
	if err := json.Unmarshal(values[0], &name); err != nil {
		return "", nil, false, err
	}
	if len(values) < 2 {
		return name, nil, true, nil
	}
	return name, values[1], true, nil
}

func TestSocketIOLiveInkJoinReadyAndForward(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	ioServer := socket.NewServer(nil, nil)
	hub := NewHub(ioServer, nil, nil, nil, nil)
	hub.roomExistsOverride = func(roomID string) bool { return roomID == "room-e2e" }
	hub.roomEndedOverride = func(string) bool { return false }
	hub.Register()
	httpServer := httptest.NewServer(ioServer.ServeHandler(nil))
	defer httpServer.Close()
	defer ioServer.Close(nil)

	receiver, err := newPollingSocketClient(ctx, httpServer.URL, "receiver")
	if err != nil {
		t.Fatal(err)
	}
	if err := receiver.emit(ctx, EventJoinRoom, "room-e2e"); err != nil {
		t.Fatal(err)
	}
	assertLiveInkReady(t, receiver, ctx)

	sender, err := newPollingSocketClient(ctx, httpServer.URL, "sender")
	if err != nil {
		t.Fatal(err)
	}
	if err := sender.emit(ctx, EventJoinRoom, "room-e2e"); err != nil {
		t.Fatal(err)
	}
	assertLiveInkReady(t, sender, ctx)

	usersPayload, err := receiver.waitEvent(ctx, EventRoomUserChange)
	if err != nil {
		t.Fatal(err)
	}
	var users []RoomUser
	if err := json.Unmarshal(usersPayload, &users); err != nil {
		t.Fatal(err)
	}
	if len(users) != 2 {
		t.Fatalf("expected two room users before volatile send, got %d", len(users))
	}

	pollResult := make(chan struct {
		packets []string
		err     error
	}, 1)
	go func() {
		packets, pollErr := receiver.poll(ctx)
		pollResult <- struct {
			packets []string
			err     error
		}{packets: packets, err: pollErr}
	}()
	waitForPollingWritable(t, ctx, ioServer, receiver.engineSID)

	ciphertext := []byte{1, 2, 3, 4, 5}
	iv := []byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}
	binaryEvent := `452-["server-live-ink","room-e2e",{"encryptedBuffer":{"_placeholder":true,"num":0},"iv":{"_placeholder":true,"num":1}}]`
	binaryPayload := strings.Join([]string{
		binaryEvent,
		"b" + base64.StdEncoding.EncodeToString(ciphertext),
		"b" + base64.StdEncoding.EncodeToString(iv),
	}, enginePacketSeparator)
	if err := sender.post(ctx, binaryPayload); err != nil {
		t.Fatal(err)
	}

	result := <-pollResult
	if result.err != nil {
		t.Fatal(result.err)
	}
	packets := result.packets
	for binaryAttachmentCount(packets) < 2 {
		more, err := receiver.poll(ctx)
		if err != nil {
			t.Fatal(err)
		}
		packets = append(packets, more...)
	}
	assertForwardedLiveInk(t, packets, sender.socketSID, ciphertext, iv)
	assertVolatileFrameIsNotBuffered(t, ctx, ioServer, hub, receiver, sender)
}

func assertLiveInkReady(t *testing.T, client *pollingSocketClient, ctx context.Context) {
	t.Helper()
	payload, err := client.waitEvent(ctx, EventLiveInkReady)
	if err != nil {
		t.Fatal(err)
	}
	var ready LiveInkReady
	if err := json.Unmarshal(payload, &ready); err != nil {
		t.Fatal(err)
	}
	if ready.RoomID != "room-e2e" || ready.LiveInkProtocolVersion != liveInkProtocolVersion {
		t.Fatalf("unexpected live ink ready payload: %+v", ready)
	}
}

func waitForPollingWritable(t *testing.T, ctx context.Context, ioServer *socket.Server, engineSID string) {
	t.Helper()
	ticker := time.NewTicker(time.Millisecond)
	defer ticker.Stop()
	for {
		engineSocket, ok := ioServer.Engine().Clients().Load(engineSID)
		if ok && engineSocket.Transport().Writable() {
			return
		}
		select {
		case <-ctx.Done():
			t.Fatal("receiver polling transport did not become writable")
		case <-ticker.C:
		}
	}
}

func assertVolatileFrameIsNotBuffered(
	t *testing.T,
	ctx context.Context,
	ioServer *socket.Server,
	hub *Hub,
	receiver, sender *pollingSocketClient,
) {
	t.Helper()
	senderSocket, ok := ioServer.Sockets().Sockets().Load(socket.SocketId(sender.socketSID))
	if !ok {
		t.Fatal("sender Socket.IO server socket is missing")
	}
	engineSocket, ok := ioServer.Engine().Clients().Load(receiver.engineSID)
	if !ok || engineSocket.Transport().Writable() {
		t.Fatal("receiver must have no active poll before the volatile drop check")
	}
	hub.forwardLiveInk(senderSocket, []any{"room-e2e", map[string]any{
		"encryptedBuffer": []byte{9, 9, 9},
		"iv":              []byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11},
	}})

	pollResult := make(chan struct {
		packets []string
		err     error
	}, 1)
	go func() {
		packets, pollErr := receiver.poll(ctx)
		pollResult <- struct {
			packets []string
			err     error
		}{packets: packets, err: pollErr}
	}()
	waitForPollingWritable(t, ctx, ioServer, receiver.engineSID)
	senderSocket.To(socket.Room("room-e2e")).Emit("reliable-test-marker", "done")
	result := <-pollResult
	if result.err != nil {
		t.Fatal(result.err)
	}
	foundMarker := false
	for _, packet := range result.packets {
		name, _, event, err := socketEvent(packet)
		if err != nil {
			t.Fatal(err)
		}
		if strings.HasPrefix(packet, "45") {
			t.Fatalf("volatile live ink was buffered without an active poll: %q", result.packets)
		}
		foundMarker = foundMarker || event && name == "reliable-test-marker"
	}
	if !foundMarker {
		t.Fatalf("reliable marker did not flush the receiver poll: %q", result.packets)
	}
}

func assertForwardedLiveInk(t *testing.T, packets []string, senderSocketID string, ciphertext, iv []byte) {
	t.Helper()
	var header map[string]any
	attachments := make([][]byte, 0, 2)
	for _, packet := range packets {
		switch {
		case strings.HasPrefix(packet, "452-"):
			var values []json.RawMessage
			if err := json.Unmarshal([]byte(packet[4:]), &values); err != nil {
				t.Fatal(err)
			}
			var event string
			if len(values) != 2 || json.Unmarshal(values[0], &event) != nil || event != EventClientLiveInk {
				t.Fatalf("unexpected binary event header %q", packet)
			}
			if err := json.Unmarshal(values[1], &header); err != nil {
				t.Fatal(err)
			}
		case strings.HasPrefix(packet, "b"):
			decoded, err := base64.StdEncoding.DecodeString(packet[1:])
			if err != nil {
				t.Fatal(err)
			}
			attachments = append(attachments, decoded)
		}
	}
	if header == nil || header["senderSocketId"] != senderSocketID {
		t.Fatalf("missing server-derived sender socket id in %#v", header)
	}
	encryptedAttachment, encryptedOK := binaryPlaceholderNumber(header["encryptedBuffer"])
	ivAttachment, ivOK := binaryPlaceholderNumber(header["iv"])
	if !encryptedOK || !ivOK || len(attachments) != 2 ||
		string(attachments[encryptedAttachment]) != string(ciphertext) ||
		string(attachments[ivAttachment]) != string(iv) {
		t.Fatalf("unexpected live ink binary attachments: packets=%q attachments=%#v header=%#v", packets, attachments, header)
	}
}

func binaryPlaceholderNumber(value any) (int, bool) {
	placeholder, ok := value.(map[string]any)
	if !ok || placeholder["_placeholder"] != true {
		return 0, false
	}
	number, ok := placeholder["num"].(float64)
	if !ok || number < 0 || number >= 2 || number != float64(int(number)) {
		return 0, false
	}
	return int(number), true
}

func binaryAttachmentCount(packets []string) int {
	count := 0
	for _, packet := range packets {
		if strings.HasPrefix(packet, "b") {
			count++
		}
	}
	return count
}
