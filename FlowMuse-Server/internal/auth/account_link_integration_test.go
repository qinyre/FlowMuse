package auth

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Opt-in tests require a disposable database, never DATABASE_URL or production.
func isolatedAuthStore(t *testing.T, legacy bool) *UserStore {
	t.Helper()
	dsn := os.Getenv("FLOWMUSE_AUTH_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set FLOWMUSE_AUTH_TEST_DATABASE_URL to a disposable *_test database")
	}
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal("invalid test database URL")
	}
	if !strings.HasSuffix(cfg.ConnConfig.Database, "_test") {
		t.Fatal("test database name must end in _test")
	}
	schema := "auth_test_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	cfg.ConnConfig.RuntimeParams["search_path"] = schema
	db, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, err := db.Exec(context.Background(), "DROP SCHEMA "+pgx.Identifier{schema}.Sanitize()+" CASCADE")
		if err != nil {
			t.Error(err)
		}
		db.Close()
	})
	if _, err := db.Exec(context.Background(), "CREATE SCHEMA "+pgx.Identifier{schema}.Sanitize()); err != nil {
		t.Fatal(err)
	}
	s := NewUserStore(db)
	if legacy {
		_, err := db.Exec(context.Background(), `
   CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL, avatar_url TEXT NOT NULL DEFAULT '', email_verified_at TIMESTAMPTZ,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
   CREATE TABLE auth_sessions (id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
   CREATE TABLE auth_email_tokens (token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    purpose TEXT NOT NULL, expires_at TIMESTAMPTZ NOT NULL, used_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());`)
		if err != nil {
			t.Fatal(err)
		}
		// Register on the old schema before migration, retaining a real password hash.
		if _, err := s.Register(context.Background(), "legacy@example.test", "test-password", "Legacy"); err != nil {
			t.Fatal(err)
		}
	}
	for i := 0; i < 2; i++ {
		if err := s.EnsureSchema(context.Background()); err != nil {
			t.Fatal(err)
		}
	}
	return s
}

