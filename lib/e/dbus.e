// D-Bus (L126): the message wire format, the authentication exchange and a client over caller buffers, no socket.
// `put_value`/`get_value` marshal and unmarshal typed values by signature in either byte order with the
// specification's alignment, array length limits (64 MiB) and nesting limits (32 arrays, 32 structs, 64 total);
// `message_encode`/`message_decode` read and write whole messages (method call, return, error, signal) with the
// header fields in the order libdbus writes them; `auth_*` run the SASL EXTERNAL (or ANONYMOUS) handshake as lines;
// `Bus` keeps the serial counter and the table of calls awaiting a reply; match rules are built and tested as the
// bus does. The transport (an AF_UNIX socket named by `parse_address`) is `e.os`'s; the standard bus calls (Hello,
// RequestName, AddMatch) are builders here. No service implementations.
//
// Memory: decoding allocates arrays and structs from the arena; strings borrow the input.
use e.mem
use e.str

error Truncated
error Invalid
error TooLarge
error TooSmall
error Unsupported
error Rejected

const METHOD_CALL: u8 = 1u8
const METHOD_RETURN: u8 = 2u8
const ERROR: u8 = 3u8
const SIGNAL: u8 = 4u8

const FLAG_NO_REPLY_EXPECTED: u8 = 1u8
const FLAG_NO_AUTO_START: u8 = 2u8

const MAX_ARRAY: usize = 67108864usize
const MAX_MESSAGE: usize = 134217728usize

type ArrayValue = struct { element: str, items: []const Value }
type VariantValue = struct { signature: str, value: []const Value }
type Value = union enum u8 { Byte: u8, Bool: bool, I16: i16, U16: u16, I32: i32, U32: u32, I64: i64, U64: u64, Double: f64, Str: str, Path: str, Sig: str, Fd: u32, Array: ArrayValue, Struct: []const Value, Entry: []const Value, Variant: VariantValue }
type Message = struct { little: bool, kind: u8, flags: u8, serial: u32, path: str, interface: str, member: str, error_name: str, reply_serial: u32, destination: str, sender: str, signature: str, unix_fds: u32, body: []const Value }
type Pending = struct { used: bool, serial: u32 }
type Bus = struct { serial: u32, calls: []Pending, unique_name: str }
type Address = struct { transport: str, path: str, abstract_name: str, host: str, port: u16, guid: str, runtime: bool }

// --- signatures --------------------------------------------------------------------------------------------------

fn is_basic(c: u8) -> bool {
    ret c == 121u8 || c == 98u8 || c == 110u8 || c == 113u8 || c == 105u8 || c == 117u8 || c == 120u8 || c == 116u8 || c == 100u8 || c == 115u8 || c == 111u8 || c == 103u8 || c == 104u8
}

// The length of the single complete type starting at `at` in `sig`, or zero when it is malformed. `depth` counts
// array and struct nesting separately as the specification limits them.
fn complete_len(sig: str, at: usize, arrays: u32, structs: u32) -> usize {
    if at >= sig.len { ret 0usize }
    let c = sig[at]
    if is_basic(c) || c == 118u8 { ret 1usize }
    if c == 97u8 {
        if arrays >= 32u32 { ret 0usize }
        if at + 1usize >= sig.len { ret 0usize }
        if sig[at + 1usize] == 123u8 {
            // a{kv}: a basic key and any value.
            if structs >= 32u32 { ret 0usize }
            if at + 2usize >= sig.len || !is_basic(sig[at + 2usize]) { ret 0usize }
            let value_len = complete_len(sig, at + 3usize, arrays + 1u32, structs + 1u32)
            if value_len == 0usize { ret 0usize }
            if at + 3usize + value_len >= sig.len || sig[at + 3usize + value_len] != 125u8 { ret 0usize }
            ret 4usize + value_len
        }
        let n = complete_len(sig, at + 1usize, arrays + 1u32, structs)
        if n == 0usize { ret 0usize }
        ret 1usize + n
    }
    if c == 40u8 {
        if structs >= 32u32 { ret 0usize }
        var i = at + 1usize
        var members = 0usize
        while i < sig.len && sig[i] != 41u8 {
            let n = complete_len(sig, i, arrays, structs + 1u32)
            if n == 0usize { ret 0usize }
            i += n
            members += 1usize
        }
        if i >= sig.len || members == 0usize { ret 0usize }
        ret i + 1usize - at
    }
    ret 0usize
}

// Whether `sig` is a valid signature: complete types back to back, at most 255 bytes.
fn valid_signature(sig: str) -> bool {
    if sig.len > 255usize { ret false }
    var i = 0usize
    while i < sig.len {
        let n = complete_len(sig, i, 0u32, 0u32)
        if n == 0usize { ret false }
        i += n
    }
    ret true
}

fn align_of(c: u8) -> usize {
    if c == 121u8 || c == 103u8 || c == 118u8 { ret 1usize }
    if c == 110u8 || c == 113u8 { ret 2usize }
    if c == 120u8 || c == 116u8 || c == 100u8 || c == 40u8 || c == 123u8 { ret 8usize }
    ret 4usize
}

// --- marshalling -------------------------------------------------------------------------------------------------

fn pad_to(dst: []u8, at: *usize, n: usize) -> err {
    while *at % n != 0usize {
        if *at >= dst.len { ret TooSmall }
        dst[*at] = 0u8
        *at += 1usize
    }
    ret ok
}

fn put_u32(dst: []u8, at: *usize, little: bool, v: u32) -> err {
    let e = pad_to(dst, at, 4usize)
    if e != ok { ret e }
    if *at + 4usize > dst.len { ret TooSmall }
    if little {
        dst[*at] = u8(v & 255u32)
        dst[*at + 1usize] = u8((v >> 8u32) & 255u32)
        dst[*at + 2usize] = u8((v >> 16u32) & 255u32)
        dst[*at + 3usize] = u8((v >> 24u32) & 255u32)
    } else {
        dst[*at] = u8((v >> 24u32) & 255u32)
        dst[*at + 1usize] = u8((v >> 16u32) & 255u32)
        dst[*at + 2usize] = u8((v >> 8u32) & 255u32)
        dst[*at + 3usize] = u8(v & 255u32)
    }
    *at += 4usize
    ret ok
}

