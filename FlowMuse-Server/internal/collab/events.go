package collab

const (
	EventInitRoom             = "init-room"
	EventJoinRoom             = "join-room"
	EventLeaveRoom            = "leave-room"
	EventEndRoom              = "end-room"
	EventRoomEnded            = "room-ended"
	EventRoomError            = "room-error"
	EventNewUser              = "new-user"
	EventFirstInRoom          = "first-in-room"
	EventRoomUserChange       = "room-user-change"
	EventServerBroadcast      = "server-broadcast"
	EventServerVolatile       = "server-volatile-broadcast"
	EventClientBroadcast      = "client-broadcast"
	EventServerLiveInk        = "server-live-ink"
	EventClientLiveInk        = "client-live-ink"
	EventLiveInkReady         = "live-ink-ready"
	EventUserFollow           = "user-follow"
	EventUserFollowRoomChange = "user-follow-room-change"
)

type EncryptedFrame struct {
	EncryptedBuffer []byte `json:"encryptedBuffer"`
	IV              []byte `json:"iv"`
}

type ReceivedLiveInkFrame struct {
	EncryptedBuffer []byte `json:"encryptedBuffer"`
	IV              []byte `json:"iv"`
	SenderSocketID  string `json:"senderSocketId"`
}

type LiveInkReady struct {
	RoomID                 string `json:"roomId"`
	LiveInkProtocolVersion int    `json:"liveInkProtocolVersion"`
}

type RoomUser struct {
	SocketID  string `json:"socketId"`
	UserID    string `json:"userId,omitempty"`
	Username  string `json:"username"`
	AvatarURL string `json:"avatarUrl,omitempty"`
	IsGuest   bool   `json:"isGuest"`
}
