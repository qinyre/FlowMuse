package collab

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"flowmuse/server/internal/auth"
	"flowmuse/server/internal/storage"

	"github.com/jackc/pgx/v5"
	parserTypes "github.com/zishang520/engine.io-go-parser/types"
	"github.com/zishang520/socket.io/v2/socket"
)

const maxEncryptedFrameBytes = 8 * 1024 * 1024

const (
	liveInkProtocolVersion    = 2
	liveInkIVBytes            = 12
	maxLiveInkCiphertextBytes = 64 * 1024
	liveInkSocketRate         = 60.0
	liveInkSocketBurst        = 120.0
	liveInkRoomRate           = 300.0
	liveInkRoomBurst          = 600.0
)

type liveInkDropReason string

const (
	liveInkDropInvalidEnvelope liveInkDropReason = "invalid_envelope"
	liveInkDropNotMember       liveInkDropReason = "not_member"
	liveInkDropInvalidIV       liveInkDropReason = "invalid_iv"
	liveInkDropOversize        liveInkDropReason = "ciphertext_oversize"
	liveInkDropUnsupported     liveInkDropReason = "unsupported_bytes"
	liveInkDropSocketRate      liveInkDropReason = "socket_rate"
	liveInkDropRoomRate        liveInkDropReason = "room_rate"
)

type tokenBucket struct {
	tokens float64
	last   time.Time
}

