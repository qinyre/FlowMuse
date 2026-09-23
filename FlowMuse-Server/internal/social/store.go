package social

import (
	"context"
	"crypto/rand"
	"encoding/base32"
	"errors"
	"regexp"
	"strings"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrInvalid   = errors.New("invalid social input")
	ErrNotFound  = errors.New("social resource not found")
	ErrConflict  = errors.New("social version conflict")
	ErrForbidden = errors.New("social interaction forbidden")
	ErrLimit     = errors.New("social rate or quantity limit")
)

var safeID = regexp.MustCompile(`^[A-Za-z0-9_-]{1,128}$`)
var friendCodePattern = regexp.MustCompile(`^[A-Z2-7]{12}$`)
var roomSecretPattern = regexp.MustCompile(`(?i)(?:#room=|#room%3d|[a-z0-9_-]{20},[a-z0-9_-]{22}(?:[^a-z0-9_-]|$))`)

type Store struct{ db *pgxpool.Pool }

func NewStore(db *pgxpool.Pool) *Store { return &Store{db: db} }

func isUniqueConflict(err error) bool {
	var pgerr *pgconn.PgError
	return errors.As(err, &pgerr) && pgerr.Code == "23505"
}

func (s *Store) EnsureSchema(ctx context.Context) error {
	_, err := s.db.Exec(ctx, `
ALTER TABLE users ADD COLUMN IF NOT EXISTS friend_code TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS users_friend_code_key ON users(friend_code) WHERE friend_code IS NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS social_request_day DATE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS social_requests_today INTEGER NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS social_relationships (
 id TEXT PRIMARY KEY,
 user_low_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 user_high_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 requester_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 request_client_id TEXT NOT NULL,
 state TEXT NOT NULL CHECK (state IN ('pending','accepted','declined','cancelled','removed')),
 version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
 request_message TEXT NOT NULL DEFAULT '',
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK (user_low_id < user_high_id),
 CHECK (requester_id IN (user_low_id,user_high_id)),
 UNIQUE(user_low_id,user_high_id), UNIQUE(requester_id,request_client_id)
);
CREATE INDEX IF NOT EXISTS social_relationships_low_idx ON social_relationships(user_low_id,state,id);
CREATE INDEX IF NOT EXISTS social_relationships_high_idx ON social_relationships(user_high_id,state,id);
CREATE TABLE IF NOT EXISTS social_blocks (
 blocker_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK (blocker_id <> blocked_id), PRIMARY KEY(blocker_id,blocked_id)
);
CREATE INDEX IF NOT EXISTS social_blocks_reverse_idx ON social_blocks(blocked_id,blocker_id);
CREATE TABLE IF NOT EXISTS direct_conversations (
 id TEXT PRIMARY KEY,
 relationship_id TEXT NOT NULL UNIQUE REFERENCES social_relationships(id),
 user_low_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 user_high_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 last_seq BIGINT NOT NULL DEFAULT 0,
 low_read_seq BIGINT NOT NULL DEFAULT 0,
 high_read_seq BIGINT NOT NULL DEFAULT 0,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK (user_low_id < user_high_id),
 CHECK (low_read_seq >= 0 AND low_read_seq <= last_seq AND high_read_seq >= 0 AND high_read_seq <= last_seq),
 UNIQUE(user_low_id,user_high_id)
);
CREATE INDEX IF NOT EXISTS direct_conversations_low_idx ON direct_conversations(user_low_id,id);
CREATE INDEX IF NOT EXISTS direct_conversations_high_idx ON direct_conversations(user_high_id,id);
CREATE TABLE IF NOT EXISTS direct_messages (
 conversation_id TEXT NOT NULL REFERENCES direct_conversations(id) ON DELETE CASCADE,
 seq BIGINT NOT NULL CHECK (seq > 0),
 id TEXT NOT NULL UNIQUE,
 sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 client_message_id TEXT NOT NULL,
 kind TEXT NOT NULL DEFAULT 'text' CHECK (kind = 'text'),
 body_text TEXT NOT NULL CHECK (char_length(body_text) BETWEEN 1 AND 2000 AND octet_length(body_text) <= 8192),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(conversation_id,seq), UNIQUE(sender_id,client_message_id)
);
CREATE INDEX IF NOT EXISTS direct_messages_sender_time_idx ON direct_messages(sender_id,created_at);
`)
	return err
}

type Person struct {
	ID          string `json:"id"`
	DisplayName string `json:"displayName"`
	AvatarURL   string `json:"avatarUrl"`
	FriendCode  string `json:"friendCode"`
}

