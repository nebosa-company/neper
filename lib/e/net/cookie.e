// HTTP cookies (RFC 6265): `parse` reads a `Set-Cookie` line received from `host` for `path` into a `Cookie`
// (name, value, Domain with its host-only flag, Path with the default-path rule, Expires or Max-Age as a Unix time,
// Secure, HttpOnly, SameSite), `store` puts it in a `Jar` the caller owns (replacing a cookie of the same name,
// domain and path, dropping one whose time has passed), and `header` builds the `Cookie` request header for a URL:
// the cookies whose domain and path match, not expired, `Secure` ones only on https, the longer path first and
// earlier-stored first among equal paths. A cookie for a public suffix is not refused here (the caller has the
// suffix list); a Domain attribute that does not cover the host is refused, as is a `__Host-` or `__Secure-` prefix
// breaking its rules. Expires dates are read as `e.fmt.mail`'s dates are (IMF-fixdate and its common variants).
//
// Memory: strings of a parsed cookie live in the arena passed in; a jar holds its cookies in a slice the caller gives.
use e.mem
use e.str
use e.fmt.mail as mail

error Invalid
error Refused
error JarFull

type SameSite = enum u8 { Unset, Lax, Strict, None }
type Cookie = struct {
    name: str,
    value: str,
    domain: str,
    host_only: bool,
    path: str,
    expires: i64,
    has_expires: bool,
    secure: bool,
    http_only: bool,
    same_site: SameSite,
    created: i64,
}
type Jar = struct { cookies: []Cookie, count: usize, clock: i64 }

