package social

import (
	"context"
	"errors"
	"strconv"
	"sync"
	"testing"
)

func friendConversation(t *testing.T, s *Store, a, b Person) Relationship {
	t.Helper()
	ctx := context.Background()
	r, err := s.RequestFriend(ctx, a.ID, b.FriendCode, "", "request-chat", 0)
	if err != nil {
		t.Fatal(err)
	}
	r, err = s.RelationshipAction(ctx, b.ID, r.ID, "accept", r.Version)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestMessagesDeduplicateAndReadCursor(t *testing.T) {
	s, p := socialStore(t)
	ctx := context.Background()
	a, b, c := p[0], p[1], p[2]
	r := friendConversation(t, s, a, b)
	id := r.ConversationID
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			m, _, err := s.SendMessage(ctx, a.ID, id, "same-message", "你好😀")
			if err != nil || m.Seq != 1 {
				t.Error("duplicate write", err)
			}
		}()
	}
	wg.Wait()
	if _, _, err := s.SendMessage(ctx, a.ID, id, "same-message", "different"); !errors.Is(err, ErrConflict) {
		t.Fatal("content replay accepted")
	}
	if _, err := s.Messages(ctx, c.ID, id, 0, 0, 50); !errors.Is(err, ErrNotFound) {
		t.Fatal("third party read messages")
	}
	if _, _, err := s.SendMessage(ctx, c.ID, id, "other", "hello"); !errors.Is(err, ErrNotFound) {
		t.Fatal("third party sent message")
	}
	if n, err := s.UnreadCount(ctx, a.ID); err != nil || n != 0 {
		t.Fatal("self message unread", err)
	}
	if n, err := s.UnreadCount(ctx, b.ID); err != nil || n != 1 {
		t.Fatal("wrong recipient unread", err)
	}
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, _, err := s.SendMessage(ctx, a.ID, id, "concurrent-"+strconv.Itoa(i), "message")
			if err != nil {
				t.Error(err)
			}
		}(i)
	}
	wg.Wait()
	messages, err := s.Messages(ctx, b.ID, id, 0, 1, 100)
	if err != nil || len(messages) != 6 {
		t.Fatal("catch-up lost messages", err)
	}
	for i, m := range messages {
		if m.Seq != int64(i+2) {
			t.Fatal("committed sequence has gap")
		}
	}
	if err := s.MarkRead(ctx, b.ID, id, 7); err != nil {
		t.Fatal(err)
	}
	if err := s.MarkRead(ctx, b.ID, id, 3); err != nil {
		t.Fatal(err)
	}
	convos, err := s.Conversations(ctx, b.ID, "", 20)
	if err != nil || len(convos) != 1 || convos[0].ReadSeq != 7 || convos[0].UnreadCount != 0 || convos[0].LastMessage.Seq != 7 {
		t.Fatal("cursor regressed or summary incorrect", err)
	}
	if err := s.MarkRead(ctx, c.ID, id, 7); !errors.Is(err, ErrNotFound) {
		t.Fatal("third party marked read")
	}
	if err := s.SetBlock(ctx, b.ID, a.ID, true); err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.SendMessage(ctx, a.ID, id, "blocked", "new"); !errors.Is(err, ErrForbidden) {
		t.Fatal("block bypassed")
	}
	if messages, err := s.Messages(ctx, b.ID, id, 0, 0, 50); err != nil || len(messages) != 7 {
		t.Fatal("history disappeared", err)
	}
	if _, _, err := s.SendMessage(ctx, a.ID, id, "same-message", "你好😀"); err != nil {
		t.Fatal("committed retry lost result", err)
	}
}

func TestMessageRollbackAndBlockRace(t *testing.T) {
	s, p := socialStore(t)
	ctx := context.Background()
	a, b := p[0], p[1]
	r := friendConversation(t, s, a, b)
	id := r.ConversationID
	// A database failure after allocation must roll back last_seq as well.
	_, err := s.db.Exec(ctx, `ALTER TABLE direct_messages ADD CONSTRAINT test_reject CHECK(body_text<>'rejected')`)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.SendMessage(ctx, a.ID, id, "rollback", "rejected"); err == nil {
		t.Fatal("forced failure missing")
	}
	m, _, err := s.SendMessage(ctx, a.ID, id, "first", "ok")
	if err != nil || m.Seq != 1 {
		t.Fatal("rollback left a gap", err)
	}
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		_, _, err := s.SendMessage(ctx, a.ID, id, "race", "hello")
		if err != nil && !errors.Is(err, ErrForbidden) {
			t.Error(err)
		}
	}()
	go func() {
		defer wg.Done()
		if err := s.SetBlock(ctx, b.ID, a.ID, true); err != nil {
			t.Error(err)
		}
	}()
	wg.Wait()
	if _, _, err := s.SendMessage(ctx, a.ID, id, "after-block", "hello"); !errors.Is(err, ErrForbidden) {
		t.Fatal("send after committed block allowed")
	}
}
