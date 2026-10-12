// TFTP (RFC 1350) with the option extension (RFC 2347 OACK, 2348 `blksize`, 2349 `tsize`,
// RFC 2349 `timeout`), as caller-buffer codecs and a sans-IO client transfer. Nothing here
// touches a socket: `read_start`/`write_start` build the first packet, each datagram that
// arrives goes to `read_step`/`write_step`, and the answer is the next datagram to send and
// whether the transfer is over. The caller owns the UDP socket, the retransmission timer
// (resend the last packet on a timeout) and the TID rule: the request goes to the server's
// port 69, every later packet to the source port of the first reply.
//
// Packets: opcode (u16 big endian) then RRQ/WRQ `filename\0mode\0[option\0value\0]*`,
// DATA `block data`, ACK `block`, ERROR `code message\0`, OACK `[option\0value\0]*`.
// A DATA packet shorter than the block size ends the transfer; block numbers wrap at 65535
// only in the sense of the u16 field (a transfer past 65535 blocks is refused here).

type Packet = struct { opcode: u16, block: u16, error_code: u16, text: str, mode: str, data: []const u8, options: []const u8 }
type Transfer = struct { writing: bool, block: u16, blksize: u16, tsize: u64, started: bool, done: bool, error_code: u16, data: []const u8, out: []u8, written: usize, last_len: usize }
type Step = struct { reply_len: usize, finished: bool }
error Malformed
error TooSmall
error Remote
error Protocol
error TooLong

fn op_rrq() -> u16 { ret 1u16 }
fn op_wrq() -> u16 { ret 2u16 }
fn op_data() -> u16 { ret 3u16 }
fn op_ack() -> u16 { ret 4u16 }
fn op_error() -> u16 { ret 5u16 }
fn op_oack() -> u16 { ret 6u16 }
fn default_blksize() -> u16 { ret 512u16 }

fn put_u16(dst: []u8, at: usize, v: u16) {
    dst[at] = u8(v >> 8u32)
    dst[at + 1usize] = u8(v & 255u16)
}

fn get_u16(src: []const u8, at: usize) -> u16 { ret u16(u32(src[at]) * 256u32 + u32(src[at + 1usize])) }

fn put_cstr(dst: []u8, at: usize, s: str) -> (usize, bool) {
    if at + s.len + 1usize > dst.len { ret (at, false) }
    var i = 0usize
    while i < s.len {
        dst[at + i] = s[i]
        i += 1usize
    }
    dst[at + s.len] = 0u8
    ret (at + s.len + 1usize, true)
}

// `option\0value\0` pairs for a request or OACK: `names[i]` with `values[i]`.
fn put_options(dst: []u8, at: usize, names: []const str, values: []const str) -> (usize, bool) {
    var n = at
    var i = 0usize
    while i < names.len {
        let (n1, f1) = put_cstr(dst, n, names[i])
        if !f1 { ret (at, false) }
        let (n2, f2) = put_cstr(dst, n1, values[i])
        if !f2 { ret (at, false) }
        n = n2
        i += 1usize
    }
    ret (n, true)
}

// RRQ (`writing == false`) or WRQ.
fn encode_request(writing: bool, filename: str, mode: str, names: []const str, values: []const str, dst: []u8) -> (usize, err) {
    if dst.len < 2usize { ret (0usize, TooSmall) }
    var op = op_rrq()
    if writing { op = op_wrq() }
    put_u16(dst, 0usize, op)
    let (n1, f1) = put_cstr(dst, 2usize, filename)
    if !f1 { ret (0usize, TooSmall) }
    let (n2, f2) = put_cstr(dst, n1, mode)
    if !f2 { ret (0usize, TooSmall) }
    let (n3, f3) = put_options(dst, n2, names, values)
    if !f3 { ret (0usize, TooSmall) }
    ret (n3, ok)
}

fn encode_data(block: u16, payload: []const u8, dst: []u8) -> (usize, err) {
    if dst.len < 4usize + payload.len { ret (0usize, TooSmall) }
    put_u16(dst, 0usize, op_data())
    put_u16(dst, 2usize, block)
    var i = 0usize
    while i < payload.len {
        dst[4usize + i] = payload[i]
        i += 1usize
    }
    ret (4usize + payload.len, ok)
}

fn encode_ack(block: u16, dst: []u8) -> (usize, err) {
    if dst.len < 4usize { ret (0usize, TooSmall) }
    put_u16(dst, 0usize, op_ack())
    put_u16(dst, 2usize, block)
    ret (4usize, ok)
}

fn encode_error(code: u16, message: str, dst: []u8) -> (usize, err) {
    if dst.len < 4usize { ret (0usize, TooSmall) }
    put_u16(dst, 0usize, op_error())
    put_u16(dst, 2usize, code)
    let (n, fits) = put_cstr(dst, 4usize, message)
    if !fits { ret (0usize, TooSmall) }
    ret (n, ok)
}

fn encode_oack(names: []const str, values: []const str, dst: []u8) -> (usize, err) {
    if dst.len < 2usize { ret (0usize, TooSmall) }
    put_u16(dst, 0usize, op_oack())
    let (n, fits) = put_options(dst, 2usize, names, values)
    if !fits { ret (0usize, TooSmall) }
    ret (n, ok)
}

