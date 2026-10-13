// AWS Signature Version 4 request signing (L048: what the Petcow drivers' SDK calls do before they send), after
// botocore's `SigV4Auth` and `S3SigV4Auth` (the algorithm the AWS SDKs share): the canonical request (the method, the
// path as `quote(normalized, safe='/~')` or as it is for S3, the sorted query, the lower-cased and trimmed headers, the
// signed header names and the payload hash), the string to sign over the credential scope, and the signature from the
// date/region/service/`aws4_request` HMAC chain. `sign_request` does what `add_auth` does to a request: it takes
// the `Authorization`, sets `X-Amz-Date` (or re-writes `Date`), `X-Amz-Security-Token`, and for S3 or an unsigned
// payload `X-Amz-Content-SHA256`, and appends the new `Authorization`.
//
// A request is JSON: `{method, url, headers: [[name, value], ...], params: [[key, value], ...] | null, body: text,
// region, service, access_key, secret_key, token, timestamp: "YYYYMMDDTHHMMSSZ", s3: bool, payload_signing: bool | null,
// streaming_input: bool}`; `params`, when present, replaces the query of the URL in the canonical request (as
// `AWSRequest.params` does). The clock is the caller's (`timestamp`), nothing is read from the system.
//
// Limits (botocore's own are the oracle): a header value is trimmed on ASCII and Unicode white space as Python's
// `str.split()` has it; a URL is read the way `urlsplit` reads a valid one (an invalid port or a malformed bracket is not
// diagnosed); the S3 configuration object of a client (`payload_signing_enabled` there) is the plain `payload_signing`.
//
// Memory: the arena is retained.

use e.algo.ir as ir
use e.algo.sync as sync
use e.bytes
use e.crypto.hash as hash
use e.crypto.mac as mac
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.str
use e.text.utf8 as utf8

fn empty_hash() -> str { ret "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" }

fn unsigned_payload() -> str { ret "UNSIGNED-PAYLOAD" }

type Header = struct { name: str, value: str }

fn concat_all(a: *mem.Arena, parts: []const str, sep: str) -> str {
    var total = 0usize
    var i = 0usize
    while i < parts.len {
        total = total + parts[i].len
        if i > 0usize { total = total + sep.len }
        i += 1usize
    }
    let (b, be) = str.builder(a, total + 1usize)
    if be != ok { ret "" }
    var builder = b
    i = 0usize
    while i < parts.len {
        if i > 0usize { let e0 = str.push(&builder, sep) }
        let e1 = str.push(&builder, parts[i])
        i += 1usize
    }
    ret str.done(&builder)
}

fn cat2(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { ret "" }
    ret out
}

// --- text helpers ----------------------------------------------------------------------------------------------------

fn lower_ascii_text(a: *mem.Arena, s: str) -> str {
    let (buf, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        buf[i] = c
        i += 1usize
    }
    let out: str = buf[0usize..s.len]
    ret out
}

fn eq_fold(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        var p = x[i]
        var q = y[i]
        if p >= 65u8 && p <= 90u8 { p = p + 32u8 }
        if q >= 65u8 && q <= 90u8 { q = q + 32u8 }
        if p != q { ret false }
        i += 1usize
    }
    ret true
}

fn hex_text(a: *mem.Arena, b: []const u8) -> str {
    let (buf, e) = mem.alloc[u8](a, b.len * 2usize + 1usize)
    if e != ok { ret "" }
    let (out, he) = bytes.hex_encode(buf, b, false)
    ret out
}

fn sha256_hex(a: *mem.Arena, data: []const u8) -> str {
    let digest = hash.sha256(data)
    ret hex_text(a, digest[0..])
}

// `urllib.parse.quote(s, safe=safe)`: letters, digits, `_.-~` and the safe bytes stay, every other byte of the UTF-8 text
// is `%XX` in upper case.
fn quote(a: *mem.Arena, s: str, safe: str) -> str {
    let (buf, e) = mem.alloc[u8](a, s.len * 3usize + 1usize)
    if e != ok { ret s }
    let digits = "0123456789ABCDEF"
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        var keep = (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 || c == 46u8 || c == 45u8 || c == 126u8
        var k = 0usize
        while !keep && k < safe.len {
            if safe[k] == c { keep = true }
            k += 1usize
        }
        if keep {
            buf[n] = c
            n += 1usize
        } else {
            buf[n] = 37u8
            buf[n + 1usize] = digits[usize(c >> 4u8)]
            buf[n + 2usize] = digits[usize(c & 15u8)]
            n += 3usize
        }
        i += 1usize
    }
    let out: str = buf[0usize..n]
    ret out
}

