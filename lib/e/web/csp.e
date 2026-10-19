// Content Security Policy Level 3 (the parts a browser enforces while it loads and runs a page): the header and `<meta>` syntax
// parsed into policies, the fetch-directive fallback chain (`script-src-elem` -> `script-src` -> `default-src` and so on),
// source expressions matched against a request URL (`'none'`, `'self'`, `*`, scheme sources, host sources with wildcard
// subdomains, ports and paths), inline scripts and styles allowed by nonce or by SHA-256/384/512 hash, `'unsafe-inline'`
// (ignored once a nonce or hash is present, as the specification says), `'unsafe-eval'`, `'strict-dynamic'`, and the
// non-fetch directives that are plain source lists (`base-uri`, `form-action`).
//
// A document may have several policies (several headers, or one header with commas, plus `<meta>`): every enforced policy
// must allow the action. Report-only policies are parsed and kept apart; they never block.
//
// Not here: violation reporting (`report-uri`, `report-to`), `frame-ancestors` and `sandbox` enforcement, trusted types,
// `require-sri-for`, and `strict-dynamic`'s propagation to scripts a trusted script inserts (the caller passes `dynamic`).
use e.bytes
use e.crypto.hash as hash
use e.fmt.url as url
use e.mem
use e.str

type Directive = struct { name: str, values: []str }
type Policy = struct { dirs: []Directive, report_only: bool }
type PolicySet = struct { items: []Policy }

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 || c == 12u8 }

fn lower(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
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

fn starts_with_fold(s: str, prefix: str) -> bool {
    if s.len < prefix.len { ret false }
    ret eq_fold(s[0usize..prefix.len], prefix)
}

// The whitespace-separated tokens of `s`.
fn tokens(a: *mem.Arena, s: str) -> []str {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        while i < s.len && is_space(s[i]) { i += 1usize }
        if i >= s.len { break }
        n += 1usize
        while i < s.len && !is_space(s[i]) { i += 1usize }
    }
    let (out, e) = mem.alloc[str](a, n + 1usize)
    if e != ok { ret zero }
    var k = 0usize
    i = 0usize
    while i < s.len {
        while i < s.len && is_space(s[i]) { i += 1usize }
        if i >= s.len { break }
        let start = i
        while i < s.len && !is_space(s[i]) { i += 1usize }
        out[k] = s[start..i]
        k += 1usize
    }
    ret out[0usize..n]
}

fn count_char(s: str, ch: u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] == ch { n += 1usize }
        i += 1usize
    }
    ret n
}

// One policy: directives separated by `;`, each a name and its values; a repeated name is ignored after the first.
fn parse_policy(a: *mem.Arena, text: str, report_only: bool) -> (Policy, err) {
    let parts = count_char(text, 59u8) + 1usize
    let (dirs, de) = mem.alloc[Directive](a, parts)
    if de != ok { ret (zero, de) }
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == 59u8 {
            let toks = tokens(a, text[start..i])
            start = i + 1usize
            if toks.len > 0usize {
                let name = lower(a, toks[0usize])
                var dup = false
                var k = 0usize
                while k < n {
                    if str.eq(dirs[k].name, name) { dup = true }
                    k += 1usize
                }
                if !dup {
                    dirs[n] = Directive { name: name, values: toks[1usize..toks.len] }
                    n += 1usize
                }
            }
        }
        i += 1usize
    }
    ret (Policy { dirs: dirs[0usize..n], report_only: report_only }, ok)
}

// A header value: policies separated by commas.
fn parse_set(a: *mem.Arena, header: str, report_only: bool) -> (PolicySet, err) {
    let parts = count_char(header, 44u8) + 1usize
    let (items, ie) = mem.alloc[Policy](a, parts)
    if ie != ok { ret (zero, ie) }
    var n = 0usize
    var start = 0usize
    var i = 0usize
    while i <= header.len {
        if i == header.len || header[i] == 44u8 {
            let piece = str.trim(header[start..i])
            start = i + 1usize
            if piece.len > 0usize {
                let (p, pe) = parse_policy(a, piece, report_only)
                if pe != ok { ret (zero, pe) }
                if p.dirs.len > 0usize {
                    items[n] = p
                    n += 1usize
                }
            }
        }
        i += 1usize
    }
    ret (PolicySet { items: items[0usize..n] }, ok)
}

