package collab

const (
	EventInitRoom             = "init-room"
	EventJoinRoom             = "join-room"
	EventLeaveRoom            = "leave-room"
	EventRoomError            = "room-error"
	EventNewUser              = "new-user"
	EventFirstInRoom          = "first-in-room"
	EventRoomUserChange       = "room-user-change"
	EventServerBroadcast      = "server-broadcast"
	EventServerVolatile       = "server-volatile-broadcast"
	EventClientBroadcast      = "client-broadcast"
	EventUserFollow           = "user-follow"
	EventUserFollowRoomChange = "user-follow-room-change"
)

type EncryptedFrame struct {
	EncryptedBuffer []byte `json:"encryptedBuffer"`
	IV              []byte `json:"iv"`
}

type RoomUser struct {
	SocketID  string `json:"socketId"`
	UserID    string `json:"userId,omitempty"`
	Username  string `json:"username"`
	AvatarURL string `json:"avatarUrl,omitempty"`
	IsGuest   bool   `json:"isGuest"`
}
