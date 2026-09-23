package auth

import (
	"context"
	"errors"
	"net/mail"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrEmailAlreadyRegistered = errors.New("email already registered")
	ErrInvalidCredentials     = errors.New("invalid email or password")
	ErrInvalidRegistration    = errors.New("invalid registration")
	ErrEmailNotVerified       = errors.New("email not verified")
	ErrInvalidAccountToken    = errors.New("invalid account token")
	ErrIdentityAlreadyLinked  = errors.New("login method already linked")
	ErrEmailBindingPending    = errors.New("email binding not verified")
	ErrEmailRateLimited       = errors.New("email requested too recently")
)

type User struct {
	ID              string `json:"id"`
	Email           string `json:"email"`
	DisplayName     string `json:"displayName"`
	AvatarURL       string `json:"avatarUrl,omitempty"`
	RegisteredAt    int64  `json:"registeredAt"`
	EmailVerified   bool   `json:"emailVerified"`
	EmailVerifiedAt int64  `json:"emailVerifiedAt,omitempty"`
	UpdatedAt       int64  `json:"updatedAt,omitempty"`
	HuaweiLinked    bool   `json:"huaweiLinked"`
	HasPassword     bool   `json:"hasPassword"`
}

// HasVerifiedIdentity is shared by HTTP and Socket.IO authentication.
func (u User) HasVerifiedIdentity() bool {
	return u.EmailVerified || u.HuaweiLinked
}

type UserStore struct {
	db *pgxpool.Pool
}

func NewUserStore(db *pgxpool.Pool) *UserStore {
	return &UserStore{db: db}
}

func (s *UserStore) EnsureSchema(ctx context.Context) error {
	_, err := s.db.Exec(ctx, `
CREATE TABLE IF NOT EXISTS users (
	id TEXT PRIMARY KEY,
	email TEXT UNIQUE,
	password_hash TEXT,
	display_name TEXT NOT NULL,
	avatar_url TEXT NOT NULL DEFAULT '',
	email_verified_at TIMESTAMPTZ,
	registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS huawei_union_id TEXT;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS users_huawei_union_id_key
ON users (huawei_union_id) WHERE huawei_union_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS auth_sessions (
	id TEXT PRIMARY KEY,
	user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	expires_at TIMESTAMPTZ NOT NULL,
	revoked_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth_email_tokens (
	token_hash TEXT PRIMARY KEY,
	user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	purpose TEXT NOT NULL,
	expires_at TIMESTAMPTZ NOT NULL,
	used_at TIMESTAMPTZ,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS auth_email_tokens_user_purpose_idx
ON auth_email_tokens (user_id, purpose);

ALTER TABLE auth_email_tokens ADD COLUMN IF NOT EXISTS target_email TEXT;
ALTER TABLE auth_email_tokens ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
ALTER TABLE auth_email_tokens ADD COLUMN IF NOT EXISTS session_id TEXT REFERENCES auth_sessions(id) ON DELETE CASCADE;
`)
	return err
}

func (s *UserStore) Register(ctx context.Context, email, password, displayName string) (User, error) {
	normalizedEmail, err := normalizeEmail(email)
	if err != nil || !validPassword(password) {
		return User{}, ErrInvalidRegistration
	}
	displayName = cleanDisplayName(displayName)
	if displayName == "" {
		displayName = normalizedEmail
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return User{}, err
	}
	user := User{
		ID:          uuid.NewString(),
		Email:       normalizedEmail,
		DisplayName: displayName,
		HasPassword: true,
	}
	var registeredAt time.Time
	var updatedAt time.Time
	err = s.db.QueryRow(ctx, `
INSERT INTO users (id, email, password_hash, display_name)
VALUES ($1, $2, $3, $4)
RETURNING registered_at, updated_at`,
		user.ID,
		user.Email,
		string(hash),
		user.DisplayName,
	).Scan(&registeredAt, &updatedAt)
	if err != nil {
		if strings.Contains(err.Error(), "users_email_key") {
			return User{}, ErrEmailAlreadyRegistered
		}
		return User{}, err
	}
	user.RegisteredAt = registeredAt.UnixMilli()
	user.UpdatedAt = updatedAt.UnixMilli()
	return user, nil
}

func (s *UserStore) Login(ctx context.Context, email, password string) (User, error) {
	normalizedEmail, err := normalizeEmail(email)
	if err != nil {
		return User{}, ErrInvalidCredentials
	}
	user, hash, err := s.loadByEmail(ctx, normalizedEmail)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrInvalidCredentials
	}
	if err != nil {
		return User{}, err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return User{}, ErrInvalidCredentials
	}
	if !user.EmailVerified {
		return User{}, ErrEmailNotVerified
	}
	return user, nil
}

