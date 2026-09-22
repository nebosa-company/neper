// STUN messages (RFC 5389/8489) and ICE candidate gathering (RFC 8445) over
// caller storage, without sockets: `encode_binding_request` and
// `encode_binding_response` write a message, `decode` checks a header and
// `attribute_next` walks the TLV attributes; `xor_mapped_address`,
// `mapped_address` and `error_code` read the common values;
// `add_message_integrity` / `verify_message_integrity` are HMAC-SHA1 over the
// message with the header length patched as the RFC prescribes, and
// `add_fingerprint` / `verify_fingerprint` are CRC32 xor 0x5354554e. The ICE
// half computes RFC 8445 priorities and foundations, gathers host candidates
// from local addresses, adds a server-reflexive one from a caller-relayed
// binding response, sorts them, and forms the pruned, priority-ordered
// candidate pairs. Every response is caller-relayed: the module never sends.

use e.algo.hash as ahash
use e.crypto.hash as chash

type Address = struct { family: u8, port: u16, ip: [16]u8 }
type Header = struct { kind: u16, length: u16, txid: [12]u8 }
type Candidate = struct { kind: u8, address: Address, base: Address, priority: u32, foundation: u32, component: u8 }
type Pair = struct { local: u32, remote: u32, priority: u64 }
error Malformed
error TooSmall
error Invalid

const COOKIE: u32 = 554869826u32
const FINGERPRINT_XOR: u32 = 1398035790u32
const BINDING_REQUEST: u16 = 1u16
const BINDING_RESPONSE: u16 = 257u16
const BINDING_ERROR: u16 = 273u16
const ATTR_MAPPED_ADDRESS: u16 = 1u16
const ATTR_USERNAME: u16 = 6u16
const ATTR_MESSAGE_INTEGRITY: u16 = 8u16
const ATTR_ERROR_CODE: u16 = 9u16
const ATTR_UNKNOWN_ATTRIBUTES: u16 = 10u16
const ATTR_REALM: u16 = 20u16
const ATTR_NONCE: u16 = 21u16
const ATTR_XOR_MAPPED_ADDRESS: u16 = 32u16
const ATTR_PRIORITY: u16 = 36u16
const ATTR_USE_CANDIDATE: u16 = 37u16
const ATTR_SOFTWARE: u16 = 32802u16
const ATTR_FINGERPRINT: u16 = 32808u16
const ATTR_ICE_CONTROLLED: u16 = 32809u16
const ATTR_ICE_CONTROLLING: u16 = 32810u16
const FAMILY_IPV4: u8 = 1u8
const FAMILY_IPV6: u8 = 2u8
const HOST: u8 = 0u8
const SERVER_REFLEXIVE: u8 = 1u8
const PEER_REFLEXIVE: u8 = 2u8
const RELAYED: u8 = 3u8
// The largest message `verify_message_integrity` and `add_message_integrity` accept.
// ponytail: a fixed HMAC scratch buffer; stream the hash if messages outgrow 1964 bytes.
const MAX_MESSAGE: usize = 1964usize

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

fn padded(length: usize) -> usize { ret (length + 3usize) & ~3usize }

// An IPv4 address from its four octets.
fn ipv4(a: u8, b: u8, c: u8, d: u8, port: u16) -> Address {
    var ip: [16]u8 = zero
    ip[0] = a
    ip[1] = b
    ip[2] = c
    ip[3] = d
    ret Address { family: FAMILY_IPV4, port: port, ip: ip }
}

fn ip_len(family: u8) -> usize {
    if family == FAMILY_IPV6 { ret 16usize }
    ret 4usize
}

fn address_equal(a: Address, b: Address) -> bool {
    if a.family != b.family || a.port != b.port { ret false }
    var i = 0usize
    while i < ip_len(a.family) {
        if a.ip[i] != b.ip[i] { ret false }
        i += 1usize
    }
    ret true
}

// The class of a message type: 0 request, 1 indication, 2 success, 3 error.
fn message_class(kind: u16) -> u8 {
    ret u8(((kind >> 4u32) & 1u16) | ((kind >> 7u32) & 2u16))
}

// The method of a message type with the class bits removed (1 is Binding).
fn message_method(kind: u16) -> u16 {
    ret (kind & 15u16) | ((kind >> 1u32) & 112u16) | ((kind >> 2u32) & 3968u16)
}