// botocore's `remove_dot_segments`: RFC 3986 5.2.4 plus the removal of empty segments.
fn remove_dot_segments(a: *mem.Arena, url: str) -> str {
    if url.len == 0usize { ret "" }
    let (segs, e) = mem.alloc[str](a, url.len + 2usize)
    if e != ok { ret url }
    var count = 0usize
    var start = 0usize
    var i = 0usize
    while i <= url.len {
        if i == url.len || url[i] == 47u8 {
            let piece = url[start..i]
            if piece.len > 0usize && !str.eq(piece, ".") {
                if str.eq(piece, "..") {
                    if count > 0usize { count -= 1usize }
                } else {
                    segs[count] = piece
                    count += 1usize
                }
            }
            start = i + 1usize
        }
        i += 1usize
    }
    var first = ""
    if url[0usize] == 47u8 { first = "/" }
    var last = ""
    if url[url.len - 1usize] == 47u8 && count > 0usize { last = "/" }
    let joined = concat_all(a, segs[0usize..count], "/")
    ret cat2(a, cat2(a, first, joined), last)
}

fn normalize_url_path(a: *mem.Arena, path: str) -> str {
    if path.len == 0usize { ret "/" }
    ret remove_dot_segments(a, path)
}

// Python's `str.split()` whitespace.
fn py_space(u: u32) -> bool {
    if u >= 9u32 && u <= 13u32 { ret true }
    if u >= 28u32 && u <= 32u32 { ret true }
    if u == 133u32 || u == 160u32 || u == 5760u32 { ret true }
    if u >= 8192u32 && u <= 8202u32 { ret true }
    ret u == 8232u32 || u == 8233u32 || u == 8239u32 || u == 8287u32 || u == 12288u32
}

