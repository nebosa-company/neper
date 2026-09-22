// CoAP (RFC 7252) over caller buffers, no sockets: `Message` is the 4-byte
// header (version 1, type, token length, code, id), token, the raw option
// bytes and the payload; `encode` / `decode` move it to and from bytes;
// options are built into a caller buffer in ascending number order with
// `options_add` / `options_add_uint` and read back with `option_next`
// (delta encoding with the 13/14 extension bytes, 15 is `Malformed`);
// `request` assembles a whole request from URI segments; `Exchange` is one
// row of a client table driven by an explicit clock (`exchange_send`,
// `exchange_receive` matching acks by id and responses by token,
// `exchange_timeouts` on the section 4.2 schedule: ACK_TIMEOUT 2 s, random
// factor 1.5 from a caller `jitter`, four retransmissions, then `Timeout`);
// `block_encode` / `block_decode` are the RFC 7959 Block1/Block2 values.

type Message = struct { kind: u8, code: u8, id: u16, token: []const u8, options: []const u8, payload: []const u8 }
type Exchange = struct { id: u16, token: []const u8, state: State, retries: u32, deadline: u64, timeout: u64, confirmable: bool }
type State = enum u8 { Idle, Waiting, Acked, Done, Failed }
type Reply = enum u8 { None, Piggybacked, Separate, EmptyAck, Reset }
error Malformed
error TooSmall
error Invalid
error Timeout

// ---- constants -------------------------------------------------------------

fn kind_con() -> u8 { ret 0u8 }
fn kind_non() -> u8 { ret 1u8 }
fn kind_ack() -> u8 { ret 2u8 }
fn kind_rst() -> u8 { ret 3u8 }

fn code(class: u8, detail: u8) -> u8 { ret ((class & 7u8) << 5u32) | (detail & 31u8) }
fn code_class(c: u8) -> u8 { ret c >> 5u32 }
fn code_detail(c: u8) -> u8 { ret c & 31u8 }
fn code_empty() -> u8 { ret 0u8 }
fn code_get() -> u8 { ret 1u8 }
fn code_post() -> u8 { ret 2u8 }
fn code_put() -> u8 { ret 3u8 }
fn code_delete() -> u8 { ret 4u8 }
fn code_content() -> u8 { ret code(2u8, 5u8) }
fn code_not_found() -> u8 { ret code(4u8, 4u8) }

fn opt_uri_host() -> u16 { ret 3u16 }
fn opt_etag() -> u16 { ret 4u16 }
fn opt_observe() -> u16 { ret 6u16 }
fn opt_uri_port() -> u16 { ret 7u16 }
fn opt_location_path() -> u16 { ret 8u16 }
fn opt_uri_path() -> u16 { ret 11u16 }
fn opt_content_format() -> u16 { ret 12u16 }
fn opt_max_age() -> u16 { ret 14u16 }
fn opt_uri_query() -> u16 { ret 15u16 }
fn opt_accept() -> u16 { ret 17u16 }
fn opt_block2() -> u16 { ret 23u16 }
fn opt_block1() -> u16 { ret 27u16 }
fn opt_size2() -> u16 { ret 28u16 }
fn opt_size1() -> u16 { ret 60u16 }

fn ack_timeout_ms() -> u64 { ret 2000u64 }
fn ack_random_factor() -> f64 { ret 1.5f64 }
fn max_retransmit() -> u32 { ret 4u32 }

// ---- options -----------------------------------------------------------------

// The nibble and the count of extension bytes for a delta or length.
fn ext_nibble(v: usize) -> (u8, usize) {
    if v < 13usize { ret (u8(v), 0usize) }
    if v < 269usize { ret (13u8, 1usize) }
    ret (14u8, 2usize)
}

fn write_ext(dst: []u8, p: usize, v: usize) -> usize {
    if v < 13usize { ret p }
    if v < 269usize {
        dst[p] = u8(v - 13usize)
        ret p + 1usize
    }
    let w = v - 269usize
    dst[p] = u8((w >> 8u32) & 255usize)
    dst[p + 1usize] = u8(w & 255usize)
    ret p + 2usize
}

