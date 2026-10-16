// URLs by the WHATWG URL Standard (tracker 1.5): the basic URL parser with its state override (the setters of the URL
// API use it), host parsing (domains through IDNA, IPv4 in every legacy notation, IPv6, opaque hosts), the percent-encode
// sets, serialisation, `origin` and the setter operations. A `Url` holds its components as text; `parse` takes an optional
// base for relative references. Failure is the error `Failure`.
//
// Differences from the Standard, on purpose: the encoding is always UTF-8; domain-to-ASCII is `e.net.idna` (IDNA 2008
// with NFC and simple lower-casing), not the UTS #46 mapping table, so a handful of compatibility mappings are refused
// where a browser would fold them.
//
// Memory: every result is allocated in the arena it is given; nothing else is retained.

use e.data.list as list
use e.mem
use e.net.uts46 as uts46
use e.str
use e.text.utf8 as utf8

type Url = struct {
    scheme: str, username: str, password: str,
    host: str, has_host: bool, port: i32,
    path: str, opaque_path: bool,
    query: str, has_query: bool,
    fragment: str, has_fragment: bool
}

error Failure

// The states of the basic URL parser, which a setter names as its override.
type State = enum u8 { SchemeStart, Scheme, NoScheme, SpecialRelativeOrAuthority, PathOrAuthority, Relative, RelativeSlash, SpecialAuthoritySlashes, SpecialAuthorityIgnoreSlashes, Authority, Host, Hostname, Port, File, FileSlash, FileHost, PathStart, Path, OpaquePath, Query, Fragment }

type EncodeSet = enum u8 { C0, Fragment, Query, SpecialQuery, Path, Userinfo, Component }

const EOF: u32 = 4294967295u32

// --- Byte buffers.

type Buf = struct { data: []u8, len: usize }

fn buf_new(a: *mem.Arena, cap: usize) -> (Buf, err) {
    let (d, e) = mem.alloc[u8](a, cap + 16usize)
    if e != ok { ret (zero, e) }
    ret (Buf { data: d, len: 0usize }, ok)
}

fn buf_byte(b: *Buf, c: u8) {
    if b.len < b.data.len {
        b.data[b.len] = c
        b.len += 1usize
    }
}

fn buf_str(b: *Buf, s: str) {
    var i = 0usize
    while i < s.len {
        buf_byte(b, s[i])
        i += 1usize
    }
}

fn buf_text(b: *const Buf) -> str { ret b.data[0usize..b.len] }

// A copy of the buffer's bytes that outlives its reuse.
fn buf_take(a: *mem.Arena, b: *const Buf) -> str {
    let (d, e) = mem.alloc[u8](a, b.len + 1usize)
    if e != ok { ret "" }
    var i = 0usize
    while i < b.len {
        d[i] = b.data[i]
        i += 1usize
    }
    ret d[0usize..b.len]
}

fn copy_str(a: *mem.Arena, s: str) -> str {
    let (d, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret "" }
    var i = 0usize
    while i < s.len {
        d[i] = s[i]
        i += 1usize
    }
    ret d[0usize..s.len]
}

// --- Character classes.

fn is_alpha(c: u32) -> bool { ret (c >= 65u32 && c <= 90u32) || (c >= 97u32 && c <= 122u32) }

fn is_digit(c: u32) -> bool { ret c >= 48u32 && c <= 57u32 }

fn is_hex(c: u32) -> bool { ret is_digit(c) || (c >= 65u32 && c <= 70u32) || (c >= 97u32 && c <= 102u32) }

fn lower_ascii(c: u32) -> u32 {
    if c >= 65u32 && c <= 90u32 { ret c + 32u32 }
    ret c
}

fn hex_val(c: u32) -> u32 {
    if is_digit(c) { ret c - 48u32 }
    if c >= 97u32 { ret c - 87u32 }
    ret c - 55u32
}

fn hex_digit(n: u32) -> u8 {
    if n < 10u32 { ret u8(48u32 + n) }
    ret u8(55u32 + n)
}

// Whether `c` is in the percent-encode set.
fn in_set(c: u32, set: EncodeSet) -> bool {
    if c <= 31u32 || c > 126u32 { ret true }
    if set == .C0 { ret false }
    if set == .Fragment { ret c == 32u32 || c == 34u32 || c == 60u32 || c == 62u32 || c == 96u32 }
    let query = c == 32u32 || c == 34u32 || c == 35u32 || c == 60u32 || c == 62u32
    if set == .Query { ret query }
    if set == .SpecialQuery { ret query || c == 39u32 }
    let path = query || c == 63u32 || c == 94u32 || c == 96u32 || c == 123u32 || c == 125u32
    if set == .Path { ret path }
    let userinfo = path || c == 47u32 || c == 58u32 || c == 59u32 || c == 61u32 || c == 64u32 || (c >= 91u32 && c <= 94u32) || c == 124u32
    if set == .Userinfo { ret userinfo }
    ret userinfo || (c >= 36u32 && c <= 38u32) || c == 43u32 || c == 44u32
}

fn put_pct(b: *Buf, byte: u8) {
    buf_byte(b, 37u8)
    buf_byte(b, hex_digit(u32(byte) >> 4u32))
    buf_byte(b, hex_digit(u32(byte) & 15u32))
}

// The UTF-8 percent-encoding of a scalar: bytes in the set as %XX, the rest as they are.
fn put_encoded(b: *Buf, c: u32, set: EncodeSet) {
    if c < 128u32 {
        if in_set(c, set) { put_pct(b, u8(c)) } else { buf_byte(b, u8(c)) }
        ret
    }
    var tmp: [4]u8 = zero
    let (n, e) = utf8.encode(c, tmp[0usize..4usize])
    if e != ok { ret }
    var i = 0usize
    while i < usize(n) {
        put_pct(b, tmp[i])
        i += 1usize
    }
}

fn put_scalar(b: *Buf, c: u32) {
    if c < 128u32 {
        buf_byte(b, u8(c))
        ret
    }
    var tmp: [4]u8 = zero
    let (n, e) = utf8.encode(c, tmp[0usize..4usize])
    if e != ok { ret }
    var i = 0usize
    while i < usize(n) {
        buf_byte(b, tmp[i])
        i += 1usize
    }
}

// --- Schemes.

