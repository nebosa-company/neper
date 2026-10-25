// A browser-style HTTP(S) client (tracker 4.1, 4.2): `fetch` takes a URL string, method, headers and body, and answers the
// final response after following redirects, with the body already content-decoded. It builds on `e.net.http` (HTTP/1.1,
// TLS 1.3 through `e.net.tls`), `e.fmt.url` (parsing and redirect resolution), `e.net.cookie` (a jar of the client's own),
// and the decoders in `e.fmt` (gzip, deflate, Brotli, zstd).
//
// What it does: refuses the Fetch Standard's blocked ports and non-HTTP schemes (`data:` URLs are answered directly),
// sends Host, User-Agent, Accept, Accept-Language, Accept-Encoding, Referer, Cookie (per `credentials`) and the caller's
// headers; stores `Set-Cookie`; follows 301, 302, 303, 307 and 308 (a POST becomes a GET on 301/302/303 as the Standard
// says, and `Authorization` is dropped when the origin changes) up to `max_redirects`; decodes `Content-Encoding` in
// reverse order with a cap on the decoded size.
//
// What it does not do yet: connection reuse (every request is `Connection: close`), HTTP/2 multiplexing (each request has its own
// h2 connection, chosen by ALPN; a server that does not offer h2 is remembered and spoken to over HTTP/1.1), caching, CORS or CSP (those are
// the request pipeline above it, `e.web`), proxies and authentication challenges.
//
// Memory: everything the response holds lives in the client's arena.

use e.fmt.brotli as brotli
use e.fmt.gzip as gzip
use e.fmt.url as url
use e.fmt.zlib as zlib
use e.fmt.zstd as zstd
use e.fs
use e.io
use e.mem
use e.net
use e.net.cookie as cookie
use e.net.h2client as h2client
use e.net.http as http
use e.net.policy as policy
use e.net.tls
use e.os
use e.str
use e.time

error BadUrl
error BlockedPort
error BlockedByFilter
error CertificateError
error CertificateExpired
error CertificateName
error CertificateUntrusted
error UnsupportedScheme
error TooManyRedirects
error RedirectRefused
error NoAddress
error NetworkError
error BadEncoding
error TooLarge

type Credentials = enum u8 { Omit, SameOrigin, Include }
type Redirect = enum u8 { Follow, Error, Manual }

type Request = struct {
    url: str, method: http.Method, headers: []const http.Header, body: []const u8,
    redirect: Redirect, credentials: Credentials, referrer: str
}

type Response = struct {
    url: str, status: u16, status_text: str, headers: []const http.Header, body: []const u8,
    redirected: bool, redirects: usize
}

// `allow_file` lets `file:` URLs be read from the local disk (for tests and local pages; off by default).
type Config = struct {
    roots: []const u8, user_agent: str, accept_language: str,
    body_limit: usize, max_redirects: usize, allow_file: bool, block_hosts: []const str, allow_hosts: []const str, third_hosts: []const str
}

type Client = struct { a: *mem.Arena, cfg: Config, jar: cookie.Jar, h1_hosts: [16]str, h1_count: usize, blocked: usize }

fn default_config(roots: []const u8) -> Config {
    ret Config { roots: roots, user_agent: "Mozilla/5.0 (compatible; Neper/1.0)", accept_language: "en-US,en;q=0.9", body_limit: 67108864usize, max_redirects: 20usize, allow_file: false, block_hosts: zero, allow_hosts: zero, third_hosts: zero }
}

// A client with a jar of up to `max_cookies` cookies.
fn client(a: *mem.Arena, cfg: Config, max_cookies: usize) -> (Client, err) {
    let (cookies, ce) = mem.alloc[cookie.Cookie](a, max_cookies)
    if ce != ok { ret (zero, ce) }
    let (text, te) = mem.alloc[u8](a, max_cookies * 256usize)
    if te != ok { ret (zero, te) }
    ret (Client { a: a, cfg: cfg, jar: cookie.jar_new(cookies, text), h1_hosts: zero, h1_count: 0usize, blocked: 0usize }, ok)
}

