// QUIC connection migration (RFC 9000 s8.1, s9, s17, s19) over caller
// storage, no sockets and no crypto: the caller passes packets, clocks
// (`now`) and randomness (the 8-byte challenge). `header_decode` reads
// long headers (Initial, 0-RTT, Handshake, Retry, Version Negotiation)
// and short headers with a caller-known DCID length; `frame_decode` and
// the `frame_encode_*` family cover the frames migration needs
// (PADDING, PING, ACK, NEW_CONNECTION_ID, RETIRE_CONNECTION_ID,
// PATH_CHALLENGE, PATH_RESPONSE, CONNECTION_CLOSE); `CidSet` tracks the
// connection IDs a peer issued; `Connection` holds the paths and the
// two CID sets, `migrate` opens a path on a fresh CID with a padded
// PATH_CHALLENGE, `on_path_response` validates and switches, `retire_old`
// emits RETIRE_CONNECTION_ID for the abandoned CID, `path_timeout` fails
// a validation after three PTOs, and `amplification_allowance` /
// `can_send` are the 3x anti-amplification limit of s8.1.
//
// The QUIC varint (s16) is also in e.net.http3; the eight lines are
// duplicated rather than coupling the two modules.

type Header = struct { long: bool, kind: u8, version: u32, spin: bool, key_phase: bool, dcid: []const u8, scid: []const u8, token: []const u8, payload_offset: usize, length: u64 }
type Frame = struct { kind: u8, seq: u64, retire_prior_to: u64, cid: []const u8, token: []const u8, data: [8]u8, largest: u64, delay: u64, range_count: u64, ranges: []const u8, ecn: [3]u64, error_code: u64, frame_type: u64, reason: []const u8 }
type Address = struct { family: u8, port: u16, ip: [16]u8 }
type PathState = enum u8 { Unvalidated, Validating, Validated, Failed }
type Path = struct { local: Address, remote: Address, state: PathState, challenge: [8]u8, sent_at: u64, dcid_index: u32, bytes_sent: u64, bytes_received: u64 }
type CidSet = struct { seq: []u64, cid: []u8, cid_len: []u8, token: []u8, active: []u8, retire_prior_to: u64, count: usize }
type Connection = struct { paths: []Path, path_count: usize, active_path: u32, previous_path: u32, retire_pending: bool, cids: CidSet, peer_cids: CidSet }
error Malformed
error Invalid
error TooSmall
error Full
error NoCid

const KIND_INITIAL: u8 = 0u8
const KIND_ZERO_RTT: u8 = 1u8
const KIND_HANDSHAKE: u8 = 2u8
const KIND_RETRY: u8 = 3u8
const KIND_VERSION_NEGOTIATION: u8 = 4u8
const FRAME_PADDING: u8 = 0u8
const FRAME_PING: u8 = 1u8
const FRAME_ACK: u8 = 2u8
const FRAME_ACK_ECN: u8 = 3u8
const FRAME_NEW_CONNECTION_ID: u8 = 24u8
const FRAME_RETIRE_CONNECTION_ID: u8 = 25u8
const FRAME_PATH_CHALLENGE: u8 = 26u8
const FRAME_PATH_RESPONSE: u8 = 27u8
const FRAME_CONNECTION_CLOSE: u8 = 28u8
const FRAME_APPLICATION_CLOSE: u8 = 29u8
const MAX_CID: usize = 20usize
const TOKEN_LEN: usize = 16usize
const MIN_DATAGRAM: usize = 1200usize
const FAMILY_IPV4: u8 = 1u8
const FAMILY_IPV6: u8 = 2u8
// A CID slot: 0 retired, 1 issued and never used on a path, 2 in use.
const CID_RETIRED: u8 = 0u8
const CID_UNUSED: u8 = 1u8
const CID_IN_USE: u8 = 2u8

// ---- varint (s16) ---------------------------------------------------------

// Encode `v` (below 2^62) in the shortest form; answers the byte count.
fn varint_encode(dst: []u8, v: u64) -> (usize, err) {
    if v >= (1u64 << 62u32) { ret (0usize, Invalid) }
    var n = 1usize
    var prefix = 0u8
    if v >= 64u64 {
        n = 2usize
        prefix = 64u8
    }
    if v >= 16384u64 {
        n = 4usize
        prefix = 128u8
    }
    if v >= 1073741824u64 {
        n = 8usize
        prefix = 192u8
    }
    if dst.len < n { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        dst[i] = u8((v >> u32((n - 1usize - i) * 8usize)) & 255u64)
        i += 1usize
    }
    dst[0] = dst[0] | prefix
    ret (n, ok)
}

