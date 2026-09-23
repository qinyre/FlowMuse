// Independent test harness only. CIRCL is not linked into the FlowMuse server.
package main

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"github.com/cloudflare/circl/hpke"
	"os"
)

type vector struct {
	SenderPrivate    []byte `json:"senderPrivate"`
	RecipientPrivate []byte `json:"recipientPrivate"`
	Info             []byte `json:"info"`
	AAD              []byte `json:"aad"`
	Plaintext        []byte `json:"plaintext"`
	Enc              []byte `json:"enc"`
	Ciphertext       []byte `json:"ciphertext"`
}

func must(err error) {
	if err != nil {
		panic("HPKE interop failed (no fixture output)")
	}
}
func main() {
	if len(os.Args) != 3 {
		panic("Use INPUT OUTPUT")
	}
	data, err := os.ReadFile(os.Args[1])
	must(err)
	var vectors []vector
	must(json.Unmarshal(data, &vectors))
	if len(vectors) != 16 {
		panic("Unexpected vector count")
	}
	suite := hpke.NewSuite(hpke.KEM_X25519_HKDF_SHA256, hpke.KDF_HKDF_SHA256, hpke.AEAD_AES128GCM)
	scheme := hpke.KEM_X25519_HKDF_SHA256.Scheme()
	for i, v := range vectors {
		a, err := scheme.UnmarshalBinaryPrivateKey(v.SenderPrivate)
		must(err)
		b, err := scheme.UnmarshalBinaryPrivateKey(v.RecipientPrivate)
		must(err)
		r, err := suite.NewReceiver(b, v.Info)
		must(err)
		opener, err := r.SetupAuth(v.Enc, a.Public())
		must(err)
		plain, err := opener.Open(v.Ciphertext, v.AAD)
		must(err)
		if !bytes.Equal(plain, v.Plaintext) {
			panic("Dart -> CIRCL mismatch")
		}
		s, err := suite.NewSender(b.Public(), v.Info)
		must(err)
		enc, sealer, err := s.SetupAuth(rand.Reader, a)
		must(err)
		ciphertext, err := sealer.Seal(v.Plaintext, v.AAD)
		must(err)
		vectors[i].Enc = enc
		vectors[i].Ciphertext = ciphertext
	}
	output, err := json.Marshal(vectors)
	must(err)
	must(os.WriteFile(os.Args[2], output, 0600))
	fmt.Println("Dart -> CIRCL: 16 Auth vectors passed")
}