type Relationship struct {
	ID              string `json:"id"`
	Person          Person `json:"person"`
	RequesterID     string `json:"requesterId"`
	ClientRequestID string `json:"clientRequestId"`
	State           string `json:"state"`
	Version         int64  `json:"version,string"`
	RequestMessage  string `json:"requestMessage"`
	ConversationID  string `json:"conversationId"`
	UpdatedAt       int64  `json:"updatedAt"`
}

type Lookup struct {
	Person       Person        `json:"person"`
	Relationship *Relationship `json:"relationship"`
	Version      int64         `json:"version,string"`
}

type Message struct {
	ID              string `json:"id"`
	ConversationID  string `json:"conversationId"`
	Seq             int64  `json:"seq,string"`
	SenderID        string `json:"senderId"`
	ClientMessageID string `json:"clientMessageId"`
	Kind            string `json:"kind"`
	Text            string `json:"text"`
	CreatedAt       int64  `json:"createdAt"`
}

type Conversation struct {
	Cursor      string   `json:"-"`
	ID          string   `json:"id"`
	Person      Person   `json:"person"`
	CanSend     bool     `json:"canSend"`
	LastSeq     int64    `json:"lastSeq,string"`
	ReadSeq     int64    `json:"readSeq,string"`
	UnreadCount int64    `json:"unreadCount"`
	UpdatedAt   int64    `json:"updatedAt"`
	LastMessage *Message `json:"lastMessage"`
}

func normalizeCode(code string) string {
	return strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(code), "-", ""))
}

func normalizeText(text string, maxRunes, maxBytes int, allowEmpty bool) (string, error) {
	text = strings.TrimSpace(text)
	if !utf8.ValidString(text) || strings.ContainsRune(text, 0) || (!allowEmpty && text == "") || utf8.RuneCountInString(text) > maxRunes || len(text) > maxBytes || roomSecretPattern.MatchString(text) {
		return "", ErrInvalid
	}
	return text, nil
}

// Keep legacy auto-generated email display names out of public social profiles.
const personColumns = `u.id, CASE WHEN lower(u.display_name) = lower(COALESCE(u.email,'')) THEN 'FlowMuse 用户' ELSE u.display_name END, u.avatar_url, COALESCE(u.friend_code,'')`

func scanPerson(row pgx.Row) (Person, error) {
	var p Person
	err := row.Scan(&p.ID, &p.DisplayName, &p.AvatarURL, &p.FriendCode)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrNotFound
	}
	return p, err
}

func (s *Store) Me(ctx context.Context, userID string) (Person, error) {
	// Unique collisions are retried without overwriting an already assigned code.
	for i := 0; i < 4; i++ {
		var bytes [8]byte
		if _, err := rand.Read(bytes[:]); err != nil {
			return Person{}, err
		}
		code := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(bytes[:])[:12]
		_, err := s.db.Exec(ctx, `UPDATE users SET friend_code=$2 WHERE id=$1 AND friend_code IS NULL AND NOT EXISTS (SELECT 1 FROM users WHERE friend_code=$2)`, userID, code)
		if err != nil {
			if isUniqueConflict(err) {
				continue
			}
			return Person{}, err
		}
		p, err := scanPerson(s.db.QueryRow(ctx, `SELECT `+personColumns+` FROM users u WHERE u.id=$1`, userID))
		if err != nil || p.FriendCode != "" {
			return p, err
		}
	}
	return Person{}, ErrConflict
}

func lockPair(ctx context.Context, tx pgx.Tx, a, b string) (string, string, error) {
	if a == b || !safeID.MatchString(a) || !safeID.MatchString(b) {
		return "", "", ErrInvalid
	}
	if a > b {
		a, b = b, a
	}
	rows, err := tx.Query(ctx, `SELECT id FROM users WHERE id IN ($1,$2) ORDER BY id FOR UPDATE`, a, b)
	if err != nil {
		return "", "", err
	}
	defer rows.Close()
	n := 0
	for rows.Next() {
		n++
	}
	if err := rows.Err(); err != nil {
		return "", "", err
	}
	if n != 2 {
		return "", "", ErrNotFound
	}
	return a, b, nil
}

func blocked(ctx context.Context, tx pgx.Tx, a, b string) (bool, error) {
	var yes bool
	err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM social_blocks WHERE (blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1))`, a, b).Scan(&yes)
	return yes, err
}
