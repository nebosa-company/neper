// Redis serialization protocol, RESP2 and RESP3 (L114), over caller buffers: `encode_command` writes a command as an
// array of bulk strings; `parse` reads one reply from the front of a byte stream and answers the bytes it used, or
// `Incomplete` until the rest has arrived. RESP3's null, boolean, double, big number, blob error, verbatim string,
// map, set and push types are read as well as RESP2's; an attribute frame (`|`) is skipped and the value after it
// returned. A reply borrows the input buffer for strings and allocates arrays and maps from the arena (reset on any
// error, so a retry after `Incomplete` costs nothing). Also here: the cluster key slot (CRC-16/XMODEM with hash
// tags), MOVED/ASK redirect parsing, error classification and pub/sub message recognition (RESP2 arrays and RESP3
// pushes). No sockets and no connection pool: the caller moves bytes, as `e.net.mqtt` does.
//
// Memory: strings borrow; arrays and maps come from `a`; limits bound a hostile peer (declared sizes are checked
// before anything is allocated).
use e.mem
use e.str

error Incomplete
error Invalid
error TooLarge
error TooSmall

type Pair = struct { key: Value, value: Value }
type Verbatim = struct { format: str, data: []const u8 }
type Value = union enum u8 { Null, Simple: str, Error: str, Integer: i64, Bulk: []const u8, Array: []const Value, Bool: bool, Double: f64, Big: str, Map: []const Pair, Set: []const Value, Push: []const Value, Verbatim: Verbatim, BlobError: []const u8 }
type Limits = struct { max_bulk: usize, max_elements: usize, max_depth: u16 }
type ErrorKind = enum u8 { Generic, Moved, Ask, WrongType, NoAuth, ReadOnly, Loading, TryAgain, ClusterDown, MasterDown, NoScript, Busy }
type Redirect = struct { ask: bool, slot: u16, host: str, port: u16 }
type PubSubKind = enum u8 { Message, PMessage, Subscribe, Unsubscribe, PSubscribe, PUnsubscribe }
type PubSub = struct { kind: PubSubKind, pattern: []const u8, channel: []const u8, payload: []const u8, count: i64 }
type Session = struct { protocol: u8, pending: usize, subscriptions: usize }

fn limits() -> Limits {
    ret Limits { max_bulk: 536870912usize, max_elements: 1048576usize, max_depth: 32u16 }
}

// --- encoding ----------------------------------------------------------------------------------------------------

fn put_bytes(dst: []u8, at: *usize, src: []const u8) -> err {
    if *at + src.len > dst.len { ret TooSmall }
    mem.copy[u8](dst[*at..*at + src.len], src)
    *at += src.len
    ret ok
}

fn put_decimal(dst: []u8, at: *usize, value: usize) -> err {
    var digits: [20]u8 = zero
    var n = 0usize
    var v = value
    if v == 0usize {
        digits[0usize] = 48u8
        n = 1usize
    }
    while v > 0usize {
        digits[n] = 48u8 + u8(v % 10usize)
        v = v / 10usize
        n += 1usize
    }
    if *at + n > dst.len { ret TooSmall }
    var i = 0usize
    while i < n {
        dst[*at + i] = digits[n - 1usize - i]
        i += 1usize
    }
    *at += n
    ret ok
}

// A command: `*<n>\r\n` then each argument as `$<len>\r\n<bytes>\r\n`. Answers the bytes written.
fn encode_command(dst: []u8, args: []const []const u8) -> (usize, err) {
    var at = 0usize
    var e = put_bytes(dst, &at, "*")
    if e != ok { ret (0usize, e) }
    e = put_decimal(dst, &at, args.len)
    if e != ok { ret (0usize, e) }
    e = put_bytes(dst, &at, "\r\n")
    if e != ok { ret (0usize, e) }
    var i = 0usize
    while i < args.len {
        e = put_bytes(dst, &at, "$")
        if e != ok { ret (0usize, e) }
        e = put_decimal(dst, &at, args[i].len)
        if e != ok { ret (0usize, e) }
        e = put_bytes(dst, &at, "\r\n")
        if e != ok { ret (0usize, e) }
        e = put_bytes(dst, &at, args[i])
        if e != ok { ret (0usize, e) }
        e = put_bytes(dst, &at, "\r\n")
        if e != ok { ret (0usize, e) }
        i += 1usize
    }
    ret (at, ok)
}

