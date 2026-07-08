package storage

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrRoomAccessDenied = errors.New("room access denied")
var ErrRoomEnded = errors.New("room ended")

type RoomMetadata struct {
	RoomID        string `json:"roomId"`
	OwnerID       string `json:"ownerId,omitempty"`
	OwnerKeyHash  string `json:"-"`
	AccessPolicy  string `json:"accessPolicy"`
	CreatedAt     int64  `json:"createdAt"`
	EndedAt       int64  `json:"endedAt,omitempty"`
	EndedBy       string `json:"endedBy,omitempty"`
	LastJoinedAt  int64  `json:"lastJoinedAt,omitempty"`
	MemberRole    string `json:"memberRole,omitempty"`
	Authenticated bool   `json:"authenticated"`
	Ended         bool   `json:"ended"`
}

type RoomStore struct {
	db *pgxpool.Pool
}

func NewRoomStore(db *pgxpool.Pool) *RoomStore {
	return &RoomStore{db: db}
}

func (s *RoomStore) EnsureSchema(ctx context.Context) error {
	_, err := s.db.Exec(ctx, `
CREATE TABLE IF NOT EXISTS collaboration_rooms (
	room_id TEXT PRIMARY KEY,
	owner_id TEXT REFERENCES users(id) ON DELETE SET NULL,
	owner_key_hash TEXT NOT NULL DEFAULT '',
	access_policy TEXT NOT NULL DEFAULT 'link_guest',
	ended_at TIMESTAMPTZ,
	ended_by TEXT REFERENCES users(id) ON DELETE SET NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS room_members (
	room_id TEXT NOT NULL REFERENCES collaboration_rooms(room_id) ON DELETE CASCADE,
	user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	role TEXT NOT NULL DEFAULT 'editor',
	joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	PRIMARY KEY (room_id, user_id)
);

CREATE TABLE IF NOT EXISTS room_invites (
	id TEXT PRIMARY KEY,
	room_id TEXT NOT NULL REFERENCES collaboration_rooms(room_id) ON DELETE CASCADE,
	created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
	role TEXT NOT NULL DEFAULT 'editor',
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	expires_at TIMESTAMPTZ
)`)
	return err
}

func (s *RoomStore) CreateRoom(ctx context.Context, roomID string, ownerID string, ownerKeyHash string) (RoomMetadata, error) {
	var createdAt time.Time
	err := s.db.QueryRow(ctx, `
INSERT INTO collaboration_rooms (room_id, owner_id, owner_key_hash)
VALUES ($1, NULLIF($2, ''), $3)
ON CONFLICT (room_id) DO UPDATE SET
	owner_key_hash = CASE
		WHEN collaboration_rooms.owner_key_hash = '' THEN EXCLUDED.owner_key_hash
		ELSE collaboration_rooms.owner_key_hash
	END
RETURNING created_at`, roomID, ownerID, ownerKeyHash).Scan(&createdAt)
	if err != nil {
		return RoomMetadata{}, err
	}
	if ownerID != "" {
		if err := s.UpsertMember(ctx, roomID, ownerID, "owner"); err != nil {
			return RoomMetadata{}, err
		}
	}
	return RoomMetadata{
		RoomID:        roomID,
		OwnerID:       ownerID,
		OwnerKeyHash:  ownerKeyHash,
		AccessPolicy:  "link_guest",
		CreatedAt:     createdAt.UnixMilli(),
		MemberRole:    roleForOwner(ownerID),
		Authenticated: ownerID != "",
	}, nil
}

func (s *RoomStore) LoadRoom(ctx context.Context, roomID string, userID string) (RoomMetadata, error) {
	var metadata RoomMetadata
	var createdAt time.Time
	var endedAt *time.Time
	var joinedAt *time.Time
	err := s.db.QueryRow(ctx, `
SELECT r.room_id, COALESCE(r.owner_id, ''), COALESCE(r.owner_key_hash, ''), r.access_policy, r.created_at,
	COALESCE(r.ended_by, ''), r.ended_at,
	COALESCE(m.role, ''), m.joined_at
FROM collaboration_rooms r
LEFT JOIN room_members m ON m.room_id = r.room_id AND m.user_id = NULLIF($2, '')
WHERE r.room_id = $1`, roomID, userID).Scan(
		&metadata.RoomID,
		&metadata.OwnerID,
		&metadata.OwnerKeyHash,
		&metadata.AccessPolicy,
		&createdAt,
		&metadata.EndedBy,
		&endedAt,
		&metadata.MemberRole,
		&joinedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return RoomMetadata{RoomID: roomID, AccessPolicy: "link_guest"}, nil
	}
	if err != nil {
		return RoomMetadata{}, err
	}
	metadata.CreatedAt = createdAt.UnixMilli()
	if endedAt != nil {
		metadata.Ended = true
		metadata.EndedAt = endedAt.UnixMilli()
	}
	metadata.Authenticated = userID != ""
	if joinedAt != nil {
		metadata.LastJoinedAt = joinedAt.UnixMilli()
	}
	if metadata.MemberRole == "" && metadata.OwnerID != "" && metadata.OwnerID == userID {
		metadata.MemberRole = "owner"
	}
	return metadata, nil
}

func (s *RoomStore) UpsertMember(ctx context.Context, roomID, userID, role string) error {
	if roomID == "" || userID == "" {
		return nil
	}
	_, err := s.db.Exec(ctx, `
INSERT INTO room_members (room_id, user_id, role)
VALUES ($1, $2, $3)
ON CONFLICT (room_id, user_id) DO UPDATE SET
	role = room_members.role,
	joined_at = now()`, roomID, userID, role)
	return err
}

func (s *RoomStore) EndRoom(ctx context.Context, roomID, userID, ownerKeyHash string) (RoomMetadata, error) {
	metadata, err := s.LoadRoom(ctx, roomID, userID)
	if err != nil {
		return RoomMetadata{}, err
	}
	if metadata.Ended {
		return metadata, nil
	}
	ownsByAccount := userID != "" && metadata.OwnerID != "" && metadata.OwnerID == userID
	ownsByKey := ownerKeyHash != "" &&
		metadata.OwnerKeyHash != "" &&
		metadata.OwnerKeyHash == ownerKeyHash
	if !ownsByAccount && !ownsByKey {
		return RoomMetadata{}, ErrRoomAccessDenied
	}
	var endedAt time.Time
	err = s.db.QueryRow(ctx, `
UPDATE collaboration_rooms
SET ended_at = now(), ended_by = NULLIF($2, '')
WHERE room_id = $1
RETURNING ended_at`, roomID, userID).Scan(&endedAt)
	if err != nil {
		return RoomMetadata{}, err
	}
	metadata.Ended = true
	metadata.EndedAt = endedAt.UnixMilli()
	metadata.EndedBy = userID
	return metadata, nil
}

func roleForOwner(ownerID string) string {
	if ownerID == "" {
		return ""
	}
	return "owner"
}
