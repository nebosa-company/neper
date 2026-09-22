// HMAC by RFC 2104 over `e.crypto.hash`'s SHA-256 and SHA-512: a key longer than the
// block is hashed first, the key is padded to the block and XORed with 0x36 for the
// inner hash and 0x5c for the outer, and the tag is the outer hash of the inner
// digest. The streaming state is the two hash states; `done` consumes them, and a
// tag is verified in constant time.

use e.crypto.hash as hash
use e.crypto.aead as aead

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

// --- Poly1305 by RFC 8439 as a bare one-time authenticator, over the 26-bit limb
// arithmetic `e.crypto.aead` keeps for ChaCha20-Poly1305. The streaming state holds
// the last partial block, because the final block is padded differently from the
// full ones; `done` consumes the state. The key must never authenticate two messages.
type Poly1305 = struct { inner: aead.Poly, block: [16]u8, block_len: usize }

fn poly1305_init(key: [32]u8) -> Poly1305 {
    var s: Poly1305 = zero
    s.inner = aead.poly_init(key[0..])
    ret s
}

fn poly1305_update(state: *Poly1305, bytes: []const u8) {
    var at = 0usize
    if state.block_len > 0usize {
        while state.block_len < 16usize && at < bytes.len {
            state.block[state.block_len] = bytes[at]
            state.block_len += 1usize
            at += 1usize
        }
        if state.block_len < 16usize { ret }
        aead.poly_block(&state.inner, state.block[0..], false)
        state.block_len = 0usize
    }
    while at + 16usize <= bytes.len {
        aead.poly_block(&state.inner, bytes[at..at + 16usize], false)
        at += 16usize
    }
    while at < bytes.len {
        state.block[state.block_len] = bytes[at]
        state.block_len += 1usize
        at += 1usize
    }
}

fn poly1305_done(state: *Poly1305) -> [16]u8 {
    if state.block_len > 0usize { aead.poly_block(&state.inner, state.block[..state.block_len], true) }
    state.block_len = 0usize
    ret aead.poly_tag(&state.inner)
}

fn poly1305(key: [32]u8, message: []const u8) -> [16]u8 {
    var s = poly1305_init(key)
    poly1305_update(&s, message)
    ret poly1305_done(&s)
}

fn poly1305_verify(key: [32]u8, message: []const u8, tag: [16]u8) -> bool {
    let computed = poly1305(key, message)
    ret hash.equal_constant_time(computed[0..], tag[0..])
}