// `HELLO <version> [AUTH user password]`: switches the connection to RESP3 (or 2) and authenticates.
fn encode_hello(dst: []u8, version: u8, user: str, password: str) -> (usize, err) {
    var number: [1]u8 = zero
    number[0usize] = 48u8 + version
    if user.len == 0usize && password.len == 0usize {
        var args: [2][]const u8 = zero
        args[0usize] = "HELLO"
        args[1usize] = number[0usize..1usize]
        let (n, e) = encode_command(dst, args[0usize..])
        ret (n, e)
    }
    var args3: [5][]const u8 = zero
    args3[0usize] = "HELLO"
    args3[1usize] = number[0usize..1usize]
    args3[2usize] = "AUTH"
    args3[3usize] = user
    args3[4usize] = password
    let (m, e2) = encode_command(dst, args3[0usize..])
    ret (m, e2)
}

// --- decoding ----------------------------------------------------------------------------------------------------

// The end of the line starting at `at` (the index of its CR), or `Incomplete`.
fn line_end(buf: []const u8, at: usize) -> (usize, err) {
    var i = at
    while i + 1usize < buf.len {
        if buf[i] == 13u8 {
            if buf[i + 1usize] == 10u8 { ret (i, ok) }
            ret (0usize, Invalid)
        }
        i += 1usize
    }
    ret (0usize, Incomplete)
}

fn parse_integer(s: str) -> (i64, bool) {
    if s.len == 0usize || s.len > 20usize { ret (0i64, false) }
    var i = 0usize
    var negative = false
    if s[0usize] == 45u8 {
        negative = true
        i = 1usize
    } else if s[0usize] == 43u8 {
        i = 1usize
    }
    if i == s.len { ret (0i64, false) }
    var magnitude = 0u64
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret (0i64, false) }
        let digit = u64(s[i] - 48u8)
        if magnitude > (9223372036854775808u64 - digit) / 10u64 { ret (0i64, false) }
        magnitude = magnitude * 10u64 + digit
        i += 1usize
    }
    if negative {
        if magnitude > 9223372036854775808u64 { ret (0i64, false) }
        if magnitude == 9223372036854775808u64 { ret (0i64 - 9223372036854775807i64 - 1i64, true) }
        ret (0i64 - i64(magnitude), true)
    }
    if magnitude > 9223372036854775807u64 { ret (0i64, false) }
    ret (i64(magnitude), true)
}

fn parse_double(s: str) -> (f64, bool) {
    if str.eq(s, "inf") || str.eq(s, "+inf") { ret (mem.bitcast[f64](9218868437227405312u64), true) }
    if str.eq(s, "-inf") { ret (mem.bitcast[f64](18442240474082181120u64), true) }
    if str.eq(s, "nan") || str.eq(s, "-nan") { ret (mem.bitcast[f64](9221120237041090560u64), true) }
    let (v, e) = str.parse_f64(s)
    ret (v, e == ok)
}

fn element_slice(a: *mem.Arena, count: usize) -> ([]Value, err) {
    let (items, e) = mem.alloc[Value](a, count)
    ret (items, e)
}

fn pair_slice(a: *mem.Arena, count: usize) -> ([]Pair, err) {
    let (items, e) = mem.alloc[Pair](a, count)
    ret (items, e)
}

