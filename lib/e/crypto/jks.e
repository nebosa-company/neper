// Java KeyStore (JKS, version 2) files: read the entries, check the keystore's integrity
// digest with the store password, decrypt a private key to PKCS #8, and write a keystore.
//
// Layout (all integers big endian): magic `FEEDFEED`, version 2, entry count, then per entry a
// tag (1 private key, 2 trusted certificate), the alias as a `u16`-length modified UTF-8
// string, a `u64` creation time in milliseconds, and either an EncryptedPrivateKeyInfo
// (u32 length, DER) followed by a u32 count of certificates (each a `X.509` type string, u32
// length, DER), or one certificate. A 20-byte SHA-1 of `password(UTF-16BE) || "Mighty
// Aphrodite" || everything before it` ends the file.
//
// A private key is protected with Sun's proprietary scheme, algorithm
// 1.3.6.1.4.1.42.2.17.1.1: the payload is `salt(20) || PKCS#8 XOR keystream || SHA-1(password
// || PKCS#8)` with keystream block i = SHA-1(password(UTF-16BE) || block i-1), block 0 over
// the salt. It is a weak, legacy scheme (SHA-1, no work factor); it is here to interoperate with
// existing keystores, not to protect new keys. PKCS #12 stores are a separate format.
//
// The password is UTF-8 text that is re-encoded as UTF-16BE (supplementary characters as
// surrogate pairs), as the JDK does with its `char[]`.

use e.mem
use e.crypto.hash as hash
use e.fmt.asn1 as asn1

type Entry = struct { alias: str, is_key: bool, timestamp_ms: u64, protected: []const u8, chain: []const []const u8 }
type Keystore = struct { entries: []Entry }
error Invalid
error BadPassword
error Unsupported
error TooSmall

const DEPTH: u16 = 8u16

// UTF-8 to UTF-16BE bytes into `dst`; returns the byte length.
fn password_bytes(password: str, dst: []u8) -> (usize, err) {
    var n = 0usize
    var i = 0usize
    while i < password.len {
        let c = u32(password[i])
        var cp = c
        var width = 1usize
        if c >= 240u32 {
            if i + 3usize >= password.len { ret (0usize, Invalid) }
            cp = ((c & 7u32) << 18u32) | ((u32(password[i + 1usize]) & 63u32) << 12u32) | ((u32(password[i + 2usize]) & 63u32) << 6u32) | (u32(password[i + 3usize]) & 63u32)
            width = 4usize
        } else if c >= 224u32 {
            if i + 2usize >= password.len { ret (0usize, Invalid) }
            cp = ((c & 15u32) << 12u32) | ((u32(password[i + 1usize]) & 63u32) << 6u32) | (u32(password[i + 2usize]) & 63u32)
            width = 3usize
        } else if c >= 192u32 {
            if i + 1usize >= password.len { ret (0usize, Invalid) }
            cp = ((c & 31u32) << 6u32) | (u32(password[i + 1usize]) & 63u32)
            width = 2usize
        }
        if cp >= 65536u32 {
            if n + 4usize > dst.len { ret (0usize, TooSmall) }
            let v = cp - 65536u32
            let high = 55296u32 + (v >> 10u32)
            let low = 56320u32 + (v & 1023u32)
            dst[n] = u8(high >> 8u32)
            dst[n + 1usize] = u8(high & 255u32)
            dst[n + 2usize] = u8(low >> 8u32)
            dst[n + 3usize] = u8(low & 255u32)
            n += 4usize
        } else {
            if n + 2usize > dst.len { ret (0usize, TooSmall) }
            dst[n] = u8(cp >> 8u32)
            dst[n + 1usize] = u8(cp & 255u32)
            n += 2usize
        }
        i += width
    }
    ret (n, ok)
}

fn be16(d: []const u8, at: usize) -> usize { ret usize(d[at]) * 256usize + usize(d[at + 1usize]) }

fn be32(d: []const u8, at: usize) -> usize {
    ret ((usize(d[at]) * 256usize + usize(d[at + 1usize])) * 256usize + usize(d[at + 2usize])) * 256usize + usize(d[at + 3usize])
}

