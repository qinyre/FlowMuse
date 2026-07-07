package storage

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type SceneSnapshot struct {
	RoomID           string `json:"roomId"`
	SceneVersion     int64  `json:"sceneVersion"`
	SceneHash        string `json:"sceneHash"`
	BaseSceneVersion int64  `json:"baseSceneVersion"`
	BaseSceneHash    string `json:"baseSceneHash"`
	EncryptedBuffer  []byte `json:"encryptedBuffer"`
	IV               []byte `json:"iv"`
	UpdatedAt        int64  `json:"updatedAt"`
}

type SceneStore struct {
	db *pgxpool.Pool
}

func NewSceneStore(db *pgxpool.Pool) *SceneStore {
	return &SceneStore{db: db}
}

func (s *SceneStore) EnsureSchema(ctx context.Context) error {
	_, err := s.db.Exec(ctx, `
CREATE TABLE IF NOT EXISTS excalidraw_scenes (
	room_id TEXT PRIMARY KEY,
	scene_version BIGINT NOT NULL,
	scene_hash TEXT NOT NULL DEFAULT '',
	encrypted_buffer BYTEA NOT NULL,
	iv BYTEA NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
)`)
	return err
}

func (s *SceneStore) Load(ctx context.Context, roomID string) (*SceneSnapshot, error) {
	var snapshot SceneSnapshot
	var updatedAt time.Time
	err := s.db.QueryRow(ctx, `
SELECT room_id, scene_version, scene_hash, encrypted_buffer, iv, updated_at
FROM excalidraw_scenes
WHERE room_id = $1`, roomID).Scan(
		&snapshot.RoomID,
		&snapshot.SceneVersion,
		&snapshot.SceneHash,
		&snapshot.EncryptedBuffer,
		&snapshot.IV,
		&updatedAt,
	)
	if err != nil {
		return nil, err
	}
	snapshot.UpdatedAt = updatedAt.UnixMilli()
	return &snapshot, nil
}

func (s *SceneStore) Save(ctx context.Context, snapshot SceneSnapshot) error {
	tag, err := s.db.Exec(ctx, `
INSERT INTO excalidraw_scenes (room_id, scene_version, scene_hash, encrypted_buffer, iv)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (room_id) DO UPDATE SET
	scene_version = EXCLUDED.scene_version,
	scene_hash = EXCLUDED.scene_hash,
	encrypted_buffer = EXCLUDED.encrypted_buffer,
	iv = EXCLUDED.iv,
	updated_at = now()
WHERE excalidraw_scenes.scene_version = $6
	AND excalidraw_scenes.scene_hash = $7`,
		snapshot.RoomID,
		snapshot.SceneVersion,
		snapshot.SceneHash,
		snapshot.EncryptedBuffer,
		snapshot.IV,
		snapshot.BaseSceneVersion,
		snapshot.BaseSceneHash,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrStaleSceneSnapshot
	}
	return nil
}

func (s *SceneStore) Create(ctx context.Context, snapshot SceneSnapshot) error {
	tag, err := s.db.Exec(ctx, `
INSERT INTO excalidraw_scenes (room_id, scene_version, scene_hash, encrypted_buffer, iv)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (room_id) DO NOTHING`,
		snapshot.RoomID,
		snapshot.SceneVersion,
		snapshot.SceneHash,
		snapshot.EncryptedBuffer,
		snapshot.IV,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrRoomAlreadyExists
	}
	return nil
}