fn put_u16(dst: []u8, at: *usize, little: bool, v: u16) -> err {
    let e = pad_to(dst, at, 2usize)
    if e != ok { ret e }
    if *at + 2usize > dst.len { ret TooSmall }
    if little {
        dst[*at] = u8(v & 255u16)
        dst[*at + 1usize] = u8(v >> 8u16)
    } else {
        dst[*at] = u8(v >> 8u16)
        dst[*at + 1usize] = u8(v & 255u16)
    }
    *at += 2usize
    ret ok
}

fn put_u64(dst: []u8, at: *usize, little: bool, v: u64) -> err {
    let e = pad_to(dst, at, 8usize)
    if e != ok { ret e }
    if *at + 8usize > dst.len { ret TooSmall }
    var i = 0usize
    while i < 8usize {
        let shift = u64(i * 8usize)
        if little {
            dst[*at + i] = u8((v >> shift) & 255u64)
        } else {
            dst[*at + 7usize - i] = u8((v >> shift) & 255u64)
        }
        i += 1usize
    }
    *at += 8usize
    ret ok
}

fn put_byte(dst: []u8, at: *usize, b: u8) -> err {
    if *at >= dst.len { ret TooSmall }
    dst[*at] = b
    *at += 1usize
    ret ok
}

fn put_string(dst: []u8, at: *usize, little: bool, s: str) -> err {
    var e = put_u32(dst, at, little, u32(s.len))
    if e != ok { ret e }
    if *at + s.len + 1usize > dst.len { ret TooSmall }
    mem.copy[u8](dst[*at..*at + s.len], s)
    *at += s.len
    ret put_byte(dst, at, 0u8)
}

fn put_signature(dst: []u8, at: *usize, s: str) -> err {
    if s.len > 255usize { ret Invalid }
    var e = put_byte(dst, at, u8(s.len))
    if e != ok { ret e }
    if *at + s.len + 1usize > dst.len { ret TooSmall }
    mem.copy[u8](dst[*at..*at + s.len], s)
    *at += s.len
    ret put_byte(dst, at, 0u8)
}

// One value of the single complete type `sig`.
fn put_value(dst: []u8, at: *usize, little: bool, sig: str, v: Value) -> err {
    let c = sig[0usize]
    var e: err = ok
    if c == 121u8 {
        switch v {
        case .Byte as b:
            ret put_byte(dst, at, b)
        default:
            ret Invalid
        }
    }
    if c == 98u8 {
        switch v {
        case .Bool as b:
            var n = 0u32
            if b { n = 1u32 }
            ret put_u32(dst, at, little, n)
        default:
            ret Invalid
        }
    }
    if c == 110u8 {
        switch v {
        case .I16 as n:
            ret put_u16(dst, at, little, mem.bitcast[u16](n))
        default:
            ret Invalid
        }
    }
    if c == 113u8 {
        switch v {
        case .U16 as n:
            ret put_u16(dst, at, little, n)
        default:
            ret Invalid
        }
    }
    if c == 105u8 {
        switch v {
        case .I32 as n:
            ret put_u32(dst, at, little, mem.bitcast[u32](n))
        default:
            ret Invalid
        }
    }
    if c == 117u8 {
        switch v {
        case .U32 as n:
            ret put_u32(dst, at, little, n)
        default:
            ret Invalid
        }
    }
    if c == 104u8 {
        switch v {
        case .Fd as n:
            ret put_u32(dst, at, little, n)
        default:
            ret Invalid
        }
    }
    if c == 120u8 {
        switch v {
        case .I64 as n:
            ret put_u64(dst, at, little, mem.bitcast[u64](n))
        default:
            ret Invalid
        }
    }
    if c == 116u8 {
        switch v {
        case .U64 as n:
            ret put_u64(dst, at, little, n)
        default:
            ret Invalid
        }
    }
    if c == 100u8 {
        switch v {
        case .Double as d:
            ret put_u64(dst, at, little, mem.bitcast[u64](d))
        default:
            ret Invalid
        }
    }
    if c == 115u8 {
        switch v {
        case .Str as s:
            ret put_string(dst, at, little, s)
        default:
            ret Invalid
        }
    }
    if c == 111u8 {
        switch v {
        case .Path as s:
            ret put_string(dst, at, little, s)
        default:
            ret Invalid
        }
    }
    if c == 103u8 {
        switch v {
        case .Sig as s:
            ret put_signature(dst, at, s)
        default:
            ret Invalid
        }
    }
    if c == 118u8 {
        switch v {
        case .Variant as inner:
            if !valid_signature(inner.signature) || inner.value.len != 1usize { ret Invalid }
            if complete_len(inner.signature, 0usize, 0u32, 0u32) != inner.signature.len { ret Invalid }
            e = put_signature(dst, at, inner.signature)
            if e != ok { ret e }
            ret put_value(dst, at, little, inner.signature, inner.value[0usize])
        default:
            ret Invalid
        }
    }
    if c == 40u8 {
        switch v {
        case .Struct as members:
            e = pad_to(dst, at, 8usize)
            if e != ok { ret e }
            var i = 1usize
            var m = 0usize
            while i < sig.len - 1usize {
                let n = complete_len(sig, i, 0u32, 1u32)
                if n == 0usize || m >= members.len { ret Invalid }
                e = put_value(dst, at, little, sig[i..i + n], members[m])
                if e != ok { ret e }
                i += n
                m += 1usize
            }
            if m != members.len { ret Invalid }
            ret ok
        default:
            ret Invalid
        }
    }
    if c == 97u8 {
        switch v {
        case .Array as arr:
            let element = sig[1usize..]
            if !str.eq(arr.element, element) { ret Invalid }
            e = put_u32(dst, at, little, 0u32)
            if e != ok { ret e }
            let length_at = *at - 4usize
            e = pad_to(dst, at, align_of(element[0usize]))
            if e != ok { ret e }
            let start = *at
            var i = 0usize
            while i < arr.items.len {
                if element[0usize] == 123u8 {
                    switch arr.items[i] {
                    case .Entry as pair:
                        e = pad_to(dst, at, 8usize)
                        if e != ok { ret e }
                        let kn = complete_len(element, 1usize, 0u32, 1u32)
                        if pair.len != 2usize { ret Invalid }
                        e = put_value(dst, at, little, element[1usize..1usize + kn], pair[0usize])
                        if e != ok { ret e }
                        e = put_value(dst, at, little, element[1usize + kn..element.len - 1usize], pair[1usize])
                        if e != ok { ret e }
                    default:
                        ret Invalid
                    }
                } else {
                    e = put_value(dst, at, little, element, arr.items[i])
                    if e != ok { ret e }
                }
                i += 1usize
            }
            let size = *at - start
            if size > MAX_ARRAY { ret TooLarge }
            var shown = length_at
            e = put_u32_at(dst, &shown, little, u32(size))
            ret e
        default:
            ret Invalid
        }
    }
    ret Invalid
}