// Decode one varint; answers the value and the bytes consumed.
fn varint_decode(src: []const u8) -> (u64, usize, err) {
    if src.len == 0usize { ret (0u64, 0usize, TooSmall) }
    let n = 1usize << u32(src[0] >> 6u32)
    if src.len < n { ret (0u64, 0usize, TooSmall) }
    var v = u64(src[0] & 63u8)
    var i = 1usize
    while i < n {
        v = (v << 8u32) | u64(src[i])
        i += 1usize
    }
    ret (v, n, ok)
}

// Append a varint at `*at`.
fn put_varint(dst: []u8, at: *usize, v: u64) -> err {
    let (n, e) = varint_encode(dst[*at..], v)
    if e != ok { ret e }
    *at = *at + n
    ret ok
}

fn load32(src: []const u8, at: usize) -> u32 {
    ret (u32(src[at]) << 24u32) | (u32(src[at + 1usize]) << 16u32) | (u32(src[at + 2usize]) << 8u32) | u32(src[at + 3usize])
}

fn copy_bytes(dst: []u8, at: usize, src: []const u8) {
    var i = 0usize
    while i < src.len {
        dst[at + i] = src[i]
        i += 1usize
    }
}

// ---- headers (s17) --------------------------------------------------------

// Read a packet header. A first byte with the form bit set is a long header
// (version 0 is Version Negotiation, `kind` KIND_VERSION_NEGOTIATION);
// otherwise a short header whose DCID is `short_dcid_len` bytes. `Malformed`
// for a clear fixed bit, a CID above 20 bytes (long headers of a non-zero
// version) or a Length overrunning `src`; `TooSmall` when `src` ends early.
// `payload_offset` is where the packet number starts; for Retry and Version
// Negotiation `length` is simply what remains.
fn header_decode(src: []const u8, short_dcid_len: usize) -> (Header, err) {
    var h: Header = zero
    if src.len == 0usize { ret (h, TooSmall) }
    let first = src[0]
    if (first & 128u8) == 0u8 {
        if (first & 64u8) == 0u8 { ret (h, Malformed) }
        if src.len < 1usize + short_dcid_len { ret (h, TooSmall) }
        h.spin = (first & 32u8) != 0u8
        h.key_phase = (first & 4u8) != 0u8
        h.dcid = src[1usize..1usize + short_dcid_len]
        h.payload_offset = 1usize + short_dcid_len
        h.length = u64(src.len - h.payload_offset)
        ret (h, ok)
    }
    h.long = true
    if src.len < 6usize { ret (h, TooSmall) }
    h.version = load32(src, 1usize)
    if h.version != 0u32 && (first & 64u8) == 0u8 { ret (h, Malformed) }
    var at = 5usize
    let dcid_len = usize(src[at])
    at += 1usize
    if h.version != 0u32 && dcid_len > MAX_CID { ret (h, Malformed) }
    if src.len < at + dcid_len + 1usize { ret (h, TooSmall) }
    h.dcid = src[at..at + dcid_len]
    at += dcid_len
    let scid_len = usize(src[at])
    at += 1usize
    if h.version != 0u32 && scid_len > MAX_CID { ret (h, Malformed) }
    if src.len < at + scid_len { ret (h, TooSmall) }
    h.scid = src[at..at + scid_len]
    at += scid_len
    if h.version == 0u32 {
        h.kind = KIND_VERSION_NEGOTIATION
        h.payload_offset = at
        h.length = u64(src.len - at)
        ret (h, ok)
    }
    h.kind = (first >> 4u32) & 3u8
    if h.kind == KIND_INITIAL {
        let (token_len, n, e) = varint_decode(src[at..])
        if e != ok { ret (h, e) }
        at += n
        if src.len < at + usize(token_len) { ret (h, TooSmall) }
        h.token = src[at..at + usize(token_len)]
        at += usize(token_len)
    }
    if h.kind == KIND_RETRY {
        h.payload_offset = at
        h.length = u64(src.len - at)
        ret (h, ok)
    }
    let (length, n, e) = varint_decode(src[at..])
    if e != ok { ret (h, e) }
    at += n
    if u64(src.len - at) < length { ret (h, Malformed) }
    h.payload_offset = at
    h.length = length
    ret (h, ok)
}

