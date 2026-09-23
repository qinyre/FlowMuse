package social

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const invitationSuite = "HPKE-Auth-X25519-HKDF-SHA256-AES128GCM-v1"

var ErrInviteGone = errors.New("invitation no longer available")
var ErrEnvelopeMissing = errors.New("invitation envelope unavailable for device")

type Envelope struct {
	Version        int    `json:"version"`
	Suite          string `json:"suite"`
	InviteID       string `json:"inviteId"`
	RoomID         string `json:"roomId"`
	SenderID       string `json:"senderId"`
	RecipientID    string `json:"recipientId"`
	SenderDeviceID string `json:"senderDeviceId"`
	SenderKeyID    string `json:"senderKeyId"`
	DeviceID       string `json:"recipientDeviceId"`
	KeyID          string `json:"keyId"`
	ExpiresAt      int64  `json:"expiresAt"`
	Enc            string `json:"enc"`
	Ciphertext     string `json:"ciphertext"`
}
type InvitationRequest struct {
	ID            string     `json:"inviteId"`
	ClientID      string     `json:"clientInviteId"`
	RoomID        string     `json:"roomId"`
	RecipientID   string     `json:"recipientId"`
	ExpiresAt     int64      `json:"expiresAt"`
	KeysetVersion int64      `json:"keysetVersion,string"`
	Envelopes     []Envelope `json:"envelopes"`
}
type Invitation struct {
	ID             string `json:"id"`
	RoomID         string `json:"roomId"`
	SenderID       string `json:"senderId"`
	RecipientID    string `json:"recipientId"`
	ConversationID string `json:"conversationId"`
	Status         string `json:"status"`
	Version        int64  `json:"version,string"`
	ExpiresAt      int64  `json:"expiresAt"`
	JoinedAt       int64  `json:"joinedAt"`
}
type AcceptedInvitation struct {
	Invitation Invitation `json:"invitation"`
	Envelope   Envelope   `json:"envelope"`
}

const invitationQuery = `SELECT i.id,i.room_id,i.created_by,i.recipient_id,i.conversation_id,
 CASE WHEN i.status IN('pending','accepted') AND r.ended_at IS NOT NULL THEN 'room_ended'
 WHEN i.status IN('pending','accepted') AND i.expires_at<=clock_timestamp() THEN 'expired' ELSE i.status END,
 i.version,i.expires_at,i.joined_at FROM room_invites i JOIN collaboration_rooms r ON r.room_id=i.room_id
 WHERE i.recipient_id IS NOT NULL`

func scanInvitation(row pgx.Row) (Invitation, error) {
	var i Invitation
	var expiry time.Time
	var joined *time.Time
	err := row.Scan(&i.ID, &i.RoomID, &i.SenderID, &i.RecipientID, &i.ConversationID, &i.Status, &i.Version, &expiry, &joined)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrNotFound
	}
	i.ExpiresAt = expiry.UnixMilli()
	if joined != nil {
		i.JoinedAt = joined.UnixMilli()
	}
	return i, err
}
func activeInvitation(i Invitation) bool { return i.Status == "pending" || i.Status == "accepted" }

