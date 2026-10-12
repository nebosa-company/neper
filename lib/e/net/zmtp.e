// ZeroMQ's wire protocol (ZMTP 3.x, NULL security) and the brokerless socket patterns on top
// of one connection: PUB/SUB with prefix subscriptions, PUSH/PULL, REQ/REP envelopes and
// DEALER/ROUTER identity routing, over `e.net` TCP sockets. No broker, no background thread:
// every call is a blocking read or write on the connection it is given, so the caller owns
// concurrency (one thread per connection, or one connection per role).
//
// Wire (ZMTP 3.1 as libzmq 4.3 speaks it, verified against its byte streams): a 64-byte
// greeting (`FF`, seven zero bytes, the identity length plus one, `7F`, version 3.1, the
// mechanism `NULL` padded to 20 bytes, an as-server flag, 31 zero bytes), then a `READY`
// command carrying `Socket-Type` (and `Identity` for REQ, DEALER and ROUTER), then frames:
// a flags byte (MORE 1, LONG 2, COMMAND 4), a one-byte or (LONG) eight-byte big-endian
// length, the body. A message is its frames up to the first without MORE. A SUB tells its
// peer what it wants with `SUBSCRIBE`/`CANCEL` command frames carrying the prefix.
//
// Patterns. A REQ prefixes an empty delimiter frame and a REP strips and restores the
// envelope; a ROUTER prepends the peer's identity (its `Identity` property, or an
// auto-assigned five-byte id: a zero byte and a big-endian counter) and routes outgoing
// messages by their first frame; a PUB sends a message to a SUB only when one of its
// subscribed prefixes matches the first frame. Not here: PLAIN/CURVE security, ZMTP 2.0 and
// 1.0 peers, heartbeats (PING/PONG), multi-peer socket objects with automatic reconnect and
// queues, and inproc/ipc transports.

use e.mem
use e.net

type SocketType = enum u8 { Pair, Pub, Sub, Req, Rep, Dealer, Router, Pull, Push, XPub, XSub }
type Frame = struct { more: bool, command: bool, body: []const u8 }
type Greeting = struct { major: u8, minor: u8, as_server: bool, identity_hint: u8 }
type Ready = struct { socket_type: SocketType, identity: []const u8, has_identity: bool }
type Subscriptions = struct { prefixes: []str, count: usize, everything: bool }
type Conn = struct { sock: net.Socket, buf: []u8, filled: usize, consumed: usize, local: SocketType, remote: SocketType, local_identity: []const u8, remote_id: [256]u8, remote_id_len: usize, ready: bool }
error Malformed
error NeedMore
error TooSmall
error Incompatible
error Unsupported
error Closed
error TooLarge

fn type_name(t: SocketType) -> str {
    if t == .Pair { ret "PAIR" }
    if t == .Pub { ret "PUB" }
    if t == .Sub { ret "SUB" }
    if t == .Req { ret "REQ" }
    if t == .Rep { ret "REP" }
    if t == .Dealer { ret "DEALER" }
    if t == .Router { ret "ROUTER" }
    if t == .Pull { ret "PULL" }
    if t == .Push { ret "PUSH" }
    if t == .XPub { ret "XPUB" }
    ret "XSUB"
}

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn type_of_name(name: []const u8) -> (SocketType, bool) {
    var t = 0u8
    while t <= 10u8 {
        let candidate = socket_type_at(t)
        if same(name, type_name(candidate)) { ret (candidate, true) }
        t += 1u8
    }
    ret (.Pair, false)
}

fn type_index(t: SocketType) -> u8 {
    if t == .Pair { ret 0u8 }
    if t == .Pub { ret 1u8 }
    if t == .Sub { ret 2u8 }
    if t == .Req { ret 3u8 }
    if t == .Rep { ret 4u8 }
    if t == .Dealer { ret 5u8 }
    if t == .Router { ret 6u8 }
    if t == .Pull { ret 7u8 }
    if t == .Push { ret 8u8 }
    if t == .XPub { ret 9u8 }
    ret 10u8
}

