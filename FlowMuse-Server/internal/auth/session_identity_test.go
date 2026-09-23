package auth

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestSocketToken(t *testing.T) {
	for _, tc := range []struct {
		name, header string
		auth         any
		want         string
		invalid      bool
	}{
		{"guest", "", nil, "", false},
		{"web", "", map[string]any{"token": "test-token"}, "test-token", false},
		{"native", "Bearer test-token", nil, "test-token", false},
		{"both", "Bearer test-token", map[string]any{"token": "test-token"}, "test-token", false},
		{"conflict", "Bearer one", map[string]any{"token": "two"}, "", true},
		{"bad header", "Basic one", nil, "", true},
		{"bad auth", "", map[string]any{"token": 1}, "", true},
		{"empty auth", "", map[string]any{"token": ""}, "", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := socketToken(tc.header, tc.auth)
			if got != tc.want || (err != nil) != tc.invalid {
				t.Fatal("unexpected credential resolution")
			}
		})
	}
}

func TestAuthenticateTokenRequiresActiveVerifiedIdentity(t *testing.T) {
	s := isolatedAuthStore(t, false)
	ctx := context.Background()
	u, err := s.LoginHuawei(ctx, "test-social-huawei")
	if err != nil {
		t.Fatal(err)
	}
	tokens := NewTokenService("test-session-secret", time.Hour)
	sid, err := s.CreateSession(ctx, u.ID, time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	token, _ := tokens.Issue(u, sid)
	identity, err := s.AuthenticateToken(ctx, tokens, token)
	if err != nil || identity.IsGuest || identity.UserID != u.ID || identity.Email != "" {
		t.Fatal("Huawei-only identity rejected")
	}
	cancelled, cancel := context.WithCancel(ctx)
	cancel()
	if _, err := s.AuthenticateToken(cancelled, tokens, token); err == nil || errors.Is(err, ErrInvalidToken) {
		t.Fatal("database cancellation must not revoke valid credentials")
	}
	for _, invalid := range []string{"", "forged", token + "x"} {
		if _, err := s.AuthenticateToken(ctx, tokens, invalid); err == nil {
			t.Fatal("invalid token accepted")
		}
	}
	expired, _ := NewTokenService("test-session-secret", -time.Hour).Issue(u, sid)
	if _, err := s.AuthenticateToken(ctx, tokens, expired); err == nil {
		t.Fatal("expired token accepted")
	}
	if err := s.RevokeSession(ctx, sid, u.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.AuthenticateToken(ctx, tokens, token); err == nil {
		t.Fatal("revoked token accepted")
	}
	unverified, err := s.Register(ctx, "unverified@example.test", "test-password", "未验证")
	if err != nil {
		t.Fatal(err)
	}
	sid, err = s.CreateSession(ctx, unverified.ID, time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	token, _ = tokens.Issue(unverified, sid)
	if _, err := s.AuthenticateToken(ctx, tokens, token); err == nil {
		t.Fatal("unverified identity accepted")
	}
}
