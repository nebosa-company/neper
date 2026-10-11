// SNMP v1 and v2c messages (RFC 1157, RFC 3416) as bytes, over a small BER codec (ITU X.690): `build_request`
// writes a GetRequest, GetNextRequest or SetRequest for one variable binding; `decode` reads a message of any
// PDU (a GetResponse above all) with up to eight bindings. Object identifiers are arrays of arcs
// (`1.3.6.1.2.1.1.1.0` is `[1, 3, 6, 1, 2, 1, 1, 1, 0]`, at most 16 arcs); values are an INTEGER or Gauge32,
// Counter32, TimeTicks, Counter64 (saturating at the largest i64), an octet string or IpAddress (bytes), an OID, NULL or one
// of the v2c exceptions (noSuchObject, noSuchInstance, endOfMibView). Lengths are definite, short or long
// form (up to four length bytes); anything longer, a truncated element or a tag the message does not allow
// is `Malformed`. No UDP here: the caller sends the bytes to port 161. SNMPv3 is not covered.

error Malformed
error TooSmall
error TooMany

const V1: u8 = 0u8
const V2C: u8 = 1u8
const GET: u8 = 160u8
const GET_NEXT: u8 = 161u8
const RESPONSE: u8 = 162u8
const SET: u8 = 163u8
const TRAP_V2: u8 = 167u8
const T_INTEGER: u8 = 2u8
const T_OCTETS: u8 = 4u8
const T_NULL: u8 = 5u8
const T_OID: u8 = 6u8
const T_SEQUENCE: u8 = 48u8
const T_IPADDRESS: u8 = 64u8
const T_COUNTER32: u8 = 65u8
const T_GAUGE32: u8 = 66u8
const T_TIMETICKS: u8 = 67u8
const T_COUNTER64: u8 = 70u8
const T_NO_SUCH_OBJECT: u8 = 128u8
const T_NO_SUCH_INSTANCE: u8 = 129u8
const T_END_OF_MIB: u8 = 130u8
const MAX_BINDINGS: usize = 8usize
const MAX_ARCS: usize = 16usize

type Message = struct {
    version: u8,
    community: [64]u8,
    community_len: usize,
    pdu: u8,
    request_id: i64,
    error_status: i64,
    error_index: i64,
    count: usize,
    oid_arcs: [128]u32,
    oid_len: [8]usize,
    kind: [8]u8,
    number: [8]i64,
    bytes: [512]u8,
    bytes_at: [8]usize,
    bytes_len: [8]usize,
}

// ---- Writing.

fn put_length(out: []u8, at: usize, length: usize) -> usize {
    if length < 128usize {
        out[at] = u8(length)
        ret at + 1usize
    }
    if length < 256usize {
        out[at] = 129u8
        out[at + 1usize] = u8(length)
        ret at + 2usize
    }
    out[at] = 130u8
    out[at + 1usize] = u8(length >> 8usize)
    out[at + 2usize] = u8(length & 255usize)
    ret at + 3usize
}

fn length_size(length: usize) -> usize {
    if length < 128usize { ret 1usize }
    if length < 256usize { ret 2usize }
    ret 3usize
}

// An INTEGER's content bytes: the shortest two's-complement form of `value`.
fn integer_bytes(value: i64, tmp: []u8) -> usize {
    // The bytes of the value, or of -1 - value (its complement) for a negative one, then inverted.
    let negative = value < 0i64
    var rest = value
    if negative { rest = (0i64 - 1i64) - value }
    var i = 0usize
    while i < 8usize {
        var b = u8(rest % 256i64)
        rest = rest / 256i64
        if negative { b = 255u8 - b }
        tmp[7usize - i] = b
        i += 1usize
    }
    var start = 0usize
    var trimming = true
    while trimming && start < 7usize {
        let first = tmp[start]
        let next = tmp[start + 1usize]
        if (first == 0u8 && (next & 128u8) == 0u8) || (first == 255u8 && (next & 128u8) != 0u8) {
            start += 1usize
        } else {
            trimming = false
        }
    }
    let out = 8usize - start
    var k = 0usize
    while k < out {
        tmp[k] = tmp[start + k]
        k += 1usize
    }
    ret out
}