func (s *Store) Invitation(ctx context.Context, user, id string) (Invitation, error) {
	if !safeID.MatchString(id) {
		return Invitation{}, ErrNotFound
	}
	return scanInvitation(s.db.QueryRow(ctx, invitationQuery+` AND i.id=$1 AND $2 IN(i.created_by,i.recipient_id)`, id, user))
}
func (s *Store) Invitations(ctx context.Context, user, direction, cursor string, limit int) ([]Invitation, error) {
	if direction != "received" && direction != "sent" {
		return nil, ErrInvalid
	}
	column := "i.recipient_id"
	if direction == "sent" {
		column = "i.created_by"
	}
	rows, err := s.db.Query(ctx, invitationQuery+` AND `+column+`=$1 AND i.id>$2 ORDER BY i.id LIMIT $3`, user, cursor, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []Invitation{}
	for rows.Next() {
		i, err := scanInvitation(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, i)
	}
	return result, rows.Err()
}

func validateEnvelopes(tx pgx.Tx, ctx context.Context, i Invitation, keyset int64, items []Envelope) error {
	if len(items) < 1 || len(items) > 5 || keyset < 1 {
		return ErrInvalid
	}
	var current int64
	if err := tx.QueryRow(ctx, `SELECT social_keyset_version FROM users WHERE id=$1`, i.RecipientID).Scan(&current); err != nil {
		return err
	}
	if current != keyset {
		return ErrConflict
	}
	seen := map[string]bool{}
	for _, e := range items {
		if e.Version != 1 || e.Suite != invitationSuite || e.InviteID != i.ID || e.RoomID != i.RoomID ||
			e.SenderID != i.SenderID || e.RecipientID != i.RecipientID || e.ExpiresAt != i.ExpiresAt ||
			!safeID.MatchString(e.DeviceID) || !safeID.MatchString(e.KeyID) || !safeID.MatchString(e.SenderDeviceID) || !safeID.MatchString(e.SenderKeyID) || seen[e.DeviceID] {
			return ErrInvalid
		}
		seen[e.DeviceID] = true
		if _, err := validPublicKey(e.Enc); err != nil {
			return ErrInvalid
		}
		ct, err := base64.RawURLEncoding.DecodeString(e.Ciphertext)
		if err != nil || len(ct) < 16 || len(ct) > 2048 || base64.RawURLEncoding.EncodeToString(ct) != e.Ciphertext {
			return ErrInvalid
		}
		var valid bool
		err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM social_devices WHERE id=$1 AND user_id=$2 AND key_id=$3 AND revoked_at IS NULL)
 AND EXISTS(SELECT 1 FROM social_devices WHERE id=$4 AND user_id=$5 AND key_id=$6 AND revoked_at IS NULL)`, e.DeviceID, i.RecipientID, e.KeyID, e.SenderDeviceID, i.SenderID, e.SenderKeyID).Scan(&valid)
		if err != nil {
			return err
		}
		if !valid {
			return ErrConflict
		}
	}
	return nil
}

func lockInviteRoom(ctx context.Context, tx pgx.Tx, room, owner string) error {
	var actual *string
	var ended *time.Time
	err := tx.QueryRow(ctx, `SELECT owner_id,ended_at FROM collaboration_rooms WHERE room_id=$1 FOR UPDATE`, room).Scan(&actual, &ended)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if actual == nil || *actual != owner {
		return ErrForbidden
	}
	if ended != nil {
		return ErrInviteGone
	}
	return nil
}
func insertEnvelope(ctx context.Context, tx pgx.Tx, e Envelope) error {
	_, err := tx.Exec(ctx, `INSERT INTO room_invite_envelopes(invite_id,recipient_user_id,device_id,key_id,sender_user_id,sender_device_id,sender_key_id,suite,enc,ciphertext)
 VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, e.InviteID, e.RecipientID, e.DeviceID, e.KeyID, e.SenderID, e.SenderDeviceID, e.SenderKeyID, e.Suite, e.Enc, e.Ciphertext)
	return err
}

