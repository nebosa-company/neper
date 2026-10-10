// HTTP policy helpers (L046), after Vaper's `net/` pure policy files: RFC 9111 caching (`http_cache.dart`: what may be
// stored, freshness, age, heuristic lifetime, stale-if-error, conditional headers), the RFC 6265bis cookie jar
// (`cookie_jar.dart`: Secure, SameSite, `__Host-`/`__Secure-` prefixes, CHIPS partitions, third-party blocking, caps),
// CORS and cross-origin response policies (`cors.dart`: simple requests, preflight, the response check, the preflight
// cache, CORP, COEP, COOP), Content-Security-Policy source lists (`csp_policy.dart`), the IP-literal private-network
// classifier (`private_network.dart`) and the Adblock Plus filter-list subset (`filter_list_parser.dart`). Pure functions
// and arena-backed values; time is a parameter in milliseconds since the epoch.
//
// `parse_url` reads the shapes Dart's `Uri.tryParse` answers for (scheme, authority with userinfo, host lower-cased, an
// IPv6 literal without its brackets, a port that is dropped when it is the scheme's default, path, query, fragment); a
// port with a non-digit is refused.
//
// ponytail: host and path characters outside the URL grammar are not percent-encoded as Dart does, dot segments are not
// removed, and weekday names in an HTTP date are not checked against the date (the reference does not either).
//
// Memory: the arena is retained.

use e.algo.formula as f
use e.mem
use e.str

// --- numbers, text and dates ---------------------------------------------------------------------------------

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

fn trim(s: str) -> str {
    var from = 0usize
    var to = s.len
    while from < to && is_ws(s[from]) { from += 1usize }
    while to > from && is_ws(s[to - 1usize]) { to -= 1usize }
    ret s[from..to]
}

fn hex_val(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c) - 48i32 }
    if c >= 97u8 && c <= 102u8 { ret i32(c) - 87i32 }
    if c >= 65u8 && c <= 70u8 { ret i32(c) - 55i32 }
    ret -1i32
}

// Dart's `int.tryParse`: optional surrounding whitespace, an optional sign, then decimal digits or `0x` hex digits.
fn int_try_parse(text: str) -> (i64, bool) {
    let s = trim(text)
    if s.len == 0usize { ret (0i64, false) }
    var i = 0usize
    var negative = false
    if s[0] == 45u8 {
        negative = true
        i = 1usize
    } else if s[0] == 43u8 {
        i = 1usize
    }
    if i >= s.len { ret (0i64, false) }
    var value = 0i64
    if i + 2usize < s.len + 0usize && s[i] == 48u8 && (s[i + 1usize] == 120u8 || s[i + 1usize] == 88u8) {
        i += 2usize
        if i >= s.len { ret (0i64, false) }
        while i < s.len {
            let d = hex_val(s[i])
            if d < 0i32 { ret (0i64, false) }
            if value > 576460752303423487i64 { ret (0i64, false) }
            value = value * 16i64 + i64(d)
            i += 1usize
        }
    } else {
        while i < s.len {
            let c = s[i]
            if c < 48u8 || c > 57u8 { ret (0i64, false) }
            let d = i64(c - 48u8)
            if value > 922337203685477579i64 || (value == 922337203685477579i64 && d > 7i64) { ret (0i64, false) }
            value = value * 10i64 + d
            i += 1usize
        }
    }
    if negative { value = 0i64 - value }
    ret (value, true)
}

fn days_from_civil(y_in: i64, m: i64, d: i64) -> i64 {
    var y = y_in
    if m <= 2i64 { y -= 1i64 }
    var era = y / 400i64
    if y < 0i64 { era = (y - 399i64) / 400i64 }
    let yoe = y - era * 400i64
    var mp = m + 9i64
    if m > 2i64 { mp = m - 3i64 }
    let doy = (153i64 * mp + 2i64) / 5i64 + d - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    ret era * 146097i64 + doe - 719468i64
}

// `DateTime.utc(year, month, day, h, m, s)` in milliseconds; an out-of-range field carries into the next, as it does there.
fn utc_ms(year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64) -> i64 {
    var y = year
    var m = month - 1i64
    var carry = m / 12i64
    var rem = m % 12i64
    if rem < 0i64 {
        rem += 12i64
        carry -= 1i64
    }
    y += carry
    m = rem + 1i64
    let days = days_from_civil(y, m, 1i64) + day - 1i64
    ret ((days * 24i64 + hour) * 60i64 + minute) * 60000i64 + second * 1000i64
}