fn put_integer(out: []u8, at: usize, tag: u8, value: i64) -> usize {
    var tmp: [8]u8 = zero
    let n = integer_bytes(value, tmp[0..])
    out[at] = tag
    out[at + 1usize] = u8(n)
    var i = 0usize
    while i < n {
        out[at + 2usize + i] = tmp[i]
        i += 1usize
    }
    ret at + 2usize + n
}

fn base128_size(v: u32) -> usize {
    if v < 128u32 { ret 1usize }
    if v < 16384u32 { ret 2usize }
    if v < 2097152u32 { ret 3usize }
    if v < 268435456u32 { ret 4usize }
    ret 5usize
}

fn put_base128(out: []u8, at: usize, v: u32) -> usize {
    let n = base128_size(v)
    var i = 0usize
    while i < n {
        let shift = u32(7usize * (n - 1usize - i))
        var b = u8((v >> shift) & 127u32)
        if i + 1usize < n { b = b | 128u8 }
        out[at + i] = b
        i += 1usize
    }
    ret at + n
}

fn oid_content_size(arcs: []const u32) -> usize {
    if arcs.len < 2usize { ret 0usize }
    var n = base128_size(arcs[0usize] * 40u32 + arcs[1usize])
    var i = 2usize
    while i < arcs.len {
        n += base128_size(arcs[i])
        i += 1usize
    }
    ret n
}

fn put_oid(out: []u8, at: usize, arcs: []const u32) -> usize {
    let size = oid_content_size(arcs)
    out[at] = T_OID
    var p = put_length(out, at + 1usize, size)
    p = put_base128(out, p, arcs[0usize] * 40u32 + arcs[1usize])
    var i = 2usize
    while i < arcs.len {
        p = put_base128(out, p, arcs[i])
        i += 1usize
    }
    ret p
}

fn oid_total(arcs: []const u32) -> usize {
    let size = oid_content_size(arcs)
    ret 1usize + length_size(size) + size
}

fn integer_total(value: i64) -> usize {
    var tmp: [8]u8 = zero
    ret 2usize + integer_bytes(value, tmp[0..])
}

// A request message for one binding: `kind` GET, GET_NEXT or SET; for SET the value is `text` (an octet string) when
// `has_text` is set and the integer `number` otherwise; GET and GET_NEXT carry NULL. The length, or TooSmall.
fn build_request(out: []u8, version: u8, community: str, kind: u8, request_id: i64, oid: []const u32, has_text: bool, text: str, number: i64) -> (usize, err) {
    if oid.len < 2usize || oid.len > MAX_ARCS || community.len > 64usize { ret (0usize, Malformed) }
    var value_total = 2usize
    if kind == SET {
        if has_text { value_total = 1usize + length_size(text.len) + text.len } else { value_total = integer_total(number) }
    }
    let binding_content = oid_total(oid) + value_total
    let binding_total = 1usize + length_size(binding_content) + binding_content
    let list_total = 1usize + length_size(binding_total) + binding_total
    let pdu_content = integer_total(request_id) + integer_total(0i64) + integer_total(0i64) + list_total
    let pdu_total = 1usize + length_size(pdu_content) + pdu_content
    let message_content = integer_total(i64(version)) + 1usize + length_size(community.len) + community.len + pdu_total
    let total = 1usize + length_size(message_content) + message_content
    if out.len < total { ret (0usize, TooSmall) }
    var at = 0usize
    out[at] = T_SEQUENCE
    at = put_length(out, at + 1usize, message_content)
    at = put_integer(out, at, T_INTEGER, i64(version))
    out[at] = T_OCTETS
    at = put_length(out, at + 1usize, community.len)
    var i = 0usize
    while i < community.len {
        out[at + i] = community[i]
        i += 1usize
    }
    at += community.len
    out[at] = kind
    at = put_length(out, at + 1usize, pdu_content)
    at = put_integer(out, at, T_INTEGER, request_id)
    at = put_integer(out, at, T_INTEGER, 0i64)
    at = put_integer(out, at, T_INTEGER, 0i64)
    out[at] = T_SEQUENCE
    at = put_length(out, at + 1usize, binding_total)
    out[at] = T_SEQUENCE
    at = put_length(out, at + 1usize, binding_content)
    at = put_oid(out, at, oid)
    if kind == SET {
        if has_text {
            out[at] = T_OCTETS
            at = put_length(out, at + 1usize, text.len)
            var k = 0usize
            while k < text.len {
                out[at + k] = text[k]
                k += 1usize
            }
            at += text.len
        } else {
            at = put_integer(out, at, T_INTEGER, number)
        }
    } else {
        out[at] = T_NULL
        out[at + 1usize] = 0u8
        at += 2usize
    }
    ret (at, ok)
}