func TestAccountMigrationAndBindings(t *testing.T) {
	for _, legacy := range []bool{false, true} {
		name := "fresh"
		if legacy {
			name = "upgrade"
		}
		t.Run(name, func(t *testing.T) {
			s := isolatedAuthStore(t, legacy)
			ctx := context.Background()
			if legacy {
				u, _, err := s.loadByEmail(ctx, "legacy@example.test")
				if err != nil {
					t.Fatal(err)
				}
				if _, err := s.MarkEmailVerified(ctx, u.ID); err != nil {
					t.Fatal(err)
				}
				if _, err := s.Login(ctx, "legacy@example.test", "test-password"); err != nil {
					t.Fatal("old login broken", err)
				}
			}
			owner, err := s.LoginHuawei(ctx, "huawei-one")
			if err != nil {
				t.Fatal(err)
			}
			if owner.Email != "" || owner.EmailVerified || owner.HasPassword || !owner.HuaweiLinked {
				t.Fatal("incorrect Huawei-only flags")
			}
			var wg sync.WaitGroup
			for i := 0; i < 4; i++ {
				wg.Add(1)
				go func() {
					defer wg.Done()
					u, e := s.LoginHuawei(ctx, "huawei-one")
					if e != nil || u.ID != owner.ID {
						t.Error("concurrent login changed identity", e)
					}
				}()
			}
			wg.Wait()
			sid, err := s.CreateSession(ctx, owner.ID, time.Now().Add(time.Hour))
			if err != nil {
				t.Fatal(err)
			}
			sid2, err := s.CreateSession(ctx, owner.ID, time.Now().Add(time.Hour))
			if err != nil {
				t.Fatal(err)
			}
			other, err := s.LoginHuawei(ctx, "huawei-two")
			if err != nil {
				t.Fatal(err)
			}
			otherSID, err := s.CreateSession(ctx, other.ID, time.Now().Add(time.Hour))
			if err != nil {
				t.Fatal(err)
			}
			if _, err := s.UpdateProfile(ctx, owner.ID, "Harmony User"); err != nil {
				t.Fatal(err)
			}
			if _, err := s.SetAvatarURL(ctx, owner.ID, "/test/avatar"); err != nil {
				t.Fatal(err)
			}
			if err := s.ChangePassword(ctx, owner.ID, "test-password", "new-password"); !errors.Is(err, ErrInvalidCredentials) {
				t.Fatal("Huawei-only password change accepted")
			}
			proof, _ := randomToken()
			requestID := hashToken(proof)
			if _, err := s.CreateEmailBinding(ctx, owner.ID, sid, "Test@Example.test", requestID, time.Now().Add(time.Minute)); err != nil {
				t.Fatal(err)
			}
			if _, err := s.CreateEmailBinding(ctx, owner.ID, sid, "test@example.test", "retry", time.Now().Add(time.Minute)); !errors.Is(err, ErrEmailRateLimited) {
				t.Fatal("mail cooldown missing", err)
			}
			if _, err := s.CompleteEmailBinding(ctx, owner.ID, sid, requestID, "test-password"); !errors.Is(err, ErrEmailBindingPending) {
				t.Fatal("unverified binding accepted", err)
			}
			if err := s.VerifyEmailBinding(ctx, requestID); err != nil {
				t.Fatal(err)
			}
			unchanged, _ := s.Load(ctx, owner.ID)
			if unchanged.Email != "" {
				t.Fatal("email proof changed account")
			}
			if _, err := s.CompleteEmailBinding(ctx, owner.ID, sid2, requestID, "test-password"); !errors.Is(err, ErrInvalidAccountToken) {
				t.Fatal("other session accepted", err)
			}
			if _, err := s.CompleteEmailBinding(ctx, other.ID, otherSID, requestID, "test-password"); !errors.Is(err, ErrInvalidAccountToken) {
				t.Fatal("other account accepted", err)
			}
			outcomes := make(chan error, 2)
			for i := 0; i < 2; i++ {
				go func() { _, e := s.CompleteEmailBinding(ctx, owner.ID, sid, requestID, "test-password"); outcomes <- e }()
			}
			successes := 0
			for i := 0; i < 2; i++ {
				if <-outcomes == nil {
					successes++
				}
			}
			if successes != 1 {
				t.Fatal("concurrent binding not single-use")
			}
			linked, err := s.Login(ctx, "test@example.test", "test-password")
			if err != nil {
				t.Fatal(err)
			}
			if linked.ID != owner.ID || !linked.HasPassword || !linked.EmailVerified || !linked.HuaweiLinked {
				t.Fatal("email login changed account")
			}
			again, err := s.LoginHuawei(ctx, "huawei-one")
			if err != nil || again.ID != owner.ID {
				t.Fatal("Huawei login changed account", err)
			}
			if err := s.VerifyEmailBinding(ctx, requestID); !errors.Is(err, ErrInvalidAccountToken) {
				t.Fatal("replayed verification accepted", err)
			}
			if _, err := s.CreateEmailBinding(ctx, other.ID, otherSID, "test@example.test", "occupied", time.Now().Add(time.Minute)); !errors.Is(err, ErrEmailAlreadyRegistered) {
				t.Fatal("occupied email accepted", err)
			}
			if _, err := s.BindHuawei(ctx, other.ID, otherSID, "huawei-one"); !errors.Is(err, ErrIdentityAlreadyLinked) {
				t.Fatal("occupied Huawei accepted", err)
			}
			emailUser, err := s.Register(ctx, "email@example.test", "test-password", "Email")
			if err != nil {
				t.Fatal(err)
			}
			emailSID, err := s.CreateSession(ctx, emailUser.ID, time.Now().Add(time.Hour))
			if err != nil {
				t.Fatal(err)
			}
			if _, err := s.BindHuawei(ctx, emailUser.ID, emailSID, "huawei-three"); !errors.Is(err, ErrInvalidCredentials) {
				t.Fatal("unverified email can bind", err)
			}
			if _, err := s.MarkEmailVerified(ctx, emailUser.ID); err != nil {
				t.Fatal(err)
			}
			if _, err := s.BindHuawei(ctx, emailUser.ID, emailSID, "huawei-one"); !errors.Is(err, ErrIdentityAlreadyLinked) {
				t.Fatal("identity transfer accepted", err)
			}
			if _, err := s.BindHuawei(ctx, emailUser.ID, emailSID, "huawei-three"); err != nil {
				t.Fatal(err)
			}
			linkedEmail, err := s.LoginHuawei(ctx, "huawei-three")
			if err != nil || linkedEmail.ID != emailUser.ID {
				t.Fatal("email to Huawei binding changed user", err)
			}
			if err := s.RevokeSession(ctx, emailSID, emailUser.ID); err != nil {
				t.Fatal(err)
			}
			if _, err := s.BindHuawei(ctx, emailUser.ID, emailSID, "huawei-three"); !errors.Is(err, ErrInvalidCredentials) {
				t.Fatal("revoked session accepted", err)
			}
			if err := s.EnsureSchema(ctx); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestBindingProofExpiryAndHTTP(t *testing.T) {
	s := isolatedAuthStore(t, false)
	ctx := context.Background()
	user, err := s.LoginHuawei(ctx, "http-user")
	if err != nil {
		t.Fatal(err)
	}
	sid, err := s.CreateSession(ctx, user.ID, time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	service := NewTokenService("test-service-secret", time.Hour)
	bearer, err := service.Issue(user, sid)
	if err != nil {
		t.Fatal(err)
	}
	api := NewHTTPAPI(s, nil, service, NewMailer(MailConfig{}), "https://app.example.test", time.Second*5, time.Hour, time.Minute)
	mux := http.NewServeMux()
	api.Register(mux)
	call := func(method, path, body, token string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, path, strings.NewReader(body))
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		mux.ServeHTTP(w, r)
		return w
	}
	if w := call("GET", "/api/auth/me", "", bearer); w.Code != 200 {
		t.Fatal("Huawei identity rejected", w.Code)
	}
	if w := call("PUT", "/api/auth/me", `{"displayName":"Updated"}`, bearer); w.Code != 200 {
		t.Fatal("PUT rejected", w.Code)
	}
	if w := call("POST", "/api/auth/email-binding/complete", `{}`, ""); w.Code != 401 {
		t.Fatal("anonymous binding accepted", w.Code)
	}
	proof, _ := randomToken()
	id := hashToken(proof)
	if _, err := s.CreateEmailBinding(ctx, user.ID, sid, "first@example.test", id, time.Now().Add(-time.Minute)); err != nil {
		t.Fatal(err)
	}
	if err := s.VerifyEmailBinding(ctx, id); !errors.Is(err, ErrInvalidAccountToken) {
		t.Fatal("expired proof accepted", err)
	}
	_, err = s.db.Exec(ctx, `UPDATE auth_email_tokens SET created_at = now() - interval '2 minutes'`)
	if err != nil {
		t.Fatal(err)
	}
	proof2, _ := randomToken()
	id2 := hashToken(proof2)
	if _, err := s.CreateEmailBinding(ctx, user.ID, sid, "second@example.test", id2, time.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if err := s.VerifyEmailBinding(ctx, id); !errors.Is(err, ErrInvalidAccountToken) {
		t.Fatal("superseded proof accepted", err)
	}
	body, _ := json.Marshal(map[string]string{"token": proof2})
	if w := call("POST", "/api/auth/verify-email", string(body), ""); w.Code < 400 {
		t.Fatal("binding proof accepted as login")
	}
	w := call("POST", "/api/auth/email-binding/verify", string(body), bearer)
	if w.Code != 204 || w.Body.Len() != 0 || len(w.Result().Cookies()) != 0 {
		t.Fatal("email proof issued session", w.Code)
	}
	if _, err := s.CompleteEmailBinding(ctx, user.ID, sid, id2, strings.Repeat("x", 73)); !errors.Is(err, ErrInvalidRegistration) {
		t.Fatal("oversized password accepted", err)
	}
	if err := s.RevokeSession(ctx, sid, user.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteEmailBinding(ctx, user.ID, sid, id2, "test-password"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatal("revoked binding accepted", err)
	}
	if w := call("GET", "/api/auth/me", "", bearer); w.Code != 401 {
		t.Fatal("revoked HTTP session accepted", w.Code)
	}
}
