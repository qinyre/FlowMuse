package social

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const relationshipQuery = `SELECT r.id, ` + personColumns + `, r.requester_id,r.request_client_id,r.state,r.version,r.request_message,COALESCE(c.id,''),r.updated_at
FROM social_relationships r
JOIN users u ON u.id=CASE WHEN r.user_low_id=$1 THEN r.user_high_id ELSE r.user_low_id END
LEFT JOIN direct_conversations c ON c.relationship_id=r.id
WHERE $1 IN (r.user_low_id,r.user_high_id)`

func scanRelationship(row pgx.Row) (Relationship, error) {
	var r Relationship
	var updated time.Time
	err := row.Scan(&r.ID, &r.Person.ID, &r.Person.DisplayName, &r.Person.AvatarURL, &r.Person.FriendCode, &r.RequesterID, &r.ClientRequestID, &r.State, &r.Version, &r.RequestMessage, &r.ConversationID, &updated)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrNotFound
	}
	r.UpdatedAt = updated.UnixMilli()
	return r, err
}

func (s *Store) Lookup(ctx context.Context, userID, code string) (Lookup, error) {
	code = normalizeCode(code)
	if !friendCodePattern.MatchString(code) {
		return Lookup{}, ErrInvalid
	}
	p, err := scanPerson(s.db.QueryRow(ctx, `SELECT `+personColumns+` FROM users u WHERE u.friend_code=$2 AND u.id<>$1
AND NOT EXISTS(SELECT 1 FROM social_blocks WHERE (blocker_id=$1 AND blocked_id=u.id) OR (blocker_id=u.id AND blocked_id=$1))`, userID, code))
	if err != nil {
		return Lookup{}, err
	}
	result := Lookup{Person: p}
	r, err := scanRelationship(s.db.QueryRow(ctx, relationshipQuery+` AND u.id=$2`, userID, p.ID))
	if err == nil {
		result.Relationship = &r
		result.Version = r.Version
	} else if !errors.Is(err, ErrNotFound) {
		return Lookup{}, err
	}
	return result, nil
}

func (s *Store) Relationships(ctx context.Context, userID, state, cursor string, limit int) ([]Relationship, error) {
	if state != "" && state != "accepted" && state != "pending" {
		return nil, ErrInvalid
	}
	rows, err := s.db.Query(ctx, relationshipQuery+` AND ($2='' OR r.state=$2) AND r.id>$3 ORDER BY r.id LIMIT $4`, userID, state, cursor, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []Relationship{}
	for rows.Next() {
		r, err := scanRelationship(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, r)
	}
	return result, rows.Err()
}

func (s *Store) RequestFriend(ctx context.Context, userID, code, message, clientID string, expected int64) (Relationship, error) {
	code = normalizeCode(code)
	message, err := normalizeText(message, 100, 400, true)
	if err != nil || !friendCodePattern.MatchString(code) || !safeID.MatchString(clientID) || expected < 0 {
		return Relationship{}, ErrInvalid
	}
	var other string
	err = s.db.QueryRow(ctx, `SELECT id FROM users WHERE friend_code=$1`, code).Scan(&other)
	if errors.Is(err, pgx.ErrNoRows) {
		return Relationship{}, ErrNotFound
	}
	if err != nil {
		return Relationship{}, err
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Relationship{}, err
	}
	defer tx.Rollback(ctx)
	low, high, err := lockPair(ctx, tx, userID, other)
	if err != nil {
		return Relationship{}, err
	}
	if yes, err := blocked(ctx, tx, low, high); err != nil {
		return Relationship{}, err
	} else if yes {
		return Relationship{}, ErrNotFound
	}
	var id, requester, currentClient, state, currentMessage string
	var version int64
	err = tx.QueryRow(ctx, `SELECT id,requester_id,request_client_id,state,version,request_message FROM social_relationships WHERE user_low_id=$1 AND user_high_id=$2 FOR UPDATE`, low, high).Scan(&id, &requester, &currentClient, &state, &version, &currentMessage)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return Relationship{}, err
	}
	if id != "" && requester == userID && currentClient == clientID {
		if currentMessage != message {
			return Relationship{}, ErrConflict
		}
		return finishRelationship(ctx, tx, userID, id)
	}
	if version != expected {
		return Relationship{}, ErrConflict
	}
	if state == "accepted" || state == "pending" {
		return finishRelationship(ctx, tx, userID, id)
	}
	if err := checkRelationLimit(ctx, tx, low, high, "pending", 50); err != nil {
		return Relationship{}, err
	}
	tag, err := tx.Exec(ctx, `UPDATE users SET social_request_day=CURRENT_DATE,
 social_requests_today=CASE WHEN social_request_day=CURRENT_DATE THEN social_requests_today+1 ELSE 1 END
 WHERE id=$1 AND (social_request_day IS DISTINCT FROM CURRENT_DATE OR social_requests_today<20)`, userID)
	if err != nil {
		return Relationship{}, err
	}
	if tag.RowsAffected() != 1 {
		return Relationship{}, ErrLimit
	}
	if id == "" {
		id = uuid.NewString()
		_, err = tx.Exec(ctx, `INSERT INTO social_relationships(id,user_low_id,user_high_id,requester_id,request_client_id,state,request_message) VALUES($1,$2,$3,$4,$5,'pending',$6)`, id, low, high, userID, clientID, message)
	} else {
		_, err = tx.Exec(ctx, `UPDATE social_relationships SET requester_id=$2,request_client_id=$3,request_message=$4,state='pending',version=version+1,updated_at=now() WHERE id=$1`, id, userID, clientID, message)
	}
	if isUniqueConflict(err) {
		return Relationship{}, ErrConflict
	}
	if err != nil {
		return Relationship{}, err
	}
	return finishRelationship(ctx, tx, userID, id)
}

