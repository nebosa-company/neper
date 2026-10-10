// The outbound-URL guard (L046), after Appdor's `src/io/ssrf-guard.js`: a user-supplied URL is judged before it is fetched.
// `is_blocked_address` and `block_reason` classify an IP literal (the private, loopback, link-local, carrier-grade-NAT,
// multicast and reserved IPv4 ranges, IPv6 loopback, unique-local and link-local, and the `::ffff:` mapped forms in both
// their dotted and hex spellings); `check_url_sync` is the verdict that needs no resolver (scheme, literal addresses with
// the WHATWG host normalisation -- `2130706433` and `0x7f.1` are loopback -- dotless container names, the cloud metadata
// endpoint, `localhost`); `check_url` adds the resolved addresses, every one of which must be public, and returns exactly
// the answers it approved so a connection can be pinned to them. Messages are the reference's.
//
// ponytail: only ASCII hostnames are normalised (no IDNA); percent-encoded hosts are decoded; a URL whose path, query or
// fragment is unusual is not re-serialised (the verdict carries the hostname, not an `href`).
//
// Memory: the arena is retained.

use e.algo.formula as f
use e.mem
use e.str

type Verdict = struct { valid: bool, message: str, host: str, addresses: []const str, resolved: bool }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn lower(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

fn is_ws(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 11u8 || c == 12u8 || c == 13u8 }

fn trimmed(s: str) -> str {
    var from = 0usize
    var to = s.len
    while from < to && is_ws(s[from]) { from += 1usize }
    while to > from && is_ws(s[to - 1usize]) { to -= 1usize }
    ret s[from..to]
}

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn hex_val(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c) - 48i32 }
    if c >= 97u8 && c <= 102u8 { ret i32(c) - 87i32 }
    if c >= 65u8 && c <= 70u8 { ret i32(c) - 55i32 }
    ret -1i32
}

fn contains_colon(s: str) -> bool { ret str.contains(s, ":") }

fn strip_brackets(s: str) -> str {
    var out = s
    if out.len > 0usize && out[0] == 91u8 { out = out[1usize..] }
    if out.len > 0usize && out[out.len - 1usize] == 93u8 { out = out[0usize..out.len - 1usize] }
    ret out
}