fn socket_type_at(i: u8) -> SocketType {
    if i == 0u8 { ret .Pair }
    if i == 1u8 { ret .Pub }
    if i == 2u8 { ret .Sub }
    if i == 3u8 { ret .Req }
    if i == 4u8 { ret .Rep }
    if i == 5u8 { ret .Dealer }
    if i == 6u8 { ret .Router }
    if i == 7u8 { ret .Pull }
    if i == 8u8 { ret .Push }
    if i == 9u8 { ret .XPub }
    ret .XSub
}

// Which socket types may talk (RFC 23 section 6, the compatibility table).
fn compatible(a: SocketType, b: SocketType) -> bool {
    if a == .Pair { ret b == .Pair }
    if a == .Pub { ret b == .Sub || b == .XSub }
    if a == .XPub { ret b == .Sub || b == .XSub }
    if a == .Sub { ret b == .Pub || b == .XPub }
    if a == .XSub { ret b == .Pub || b == .XPub }
    if a == .Req { ret b == .Rep || b == .Router }
    if a == .Rep { ret b == .Req || b == .Dealer }
    if a == .Dealer { ret b == .Rep || b == .Dealer || b == .Router }
    if a == .Router { ret b == .Req || b == .Dealer || b == .Router }
    if a == .Push { ret b == .Pull }
    if a == .Pull { ret b == .Push }
    ret false
}

fn sends_identity(t: SocketType) -> bool { ret t == .Req || t == .Dealer || t == .Router }

// ---- greeting ----

fn greeting_size() -> usize { ret 64usize }

fn encode_greeting(dst: []u8, as_server: bool, identity_len: usize) -> (usize, err) {
    if dst.len < 64usize { ret (0usize, TooSmall) }
    var i = 0usize
    while i < 64usize {
        dst[i] = 0u8
        i += 1usize
    }
    dst[0usize] = 255u8
    var hint = identity_len + 1usize
    if hint > 255usize { hint = 255usize }
    dst[8usize] = u8(hint)
    dst[9usize] = 127u8
    dst[10usize] = 3u8
    dst[11usize] = 1u8
    dst[12usize] = 78u8
    dst[13usize] = 85u8
    dst[14usize] = 76u8
    dst[15usize] = 76u8
    if as_server { dst[32usize] = 1u8 }
    ret (64usize, ok)
}

fn decode_greeting(src: []const u8) -> (Greeting, err) {
    var g: Greeting = zero
    if src.len < 64usize { ret (g, NeedMore) }
    if src[0usize] != 255u8 || src[9usize] != 127u8 { ret (g, Malformed) }
    g.major = src[10usize]
    g.minor = src[11usize]
    g.identity_hint = src[8usize]
    if g.major < 3u8 { ret (g, Unsupported) }
    if !(src[12usize] == 78u8 && src[13usize] == 85u8 && src[14usize] == 76u8 && src[15usize] == 76u8 && src[16usize] == 0u8) { ret (g, Unsupported) }
    g.as_server = src[32usize] == 1u8
    ret (g, ok)
}

// ---- frames ----

fn encode_frame(dst: []u8, more: bool, command: bool, body: []const u8) -> (usize, err) {
    var flags = 0u8
    if more { flags = flags | 1u8 }
    if command { flags = flags | 4u8 }
    var at = 0usize
    if body.len > 255usize {
        if dst.len < 9usize + body.len { ret (0usize, TooSmall) }
        dst[0usize] = flags | 2u8
        var i = 0usize
        while i < 8usize {
            dst[1usize + i] = u8((u64(body.len) >> u64((7usize - i) * 8usize)) & 255u64)
            i += 1usize
        }
        at = 9usize
    } else {
        if dst.len < 2usize + body.len { ret (0usize, TooSmall) }
        dst[0usize] = flags
        dst[1usize] = u8(body.len)
        at = 2usize
    }
    var k = 0usize
    while k < body.len {
        dst[at + k] = body[k]
        k += 1usize
    }
    ret (at + body.len, ok)
}