func (b *tokenBucket) allow(now time.Time, rate, burst float64) bool {
	if b.last.IsZero() {
		b.tokens = burst
	} else if elapsed := now.Sub(b.last).Seconds(); elapsed > 0 {
		b.tokens = min(burst, b.tokens+elapsed*rate)
	}
	b.last = now
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

type Hub struct {
	server     *socket.Server
	sceneStore *storage.SceneStore
	roomStore  *storage.RoomStore
	userStore  *auth.UserStore
	tokens     *auth.TokenService

	mu                   sync.Mutex
	roomUsers            map[string]map[string]RoomUser
	socketRooms          map[string]string
	socketUsers          map[string]RoomUser
	followRooms          map[string]map[string]struct{}
	liveInkSocketBuckets map[string]*tokenBucket
	liveInkRoomBuckets   map[string]*tokenBucket
	liveInkDropCounts    map[liveInkDropReason]uint64
	now                  func() time.Time
}

func NewHub(
	server *socket.Server,
	sceneStore *storage.SceneStore,
	roomStore *storage.RoomStore,
	userStore *auth.UserStore,
	tokens *auth.TokenService,
) *Hub {
	return &Hub{
		server:               server,
		sceneStore:           sceneStore,
		roomStore:            roomStore,
		userStore:            userStore,
		tokens:               tokens,
		roomUsers:            map[string]map[string]RoomUser{},
		socketRooms:          map[string]string{},
		socketUsers:          map[string]RoomUser{},
		followRooms:          map[string]map[string]struct{}{},
		liveInkSocketBuckets: map[string]*tokenBucket{},
		liveInkRoomBuckets:   map[string]*tokenBucket{},
		liveInkDropCounts:    map[liveInkDropReason]uint64{},
		now:                  time.Now,
	}
}

func (h *Hub) Register() {
	h.server.On("connection", func(clients ...any) {
		client := clients[0].(*socket.Socket)
		h.rememberSocketIdentity(client)
		client.Emit(EventInitRoom)

		client.On(EventJoinRoom, func(args ...any) {
			roomID, ok := firstString(args)
			if !ok {
				return
			}
			h.joinRoom(client, roomID)
		})

		client.On(EventLeaveRoom, func(args ...any) {
			roomID, ok := firstString(args)
			if !ok {
				return
			}
			h.leaveRoom(client, roomID)
		})

		client.On(EventEndRoom, func(args ...any) {
			roomID, ownerKey, ok := endRoomPayload(args)
			if !ok {
				return
			}
			h.endRoom(client, roomID, ownerKey)
		})

		client.On(EventServerBroadcast, func(args ...any) {
			h.forward(client, args, false)
		})

		client.On(EventServerVolatile, func(args ...any) {
			h.forward(client, args, true)
		})

		client.On(EventServerLiveInk, func(args ...any) {
			h.forwardLiveInk(client, args)
		})

		client.On(EventUserFollow, func(args ...any) {
			h.userFollow(client, args)
		})

		client.On("disconnect", func(...any) {
			h.leaveAll(client)
		})
	})
}

func (h *Hub) joinRoom(client *socket.Socket, roomID string) {
	if !h.roomExists(roomID) {
		client.Emit(EventRoomError, "房间不存在或尚未创建")
		return
	}
	if h.roomEnded(roomID) {
		client.Emit(EventRoomError, "协作房间已结束")
		return
	}
	socketID := string(client.Id())
	room := socket.Room(roomID)

	h.mu.Lock()
	if previousRoomID := h.socketRooms[socketID]; previousRoomID != "" && previousRoomID != roomID {
		h.removeFromRoomLocked(socketID, previousRoomID)
		client.Leave(socket.Room(previousRoomID))
	}
	users := h.roomUsers[roomID]
	first := len(users) == 0
	if users == nil {
		users = map[string]RoomUser{}
		h.roomUsers[roomID] = users
	}
	user := h.socketUsers[socketID]
	if user.SocketID == "" {
		user = roomUserFromSocket(client, h.identityFromSocket(client))
		h.socketUsers[socketID] = user
	}
	users[socketID] = user
	h.socketRooms[socketID] = roomID
	currentUsers := roomUserList(users)
	h.mu.Unlock()

	h.recordRoomJoin(roomID, user)
	client.Join(room)
	if first {
		client.Emit(EventFirstInRoom)
	} else {
		client.To(room).Emit(EventNewUser, user)
	}
	h.server.To(room).Emit(EventRoomUserChange, currentUsers)
	client.Emit(EventLiveInkReady, LiveInkReady{
		RoomID:                 roomID,
		LiveInkProtocolVersion: liveInkProtocolVersion,
	})
}

func (h *Hub) forwardLiveInk(client *socket.Socket, args []any) {
	h.withLiveInkFrame(string(client.Id()), args, func(roomID string, frame ReceivedLiveInkFrame) {
		client.To(socket.Room(roomID)).Volatile().Emit(EventClientLiveInk, frame)
	})
}

func (h *Hub) liveInkFrameFor(socketID string, args []any) (string, ReceivedLiveInkFrame, bool) {
	var roomID string
	var frame ReceivedLiveInkFrame
	ok := h.withLiveInkFrame(socketID, args, func(acceptedRoomID string, acceptedFrame ReceivedLiveInkFrame) {
		roomID = acceptedRoomID
		frame = acceptedFrame
	})
	return roomID, frame, ok
}

func (h *Hub) withLiveInkFrame(socketID string, args []any, accept func(string, ReceivedLiveInkFrame)) bool {
	roomID, ok := liveInkRoomID(args)
	if !ok {
		if reason := h.consumeLiveInkIngressToken(socketID, ""); reason != "" {
			h.recordLiveInkDrop(socketID, reason, visibleLiveInkBytes(args))
			return false
		}
		h.recordLiveInkDrop(socketID, liveInkDropInvalidEnvelope, visibleLiveInkBytes(args))
		return false
	}
	if reason := h.consumeLiveInkIngressToken(socketID, roomID); reason != "" {
		h.recordLiveInkDrop(socketID, reason, visibleLiveInkBytes(args))
		return false
	}
	encryptedBuffer, iv, byteCount, reason, ok := parseLiveInkEnvelope(args[1])
	if !ok {
		h.recordLiveInkDrop(socketID, reason, byteCount)
		return false
	}

	h.mu.Lock()
	if h.socketRooms[socketID] != roomID {
		h.mu.Unlock()
		h.recordLiveInkDrop(socketID, liveInkDropNotMember, byteCount)
		return false
	}
	if reason := h.consumeLiveInkRoomTokenLocked(roomID); reason != "" {
		h.mu.Unlock()
		h.recordLiveInkDrop(socketID, reason, byteCount)
		return false
	}
	frame := ReceivedLiveInkFrame{
		EncryptedBuffer: cloneBytes(encryptedBuffer),
		IV:              cloneBytes(iv),
		SenderSocketID:  socketID,
	}
	accept(roomID, frame)
	h.mu.Unlock()
	return true
}

func (h *Hub) consumeLiveInkIngressToken(socketID, roomID string) liveInkDropReason {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.liveInkSocketBuckets == nil {
		h.liveInkSocketBuckets = map[string]*tokenBucket{}
	}
	now := h.liveInkNow()
	socketBucket := h.liveInkSocketBuckets[socketID]
	if socketBucket == nil {
		socketBucket = &tokenBucket{}
		h.liveInkSocketBuckets[socketID] = socketBucket
	}
	if !socketBucket.allow(now, liveInkSocketRate, liveInkSocketBurst) {
		return liveInkDropSocketRate
	}
	if roomID != "" && h.socketRooms[socketID] != roomID {
		return liveInkDropNotMember
	}
	return ""
}

func (h *Hub) consumeLiveInkToken(socketID, roomID string) liveInkDropReason {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.socketRooms[socketID] != roomID {
		return liveInkDropNotMember
	}
	if h.liveInkSocketBuckets == nil {
		h.liveInkSocketBuckets = map[string]*tokenBucket{}
	}
	if h.liveInkRoomBuckets == nil {
		h.liveInkRoomBuckets = map[string]*tokenBucket{}
	}
	now := h.liveInkNow()
	socketBucket := h.liveInkSocketBuckets[socketID]
	if socketBucket == nil {
		socketBucket = &tokenBucket{}
		h.liveInkSocketBuckets[socketID] = socketBucket
	}
	if !socketBucket.allow(now, liveInkSocketRate, liveInkSocketBurst) {
		return liveInkDropSocketRate
	}
	return h.consumeLiveInkRoomTokenLockedAt(roomID, now)
}

func (h *Hub) consumeLiveInkRoomTokenLocked(roomID string) liveInkDropReason {
	return h.consumeLiveInkRoomTokenLockedAt(roomID, h.liveInkNow())
}

func (h *Hub) consumeLiveInkRoomTokenLockedAt(roomID string, now time.Time) liveInkDropReason {
	if h.liveInkRoomBuckets == nil {
		h.liveInkRoomBuckets = map[string]*tokenBucket{}
	}
	roomBucket := h.liveInkRoomBuckets[roomID]
	if roomBucket == nil {
		roomBucket = &tokenBucket{}
		h.liveInkRoomBuckets[roomID] = roomBucket
	}
	if !roomBucket.allow(now, liveInkRoomRate, liveInkRoomBurst) {
		return liveInkDropRoomRate
	}
	return ""
}

func (h *Hub) liveInkNow() time.Time {
	if h.now != nil {
		return h.now()
	}
	return time.Now()
}

func (h *Hub) forward(client *socket.Socket, args []any, volatile bool) {
	roomID, frame, ok := parseBroadcastArgs(args)
	if !ok {
		log.Printf(
			"[FlowMuseCollab][server][broadcast_drop] socket=%s reason=parse_broadcast_failed args=%s",
			client.Id(),
			describeArgTypes(args),
		)
		return
	}
	socketID := string(client.Id())
	h.mu.Lock()
	currentRoomID := h.socketRooms[socketID]
	h.mu.Unlock()
	if currentRoomID != roomID {
		client.Emit(EventRoomError, "当前连接不在目标房间")
		return
	}
	if len(frame.EncryptedBuffer)+len(frame.IV) > maxEncryptedFrameBytes {
		client.Emit(EventRoomError, "协作消息过大")
		return
	}
	logForward(socketID, roomID, frame, volatile)
	operator := client.To(socket.Room(roomID))
	if volatile {
		operator = operator.Volatile()
	}
	operator.Emit(EventClientBroadcast, frame.EncryptedBuffer, frame.IV)
}

func (h *Hub) leaveRoom(client *socket.Socket, roomID string) {
	socketID := string(client.Id())

	h.mu.Lock()
	if h.socketRooms[socketID] != roomID {
		h.mu.Unlock()
		return
	}
	h.removeFromRoomLocked(socketID, roomID)
	users := roomUserList(h.roomUsers[roomID])
	h.mu.Unlock()

	client.Leave(socket.Room(roomID))
	h.server.To(socket.Room(roomID)).Emit(EventRoomUserChange, users)
}

func (h *Hub) endRoom(client *socket.Socket, roomID string, ownerKey string) {
	identity := h.identityFromSocket(client)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	metadata, err := h.roomStore.EndRoom(ctx, roomID, identity.UserID, hashOwnerKey(roomID, ownerKey))
	if errors.Is(err, storage.ErrRoomAccessDenied) {
		client.Emit(EventRoomError, "只有房主可以结束协作")
		return
	}
	if err != nil {
		client.Emit(EventRoomError, err.Error())
		return
	}

	h.mu.Lock()
	users := h.roomUsers[roomID]
	socketIDs := make([]string, 0, len(users))
	for socketID := range users {
		socketIDs = append(socketIDs, socketID)
		delete(h.socketRooms, socketID)
		delete(h.liveInkSocketBuckets, socketID)
	}
	delete(h.roomUsers, roomID)
	delete(h.liveInkRoomBuckets, roomID)
	h.mu.Unlock()

	room := socket.Room(roomID)
	h.server.To(room).Emit(EventRoomEnded, metadata)
	h.server.To(room).Emit(EventRoomUserChange, []RoomUser{})
	for _, socketID := range socketIDs {
		h.server.In(socket.Room(socketID)).SocketsLeave(room)
	}
}

func (h *Hub) userFollow(client *socket.Socket, args []any) {
	roomID, followedSocketID, ok := parseUserFollowArgs(args)
	if !ok {
		return
	}
	socketID := string(client.Id())
	followRoomID := fmt.Sprintf("%s:%s", roomID, followedSocketID)

	h.mu.Lock()
	followers := h.followRooms[followRoomID]
	if followers == nil {
		followers = map[string]struct{}{}
		h.followRooms[followRoomID] = followers
	}
	followers[socketID] = struct{}{}
	followerIDs := make([]string, 0, len(followers))
	for id := range followers {
		followerIDs = append(followerIDs, id)
	}
	h.mu.Unlock()

	h.server.To(socket.Room(roomID)).Emit(EventUserFollowRoomChange, followedSocketID, followerIDs)
}

func (h *Hub) leaveAll(client *socket.Socket) {
	socketID := string(client.Id())
	roomID, users := h.removeSocket(socketID)

	if roomID != "" {
		h.server.To(socket.Room(roomID)).Emit(EventRoomUserChange, users)
	}
}

func (h *Hub) removeSocket(socketID string) (string, []RoomUser) {
	h.mu.Lock()
	defer h.mu.Unlock()
	roomID := h.socketRooms[socketID]
	if roomID != "" {
		h.removeFromRoomLocked(socketID, roomID)
	}
	for followRoomID, followers := range h.followRooms {
		delete(followers, socketID)
		if len(followers) == 0 {
			delete(h.followRooms, followRoomID)
		}
	}
	var users []RoomUser
	if roomID != "" {
		users = roomUserList(h.roomUsers[roomID])
	}
	delete(h.socketUsers, socketID)
	delete(h.liveInkSocketBuckets, socketID)
	return roomID, users
}

func logForward(socketID, roomID string, frame EncryptedFrame, volatile bool) {
	if volatile {
		return
	}
	log.Printf(
		"[FlowMuseCollab][server][broadcast_forward] socket=%s room=%s encryptedBytes=%d ivBytes=%d volatile=false",
		socketID,
		roomID,
		len(frame.EncryptedBuffer),
		len(frame.IV),
	)
}

func (h *Hub) removeFromRoomLocked(socketID, roomID string) {
	delete(h.socketRooms, socketID)
	delete(h.liveInkSocketBuckets, socketID)
	users := h.roomUsers[roomID]
	if users == nil {
		delete(h.liveInkRoomBuckets, roomID)
		return
	}
	delete(users, socketID)
	if len(users) == 0 {
		delete(h.roomUsers, roomID)
		delete(h.liveInkRoomBuckets, roomID)
	}
}

func (h *Hub) roomExists(roomID string) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_, err := h.sceneStore.Load(ctx, roomID)
	if err == nil {
		return true
	}
	return !errors.Is(err, pgx.ErrNoRows)
}