func (s *UserStore) Load(ctx context.Context, userID string) (User, error) {
	var user User
	var registeredAt time.Time
	var updatedAt time.Time
	var verifiedAt *time.Time
	err := s.db.QueryRow(ctx, `
SELECT id, COALESCE(email, ''), display_name, avatar_url, registered_at, updated_at, email_verified_at,
       huawei_union_id IS NOT NULL, password_hash IS NOT NULL
FROM users
WHERE id = $1`, userID).Scan(
		&user.ID,
		&user.Email,
		&user.DisplayName,
		&user.AvatarURL,
		&registeredAt,
		&updatedAt,
		&verifiedAt,
		&user.HuaweiLinked,
		&user.HasPassword,
	)
	if err != nil {
		return User{}, err
	}
	fillUserTimes(&user, registeredAt, updatedAt, verifiedAt)
	return user, nil
}

func (s *UserStore) LoadByEmail(ctx context.Context, email string) (User, error) {
	normalizedEmail, err := normalizeEmail(email)
	if err != nil {
		return User{}, ErrInvalidCredentials
	}
	user, _, err := s.loadByEmail(ctx, normalizedEmail)
	return user, err
}

func (s *UserStore) UpdateProfile(ctx context.Context, userID, displayName string) (User, error) {
	displayName = cleanDisplayName(displayName)
	if displayName == "" {
		return User{}, ErrInvalidRegistration
	}
	var user User
	var registeredAt time.Time
	var updatedAt time.Time
	var verifiedAt *time.Time
	err := s.db.QueryRow(ctx, `
UPDATE users
SET display_name = $2, updated_at = now()
WHERE id = $1
RETURNING id, COALESCE(email, ''), display_name, avatar_url, registered_at, updated_at, email_verified_at,
          huawei_union_id IS NOT NULL, password_hash IS NOT NULL`,
		userID,
		displayName,
	).Scan(
		&user.ID,
		&user.Email,
		&user.DisplayName,
		&user.AvatarURL,
		&registeredAt,
		&updatedAt,
		&verifiedAt,
		&user.HuaweiLinked,
		&user.HasPassword,
	)
	if err != nil {
		return User{}, err
	}
	fillUserTimes(&user, registeredAt, updatedAt, verifiedAt)
	return user, nil
}

func (s *UserStore) SetAvatarURL(ctx context.Context, userID, avatarURL string) (User, error) {
	var user User
	var registeredAt time.Time
	var updatedAt time.Time
	var verifiedAt *time.Time
	err := s.db.QueryRow(ctx, `
UPDATE users
SET avatar_url = $2, updated_at = now()
WHERE id = $1
RETURNING id, COALESCE(email, ''), display_name, avatar_url, registered_at, updated_at, email_verified_at,
          huawei_union_id IS NOT NULL, password_hash IS NOT NULL`,
		userID,
		avatarURL,
	).Scan(
		&user.ID,
		&user.Email,
		&user.DisplayName,
		&user.AvatarURL,
		&registeredAt,
		&updatedAt,
		&verifiedAt,
		&user.HuaweiLinked,
		&user.HasPassword,
	)
	if err != nil {
		return User{}, err
	}
	fillUserTimes(&user, registeredAt, updatedAt, verifiedAt)
	return user, nil
}

func (s *UserStore) ChangePassword(ctx context.Context, userID, oldPassword, newPassword string) error {
	if !validPassword(newPassword) {
		return ErrInvalidRegistration
	}
	var hash string
	err := s.db.QueryRow(ctx, `SELECT COALESCE(password_hash, '') FROM users WHERE id = $1`, userID).Scan(&hash)
	if err != nil {
		return err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(oldPassword)) != nil {
		return ErrInvalidCredentials
	}
	nextHash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	_, err = s.db.Exec(ctx, `
UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1`, userID, string(nextHash))
	return err
}

