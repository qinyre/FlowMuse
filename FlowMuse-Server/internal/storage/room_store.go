package storage

import (
	"context"
	"crypto/subtle"
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
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return RoomMetadata{}, err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, `
INSERT INTO collaboration_rooms (room_id, owner_id, owner_key_hash)
VALUES ($1, NULLIF($2, ''), $3)
ON CONFLICT (room_id) DO NOTHING`, roomID, ownerID, ownerKeyHash)
	if err != nil {
		return RoomMetadata{}, err
	}
	// A retry cannot claim a room or initialize another owner's key hash.
	_, err = tx.Exec(ctx, `
INSERT INTO room_members (room_id, user_id, role)
SELECT room_id, owner_id, 'owner' FROM collaboration_rooms
WHERE room_id=$1 AND owner_id IS NOT NULL
ON CONFLICT (room_id, user_id) DO NOTHING`, roomID)
	if err != nil {
		return RoomMetadata{}, err
	}
	metadata, err := scanRoom(tx.QueryRow(ctx, roomMetadataQuery, roomID, ownerID), ownerID)
	if err != nil {
		return RoomMetadata{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return RoomMetadata{}, err
	}
	return metadata, nil
}

// FindRoom distinguishes missing metadata from legacy LoadRoom's fallback.
func (s *RoomStore) FindRoom(ctx context.Context, roomID, userID string) (RoomMetadata, error) {
	return scanRoom(s.db.QueryRow(ctx, roomMetadataQuery, roomID, userID), userID)
}

func (s *RoomStore) LoadRoom(ctx context.Context, roomID string, userID string) (RoomMetadata, error) {
	metadata, err := s.FindRoom(ctx, roomID, userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return RoomMetadata{RoomID: roomID, AccessPolicy: "link_guest"}, nil
	}
	return metadata, err
}

const roomMetadataQuery = `
SELECT r.room_id, COALESCE(r.owner_id, ''), COALESCE(r.owner_key_hash, ''), r.access_policy, r.created_at,
	COALESCE(r.ended_by, ''), r.ended_at,
	CASE WHEN r.owner_id = NULLIF($2, '') THEN 'owner'
	     WHEN m.role = 'owner' THEN 'editor' ELSE COALESCE(m.role, '') END, m.joined_at
FROM collaboration_rooms r
LEFT JOIN room_members m ON m.room_id = r.room_id AND m.user_id = NULLIF($2, '')
WHERE r.room_id = $1`

func scanRoom(row pgx.Row, userID string) (RoomMetadata, error) {
	var metadata RoomMetadata
	var createdAt time.Time
	var endedAt, joinedAt *time.Time
	err := row.Scan(
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

func (s *RoomStore) UpsertMember(ctx context.Context, roomID, userID, _ string) error {
	if roomID == "" || userID == "" {
		return nil
	}
	_, err := s.db.Exec(ctx, `
INSERT INTO room_members (room_id, user_id, role)
SELECT room_id, $2, CASE WHEN owner_id = $2 THEN 'owner' ELSE 'editor' END
FROM collaboration_rooms WHERE room_id = $1
ON CONFLICT (room_id, user_id) DO UPDATE SET
	joined_at = now()`, roomID, userID)
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
	ownsByKey := ownerKeyHashesEqual(metadata.OwnerKeyHash, ownerKeyHash)
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

func ownerKeyHashesEqual(expected, supplied string) bool {
	if expected == "" || supplied == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(expected), []byte(supplied)) == 1
}
