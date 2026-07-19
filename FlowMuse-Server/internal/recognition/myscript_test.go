package recognition

import "testing"

func TestHMACSignatureSignsRequestBody(t *testing.T) {
	got := hmacSignature("app", "secret", []byte("hello"))
	const want = "01F9D74906D5AC3D38004370023C4F8BA9D5AF16C20698242EB913F8B8F7A376C23DE1328A1D7D3505EAA91A21A3347DACCDC1C12831C600E827FAE90FA3A2AE"
	if got != want {
		t.Fatalf("hmacSignature() = %s, want %s", got, want)
	}
}