// Overwrite a u32 already written (an array's length) without realigning.
fn put_u32_at(dst: []u8, at: *usize, little: bool, v: u32) -> err {
    if *at + 4usize > dst.len { ret TooSmall }
    if little {
        dst[*at] = u8(v & 255u32)
        dst[*at + 1usize] = u8((v >> 8u32) & 255u32)
        dst[*at + 2usize] = u8((v >> 16u32) & 255u32)
        dst[*at + 3usize] = u8((v >> 24u32) & 255u32)
    } else {
        dst[*at] = u8((v >> 24u32) & 255u32)
        dst[*at + 1usize] = u8((v >> 16u32) & 255u32)
        dst[*at + 2usize] = u8((v >> 8u32) & 255u32)
        dst[*at + 3usize] = u8(v & 255u32)
    }
    ret ok
}

// --- unmarshalling -----------------------------------------------------------------------------------------------

fn skip_pad(buf: []const u8, at: *usize, n: usize) -> err {
    while *at % n != 0usize {
        if *at >= buf.len { ret Truncated }
        if buf[*at] != 0u8 { ret Invalid }
        *at += 1usize
    }
    ret ok
}

fn get_u32(buf: []const u8, at: *usize, little: bool) -> (u32, err) {
    let e = skip_pad(buf, at, 4usize)
    if e != ok { ret (0u32, e) }
    if *at + 4usize > buf.len { ret (0u32, Truncated) }
    var v = 0u32
    if little {
        v = u32(buf[*at]) | (u32(buf[*at + 1usize]) << 8u32) | (u32(buf[*at + 2usize]) << 16u32) | (u32(buf[*at + 3usize]) << 24u32)
    } else {
        v = u32(buf[*at + 3usize]) | (u32(buf[*at + 2usize]) << 8u32) | (u32(buf[*at + 1usize]) << 16u32) | (u32(buf[*at]) << 24u32)
    }
    *at += 4usize
    ret (v, ok)
}

fn get_u16(buf: []const u8, at: *usize, little: bool) -> (u16, err) {
    let e = skip_pad(buf, at, 2usize)
    if e != ok { ret (0u16, e) }
    if *at + 2usize > buf.len { ret (0u16, Truncated) }
    var v = 0u16
    if little {
        v = u16(buf[*at]) | (u16(buf[*at + 1usize]) << 8u16)
    } else {
        v = u16(buf[*at + 1usize]) | (u16(buf[*at]) << 8u16)
    }
    *at += 2usize
    ret (v, ok)
}

fn get_u64(buf: []const u8, at: *usize, little: bool) -> (u64, err) {
    let e = skip_pad(buf, at, 8usize)
    if e != ok { ret (0u64, e) }
    if *at + 8usize > buf.len { ret (0u64, Truncated) }
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        var b = u64(buf[*at + i])
        if !little { b = u64(buf[*at + 7usize - i]) }
        v = v | (b << u64(i * 8usize))
        i += 1usize
    }
    *at += 8usize
    ret (v, ok)
}

fn get_string(buf: []const u8, at: *usize, little: bool) -> (str, err) {
    let (n, e) = get_u32(buf, at, little)
    if e != ok { ret ("", e) }
    let len = usize(n)
    if *at + len + 1usize > buf.len { ret ("", Truncated) }
    if buf[*at + len] != 0u8 { ret ("", Invalid) }
    var i = 0usize
    while i < len {
        if buf[*at + i] == 0u8 { ret ("", Invalid) }
        i += 1usize
    }
    let s: str = buf[*at..*at + len]
    *at += len + 1usize
    ret (s, ok)
}

fn get_signature(buf: []const u8, at: *usize) -> (str, err) {
    if *at >= buf.len { ret ("", Truncated) }
    let len = usize(buf[*at])
    *at += 1usize
    if *at + len + 1usize > buf.len { ret ("", Truncated) }
    if buf[*at + len] != 0u8 { ret ("", Invalid) }
    let s: str = buf[*at..*at + len]
    *at += len + 1usize
    if !valid_signature(s) { ret ("", Invalid) }
    ret (s, ok)
}