// A short header: fixed bit, spin bit, key phase and `dcid`; the packet
// number follows (its length bits are left at one byte). Answers the size.
fn header_encode_short(dst: []u8, dcid: []const u8, spin: bool, key_phase: bool) -> (usize, err) {
    if dcid.len > MAX_CID { ret (0usize, Invalid) }
    if dst.len < 1usize + dcid.len { ret (0usize, TooSmall) }
    var first = 64u8
    if spin { first = first | 32u8 }
    if key_phase { first = first | 4u8 }
    dst[0] = first
    copy_bytes(dst, 1usize, dcid)
    ret (1usize + dcid.len, ok)
}

// A long header of `kind` (KIND_INITIAL..KIND_RETRY): Initial carries
// `token` with its length, Retry appends `token` raw (the retry token) and
// no Length, version 0 stops after the SCID (the caller appends the
// supported versions). `length` is the Length field for the other kinds.
fn header_encode_long(dst: []u8, kind: u8, version: u32, dcid: []const u8, scid: []const u8, token: []const u8, length: u64) -> (usize, err) {
    if kind > KIND_RETRY || dcid.len > MAX_CID || scid.len > MAX_CID { ret (0usize, Invalid) }
    var need = 7usize + dcid.len + scid.len
    if dst.len < need { ret (0usize, TooSmall) }
    dst[0] = 192u8 | (kind << 4u32)
    dst[1] = u8(version >> 24u32)
    dst[2] = u8((version >> 16u32) & 255u32)
    dst[3] = u8((version >> 8u32) & 255u32)
    dst[4] = u8(version & 255u32)
    dst[5] = u8(dcid.len)
    copy_bytes(dst, 6usize, dcid)
    var at = 6usize + dcid.len
    dst[at] = u8(scid.len)
    at += 1usize
    copy_bytes(dst, at, scid)
    at += scid.len
    if version == 0u32 { ret (at, ok) }
    if kind == KIND_INITIAL {
        let (n, e) = varint_encode(dst[at..], u64(token.len))
        if e != ok { ret (0usize, e) }
        at += n
        if dst.len < at + token.len { ret (0usize, TooSmall) }
        copy_bytes(dst, at, token)
        at += token.len
    }
    if kind == KIND_RETRY {
        if dst.len < at + token.len { ret (0usize, TooSmall) }
        copy_bytes(dst, at, token)
        ret (at + token.len, ok)
    }
    let (n, e) = varint_encode(dst[at..], length)
    if e != ok { ret (0usize, e) }
    ret (at + n, ok)
}

// ---- frames (s19) ---------------------------------------------------------