// Append option `number` with `value` after `*used` bytes of `buf`; numbers
// must not decrease (`Invalid`), `TooSmall` when `buf` cannot hold it.
fn options_add(buf: []u8, used: *usize, last_number: *u16, number: u16, value: []const u8) -> err {
    if number < *last_number || value.len > 65804usize { ret Invalid }
    let delta = usize(number - *last_number)
    let (dn, de) = ext_nibble(delta)
    let (ln, le) = ext_nibble(value.len)
    if buf.len - *used < 1usize + de + le + value.len { ret TooSmall }
    var p = *used
    buf[p] = (dn << 4u32) | ln
    p = write_ext(buf, p + 1usize, delta)
    p = write_ext(buf, p, value.len)
    var i = 0usize
    while i < value.len {
        buf[p + i] = value[i]
        i += 1usize
    }
    *used = p + value.len
    *last_number = number
    ret ok
}

// A uint option in its minimal big-endian length (0 is the empty value).
fn options_add_uint(buf: []u8, used: *usize, last_number: *u16, number: u16, value: u32) -> err {
    var tmp: [4]u8 = zero
    var n = 0usize
    var v = value
    while v != 0u32 {
        n += 1usize
        tmp[4usize - n] = u8(v & 255u32)
        v = v >> 8u32
    }
    ret options_add(buf, used, last_number, number, tmp[4usize - n..])
}

// Decode a uint option value (at most 4 bytes, else `Malformed`).
fn option_uint(value: []const u8) -> (u32, err) {
    if value.len > 4usize { ret (0u32, Malformed) }
    var v = 0u32
    var i = 0usize
    while i < value.len {
        v = (v << 8u32) | u32(value[i])
        i += 1usize
    }
    ret (v, ok)
}

// Read one delta-or-length field: (value, position after its extension bytes).
fn read_ext(src: []const u8, nibble: u8, p: usize) -> (usize, usize, err) {
    if nibble < 13u8 { ret (usize(nibble), p, ok) }
    if nibble == 15u8 { ret (0usize, p, Malformed) }
    if nibble == 13u8 {
        if p >= src.len { ret (0usize, p, Malformed) }
        ret (13usize + usize(src[p]), p + 1usize, ok)
    }
    if p + 1usize >= src.len { ret (0usize, p, Malformed) }
    ret (269usize + (usize(src[p]) << 8u32) + usize(src[p + 1usize]), p + 2usize, ok)
}

// The option at `p`: (delta, value start, value length, err).
fn parse_option(src: []const u8, p: usize) -> (usize, usize, usize, err) {
    let (delta, p1, de) = read_ext(src, src[p] >> 4u32, p + 1usize)
    if de != ok { ret (0usize, 0usize, 0usize, de) }
    let (len, p2, le) = read_ext(src, src[p] & 15u8, p1)
    if le != ok { ret (0usize, 0usize, 0usize, le) }
    if p2 + len > src.len { ret (0usize, 0usize, 0usize, Malformed) }
    ret (delta, p2, len, ok)
}

// The next option of `options` from `*pos`: (number, value, another follows,
// err). At the end answers (0, empty, false, ok).
fn option_next(options: []const u8, pos: *usize, last: *u16) -> (u16, []const u8, bool, err) {
    if *pos >= options.len { ret (0u16, options[..0usize], false, ok) }
    let (delta, start, len, e) = parse_option(options, *pos)
    if e != ok { ret (0u16, options[..0usize], false, e) }
    if usize(*last) + delta > 65535usize { ret (0u16, options[..0usize], false, Malformed) }
    *last = u16(usize(*last) + delta)
    *pos = start + len
    ret (*last, options[start..start + len], *pos < options.len, ok)
}

// ---- messages ----------------------------------------------------------------

