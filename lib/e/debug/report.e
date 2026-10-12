// A crash and error report upload client (L149) speaking the Sentry envelope protocol over
// `e.net.http`: DSN parsing, event JSON, envelope framing, the `X-Sentry-Auth` header, rate-limit
// parsing, and a bounded offline queue with a flush that decides per response what happens to an
// envelope. There is no hub, no integration and no performance monitoring: vendor APM SDKs stay
// hand-built, and the server side (the store that receives these) is the application's.
//
// DSN: `{scheme}://{public_key}[:{secret_key}]@{host}[:{port}]/[{path}/]{project_id}`; the port
// defaults to 80 or 443 by scheme; the envelope endpoint is `{path}/api/{project_id}/envelope/`.
// An envelope is `{headers}\n` then, per item, `{item headers}\n{payload}\n`, every header a
// compact JSON object in a fixed key order with `length` last (an event's item headers are
// `type`, `content_type`, `length`; an attachment's are `filename`, `content_type`, `type`,
// `length`, as sentry-sdk writes them). JSON text is written as UTF-8, not `\u`-escaped: the same
// document, different bytes for non-ASCII text.
//
// Delivery: `capture` serializes and queues; nothing touches the network until `flush`. The
// queue holds `max_items` envelopes and `max_bytes` bytes and drops the oldest to fit (counted in
// `dropped`). A flush sends oldest first, at most `max_send` per call: 2xx removes the envelope; 429 or
// any `X-Sentry-Rate-Limits` limit naming `error` (or every category) pauses sends until its
// deadline and keeps the envelope; another 4xx drops it as rejected; a 5xx or a transport
// failure keeps it, stops the flush and backs the next attempt off 1 s, 2 s, 4 s ... up to 60 s.
// The offline queue persists through an `e.store` key. Time is the caller's clock: every
// operation that needs it takes `now` in nanoseconds.
//
// Not here: sessions, transactions, breadcrumbs, a hub with scopes, TLS-less `https` (a DSN with
// `https` is parsed, and sent through the `Transport` the caller supplies; `tls_transport`
// wraps `http.request_tls`), compression, and symbolication (frames carry what `e.debug`
// reported).

use e.debug
use e.mem
use e.net
use e.net.http as http
use e.net.tls as tls
use e.store
use e.str
use e.time

const MAX_HEADERS: usize = 4usize
const SECOND_NS: i64 = 1000000000i64
const MAX_BACKOFF_S: i64 = 60i64

type Dsn = struct { scheme: str, public_key: str, secret_key: str, host: str, port: u16, path: str, project_id: str }
type Tag = struct { key: str, value: str }
type Event = struct { id: str, timestamp: i64, level: str, message: str, err_type: str, err_value: str, frames: []const debug.Frame, release: str, environment: str, tags: []const Tag }
type Item = struct { kind: str, content_type: str, filename: str, payload: str }
type Limit = struct { category: str, until: i64 }
type Transport = struct { ctx: *void, send: fn(*void, *mem.Arena, *const http.Request) -> (http.Response, err) }
type NetTransport = struct { endpoint: net.Endpoint, limits: http.Limits }
type TlsTransport = struct { endpoint: net.Endpoint, config: tls.ClientConfig, limits: http.Limits }
type Client = struct { dsn: Dsn, a: *mem.Arena, transport: Transport, name: str, queue: []str, count: usize, bytes: usize, max_items: usize, max_bytes: usize, dropped: usize, rejected: usize, sent: usize, failures: u32, retry_at: i64, limited_until: i64 }

error Invalid
error TooLarge
error Corrupt

// ---- DSN ----------------------------------------------------------------------------------

fn find_byte(s: str, from: usize, c: u8) -> usize {
    var i = from
    while i < s.len {
        if s[i] == c { ret i }
        i += 1usize
    }
    ret s.len
}