func (h *Hub) roomEnded(roomID string) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	metadata, err := h.roomStore.LoadRoom(ctx, roomID, "")
	return err == nil && metadata.Ended
}

func parseBroadcastArgs(args []any) (string, EncryptedFrame, bool) {
	if len(args) < 2 {
		return "", EncryptedFrame{}, false
	}
	roomID, ok := asString(args[0])
	if !ok {
		return "", EncryptedFrame{}, false
	}
	if frame, ok := asFrame(args[1]); ok {
		return roomID, frame, true
	}
	if len(args) < 3 {
		return "", EncryptedFrame{}, false
	}
	encryptedBuffer, ok := asBytes(args[1])
	if !ok {
		return "", EncryptedFrame{}, false
	}
	iv, ok := asBytes(args[2])
	if !ok {
		return "", EncryptedFrame{}, false
	}
	return roomID, EncryptedFrame{EncryptedBuffer: encryptedBuffer, IV: iv}, true
}

func liveInkRoomID(args []any) (string, bool) {
	if len(args) != 2 {
		return "", false
	}
	return asString(args[0])
}

func parseLiveInkEnvelope(value any) ([]byte, []byte, int, liveInkDropReason, bool) {
	values, ok := value.(map[string]any)
	if !ok {
		return nil, nil, 0, liveInkDropInvalidEnvelope, false
	}
	encryptedBuffer, encryptedBytes, supported := visibleBytes(values["encryptedBuffer"], maxLiveInkCiphertextBytes)
	iv, ivBytes, ivSupported := visibleBytes(values["iv"], liveInkIVBytes)
	byteCount := encryptedBytes + ivBytes
	if !supported || !ivSupported {
		return nil, nil, byteCount, liveInkDropUnsupported, false
	}
	if ivBytes != liveInkIVBytes {
		return nil, nil, byteCount, liveInkDropInvalidIV, false
	}
	if encryptedBytes > maxLiveInkCiphertextBytes {
		return nil, nil, byteCount, liveInkDropOversize, false
	}
	return encryptedBuffer, iv, byteCount, "", true
}