// One frame at the front of `src`: the frame (its body a slice of `src`) and the bytes consumed.
fn decode_frame(src: []const u8) -> (Frame, usize, err) {
    var f: Frame = zero
    if src.len < 2usize { ret (f, 0usize, NeedMore) }
    let flags = src[0usize]
    if flags & 248u8 != 0u8 { ret (f, 0usize, Malformed) }
    var header = 2usize
    var length = 0u64
    if flags & 2u8 != 0u8 {
        if src.len < 9usize { ret (f, 0usize, NeedMore) }
        header = 9usize
        var i = 0usize
        while i < 8usize {
            length = length * 256u64 + u64(src[1usize + i])
            i += 1usize
        }
        if length > 1073741824u64 { ret (f, 0usize, TooLarge) }
    } else {
        length = u64(src[1usize])
    }
    let total = header + usize(length)
    if src.len < total { ret (f, 0usize, NeedMore) }
    f.more = flags & 1u8 != 0u8
    f.command = flags & 4u8 != 0u8
    f.body = src[header..total]
    ret (f, total, ok)
}

// ---- READY and subscription commands ----

fn put_property(dst: []u8, at: usize, name: str, value: []const u8) -> usize {
    dst[at] = u8(name.len)
    var i = 0usize
    while i < name.len {
        dst[at + 1usize + i] = name[i]
        i += 1usize
    }
    var p = at + 1usize + name.len
    dst[p] = u8((value.len >> 24u32) & 255usize)
    dst[p + 1usize] = u8((value.len >> 16u32) & 255usize)
    dst[p + 2usize] = u8((value.len >> 8u32) & 255usize)
    dst[p + 3usize] = u8(value.len & 255usize)
    p += 4usize
    var k = 0usize
    while k < value.len {
        dst[p + k] = value[k]
        k += 1usize
    }
    ret p + value.len
}

// The READY command frame (with its frame header) for `t` and `identity`.
fn encode_ready(dst: []u8, t: SocketType, identity: []const u8) -> (usize, err) {
    var body: [320]u8 = zero
    body[0usize] = 5u8
    body[1usize] = 82u8
    body[2usize] = 69u8
    body[3usize] = 65u8
    body[4usize] = 68u8
    body[5usize] = 89u8
    if identity.len > 255usize { ret (0usize, TooLarge) }
    var at = put_property(body[0usize..320usize], 6usize, "Socket-Type", type_name(t))
    if sends_identity(t) { at = put_property(body[0usize..320usize], at, "Identity", identity) }
    let (n, e) = encode_frame(dst, false, true, body[0usize..at])
    ret (n, e)
}

fn decode_ready(body: []const u8) -> (Ready, err) {
    var r: Ready = zero
    if body.len < 6usize || body[0usize] != 5u8 { ret (r, Malformed) }
    if !(body[1usize] == 82u8 && body[2usize] == 69u8 && body[3usize] == 65u8 && body[4usize] == 68u8 && body[5usize] == 89u8) { ret (r, Malformed) }
    var at = 6usize
    var have_type = false
    while at < body.len {
        let name_len = usize(body[at])
        if at + 1usize + name_len + 4usize > body.len { ret (r, Malformed) }
        let name = body[at + 1usize..at + 1usize + name_len]
        let p = at + 1usize + name_len
        let value_len = ((usize(body[p]) * 256usize + usize(body[p + 1usize])) * 256usize + usize(body[p + 2usize])) * 256usize + usize(body[p + 3usize])
        if p + 4usize + value_len > body.len { ret (r, Malformed) }
        let value = body[p + 4usize..p + 4usize + value_len]
        if same(name, "Socket-Type") {
            let (t, known) = type_of_name(value)
            if !known { ret (r, Unsupported) }
            r.socket_type = t
            have_type = true
        } else if same(name, "Identity") {
            r.identity = value
            r.has_identity = true
        }
        at = p + 4usize + value_len
    }
    if !have_type { ret (r, Malformed) }
    ret (r, ok)
}

