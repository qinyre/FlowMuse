package collab

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"flowmuse/server/internal/auth"
	"flowmuse/server/internal/storage"

	"github.com/jackc/pgx/v5"
	"github.com/zishang520/socket.io/v2/socket"
)

const maxEncryptedFrameBytes = 8 * 1024 * 1024

type Hub struct {
	server     *socket.Server
	sceneStore *storage.SceneStore
	roomStore  *storage.RoomStore
	userStore  *auth.UserStore
	tokens     *auth.TokenService

	mu          sync.Mutex
	roomUsers   map[string]map[string]RoomUser
	socketRooms map[string]string
	socketUsers map[string]RoomUser
	followRooms map[string]map[string]struct{}
}

func NewHub(
	server *socket.Server,
	sceneStore *storage.SceneStore,
	roomStore *storage.RoomStore,
	userStore *auth.UserStore,
	tokens *auth.TokenService,
) *Hub {
	return &Hub{
		server:      server,
		sceneStore:  sceneStore,
		roomStore:   roomStore,
		userStore:   userStore,
		tokens:      tokens,
		roomUsers:   map[string]map[string]RoomUser{},
		socketRooms: map[string]string{},
		socketUsers: map[string]RoomUser{},
		followRooms: map[string]map[string]struct{}{},
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
			roomID, ok := firstString(args)
			if !ok {
				return
			}
			h.endRoom(client, roomID)
		})

		client.On(EventServerBroadcast, func(args ...any) {
			h.forward(client, args, false)
		})

		client.On(EventServerVolatile, func(args ...any) {
			h.forward(client, args, true)
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
		user = roomUserFromSocket(client, auth.Identity{
			DisplayName: auth.GuestName(socketID),
			IsGuest:     true,
		})
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
}

func (h *Hub) forward(client *socket.Socket, args []any, volatile bool) {
	roomID, frame, ok := parseBroadcastArgs(args)
	if !ok {
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

func (h *Hub) endRoom(client *socket.Socket, roomID string) {
	identity := h.identityFromSocket(client)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	metadata, err := h.roomStore.EndRoom(ctx, roomID, identity.UserID)
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
	}
	delete(h.roomUsers, roomID)
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

	h.mu.Lock()
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
	h.mu.Unlock()

	if roomID != "" {
		h.server.To(socket.Room(roomID)).Emit(EventRoomUserChange, users)
	}
}

func (h *Hub) removeFromRoomLocked(socketID, roomID string) {
	delete(h.socketRooms, socketID)
	users := h.roomUsers[roomID]
	if users == nil {
		return
	}
	delete(users, socketID)
	if len(users) == 0 {
		delete(h.roomUsers, roomID)
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
		return typed, true
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

func firstString(args []any) (string, bool) {
	if len(args) == 0 {
		return "", false
	}
	return asString(args[0])
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
		if userID, err := h.tokens.Verify(token); err == nil {
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
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
	return auth.Identity{
		DisplayName: auth.GuestName(string(client.Id()) + remoteAddress(client)),
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