// Policies from `more` appended to `base` (a later header or a `<meta>` adds policies; it never removes one).
fn merge(a: *mem.Arena, base: PolicySet, more: PolicySet) -> PolicySet {
    let (items, e) = mem.alloc[Policy](a, base.items.len + more.items.len + 1usize)
    if e != ok { ret base }
    var n = 0usize
    var i = 0usize
    while i < base.items.len {
        items[n] = base.items[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < more.items.len {
        items[n] = more.items[i]
        n += 1usize
        i += 1usize
    }
    ret PolicySet { items: items[0usize..n] }
}

fn find_dir(p: *const Policy, name: str) -> (Directive, bool) {
    var i = 0usize
    while i < p.dirs.len {
        if str.eq(p.dirs[i].name, name) { ret (p.dirs[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

// The directive that governs `name` in `p` after the fallback chain, if any.
fn effective(p: *const Policy, name: str) -> (Directive, bool) {
    var chain: [4]str = zero
    var n = 0usize
    if str.eq(name, "script-src-elem") || str.eq(name, "script-src-attr") {
        chain[0usize] = name
        chain[1usize] = "script-src"
        chain[2usize] = "default-src"
        n = 3usize
    } else if str.eq(name, "style-src-elem") || str.eq(name, "style-src-attr") {
        chain[0usize] = name
        chain[1usize] = "style-src"
        chain[2usize] = "default-src"
        n = 3usize
    } else if str.eq(name, "worker-src") {
        chain[0usize] = name
        chain[1usize] = "child-src"
        chain[2usize] = "script-src"
        chain[3usize] = "default-src"
        n = 4usize
    } else if str.eq(name, "frame-src") {
        chain[0usize] = name
        chain[1usize] = "child-src"
        chain[2usize] = "default-src"
        n = 3usize
    } else if str.eq(name, "base-uri") || str.eq(name, "form-action") || str.eq(name, "frame-ancestors") {
        chain[0usize] = name
        n = 1usize
    } else {
        chain[0usize] = name
        chain[1usize] = "default-src"
        n = 2usize
    }
    var i = 0usize
    while i < n {
        let (d, found) = find_dir(p, chain[i])
        if found { ret (d, true) }
        i += 1usize
    }
    ret (zero, false)
}

fn has_value(d: Directive, kw: str) -> bool {
    var i = 0usize
    while i < d.values.len {
        if eq_fold(d.values[i], kw) { ret true }
        i += 1usize
    }
    ret false
}

fn is_nonce_or_hash(v: str) -> bool {
    ret starts_with_fold(v, "'nonce-") || starts_with_fold(v, "'sha256-") || starts_with_fold(v, "'sha384-") || starts_with_fold(v, "'sha512-")
}

fn has_nonce_or_hash(d: Directive) -> bool {
    var i = 0usize
    while i < d.values.len {
        if is_nonce_or_hash(d.values[i]) { ret true }
        i += 1usize
    }
    ret false
}

// ---- URL matching ------------------------------------------------------------------------------------------------------

fn port_of(a: *mem.Arena, u: *const url.Url) -> i32 {
    if u.port >= 0i32 { ret u.port }
    ret url.default_port(u.scheme)
}

fn scheme_matches(expr: str, actual: str) -> bool {
    if eq_fold(expr, actual) { ret true }
    if eq_fold(expr, "http") && eq_fold(actual, "https") { ret true }
    if eq_fold(expr, "ws") && (eq_fold(actual, "wss") || eq_fold(actual, "http") || eq_fold(actual, "https")) { ret true }
    if eq_fold(expr, "wss") && eq_fold(actual, "https") { ret true }
    ret false
}

fn is_network_scheme(s: str) -> bool { ret eq_fold(s, "http") || eq_fold(s, "https") || eq_fold(s, "ws") || eq_fold(s, "wss") }

fn parse_decimal(s: str) -> (i32, bool) {
    if s.len == 0usize || s.len > 5usize { ret (0i32, false) }
    var v = 0i32
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret (0i32, false) }
        v = v * 10i32 + i32(s[i] - 48u8)
        i += 1usize
    }
    ret (v, true)
}

fn same_origin(a: *mem.Arena, x: *const url.Url, y: *const url.Url) -> bool {
    if !eq_fold(x.host, y.host) { ret false }
    if eq_fold(x.scheme, y.scheme) && port_of(a, x) == port_of(a, y) { ret true }
    // A page on http may reach the same host over https, and ws over wss, on the scheme's default port.
    if scheme_matches(y.scheme, x.scheme) && port_of(a, x) == url.default_port(x.scheme) && port_of(a, y) == url.default_port(y.scheme) { ret true }
    ret false
}

fn source_matches(a: *mem.Arena, src: str, dest: *const url.Url, page: *const url.Url, redirected: bool) -> bool {
    if src.len == 0usize { ret false }
    if src[0usize] == 39u8 {
        if eq_fold(src, "'self'") { ret same_origin(a, dest, page) }
        ret false
    }
    if str.eq(src, "*") {
        ret is_network_scheme(dest.scheme) || eq_fold(dest.scheme, page.scheme)
    }
    if src[src.len - 1usize] == 58u8 && count_char(src, 47u8) == 0usize && src.len > 1usize {
        ret scheme_matches(src[0usize..src.len - 1usize], dest.scheme)
    }
    // scheme-part "://" host-part [":" port] [path]
    var rest = src
    var expr_scheme = ""
    var has_scheme = false
    let (sc, after, sfound) = str.split_once(rest, "://")
    if sfound {
        expr_scheme = sc
        has_scheme = true
        rest = after
    }
    var path = ""
    var has_path = false
    var hostport = rest
    var slash = 0usize
    while slash < rest.len && rest[slash] != 47u8 { slash += 1usize }
    if slash < rest.len {
        hostport = rest[0usize..slash]
        path = rest[slash..]
        has_path = true
    }
    var host = hostport
    var port = ""
    var has_port = false
    var colon = hostport.len
    while colon > 0usize && hostport[colon - 1usize] != 58u8 { colon -= 1usize }
    if colon > 0usize && hostport[0usize] != 91u8 {
        host = hostport[0usize..colon - 1usize]
        port = hostport[colon..]
        has_port = true
    }
    if host.len == 0usize { ret false }
    if has_scheme {
        if !scheme_matches(expr_scheme, dest.scheme) { ret false }
    } else {
        if !scheme_matches(page.scheme, dest.scheme) && !eq_fold(page.scheme, dest.scheme) { ret false }
    }
    if str.eq(host, "*") {
        // any host
    } else if host[0usize] == 42u8 {
        if host.len < 3usize || host[1usize] != 46u8 { ret false }
        let suffix = host[1usize..]
        if dest.host.len <= suffix.len { ret false }
        if !eq_fold(dest.host[dest.host.len - suffix.len..], suffix) { ret false }
    } else {
        if !eq_fold(host, dest.host) { ret false }
    }
    if has_port {
        if !str.eq(port, "*") {
            let (pv, pgood) = parse_decimal(port)
            if !pgood { ret false }
            let tp = port_of(a, dest)
            if pv != tp && !(pv == 80i32 && tp == 443i32) { ret false }
        }
    } else {
        let tp = port_of(a, dest)
        if tp != url.default_port(dest.scheme) { ret false }
    }
    if has_path && !redirected && path.len > 0usize {
        if path[path.len - 1usize] == 47u8 {
            if dest.path.len < path.len || !str.eq(dest.path[0usize..path.len], path) { ret false }
        } else {
            if !str.eq(dest.path, path) { ret false }
        }
    }
    ret true
}

fn directive_allows_url(a: *mem.Arena, d: Directive, dest: *const url.Url, page: *const url.Url, redirected: bool, strict_dynamic_ok: bool) -> bool {
    if d.values.len == 0usize { ret false }
    if strict_dynamic_ok && has_value(d, "'strict-dynamic'") { ret true }
    var i = 0usize
    while i < d.values.len {
        if source_matches(a, d.values[i], dest, page, redirected) { ret true }
        i += 1usize
    }
    ret false
}

// Whether every enforced policy lets `page` load `dest` for `directive` (`script-src-elem`, `img-src`, `connect-src`, ...).
// `dynamic` is true for a script a trusted script inserted (it passes under `'strict-dynamic'`).
fn url_allowed(a: *mem.Arena, set: PolicySet, directive: str, target_text: str, page_text: str, redirected: bool, dynamic: bool) -> bool {
    let (dest, te) = url.parse(a, target_text, zero, false)
    if te != ok { ret false }
    let (page, pe) = url.parse(a, page_text, zero, false)
    if pe != ok { ret false }
    var i = 0usize
    while i < set.items.len {
        let p = &set.items[i]
        i += 1usize
        if p.report_only { continue }
        let (d, found) = effective(p, directive)
        if !found { continue }
        if !directive_allows_url(a, d, &dest, &page, redirected, dynamic) { ret false }
    }
    ret true
}

// ---- Inline content ----------------------------------------------------------------------------------------------------

fn b64_hash(a: *mem.Arena, algo: str, content: str) -> str {
    var digest: [64]u8 = zero
    var n = 0usize
    if str.eq(algo, "sha256") {
        let h = hash.sha256(content)
        var i = 0usize
        while i < 32usize {
            digest[i] = h[i]
            i += 1usize
        }
        n = 32usize
    } else if str.eq(algo, "sha512") {
        let h5 = hash.sha512(content)
        var j = 0usize
        while j < 64usize {
            digest[j] = h5[j]
            j += 1usize
        }
        n = 64usize
    } else {
        ret ""
    }
    let (buf, e) = mem.alloc[u8](a, 128usize)
    if e != ok { ret "" }
    let (text, ee) = bytes.base64_encode(buf, digest[0usize..n], .Standard, true)
    if ee != ok { ret "" }
    ret text
}

fn inline_ok_for(a: *mem.Arena, d: Directive, nonce: str, content: str, is_script: bool) -> bool {
    var i = 0usize
    while i < d.values.len {
        let v = d.values[i]
        i += 1usize
        if v.len < 3usize || v[0usize] != 39u8 || v[v.len - 1usize] != 39u8 { continue }
        let inner = v[1usize..v.len - 1usize]
        if starts_with_fold(inner, "nonce-") {
            if nonce.len > 0usize && str.eq(inner[6usize..], nonce) { ret true }
        } else if starts_with_fold(inner, "sha256-") {
            if str.eq(inner[7usize..], b64_hash(a, "sha256", content)) { ret true }
        } else if starts_with_fold(inner, "sha512-") {
            if str.eq(inner[7usize..], b64_hash(a, "sha512", content)) { ret true }
        }
    }
    if has_nonce_or_hash(d) { ret false }
    if is_script && has_value(d, "'strict-dynamic'") { ret false }
    ret has_value(d, "'unsafe-inline'")
}

// Whether every enforced policy lets an inline script or style (`directive` is `script-src-elem`, `style-src-elem`,
// `script-src-attr` or `style-src-attr`) with this `nonce` attribute (empty when none) and text content run.
fn inline_allowed(a: *mem.Arena, set: PolicySet, directive: str, nonce: str, content: str) -> bool {
    var is_script = starts_with_fold(directive, "script")
    var i = 0usize
    while i < set.items.len {
        let p = &set.items[i]
        i += 1usize
        if p.report_only { continue }
        let (d, found) = effective(p, directive)
        if !found { continue }
        if !inline_ok_for(a, d, nonce, content, is_script) { ret false }
    }
    ret true
}

// Whether `eval` and `new Function` may run (`'unsafe-eval'` in the governing `script-src`).
fn eval_allowed(set: PolicySet) -> bool {
    var i = 0usize
    while i < set.items.len {
        let p = &set.items[i]
        i += 1usize
        if p.report_only { continue }
        let (d, found) = effective(p, "script-src")
        if !found { continue }
        if !has_value(d, "'unsafe-eval'") { ret false }
    }
    ret true
}

fn has_directive(set: PolicySet, name: str) -> bool {
    var i = 0usize
    while i < set.items.len {
        let (d, found) = find_dir(&set.items[i], name)
        if found && !set.items[i].report_only { ret true }
        i += 1usize
    }
    ret false
}

fn enforced(set: PolicySet) -> bool {
    var i = 0usize
    while i < set.items.len {
        if !set.items[i].report_only { ret true }
        i += 1usize
    }
    ret false
}