// A SUBSCRIBE (`subscribe`) or CANCEL command frame for `prefix`.
fn encode_subscription(dst: []u8, subscribe: bool, prefix: []const u8) -> (usize, err) {
    var body: [300]u8 = zero
    var at = 0usize
    let name = "SUBSCRIBE"
    let cancel = "CANCEL"
    if subscribe {
        body[0usize] = 9u8
        var i = 0usize
        while i < 9usize {
            body[1usize + i] = name[i]
            i += 1usize
        }
        at = 10usize
    } else {
        body[0usize] = 6u8
        var i = 0usize
        while i < 6usize {
            body[1usize + i] = cancel[i]
            i += 1usize
        }
        at = 7usize
    }
    if at + prefix.len > 300usize { ret (0usize, TooLarge) }
    var k = 0usize
    while k < prefix.len {
        body[at + k] = prefix[k]
        k += 1usize
    }
    let (n, e) = encode_frame(dst, false, true, body[0usize..at + prefix.len])
    ret (n, e)
}

// (is a subscription command, subscribe?, prefix).
fn decode_subscription(body: []const u8) -> (bool, bool, []const u8) {
    if body.len >= 10usize && body[0usize] == 9u8 && same(body[1usize..10usize], "SUBSCRIBE") { ret (true, true, body[10usize..body.len]) }
    if body.len >= 7usize && body[0usize] == 6u8 && same(body[1usize..7usize], "CANCEL") { ret (true, false, body[7usize..body.len]) }
    ret (false, false, body[0usize..0usize])
}

// ---- subscription set (the PUB side) ----

fn subscriptions(a: *mem.Arena, capacity: usize) -> (Subscriptions, err) {
    var s: Subscriptions = zero
    let (p, e) = mem.alloc[str](a, capacity)
    if e != ok { ret (s, e) }
    s.prefixes = p
    ret (s, ok)
}

fn add_prefix(s: *Subscriptions, prefix: []const u8) -> err {
    if prefix.len == 0usize {
        s.everything = true
        ret ok
    }
    var i = 0usize
    while i < s.count {
        if same(s.prefixes[i], prefix) { ret ok }
        i += 1usize
    }
    if s.count >= s.prefixes.len { ret TooLarge }
    s.prefixes[s.count] = prefix
    s.count += 1usize
    ret ok
}

fn remove_prefix(s: *Subscriptions, prefix: []const u8) {
    if prefix.len == 0usize {
        s.everything = false
        ret
    }
    var i = 0usize
    while i < s.count {
        if same(s.prefixes[i], prefix) {
            s.prefixes[i] = s.prefixes[s.count - 1usize]
            s.count -= 1usize
            ret
        }
        i += 1usize
    }
}

// Does a message whose first frame is `topic` pass any subscribed prefix?
fn wants(s: *const Subscriptions, topic: []const u8) -> bool {
    if s.everything { ret true }
    var i = 0usize
    while i < s.count {
        let p = s.prefixes[i]
        if p.len <= topic.len && same(topic[0usize..p.len], p) { ret true }
        i += 1usize
    }
    ret false
}

// ---- a blocking connection ----

fn conn(sock: net.Socket, buf: []u8, local: SocketType, identity: []const u8) -> Conn {
    var c: Conn = zero
    c.sock = sock
    c.buf = buf
    c.local = local
    c.local_identity = identity
    ret c
}

fn send_all(sock: net.Socket, data: []const u8) -> err {
    var sent = 0usize
    while sent < data.len {
        let (n, e) = net.send(sock, data[sent..data.len])
        if e != ok { ret e }
        if n == 0usize { ret Closed }
        sent += n
    }
    ret ok
}

