// `e.store` over HTTP: an `HttpStore` speaks a small REST object protocol to a base path --
// `PUT /base/key` stores, `GET` reads (404 is `NotFound`), `HEAD` answers the size in
// Content-Length, `DELETE` removes (404 is fine), and `GET /base/?prefix=P` lists one
// `key<TAB>size` line per object in byte order. Keys are percent-encoded per byte, `/`
// kept. The transport is a function pointer, so a caller can put a TLS client, a proxy or
// a test server behind it; `net_transport` is plain TCP over `e.net.http.request`.
//
// ponytail: one request per call, no connection reuse, no multipart or range reads;
// S3-style signing is a cloud client's job and stays out per the cloud ruling.
use e.mem
use e.net
use e.net.http as http
use e.store
use e.str

type Transport = struct { ctx: *void, send: fn(*void, *mem.Arena, *const http.Request) -> (http.Response, err) }
type HttpStore = struct { transport: Transport, host: str, base: str }
type NetTransport = struct { endpoint: net.Endpoint, limits: http.Limits }

fn net_transport(t: *NetTransport) -> Transport {
    ret Transport { ctx: mem.cast[*void](t), send: net_send }
}

fn net_send(ctx: *void, a: *mem.Arena, req: *const http.Request) -> (http.Response, err) {
    let t = mem.cast[*NetTransport](ctx)
    let (response, e) = http.request(a, t.endpoint, req, t.limits)
    ret (response, e)
}

fn http_store(h: *HttpStore) -> store.Store {
    ret store.Store { ctx: mem.cast[*void](h), put: http_put, get: http_get, stat: http_stat, delete: http_delete, list: http_list }
}

fn is_unreserved(c: u8) -> bool {
    ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 45u8 || c == 46u8 || c == 95u8 || c == 126u8
}

fn push_hex_byte(b: *str.Builder, v: u8) -> err {
    let hi = v >> 4u8
    let lo = v & 15u8
    if hi < 10u8 { try str.push_byte(b, 48u8 + hi) } else { try str.push_byte(b, 55u8 + hi) }
    if lo < 10u8 { try str.push_byte(b, 48u8 + lo) } else { try str.push_byte(b, 55u8 + lo) }
    ret ok
}

// Every byte but A-Z a-z 0-9 `-` `.` `_` `~` and `/` as `%XX` (uppercase hex).
fn push_encoded(b: *str.Builder, s: str) -> err {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if is_unreserved(c) || c == 47u8 {
            try str.push_byte(b, c)
        } else {
            try str.push_byte(b, 37u8)
            try push_hex_byte(b, c)
        }
        i += 1usize
    }
    ret ok
}

fn encoded(a: *mem.Arena, s: str) -> (str, err) {
    let (b0, be) = str.builder(a, s.len * 3usize + 1usize)
    if be != ok { ret ("", be) }
    var b = b0
    try push_encoded(&b, s)
    ret (str.done(&b), ok)
}

// `base` + `/` + the encoded key, plus `?prefix=` and an encoded prefix when `query` is set.
fn target_of(a: *mem.Arena, h: *HttpStore, key: str, listing: bool) -> (str, err) {
    let (b0, be) = str.builder(a, h.base.len + key.len * 3usize + 16usize)
    if be != ok { ret ("", be) }
    var b = b0
    try str.push(&b, h.base)
    try str.push_byte(&b, 47u8)
    if listing {
        try str.push(&b, "?prefix=")
        try push_encoded(&b, key)
    } else {
        try push_encoded(&b, key)
    }
    ret (str.done(&b), ok)
}

fn send(h: *HttpStore, a: *mem.Arena, method: http.Method, path_text: str, body: []const u8) -> (http.Response, err) {
    let (headers, he) = mem.alloc[http.Header](a, 1usize)
    if he != ok { ret (zero, he) }
    headers[0] = http.Header{ name: "Host", value: h.host }
    var req: http.Request = zero
    req.method = method
    req.target = path_text
    req.version = .Http11
    req.headers = headers[0usize..1usize]
    req.body = body
    let (response, e) = h.transport.send(h.transport.ctx, a, &req)
    ret (response, e)
}

