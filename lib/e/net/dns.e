// DNS over caller storage, without sockets. RFC 1035 wire format:
// `encode_query` writes a query with an optional EDNS OPT record, `decode_header`,
// `decode_name` (compression pointers, loop-safe: a pointer must go backwards),
// `skip_question`, `decode_rr` and the `rdata_*` readers for A, AAAA, TXT and MX;
// names are handled in their uncompressed wire form (`name_text` renders one).
// RFC 4034/4035 DNSSEC: `rdata_rrsig`, `rdata_dnskey`, `rdata_ds`, `key_tag`,
// `ds_digest` (SHA-256), `dnssec_validate` over an RRset in canonical form and
// order with Ed25519 (15) and ECDSA P-256/SHA-256 (13), and `chain_validate` from a
// parent DS to a DNSKEY RRset. RFC 8484 DoH: `query_doh` builds the exact HTTP/1.1
// GET or POST bytes and `doh_response_body` splits a 200 response; `query_dot_frame`
// is the RFC 7858 two-byte length prefix.
//
// ponytail: RSA (algorithm 8) and SHA-1/SHA-384 DS digests answer `Unsupported`;
// no RSA or SHA-384 exists in e.crypto yet. An RRset holds at most MAX_RRS records.

use e.bytes
use e.crypto.hash as hash
use e.crypto.sign as sign
use e.mem

type Header = struct { id: u16, flags: u16, qdcount: u16, ancount: u16, nscount: u16, arcount: u16 }
type Rr = struct { name_len: usize, kind: u16, class: u16, ttl: u32, rdata: []const u8, rdata_at: usize }
type Rrsig = struct { type_covered: u16, algorithm: u8, labels: u8, original_ttl: u32, expiration: u32, inception: u32, key_tag: u16, signer: []const u8, signature: []const u8 }
type Dnskey = struct { flags: u16, protocol: u8, algorithm: u8, public_key: []const u8 }
type Ds = struct { key_tag: u16, algorithm: u8, digest_type: u8, digest: []const u8 }
error Malformed
error Invalid
error TooSmall
error Unsupported
error Expired
error NotYetValid
error BadSignature

const TYPE_A: u16 = 1u16
const TYPE_NS: u16 = 2u16
const TYPE_CNAME: u16 = 5u16
const TYPE_SOA: u16 = 6u16
const TYPE_PTR: u16 = 12u16
const TYPE_MX: u16 = 15u16
const TYPE_TXT: u16 = 16u16
const TYPE_AAAA: u16 = 28u16
const TYPE_SRV: u16 = 33u16
const TYPE_DNAME: u16 = 39u16
const TYPE_OPT: u16 = 41u16
const TYPE_DS: u16 = 43u16
const TYPE_RRSIG: u16 = 46u16
const TYPE_DNSKEY: u16 = 48u16
const CLASS_IN: u16 = 1u16
const FLAG_RD: u16 = 256u16
const DNSKEY_SEP: u16 = 256u16
const ALG_RSASHA256: u8 = 8u8
const ALG_ECDSAP256SHA256: u8 = 13u8
const ALG_ED25519: u8 = 15u8
const DS_SHA256: u8 = 2u8
const MAX_NAME: usize = 255usize
const MAX_RRS: usize = 64usize

fn store16(dst: []u8, at: usize, value: u16) {
    dst[at] = u8(value >> 8u32)
    dst[at + 1usize] = u8(value & 255u16)
}

fn store32(dst: []u8, at: usize, value: u32) {
    dst[at] = u8(value >> 24u32)
    dst[at + 1usize] = u8((value >> 16u32) & 255u32)
    dst[at + 2usize] = u8((value >> 8u32) & 255u32)
    dst[at + 3usize] = u8(value & 255u32)
}

fn load16(src: []const u8, at: usize) -> u16 {
    ret (u16(src[at]) << 8u32) | u16(src[at + 1usize])
}

fn load32(src: []const u8, at: usize) -> u32 {
    ret (u32(src[at]) << 24u32) | (u32(src[at + 1usize]) << 16u32) | (u32(src[at + 2usize]) << 8u32) | u32(src[at + 3usize])
}

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn put(dst: []u8, at: *usize, text: []const u8) -> err {
    if *at + text.len > dst.len { ret TooSmall }
    mem.copy[u8](dst[*at..*at + text.len], text)
    *at += text.len
    ret ok
}

