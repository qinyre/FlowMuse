package social

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"flowmuse/server/internal/auth"
	"github.com/zishang520/socket.io/v2/socket"
)

func TestSocialSocketWebAuthIsolationAndRevocation(t *testing.T) {
	s, p := socialStore(t)
	ctx := context.Background()
	users := auth.NewUserStore(s.db)
	tokens := auth.NewTokenService("test-social-socket", time.Hour)
	u, err := users.Load(ctx, p[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	sid, err := users.CreateSession(ctx, u.ID, time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	token, _ := tokens.Issue(u, sid)
	server := socket.NewServer(nil, nil)
	defer server.Close(nil)
	h := NewHub(server, users, tokens, true)
	defer h.Close()
	mux := http.NewServeMux()
	mux.Handle("/socket.io/", server.ServeHandler(nil))
	httpServer := httptest.NewServer(mux)
	defer httpServer.Close()
	client := &http.Client{Timeout: 5 * time.Second}
	get := func(url string) string {
		t.Helper()
		r, err := client.Get(url)
		if err != nil {
			t.Fatal(err)
		}
		defer r.Body.Close()
		b, _ := io.ReadAll(r.Body)
		return string(b)
	}
	post := func(url, body string) {
		t.Helper()
		r, err := client.Post(url, "text/plain", strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		r.Body.Close()
		if r.StatusCode != 200 {
			t.Fatal("engine send failed")
		}
	}
	connect := func(authBody string) (string, string) {
		t.Helper()
		base := httpServer.URL + "/socket.io/?EIO=4&transport=polling"
		open := get(base)
		var packet struct {
			SID string `json:"sid"`
		}
		if len(open) < 2 || json.Unmarshal([]byte(open[1:]), &packet) != nil {
			t.Fatal("engine handshake failed")
		}
		url := base + "&sid=" + packet.SID
		post(url, "40/social,"+authBody)
		return url, get(url)
	}
	_, denied := connect(`{}`)
	if !strings.Contains(denied, "44/social,") {
		t.Fatal("guest entered social namespace")
	}
	_, denied = connect(`{"token":"forged"}`)
	if !strings.Contains(denied, "44/social,") {
		t.Fatal("forged token entered")
	}
	body, _ := json.Marshal(map[string]string{"token": token})
	url, accepted := connect(string(body))
	if !strings.Contains(accepted, "40/social,") {
		t.Fatal("browser-only auth.token rejected")
	}
	h.Notify("relationship.changed", "other-user-only", p[1].ID)
	h.Notify("conversation.changed", "own-id", p[0].ID)
	packet := get(url)
	if strings.Contains(packet, "other-user-only") || !strings.Contains(packet, "own-id") {
		t.Fatal("notification isolation failed")
	}
	// Simulate a database query failure inside this test's isolated schema.
	if _, err := s.db.Exec(ctx, `ALTER TABLE auth_sessions RENAME TO temporarily_unavailable_sessions`); err != nil {
		t.Fatal(err)
	}
	h.deliver(hint{event: "conversation.changed", id: "unverified-hint", users: []string{u.ID}})
	if _, err := s.db.Exec(ctx, `ALTER TABLE temporarily_unavailable_sessions RENAME TO auth_sessions`); err != nil {
		t.Fatal(err)
	}
	h.Notify("conversation.changed", "after-recovery", u.ID)
	packet = get(url)
	if !strings.Contains(packet, "after-recovery") || strings.Contains(packet, "session.revoked") || strings.Contains(packet, "unverified-hint") {
		t.Fatal("temporary database failure revoked session or delivered unchecked data")
	}
	if err := users.RevokeSession(ctx, sid, u.ID); err != nil {
		t.Fatal(err)
	}
	h.Notify("conversation.changed", "after-revoke", p[0].ID)
	packet = get(url)
	if strings.Contains(packet, "after-revoke") || !strings.Contains(packet, "session.revoked") {
		t.Fatal("revoked session received hints")
	}
}
