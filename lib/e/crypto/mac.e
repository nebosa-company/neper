// HMAC by RFC 2104 over `e.crypto.hash`'s SHA-256 and SHA-512: a key longer than the
// block is hashed first, the key is padded to the block and XORed with 0x36 for the
// inner hash and 0x5c for the outer, and the tag is the outer hash of the inner
// digest. The streaming state is the two hash states; `done` consumes them, and a
// tag is verified in constant time.

use e.crypto.hash as hash

type HmacSha256 = struct { inner: hash.Sha256, outer: hash.Sha256 }
type HmacSha512 = struct { inner: hash.Sha512, outer: hash.Sha512 }

fn sha256_init(key: []const u8) -> HmacSha256 {
    var block: [64]u8 = zero
    if key.len > 64usize {
        let digest = hash.sha256(key)
        var at = 0usize
        while at < 32usize {
            block[at] = digest[at]
            at += 1usize
        }
    } else {
        var at = 0usize
        while at < key.len {
            block[at] = key[at]
            at += 1usize
        }
    }
    var s: HmacSha256 = zero
    s.inner = hash.sha256_init()
    s.outer = hash.sha256_init()
    var inner_pad: [64]u8 = zero
    var outer_pad: [64]u8 = zero
    var at = 0usize
    while at < 64usize {
        inner_pad[at] = block[at] ^ 54u8
        outer_pad[at] = block[at] ^ 92u8
        at += 1usize
    }
    hash.sha256_update(&s.inner, inner_pad[0..])
    hash.sha256_update(&s.outer, outer_pad[0..])
    ret s
}

fn sha256_update(state: *HmacSha256, bytes: []const u8) { hash.sha256_update(&state.inner, bytes) }

fn sha256_done(state: *HmacSha256) -> [32]u8 {
    let inner = hash.sha256_done(&state.inner)
    hash.sha256_update(&state.outer, inner[0..])
    ret hash.sha256_done(&state.outer)
}

fn hmac_sha256(key: []const u8, message: []const u8) -> [32]u8 {
    var s = sha256_init(key)
    sha256_update(&s, message)
    ret sha256_done(&s)
}

fn verify_sha256(key: []const u8, message: []const u8, tag: [32]u8) -> bool {
    let computed = hmac_sha256(key, message)
    ret hash.equal_constant_time(computed[0..], tag[0..])
}

fn sha512_init(key: []const u8) -> HmacSha512 {
    var block: [128]u8 = zero
    if key.len > 128usize {
        let digest = hash.sha512(key)
        var at = 0usize
        while at < 64usize {
            block[at] = digest[at]
            at += 1usize
        }
    } else {
        var at = 0usize
        while at < key.len {
            block[at] = key[at]
            at += 1usize
        }
    }
    var s: HmacSha512 = zero
    s.inner = hash.sha512_init()
    s.outer = hash.sha512_init()
    var inner_pad: [128]u8 = zero
    var outer_pad: [128]u8 = zero
    var at = 0usize
    while at < 128usize {
        inner_pad[at] = block[at] ^ 54u8
        outer_pad[at] = block[at] ^ 92u8
        at += 1usize
    }
    hash.sha512_update(&s.inner, inner_pad[0..])
    hash.sha512_update(&s.outer, outer_pad[0..])
    ret s
}

fn sha512_update(state: *HmacSha512, bytes: []const u8) { hash.sha512_update(&state.inner, bytes) }

fn sha512_done(state: *HmacSha512) -> [64]u8 {
    let inner = hash.sha512_done(&state.inner)
    hash.sha512_update(&state.outer, inner[0..])
    ret hash.sha512_done(&state.outer)
}

fn hmac_sha512(key: []const u8, message: []const u8) -> [64]u8 {
    var s = sha512_init(key)
    sha512_update(&s, message)
    ret sha512_done(&s)
}

fn verify_sha512(key: []const u8, message: []const u8, tag: [64]u8) -> bool {
    let computed = hmac_sha512(key, message)
    ret hash.equal_constant_time(computed[0..], tag[0..])
}
