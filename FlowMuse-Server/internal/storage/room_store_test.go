package storage

import "testing"

func TestOwnerKeyHashesEqual(t *testing.T) {
	hash := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

	if !ownerKeyHashesEqual(hash, hash) {
		t.Fatal("matching owner key hashes were rejected")
	}
	if ownerKeyHashesEqual(hash, hash[:63]+"0") {
		t.Fatal("different owner key hashes were accepted")
	}
	if ownerKeyHashesEqual(hash, "") {
		t.Fatal("empty owner key hash was accepted")
	}
}
