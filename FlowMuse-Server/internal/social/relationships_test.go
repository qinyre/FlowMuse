package social

import (
	"context"
	"errors"
	"sync"
	"testing"
)

func TestFriendLifecycleAndReplay(t *testing.T) {
	s, p := socialStore(t)
	ctx := context.Background()
	a, b, c := p[0], p[1], p[2]
	if _, err := s.RequestFriend(ctx, a.ID, a.FriendCode, "", "self", 0); !errors.Is(err, ErrInvalid) {
		t.Fatal("self accepted")
	}
	r, err := s.RequestFriend(ctx, a.ID, b.FriendCode, "你好", "request-1", 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.RelationshipAction(ctx, c.ID, r.ID, "accept", 1); !errors.Is(err, ErrNotFound) {
		t.Fatal("third party accepted")
	}
	if _, err := s.RelationshipAction(ctx, a.ID, r.ID, "accept", 1); !errors.Is(err, ErrForbidden) {
		t.Fatal("sender accepted own request")
	}
	if _, err := s.RequestFriend(ctx, a.ID, b.FriendCode, "changed", "request-1", 0); !errors.Is(err, ErrConflict) {
		t.Fatal("replay changed text")
	}
	mutual, err := s.RequestFriend(ctx, b.ID, a.FriendCode, "你好", "reverse", 1)
	if err != nil || mutual.State != "pending" || mutual.RequesterID != a.ID {
		t.Fatal("mutual request auto accepted", err)
	}
	r, err = s.RelationshipAction(ctx, b.ID, r.ID, "accept", 1)
	if err != nil || r.ConversationID == "" {
		t.Fatal("accept failed", err)
	}
	conversation := r.ConversationID
	if _, err := s.RelationshipAction(ctx, b.ID, r.ID, "accept", 1); err != nil {
		t.Fatal("retry accept", err)
	}
	r, err = s.RelationshipAction(ctx, a.ID, r.ID, "remove", r.Version)
	if err != nil {
		t.Fatal(err)
	}
	retry, err := s.RequestFriend(ctx, a.ID, b.FriendCode, "你好", "request-1", 0)
	if err != nil || retry.State != "removed" {
		t.Fatal("retry resurrected friendship", err)
	}
	r, err = s.RequestFriend(ctx, a.ID, b.FriendCode, "再加", "request-2", r.Version)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.RequestFriend(ctx, a.ID, b.FriendCode, "你好", "request-1", 0); !errors.Is(err, ErrConflict) {
		t.Fatal("old generation accepted")
	}
	r, err = s.RelationshipAction(ctx, b.ID, r.ID, "accept", r.Version)
	if err != nil || r.ConversationID != conversation {
		t.Fatal("conversation was replaced", err)
	}
	if err := s.SetBlock(ctx, b.ID, a.ID, true); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Lookup(ctx, a.ID, b.FriendCode); !errors.Is(err, ErrNotFound) {
		t.Fatal("blocked lookup visible")
	}
	if _, err := s.RequestFriend(ctx, a.ID, b.FriendCode, "", "request-3", r.Version+1); !errors.Is(err, ErrNotFound) {
		t.Fatal("block bypassed")
	}
	if err := s.SetBlock(ctx, b.ID, a.ID, false); err != nil {
		t.Fatal(err)
	}
	got, err := s.Lookup(ctx, a.ID, b.FriendCode)
	if err != nil || got.Relationship.State != "removed" {
		t.Fatal("unblock restored friendship", err)
	}
}

func TestConcurrentFriendRequestsAndBlocks(t *testing.T) {
	s, p := socialStore(t)
	ctx := context.Background()
	a, b := p[0], p[1]
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := s.RequestFriend(ctx, a.ID, b.FriendCode, "", "same-request", 0)
			if err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	lookup, err := s.Lookup(ctx, b.ID, a.FriendCode)
	if err != nil {
		t.Fatal(err)
	}
	r := lookup.Relationship
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := s.RelationshipAction(ctx, b.ID, r.ID, "accept", r.Version)
			if err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	var count int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM direct_conversations`).Scan(&count); err != nil || count != 1 {
		t.Fatal("duplicate conversation", err)
	}
	// Blocking also serializes when no relationship row exists yet.
	other := p[2]
	wg.Add(2)
	go func() {
		defer wg.Done()
		_, err := s.RequestFriend(ctx, a.ID, other.FriendCode, "", "race-block", 0)
		if err != nil && !errors.Is(err, ErrNotFound) {
			t.Error(err)
		}
	}()
	go func() {
		defer wg.Done()
		if err := s.SetBlock(ctx, other.ID, a.ID, true); err != nil {
			t.Error(err)
		}
	}()
	wg.Wait()
	if _, err := s.Lookup(ctx, a.ID, other.FriendCode); !errors.Is(err, ErrNotFound) {
		t.Fatal("block race leaked relation")
	}
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM social_relationships WHERE $1 IN(user_low_id,user_high_id) AND state IN('pending','accepted')`, other.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("active relationship survived block", err)
	}
}