fn put_decimal(dst: []u8, at: *usize, value: usize) -> err {
    var digits: [20]u8 = zero
    var n = 0usize
    var v = value
    if v == 0usize {
        digits[0] = 48u8
        n = 1usize
    }
    while v > 0usize {
        digits[n] = u8(48usize + v % 10usize)
        v /= 10usize
        n += 1usize
    }
    if *at + n > dst.len { ret TooSmall }
    var i = 0usize
    while i < n {
        dst[*at + i] = digits[n - 1usize - i]
        i += 1usize
    }
    *at += n
    ret ok
}

// A presentation name (`example.com.`, the trailing dot optional, `.` the root) into
// its wire form at `dst[at..]`; labels are at most 63 octets and the name 255.
fn encode_name(dst: []u8, at: usize, name: str) -> (usize, err) {
    var end = name.len
    if end > 0usize && name[end - 1usize] == 46u8 { end -= 1usize }
    var out = at
    var start = 0usize
    while start < end {
        var stop = start
        while stop < end && name[stop] != 46u8 { stop += 1usize }
        let label_len = stop - start
        if label_len == 0usize || label_len > 63usize { ret (at, Invalid) }
        if out + 1usize + label_len > dst.len { ret (at, TooSmall) }
        dst[out] = u8(label_len)
        mem.copy[u8](dst[out + 1usize..out + 1usize + label_len], name[start..stop])
        out += 1usize + label_len
        start = stop + 1usize
    }
    if out + 1usize > dst.len { ret (at, TooSmall) }
    dst[out] = 0u8
    out += 1usize
    if out - at > MAX_NAME { ret (at, Invalid) }
    ret (out, ok)
}

// A query for `name`/`qtype`/`qclass` with `id`; `edns_udp_size` above 0 adds an OPT
// record in the additional section carrying the DO bit when `dnssec_ok`.
fn encode_query(dst: []u8, id: u16, name: str, qtype: u16, qclass: u16, recursion_desired: bool, edns_udp_size: u16, dnssec_ok: bool) -> (usize, err) {
    if dst.len < 12usize { ret (0usize, TooSmall) }
    store16(dst, 0usize, id)
    var flags = 0u16
    if recursion_desired { flags = FLAG_RD }
    store16(dst, 2usize, flags)
    store16(dst, 4usize, 1u16)
    store16(dst, 6usize, 0u16)
    store16(dst, 8usize, 0u16)
    var additional = 0u16
    if edns_udp_size > 0u16 { additional = 1u16 }
    store16(dst, 10usize, additional)
    let (after_name, name_error) = encode_name(dst, 12usize, name)
    if name_error != ok { ret (0usize, name_error) }
    var at = after_name
    if at + 4usize > dst.len { ret (0usize, TooSmall) }
    store16(dst, at, qtype)
    store16(dst, at + 2usize, qclass)
    at += 4usize
    if edns_udp_size > 0u16 {
        if at + 11usize > dst.len { ret (0usize, TooSmall) }
        dst[at] = 0u8
        store16(dst, at + 1usize, TYPE_OPT)
        store16(dst, at + 3usize, edns_udp_size)
        var ttl = 0u32
        if dnssec_ok { ttl = 32768u32 }
        store32(dst, at + 5usize, ttl)
        store16(dst, at + 9usize, 0u16)
        at += 11usize
    }
    ret (at, ok)
}

fn decode_header(src: []const u8) -> (Header, err) {
    var h: Header = zero
    if src.len < 12usize { ret (h, TooSmall) }
    h.id = load16(src, 0usize)
    h.flags = load16(src, 2usize)
    h.qdcount = load16(src, 4usize)
    h.ancount = load16(src, 6usize)
    h.nscount = load16(src, 8usize)
    h.arcount = load16(src, 10usize)
    ret (h, ok)
}

fn header_is_response(h: Header) -> bool { ret (h.flags & 32768u16) != 0u16 }
fn header_rcode(h: Header) -> u8 { ret u8(h.flags & 15u16) }
fn header_authentic_data(h: Header) -> bool { ret (h.flags & 32u16) != 0u16 }
fn header_truncated(h: Header) -> bool { ret (h.flags & 512u16) != 0u16 }