// A NUL-terminated string at `at`; returns it and the index after the terminator.
fn read_cstr(src: []const u8, at: usize) -> (str, usize, bool) {
    var i = at
    while i < src.len && src[i] != 0u8 { i += 1usize }
    if i >= src.len { ret ("", at, false) }
    ret (src[at..i], i + 1usize, true)
}

// The option bytes of an OACK or request, as the raw `name\0value\0...` run; `option_next` walks it.
fn option_next(run: []const u8, at: usize) -> (str, str, usize, bool) {
    if at >= run.len { ret ("", "", at, false) }
    let (name, after_name, name_ok) = read_cstr(run, at)
    if !name_ok { ret ("", "", at, false) }
    let (value, after_value, value_ok) = read_cstr(run, after_name)
    if !value_ok { ret ("", "", at, false) }
    ret (name, value, after_value, true)
}

fn decode(src: []const u8) -> (Packet, err) {
    var p: Packet = zero
    if src.len < 2usize { ret (p, Malformed) }
    p.opcode = get_u16(src, 0usize)
    if p.opcode == op_rrq() || p.opcode == op_wrq() {
        let (filename, n1, f1) = read_cstr(src, 2usize)
        if !f1 || filename.len == 0usize { ret (p, Malformed) }
        let (mode, n2, f2) = read_cstr(src, n1)
        if !f2 { ret (p, Malformed) }
        p.text = filename
        p.mode = mode
        p.options = src[n2..src.len]
        // the option run must be whole pairs
        var at = 0usize
        while at < p.options.len {
            let (name, value, next, good) = option_next(p.options, at)
            if !good { ret (p, Malformed) }
            at = next
        }
        ret (p, ok)
    }
    if p.opcode == op_data() {
        if src.len < 4usize { ret (p, Malformed) }
        p.block = get_u16(src, 2usize)
        p.data = src[4usize..src.len]
        ret (p, ok)
    }
    if p.opcode == op_ack() {
        if src.len != 4usize { ret (p, Malformed) }
        p.block = get_u16(src, 2usize)
        ret (p, ok)
    }
    if p.opcode == op_error() {
        if src.len < 5usize { ret (p, Malformed) }
        p.error_code = get_u16(src, 2usize)
        let (message, n, good) = read_cstr(src, 4usize)
        if !good { ret (p, Malformed) }
        p.text = message
        ret (p, ok)
    }
    if p.opcode == op_oack() {
        p.options = src[2usize..src.len]
        var at = 0usize
        while at < p.options.len {
            let (name, value, next, good) = option_next(p.options, at)
            if !good { ret (p, Malformed) }
            at = next
        }
        ret (p, ok)
    }
    ret (p, Malformed)
}

fn number_text(v: u64, dst: []u8) -> str {
    var digits: [20]u8 = zero
    var count = 0usize
    var x = v
    if x == 0u64 {
        digits[0usize] = 48u8
        count = 1usize
    }
    while x > 0u64 {
        digits[count] = u8(48u64 + x % 10u64)
        count += 1usize
        x = x / 10u64
    }
    var k = 0usize
    while k < count {
        dst[k] = digits[count - 1usize - k]
        k += 1usize
    }
    ret dst[..count]
}

fn parse_number(s: str) -> (u64, bool) {
    if s.len == 0usize || s.len > 18usize { ret (0u64, false) }
    var v = 0u64
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret (0u64, false) }
        v = v * 10u64 + u64(s[i] - 48u8)
        i += 1usize
    }
    ret (v, true)
}

fn same_fold(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        var x = a[i]
        var y = b[i]
        if x >= 65u8 && x <= 90u8 { x += 32u8 }
        if y >= 65u8 && y <= 90u8 { y += 32u8 }
        if x != y { ret false }
        i += 1usize
    }
    ret true
}

// ---- client transfers ----

// Starts a download of `filename` into `out`. A `blksize` of 0 or 512 sends no option (plain
// RFC 1350); another value requests it (RFC 2348, 8..65464) and asks for `tsize`.
fn read_start(t: *Transfer, filename: str, mode: str, blksize: u16, out: []u8, request: []u8) -> (usize, err) {
    var fresh: Transfer = zero
    *t = fresh
    t.writing = false
    t.blksize = default_blksize()
    t.out = out
    t.started = true
    var names: [2]str = zero
    var values: [2]str = zero
    var count = 0usize
    var size_text: [8]u8 = zero
    if blksize != 0u16 && blksize != 512u16 {
        if blksize < 8u16 || blksize > 65464u16 { ret (0usize, Protocol) }
        names[0usize] = "blksize"
        values[0usize] = number_text(u64(blksize), size_text[0usize..8usize])
        names[1usize] = "tsize"
        values[1usize] = "0"
        count = 2usize
    }
    let (n, e) = encode_request(false, filename, mode, names[0usize..count], values[0usize..count], request)
    ret (n, e)
}

