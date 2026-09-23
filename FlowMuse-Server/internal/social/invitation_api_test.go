package social

import (
	"encoding/json"
	"flowmuse/server/internal/auth"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestInvitationHTTPContractAndFlag(t *testing.T) {
	s, p, b := inviteFixture(t)
	api := NewHTTPAPI(s, func(r *http.Request) (auth.Identity, error) {
		return auth.Identity{UserID: r.Header.Get("X-Test-User")}, nil
	}, true, 10*time.Second)
	call := func(method, path, user, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "/api/social/"+path, strings.NewReader(body))
		r.Header.Set("X-Test-User", user)
		w := httptest.NewRecorder()
		api.serve(w, r)
		return w
	}
	if w := call("GET", "devices", p[0].ID, ""); w.Code != 503 {
		t.Fatal("invite flag not isolated")
	}
	if w := call("GET", "me", p[0].ID, ""); w.Code != 200 || !strings.Contains(w.Body.String(), `"invitations":false`) {
		t.Fatal("capability incorrect")
	}
	api.InvitationsEnabled = true
	if w := call("GET", "devices", "", ""); w.Code != 401 {
		t.Fatal("guest accessed devices")
	}
	if w := call("POST", "devices", p[0].ID, `{"id":"x","userId":"forged"}`); w.Code != 400 {
		t.Fatal("device identity injection accepted")
	}
	payload, _ := json.Marshal(b)
	if w := call("POST", "invitations", p[0].ID, string(payload)); w.Code != 200 {
		t.Fatal("create HTTP failed", w.Code)
	}
	if w := call("GET", "invitations/"+b.ID, p[2].ID, ""); w.Code != 404 {
		t.Fatal("invite existence leaked")
	}
	if w := call("GET", "invitations?direction=received", p[1].ID, ""); w.Code != 200 || !strings.Contains(w.Body.String(), b.ID) {
		t.Fatal("inbox missing invite")
	}
	accept := `{"deviceId":"recipient-device","keyId":"key-recipient-device"}`
	if w := call("POST", "invitations/"+b.ID+"/accept", p[1].ID, accept); w.Code != 200 || !strings.Contains(w.Body.String(), `"suite":"`+invitationSuite+`"`) {
		t.Fatal("accept wire mismatch", w.Code)
	}
	if w := call("POST", "invitations/"+b.ID+"/decline", p[1].ID, `{"expectedVersion":"2"}`); w.Code != 200 {
		t.Fatal("decline failed", w.Code)
	}
	if w := call("POST", "invitations/"+b.ID+"/accept", p[1].ID, accept); w.Code != 410 {
		t.Fatal("declined invite accepted", w.Code)
	}
}
