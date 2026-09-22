// HTTP/3 (RFC 9114) binary framing over caller buffers, no transport: the
// QUIC variable-length integer (RFC 9000 section 16), frames as type varint,
// length varint and payload (`frame_encode` / `frame_decode`, `frames` splits
// a stream's bytes and stops at a partial tail), SETTINGS and GOAWAY payloads,
// unidirectional stream types, and a QPACK (RFC 9204) header block codec that
// uses the static table only: indexed field lines, literals with a static name
// reference, literals with a literal name, never Huffman and never the dynamic
// table (those decode to `Unsupported`).

type Frame = struct { kind: u64, payload: []const u8 }
error Invalid
error Incomplete
error TooSmall
error Unsupported
error Malformed

// ---- constants -------------------------------------------------------------

fn frame_data() -> u64 { ret 0x00u64 }
fn frame_headers() -> u64 { ret 0x01u64 }
fn frame_cancel_push() -> u64 { ret 0x03u64 }
fn frame_settings() -> u64 { ret 0x04u64 }
fn frame_push_promise() -> u64 { ret 0x05u64 }
fn frame_goaway() -> u64 { ret 0x07u64 }
fn frame_max_push_id() -> u64 { ret 0x0du64 }

fn stream_control() -> u64 { ret 0x00u64 }
fn stream_push() -> u64 { ret 0x01u64 }
fn stream_qpack_encoder() -> u64 { ret 0x02u64 }
fn stream_qpack_decoder() -> u64 { ret 0x03u64 }

fn setting_qpack_max_table_capacity() -> u64 { ret 0x01u64 }
fn setting_max_field_section_size() -> u64 { ret 0x06u64 }
fn setting_qpack_blocked_streams() -> u64 { ret 0x07u64 }

// The HTTP/2 frame types that have no HTTP/3 meaning (section 7.2.8).
fn frame_forbidden(kind: u64) -> bool { ret kind == 0x02u64 || kind == 0x06u64 || kind == 0x08u64 || kind == 0x09u64 }

// A frame type of the form 0x1f * N + 0x21 is reserved and to be ignored.
fn frame_reserved(kind: u64) -> bool { ret kind >= 0x21u64 && (kind - 0x21u64) % 0x1fu64 == 0u64 }

// ---- varints ---------------------------------------------------------------

fn varint_max() -> u64 { ret (1u64 << 62u32) - 1u64 }

fn varint_len(v: u64) -> usize {
    if v < 64u64 { ret 1usize }
    if v < 16384u64 { ret 2usize }
    if v < 1073741824u64 { ret 4usize }
    ret 8usize
}

// `Invalid` above 2^62 - 1, `TooSmall` when `dst` cannot hold the encoding.
fn varint_encode(dst: []u8, v: u64) -> (usize, err) {
    if v > varint_max() { ret (0usize, Invalid) }
    let n = varint_len(v)
    if dst.len < n { ret (0usize, TooSmall) }
    var i = n
    var x = v
    while i > 0usize {
        i -= 1usize
        dst[i] = u8(x & 255u64)
        x = x >> 8u32
    }
    if n == 2usize { dst[0usize] = dst[0usize] | 0x40u8 }
    if n == 4usize { dst[0usize] = dst[0usize] | 0x80u8 }
    if n == 8usize { dst[0usize] = dst[0usize] | 0xc0u8 }
    ret (n, ok)
}

// (value, bytes consumed, err); `Incomplete` when `src` ends inside it.
fn varint_decode(src: []const u8) -> (u64, usize, err) {
    if src.len == 0usize { ret (0u64, 0usize, Incomplete) }
    let n = 1usize << u32(src[0usize] >> 6u32)
    if src.len < n { ret (0u64, 0usize, Incomplete) }
    var v = u64(src[0usize] & 0x3fu8)
    var i = 1usize
    while i < n {
        v = (v << 8u32) | u64(src[i])
        i += 1usize
    }
    ret (v, n, ok)
}

fn append(dst: []u8, p: usize, src: []const u8) -> usize {
    var i = 0usize
    while i < src.len {
        dst[p + i] = src[i]
        i += 1usize
    }
    ret p + src.len
}