func (s *Store) CreateInvitation(ctx context.Context, user string, body InvitationRequest) (Invitation, error) {
	if !safeID.MatchString(body.ID) || !safeID.MatchString(body.ClientID) || !safeID.MatchString(body.RoomID) || !safeID.MatchString(body.RecipientID) || user == body.RecipientID {
		return Invitation{}, ErrInvalid
	}
	body.Envelopes = slices.Clone(body.Envelopes)
	slices.SortFunc(body.Envelopes, func(a, b Envelope) int {
		if a.DeviceID < b.DeviceID {
			return -1
		}
		if a.DeviceID > b.DeviceID {
			return 1
		}
		return 0
	})
	encoded, err := json.Marshal(body)
	if err != nil {
		return Invitation{}, ErrInvalid
	}
	digest := sha256.Sum256(encoded)
	requestHash := hex.EncodeToString(digest[:])
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Invitation{}, err
	}
	defer tx.Rollback(ctx)
	if _, _, err = lockPair(ctx, tx, user, body.RecipientID); err != nil {
		return Invitation{}, err
	}
	var oldID, oldHash string
	err = tx.QueryRow(ctx, `SELECT id,request_hash FROM room_invites WHERE created_by=$1 AND client_invite_id=$2`, user, body.ClientID).Scan(&oldID, &oldHash)
	if err == nil {
		if oldHash != requestHash {
			return Invitation{}, ErrConflict
		}
		return scanInvitation(tx.QueryRow(ctx, invitationQuery+` AND i.id=$1`, oldID))
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Invitation{}, err
	}
	// Check expiry after deduplication: an old successful request remains retryable.
	now := time.Now().UnixMilli()
	if body.ExpiresAt <= now || body.ExpiresAt > now+int64((24*time.Hour)/time.Millisecond) {
		return Invitation{}, ErrInvalid
	}
	relation, err := requireFriends(ctx, tx, user, body.RecipientID)
	if err != nil {
		return Invitation{}, err
	}
	if err = lockInviteRoom(ctx, tx, body.RoomID, user); err != nil {
		return Invitation{}, err
	}
	i := Invitation{ID: body.ID, RoomID: body.RoomID, SenderID: user, RecipientID: body.RecipientID, ExpiresAt: body.ExpiresAt, Status: "pending", Version: 1}
	if err = validateEnvelopes(tx, ctx, i, body.KeysetVersion, body.Envelopes); err != nil {
		return Invitation{}, err
	}
	var recent int
	if err = tx.QueryRow(ctx, `SELECT count(*) FROM room_invites WHERE created_by=$1 AND room_id=$2 AND recipient_id=$3 AND created_at>now()-interval '1 minute'`, user, body.RoomID, body.RecipientID).Scan(&recent); err != nil {
		return Invitation{}, err
	}
	if recent > 0 {
		return Invitation{}, ErrLimit
	}
	if err = tx.QueryRow(ctx, `SELECT id FROM direct_conversations WHERE relationship_id=$1`, relation).Scan(&i.ConversationID); err != nil {
		return Invitation{}, err
	}
	_, err = tx.Exec(ctx, `INSERT INTO room_invites(id,room_id,created_by,recipient_id,conversation_id,client_invite_id,status,expires_at,request_hash)
 VALUES($1,$2,$3,$4,$5,$6,'pending',$7,$8)`, i.ID, i.RoomID, user, i.RecipientID, i.ConversationID, body.ClientID, time.UnixMilli(i.ExpiresAt), requestHash)
	if isUniqueConflict(err) {
		return Invitation{}, ErrConflict
	}
	if err != nil {
		return Invitation{}, err
	}
	for _, e := range body.Envelopes {
		if err = insertEnvelope(ctx, tx, e); err != nil {
			return Invitation{}, err
		}
	}
	var seq int64
	if err = tx.QueryRow(ctx, `UPDATE direct_conversations SET last_seq=last_seq+1,updated_at=now() WHERE id=$1 RETURNING last_seq`, i.ConversationID).Scan(&seq); err != nil {
		return Invitation{}, err
	}
	_, err = tx.Exec(ctx, `INSERT INTO direct_messages(id,conversation_id,seq,sender_id,client_message_id,kind,invite_id)
 VALUES($1,$2,$3,$4,$5,'invitation',$6)`, uuid.NewString(), i.ConversationID, seq, user, "invite-"+uuid.NewString(), i.ID)
	if err != nil {
		return Invitation{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return Invitation{}, err
	}
	return i, nil
}

// Callers lock users, relationship (when needed), room, then invitation; all
// later reads use the same transaction so revoke/block/expiry cannot race a grant.
func lockInvitation(ctx context.Context, tx pgx.Tx, i Invitation) (Invitation, error) {
	return scanInvitation(tx.QueryRow(ctx, invitationQuery+` AND i.id=$1 FOR UPDATE OF i`, i.ID))
}

