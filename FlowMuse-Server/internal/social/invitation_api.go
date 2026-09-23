package social

import (
	"net/http"
	"strings"
)

func (api *HTTPAPI) serveInvitations(w http.ResponseWriter, r *http.Request, user, path string) {
	ctx := r.Context()
	var result any
	var err error
	switch {
	case path == "devices" && r.Method == "POST":
		var body struct {
			ID        string `json:"id"`
			KeyID     string `json:"keyId"`
			PublicKey string `json:"publicKey"`
			Label     string `json:"label"`
		}
		if !decode(w, r, &body) {
			return
		}
		result, err = api.store.RegisterDevice(ctx, user, Device{ID: body.ID, KeyID: body.KeyID, PublicKey: body.PublicKey, Label: body.Label})
		if err == nil {
			api.changed("invitation.changed", "", user)
		}
	case path == "devices" && r.Method == "GET":
		result, err = api.store.Devices(ctx, user, user)
	case strings.HasPrefix(path, "devices/") && r.Method == "POST":
		id, ok := actionID(path, "devices", "revoke")
		if !ok {
			respondError(w, ErrNotFound)
			return
		}
		var body struct{}
		if !decode(w, r, &body) {
			return
		}
		err = api.store.RevokeDevice(ctx, user, id)
		result = map[string]bool{"ok": err == nil}
		if err == nil {
			api.changed("invitation.changed", "", user)
		}
	case strings.HasPrefix(path, "friends/") && r.Method == "GET":
		id, ok := actionID(path, "friends", "devices")
		if !ok {
			respondError(w, ErrNotFound)
			return
		}
		result, err = api.store.Devices(ctx, user, id)
	case path == "invitations" && r.Method == "POST":
		var body InvitationRequest
		if !decode(w, r, &body) {
			return
		}
		var i Invitation
		i, err = api.store.CreateInvitation(ctx, user, body)
		result = i
		if err == nil {
			api.invitationChanged(i)
		}
	case path == "invitations" && r.Method == "GET":
		limit, cursor, ok := page(r, 20)
		if !ok {
			respondError(w, ErrInvalid)
			return
		}
		direction := r.URL.Query().Get("direction")
		if direction == "" {
			direction = "received"
		}
		var items []Invitation
		items, err = api.store.Invitations(ctx, user, direction, cursor, limit+1)
		next := ""
		if len(items) > limit {
			items = items[:limit]
			next = items[len(items)-1].ID
		}
		result = map[string]any{"items": items, "nextCursor": next}
	case strings.HasPrefix(path, "invitations/"):
		parts := strings.Split(path, "/")
		if len(parts) < 2 || !safeID.MatchString(parts[1]) {
			respondError(w, ErrNotFound)
			return
		}
		id := parts[1]
		if len(parts) == 2 && r.Method == "GET" {
			result, err = api.store.Invitation(ctx, user, id)
			break
		}
		if len(parts) != 3 || r.Method != "POST" {
			respondError(w, ErrNotFound)
			return
		}
		var i Invitation
		switch parts[2] {
		case "accept":
			var body struct {
				DeviceID string `json:"deviceId"`
				KeyID    string `json:"keyId"`
			}
			if !decode(w, r, &body) {
				return
			}
			var accepted AcceptedInvitation
			accepted, err = api.store.AcceptInvitation(ctx, user, id, body.DeviceID, body.KeyID)
			result = accepted
			i = accepted.Invitation
		case "decline", "revoke":
			var body struct {
				ExpectedVersion *int64 `json:"expectedVersion,string"`
			}
			if !decode(w, r, &body) {
				return
			}
			if body.ExpectedVersion == nil {
				respondError(w, ErrInvalid)
				return
			}
			i, err = api.store.InvitationAction(ctx, user, id, parts[2], *body.ExpectedVersion)
			result = i
		case "joined":
			var body struct{}
			if !decode(w, r, &body) {
				return
			}
			i, err = api.store.InvitationJoined(ctx, user, id)
			result = i
		case "envelopes":
			var body struct {
				KeysetVersion int64      `json:"keysetVersion,string"`
				Envelopes     []Envelope `json:"envelopes"`
			}
			if !decode(w, r, &body) {
				return
			}
			i, err = api.store.AddInvitationEnvelopes(ctx, user, id, body.KeysetVersion, body.Envelopes)
			result = i
		default:
			respondError(w, ErrNotFound)
			return
		}
		if err == nil {
			api.invitationChanged(i)
		}
	default:
		respondError(w, ErrNotFound)
		return
	}
	if err != nil {
		respondError(w, err)
		return
	}
	writeJSON(w, 200, result)
}

func (api *HTTPAPI) invitationChanged(i Invitation) {
	api.changed("invitation.changed", i.ID, i.SenderID, i.RecipientID)
	api.changed("conversation.changed", i.ConversationID, i.SenderID, i.RecipientID)
}
