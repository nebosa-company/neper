// Browser authentication over caller storage: PKCE for OAuth 2.0 (RFC 7636)
// and WebAuthn assertion verification (Web Authentication Level 2, section
// 7.2). `pkce_verifier` draws 43 to 128 unreserved characters from a caller
// `Pcg64`, `pkce_challenge` is `base64url(SHA-256(verifier))` without
// padding (the `S256` method), and `pkce` does both. `webauthn_verify` takes
// the assertion's `authenticatorData`, `clientDataJSON` and `signature`,
// checks the relying party id hash, the user-presence flag, the client data's
// type, challenge and origin, and verifies the signature over
// `authenticatorData || SHA-256(clientDataJSON)` with the credential's
// public key: ES256 (P-256 with SHA-256, a DER signature) or EdDSA (Ed25519).

use e.algo.rand
use e.bytes
use e.crypto.hash as hash
use e.crypto.sign as sign
use e.fmt.jwt as jwt
use e.mem
use e.str

type Key = union enum u8 { P256: sign.P256PublicKey, Ed25519: sign.Ed25519PublicKey }
type Assertion = struct { rp_id_hash: [32]u8, user_present: bool, user_verified: bool, sign_count: u32 }
error TooSmall
error Invalid
error Malformed
error BadRpId
error UserNotPresent
error BadClientData
error BadSignature

// The unreserved characters RFC 7636 allows: `[A-Za-z0-9-._~]`.
fn unreserved(index: u64) -> u8 {
    let table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    ret table[usize(index)]
}

// A code verifier filling `dst`, whose length must be 43 to 128; each
// character is one `pcg64_bounded(66)` draw.
fn pkce_verifier(rng: *rand.Pcg64, dst: []u8) -> (str, err) {
    if dst.len < 43usize || dst.len > 128usize { ret ("", Invalid) }
    var i = 0usize
    while i < dst.len {
        dst[i] = unreserved(rand.pcg64_bounded(rng, 66u64))
        i += 1usize
    }
    ret (dst, ok)
}

// The S256 challenge of a verifier: 43 characters into `dst`.
fn pkce_challenge(verifier: str, dst: []u8) -> (str, err) {
    if verifier.len < 43usize || verifier.len > 128usize { ret ("", Invalid) }
    let digest = hash.sha256(verifier)
    let (text, encode_error) = bytes.base64_encode(dst, digest[0..], .Url, false)
    if encode_error != ok { ret ("", TooSmall) }
    ret (text, ok)
}

// A fresh verifier into `verifier_dst` and its challenge into `challenge_dst`.
fn pkce(rng: *rand.Pcg64, verifier_dst: []u8, challenge_dst: []u8) -> (str, str, err) {
    let (verifier, verifier_error) = pkce_verifier(rng, verifier_dst)
    if verifier_error != ok { ret ("", "", verifier_error) }
    let (challenge, challenge_error) = pkce_challenge(verifier, challenge_dst)
    if challenge_error != ok { ret ("", "", challenge_error) }
    ret (verifier, challenge, ok)
}

// The fixed head of `authenticatorData`: rpIdHash (32), flags (1), signCount (4).
fn parse_authenticator_data(auth_data: []const u8) -> (Assertion, err) {
    if auth_data.len < 37usize { ret (zero, Malformed) }
    var a: Assertion = zero
    mem.copy[u8](a.rp_id_hash[0..], auth_data[..32usize])
    a.user_present = (auth_data[32usize] & 1u8) != 0u8
    a.user_verified = (auth_data[32usize] & 4u8) != 0u8
    a.sign_count = (u32(auth_data[33usize]) << 24u32) | (u32(auth_data[34usize]) << 16u32) | (u32(auth_data[35usize]) << 8u32) | u32(auth_data[36usize])
    ret (a, ok)
}

// The string member `name` of the client data object, or `BadClientData`.
fn client_string(client_data: str, name: str) -> (str, err) {
    let (raw, present, member_error) = jwt.member(client_data, name)
    if member_error != ok || !present { ret ("", BadClientData) }
    let (value, is_string) = jwt.string_of(raw)
    if !is_string { ret ("", BadClientData) }
    ret (value, ok)
}

// Verify an assertion: `challenge` is the base64url text the relying party
// issued (as it appears in the client data), `origin` the expected origin.
// `scratch` holds the signed message (`auth_data.len + 32` bytes). Answers
// the parsed authenticator data; the caller compares `sign_count` with the
// stored one.
fn webauthn_verify(auth_data: []const u8, client_data: []const u8, signature: []const u8, key: Key, rp_id: str, challenge: str, origin: str, scratch: []u8) -> (Assertion, err) {
    let (a, parse_error) = parse_authenticator_data(auth_data)
    if parse_error != ok { ret (zero, parse_error) }
    let expected_rp = hash.sha256(rp_id)
    if !hash.equal_constant_time(a.rp_id_hash[0..], expected_rp[0..]) { ret (a, BadRpId) }
    if !a.user_present { ret (a, UserNotPresent) }
    let (kind, kind_error) = client_string(client_data, "type")
    if kind_error != ok { ret (a, kind_error) }
    if !str.eq(kind, "webauthn.get") { ret (a, BadClientData) }
    let (got_challenge, challenge_error) = client_string(client_data, "challenge")
    if challenge_error != ok { ret (a, challenge_error) }
    if !str.eq(got_challenge, challenge) { ret (a, BadClientData) }
    let (got_origin, origin_error) = client_string(client_data, "origin")
    if origin_error != ok { ret (a, origin_error) }
    if !str.eq(got_origin, origin) { ret (a, BadClientData) }
    if scratch.len < auth_data.len + 32usize { ret (a, TooSmall) }
    mem.copy[u8](scratch[..auth_data.len], auth_data)
    let client_hash = hash.sha256(client_data)
    mem.copy[u8](scratch[auth_data.len..auth_data.len + 32usize], client_hash[0..])
    let message = scratch[..auth_data.len + 32usize]
    switch key {
    case .P256 as p256:
        if sign.p256_verify(p256, message, signature) { ret (a, ok) }
    case .Ed25519 as ed:
        if signature.len != 64usize { ret (a, BadSignature) }
        var sig: sign.Ed25519Signature = zero
        mem.copy[u8](sig.bytes[0..], signature)
        if sign.ed25519_verify(ed, message, sig) { ret (a, ok) }
    }
    ret (a, BadSignature)
}
