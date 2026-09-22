// The Noise Protocol Framework (revision 34) instantiated as 25519_ChaChaPoly_BLAKE2s,
// with the IK handshake (`<- s` / `-> e, es, s, ss` / `<- e, ee, se`) and its IKpsk2
// modifier -- the pair WireGuard runs. BLAKE2s (RFC 7693) lives here because
// `e.crypto.hash` has none; Noise's HKDF is HMAC-BLAKE2s chained two or three times.
// Every state is a plain record in caller storage; ephemerals are supplied by the
// caller so a handshake is deterministic under test.
//
// The handshake state machine is fixed to IK: `step` 0 is message 1 (initiator writes),
// 1 is message 2 (responder writes), 2 is finished and `split` may be called. `psk`
// present turns IK into IKpsk2: each `e` token also mixes the ephemeral into the
// chaining key and the psk is mixed after `se`.
//
// ponytail: only IK/IKpsk2 -- a token interpreter over the other patterns (XX, NN,
// KK...) is the upgrade if a second pattern is ever needed.
// ponytail: WireGuard's outer framing (MAC1/MAC2 over the responder's static, TAI64N
// timestamps, the construction and identifier strings, the cookie reply) is not here;
// a WireGuard module would build it over `initialize`/`write_message`/`read_message`.

use e.crypto.aead as aead
use e.crypto.hash as hash
use e.crypto.kx as kx

error Invalid
error TooSmall
error Authentication

// --- BLAKE2s.

type Blake2s = struct { h: [8]u32, t: u64, block: [64]u8, block_len: usize, out_len: usize }
type Hkdf = struct { a: [32]u8, b: [32]u8, c: [32]u8 }

fn iv(i: usize) -> u32 {
    let table: [8]u32 = [8]u32{ 1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225 }
    ret table[i]
}

fn sigma(round: usize, i: usize) -> usize {
    let table: [160]u8 = [160]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3, 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4, 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8, 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13, 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9, 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11, 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10, 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5, 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0 }
    ret usize(table[round * 16usize + i])
}

fn load_le32(bytes: []const u8, at: usize) -> u32 {
    let low = u32(bytes[at]) | (u32(bytes[at + 1usize]) << 8u32)
    ret low | (u32(bytes[at + 2usize]) << 16u32) | (u32(bytes[at + 3usize]) << 24u32)
}

fn rotr(x: u32, n: u32) -> u32 { ret (x >> n) | (x << (32u32 - n)) }

fn g(v: []u32, a: usize, b: usize, c: usize, d: usize, x: u32, y: u32) {
    v[a] = v[a] +% v[b] +% x
    v[d] = rotr(v[d] ^ v[a], 16u32)
    v[c] = v[c] +% v[d]
    v[b] = rotr(v[b] ^ v[c], 12u32)
    v[a] = v[a] +% v[b] +% y
    v[d] = rotr(v[d] ^ v[a], 8u32)
    v[c] = v[c] +% v[d]
    v[b] = rotr(v[b] ^ v[c], 7u32)
}

fn compress(s: *Blake2s, last: bool) {
    var m: [16]u32 = zero
    var i = 0usize
    while i < 16usize {
        m[i] = load_le32(s.block[0..], i * 4usize)
        i += 1usize
    }
    var v: [16]u32 = zero
    i = 0usize
    while i < 8usize {
        v[i] = s.h[i]
        v[i + 8usize] = iv(i)
        i += 1usize
    }
    v[12] = v[12] ^ u32(s.t & 4294967295u64)
    v[13] = v[13] ^ u32(s.t >> 32u32)
    if last { v[14] = ~v[14] }
    var round = 0usize
    while round < 10usize {
        g(v[0..], 0usize, 4usize, 8usize, 12usize, m[sigma(round, 0usize)], m[sigma(round, 1usize)])
        g(v[0..], 1usize, 5usize, 9usize, 13usize, m[sigma(round, 2usize)], m[sigma(round, 3usize)])
        g(v[0..], 2usize, 6usize, 10usize, 14usize, m[sigma(round, 4usize)], m[sigma(round, 5usize)])
        g(v[0..], 3usize, 7usize, 11usize, 15usize, m[sigma(round, 6usize)], m[sigma(round, 7usize)])
        g(v[0..], 0usize, 5usize, 10usize, 15usize, m[sigma(round, 8usize)], m[sigma(round, 9usize)])
        g(v[0..], 1usize, 6usize, 11usize, 12usize, m[sigma(round, 10usize)], m[sigma(round, 11usize)])
        g(v[0..], 2usize, 7usize, 8usize, 13usize, m[sigma(round, 12usize)], m[sigma(round, 13usize)])
        g(v[0..], 3usize, 4usize, 9usize, 14usize, m[sigma(round, 14usize)], m[sigma(round, 15usize)])
        round += 1usize
    }
    i = 0usize
    while i < 8usize {
        s.h[i] = s.h[i] ^ v[i] ^ v[i + 8usize]
        i += 1usize
    }
}