// Makes room and reads more bytes from the socket into the buffer.
fn fill(c: *Conn) -> err {
    if c.consumed > 0usize {
        var i = 0usize
        while i < c.filled - c.consumed {
            c.buf[i] = c.buf[c.consumed + i]
            i += 1usize
        }
        c.filled -= c.consumed
        c.consumed = 0usize
    }
    if c.filled >= c.buf.len { ret TooLarge }
    let (n, e) = net.receive(c.sock, c.buf[c.filled..c.buf.len])
    if e != ok { ret e }
    if n == 0usize { ret Closed }
    c.filled += n
    ret ok
}

// Greeting and READY out, the peer's greeting and READY in; checks the socket types fit.
fn handshake(c: *Conn, as_server: bool) -> err {
    var out: [400]u8 = zero
    let (gn, ge) = encode_greeting(out[0usize..400usize], as_server, c.local_identity.len)
    if ge != ok { ret ge }
    let (rn, re) = encode_ready(out[gn..400usize], c.local, c.local_identity)
    if re != ok { ret re }
    try send_all(c.sock, out[0usize..gn + rn])
    while c.filled - c.consumed < 64usize { try fill(c) }
    let (g, g_error) = decode_greeting(c.buf[c.consumed..c.filled])
    if g_error != ok { ret g_error }
    c.consumed += 64usize
    while true {
        let (f, used, fe) = decode_frame(c.buf[c.consumed..c.filled])
        if fe == NeedMore {
            try fill(c)
            continue
        }
        if fe != ok { ret fe }
        if !f.command { ret Malformed }
        let (r, ready_error) = decode_ready(f.body)
        if ready_error != ok { ret ready_error }
        if !compatible(c.local, r.socket_type) { ret Incompatible }
        c.remote = r.socket_type
        var k = 0usize
        while k < r.identity.len && k < 256usize {
            c.remote_id[k] = r.identity[k]
            k += 1usize
        }
        c.remote_id_len = r.identity.len
        c.consumed += used
        c.ready = true
        break
    }
    ret ok
}

// Sends a message: `parts` as frames, all but the last with MORE.
fn send_message(c: *Conn, parts: []const []const u8) -> err {
    if parts.len == 0usize { ret Malformed }
    var i = 0usize
    while i < parts.len {
        var frame_buf: [1500]u8 = zero
        if parts[i].len + 9usize <= 1500usize {
            let (n, e) = encode_frame(frame_buf[0usize..1500usize], i + 1usize < parts.len, false, parts[i])
            if e != ok { ret e }
            try send_all(c.sock, frame_buf[0usize..n])
        } else {
            // big frame: header alone, then the body straight from the caller's slice
            let (hn, he) = encode_frame(frame_buf[0usize..1500usize], i + 1usize < parts.len, false, parts[i][0usize..0usize])
            if he != ok { ret he }
            var header: [9]u8 = zero
            header[0usize] = 2u8
            if i + 1usize < parts.len { header[0usize] = 3u8 }
            var k = 0usize
            while k < 8usize {
                header[1usize + k] = u8((u64(parts[i].len) >> u64((7usize - k) * 8usize)) & 255u64)
                k += 1usize
            }
            try send_all(c.sock, header[0usize..9usize])
            try send_all(c.sock, parts[i])
        }
        i += 1usize
    }
    ret ok
}

fn send_command(c: *Conn, frame: []const u8) -> err { ret send_all(c.sock, frame) }

// Next frame (commands included); its body is valid until the next read from this connection.
fn recv_frame(c: *Conn) -> (Frame, err) {
    while true {
        let (f, used, e) = decode_frame(c.buf[c.consumed..c.filled])
        if e == NeedMore {
            let fe = fill(c)
            if fe != ok { ret (f, fe) }
            continue
        }
        if e != ok { ret (f, e) }
        c.consumed += used
        ret (f, ok)
    }
    var none: Frame = zero
    ret (none, Malformed)
}