// One value of the single complete type `sig` at `*at`.
fn get_value(a: *mem.Arena, buf: []const u8, at: *usize, little: bool, sig: str, depth: u32) -> (Value, err) {
    var none = Value { Byte: 0u8 }
    if depth > 64u32 { ret (none, TooLarge) }
    let c = sig[0usize]
    if c == 121u8 {
        if *at >= buf.len { ret (none, Truncated) }
        let b = buf[*at]
        *at += 1usize
        ret (Value { Byte: b }, ok)
    }
    if c == 98u8 {
        let (n, e) = get_u32(buf, at, little)
        if e != ok { ret (none, e) }
        if n > 1u32 { ret (none, Invalid) }
        ret (Value { Bool: n == 1u32 }, ok)
    }
    if c == 110u8 || c == 113u8 {
        let (n, e) = get_u16(buf, at, little)
        if e != ok { ret (none, e) }
        if c == 113u8 { ret (Value { U16: n }, ok) }
        ret (Value { I16: mem.bitcast[i16](n) }, ok)
    }
    if c == 105u8 || c == 117u8 || c == 104u8 {
        let (n, e) = get_u32(buf, at, little)
        if e != ok { ret (none, e) }
        if c == 117u8 { ret (Value { U32: n }, ok) }
        if c == 104u8 { ret (Value { Fd: n }, ok) }
        ret (Value { I32: mem.bitcast[i32](n) }, ok)
    }
    if c == 120u8 || c == 116u8 || c == 100u8 {
        let (n, e) = get_u64(buf, at, little)
        if e != ok { ret (none, e) }
        if c == 116u8 { ret (Value { U64: n }, ok) }
        if c == 100u8 { ret (Value { Double: mem.bitcast[f64](n) }, ok) }
        ret (Value { I64: mem.bitcast[i64](n) }, ok)
    }
    if c == 115u8 || c == 111u8 {
        let (s, e) = get_string(buf, at, little)
        if e != ok { ret (none, e) }
        if c == 111u8 { ret (Value { Path: s }, ok) }
        ret (Value { Str: s }, ok)
    }
    if c == 103u8 {
        let (s, e) = get_signature(buf, at)
        if e != ok { ret (none, e) }
        ret (Value { Sig: s }, ok)
    }
    if c == 118u8 {
        let (s, e) = get_signature(buf, at)
        if e != ok { ret (none, e) }
        if s.len == 0usize || complete_len(s, 0usize, 0u32, 0u32) != s.len { ret (none, Invalid) }
        let (inner, inner_error) = get_value(a, buf, at, little, s, depth + 1u32)
        if inner_error != ok { ret (none, inner_error) }
        let (cell, alloc_error) = mem.alloc[Value](a, 1usize)
        if alloc_error != ok { ret (none, alloc_error) }
        cell[0usize] = inner
        ret (Value { Variant: VariantValue { signature: s, value: cell } }, ok)
    }
    if c == 40u8 {
        let e = skip_pad(buf, at, 8usize)
        if e != ok { ret (none, e) }
        var count = 0usize
        var i = 1usize
        while i < sig.len - 1usize {
            let n = complete_len(sig, i, 0u32, 1u32)
            if n == 0usize { ret (none, Invalid) }
            count += 1usize
            i += n
        }
        let (members, alloc_error) = mem.alloc[Value](a, count)
        if alloc_error != ok { ret (none, alloc_error) }
        i = 1usize
        var m = 0usize
        while m < count {
            let n = complete_len(sig, i, 0u32, 1u32)
            let (member, member_error) = get_value(a, buf, at, little, sig[i..i + n], depth + 1u32)
            if member_error != ok { ret (none, member_error) }
            members[m] = member
            i += n
            m += 1usize
        }
        ret (Value { Struct: members }, ok)
    }
    if c == 97u8 {
        let element = sig[1usize..]
        let (size32, size_error) = get_u32(buf, at, little)
        if size_error != ok { ret (none, size_error) }
        let size = usize(size32)
        if size > MAX_ARRAY { ret (none, TooLarge) }
        let pad_error = skip_pad(buf, at, align_of(element[0usize]))
        if pad_error != ok { ret (none, pad_error) }
        if *at + size > buf.len { ret (none, Truncated) }
        let end = *at + size
        // Count the elements first by walking them on a scratch position, then read for real.
        var count = 0usize
        var probe = *at
        var guard = 0usize
        while probe < end {
            let before = probe
            if element[0usize] == 123u8 {
                let kn = complete_len(element, 1usize, 0u32, 1u32)
                let probe_pad = skip_pad(buf, &probe, 8usize)
                if probe_pad != ok { ret (none, probe_pad) }
                let (k, ke) = skip_value(buf, &probe, little, element[1usize..1usize + kn], end)
                if ke != ok { ret (none, ke) }
                let (v, ve) = skip_value(buf, &probe, little, element[1usize + kn..element.len - 1usize], end)
                if ve != ok { ret (none, ve) }
            } else {
                let (s, se) = skip_value(buf, &probe, little, element, end)
                if se != ok { ret (none, se) }
            }
            if probe == before { ret (none, Invalid) }
            count += 1usize
            guard += 1usize
            if guard > size { ret (none, Invalid) }
        }
        if probe != end { ret (none, Invalid) }
        let (items, alloc_error) = mem.alloc[Value](a, count)
        if alloc_error != ok { ret (none, alloc_error) }
        var i = 0usize
        while i < count {
            if element[0usize] == 123u8 {
                let pad = skip_pad(buf, at, 8usize)
                if pad != ok { ret (none, pad) }
                let kn = complete_len(element, 1usize, 0u32, 1u32)
                let (k, key_error) = get_value(a, buf, at, little, element[1usize..1usize + kn], depth + 1u32)
                if key_error != ok { ret (none, key_error) }
                let (v, value_error) = get_value(a, buf, at, little, element[1usize + kn..element.len - 1usize], depth + 1u32)
                if value_error != ok { ret (none, value_error) }
                let (cells, cells_error) = mem.alloc[Value](a, 2usize)
                if cells_error != ok { ret (none, cells_error) }
                cells[0usize] = k
                cells[1usize] = v
                items[i] = Value { Entry: cells }
            } else {
                let (item, item_error) = get_value(a, buf, at, little, element, depth + 1u32)
                if item_error != ok { ret (none, item_error) }
                items[i] = item
            }
            i += 1usize
        }
        ret (Value { Array: ArrayValue { element: element, items: items } }, ok)
    }
    ret (none, Invalid)
}