func (s *UserStore) ResetPassword(ctx context.Context, userID, newPassword string) error {
	if !validPassword(newPassword) {
		return ErrInvalidRegistration
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	_, err = s.db.Exec(ctx, `
UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1`, userID, string(hash))
	return err
}

func (s *UserStore) MarkEmailVerified(ctx context.Context, userID string) (User, error) {
	var user User
	var registeredAt time.Time
	var updatedAt time.Time
	var verifiedAt *time.Time
	err := s.db.QueryRow(ctx, `
UPDATE users
SET email_verified_at = COALESCE(email_verified_at, now()), updated_at = now()
WHERE id = $1 AND email IS NOT NULL
RETURNING id, COALESCE(email, ''), display_name, avatar_url, registered_at, updated_at, email_verified_at,
          huawei_union_id IS NOT NULL, password_hash IS NOT NULL`,
		userID,
	).Scan(
		&user.ID,
		&user.Email,
		&user.DisplayName,
		&user.AvatarURL,
		&registeredAt,
		&updatedAt,
		&verifiedAt,
		&user.HuaweiLinked,
		&user.HasPassword,
	)
	if err != nil {
		return User{}, err
	}
	fillUserTimes(&user, registeredAt, updatedAt, verifiedAt)
	return user, nil
}

func (s *UserStore) CreateSession(ctx context.Context, userID string, expiresAt time.Time) (string, error) {
	sessionID := uuid.NewString()
	_, err := s.db.Exec(ctx, `
INSERT INTO auth_sessions (id, user_id, expires_at)
VALUES ($1, $2, $3)`, sessionID, userID, expiresAt)
	return sessionID, err
}

func (s *UserStore) sessionActive(ctx context.Context, sessionID, userID string) (bool, error) {
	var exists bool
	err := s.db.QueryRow(ctx, `
SELECT EXISTS (
	SELECT 1 FROM auth_sessions
	WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL AND expires_at > now()
)`, sessionID, userID).Scan(&exists)
	return exists, err
}

func (s *UserStore) RevokeSession(ctx context.Context, sessionID, userID string) error {
	_, err := s.db.Exec(ctx, `
UPDATE auth_sessions
SET revoked_at = COALESCE(revoked_at, now())
WHERE id = $1 AND user_id = $2`, sessionID, userID)
	return err
}

func (s *UserStore) RevokeUserSessions(ctx context.Context, userID string) error {
	_, err := s.db.Exec(ctx, `
UPDATE auth_sessions
SET revoked_at = COALESCE(revoked_at, now())
WHERE user_id = $1 AND revoked_at IS NULL`, userID)
	return err
}

func (s *UserStore) CreateEmailToken(ctx context.Context, userID, purpose, tokenHash string, expiresAt time.Time) error {
	_, err := s.db.Exec(ctx, `
DELETE FROM auth_email_tokens
WHERE user_id = $1 AND purpose = $2 AND used_at IS NULL`, userID, purpose)
	if err != nil {
		return err
	}
	_, err = s.db.Exec(ctx, `
INSERT INTO auth_email_tokens (token_hash, user_id, purpose, expires_at)
VALUES ($1, $2, $3, $4)`, tokenHash, userID, purpose, expiresAt)
	return err
}

func (s *UserStore) ConsumeEmailToken(ctx context.Context, purpose, tokenHash string) (string, error) {
	var userID string
	err := s.db.QueryRow(ctx, `
UPDATE auth_email_tokens
SET used_at = now()
WHERE token_hash = $1 AND purpose = $2 AND used_at IS NULL AND expires_at > now()
RETURNING user_id`, tokenHash, purpose).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrInvalidAccountToken
	}
	return userID, err
}

func (s *UserStore) loadByEmail(ctx context.Context, email string) (User, string, error) {
	var user User
	var hash string
	var registeredAt time.Time
	var updatedAt time.Time
	var verifiedAt *time.Time
	err := s.db.QueryRow(ctx, `
SELECT id, COALESCE(email, ''), COALESCE(password_hash, ''), display_name, avatar_url, registered_at, updated_at, email_verified_at,
       huawei_union_id IS NOT NULL, password_hash IS NOT NULL
FROM users
WHERE email = $1`, email).Scan(
		&user.ID,
		&user.Email,
		&hash,
		&user.DisplayName,
		&user.AvatarURL,
		&registeredAt,
		&updatedAt,
		&verifiedAt,
		&user.HuaweiLinked,
		&user.HasPassword,
	)
	if err != nil {
		return User{}, "", err
	}
	fillUserTimes(&user, registeredAt, updatedAt, verifiedAt)
	return user, hash, nil
}

func fillUserTimes(user *User, registeredAt, updatedAt time.Time, verifiedAt *time.Time) {
	user.RegisteredAt = registeredAt.UnixMilli()
	user.UpdatedAt = updatedAt.UnixMilli()
	user.EmailVerified = verifiedAt != nil
	if verifiedAt != nil {
		user.EmailVerifiedAt = verifiedAt.UnixMilli()
	}
}

func normalizeEmail(value string) (string, error) {
	parsed, err := mail.ParseAddress(strings.TrimSpace(value))
	if err != nil {
		return "", err
	}
	if len(parsed.Address) > 254 {
		return "", ErrInvalidRegistration
	}
	return strings.ToLower(parsed.Address), nil
}

func validPassword(password string) bool {
	return len(password) >= 8 && len(password) <= 72
}

func cleanDisplayName(value string) string {
	value = strings.TrimSpace(value)
	if len([]rune(value)) > 40 {
		return string([]rune(value)[:40])
	}
	return value
}
