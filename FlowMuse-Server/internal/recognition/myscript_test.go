package recognition

import "testing"

func TestHMACSignatureSignsRequestBody(t *testing.T) {
	got := hmacSignature("app", "secret", []byte("hello"))
	const want = "01f9d74906d5ac3d38004370023c4f8ba9d5af16c20698242eb913f8b8f7a376c23de1328a1d7d3505eaa91a21a3347daccdc1c12831c600e827fae90fa3a2ae"
	if got != want {
		t.Fatalf("hmacSignature() = %s, want %s", got, want)
	}
}