// Advance `*at` past one value without building it (used to count array elements); `limit` bounds the read.
fn skip_value(buf: []const u8, at: *usize, little: bool, sig: str, limit: usize) -> (bool, err) {
    let c = sig[0usize]
    if c == 121u8 {
        if *at >= limit { ret (false, Truncated) }
        *at += 1usize
        ret (true, ok)
    }
    if c == 110u8 || c == 113u8 {
        let e = skip_pad(buf, at, 2usize)
        if e != ok { ret (false, e) }
        if *at + 2usize > limit { ret (false, Truncated) }
        *at += 2usize
        ret (true, ok)
    }
    if c == 98u8 || c == 105u8 || c == 117u8 || c == 104u8 {
        let e = skip_pad(buf, at, 4usize)
        if e != ok { ret (false, e) }
        if *at + 4usize > limit { ret (false, Truncated) }
        *at += 4usize
        ret (true, ok)
    }
    if c == 120u8 || c == 116u8 || c == 100u8 {
        let e = skip_pad(buf, at, 8usize)
        if e != ok { ret (false, e) }
        if *at + 8usize > limit { ret (false, Truncated) }
        *at += 8usize
        ret (true, ok)
    }
    if c == 115u8 || c == 111u8 {
        let (n, e) = get_u32(buf, at, little)
        if e != ok { ret (false, e) }
        if *at + usize(n) + 1usize > limit { ret (false, Truncated) }
        *at += usize(n) + 1usize
        ret (true, ok)
    }
    if c == 103u8 {
        if *at >= limit { ret (false, Truncated) }
        let n = usize(buf[*at])
        if *at + n + 2usize > limit { ret (false, Truncated) }
        *at += n + 2usize
        ret (true, ok)
    }
    if c == 118u8 {
        if *at >= limit { ret (false, Truncated) }
        let n = usize(buf[*at])
        if *at + n + 2usize > limit { ret (false, Truncated) }
        let s: str = buf[*at + 1usize..*at + 1usize + n]
        *at += n + 2usize
        if s.len == 0usize || complete_len(s, 0usize, 0u32, 0u32) != s.len { ret (false, Invalid) }
        let (r, e) = skip_value(buf, at, little, s, limit)
        ret (r, e)
    }
    if c == 40u8 {
        let e = skip_pad(buf, at, 8usize)
        if e != ok { ret (false, e) }
        var i = 1usize
        while i < sig.len - 1usize {
            let n = complete_len(sig, i, 0u32, 1u32)
            if n == 0usize { ret (false, Invalid) }
            let (r, re) = skip_value(buf, at, little, sig[i..i + n], limit)
            if re != ok { ret (false, re) }
            i += n
        }
        ret (true, ok)
    }
    if c == 97u8 {
        let (size32, size_error) = get_u32(buf, at, little)
        if size_error != ok { ret (false, size_error) }
        let element = sig[1usize..]
        let pad = skip_pad(buf, at, align_of(element[0usize]))
        if pad != ok { ret (false, pad) }
        if *at + usize(size32) > limit { ret (false, Truncated) }
        *at += usize(size32)
        ret (true, ok)
    }
    ret (false, Invalid)
}

// --- messages ----------------------------------------------------------------------------------------------------

fn message(kind: u8, serial: u32) -> Message {
    var no_body: []const Value = zero
    ret Message { little: true, kind: kind, flags: 0u8, serial: serial, path: "", interface: "", member: "", error_name: "", reply_serial: 0u32, destination: "", sender: "", signature: "", unix_fds: 0u32, body: no_body }
}

fn put_field(dst: []u8, at: *usize, little: bool, code: u8, sig: str, text: str, number: u32, is_number: bool) -> err {
    var e = pad_to(dst, at, 8usize)
    if e != ok { ret e }
    e = put_byte(dst, at, code)
    if e != ok { ret e }
    e = put_signature(dst, at, sig)
    if e != ok { ret e }
    if is_number { ret put_u32(dst, at, little, number) }
    if sig[0usize] == 103u8 { ret put_signature(dst, at, text) }
    ret put_string(dst, at, little, text)
}