fn is_special_scheme(s: str) -> bool {
    ret str.eq(s, "http") || str.eq(s, "https") || str.eq(s, "ws") || str.eq(s, "wss") || str.eq(s, "ftp") || str.eq(s, "file")
}

// The default port of a special scheme (-1 for none, including `file`).
fn default_port(s: str) -> i32 {
    if str.eq(s, "http") || str.eq(s, "ws") { ret 80i32 }
    if str.eq(s, "https") || str.eq(s, "wss") { ret 443i32 }
    if str.eq(s, "ftp") { ret 21i32 }
    ret -1i32
}

fn is_special(u: *const Url) -> bool { ret is_special_scheme(u.scheme) }

fn includes_credentials(u: *const Url) -> bool { ret u.username.len > 0usize || u.password.len > 0usize }

// --- Hosts.

fn forbidden_host(c: u32) -> bool {
    ret c == 0u32 || c == 9u32 || c == 10u32 || c == 13u32 || c == 32u32 || c == 35u32 || c == 47u32 || c == 58u32 || c == 60u32 || c == 62u32 || c == 63u32 || c == 64u32 || c == 91u32 || c == 92u32 || c == 93u32 || c == 94u32 || c == 124u32
}

fn forbidden_domain(c: u32) -> bool {
    ret forbidden_host(c) || c <= 31u32 || c == 37u32 || c == 127u32
}

// Percent-decoded bytes of `s`, as valid UTF-8 (a malformed sequence becomes U+FFFD).
fn pct_decode_utf8(a: *mem.Arena, s: str) -> str {
    let (raw, e1) = mem.alloc[u8](a, s.len + 1usize)
    if e1 != ok { ret "" }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] == 37u8 && i + 2usize < s.len + 0usize && i + 2usize <= s.len - 1usize && is_hex(u32(s[i + 1usize])) && is_hex(u32(s[i + 2usize])) {
            raw[n] = u8(hex_val(u32(s[i + 1usize])) * 16u32 + hex_val(u32(s[i + 2usize])))
            n += 1usize
            i += 3usize
        } else {
            raw[n] = s[i]
            n += 1usize
            i += 1usize
        }
    }
    let bytes = raw[0usize..n]
    if utf8.validate(bytes) { ret bytes }
    let (out, e2) = mem.alloc[u8](a, n * 3usize + 3usize)
    if e2 != ok { ret "" }
    var m = 0usize
    var it = utf8.iterator(bytes)
    while true {
        let (sc, more) = utf8.iterator_next(&it)
        if !more { break }
        var tmp: [4]u8 = zero
        let (w, ee) = utf8.encode(sc, tmp[0usize..4usize])
        if ee != ok { continue }
        var k = 0usize
        while k < usize(w) {
            out[m] = tmp[k]
            m += 1usize
            k += 1usize
        }
    }
    ret out[0usize..m]
}

fn lower_ascii_copy(a: *mem.Arena, s: str) -> str {
    let (d, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret "" }
    var i = 0usize
    while i < s.len {
        d[i] = u8(lower_ascii(u32(s[i])))
        i += 1usize
    }
    ret d[0usize..s.len]
}

fn all_ascii(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] >= 128u8 { ret false }
        i += 1usize
    }
    ret true
}

// Whether any label of an ASCII domain starts with `xn--` (any case).
fn has_xn_label(s: str) -> bool {
    var start = 0usize
    var i = 0usize
    while i <= s.len {
        if i == s.len || s[i] == 46u8 {
            if i - start >= 4usize && lower_ascii(u32(s[start])) == 120u32 && lower_ascii(u32(s[start + 1usize])) == 110u32 && s[start + 2usize] == 45u8 && s[start + 3usize] == 45u8 { ret true }
            start = i + 1usize
        }
        i += 1usize
    }
    ret false
}

// Domain to ASCII (UTS #46, not strict): plain ASCII is lower-cased, anything else goes through the mapping table.
fn domain_to_ascii(a: *mem.Arena, domain: str) -> (str, bool) {
    if all_ascii(domain) && !has_xn_label(domain) {
        if domain.len == 0usize { ret ("", false) }
        ret (lower_ascii_copy(a, domain), true)
    }
    let (r, good) = uts46.to_ascii(a, domain, false)
    if !good || r.len == 0usize { ret ("", false) }
    ret (r, true)
}

// One IPv4 number in the legacy notations: decimal, 0x hexadecimal, leading-0 octal. `ok` false for anything else.
fn ipv4_number(s: str) -> (u64, bool) {
    if s.len == 0usize { ret (0u64, false) }
    var radix = 10u64
    var at = 0usize
    if s.len >= 2usize && s[0usize] == 48u8 && (s[1usize] == 120u8 || s[1usize] == 88u8) {
        radix = 16u64
        at = 2usize
    } else if s.len >= 2usize && s[0usize] == 48u8 {
        radix = 8u64
        at = 1usize
    }
    var v = 0u64
    while at < s.len {
        let c = u32(s[at])
        var d = 0u64
        if radix == 16u64 {
            if !is_hex(c) { ret (0u64, false) }
            d = u64(hex_val(c))
        } else {
            if !is_digit(c) { ret (0u64, false) }
            d = u64(c - 48u32)
            if d >= radix { ret (0u64, false) }
        }
        v = v * radix + d
        if v > 18446744073709551u64 { v = 18446744073709551u64 }
        at += 1usize
    }
    ret (v, true)
}

fn split_dots(a: *mem.Arena, s: str) -> []const str {
    var out = list_of_str(a)
    var start = 0usize
    var i = 0usize
    while i <= s.len {
        if i == s.len || s[i] == 46u8 {
            let pushed = list.push[str](&out, s[start..i])
            start = i + 1usize
        }
        i += 1usize
    }
    ret list.slice_const[str](&out)
}

fn list_of_str(a: *mem.Arena) -> list.List[str] {
    let (l, e) = list.init[str](a, 8usize)
    if e != ok { ret zero }
    ret l
}

// Whether the last label of an ASCII domain is a number (decimal digits or a legacy IPv4 number).
fn ends_in_number(a: *mem.Arena, domain: str) -> bool {
    var parts = split_dots(a, domain)
    var n = parts.len
    if n == 0usize { ret false }
    if parts[n - 1usize].len == 0usize {
        if n == 1usize { ret false }
        n -= 1usize
    }
    let last = parts[n - 1usize]
    if last.len > 0usize {
        var digits = true
        var i = 0usize
        while i < last.len {
            if !is_digit(u32(last[i])) { digits = false }
            i += 1usize
        }
        if digits { ret true }
    }
    let (_v, good) = ipv4_number(last)
    ret good
}

