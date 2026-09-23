// Published single-shot Auth vector: RFC 9180 A.1.3.
const hpkeAuthVectorJson = r'''
{
  "source": "RFC 9180 A.1.3; cfrg/draft-irtf-cfrg-hpke/test-vectors.json",
  "mode": 2,
  "kem_id": 32,
  "kdf_id": 1,
  "aead_id": 1,
  "info": "4f6465206f6e2061204772656369616e2055726e",
  "skRm": "fdea67cf831f1ca98d8e27b1f6abeb5b7745e9d35348b80fa407ff6958f9137e",
  "skSm": "dc4a146313cce60a278a5323d321f051c5707e9c45ba21a3479fecdf76fc69dd",
  "skEm": "ff4442ef24fbc3c1ff86375b0be1e77e88a0de1e79b30896d73411c5ff4c3518",
  "pkRm": "1632d5c2f71c2b38d0a8fcc359355200caa8b1ffdf28618080466c909cb69b2e",
  "pkSm": "8b0c70873dc5aecb7f9ee4e62406a397b350e57012be45cf53b7105ae731790b",
  "enc": "23fb952571a14a25e3d678140cd0e5eb47a0961bb18afcf85896e5453c312e76",
  "encryption": {
    "aad": "436f756e742d30",
    "ct": "5fd92cc9d46dbf8943e72a07e42f363ed5f721212cd90bcfd072bfd9f44e06b80fd17824947496e21b680c141b",
    "nonce": "a1bc314c1942ade7051ffed0",
    "pt": "4265617574792069732074727574682c20747275746820626561757479"
  }
}
''';