func (s *Store) AcceptInvitation(ctx context.Context, user, id, device, key string) (AcceptedInvitation, error) {
	i, err := s.Invitation(ctx, user, id)
	if err != nil {
		return AcceptedInvitation{}, err
	}
	if user != i.RecipientID || !safeID.MatchString(device) || !safeID.MatchString(key) {
		return AcceptedInvitation{}, ErrNotFound
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return AcceptedInvitation{}, err
	}
	defer tx.Rollback(ctx)
	if _, _, err = lockPair(ctx, tx, i.SenderID, i.RecipientID); err != nil {
		return AcceptedInvitation{}, err
	}
	if _, err = requireFriends(ctx, tx, i.SenderID, i.RecipientID); err != nil {
		return AcceptedInvitation{}, err
	}
	if err = lockInviteRoom(ctx, tx, i.RoomID, i.SenderID); err != nil {
		return AcceptedInvitation{}, err
	}
	i, err = lockInvitation(ctx, tx, i)
	if err != nil {
		return AcceptedInvitation{}, err
	}
	if !activeInvitation(i) {
		return AcceptedInvitation{}, ErrInviteGone
	}
	e := Envelope{Version: 1, InviteID: i.ID, RoomID: i.RoomID, SenderID: i.SenderID, RecipientID: i.RecipientID, DeviceID: device, KeyID: key, ExpiresAt: i.ExpiresAt}
	err = tx.QueryRow(ctx, `SELECT e.sender_device_id,e.sender_key_id,e.suite,e.enc,e.ciphertext FROM room_invite_envelopes e
 JOIN social_devices r ON r.id=e.device_id AND r.user_id=e.recipient_user_id AND r.key_id=e.key_id
 JOIN social_devices s ON s.id=e.sender_device_id AND s.user_id=e.sender_user_id AND s.key_id=e.sender_key_id
 WHERE e.invite_id=$1 AND e.device_id=$2 AND e.key_id=$3 AND e.recipient_user_id=$4 AND r.revoked_at IS NULL AND s.revoked_at IS NULL`, id, device, key, user).Scan(&e.SenderDeviceID, &e.SenderKeyID, &e.Suite, &e.Enc, &e.Ciphertext)
	if errors.Is(err, pgx.ErrNoRows) {
		return AcceptedInvitation{}, ErrEnvelopeMissing
	}
	if err != nil {
		return AcceptedInvitation{}, err
	}
	if i.Status == "pending" {
		if _, err = tx.Exec(ctx, `UPDATE room_invites SET status='accepted',accepted_at=now(),version=version+1 WHERE id=$1`, id); err != nil {
			return AcceptedInvitation{}, err
		}
		i.Status = "accepted"
		i.Version++
	}
	if err = tx.Commit(ctx); err != nil {
		return AcceptedInvitation{}, err
	}
	return AcceptedInvitation{i, e}, nil
}