// One value at `*at`, moving `*at` past it.
fn read_value(a: *mem.Arena, buf: []const u8, at: *usize, lim: *const Limits, depth: u16) -> (Value, err) {
    var none: Value = .Null
    if depth > lim.max_depth { ret (none, TooLarge) }
    if *at >= buf.len { ret (none, Incomplete) }
    let tag = buf[*at]
    let (end, line_error) = line_end(buf, *at + 1usize)
    if line_error != ok { ret (none, line_error) }
    let head = buf[*at + 1usize..end]
    let after = end + 2usize
    if tag == 43u8 {
        *at = after
        ret (Value { Simple: head }, ok)
    }
    if tag == 45u8 {
        *at = after
        ret (Value { Error: head }, ok)
    }
    if tag == 58u8 {
        let (n, good) = parse_integer(head)
        if !good { ret (none, Invalid) }
        *at = after
        ret (Value { Integer: n }, ok)
    }
    if tag == 95u8 {
        if head.len != 0usize { ret (none, Invalid) }
        *at = after
        ret (none, ok)
    }
    if tag == 35u8 {
        if head.len != 1usize || (head[0usize] != 116u8 && head[0usize] != 102u8) { ret (none, Invalid) }
        *at = after
        ret (Value { Bool: head[0usize] == 116u8 }, ok)
    }
    if tag == 44u8 {
        let (d, good) = parse_double(head)
        if !good { ret (none, Invalid) }
        *at = after
        ret (Value { Double: d }, ok)
    }
    if tag == 40u8 {
        if head.len == 0usize { ret (none, Invalid) }
        *at = after
        ret (Value { Big: head }, ok)
    }
    if tag == 36u8 || tag == 33u8 || tag == 61u8 {
        // $ bulk, ! blob error, = verbatim string: a length, that many bytes, CRLF. `$-1` is the RESP2 null.
        if tag == 36u8 && str.eq(head, "-1") {
            *at = after
            ret (none, ok)
        }
        let (n, good) = parse_integer(head)
        if !good || n < 0i64 { ret (none, Invalid) }
        let size = usize(n)
        if size > lim.max_bulk { ret (none, TooLarge) }
        if after + size + 2usize > buf.len { ret (none, Incomplete) }
        if buf[after + size] != 13u8 || buf[after + size + 1usize] != 10u8 { ret (none, Invalid) }
        let data = buf[after..after + size]
        *at = after + size + 2usize
        if tag == 36u8 { ret (Value { Bulk: data }, ok) }
        if tag == 33u8 { ret (Value { BlobError: data }, ok) }
        if size < 4usize || data[3usize] != 58u8 { ret (none, Invalid) }
        ret (Value { Verbatim: Verbatim { format: data[0usize..3usize], data: data[4usize..] } }, ok)
    }
    if tag == 42u8 || tag == 126u8 || tag == 62u8 {
        // * array, ~ set, > push. `*-1` is the RESP2 null array.
        if tag == 42u8 && str.eq(head, "-1") {
            *at = after
            ret (none, ok)
        }
        let (n, good) = parse_integer(head)
        if !good || n < 0i64 { ret (none, Invalid) }
        let count = usize(n)
        if count > lim.max_elements { ret (none, TooLarge) }
        if after + count * 3usize > buf.len { ret (none, Incomplete) }
        let (items, alloc_error) = element_slice(a, count)
        if alloc_error != ok { ret (none, alloc_error) }
        var pos = after
        var i = 0usize
        while i < count {
            let (item, item_error) = read_value(a, buf, &pos, lim, depth + 1u16)
            if item_error != ok { ret (none, item_error) }
            items[i] = item
            i += 1usize
        }
        *at = pos
        if tag == 42u8 { ret (Value { Array: items }, ok) }
        if tag == 126u8 { ret (Value { Set: items }, ok) }
        ret (Value { Push: items }, ok)
    }
    if tag == 37u8 || tag == 124u8 {
        // % map, | attribute (read, then dropped: the value after it is the reply).
        let (n, good) = parse_integer(head)
        if !good || n < 0i64 { ret (none, Invalid) }
        let count = usize(n)
        if count > lim.max_elements { ret (none, TooLarge) }
        if after + count * 6usize > buf.len { ret (none, Incomplete) }
        let (pairs, alloc_error) = pair_slice(a, count)
        if alloc_error != ok { ret (none, alloc_error) }
        var pos = after
        var i = 0usize
        while i < count {
            let (k, key_error) = read_value(a, buf, &pos, lim, depth + 1u16)
            if key_error != ok { ret (none, key_error) }
            let (v, value_error) = read_value(a, buf, &pos, lim, depth + 1u16)
            if value_error != ok { ret (none, value_error) }
            pairs[i] = Pair { key: k, value: v }
            i += 1usize
        }
        *at = pos
        if tag == 37u8 { ret (Value { Map: pairs }, ok) }
        let (next, next_error) = read_value(a, buf, at, lim, depth)
        if next_error != ok { ret (none, next_error) }
        ret (next, ok)
    }
    ret (none, Invalid)
}