// Header `kind` with a zero length; answers 20.
fn encode_header(dst: []u8, kind: u16, txid: [12]u8) -> (usize, err) {
    if dst.len < 20usize { ret (0usize, TooSmall) }
    store16(dst, 0usize, kind)
    store16(dst, 2usize, 0u16)
    store32(dst, 4usize, COOKIE)
    var i = 0usize
    while i < 12usize {
        dst[8usize + i] = txid[i]
        i += 1usize
    }
    ret (20usize, ok)
}

// Append attribute `kind` with `value` (zero padded to 4) at `*used` and fix the
// header length; `Invalid` for a value above 65535 bytes.
fn add_attribute(buf: []u8, used: *usize, kind: u16, value: []const u8) -> err {
    if value.len > 65535usize { ret Invalid }
    let at = *used
    let total = 4usize + padded(value.len)
    if at < 20usize || at + total > buf.len { ret TooSmall }
    store16(buf, at, kind)
    store16(buf, at + 2usize, u16(value.len))
    var i = 0usize
    while i < value.len {
        buf[at + 4usize + i] = value[i]
        i += 1usize
    }
    while i < padded(value.len) {
        buf[at + 4usize + i] = 0u8
        i += 1usize
    }
    *used = at + total
    store16(buf, 2usize, u16(*used - 20usize))
    ret ok
}

// A Binding request with optional SOFTWARE (when non-empty) and FINGERPRINT.
fn encode_binding_request(dst: []u8, txid: [12]u8, software: str, fingerprint: bool) -> (usize, err) {
    var (used, e) = encode_header(dst, BINDING_REQUEST, txid)
    if e != ok { ret (0usize, e) }
    if software.len > 0usize {
        e = add_attribute(dst, &used, ATTR_SOFTWARE, software)
        if e != ok { ret (0usize, e) }
    }
    if fingerprint {
        e = add_fingerprint(dst, &used)
        if e != ok { ret (0usize, e) }
    }
    ret (used, ok)
}

// A Binding success response carrying `mapped` as XOR-MAPPED-ADDRESS (`xor`) or MAPPED-ADDRESS.
fn encode_binding_response(dst: []u8, txid: [12]u8, mapped: Address, xor: bool) -> (usize, err) {
    var (used, e) = encode_header(dst, BINDING_RESPONSE, txid)
    if e != ok { ret (0usize, e) }
    var value: [20]u8 = zero
    value[1] = mapped.family
    store16(value[0..], 2usize, mapped.port)
    var i = 0usize
    while i < ip_len(mapped.family) {
        value[4usize + i] = mapped.ip[i]
        i += 1usize
    }
    if xor {
        store16(value[0..], 2usize, mapped.port ^ u16(COOKIE >> 16u32))
        i = 0usize
        while i < ip_len(mapped.family) {
            value[4usize + i] = value[4usize + i] ^ xor_byte(txid, i)
            i += 1usize
        }
        e = add_attribute(dst, &used, ATTR_XOR_MAPPED_ADDRESS, value[..4usize + ip_len(mapped.family)])
    } else {
        e = add_attribute(dst, &used, ATTR_MAPPED_ADDRESS, value[..4usize + ip_len(mapped.family)])
    }
    if e != ok { ret (0usize, e) }
    ret (used, ok)
}

// Byte `i` of the XOR mask: the cookie followed by the transaction id.
fn xor_byte(txid: [12]u8, i: usize) -> u8 {
    if i < 4usize { ret u8((COOKIE >> u32((3usize - i) * 8usize)) & 255u32) }
    ret txid[i - 4usize]
}

// Check and read the header: `Malformed` when the first two bits are set, the
// cookie is wrong, the length is not a multiple of 4, or `src` is shorter than
// the header plus its declared length. Trailing bytes are tolerated.
fn decode(src: []const u8) -> (Header, err) {
    var h: Header = zero
    if src.len < 20usize { ret (h, TooSmall) }
    if (src[0] & 192u8) != 0u8 || load32(src, 4usize) != COOKIE { ret (h, Malformed) }
    h.kind = load16(src, 0usize)
    h.length = load16(src, 2usize)
    if usize(h.length) % 4usize != 0usize || 20usize + usize(h.length) > src.len { ret (h, Malformed) }
    var i = 0usize
    while i < 12usize {
        h.txid[i] = src[8usize + i]
        i += 1usize
    }
    ret (h, ok)
}