// A BLAKE2s state for `out_len` bytes (1..32) of digest; a non-empty `key` (at most 32
// bytes) makes the keyed variant, which is BLAKE2s's own MAC.
fn blake2s_init(out_len: usize, key: []const u8) -> Blake2s {
    var s: Blake2s = zero
    var i = 0usize
    while i < 8usize {
        s.h[i] = iv(i)
        i += 1usize
    }
    s.h[0] = s.h[0] ^ 16842752u32 ^ u32(out_len & 255usize) ^ (u32(key.len & 255usize) << 8u32)
    s.out_len = out_len
    if key.len > 0usize {
        var padded: [64]u8 = zero
        i = 0usize
        while i < key.len {
            padded[i] = key[i]
            i += 1usize
        }
        blake2s_update(&s, padded[0..])
    }
    ret s
}

fn blake2s_update(s: *Blake2s, bytes: []const u8) {
    var i = 0usize
    while i < bytes.len {
        if s.block_len == 64usize {
            s.t += 64u64
            compress(s, false)
            s.block_len = 0usize
        }
        s.block[s.block_len] = bytes[i]
        s.block_len += 1usize
        i += 1usize
    }
}

// The digest in the first `out_len` bytes of the answer; the state is spent.
fn blake2s_done(s: *Blake2s) -> [32]u8 {
    s.t += u64(s.block_len)
    while s.block_len < 64usize {
        s.block[s.block_len] = 0u8
        s.block_len += 1usize
    }
    compress(s, true)
    var out: [32]u8 = zero
    var i = 0usize
    while i < s.out_len {
        let word = s.h[i / 4usize] >> u32((i % 4usize) * 8usize)
        out[i] = u8(word & 255u32)
        i += 1usize
    }
    ret out
}

fn blake2s(data: []const u8) -> [32]u8 {
    var s = blake2s_new()
    blake2s_update(&s, data)
    ret blake2s_done(&s)
}

fn blake2s_keyed(key: []const u8, data: []const u8) -> [32]u8 {
    var s = blake2s_init(32usize, key)
    blake2s_update(&s, data)
    ret blake2s_done(&s)
}

fn blake2s_new() -> Blake2s {
    let none: [0]u8 = zero
    ret blake2s_init(32usize, none[0..])
}

fn zero_key() -> [32]u8 {
    let k: [32]u8 = zero
    ret k
}

// HMAC-BLAKE2s (RFC 2104 with a 64-byte block); a key longer than the block is hashed.
fn hmac_blake2s(key: []const u8, data: []const u8) -> [32]u8 {
    var k: [64]u8 = zero
    var i = 0usize
    if key.len > 64usize {
        let digest = blake2s(key)
        while i < 32usize {
            k[i] = digest[i]
            i += 1usize
        }
    } else {
        while i < key.len {
            k[i] = key[i]
            i += 1usize
        }
    }
    var pad: [64]u8 = zero
    i = 0usize
    while i < 64usize {
        pad[i] = k[i] ^ 54u8
        i += 1usize
    }
    var inner = blake2s_new()
    blake2s_update(&inner, pad[0..])
    blake2s_update(&inner, data)
    let inner_digest = blake2s_done(&inner)
    i = 0usize
    while i < 64usize {
        pad[i] = k[i] ^ 92u8
        i += 1usize
    }
    var outer = blake2s_new()
    blake2s_update(&outer, pad[0..])
    blake2s_update(&outer, inner_digest[0..])
    ret blake2s_done(&outer)
}

// Noise HKDF: temp = HMAC(ck, ikm); a = HMAC(temp, 1); b = HMAC(temp, a || 2); c = HMAC(temp, b || 3).
fn hkdf3(chaining_key: [32]u8, input_key_material: []const u8) -> Hkdf {
    let temp = hmac_blake2s(chaining_key[0..], input_key_material)
    var out: Hkdf = zero
    var buffer: [33]u8 = zero
    buffer[0] = 1u8
    out.a = hmac_blake2s(temp[0..], buffer[..1usize])
    var i = 0usize
    while i < 32usize {
        buffer[i] = out.a[i]
        i += 1usize
    }
    buffer[32] = 2u8
    out.b = hmac_blake2s(temp[0..], buffer[0..])
    i = 0usize
    while i < 32usize {
        buffer[i] = out.b[i]
        i += 1usize
    }
    buffer[32] = 3u8
    out.c = hmac_blake2s(temp[0..], buffer[0..])
    ret out
}

