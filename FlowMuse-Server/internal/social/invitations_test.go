package social

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flowmuse/server/internal/storage"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
)

func inviteFixture(t *testing.T) (*Store, []Person, InvitationRequest) {
	t.Helper()
	s, p := socialStore(t)
	ctx := context.Background()
	friendConversation(t, s, p[0], p[1])
	if _, err := storage.NewRoomStore(s.db).CreateRoom(ctx, "invite-room", p[0].ID, "test-owner-hash"); err != nil {
		t.Fatal(err)
	}
	a, err := s.RegisterDevice(ctx, p[0].ID, testDevice("sender-device", 19))
	if err != nil {
		t.Fatal(err)
	}
	b, err := s.RegisterDevice(ctx, p[1].ID, testDevice("recipient-device", 35))
	if err != nil {
		t.Fatal(err)
	}
	expiry := time.Now().Add(time.Hour).UnixMilli()
	e := Envelope{Version: 1, Suite: invitationSuite, InviteID: "invite-one", RoomID: "invite-room", SenderID: p[0].ID, RecipientID: p[1].ID,
		SenderDeviceID: a.ID, SenderKeyID: a.KeyID, DeviceID: b.ID, KeyID: b.KeyID, ExpiresAt: expiry, Enc: b.PublicKey, Ciphertext: base64.RawURLEncoding.EncodeToString(make([]byte, 32))}
	return s, p, InvitationRequest{ID: e.InviteID, ClientID: "client-one", RoomID: e.RoomID, RecipientID: e.RecipientID, ExpiresAt: expiry, KeysetVersion: 1, Envelopes: []Envelope{e}}
}

func TestInvitationAtomicDeduplicationAndJoin(t *testing.T) {
	s, p, b := inviteFixture(t)
	ctx := context.Background()
	var wg sync.WaitGroup
	for n := 0; n < 4; n++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := s.CreateInvitation(ctx, p[0].ID, b); err != nil {
				t.Error("concurrent retry", err)
			}
		}()
	}
	wg.Wait()
	i, err := s.Invitation(ctx, p[1].ID, b.ID)
	if err != nil {
		t.Fatal(err)
	}
	messages, err := s.Messages(ctx, p[1].ID, i.ConversationID, 0, 0, 100)
	if err != nil || len(messages) != 1 || messages[0].Kind != "invitation" || messages[0].Invitation == nil || messages[0].Invitation.Status != "pending" {
		t.Fatal("card not atomic", err)
	}
	wire, _ := json.Marshal(messages[0])
	if strings.Contains(string(wire), "ciphertext") || strings.Contains(string(wire), "ownerKey") || strings.Contains(string(wire), "roomKey") {
		t.Fatal("card leaked secrets")
	}
	b.Envelopes = slices.Clone(b.Envelopes)
	b.Envelopes[0].Ciphertext = base64.RawURLEncoding.EncodeToString(make([]byte, 33))
	if _, err = s.CreateInvitation(ctx, p[0].ID, b); !errors.Is(err, ErrConflict) {
		t.Fatal("idempotency body overwritten")
	}
	if _, err = s.Invitation(ctx, p[2].ID, i.ID); !errors.Is(err, ErrNotFound) {
		t.Fatal("third party saw invite")
	}
	e := b.Envelopes[0]
	if _, err = s.AcceptInvitation(ctx, p[0].ID, i.ID, e.DeviceID, e.KeyID); !errors.Is(err, ErrNotFound) {
		t.Fatal("sender accepted")
	}
	if _, err = s.AcceptInvitation(ctx, p[1].ID, i.ID, "sender-device", "key-sender-device"); !errors.Is(err, ErrEnvelopeMissing) {
		t.Fatal("other account device accepted")
	}
	accepted, err := s.AcceptInvitation(ctx, p[1].ID, i.ID, e.DeviceID, e.KeyID)
	if err != nil || accepted.Invitation.Status != "accepted" {
		t.Fatal("accept failed", err)
	}
	again, err := s.AcceptInvitation(ctx, p[1].ID, i.ID, e.DeviceID, e.KeyID)
	if err != nil || again.Invitation.Version != accepted.Invitation.Version {
		t.Fatal("accept retry changed version", err)
	}
	if _, err = s.InvitationJoined(ctx, p[1].ID, i.ID); !errors.Is(err, ErrForbidden) {
		t.Fatal("joined without room membership")
	}
	if err = storage.NewRoomStore(s.db).UpsertMember(ctx, i.RoomID, p[1].ID, "editor"); err != nil {
		t.Fatal(err)
	}
	joined, err := s.InvitationJoined(ctx, p[1].ID, i.ID)
	if err != nil || joined.JoinedAt == 0 {
		t.Fatal("join confirmation failed", err)
	}
	if err = s.SetBlock(ctx, p[1].ID, p[0].ID, true); err != nil {
		t.Fatal(err)
	}
	blockedInvite, err := s.Invitation(ctx, p[1].ID, i.ID)
	if err != nil || blockedInvite.Status != "revoked" {
		t.Fatal("block did not revoke invite", err)
	}
	if _, err = s.AcceptInvitation(ctx, p[1].ID, i.ID, e.DeviceID, e.KeyID); !errors.Is(err, ErrForbidden) {
		t.Fatal("blocked invite granted")
	}
}