// The attribute at `*pos` (start at 20): its type, value, whether another
// follows, and `Malformed` when the value overruns the message.
fn attribute_next(src: []const u8, pos: *usize) -> (u16, []const u8, bool, err) {
    let end = 20usize + usize(load16(src, 2usize))
    let at = *pos
    if at + 4usize > end || end > src.len { ret (0u16, src[0..0usize], false, Malformed) }
    let kind = load16(src, at)
    let length = usize(load16(src, at + 2usize))
    if at + 4usize + length > end { ret (0u16, src[0..0usize], false, Malformed) }
    *pos = at + 4usize + padded(length)
    ret (kind, src[at + 4usize..at + 4usize + length], *pos < end, ok)
}

// Find the first attribute of `kind`; answers its value and its offset in `src`.
fn find_attribute(src: []const u8, kind: u16) -> ([]const u8, usize, bool) {
    var pos = 20usize
    var more = true
    while more {
        let start = pos
        let (found, value, rest, e) = attribute_next(src, &pos)
        if e != ok { ret (src[0..0usize], 0usize, false) }
        if found == kind { ret (value, start, true) }
        more = rest
    }
    ret (src[0..0usize], 0usize, false)
}

// A MAPPED-ADDRESS value.
fn mapped_address(value: []const u8) -> (Address, err) {
    var a: Address = zero
    if value.len < 8usize { ret (a, Malformed) }
    a.family = value[1]
    if a.family != FAMILY_IPV4 && a.family != FAMILY_IPV6 { ret (a, Malformed) }
    if value.len < 4usize + ip_len(a.family) { ret (a, Malformed) }
    a.port = load16(value, 2usize)
    var i = 0usize
    while i < ip_len(a.family) {
        a.ip[i] = value[4usize + i]
        i += 1usize
    }
    ret (a, ok)
}

// An XOR-MAPPED-ADDRESS value unmasked with the cookie (and `txid` for IPv6).
fn xor_mapped_address(value: []const u8, txid: [12]u8) -> (Address, err) {
    var (a, e) = mapped_address(value)
    if e != ok { ret (a, e) }
    a.port = a.port ^ u16(COOKIE >> 16u32)
    var i = 0usize
    while i < ip_len(a.family) {
        a.ip[i] = a.ip[i] ^ xor_byte(txid, i)
        i += 1usize
    }
    ret (a, ok)
}

// An ERROR-CODE value: the code (class * 100 + number) and the reason phrase.
fn error_code(value: []const u8) -> (u32, str, err) {
    if value.len < 4usize { ret (0u32, "", Malformed) }
    let code = u32(value[2] & 7u8) * 100u32 + u32(value[3])
    ret (code, value[4usize..], ok)
}

// Append MESSAGE-INTEGRITY over `buf[..*used]` with the header length covering
// the new attribute; `key` is the short-term password or `long_term_key`.
fn add_message_integrity(buf: []u8, used: *usize, key: []const u8) -> err {
    let at = *used
    if at < 20usize || at > MAX_MESSAGE { ret Invalid }
    if at + 24usize > buf.len { ret TooSmall }
    store16(buf, 2usize, u16(at + 24usize - 20usize))
    let mac = hmac_sha1(key, buf[..at], u16(at + 4usize))
    ret add_attribute(buf, used, ATTR_MESSAGE_INTEGRITY, mac[0..])
}

// True when `src` carries MESSAGE-INTEGRITY and it matches `key`.
fn verify_message_integrity(src: []const u8, key: []const u8) -> bool {
    let (value, start, found) = find_attribute(src, ATTR_MESSAGE_INTEGRITY)
    if !found || value.len != 20usize || start > MAX_MESSAGE { ret false }
    let mac = hmac_sha1(key, src[..start], u16(start + 4usize))
    var diff = 0u8
    var i = 0usize
    while i < 20usize {
        diff = diff | (mac[i] ^ value[i])
        i += 1usize
    }
    ret diff == 0u8
}