// The two-output form; `c` is left zero.
fn hkdf2(chaining_key: [32]u8, input_key_material: []const u8) -> Hkdf {
    var out = hkdf3(chaining_key, input_key_material)
    out.c = zero_key()
    ret out
}

// --- CipherState.

type CipherState = struct { k: [32]u8, n: u64, has_key: bool }

fn cipher_state(k: [32]u8) -> CipherState {
    ret CipherState { k: k, n: 0u64, has_key: true }
}

fn nonce_bytes(n: u64) -> [12]u8 {
    var nonce: [12]u8 = zero
    var i = 0usize
    while i < 8usize {
        nonce[4usize + i] = u8((n >> u32(i * 8usize)) & 255u64)
        i += 1usize
    }
    ret nonce
}

// ChaCha20-Poly1305 under the state's key and nonce `n`, which then advances; without a
// key the plaintext is copied through. The nonce 2^64 - 1 is reserved: `Invalid`.
fn encrypt_with_ad(cs: *CipherState, ad: []const u8, plain: []const u8, out: []u8) -> (usize, err) {
    if !cs.has_key {
        if out.len < plain.len { ret (0usize, TooSmall) }
        copy(out, plain)
        ret (plain.len, ok)
    }
    if cs.n == 18446744073709551615u64 { ret (0usize, Invalid) }
    let (written, seal_error) = aead.chacha20_poly1305_seal(out, cs.k, nonce_bytes(cs.n), ad, plain)
    if seal_error == aead.TooSmall { ret (0usize, TooSmall) }
    if seal_error != ok { ret (0usize, Invalid) }
    cs.n += 1u64
    ret (written, ok)
}

// The inverse; a failed tag is `Authentication` and leaves the nonce unmoved.
fn decrypt_with_ad(cs: *CipherState, ad: []const u8, sealed: []const u8, out: []u8) -> (usize, err) {
    if !cs.has_key {
        if out.len < sealed.len { ret (0usize, TooSmall) }
        copy(out, sealed)
        ret (sealed.len, ok)
    }
    if cs.n == 18446744073709551615u64 { ret (0usize, Invalid) }
    let (written, open_error) = aead.chacha20_poly1305_open(out, cs.k, nonce_bytes(cs.n), ad, sealed)
    if open_error == aead.TooSmall { ret (0usize, TooSmall) }
    if open_error == aead.Authentication { ret (0usize, Authentication) }
    if open_error != ok { ret (0usize, Invalid) }
    cs.n += 1u64
    ret (written, ok)
}

// k = ENCRYPT(k, 2^64 - 1, "", zeros[32]) truncated to 32 bytes; the nonce is kept.
fn rekey(cs: *CipherState) {
    var sealed: [48]u8 = zero
    let zeros: [32]u8 = zero
    let (_, seal_error) = aead.chacha20_poly1305_seal(sealed[0..], cs.k, nonce_bytes(18446744073709551615u64), zeros[..0usize], zeros[0..])
    if seal_error != ok { ret }
    var i = 0usize
    while i < 32usize {
        cs.k[i] = sealed[i]
        i += 1usize
    }
}

fn copy(dst: []u8, src: []const u8) {
    var i = 0usize
    while i < src.len {
        dst[i] = src[i]
        i += 1usize
    }
}

// --- SymmetricState.

type SymmetricState = struct { cipher: CipherState, ck: [32]u8, h: [32]u8 }

fn symmetric_state(protocol_name: str) -> SymmetricState {
    var s: SymmetricState = zero
    if protocol_name.len <= 32usize {
        copy(s.h[0..], protocol_name)
    } else {
        s.h = blake2s(protocol_name)
    }
    s.ck = s.h
    ret s
}

fn mix_hash(s: *SymmetricState, data: []const u8) {
    var state = blake2s_new()
    blake2s_update(&state, s.h[0..])
    blake2s_update(&state, data)
    s.h = blake2s_done(&state)
}

fn mix_key(s: *SymmetricState, input_key_material: []const u8) {
    let out = hkdf2(s.ck, input_key_material)
    s.ck = out.a
    s.cipher = cipher_state(out.b)
}