fn be64(d: []const u8, at: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        v = v * 256u64 + u64(d[at + i])
        i += 1usize
    }
    ret v
}

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn integrity_digest(a: *mem.Arena, password: str, body: []const u8) -> ([20]u8, err) {
    var pw: [512]u8 = zero
    let (pn, pe) = password_bytes(password, pw[0usize..512usize])
    if pe != ok { ret (zero, pe) }
    let mark = mem.mark(a)
    let (buf, alloc_error) = mem.alloc[u8](a, pn + 16usize + body.len)
    if alloc_error != ok { ret (zero, alloc_error) }
    mem.copy[u8](buf[0usize..pn], pw[0usize..pn])
    let whiten = "Mighty Aphrodite"
    var k = 0usize
    while k < 16usize {
        buf[pn + k] = whiten[k]
        k += 1usize
    }
    mem.copy[u8](buf[pn + 16usize..pn + 16usize + body.len], body)
    let d = hash.legacy_sha1(buf[0usize..pn + 16usize + body.len])
    mem.reset(a, mark)
    ret (d, ok)
}

fn parse(a: *mem.Arena, data: []const u8, password: str) -> (Keystore, err) {
    var ks: Keystore = zero
    if data.len < 32usize { ret (ks, Invalid) }
    if be32(data, 0usize) != 4277010157usize { ret (ks, Invalid) }
    if be32(data, 4usize) != 2usize { ret (ks, Unsupported) }
    let body_len = data.len - 20usize
    let (digest, digest_error) = integrity_digest(a, password, data[0usize..body_len])
    if digest_error != ok { ret (ks, digest_error) }
    if !same(digest[0usize..20usize], data[body_len..data.len]) { ret (ks, BadPassword) }
    let count = be32(data, 8usize)
    if count > 100000usize { ret (ks, Invalid) }
    let (entries, entries_error) = mem.alloc[Entry](a, count + 1usize)
    if entries_error != ok { ret (ks, entries_error) }
    var at = 12usize
    var i = 0usize
    while i < count {
        if at + 4usize > body_len { ret (ks, Invalid) }
        let tag = be32(data, at)
        at += 4usize
        if at + 2usize > body_len { ret (ks, Invalid) }
        let alias_len = be16(data, at)
        at += 2usize
        if at + alias_len + 8usize > body_len { ret (ks, Invalid) }
        var e: Entry = zero
        e.alias = data[at..at + alias_len]
        at += alias_len
        e.timestamp_ms = be64(data, at)
        at += 8usize
        if tag == 1usize {
            e.is_key = true
            if at + 4usize > body_len { ret (ks, Invalid) }
            let key_len = be32(data, at)
            at += 4usize
            if at + key_len + 4usize > body_len { ret (ks, Invalid) }
            e.protected = data[at..at + key_len]
            at += key_len
            let chain_count = be32(data, at)
            at += 4usize
            if chain_count > 1000usize { ret (ks, Invalid) }
            let (chain, chain_error) = mem.alloc[[]const u8](a, chain_count + 1usize)
            if chain_error != ok { ret (ks, chain_error) }
            var c = 0usize
            while c < chain_count {
                if at + 2usize > body_len { ret (ks, Invalid) }
                let type_len = be16(data, at)
                at += 2usize + type_len
                if at + 4usize > body_len { ret (ks, Invalid) }
                let cert_len = be32(data, at)
                at += 4usize
                if at + cert_len > body_len { ret (ks, Invalid) }
                chain[c] = data[at..at + cert_len]
                at += cert_len
                c += 1usize
            }
            e.chain = chain[0usize..chain_count]
        } else if tag == 2usize {
            if at + 2usize > body_len { ret (ks, Invalid) }
            let type_len = be16(data, at)
            at += 2usize + type_len
            if at + 4usize > body_len { ret (ks, Invalid) }
            let cert_len = be32(data, at)
            at += 4usize
            if at + cert_len > body_len { ret (ks, Invalid) }
            let (chain, chain_error) = mem.alloc[[]const u8](a, 1usize)
            if chain_error != ok { ret (ks, chain_error) }
            chain[0usize] = data[at..at + cert_len]
            at += cert_len
            e.chain = chain[0usize..1usize]
        } else {
            ret (ks, Unsupported)
        }
        entries[i] = e
        i += 1usize
    }
    if at != body_len { ret (ks, Invalid) }
    ks.entries = entries[0usize..count]
    ret (ks, ok)
}

// The Sun keystream: block 0 = SHA-1(password || salt), block i = SHA-1(password || block i-1).
fn keystream_block(pw: []const u8, previous: []const u8) -> [20]u8 {
    var buf: [532]u8 = zero
    mem.copy[u8](buf[0usize..pw.len], pw)
    mem.copy[u8](buf[pw.len..pw.len + 20usize], previous)
    ret hash.legacy_sha1(buf[0usize..pw.len + 20usize])
}

