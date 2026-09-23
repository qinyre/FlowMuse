package social

import (
	"context"
	"errors"
	"strings"
	"testing"

	"flowmuse/server/internal/auth"
	"flowmuse/server/internal/storage"
	"flowmuse/server/internal/testutil"
	"github.com/jackc/pgx/v5/pgconn"
)

func socialStore(t *testing.T) (*Store, []Person) {
	t.Helper()
	db := testutil.Postgres(t)
	ctx := context.Background()
	users := auth.NewUserStore(db)
	if err := users.EnsureSchema(ctx); err != nil {
		t.Fatal(err)
	}
	rooms := storage.NewRoomStore(db)
	if err := rooms.EnsureSchema(ctx); err != nil {
		t.Fatal(err)
	}
	s := NewStore(db)
	people := []Person{}
	// Users exist before migration, exercising the login-version upgrade path.
	for _, name := range []string{"alice", "bob", "charlie"} {
		u, err := users.LoginHuawei(ctx, "test-"+name)
		if err != nil {
			t.Fatal(err)
		}
		people = append(people, Person{ID: u.ID})
	}
	for i := 0; i < 2; i++ {
		if err := s.EnsureSchema(ctx); err != nil {
			t.Fatal(err)
		}
	}
	for i, p := range people {
		var err error
		people[i], err = s.Me(ctx, p.ID)
		if err != nil {
			t.Fatal(err)
		}
	}
	return s, people
}

func TestSchemaAndFriendCodes(t *testing.T) {
	s, people := socialStore(t)
	ctx := context.Background()
	seen := map[string]bool{}
	for _, p := range people {
		if !friendCodePattern.MatchString(p.FriendCode) || seen[p.FriendCode] {
			t.Fatal("invalid or duplicate code")
		}
		seen[p.FriendCode] = true
		again, err := s.Me(ctx, p.ID)
		if err != nil || again.FriendCode != p.FriendCode {
			t.Fatal("code changed", err)
		}
	}
	_, err := s.db.Exec(ctx, `UPDATE users SET friend_code=$1 WHERE id=$2`, people[0].FriendCode, people[1].ID)
	var pgerr *pgconn.PgError
	if !errors.As(err, &pgerr) || pgerr.Code != "23505" {
		t.Fatal("code uniqueness missing")
	}
	_, err = s.db.Exec(ctx, `UPDATE users SET email='private@example.test',display_name='private@example.test' WHERE id=$1`, people[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	p, err := s.Me(ctx, people[0].ID)
	if err != nil || strings.Contains(p.DisplayName, "@") {
		t.Fatal("public projection exposed default email")
	}
}

func TestTextValidation(t *testing.T) {
	for _, value := range []string{"short," + strings.Repeat("b", 22), "https://example.test/%23room%3Dany%2Csecret"} {
		if _, err := normalizeText(value, 2000, 8192, false); err == nil {
			t.Fatal("room key accepted")
		}
	}
	for _, value := range []string{"", " \n ", strings.Repeat("字", 2001), "a\x00b", "#room=" + strings.Repeat("a", 20) + "," + strings.Repeat("b", 22)} {
		if _, err := normalizeText(value, 2000, 8192, false); err == nil {
			t.Fatal("invalid text accepted")
		}
	}
	if _, err := normalizeText(strings.Repeat("😀", 2000), 2000, 8192, false); err != nil {
		t.Fatal("valid Unicode rejected")
	}
}
