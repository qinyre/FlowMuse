package social

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"flowmuse/server/internal/auth"
)

func TestSocialHTTPRequiresIdentityAndHidesPrivateFields(t *testing.T) {
	s, p := socialStore(t)
	ctx := context.Background()
	users := auth.NewUserStore(s.db)
	tokens := auth.NewTokenService("social-http-test", time.Hour)
	authAPI := auth.NewHTTPAPI(users, nil, tokens, nil, "", 10*time.Second, time.Hour, time.Hour)
	mux := http.NewServeMux()
	NewHTTPAPI(s, authAPI.IdentityFromRequest, true, 10*time.Second).Register(mux)
	call := func(method, path, token, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "/api/social/"+path, strings.NewReader(body))
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		mux.ServeHTTP(w, r)
		return w
	}
	if w := call("GET", "me", "", ""); w.Code != 401 {
		t.Fatal("guest admitted")
	}
	u, err := users.Load(ctx, p[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	sid, err := users.CreateSession(ctx, u.ID, time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	token, _ := tokens.Issue(u, sid)
	w := call("GET", "me", token, "")
	if w.Code != 200 {
		t.Fatal("Huawei-only account rejected", w.Code)
	}
	for _, field := range []string{"email", "huawei", "password", "token"} {
		if strings.Contains(strings.ToLower(w.Body.String()), field) {
			t.Fatal("private account field in projection")
		}
	}
	for _, body := range []string{`{"friendCode":"ABC"}{}`, `{"friendCode":"ABC","userId":"forged"}`, `{"friendCode":"` + strings.Repeat("a", 66000) + `"}`} {
		w := call("POST", "people/lookup", token, body)
		if w.Code != 400 && w.Code != 413 {
			t.Fatal("bad input accepted")
		}
	}
	body, _ := json.Marshal(map[string]any{"friendCode": p[1].FriendCode, "clientRequestId": "http-test", "expectedVersion": "0"})
	if w := call("POST", "relationships", token, string(body)); w.Code != 200 {
		t.Fatal("request failed", w.Code)
	}
	if err := users.RevokeSession(ctx, sid, u.ID); err != nil {
		t.Fatal(err)
	}
	if w := call("GET", "me", token, ""); w.Code != 401 {
		t.Fatal("revoked session admitted")
	}
}

func TestSocialDisabledAndRateIsolation(t *testing.T) {
	api := NewHTTPAPI(nil, nil, false, time.Second)
	mux := http.NewServeMux()
	api.Register(mux)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, httptest.NewRequest("GET", "/api/social/me", nil))
	if w.Code != 503 {
		t.Fatal("disabled module did not return 503")
	}
	if !api.allow("a", 1) || api.allow("a", 1) || !api.allow("b", 1) {
		t.Fatal("rate limit not isolated per account")
	}
}
