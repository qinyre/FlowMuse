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
)

type User struct {
	ID           string `json:"id"`
	Email        string `json:"email"`
	DisplayName  string `json:"displayName"`
	AvatarURL    string `json:"avatarUrl,omitempty"`
	RegisteredAt int64  `json:"registeredAt"`
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
	email TEXT NOT NULL UNIQUE,
	password_hash TEXT NOT NULL,
	display_name TEXT NOT NULL,
	avatar_url TEXT NOT NULL DEFAULT '',
	registered_at TIMESTAMPTZ NOT NULL DEFAULT now()
)`)
	return err
}

func (s *UserStore) Register(ctx context.Context, email, password, displayName string) (User, error) {
	normalizedEmail, err := normalizeEmail(email)
	if err != nil || len(password) < 8 {
		return User{}, ErrInvalidRegistration
	}
	displayName = strings.TrimSpace(displayName)
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
	}
	var registeredAt time.Time
	err = s.db.QueryRow(ctx, `
INSERT INTO users (id, email, password_hash, display_name)
VALUES ($1, $2, $3, $4)
RETURNING registered_at`,
		user.ID,
		user.Email,
		string(hash),
		user.DisplayName,
	).Scan(&registeredAt)
	if err != nil {
		if strings.Contains(err.Error(), "users_email_key") {
			return User{}, ErrEmailAlreadyRegistered
		}
		return User{}, err
	}
	user.RegisteredAt = registeredAt.UnixMilli()
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
	return user, nil
}

func (s *UserStore) Load(ctx context.Context, userID string) (User, error) {
	var user User
	var registeredAt time.Time
	err := s.db.QueryRow(ctx, `
SELECT id, email, display_name, avatar_url, registered_at
FROM users
WHERE id = $1`, userID).Scan(
		&user.ID,
		&user.Email,
		&user.DisplayName,
		&user.AvatarURL,
		&registeredAt,
	)
	if err != nil {
		return User{}, err
	}
	user.RegisteredAt = registeredAt.UnixMilli()
	return user, nil
}

func (s *UserStore) loadByEmail(ctx context.Context, email string) (User, string, error) {
	var user User
	var hash string
	var registeredAt time.Time
	err := s.db.QueryRow(ctx, `
SELECT id, email, password_hash, display_name, avatar_url, registered_at
FROM users
WHERE email = $1`, email).Scan(
		&user.ID,
		&user.Email,
		&hash,
		&user.DisplayName,
		&user.AvatarURL,
		&registeredAt,
	)
	if err != nil {
		return User{}, "", err
	}
	user.RegisteredAt = registeredAt.UnixMilli()
	return user, hash, nil
}

func normalizeEmail(value string) (string, error) {
	parsed, err := mail.ParseAddress(strings.TrimSpace(value))
	if err != nil {
		return "", err
	}
	return strings.ToLower(parsed.Address), nil
}