// The name at `*pos` into `out` in uncompressed wire form, following compression
// pointers, which must point before the pointer itself. `*pos` moves past the name in
// `src`; the result is the length written.
fn decode_name(src: []const u8, pos: *usize, out: []u8) -> (usize, err) {
    var at = *pos
    var written = 0usize
    var jumped = false
    var end_of_name = 0usize
    while true {
        if at >= src.len { ret (0usize, Malformed) }
        let length = usize(src[at])
        if length >= 192usize {
            if at + 2usize > src.len { ret (0usize, Malformed) }
            let target_at = ((length & 63usize) << 8u32) | usize(src[at + 1usize])
            if target_at >= at { ret (0usize, Malformed) }
            if !jumped { end_of_name = at + 2usize }
            jumped = true
            at = target_at
            continue
        }
        if length >= 64usize { ret (0usize, Malformed) }
        if at + 1usize + length > src.len { ret (0usize, Malformed) }
        if written + 1usize + length > out.len { ret (0usize, TooSmall) }
        if written + 1usize + length > MAX_NAME { ret (0usize, Malformed) }
        out[written] = src[at]
        mem.copy[u8](out[written + 1usize..written + 1usize + length], src[at + 1usize..at + 1usize + length])
        written += 1usize + length
        at += 1usize + length
        if length == 0usize {
            if !jumped { end_of_name = at }
            *pos = end_of_name
            ret (written, ok)
        }
    }
    ret (0usize, Malformed)
}

// The question at `*pos` skipped; `*pos` moves past its name, type and class.
fn skip_question(src: []const u8, pos: *usize) -> err {
    var scratch: [255]u8 = zero
    let (_, name_error) = decode_name(src, pos, scratch[0..])
    if name_error != ok { ret name_error }
    if *pos + 4usize > src.len { ret Malformed }
    *pos += 4usize
    ret ok
}

// The question at `*pos`: its name into `out_name`, then type and class.
fn decode_question(src: []const u8, pos: *usize, out_name: []u8) -> (usize, u16, u16, err) {
    let (name_len, name_error) = decode_name(src, pos, out_name)
    if name_error != ok { ret (0usize, 0u16, 0u16, name_error) }
    if *pos + 4usize > src.len { ret (0usize, 0u16, 0u16, Malformed) }
    let kind = load16(src, *pos)
    let class = load16(src, *pos + 2usize)
    *pos += 4usize
    ret (name_len, kind, class, ok)
}

// The resource record at `*pos`: owner name into `out_name`, rdata as a view of `src`.
fn decode_rr(src: []const u8, pos: *usize, out_name: []u8) -> (Rr, err) {
    var r: Rr = zero
    let (name_len, name_error) = decode_name(src, pos, out_name)
    if name_error != ok { ret (r, name_error) }
    if *pos + 10usize > src.len { ret (r, Malformed) }
    r.name_len = name_len
    r.kind = load16(src, *pos)
    r.class = load16(src, *pos + 2usize)
    r.ttl = load32(src, *pos + 4usize)
    let rdlength = usize(load16(src, *pos + 8usize))
    let rdata_at = *pos + 10usize
    if rdata_at + rdlength > src.len { ret (r, Malformed) }
    r.rdata = src[rdata_at..rdata_at + rdlength]
    r.rdata_at = rdata_at
    *pos = rdata_at + rdlength
    ret (r, ok)
}

fn rdata_a(rdata: []const u8) -> ([4]u8, err) {
    var out: [4]u8 = zero
    if rdata.len != 4usize { ret (out, Malformed) }
    mem.copy[u8](out[0..], rdata)
    ret (out, ok)
}

fn rdata_aaaa(rdata: []const u8) -> ([16]u8, err) {
    var out: [16]u8 = zero
    if rdata.len != 16usize { ret (out, Malformed) }
    mem.copy[u8](out[0..], rdata)
    ret (out, ok)
}

// The next character-string of a TXT rdata at `*pos` (start at 0), copied into `out`.
fn rdata_txt(rdata: []const u8, pos: *usize, out: []u8) -> (usize, err) {
    if *pos >= rdata.len { ret (0usize, Malformed) }
    let length = usize(rdata[*pos])
    if *pos + 1usize + length > rdata.len { ret (0usize, Malformed) }
    if length > out.len { ret (0usize, TooSmall) }
    mem.copy[u8](out[..length], rdata[*pos + 1usize..*pos + 1usize + length])
    *pos += 1usize + length
    ret (length, ok)
}