fn fold(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn eq_fold(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if fold(a[i]) != fold(b[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn lower(a: *mem.Arena, s: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, s.len + 1usize)
    if out_error != ok { ret ("", out_error) }
    var i = 0usize
    while i < s.len {
        out[i] = fold(s[i])
        i += 1usize
    }
    ret (out[0usize..s.len], ok)
}

fn starts_fold(s: str, prefix: str) -> bool {
    if s.len < prefix.len { ret false }
    ret eq_fold(s[0usize..prefix.len], prefix)
}

// RFC 6265 5.1.4: the default path of a request path: up to, not including, its last `/` (or `/`).
fn default_path(request_path: str) -> str {
    if request_path.len == 0usize || request_path[0usize] != 47u8 { ret "/" }
    var last = 0usize
    var i = 0usize
    while i < request_path.len {
        if request_path[i] == 47u8 { last = i }
        i += 1usize
    }
    if last == 0usize { ret "/" }
    ret request_path[0usize..last]
}

// RFC 6265 5.1.3: whether `host` domain-matches `domain` (equal, or a subdomain of it for a name, not an address).
fn domain_match(host: str, domain: str) -> bool {
    if eq_fold(host, domain) { ret true }
    if host.len <= domain.len { ret false }
    if !eq_fold(host[host.len - domain.len..host.len], domain) { ret false }
    if host[host.len - domain.len - 1usize] != 46u8 { ret false }
    // Not an IPv4 literal.
    var all_digits_dots = true
    var i = 0usize
    while i < host.len {
        let c = host[i]
        if !((c >= 48u8 && c <= 57u8) || c == 46u8) { all_digits_dots = false }
        i += 1usize
    }
    ret !all_digits_dots
}

// RFC 6265 5.1.4: whether `request_path` path-matches the cookie's `cookie_path`.
fn path_match(request_path: str, cookie_path: str) -> bool {
    if str.eq(request_path, cookie_path) { ret true }
    if request_path.len > cookie_path.len && str.starts_with(request_path, cookie_path) {
        if cookie_path.len > 0usize && cookie_path[cookie_path.len - 1usize] == 47u8 { ret true }
        if request_path[cookie_path.len] == 47u8 { ret true }
    }
    ret false
}

fn trim(s: str) -> str { ret str.trim(s) }

// Parse the `Set-Cookie` value `line` received from `host` (lower case) for `request_path` at Unix time `now`.
fn parse(a: *mem.Arena, line: str, host: str, request_path: str, secure_request: bool, now: i64) -> (Cookie, err) {
    var c: Cookie = zero
    // name=value is up to the first `;`.
    var semi = line.len
    var i = 0usize
    while i < line.len {
        if line[i] == 59u8 {
            semi = i
            i = line.len
        } else {
            i += 1usize
        }
    }
    let pair = trim(line[0usize..semi])
    var eq = pair.len
    i = 0usize
    while i < pair.len {
        if pair[i] == 61u8 {
            eq = i
            i = pair.len
        } else {
            i += 1usize
        }
    }
    if eq >= pair.len { ret (c, Invalid) }
    c.name = trim(pair[0usize..eq])
    c.value = trim(pair[eq + 1usize..pair.len])
    if c.name.len == 0usize { ret (c, Invalid) }
    var domain = ""
    var has_domain = false
    var path_attribute = ""
    var has_path = false
    var max_age = 0i64
    var has_max_age = false
    var rest = semi
    while rest < line.len {
        // line[rest] is `;`.
        var next = line.len
        var j = rest + 1usize
        while j < line.len {
            if line[j] == 59u8 {
                next = j
                j = line.len
            } else {
                j += 1usize
            }
        }
        let attr = trim(line[rest + 1usize..next])
        var aeq = attr.len
        var k = 0usize
        while k < attr.len {
            if attr[k] == 61u8 {
                aeq = k
                k = attr.len
            } else {
                k += 1usize
            }
        }
        let aname = trim(attr[0usize..aeq])
        var avalue = ""
        if aeq < attr.len { avalue = trim(attr[aeq + 1usize..attr.len]) }
        if eq_fold(aname, "expires") {
            let (stamp, date_error) = mail.parse_date(avalue)
            if date_error == ok {
                c.expires = stamp.instant
                c.has_expires = true
            }
        } else if eq_fold(aname, "max-age") {
            // An optional minus and digits; anything else ignores the attribute.
            var neg = false
            var d = 0usize
            if avalue.len > 0usize && avalue[0usize] == 45u8 {
                neg = true
                d = 1usize
            }
            var good = d < avalue.len
            var n = 0i64
            while d < avalue.len {
                if avalue[d] < 48u8 || avalue[d] > 57u8 {
                    good = false
                } else if n < 100000000000i64 {
                    n = n * 10i64 + i64(avalue[d] - 48u8)
                }
                d += 1usize
            }
            if good {
                if neg { n = 0i64 - n }
                max_age = n
                has_max_age = true
            }
        } else if eq_fold(aname, "domain") {
            domain = avalue
            has_domain = true
        } else if eq_fold(aname, "path") {
            path_attribute = avalue
            has_path = true
        } else if eq_fold(aname, "secure") {
            c.secure = true
        } else if eq_fold(aname, "httponly") {
            c.http_only = true
        } else if eq_fold(aname, "samesite") {
            if eq_fold(avalue, "lax") { c.same_site = .Lax }
            if eq_fold(avalue, "strict") { c.same_site = .Strict }
            if eq_fold(avalue, "none") { c.same_site = .None }
        }
        rest = next
    }
    // Max-Age wins over Expires.
    if has_max_age {
        c.has_expires = true
        if max_age <= 0i64 { c.expires = 0i64 } else { c.expires = now + max_age }
    }
    // The domain: a leading dot is dropped; it must cover the host; otherwise the cookie is host-only.
    if has_domain && domain.len > 0usize {
        var d = domain
        if d[0usize] == 46u8 { d = d[1usize..d.len] }
        let (folded, fold_error) = lower(a, d)
        if fold_error != ok { ret (c, fold_error) }
        if !domain_match(host, folded) { ret (c, Refused) }
        c.domain = folded
        c.host_only = false
    } else {
        c.domain = host
        c.host_only = true
    }
    if has_path && path_attribute.len > 0usize && path_attribute[0usize] == 47u8 {
        c.path = path_attribute
    } else {
        c.path = default_path(request_path)
    }
    // The prefixes: __Secure- needs Secure from a secure request; __Host- also no Domain and path `/`.
    if starts_fold(c.name, "__Secure-") && !(c.secure && secure_request) { ret (c, Refused) }
    if starts_fold(c.name, "__Host-") {
        if !(c.secure && secure_request) || !c.host_only || !str.eq(c.path, "/") { ret (c, Refused) }
    }
    if c.secure && !secure_request { ret (c, Refused) }
    c.created = now
    ret (c, ok)
}

fn expired(c: Cookie, now: i64) -> bool {
    ret c.has_expires && c.expires <= now
}

fn jar_new(storage: []Cookie) -> Jar {
    ret Jar { cookies: storage, count: 0usize, clock: 0i64 }
}

// Put `c` in the jar: it replaces a cookie of the same name, domain and path (keeping the old creation time); a cookie
// already expired removes it and is not stored. JarFull when the jar has no room, after dropping the expired ones.
fn store(jar: *Jar, c: Cookie, now: i64) -> err {
    var i = 0usize
    while i < jar.count {
        let o = jar.cookies[i]
        if str.eq(o.name, c.name) && eq_fold(o.domain, c.domain) && str.eq(o.path, c.path) {
            if expired(c, now) {
                // Remove it by moving the last one down.
                jar.cookies[i] = jar.cookies[jar.count - 1usize]
                jar.count -= 1usize
                ret ok
            }
            var replacement = c
            replacement.created = o.created
            jar.cookies[i] = replacement
            ret ok
        }
        i += 1usize
    }
    if expired(c, now) { ret ok }
    // Drop expired cookies to make room.
    if jar.count >= jar.cookies.len {
        var kept = 0usize
        var k = 0usize
        while k < jar.count {
            if !expired(jar.cookies[k], now) {
                jar.cookies[kept] = jar.cookies[k]
                kept += 1usize
            }
            k += 1usize
        }
        jar.count = kept
    }
    if jar.count >= jar.cookies.len { ret JarFull }
    jar.cookies[jar.count] = c
    jar.count += 1usize
    ret ok
}

// The `Cookie` request header for a request to `host` and `path` (`secure`: https): "a=1; b=2", empty when no cookie
// applies. Ordered by path length, longest first, then by creation time.
fn header(a: *mem.Arena, jar: *Jar, host: str, path: str, secure: bool, now: i64) -> (str, err) {
    var chosen: [64]usize = zero
    var n = 0usize
    var i = 0usize
    while i < jar.count && n < 64usize {
        let c = jar.cookies[i]
        var domain_ok = false
        if c.host_only { domain_ok = eq_fold(host, c.domain) } else { domain_ok = domain_match(host, c.domain) }
        if domain_ok && path_match(path, c.path) && (!c.secure || secure) && !expired(c, now) {
            chosen[n] = i
            n += 1usize
        }
        i += 1usize
    }
    // Insertion sort: longer path first, then earlier creation.
    var s = 1usize
    while s < n {
        let value = chosen[s]
        var t = s
        while t > 0usize {
            let before = jar.cookies[chosen[t - 1usize]]
            let mine = jar.cookies[value]
            var move = false
            if mine.path.len > before.path.len { move = true }
            if mine.path.len == before.path.len && mine.created < before.created { move = true }
            if !move { break }
            chosen[t] = chosen[t - 1usize]
            t -= 1usize
        }
        chosen[t] = value
        s += 1usize
    }
    var size = 0usize
    var m = 0usize
    while m < n {
        let c = jar.cookies[chosen[m]]
        size += c.name.len + c.value.len + 3usize
        m += 1usize
    }
    if n == 0usize { ret ("", ok) }
    let (buffer, buffer_error) = mem.alloc[u8](a, size + 1usize)
    if buffer_error != ok { ret ("", buffer_error) }
    var at = 0usize
    m = 0usize
    while m < n {
        let c = jar.cookies[chosen[m]]
        if m > 0usize {
            buffer[at] = 59u8
            buffer[at + 1usize] = 32u8
            at += 2usize
        }
        var j = 0usize
        while j < c.name.len {
            buffer[at + j] = c.name[j]
            j += 1usize
        }
        at += c.name.len
        buffer[at] = 61u8
        at += 1usize
        j = 0usize
        while j < c.value.len {
            buffer[at + j] = c.value[j]
            j += 1usize
        }
        at += c.value.len
        m += 1usize
    }
    ret (buffer[0usize..at], ok)
}