fn parse_ipv4(a: *mem.Arena, input: str) -> (str, bool) {
    var parts = split_dots(a, input)
    var n = parts.len
    if parts[n - 1usize].len == 0usize && n > 1usize { n -= 1usize }
    if n > 4usize { ret ("", false) }
    var nums: [4]u64 = zero
    var i = 0usize
    while i < n {
        let (v, good) = ipv4_number(parts[i])
        if !good { ret ("", false) }
        nums[i] = v
        i += 1usize
    }
    i = 0usize
    while i + 1usize < n {
        if nums[i] > 255u64 { ret ("", false) }
        i += 1usize
    }
    var limit = 1u64
    var k = 0usize
    while k < 5usize - n {
        limit = limit * 256u64
        k += 1usize
    }
    if nums[n - 1usize] >= limit { ret ("", false) }
    var ipv4 = nums[n - 1usize]
    i = 0usize
    var mult = 16777216u64
    while i + 1usize < n {
        ipv4 = ipv4 + nums[i] * mult
        mult = mult / 256u64
        i += 1usize
    }
    let (b, be) = buf_new(a, 16usize)
    if be != ok { ret ("", false) }
    var buf = b
    var shift = 24u64
    var j = 0usize
    while j < 4usize {
        let octet = (ipv4 >> shift) & 255u64
        put_decimal(&buf, octet)
        if j < 3usize { buf_byte(&buf, 46u8) }
        if shift >= 8u64 { shift -= 8u64 }
        j += 1usize
    }
    ret (buf_take(a, &buf), true)
}

fn put_decimal(b: *Buf, v: u64) {
    if v >= 10u64 { put_decimal(b, v / 10u64) }
    buf_byte(b, u8(48u64 + v % 10u64))
}

fn put_hex16(b: *Buf, v: u32) {
    var started = false
    var shift = 12u32
    var i = 0usize
    while i < 4usize {
        let d = (v >> shift) & 15u32
        if d != 0u32 || started || i == 3usize {
            started = true
            var c = u8(48u32 + d)
            if d >= 10u32 { c = u8(87u32 + d) }
            buf_byte(b, c)
        }
        if shift >= 4u32 { shift -= 4u32 }
        i += 1usize
    }
}

fn parse_ipv6(a: *mem.Arena, input: str) -> (str, bool) {
    var pieces: [8]u32 = zero
    var piece_index = 0usize
    var compress = 8usize
    var has_compress = false
    var p = 0usize
    let n = input.len
    if p < n && input[p] == 58u8 {
        if p + 1usize >= n || input[p + 1usize] != 58u8 { ret ("", false) }
        p += 2usize
        piece_index += 1usize
        compress = piece_index
        has_compress = true
    }
    while p < n {
        if piece_index == 8usize { ret ("", false) }
        if input[p] == 58u8 {
            if has_compress { ret ("", false) }
            p += 1usize
            piece_index += 1usize
            compress = piece_index
            has_compress = true
            continue
        }
        var value = 0u32
        var length = 0usize
        while length < 4usize && p < n && is_hex(u32(input[p])) {
            value = value * 16u32 + hex_val(u32(input[p]))
            p += 1usize
            length += 1usize
        }
        if p < n && input[p] == 46u8 {
            if length == 0usize { ret ("", false) }
            p -= length
            if piece_index > 6usize { ret ("", false) }
            var numbers_seen = 0usize
            while p < n {
                var ipv4_piece = -1i32
                if numbers_seen > 0usize {
                    if input[p] == 46u8 && numbers_seen < 4usize {
                        p += 1usize
                    } else {
                        ret ("", false)
                    }
                }
                if p >= n || !is_digit(u32(input[p])) { ret ("", false) }
                while p < n && is_digit(u32(input[p])) {
                    let number = i32(input[p]) - 48i32
                    if ipv4_piece == -1i32 {
                        ipv4_piece = number
                    } else if ipv4_piece == 0i32 {
                        ret ("", false)
                    } else {
                        ipv4_piece = ipv4_piece * 10i32 + number
                    }
                    if ipv4_piece > 255i32 { ret ("", false) }
                    p += 1usize
                }
                pieces[piece_index] = pieces[piece_index] * 256u32 + u32(ipv4_piece)
                numbers_seen += 1usize
                if numbers_seen == 2usize || numbers_seen == 4usize { piece_index += 1usize }
            }
            if numbers_seen != 4usize { ret ("", false) }
            break
        } else if p < n && input[p] == 58u8 {
            p += 1usize
            if p >= n { ret ("", false) }
        } else if p < n {
            ret ("", false)
        }
        pieces[piece_index] = value
        piece_index += 1usize
    }
    if has_compress {
        var swaps = piece_index - compress
        piece_index = 7usize
        while piece_index != 0usize && swaps > 0usize {
            let from = compress + swaps - 1usize
            let tmp = pieces[piece_index]
            pieces[piece_index] = pieces[from]
            pieces[from] = tmp
            piece_index -= 1usize
            swaps -= 1usize
        }
    } else if piece_index != 8usize {
        ret ("", false)
    }
    // Serialise, compressing the first longest run of two or more zero pieces.
    var best = 8usize
    var best_len = 0usize
    var i = 0usize
    while i < 8usize {
        if pieces[i] == 0u32 {
            var j = i
            while j < 8usize && pieces[j] == 0u32 { j += 1usize }
            if j - i > best_len {
                best = i
                best_len = j - i
            }
            i = j
        } else {
            i += 1usize
        }
    }
    if best_len < 2usize { best = 8usize }
    let (b, be) = buf_new(a, 48usize)
    if be != ok { ret ("", false) }
    var buf = b
    buf_byte(&buf, 91u8)
    var ignore0 = false
    i = 0usize
    while i < 8usize {
        if ignore0 && pieces[i] == 0u32 {
            i += 1usize
            continue
        } else if ignore0 {
            ignore0 = false
        }
        if best == i {
            if i == 0usize { buf_str(&buf, "::") } else { buf_byte(&buf, 58u8) }
            ignore0 = true
            i += 1usize
            continue
        }
        put_hex16(&buf, pieces[i])
        if i != 7usize { buf_byte(&buf, 58u8) }
        i += 1usize
    }
    buf_byte(&buf, 93u8)
    ret (buf_take(a, &buf), true)
}

