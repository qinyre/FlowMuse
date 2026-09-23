package social

import (
	"context"
	"crypto/ecdh"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"github.com/jackc/pgx/v5"
	"strings"
	"time"
	"unicode/utf8"
)

func (s *Store) ensureInvitationSchema(ctx context.Context) error {
	_, err := s.db.Exec(ctx, `
ALTER TABLE users ADD COLUMN IF NOT EXISTS social_keyset_version BIGINT NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS social_devices (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 key_id TEXT NOT NULL, public_key TEXT NOT NULL, key_fingerprint TEXT NOT NULL,
 platform_label TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), revoked_at TIMESTAMPTZ,
 UNIQUE(user_id,key_id), UNIQUE(id,user_id,key_id)
);
CREATE INDEX IF NOT EXISTS social_devices_user_idx ON social_devices(user_id,created_at);
ALTER TABLE room_invites ADD COLUMN IF NOT EXISTS recipient_id TEXT REFERENCES users(id);
ALTER TABLE room_invites ADD COLUMN IF NOT EXISTS conversation_id TEXT REFERENCES direct_conversations(id);
ALTER TABLE room_invites ADD COLUMN IF NOT EXISTS client_invite_id TEXT;
ALTER TABLE room_invites ADD COLUMN IF NOT EXISTS status TEXT;
ALTER TABLE room_invites ADD COLUMN IF NOT EXISTS version BIGINT NOT NULL DEFAULT 1;
ALTER TABLE room_invites ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;
ALTER TABLE room_invites ADD COLUMN IF NOT EXISTS joined_at TIMESTAMPTZ;
ALTER TABLE room_invites ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;
ALTER TABLE room_invites ADD COLUMN IF NOT EXISTS request_hash TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS room_invites_client_idx ON room_invites(created_by,client_invite_id) WHERE client_invite_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS room_invites_recipient_idx ON room_invites(recipient_id,id);
CREATE INDEX IF NOT EXISTS room_invites_sender_time_idx ON room_invites(created_by,room_id,recipient_id,created_at);
ALTER TABLE room_invites DROP CONSTRAINT IF EXISTS room_invites_social_check;
ALTER TABLE room_invites ADD CONSTRAINT room_invites_social_check CHECK(recipient_id IS NULL OR
 (created_by IS NOT NULL AND created_by<>recipient_id AND conversation_id IS NOT NULL AND
 client_invite_id IS NOT NULL AND request_hash IS NOT NULL AND expires_at IS NOT NULL AND version>0 AND
 status IS NOT NULL AND status IN('pending','accepted','declined','revoked')));
CREATE TABLE IF NOT EXISTS room_invite_envelopes (
 invite_id TEXT NOT NULL REFERENCES room_invites(id) ON DELETE CASCADE,
 recipient_user_id TEXT NOT NULL REFERENCES users(id), device_id TEXT NOT NULL, key_id TEXT NOT NULL,
 sender_user_id TEXT NOT NULL REFERENCES users(id), sender_device_id TEXT NOT NULL, sender_key_id TEXT NOT NULL,
 suite TEXT NOT NULL, enc TEXT NOT NULL, ciphertext TEXT NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(invite_id,device_id,key_id),
 FOREIGN KEY(device_id,recipient_user_id,key_id) REFERENCES social_devices(id,user_id,key_id),
 FOREIGN KEY(sender_device_id,sender_user_id,sender_key_id) REFERENCES social_devices(id,user_id,key_id)
);
ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS invite_id TEXT REFERENCES room_invites(id);
ALTER TABLE direct_messages ALTER COLUMN body_text DROP NOT NULL;
ALTER TABLE direct_messages DROP CONSTRAINT IF EXISTS direct_messages_kind_check;
ALTER TABLE direct_messages DROP CONSTRAINT IF EXISTS direct_messages_body_text_check;
ALTER TABLE direct_messages DROP CONSTRAINT IF EXISTS direct_messages_content_check;
ALTER TABLE direct_messages ADD CONSTRAINT direct_messages_content_check CHECK(
 (kind='text' AND invite_id IS NULL AND body_text IS NOT NULL AND char_length(body_text) BETWEEN 1 AND 2000 AND octet_length(body_text)<=8192) OR
 (kind='invitation' AND invite_id IS NOT NULL AND body_text IS NULL));
CREATE UNIQUE INDEX IF NOT EXISTS direct_messages_invite_idx ON direct_messages(invite_id) WHERE invite_id IS NOT NULL;
`)
	return err
}

type Device struct {
	ID          string `json:"id"`
	UserID      string `json:"userId"`
	KeyID       string `json:"keyId"`
	PublicKey   string `json:"publicKey"`
	Fingerprint string `json:"fingerprint"`
	Label       string `json:"label"`
	RevokedAt   int64  `json:"revokedAt"`
}
type DeviceSet struct {
	Items   []Device `json:"items"`
	Version int64    `json:"keysetVersion,string"`
}

const deviceColumns = `id,user_id,key_id,public_key,key_fingerprint,platform_label,revoked_at`

func scanDevice(row pgx.Row) (Device, error) {
	var d Device
	var revoked *time.Time
	err := row.Scan(&d.ID, &d.UserID, &d.KeyID, &d.PublicKey, &d.Fingerprint, &d.Label, &revoked)
	if revoked != nil {
		d.RevokedAt = revoked.UnixMilli()
	}
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrNotFound
	}
	return d, err
}