// Decode one frame at the start of `src`; answers it and the bytes consumed.
// A PADDING frame consumes the whole run of zero bytes. ACK ranges are kept
// as their raw bytes in `ranges` for `ack_ranges`; `Invalid` for a frame
// type this module does not handle.
fn frame_decode(src: []const u8) -> (Frame, usize, err) {
    var f: Frame = zero
    if src.len == 0usize { ret (f, 0usize, TooSmall) }
    f.kind = src[0]
    var at = 1usize
    if f.kind == FRAME_PADDING {
        while at < src.len && src[at] == 0u8 { at += 1usize }
        ret (f, at, ok)
    }
    if f.kind == FRAME_PING { ret (f, 1usize, ok) }
    if f.kind == FRAME_PATH_CHALLENGE || f.kind == FRAME_PATH_RESPONSE {
        if src.len < 9usize { ret (f, 0usize, TooSmall) }
        var i = 0usize
        while i < 8usize {
            f.data[i] = src[1usize + i]
            i += 1usize
        }
        ret (f, 9usize, ok)
    }
    if f.kind == FRAME_NEW_CONNECTION_ID {
        let (seq, n1, e1) = varint_decode(src[at..])
        if e1 != ok { ret (f, 0usize, e1) }
        at += n1
        let (prior, n2, e2) = varint_decode(src[at..])
        if e2 != ok { ret (f, 0usize, e2) }
        at += n2
        if src.len < at + 1usize { ret (f, 0usize, TooSmall) }
        let cid_len = usize(src[at])
        at += 1usize
        if cid_len < 1usize || cid_len > MAX_CID || prior > seq { ret (f, 0usize, Malformed) }
        if src.len < at + cid_len + TOKEN_LEN { ret (f, 0usize, TooSmall) }
        f.seq = seq
        f.retire_prior_to = prior
        f.cid = src[at..at + cid_len]
        at += cid_len
        f.token = src[at..at + TOKEN_LEN]
        ret (f, at + TOKEN_LEN, ok)
    }
    if f.kind == FRAME_RETIRE_CONNECTION_ID {
        let (seq, n, e) = varint_decode(src[at..])
        if e != ok { ret (f, 0usize, e) }
        f.seq = seq
        ret (f, at + n, ok)
    }
    if f.kind == FRAME_ACK || f.kind == FRAME_ACK_ECN {
        let (largest, n1, e1) = varint_decode(src[at..])
        if e1 != ok { ret (f, 0usize, e1) }
        at += n1
        let (delay, n2, e2) = varint_decode(src[at..])
        if e2 != ok { ret (f, 0usize, e2) }
        at += n2
        let (range_count, n3, e3) = varint_decode(src[at..])
        if e3 != ok { ret (f, 0usize, e3) }
        at += n3
        f.largest = largest
        f.delay = delay
        f.range_count = range_count
        let start = at
        // Walk the ranges once to find their extent and check they stay above zero.
        let (first, n4, e4) = varint_decode(src[at..])
        if e4 != ok { ret (f, 0usize, e4) }
        at += n4
        if first > largest { ret (f, 0usize, Malformed) }
        var lo = largest - first
        var k = 0u64
        while k < range_count {
            let (gap, ng, eg) = varint_decode(src[at..])
            if eg != ok { ret (f, 0usize, eg) }
            at += ng
            let (length, nl, el) = varint_decode(src[at..])
            if el != ok { ret (f, 0usize, el) }
            at += nl
            if gap + 2u64 > lo { ret (f, 0usize, Malformed) }
            let hi = lo - gap - 2u64
            if length > hi { ret (f, 0usize, Malformed) }
            lo = hi - length
            k += 1u64
        }
        f.ranges = src[start..at]
        if f.kind == FRAME_ACK_ECN {
            var c = 0usize
            while c < 3usize {
                let (count, nc, ec) = varint_decode(src[at..])
                if ec != ok { ret (f, 0usize, ec) }
                at += nc
                f.ecn[c] = count
                c += 1usize
            }
        }
        ret (f, at, ok)
    }
    if f.kind == FRAME_CONNECTION_CLOSE || f.kind == FRAME_APPLICATION_CLOSE {
        let (code, n1, e1) = varint_decode(src[at..])
        if e1 != ok { ret (f, 0usize, e1) }
        at += n1
        f.error_code = code
        if f.kind == FRAME_CONNECTION_CLOSE {
            let (frame_type, n2, e2) = varint_decode(src[at..])
            if e2 != ok { ret (f, 0usize, e2) }
            at += n2
            f.frame_type = frame_type
        }
        let (reason_len, n3, e3) = varint_decode(src[at..])
        if e3 != ok { ret (f, 0usize, e3) }
        at += n3
        if src.len < at + usize(reason_len) { ret (f, 0usize, TooSmall) }
        f.reason = src[at..at + usize(reason_len)]
        ret (f, at + usize(reason_len), ok)
    }
    ret (f, 0usize, Invalid)
}

// The acknowledged ranges of a decoded ACK, largest first, as inclusive
// `lo[i]..hi[i]`; answers the count (`range_count + 1`).
fn ack_ranges(f: *const Frame, lo: []u64, hi: []u64) -> (usize, err) {
    if f.kind != FRAME_ACK && f.kind != FRAME_ACK_ECN { ret (0usize, Invalid) }
    let total = usize(f.range_count) + 1usize
    if lo.len < total || hi.len < total { ret (0usize, TooSmall) }
    var at = 0usize
    let (first, n, _) = varint_decode(f.ranges[at..])
    at += n
    hi[0] = f.largest
    lo[0] = f.largest - first
    var k = 1usize
    while k < total {
        let (gap, ng, _) = varint_decode(f.ranges[at..])
        at += ng
        let (length, nl, _) = varint_decode(f.ranges[at..])
        at += nl
        hi[k] = lo[k - 1usize] - gap - 2u64
        lo[k] = hi[k] - length
        k += 1usize
    }
    ret (total, ok)
}