// visibleBytes checks a payload's visible length without copying it. Socket.IO's
// BufferInterface exposes Len, so oversized payloads are rejected before Bytes.
// Generic []any values are intentionally rejected instead of allocating a copy.
func visibleBytes(value any, maxBytes int) ([]byte, int, bool) {
	switch typed := value.(type) {
	case []byte:
		return typed, len(typed), true
	case parserTypes.BufferInterface:
		length := typed.Len()
		if length < 0 {
			return nil, 0, false
		}
		if length > maxBytes {
			return nil, length, true
		}
		return typed.Bytes(), length, true
	default:
		return nil, visibleByteLen(value), false
	}
}

func visibleByteLen(value any) int {
	switch typed := value.(type) {
	case []byte:
		return len(typed)
	case []any:
		return len(typed)
	case parserTypes.BufferInterface:
		return typed.Len()
	default:
		return 0
	}
}

func visibleLiveInkBytes(args []any) int {
	if len(args) < 2 {
		return 0
	}
	values, ok := args[1].(map[string]any)
	if !ok {
		return visibleByteLen(args[1])
	}
	return visibleByteLen(values["encryptedBuffer"]) + visibleByteLen(values["iv"])
}

func logLiveInkDrop(socketID string, reason liveInkDropReason, byteCount int) {
	if len(socketID) > 8 {
		socketID = socketID[:8]
	}
	log.Printf(
		"[FlowMuseCollab][server][live_ink_drop] reason=%s socket=%s bytes=%d",
		reason,
		socketID,
		byteCount,
	)
}

