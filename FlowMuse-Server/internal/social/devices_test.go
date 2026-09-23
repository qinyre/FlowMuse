package social

import (
	"context"
	"crypto/ecdh"
	"encoding/base64"
	"errors"
	"fmt"
	"testing"
)

func testDevice(id string, seed byte) Device {
	bytes := make([]byte, 32)
	bytes[0] = seed
	key, _ := ecdh.X25519().NewPrivateKey(bytes)
	return Device{ID: id, KeyID: "key-" + id, PublicKey: base64.RawURLEncoding.EncodeToString(key.PublicKey().Bytes()), Label: "测试设备"}
}

func TestDeviceRegistrationIsolationAndRevocation(t *testing.T) {
	s, p := socialStore(t)
	ctx := context.Background()
	d, err := s.RegisterDevice(ctx, p[0].ID, testDevice("alice-device", 19))
	if err != nil {
		t.Fatal(err)
	}
	if d.UserID != p[0].ID || len(d.Fingerprint) != 64 {
		t.Fatal("invalid public device projection")
	}
	for i := 0; i < 2; i++ {
		if _, err = s.RegisterDevice(ctx, p[0].ID, d); err != nil {
			t.Fatal("retry failed", err)
		}
	}
	own, err := s.Devices(ctx, p[0].ID, p[0].ID)
	if err != nil || own.Version != 1 || len(own.Items) != 1 {
		t.Fatal("registration not idempotent", err)
	}
	changed := d
	changed.PublicKey = testDevice("another", 35).PublicKey
	if _, err = s.RegisterDevice(ctx, p[0].ID, changed); !errors.Is(err, ErrConflict) {
		t.Fatal("key replacement accepted")
	}
	if _, err = s.RegisterDevice(ctx, p[1].ID, d); !errors.Is(err, ErrConflict) {
		t.Fatal("device ownership changed")
	}
	if _, err = s.Devices(ctx, p[1].ID, p[0].ID); !errors.Is(err, ErrForbidden) {
		t.Fatal("stranger read devices")
	}
	if err = s.RevokeDevice(ctx, p[1].ID, d.ID); !errors.Is(err, ErrNotFound) {
		t.Fatal("stranger revoked device")
	}
	friendConversation(t, s, p[0], p[1])
	if got, err := s.Devices(ctx, p[1].ID, p[0].ID); err != nil || len(got.Items) != 1 {
		t.Fatal("friend cannot read devices", err)
	}
	for i := 0; i < 2; i++ {
		if err = s.RevokeDevice(ctx, p[0].ID, d.ID); err != nil {
			t.Fatal(err)
		}
	}
	own, err = s.Devices(ctx, p[0].ID, p[0].ID)
	if err != nil || own.Version != 2 || own.Items[0].RevokedAt == 0 {
		t.Fatal("revocation version", err)
	}
	if got, err := s.Devices(ctx, p[1].ID, p[0].ID); err != nil || len(got.Items) != 0 {
		t.Fatal("revoked device visible to peer", err)
	}
	if _, err = s.RegisterDevice(ctx, p[0].ID, d); !errors.Is(err, ErrConflict) {
		t.Fatal("revoked key resurrected")
	}
}

func TestDeviceInvalidKeysAndLimit(t *testing.T) {
	s, p := socialStore(t)
	ctx := context.Background()
	invalid := testDevice("bad", 1)
	invalid.PublicKey = base64.RawURLEncoding.EncodeToString(make([]byte, 32))
	if _, err := s.RegisterDevice(ctx, p[0].ID, invalid); !errors.Is(err, ErrInvalid) {
		t.Fatal("zero point accepted")
	}
	for i := 0; i < 5; i++ {
		if _, err := s.RegisterDevice(ctx, p[0].ID, testDevice(fmt.Sprint("d", i), byte(20+i*8))); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := s.RegisterDevice(ctx, p[0].ID, testDevice("overflow", 63)); !errors.Is(err, ErrLimit) {
		t.Fatal("device limit missing")
	}
}