fn encode(dst: []u8, m: *const Message) -> (usize, err) {
    if m.kind > 3u8 || m.token.len > 8usize { ret (0usize, Invalid) }
    var need = 4usize + m.token.len + m.options.len
    if m.payload.len > 0usize { need += 1usize + m.payload.len }
    if dst.len < need { ret (0usize, TooSmall) }
    dst[0usize] = 64u8 | (m.kind << 4u32) | u8(m.token.len)
    dst[1usize] = m.code
    dst[2usize] = u8(m.id >> 8u32)
    dst[3usize] = u8(m.id & 255u16)
    var p = 4usize
    p = append(dst, p, m.token)
    p = append(dst, p, m.options)
    if m.payload.len > 0usize {
        dst[p] = 255u8
        p = append(dst, p + 1usize, m.payload)
    }
    ret (p, ok)
}

fn append(dst: []u8, p: usize, src: []const u8) -> usize {
    var i = 0usize
    while i < src.len {
        dst[p + i] = src[i]
        i += 1usize
    }
    ret p + src.len
}

// `Malformed` for a short header, version other than 1, token length over 8,
// a bad option (delta or length nibble 15, truncated extension or value) or
// a payload marker with nothing after it. The option bytes are validated but
// kept raw; walk them with `option_next`.
fn decode(src: []const u8) -> (Message, err) {
    let none = Message { kind: 0u8, code: 0u8, id: 0u16, token: src[..0usize], options: src[..0usize], payload: src[..0usize] }
    if src.len < 4usize || (src[0usize] >> 6u32) != 1u8 { ret (none, Malformed) }
    let tkl = usize(src[0usize] & 15u8)
    if tkl > 8usize || 4usize + tkl > src.len { ret (none, Malformed) }
    let opt_start = 4usize + tkl
    var p = opt_start
    var last = 0usize
    while p < src.len && src[p] != 255u8 {
        let (delta, start, len, e) = parse_option(src, p)
        if e != ok { ret (none, e) }
        last += delta
        if last > 65535usize { ret (none, Malformed) }
        p = start + len
    }
    var payload = src[..0usize]
    if p < src.len {
        if p + 1usize >= src.len { ret (none, Malformed) }
        payload = src[p + 1usize..]
    }
    let m = Message { kind: (src[0usize] >> 4u32) & 3u8, code: src[1usize], id: (u16(src[2usize]) << 8u32) | u16(src[3usize]), token: src[4usize..opt_start], options: src[opt_start..p], payload: payload }
    ret (m, ok)
}

// A complete request into `dst`: `method` is a 0.xx code, one Uri-Path
// option per segment, Content-Format when `content_format` is not -1, one
// Uri-Query per query, then the payload.
fn request(dst: []u8, method: u8, uri_path: []const str, uri_query: []const str, token: []const u8, id: u16, confirmable: bool, payload: []const u8, content_format: i32) -> (usize, err) {
    if token.len > 8usize || code_class(method) != 0u8 { ret (0usize, Invalid) }
    var kind = kind_non()
    if confirmable { kind = kind_con() }
    let head = 4usize + token.len
    if dst.len < head { ret (0usize, TooSmall) }
    var used = 0usize
    var last = 0u16
    var i = 0usize
    while i < uri_path.len {
        let e = options_add(dst[head..], &used, &last, opt_uri_path(), uri_path[i])
        if e != ok { ret (0usize, e) }
        i += 1usize
    }
    if content_format >= 0i32 {
        let e = options_add_uint(dst[head..], &used, &last, opt_content_format(), u32(content_format))
        if e != ok { ret (0usize, e) }
    }
    i = 0usize
    while i < uri_query.len {
        let e = options_add(dst[head..], &used, &last, opt_uri_query(), uri_query[i])
        if e != ok { ret (0usize, e) }
        i += 1usize
    }
    let m = Message { kind: kind, code: method, id: id, token: token, options: dst[head..head + used], payload: payload }
    // The options already sit at their final place; encode re-copies them onto themselves.
    let (n, e) = encode(dst, &m)
    ret (n, e)
}