// The host parser: `opaque` for non-special URLs.
fn parse_host(a: *mem.Arena, input: str, opaque: bool) -> (str, bool) {
    if input.len > 0usize && input[0usize] == 91u8 {
        if input[input.len - 1usize] != 93u8 { ret ("", false) }
        let (v6, v6_ok) = parse_ipv6(a, input[1usize..input.len - 1usize])
        ret (v6, v6_ok)
    }
    if opaque {
        var i = 0usize
        while i < input.len {
            if forbidden_host(u32(input[i])) { ret ("", false) }
            i += 1usize
        }
        let (b, be) = buf_new(a, input.len * 3usize)
        if be != ok { ret ("", false) }
        var buf = b
        var it = utf8.iterator(input)
        while true {
            let (sc, more) = utf8.iterator_next(&it)
            if !more { break }
            put_encoded(&buf, sc, .C0)
        }
        ret (buf_take(a, &buf), true)
    }
    let domain = pct_decode_utf8(a, input)
    let (ascii, good) = domain_to_ascii(a, domain)
    if !good { ret ("", false) }
    var i2 = 0usize
    while i2 < ascii.len {
        if forbidden_domain(u32(ascii[i2])) { ret ("", false) }
        i2 += 1usize
    }
    if ends_in_number(a, ascii) {
        let (v4, v4_ok) = parse_ipv4(a, ascii)
        ret (v4, v4_ok)
    }
    ret (ascii, true)
}

// --- Windows drive letters.

fn is_windows_drive_letter(s: str) -> bool {
    ret s.len == 2usize && is_alpha(u32(s[0usize])) && (s[1usize] == 58u8 || s[1usize] == 124u8)
}

fn is_normalized_drive_letter(s: str) -> bool {
    ret s.len == 2usize && is_alpha(u32(s[0usize])) && s[1usize] == 58u8
}

// Whether the scalars from `at` start with a Windows drive letter not followed by anything but / \ ? # or the end.
fn starts_with_drive_letter(cps: []const u32, at: usize) -> bool {
    if at + 1usize >= cps.len { ret false }
    if !is_alpha(cps[at]) || (cps[at + 1usize] != 58u32 && cps[at + 1usize] != 124u32) { ret false }
    if at + 2usize == cps.len { ret true }
    let c = cps[at + 2usize]
    ret c == 47u32 || c == 92u32 || c == 63u32 || c == 35u32
}

// --- Path helpers.

fn is_single_dot(s: str) -> bool {
    ret str.eq(s, ".") || str.eq(s, "%2e") || str.eq(s, "%2E")
}

fn is_double_dot(s: str) -> bool {
    if str.eq(s, "..") || str.eq(s, ".%2e") || str.eq(s, ".%2E") || str.eq(s, "%2e.") || str.eq(s, "%2E.") { ret true }
    ret str.eq(s, "%2e%2e") || str.eq(s, "%2e%2E") || str.eq(s, "%2E%2e") || str.eq(s, "%2E%2E")
}

// --- The parser.

type Parser = struct {
    a: *mem.Arena, scheme: str, username: str, password: str,
    host: str, has_host: bool, port: i32,
    segs: list.List[str], opaque_path: bool, opaque_text: Buf,
    query: str, has_query: bool, fragment: str, has_fragment: bool
}

fn from_parser(p: *const Parser) -> Url {
    var u: Url = zero
    u.scheme = p.scheme
    u.username = p.username
    u.password = p.password
    u.host = p.host
    u.has_host = p.has_host
    u.port = p.port
    u.opaque_path = p.opaque_path
    u.query = p.query
    u.has_query = p.has_query
    u.fragment = p.fragment
    u.has_fragment = p.has_fragment
    u.path = join_path(p)
    ret u
}

fn join_path(p: *const Parser) -> str {
    if p.opaque_path { ret buf_take(p.a, &p.opaque_text) }
    var total = 0usize
    var i = 0usize
    while i < p.segs.len {
        total += p.segs.items[i].len + 1usize
        i += 1usize
    }
    let (b, be) = buf_new(p.a, total)
    if be != ok { ret "" }
    var buf = b
    i = 0usize
    while i < p.segs.len {
        buf_byte(&buf, 47u8)
        buf_str(&buf, p.segs.items[i])
        i += 1usize
    }
    ret buf_take(p.a, &buf)
}

// Splits a serialised path back into its segments.
fn path_segments(a: *mem.Arena, path: str) -> list.List[str] {
    var segs = list_of_str(a)
    if path.len == 0usize { ret segs }
    var start = 1usize
    var i = 1usize
    while i <= path.len {
        if i == path.len || path[i] == 47u8 {
            let pushed = list.push[str](&segs, copy_str(a, path[start..i]))
            start = i + 1usize
        }
        i += 1usize
    }
    ret segs
}

fn to_parser(a: *mem.Arena, u: *const Url) -> Parser {
    var p: Parser = zero
    p.a = a
    p.scheme = u.scheme
    p.username = u.username
    p.password = u.password
    p.host = u.host
    p.has_host = u.has_host
    p.port = u.port
    p.opaque_path = u.opaque_path
    p.query = u.query
    p.has_query = u.has_query
    p.fragment = u.fragment
    p.has_fragment = u.has_fragment
    let (ob, oe) = buf_new(a, u.path.len)
    if oe == ok {
        p.opaque_text = ob
        if u.opaque_path { buf_str(&p.opaque_text, u.path) }
    }
    if u.opaque_path {
        p.segs = list_of_str(a)
    } else {
        p.segs = path_segments(a, u.path)
    }
    ret p
}

fn shorten_path(p: *Parser) {
    if p.segs.len == 0usize { ret }
    if str.eq(p.scheme, "file") && p.segs.len == 1usize && is_normalized_drive_letter(p.segs.items[0usize]) { ret }
    p.segs.len -= 1usize
}

fn push_seg(p: *Parser, s: str) {
    let pushed = list.push[str](&p.segs, copy_str(p.a, s))
}

fn decode_input(a: *mem.Arena, input: str) -> ([]u32, err) {
    let (out, e) = mem.alloc[u32](a, input.len + 1usize)
    if e != ok { ret (zero, e) }
    var n = 0usize
    var it = utf8.iterator(input)
    while true {
        let (sc, more) = utf8.iterator_next(&it)
        if !more { break }
        out[n] = sc
        n += 1usize
    }
    ret (out[0usize..n], ok)
}