// ---- Reading.

// The tag at `at`, the content start and its length, and the end offset; Malformed on a bad or overlong length.
fn read_header(data: []const u8, at: usize, limit: usize) -> (u8, usize, usize, err) {
    if at + 2usize > limit { ret (0u8, 0usize, 0usize, Malformed) }
    let tag = data[at]
    let first = usize(data[at + 1usize])
    var length = first
    var start = at + 2usize
    if first >= 128usize {
        let count = first - 128usize
        if count == 0usize || count > 3usize || at + 2usize + count > limit { ret (0u8, 0usize, 0usize, Malformed) }
        length = 0usize
        var i = 0usize
        while i < count {
            length = length * 256usize + usize(data[at + 2usize + i])
            i += 1usize
        }
        start = at + 2usize + count
    }
    if start + length > limit { ret (0u8, 0usize, 0usize, Malformed) }
    ret (tag, start, length, ok)
}

fn read_integer(data: []const u8, start: usize, length: usize) -> i64 {
    if length == 0usize || length > 9usize { ret 0i64 }
    let negative = (data[start] & 128u8) != 0u8
    var magnitude = 0i64
    var i = 0usize
    while i < length {
        var b = i64(data[start + i])
        if negative { b = 255i64 - b }
        if magnitude > 36028797018963967i64 { ret 0i64 }
        magnitude = magnitude * 256i64 + b
        i += 1usize
    }
    if negative { ret (0i64 - 1i64) - magnitude }
    ret magnitude
}