// An MX record's preference and exchange (into `out_name`, uncompressed); `r` must
// come from `decode_rr` over the same `src`, as the exchange may be compressed.
fn rdata_mx(src: []const u8, r: Rr, out_name: []u8) -> (u16, usize, err) {
    if r.rdata.len < 3usize { ret (0u16, 0usize, Malformed) }
    let preference = load16(r.rdata, 0usize)
    var at = r.rdata_at + 2usize
    let (name_len, name_error) = decode_name(src, &at, out_name)
    if name_error != ok { ret (0u16, 0usize, name_error) }
    if at != r.rdata_at + r.rdata.len { ret (0u16, 0usize, Malformed) }
    ret (preference, name_len, ok)
}

// A single-name rdata (NS, CNAME, PTR, DNAME) expanded into `out_name`.
fn rdata_name(src: []const u8, r: Rr, out_name: []u8) -> (usize, err) {
    var at = r.rdata_at
    let (name_len, name_error) = decode_name(src, &at, out_name)
    if name_error != ok { ret (0usize, name_error) }
    if at != r.rdata_at + r.rdata.len { ret (0usize, Malformed) }
    ret (name_len, ok)
}

// The length of the uncompressed wire name starting `name[0]`, or `Malformed`.
fn wire_name_len(name: []const u8) -> (usize, err) {
    var at = 0usize
    while at < name.len {
        let length = usize(name[at])
        if length >= 64usize { ret (0usize, Malformed) }
        at += 1usize + length
        if length == 0usize {
            if at > MAX_NAME { ret (0usize, Malformed) }
            ret (at, ok)
        }
    }
    ret (0usize, Malformed)
}

// An uncompressed wire name lowercased into `out` (RFC 4034 §6.2), for signing.
fn canonical_name(name: []const u8, out: []u8) -> (usize, err) {
    let (length, length_error) = wire_name_len(name)
    if length_error != ok { ret (0usize, length_error) }
    if length > out.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < length {
        out[i] = lower(name[i])
        i += 1usize
    }
    ret (length, ok)
}

// An uncompressed wire name rendered as `example.com.` (root as `.`).
fn name_text(name: []const u8, out: []u8) -> (usize, err) {
    let (length, length_error) = wire_name_len(name)
    if length_error != ok { ret (0usize, length_error) }
    if length == 1usize {
        if out.len < 1usize { ret (0usize, TooSmall) }
        out[0] = 46u8
        ret (1usize, ok)
    }
    if length - 1usize > out.len { ret (0usize, TooSmall) }
    var at = 0usize
    var written = 0usize
    while name[at] != 0u8 {
        let label_len = usize(name[at])
        mem.copy[u8](out[written..written + label_len], name[at + 1usize..at + 1usize + label_len])
        written += label_len
        out[written] = 46u8
        written += 1usize
        at += 1usize + label_len
    }
    ret (written, ok)
}

// Case-insensitive equality of two uncompressed wire names.
fn name_equal_fold(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if lower(a[i]) != lower(b[i]) { ret false }
        i += 1usize
    }
    ret true
}

// Whether `ancestor` is `name` or a parent of it (both uncompressed wire names).
fn name_is_within(name: []const u8, ancestor: []const u8) -> bool {
    let (name_len, name_error) = wire_name_len(name)
    let (ancestor_len, ancestor_error) = wire_name_len(ancestor)
    if name_error != ok || ancestor_error != ok { ret false }
    var at = 0usize
    while at < name_len {
        if name_len - at == ancestor_len && name_equal_fold(name[at..name_len], ancestor[..ancestor_len]) { ret true }
        at += 1usize + usize(name[at])
    }
    ret false
}

fn rdata_rrsig(rdata: []const u8) -> (Rrsig, err) {
    var s: Rrsig = zero
    if rdata.len < 19usize { ret (s, Malformed) }
    s.type_covered = load16(rdata, 0usize)
    s.algorithm = rdata[2]
    s.labels = rdata[3]
    s.original_ttl = load32(rdata, 4usize)
    s.expiration = load32(rdata, 8usize)
    s.inception = load32(rdata, 12usize)
    s.key_tag = load16(rdata, 16usize)
    let (signer_len, signer_error) = wire_name_len(rdata[18usize..])
    if signer_error != ok { ret (s, Malformed) }
    s.signer = rdata[18usize..18usize + signer_len]
    s.signature = rdata[18usize + signer_len..]
    if s.signature.len == 0usize { ret (s, Malformed) }
    ret (s, ok)
}