// A whole message: the fixed header, the header-field array (path, interface, member, error name, reply serial,
// destination, sender, signature, unix fds, in libdbus's order), the padding to 8 and the body marshalled by
// `m.signature`. Answers the bytes written.
fn message_encode(dst: []u8, m: *const Message) -> (usize, err) {
    if m.serial == 0u32 || m.kind < 1u8 || m.kind > 4u8 { ret (0usize, Invalid) }
    if !valid_signature(m.signature) { ret (0usize, Invalid) }
    var at = 0usize
    var e = put_byte(dst, &at, 108u8)
    if !m.little { dst[0usize] = 66u8 }
    if e != ok { ret (0usize, e) }
    e = put_byte(dst, &at, m.kind)
    if e != ok { ret (0usize, e) }
    e = put_byte(dst, &at, m.flags)
    if e != ok { ret (0usize, e) }
    e = put_byte(dst, &at, 1u8)
    if e != ok { ret (0usize, e) }
    e = put_u32(dst, &at, m.little, 0u32)
    if e != ok { ret (0usize, e) }
    e = put_u32(dst, &at, m.little, m.serial)
    if e != ok { ret (0usize, e) }
    e = put_u32(dst, &at, m.little, 0u32)
    if e != ok { ret (0usize, e) }
    let fields_at = at - 4usize
    let fields_start = at
    if m.path.len > 0usize {
        e = put_field(dst, &at, m.little, 1u8, "o", m.path, 0u32, false)
        if e != ok { ret (0usize, e) }
    }
    if m.interface.len > 0usize {
        e = put_field(dst, &at, m.little, 2u8, "s", m.interface, 0u32, false)
        if e != ok { ret (0usize, e) }
    }
    if m.member.len > 0usize {
        e = put_field(dst, &at, m.little, 3u8, "s", m.member, 0u32, false)
        if e != ok { ret (0usize, e) }
    }
    if m.error_name.len > 0usize {
        e = put_field(dst, &at, m.little, 4u8, "s", m.error_name, 0u32, false)
        if e != ok { ret (0usize, e) }
    }
    if m.reply_serial != 0u32 {
        e = put_field(dst, &at, m.little, 5u8, "u", "", m.reply_serial, true)
        if e != ok { ret (0usize, e) }
    }
    if m.destination.len > 0usize {
        e = put_field(dst, &at, m.little, 6u8, "s", m.destination, 0u32, false)
        if e != ok { ret (0usize, e) }
    }
    if m.sender.len > 0usize {
        e = put_field(dst, &at, m.little, 7u8, "s", m.sender, 0u32, false)
        if e != ok { ret (0usize, e) }
    }
    if m.signature.len > 0usize {
        e = put_field(dst, &at, m.little, 8u8, "g", m.signature, 0u32, false)
        if e != ok { ret (0usize, e) }
    }
    if m.unix_fds != 0u32 {
        e = put_field(dst, &at, m.little, 9u8, "u", "", m.unix_fds, true)
        if e != ok { ret (0usize, e) }
    }
    var patch = fields_at
    e = put_u32_at(dst, &patch, m.little, u32(at - fields_start))
    if e != ok { ret (0usize, e) }
    e = pad_to(dst, &at, 8usize)
    if e != ok { ret (0usize, e) }
    let body_start = at
    var i = 0usize
    var v = 0usize
    while i < m.signature.len {
        let n = complete_len(m.signature, i, 0u32, 0u32)
        if v >= m.body.len { ret (0usize, Invalid) }
        e = put_value(dst, &at, m.little, m.signature[i..i + n], m.body[v])
        if e != ok { ret (0usize, e) }
        i += n
        v += 1usize
    }
    if v != m.body.len { ret (0usize, Invalid) }
    var body_len_at = 4usize
    e = put_u32_at(dst, &body_len_at, m.little, u32(at - body_start))
    if e != ok { ret (0usize, e) }
    ret (at, ok)
}

// One whole message at the front of `buf` and the bytes it used; `Truncated` until all of it is there.
fn message_decode(a: *mem.Arena, buf: []const u8) -> (Message, usize, err) {
    var m: Message = zero
    if buf.len < 16usize { ret (m, 0usize, Truncated) }
    if buf[0usize] == 108u8 {
        m.little = true
    } else if buf[0usize] == 66u8 {
        m.little = false
    } else {
        ret (m, 0usize, Invalid)
    }
    m.kind = buf[1usize]
    m.flags = buf[2usize]
    if buf[3usize] != 1u8 { ret (m, 0usize, Unsupported) }
    var at = 4usize
    let (body_len32, e1) = get_u32(buf, &at, m.little)
    let (serial, e2) = get_u32(buf, &at, m.little)
    let (fields_len32, e3) = get_u32(buf, &at, m.little)
    if e1 != ok || e2 != ok || e3 != ok { ret (m, 0usize, Truncated) }
    let fields_len = usize(fields_len32)
    let body_len = usize(body_len32)
    if fields_len > 67108864usize || body_len > MAX_MESSAGE { ret (m, 0usize, TooLarge) }
    var body_start = 16usize + fields_len
    if body_start % 8usize != 0usize { body_start += 8usize - body_start % 8usize }
    let total = body_start + body_len
    if total > MAX_MESSAGE { ret (m, 0usize, TooLarge) }
    if buf.len < total { ret (m, 0usize, Truncated) }
    if m.kind < 1u8 || m.kind > 4u8 { ret (m, 0usize, Invalid) }
    if serial == 0u32 { ret (m, 0usize, Invalid) }
    m.serial = serial
    let fields_end = 16usize + fields_len
    while at < fields_end {
        let pad_error = skip_pad(buf, &at, 8usize)
        if pad_error != ok { ret (m, 0usize, pad_error) }
        if at >= fields_end { break }
        let code = buf[at]
        at += 1usize
        let (sig, sig_error) = get_signature(buf, &at)
        if sig_error != ok { ret (m, 0usize, sig_error) }
        if sig.len != 1usize { ret (m, 0usize, Invalid) }
        if code == 5u8 || code == 9u8 {
            if sig[0usize] != 117u8 { ret (m, 0usize, Invalid) }
            let (n, ne) = get_u32(buf, &at, m.little)
            if ne != ok { ret (m, 0usize, ne) }
            if code == 5u8 {
                m.reply_serial = n
            } else {
                m.unix_fds = n
            }
        } else if code == 8u8 {
            if sig[0usize] != 103u8 { ret (m, 0usize, Invalid) }
            let (s, se) = get_signature(buf, &at)
            if se != ok { ret (m, 0usize, se) }
            m.signature = s
        } else if code >= 1u8 && code <= 7u8 {
            if sig[0usize] != 115u8 && sig[0usize] != 111u8 { ret (m, 0usize, Invalid) }
            let (s, se) = get_string(buf, &at, m.little)
            if se != ok { ret (m, 0usize, se) }
            if code == 1u8 {
                m.path = s
            } else if code == 2u8 {
                m.interface = s
            } else if code == 3u8 {
                m.member = s
            } else if code == 4u8 {
                m.error_name = s
            } else if code == 6u8 {
                m.destination = s
            } else if code == 7u8 {
                m.sender = s
            }
        } else {
            // An unknown field is skipped by its signature, as the specification asks.
            let (r, re) = skip_value(buf, &at, m.little, sig, fields_end)
            if re != ok { ret (m, 0usize, re) }
        }
    }
    if at != fields_end { ret (m, 0usize, Invalid) }
    // Required fields by kind.
    if m.kind == METHOD_CALL && (m.path.len == 0usize || m.member.len == 0usize) { ret (m, 0usize, Invalid) }
    if m.kind == METHOD_RETURN && m.reply_serial == 0u32 { ret (m, 0usize, Invalid) }
    if m.kind == ERROR && (m.error_name.len == 0usize || m.reply_serial == 0u32) { ret (m, 0usize, Invalid) }
    if m.kind == SIGNAL && (m.path.len == 0usize || m.interface.len == 0usize || m.member.len == 0usize) { ret (m, 0usize, Invalid) }
    // The body.
    var b = body_start
    var count = 0usize
    var i = 0usize
    while i < m.signature.len {
        let n = complete_len(m.signature, i, 0u32, 0u32)
        i += n
        count += 1usize
    }
    let (values, alloc_error) = mem.alloc[Value](a, count)
    if alloc_error != ok { ret (m, 0usize, alloc_error) }
    i = 0usize
    var v = 0usize
    while v < count {
        let n = complete_len(m.signature, i, 0u32, 0u32)
        let (value, value_error) = get_value(a, buf[0usize..total], &b, m.little, m.signature[i..i + n], 0u32)
        if value_error != ok { ret (m, 0usize, value_error) }
        values[v] = value
        i += n
        v += 1usize
    }
    if b != total { ret (m, 0usize, Invalid) }
    m.body = values
    ret (m, total, ok)
}

