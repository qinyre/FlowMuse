package collab

import (
	"fmt"
	"sync"

	"github.com/zishang520/socket.io/v2/socket"
)

type Hub struct {
	server *socket.Server

	mu          sync.Mutex
	roomUsers   map[string]map[string]struct{}
	socketRooms map[string]string
	followRooms map[string]map[string]struct{}
}

func NewHub(server *socket.Server) *Hub {
	return &Hub{
		server:      server,
		roomUsers:   map[string]map[string]struct{}{},
		socketRooms: map[string]string{},
		followRooms: map[string]map[string]struct{}{},
	}
}

func (h *Hub) Register() {
	h.server.On("connection", func(clients ...any) {
		client := clients[0].(*socket.Socket)
		client.Emit(EventInitRoom)

		client.On(EventJoinRoom, func(args ...any) {
			roomID, ok := firstString(args)
			if !ok {
				return
			}
			h.joinRoom(client, roomID)
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
		users = map[string]struct{}{}
		h.roomUsers[roomID] = users
	}
	users[socketID] = struct{}{}
	h.socketRooms[socketID] = roomID
	currentUsers := roomUserList(users)
	h.mu.Unlock()

	client.Join(room)
	if first {
		client.Emit(EventFirstInRoom)
	} else {
		client.To(room).Emit(EventNewUser, socketID)
	}
	h.server.To(room).Emit(EventRoomUserChange, currentUsers)
}

func (h *Hub) forward(client *socket.Socket, args []any, volatile bool) {
	roomID, frame, ok := parseBroadcastArgs(args)
	if !ok {
		return
	}
	operator := client.To(socket.Room(roomID))
	if volatile {
		operator = operator.Volatile()
	}
	operator.Emit(EventClientBroadcast, frame.EncryptedBuffer, frame.IV)
}

func (h *Hub) userFollow(client *socket.Socket, args []any) {
	if len(args) < 2 {
		return
	}
	roomID, ok := asString(args[0])
	if !ok {
		return
	}
	followedSocketID, ok := asString(args[1])
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

func roomUserList(users map[string]struct{}) []RoomUser {
	list := make([]RoomUser, 0, len(users))
	for socketID := range users {
		list = append(list, RoomUser{SocketID: socketID})
	}
	return list
}