fn rdata_dnskey(rdata: []const u8) -> (Dnskey, err) {
    var k: Dnskey = zero
    if rdata.len < 5usize { ret (k, Malformed) }
    k.flags = load16(rdata, 0usize)
    k.protocol = rdata[2]
    k.algorithm = rdata[3]
    k.public_key = rdata[4usize..]
    ret (k, ok)
}

fn rdata_ds(rdata: []const u8) -> (Ds, err) {
    var d: Ds = zero
    if rdata.len < 5usize { ret (d, Malformed) }
    d.key_tag = load16(rdata, 0usize)
    d.algorithm = rdata[2]
    d.digest_type = rdata[3]
    d.digest = rdata[4usize..]
    ret (d, ok)
}

// RFC 4034 Appendix B over a DNSKEY rdata.
fn key_tag(dnskey_rdata: []const u8) -> u16 {
    var ac = 0u32
    var i = 0usize
    while i < dnskey_rdata.len {
        if (i & 1usize) == 0usize {
            ac +%= u32(dnskey_rdata[i]) << 8u32
        } else {
            ac +%= u32(dnskey_rdata[i])
        }
        i += 1usize
    }
    ac +%= (ac >> 16u32) & 65535u32
    ret u16(ac & 65535u32)
}

// The DS digest of `owner` (uncompressed wire name, lowercased here) and a DNSKEY
// rdata; only digest type 2 (SHA-256) is supported.
fn ds_digest(owner: []const u8, dnskey_rdata: []const u8, digest_type: u8) -> ([32]u8, err) {
    var out: [32]u8 = zero
    if digest_type != DS_SHA256 { ret (out, Unsupported) }
    var canonical: [255]u8 = zero
    let (owner_len, owner_error) = canonical_name(owner, canonical[0..])
    if owner_error != ok { ret (out, owner_error) }
    var h = hash.sha256_init()
    hash.sha256_update(&h, canonical[..owner_len])
    hash.sha256_update(&h, dnskey_rdata)
    out = hash.sha256_done(&h)
    ret (out, ok)
}

// Lowercase the wire name at `data[at..]` in place, answering the position after it.
fn lower_name_in_place(data: []u8, at: usize) -> (usize, err) {
    let (length, length_error) = wire_name_len(data[at..])
    if length_error != ok { ret (at, length_error) }
    var i = at
    while i < at + length {
        data[i] = lower(data[i])
        i += 1usize
    }
    ret (at + length, ok)
}

// RFC 4034 §6.2: the rdata of `kind` in `data[at..end]` lowercased where it carries
// names. ponytail: NAPTR, PX, SIG, NXT and A6 keep their case; add them when met.
fn canonical_rdata_in_place(data: []u8, at: usize, end: usize, kind: u16) -> err {
    var names = 0usize
    var skip = 0usize
    if kind == TYPE_NS || kind == TYPE_CNAME || kind == TYPE_PTR || kind == TYPE_DNAME || kind == 3u16 || kind == 4u16 || kind == 7u16 || kind == 8u16 || kind == 9u16 { names = 1usize }
    if kind == TYPE_MX || kind == 18u16 || kind == 21u16 || kind == 36u16 {
        names = 1usize
        skip = 2usize
    }
    if kind == TYPE_SRV {
        names = 1usize
        skip = 6usize
    }
    if kind == TYPE_SOA || kind == 14u16 || kind == 17u16 { names = 2usize }
    if names == 0usize { ret ok }
    if at + skip > end { ret Malformed }
    var pos = at + skip
    while names > 0usize {
        let (after, name_error) = lower_name_in_place(data[..end], pos)
        if name_error != ok { ret name_error }
        pos = after
        names -= 1usize
    }
    ret ok
}

fn less_bytes(a: []const u8, b: []const u8) -> bool {
    var i = 0usize
    while i < a.len && i < b.len {
        if a[i] != b[i] { ret a[i] < b[i] }
        i += 1usize
    }
    ret a.len < b.len
}