// Feeds one datagram from the server; writes the datagram to answer with into `reply`.
fn read_step(t: *Transfer, incoming: []const u8, reply: []u8) -> (Step, err) {
    var s: Step = zero
    let (p, decode_error) = decode(incoming)
    if decode_error != ok { ret (s, decode_error) }
    if p.opcode == op_error() {
        t.error_code = p.error_code
        t.done = true
        ret (s, Remote)
    }
    if p.opcode == op_oack() {
        if t.block != 0u16 || t.written != 0usize { ret (s, Protocol) }
        var at = 0usize
        while at < p.options.len {
            let (name, value, next, good) = option_next(p.options, at)
            if !good { ret (s, Malformed) }
            at = next
            if same_fold(name, "blksize") {
                let (v, number_ok) = parse_number(value)
                if !number_ok || v < 8u64 || v > 65464u64 { ret (s, Protocol) }
                t.blksize = u16(v)
            } else if same_fold(name, "tsize") {
                let (v, number_ok) = parse_number(value)
                if number_ok { t.tsize = v }
            }
        }
        let (n, e) = encode_ack(0u16, reply)
        if e != ok { ret (s, e) }
        s.reply_len = n
        ret (s, ok)
    }
    if p.opcode != op_data() { ret (s, Protocol) }
    let expected = t.block + 1u16
    if p.block == t.block && t.block != 0u16 {
        // the server did not see our ACK: answer it again, store nothing
        let (n, e) = encode_ack(p.block, reply)
        if e != ok { ret (s, e) }
        s.reply_len = n
        ret (s, ok)
    }
    if p.block != expected { ret (s, ok) }
    if p.data.len > usize(t.blksize) { ret (s, Protocol) }
    if t.written + p.data.len > t.out.len { ret (s, TooLong) }
    var i = 0usize
    while i < p.data.len {
        t.out[t.written + i] = p.data[i]
        i += 1usize
    }
    t.written += p.data.len
    t.block = expected
    let (n, e) = encode_ack(expected, reply)
    if e != ok { ret (s, e) }
    s.reply_len = n
    if p.data.len < usize(t.blksize) {
        t.done = true
        s.finished = true
    }
    ret (s, ok)
}

// Starts an upload of `data`. Option negotiation as for `read_start`, with `tsize` set to the length.
fn write_start(t: *Transfer, filename: str, mode: str, blksize: u16, data: []const u8, request: []u8) -> (usize, err) {
    var fresh: Transfer = zero
    *t = fresh
    t.writing = true
    t.blksize = default_blksize()
    t.data = data
    t.started = true
    var names: [2]str = zero
    var values: [2]str = zero
    var count = 0usize
    var size_text: [8]u8 = zero
    var total_text: [20]u8 = zero
    if blksize != 0u16 && blksize != 512u16 {
        if blksize < 8u16 || blksize > 65464u16 { ret (0usize, Protocol) }
        names[0usize] = "blksize"
        values[0usize] = number_text(u64(blksize), size_text[0usize..8usize])
        names[1usize] = "tsize"
        values[1usize] = number_text(u64(data.len), total_text[0usize..20usize])
        count = 2usize
    }
    let (n, e) = encode_request(true, filename, mode, names[0usize..count], values[0usize..count], request)
    ret (n, e)
}

// Feeds one datagram (ACK or OACK) and builds the next DATA packet into `reply`.
fn write_step(t: *Transfer, incoming: []const u8, reply: []u8) -> (Step, err) {
    var s: Step = zero
    let (p, decode_error) = decode(incoming)
    if decode_error != ok { ret (s, decode_error) }
    if p.opcode == op_error() {
        t.error_code = p.error_code
        t.done = true
        ret (s, Remote)
    }
    var acked = t.block
    if p.opcode == op_oack() {
        if t.block != 0u16 || t.written != 0usize { ret (s, Protocol) }
        var at = 0usize
        while at < p.options.len {
            let (name, value, next, good) = option_next(p.options, at)
            if !good { ret (s, Malformed) }
            at = next
            if same_fold(name, "blksize") {
                let (v, number_ok) = parse_number(value)
                if !number_ok || v < 8u64 || v > 65464u64 { ret (s, Protocol) }
                t.blksize = u16(v)
            }
        }
        acked = 0u16
    } else if p.opcode == op_ack() {
        acked = p.block
    } else {
        ret (s, Protocol)
    }
    // only the ACK for the block just sent advances the transfer; a duplicate is ignored
    if acked != t.block { ret (s, ok) }
    if t.written == t.data.len && t.block != 0u16 && t.last_len < usize(t.blksize) {
        t.done = true
        s.finished = true
        ret (s, ok)
    }
    let next_block = t.block + 1u16
    if next_block == 0u16 { ret (s, TooLong) }
    var take = t.data.len - t.written
    if take > usize(t.blksize) { take = usize(t.blksize) }
    let (n, e) = encode_data(next_block, t.data[t.written..t.written + take], reply)
    if e != ok { ret (s, e) }
    t.block = next_block
    t.written += take
    t.last_len = take
    s.reply_len = n
    ret (s, ok)
}