// Read a message. Up to eight bindings; more is TooMany.
fn decode(data: []const u8) -> (Message, err) {
    var m: Message = zero
    let (outer_tag, outer_start, outer_len, outer_error) = read_header(data, 0usize, data.len)
    if outer_error != ok || outer_tag != T_SEQUENCE { ret (m, Malformed) }
    let end = outer_start + outer_len
    let (v_tag, v_start, v_len, v_error) = read_header(data, outer_start, end)
    if v_error != ok || v_tag != T_INTEGER { ret (m, Malformed) }
    let version = read_integer(data, v_start, v_len)
    if version != 0i64 && version != 1i64 { ret (m, Malformed) }
    m.version = u8(version)
    let (c_tag, c_start, c_len, c_error) = read_header(data, v_start + v_len, end)
    if c_error != ok || c_tag != T_OCTETS || c_len > 64usize { ret (m, Malformed) }
    var i = 0usize
    while i < c_len {
        m.community[i] = data[c_start + i]
        i += 1usize
    }
    m.community_len = c_len
    let (p_tag, p_start, p_len, p_error) = read_header(data, c_start + c_len, end)
    if p_error != ok || p_tag < 160u8 || p_tag > 167u8 { ret (m, Malformed) }
    m.pdu = p_tag
    let p_end = p_start + p_len
    let (r_tag, r_start, r_len, r_error) = read_header(data, p_start, p_end)
    if r_error != ok || r_tag != T_INTEGER { ret (m, Malformed) }
    m.request_id = read_integer(data, r_start, r_len)
    let (s_tag, s_start, s_len, s_error) = read_header(data, r_start + r_len, p_end)
    if s_error != ok || s_tag != T_INTEGER { ret (m, Malformed) }
    m.error_status = read_integer(data, s_start, s_len)
    let (x_tag, x_start, x_len, x_error) = read_header(data, s_start + s_len, p_end)
    if x_error != ok || x_tag != T_INTEGER { ret (m, Malformed) }
    m.error_index = read_integer(data, x_start, x_len)
    let (l_tag, l_start, l_len, l_error) = read_header(data, x_start + x_len, p_end)
    if l_error != ok || l_tag != T_SEQUENCE { ret (m, Malformed) }
    let l_end = l_start + l_len
    var at = l_start
    var bytes_used = 0usize
    while at < l_end {
        if m.count >= MAX_BINDINGS { ret (m, TooMany) }
        let (b_tag, b_start, b_len, b_error) = read_header(data, at, l_end)
        if b_error != ok || b_tag != T_SEQUENCE { ret (m, Malformed) }
        let b_end = b_start + b_len
        let (o_tag, o_start, o_len, o_error) = read_header(data, b_start, b_end)
        if o_error != ok || o_tag != T_OID || o_len == 0usize { ret (m, Malformed) }
        let n = m.count
        // The arcs: the first byte group carries two.
        var arcs = 0usize
        var value = 0u32
        var k = 0usize
        var first = true
        while k < o_len {
            let b = data[o_start + k]
            value = value * 128u32 + u32(b & 127u8)
            if (b & 128u8) == 0u8 {
                if first {
                    var a = value / 40u32
                    if a > 2u32 { a = 2u32 }
                    if arcs + 2usize > MAX_ARCS { ret (m, Malformed) }
                    m.oid_arcs[n * MAX_ARCS + arcs] = a
                    m.oid_arcs[n * MAX_ARCS + arcs + 1usize] = value - a * 40u32
                    arcs += 2usize
                    first = false
                } else {
                    if arcs + 1usize > MAX_ARCS { ret (m, Malformed) }
                    m.oid_arcs[n * MAX_ARCS + arcs] = value
                    arcs += 1usize
                }
                value = 0u32
            }
            k += 1usize
        }
        m.oid_len[n] = arcs
        let (v2_tag, v2_start, v2_len, v2_error) = read_header(data, o_start + o_len, b_end)
        if v2_error != ok { ret (m, Malformed) }
        m.kind[n] = v2_tag
        if v2_tag == T_INTEGER || v2_tag == T_COUNTER32 || v2_tag == T_GAUGE32 || v2_tag == T_TIMETICKS || v2_tag == T_COUNTER64 {
            if v2_len == 0usize || v2_len > 9usize { ret (m, Malformed) }
            if v2_tag == T_INTEGER {
                m.number[n] = read_integer(data, v2_start, v2_len)
            } else {
                // Unsigned: no sign extension.
                var u = 0u64
                var j = 0usize
                while j < v2_len {
                    u = (u << 8u64) | u64(data[v2_start + j])
                    j += 1usize
                }
                if u > 9223372036854775807u64 { u = 9223372036854775807u64 }
                m.number[n] = i64(u)
            }
        } else if v2_tag == T_OCTETS || v2_tag == T_IPADDRESS || v2_tag == T_OID {
            if bytes_used + v2_len > 512usize { ret (m, TooMany) }
            var j = 0usize
            while j < v2_len {
                m.bytes[bytes_used + j] = data[v2_start + j]
                j += 1usize
            }
            m.bytes_at[n] = bytes_used
            m.bytes_len[n] = v2_len
            bytes_used += v2_len
        } else if v2_tag == T_NULL || v2_tag == T_NO_SUCH_OBJECT || v2_tag == T_NO_SUCH_INSTANCE || v2_tag == T_END_OF_MIB {
            if v2_len != 0usize { ret (m, Malformed) }
        } else {
            ret (m, Malformed)
        }
        m.count += 1usize
        at = b_end
    }
    ret (m, ok)
}