fn is_c0_or_space(c: u32) -> bool { ret c <= 32u32 }

fn is_tab_newline(c: u32) -> bool { ret c == 9u32 || c == 10u32 || c == 13u32 }

// Runs the basic URL parser over `input`. `base_ptr` is a pointer to the base (a null address: none). When `target` is
// given the parser works on it with `override` as the starting state and answers whether the setter succeeded.
fn run(a: *mem.Arena, input_text: str, base: *const Url, has_base: bool, p: *Parser, has_override: bool, override: State) -> bool {
    // The opaque path buffer must hold what this input can add to what it already holds.
    if p.opaque_text.data.len < p.opaque_text.len + input_text.len * 3usize + 32usize {
        var grown = zero_buf(a, p.opaque_text.len + input_text.len * 3usize + 32usize)
        buf_str(&grown, buf_text(&p.opaque_text))
        p.opaque_text = grown
    }
    let trim = !has_override
    let (all, de) = decode_input(a, input_text)
    if de != ok { ret false }
    var lo = 0usize
    var hi = all.len
    if trim {
        while lo < hi && is_c0_or_space(all[lo]) { lo += 1usize }
        while hi > lo && is_c0_or_space(all[hi - 1usize]) { hi -= 1usize }
    }
    let (cps_mem, ce) = mem.alloc[u32](a, hi - lo + 1usize)
    if ce != ok { ret false }
    var n = 0usize
    var i = lo
    while i < hi {
        if !is_tab_newline(all[i]) {
            cps_mem[n] = all[i]
            n += 1usize
        }
        i += 1usize
    }
    let cps = cps_mem[0usize..n]
    var state = State.SchemeStart
    if has_override { state = override }
    let (bb, be) = buf_new(a, input_text.len * 3usize + 16usize)
    if be != ok { ret false }
    var buffer = bb
    var at_sign_seen = false
    var inside_brackets = false
    var password_token_seen = false
    var pointer = 0i64
    let count = i64(n)
    while true {
        var c = EOF
        if pointer >= 0i64 && pointer < count { c = cps[usize(pointer)] }
        let special = is_special_scheme(p.scheme)
        if state == .SchemeStart {
            if c != EOF && is_alpha(c) {
                buf_byte(&buffer, u8(lower_ascii(c)))
                state = .Scheme
            } else if !has_override {
                state = .NoScheme
                pointer -= 1i64
            } else {
                ret false
            }
        } else if state == .Scheme {
            if c != EOF && (is_alpha(c) || is_digit(c) || c == 43u32 || c == 45u32 || c == 46u32) {
                buf_byte(&buffer, u8(lower_ascii(c)))
            } else if c == 58u32 {
                let candidate = buf_take(a, &buffer)
                if has_override {
                    if is_special_scheme(p.scheme) != is_special_scheme(candidate) { ret true }
                    if (p.username.len > 0usize || p.password.len > 0usize || p.port >= 0i32) && str.eq(candidate, "file") { ret true }
                    if str.eq(p.scheme, "file") && p.has_host && p.host.len == 0usize { ret true }
                }
                p.scheme = candidate
                if has_override {
                    if p.port == default_port(p.scheme) { p.port = -1i32 }
                    ret true
                }
                buffer.len = 0usize
                if str.eq(p.scheme, "file") {
                    state = .File
                } else if is_special_scheme(p.scheme) && has_base && str.eq(base.scheme, p.scheme) {
                    state = .SpecialRelativeOrAuthority
                } else if is_special_scheme(p.scheme) {
                    state = .SpecialAuthoritySlashes
                } else if pointer + 1i64 < count && cps[usize(pointer + 1i64)] == 47u32 {
                    state = .PathOrAuthority
                    pointer += 1i64
                } else {
                    p.opaque_path = true
                    p.opaque_text.len = 0usize
                    state = .OpaquePath
                }
            } else if !has_override {
                buffer.len = 0usize
                state = .NoScheme
                pointer = -1i64
            } else {
                ret false
            }
        } else if state == .NoScheme {
            if !has_base || (base.opaque_path && c != 35u32) { ret false }
            if base.opaque_path && c == 35u32 {
                p.scheme = base.scheme
                p.opaque_path = true
                p.opaque_text.len = 0usize
                buf_str(&p.opaque_text, base.path)
                p.query = base.query
                p.has_query = base.has_query
                p.fragment = ""
                p.has_fragment = true
                state = .Fragment
            } else if !str.eq(base.scheme, "file") {
                state = .Relative
                pointer -= 1i64
            } else {
                state = .File
                pointer -= 1i64
            }
        } else if state == .SpecialRelativeOrAuthority {
            if c == 47u32 && pointer + 1i64 < count && cps[usize(pointer + 1i64)] == 47u32 {
                state = .SpecialAuthorityIgnoreSlashes
                pointer += 1i64
            } else {
                state = .Relative
                pointer -= 1i64
            }
        } else if state == .PathOrAuthority {
            if c == 47u32 {
                state = .Authority
            } else {
                state = .Path
                pointer -= 1i64
            }
        } else if state == .Relative {
            p.scheme = base.scheme
            if c == 47u32 {
                state = .RelativeSlash
            } else if is_special_scheme(p.scheme) && c == 92u32 {
                state = .RelativeSlash
            } else {
                p.username = base.username
                p.password = base.password
                p.host = base.host
                p.has_host = base.has_host
                p.port = base.port
                p.segs = path_segments(a, base.path)
                p.opaque_path = false
                p.query = base.query
                p.has_query = base.has_query
                if c == 63u32 {
                    p.query = ""
                    p.has_query = true
                    state = .Query
                } else if c == 35u32 {
                    p.fragment = ""
                    p.has_fragment = true
                    state = .Fragment
                } else if c != EOF {
                    p.query = ""
                    p.has_query = false
                    shorten_path(p)
                    state = .Path
                    pointer -= 1i64
                }
            }
        } else if state == .RelativeSlash {
            if special && (c == 47u32 || c == 92u32) {
                state = .SpecialAuthorityIgnoreSlashes
            } else if c == 47u32 {
                state = .Authority
            } else {
                p.username = base.username
                p.password = base.password
                p.host = base.host
                p.has_host = base.has_host
                p.port = base.port
                state = .Path
                pointer -= 1i64
            }
        } else if state == .SpecialAuthoritySlashes {
            if c == 47u32 && pointer + 1i64 < count && cps[usize(pointer + 1i64)] == 47u32 {
                state = .SpecialAuthorityIgnoreSlashes
                pointer += 1i64
            } else {
                state = .SpecialAuthorityIgnoreSlashes
                pointer -= 1i64
            }
        } else if state == .SpecialAuthorityIgnoreSlashes {
            if c != 47u32 && c != 92u32 {
                state = .Authority
                pointer -= 1i64
            }
        } else if state == .Authority {
            if c == 64u32 {
                if at_sign_seen {
                    // A second @: the first one's text belongs to the password.
                    let held = buf_take(a, &buffer)
                    buffer.len = 0usize
                    buf_str(&buffer, "%40")
                    buf_str(&buffer, held)
                }
                at_sign_seen = true
                var ub = zero_buf(a, buffer.len * 3usize + p.username.len + p.password.len + 8usize)
                var pb = zero_buf(a, buffer.len * 3usize + p.username.len + p.password.len + 8usize)
                buf_str(&ub, p.username)
                buf_str(&pb, p.password)
                var it = utf8.iterator(buf_text(&buffer))
                while true {
                    let (sc, more) = utf8.iterator_next(&it)
                    if !more { break }
                    if sc == 58u32 && !password_token_seen {
                        password_token_seen = true
                        continue
                    }
                    if password_token_seen { put_encoded(&pb, sc, .Userinfo) } else { put_encoded(&ub, sc, .Userinfo) }
                }
                p.username = buf_take(a, &ub)
                p.password = buf_take(a, &pb)
                buffer.len = 0usize
            } else if c == EOF || c == 47u32 || c == 63u32 || c == 35u32 || (special && c == 92u32) {
                if at_sign_seen && buffer.len == 0usize { ret false }
                let held = buf_take(a, &buffer)
                var chars = 0i64
                var it2 = utf8.iterator(held)
                while true {
                    let (sc2, more2) = utf8.iterator_next(&it2)
                    if !more2 { break }
                    chars += 1i64
                }
                pointer -= chars + 1i64
                buffer.len = 0usize
                state = .Host
            } else {
                put_scalar(&buffer, c)
            }
        } else if state == .Host || state == .Hostname {
            if has_override && str.eq(p.scheme, "file") {
                pointer -= 1i64
                state = .FileHost
            } else if c == 58u32 && !inside_brackets {
                if buffer.len == 0usize { ret false }
                if has_override && override == .Hostname { ret false }
                let (h, good) = parse_host(a, buf_take(a, &buffer), !special)
                if !good { ret false }
                p.host = h
                p.has_host = true
                buffer.len = 0usize
                state = .Port
            } else if c == EOF || c == 47u32 || c == 63u32 || c == 35u32 || (special && c == 92u32) {
                pointer -= 1i64
                if special && buffer.len == 0usize {
                    ret false
                } else if has_override && buffer.len == 0usize && (p.username.len > 0usize || p.password.len > 0usize || p.port >= 0i32) {
                    ret false
                }
                let (h2, good2) = parse_host(a, buf_take(a, &buffer), !special)
                if !good2 { ret false }
                p.host = h2
                p.has_host = true
                buffer.len = 0usize
                state = .PathStart
                if has_override { ret true }
            } else {
                if c == 91u32 { inside_brackets = true }
                if c == 93u32 { inside_brackets = false }
                put_scalar(&buffer, c)
            }
        } else if state == .Port {
            if c != EOF && is_digit(c) {
                buf_byte(&buffer, u8(c))
            } else if c == EOF || c == 47u32 || c == 63u32 || c == 35u32 || (special && c == 92u32) || has_override {
                if buffer.len != 0usize {
                    var port = 0i64
                    var k = 0usize
                    while k < buffer.len {
                        port = port * 10i64 + i64(buffer.data[k]) - 48i64
                        if port > 65535i64 { ret false }
                        k += 1usize
                    }
                    if i32(port) == default_port(p.scheme) { p.port = -1i32 } else { p.port = i32(port) }
                    buffer.len = 0usize
                    if has_override { ret true }
                }
                if has_override { ret true }
                state = .PathStart
                pointer -= 1i64
            } else {
                ret false
            }
        } else if state == .File {
            p.scheme = "file"
            p.host = ""
            p.has_host = true
            if c == 47u32 || c == 92u32 {
                state = .FileSlash
            } else if has_base && str.eq(base.scheme, "file") {
                p.host = base.host
                p.has_host = base.has_host
                p.segs = path_segments(a, base.path)
                p.opaque_path = false
                p.query = base.query
                p.has_query = base.has_query
                if c == 63u32 {
                    p.query = ""
                    p.has_query = true
                    state = .Query
                } else if c == 35u32 {
                    p.fragment = ""
                    p.has_fragment = true
                    state = .Fragment
                } else if c != EOF {
                    p.query = ""
                    p.has_query = false
                    if !starts_with_drive_letter(cps, usize(pointer)) { shorten_path(p) } else { p.segs.len = 0usize }
                    state = .Path
                    pointer -= 1i64
                }
            } else {
                state = .Path
                pointer -= 1i64
            }
        } else if state == .FileSlash {
            if c == 47u32 || c == 92u32 {
                state = .FileHost
            } else {
                if has_base && str.eq(base.scheme, "file") {
                    p.host = base.host
                    p.has_host = base.has_host
                    let bsegs = path_segments(a, base.path)
                    if !starts_with_drive_letter(cps, usize(pointer)) && bsegs.len > 0usize && is_normalized_drive_letter(bsegs.items[0usize]) { push_seg(p, bsegs.items[0usize]) }
                }
                state = .Path
                pointer -= 1i64
            }
        } else if state == .FileHost {
            if c == EOF || c == 47u32 || c == 92u32 || c == 63u32 || c == 35u32 {
                pointer -= 1i64
                if !has_override && is_windows_drive_letter(buf_text(&buffer)) {
                    state = .Path
                } else if buffer.len == 0usize {
                    p.host = ""
                    p.has_host = true
                    if has_override { ret true }
                    state = .PathStart
                } else {
                    let (h3, good3) = parse_host(a, buf_take(a, &buffer), !special)
                    if !good3 { ret false }
                    var hh = h3
                    if str.eq(hh, "localhost") { hh = "" }
                    p.host = hh
                    p.has_host = true
                    if has_override { ret true }
                    buffer.len = 0usize
                    state = .PathStart
                }
            } else {
                put_scalar(&buffer, c)
            }
        } else if state == .PathStart {
            if special {
                state = .Path
                if c != 47u32 && c != 92u32 { pointer -= 1i64 }
            } else if !has_override && c == 63u32 {
                p.query = ""
                p.has_query = true
                state = .Query
            } else if !has_override && c == 35u32 {
                p.fragment = ""
                p.has_fragment = true
                state = .Fragment
            } else if c != EOF {
                state = .Path
                if c != 47u32 { pointer -= 1i64 }
            } else if has_override && !p.has_host {
                push_seg(p, "")
            }
        } else if state == .Path {
            if c == EOF || c == 47u32 || (special && c == 92u32) || (!has_override && (c == 63u32 || c == 35u32)) {
                let seg = buf_take(a, &buffer)
                let slash = c == 47u32 || (special && c == 92u32)
                if is_double_dot(seg) {
                    shorten_path(p)
                    if !slash { push_seg(p, "") }
                } else if is_single_dot(seg) && !slash {
                    push_seg(p, "")
                } else if !is_single_dot(seg) {
                    var s2 = seg
                    if str.eq(p.scheme, "file") && p.segs.len == 0usize && is_windows_drive_letter(seg) {
                        let (fixed, fe) = mem.alloc[u8](a, 3usize)
                        if fe == ok {
                            fixed[0usize] = seg[0usize]
                            fixed[1usize] = 58u8
                            s2 = fixed[0usize..2usize]
                        }
                    }
                    push_seg(p, s2)
                }
                buffer.len = 0usize
                if c == 63u32 {
                    p.query = ""
                    p.has_query = true
                    state = .Query
                }
                if c == 35u32 {
                    p.fragment = ""
                    p.has_fragment = true
                    state = .Fragment
                }
            } else {
                put_encoded(&buffer, c, .Path)
            }
        } else if state == .OpaquePath {
            if c == 63u32 {
                p.query = ""
                p.has_query = true
                state = .Query
            } else if c == 35u32 {
                p.fragment = ""
                p.has_fragment = true
                state = .Fragment
            } else if c == 32u32 {
                let next = pointer + 1i64
                if next < count && (cps[usize(next)] == 63u32 || cps[usize(next)] == 35u32) { buf_str(&p.opaque_text, "%20") } else { buf_byte(&p.opaque_text, 32u8) }
            } else if c != EOF {
                put_encoded(&p.opaque_text, c, .C0)
            }
        } else if state == .Query {
            if (!has_override && c == 35u32) || c == EOF {
                var set = EncodeSet.Query
                if special { set = .SpecialQuery }
                let raw = buf_take(a, &buffer)
                var qb = zero_buf(a, raw.len * 3usize + p.query.len + 8usize)
                buf_str(&qb, p.query)
                var it3 = utf8.iterator(raw)
                while true {
                    let (sc3, more3) = utf8.iterator_next(&it3)
                    if !more3 { break }
                    put_encoded(&qb, sc3, set)
                }
                p.query = buf_take(a, &qb)
                buffer.len = 0usize
                if c == 35u32 {
                    p.fragment = ""
                    p.has_fragment = true
                    state = .Fragment
                }
            } else if c != EOF {
                put_scalar(&buffer, c)
            }
        } else if state == .Fragment {
            if c != EOF {
                var fb = zero_buf(a, p.fragment.len + 16usize)
                buf_str(&fb, p.fragment)
                put_encoded(&fb, c, .Fragment)
                p.fragment = buf_take(a, &fb)
            }
        }
        if pointer >= count { break }
        pointer += 1i64
    }
    ret true
}