fn frame_encode_padding(dst: []u8, n: usize) -> (usize, err) {
    if dst.len < n { ret (0usize, TooSmall) }
    var i = 0usize
    while i < n {
        dst[i] = 0u8
        i += 1usize
    }
    ret (n, ok)
}

fn frame_encode_ping(dst: []u8) -> (usize, err) {
    if dst.len < 1usize { ret (0usize, TooSmall) }
    dst[0] = FRAME_PING
    ret (1usize, ok)
}

fn encode_eight(dst: []u8, kind: u8, data: [8]u8) -> (usize, err) {
    if dst.len < 9usize { ret (0usize, TooSmall) }
    dst[0] = kind
    var i = 0usize
    while i < 8usize {
        dst[1usize + i] = data[i]
        i += 1usize
    }
    ret (9usize, ok)
}

fn frame_encode_path_challenge(dst: []u8, data: [8]u8) -> (usize, err) {
    let (n, e) = encode_eight(dst, FRAME_PATH_CHALLENGE, data)
    ret (n, e)
}

fn frame_encode_path_response(dst: []u8, data: [8]u8) -> (usize, err) {
    let (n, e) = encode_eight(dst, FRAME_PATH_RESPONSE, data)
    ret (n, e)
}

// NEW_CONNECTION_ID: `cid` 1..20 bytes, `token` exactly 16.
fn frame_encode_new_connection_id(dst: []u8, seq: u64, retire_prior_to: u64, cid: []const u8, token: []const u8) -> (usize, err) {
    if cid.len < 1usize || cid.len > MAX_CID || token.len != TOKEN_LEN || retire_prior_to > seq { ret (0usize, Invalid) }
    if dst.len < 1usize { ret (0usize, TooSmall) }
    dst[0] = FRAME_NEW_CONNECTION_ID
    var at = 1usize
    let (n1, e1) = varint_encode(dst[at..], seq)
    if e1 != ok { ret (0usize, e1) }
    at += n1
    let (n2, e2) = varint_encode(dst[at..], retire_prior_to)
    if e2 != ok { ret (0usize, e2) }
    at += n2
    if dst.len < at + 1usize + cid.len + TOKEN_LEN { ret (0usize, TooSmall) }
    dst[at] = u8(cid.len)
    at += 1usize
    copy_bytes(dst, at, cid)
    at += cid.len
    copy_bytes(dst, at, token)
    ret (at + TOKEN_LEN, ok)
}

fn frame_encode_retire_connection_id(dst: []u8, seq: u64) -> (usize, err) {
    if dst.len < 1usize { ret (0usize, TooSmall) }
    dst[0] = FRAME_RETIRE_CONNECTION_ID
    let (n, e) = varint_encode(dst[1usize..], seq)
    if e != ok { ret (0usize, e) }
    ret (1usize + n, ok)
}

// ACK (or ACK_ECN when `ecn` is true) of the inclusive ranges `lo[i]..hi[i]`
// given largest first, non-overlapping, at least two apart; `hi[0]` is the
// largest acknowledged. `Invalid` for an empty or misordered list.
fn frame_encode_ack(dst: []u8, delay: u64, lo: []const u64, hi: []const u64, ecn: bool, ecn_counts: [3]u64) -> (usize, err) {
    if lo.len == 0usize || hi.len < lo.len { ret (0usize, Invalid) }
    if dst.len < 1usize { ret (0usize, TooSmall) }
    dst[0] = FRAME_ACK
    if ecn { dst[0] = FRAME_ACK_ECN }
    var at = 1usize
    let e1 = put_varint(dst, &at, hi[0])
    if e1 != ok { ret (0usize, e1) }
    let e2 = put_varint(dst, &at, delay)
    if e2 != ok { ret (0usize, e2) }
    let e3 = put_varint(dst, &at, u64(lo.len - 1usize))
    if e3 != ok { ret (0usize, e3) }
    var i = 0usize
    while i < lo.len {
        if hi[i] < lo[i] { ret (0usize, Invalid) }
        if i > 0usize {
            if lo[i - 1usize] < hi[i] + 2u64 { ret (0usize, Invalid) }
            let eg = put_varint(dst, &at, lo[i - 1usize] - hi[i] - 2u64)
            if eg != ok { ret (0usize, eg) }
        }
        let el = put_varint(dst, &at, hi[i] - lo[i])
        if el != ok { ret (0usize, el) }
        i += 1usize
    }
    if ecn {
        var c = 0usize
        while c < 3usize {
            let ec = put_varint(dst, &at, ecn_counts[c])
            if ec != ok { ret (0usize, ec) }
            c += 1usize
        }
    }
    ret (at, ok)
}