// One reply at the front of `buf`: the value and the bytes it occupies. On any error the arena is left as it was.
fn parse(a: *mem.Arena, buf: []const u8, lim: *const Limits) -> (Value, usize, err) {
    var none: Value = .Null
    let mark = mem.mark(a)
    var at = 0usize
    let (v, e) = read_value(a, buf, &at, lim, 0u16)
    if e != ok {
        mem.reset(a, mark)
        ret (none, 0usize, e)
    }
    ret (v, at, ok)
}

// --- cluster and errors ------------------------------------------------------------------------------------------

fn crc16_step(crc: u16, byte: u8) -> u16 {
    var c = crc ^ (u16(byte) << 8u16)
    var i = 0u8
    while i < 8u8 {
        if (c & 32768u16) != 0u16 {
            c = (c << 1u16) ^ 4129u16
        } else {
            c = c << 1u16
        }
        i += 1u8
    }
    ret c
}

// The cluster hash slot of a key (CRC-16/XMODEM mod 16384), hashing only the first non-empty `{tag}` when present.
fn key_slot(key: []const u8) -> u16 {
    var start = key.len
    var i = 0usize
    while i < key.len {
        if key[i] == 123u8 {
            start = i
            break
        }
        i += 1usize
    }
    var lo = 0usize
    var hi = key.len
    if start < key.len {
        var j = start + 1usize
        while j < key.len && key[j] != 125u8 { j += 1usize }
        if j < key.len && j != start + 1usize {
            lo = start + 1usize
            hi = j
        }
    }
    var crc = 0u16
    var k = lo
    while k < hi {
        crc = crc16_step(crc, key[k])
        k += 1usize
    }
    ret crc % 16384u16
}

fn starts(text: str, prefix: str) -> bool {
    if text.len < prefix.len { ret false }
    ret str.eq(text[0usize..prefix.len], prefix)
}

// The class of an error reply by its first word.
fn error_kind(text: str) -> ErrorKind {
    if starts(text, "MOVED ") { ret .Moved }
    if starts(text, "ASK ") { ret .Ask }
    if starts(text, "WRONGTYPE") { ret .WrongType }
    if starts(text, "NOAUTH") || starts(text, "WRONGPASS") { ret .NoAuth }
    if starts(text, "READONLY") { ret .ReadOnly }
    if starts(text, "LOADING") { ret .Loading }
    if starts(text, "TRYAGAIN") { ret .TryAgain }
    if starts(text, "CLUSTERDOWN") { ret .ClusterDown }
    if starts(text, "MASTERDOWN") { ret .MasterDown }
    if starts(text, "NOSCRIPT") { ret .NoScript }
    if starts(text, "BUSY") { ret .Busy }
    ret .Generic
}

// `MOVED <slot> <host>:<port>` or `ASK <slot> <host>:<port>`; the host may be empty (the same node) or an IPv6
// literal, so the port is what follows the last colon.
fn parse_redirect(text: str) -> (Redirect, bool) {
    var r: Redirect = zero
    var rest = text
    if starts(text, "MOVED ") {
        rest = text[6usize..]
    } else if starts(text, "ASK ") {
        r.ask = true
        rest = text[4usize..]
    } else {
        ret (r, false)
    }
    var sp = 0usize
    while sp < rest.len && rest[sp] != 32u8 { sp += 1usize }
    if sp == 0usize || sp >= rest.len { ret (r, false) }
    let (slot, slot_ok) = parse_integer(rest[0usize..sp])
    if !slot_ok || slot < 0i64 || slot > 16383i64 { ret (r, false) }
    let address = rest[sp + 1usize..]
    var colon = address.len
    var i = address.len
    while i > 0usize {
        i -= 1usize
        if address[i] == 58u8 {
            colon = i
            break
        }
    }
    if colon == address.len { ret (r, false) }
    let (port, port_ok) = parse_integer(address[colon + 1usize..])
    if !port_ok || port < 0i64 || port > 65535i64 { ret (r, false) }
    r.slot = u16(slot)
    r.host = address[0usize..colon]
    r.port = u16(port)
    ret (r, true)
}

// --- pub/sub and sessions ----------------------------------------------------------------------------------------