// --- authentication ----------------------------------------------------------------------------------------------

fn hex_digit(v: u8) -> u8 {
    if v < 10u8 { ret 48u8 + v }
    ret 87u8 + v
}

// The client's first bytes: a NUL, then `AUTH EXTERNAL <hex of the decimal uid text>` and CR LF. `uid` is the
// user id as decimal text ("1000").
fn auth_external(dst: []u8, uid: str) -> (usize, err) {
    let head = "\0AUTH EXTERNAL "
    let n = head.len + uid.len * 2usize + 2usize
    if dst.len < n { ret (0usize, TooSmall) }
    mem.copy[u8](dst[0usize..head.len], head)
    var at = head.len
    var i = 0usize
    while i < uid.len {
        dst[at] = hex_digit(uid[i] >> 4u8)
        dst[at + 1usize] = hex_digit(uid[i] & 15u8)
        at += 2usize
        i += 1usize
    }
    dst[at] = 13u8
    dst[at + 1usize] = 10u8
    ret (at + 2usize, ok)
}

fn auth_anonymous(dst: []u8) -> (usize, err) {
    let line = "\0AUTH ANONYMOUS\r\n"
    if dst.len < line.len { ret (0usize, TooSmall) }
    mem.copy[u8](dst[0usize..line.len], line)
    ret (line.len, ok)
}

// A server line (without CR LF). `OK <guid>` answers `BEGIN` (written into `dst`, `begun` true) and is the end of
// authentication; `REJECTED <mechanisms>` is `Rejected`; `AGREE_UNIX_FD` and `DATA` are accepted and ignored here.
fn auth_reply(line: str, dst: []u8) -> (usize, bool, err) {
    if line.len >= 2usize && str.eq(line[0usize..2usize], "OK") {
        let begin = "BEGIN\r\n"
        if dst.len < begin.len { ret (0usize, false, TooSmall) }
        mem.copy[u8](dst[0usize..begin.len], begin)
        ret (begin.len, true, ok)
    }
    if line.len >= 8usize && str.eq(line[0usize..8usize], "REJECTED") { ret (0usize, false, Rejected) }
    if line.len >= 5usize && str.eq(line[0usize..5usize], "ERROR") { ret (0usize, false, Rejected) }
    ret (0usize, false, ok)
}

// --- the bus -----------------------------------------------------------------------------------------------------

fn bus_new(calls: []Pending) -> Bus {
    var i = 0usize
    while i < calls.len {
        calls[i].used = false
        i += 1usize
    }
    ret Bus { serial: 0u32, calls: calls, unique_name: "" }
}

fn next_serial(b: *Bus) -> u32 {
    b.serial += 1u32
    if b.serial == 0u32 { b.serial = 1u32 }
    ret b.serial
}

// A method call message ready for `message_encode`, serial allocated and registered as pending unless the caller set
// `FLAG_NO_REPLY_EXPECTED`.
fn call(b: *Bus, destination: str, path: str, interface: str, member: str, signature: str, body: []const Value, flags: u8) -> (Message, err) {
    var m = message(METHOD_CALL, next_serial(b))
    m.destination = destination
    m.path = path
    m.interface = interface
    m.member = member
    m.signature = signature
    m.body = body
    m.flags = flags
    if (flags & FLAG_NO_REPLY_EXPECTED) == 0u8 {
        var free = b.calls.len
        var i = 0usize
        while i < b.calls.len {
            if !b.calls[i].used {
                free = i
                break
            }
            i += 1usize
        }
        if free == b.calls.len { ret (m, TooSmall) }
        b.calls[free] = Pending { used: true, serial: m.serial }
    }
    ret (m, ok)
}