// `a.b.c.d` with each part 1-3 decimal digits at most 255, as a 32-bit number; false otherwise.
fn ipv4_to_int(s: str) -> (u64, bool) {
    var out = 0u64
    var parts = 0usize
    var start = 0usize
    var i = 0usize
    while i <= s.len {
        if i == s.len || s[i] == 46u8 {
            let part = s[start..i]
            if part.len == 0usize || part.len > 3usize { ret (0u64, false) }
            var n = 0u64
            var k = 0usize
            while k < part.len {
                if !is_digit(part[k]) { ret (0u64, false) }
                n = n * 10u64 + u64(part[k] - 48u8)
                k += 1usize
            }
            if n > 255u64 { ret (0u64, false) }
            out = out * 256u64 + n
            parts += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    if parts != 4usize { ret (0u64, false) }
    ret (out, true)
}

fn blocked_v4(addr: u64) -> (str, bool) {
    // base, prefix bits, reason
    if (addr >> 24u64) == 0u64 { ret ("this network", true) }
    if (addr >> 24u64) == 10u64 { ret ("private", true) }
    if (addr >> 22u64) == (100u64 << 2u64) + 1u64 { ret ("carrier-grade NAT", true) }
    if (addr >> 24u64) == 127u64 { ret ("loopback", true) }
    if (addr >> 16u64) == 43518u64 { ret ("link-local — cloud metadata lives here", true) }
    if (addr >> 20u64) == (172u64 << 4u64) + 1u64 { ret ("private — the compose network", true) }
    if (addr >> 8u64) == 12582912u64 { ret ("IETF protocol assignments", true) }
    if (addr >> 16u64) == 49320u64 { ret ("private", true) }
    if (addr >> 17u64) == 198u64 * 128u64 + 9u64 { ret ("benchmarking", true) }
    if (addr >> 28u64) == 14u64 { ret ("multicast", true) }
    if (addr >> 28u64) == 15u64 { ret ("reserved", true) }
    ret ("", false)
}

// `::ffff:a.b.c.d` or `::ffff:h:l`; the dotted IPv4 it carries, or false.
fn mapped_ipv4(a: *mem.Arena, value: str) -> (str, bool) {
    if !str.starts_with(value, "::ffff:") { ret ("", false) }
    let rest = value[7usize..]
    // dotted: digits and dots with exactly three dots
    var dots = 0usize
    var dotted = rest.len > 0usize
    var i = 0usize
    while i < rest.len {
        if rest[i] == 46u8 {
            dots += 1usize
        } else if !is_digit(rest[i]) {
            dotted = false
        }
        i += 1usize
    }
    if dotted && dots == 3usize {
        // `\d+` parts: every part non-empty
        var ok_parts = true
        var start = 0usize
        var k = 0usize
        while k <= rest.len {
            if k == rest.len || rest[k] == 46u8 {
                if k == start { ok_parts = false }
                start = k + 1usize
            }
            k += 1usize
        }
        if ok_parts { ret (rest, true) }
        ret ("", false)
    }
    // hex: 1-4 hex digits, a colon, 1-4 hex digits
    let colon = index_of(rest, 58u8)
    if colon < 1i64 || colon > 4i64 { ret ("", false) }
    let h = rest[0usize..usize(colon)]
    let l = rest[usize(colon) + 1usize..]
    if l.len < 1usize || l.len > 4usize { ret ("", false) }
    var hi = 0u64
    var lo = 0u64
    var j = 0usize
    while j < h.len {
        let d = hex_val(h[j])
        if d < 0i32 { ret ("", false) }
        hi = hi * 16u64 + u64(d)
        j += 1usize
    }
    j = 0usize
    while j < l.len {
        let d = hex_val(l[j])
        if d < 0i32 { ret ("", false) }
        lo = lo * 16u64 + u64(d)
        j += 1usize
    }
    let n = (hi << 16u64) + lo
    let b0 = f.number_text(a, f64((n >> 24u64) & 255u64))
    let b1 = f.number_text(a, f64((n >> 16u64) & 255u64))
    let b2 = f.number_text(a, f64((n >> 8u64) & 255u64))
    let b3 = f.number_text(a, f64(n & 255u64))
    ret (join(a, join(a, join(a, b0, "."), join(a, b1, ".")), join(a, join(a, b2, "."), b3)), true)
}

fn index_of(s: str, c: u8) -> i64 {
    var i = 0usize
    while i < s.len {
        if s[i] == c { ret i64(i) }
        i += 1usize
    }
    ret -1i64
}

// Whether a literal address must never be the target of a user-supplied fetch.
fn is_blocked_address(a: *mem.Arena, ip: str) -> bool {
    let value = strip_brackets(lower(a, trimmed(ip)))
    if value.len == 0usize { ret true }
    if contains_colon(value) {
        let (v4, has) = mapped_ipv4(a, value)
        if has { ret is_blocked_address(a, v4) }
        if str.eq(value, "::") || str.eq(value, "::1") { ret true }
        let colon = index_of(value, 58u8)
        var head = value
        if colon >= 0i64 { head = value[0usize..usize(colon)] }
        if head.len >= 2usize && head[0] == 102u8 && (head[1] == 99u8 || head[1] == 100u8) { ret true }
        if head.len >= 3usize && head[0] == 102u8 && head[1] == 101u8 && (head[2] == 56u8 || head[2] == 57u8 || head[2] == 97u8 || head[2] == 98u8) { ret true }
        ret false
    }
    let (addr, valid) = ipv4_to_int(value)
    if !valid { ret true }
    let (why, hit) = blocked_v4(addr)
    ret hit
}

// Which rule blocked an address, for an error worth reading.
fn block_reason(a: *mem.Arena, ip: str) -> str {
    let value = strip_brackets(lower(a, trimmed(ip)))
    if contains_colon(value) {
        let (v4, has) = mapped_ipv4(a, value)
        if has { ret block_reason(a, v4) }
        if str.eq(value, "::") || str.eq(value, "::1") { ret "loopback" }
        let colon = index_of(value, 58u8)
        var head = value
        if colon >= 0i64 { head = value[0usize..usize(colon)] }
        if head.len >= 2usize && head[0] == 102u8 && (head[1] == 99u8 || head[1] == 100u8) { ret "a unique-local address" }
        if head.len >= 3usize && head[0] == 102u8 && head[1] == 101u8 && (head[2] == 56u8 || head[2] == 57u8 || head[2] == 97u8 || head[2] == 98u8) { ret "link-local — cloud metadata lives here" }
        ret "not a public address"
    }
    let (addr, valid) = ipv4_to_int(value)
    if valid {
        let (why, hit) = blocked_v4(addr)
        if hit { ret why }
    }
    ret "not a public address"
}

fn hex4(a: *mem.Arena, n: u64) -> str {
    if n == 0u64 { ret "0" }
    var digits: [4]u8 = zero
    var k = 0usize
    var rest = n
    while rest > 0u64 && k < 4usize {
        let d = u8(rest & 15u64)
        if d < 10u8 {
            digits[k] = 48u8 + d
        } else {
            digits[k] = 87u8 + d
        }
        k += 1usize
        rest = rest >> 4u64
    }
    var out = ""
    while k > 0usize {
        k -= 1usize
        out = join(a, out, digits[k..k + 1usize])
    }
    ret out
}

// An IPv6 literal (no brackets) in the WHATWG serialisation, or false when it is not one.
fn parse_ipv6(a: *mem.Arena, s: str) -> (str, bool) {
    var pieces: [8]u64 = zero
    var piece_index = 0usize
    var compress = -1i64
    var p = 0usize
    if s.len == 0usize { ret ("", false) }
    if s[0] == 58u8 {
        if s.len < 2usize || s[1] != 58u8 { ret ("", false) }
        p = 2usize
        piece_index += 1usize
        compress = i64(piece_index)
    }
    while p < s.len {
        if piece_index == 8usize { ret ("", false) }
        if s[p] == 58u8 {
            if compress >= 0i64 { ret ("", false) }
            p += 1usize
            piece_index += 1usize
            compress = i64(piece_index)
            continue
        }
        var value = 0u64
        var length = 0usize
        while length < 4usize && p < s.len && hex_val(s[p]) >= 0i32 {
            value = value * 16u64 + u64(hex_val(s[p]))
            p += 1usize
            length += 1usize
        }
        if p < s.len && s[p] == 46u8 {
            if length == 0usize { ret ("", false) }
            p -= length
            if piece_index > 6usize { ret ("", false) }
            var seen = 0usize
            while p < s.len {
                var v4 = -1i64
                if seen > 0usize {
                    if s[p] == 46u8 && seen < 4usize {
                        p += 1usize
                    } else {
                        ret ("", false)
                    }
                }
                if p >= s.len || !is_digit(s[p]) { ret ("", false) }
                while p < s.len && is_digit(s[p]) {
                    let number = i64(s[p] - 48u8)
                    if v4 < 0i64 {
                        v4 = number
                    } else if v4 == 0i64 {
                        ret ("", false)
                    } else {
                        v4 = v4 * 10i64 + number
                    }
                    if v4 > 255i64 { ret ("", false) }
                    p += 1usize
                }
                pieces[piece_index] = pieces[piece_index] * 256u64 + u64(v4)
                seen += 1usize
                if seen == 2usize || seen == 4usize { piece_index += 1usize }
            }
            if seen != 4usize { ret ("", false) }
            break
        } else if p < s.len && s[p] == 58u8 {
            p += 1usize
            if p >= s.len { ret ("", false) }
        } else if p < s.len {
            ret ("", false)
        }
        pieces[piece_index] = value
        piece_index += 1usize
    }
    if compress >= 0i64 {
        var swaps = piece_index - usize(compress)
        piece_index = 7usize
        while piece_index != 0usize && swaps > 0usize {
            let at = usize(compress) + swaps - 1usize
            let t = pieces[piece_index]
            pieces[piece_index] = pieces[at]
            pieces[at] = t
            piece_index -= 1usize
            swaps -= 1usize
        }
    } else if piece_index != 8usize {
        ret ("", false)
    }
    // serialise: the first longest run (>1) of zero pieces becomes `::`
    var best_start = -1i64
    var best_len = 0usize
    var i = 0usize
    while i < 8usize {
        if pieces[i] == 0u64 {
            var j = i
            while j < 8usize && pieces[j] == 0u64 { j += 1usize }
            if j - i > best_len {
                best_len = j - i
                best_start = i64(i)
            }
            i = j
        } else {
            i += 1usize
        }
    }
    if best_len < 2usize { best_start = -1i64 }
    var out = ""
    var ignore0 = false
    i = 0usize
    while i < 8usize {
        if ignore0 && pieces[i] == 0u64 {
            i += 1usize
            continue
        }
        ignore0 = false
        if best_start == i64(i) {
            if i == 0usize {
                out = join(a, out, "::")
            } else {
                out = join(a, out, ":")
            }
            ignore0 = true
            i += 1usize
            continue
        }
        out = join(a, out, hex4(a, pieces[i]))
        if i != 7usize { out = join(a, out, ":") }
        i += 1usize
    }
    ret (out, true)
}

fn parse_number_part(s: str) -> (u64, bool) {
    if s.len == 0usize { ret (0u64, false) }
    var radix = 10u64
    var i = 0usize
    if s.len >= 2usize && s[0] == 48u8 && (s[1] == 120u8 || s[1] == 88u8) {
        radix = 16u64
        i = 2usize
    } else if s.len >= 2usize && s[0] == 48u8 {
        radix = 8u64
        i = 1usize
    }
    var value = 0u64
    while i < s.len {
        let d = hex_val(s[i])
        if d < 0i32 || u64(d) >= radix { ret (0u64, false) }
        value = value * radix + u64(d)
        if value > 17179869184u64 { value = 17179869184u64 }
        i += 1usize
    }
    ret (value, true)
}

fn ends_in_number(parts: []const str, count: usize) -> bool {
    var n = count
    if n > 0usize && parts[n - 1usize].len == 0usize {
        if n == 1usize { ret false }
        n -= 1usize
    }
    let last = parts[n - 1usize]
    if last.len == 0usize { ret false }
    var all_digits = true
    var i = 0usize
    while i < last.len {
        if !is_digit(last[i]) { all_digits = false }
        i += 1usize
    }
    if all_digits { ret true }
    let (v, ok_v) = parse_number_part(last)
    if ok_v && last.len >= 2usize && last[0] == 48u8 && (last[1] == 120u8 || last[1] == 88u8) { ret true }
    ret false
}

// WHATWG IPv4 parsing of a host that ends in a number: the dotted quad, or false when it is a failure.
fn parse_ipv4_host(a: *mem.Arena, host: str) -> (str, bool) {
    let (parts, e) = mem.alloc[str](a, host.len + 2usize)
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= host.len {
        if i == host.len || host[i] == 46u8 {
            parts[n] = host[start..i]
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    var count = n
    if count > 0usize && parts[count - 1usize].len == 0usize && count > 1usize { count -= 1usize }
    if count > 4usize { ret ("", false) }
    var numbers: [4]u64 = zero
    var k = 0usize
    while k < count {
        let (v, good) = parse_number_part(parts[k])
        if !good { ret ("", false) }
        numbers[k] = v
        k += 1usize
    }
    k = 0usize
    while k + 1usize < count {
        if numbers[k] > 255u64 { ret ("", false) }
        k += 1usize
    }
    var limit = 1u64
    var shift = 0usize
    while shift < 5usize - count {
        limit *= 256u64
        shift += 1usize
    }
    if numbers[count - 1usize] >= limit { ret ("", false) }
    var ipv4 = numbers[count - 1usize]
    var j = 0usize
    while j + 1usize < count {
        var scale = 1u64
        var s2 = 0usize
        while s2 < 3usize - j {
            scale *= 256u64
            s2 += 1usize
        }
        ipv4 += numbers[j] * scale
        j += 1usize
    }
    let b0 = f.number_text(a, f64((ipv4 >> 24u64) & 255u64))
    let b1 = f.number_text(a, f64((ipv4 >> 16u64) & 255u64))
    let b2 = f.number_text(a, f64((ipv4 >> 8u64) & 255u64))
    let b3 = f.number_text(a, f64(ipv4 & 255u64))
    ret (join(a, join(a, b0, "."), join(a, join(a, b1, "."), join(a, join(a, b2, "."), b3))), true)
}

fn percent_decode(a: *mem.Arena, s: str) -> str {
    if !str.contains(s, "%") { ret s }
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] == 37u8 && i + 2usize < s.len + 0usize && hex_val(s[i + 1usize]) >= 0i32 && hex_val(s[i + 2usize]) >= 0i32 {
            out[n] = u8(hex_val(s[i + 1usize]) * 16i32 + hex_val(s[i + 2usize]))
            n += 1usize
            i += 3usize
        } else {
            out[n] = s[i]
            n += 1usize
            i += 1usize
        }
    }
    ret out[0usize..n]
}

fn forbidden_host_char(c: u8) -> bool {
    ret c <= 32u8 || c == 35u8 || c == 47u8 || c == 58u8 || c == 60u8 || c == 62u8 || c == 63u8 || c == 64u8 || c == 91u8 || c == 92u8 || c == 93u8 || c == 94u8 || c == 124u8 || c == 37u8 || c == 127u8
}

type Parsed = struct { valid: bool, scheme: str, host: str, special: bool }

// What `new URL(text)` yields for the scheme and hostname; invalid where it throws.
fn parse_href(a: *mem.Arena, text: str) -> Parsed {
    let bad = Parsed { valid: false, scheme: "", host: "", special: false }
    var s = trimmed(text)
    if s.len == 0usize { ret bad }
    var colon = -1i64
    var i = 0usize
    while i < s.len {
        let c = s[i]
        let alpha = (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8)
        if c == 58u8 {
            colon = i64(i)
            break
        }
        if i == 0usize && !alpha { ret bad }
        if !(alpha || is_digit(c) || c == 43u8 || c == 45u8 || c == 46u8) { ret bad }
        i += 1usize
    }
    if colon < 1i64 { ret bad }
    let scheme = lower(a, s[0usize..usize(colon)])
    let special = str.eq(scheme, "http") || str.eq(scheme, "https") || str.eq(scheme, "ftp") || str.eq(scheme, "ws") || str.eq(scheme, "wss") || str.eq(scheme, "file")
    if !special { ret Parsed { valid: true, scheme: scheme, host: "", special: false } }
    var rest = s[usize(colon) + 1usize..]
    // special schemes take `/` and `\` alike, any number of them, before the authority
    var k = 0usize
    while k < rest.len && (rest[k] == 47u8 || rest[k] == 92u8) { k += 1usize }
    if str.eq(scheme, "file") { ret Parsed { valid: true, scheme: scheme, host: "", special: true } }
    rest = rest[k..]
    var end = 0usize
    while end < rest.len && rest[end] != 47u8 && rest[end] != 92u8 && rest[end] != 63u8 && rest[end] != 35u8 { end += 1usize }
    var authority = rest[0usize..end]
    let at = last_index_of(authority, 64u8)
    if at >= 0i64 { authority = authority[usize(at) + 1usize..] }
    var host = authority
    var in_brackets = false
    if authority.len > 0usize && authority[0] == 91u8 { in_brackets = true }
    let colon_at = last_index_of(authority, 58u8)
    var port_text = ""
    if colon_at >= 0i64 {
        let close = index_of(authority, 93u8)
        if !in_brackets || colon_at > close {
            host = authority[0usize..usize(colon_at)]
            port_text = authority[usize(colon_at) + 1usize..]
        }
    }
    var p = 0usize
    var port_value = 0u64
    while p < port_text.len {
        if !is_digit(port_text[p]) { ret bad }
        port_value = port_value * 10u64 + u64(port_text[p] - 48u8)
        if port_value > 65535u64 { ret bad }
        p += 1usize
    }
    if host.len == 0usize { ret bad }
    if in_brackets {
        if host.len < 2usize || host[host.len - 1usize] != 93u8 { ret bad }
        let (v6, good) = parse_ipv6(a, host[1usize..host.len - 1usize])
        if !good { ret bad }
        ret Parsed { valid: true, scheme: scheme, host: join(a, join(a, "[", v6), "]"), special: true }
    }
    let decoded = lower(a, percent_decode(a, host))
    if decoded.len == 0usize { ret bad }
    var j = 0usize
    while j < decoded.len {
        if forbidden_host_char(decoded[j]) { ret bad }
        if decoded[j] >= 128u8 { ret bad }
        j += 1usize
    }
    // does the last label look like a number?
    let (parts, e) = mem.alloc[str](a, decoded.len + 2usize)
    var n = 0usize
    var start = 0usize
    j = 0usize
    while j <= decoded.len {
        if j == decoded.len || decoded[j] == 46u8 {
            parts[n] = decoded[start..j]
            n += 1usize
            start = j + 1usize
        }
        j += 1usize
    }
    if ends_in_number(parts, n) {
        let (v4, good) = parse_ipv4_host(a, decoded)
        if !good { ret bad }
        ret Parsed { valid: true, scheme: scheme, host: v4, special: true }
    }
    ret Parsed { valid: true, scheme: scheme, host: decoded, special: true }
}

fn last_index_of(s: str, c: u8) -> i64 {
    var i = s.len
    while i > 0usize {
        if s[i - 1usize] == c { ret i64(i - 1usize) }
        i -= 1usize
    }
    ret -1i64
}

fn refused(msg: str) -> Verdict {
    let none: []const str = zero
    ret Verdict { valid: false, message: msg, host: "", addresses: none, resolved: false }
}

fn one(a: *mem.Arena, s: str) -> []const str {
    let (out, e) = mem.alloc[str](a, 1usize)
    out[0] = s
    ret out[0usize..1usize]
}

fn all_digits_dots(s: str) -> bool {
    if s.len == 0usize { ret false }
    var i = 0usize
    while i < s.len {
        if !is_digit(s[i]) && s[i] != 46u8 { ret false }
        i += 1usize
    }
    ret true
}

// Everything the guard decides without a resolver; `resolved` false means a name that needs DNS.
fn check_url_sync(a: *mem.Arena, url: str) -> Verdict {
    let p = parse_href(a, url)
    if !p.valid { ret refused("not a valid URL") }
    if !str.eq(p.scheme, "http") && !str.eq(p.scheme, "https") {
        ret refused(join(a, join(a, "refused: ", p.scheme), ": is not http or https"))
    }
    let host = lower(a, strip_brackets(p.host))
    if all_digits_dots(host) || contains_colon(host) {
        if is_blocked_address(a, host) {
            ret refused(join(a, join(a, "refused: ", host), join(a, " is ", block_reason(a, host))))
        }
        ret Verdict { valid: true, message: "", host: host, addresses: one(a, host), resolved: true }
    }
    if !str.contains(host, ".") {
        ret refused(join(a, join(a, "refused: \"", host), "\" is an internal hostname"))
    }
    if str.eq(host, "metadata.google.internal") || str.ends_with(host, ".metadata.google.internal") {
        ret refused(join(a, join(a, "refused: ", host), " is the cloud metadata endpoint"))
    }
    if str.eq(host, "localhost") || str.ends_with(host, ".localhost") {
        ret refused(join(a, join(a, "refused: ", host), " is loopback"))
    }
    let none: []const str = zero
    ret Verdict { valid: true, message: "", host: host, addresses: none, resolved: false }
}

// The guard with a resolver's answers (`has_lookup` false: no resolver; `lookup_failed`: it threw or answered nothing).
fn check_url(a: *mem.Arena, url: str, has_lookup: bool, lookup_failed: bool, answers: []const str) -> Verdict {
    let v = check_url_sync(a, url)
    if !v.valid || v.resolved { ret v }
    if !has_lookup { ret refused("refused: cannot resolve host to check it") }
    if lookup_failed || answers.len == 0usize { ret refused(join(a, join(a, "refused: ", v.host), " did not resolve")) }
    var i = 0usize
    while i < answers.len {
        if is_blocked_address(a, answers[i]) {
            ret refused(join(a, join(a, "refused: ", v.host), join(a, " resolves to ", join(a, answers[i], join(a, ", which is ", block_reason(a, answers[i]))))))
        }
        i += 1usize
    }
    ret Verdict { valid: true, message: "", host: v.host, addresses: answers, resolved: true }
}