fn mix_key_and_hash(s: *SymmetricState, input_key_material: []const u8) {
    let out = hkdf3(s.ck, input_key_material)
    s.ck = out.a
    mix_hash(s, out.b[0..])
    s.cipher = cipher_state(out.c)
}

fn encrypt_and_hash(s: *SymmetricState, plain: []const u8, out: []u8) -> (usize, err) {
    let (written, e) = encrypt_with_ad(&s.cipher, s.h[0..], plain, out)
    if e != ok { ret (0usize, e) }
    mix_hash(s, out[..written])
    ret (written, ok)
}

fn decrypt_and_hash(s: *SymmetricState, sealed: []const u8, out: []u8) -> (usize, err) {
    let (written, e) = decrypt_with_ad(&s.cipher, s.h[0..], sealed, out)
    if e != ok { ret (0usize, e) }
    mix_hash(s, sealed)
    ret (written, ok)
}

// --- HandshakeState (IK / IKpsk2).

type HandshakeState = struct { sym: SymmetricState, s_secret: [32]u8, s_public: [32]u8, e_secret: [32]u8, e_public: [32]u8, rs: [32]u8, re: [32]u8, initiator: bool, psk: [32]u8, has_psk: bool, step: u8 }
type Transport = struct { send: CipherState, recv: CipherState, h: [32]u8 }

// IK: the initiator knows the responder's static `rs` in advance; the responder passes
// any `rs` (it learns the initiator's from message 1). A 32-byte `psk` selects IKpsk2;
// an empty one is plain IK. `protocol_name` is hashed in as written.
fn initialize(protocol_name: str, initiator: bool, prologue: []const u8, s_secret: [32]u8, rs: [32]u8, psk: []const u8) -> HandshakeState {
    var hs: HandshakeState = zero
    hs.sym = symmetric_state(protocol_name)
    mix_hash(&hs.sym, prologue)
    hs.initiator = initiator
    hs.s_secret = s_secret
    hs.s_public = public_key(s_secret)
    hs.rs = rs
    if psk.len == 32usize {
        copy(hs.psk[0..], psk)
        hs.has_psk = true
    }
    if initiator {
        mix_hash(&hs.sym, rs[0..])
    } else {
        mix_hash(&hs.sym, hs.s_public[0..])
    }
    ret hs
}

fn public_key(secret: [32]u8) -> [32]u8 {
    var base: [32]u8 = zero
    base[0] = 9u8
    ret kx.x25519(secret, base)
}

fn dh(hs: *HandshakeState, secret: [32]u8, point: [32]u8) {
    let shared_secret = kx.x25519(secret, point)
    mix_key(&hs.sym, shared_secret[0..])
}

fn write_e(hs: *HandshakeState, ephemeral_secret: [32]u8, out: []u8) {
    hs.e_secret = ephemeral_secret
    hs.e_public = public_key(ephemeral_secret)
    copy(out, hs.e_public[0..])
    mix_hash(&hs.sym, hs.e_public[0..])
    if hs.has_psk { mix_key(&hs.sym, hs.e_public[0..]) }
}

fn read_e(hs: *HandshakeState, message: []const u8) {
    copy(hs.re[0..], message[..32usize])
    mix_hash(&hs.sym, hs.re[0..])
    if hs.has_psk { mix_key(&hs.sym, hs.re[0..]) }
}

// The next handshake message with `payload` into `out`; message 1 is 32 + 48 + 16 +
// payload bytes, message 2 is 32 + 16 + payload. `Invalid` when it is not this side's
// turn or the handshake is over.
fn write_message(hs: *HandshakeState, payload: []const u8, out: []u8, ephemeral_secret: [32]u8) -> (usize, err) {
    if hs.step == 0u8 && hs.initiator {
        if out.len < 96usize + payload.len { ret (0usize, TooSmall) }
        write_e(hs, ephemeral_secret, out[..32usize])
        dh(hs, hs.e_secret, hs.rs)
        let (_, s_error) = encrypt_and_hash(&hs.sym, hs.s_public[0..], out[32usize..80usize])
        if s_error != ok { ret (0usize, s_error) }
        dh(hs, hs.s_secret, hs.rs)
        let (n, payload_error) = encrypt_and_hash(&hs.sym, payload, out[80usize..])
        if payload_error != ok { ret (0usize, payload_error) }
        hs.step = 1u8
        ret (80usize + n, ok)
    }
    if hs.step == 1u8 && !hs.initiator {
        if out.len < 48usize + payload.len { ret (0usize, TooSmall) }
        write_e(hs, ephemeral_secret, out[..32usize])
        dh(hs, hs.e_secret, hs.re)
        dh(hs, hs.e_secret, hs.rs)
        if hs.has_psk { mix_key_and_hash(&hs.sym, hs.psk[0..]) }
        let (n, payload_error) = encrypt_and_hash(&hs.sym, payload, out[32usize..])
        if payload_error != ok { ret (0usize, payload_error) }
        hs.step = 2u8
        ret (32usize + n, ok)
    }
    ret (0usize, Invalid)
}

