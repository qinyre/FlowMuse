package social

import (
	"context"
	"errors"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const messageColumns = `id,conversation_id,seq,sender_id,client_message_id,kind,body_text,created_at`

func scanMessage(row pgx.Row) (Message, error) {
	var m Message
	var created time.Time
	err := row.Scan(&m.ID, &m.ConversationID, &m.Seq, &m.SenderID, &m.ClientMessageID, &m.Kind, &m.Text, &created)
	m.CreatedAt = created.UnixMilli()
	return m, err
}

func (s *Store) UnreadCount(ctx context.Context, userID string) (int64, error) {
	var count int64
	err := s.db.QueryRow(ctx, `SELECT count(*) FROM direct_messages m JOIN direct_conversations c ON c.id=m.conversation_id
 WHERE $1 IN(c.user_low_id,c.user_high_id) AND m.sender_id<>$1 AND m.seq>CASE WHEN c.user_low_id=$1 THEN c.low_read_seq ELSE c.high_read_seq END`, userID).Scan(&count)
	return count, err
}

func (s *Store) Conversations(ctx context.Context, userID, cursor string, limit int) ([]Conversation, error) {
	rows, err := s.db.Query(ctx, `SELECT c.id,`+personColumns+`,
 r.state='accepted' AND NOT EXISTS(SELECT 1 FROM social_blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=u.id) OR (b.blocker_id=u.id AND b.blocked_id=$1)),
 c.last_seq,CASE WHEN c.user_low_id=$1 THEN c.low_read_seq ELSE c.high_read_seq END,
 (SELECT count(*) FROM direct_messages x WHERE x.conversation_id=c.id AND x.sender_id<>$1 AND x.seq>CASE WHEN c.user_low_id=$1 THEN c.low_read_seq ELSE c.high_read_seq END),c.updated_at,
 COALESCE(m.id,''),COALESCE(m.seq,0),COALESCE(m.sender_id,''),COALESCE(m.client_message_id,''),COALESCE(m.kind,''),COALESCE(m.body_text,''),m.created_at
 FROM direct_conversations c
 JOIN social_relationships r ON r.id=c.relationship_id
 JOIN users u ON u.id=CASE WHEN c.user_low_id=$1 THEN c.user_high_id ELSE c.user_low_id END
 LEFT JOIN direct_messages m ON m.conversation_id=c.id AND m.seq=c.last_seq
 WHERE $1 IN(c.user_low_id,c.user_high_id) AND c.id>$2 ORDER BY c.id LIMIT $3`, userID, cursor, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Conversation{}
	for rows.Next() {
		var c Conversation
		var m Message
		var updated time.Time
		var created *time.Time
		err := rows.Scan(&c.ID, &c.Person.ID, &c.Person.DisplayName, &c.Person.AvatarURL, &c.Person.FriendCode, &c.CanSend, &c.LastSeq, &c.ReadSeq, &c.UnreadCount, &updated, &m.ID, &m.Seq, &m.SenderID, &m.ClientMessageID, &m.Kind, &m.Text, &created)
		if err != nil {
			return nil, err
		}
		c.UpdatedAt = updated.UnixMilli()
		if created != nil {
			m.CreatedAt = created.UnixMilli()
			m.ConversationID = c.ID
			c.LastMessage = &m
		}
		items = append(items, c)
	}
	return items, rows.Err()
}

func (s *Store) conversationPeer(ctx context.Context, userID, id string) (string, error) {
	if !safeID.MatchString(id) {
		return "", ErrInvalid
	}
	var peer string
	err := s.db.QueryRow(ctx, `SELECT CASE WHEN user_low_id=$1 THEN user_high_id ELSE user_low_id END FROM direct_conversations WHERE id=$2 AND $1 IN(user_low_id,user_high_id)`, userID, id).Scan(&peer)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrNotFound
	}
	return peer, err
}

func (s *Store) Messages(ctx context.Context, userID, id string, before, after int64, limit int) ([]Message, error) {
	if before < 0 || after < 0 || before > 0 && after > 0 {
		return nil, ErrInvalid
	}
	if _, err := s.conversationPeer(ctx, userID, id); err != nil {
		return nil, err
	}
	query := `SELECT ` + messageColumns + ` FROM direct_messages WHERE conversation_id=$1`
	var rows pgx.Rows
	var err error
	if after > 0 {
		rows, err = s.db.Query(ctx, query+` AND seq>$2 ORDER BY seq LIMIT $3`, id, after, limit)
	} else {
		rows, err = s.db.Query(ctx, query+` AND ($2=0 OR seq<$2) ORDER BY seq DESC LIMIT $3`, id, before, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Message{}
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, m)
	}
	if after == 0 {
		slices.Reverse(items)
	}
	return items, rows.Err()
}

func (s *Store) SendMessage(ctx context.Context, userID, id, clientID, text string) (Message, string, error) {
	text, err := normalizeText(text, 2000, 8192, false)
	if err != nil || !safeID.MatchString(clientID) {
		return Message{}, "", ErrInvalid
	}
	peer, err := s.conversationPeer(ctx, userID, id)
	if err != nil {
		return Message{}, "", err
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Message{}, "", err
	}
	defer tx.Rollback(ctx)
	low, high, err := lockPair(ctx, tx, userID, peer)
	if err != nil {
		return Message{}, "", err
	}
	// The user lock also serializes the global (sender, client ID) constraint.
	existing, err := scanMessage(tx.QueryRow(ctx, `SELECT `+messageColumns+` FROM direct_messages WHERE sender_id=$1 AND client_message_id=$2`, userID, clientID))
	if err == nil {
		if existing.ConversationID != id || existing.Text != text {
			return Message{}, "", ErrConflict
		}
		return existing, peer, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Message{}, "", err
	}
	var state string
	if err := tx.QueryRow(ctx, `SELECT state FROM social_relationships WHERE user_low_id=$1 AND user_high_id=$2 FOR UPDATE`, low, high).Scan(&state); err != nil {
		return Message{}, "", err
	}
	if state != "accepted" {
		return Message{}, "", ErrForbidden
	}
	if yes, err := blocked(ctx, tx, low, high); err != nil {
		return Message{}, "", err
	} else if yes {
		return Message{}, "", ErrForbidden
	}
	var minute, burst int
	err = tx.QueryRow(ctx, `SELECT count(*),count(*) FILTER(WHERE created_at>now()-interval '10 seconds') FROM direct_messages WHERE sender_id=$1 AND created_at>now()-interval '1 minute'`, userID).Scan(&minute, &burst)
	if err != nil {
		return Message{}, "", err
	}
	if minute >= 60 || burst >= 10 {
		return Message{}, "", ErrLimit
	}
	var seq int64
	err = tx.QueryRow(ctx, `UPDATE direct_conversations SET last_seq=last_seq+1,updated_at=now() WHERE id=$1 RETURNING last_seq`, id).Scan(&seq)
	if err != nil {
		return Message{}, "", err
	}
	m, err := scanMessage(tx.QueryRow(ctx, `INSERT INTO direct_messages(id,conversation_id,seq,sender_id,client_message_id,body_text) VALUES($1,$2,$3,$4,$5,$6) RETURNING `+messageColumns, uuid.NewString(), id, seq, userID, clientID, text))
	if err != nil {
		return Message{}, "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return Message{}, "", err
	}
	return m, peer, nil
}

func (s *Store) MarkRead(ctx context.Context, userID, id string, through int64) error {
	if through < 0 || !safeID.MatchString(id) {
		return ErrInvalid
	}
	// A single UPDATE locks the conversation and keeps the account cursor monotonic.
	tag, err := s.db.Exec(ctx, `UPDATE direct_conversations SET
 low_read_seq=CASE WHEN user_low_id=$1 THEN GREATEST(low_read_seq,$3) ELSE low_read_seq END,
 high_read_seq=CASE WHEN user_high_id=$1 THEN GREATEST(high_read_seq,$3) ELSE high_read_seq END
 WHERE id=$2 AND $1 IN(user_low_id,user_high_id) AND $3<=last_seq`, userID, id, through)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