// HMAC-SHA1 over `msg` with its header length field replaced by `length`.
fn hmac_sha1(key: []const u8, msg: []const u8, length: u16) -> [20]u8 {
    var k: [64]u8 = zero
    var i = 0usize
    if key.len > 64usize {
        let digest = chash.legacy_sha1(key)
        while i < 20usize {
            k[i] = digest[i]
            i += 1usize
        }
    } else {
        while i < key.len {
            k[i] = key[i]
            i += 1usize
        }
    }
    var scratch: [2048]u8 = zero
    i = 0usize
    while i < 64usize {
        scratch[i] = k[i] ^ 54u8
        i += 1usize
    }
    i = 0usize
    while i < msg.len {
        scratch[64usize + i] = msg[i]
        i += 1usize
    }
    store16(scratch[0..], 66usize, length)
    let inner = chash.legacy_sha1(scratch[..64usize + msg.len])
    i = 0usize
    while i < 64usize {
        scratch[i] = k[i] ^ 92u8
        i += 1usize
    }
    i = 0usize
    while i < 20usize {
        scratch[64usize + i] = inner[i]
        i += 1usize
    }
    ret chash.legacy_sha1(scratch[..84usize])
}

// Append FINGERPRINT (CRC32 of everything before it xor 0x5354554e) with the
// header length covering it.
fn add_fingerprint(buf: []u8, used: *usize) -> err {
    let at = *used
    if at < 20usize { ret Invalid }
    if at + 8usize > buf.len { ret TooSmall }
    store16(buf, 2usize, u16(at + 8usize - 20usize))
    var value: [4]u8 = zero
    store32(value[0..], 0usize, ahash.crc32(buf[..at]) ^ FINGERPRINT_XOR)
    ret add_attribute(buf, used, ATTR_FINGERPRINT, value[0..])
}

// True when `src` ends with a FINGERPRINT that matches.
fn verify_fingerprint(src: []const u8) -> bool {
    let (value, start, found) = find_attribute(src, ATTR_FINGERPRINT)
    if !found || value.len != 4usize { ret false }
    if start + 8usize != 20usize + usize(load16(src, 2usize)) { ret false }
    ret load32(value, 0usize) == (ahash.crc32(src[..start]) ^ FINGERPRINT_XOR)
}

// RFC 8445 §5.1.2.1 candidate priority: type preference 126/100/110/0 for
// host/server-reflexive/peer-reflexive/relayed.
fn priority(kind: u8, local_pref: u16, component: u8) -> u32 {
    var type_pref = 0u32
    if kind == HOST { type_pref = 126u32 }
    if kind == SERVER_REFLEXIVE { type_pref = 100u32 }
    if kind == PEER_REFLEXIVE { type_pref = 110u32 }
    ret (type_pref << 24u32) + (u32(local_pref) << 8u32) + (256u32 - u32(component))
}

// Foundation: FNV-1a over type, base family and IP, and server family and IP,
// so candidates of one type from one base towards one server share it.
fn foundation(kind: u8, base: Address, server: Address) -> u32 {
    var data: [35]u8 = zero
    data[0] = kind
    data[1] = base.family
    var i = 0usize
    while i < 16usize {
        data[2usize + i] = base.ip[i]
        data[19usize + i] = server.ip[i]
        i += 1usize
    }
    data[18] = server.family
    ret ahash.fnv1a32(data[0..])
}

// Host candidates for every local address and component 1..`components`, with
// local preference 65535 minus the address index; duplicates are dropped.
fn gather_candidates(locals: []const Address, components: u8, out: []Candidate) -> (usize, err) {
    var count = 0usize
    var i = 0usize
    while i < locals.len {
        if i > 65535usize { ret (count, Invalid) }
        var component = 1u8
        while component <= components {
            var duplicate = false
            var j = 0usize
            while j < count {
                if out[j].component == component && address_equal(out[j].address, locals[i]) { duplicate = true }
                j += 1usize
            }
            if !duplicate {
                if count >= out.len { ret (count, TooSmall) }
                let server: Address = zero
                out[count] = Candidate { kind: HOST, address: locals[i], base: locals[i], priority: priority(HOST, u16(65535usize - i), component), foundation: foundation(HOST, locals[i], server), component: component }
                count += 1usize
            }
            component += 1u8
        }
        i += 1usize
    }
    ret (count, ok)
}