func checkRelationLimit(ctx context.Context, tx pgx.Tx, a, b, state string, limit int) error {
	for _, id := range []string{a, b} {
		var count int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM social_relationships WHERE $1 IN (user_low_id,user_high_id) AND state=$2`, id, state).Scan(&count); err != nil {
			return err
		}
		if count >= limit {
			return ErrLimit
		}
	}
	return nil
}

func finishRelationship(ctx context.Context, tx pgx.Tx, userID, id string) (Relationship, error) {
	r, err := scanRelationship(tx.QueryRow(ctx, relationshipQuery+` AND r.id=$2`, userID, id))
	if err != nil {
		return Relationship{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Relationship{}, err
	}
	return r, nil
}

func (s *Store) RelationshipAction(ctx context.Context, userID, id, action string, expected int64) (Relationship, error) {
	target := map[string]string{"accept": "accepted", "decline": "declined", "cancel": "cancelled", "remove": "removed"}[action]
	if target == "" || !safeID.MatchString(id) || expected < 1 {
		return Relationship{}, ErrInvalid
	}
	var other string
	err := s.db.QueryRow(ctx, `SELECT CASE WHEN user_low_id=$1 THEN user_high_id ELSE user_low_id END FROM social_relationships WHERE id=$2 AND $1 IN (user_low_id,user_high_id)`, userID, id).Scan(&other)
	if errors.Is(err, pgx.ErrNoRows) {
		return Relationship{}, ErrNotFound
	}
	if err != nil {
		return Relationship{}, err
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Relationship{}, err
	}
	defer tx.Rollback(ctx)
	low, high, err := lockPair(ctx, tx, userID, other)
	if err != nil {
		return Relationship{}, err
	}
	var state, requester string
	var version int64
	if err := tx.QueryRow(ctx, `SELECT state,requester_id,version FROM social_relationships WHERE id=$1 FOR UPDATE`, id).Scan(&state, &requester, &version); err != nil {
		return Relationship{}, err
	}
	if (action == "accept" || action == "decline") && requester == userID || action == "cancel" && requester != userID {
		return Relationship{}, ErrForbidden
	}
	if state == target && version == expected+1 {
		return finishRelationship(ctx, tx, userID, id)
	}
	if version != expected {
		return Relationship{}, ErrConflict
	}
	if action == "remove" && state != "accepted" || action != "remove" && state != "pending" {
		return Relationship{}, ErrConflict
	}
	if yes, err := blocked(ctx, tx, low, high); err != nil {
		return Relationship{}, err
	} else if yes {
		return Relationship{}, ErrForbidden
	}
	if action == "accept" {
		if err := checkRelationLimit(ctx, tx, low, high, "accepted", 200); err != nil {
			return Relationship{}, err
		}
		_, err = tx.Exec(ctx, `INSERT INTO direct_conversations(id,relationship_id,user_low_id,user_high_id) VALUES($1,$2,$3,$4) ON CONFLICT(relationship_id) DO NOTHING`, uuid.NewString(), id, low, high)
		if err != nil {
			return Relationship{}, err
		}
	}
	_, err = tx.Exec(ctx, `UPDATE social_relationships SET state=$2,version=version+1,updated_at=now() WHERE id=$1`, id, target)
	if err != nil {
		return Relationship{}, err
	}
	if action == "remove" {
		if err = revokePairInvitations(ctx, tx, low, high); err != nil {
			return Relationship{}, err
		}
	}
	return finishRelationship(ctx, tx, userID, id)
}

func (s *Store) SetBlock(ctx context.Context, userID, other string, block bool) error {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	low, high, err := lockPair(ctx, tx, userID, other)
	if err != nil {
		return err
	}
	if block {
		var count int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM social_blocks WHERE blocker_id=$1 AND blocked_id<>$2`, userID, other).Scan(&count); err != nil {
			return err
		}
		if count >= 200 {
			return ErrLimit
		}
		_, err = tx.Exec(ctx, `INSERT INTO social_blocks(blocker_id,blocked_id) VALUES($1,$2) ON CONFLICT DO NOTHING`, userID, other)
		if err == nil {
			_, err = tx.Exec(ctx, `UPDATE social_relationships SET state='removed',version=version+1,updated_at=now() WHERE user_low_id=$1 AND user_high_id=$2 AND state IN ('pending','accepted')`, low, high)
		}
		if err == nil {
			err = revokePairInvitations(ctx, tx, low, high)
		}
	} else {
		_, err = tx.Exec(ctx, `DELETE FROM social_blocks WHERE blocker_id=$1 AND blocked_id=$2`, userID, other)
	}
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Store) Blocks(ctx context.Context, userID string) ([]Person, error) {
	rows, err := s.db.Query(ctx, `SELECT `+personColumns+` FROM social_blocks b JOIN users u ON u.id=b.blocked_id WHERE b.blocker_id=$1 ORDER BY b.created_at DESC LIMIT 200`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []Person{}
	for rows.Next() {
		p, err := scanPerson(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, p)
	}
	return result, rows.Err()
}