fn zero_buf(a: *mem.Arena, cap: usize) -> Buf {
    let (b, e) = buf_new(a, cap)
    if e != ok { ret zero }
    ret b
}

fn new_parser(a: *mem.Arena) -> Parser {
    var p: Parser = zero
    p.a = a
    p.scheme = ""
    p.username = ""
    p.password = ""
    p.host = ""
    p.has_host = false
    p.port = -1i32
    p.segs = list_of_str(a)
    p.opaque_path = false
    p.opaque_text = zero_buf(a, 64usize)
    p.query = ""
    p.fragment = ""
    ret p
}

// Parses `input` (against `base` when it is relative).
fn parse(a: *mem.Arena, input: str, base: *const Url, has_base: bool) -> (Url, err) {
    var p = new_parser(a)
    if !run(a, input, base, has_base, &p, false, State.SchemeStart) { ret (zero, Failure) }
    ret (from_parser(&p), ok)
}

// Parses `input` against a base given as text.
fn parse_against(a: *mem.Arena, input: str, base_text: str) -> (Url, err) {
    let (b, be) = parse(a, base_text, zero, false)
    if be != ok { ret (zero, be) }
    let (u, ue) = parse(a, input, &b, true)
    ret (u, ue)
}

// --- Serialisation.

fn serialize_authority(buf: *Buf, u: *const Url) {
    if u.username.len > 0usize || u.password.len > 0usize {
        buf_str(buf, u.username)
        if u.password.len > 0usize {
            buf_byte(buf, 58u8)
            buf_str(buf, u.password)
        }
        buf_byte(buf, 64u8)
    }
    buf_str(buf, u.host)
    if u.port >= 0i32 {
        buf_byte(buf, 58u8)
        put_decimal(buf, u64(u.port))
    }
}