// The inverse: the peer's message decrypted into `payload_out`; a bad tag is
// `Authentication` (a wrong psk surfaces at message 2).
fn read_message(hs: *HandshakeState, message: []const u8, payload_out: []u8) -> (usize, err) {
    if hs.step == 0u8 && !hs.initiator {
        if message.len < 96usize { ret (0usize, TooSmall) }
        read_e(hs, message)
        dh(hs, hs.s_secret, hs.re)
        var rs: [32]u8 = zero
        let (_, s_error) = decrypt_and_hash(&hs.sym, message[32usize..80usize], rs[0..])
        if s_error != ok { ret (0usize, s_error) }
        hs.rs = rs
        dh(hs, hs.s_secret, hs.rs)
        let (n, payload_error) = decrypt_and_hash(&hs.sym, message[80usize..], payload_out)
        if payload_error != ok { ret (0usize, payload_error) }
        hs.step = 1u8
        ret (n, ok)
    }
    if hs.step == 1u8 && hs.initiator {
        if message.len < 48usize { ret (0usize, TooSmall) }
        read_e(hs, message)
        dh(hs, hs.e_secret, hs.re)
        dh(hs, hs.s_secret, hs.re)
        if hs.has_psk { mix_key_and_hash(&hs.sym, hs.psk[0..]) }
        let (n, payload_error) = decrypt_and_hash(&hs.sym, message[32usize..], payload_out)
        if payload_error != ok { ret (0usize, payload_error) }
        hs.step = 2u8
        ret (n, ok)
    }
    ret (0usize, Invalid)
}

// The transport keys once the handshake is over: `send` and `recv` are already oriented
// for this side (Noise's c1 is the initiator's sending key), `h` is the handshake hash
// for channel binding. `Invalid` before message 2 has crossed.
fn split(hs: *HandshakeState) -> (Transport, err) {
    if hs.step != 2u8 { ret (zero, Invalid) }
    let out = hkdf2(hs.sym.ck, hs.sym.h[..0usize])
    var t: Transport = zero
    t.h = hs.sym.h
    if hs.initiator {
        t.send = cipher_state(out.a)
        t.recv = cipher_state(out.b)
    } else {
        t.send = cipher_state(out.b)
        t.recv = cipher_state(out.a)
    }
    ret (t, ok)
}

// The whole IK (or IKpsk2, with a 32-byte psk) handshake between two parties whose
// keys and ephemerals are all in hand, empty payloads; `message1` needs 96 bytes and
// `message2` 48. Answers the initiator's and the responder's transports.
fn handshake_ik(protocol_name: str, prologue: []const u8, i_static: [32]u8, r_static: [32]u8, i_ephemeral: [32]u8, r_ephemeral: [32]u8, psk: []const u8, message1: []u8, message2: []u8) -> (Transport, Transport, err) {
    var i = initialize(protocol_name, true, prologue, i_static, public_key(r_static), psk)
    var r = initialize(protocol_name, false, prologue, r_static, zero_key(), psk)
    var none: [0]u8 = zero
    let (n1, w1) = write_message(&i, none[0..], message1, i_ephemeral)
    if w1 != ok { ret (zero, zero, w1) }
    let (_, r1) = read_message(&r, message1[..n1], none[0..])
    if r1 != ok { ret (zero, zero, r1) }
    let (n2, w2) = write_message(&r, none[0..], message2, r_ephemeral)
    if w2 != ok { ret (zero, zero, w2) }
    let (_, r2) = read_message(&i, message2[..n2], none[0..])
    if r2 != ok { ret (zero, zero, r2) }
    let (ti, si) = split(&i)
    if si != ok { ret (zero, zero, si) }
    let (tr, sr) = split(&r)
    ret (ti, tr, sr)
}

// Constant-time equality, for comparing handshake hashes or keys.
fn equal(a: []const u8, b: []const u8) -> bool { ret hash.equal_constant_time(a, b) }