// `' '.join(value.split())`.
fn trimall(a: *mem.Arena, s: str) -> str {
    let (buf, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var n = 0usize
    var pending = false
    var it = utf8.iterator(s)
    var more = true
    var from = 0usize
    while more {
        let (u, got) = utf8.iterator_next(&it)
        if !got {
            more = false
        } else {
            var width = 1usize
            if u >= 128u32 { width = 2usize }
            if u >= 2048u32 { width = 3usize }
            if u >= 65536u32 { width = 4usize }
            if py_space(u) {
                if n > 0usize { pending = true }
            } else {
                if pending {
                    buf[n] = 32u8
                    n += 1usize
                    pending = false
                }
                var k = 0usize
                while k < width {
                    buf[n] = s[from + k]
                    n += 1usize
                    k += 1usize
                }
            }
            from = from + width
        }
    }
    let out: str = buf[0usize..n]
    ret out
}

// --- the URL -----------------------------------------------------------------------------------------------------------

type Url = struct { scheme: str, host: str, port: i64, path: str, query: str, ipv6: bool }

fn url_parts(a: *mem.Arena, url: str) -> Url {
    var u = Url { scheme: "", host: "", port: -1i64, path: "", query: "", ipv6: false }
    var rest = url
    // scheme
    var i = 0usize
    while i < rest.len && ((rest[i] >= 97u8 && rest[i] <= 122u8) || (rest[i] >= 65u8 && rest[i] <= 90u8) || (i > 0usize && ((rest[i] >= 48u8 && rest[i] <= 57u8) || rest[i] == 43u8 || rest[i] == 45u8 || rest[i] == 46u8))) { i += 1usize }
    if i > 0usize && i < rest.len && rest[i] == 58u8 {
        u.scheme = lower_ascii_text(a, rest[0usize..i])
        rest = rest[i + 1usize..rest.len]
    }
    // fragment
    var h = 0usize
    while h < rest.len && rest[h] != 35u8 { h += 1usize }
    rest = rest[0usize..h]
    var netloc = ""
    if rest.len >= 2usize && rest[0usize] == 47u8 && rest[1usize] == 47u8 {
        var j = 2usize
        while j < rest.len && rest[j] != 47u8 && rest[j] != 63u8 { j += 1usize }
        netloc = rest[2usize..j]
        rest = rest[j..rest.len]
    }
    var q = 0usize
    while q < rest.len && rest[q] != 63u8 { q += 1usize }
    u.path = rest[0usize..q]
    if q < rest.len { u.query = rest[q + 1usize..rest.len] }
    // userinfo, then host and port
    var at = netloc.len
    var k = netloc.len
    while k > 0usize {
        k -= 1usize
        if netloc[k] == 64u8 {
            at = k
            k = 0usize
        }
    }
    var hostport = netloc
    if at < netloc.len { hostport = netloc[at + 1usize..netloc.len] }
    var host = hostport
    var port_text = ""
    if hostport.len > 0usize && hostport[0usize] == 91u8 {
        var close = 0usize
        while close < hostport.len && hostport[close] != 93u8 { close += 1usize }
        if close < hostport.len {
            host = hostport[1usize..close]
            u.ipv6 = true
            if close + 1usize < hostport.len && hostport[close + 1usize] == 58u8 { port_text = hostport[close + 2usize..hostport.len] }
        }
    } else {
        var c = hostport.len
        var m = hostport.len
        while m > 0usize {
            m -= 1usize
            if hostport[m] == 58u8 {
                c = m
                m = 0usize
            }
        }
        if c < hostport.len {
            host = hostport[0usize..c]
            port_text = hostport[c + 1usize..hostport.len]
        }
    }
    u.host = lower_ascii_text(a, host)
    if port_text.len > 0usize {
        var v = 0i64
        var d = 0usize
        while d < port_text.len {
            if port_text[d] >= 48u8 && port_text[d] <= 57u8 { v = v * 10i64 + i64(port_text[d] - 48u8) }
            d += 1usize
        }
        u.port = v
    }
    ret u
}

// `_host_from_url`.
fn host_from_url(a: *mem.Arena, url: str) -> str {
    let u = url_parts(a, url)
    var host = u.host
    if u.ipv6 { host = cat2(a, cat2(a, "[", host), "]") }
    var default_port = -1i64
    if str.eq(u.scheme, "http") { default_port = 80i64 }
    if str.eq(u.scheme, "https") { default_port = 443i64 }
    if u.port >= 0i64 && u.port != default_port {
        let (t, e) = str.builder(a, 24usize)
        if e != ok { ret host }
        var b = t
        let e1 = str.push_i64(&b, u.port)
        host = cat2(a, cat2(a, host, ":"), str.done(&b))
    }
    ret host
}

// --- the signature -----------------------------------------------------------------------------------------------------

type Pair = struct { key: str, value: str }

fn pair_less(x: Pair, y: Pair) -> bool {
    let c = str.compare(x.key, y.key)
    if c != 0i32 { ret c < 0i32 }
    ret str.compare(x.value, y.value) < 0i32
}

fn sort_pairs(p: []Pair) {
    var i = 1usize
    while i < p.len {
        let v = p[i]
        var j = i
        while j > 0usize && pair_less(v, p[j - 1usize]) {
            p[j] = p[j - 1usize]
            j -= 1usize
        }
        p[j] = v
        i += 1usize
    }
}

fn pairs_text(a: *mem.Arena, p: []const Pair) -> str {
    let (parts, e) = mem.alloc[str](a, p.len + 1usize)
    if e != ok { ret "" }
    var i = 0usize
    while i < p.len {
        parts[i] = cat2(a, cat2(a, p[i].key, "="), p[i].value)
        i += 1usize
    }
    ret concat_all(a, parts[0usize..p.len], "&")
}

// The canonical query string: from `params` (every key and value quoted) or, for a request with none, the URL's own query
// split on `&` and `=` and sorted as written.
fn canonical_query(a: *mem.Arena, params: []const Pair, have_params: bool, url_query: str) -> str {
    if have_params && params.len > 0usize {
        let (p, e) = mem.alloc[Pair](a, params.len + 1usize)
        if e != ok { ret "" }
        var i = 0usize
        while i < params.len {
            p[i] = Pair { key: quote(a, params[i].key, "-_.~"), value: quote(a, params[i].value, "-_.~") }
            i += 1usize
        }
        sort_pairs(p[0usize..params.len])
        ret pairs_text(a, p[0usize..params.len])
    }
    if url_query.len == 0usize { ret "" }
    var count = 1usize
    var i = 0usize
    while i < url_query.len {
        if url_query[i] == 38u8 { count += 1usize }
        i += 1usize
    }
    let (p, e) = mem.alloc[Pair](a, count + 1usize)
    if e != ok { ret "" }
    var n = 0usize
    var start = 0usize
    i = 0usize
    while i <= url_query.len {
        if i == url_query.len || url_query[i] == 38u8 {
            let item = url_query[start..i]
            var eq = item.len
            var k = 0usize
            while k < item.len {
                if item[k] == 61u8 && eq == item.len { eq = k }
                k += 1usize
            }
            if eq < item.len {
                p[n] = Pair { key: item[0usize..eq], value: item[eq + 1usize..item.len] }
            } else {
                p[n] = Pair { key: item, value: "" }
            }
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    sort_pairs(p[0usize..n])
    ret pairs_text(a, p[0usize..n])
}

fn blacklisted(lname: str) -> bool {
    ret str.eq(lname, "connection") || str.eq(lname, "expect") || str.eq(lname, "keep-alive") || str.eq(lname, "proxy-authenticate") || str.eq(lname, "proxy-authorization") || str.eq(lname, "te") || str.eq(lname, "trailer") || str.eq(lname, "transfer-encoding") || str.eq(lname, "upgrade") || str.eq(lname, "user-agent") || str.eq(lname, "x-amzn-trace-id")
}

type Signed = struct { canonical_request: str, string_to_sign: str, signature: str, authorization: str, headers: []const Header }

fn find_header(h: []const Header, name: str) -> (str, bool) {
    var i = 0usize
    while i < h.len {
        if eq_fold(h[i].name, name) { ret (h[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

fn push_header(l: *list.List[Header], name: str, value: str) {
    let e = list.push[Header](l, Header { name: name, value: value })
}

// `SigV4Auth.canonical_request` and `signed_headers` over `headers` (with `host` supplied from the URL when absent).
fn headers_to_sign(a: *mem.Arena, headers: []const Header, url: str) -> ([]const Pair, str) {
    let (lows, e) = mem.alloc[Pair](a, headers.len + 2usize)
    if e != ok { ret (zero, "") }
    var n = 0usize
    var have_host = false
    var i = 0usize
    while i < headers.len {
        let ln = lower_ascii_text(a, headers[i].name)
        if !blacklisted(ln) {
            lows[n] = Pair { key: ln, value: headers[i].value }
            n += 1usize
            if str.eq(ln, "host") { have_host = true }
        }
        i += 1usize
    }
    if !have_host {
        lows[n] = Pair { key: "host", value: host_from_url(a, url) }
        n += 1usize
    }
    // names in sorted order, once each; the values of a name joined with ',' in the order they were given
    let (sorted_names, se) = mem.alloc[Pair](a, n + 1usize)
    if se != ok { ret (zero, "") }
    var s = 0usize
    i = 0usize
    while i < n {
        var seen = false
        var k = 0usize
        while k < s {
            if str.eq(sorted_names[k].key, lows[i].key) { seen = true }
            k += 1usize
        }
        if !seen {
            sorted_names[s] = Pair { key: lows[i].key, value: "" }
            s += 1usize
        }
        i += 1usize
    }
    sort_pairs(sorted_names[0usize..s])
    var signed_names: [64]str = zero
    i = 0usize
    while i < s {
        var vals: [32]str = zero
        var vn = 0usize
        var k = 0usize
        while k < n {
            if str.eq(lows[k].key, sorted_names[i].key) && vn < 32usize {
                vals[vn] = trimall(a, lows[k].value)
                vn += 1usize
            }
            k += 1usize
        }
        sorted_names[i].value = concat_all(a, vals[0usize..vn], ",")
        if i < 64usize { signed_names[i] = sorted_names[i].key }
        i += 1usize
    }
    var count = s
    if count > 64usize { count = 64usize }
    ret (sorted_names[0usize..s], concat_all(a, signed_names[0usize..count], ";"))
}

fn canonical_headers_text(a: *mem.Arena, p: []const Pair) -> str {
    let (parts, e) = mem.alloc[str](a, p.len + 1usize)
    if e != ok { ret "" }
    var i = 0usize
    while i < p.len {
        parts[i] = cat2(a, cat2(a, p[i].key, ":"), p[i].value)
        i += 1usize
    }
    ret concat_all(a, parts[0usize..p.len], "\n")
}

fn hmac(a: *mem.Arena, key: []const u8, message: str) -> [32]u8 {
    ret mac.hmac_sha256(key, message)
}

// The signature of a string to sign under a secret, the date (`YYYYMMDD`), region and service.
fn signature(a: *mem.Arena, secret: str, date: str, region: str, service: str, to_sign: str) -> str {
    let seed = cat2(a, "AWS4", secret)
    let k_date = hmac(a, seed, date)
    let k_region = hmac(a, k_date[0..], region)
    let k_service = hmac(a, k_region[0..], service)
    let k_signing = hmac(a, k_service[0..], "aws4_request")
    let sig = hmac(a, k_signing[0..], to_sign)
    ret hex_text(a, sig[0..])
}

// 'Mon, 01 Jan 2024 00:00:00 -0000': `email.utils.formatdate(seconds)` (the zone is `-0000` for a time that is not local).
fn http_date(a: *mem.Arena, timestamp: str) -> str {
    if timestamp.len != 16usize { ret "" }
    var v: [14]i64 = zero
    var k = 0usize
    let idx = [6]usize{ 0usize, 4usize, 6usize, 9usize, 11usize, 13usize }
    var f = 0usize
    var year = 0i64
    var month = 0i64
    var day = 0i64
    var hour = 0i64
    var minute = 0i64
    var second = 0i64
    while f < 6usize {
        let width = [6]usize{ 4usize, 2usize, 2usize, 2usize, 2usize, 2usize }
        var x = 0i64
        var d = 0usize
        while d < width[f] {
            x = x * 10i64 + i64(timestamp[idx[f] + d] - 48u8)
            d += 1usize
        }
        if f == 0usize { year = x }
        if f == 1usize { month = x }
        if f == 2usize { day = x }
        if f == 3usize { hour = x }
        if f == 4usize { minute = x }
        if f == 5usize { second = x }
        f += 1usize
    }
    // weekday: days from 1970-01-01 (a Thursday)
    var y = year
    if month <= 2i64 { y = y - 1i64 }
    var era = y / 400i64
    if y < 0i64 { era = (y - 399i64) / 400i64 }
    let yoe = y - era * 400i64
    var mp = month + 9i64
    if month > 2i64 { mp = month - 3i64 }
    let doy = (153i64 * mp + 2i64) / 5i64 + day - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    let days = era * 146097i64 + doe - 719468i64
    var wd = (days + 4i64) % 7i64
    if wd < 0i64 { wd = wd + 7i64 }
    let names = [7]str{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
    let months = [12]str{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
    let (b, be) = str.builder(a, 48usize)
    if be != ok { ret "" }
    var out = b
    let e0 = str.push(&out, names[usize(wd)])
    let e1 = str.push(&out, ", ")
    if day < 10i64 { let e2 = str.push(&out, "0") }
    let e3 = str.push_i64(&out, day)
    let e4 = str.push(&out, " ")
    let e5 = str.push(&out, months[usize(month - 1i64)])
    let e6 = str.push(&out, " ")
    let e7 = str.push_i64(&out, year)
    let e8 = str.push(&out, " ")
    if hour < 10i64 { let e9 = str.push(&out, "0") }
    let e10 = str.push_i64(&out, hour)
    let e11 = str.push(&out, ":")
    if minute < 10i64 { let e12 = str.push(&out, "0") }
    let e13 = str.push_i64(&out, minute)
    let e14 = str.push(&out, ":")
    if second < 10i64 { let e15 = str.push(&out, "0") }
    let e16 = str.push_i64(&out, second)
    let e17 = str.push(&out, " -0000")
    ret str.done(&out)
}

type Request = struct {
    method: str,
    url: str,
    headers: []const Header,
    params: []const Pair,
    have_params: bool,
    body: str,
    region: str,
    service: str,
    access_key: str,
    secret_key: str,
    token: str,
    timestamp: str,
    s3: bool,
    payload_signing: bool,
    streaming_input: bool
}

// `SigV4Auth.add_auth` / `S3SigV4Auth.add_auth`: the headers the request ends with and the intermediate texts.
fn sign_request(a: *mem.Arena, r: Request) -> Signed {
    // _modify_request_before_signing
    let (hs0, hse) = list.init[Header](a, r.headers.len + 8usize)
    var hs = hs0
    var i = 0usize
    var has_date = false
    while i < r.headers.len {
        if eq_fold(r.headers[i].name, "date") { has_date = true }
        i += 1usize
    }
    var dropped_date = false
    i = 0usize
    while i < r.headers.len {
        let n = r.headers[i].name
        var drop = eq_fold(n, "authorization")
        if has_date && (eq_fold(n, "date") || eq_fold(n, "x-amz-date")) { drop = true }
        if !has_date && eq_fold(n, "x-amz-date") { drop = true }
        if r.token.len > 0usize && eq_fold(n, "x-amz-security-token") { drop = true }
        if (!r.payload_signing || r.s3) && eq_fold(n, "x-amz-content-sha256") { drop = true }
        if !drop { push_header(&hs, n, r.headers[i].value) }
        i += 1usize
    }
    if has_date {
        push_header(&hs, "Date", http_date(a, r.timestamp))
    } else {
        push_header(&hs, "X-Amz-Date", r.timestamp)
    }
    if r.token.len > 0usize { push_header(&hs, "X-Amz-Security-Token", r.token) }
    // the payload hash
    var https = r.url.len >= 5usize && r.url[0usize] == 104u8 && r.url[1usize] == 116u8 && r.url[2usize] == 116u8 && r.url[3usize] == 112u8 && r.url[4usize] == 115u8
    var sign_payload = true
    if https { sign_payload = r.payload_signing }
    if r.s3 {
        // S3SigV4Auth: a checksum header on https and a streaming input turn body signing off
        let (md5, have_md5) = find_header(list.slice_const[Header](&hs), "Content-MD5")
        if https && have_md5 && r.streaming_input { sign_payload = false }
        if !https || !have_md5 { sign_payload = true }
        if https && have_md5 && !r.streaming_input { sign_payload = r.payload_signing }
    }
    var payload = unsigned_payload()
    if sign_payload {
        if r.body.len == 0usize { payload = empty_hash() } else { payload = sha256_hex(a, r.body) }
    }
    if !r.payload_signing && !r.s3 {
        push_header(&hs, "X-Amz-Content-SHA256", unsigned_payload())
    }
    if r.s3 { push_header(&hs, "X-Amz-Content-SHA256", payload) }
    let current = list.slice_const[Header](&hs)
    let (sha_header, have_sha) = find_header(current, "X-Amz-Content-SHA256")
    var body_checksum = payload
    if have_sha { body_checksum = sha_header }
    // canonical request
    let parts = url_parts(a, r.url)
    var path = parts.path
    if !r.s3 { path = quote(a, normalize_url_path(a, parts.path), "/~") }
    let query = canonical_query(a, r.params, r.have_params, parts.query)
    let (sorted, signed_names) = headers_to_sign(a, current, r.url)
    var upper = r.method
    let (ubuf, ue) = mem.alloc[u8](a, r.method.len + 1usize)
    if ue == ok {
        var k = 0usize
        while k < r.method.len {
            var c = r.method[k]
            if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
            ubuf[k] = c
            k += 1usize
        }
        let up: str = ubuf[0usize..r.method.len]
        upper = up
    }
    var cr: [6]str = zero
    cr[0usize] = upper
    cr[1usize] = path
    cr[2usize] = query
    cr[3usize] = cat2(a, canonical_headers_text(a, sorted), "\n")
    cr[4usize] = signed_names
    cr[5usize] = body_checksum
    let canonical = concat_all(a, cr[0usize..6usize], "\n")
    // string to sign and signature
    let date = r.timestamp[0usize..8usize]
    var scope_parts: [4]str = zero
    scope_parts[0usize] = date
    scope_parts[1usize] = r.region
    scope_parts[2usize] = r.service
    scope_parts[3usize] = "aws4_request"
    let scope = concat_all(a, scope_parts[0usize..4usize], "/")
    var sts_parts: [4]str = zero
    sts_parts[0usize] = "AWS4-HMAC-SHA256"
    sts_parts[1usize] = r.timestamp
    sts_parts[2usize] = scope
    sts_parts[3usize] = sha256_hex(a, canonical)
    let to_sign = concat_all(a, sts_parts[0usize..4usize], "\n")
    let sig = signature(a, r.secret_key, date, r.region, r.service, to_sign)
    let credential = cat2(a, cat2(a, r.access_key, "/"), scope)
    var auth_parts: [3]str = zero
    auth_parts[0usize] = cat2(a, "AWS4-HMAC-SHA256 Credential=", credential)
    auth_parts[1usize] = cat2(a, "SignedHeaders=", signed_names)
    auth_parts[2usize] = cat2(a, "Signature=", sig)
    let auth = concat_all(a, auth_parts[0usize..3usize], ", ")
    push_header(&hs, "Authorization", auth)
    ret Signed { canonical_request: canonical, string_to_sign: to_sign, signature: sig, authorization: auth, headers: list.slice_const[Header](&hs) }
}

// --- the JSON surface --------------------------------------------------------------------------------------------------

fn text_of(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn flag_of(v: json.Value, key: str, default_value: bool) -> bool {
    let (x, found) = ir.get(v, key)
    if !found { ret default_value }
    switch x {
    case .Bool as b:
        ret b
    default:
        ret default_value
    }
}

fn pairs_of(a: *mem.Arena, v: json.Value) -> []const Pair {
    let (xs, is_array) = ir.items_of(v)
    if !is_array { ret zero }
    let (out, e) = mem.alloc[Pair](a, xs.len + 1usize)
    if e != ok { ret zero }
    var n = 0usize
    var i = 0usize
    while i < xs.len {
        let (kv, ok2) = ir.items_of(xs[i])
        if ok2 && kv.len >= 2usize {
            let (k, kt) = ir.string_of(kv[0usize])
            let (val, vt) = ir.string_of(kv[1usize])
            out[n] = Pair { key: k, value: val }
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn headers_of(a: *mem.Arena, v: json.Value) -> []const Header {
    let p = pairs_of(a, v)
    let (out, e) = mem.alloc[Header](a, p.len + 1usize)
    if e != ok { ret zero }
    var i = 0usize
    while i < p.len {
        out[i] = Header { name: p[i].key, value: p[i].value }
        i += 1usize
    }
    ret out[0usize..p.len]
}

// `sign_request` over the JSON request described in the header: answers `{canonical_request, string_to_sign, signature,
// authorization, headers}`.
fn sign_json(a: *mem.Arena, v: json.Value) -> json.Value {
    let (params, have_params) = ir.get(v, "params")
    let (ps_array, ps_is_array) = ir.items_of(params)
    let req = Request {
        method: text_of(v, "method"),
        url: text_of(v, "url"),
        headers: headers_of(a, ir.value_of(v, "headers")),
        params: pairs_of(a, params),
        have_params: have_params && ps_is_array,
        body: text_of(v, "body"),
        region: text_of(v, "region"),
        service: text_of(v, "service"),
        access_key: text_of(v, "access_key"),
        secret_key: text_of(v, "secret_key"),
        token: text_of(v, "token"),
        timestamp: text_of(v, "timestamp"),
        s3: flag_of(v, "s3", false),
        payload_signing: flag_of(v, "payload_signing", true),
        streaming_input: flag_of(v, "streaming_input", false)
    }
    let s = sign_request(a, req)
    var o = sync.obj(a)
    sync.put(&o, "canonical_request", sync.text(s.canonical_request))
    sync.put(&o, "string_to_sign", sync.text(s.string_to_sign))
    sync.put(&o, "signature", sync.text(s.signature))
    sync.put(&o, "authorization", sync.text(s.authorization))
    var l = sync.empty_list(a)
    var i = 0usize
    while i < s.headers.len {
        var pair = sync.empty_list(a)
        sync.push_value(&pair, sync.text(s.headers[i].name))
        sync.push_value(&pair, sync.text(s.headers[i].value))
        sync.push_value(&l, json.Value{ Array: list.slice_const[json.Value](&pair) })
        i += 1usize
    }
    sync.put(&o, "headers", json.Value{ Array: list.slice_const[json.Value](&l) })
    ret ir.obj_value(&o)
}