fn success(status: u16) -> bool { ret status >= 200u16 && status < 300u16 }

fn http_put(ctx: *void, a: *mem.Arena, key: str, data: []const u8) -> err {
    let h = mem.cast[*HttpStore](ctx)
    let (path_text, te) = target_of(a, h, key, false)
    if te != ok { ret te }
    let (r, e) = send(h, a, .Put, path_text, data)
    if e != ok { ret store.Failed }
    if !success(r.status) { ret store.Failed }
    ret ok
}

fn http_get(ctx: *void, a: *mem.Arena, key: str, limit: usize) -> ([]u8, err) {
    let h = mem.cast[*HttpStore](ctx)
    let (path_text, te) = target_of(a, h, key, false)
    if te != ok { ret (zero, te) }
    let (r, e) = send(h, a, .Get, path_text, "")
    if e != ok { ret (zero, store.Failed) }
    if r.status == 404u16 { ret (zero, store.NotFound) }
    if !success(r.status) { ret (zero, store.Failed) }
    if limit != 0usize && r.body.len > limit { ret (zero, store.TooLarge) }
    let (buf, ae) = mem.alloc[u8](a, r.body.len + 1usize)
    if ae != ok { ret (zero, ae) }
    var i = 0usize
    while i < r.body.len {
        buf[i] = r.body[i]
        i += 1usize
    }
    ret (buf[0usize..r.body.len], ok)
}

fn parse_decimal(s: str) -> (u64, bool) {
    if s.len == 0usize { ret (0u64, false) }
    var v = 0u64
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret (0u64, false) }
        v = v * 10u64 + u64(s[i] - 48u8)
        i += 1usize
    }
    ret (v, true)
}

fn http_stat(ctx: *void, a: *mem.Arena, key: str) -> (u64, err) {
    let h = mem.cast[*HttpStore](ctx)
    let (path_text, te) = target_of(a, h, key, false)
    if te != ok { ret (0u64, te) }
    let (r, e) = send(h, a, .Head, path_text, "")
    if e != ok { ret (0u64, store.Failed) }
    if r.status == 404u16 { ret (0u64, store.NotFound) }
    if !success(r.status) { ret (0u64, store.Failed) }
    let (len_text, has) = http.header(r.headers, "Content-Length")
    if !has { ret (0u64, store.Failed) }
    let (size, good) = parse_decimal(len_text)
    if !good { ret (0u64, store.Failed) }
    ret (size, ok)
}

fn http_delete(ctx: *void, a: *mem.Arena, key: str) -> err {
    let h = mem.cast[*HttpStore](ctx)
    let (path_text, te) = target_of(a, h, key, false)
    if te != ok { ret te }
    let (r, e) = send(h, a, .Delete, path_text, "")
    if e != ok { ret store.Failed }
    if r.status == 404u16 || success(r.status) { ret ok }
    ret store.Failed
}

fn http_list(ctx: *void, a: *mem.Arena, prefix: str, out: []store.Entry) -> (usize, err) {
    let h = mem.cast[*HttpStore](ctx)
    let (path_text, te) = target_of(a, h, prefix, true)
    if te != ok { ret (0usize, te) }
    let (r, e) = send(h, a, .Get, path_text, "")
    if e != ok { ret (0usize, store.Failed) }
    if !success(r.status) { ret (0usize, store.Failed) }
    // `key<TAB>size` lines; the body is the arena's, so the keys borrow from it
    var n = 0usize
    var at = 0usize
    let body = r.body
    while at < body.len {
        var end = at
        while end < body.len && body[end] != 10u8 { end += 1usize }
        if end > at {
            var tab = at
            while tab < end && body[tab] != 9u8 { tab += 1usize }
            if tab == end { ret (n, store.Failed) }
            let (size, good) = parse_decimal(body[tab + 1usize..end])
            if !good { ret (n, store.Failed) }
            if n == out.len { ret (n, store.TooLarge) }
            out[n] = store.Entry{ key: body[at..tab], size: size }
            n += 1usize
        }
        at = end + 1usize
    }
    ret (n, ok)
}