// CONNECTION_CLOSE 0x1c (transport, with `frame_type`) or 0x1d
// (application, `frame_type` ignored) with a `reason` phrase.
fn frame_encode_connection_close(dst: []u8, kind: u8, error_code: u64, frame_type: u64, reason: []const u8) -> (usize, err) {
    if kind != FRAME_CONNECTION_CLOSE && kind != FRAME_APPLICATION_CLOSE { ret (0usize, Invalid) }
    if dst.len < 1usize { ret (0usize, TooSmall) }
    dst[0] = kind
    var at = 1usize
    let e1 = put_varint(dst, &at, error_code)
    if e1 != ok { ret (0usize, e1) }
    if kind == FRAME_CONNECTION_CLOSE {
        let e2 = put_varint(dst, &at, frame_type)
        if e2 != ok { ret (0usize, e2) }
    }
    let e3 = put_varint(dst, &at, u64(reason.len))
    if e3 != ok { ret (0usize, e3) }
    if dst.len < at + reason.len { ret (0usize, TooSmall) }
    copy_bytes(dst, at, reason)
    ret (at + reason.len, ok)
}

// ---- connection IDs (s5.1, s19.15) ------------------------------------------

// A CID set over parallel storage: `seq.len` slots, `cid` 20 bytes per slot,
// `token` 16 per slot, `cid_len` and `active` one byte each.
fn cid_set(seq: []u64, cid: []u8, cid_len: []u8, token: []u8, active: []u8) -> (CidSet, err) {
    var s: CidSet = zero
    let cap = seq.len
    if cid.len < cap * MAX_CID || cid_len.len < cap || token.len < cap * TOKEN_LEN || active.len < cap { ret (s, TooSmall) }
    s.seq = seq
    s.cid = cid
    s.cid_len = cid_len
    s.token = token
    s.active = active
    ret (s, ok)
}

// The bytes of the CID in slot `index`.
fn cid_bytes(s: *const CidSet, index: usize) -> []const u8 {
    let at = index * MAX_CID
    ret s.cid[at..at + usize(s.cid_len[index])]
}