// A whole data message into `out` (slices of the connection buffer, valid until the next
// read); command frames in between are returned to `on_command` by being skipped here and
// reported through `commands` (the count of subscription changes applied to `subs`, which
// may be null-like by passing a zero-capacity set).
fn recv_message(c: *Conn, out: [][]const u8, subs: *Subscriptions) -> (usize, err) {
    var n = 0usize
    while true {
        // keep a message's frames contiguous: compaction happens only between messages
        let (f, e) = recv_frame_keep(c)
        if e != ok { ret (0usize, e) }
        if f.command {
            let (is_sub, subscribe, prefix) = decode_subscription(f.body)
            if is_sub {
                if subscribe {
                    let ae = add_prefix(subs, prefix)
                    if ae != ok { ret (0usize, ae) }
                } else {
                    remove_prefix(subs, prefix)
                }
            }
            continue
        }
        if n >= out.len { ret (0usize, TooLarge) }
        out[n] = f.body
        n += 1usize
        if !f.more { ret (n, ok) }
    }
    ret (0usize, Malformed)
}

// Like `recv_frame` but never compacts the buffer mid-message: grows only by filling its tail.
fn recv_frame_keep(c: *Conn) -> (Frame, err) {
    while true {
        let (f, used, e) = decode_frame(c.buf[c.consumed..c.filled])
        if e == NeedMore {
            if c.filled >= c.buf.len {
                // out of room at the tail: compact only when nothing of the current message is held
                let (compacted, ce) = compact_if_possible(c)
                if ce != ok { ret (f, ce) }
                if !compacted { ret (f, TooLarge) }
            }
            let (n, re) = net.receive(c.sock, c.buf[c.filled..c.buf.len])
            if re != ok { ret (f, re) }
            if n == 0usize { ret (f, Closed) }
            c.filled += n
            continue
        }
        if e != ok { ret (f, e) }
        c.consumed += used
        ret (f, ok)
    }
    var none: Frame = zero
    ret (none, Malformed)
}

fn compact_if_possible(c: *Conn) -> (bool, err) {
    if c.consumed == 0usize { ret (false, ok) }
    var i = 0usize
    while i < c.filled - c.consumed {
        c.buf[i] = c.buf[c.consumed + i]
        i += 1usize
    }
    c.filled -= c.consumed
    c.consumed = 0usize
    ret (true, ok)
}

// ---- pattern envelopes ----

// REQ: the message with the empty delimiter frame in front, into `out`; returns the part count.
fn req_envelope(parts: []const []const u8, out: [][]const u8) -> (usize, err) {
    if parts.len + 1usize > out.len { ret (0usize, TooLarge) }
    out[0usize] = parts[0usize][0usize..0usize]
    var i = 0usize
    while i < parts.len {
        out[i + 1usize] = parts[i]
        i += 1usize
    }
    ret (parts.len + 1usize, ok)
}

// REP/REQ receive side: the index of the first frame after the empty delimiter, or `Malformed`.
fn envelope_body_start(parts: []const []const u8) -> (usize, err) {
    var i = 0usize
    while i < parts.len {
        if parts[i].len == 0usize { ret (i + 1usize, ok) }
        i += 1usize
    }
    ret (0usize, Malformed)
}

// ROUTER receive: `identity` frame plus the parts, into `out`. When the peer announced no
// identity, `auto` (five bytes) is filled from `counter` and used.
fn router_prefix(c: *const Conn, counter: u32, auto: []u8, parts: []const []const u8, out: [][]const u8) -> (usize, err) {
    if parts.len + 1usize > out.len { ret (0usize, TooLarge) }
    var id = c.remote_id[0usize..c.remote_id_len]
    if id.len == 0usize {
        auto[0usize] = 0u8
        auto[1usize] = u8((counter >> 24u32) & 255u32)
        auto[2usize] = u8((counter >> 16u32) & 255u32)
        auto[3usize] = u8((counter >> 8u32) & 255u32)
        auto[4usize] = u8(counter & 255u32)
        id = auto[0usize..5usize]
    }
    out[0usize] = id
    var i = 0usize
    while i < parts.len {
        out[i + 1usize] = parts[i]
        i += 1usize
    }
    ret (parts.len + 1usize, ok)
}