// ---- frames ----------------------------------------------------------------

// Type varint, length varint, payload. A forbidden HTTP/2 type is `Invalid`.
fn frame_encode(dst: []u8, kind: u64, payload: []const u8) -> (usize, err) {
    if frame_forbidden(kind) || kind > varint_max() { ret (0usize, Invalid) }
    let need = varint_len(kind) + varint_len(u64(payload.len)) + payload.len
    if dst.len < need { ret (0usize, TooSmall) }
    let (a, _) = varint_encode(dst, kind)
    let (b, _) = varint_encode(dst[a..], u64(payload.len))
    let p = append(dst, a + b, payload)
    ret (p, ok)
}

// (frame, bytes consumed, err). On `Incomplete` the count is the whole
// frame's length when the header was readable, else 0.
fn frame_decode(src: []const u8) -> (Frame, usize, err) {
    let none = Frame { kind: 0u64, payload: src[..0usize] }
    let (kind, a, ea) = varint_decode(src)
    if ea != ok { ret (none, 0usize, ea) }
    if frame_forbidden(kind) { ret (none, 0usize, Invalid) }
    let (length, b, eb) = varint_decode(src[a..])
    if eb != ok { ret (none, 0usize, eb) }
    // A length no caller buffer reaches: report it without a usable count.
    if length > 0xffffffffu64 { ret (none, 0usize, Incomplete) }
    let need = a + b + usize(length)
    if src.len < need { ret (none, need, Incomplete) }
    ret (Frame { kind: kind, payload: src[a + b..need] }, need, ok)
}

// Split `stream` into whole frames: (count, bytes consumed, err). Reserved
// types are listed with their kind for the caller to skip; a partial trailing
// frame stops the walk with `Incomplete`, a forbidden type with `Invalid`,
// and a full `out` with `TooSmall`.
fn frames(stream: []const u8, out: []Frame) -> (usize, usize, err) {
    var n = 0usize
    var pos = 0usize
    while pos < stream.len {
        let (f, used, e) = frame_decode(stream[pos..])
        if e != ok { ret (n, pos, e) }
        if n >= out.len { ret (n, pos, TooSmall) }
        out[n] = f
        n += 1usize
        pos += used
    }
    ret (n, pos, ok)
}

// ---- settings, goaway, stream types ---------------------------------------

// A reserved HTTP/2 setting identifier (section 7.2.4.1).
fn setting_forbidden(id: u64) -> bool { ret id >= 0x02u64 && id <= 0x05u64 }

fn settings_encode(dst: []u8, ids: []const u64, values: []const u64) -> (usize, err) {
    if ids.len != values.len { ret (0usize, Invalid) }
    var p = 0usize
    var i = 0usize
    while i < ids.len {
        if setting_forbidden(ids[i]) { ret (0usize, Invalid) }
        var j = 0usize
        while j < i {
            if ids[j] == ids[i] { ret (0usize, Invalid) }
            j += 1usize
        }
        let (a, ea) = varint_encode(dst[p..], ids[i])
        if ea != ok { ret (0usize, ea) }
        let (b, eb) = varint_encode(dst[p + a..], values[i])
        if eb != ok { ret (0usize, eb) }
        p += a + b
        i += 1usize
    }
    ret (p, ok)
}

// The pairs of a SETTINGS payload: duplicate or HTTP/2 identifiers are
// `Invalid`, a truncated varint `Malformed`, more pairs than room `TooSmall`.
fn settings_decode(payload: []const u8, ids: []u64, values: []u64) -> (usize, err) {
    var n = 0usize
    var p = 0usize
    while p < payload.len {
        let (id, a, ea) = varint_decode(payload[p..])
        if ea != ok { ret (n, Malformed) }
        let (v, b, eb) = varint_decode(payload[p + a..])
        if eb != ok { ret (n, Malformed) }
        if setting_forbidden(id) { ret (n, Invalid) }
        var j = 0usize
        while j < n {
            if ids[j] == id { ret (n, Invalid) }
            j += 1usize
        }
        if n >= ids.len || n >= values.len { ret (n, TooSmall) }
        ids[n] = id
        values[n] = v
        n += 1usize
        p += a + b
    }
    ret (n, ok)
}