fn cids_find(s: *const CidSet, seq: u64) -> (usize, bool) {
    var i = 0usize
    while i < s.count {
        if s.seq[i] == seq { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn bytes_equal(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// Record a peer-issued CID: a repeat of a known (seq, cid, token) is ignored,
// the same seq with other content or the same cid under another seq is
// `Invalid`, `retire_prior_to > seq` is `Malformed`, `Full` when no slot is
// left. A seq already below `retire_prior_to` is dropped silently, and a
// larger `retire_prior_to` retires every earlier slot.
fn cids_insert(s: *CidSet, seq: u64, retire_prior_to: u64, cid: []const u8, token: []const u8) -> err {
    if retire_prior_to > seq { ret Malformed }
    if cid.len < 1usize || cid.len > MAX_CID || token.len != TOKEN_LEN { ret Invalid }
    var i = 0usize
    while i < s.count {
        if s.seq[i] == seq {
            if bytes_equal(cid_bytes(s, i), cid) && bytes_equal(s.token[i * TOKEN_LEN..(i + 1usize) * TOKEN_LEN], token) { ret ok }
            ret Invalid
        }
        if bytes_equal(cid_bytes(s, i), cid) { ret Invalid }
        i += 1usize
    }
    if seq >= s.retire_prior_to {
        if s.count >= s.seq.len { ret Full }
        let slot = s.count
        s.seq[slot] = seq
        s.cid_len[slot] = u8(cid.len)
        copy_bytes(s.cid, slot * MAX_CID, cid)
        copy_bytes(s.token, slot * TOKEN_LEN, token)
        s.active[slot] = CID_UNUSED
        s.count += 1usize
    }
    if retire_prior_to > s.retire_prior_to {
        s.retire_prior_to = retire_prior_to
        // ponytail: the retired slots are only marked; the RETIRE_CONNECTION_ID
        // frames they owe the peer are left to the caller (cids_retire + encode).
        var k = 0usize
        while k < s.count {
            if s.seq[k] < retire_prior_to { s.active[k] = CID_RETIRED }
            k += 1usize
        }
    }
    ret ok
}

// `cids_insert` from a decoded NEW_CONNECTION_ID frame (`Invalid` otherwise).
fn cids_add(s: *CidSet, f: *const Frame) -> err {
    if f.kind != FRAME_NEW_CONNECTION_ID { ret Invalid }
    ret cids_insert(s, f.seq, f.retire_prior_to, f.cid, f.token)
}

// Retire the CID with `seq`; answers whether an active one was found.
fn cids_retire(s: *CidSet, seq: u64) -> bool {
    let (i, found) = cids_find(s, seq)
    if !found || s.active[i] == CID_RETIRED { ret false }
    s.active[i] = CID_RETIRED
    ret true
}

fn cids_active_count(s: *const CidSet) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.count {
        if s.active[i] != CID_RETIRED { n += 1usize }
        i += 1usize
    }
    ret n
}

// The first slot issued and never used on any path (s9.5).
fn cids_pick_unused(s: *const CidSet) -> (usize, bool) {
    var i = 0usize
    while i < s.count {
        if s.active[i] == CID_UNUSED { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// ---- addresses and paths ----------------------------------------------------

fn ipv4(a: u8, b: u8, c: u8, d: u8, port: u16) -> Address {
    var ip: [16]u8 = zero
    ip[0] = a
    ip[1] = b
    ip[2] = c
    ip[3] = d
    ret Address { family: FAMILY_IPV4, port: port, ip: ip }
}

fn address_equal(a: Address, b: Address) -> bool {
    if a.family != b.family || a.port != b.port { ret false }
    var n = 4usize
    if a.family == FAMILY_IPV6 { n = 16usize }
    var i = 0usize
    while i < n {
        if a.ip[i] != b.ip[i] { ret false }
        i += 1usize
    }
    ret true
}

// The s8.1 anti-amplification allowance: three times what the path has
// received minus what it has sent, unlimited once validated.
fn amplification_allowance(p: *const Path) -> u64 {
    if p.state == .Validated { ret ~0u64 }
    let budget = 3u64 *% p.bytes_received
    if budget <= p.bytes_sent { ret 0u64 }
    ret budget - p.bytes_sent
}

fn can_send(p: *const Path, n: u64) -> bool { ret amplification_allowance(p) >= n }

// A connection with one validated path (the handshake's) using peer CID slot
// `dcid_index`; `paths` is the path storage, `cids` the CIDs we issued and
// `peer_cids` the peer's.
fn connection(paths: []Path, cids: CidSet, peer_cids: CidSet, local: Address, remote: Address, dcid_index: usize) -> (Connection, err) {
    var c: Connection = zero
    if paths.len == 0usize { ret (c, TooSmall) }
    if dcid_index >= peer_cids.count || peer_cids.active[dcid_index] == CID_RETIRED { ret (c, Invalid) }
    c.paths = paths
    c.cids = cids
    c.peer_cids = peer_cids
    c.peer_cids.active[dcid_index] = CID_IN_USE
    var zero_challenge: [8]u8 = zero
    paths[0] = Path { local: local, remote: remote, state: .Validated, challenge: zero_challenge, sent_at: 0u64, dcid_index: u32(dcid_index), bytes_sent: 0u64, bytes_received: 0u64 }
    c.path_count = 1usize
    ret (c, ok)
}

// Count `n` bytes as received on path `index` (feeds the amplification limit).
fn path_received(c: *Connection, index: usize, n: u64) {
    c.paths[index].bytes_received += n
}

// Open a path to `new_remote` on a never-used peer CID and write the probe
// datagram into `out`: a short header, PATH_CHALLENGE with `challenge`, and
// PADDING up to 1200 bytes (s8.2.1, s9.3). `Invalid` when `new_remote` is
// the active path's address, `Full` with no path slot, `NoCid` with no
// unused CID (s9.5 forbids reusing one), `TooSmall` below 1200 bytes.
// Answers the datagram size; the new path is `path_count - 1`, Validating.
fn migrate(c: *Connection, new_remote: Address, now: u64, challenge: [8]u8, out: []u8) -> (usize, err) {
    let cur = c.paths[usize(c.active_path)]
    if address_equal(new_remote, cur.remote) { ret (0usize, Invalid) }
    if c.path_count >= c.paths.len { ret (0usize, Full) }
    let (index, found) = cids_pick_unused(&c.peer_cids)
    if !found { ret (0usize, NoCid) }
    if out.len < MIN_DATAGRAM { ret (0usize, TooSmall) }
    let (h, he) = header_encode_short(out, cid_bytes(&c.peer_cids, index), false, false)
    if he != ok { ret (0usize, he) }
    let (f, fe) = frame_encode_path_challenge(out[h..], challenge)
    if fe != ok { ret (0usize, fe) }
    let (_, pe) = frame_encode_padding(out[h + f..], MIN_DATAGRAM - h - f)
    if pe != ok { ret (0usize, pe) }
    c.peer_cids.active[index] = CID_IN_USE
    c.paths[c.path_count] = Path { local: cur.local, remote: new_remote, state: .Validating, challenge: challenge, sent_at: now, dcid_index: u32(index), bytes_sent: u64(MIN_DATAGRAM), bytes_received: 0u64 }
    c.path_count += 1usize
    ret (MIN_DATAGRAM, ok)
}

// A PATH_RESPONSE arrived: the Validating path whose challenge matches
// becomes Validated and active, and the old active path's CID is queued for
// `retire_old`. Answers whether anything matched (a stray response is ignored).
fn on_path_response(c: *Connection, data: [8]u8, now: u64) -> (bool, err) {
    var i = 0usize
    while i < c.path_count {
        if c.paths[i].state == .Validating {
            var same = true
            var k = 0usize
            while k < 8usize {
                if c.paths[i].challenge[k] != data[k] { same = false }
                k += 1usize
            }
            if same {
                c.paths[i].state = .Validated
                c.paths[i].sent_at = now
                c.previous_path = c.active_path
                c.active_path = u32(i)
                c.retire_pending = true
                ret (true, ok)
            }
        }
        i += 1usize
    }
    ret (false, ok)
}

// After a switch, retire the CID the abandoned path used: writes one
// RETIRE_CONNECTION_ID frame and marks the slot retired. Answers 0 bytes
// when nothing is pending.
fn retire_old(c: *Connection, out: []u8) -> (usize, err) {
    if !c.retire_pending { ret (0usize, ok) }
    let index = usize(c.paths[usize(c.previous_path)].dcid_index)
    let seq = c.peer_cids.seq[index]
    let (n, e) = frame_encode_retire_connection_id(out, seq)
    if e != ok { ret (0usize, e) }
    c.retire_pending = false
    let _ = cids_retire(&c.peer_cids, seq)
    ret (n, ok)
}

// Answer a PATH_CHALLENGE received on path `index` with a PATH_RESPONSE
// datagram on that path (its DCID), padded to 1200 bytes when the
// anti-amplification allowance permits (s8.2.2). Answers the datagram size.
fn on_path_challenge(c: *Connection, data: [8]u8, index: usize, out: []u8) -> (usize, err) {
    if index >= c.path_count { ret (0usize, Invalid) }
    let p = c.paths[index]
    let (h, he) = header_encode_short(out, cid_bytes(&c.peer_cids, usize(p.dcid_index)), false, false)
    if he != ok { ret (0usize, he) }
    let (f, fe) = frame_encode_path_response(out[h..], data)
    if fe != ok { ret (0usize, fe) }
    var total = h + f
    if can_send(&c.paths[index], u64(MIN_DATAGRAM)) {
        let (_, pe) = frame_encode_padding(out[total..], MIN_DATAGRAM - total)
        if pe != ok { ret (0usize, pe) }
        total = MIN_DATAGRAM
    }
    c.paths[index].bytes_sent += u64(total)
    ret (total, ok)
}

// Fail every Validating path whose challenge is `3 * pto` old (s8.2.4); the
// active path is untouched. Answers whether any failed.
// ponytail: a failed path keeps its CID marked in use; retire it by hand if
// the CID budget matters.
fn path_timeout(c: *Connection, now: u64, pto: u64) -> bool {
    var failed = false
    var i = 0usize
    while i < c.path_count {
        if c.paths[i].state == .Validating && now >= c.paths[i].sent_at + 3u64 * pto {
            c.paths[i].state = .Failed
            failed = true
        }
        i += 1usize
    }
    ret failed
}