fn unix_seconds() -> i64 {
    let (t, e) = time.now()
    if e != ok { ret 0i64 }
    ret t.nanos / 1000000000i64
}

fn lower_byte(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn eq_fold(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if lower_byte(x[i]) != lower_byte(y[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn header_value(headers: []const http.Header, name: str) -> (str, bool) {
    var i = 0usize
    while i < headers.len {
        if eq_fold(headers[i].name, name) { ret (headers[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

// The ports the Fetch Standard refuses.
fn bad_port(port: i32) -> bool {
    if port < 0i32 { ret false }
    let p = u32(port)
    if p == 1u32 || p == 7u32 || p == 9u32 || p == 11u32 || p == 13u32 || p == 15u32 || p == 17u32 || p == 19u32 || p == 20u32 || p == 21u32 || p == 22u32 || p == 23u32 || p == 25u32 || p == 37u32 || p == 42u32 || p == 43u32 || p == 53u32 { ret true }
    if p == 69u32 || p == 77u32 || p == 79u32 || p == 87u32 || p == 95u32 || p == 101u32 || p == 102u32 || p == 103u32 || p == 104u32 || p == 109u32 || p == 110u32 || p == 111u32 || p == 113u32 || p == 115u32 || p == 117u32 || p == 119u32 || p == 123u32 { ret true }
    if p == 135u32 || p == 137u32 || p == 139u32 || p == 143u32 || p == 161u32 || p == 179u32 || p == 389u32 || p == 427u32 || p == 465u32 || p == 512u32 || p == 513u32 || p == 514u32 || p == 515u32 || p == 526u32 || p == 530u32 || p == 531u32 || p == 532u32 || p == 540u32 { ret true }
    if p == 548u32 || p == 554u32 || p == 556u32 || p == 563u32 || p == 587u32 || p == 601u32 || p == 636u32 || p == 989u32 || p == 990u32 || p == 993u32 || p == 995u32 || p == 1719u32 || p == 1720u32 || p == 1723u32 || p == 2049u32 || p == 3659u32 || p == 4045u32 || p == 4190u32 { ret true }
    if p == 5060u32 || p == 5061u32 || p == 6000u32 || p == 6566u32 || (p >= 6665u32 && p <= 6669u32) || p == 6679u32 || p == 6697u32 || p == 10080u32 { ret true }
    ret false
}

// --- data: URLs (RFC 2397 as the Fetch Standard reads them).

fn hex_val(c: u8) -> u32 {
    if c >= 48u8 && c <= 57u8 { ret u32(c) - 48u32 }
    if c >= 97u8 && c <= 102u8 { ret u32(c) - 87u32 }
    if c >= 65u8 && c <= 70u8 { ret u32(c) - 55u32 }
    ret 99u32
}

fn pct_decode(a: *mem.Arena, s: str) -> []u8 {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret zero }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] == 37u8 && i + 2usize < s.len + 0usize && hex_val(s[i + 1usize]) < 16u32 && hex_val(s[i + 2usize]) < 16u32 {
            out[n] = u8(hex_val(s[i + 1usize]) * 16u32 + hex_val(s[i + 2usize]))
            i += 3usize
        } else {
            out[n] = s[i]
            i += 1usize
        }
        n += 1usize
    }
    ret out[0usize..n]
}

fn b64_val(c: u8) -> u32 {
    if c >= 65u8 && c <= 90u8 { ret u32(c) - 65u32 }
    if c >= 97u8 && c <= 122u8 { ret u32(c) - 71u32 }
    if c >= 48u8 && c <= 57u8 { ret u32(c) + 4u32 }
    if c == 43u8 || c == 45u8 { ret 62u32 }
    if c == 47u8 || c == 95u8 { ret 63u32 }
    ret 99u32
}

fn b64_decode(a: *mem.Arena, s: []const u8) -> ([]u8, bool) {
    let (out, e) = mem.alloc[u8](a, s.len / 4usize * 3usize + 4usize)
    if e != ok { ret (zero, false) }
    var acc = 0u32
    var bits = 0u32
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        i += 1usize
        if c == 61u8 || c == 32u8 || c == 10u8 || c == 13u8 || c == 9u8 { continue }
        let v = b64_val(c)
        if v > 63u32 { ret (zero, false) }
        acc = (acc << 6u32) | v
        bits += 6u32
        if bits >= 8u32 {
            bits -= 8u32
            out[n] = u8((acc >> bits) & 255u32)
            n += 1usize
        }
    }
    ret (out[0usize..n], true)
}

fn data_response(c: *Client, u: *const url.Url, full: str) -> (Response, err) {
    // data:[<mediatype>][;base64],<data>
    let rest = u.path
    var comma = 0usize
    while comma < rest.len && rest[comma] != 44u8 { comma += 1usize }
    if comma >= rest.len { ret (zero, BadUrl) }
    var meta = rest[0usize..comma]
    var payload = rest[comma + 1usize..]
    if u.has_query { payload = rest[comma + 1usize..] }
    var base64 = false
    var i = meta.len
    // A trailing ";base64" (any case) switches the decoder.
    if meta.len >= 7usize && eq_fold(meta[meta.len - 7usize..], ";base64") {
        base64 = true
        meta = meta[0usize..meta.len - 7usize]
    }
    i = 0usize
    var mime = "text/plain;charset=US-ASCII"
    if meta.len > 0usize {
        let m = str.trim(meta)
        if m.len > 0usize && m[0usize] == 59u8 {
            let (joined, je) = str.concat(c.a, "text/plain", m)
            if je == ok { mime = joined }
        } else if m.len > 0usize {
            mime = m
        }
    }
    var body: []const u8 = zero
    var full_payload = payload
    if u.has_query {
        let (q, qe) = str.concat(c.a, "?", u.query)
        if qe == ok {
            let (pq, pe) = str.concat(c.a, payload, q)
            if pe == ok { full_payload = pq }
        }
    }
    let raw = pct_decode(c.a, full_payload)
    if base64 {
        let (decoded, good) = b64_decode(c.a, raw)
        if !good { ret (zero, BadUrl) }
        body = decoded
    } else {
        body = raw
    }
    let (hs, he) = mem.alloc[http.Header](c.a, 1usize)
    if he != ok { ret (zero, he) }
    hs[0usize] = http.Header { name: "Content-Type", value: mime }
    ret (Response { url: full, status: 200u16, status_text: "OK", headers: hs[0usize..1usize], body: body, redirected: false, redirects: 0usize }, ok)
}

// --- file: URLs.

fn mime_of_extension(path: str) -> str {
    var dot = path.len
    while dot > 0usize && path[dot - 1usize] != 46u8 && path[dot - 1usize] != 47u8 { dot -= 1usize }
    if dot == 0usize || path[dot - 1usize] != 46u8 { ret "application/octet-stream" }
    let ext = path[dot..]
    if eq_fold(ext, "html") || eq_fold(ext, "htm") { ret "text/html" }
    if eq_fold(ext, "xht") || eq_fold(ext, "xhtml") { ret "application/xhtml+xml" }
    if eq_fold(ext, "css") { ret "text/css" }
    if eq_fold(ext, "js") { ret "text/javascript" }
    if eq_fold(ext, "json") { ret "application/json" }
    if eq_fold(ext, "txt") { ret "text/plain" }
    if eq_fold(ext, "png") { ret "image/png" }
    if eq_fold(ext, "jpg") || eq_fold(ext, "jpeg") { ret "image/jpeg" }
    if eq_fold(ext, "gif") { ret "image/gif" }
    if eq_fold(ext, "webp") { ret "image/webp" }
    if eq_fold(ext, "svg") { ret "image/svg+xml" }
    if eq_fold(ext, "ttf") { ret "font/ttf" }
    if eq_fold(ext, "woff") { ret "font/woff" }
    if eq_fold(ext, "woff2") { ret "font/woff2" }
    ret "application/octet-stream"
}

// The local file a `file:` URL names, read whole (the path is percent-decoded; `/C:/x` becomes `C:/x`).
fn file_response(c: *Client, u: *const url.Url) -> (Response, err) {
    if !c.cfg.allow_file { ret (zero, UnsupportedScheme) }
    let decoded = pct_decode(c.a, u.path)
    var from = 0usize
    if decoded.len >= 3usize && decoded[0usize] == 47u8 && decoded[2usize] == 58u8 { from = 1usize }
    let path = decoded[from..]
    let (bytes, re) = fs.read_file(c.a, path, c.cfg.body_limit)
    if re != ok {
        let (none, he) = mem.alloc[http.Header](c.a, 1usize)
        if he != ok { ret (zero, he) }
        none[0usize] = http.Header { name: "Content-Type", value: "text/plain" }
        ret (Response { url: url.href(c.a, u, true), status: 404u16, status_text: "Not Found", headers: none[0usize..1usize], body: "", redirected: false, redirects: 0usize }, ok)
    }
    let (hs, hse) = mem.alloc[http.Header](c.a, 1usize)
    if hse != ok { ret (zero, hse) }
    hs[0usize] = http.Header { name: "Content-Type", value: mime_of_extension(path) }
    ret (Response { url: url.href(c.a, u, true), status: 200u16, status_text: "OK", headers: hs[0usize..1usize], body: bytes, redirected: false, redirects: 0usize }, ok)
}

// --- Content decoding.

fn grow_copy(a: *mem.Arena, old: []u8, used: usize, want: usize) -> []u8 {
    let (n, e) = mem.alloc[u8](a, want)
    if e != ok { ret zero }
    var i = 0usize
    while i < used {
        n[i] = old[i]
        i += 1usize
    }
    ret n
}

fn inflate_with(a: *mem.Arena, body: []const u8, limit: usize, kind: u8) -> ([]const u8, err) {
    var st = io.SliceReader { data: body, off: 0usize }
    let src = io.slice_reader(&st)
    let (storage, se) = mem.alloc[u8](a, 400000usize)
    if se != ok { ret (zero, se) }
    var out_cap = body.len * 4usize + 4096usize
    if out_cap > limit { out_cap = limit }
    var out = grow_copy(a, zero, 0usize, out_cap)
    var used = 0usize
    if kind == 0u8 {
        let (rd, re) = gzip.reader(storage, src, u64(limit))
        if re != ok { ret (zero, BadEncoding) }
        var r = rd
        while true {
            if used == out.len {
                if out.len >= limit { ret (zero, TooLarge) }
                var bigger = out.len * 2usize
                if bigger > limit { bigger = limit }
                out = grow_copy(a, out, used, bigger)
            }
            let (n, rerr) = gzip.read(&r, out[used..])
            if rerr == io.End { break }
            if rerr != ok { ret (zero, BadEncoding) }
            if n == 0usize { break }
            used += n
        }
    } else {
        let (rd2, re2) = zlib.reader(storage, src, u64(limit))
        if re2 != ok { ret (zero, BadEncoding) }
        var r2 = rd2
        while true {
            if used == out.len {
                if out.len >= limit { ret (zero, TooLarge) }
                var bigger2 = out.len * 2usize
                if bigger2 > limit { bigger2 = limit }
                out = grow_copy(a, out, used, bigger2)
            }
            let (n2, rerr2) = zlib.read(&r2, out[used..])
            if rerr2 == io.End { break }
            if rerr2 != ok { ret (zero, BadEncoding) }
            if n2 == 0usize { break }
            used += n2
        }
    }
    ret (out[0usize..used], ok)
}

fn brotli_decode(a: *mem.Arena, body: []const u8, limit: usize) -> ([]const u8, err) {
    let (scratch, se) = mem.alloc[u8](a, brotli.decode_scratch_required())
    if se != ok { ret (zero, se) }
    var cap = body.len * 8usize + 65536usize
    while true {
        if cap > limit { cap = limit }
        let (dst, de) = mem.alloc[u8](a, cap)
        if de != ok { ret (zero, de) }
        let (n, be) = brotli.decode(body, dst, scratch)
        if be == ok { ret (dst[0usize..n], ok) }
        if be != brotli.TooSmall || cap >= limit { ret (zero, BadEncoding) }
        cap = cap * 2usize
    }
    ret (zero, BadEncoding)
}

// Undoes `Content-Encoding` (a comma list, applied in that order) on a body.
fn decode_content(a: *mem.Arena, encodings: str, body_in: []const u8, limit: usize) -> ([]const u8, err) {
    var body = body_in
    // Walk the list from the last coding to the first.
    var end = encodings.len
    while end > 0usize {
        var start = end
        while start > 0usize && encodings[start - 1usize] != 44u8 { start -= 1usize }
        let name = str.trim(encodings[start..end])
        end = start
        if end > 0usize { end -= 1usize }
        if name.len == 0usize || eq_fold(name, "identity") { continue }
        if eq_fold(name, "gzip") || eq_fold(name, "x-gzip") {
            let (d, e) = inflate_with(a, body, limit, 0u8)
            if e != ok { ret (zero, e) }
            body = d
        } else if eq_fold(name, "deflate") {
            let (d2, e2) = inflate_with(a, body, limit, 1u8)
            if e2 != ok { ret (zero, e2) }
            body = d2
        } else if eq_fold(name, "br") {
            let (d3, e3) = brotli_decode(a, body, limit)
            if e3 != ok { ret (zero, e3) }
            body = d3
        } else if eq_fold(name, "zstd") {
            let (d4, e4) = zstd.decode(a, body, u64(limit))
            if e4 != ok { ret (zero, BadEncoding) }
            body = d4
        } else {
            ret (zero, BadEncoding)
        }
    }
    ret (body, ok)
}

// --- The request.

fn is_redirect_status(s: u16) -> bool { ret s == 301u16 || s == 302u16 || s == 303u16 || s == 307u16 || s == 308u16 }

fn host_header(a: *mem.Arena, u: *const url.Url) -> str {
    ret url.host_port(a, u)
}

fn path_and_query(a: *mem.Arena, u: *const url.Url) -> str {
    var path = u.path
    if path.len == 0usize { path = "/" }
    if !u.has_query { ret path }
    let (p, pe) = str.concat(a, path, "?")
    if pe != ok { ret path }
    let (q, qe) = str.concat(a, p, u.query)
    if qe != ok { ret path }
    ret q
}

fn same_origin(a: *mem.Arena, x: *const url.Url, y: *const url.Url) -> bool {
    ret str.eq(url.origin(a, x), url.origin(a, y))
}

fn known_h1(c: *Client, host: str) -> bool {
    var i = 0usize
    while i < c.h1_count {
        if str.eq(c.h1_hosts[i], host) { ret true }
        i += 1usize
    }
    ret false
}

fn remember_h1(c: *Client, host: str) {
    if c.h1_count < 16usize {
        c.h1_hosts[c.h1_count] = host
        c.h1_count += 1usize
    }
}

// One exchange with the server for `u` (no redirects): the raw response.
fn exchange(c: *Client, u: *const url.Url, method: http.Method, headers: []const http.Header, body: []const u8) -> (http.Response, err) {
    var port = u.port
    if port < 0i32 {
        if str.eq(u.scheme, "https") { port = 443i32 } else { port = 80i32 }
    }
    let host_text = u.host
    var bare = host_text
    if bare.len > 1usize && bare[0usize] == 91u8 { bare = bare[1usize..bare.len - 1usize] }
    let (eps, ne) = net.resolve(c.a, bare, u16(port), net.Family.Any)
    if ne != ok || eps.len == 0usize { ret (zero, NoAddress) }
    let req = http.Request { method: method, target: path_and_query(c.a, u), version: http.Version.Http11, headers: headers, body: body }
    let limits = http.Limits { start_line: 16384usize, header_bytes: 262144usize, header_count: 256usize, body_bytes: c.cfg.body_limit }
    var last = NetworkError
    var i = 0usize
    while i < eps.len {
        if str.eq(u.scheme, "https") {
            let (entropy, ee) = mem.alloc[u8](c.a, 64usize)
            if ee != ok { ret (zero, ee) }
            if os.random(entropy) != ok { ret (zero, NetworkError) }
            let (now, te) = time.now()
            if te != ok { ret (zero, te) }
            let (none, me) = mem.alloc[str](c.a, 1usize)
            if me != ok { ret (zero, me) }
            var try_h2 = !known_h1(c, bare)
            if try_h2 {
                let (protos, pre) = mem.alloc[str](c.a, 2usize)
                if pre != ok { ret (zero, pre) }
                protos[0usize] = "h2"
                protos[1usize] = "http/1.1"
                let cfg2 = tls.ClientConfig { server_name: bare, trust_roots: c.cfg.roots, alpn: protos[0usize..2usize], entropy: entropy, now: now }
                let (resp2, re2) = h2client.request(c.a, eps[i], cfg2, http.method_text(method), host_header(c.a, u), path_and_query(c.a, u), headers, body, c.cfg.body_limit)
                if re2 == ok { ret (resp2, ok) }
                if re2 == tls.InvalidCertificate { ret (zero, CertificateError) }
                if re2 == tls.CertificateExpired { ret (zero, CertificateExpired) }
                if re2 == tls.CertificateName { ret (zero, CertificateName) }
                if re2 == tls.CertificateUntrusted { ret (zero, CertificateUntrusted) }
                if re2 == h2client.NotH2 { remember_h1(c, bare) }
                try_h2 = false
            }
            let cfg = tls.ClientConfig { server_name: bare, trust_roots: c.cfg.roots, alpn: none[0usize..0usize], entropy: entropy, now: now }
            let (resp, re) = http.request_tls(c.a, eps[i], cfg, &req, limits)
            if re == ok { ret (resp, ok) }
            if re == tls.InvalidCertificate { ret (zero, CertificateError) }
            if re == tls.CertificateExpired { ret (zero, CertificateExpired) }
            if re == tls.CertificateName { ret (zero, CertificateName) }
            if re == tls.CertificateUntrusted { ret (zero, CertificateUntrusted) }
        } else {
            let (resp2, re2) = http.request(c.a, eps[i], &req, limits)
            if re2 == ok { ret (resp2, ok) }
        }
        i += 1usize
    }
    ret (zero, last)
}

fn method_after_redirect(status: u16, method: http.Method) -> http.Method {
    if status == 303u16 && method != http.Method.Head { ret http.Method.Get }
    if (status == 301u16 || status == 302u16) && method == http.Method.Post { ret http.Method.Get }
    ret method
}

// Fetches `req.url`. `Manual` redirects and `Error` are honoured; the cookie jar and `Referer` follow `req`.
fn fetch(c: *Client, req: Request) -> (Response, err) {
    var current_text = req.url
    var method = req.method
    var body = req.body
    var redirects = 0usize
    let empty_body: []const u8 = zero
    let (cur0, ce0) = url.parse(c.a, current_text, zero, false)
    if ce0 != ok { ret (zero, BadUrl) }
    var cur = cur0
    var origin_url = cur0
    while true {
        if str.eq(cur.scheme, "data") {
            let (dr, de) = data_response(c, &cur, url.href(c.a, &cur, true))
            ret (dr, de)
        }
        if str.eq(cur.scheme, "file") {
            let (fr, fe) = file_response(c, &cur)
            ret (fr, fe)
        }
        if !str.eq(cur.scheme, "http") && !str.eq(cur.scheme, "https") { ret (zero, UnsupportedScheme) }
        if bad_port(cur.port) { ret (zero, BlockedPort) }
        // A subresource (it has a referrer) whose host a filter list names is never requested; the document itself is not filtered.
        if req.referrer.len > 0usize && !policy.host_blocked(c.cfg.allow_hosts, cur.host) {
            var hit = policy.host_blocked(c.cfg.block_hosts, cur.host)
            if hit && c.cfg.third_hosts.len > 0usize && policy.host_blocked(c.cfg.third_hosts, cur.host) {
                let (rurl, re) = url.parse(c.a, req.referrer, zero, false)
                hit = re != ok || !policy.same_party(rurl.host, cur.host)
            }
            if hit {
                c.blocked += 1usize
                ret (zero, BlockedByFilter)
            }
        }
        // Request headers.
        let (hm, hme) = list_of_headers(c.a, 12usize + req.headers.len)
        if hme != ok { ret (zero, hme) }
        var hs = hm
        push_header(&hs, "Host", host_header(c.a, &cur))
        var has_ua = false
        var has_accept = false
        var has_lang = false
        var has_enc = false
        var hi = 0usize
        while hi < req.headers.len {
            if eq_fold(req.headers[hi].name, "user-agent") { has_ua = true }
            if eq_fold(req.headers[hi].name, "accept") { has_accept = true }
            if eq_fold(req.headers[hi].name, "accept-language") { has_lang = true }
            if eq_fold(req.headers[hi].name, "accept-encoding") { has_enc = true }
            // Credentials and host-specific headers do not follow a cross-origin redirect.
            var drop = false
            if eq_fold(req.headers[hi].name, "host") { drop = true }
            if eq_fold(req.headers[hi].name, "authorization") && !same_origin(c.a, &cur, &origin_url) { drop = true }
            if !drop { push_header(&hs, req.headers[hi].name, req.headers[hi].value) }
            hi += 1usize
        }
        if !has_ua { push_header(&hs, "User-Agent", c.cfg.user_agent) }
        if !has_accept { push_header(&hs, "Accept", "*/*") }
        if !has_lang { push_header(&hs, "Accept-Language", c.cfg.accept_language) }
        if !has_enc { push_header(&hs, "Accept-Encoding", "gzip, deflate, br, zstd") }
        push_header(&hs, "Connection", "close")
        if req.referrer.len > 0usize { push_header(&hs, "Referer", req.referrer) }
        var send_cookies = req.credentials == Credentials.Include || (req.credentials == Credentials.SameOrigin && same_origin(c.a, &cur, &origin_url))
        if send_cookies {
            let (cookie_line, ce) = cookie.header(c.a, &c.jar, cur.host, cur.path, str.eq(cur.scheme, "https"), unix_seconds())
            if ce == ok && cookie_line.len > 0usize { push_header(&hs, "Cookie", cookie_line) }
        }
        if body.len > 0usize || method == http.Method.Post || method == http.Method.Put {
            push_header(&hs, "Content-Length", decimal(c.a, body.len))
        }
        let (resp, ee) = exchange(c, &cur, method, hs.items[0usize..hs.len], body)
        if ee != ok { ret (zero, ee) }
        // Cookies.
        if req.credentials != Credentials.Omit {
            var k = 0usize
            while k < resp.headers.len {
                if eq_fold(resp.headers[k].name, "set-cookie") {
                    let (ck, pe) = cookie.parse(c.a, resp.headers[k].value, cur.host, cur.path, str.eq(cur.scheme, "https"), unix_seconds())
                    if pe == ok {
                        let stored = cookie.store(&c.jar, ck, unix_seconds())
                    }
                }
                k += 1usize
            }
        }
        // Redirects.
        let (location, has_location) = header_value(resp.headers, "location")
        if is_redirect_status(resp.status) && has_location && req.redirect != Redirect.Manual {
            if req.redirect == Redirect.Error { ret (zero, RedirectRefused) }
            if redirects >= c.cfg.max_redirects { ret (zero, TooManyRedirects) }
            let (next, ne) = url.parse(c.a, location, &cur, true)
            if ne != ok { ret (zero, BadUrl) }
            method = method_after_redirect(resp.status, method)
            if method == http.Method.Get || method == http.Method.Head {
                if resp.status == 303u16 || resp.status == 301u16 || resp.status == 302u16 { body = empty_body }
            }
            cur = next
            redirects += 1usize
            continue
        }
        // The final response, content-decoded.
        var final_body = resp.body
        var out_headers = resp.headers
        let (encoding, has_encoding) = header_value(resp.headers, "content-encoding")
        if has_encoding && resp.body.len > 0usize {
            let (decoded, de) = decode_content(c.a, encoding, resp.body, c.cfg.body_limit)
            if de != ok { ret (zero, de) }
            final_body = decoded
        }
        ret (Response { url: url.href(c.a, &cur, true), status: resp.status, status_text: resp.reason, headers: out_headers, body: final_body, redirected: redirects > 0usize, redirects: redirects }, ok)
    }
    ret (zero, NetworkError)
}

// --- Small helpers.

fn list_of_headers(a: *mem.Arena, cap: usize) -> (HeaderList, err) {
    let (items, e) = mem.alloc[http.Header](a, cap)
    if e != ok { ret (zero, e) }
    ret (HeaderList { items: items, len: 0usize }, ok)
}

type HeaderList = struct { items: []http.Header, len: usize }

fn push_header(l: *HeaderList, name: str, value: str) {
    if l.len < l.items.len {
        l.items[l.len] = http.Header { name: name, value: value }
        l.len += 1usize
    }
}

fn decimal(a: *mem.Arena, n: usize) -> str {
    let (out, e) = mem.alloc[u8](a, 24usize)
    if e != ok { ret "0" }
    var digits: [24]u8 = zero
    var k = 0usize
    var v = n
    if v == 0usize {
        digits[0usize] = 48u8
        k = 1usize
    }
    while v > 0usize {
        digits[k] = u8(48usize + v % 10usize)
        v = v / 10usize
        k += 1usize
    }
    var j = 0usize
    while j < k {
        out[j] = digits[k - 1usize - j]
        j += 1usize
    }
    ret out[0usize..k]
}

// The media type (lower case, without parameters) of a response's Content-Type.
fn mime_type(a: *mem.Arena, r: *const Response) -> str {
    let (ct, has) = header_value(r.headers, "content-type")
    if !has { ret "" }
    var end = 0usize
    while end < ct.len && ct[end] != 59u8 { end += 1usize }
    let t = str.trim(ct[0usize..end])
    let (out, e) = mem.alloc[u8](a, t.len + 1usize)
    if e != ok { ret t }
    var i = 0usize
    while i < t.len {
        out[i] = lower_byte(t[i])
        i += 1usize
    }
    ret out[0usize..t.len]
}

// The `charset` parameter of a response's Content-Type ("" when there is none).
fn charset_param(r: *const Response) -> str {
    let (ct, has) = header_value(r.headers, "content-type")
    if !has { ret "" }
    var i = 0usize
    while i + 7usize <= ct.len {
        if eq_fold(ct[i..i + 7usize], "charset") {
            var p = i + 7usize
            while p < ct.len && (ct[p] == 32u8 || ct[p] == 9u8) { p += 1usize }
            if p < ct.len && ct[p] == 61u8 {
                p += 1usize
                while p < ct.len && (ct[p] == 32u8 || ct[p] == 9u8) { p += 1usize }
                var q = p
                if q < ct.len && (ct[q] == 34u8 || ct[q] == 39u8) {
                    let quote = ct[q]
                    q += 1usize
                    var e = q
                    while e < ct.len && ct[e] != quote { e += 1usize }
                    ret ct[q..e]
                }
                var e2 = q
                while e2 < ct.len && ct[e2] != 59u8 && ct[e2] != 32u8 { e2 += 1usize }
                ret ct[q..e2]
            }
        }
        i += 1usize
    }
    ret ""
}