fn goaway_encode(dst: []u8, id: u64) -> (usize, err) {
    let (n, e) = varint_encode(dst, id)
    ret (n, e)
}

// The stream or push id of a GOAWAY payload; anything but one varint is `Malformed`.
fn goaway_decode(payload: []const u8) -> (u64, err) {
    let (id, n, e) = varint_decode(payload)
    if e != ok || n != payload.len { ret (0u64, Malformed) }
    ret (id, ok)
}

// The first varint of a unidirectional stream.
fn stream_type_encode(dst: []u8, kind: u64) -> (usize, err) {
    let (n, e) = varint_encode(dst, kind)
    ret (n, e)
}

fn stream_type_decode(src: []const u8) -> (u64, usize, err) {
    let (kind, n, e) = varint_decode(src)
    ret (kind, n, e)
}

// ---- QPACK static table (RFC 9204 Appendix A) ------------------------------

fn static_count() -> usize { ret 99usize }

fn static_name(i: usize) -> str {
    let t: [99]str = [99]str{ ":authority", ":path", "age", "content-disposition", "content-length", "cookie", "date", "etag", "if-modified-since", "if-none-match", "last-modified", "link", "location", "referer", "set-cookie", ":method", ":method", ":method", ":method", ":method", ":method", ":method", ":scheme", ":scheme", ":status", ":status", ":status", ":status", ":status", "accept", "accept", "accept-encoding", "accept-ranges", "access-control-allow-headers", "access-control-allow-headers", "access-control-allow-origin", "cache-control", "cache-control", "cache-control", "cache-control", "cache-control", "cache-control", "content-encoding", "content-encoding", "content-type", "content-type", "content-type", "content-type", "content-type", "content-type", "content-type", "content-type", "content-type", "content-type", "content-type", "range", "strict-transport-security", "strict-transport-security", "strict-transport-security", "vary", "vary", "x-content-type-options", "x-xss-protection", ":status", ":status", ":status", ":status", ":status", ":status", ":status", ":status", ":status", "accept-language", "access-control-allow-credentials", "access-control-allow-credentials", "access-control-allow-headers", "access-control-allow-methods", "access-control-allow-methods", "access-control-allow-methods", "access-control-expose-headers", "access-control-request-headers", "access-control-request-method", "access-control-request-method", "alt-svc", "authorization", "content-security-policy", "early-data", "expect-ct", "forwarded", "if-range", "origin", "purpose", "server", "timing-allow-origin", "upgrade-insecure-requests", "user-agent", "x-forwarded-for", "x-frame-options", "x-frame-options" }
    ret t[i]
}