// Add a server-reflexive candidate from a caller-relayed Binding response to
// the host candidate `out[base_index]`, sent to `server`. Silently dropped
// when it equals the host address (RFC 8445 §5.1.3). `Invalid` when the
// response is not a Binding success carrying a mapped address.
fn gather_reflexive(out: []Candidate, count: *usize, base_index: usize, server: Address, response: []const u8) -> err {
    if base_index >= *count { ret Invalid }
    let (h, e) = decode(response)
    if e != ok { ret e }
    if h.kind != BINDING_RESPONSE { ret Invalid }
    let (xor_value, _, has_xor) = find_attribute(response, ATTR_XOR_MAPPED_ADDRESS)
    var mapped: Address = zero
    if has_xor {
        let (a, ae) = xor_mapped_address(xor_value, h.txid)
        if ae != ok { ret ae }
        mapped = a
    } else {
        let (plain_value, _, has_plain) = find_attribute(response, ATTR_MAPPED_ADDRESS)
        if !has_plain { ret Invalid }
        let (a, ae) = mapped_address(plain_value)
        if ae != ok { ret ae }
        mapped = a
    }
    let base = out[base_index]
    if address_equal(mapped, base.address) { ret ok }
    var j = 0usize
    while j < *count {
        if out[j].component == base.component && address_equal(out[j].address, mapped) { ret ok }
        j += 1usize
    }
    if *count >= out.len { ret TooSmall }
    let local_pref = u16((base.priority >> 8u32) & 65535u32)
    out[*count] = Candidate { kind: SERVER_REFLEXIVE, address: mapped, base: base.base, priority: priority(SERVER_REFLEXIVE, local_pref, base.component), foundation: foundation(SERVER_REFLEXIVE, base.base, server), component: base.component }
    *count += 1usize
    ret ok
}

// Stable sort by priority, highest first.
fn sort_candidates(out: []Candidate) {
    var i = 1usize
    while i < out.len {
        let item = out[i]
        var j = i
        while j > 0usize && out[j - 1usize].priority < item.priority {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = item
        i += 1usize
    }
}

// RFC 8445 §6.1.2.3 pair priority from the controlling and controlled priorities.
fn pair_priority(controlling_prio: u32, controlled_prio: u32) -> u64 {
    var low = u64(controlling_prio)
    var high = u64(controlled_prio)
    var tie = 0u64
    if controlling_prio > controlled_prio {
        low = u64(controlled_prio)
        high = u64(controlling_prio)
        tie = 1u64
    }
    ret (low << 32u32) + 2u64 * high + tie
}

// Candidate pairs of one component and family, sorted by pair priority
// (highest first) and pruned: a local server-reflexive candidate stands for
// its base, so a pair whose (local base, remote) repeats an earlier one goes.
fn candidate_pairs(local: []const Candidate, remote: []const Candidate, controlling: bool, out_pairs: []Pair) -> usize {
    var count = 0usize
    var li = 0usize
    while li < local.len {
        var ri = 0usize
        while ri < remote.len {
            if count < out_pairs.len && local[li].component == remote[ri].component && local[li].address.family == remote[ri].address.family {
                var p = pair_priority(remote[ri].priority, local[li].priority)
                if controlling { p = pair_priority(local[li].priority, remote[ri].priority) }
                out_pairs[count] = Pair { local: u32(li), remote: u32(ri), priority: p }
                count += 1usize
            }
            ri += 1usize
        }
        li += 1usize
    }
    var i = 1usize
    while i < count {
        let item = out_pairs[i]
        var j = i
        while j > 0usize && out_pairs[j - 1usize].priority < item.priority {
            out_pairs[j] = out_pairs[j - 1usize]
            j -= 1usize
        }
        out_pairs[j] = item
        i += 1usize
    }
    var kept = 0usize
    i = 0usize
    while i < count {
        var duplicate = false
        var k = 0usize
        while k < kept {
            if out_pairs[k].remote == out_pairs[i].remote && address_equal(local[usize(out_pairs[k].local)].base, local[usize(out_pairs[i].local)].base) { duplicate = true }
            k += 1usize
        }
        if !duplicate {
            out_pairs[kept] = out_pairs[i]
            kept += 1usize
        }
        i += 1usize
    }
    ret kept
}