fn parse_port(s: str) -> (u16, bool) {
    if s.len == 0usize || s.len > 5usize { ret (0u16, false) }
    var v = 0u32
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret (0u16, false) }
        v = v * 10u32 + u32(s[i] - 48u8)
        i += 1usize
    }
    if v == 0u32 || v > 65535u32 { ret (0u16, false) }
    ret (u16(v), true)
}

// The pieces of a DSN; `Invalid` for a missing scheme, key, host or project id. The path is the
// text between the host and the project id, always ending in `/` ("/" when there is none).
fn parse_dsn(text: str) -> (Dsn, err) {
    var d: Dsn = zero
    let sep = find_byte(text, 0usize, 58u8)
    if sep + 2usize >= text.len || text[sep + 1usize] != 47u8 || text[sep + 2usize] != 47u8 { ret (d, Invalid) }
    d.scheme = text[0..sep]
    if !(str.eq(d.scheme, "http") || str.eq(d.scheme, "https")) { ret (d, Invalid) }
    let rest = text[sep + 3usize..text.len]
    let at = find_byte(rest, 0usize, 64u8)
    if at >= rest.len { ret (d, Invalid) }
    let creds = rest[0..at]
    let colon = find_byte(creds, 0usize, 58u8)
    d.public_key = creds[0..colon]
    if colon < creds.len { d.secret_key = creds[colon + 1usize..creds.len] }
    if d.public_key.len == 0usize { ret (d, Invalid) }
    let location = rest[at + 1usize..rest.len]
    let slash = find_byte(location, 0usize, 47u8)
    if slash >= location.len { ret (d, Invalid) }
    var hostport = location[0..slash]
    let path_and_id = location[slash..location.len]
    let hc = find_byte(hostport, 0usize, 58u8)
    d.host = hostport[0..hc]
    if d.host.len == 0usize { ret (d, Invalid) }
    d.port = 80u16
    if str.eq(d.scheme, "https") { d.port = 443u16 }
    if hc < hostport.len {
        let (p, port_ok) = parse_port(hostport[hc + 1usize..hostport.len])
        if !port_ok { ret (d, Invalid) }
        d.port = p
    }
    // the project id is the last segment, the path everything before it, keeping its slashes
    var last = path_and_id.len
    while last > 0usize && path_and_id[last - 1usize] != 47u8 { last -= 1usize }
    if last == 0usize || last >= path_and_id.len { ret (d, Invalid) }
    d.path = path_and_id[0..last]
    d.project_id = path_and_id[last..path_and_id.len]
    ret (d, ok)
}