fn equal_bytes(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// The DER SEQUENCE of two INTEGERs from a raw `r || s` signature.
fn der_from_raw(raw: []const u8, out: []u8) -> (usize, err) {
    let half = raw.len / 2usize
    var at = 2usize
    var part = 0usize
    while part < 2usize {
        var value = raw[part * half..(part + 1usize) * half]
        while value.len > 1usize && value[0] == 0u8 && (value[1] & 128u8) == 0u8 { value = value[1usize..] }
        var pad = 0usize
        if (value[0] & 128u8) != 0u8 { pad = 1usize }
        if at + 2usize + pad + value.len > out.len { ret (0usize, TooSmall) }
        out[at] = 2u8
        out[at + 1usize] = u8(value.len + pad)
        if pad == 1usize { out[at + 2usize] = 0u8 }
        mem.copy[u8](out[at + 2usize + pad..at + 2usize + pad + value.len], value)
        at += 2usize + pad + value.len
        part += 1usize
    }
    out[0] = 48u8
    out[1] = u8(at - 2usize)
    ret (at, ok)
}

fn verify_with(algorithm: u8, public_key: []const u8, message: []const u8, signature: []const u8) -> err {
    if algorithm == ALG_ED25519 {
        if public_key.len != 32usize || signature.len != 64usize { ret Malformed }
        var key: sign.Ed25519PublicKey = zero
        var sig: sign.Ed25519Signature = zero
        mem.copy[u8](key.bytes[0..], public_key)
        mem.copy[u8](sig.bytes[0..], signature)
        if sign.ed25519_verify(key, message, sig) { ret ok }
        ret BadSignature
    }
    if algorithm == ALG_ECDSAP256SHA256 {
        if public_key.len != 64usize || signature.len != 64usize { ret Malformed }
        var key: sign.P256PublicKey = zero
        key.bytes[0] = 4u8
        mem.copy[u8](key.bytes[1usize..], public_key)
        var der: [72]u8 = zero
        let (der_len, der_error) = der_from_raw(signature, der[0..])
        if der_error != ok { ret der_error }
        if sign.p256_verify(key, message, der[..der_len]) { ret ok }
        ret BadSignature
    }
    ret Unsupported
}

// RFC 4035 §5.3: `rrset` holds the records of one name/type/class back to back with
// uncompressed names; `rrsig_rdata` and `dnskey_rdata` are their RRSIG and the key.
// `scratch` needs rrsig_rdata.len + 2 * rrset.len bytes. Checks the validity window
// at `now`, the key tag, the algorithm and that the signer covers the owner, then
// verifies the signature over the canonical, rdata-sorted RRset.
fn dnssec_validate(rrset: []const u8, rrsig_rdata: []const u8, dnskey_rdata: []const u8, now: u32, scratch: []u8) -> err {
    let (rrsig, rrsig_error) = rdata_rrsig(rrsig_rdata)
    if rrsig_error != ok { ret rrsig_error }
    let (dnskey, dnskey_error) = rdata_dnskey(dnskey_rdata)
    if dnskey_error != ok { ret dnskey_error }
    if dnskey.protocol != 3u8 || dnskey.algorithm != rrsig.algorithm || key_tag(dnskey_rdata) != rrsig.key_tag { ret Invalid }
    if (now -% rrsig.inception) >= 2147483648u32 { ret NotYetValid }
    if (rrsig.expiration -% now) >= 2147483648u32 { ret Expired }
    if rrsig.algorithm == ALG_RSASHA256 { ret Unsupported }
    let prefix_len = 18usize + rrsig.signer.len
    if scratch.len < prefix_len + 2usize * rrset.len { ret TooSmall }
    mem.copy[u8](scratch[..prefix_len], rrsig_rdata[..prefix_len])
    let (_, signer_error) = lower_name_in_place(scratch, 18usize)
    if signer_error != ok { ret signer_error }
    // Canonicalise each record into the staging half, remembering where it sits.
    let staging = prefix_len + rrset.len
    mem.copy[u8](scratch[staging..staging + rrset.len], rrset)
    var starts: [MAX_RRS]usize = zero
    var ends: [MAX_RRS]usize = zero
    var rdata_starts: [MAX_RRS]usize = zero
    var count = 0usize
    var at = staging
    let end = staging + rrset.len
    while at < end {
        if count == MAX_RRS { ret TooSmall }
        let (after_name, name_error) = lower_name_in_place(scratch[..end], at)
        if name_error != ok { ret name_error }
        if !name_is_within(scratch[at..after_name], rrsig.signer) { ret Invalid }
        if count > 0usize && !equal_bytes(scratch[at..after_name], scratch[starts[0]..rdata_starts[0] - 10usize]) { ret Invalid }
        if after_name + 10usize > end { ret Malformed }
        let kind = load16(scratch, after_name)
        if kind != rrsig.type_covered { ret Invalid }
        store32(scratch, after_name + 4usize, rrsig.original_ttl)
        let rdlength = usize(load16(scratch, after_name + 8usize))
        let rdata_at = after_name + 10usize
        if rdata_at + rdlength > end { ret Malformed }
        let rdata_error = canonical_rdata_in_place(scratch, rdata_at, rdata_at + rdlength, kind)
        if rdata_error != ok { ret rdata_error }
        starts[count] = at
        rdata_starts[count] = rdata_at
        ends[count] = rdata_at + rdlength
        count += 1usize
        at = rdata_at + rdlength
    }
    if count == 0usize { ret Invalid }
    // Insertion sort by canonical rdata, then lay the records out after the prefix.
    var i = 1usize
    while i < count {
        var j = i
        while j > 0usize && less_bytes(scratch[rdata_starts[j]..ends[j]], scratch[rdata_starts[j - 1usize]..ends[j - 1usize]]) {
            let s = starts[j]
            let r = rdata_starts[j]
            let e = ends[j]
            starts[j] = starts[j - 1usize]
            rdata_starts[j] = rdata_starts[j - 1usize]
            ends[j] = ends[j - 1usize]
            starts[j - 1usize] = s
            rdata_starts[j - 1usize] = r
            ends[j - 1usize] = e
            j -= 1usize
        }
        i += 1usize
    }
    var out = prefix_len
    i = 0usize
    while i < count {
        // RFC 4034 §6.3: a duplicate rdata is dropped.
        if i > 0usize && equal_bytes(scratch[rdata_starts[i]..ends[i]], scratch[rdata_starts[i - 1usize]..ends[i - 1usize]]) {
            i += 1usize
            continue
        }
        let length = ends[i] - starts[i]
        mem.copy[u8](scratch[out..out + length], scratch[starts[i]..ends[i]])
        out += length
        i += 1usize
    }
    ret verify_with(rrsig.algorithm, dnskey.public_key, scratch[..out], rrsig.signature)
}

// RFC 4035 §5.2: a parent's DS rdata against a DNSKEY RRset (records back to back,
// uncompressed names) and its RRSIG: some DNSKEY with the SEP flag, the DS key tag
// and algorithm hashes to the DS digest, and the RRset validates with that key.
fn chain_validate(ds_rdata: []const u8, dnskey_rrset: []const u8, rrsig_rdata: []const u8, now: u32, scratch: []u8) -> err {
    let (ds, ds_error) = rdata_ds(ds_rdata)
    if ds_error != ok { ret ds_error }
    var at = 0usize
    var owner: [255]u8 = zero
    var last: err = Invalid
    while at < dnskey_rrset.len {
        let (r, rr_error) = decode_rr(dnskey_rrset, &at, owner[0..])
        if rr_error != ok { ret rr_error }
        if r.kind != TYPE_DNSKEY { ret Invalid }
        let (k, key_error) = rdata_dnskey(r.rdata)
        if key_error != ok { ret key_error }
        if (k.flags & DNSKEY_SEP) == 0u16 || k.algorithm != ds.algorithm || key_tag(r.rdata) != ds.key_tag { continue }
        let (digest, digest_error) = ds_digest(owner[..r.name_len], r.rdata, ds.digest_type)
        if digest_error != ok { ret digest_error }
        if !equal_bytes(digest[0..], ds.digest) { continue }
        last = dnssec_validate(dnskey_rrset, rrsig_rdata, r.rdata, now, scratch)
        if last == ok { ret ok }
    }
    ret last
}

// RFC 8484: the HTTP/1.1 request bytes for `wire_query` against `host` and `path`:
// GET with `?dns=` base64url unpadded, or POST with the body.
fn query_doh(dst: []u8, host: str, path: str, wire_query: []const u8, method_get: bool) -> (usize, err) {
    var at = 0usize
    // The request line and the Host header are built from these: a CR, an LF or, in the
    // path, a space would split the request, so such bytes are refused before any write.
    var checked = 0usize
    while checked < host.len {
        if host[checked] == 13u8 || host[checked] == 10u8 { ret (0usize, TooSmall) }
        checked += 1usize
    }
    checked = 0usize
    while checked < path.len {
        if path[checked] == 13u8 || path[checked] == 10u8 || path[checked] == 32u8 { ret (0usize, TooSmall) }
        checked += 1usize
    }
    if method_get {
        if put(dst, &at, "GET ") != ok || put(dst, &at, path) != ok || put(dst, &at, "?dns=") != ok { ret (0usize, TooSmall) }
        let (encoded, encode_error) = bytes.base64_encode(dst[at..], wire_query, .Url, false)
        if encode_error != ok { ret (0usize, TooSmall) }
        at += encoded.len
    } else {
        if put(dst, &at, "POST ") != ok || put(dst, &at, path) != ok { ret (0usize, TooSmall) }
    }
    if put(dst, &at, " HTTP/1.1\r\nHost: ") != ok || put(dst, &at, host) != ok { ret (0usize, TooSmall) }
    if put(dst, &at, "\r\nAccept: application/dns-message\r\n") != ok { ret (0usize, TooSmall) }
    if !method_get {
        if put(dst, &at, "Content-Type: application/dns-message\r\nContent-Length: ") != ok { ret (0usize, TooSmall) }
        if put_decimal(dst, &at, wire_query.len) != ok || put(dst, &at, "\r\n") != ok { ret (0usize, TooSmall) }
    }
    if put(dst, &at, "\r\n") != ok { ret (0usize, TooSmall) }
    if !method_get {
        if put(dst, &at, wire_query) != ok { ret (0usize, TooSmall) }
    }
    ret (at, ok)
}

fn ascii_fold_equal(a: []const u8, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if lower(a[i]) != lower(b[i]) { ret false }
        i += 1usize
    }
    ret true
}