fn sun_oid() -> [10]u8 { ret [10]u8{ 43u8, 6u8, 1u8, 4u8, 1u8, 42u8, 2u8, 17u8, 1u8, 1u8 } }

// The PKCS #8 PrivateKeyInfo inside an entry's EncryptedPrivateKeyInfo (`out` must hold the
// payload less 40 bytes). Returns the key length written into `out`.
fn decrypt_key(a: *mem.Arena, protected: []const u8, password: str, out: []u8) -> (usize, err) {
    var top = asn1.reader(protected, DEPTH)
    let (outer, outer_error) = next(&top)
    if outer_error != ok { ret (0usize, outer_error) }
    let (kids, kids_error) = asn1.children(outer, DEPTH)
    if kids_error != ok { ret (0usize, Invalid) }
    var r = kids
    let (alg, alg_error) = next(&r)
    if alg_error != ok { ret (0usize, alg_error) }
    let (alg_kids, alg_kids_error) = asn1.children(alg, DEPTH)
    if alg_kids_error != ok { ret (0usize, Invalid) }
    var ar = alg_kids
    let (oid, oid_error) = next(&ar)
    if oid_error != ok { ret (0usize, oid_error) }
    let expected = sun_oid()
    if !same(oid.content, expected[0usize..10usize]) { ret (0usize, Unsupported) }
    let (payload, payload_error) = next(&r)
    if payload_error != ok || payload.tag.number != 4u32 { ret (0usize, Invalid) }
    let blob = payload.content
    if blob.len < 40usize { ret (0usize, Invalid) }
    let key_len = blob.len - 40usize
    if out.len < key_len { ret (0usize, TooSmall) }
    var pw: [512]u8 = zero
    let (pn, pe) = password_bytes(password, pw[0usize..512usize])
    if pe != ok { ret (0usize, pe) }
    var block = keystream_block(pw[0usize..pn], blob[0usize..20usize])
    var used = 0usize
    var i = 0usize
    while i < key_len {
        if used == 20usize {
            block = keystream_block(pw[0usize..pn], block[0usize..20usize])
            used = 0usize
        }
        out[i] = blob[20usize + i] ^ block[used]
        used += 1usize
        i += 1usize
    }
    // check = SHA-1(password || plaintext)
    let (buf, alloc_error) = mem.alloc[u8](a, pn + key_len)
    if alloc_error != ok { ret (0usize, alloc_error) }
    mem.copy[u8](buf[0usize..pn], pw[0usize..pn])
    mem.copy[u8](buf[pn..pn + key_len], out[0usize..key_len])
    let check = hash.legacy_sha1(buf[0usize..pn + key_len])
    if !same(check[0usize..20usize], blob[20usize + key_len..blob.len]) { ret (0usize, BadPassword) }
    ret (key_len, ok)
}

fn next(r: *asn1.Reader) -> (asn1.Value, err) {
    let (v, present, e) = asn1.reader_next_err(r)
    if e != ok || !present { ret (zero, Invalid) }
    ret (v, ok)
}

// ---- writing ----

fn put_be16(dst: []u8, at: usize, v: usize) {
    dst[at] = u8((v >> 8u32) & 255usize)
    dst[at + 1usize] = u8(v & 255usize)
}

fn put_be32(dst: []u8, at: usize, v: usize) {
    dst[at] = u8((v >> 24u32) & 255usize)
    dst[at + 1usize] = u8((v >> 16u32) & 255usize)
    dst[at + 2usize] = u8((v >> 8u32) & 255usize)
    dst[at + 3usize] = u8(v & 255usize)
}

fn put_be64(dst: []u8, at: usize, v: u64) {
    var i = 0usize
    while i < 8usize {
        dst[at + i] = u8((v >> u64((7usize - i) * 8usize)) & 255u64)
        i += 1usize
    }
}

fn header(dst: []u8, at: usize, tag: u8, len: usize) -> usize { ret asn1.put_header(dst, at, tag, len) }