// The standard first call, `org.freedesktop.DBus.Hello`.
fn hello(b: *Bus) -> (Message, err) {
    var no_body: []const Value = zero
    let (m, e) = call(b, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello", "", no_body, 0u8)
    ret (m, e)
}

// Whether a reply or error answers a pending call; the call is retired. Signals and incoming calls are not replies.
fn retire(b: *Bus, m: *const Message) -> bool {
    if m.kind != METHOD_RETURN && m.kind != ERROR { ret false }
    var i = 0usize
    while i < b.calls.len {
        if b.calls[i].used && b.calls[i].serial == m.reply_serial {
            b.calls[i].used = false
            ret true
        }
        i += 1usize
    }
    ret false
}

// --- match rules -------------------------------------------------------------------------------------------------

// The value of `key='...'` in a match rule, with `\'` escapes undone only as far as the bus does (a quote ends the
// value, an apostrophe is written `'\''`); keys are compared exactly.
fn rule_value(rule: str, key: str) -> (str, bool) {
    var i = 0usize
    while i < rule.len {
        // A key starts at the beginning or after a comma.
        if i + key.len + 2usize <= rule.len && str.eq(rule[i..i + key.len], key) && rule[i + key.len] == 61u8 && rule[i + key.len + 1usize] == 39u8 {
            if i == 0usize || rule[i - 1usize] == 44u8 {
                let start = i + key.len + 2usize
                var end = start
                while end < rule.len && rule[end] != 39u8 { end += 1usize }
                if end >= rule.len { ret ("", false) }
                ret (rule[start..end], true)
            }
        }
        i += 1usize
    }
    ret ("", false)
}

fn path_under(namespace: str, path: str) -> bool {
    if str.eq(namespace, "/") { ret true }
    if path.len < namespace.len { ret false }
    if !str.eq(path[0usize..namespace.len], namespace) { ret false }
    ret path.len == namespace.len || path[namespace.len] == 47u8
}

fn kind_name(kind: u8) -> str {
    if kind == METHOD_CALL { ret "method_call" }
    if kind == METHOD_RETURN { ret "method_return" }
    if kind == ERROR { ret "error" }
    ret "signal"
}

// Whether `m` matches `rule` (a comma-separated list of `key='value'`): type, sender, interface, member, path,
// path_namespace, destination and `argN` for string arguments; every key present must match.
fn rule_matches(rule: str, m: *const Message) -> bool {
    let (t, has_type) = rule_value(rule, "type")
    if has_type && !str.eq(t, kind_name(m.kind)) { ret false }
    let (sender, has_sender) = rule_value(rule, "sender")
    if has_sender && !str.eq(sender, m.sender) { ret false }
    let (interface, has_interface) = rule_value(rule, "interface")
    if has_interface && !str.eq(interface, m.interface) { ret false }
    let (member, has_member) = rule_value(rule, "member")
    if has_member && !str.eq(member, m.member) { ret false }
    let (path, has_path) = rule_value(rule, "path")
    if has_path && !str.eq(path, m.path) { ret false }
    let (namespace, has_namespace) = rule_value(rule, "path_namespace")
    if has_namespace && !path_under(namespace, m.path) { ret false }
    let (destination, has_destination) = rule_value(rule, "destination")
    if has_destination && !str.eq(destination, m.destination) { ret false }
    var n = 0usize
    while n < 64usize {
        var key: [8]u8 = zero
        key[0usize] = 97u8
        key[1usize] = 114u8
        key[2usize] = 103u8
        var len = 3usize
        if n >= 10usize {
            key[len] = 48u8 + u8(n / 10usize)
            len += 1usize
        }
        key[len] = 48u8 + u8(n % 10usize)
        len += 1usize
        let name: str = key[0usize..len]
        let (want, has_arg) = rule_value(rule, name)
        if has_arg {
            if n >= m.body.len { ret false }
            switch m.body[n] {
            case .Str as s:
                if !str.eq(s, want) { ret false }
            case .Path as s:
                if !str.eq(s, want) { ret false }
            default:
                ret false
            }
        }
        n += 1usize
    }
    ret true
}

// --- addresses ---------------------------------------------------------------------------------------------------

// The first usable entry of a bus address (`unix:path=/run/user/1000/bus,guid=...`, `unix:abstract=name`,
// `unix:runtime=yes`, `tcp:host=h,port=1`), values with `%XX` escapes decoded in place into `out`.
fn parse_address(text: str, out: []u8) -> (Address, err) {
    var a: Address = zero
    var colon = 0usize
    while colon < text.len && text[colon] != 58u8 { colon += 1usize }
    if colon == 0usize || colon >= text.len { ret (a, Invalid) }
    a.transport = text[0usize..colon]
    var used = 0usize
    var i = colon + 1usize
    while i <= text.len {
        var j = i
        while j < text.len && text[j] != 44u8 && text[j] != 59u8 { j += 1usize }
        let pair = text[i..j]
        var eq = 0usize
        while eq < pair.len && pair[eq] != 61u8 { eq += 1usize }
        if eq < pair.len {
            let key = pair[0usize..eq]
            let raw = pair[eq + 1usize..]
            // Decode %XX into out.
            let start = used
            var k = 0usize
            while k < raw.len {
                var c = raw[k]
                if c == 37u8 && k + 2usize < raw.len {
                    let hi = hex_value(raw[k + 1usize])
                    let lo = hex_value(raw[k + 2usize])
                    if hi < 16u8 && lo < 16u8 {
                        c = (hi << 4u8) | lo
                        k += 2usize
                    }
                }
                if used >= out.len { ret (a, TooSmall) }
                out[used] = c
                used += 1usize
                k += 1usize
            }
            let value: str = out[start..used]
            if str.eq(key, "path") {
                a.path = value
            } else if str.eq(key, "abstract") {
                a.abstract_name = value
            } else if str.eq(key, "host") {
                a.host = value
            } else if str.eq(key, "guid") {
                a.guid = value
            } else if str.eq(key, "runtime") {
                a.runtime = str.eq(value, "yes")
            } else if str.eq(key, "port") {
                var port = 0u32
                var d = 0usize
                while d < value.len {
                    if value[d] < 48u8 || value[d] > 57u8 { ret (a, Invalid) }
                    port = port * 10u32 + u32(value[d] - 48u8)
                    d += 1usize
                }
                if port > 65535u32 { ret (a, Invalid) }
                a.port = u16(port)
            }
        }
        if j >= text.len || text[j] == 59u8 { break }
        i = j + 1usize
    }
    ret (a, ok)
}

fn hex_value(c: u8) -> u8 {
    if c >= 48u8 && c <= 57u8 { ret c - 48u8 }
    if c >= 65u8 && c <= 70u8 { ret c - 55u8 }
    if c >= 97u8 && c <= 102u8 { ret c - 87u8 }
    ret 255u8
}