fn href(a: *mem.Arena, u: *const Url, exclude_fragment: bool) -> str {
    var buf = zero_buf(a, u.scheme.len + u.username.len + u.password.len + u.host.len + u.path.len + u.query.len + u.fragment.len + 32usize)
    buf_str(&buf, u.scheme)
    buf_byte(&buf, 58u8)
    if u.has_host {
        buf_str(&buf, "//")
        serialize_authority(&buf, u)
    } else if !u.opaque_path && u.path.len > 1usize && u.path[0usize] == 47u8 && u.path[1usize] == 47u8 {
        buf_str(&buf, "/.")
    }
    buf_str(&buf, u.path)
    if u.has_query {
        buf_byte(&buf, 63u8)
        buf_str(&buf, u.query)
    }
    if !exclude_fragment && u.has_fragment {
        buf_byte(&buf, 35u8)
        buf_str(&buf, u.fragment)
    }
    ret buf_take(a, &buf)
}

// The serialisation of the origin, "null" for an opaque origin.
fn origin(a: *mem.Arena, u: *const Url) -> str {
    if str.eq(u.scheme, "blob") {
        let (inner, e) = parse(a, u.path, zero, false)
        if e == ok && (str.eq(inner.scheme, "http") || str.eq(inner.scheme, "https")) { ret origin(a, &inner) }
        ret "null"
    }
    if str.eq(u.scheme, "http") || str.eq(u.scheme, "https") || str.eq(u.scheme, "ws") || str.eq(u.scheme, "wss") || str.eq(u.scheme, "ftp") {
        var buf = zero_buf(a, u.scheme.len + u.host.len + 16usize)
        buf_str(&buf, u.scheme)
        buf_str(&buf, "://")
        buf_str(&buf, u.host)
        if u.port >= 0i32 {
            buf_byte(&buf, 58u8)
            put_decimal(&buf, u64(u.port))
        }
        ret buf_take(a, &buf)
    }
    ret "null"
}