func (h *Hub) recordLiveInkDrop(socketID string, reason liveInkDropReason, byteCount int) {
	h.mu.Lock()
	if h.liveInkDropCounts == nil {
		h.liveInkDropCounts = map[liveInkDropReason]uint64{}
	}
	count := h.liveInkDropCounts[reason] + 1
	h.liveInkDropCounts[reason] = count
	h.mu.Unlock()
	if count&(count-1) == 0 {
		logLiveInkDrop(socketID, reason, byteCount)
	}
}

func asFrame(value any) (EncryptedFrame, bool) {
	values, ok := value.(map[string]any)
	if !ok {
		return EncryptedFrame{}, false
	}
	encryptedBuffer, ok := asBytes(values["encryptedBuffer"])
	if !ok {
		return EncryptedFrame{}, false
	}
	iv, ok := asBytes(values["iv"])
	if !ok {
		return EncryptedFrame{}, false
	}
	return EncryptedFrame{EncryptedBuffer: encryptedBuffer, IV: iv}, true
}

func asBytes(value any) ([]byte, bool) {
	switch typed := value.(type) {
	case []byte:
		return cloneBytes(typed), true
	case parserTypes.BufferInterface:
		return cloneBytes(typed.Bytes()), true
	case []any:
		bytes := make([]byte, 0, len(typed))
		for _, item := range typed {
			number, ok := item.(float64)
			if !ok {
				return nil, false
			}
			bytes = append(bytes, byte(number))
		}
		return bytes, true
	default:
		return nil, false
	}
}

func cloneBytes(value []byte) []byte {
	bytes := make([]byte, len(value))
	copy(bytes, value)
	return bytes
}

func describeArgTypes(args []any) string {
	if len(args) == 0 {
		return "[]"
	}
	text := "["
	for index, arg := range args {
		if index > 0 {
			text += ", "
		}
		text += fmt.Sprintf("%T", arg)
		if values, ok := arg.(map[string]any); ok {
			text += "{"
			first := true
			for key, value := range values {
				if !first {
					text += ", "
				}
				first = false
				text += fmt.Sprintf("%s:%T", key, value)
			}
			text += "}"
		}
	}
	text += "]"
	return text
}

