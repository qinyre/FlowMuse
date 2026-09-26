package auth

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"golang.org/x/crypto/bcrypt"
)

const emailPurposeBind = "bind_email"

// LoginHuawei accepts only the UnionID already verified by HuaweiClient.
func (s *UserStore) LoginHuawei(ctx context.Context, unionID string) (User, error) {
	if unionID == "" || len(unionID) > 256 {
		return User{}, ErrInvalidCredentials
	}
	var userID string
	err := s.db.QueryRow(ctx, `
INSERT INTO users (id, huawei_union_id, display_name)
VALUES ($1, $2, '华为用户')
ON CONFLICT (huawei_union_id) WHERE huawei_union_id IS NOT NULL
DO UPDATE SET huawei_union_id = EXCLUDED.huawei_union_id
RETURNING id`, uuid.NewString(), unionID).Scan(&userID)
	if err != nil {
		return User{}, err
	}
	return s.Load(ctx, userID)
}

// FillHuaweiProfile replaces the placeholder name and Huawei-hosted avatar.
// FlowMuse profile edits and uploaded avatars take precedence on later logins.
func (s *UserStore) FillHuaweiProfile(ctx context.Context, userID, displayName, avatarURL string) (User, error) {
	_, err := s.db.Exec(ctx, `
UPDATE users SET
  display_name = CASE WHEN display_name = '华为用户' AND $2 <> '' THEN $2 ELSE display_name END,
  avatar_url = CASE WHEN (avatar_url = '' OR avatar_url LIKE 'https://%') AND $3 <> '' THEN $3 ELSE avatar_url END,
  updated_at = now()
WHERE id = $1 AND ((display_name = '华为用户' AND $2 <> '') OR ((avatar_url = '' OR avatar_url LIKE 'https://%') AND $3 <> ''))`,
		userID, displayName, avatarURL)
	if err != nil {
		return User{}, err
	}
	return s.Load(ctx, userID)
}

// lockLinkAccount serializes binding changes and session revocation. Email
// proof alone must never grant a session or move an existing account.
func lockLinkAccount(ctx context.Context, tx pgx.Tx, userID, sessionID string) (email, unionID string, err error) {
	err = tx.QueryRow(ctx, `
SELECT COALESCE(u.email, ''), COALESCE(u.huawei_union_id, '')
FROM users u JOIN auth_sessions s ON s.user_id = u.id
WHERE u.id = $1 AND s.id = $2 AND s.revoked_at IS NULL AND s.expires_at > now()
  AND (u.email_verified_at IS NOT NULL OR u.huawei_union_id IS NOT NULL)
FOR UPDATE OF u, s`, userID, sessionID).Scan(&email, &unionID)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrInvalidCredentials
	}
	return
}

func (s *UserStore) BindHuawei(ctx context.Context, userID, sessionID, unionID string) (User, error) {
	if unionID == "" || len(unionID) > 256 {
		return User{}, ErrInvalidCredentials
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return User{}, err
	}
	defer tx.Rollback(ctx)
	_, existing, err := lockLinkAccount(ctx, tx, userID, sessionID)
	if err != nil {
		return User{}, err
	}
	if existing != "" && existing != unionID {
		return User{}, ErrIdentityAlreadyLinked
	}
	if _, err = tx.Exec(ctx, `UPDATE users SET huawei_union_id = $2, updated_at = now() WHERE id = $1`, userID, unionID); err != nil {
		if isUniqueViolation(err) {
			return User{}, ErrIdentityAlreadyLinked
		}
		return User{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return User{}, err
	}
	return s.Load(ctx, userID)
}

func (s *UserStore) CreateEmailBinding(ctx context.Context, userID, sessionID, email, tokenHash string, expiresAt time.Time) (string, error) {
	email, err := normalizeEmail(email)
	if err != nil {
		return "", ErrInvalidRegistration
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)
	existing, _, err := lockLinkAccount(ctx, tx, userID, sessionID)
	if err != nil {
		return "", err
	}
	if existing != "" {
		return "", ErrIdentityAlreadyLinked
	}
	var used, recent bool
	if err = tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM users WHERE email = $1)`, email).Scan(&used); err != nil {
		return "", err
	}
	if used {
		return "", ErrEmailAlreadyRegistered
	}
	if err = tx.QueryRow(ctx, `
SELECT EXISTS (SELECT 1 FROM auth_email_tokens
WHERE user_id = $1 AND purpose = $2 AND created_at > now() - interval '60 seconds')`, userID, emailPurposeBind).Scan(&recent); err != nil {
		return "", err
	}
	if recent {
		return "", ErrEmailRateLimited
	}
	if _, err = tx.Exec(ctx, `DELETE FROM auth_email_tokens WHERE user_id = $1 AND purpose = $2`, userID, emailPurposeBind); err != nil {
		return "", err
	}
	if _, err = tx.Exec(ctx, `
INSERT INTO auth_email_tokens (token_hash, user_id, purpose, expires_at, target_email, session_id)
VALUES ($1, $2, $3, $4, $5, $6)`, tokenHash, userID, emailPurposeBind, expiresAt, email, sessionID); err != nil {
		return "", err
	}
	return email, tx.Commit(ctx)
}

func (s *UserStore) VerifyEmailBinding(ctx context.Context, tokenHash string) error {
	result, err := s.db.Exec(ctx, `
UPDATE auth_email_tokens t SET verified_at = now()
WHERE t.token_hash = $1 AND t.purpose = $2 AND t.used_at IS NULL
  AND t.verified_at IS NULL AND t.expires_at > now() AND t.target_email IS NOT NULL
  AND EXISTS (SELECT 1 FROM auth_sessions s WHERE s.id = t.session_id
              AND s.user_id = t.user_id AND s.revoked_at IS NULL AND s.expires_at > now())`, tokenHash, emailPurposeBind)
	if err != nil {
		return err
	}
	if result.RowsAffected() != 1 {
		return ErrInvalidAccountToken
	}
	return nil
}

func (s *UserStore) CompleteEmailBinding(ctx context.Context, userID, sessionID, requestID, password string) (User, error) {
	if !validPassword(password) {
		return User{}, ErrInvalidRegistration
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return User{}, err
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return User{}, err
	}
	defer tx.Rollback(ctx)
	existing, _, err := lockLinkAccount(ctx, tx, userID, sessionID)
	if err != nil {
		return User{}, err
	}
	if existing != "" {
		return User{}, ErrIdentityAlreadyLinked
	}
	var email string
	var verified bool
	err = tx.QueryRow(ctx, `
SELECT target_email, verified_at IS NOT NULL FROM auth_email_tokens
WHERE token_hash = $1 AND user_id = $2 AND session_id = $3 AND purpose = $4
  AND used_at IS NULL AND expires_at > now()
FOR UPDATE`, requestID, userID, sessionID, emailPurposeBind).Scan(&email, &verified)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrInvalidAccountToken
	}
	if err != nil {
		return User{}, err
	}
	if !verified {
		return User{}, ErrEmailBindingPending
	}
	if _, err = tx.Exec(ctx, `
UPDATE users SET email = $2, password_hash = $3, email_verified_at = now(), updated_at = now()
WHERE id = $1`, userID, email, string(hash)); err != nil {
		if isUniqueViolation(err) {
			return User{}, ErrEmailAlreadyRegistered
		}
		return User{}, err
	}
	if _, err = tx.Exec(ctx, `UPDATE auth_email_tokens SET used_at = now() WHERE token_hash = $1`, requestID); err != nil {
		return User{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return User{}, err
	}
	return s.Load(ctx, userID)
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