fn protocol(a: *mem.Arena, u: *const Url) -> str { ret join2(a, u.scheme, ":") }

fn join2(a: *mem.Arena, x: str, y: str) -> str {
    let (r, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret r
}

// "host" of the URL API: the host and, when present, ":port".
fn host_port(a: *mem.Arena, u: *const Url) -> str {
    if !u.has_host { ret "" }
    if u.port < 0i32 { ret u.host }
    var buf = zero_buf(a, u.host.len + 8usize)
    buf_str(&buf, u.host)
    buf_byte(&buf, 58u8)
    put_decimal(&buf, u64(u.port))
    ret buf_take(a, &buf)
}

fn port_text(a: *mem.Arena, u: *const Url) -> str {
    if u.port < 0i32 { ret "" }
    var buf = zero_buf(a, 8usize)
    put_decimal(&buf, u64(u.port))
    ret buf_take(a, &buf)
}

fn search(a: *mem.Arena, u: *const Url) -> str {
    if !u.has_query || u.query.len == 0usize { ret "" }
    ret join2(a, "?", u.query)
}

fn hash(a: *mem.Arena, u: *const Url) -> str {
    if !u.has_fragment || u.fragment.len == 0usize { ret "" }
    ret join2(a, "#", u.fragment)
}

// --- Setters (the URL API's), each by the parser with a state override. They answer the new URL; a refused value
// leaves the URL as it was (the caller keeps the old one).

fn cannot_have_credentials_or_port(u: *const Url) -> bool {
    ret !u.has_host || u.host.len == 0usize || str.eq(u.scheme, "file")
}

fn set_protocol(a: *mem.Arena, u: *const Url, value: str) -> Url {
    var p = to_parser(a, u)
    let text = join2(a, value, ":")
    let done = run(a, text, zero, false, &p, true, State.SchemeStart)
    ret from_parser(&p)
}

fn set_username(a: *mem.Arena, u: *const Url, value: str) -> Url {
    if cannot_have_credentials_or_port(u) { ret *u }
    var out = *u
    var buf = zero_buf(a, value.len * 3usize + 8usize)
    var it = utf8.iterator(value)
    while true {
        let (sc, more) = utf8.iterator_next(&it)
        if !more { break }
        put_encoded(&buf, sc, .Userinfo)
    }
    out.username = buf_take(a, &buf)
    ret out
}

fn set_password(a: *mem.Arena, u: *const Url, value: str) -> Url {
    if cannot_have_credentials_or_port(u) { ret *u }
    var out = *u
    var buf = zero_buf(a, value.len * 3usize + 8usize)
    var it = utf8.iterator(value)
    while true {
        let (sc, more) = utf8.iterator_next(&it)
        if !more { break }
        put_encoded(&buf, sc, .Userinfo)
    }
    out.password = buf_take(a, &buf)
    ret out
}

fn set_host(a: *mem.Arena, u: *const Url, value: str) -> Url {
    if u.opaque_path { ret *u }
    var p = to_parser(a, u)
    let done = run(a, value, zero, false, &p, true, State.Host)
    ret from_parser(&p)
}

fn set_hostname(a: *mem.Arena, u: *const Url, value: str) -> Url {
    if u.opaque_path { ret *u }
    var p = to_parser(a, u)
    let done = run(a, value, zero, false, &p, true, State.Hostname)
    ret from_parser(&p)
}

fn set_port(a: *mem.Arena, u: *const Url, value: str) -> Url {
    if cannot_have_credentials_or_port(u) { ret *u }
    var out = *u
    if value.len == 0usize {
        out.port = -1i32
        ret out
    }
    var p = to_parser(a, u)
    let done = run(a, value, zero, false, &p, true, State.Port)
    ret from_parser(&p)
}

fn set_pathname(a: *mem.Arena, u: *const Url, value: str) -> Url {
    if u.opaque_path { ret *u }
    var p = to_parser(a, u)
    p.segs.len = 0usize
    let done = run(a, value, zero, false, &p, true, State.PathStart)
    ret from_parser(&p)
}

fn strip_trailing_spaces(u: *Url) {
    if !u.opaque_path || u.has_fragment || u.has_query { ret }
    while u.path.len > 0usize && u.path[u.path.len - 1usize] == 32u8 { u.path = u.path[0usize..u.path.len - 1usize] }
}

fn set_search(a: *mem.Arena, u: *const Url, value: str) -> Url {
    var out = *u
    if value.len == 0usize {
        out.query = ""
        out.has_query = false
        strip_trailing_spaces(&out)
        ret out
    }
    var text = value
    if value[0usize] == 63u8 { text = value[1usize..] }
    var p = to_parser(a, u)
    p.query = ""
    p.has_query = true
    let done = run(a, text, zero, false, &p, true, State.Query)
    ret from_parser(&p)
}

fn set_hash(a: *mem.Arena, u: *const Url, value: str) -> Url {
    var out = *u
    if value.len == 0usize {
        out.fragment = ""
        out.has_fragment = false
        strip_trailing_spaces(&out)
        ret out
    }
    var text = value
    if value[0usize] == 35u8 { text = value[1usize..] }
    var p = to_parser(a, u)
    p.fragment = ""
    p.has_fragment = true
    let done = run(a, text, zero, false, &p, true, State.Fragment)
    ret from_parser(&p)
}