fn bytes_of(v: Value) -> ([]const u8, bool) {
    switch v {
    case .Bulk as b:
        ret (b, true)
    case .Simple as s:
        ret (s, true)
    default:
        ret ("", false)
    }
    ret ("", false)
}

fn same_ascii(left: []const u8, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        var c = left[i]
        if c >= 65u8 && c <= 90u8 { c += 32u8 }
        if c != right[i] { ret false }
        i += 1usize
    }
    ret true
}

// A pub/sub event in an array or push reply: message, pmessage, and the (p)subscribe/(p)unsubscribe confirmations.
fn pubsub_event(items: []const Value) -> (PubSub, bool) {
    var p: PubSub = zero
    if items.len < 3usize { ret (p, false) }
    let (name, name_ok) = bytes_of(items[0usize])
    if !name_ok { ret (p, false) }
    if same_ascii(name, "message") && items.len == 3usize {
        let (channel, c_ok) = bytes_of(items[1usize])
        let (payload, p_ok) = bytes_of(items[2usize])
        if !c_ok || !p_ok { ret (p, false) }
        p.kind = .Message
        p.channel = channel
        p.payload = payload
        ret (p, true)
    }
    if same_ascii(name, "pmessage") && items.len == 4usize {
        let (pattern, pat_ok) = bytes_of(items[1usize])
        let (channel, c_ok) = bytes_of(items[2usize])
        let (payload, p_ok) = bytes_of(items[3usize])
        if !pat_ok || !c_ok || !p_ok { ret (p, false) }
        p.kind = .PMessage
        p.pattern = pattern
        p.channel = channel
        p.payload = payload
        ret (p, true)
    }
    if items.len == 3usize {
        var kind: PubSubKind = .Subscribe
        var matched = false
        if same_ascii(name, "subscribe") {
            matched = true
        } else if same_ascii(name, "unsubscribe") {
            kind = .Unsubscribe
            matched = true
        } else if same_ascii(name, "psubscribe") {
            kind = .PSubscribe
            matched = true
        } else if same_ascii(name, "punsubscribe") {
            kind = .PUnsubscribe
            matched = true
        }
        if !matched { ret (p, false) }
        let (channel, c_ok) = bytes_of(items[1usize])
        if !c_ok { ret (p, false) }
        switch items[2usize] {
        case .Integer as n:
            p.count = n
        default:
            p.count = 0i64
        }
        p.kind = kind
        p.channel = channel
        ret (p, true)
    }
    ret (p, false)
}

fn session(protocol: u8) -> Session {
    ret Session { protocol: protocol, pending: 0usize, subscriptions: 0usize }
}

// A reply that answers a command the session sent (it consumes a pending slot) rather than an unsolicited push or
// pub/sub message. RESP3 pushes are never replies; in RESP2 an array that is a pub/sub message never is either.
fn is_reply(s: *const Session, v: Value) -> bool {
    switch v {
    case .Push as items:
        ret false
    case .Array as items:
        if s.protocol == 2u8 && s.subscriptions > 0usize {
            let (event, found) = pubsub_event(items)
            if found && (event.kind == .Message || event.kind == .PMessage) { ret false }
        }
        ret true
    default:
        ret true
    }
    ret true
}

// Account for a received value: a reply consumes a pending command; a (p)subscribe or (p)unsubscribe
// confirmation also moves the session's subscription count.
fn note(s: *Session, v: Value) {
    if is_reply(s, v) && s.pending > 0usize {
        s.pending -= 1usize
    }
    switch v {
    case .Array as items:
        let (event, found) = pubsub_event(items)
        if found { apply(s, event) }
    case .Push as items:
        let (event, found) = pubsub_event(items)
        if found { apply(s, event) }
    default:
        ret
    }
}

fn apply(s: *Session, event: PubSub) {
    if event.kind == .Subscribe || event.kind == .PSubscribe || event.kind == .Unsubscribe || event.kind == .PUnsubscribe {
        if event.count >= 0i64 { s.subscriptions = usize(event.count) }
    }
}

// Write a command and count the replies it will draw (one for most; one per channel for SUBSCRIBE and friends).
fn send(s: *Session, dst: []u8, args: []const []const u8, replies: usize) -> (usize, err) {
    let (n, e) = encode_command(dst, args)
    if e == ok { s.pending += replies }
    ret (n, e)
}