func TestInvitationValidationRollbackAndDeviceChanges(t *testing.T) {
	s, p, b := inviteFixture(t)
	ctx := context.Background()
	bad := b
	bad.KeysetVersion = 99
	if _, err := s.CreateInvitation(ctx, p[0].ID, bad); !errors.Is(err, ErrConflict) {
		t.Fatal("stale device set accepted")
	}
	bad = b
	bad.Envelopes = slices.Clone(b.Envelopes)
	bad.Envelopes[0].SenderID = p[2].ID
	if _, err := s.CreateInvitation(ctx, p[0].ID, bad); !errors.Is(err, ErrInvalid) {
		t.Fatal("forged context accepted")
	}
	var count int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM room_invites WHERE recipient_id IS NOT NULL`).Scan(&count); err != nil || count != 0 {
		t.Fatal("partial invite persisted", err)
	}
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM direct_messages`).Scan(&count); err != nil || count != 0 {
		t.Fatal("orphan card persisted", err)
	}
	i, err := s.CreateInvitation(ctx, p[0].ID, b)
	if err != nil {
		t.Fatal(err)
	}
	newDevice, err := s.RegisterDevice(ctx, p[1].ID, testDevice("new-device", 51))
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.AcceptInvitation(ctx, p[1].ID, i.ID, newDevice.ID, newDevice.KeyID); !errors.Is(err, ErrEnvelopeMissing) {
		t.Fatal("new device received old envelope")
	}
	e := b.Envelopes[0]
	e.DeviceID = newDevice.ID
	e.KeyID = newDevice.KeyID
	updated, err := s.AddInvitationEnvelopes(ctx, p[0].ID, i.ID, 2, []Envelope{e})
	if err != nil {
		t.Fatal(err)
	}
	retry, err := s.AddInvitationEnvelopes(ctx, p[0].ID, i.ID, 2, []Envelope{e})
	if err != nil || updated.Version != retry.Version {
		t.Fatal("supplement retry duplicated", err)
	}
	if _, err = s.AcceptInvitation(ctx, p[1].ID, i.ID, newDevice.ID, newDevice.KeyID); err != nil {
		t.Fatal(err)
	}
	if err = s.RevokeDevice(ctx, p[0].ID, e.SenderDeviceID); err != nil {
		t.Fatal(err)
	}
	if _, err = s.AcceptInvitation(ctx, p[1].ID, i.ID, newDevice.ID, newDevice.KeyID); !errors.Is(err, ErrEnvelopeMissing) {
		t.Fatal("revoked sender envelope issued")
	}
}

func TestInvitationExpiryRevocationAndRoomOwner(t *testing.T) {
	s, p, b := inviteFixture(t)
	ctx := context.Background()
	if _, err := s.db.Exec(ctx, `UPDATE collaboration_rooms SET owner_id=$1 WHERE room_id=$2`, p[1].ID, b.RoomID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateInvitation(ctx, p[0].ID, b); !errors.Is(err, ErrForbidden) {
		t.Fatal("fake owner sent invite")
	}
	if _, err := s.db.Exec(ctx, `UPDATE collaboration_rooms SET owner_id=$1 WHERE room_id=$2`, p[0].ID, b.RoomID); err != nil {
		t.Fatal(err)
	}
	i, err := s.CreateInvitation(ctx, p[0].ID, b)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.InvitationAction(ctx, p[1].ID, i.ID, "revoke", i.Version); !errors.Is(err, ErrNotFound) {
		t.Fatal("recipient revoked sender invite")
	}
	revoked, err := s.InvitationAction(ctx, p[0].ID, i.ID, "revoke", i.Version)
	if err != nil || revoked.Status != "revoked" {
		t.Fatal(err)
	}
	if _, err = s.InvitationAction(ctx, p[0].ID, i.ID, "revoke", i.Version); err != nil {
		t.Fatal("revoke retry failed", err)
	}
	if _, err = s.AcceptInvitation(ctx, p[1].ID, i.ID, b.Envelopes[0].DeviceID, b.Envelopes[0].KeyID); !errors.Is(err, ErrInviteGone) {
		t.Fatal("revoked accepted")
	}
	if _, err = s.db.Exec(ctx, `UPDATE room_invites SET status='pending',expires_at=now()-interval '1 second' WHERE id=$1`, i.ID); err != nil {
		t.Fatal(err)
	}
	expired, err := s.Invitation(ctx, p[1].ID, i.ID)
	if err != nil || expired.Status != "expired" {
		t.Fatal("expired status", err)
	}
	if _, err = s.AcceptInvitation(ctx, p[1].ID, i.ID, b.Envelopes[0].DeviceID, b.Envelopes[0].KeyID); !errors.Is(err, ErrInviteGone) {
		t.Fatal("expired accepted")
	}
	if _, err = storage.NewRoomStore(s.db).EndRoom(ctx, i.RoomID, p[0].ID, ""); err != nil {
		t.Fatal(err)
	}
	ended, err := s.Invitation(ctx, p[1].ID, i.ID)
	if err != nil || ended.Status != "room_ended" {
		t.Fatal("room-ended status", err)
	}
}
