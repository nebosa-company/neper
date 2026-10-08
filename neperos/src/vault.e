// The Secure vault's cryptography (D2252, C116), with no I/O: a key from the master password, and records
// sealed under it. The key is PBKDF2-HMAC-SHA-256 over the password and a 16-byte salt, 32 bytes, with an
// iteration count the vault stores so it can rise without a new format; every record is AES-256-GCM with a
// fresh random 12-byte nonce, and its name (`meta`, `l3`, `c1` ...) as the additional data, so a record
// moved to another name fails to open. A record on disk is
//     version (1) | nonce (12) | ciphertext | tag (16)
// and the meta file is
//     version (1) | iterations (4, little end) | salt (16) | a record sealing a known phrase
// so the right password is the one that opens the phrase: a wrong one fails the tag, never yields garbage.
use e.mem
use e.crypto.kdf as kdf
use e.crypto.aead as aead

error WrongPassword
error Damaged
error TooSmall

const VERSION: u8 = 1u8
const SALT_BYTES: usize = 16usize
const NONCE_BYTES: usize = 12usize
const TAG_BYTES: usize = 16usize
const RECORD_OVERHEAD: usize = 29usize
const META_HEADER: usize = 21usize

// The phrase the meta record seals; opening it is how a password is checked.
fn phrase() -> str {
    ret "neper-vault-v1"
}

// The 32-byte key of `password` under `salt` after `iterations` rounds.
fn derive(password: []const u8, salt: []const u8, iterations: u32) -> ([32]u8, err) {
    var key: [32]u8 = zero
    let derived = kdf.pbkdf2_sha256(password, salt, iterations, key[0..])
    ret (key, derived)
}

fn nonce_from(bytes: []const u8) -> [12]u8 {
    var nonce: [12]u8 = zero
    var i = 0usize
    while i < NONCE_BYTES && i < bytes.len {
        nonce[i] = bytes[i]
        i += 1usize
    }
    ret nonce
}

// Seal `plain` into `out` as a record named `name`; the record's length. `nonce` must be fresh random bytes
// (the caller draws them: a nonce is never reused under one key).
fn seal(key: [32]u8, nonce: []const u8, name: str, plain: []const u8, out: []u8) -> (usize, err) {
    if out.len < plain.len + RECORD_OVERHEAD || nonce.len < NONCE_BYTES { ret (0usize, TooSmall) }
    out[0] = VERSION
    var i = 0usize
    while i < NONCE_BYTES {
        out[1usize + i] = nonce[i]
        i += 1usize
    }
    let (written, seal_error) = aead.aes256_gcm_seal(out[13usize..], key, nonce_from(nonce), name, plain)
    if seal_error != ok { ret (0usize, seal_error) }
    ret (13usize + written, ok)
}

// Open the record named `name` into `out`; the plaintext's length, `Damaged` for a record that is not one,
// `WrongPassword` when the tag does not match (a wrong key, a changed byte or a record under another name).
fn open(key: [32]u8, name: str, record: []const u8, out: []u8) -> (usize, err) {
    if record.len < RECORD_OVERHEAD || record[0] != VERSION { ret (0usize, Damaged) }
    let (written, open_error) = aead.aes256_gcm_open(out, key, nonce_from(record[1usize..13usize]), name, record[13usize..])
    if open_error != ok { ret (0usize, WrongPassword) }
    ret (written, ok)
}

// The meta file for a new vault: the stored iteration count and salt, and the sealed phrase. `out` needs 64 bytes.
fn meta_make(key: [32]u8, salt: []const u8, iterations: u32, nonce: []const u8, out: []u8) -> (usize, err) {
    if out.len < META_HEADER + RECORD_OVERHEAD + 14usize || salt.len < SALT_BYTES { ret (0usize, TooSmall) }
    out[0] = VERSION
    out[1] = u8(iterations & 255u32)
    out[2] = u8((iterations >> 8u32) & 255u32)
    out[3] = u8((iterations >> 16u32) & 255u32)
    out[4] = u8((iterations >> 24u32) & 255u32)
    var i = 0usize
    while i < SALT_BYTES {
        out[5usize + i] = salt[i]
        i += 1usize
    }
    let (written, seal_error) = seal(key, nonce, "meta", phrase(), out[META_HEADER..])
    if seal_error != ok { ret (0usize, seal_error) }
    ret (META_HEADER + written, ok)
}

// The iteration count a meta file stores, or zero for a file that is not one.
fn meta_iterations(meta: []const u8) -> u32 {
    if meta.len < META_HEADER + RECORD_OVERHEAD + 14usize || meta[0] != VERSION { ret 0u32 }
    ret u32(meta[1]) | (u32(meta[2]) << 8u32) | (u32(meta[3]) << 16u32) | (u32(meta[4]) << 24u32)
}

// The key `password` makes from a meta file's salt and count, if it opens the file's phrase.
fn meta_unlock(meta: []const u8, password: []const u8) -> ([32]u8, err) {
    var none: [32]u8 = zero
    let iterations = meta_iterations(meta)
    if iterations == 0u32 { ret (none, Damaged) }
    let (key, derive_error) = derive(password, meta[5usize..21usize], iterations)
    if derive_error != ok { ret (none, derive_error) }
    var plain: [32]u8 = zero
    let (n, open_error) = open(key, "meta", meta[META_HEADER..], plain[0..])
    if open_error != ok { ret (none, open_error) }
    var i = 0usize
    let expected = phrase()
    if n != expected.len { ret (none, Damaged) }
    while i < n {
        if plain[i] != expected[i] { ret (none, Damaged) }
        i += 1usize
    }
    ret (key, ok)
}
