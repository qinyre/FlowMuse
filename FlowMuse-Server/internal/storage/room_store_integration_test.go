package storage_test

import (
	"context"
	"errors"
	"testing"

	"flowmuse/server/internal/auth"
	"flowmuse/server/internal/storage"
	"flowmuse/server/internal/testutil"
	"github.com/jackc/pgx/v5"
)

func TestRoomCreationPreservesRealOwner(t *testing.T) {
	db := testutil.Postgres(t)
	ctx := context.Background()
	users := auth.NewUserStore(db)
	if err := users.EnsureSchema(ctx); err != nil {
		t.Fatal(err)
	}
	a, err := users.LoginHuawei(ctx, "test-owner-a")
	if err != nil {
		t.Fatal(err)
	}
	b, err := users.LoginHuawei(ctx, "test-owner-b")
	if err != nil {
		t.Fatal(err)
	}
	rooms := storage.NewRoomStore(db)
	if err := rooms.EnsureSchema(ctx); err != nil {
		t.Fatal(err)
	}
	first, err := rooms.CreateRoom(ctx, "room-test", a.ID, "test-owner-hash")
	if err != nil {
		t.Fatal(err)
	}
	for _, caller := range []string{a.ID, b.ID, ""} {
		got, err := rooms.CreateRoom(ctx, "room-test", caller, "different-test-hash")
		if err != nil || got.OwnerID != a.ID || got.OwnerKeyHash != first.OwnerKeyHash || got.CreatedAt != first.CreatedAt {
			t.Fatal("room ownership changed", err)
		}
		if (got.MemberRole == "owner") != (caller == a.ID) {
			t.Fatal("caller gained owner role")
		}
	}
	if err := rooms.UpsertMember(ctx, "room-test", b.ID, "owner"); err != nil {
		t.Fatal(err)
	}
	got, _ := rooms.FindRoom(ctx, "room-test", b.ID)
	if got.MemberRole != "editor" {
		t.Fatal("member can forge owner role")
	}
	if _, err := rooms.EndRoom(ctx, "room-test", b.ID, "different-test-hash"); !errors.Is(err, storage.ErrRoomAccessDenied) {
		t.Fatal("non-owner ended room")
	}
	if _, err := rooms.FindRoom(ctx, "missing", a.ID); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatal("missing room treated as existing")
	}
	if _, err := rooms.CreateRoom(ctx, "guest-room", "", ""); err != nil {
		t.Fatal(err)
	}
	got, err = rooms.CreateRoom(ctx, "guest-room", b.ID, "new-test-hash")
	if err != nil || got.OwnerID != "" || got.OwnerKeyHash != "" {
		t.Fatal("guest room claimed by retry")
	}
	if _, err := rooms.EndRoom(ctx, "room-test", a.ID, ""); err != nil {
		t.Fatal(err)
	}
	got, err = rooms.CreateRoom(ctx, "room-test", a.ID, first.OwnerKeyHash)
	if err != nil || !got.Ended {
		t.Fatal("retry reopened ended room")
	}
}