func validPublicKey(encoded string) ([]byte, error) {
	data, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil || len(data) != 32 || base64.RawURLEncoding.EncodeToString(data) != encoded || data[31]&128 != 0 {
		return nil, ErrInvalid
	}
	// Reject small-order points using the standard library's all-zero DH check.
	seed := make([]byte, 32)
	seed[0] = 9
	sk, err := ecdh.X25519().NewPrivateKey(seed)
	if err != nil {
		return nil, err
	}
	pk, err := ecdh.X25519().NewPublicKey(data)
	if err != nil {
		return nil, ErrInvalid
	}
	if _, err = sk.ECDH(pk); err != nil {
		return nil, ErrInvalid
	}
	return data, nil
}

func (s *Store) RegisterDevice(ctx context.Context, user string, d Device) (Device, error) {
	key, err := validPublicKey(d.PublicKey)
	d.Label = strings.TrimSpace(d.Label)
	if err != nil || !safeID.MatchString(d.ID) || !safeID.MatchString(d.KeyID) ||
		len(d.Label) == 0 || utf8.RuneCountInString(d.Label) > 40 || strings.ContainsRune(d.Label, 0) {
		return Device{}, ErrInvalid
	}
	sum := sha256.Sum256(key)
	d.Fingerprint = hex.EncodeToString(sum[:])
	d.UserID = user
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Device{}, err
	}
	defer tx.Rollback(ctx)
	var version int64
	if err = tx.QueryRow(ctx, `SELECT social_keyset_version FROM users WHERE id=$1 FOR NO KEY UPDATE`, user).Scan(&version); err != nil {
		return Device{}, err
	}
	old, err := scanDevice(tx.QueryRow(ctx, `SELECT `+deviceColumns+` FROM social_devices WHERE id=$1 OR (user_id=$2 AND key_id=$3) LIMIT 1`, d.ID, user, d.KeyID))
	if err == nil {
		if old.ID != d.ID || old.UserID != user || old.KeyID != d.KeyID || old.PublicKey != d.PublicKey || old.RevokedAt != 0 {
			return Device{}, ErrConflict
		}
		return old, nil
	}
	if !errors.Is(err, ErrNotFound) {
		return Device{}, err
	}
	var active, daily int
	if err = tx.QueryRow(ctx, `SELECT count(*) FILTER(WHERE revoked_at IS NULL),count(*) FILTER(WHERE created_at>now()-interval '1 day') FROM social_devices WHERE user_id=$1`, user).Scan(&active, &daily); err != nil {
		return Device{}, err
	}
	if active >= 5 || daily >= 20 {
		return Device{}, ErrLimit
	}
	_, err = tx.Exec(ctx, `INSERT INTO social_devices(id,user_id,key_id,public_key,key_fingerprint,platform_label) VALUES($1,$2,$3,$4,$5,$6)`, d.ID, user, d.KeyID, d.PublicKey, d.Fingerprint, d.Label)
	if isUniqueConflict(err) {
		return Device{}, ErrConflict
	}
	if err != nil {
		return Device{}, err
	}
	if _, err = tx.Exec(ctx, `UPDATE users SET social_keyset_version=social_keyset_version+1 WHERE id=$1`, user); err != nil {
		return Device{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return Device{}, err
	}
	return d, nil
}

func requireFriends(ctx context.Context, tx pgx.Tx, a, b string) (string, error) {
	low, high := a, b
	if low > high {
		low, high = high, low
	}
	var id, state string
	err := tx.QueryRow(ctx, `SELECT id,state FROM social_relationships WHERE user_low_id=$1 AND user_high_id=$2 FOR UPDATE`, low, high).Scan(&id, &state)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrForbidden
	}
	if err != nil {
		return "", err
	}
	if state != "accepted" {
		return "", ErrForbidden
	}
	yes, err := blocked(ctx, tx, a, b)
	if err != nil {
		return "", err
	}
	if yes {
		return "", ErrForbidden
	}
	return id, nil
}

func (s *Store) Devices(ctx context.Context, user, target string) (DeviceSet, error) {
	if !safeID.MatchString(target) {
		return DeviceSet{}, ErrInvalid
	}
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead})
	if err != nil {
		return DeviceSet{}, err
	}
	defer tx.Rollback(ctx)
	if user != target {
		if _, err = requireFriends(ctx, tx, user, target); err != nil {
			return DeviceSet{}, err
		}
	}
	result := DeviceSet{Items: []Device{}}
	if err = tx.QueryRow(ctx, `SELECT social_keyset_version FROM users WHERE id=$1`, target).Scan(&result.Version); err != nil {
		return result, err
	}
	rows, err := tx.Query(ctx, `SELECT `+deviceColumns+` FROM social_devices WHERE user_id=$1 AND ($2 OR revoked_at IS NULL) ORDER BY created_at DESC LIMIT 100`, target, user == target)
	if err != nil {
		return result, err
	}
	defer rows.Close()
	for rows.Next() {
		d, err := scanDevice(rows)
		if err != nil {
			return result, err
		}
		result.Items = append(result.Items, d)
	}
	return result, rows.Err()
}

func (s *Store) RevokeDevice(ctx context.Context, user, id string) error {
	if !safeID.MatchString(id) {
		return ErrInvalid
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var version int64
	if err = tx.QueryRow(ctx, `SELECT social_keyset_version FROM users WHERE id=$1 FOR NO KEY UPDATE`, user).Scan(&version); err != nil {
		return err
	}
	var revoked *time.Time
	if err = tx.QueryRow(ctx, `SELECT revoked_at FROM social_devices WHERE id=$1 AND user_id=$2`, id, user).Scan(&revoked); errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	} else if err != nil {
		return err
	}
	if revoked == nil {
		if _, err = tx.Exec(ctx, `UPDATE social_devices SET revoked_at=now() WHERE id=$1`, id); err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, `UPDATE users SET social_keyset_version=social_keyset_version+1 WHERE id=$1`, user); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