fn text_at_no_case(s: str, at: usize, want: str) -> bool {
    if at + want.len > s.len { ret false }
    var i = 0usize
    while i < want.len {
        var c = s[at + i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        var w = want[i]
        if w >= 65u8 && w <= 90u8 { w += 32u8 }
        if c != w { ret false }
        i += 1usize
    }
    ret true
}

fn weekday_abbr(i: usize) -> str {
    let names = [7]str{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
    ret names[i]
}

fn weekday_full(i: usize) -> str {
    let names = [7]str{ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
    ret names[i]
}

fn month_abbr(i: usize) -> str {
    let names = [12]str{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
    ret names[i]
}

type DateScan = struct { s: str, at: usize, bad: bool }

fn scan_expect(d: *DateScan, c: u8) {
    if d.at < d.s.len && d.s[d.at] == c {
        d.at += 1usize
    } else {
        d.bad = true
    }
}

fn scan_maybe(d: *DateScan, c: u8) -> bool {
    if d.at < d.s.len && d.s[d.at] == c {
        d.at += 1usize
        ret true
    }
    ret false
}

fn scan_month(d: *DateScan) -> i64 {
    var i = 0usize
    while i < 12usize {
        if text_at_no_case(d.s, d.at, month_abbr(i)) {
            d.at += 3usize
            ret i64(i)
        }
        i += 1usize
    }
    d.bad = true
    ret 0i64
}

fn scan_num(d: *DateScan, max_len: usize) -> i64 {
    var value = 0i64
    let start = d.at
    while d.at < d.s.len && d.s[d.at] >= 48u8 && d.s[d.at] <= 57u8 {
        value = value * 10i64 + i64(d.s[d.at] - 48u8)
        d.at += 1usize
    }
    let len = d.at - start
    if len > 0usize && len <= max_len { ret value }
    d.bad = true
    ret 0i64
}

// `HttpDate.parse` of the three formats (RFC 1123, RFC 850, asctime); false for anything else.
fn parse_http_date(s: str) -> (i64, bool) {
    if s.len == 0usize { ret (0i64, false) }
    var d = DateScan { s: s, at: 0usize, bad: false }
    // 0 asctime, 1 rfc1123 (separator ' '), 2 rfc850 (separator '-')
    var format = -1i32
    var i = 0usize
    while i < 7usize && format < 0i32 {
        let abbr = weekday_abbr(i)
        if text_at_no_case(s, 0usize, abbr) {
            let full = weekday_full(i)
            if text_at_no_case(s, 0usize, full) {
                d.at = full.len
                scan_expect(&d, 44u8)
                format = 2i32
            } else {
                d.at = 3usize
                if d.at < s.len && s[d.at] == 44u8 {
                    d.at += 1usize
                    format = 1i32
                } else if d.at < s.len && s[d.at] == 32u8 {
                    d.at += 1usize
                    format = 0i32
                } else {
                    ret (0i64, false)
                }
            }
            break
        }
        i += 1usize
    }
    if format < 0i32 || d.bad { ret (0i64, false) }
    var year = 0i64
    var month = 0i64
    var day = 0i64
    var hours = 0i64
    var minutes = 0i64
    var seconds = 0i64
    if format == 0i32 {
        month = scan_month(&d)
        scan_expect(&d, 32u8)
        if d.bad { ret (0i64, false) }
        if d.at >= s.len { ret (0i64, false) }
        if s[d.at] == 32u8 { d.at += 1usize }
        day = scan_num(&d, 2usize)
        scan_expect(&d, 32u8)
        hours = scan_num(&d, 2usize)
        scan_expect(&d, 58u8)
        minutes = scan_num(&d, 2usize)
        scan_expect(&d, 58u8)
        seconds = scan_num(&d, 2usize)
        scan_expect(&d, 32u8)
        year = scan_num(&d, 4usize)
    } else {
        var sep = 32u8
        if format == 2i32 { sep = 45u8 }
        scan_expect(&d, 32u8)
        day = scan_num(&d, 2usize)
        if !scan_maybe(&d, sep) { d.bad = true }
        month = scan_month(&d)
        if !scan_maybe(&d, sep) { d.bad = true }
        year = scan_num(&d, 4usize)
        scan_expect(&d, 32u8)
        hours = scan_num(&d, 2usize)
        scan_expect(&d, 58u8)
        minutes = scan_num(&d, 2usize)
        scan_expect(&d, 58u8)
        seconds = scan_num(&d, 2usize)
        if text_at_no_case(s, d.at, " GMT") {
            d.at += 4usize
        } else {
            d.bad = true
        }
    }
    if d.bad || d.at != s.len { ret (0i64, false) }
    ret (utc_ms(year, month + 1i64, day, hours, minutes, seconds), true)
}

// --- URLs ------------------------------------------------------------------------------------------------------

type Url = struct { valid: bool, scheme: str, userinfo: str, has_authority: bool, host: str, has_port: bool, port: i64, path: str, has_query: bool, query: str, has_fragment: bool, fragment: str }

fn bad_url() -> Url {
    ret Url { valid: false, scheme: "", userinfo: "", has_authority: false, host: "", has_port: false, port: 0i64, path: "", has_query: false, query: "", has_fragment: false, fragment: "" }
}

// What `Uri.tryParse` gives for an absolute or relative reference; `valid` false where it returns null.
fn parse_url(a: *mem.Arena, source: str) -> Url {
    var u = bad_url()
    u.valid = true
    var at = 0usize
    // scheme
    var k = 0usize
    var scheme_end = 0usize
    var has_scheme = false
    while k < source.len {
        let c = source[k]
        let alpha = (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8)
        let digit = c >= 48u8 && c <= 57u8
        if c == 58u8 {
            has_scheme = k > 0usize
            scheme_end = k
            break
        }
        if k == 0usize && !alpha { break }
        if !(alpha || digit || c == 43u8 || c == 45u8 || c == 46u8) { break }
        k += 1usize
    }
    if has_scheme {
        u.scheme = lower(a, source[0usize..scheme_end])
        at = scheme_end + 1usize
    }
    // fragment and query
    var rest = source[at..]
    let hash = index_of(rest, 35u8)
    if hash >= 0i64 {
        u.has_fragment = true
        u.fragment = rest[usize(hash) + 1usize..]
        rest = rest[0usize..usize(hash)]
    }
    let q = index_of(rest, 63u8)
    if q >= 0i64 {
        u.has_query = true
        u.query = rest[usize(q) + 1usize..]
        rest = rest[0usize..usize(q)]
    }
    if str.starts_with(rest, "//") {
        u.has_authority = true
        var slash = 2usize
        while slash < rest.len && rest[slash] != 47u8 { slash += 1usize }
        var authority = rest[2usize..slash]
        u.path = rest[slash..]
        let amp = last_index_of(authority, 64u8)
        if amp >= 0i64 {
            u.userinfo = authority[0usize..usize(amp)]
            authority = authority[usize(amp) + 1usize..]
        }
        var host = authority
        var port_text = ""
        var has_colon = false
        if authority.len > 0usize && authority[0] == 91u8 {
            let close = index_of(authority, 93u8)
            if close < 0i64 { ret bad_url() }
            host = authority[1usize..usize(close)]
            let after = authority[usize(close) + 1usize..]
            if after.len > 0usize {
                if after[0] != 58u8 { ret bad_url() }
                has_colon = true
                port_text = after[1usize..]
            }
        } else {
            let colon = last_index_of(authority, 58u8)
            if colon >= 0i64 {
                host = authority[0usize..usize(colon)]
                port_text = authority[usize(colon) + 1usize..]
                has_colon = true
            }
        }
        u.host = lower(a, host)
        if has_colon && port_text.len > 0usize {
            var p = 0i64
            var i = 0usize
            while i < port_text.len {
                let c = port_text[i]
                if c < 48u8 || c > 57u8 { ret bad_url() }
                p = p * 10i64 + i64(c - 48u8)
                if p > 65535i64 { ret bad_url() }
                i += 1usize
            }
            u.port = p
            u.has_port = true
        }
        var default_port = 0i64
        if str.eq(u.scheme, "http") { default_port = 80i64 }
        if str.eq(u.scheme, "https") { default_port = 443i64 }
        if u.has_port && u.port == default_port { u.has_port = false }
        if !u.has_port { u.port = default_port }
    } else {
        u.path = rest
    }
    ret u
}

fn index_of(s: str, c: u8) -> i64 {
    var i = 0usize
    while i < s.len {
        if s[i] == c { ret i64(i) }
        i += 1usize
    }
    ret -1i64
}

fn last_index_of(s: str, c: u8) -> i64 {
    var i = s.len
    while i > 0usize {
        if s[i - 1usize] == c { ret i64(i - 1usize) }
        i -= 1usize
    }
    ret -1i64
}

fn port_str(a: *mem.Arena, n: i64) -> str { ret f.number_text(a, f64(n)) }

// `Uri.toString()` for the parts parsed.
fn url_text(a: *mem.Arena, u: Url) -> str {
    var out = ""
    if u.scheme.len > 0usize { out = join(a, u.scheme, ":") }
    if u.has_authority {
        out = join(a, out, "//")
        if u.userinfo.len > 0usize { out = join(a, out, join(a, u.userinfo, "@")) }
        if str.contains(u.host, ":") {
            out = join(a, out, join(a, "[", join(a, u.host, "]")))
        } else {
            out = join(a, out, u.host)
        }
        if u.has_port { out = join(a, out, join(a, ":", port_str(a, u.port))) }
    }
    out = join(a, out, u.path)
    if u.has_query { out = join(a, out, join(a, "?", u.query)) }
    if u.has_fragment { out = join(a, out, join(a, "#", u.fragment)) }
    ret out
}

// `scheme://host[:port]` for an http(s) URL with a host, else false.
fn norm_origin(a: *mem.Arena, source: str) -> (str, bool) {
    let u = parse_url(a, source)
    if !u.valid || u.host.len == 0usize { ret ("", false) }
    if !str.eq(u.scheme, "http") && !str.eq(u.scheme, "https") { ret ("", false) }
    var port = ""
    if u.has_port { port = join(a, ":", port_str(a, u.port)) }
    ret (join(a, join(a, u.scheme, "://"), join(a, u.host, port)), true)
}

// --- headers ---------------------------------------------------------------------------------------------------

// Header names are lower-cased by the caller; a later duplicate wins, as in a map.
type Headers = struct { names: []const str, values: []const str }

fn header_get(h: Headers, key: str) -> (str, bool) {
    var i = h.names.len
    while i > 0usize {
        if str.eq(h.names[i - 1usize], key) { ret (h.values[i - 1usize], true) }
        i -= 1usize
    }
    ret ("", false)
}

type Directives = struct { names: []const str, values: []const str }

fn directive_get(d: Directives, key: str) -> (str, bool) {
    var i = d.names.len
    while i > 0usize {
        if str.eq(d.names[i - 1usize], key) { ret (d.values[i - 1usize], true) }
        i -= 1usize
    }
    ret ("", false)
}

fn has_directive(d: Directives, key: str) -> bool {
    let (v, found) = directive_get(d, key)
    ret found
}

fn strip_quotes(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] != 34u8 {
            out[n] = s[i]
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// A `Cache-Control` value as directive names (lower-cased) and values; a valueless directive has an empty value.
fn parse_cache_control(a: *mem.Arena, value: str, has: bool) -> Directives {
    let none: []const str = zero
    if !has { ret Directives { names: none, values: none } }
    let (names, e1) = mem.alloc[str](a, value.len + 1usize)
    let (values, e2) = mem.alloc[str](a, value.len + 1usize)
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= value.len {
        if i == value.len || value[i] == 44u8 {
            let part = lower(a, trim(value[start..i]))
            start = i + 1usize
            if part.len > 0usize {
                let eq = index_of(part, 61u8)
                if eq < 0i64 {
                    names[n] = part
                    values[n] = ""
                } else {
                    names[n] = part[0usize..usize(eq)]
                    values[n] = trim(strip_quotes(a, part[usize(eq) + 1usize..]))
                }
                n += 1usize
            }
        }
        i += 1usize
    }
    ret Directives { names: names[0usize..n], values: values[0usize..n] }
}

fn cache_control(a: *mem.Arena, h: Headers) -> Directives {
    let (v, has) = header_get(h, "cache-control")
    ret parse_cache_control(a, v, has)
}

// --- HTTP caching (RFC 9111 subset) ----------------------------------------------------------------------------

type Freshness = struct { fresh: bool, must_revalidate: bool }

fn truthy_header(h: Headers, key: str) -> bool {
    let (v, has) = header_get(h, key)
    ret has && v.len > 0usize
}

// Whether a response may be stored in a private cache.
fn http_is_cacheable(a: *mem.Arena, status: i64, h: Headers) -> bool {
    if !(status == 200i64 || status == 203i64 || status == 301i64 || status == 308i64 || status == 410i64) { ret false }
    let cc = cache_control(a, h)
    if has_directive(cc, "no-store") { ret false }
    let (vary_raw, has_vary) = header_get(h, "vary")
    if has_vary {
        let vary = lower(a, vary_raw)
        if str.eq(vary, "*") || str.contains(vary, "cookie") || str.contains(vary, "authorization") { ret false }
    }
    let (expires, has_expires) = header_get(h, "expires")
    let has_freshness = has_directive(cc, "max-age") || has_directive(cc, "s-maxage") || has_expires
    let has_validator = truthy_header(h, "etag") || truthy_header(h, "last-modified")
    ret has_freshness || has_validator
}

fn seconds_between(later_ms: i64, earlier_ms: i64) -> i64 { ret (later_ms - earlier_ms) / 1000i64 }

// The explicit lifetime in seconds from `max-age`, `s-maxage` or `Expires` minus `Date`; false when none is declared.
fn freshness_lifetime(a: *mem.Arena, h: Headers, now_ms: i64) -> (i64, bool) {
    let cc = cache_control(a, h)
    let (ma, has_ma) = directive_get(cc, "max-age")
    if has_ma {
        let (v, ok_v) = int_try_parse(ma)
        if ok_v {
            if v < 0i64 { ret (0i64, true) }
            ret (v, true)
        }
    }
    let (sm, has_sm) = directive_get(cc, "s-maxage")
    if has_sm {
        let (v, ok_v) = int_try_parse(sm)
        if ok_v {
            if v < 0i64 { ret (0i64, true) }
            ret (v, true)
        }
    }
    let (expires, has_expires) = header_get(h, "expires")
    if has_expires {
        let (exp, ok_e) = parse_http_date(expires)
        if ok_e {
            var date = now_ms
            let (date_text, has_date) = header_get(h, "date")
            if has_date {
                let (d, ok_d) = parse_http_date(date_text)
                if ok_d { date = d }
            }
            let secs = seconds_between(exp, date)
            if secs < 0i64 { ret (0i64, true) }
            ret (secs, true)
        }
    }
    ret (0i64, false)
}

// 10% of the interval between `Date` (else now) and `Last-Modified`, at most a day; false without a usable `Last-Modified`.
fn heuristic_lifetime(h: Headers, now_ms: i64) -> (i64, bool) {
    let (lm_text, has_lm) = header_get(h, "last-modified")
    if !has_lm { ret (0i64, false) }
    let (lm, ok_lm) = parse_http_date(lm_text)
    if !ok_lm { ret (0i64, false) }
    var date = now_ms
    let (date_text, has_date) = header_get(h, "date")
    if has_date {
        let (d, ok_d) = parse_http_date(date_text)
        if ok_d { date = d }
    }
    let interval = seconds_between(date, lm)
    if interval <= 0i64 { ret (0i64, true) }
    let heuristic = interval / 10i64
    if heuristic > 86400i64 { ret (86400i64, true) }
    ret (heuristic, true)
}

// Age at store plus the time resident, in seconds.
fn current_age(h: Headers, created_ms: i64, now_ms: i64) -> i64 {
    var age = 0i64
    let (age_text, has_age) = header_get(h, "age")
    if has_age {
        let (v, ok_v) = int_try_parse(age_text)
        if ok_v { age = v }
    }
    var resident = seconds_between(now_ms, created_ms)
    if resident < 0i64 { resident = 0i64 }
    ret age + resident
}

// Whether a stored response is fresh, and whether it must be revalidated before any reuse.
fn http_freshness(a: *mem.Arena, h: Headers, created_ms: i64, now_ms: i64) -> Freshness {
    let cc = cache_control(a, h)
    if has_directive(cc, "no-cache") { ret Freshness { fresh: false, must_revalidate: true } }
    var (lifetime, has_lifetime) = freshness_lifetime(a, h, now_ms)
    if !has_lifetime && !has_directive(cc, "must-revalidate") {
        let (hl, has_hl) = heuristic_lifetime(h, now_ms)
        lifetime = hl
        has_lifetime = has_hl
    }
    if !has_lifetime { ret Freshness { fresh: false, must_revalidate: has_directive(cc, "must-revalidate") } }
    let age = current_age(h, created_ms, now_ms)
    let fresh = age < lifetime
    ret Freshness { fresh: fresh, must_revalidate: !fresh && has_directive(cc, "must-revalidate") }
}

// Whether a stale copy may be served when revalidation fails with a transport error.
fn http_can_serve_stale_on_error(a: *mem.Arena, h: Headers, created_ms: i64, now_ms: i64) -> bool {
    let cc = cache_control(a, h)
    if has_directive(cc, "must-revalidate") { ret false }
    let (sie, has_sie) = directive_get(cc, "stale-if-error")
    if has_sie {
        let (n, ok_n) = int_try_parse(sie)
        if ok_n {
            var (lifetime, has_lifetime) = freshness_lifetime(a, h, now_ms)
            if !has_lifetime {
                let (hl, has_hl) = heuristic_lifetime(h, now_ms)
                lifetime = hl
                has_lifetime = has_hl
            }
            if !has_lifetime { lifetime = 0i64 }
            ret current_age(h, created_ms, now_ms) <= lifetime + n
        }
    }
    ret true
}

type Conditional = struct { has_none_match: bool, if_none_match: str, has_modified_since: bool, if_modified_since: str }

// `ETag` as `If-None-Match` and `Last-Modified` as `If-Modified-Since`.
fn conditional_headers(h: Headers) -> Conditional {
    let (etag, has_etag) = header_get(h, "etag")
    let (lm, has_lm) = header_get(h, "last-modified")
    ret Conditional { has_none_match: has_etag && etag.len > 0usize, if_none_match: etag, has_modified_since: has_lm && lm.len > 0usize, if_modified_since: lm }
}

// --- private network -------------------------------------------------------------------------------------------

fn parse_ipv4(s: str) -> (i64, i64, bool) {
    var octets: [4]i64 = zero
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= s.len {
        if i == s.len || s[i] == 46u8 {
            if n >= 4usize { ret (0i64, 0i64, false) }
            let part = s[start..i]
            if part.len == 0usize || part.len > 3usize { ret (0i64, 0i64, false) }
            let (v, ok_v) = int_try_parse(part)
            if !ok_v || v < 0i64 || v > 255i64 { ret (0i64, 0i64, false) }
            octets[n] = v
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    if n != 4usize { ret (0i64, 0i64, false) }
    ret (octets[0], octets[1], true)
}

// Loopback, private or link-local IP literal, or `localhost`.
fn is_private_network_host(a: *mem.Arena, host: str) -> bool {
    if host.len == 0usize { ret false }
    let h = lower(a, host)
    if str.eq(h, "localhost") || str.ends_with(h, ".localhost") { ret true }
    var bare = h
    if str.starts_with(h, "[") && str.ends_with(h, "]") { bare = h[1usize..h.len - 1usize] }
    let (o0, o1, is_v4) = parse_ipv4(bare)
    if is_v4 {
        if o0 == 0i64 || o0 == 127i64 || o0 == 10i64 { ret true }
        if o0 == 172i64 && o1 >= 16i64 && o1 <= 31i64 { ret true }
        if o0 == 192i64 && o1 == 168i64 { ret true }
        if o0 == 169i64 && o1 == 254i64 { ret true }
        ret false
    }
    if str.eq(bare, "::1") { ret true }
    if str.starts_with(bare, "fc") || str.starts_with(bare, "fd") { ret true }
    if str.starts_with(bare, "fe8") || str.starts_with(bare, "fe9") || str.starts_with(bare, "fea") || str.starts_with(bare, "feb") { ret true }
    ret false
}

// --- filter lists ----------------------------------------------------------------------------------------------

type FilterRules = struct { domains: []const str, selectors: []const str }

fn add_unique(out: []str, n: *usize, v: str) {
    var i = 0usize
    while i < *n {
        if str.eq(out[i], v) { ret }
        i += 1usize
    }
    out[*n] = v
    *n += 1usize
}

// Adblock Plus rules: `||host^` network rules and global `##selector` cosmetic rules; everything else is skipped.
fn parse_filter_list(a: *mem.Arena, text: str) -> FilterRules {
    let (domains, e1) = mem.alloc[str](a, text.len + 1usize)
    let (selectors, e2) = mem.alloc[str](a, text.len + 1usize)
    var nd = 0usize
    var ns = 0usize
    var start = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == 10u8 {
            let line = trim(text[start..i])
            start = i + 1usize
            i += 1usize
            if line.len == 0usize { continue }
            if str.starts_with(line, "!") || str.starts_with(line, "[Adblock") || str.starts_with(line, "@@") { continue }
            if str.starts_with(line, "##") {
                let selector = trim(line[2usize..])
                if selector.len > 0usize && !str.starts_with(selector, "+js(") { add_unique(selectors, &ns, selector) }
                continue
            }
            if str.starts_with(line, "||") {
                var end = line.len
                var k = 2usize
                while k < line.len {
                    if line[k] == 94u8 {
                        end = k
                        break
                    }
                    k += 1usize
                }
                let host = trim(lower(a, line[2usize..end]))
                if host.len > 0usize && !str.contains(host, "/") && !str.contains(host, "*") && !str.contains(host, "[") { add_unique(domains, &nd, host) }
            }
            continue
        }
        i += 1usize
    }
    ret FilterRules { domains: domains[0usize..nd], selectors: selectors[0usize..ns] }
}

// --- Content-Security-Policy -----------------------------------------------------------------------------------

type SourceSet = struct { present: bool, items: []const str }

type Csp = struct { blocks_scripts: bool, connect: SourceSet, image: SourceSet, style: SourceSet, font: SourceSet }

fn no_sources() -> SourceSet {
    let none: []const str = zero
    ret SourceSet { present: false, items: none }
}

fn words(a: *mem.Arena, s: str) -> []const str {
    // `trim().split(RegExp(r'\s+'))`: the empty string yields one empty token
    let t = trim(s)
    let (out, e) = mem.alloc[str](a, t.len + 2usize)
    var n = 0usize
    var i = 0usize
    if t.len == 0usize {
        out[0] = ""
        ret out[0usize..1usize]
    }
    while i < t.len {
        while i < t.len && is_ws(t[i]) { i += 1usize }
        let from = i
        while i < t.len && !is_ws(t[i]) { i += 1usize }
        if i > from {
            out[n] = t[from..i]
            n += 1usize
        }
    }
    ret out[0usize..n]
}

fn expand_sources(a: *mem.Arena, sources: str, has: bool, document_url: str) -> SourceSet {
    if !has { ret no_sources() }
    let tokens = words(a, sources)
    var star = false
    var i = 0usize
    while i < tokens.len {
        if str.eq(tokens[i], "*") { star = true }
        i += 1usize
    }
    if tokens.len == 0usize || star { ret no_sources() }
    let none: []const str = zero
    if tokens.len == 1usize && str.eq(tokens[0], "'none'") { ret SourceSet { present: true, items: none } }
    let (doc_origin, has_origin) = norm_origin(a, document_url)
    let (out, e) = mem.alloc[str](a, tokens.len + 1usize)
    var n = 0usize
    i = 0usize
    while i < tokens.len {
        let tok = tokens[i]
        i += 1usize
        if str.eq(tok, "'self'") && has_origin {
            add_unique(out, &n, doc_origin)
        } else if str.starts_with(tok, "https:") || str.starts_with(tok, "http:") {
            let sep = index_of(tok, 58u8)
            if str.contains(tok, "://") {
                var at = 0usize
                var k = 0usize
                while k + 3usize <= tok.len {
                    if str.eq(tok[k..k + 3usize], "://") {
                        at = k + 3usize
                        break
                    }
                    k += 1usize
                }
                var rest = tok[at..]
                let slash = index_of(rest, 47u8)
                if slash >= 0i64 { rest = rest[0usize..usize(slash)] }
                let scheme = lower(a, tok[0usize..usize(sep)])
                if rest.len > 0usize { add_unique(out, &n, join(a, join(a, scheme, "://"), lower(a, rest))) }
            } else {
                add_unique(out, &n, tok)
            }
        }
    }
    ret SourceSet { present: true, items: out[0usize..n] }
}

fn directive_value(a: *mem.Arena, names: []const str, values: []const str, key: str) -> (str, bool) {
    var i = names.len
    while i > 0usize {
        if str.eq(names[i - 1usize], key) { ret (values[i - 1usize], true) }
        i -= 1usize
    }
    ret ("", false)
}

// A `Content-Security-Policy` header for a document at `document_url`; `has_header` false is the empty policy.
fn parse_csp(a: *mem.Arena, header: str, has_header: bool, document_url: str) -> Csp {
    if !has_header { ret Csp { blocks_scripts: false, connect: no_sources(), image: no_sources(), style: no_sources(), font: no_sources() } }
    let (names, e1) = mem.alloc[str](a, header.len + 1usize)
    let (values, e2) = mem.alloc[str](a, header.len + 1usize)
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= header.len {
        if i == header.len || header[i] == 59u8 {
            let directive = trim(header[start..i])
            start = i + 1usize
            if directive.len > 0usize {
                let parts = words(a, directive)
                if parts.len > 0usize && parts[0].len > 0usize {
                    let name = lower(a, parts[0])
                    var joined = ""
                    var k = 1usize
                    while k < parts.len {
                        if k > 1usize { joined = join(a, joined, " ") }
                        joined = join(a, joined, lower(a, parts[k]))
                        k += 1usize
                    }
                    names[n] = name
                    values[n] = joined
                    n += 1usize
                }
            }
        }
        i += 1usize
    }
    let ns = names[0usize..n]
    let vs = values[0usize..n]
    let (default_src, has_default) = directive_value(a, ns, vs, "default-src")
    var script = default_src
    var has_script = has_default
    let (s1, h1) = directive_value(a, ns, vs, "script-src")
    if h1 {
        script = s1
        has_script = true
    }
    var blocks = false
    if has_script && str.eq(script, "'none'") { blocks = true }
    let kinds = [4]str{ "connect-src", "img-src", "style-src", "font-src" }
    var sets: [4]SourceSet = zero
    var q = 0usize
    while q < 4usize {
        var src = default_src
        var has_src = has_default
        let (sv, hv) = directive_value(a, ns, vs, kinds[q])
        if hv {
            src = sv
            has_src = true
        }
        sets[q] = expand_sources(a, src, has_src, document_url)
        q += 1usize
    }
    ret Csp { blocks_scripts: blocks, connect: sets[0], image: sets[1], style: sets[2], font: sets[3] }
}

fn source_allows(a: *mem.Arena, source: str, dest: Url, dest_origin: str, has_target_origin: bool) -> bool {
    if has_target_origin && str.eq(source, dest_origin) { ret true }
    var si = -1i64
    var k = 0usize
    while k + 3usize <= source.len {
        if str.eq(source[k..k + 3usize], "://") {
            si = i64(k)
            break
        }
        k += 1usize
    }
    if si < 0i64 { ret false }
    if !str.eq(lower(a, source[0usize..usize(si)]), dest.scheme) { ret false }
    var host_port = source[usize(si) + 3usize..]
    let slash = index_of(host_port, 47u8)
    if slash >= 0i64 { host_port = host_port[0usize..usize(slash)] }
    var host = host_port
    var port = ""
    var has_port = false
    let colon = last_index_of(host_port, 58u8)
    if colon > 0i64 {
        let (pv, ok_p) = int_try_parse(host_port[usize(colon) + 1usize..])
        if ok_p {
            host = host_port[0usize..usize(colon)]
            port = host_port[usize(colon) + 1usize..]
            has_port = true
        }
    }
    host = lower(a, host)
    let th = lower(a, dest.host)
    var host_ok = false
    if str.starts_with(host, "*.") {
        let suffix = host[2usize..]
        host_ok = str.eq(th, suffix) || str.ends_with(th, join(a, ".", suffix))
    } else {
        host_ok = str.eq(th, host)
    }
    if !host_ok { ret false }
    if has_port {
        var tp = 80i64
        if dest.has_port {
            tp = dest.port
        } else if str.eq(dest.scheme, "https") {
            tp = 443i64
        }
        if !str.eq(port_str(a, tp), port) { ret false }
    }
    ret true
}

fn blocked_by(a: *mem.Arena, target_url: str, s: SourceSet) -> bool {
    if !s.present { ret false }
    if s.items.len == 0usize { ret true }
    let dest = parse_url(a, target_url)
    if !dest.valid || dest.host.len == 0usize { ret true }
    let scheme_source = join(a, dest.scheme, ":")
    var i = 0usize
    while i < s.items.len {
        if str.eq(s.items[i], scheme_source) { ret false }
        i += 1usize
    }
    let (origin, has_origin) = norm_origin(a, target_url)
    i = 0usize
    while i < s.items.len {
        if source_allows(a, s.items[i], dest, origin, has_origin) { ret false }
        i += 1usize
    }
    ret true
}

fn csp_blocks_connect(a: *mem.Arena, p: Csp, url: str) -> bool { ret blocked_by(a, url, p.connect) }
fn csp_blocks_image(a: *mem.Arena, p: Csp, url: str) -> bool { ret blocked_by(a, url, p.image) }
fn csp_blocks_style(a: *mem.Arena, p: Csp, url: str) -> bool { ret blocked_by(a, url, p.style) }
fn csp_blocks_font(a: *mem.Arena, p: Csp, url: str) -> bool { ret blocked_by(a, url, p.font) }

// --- CORS, CORP, COEP, COOP ------------------------------------------------------------------------------------

fn is_safelisted_method(a: *mem.Arena, method: str) -> bool {
    let m = upper(a, method)
    ret str.eq(m, "GET") || str.eq(m, "HEAD") || str.eq(m, "POST")
}

fn upper(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 97u8 && c <= 122u8 { c -= 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

// Whether `name: value` is a CORS-safelisted request header.
fn is_cors_safelisted_request_header(a: *mem.Arena, name: str, value: str) -> bool {
    let l = lower(a, trim(name))
    if !(str.eq(l, "accept") || str.eq(l, "accept-language") || str.eq(l, "content-language") || str.eq(l, "content-type")) { ret false }
    if value.len > 128usize { ret false }
    if str.eq(l, "content-type") {
        let semi = index_of(value, 59u8)
        var essence = value
        if semi >= 0i64 { essence = value[0usize..usize(semi)] }
        let e = lower(a, trim(essence))
        ret str.eq(e, "application/x-www-form-urlencoded") || str.eq(e, "multipart/form-data") || str.eq(e, "text/plain")
    }
    ret true
}

// The non-safelisted header names, lower-cased and sorted.
fn cors_unsafe_header_names(a: *mem.Arena, h: Headers) -> []const str {
    let (out, e) = mem.alloc[str](a, h.names.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < h.names.len {
        if !is_cors_safelisted_request_header(a, h.names[i], h.values[i]) {
            out[n] = lower(a, trim(h.names[i]))
            n += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < n {
        let cur = out[i]
        var j = i
        while j > 0usize && str.compare(out[j - 1usize], cur) > 0i32 {
            out[j] = out[j - 1usize]
            j -= 1usize
        }
        out[j] = cur
        i += 1usize
    }
    ret out[0usize..n]
}

fn is_simple_cors_request(a: *mem.Arena, method: str, h: Headers) -> bool {
    ret is_safelisted_method(a, method) && cors_unsafe_header_names(a, h).len == 0usize
}

fn split_header_list(a: *mem.Arena, value: str, has: bool) -> []const str {
    let none: []const str = zero
    if !has { ret none }
    let (out, e) = mem.alloc[str](a, value.len + 1usize)
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= value.len {
        if i == value.len || value[i] == 44u8 {
            let part = trim(value[start..i])
            start = i + 1usize
            if part.len > 0usize {
                out[n] = part
                n += 1usize
            }
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn list_contains(xs: []const str, v: str) -> bool {
    var i = 0usize
    while i < xs.len {
        if str.eq(xs[i], v) { ret true }
        i += 1usize
    }
    ret false
}

// `scheme://host[:port]` for http(s) URLs with a host.
fn cors_serialize_origin(a: *mem.Arena, url: str) -> (str, bool) {
    let (o, good) = norm_origin(a, url)
    ret (o, good)
}

type Reason = struct { blocked: bool, text: str }

fn allowed() -> Reason { ret Reason { blocked: false, text: "" } }

fn blocked(text: str) -> Reason { ret Reason { blocked: true, text: text } }

// The CORS check on a cross-origin response.
fn cors_response_block_reason(a: *mem.Arena, document_origin: str, response: Headers, credentialed: bool) -> Reason {
    let (acao_raw, has_acao) = header_get(response, "access-control-allow-origin")
    let acao = trim(acao_raw)
    if !has_acao || acao.len == 0usize { ret blocked("CORS: missing Access-Control-Allow-Origin") }
    if str.eq(acao, "*") {
        if credentialed { ret blocked("CORS: wildcard Access-Control-Allow-Origin cannot authorize a credentialed request") }
    } else {
        let (serial, has_serial) = cors_serialize_origin(a, acao)
        var shown = acao
        if has_serial { shown = serial }
        if !str.eq(shown, document_origin) {
            ret blocked(join(a, join(a, "CORS: Access-Control-Allow-Origin '", acao), join(a, "' does not match origin ", document_origin)))
        }
    }
    if credentialed {
        let (acac_raw, has_acac) = header_get(response, "access-control-allow-credentials")
        if !has_acac || !str.eq(trim(acac_raw), "true") {
            ret blocked("CORS: credentialed request without Access-Control-Allow-Credentials: true")
        }
    }
    ret allowed()
}

// A preflight response checked against the intended method and headers.
fn cors_preflight_block_reason(a: *mem.Arena, document_origin: str, method: str, unsafe_names: []const str, status: i64, response: Headers, credentialed: bool) -> Reason {
    if status < 200i64 || status >= 300i64 { ret blocked(join(a, "CORS preflight: HTTP ", f.number_text(a, f64(status)))) }
    let origin_reason = cors_response_block_reason(a, document_origin, response, credentialed)
    if origin_reason.blocked { ret origin_reason }
    let (methods_raw, has_methods) = header_get(response, "access-control-allow-methods")
    let methods = split_header_list(a, methods_raw, has_methods)
    var method_star = false
    var up_methods = methods
    let (um, ume) = mem.alloc[str](a, methods.len + 1usize)
    var i = 0usize
    while i < methods.len {
        um[i] = upper(a, methods[i])
        if str.eq(methods[i], "*") { method_star = true }
        i += 1usize
    }
    up_methods = um[0usize..methods.len]
    let wanted = upper(a, method)
    if !(method_star && !credentialed) && !list_contains(up_methods, wanted) && !is_safelisted_method(a, wanted) {
        ret blocked(join(a, join(a, "CORS preflight: method ", wanted), " not allowed by Access-Control-Allow-Methods"))
    }
    let (headers_raw, has_headers) = header_get(response, "access-control-allow-headers")
    let allowed_raw = split_header_list(a, headers_raw, has_headers)
    let (lh, lhe) = mem.alloc[str](a, allowed_raw.len + 1usize)
    var header_star = false
    i = 0usize
    while i < allowed_raw.len {
        lh[i] = lower(a, allowed_raw[i])
        if str.eq(lh[i], "*") { header_star = true }
        i += 1usize
    }
    let names = lh[0usize..allowed_raw.len]
    i = 0usize
    while i < unsafe_names.len {
        let name = unsafe_names[i]
        let covered = list_contains(names, name) || (header_star && !credentialed && !str.eq(name, "authorization"))
        if !covered {
            ret blocked(join(a, join(a, "CORS preflight: header ", name), " not allowed by Access-Control-Allow-Headers"))
        }
        i += 1usize
    }
    ret allowed()
}

type PreflightEntry = struct { key: str, methods: []const str, method_wildcard: bool, header_names: []const str, header_wildcard: bool, expires_ms: i64 }

type PreflightCache = struct { entries: []PreflightEntry, count: usize }

fn new_preflight_cache(a: *mem.Arena) -> PreflightCache {
    let (entries, e) = mem.alloc[PreflightEntry](a, 257usize)
    ret PreflightCache { entries: entries, count: 0usize }
}

fn preflight_key(a: *mem.Arena, origin: str, url: str, credentialed: bool) -> str {
    let u = parse_url(a, url)
    var mode = "anon"
    if credentialed { mode = "cred" }
    ret join(a, join(a, origin, " "), join(a, join(a, mode, " "), url_text(a, u)))
}

// Records a successful preflight; a non-positive `Access-Control-Max-Age` disables caching.
fn preflight_store(a: *mem.Arena, c: *PreflightCache, origin: str, url: str, response: Headers, credentialed: bool, now_ms: i64) {
    var max_age = 5i64
    let (raw, has_raw) = header_get(response, "access-control-max-age")
    if has_raw {
        let (secs, ok_s) = int_try_parse(trim(raw))
        if ok_s {
            if secs <= 0i64 { ret }
            max_age = secs
            if max_age > 7200i64 { max_age = 7200i64 }
        }
    }
    let (methods_raw, has_methods) = header_get(response, "access-control-allow-methods")
    let methods = split_header_list(a, methods_raw, has_methods)
    let (um, e1) = mem.alloc[str](a, methods.len + 1usize)
    var method_star = false
    var i = 0usize
    while i < methods.len {
        um[i] = upper(a, methods[i])
        if str.eq(um[i], "*") { method_star = true }
        i += 1usize
    }
    let (headers_raw, has_headers) = header_get(response, "access-control-allow-headers")
    let hs = split_header_list(a, headers_raw, has_headers)
    let (lh, e2) = mem.alloc[str](a, hs.len + 1usize)
    var header_star = false
    i = 0usize
    while i < hs.len {
        lh[i] = lower(a, hs[i])
        if str.eq(lh[i], "*") { header_star = true }
        i += 1usize
    }
    let key = preflight_key(a, origin, url, credentialed)
    let entry = PreflightEntry {
        key: key,
        methods: um[0usize..methods.len],
        method_wildcard: method_star && !credentialed,
        header_names: lh[0usize..hs.len],
        header_wildcard: header_star && !credentialed,
        expires_ms: now_ms + max_age * 1000i64,
    }
    var at = c.count
    i = 0usize
    while i < c.count {
        if str.eq(c.entries[i].key, key) { at = i }
        i += 1usize
    }
    if at < c.count {
        c.entries[at] = entry
        ret
    }
    if c.count >= 256usize {
        var k = 1usize
        while k < c.count {
            c.entries[k - 1usize] = c.entries[k]
            k += 1usize
        }
        c.count -= 1usize
    }
    c.entries[c.count] = entry
    c.count += 1usize
}

// Whether a fresh grant already authorizes the method and headers; an expired entry is dropped.
fn preflight_is_allowed(a: *mem.Arena, c: *PreflightCache, origin: str, url: str, method: str, unsafe_names: []const str, credentialed: bool, now_ms: i64) -> bool {
    let key = preflight_key(a, origin, url, credentialed)
    var at = c.count
    var i = 0usize
    while i < c.count {
        if str.eq(c.entries[i].key, key) { at = i }
        i += 1usize
    }
    if at >= c.count { ret false }
    let e = c.entries[at]
    if !(now_ms < e.expires_ms) {
        var k = at + 1usize
        while k < c.count {
            c.entries[k - 1usize] = c.entries[k]
            k += 1usize
        }
        c.count -= 1usize
        ret false
    }
    let wanted = upper(a, method)
    let method_ok = e.method_wildcard || list_contains(e.methods, wanted) || is_safelisted_method(a, wanted)
    if !method_ok { ret false }
    i = 0usize
    while i < unsafe_names.len {
        let name = unsafe_names[i]
        let covered = list_contains(e.header_names, name) || (e.header_wildcard && !str.eq(name, "authorization"))
        if !covered { ret false }
        i += 1usize
    }
    ret true
}

// 0 none, 1 same-origin, 2 same-site, 3 cross-origin
fn parse_corp(a: *mem.Arena, value: str, has: bool) -> i32 {
    if !has { ret 0i32 }
    let v = lower(a, trim(value))
    if str.eq(v, "same-origin") { ret 1i32 }
    if str.eq(v, "same-site") { ret 2i32 }
    if str.eq(v, "cross-origin") { ret 3i32 }
    ret 0i32
}

// 0 unsafe-none, 1 require-corp, 2 credentialless
fn parse_coep(a: *mem.Arena, value: str, has: bool) -> i32 {
    if !has { ret 0i32 }
    let v = lower(a, trim(value))
    if str.eq(v, "require-corp") { ret 1i32 }
    if str.eq(v, "credentialless") { ret 2i32 }
    ret 0i32
}

// 0 unsafe-none, 1 same-origin, 2 same-origin-allow-popups
fn parse_coop(a: *mem.Arena, value: str, has: bool) -> i32 {
    if !has { ret 0i32 }
    let v = lower(a, trim(value))
    if str.eq(v, "same-origin") { ret 1i32 }
    if str.eq(v, "same-origin-allow-popups") { ret 2i32 }
    ret 0i32
}

fn all_numeric_labels(labels: []const str, count: usize) -> bool {
    var i = 0usize
    while i < count {
        if labels[i].len == 0usize { ret false }
        let (v, ok_v) = int_try_parse(labels[i])
        if !ok_v { ret false }
        i += 1usize
    }
    ret true
}

fn split_dots(a: *mem.Arena, s: str) -> []const str {
    let (out, e) = mem.alloc[str](a, s.len + 2usize)
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= s.len {
        if i == s.len || s[i] == 46u8 {
            out[n] = s[start..i]
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn join_labels(a: *mem.Arena, labels: []const str, from: usize) -> str {
    var out = ""
    var i = from
    while i < labels.len {
        if i > from { out = join(a, out, ".") }
        out = join(a, out, labels[i])
        i += 1usize
    }
    ret out
}

// The site of a host as `cors.dart` approximates it: the last two labels, three under a `<sld>.<cc>` suffix.
fn registrable_domain_cors(a: *mem.Arena, host: str) -> str {
    let h = lower(a, host)
    if str.contains(h, ":") || !str.contains(h, ".") { ret h }
    let labels = split_dots(a, h)
    if all_numeric_labels(labels, labels.len) { ret h }
    var take = 2usize
    if labels.len >= 3usize {
        let last = labels[labels.len - 1usize]
        let second = labels[labels.len - 2usize]
        if last.len == 2usize && (str.eq(second, "co") || str.eq(second, "com") || str.eq(second, "net") || str.eq(second, "org") || str.eq(second, "gov") || str.eq(second, "ac") || str.eq(second, "edu")) {
            take = 3usize
        }
    }
    ret join_labels(a, labels, labels.len - take)
}

// The Cross-Origin-Resource-Policy check for a no-cors response; `has_document` false is an about:/data: document.
fn corp_block_reason(a: *mem.Arena, document_origin: str, has_document: bool, resource_url: str, corp_header: str, has_corp: bool, embedder_requires_corp: bool) -> Reason {
    let resource = parse_url(a, resource_url)
    if !str.eq(resource.scheme, "http") && !str.eq(resource.scheme, "https") { ret allowed() }
    let (resource_origin, has_origin) = norm_origin(a, url_text(a, resource))
    if !has_origin { ret allowed() }
    if has_document && str.eq(document_origin, resource_origin) { ret allowed() }
    let policy = parse_corp(a, corp_header, has_corp)
    if policy == 3i32 { ret allowed() }
    if policy == 1i32 { ret blocked("blocked by Cross-Origin-Resource-Policy: same-origin") }
    if policy == 2i32 {
        var doc = bad_url()
        if has_document { doc = parse_url(a, document_origin) }
        let doc_host = doc.host
        var same_site = false
        if doc.valid && doc_host.len > 0usize {
            same_site = str.eq(registrable_domain_cors(a, doc_host), registrable_domain_cors(a, resource.host))
        }
        if !same_site { ret blocked("blocked by Cross-Origin-Resource-Policy: same-site (cross-site request)") }
        if doc.valid && str.eq(doc.scheme, "https") && !str.eq(resource.scheme, "https") {
            ret blocked("blocked by Cross-Origin-Resource-Policy: same-site (https document, non-https resource)")
        }
        ret allowed()
    }
    if embedder_requires_corp {
        ret blocked("blocked by Cross-Origin-Embedder-Policy: require-corp (cross-origin response without Cross-Origin-Resource-Policy)")
    }
    ret allowed()
}

// The embedding gate for a cross-origin no-cors response, with COEP's CORS-approval escape hatch.
fn no_cors_response_block_reason(a: *mem.Arena, document_origin: str, has_document: bool, resource_url: str, response: Headers, embedder_requires_corp: bool) -> Reason {
    let (corp, has_corp) = header_get(response, "cross-origin-resource-policy")
    let reason = corp_block_reason(a, document_origin, has_document, resource_url, corp, has_corp, embedder_requires_corp)
    if !reason.blocked { ret allowed() }
    if embedder_requires_corp && parse_corp(a, corp, has_corp) == 0i32 && has_document {
        let cors = cors_response_block_reason(a, document_origin, response, false)
        if !cors.blocked { ret allowed() }
    }
    ret reason
}

// --- cookie jar ------------------------------------------------------------------------------------------------

type Cookie = struct { name: str, value: str, domain: str, path: str, has_partition: bool, partition: str, has_expires: bool, expires_ms: i64, secure: bool, http_only: bool, same_site: u8, created_ms: i64 }

type CookieJar = struct { cookies: []Cookie, count: usize, block_third_party: bool }

fn new_cookie_jar(a: *mem.Arena, block_third_party: bool) -> CookieJar {
    let (cookies, e) = mem.alloc[Cookie](a, 3001usize)
    ret CookieJar { cookies: cookies, count: 0usize, block_third_party: block_third_party }
}

fn jar_remove_at(j: *CookieJar, at: usize) {
    var k = at + 1usize
    while k < j.count {
        j.cookies[k - 1usize] = j.cookies[k]
        k += 1usize
    }
    j.count -= 1usize
}

fn jar_find(j: *CookieJar, c: Cookie) -> i64 {
    var i = 0usize
    while i < j.count {
        let o = j.cookies[i]
        if str.eq(o.name, c.name) && str.eq(o.domain, c.domain) && str.eq(o.path, c.path) && o.has_partition == c.has_partition && str.eq(o.partition, c.partition) { ret i64(i) }
        i += 1usize
    }
    ret -1i64
}

fn domain_matches(a: *mem.Arena, host: str, domain: str) -> bool {
    let h = lower(a, host)
    let d = lower(a, domain)
    if str.eq(h, d) { ret true }
    ret str.ends_with(h, join(a, ".", d))
}

// Last two labels of a host (IP literals and short hosts as they are).
fn registrable_domain_jar(a: *mem.Arena, host: str) -> str {
    let h = lower(a, host)
    if str.contains(h, ":") { ret h }
    let labels = split_dots(a, h)
    if labels.len <= 2usize { ret h }
    var numeric = true
    var i = 0usize
    while i < labels.len {
        let (v, ok_v) = int_try_parse(labels[i])
        if !ok_v { numeric = false }
        i += 1usize
    }
    if numeric { ret h }
    ret join_labels(a, labels, labels.len - 2usize)
}

// `scheme://registrable-domain` for a URL with a host.
fn partition_key_for(a: *mem.Arena, u: Url) -> (str, bool) {
    if u.host.len == 0usize { ret ("", false) }
    ret (join(a, join(a, u.scheme, "://"), registrable_domain_jar(a, u.host)), true)
}

fn is_third_party(a: *mem.Arena, u: Url, partition_key: str, has_partition: bool) -> bool {
    if !has_partition { ret false }
    let (site, has_site) = partition_key_for(a, u)
    if !has_site { ret false }
    ret !str.eq(site, partition_key)
}

fn digit_run(s: str, at: usize, min: usize, max: usize) -> usize {
    var n = 0usize
    while at + n < s.len && s[at + n] >= 48u8 && s[at + n] <= 57u8 && n < max { n += 1usize }
    if n < min { ret 0usize }
    ret n
}

// The first `D{1,2} <word{3}> D{4} DD:DD:DD` in a cookie `Expires` value, as UTC milliseconds.
fn parse_cookie_date(a: *mem.Arena, raw: str) -> (i64, bool) {
    var start = 0usize
    while start < raw.len {
        var at = start
        // day: 1-2 digits (greedy with backtracking to 1)
        var found = false
        var day_len = digit_run(raw, at, 1usize, 2usize)
        while day_len > 0usize && !found {
            var p = at + day_len
            var ws = 0usize
            while p + ws < raw.len && is_ws(raw[p + ws]) { ws += 1usize }
            if ws > 0usize {
                p += ws
                if p + 3usize <= raw.len {
                    var word_ok = true
                    var k = 0usize
                    while k < 3usize {
                        let c = raw[p + k]
                        if !((c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) || c == 95u8) { word_ok = false }
                        k += 1usize
                    }
                    if word_ok {
                        let month_text = lower(a, raw[p..p + 3usize])
                        var q = p + 3usize
                        var ws2 = 0usize
                        while q + ws2 < raw.len && is_ws(raw[q + ws2]) { ws2 += 1usize }
                        if ws2 > 0usize {
                            q += ws2
                            if digit_run(raw, q, 4usize, 4usize) == 4usize {
                                var r = q + 4usize
                                var ws3 = 0usize
                                while r + ws3 < raw.len && is_ws(raw[r + ws3]) { ws3 += 1usize }
                                if ws3 > 0usize {
                                    r += ws3
                                    if digit_run(raw, r, 2usize, 2usize) == 2usize && r + 2usize < raw.len && raw[r + 2usize] == 58u8 && digit_run(raw, r + 3usize, 2usize, 2usize) == 2usize && r + 5usize < raw.len && raw[r + 5usize] == 58u8 && digit_run(raw, r + 6usize, 2usize, 2usize) == 2usize {
                                        let months = [12]str{ "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" }
                                        var month = 0i64
                                        var m = 0usize
                                        while m < 12usize {
                                            if str.eq(months[m], month_text) { month = i64(m) + 1i64 }
                                            m += 1usize
                                        }
                                        if month == 0i64 { ret (0i64, false) }
                                        let day = num_of(raw[at..at + day_len])
                                        let year = num_of(raw[q..q + 4usize])
                                        let hour = num_of(raw[r..r + 2usize])
                                        let minute = num_of(raw[r + 3usize..r + 5usize])
                                        let second = num_of(raw[r + 6usize..r + 8usize])
                                        ret (utc_ms(year, month, day, hour, minute, second), true)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            day_len -= 1usize
            found = false
        }
        start += 1usize
        at = start
    }
    ret (0i64, false)
}

fn num_of(s: str) -> i64 {
    var v = 0i64
    var i = 0usize
    while i < s.len {
        v = v * 10i64 + i64(s[i] - 48u8)
        i += 1usize
    }
    ret v
}

// The `Set-Cookie` values in a joined header: split at a comma followed by `name=value` where it is not inside a date.
fn split_set_cookie(a: *mem.Arena, raw: str) -> []const str {
    let (out, e) = mem.alloc[str](a, raw.len + 1usize)
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i < raw.len {
        if raw[i] == 44u8 {
            var p = i + 1usize
            while p < raw.len && is_ws(raw[p]) { p += 1usize }
            var q = p
            while q < raw.len && !is_ws(raw[q]) && raw[q] != 44u8 && raw[q] != 59u8 && raw[q] != 61u8 { q += 1usize }
            if q > p && q + 1usize < raw.len && raw[q] == 61u8 {
                let c = raw[q + 1usize]
                if !is_ws(c) && c != 44u8 && c != 59u8 && c != 61u8 {
                    if i > start {
                        out[n] = raw[start..i]
                        n += 1usize
                    }
                    start = p
                    i = p
                    continue
                }
            }
        }
        i += 1usize
    }
    if raw.len > start {
        out[n] = raw[start..]
        n += 1usize
    }
    ret out[0usize..n]
}

fn same_site_allowed(ss: u8, is_top_level: bool) -> bool {
    if ss == 2u8 { ret true }
    ret is_top_level
}

// Processes one `Set-Cookie` header received for `url`; `partition_key` is the top-frame site when known.
fn jar_process_one(a: *mem.Arena, j: *CookieJar, request: Url, header: str, partition_key: str, has_partition_key: bool, now_ms: i64) {
    let parts_end = index_of(header, 59u8)
    var first = header
    if parts_end >= 0i64 { first = header[0usize..usize(parts_end)] }
    let nv = trim(first)
    let eq = index_of(nv, 61u8)
    if eq < 0i64 { ret }
    let name = trim(nv[0usize..usize(eq)])
    let value = trim(nv[usize(eq) + 1usize..])
    if name.len == 0usize { ret }
    if name.len + value.len > 4096usize { ret }
    var domain = request.host
    var path = "/"
    var secure = false
    var http_only = false
    var partitioned = false
    var has_domain_attr = false
    var explicit_root = false
    var has_expires = false
    var expires_ms = 0i64
    var same_site = 1u8
    var rest = ""
    if parts_end >= 0i64 { rest = header[usize(parts_end) + 1usize..] }
    var start = 0usize
    var i = 0usize
    while i <= rest.len && parts_end >= 0i64 {
        if i == rest.len || rest[i] == 59u8 {
            let attr = trim(rest[start..i])
            start = i + 1usize
            let low = lower(a, attr)
            if str.eq(low, "secure") {
                secure = true
            } else if str.eq(low, "httponly") {
                http_only = true
            } else if str.eq(low, "partitioned") {
                partitioned = true
            } else if str.starts_with(low, "samesite=") {
                let v = lower(a, trim(attr[9usize..]))
                if str.eq(v, "strict") {
                    same_site = 0u8
                } else if str.eq(v, "none") {
                    same_site = 2u8
                } else {
                    same_site = 1u8
                }
            } else if str.starts_with(low, "domain=") {
                has_domain_attr = true
                var d = lower(a, trim(attr[7usize..]))
                if str.starts_with(d, ".") { d = d[1usize..] }
                if domain_matches(a, request.host, d) { domain = d }
            } else if str.starts_with(low, "path=") {
                let p = trim(attr[5usize..])
                if str.starts_with(p, "/") {
                    path = p
                    explicit_root = str.eq(p, "/")
                }
            } else if str.starts_with(low, "max-age=") {
                let (secs, ok_s) = int_try_parse(trim(attr[8usize..]))
                if ok_s {
                    has_expires = true
                    if secs <= 0i64 {
                        expires_ms = 0i64
                    } else {
                        expires_ms = now_ms + secs * 1000i64
                    }
                }
            } else if str.starts_with(low, "expires=") {
                if !has_expires {
                    let (ms, ok_d) = parse_cookie_date(a, trim(attr[8usize..]))
                    if ok_d {
                        has_expires = true
                        expires_ms = ms
                    }
                }
            }
        }
        i += 1usize
    }
    if same_site == 2u8 && !secure { same_site = 1u8 }
    let low_name = lower(a, name)
    if str.starts_with(low_name, "__host-") {
        if !secure || !str.eq(request.scheme, "https") { ret }
        if has_domain_attr || !explicit_root { ret }
    } else if str.starts_with(low_name, "__secure-") {
        if !secure || !str.eq(request.scheme, "https") { ret }
    }
    if partitioned && (!secure || !has_partition_key) { ret }
    if !partitioned && j.block_third_party && is_third_party(a, request, partition_key, has_partition_key) { ret }
    if !str.contains(domain, ".") { ret }
    let cookie = Cookie {
        name: name,
        value: value,
        domain: domain,
        path: path,
        has_partition: partitioned,
        partition: partition_key,
        has_expires: has_expires,
        expires_ms: expires_ms,
        secure: secure,
        http_only: http_only,
        same_site: same_site,
        created_ms: now_ms,
    }
    var keyed = cookie
    if !partitioned { keyed.partition = "" }
    var stored = cookie
    if !partitioned { stored.partition = "" }
    let at = jar_find(j, keyed)
    let is_delete = has_expires && (expires_ms <= 0i64 || expires_ms < now_ms)
    if is_delete {
        if at >= 0i64 { jar_remove_at(j, usize(at)) }
        ret
    }
    // per-domain cap
    var domain_count = 0usize
    var k = 0usize
    while k < j.count {
        if str.eq(j.cookies[k].domain, domain) { domain_count += 1usize }
        k += 1usize
    }
    if at < 0i64 && domain_count >= 50usize {
        var oldest = -1i64
        k = 0usize
        while k < j.count {
            if str.eq(j.cookies[k].domain, domain) && !j.cookies[k].secure {
                if oldest < 0i64 || j.cookies[k].created_ms < j.cookies[usize(oldest)].created_ms { oldest = i64(k) }
            }
            k += 1usize
        }
        if oldest >= 0i64 {
            jar_remove_at(j, usize(oldest))
        } else {
            ret
        }
    }
    while j.count >= 3000usize { jar_remove_at(j, 0usize) }
    let again = jar_find(j, keyed)
    if again >= 0i64 {
        j.cookies[usize(again)] = stored
    } else {
        j.cookies[j.count] = stored
        j.count += 1usize
    }
}

// Stores the valid cookies of a (possibly joined) `Set-Cookie` header received for `url`.
fn jar_process_response(a: *mem.Arena, j: *CookieJar, url: str, set_cookie: str, partition_key: str, has_partition_key: bool, now_ms: i64) {
    let u = parse_url(a, url)
    if !u.valid { ret }
    let headers = split_set_cookie(a, set_cookie)
    var i = 0usize
    while i < headers.len {
        jar_process_one(a, j, u, headers[i], partition_key, has_partition_key, now_ms)
        i += 1usize
    }
}

type CookieHeader = struct { present: bool, value: str }

// The `Cookie` header for a request, or absent when no cookie applies.
fn jar_cookie_header(a: *mem.Arena, j: *CookieJar, url: str, is_top_level: bool, partition_key: str, has_partition_key: bool, now_ms: i64) -> CookieHeader {
    let u = parse_url(a, url)
    if !u.valid { ret CookieHeader { present: false, value: "" } }
    let third_party = is_third_party(a, u, partition_key, has_partition_key)
    var i = 0usize
    while i < j.count {
        let c = j.cookies[i]
        if c.has_expires && c.expires_ms < now_ms {
            jar_remove_at(j, i)
            continue
        }
        i += 1usize
    }
    var out = ""
    var n = 0usize
    i = 0usize
    while i < j.count {
        let c = j.cookies[i]
        i += 1usize
        if c.has_partition {
            if !has_partition_key || !str.eq(c.partition, partition_key) { continue }
        } else if j.block_third_party && third_party {
            continue
        }
        if !domain_matches(a, u.host, c.domain) { continue }
        if !str.starts_with(u.path, c.path) { continue }
        if c.secure && !str.eq(u.scheme, "https") { continue }
        if !same_site_allowed(c.same_site, is_top_level) { continue }
        if n > 0usize { out = join(a, out, "; ") }
        out = join(a, out, join(a, c.name, join(a, "=", c.value)))
        n += 1usize
    }
    ret CookieHeader { present: n > 0usize, value: out }
}

fn jar_clear(j: *CookieJar) { j.count = 0usize }

fn jar_clear_origin(a: *mem.Arena, j: *CookieJar, origin_host: str) {
    var i = 0usize
    while i < j.count {
        if domain_matches(a, origin_host, j.cookies[i].domain) {
            jar_remove_at(j, i)
            continue
        }
        i += 1usize
    }
}
