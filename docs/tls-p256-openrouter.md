# TLS ECDSA P-256 interoperability closure

Status: delivered by D645-D649.

## Scope

Neper's checked TLS 1.3 client profile now interoperates with servers whose
certificate chain and `CertificateVerify` message use ECDSA over P-256 with
SHA-256. This is the profile served by OpenRouter at the time of the integration
probe. The change extends the existing Ed25519 profile; it does not replace it.

The delivered path is deliberately narrow:

- `e.crypto.sign.p256_verify` accepts an uncompressed SEC1 P-256 public key,
  hashes the message with SHA-256, and verifies a strict DER ECDSA signature;
- `e.crypto.x509` parses RFC 5480 P-256 subject keys and verifies
  `ecdsa-with-SHA256` certificate links;
- the TLS ClientHello advertises `ecdsa_secp256r1_sha256` (`0x0403`) beside
  Ed25519, and CertificateVerify dispatches by the server's selected scheme;
- compatibility ChangeCipherSpec records and handshake messages split across
  protected TLS records are accepted without weakening transcript validation;
- an unsupported certificate after an already trusted issuer is parsed but is
  not treated as an authoritative chain link.

## Evidence

| Decision | Focused evidence |
|---|---|
| D645 | RFC 6979 P-256/SHA-256 vector; changed key, message, and signature refusals in `link/crypto_sign` |
| D646 | Deterministic P-256 root and leaf parsing, link verification, hostname and trust checks in `link/crypto_x509` |
| D647 | ClientHello offer and P-256 CertificateVerify acceptance/refusal in `link/net_tls`; `neper info` capability |
| D648 | Compatibility-record and fragmented protected-handshake reassembly in `link/net_tls` |
| D649 | Supported P-256 anchor with an unused unsupported certificate suffix in `link/crypto_x509` |

The live `openrouter.ai` probe returned HTTP 200 on Windows and Linux when the
required WE1 trust root was supplied explicitly. This is interoperability
evidence, not an ambient-trust claim: Neper does not consult the host trust store.

## Explicit exclusions

P-256 private-key parsing and server signing are not in this profile. RSA,
P-384/SHA-384, client authentication, session resumption, and 0-RTT remain
unsupported. An unsupported chain element cannot authenticate a link, and
certificate or CertificateVerify verification is never bypassed.