fn static_value(i: usize) -> str {
    let t: [99]str = [99]str{ "", "/", "0", "", "0", "", "", "", "", "", "", "", "", "", "", "CONNECT", "DELETE", "GET", "HEAD", "OPTIONS", "POST", "PUT", "http", "https", "103", "200", "304", "404", "503", "*/*", "application/dns-message", "gzip, deflate, br", "bytes", "cache-control", "content-type", "*", "max-age=0", "max-age=2592000", "max-age=604800", "no-cache", "no-store", "public, max-age=31536000", "br", "gzip", "application/dns-message", "application/javascript", "application/json", "application/x-www-form-urlencoded", "image/gif", "image/jpeg", "image/png", "text/css", "text/html; charset=utf-8", "text/plain", "text/plain;charset=utf-8", "bytes=0-", "max-age=31536000", "max-age=31536000; includesubdomains", "max-age=31536000; includesubdomains; preload", "accept-encoding", "origin", "nosniff", "1; mode=block", "100", "204", "206", "302", "400", "403", "421", "425", "500", "", "FALSE", "TRUE", "*", "get", "get, post, options", "options", "content-length", "content-type", "get", "post", "clear", "", "script-src 'none'; object-src 'none'; base-uri 'none'", "1", "", "", "", "", "prefetch", "", "*", "1", "", "", "deny", "sameorigin" }
    ret t[i]
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// The first static entry with this name and value, or the first with the
// name alone: (index, whole match, any match).
fn static_find(name: str, value: str) -> (usize, bool, bool) {
    var name_at = 0usize
    var have_name = false
    var i = 0usize
    while i < static_count() {
        if same(static_name(i), name) {
            if same(static_value(i), value) { ret (i, true, true) }
            if !have_name {
                name_at = i
                have_name = true
            }
        }
        i += 1usize
    }
    ret (name_at, false, have_name)
}

// ---- prefix integers (RFC 7541 section 5.1) --------------------------------

// `flags` are the bits above the `bits`-wide prefix of the first byte.
fn prefix_int_encode(dst: []u8, flags: u8, bits: u32, v: u64) -> (usize, err) {
    let m = (1u64 << bits) - 1u64
    if dst.len < 1usize { ret (0usize, TooSmall) }
    if v < m {
        dst[0usize] = flags | u8(v)
        ret (1usize, ok)
    }
    dst[0usize] = flags | u8(m)
    var x = v - m
    var p = 1usize
    while x >= 128u64 {
        if p >= dst.len { ret (0usize, TooSmall) }
        dst[p] = u8(x & 127u64) | 128u8
        x = x >> 7u32
        p += 1usize
    }
    if p >= dst.len { ret (0usize, TooSmall) }
    dst[p] = u8(x)
    ret (p + 1usize, ok)
}

// (value, bytes consumed, err): `Malformed` when `src` ends inside it or the
// continuation runs past 64 bits.
fn prefix_int_decode(src: []const u8, bits: u32) -> (u64, usize, err) {
    if src.len == 0usize { ret (0u64, 0usize, Malformed) }
    let m = (1u64 << bits) - 1u64
    var v = u64(src[0usize]) & m
    if v < m { ret (v, 1usize, ok) }
    var p = 1usize
    var shift = 0u32
    while true {
        if p >= src.len || shift > 56u32 { ret (0u64, 0usize, Malformed) }
        let b = src[p]
        p += 1usize
        v += u64(b & 127u8) << shift
        shift += 7u32
        if (b & 128u8) == 0u8 { ret (v, p, ok) }
    }
    ret (0u64, 0usize, Malformed)
}

// A string literal without Huffman coding: 7-bit prefix length, then the bytes.
fn string_encode(dst: []u8, s: str) -> (usize, err) {
    let (n, e) = prefix_int_encode(dst, 0u8, 7u32, u64(s.len))
    if e != ok { ret (0usize, e) }
    if dst.len - n < s.len { ret (0usize, TooSmall) }
    let p = append(dst, n, s)
    ret (p, ok)
}

// Copy the literal at `src` into `scratch` from `*used`: (text, consumed, err).
// A set Huffman bit is `Unsupported`.
fn string_decode(src: []const u8, scratch: []u8, used: *usize) -> (str, usize, err) {
    if src.len == 0usize { ret (scratch[..0usize], 0usize, Malformed) }
    if (src[0usize] & 128u8) != 0u8 { ret (scratch[..0usize], 0usize, Unsupported) }
    let (n, p, e) = prefix_int_decode(src, 7u32)
    if e != ok { ret (scratch[..0usize], 0usize, e) }
    if n > u64(src.len) || src.len - p < usize(n) { ret (scratch[..0usize], 0usize, Malformed) }
    let count = usize(n)
    if scratch.len - *used < count { ret (scratch[..0usize], 0usize, TooSmall) }
    let lo = *used
    let hi = append(scratch, lo, src[p..p + count])
    *used = hi
    ret (scratch[lo..hi], p + count, ok)
}

// ---- QPACK header blocks -----------------------------------------------------

// A field section whose Required Insert Count and Delta Base are 0 (the two
// prefix bytes `00 00`), then one line per pair: indexed when name and value
// are a static entry, a static name reference with a literal value when only
// the name is, a literal name and value otherwise. Never Huffman coded.
fn headers_encode(dst: []u8, names: []const str, values: []const str) -> (usize, err) {
    if names.len != values.len { ret (0usize, Invalid) }
    if dst.len < 2usize { ret (0usize, TooSmall) }
    dst[0usize] = 0u8
    dst[1usize] = 0u8
    var p = 2usize
    var i = 0usize
    while i < names.len {
        let (idx, whole, named) = static_find(names[i], values[i])
        if whole {
            let (n, e) = prefix_int_encode(dst[p..], 0xc0u8, 6u32, u64(idx))
            if e != ok { ret (0usize, e) }
            p += n
        } else {
            if named {
                let (n, e) = prefix_int_encode(dst[p..], 0x50u8, 4u32, u64(idx))
                if e != ok { ret (0usize, e) }
                p += n
            } else {
                let (n, e) = prefix_int_encode(dst[p..], 0x20u8, 3u32, u64(names[i].len))
                if e != ok { ret (0usize, e) }
                if dst.len - p - n < names[i].len { ret (0usize, TooSmall) }
                p = append(dst, p + n, names[i])
            }
            let (m, e2) = string_encode(dst[p..], values[i])
            if e2 != ok { ret (0usize, e2) }
            p += m
        }
        i += 1usize
    }
    ret (p, ok)
}

// The pairs of a header block: names and values that are literals are copied
// into `scratch`, static ones point at the table. `Unsupported` for a non-zero
// Required Insert Count or Delta Base, any dynamic-table or post-base line and
// any Huffman-coded string; `Invalid` for a static index past the table;
// `Malformed` for a truncated block; `TooSmall` when the outputs run out.
fn headers_decode(block: []const u8, names_out: []str, values_out: []str, scratch: []u8) -> (usize, err) {
    let (ric, a, ea) = prefix_int_decode(block, 8u32)
    if ea != ok { ret (0usize, Malformed) }
    if ric != 0u64 { ret (0usize, Unsupported) }
    let (base, b, eb) = prefix_int_decode(block[a..], 7u32)
    if eb != ok { ret (0usize, Malformed) }
    if base != 0u64 || (block[a] & 128u8) != 0u8 { ret (0usize, Unsupported) }
    var p = a + b
    var n = 0usize
    var used = 0usize
    while p < block.len {
        if n >= names_out.len || n >= values_out.len { ret (n, TooSmall) }
        let lead = block[p]
        if (lead & 0x80u8) != 0u8 {
            // indexed field line: 1 T xxxxxx
            if (lead & 0x40u8) == 0u8 { ret (n, Unsupported) }
            let (idx, m, e) = prefix_int_decode(block[p..], 6u32)
            if e != ok { ret (n, e) }
            if idx >= u64(static_count()) { ret (n, Invalid) }
            names_out[n] = static_name(usize(idx))
            values_out[n] = static_value(usize(idx))
            p += m
        } else {
            if (lead & 0x40u8) != 0u8 {
                // literal with name reference: 01 N T xxxx
                if (lead & 0x10u8) == 0u8 { ret (n, Unsupported) }
                let (idx, m, e) = prefix_int_decode(block[p..], 4u32)
                if e != ok { ret (n, e) }
                if idx >= u64(static_count()) { ret (n, Invalid) }
                names_out[n] = static_name(usize(idx))
                p += m
            } else {
                if (lead & 0x20u8) == 0u8 { ret (n, Unsupported) }
                // literal with literal name: 001 N H xxx
                if (lead & 0x08u8) != 0u8 { ret (n, Unsupported) }
                let (count, m, e) = prefix_int_decode(block[p..], 3u32)
                if e != ok { ret (n, e) }
                p += m
                if count > u64(block.len) || block.len - p < usize(count) { ret (n, Malformed) }
                if scratch.len - used < usize(count) { ret (n, TooSmall) }
                let hi = append(scratch, used, block[p..p + usize(count)])
                names_out[n] = scratch[used..hi]
                used = hi
                p += usize(count)
            }
            let (value, m2, e2) = string_decode(block[p..], scratch, &used)
            if e2 != ok { ret (n, e2) }
            values_out[n] = value
            p += m2
        }
        n += 1usize
    }
    ret (n, ok)
}