func firstString(args []any) (string, bool) {
	if len(args) == 0 {
		return "", false
	}
	return asString(args[0])
}

func endRoomPayload(args []any) (string, string, bool) {
	if len(args) == 0 {
		return "", "", false
	}
	if roomID, ok := asString(args[0]); ok {
		return roomID, "", true
	}
	values, ok := args[0].(map[string]any)
	if !ok {
		return "", "", false
	}
	roomID, ok := asString(values["roomId"])
	if !ok {
		return "", "", false
	}
	ownerKey, _ := asString(values["ownerKey"])
	return roomID, ownerKey, true
}

func asString(value any) (string, bool) {
	text, ok := value.(string)
	return text, ok && text != ""
}

func roomUserList(users map[string]RoomUser) []RoomUser {
	list := make([]RoomUser, 0, len(users))
	for _, user := range users {
		list = append(list, user)
	}
	return list
}

func (h *Hub) rememberSocketIdentity(client *socket.Socket) {
	identity := h.identityFromSocket(client)
	user := roomUserFromSocket(client, identity)
	h.mu.Lock()
	h.socketUsers[user.SocketID] = user
	h.mu.Unlock()
}

func (h *Hub) identityFromSocket(client *socket.Socket) auth.Identity {
	token := auth.BearerToken(requestHeader(client, "Authorization"))
	if token != "" {
		if userID, sessionID, err := h.tokens.Verify(token); err == nil {
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			if !h.userStore.SessionActive(ctx, sessionID, userID) {
				return guestIdentityFromSocket(client)
			}
			if user, err := h.userStore.Load(ctx, userID); err == nil {
				return auth.Identity{
					UserID:      user.ID,
					Email:       user.Email,
					DisplayName: user.DisplayName,
					AvatarURL:   user.AvatarURL,
					IsGuest:     false,
				}
			}
		}
	}
	return guestIdentityFromSocket(client)
}

func guestIdentityFromSocket(client *socket.Socket) auth.Identity {
	displayName := strings.TrimSpace(requestQuery(client, "guestName"))
	if displayName == "" {
		displayName = auth.GuestName(string(client.Id()) + remoteAddress(client))
	}
	return auth.Identity{
		DisplayName: displayName,
		AvatarURL:   strings.TrimSpace(requestQuery(client, "guestAvatarUrl")),
		IsGuest:     true,
	}
}

func roomUserFromSocket(client *socket.Socket, identity auth.Identity) RoomUser {
	return RoomUser{
		SocketID:  string(client.Id()),
		UserID:    identity.UserID,
		Username:  identity.Username(),
		AvatarURL: identity.AvatarURL,
		IsGuest:   identity.IsGuest,
	}
}

func (h *Hub) recordRoomJoin(roomID string, user RoomUser) {
	if user.UserID == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = h.roomStore.UpsertMember(ctx, roomID, user.UserID, "editor")
}

func requestHeader(client *socket.Socket, key string) string {
	if client == nil || client.Request() == nil || client.Request().Request() == nil {
		return ""
	}
	return client.Request().Request().Header.Get(key)
}

func requestQuery(client *socket.Socket, key string) string {
	if client == nil || client.Request() == nil || client.Request().Request() == nil {
		return ""
	}
	return client.Request().Request().URL.Query().Get(key)
}

func remoteAddress(client *socket.Socket) string {
	if client == nil || client.Request() == nil || client.Request().Request() == nil {
		return ""
	}
	return client.Request().Request().RemoteAddr
}

func parseUserFollowArgs(args []any) (string, string, bool) {
	if len(args) >= 2 {
		roomID, roomOK := asString(args[0])
		followedSocketID, socketOK := asString(args[1])
		return roomID, followedSocketID, roomOK && socketOK
	}
	if len(args) == 0 {
		return "", "", false
	}
	payload, ok := args[0].(map[string]any)
	if !ok {
		return "", "", false
	}
	userToFollow, ok := payload["userToFollow"].(map[string]any)
	if !ok {
		return "", "", false
	}
	roomID, roomOK := asString(payload["roomId"])
	followedSocketID, socketOK := asString(userToFollow["socketId"])
	return roomID, followedSocketID, roomOK && socketOK
}