// Protects `pkcs8` with `password` and `salt` into an EncryptedPrivateKeyInfo DER in `out`;
// returns its length.
fn protect_key(pkcs8: []const u8, password: str, salt: []const u8, out: []u8) -> (usize, err) {
    if salt.len != 20usize { ret (0usize, Invalid) }
    var pw: [512]u8 = zero
    let (pn, pe) = password_bytes(password, pw[0usize..512usize])
    if pe != ok { ret (0usize, pe) }
    let payload_len = 20usize + pkcs8.len + 20usize
    // SEQ { SEQ { OID, NULL }, OCTET STRING }
    let alg_content = 2usize + 10usize + 2usize
    var octet_header = 2usize
    if payload_len >= 128usize { octet_header = 3usize }
    if payload_len >= 256usize { octet_header = 4usize }
    let seq_content = 2usize + alg_content + octet_header + payload_len
    var seq_header = 2usize
    if seq_content >= 128usize { seq_header = 3usize }
    if seq_content >= 256usize { seq_header = 4usize }
    if out.len < seq_header + seq_content { ret (0usize, TooSmall) }
    var at = header(out, 0usize, 48u8, seq_content)
    at = header(out, at, 48u8, alg_content)
    at = header(out, at, 6u8, 10usize)
    let oid = sun_oid()
    var i = 0usize
    while i < 10usize {
        out[at + i] = oid[i]
        i += 1usize
    }
    at += 10usize
    out[at] = 5u8
    out[at + 1usize] = 0u8
    at += 2usize
    at = header(out, at, 4u8, payload_len)
    i = 0usize
    while i < 20usize {
        out[at + i] = salt[i]
        i += 1usize
    }
    var block = keystream_block(pw[0usize..pn], salt)
    var used = 0usize
    i = 0usize
    while i < pkcs8.len {
        if used == 20usize {
            block = keystream_block(pw[0usize..pn], block[0usize..20usize])
            used = 0usize
        }
        out[at + 20usize + i] = pkcs8[i] ^ block[used]
        used += 1usize
        i += 1usize
    }
    var check_buf: [4096]u8 = zero
    if pn + pkcs8.len > 4096usize { ret (0usize, TooSmall) }
    mem.copy[u8](check_buf[0usize..pn], pw[0usize..pn])
    mem.copy[u8](check_buf[pn..pn + pkcs8.len], pkcs8)
    let check = hash.legacy_sha1(check_buf[0usize..pn + pkcs8.len])
    i = 0usize
    while i < 20usize {
        out[at + 20usize + pkcs8.len + i] = check[i]
        i += 1usize
    }
    ret (at + payload_len, ok)
}

fn put_utf(dst: []u8, at: usize, s: str) -> usize {
    put_be16(dst, at, s.len)
    var i = 0usize
    while i < s.len {
        dst[at + 2usize + i] = s[i]
        i += 1usize
    }
    ret at + 2usize + s.len
}

// A keystore from `entries` (keys already protected, e.g. by `protect_key`), with the
// integrity digest for `password`. Returns the length written to `out`.
fn encode(a: *mem.Arena, entries: []const Entry, password: str, out: []u8) -> (usize, err) {
    var need = 12usize + 20usize
    var i = 0usize
    while i < entries.len {
        need += 4usize + 2usize + entries[i].alias.len + 8usize
        if entries[i].is_key {
            need += 4usize + entries[i].protected.len + 4usize
            var c = 0usize
            while c < entries[i].chain.len {
                need += 2usize + 5usize + 4usize + entries[i].chain[c].len
                c += 1usize
            }
        } else {
            if entries[i].chain.len != 1usize { ret (0usize, Invalid) }
            need += 2usize + 5usize + 4usize + entries[i].chain[0usize].len
        }
        i += 1usize
    }
    if out.len < need { ret (0usize, TooSmall) }
    put_be32(out, 0usize, 4277010157usize)
    put_be32(out, 4usize, 2usize)
    put_be32(out, 8usize, entries.len)
    var at = 12usize
    i = 0usize
    while i < entries.len {
        let e = entries[i]
        var tag = 2usize
        if e.is_key { tag = 1usize }
        put_be32(out, at, tag)
        at += 4usize
        at = put_utf(out, at, e.alias)
        put_be64(out, at, e.timestamp_ms)
        at += 8usize
        if e.is_key {
            put_be32(out, at, e.protected.len)
            at += 4usize
            mem.copy[u8](out[at..at + e.protected.len], e.protected)
            at += e.protected.len
            put_be32(out, at, e.chain.len)
            at += 4usize
        }
        var c = 0usize
        while c < e.chain.len {
            at = put_utf(out, at, "X.509")
            put_be32(out, at, e.chain[c].len)
            at += 4usize
            mem.copy[u8](out[at..at + e.chain[c].len], e.chain[c])
            at += e.chain[c].len
            c += 1usize
        }
        i += 1usize
    }
    let (digest, digest_error) = integrity_digest(a, password, out[0usize..at])
    if digest_error != ok { ret (0usize, digest_error) }
    mem.copy[u8](out[at..at + 20usize], digest[0usize..20usize])
    ret (at + 20usize, ok)
}