func (s *Store) InvitationAction(ctx context.Context, user, id, action string, expected int64) (Invitation, error) {
	i, err := s.Invitation(ctx, user, id)
	if err != nil {
		return Invitation{}, err
	}
	target := "declined"
	if action == "revoke" {
		target = "revoked"
		if user != i.SenderID {
			return Invitation{}, ErrNotFound
		}
	} else if action != "decline" || user != i.RecipientID {
		return Invitation{}, ErrNotFound
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Invitation{}, err
	}
	defer tx.Rollback(ctx)
	if _, _, err = lockPair(ctx, tx, i.SenderID, i.RecipientID); err != nil {
		return Invitation{}, err
	}
	// No room lock needed: declining/revoking never grants access or writes members.
	i, err = lockInvitation(ctx, tx, i)
	if err != nil {
		return Invitation{}, err
	}
	if i.Status == target && i.Version == expected+1 {
		return i, nil
	}
	if expected < 1 || i.Version != expected {
		return Invitation{}, ErrConflict
	}
	if !activeInvitation(i) {
		return Invitation{}, ErrInviteGone
	}
	_, err = tx.Exec(ctx, `UPDATE room_invites SET status=$2,version=version+1,revoked_at=CASE WHEN $2='revoked' THEN now() ELSE revoked_at END WHERE id=$1`, id, target)
	if err != nil {
		return Invitation{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return Invitation{}, err
	}
	i.Status = target
	i.Version++
	return i, nil
}

func (s *Store) InvitationJoined(ctx context.Context, user, id string) (Invitation, error) {
	i, err := s.Invitation(ctx, user, id)
	if err != nil {
		return Invitation{}, err
	}
	if user != i.RecipientID {
		return Invitation{}, ErrNotFound
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Invitation{}, err
	}
	defer tx.Rollback(ctx)
	if _, _, err = lockPair(ctx, tx, i.SenderID, i.RecipientID); err != nil {
		return Invitation{}, err
	}
	if _, err = requireFriends(ctx, tx, i.SenderID, i.RecipientID); err != nil {
		return Invitation{}, err
	}
	if err = lockInviteRoom(ctx, tx, i.RoomID, i.SenderID); err != nil {
		return Invitation{}, err
	}
	i, err = lockInvitation(ctx, tx, i)
	if err != nil {
		return Invitation{}, err
	}
	if i.Status != "accepted" {
		return Invitation{}, ErrInviteGone
	}
	var member bool
	if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM room_members WHERE room_id=$1 AND user_id=$2)`, i.RoomID, user).Scan(&member); err != nil {
		return Invitation{}, err
	}
	if !member {
		return Invitation{}, ErrForbidden
	}
	if i.JoinedAt == 0 {
		var joined time.Time
		err = tx.QueryRow(ctx, `UPDATE room_invites SET joined_at=now(),version=version+1 WHERE id=$1 RETURNING joined_at,version`, id).Scan(&joined, &i.Version)
		if err != nil {
			return Invitation{}, err
		}
		i.JoinedAt = joined.UnixMilli()
	}
	if err = tx.Commit(ctx); err != nil {
		return Invitation{}, err
	}
	return i, nil
}

func (s *Store) AddInvitationEnvelopes(ctx context.Context, user, id string, keyset int64, items []Envelope) (Invitation, error) {
	i, err := s.Invitation(ctx, user, id)
	if err != nil {
		return Invitation{}, err
	}
	if user != i.SenderID {
		return Invitation{}, ErrNotFound
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Invitation{}, err
	}
	defer tx.Rollback(ctx)
	if _, _, err = lockPair(ctx, tx, i.SenderID, i.RecipientID); err != nil {
		return Invitation{}, err
	}
	if _, err = requireFriends(ctx, tx, i.SenderID, i.RecipientID); err != nil {
		return Invitation{}, err
	}
	if err = lockInviteRoom(ctx, tx, i.RoomID, user); err != nil {
		return Invitation{}, err
	}
	i, err = lockInvitation(ctx, tx, i)
	if err != nil {
		return Invitation{}, err
	}
	if !activeInvitation(i) {
		return Invitation{}, ErrInviteGone
	}
	if err = validateEnvelopes(tx, ctx, i, keyset, items); err != nil {
		return Invitation{}, err
	}
	added := false
	for _, e := range items {
		var enc, ct, senderDevice, senderKey, suite string
		err = tx.QueryRow(ctx, `SELECT enc,ciphertext,sender_device_id,sender_key_id,suite FROM room_invite_envelopes WHERE invite_id=$1 AND device_id=$2 AND key_id=$3`, id, e.DeviceID, e.KeyID).Scan(&enc, &ct, &senderDevice, &senderKey, &suite)
		if err == nil {
			if enc != e.Enc || ct != e.Ciphertext || senderDevice != e.SenderDeviceID || senderKey != e.SenderKeyID || suite != e.Suite {
				return Invitation{}, ErrConflict
			}
			continue
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return Invitation{}, err
		}
		if err = insertEnvelope(ctx, tx, e); err != nil {
			return Invitation{}, err
		}
		added = true
	}
	if added {
		if _, err = tx.Exec(ctx, `UPDATE room_invites SET version=version+1 WHERE id=$1`, id); err != nil {
			return Invitation{}, err
		}
		i.Version++
	}
	if err = tx.Commit(ctx); err != nil {
		return Invitation{}, err
	}
	return i, nil
}

func revokePairInvitations(ctx context.Context, tx pgx.Tx, a, b string) error {
	_, err := tx.Exec(ctx, `UPDATE room_invites SET status='revoked',version=version+1,revoked_at=now()
 WHERE ((created_by=$1 AND recipient_id=$2) OR (created_by=$2 AND recipient_id=$1)) AND status IN('pending','accepted')`, a, b)
	return err
}