// The body of an HTTP/1.x response with status 200; `Invalid` for any other status,
// `Malformed` without a status line or blank line, `TooSmall` when Content-Length
// promises more than arrived.
fn doh_response_body(http_response: []const u8) -> ([]const u8, err) {
    var none: []const u8 = zero
    if http_response.len < 12usize || http_response[0] != 72u8 || http_response[1] != 84u8 || http_response[2] != 84u8 || http_response[3] != 80u8 || http_response[4] != 47u8 { ret (none, Malformed) }
    if http_response[8] != 32u8 { ret (none, Malformed) }
    if http_response[9] != 50u8 || http_response[10] != 48u8 || http_response[11] != 48u8 { ret (none, Invalid) }
    var at = 0usize
    var content_length = 0usize
    var has_length = false
    var line_start = 0usize
    while at + 1usize < http_response.len {
        if http_response[at] == 13u8 && http_response[at + 1usize] == 10u8 {
            let line = http_response[line_start..at]
            if line.len > 15usize && ascii_fold_equal(line[..15usize], "content-length:") {
                var i = 15usize
                while i < line.len && line[i] == 32u8 { i += 1usize }
                if i == line.len { ret (none, Malformed) }
                has_length = true
                content_length = 0usize
                while i < line.len {
                    if line[i] < 48u8 || line[i] > 57u8 { ret (none, Malformed) }
                    if content_length > (18446744073709551615usize - usize(line[i] - 48u8)) / 10usize { ret (none, Invalid) }
                    content_length = content_length * 10usize + usize(line[i] - 48u8)
                    i += 1usize
                }
            }
            if line.len == 0usize {
                let body = http_response[at + 2usize..]
                if has_length {
                    if body.len < content_length { ret (none, TooSmall) }
                    ret (body[..content_length], ok)
                }
                ret (body, ok)
            }
            at += 2usize
            line_start = at
            continue
        }
        at += 1usize
    }
    ret (none, Malformed)
}

// RFC 7858 / RFC 1035 §4.2.2: the two-byte length prefix plus the query.
fn query_dot_frame(dst: []u8, wire_query: []const u8) -> (usize, err) {
    if wire_query.len > 65535usize { ret (0usize, Invalid) }
    if dst.len < 2usize + wire_query.len { ret (0usize, TooSmall) }
    store16(dst, 0usize, u16(wire_query.len))
    mem.copy[u8](dst[2usize..2usize + wire_query.len], wire_query)
    ret (2usize + wire_query.len, ok)
}