// `{path}api/{project_id}/envelope/`.
fn envelope_target(a: *mem.Arena, d: *const Dsn) -> (str, err) {
    let (b0, builder_error) = str.builder(a, 96usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = b0
    var failure = str.push(&b, d.path)
    if failure == ok { failure = str.push(&b, "api/") }
    if failure == ok { failure = str.push(&b, d.project_id) }
    if failure == ok { failure = str.push(&b, "/envelope/") }
    if failure != ok { ret ("", failure) }
    ret (str.done(&b), ok)
}

// The `X-Sentry-Auth` value, in sentry-sdk's order: key, version, client, secret.
fn auth_header(a: *mem.Arena, d: *const Dsn, sdk: str) -> (str, err) {
    let (b0, builder_error) = str.builder(a, 160usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = b0
    var failure = str.push(&b, "Sentry sentry_key=")
    if failure == ok { failure = str.push(&b, d.public_key) }
    if failure == ok { failure = str.push(&b, ", sentry_version=7, sentry_client=") }
    if failure == ok { failure = str.push(&b, sdk) }
    if failure == ok && d.secret_key.len != 0usize {
        failure = str.push(&b, ", sentry_secret=")
        if failure == ok { failure = str.push(&b, d.secret_key) }
    }
    if failure != ok { ret ("", failure) }
    ret (str.done(&b), ok)
}

// ---- JSON and envelopes --------------------------------------------------------------------

fn push_hex2(b: *str.Builder, v: u8) -> err {
    let digits = "0123456789abcdef"
    try str.push_byte(b, digits[usize(v >> 4u8)])
    ret str.push_byte(b, digits[usize(v & 15u8)])
}

// A JSON string literal: `"` `\` and the short escapes, other controls as \u00xx.
fn push_json_string(b: *str.Builder, s: str) -> err {
    try str.push_byte(b, 34u8)
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 34u8 {
            try str.push(b, "\\\"")
        } else {
            if c == 92u8 {
                try str.push(b, "\\\\")
            } else {
                if c == 10u8 {
                    try str.push(b, "\\n")
                } else {
                    if c == 13u8 {
                        try str.push(b, "\\r")
                    } else {
                        if c == 9u8 {
                            try str.push(b, "\\t")
                        } else {
                            if c == 8u8 {
                                try str.push(b, "\\b")
                            } else {
                                if c == 12u8 {
                                    try str.push(b, "\\f")
                                } else {
                                    if c < 32u8 {
                                        try str.push(b, "\\u00")
                                        try push_hex2(b, c)
                                    } else {
                                        try str.push_byte(b, c)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        i += 1usize
    }
    ret str.push_byte(b, 34u8)
}

fn push_key(b: *str.Builder, first: bool, name: str) -> err {
    if !first { try str.push_byte(b, 44u8) }
    try push_json_string(b, name)
    ret str.push_byte(b, 58u8)
}

fn push_timestamp(b: *str.Builder, nanos: i64) -> err {
    var buf: [40]u8 = zero
    let text = time.format_iso8601(time.Timestamp { nanos: nanos }, buf[0..])
    ret push_json_string(b, text)
}

fn push_frame(b: *str.Builder, f: debug.Frame) -> err {
    try str.push_byte(b, 123u8)
    var first = true
    if f.function.len != 0usize {
        try push_key(b, first, "function")
        try push_json_string(b, f.function)
        first = false
    }
    if f.file.len != 0usize {
        try push_key(b, first, "filename")
        try push_json_string(b, f.file)
        first = false
    }
    if f.line != 0u32 {
        try push_key(b, first, "lineno")
        try str.push_u32(b, f.line)
        first = false
    }
    if f.address != 0usize {
        try push_key(b, first, "instruction_addr")
        try str.push_byte(b, 34u8)
        try str.push(b, "0x")
        try str.push_hex_u64(b, u64(f.address))
        try str.push_byte(b, 34u8)
        first = false
    }
    ret str.push_byte(b, 125u8)
}

// The event as compact JSON in a fixed key order: `event_id`, `timestamp`, `platform`, `level`,
// `message`, `exception`, `release`, `environment`, `tags`. Frames are given innermost first (as
// `e.debug.backtrace` answers them) and written oldest first, as the protocol wants.
fn event_json(a: *mem.Arena, ev: *const Event) -> (str, err) {
    if ev.id.len != 32usize || ev.level.len == 0usize { ret ("", Invalid) }
    let (b0, builder_error) = str.builder(a, 512usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = b0
    var failure = write_event(&b, ev)
    if failure != ok { ret ("", failure) }
    ret (str.done(&b), ok)
}

fn write_event(b: *str.Builder, ev: *const Event) -> err {
    try str.push_byte(b, 123u8)
    try push_key(b, true, "event_id")
    try push_json_string(b, ev.id)
    try push_key(b, false, "timestamp")
    try push_timestamp(b, ev.timestamp)
    try push_key(b, false, "platform")
    try push_json_string(b, "native")
    try push_key(b, false, "level")
    try push_json_string(b, ev.level)
    if ev.message.len != 0usize {
        try push_key(b, false, "message")
        try push_json_string(b, ev.message)
    }
    if ev.err_type.len != 0usize {
        try push_key(b, false, "exception")
        try str.push(b, "{\"values\":[{")
        try push_key(b, true, "type")
        try push_json_string(b, ev.err_type)
        try push_key(b, false, "value")
        try push_json_string(b, ev.err_value)
        if ev.frames.len != 0usize {
            try push_key(b, false, "stacktrace")
            try str.push(b, "{\"frames\":[")
            var i = ev.frames.len
            var first = true
            while i > 0usize {
                i -= 1usize
                if !first { try str.push_byte(b, 44u8) }
                try push_frame(b, ev.frames[i])
                first = false
            }
            try str.push(b, "]}")
        }
        try str.push(b, "}]}")
    }
    if ev.release.len != 0usize {
        try push_key(b, false, "release")
        try push_json_string(b, ev.release)
    }
    if ev.environment.len != 0usize {
        try push_key(b, false, "environment")
        try push_json_string(b, ev.environment)
    }
    if ev.tags.len != 0usize {
        try push_key(b, false, "tags")
        try str.push_byte(b, 123u8)
        var t = 0usize
        while t < ev.tags.len {
            try push_key(b, t == 0usize, ev.tags[t].key)
            try push_json_string(b, ev.tags[t].value)
            t += 1usize
        }
        try str.push_byte(b, 125u8)
    }
    ret str.push_byte(b, 125u8)
}

// An event item.
fn event_item(a: *mem.Arena, ev: *const Event) -> (Item, err) {
    let (payload, json_error) = event_json(a, ev)
    if json_error != ok { ret (zero, json_error) }
    ret (Item { kind: "event", content_type: "application/json", filename: "", payload: payload }, ok)
}

fn push_item(b: *str.Builder, it: Item) -> err {
    try str.push_byte(b, 123u8)
    if str.eq(it.kind, "attachment") {
        try push_key(b, true, "filename")
        try push_json_string(b, it.filename)
        try push_key(b, false, "content_type")
        try push_json_string(b, it.content_type)
        try push_key(b, false, "type")
        try push_json_string(b, it.kind)
    } else {
        try push_key(b, true, "type")
        try push_json_string(b, it.kind)
        try push_key(b, false, "content_type")
        try push_json_string(b, it.content_type)
    }
    try push_key(b, false, "length")
    try str.push_usize(b, it.payload.len)
    try str.push(b, "}\n")
    try str.push(b, it.payload)
    ret str.push_byte(b, 10u8)
}

// The envelope bytes: headers (`event_id`, `sent_at`), then each item.
fn envelope(a: *mem.Arena, event_id: str, sent_at: i64, items: []const Item) -> (str, err) {
    if event_id.len != 32usize || items.len == 0usize { ret ("", Invalid) }
    var total = 128usize
    var i = 0usize
    while i < items.len {
        total += items[i].payload.len * 2usize + 160usize
        i += 1usize
    }
    let (b0, builder_error) = str.builder(a, total)
    if builder_error != ok { ret ("", builder_error) }
    var b = b0
    var failure = str.push(&b, "{\"event_id\":")
    if failure == ok { failure = push_json_string(&b, event_id) }
    if failure == ok { failure = str.push(&b, ",\"sent_at\":") }
    if failure == ok { failure = push_timestamp(&b, sent_at) }
    if failure == ok { failure = str.push(&b, "}\n") }
    i = 0usize
    while failure == ok && i < items.len {
        failure = push_item(&b, items[i])
        i += 1usize
    }
    if failure != ok { ret ("", failure) }
    ret (str.done(&b), ok)
}

// ---- rate limits ---------------------------------------------------------------------------

fn trim_space(s: str) -> str {
    var lo = 0usize
    var hi = s.len
    while lo < hi && (s[lo] == 32u8 || s[lo] == 9u8) { lo += 1usize }
    while hi > lo && (s[hi - 1usize] == 32u8 || s[hi - 1usize] == 9u8) { hi -= 1usize }
    ret s[lo..hi]
}

fn parse_seconds(s: str, fallback: i64) -> i64 {
    if s.len == 0usize || s.len > 9usize { ret fallback }
    var v = 0i64
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret fallback }
        v = v * 10i64 + i64(s[i] - 48u8)
        i += 1usize
    }
    ret v
}

// `retry_after:category;category:scope[:reason], ...` into `out`; how many limits. An empty
// category list limits every category (an empty `category`); a group whose retry time is not a
// number is skipped, as sentry-sdk does.
fn parse_rate_limits(header: str, now: i64, out: []Limit) -> usize {
    var n = 0usize
    var at = 0usize
    while at <= header.len {
        let end = find_byte(header, at, 44u8)
        let group = trim_space(header[at..end])
        at = end + 1usize
        if group.len == 0usize { continue }
        let c1 = find_byte(group, 0usize, 58u8)
        let seconds = parse_seconds(trim_space(group[0..c1]), -1i64)
        if seconds < 0i64 { continue }
        var cats = ""
        if c1 < group.len {
            let c2 = find_byte(group, c1 + 1usize, 58u8)
            cats = group[c1 + 1usize..c2]
        }
        let until = now + seconds * SECOND_NS
        if cats.len == 0usize {
            if n < out.len {
                out[n] = Limit { category: "", until: until }
                n += 1usize
            }
        } else {
            var cp = 0usize
            while cp <= cats.len {
                let ce = find_byte(cats, cp, 59u8)
                if n < out.len && ce > cp {
                    out[n] = Limit { category: cats[cp..ce], until: until }
                    n += 1usize
                }
                cp = ce + 1usize
            }
        }
    }
    ret n
}

// ---- transports ---------------------------------------------------------------------------

fn net_send(ctx: *void, a: *mem.Arena, req: *const http.Request) -> (http.Response, err) {
    let t = mem.cast[*NetTransport](ctx)
    let (response, e) = http.request(a, t.endpoint, req, t.limits)
    ret (response, e)
}

fn net_transport(t: *NetTransport) -> Transport {
    ret Transport { ctx: mem.cast[*void](t), send: net_send }
}

fn tls_send(ctx: *void, a: *mem.Arena, req: *const http.Request) -> (http.Response, err) {
    let t = mem.cast[*TlsTransport](ctx)
    let (response, e) = http.request_tls(a, t.endpoint, t.config, req, t.limits)
    ret (response, e)
}

fn tls_transport(t: *TlsTransport) -> Transport {
    ret Transport { ctx: mem.cast[*void](t), send: tls_send }
}

// ---- the client and its queue --------------------------------------------------------------

fn client(a: *mem.Arena, dsn_text: str, transport: Transport, sdk_name: str, max_items: usize, max_bytes: usize) -> (Client, err) {
    var c: Client = zero
    let (dsn, dsn_error) = parse_dsn(dsn_text)
    if dsn_error != ok { ret (c, dsn_error) }
    if max_items == 0usize || max_bytes == 0usize { ret (c, Invalid) }
    let (queue, queue_error) = mem.alloc[str](a, max_items)
    if queue_error != ok { ret (c, queue_error) }
    c.dsn = dsn
    c.a = a
    c.transport = transport
    c.name = sdk_name
    c.queue = queue
    c.max_items = max_items
    c.max_bytes = max_bytes
    ret (c, ok)
}

fn keep(a: *mem.Arena, s: str) -> (str, err) {
    let (buf, alloc_error) = mem.alloc[u8](a, s.len + 1usize)
    if alloc_error != ok { ret ("", alloc_error) }
    var i = 0usize
    while i < s.len {
        buf[i] = s[i]
        i += 1usize
    }
    ret (buf[0..s.len], ok)
}

fn pop_front(c: *Client) {
    if c.count == 0usize { ret }
    c.bytes -= c.queue[0].len
    var i = 1usize
    while i < c.count {
        c.queue[i - 1usize] = c.queue[i]
        i += 1usize
    }
    c.count -= 1usize
}

// Queues one serialized envelope, dropping the oldest to fit. `TooLarge` when it alone exceeds
// the byte budget.
fn enqueue(c: *Client, bytes_in: str) -> err {
    if bytes_in.len > c.max_bytes { ret TooLarge }
    let (copy, keep_error) = keep(c.a, bytes_in)
    if keep_error != ok { ret keep_error }
    while c.count >= c.max_items || c.bytes + copy.len > c.max_bytes {
        pop_front(c)
        c.dropped += 1usize
    }
    c.queue[c.count] = copy
    c.count += 1usize
    c.bytes += copy.len
    ret ok
}

// Serializes an event (plus attachments) into an envelope stamped `now` and queues it.
fn capture(c: *Client, ev: *const Event, attachments: []const Item, now: i64) -> err {
    var items: [4]Item = zero
    if attachments.len + 1usize > 4usize { ret Invalid }
    let (first, item_error) = event_item(c.a, ev)
    if item_error != ok { ret item_error }
    items[0] = first
    var i = 0usize
    while i < attachments.len {
        items[1usize + i] = attachments[i]
        i += 1usize
    }
    let (bytes_out, envelope_error) = envelope(c.a, ev.id, now, items[0..1usize + attachments.len])
    if envelope_error != ok { ret envelope_error }
    ret enqueue(c, bytes_out)
}

fn is_error_category(l: Limit) -> bool { ret l.category.len == 0usize || str.eq(l.category, "error") }

fn header_value(h: []const http.Header, name: str) -> (str, bool) {
    var i = 0usize
    while i < h.len {
        if lower_eq(h[i].name, name) { ret (h[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

fn lower_eq(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        var p = x[i]
        var q = y[i]
        if p >= 65u8 && p <= 90u8 { p += 32u8 }
        if q >= 65u8 && q <= 90u8 { q += 32u8 }
        if p != q { ret false }
        i += 1usize
    }
    ret true
}

// Sends queued envelopes oldest first, at most `max_send`; how many were delivered. Stops early
// at a rate limit or a failure (the envelope stays queued).
fn flush(c: *Client, now: i64, max_send: usize) -> (usize, err) {
    var delivered = 0usize
    if now < c.retry_at || now < c.limited_until { ret (0usize, ok) }
    let (path_text, target_error) = envelope_target(c.a, &c.dsn)
    if target_error != ok { ret (0usize, target_error) }
    let (auth, auth_error) = auth_header(c.a, &c.dsn, c.name)
    if auth_error != ok { ret (0usize, auth_error) }
    while c.count > 0usize && delivered < max_send {
        let (headers, header_error) = mem.alloc[http.Header](c.a, MAX_HEADERS)
        if header_error != ok { ret (delivered, header_error) }
        headers[0] = http.Header { name: "Host", value: c.dsn.host }
        headers[1] = http.Header { name: "Content-Type", value: "application/x-sentry-envelope" }
        headers[2] = http.Header { name: "X-Sentry-Auth", value: auth }
        var req: http.Request = zero
        req.method = .Post
        req.target = path_text
        req.version = .Http11
        req.headers = headers[0..3]
        req.body = c.queue[0]
        let (resp, send_error) = c.transport.send(c.transport.ctx, c.a, &req)
        if send_error != ok {
            c.failures += 1u32
            var steps = c.failures - 1u32
            if steps > 6u32 { steps = 6u32 }
            var wait = i64(1u64 << u64(steps))
            if wait > MAX_BACKOFF_S { wait = MAX_BACKOFF_S }
            c.retry_at = now + wait * SECOND_NS
            ret (delivered, ok)
        }
        if resp.status >= 200u16 && resp.status < 300u16 {
            pop_front(c)
            c.sent += 1usize
            c.failures = 0u32
            delivered += 1usize
            // a success may still carry limits (sentry sends them on 200 too)
            let (rl, has_rl) = header_value(resp.headers, "X-Sentry-Rate-Limits")
            if has_rl {
                var limits: [8]Limit = zero
                let n = parse_rate_limits(rl, now, limits[0..])
                var k = 0usize
                while k < n {
                    if is_error_category(limits[k]) && limits[k].until > c.limited_until { c.limited_until = limits[k].until }
                    k += 1usize
                }
                if now < c.limited_until { ret (delivered, ok) }
            }
        } else {
            if resp.status == 429u16 {
                var until = now + 60i64 * SECOND_NS
                let (rl2, has_rl2) = header_value(resp.headers, "X-Sentry-Rate-Limits")
                let (ra, has_ra) = header_value(resp.headers, "Retry-After")
                if has_rl2 {
                    var limits2: [8]Limit = zero
                    let n2 = parse_rate_limits(rl2, now, limits2[0..])
                    var found = false
                    var k2 = 0usize
                    while k2 < n2 {
                        if is_error_category(limits2[k2]) {
                            if !found || limits2[k2].until > until { until = limits2[k2].until }
                            found = true
                        }
                        k2 += 1usize
                    }
                } else {
                    if has_ra { until = now + parse_seconds(trim_space(ra), 60i64) * SECOND_NS }
                }
                c.limited_until = until
                ret (delivered, ok)
            }
            if resp.status >= 400u16 && resp.status < 500u16 {
                // the server will never accept this envelope
                pop_front(c)
                c.rejected += 1usize
            } else {
                c.failures += 1u32
                var steps2 = c.failures - 1u32
                if steps2 > 6u32 { steps2 = 6u32 }
                var wait2 = i64(1u64 << u64(steps2))
                if wait2 > MAX_BACKOFF_S { wait2 = MAX_BACKOFF_S }
                c.retry_at = now + wait2 * SECOND_NS
                ret (delivered, ok)
            }
        }
    }
    ret (delivered, ok)
}

fn pending(c: *Client) -> usize { ret c.count }

// ---- the offline queue on disk -------------------------------------------------------------

fn put_u32(b: *str.Builder, v: u32) -> err {
    var i = 0usize
    while i < 4usize {
        try str.push_byte(b, u8((v >> u32(i * 8usize)) & 255u32))
        i += 1usize
    }
    ret ok
}

// Writes the queued envelopes to a store key (`NRQ1`, a count, then length-prefixed blobs).
fn save_queue(c: *Client, s: *store.Store, key: str) -> err {
    let (b0, builder_error) = str.builder(c.a, c.bytes + c.count * 4usize + 16usize)
    if builder_error != ok { ret builder_error }
    var b = b0
    try str.push(&b, "NRQ1")
    try put_u32(&b, u32(c.count))
    var i = 0usize
    while i < c.count {
        try put_u32(&b, u32(c.queue[i].len))
        try str.push(&b, c.queue[i])
        i += 1usize
    }
    ret store.put(s, c.a, key, str.done(&b))
}

fn get_u32(data: str, at: usize) -> u32 {
    var v = 0u32
    var i = 0usize
    while i < 4usize {
        v |= u32(data[at + i]) << u32(i * 8usize)
        i += 1usize
    }
    ret v
}

// Reads a saved queue back, appending to what is queued (older envelopes first).
fn load_queue(c: *Client, s: *store.Store, key: str) -> err {
    let (data, get_error) = store.get(s, c.a, key, 0usize)
    if get_error != ok { ret get_error }
    if data.len < 8usize || !str.eq(data[0..4], "NRQ1") { ret Corrupt }
    let n = usize(get_u32(data, 4usize))
    var at = 8usize
    var i = 0usize
    while i < n {
        if at + 4usize > data.len { ret Corrupt }
        let len = usize(get_u32(data, at))
        at += 4usize
        if len > data.len - at { ret Corrupt }
        try enqueue(c, data[at..at + len])
        at += len
        i += 1usize
    }
    if at != data.len { ret Corrupt }
    ret ok
}

// ---- capture from a running program ---------------------------------------------------------

// An event for an error occurring now: the backtrace of the caller, innermost first, in `frames`.
fn capture_here(c: *Client, level: str, err_type: str, err_value: str, id: str, release: str, now: i64, frames: []debug.Frame) -> err {
    let got = debug.backtrace(frames)
    let ev = Event { id: id, timestamp: now, level: level, message: "", err_type: err_type, err_value: err_value, frames: got, release: release, environment: "", tags: zero }
    ret capture(c, &ev, zero, now)
}
