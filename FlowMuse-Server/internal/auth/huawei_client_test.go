package auth

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHuaweiCredentialValidation(t *testing.T) {
	for _, scenario := range []string{"valid", "no-profile-scope", "profile-failed", "profile-mismatch", "profile-unsafe-avatar", "wrong-client", "app-token", "missing-type", "expired", "missing-union", "replayed-code", "nsp-error", "timeout", "redirect", "oversize", "malformed"} {
		t.Run(scenario, func(t *testing.T) {
			info := map[string]any{"client_id": "test-app", "union_id": "test-union", "expire_in": 300, "type": 0}
			switch scenario {
			case "wrong-client":
				info["client_id"] = "another-app"
			case "app-token":
				info["type"] = 1
			case "missing-type":
				delete(info, "type")
			case "expired":
				info["expire_in"] = 0
			case "missing-union":
				delete(info, "union_id")
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != "POST" || r.Header.Get("Content-Type") != "application/x-www-form-urlencoded" {
					t.Error("expected form POST")
				}
				if err := r.ParseForm(); err != nil {
					t.Error(err)
					return
				}
				if r.URL.Path == "/token" {
					if r.PostForm.Get("code") != "test+code/%2F" || r.PostForm.Get("client_id") != "test-app" || r.PostForm.Get("client_secret") != "test-secret" || r.PostForm.Get("grant_type") != "authorization_code" {
						t.Error("authorization form did not round-trip")
					}
					switch scenario {
					case "replayed-code":
						w.WriteHeader(400)
						return
					case "timeout":
						<-r.Context().Done()
						return
					case "redirect":
						w.Header().Set("Location", "/must-not-follow")
						w.WriteHeader(307)
						return
					case "oversize":
						_, _ = w.Write([]byte(strings.Repeat("x", 65537)))
						return
					case "malformed":
						_, _ = w.Write([]byte(`{"access_token":`))
						return
					}
					scope := "openid profile"
					if scenario == "no-profile-scope" {
						scope = "openid"
					}
					_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "test-access", "token_type": "Bearer", "expires_in": 3600, "scope": scope})
					return
				}
				if r.URL.Path == "/profile" {
					if r.PostForm.Get("access_token") != "test-access" || r.PostForm.Get("getNickName") != "1" {
						t.Error("profile request lost access token or nickname preference")
					}
					if scenario == "profile-failed" {
						w.WriteHeader(503)
						return
					}
					profile := map[string]any{"unionID": "test-union", "displayName": "华为昵称", "headPictureURL": "https://upfile-drcn.platform.hicloud.com/avatar.jpg"}
					if scenario == "profile-mismatch" {
						profile["unionID"] = "other-user"
					}
					if scenario == "profile-unsafe-avatar" {
						profile["headPictureURL"] = "http://example.test/avatar.jpg"
					}
					_ = json.NewEncoder(w).Encode(profile)
					return
				}
				if r.URL.Path != "/info" {
					t.Error("followed redirect")
					return
				}
				if r.PostForm.Get("access_token") != "test-access" {
					t.Error("missing access credential")
				}
				if scenario == "nsp-error" {
					w.Header().Set("NSP_STATUS", "6")
				}
				_ = json.NewEncoder(w).Encode(info)
			}))
			defer server.Close()
			client := NewHuaweiClient("test-app", "test-secret")
			client.tokenURL, client.infoURL, client.profileURL = server.URL+"/token", server.URL+"/info", server.URL+"/profile"
			client.http.Timeout = 200 * time.Millisecond
			identity, err := client.VerifyCode(context.Background(), "test+code/%2F")
			if scenario == "valid" || strings.HasPrefix(scenario, "profile-") || scenario == "no-profile-scope" {
				if err != nil || identity.UnionID != "test-union" {
					t.Fatalf("valid exchange failed: %v", err)
				}
				if scenario == "valid" && (identity.DisplayName != "华为昵称" || identity.AvatarURL != "https://upfile-drcn.platform.hicloud.com/avatar.jpg") {
					t.Fatal("profile not returned from Huawei")
				}
				if (scenario == "profile-failed" || scenario == "profile-mismatch" || scenario == "no-profile-scope") && (identity.DisplayName != "" || identity.AvatarURL != "") {
					t.Fatal("unavailable or ungranted profile was accepted")
				}
				if scenario == "profile-unsafe-avatar" && (identity.DisplayName != "华为昵称" || identity.AvatarURL != "") {
					t.Fatal("unsafe avatar URL was accepted")
				}
			} else if err == nil || identity.UnionID != "" {
				t.Fatal("invalid upstream response accepted")
			} else if strings.Contains(err.Error(), "test-secret") || strings.Contains(err.Error(), "test-access") {
				t.Fatal("credential leaked in error")
			}
		})
	}
	for _, value := range []string{"javascript:alert(1)", "http://example.test/avatar", "https://user:pass@example.test/avatar", strings.Repeat("x", 2049)} {
		if validHuaweiAvatarURL(value) != "" {
			t.Fatal("unsafe avatar URL accepted")
		}
	}
	if NewHuaweiClient("", "secret") != nil || NewHuaweiClient("id", "") != nil {
		t.Fatal("missing config enabled login")
	}
}

func TestLoginMethodFailuresAndRateLimit(t *testing.T) {
	api := &HTTPAPI{}
	w := httptest.NewRecorder()
	api.huaweiLogin(w, httptest.NewRequest("POST", "/", strings.NewReader(`{"code":"test"}`)))
	if w.Code != 503 {
		t.Fatalf("unconfigured provider status %d", w.Code)
	}
	w = httptest.NewRecorder()
	api.huaweiLogin(w, httptest.NewRequest("GET", "/", nil))
	if w.Code != 405 {
		t.Fatalf("GET login status %d", w.Code)
	}
	now := time.Now()
	l := authRateLimiter{}
	for i := 0; i < 30; i++ {
		if !l.allow("test", now) {
			t.Fatal("limited too early")
		}
	}
	if l.allow("test", now) || !l.allow("test", now.Add(time.Minute)) {
		t.Fatal("rate window failed")
	}
	for _, u := range []User{{EmailVerified: true}, {HuaweiLinked: true}} {
		if !u.HasVerifiedIdentity() {
			t.Fatal("trusted identity rejected")
		}
	}
	if (User{}).HasVerifiedIdentity() {
		t.Fatal("unverified identity accepted")
	}
}