// ---- client exchange ---------------------------------------------------------

fn exchange() -> Exchange {
    var none: []const u8 = zero
    ret Exchange { id: 0u16, token: none, state: .Idle, retries: 0u32, deadline: 0u64, timeout: 0u64, confirmable: false }
}

// The initial timeout: ACK_TIMEOUT scaled by 1 + jitter * (ACK_RANDOM_FACTOR - 1),
// so `jitter` 0 is 2000 ms and 1 is 3000 ms (the RFC's worst case).
fn initial_timeout(jitter: f64) -> u64 {
    var j = jitter
    if j < 0.0f64 { j = 0.0f64 }
    if j > 1.0f64 { j = 1.0f64 }
    ret u64(f64(ack_timeout_ms()) * (1.0f64 + j * (ack_random_factor() - 1.0f64)))
}

// Record a request sent at `now`; a confirmable one waits for its ack on the
// retransmission schedule, a non-confirmable one only for a response by token.
fn exchange_send(x: *Exchange, now: u64, id: u16, token: []const u8, confirmable: bool, jitter: f64) {
    x.id = id
    x.token = token
    x.confirmable = confirmable
    x.retries = 0u32
    x.timeout = initial_timeout(jitter)
    x.deadline = now + x.timeout
    if confirmable { x.state = .Waiting } else { x.state = .Acked }
}

fn token_eq(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// Match `m` against the exchange: an ACK by id (empty stops retransmission,
// a response code is piggybacked), an RST by id fails it, a CON/NON response
// by token is a separate response. Answers whether it matched and how.
fn exchange_receive(x: *Exchange, m: *const Message) -> (bool, Reply, err) {
    if x.state == .Idle || x.state == .Done || x.state == .Failed { ret (false, .None, ok) }
    if m.kind == kind_ack() && m.id == x.id && x.state == .Waiting {
        if m.code == code_empty() {
            x.state = .Acked
            ret (true, .EmptyAck, ok)
        }
        x.state = .Done
        ret (true, .Piggybacked, ok)
    }
    if m.kind == kind_rst() && m.id == x.id {
        x.state = .Failed
        ret (true, .Reset, ok)
    }
    if (m.kind == kind_con() || m.kind == kind_non()) && code_class(m.code) != 0u8 && token_eq(m.token, x.token) {
        x.state = .Done
        ret (true, .Separate, ok)
    }
    ret (false, .None, ok)
}

// Poll the table at `now`: every confirmable exchange still waiting past its
// deadline is listed in `out` for retransmission (its timeout doubles); one
// that has already been retransmitted MAX_RETRANSMIT times fails instead and
// `Timeout` is answered alongside the count written.
fn exchange_timeouts(xs: []Exchange, now: u64, out: []u16) -> (usize, err) {
    var n = 0usize
    var e = ok
    var i = 0usize
    while i < xs.len {
        if xs[i].state == .Waiting && xs[i].confirmable && now >= xs[i].deadline {
            if xs[i].retries >= max_retransmit() {
                xs[i].state = .Failed
                e = Timeout
            } else {
                xs[i].retries += 1u32
                xs[i].timeout = xs[i].timeout * 2u64
                xs[i].deadline = now + xs[i].timeout
                if n < out.len { out[n] = xs[i].id }
                n += 1usize
            }
        }
        i += 1usize
    }
    ret (n, e)
}

// ---- RFC 7959 block options ----------------------------------------------------

// Block1/Block2 value: NUM << 4 | M << 3 | SZX (block size 2^(SZX+4)).
fn block_encode(num: u32, more: bool, szx: u8) -> u32 {
    var v = (num << 4u32) | u32(szx & 7u8)
    if more { v = v | 8u32 }
    ret v
}

fn block_decode(v: u32) -> (u32, bool, u8) {
    ret (v >> 4u32, (v & 8u32) != 0u32, u8(v & 7u32))
}

fn block_size(szx: u8) -> usize { ret 1usize << (u32(szx & 7u8) + 4u32) }
