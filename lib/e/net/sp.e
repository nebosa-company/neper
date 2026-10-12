// NNG / nanomsg scalability-protocols wire (SP over TCP) and the brokerless survey, request,
// publish and push patterns on one connection, over `e.net` TCP sockets. Companion to
// `e.net.zmtp`: the same blocking one-connection-at-a-time model, no broker, no thread.
//
// Wire (verified against NNG 1.x streams). Each side sends an 8-byte handshake `00 'S' 'P' 00`,
// its protocol number (u16 big endian), `00 00`, and expects the peer's; the pair must be
// compatible. A message is a u64 big-endian length then that many bytes. REQ/REP and
// SURVEYOR/RESPONDENT messages start with a 4-byte big-endian id whose high bit is set (the
// request id or the survey id, echoed in the answer); PUB/SUB, PUSH/PULL, PAIR and BUS carry
// the payload as is. SUB filtering is by payload prefix, done on the receiving side.
//
// Patterns. A surveyor stamps a fresh id on the question, then reads answers until the caller
// stops; answers carrying another id (a late reply to an earlier survey) are skipped. A
// respondent reads a question, keeps its id, and answers with it. REQ and REP work the same
// way with request ids. Not here: raw mode and multi-hop backtraces (a REP behind a device
// sees extra ids), TLS or websocket transports, reconnect, and the timeout options (a
// surveyor stops reading when it has the answers it expected or the connection ends).

use e.mem
use e.net

type Protocol = enum u8 { Pair, Pub, Sub, Req, Rep, Push, Pull, Surveyor, Respondent, Bus }
type Conn = struct { sock: net.Socket, buf: []u8, filled: usize, consumed: usize, local: Protocol, remote: Protocol, ready: bool, next_id: u32 }
error Malformed
error NeedMore
error TooSmall
error Incompatible
error Closed
error TooLarge
error NoId

fn number_of(p: Protocol) -> u16 {
    if p == .Pair { ret 16u16 }
    if p == .Pub { ret 32u16 }
    if p == .Sub { ret 33u16 }
    if p == .Req { ret 48u16 }
    if p == .Rep { ret 49u16 }
    if p == .Push { ret 80u16 }
    if p == .Pull { ret 81u16 }
    if p == .Surveyor { ret 98u16 }
    if p == .Respondent { ret 99u16 }
    ret 112u16
}

fn protocol_of(number: u16) -> (Protocol, bool) {
    if number == 16u16 { ret (.Pair, true) }
    if number == 32u16 { ret (.Pub, true) }
    if number == 33u16 { ret (.Sub, true) }
    if number == 48u16 { ret (.Req, true) }
    if number == 49u16 { ret (.Rep, true) }
    if number == 80u16 { ret (.Push, true) }
    if number == 81u16 { ret (.Pull, true) }
    if number == 98u16 { ret (.Surveyor, true) }
    if number == 99u16 { ret (.Respondent, true) }
    if number == 112u16 { ret (.Bus, true) }
    ret (.Pair, false)
}

// The protocol a peer must speak to talk to `p`.
fn peer_of(p: Protocol) -> Protocol {
    if p == .Pub { ret .Sub }
    if p == .Sub { ret .Pub }
    if p == .Req { ret .Rep }
    if p == .Rep { ret .Req }
    if p == .Push { ret .Pull }
    if p == .Pull { ret .Push }
    if p == .Surveyor { ret .Respondent }
    if p == .Respondent { ret .Surveyor }
    ret p
}

fn carries_id(p: Protocol) -> bool { ret p == .Req || p == .Rep || p == .Surveyor || p == .Respondent }

fn encode_handshake(dst: []u8, p: Protocol) -> (usize, err) {
    if dst.len < 8usize { ret (0usize, TooSmall) }
    let n = number_of(p)
    dst[0usize] = 0u8
    dst[1usize] = 83u8
    dst[2usize] = 80u8
    dst[3usize] = 0u8
    dst[4usize] = u8(n >> 8u32)
    dst[5usize] = u8(n & 255u16)
    dst[6usize] = 0u8
    dst[7usize] = 0u8
    ret (8usize, ok)
}

fn decode_handshake(src: []const u8) -> (Protocol, err) {
    if src.len < 8usize { ret (.Pair, NeedMore) }
    if src[0usize] != 0u8 || src[1usize] != 83u8 || src[2usize] != 80u8 || src[3usize] != 0u8 { ret (.Pair, Malformed) }
    let (p, known) = protocol_of(u16(src[4usize]) * 256u16 + u16(src[5usize]))
    if !known { ret (.Pair, Malformed) }
    ret (p, ok)
}

// A message with an optional 4-byte `id` header (`has_id`) followed by `payload`.
fn encode_message(dst: []u8, has_id: bool, id: u32, payload: []const u8) -> (usize, err) {
    var header = 0usize
    if has_id { header = 4usize }
    let total = header + payload.len
    if dst.len < 8usize + total { ret (0usize, TooSmall) }
    var i = 0usize
    while i < 8usize {
        dst[i] = u8((u64(total) >> u64((7usize - i) * 8usize)) & 255u64)
        i += 1usize
    }
    if has_id {
        dst[8usize] = u8(id >> 24u32)
        dst[9usize] = u8((id >> 16u32) & 255u32)
        dst[10usize] = u8((id >> 8u32) & 255u32)
        dst[11usize] = u8(id & 255u32)
    }
    var k = 0usize
    while k < payload.len {
        dst[8usize + header + k] = payload[k]
        k += 1usize
    }
    ret (8usize + total, ok)
}

// One message at the front of `src`: its body (a slice of `src`) and the bytes consumed.
fn decode_message(src: []const u8) -> ([]const u8, usize, err) {
    if src.len < 8usize { ret (src[0usize..0usize], 0usize, NeedMore) }
    var length = 0u64
    var i = 0usize
    while i < 8usize {
        length = length * 256u64 + u64(src[i])
        i += 1usize
    }
    if length > 1073741824u64 { ret (src[0usize..0usize], 0usize, TooLarge) }
    let total = 8usize + usize(length)
    if src.len < total { ret (src[0usize..0usize], 0usize, NeedMore) }
    ret (src[8usize..total], total, ok)
}

// Splits the id off a REQ/REP/SURVEY body: (id, payload); `NoId` when the high bit is not set.
fn split_id(body: []const u8) -> (u32, []const u8, err) {
    if body.len < 4usize { ret (0u32, body[0usize..0usize], NoId) }
    if body[0usize] & 128u8 == 0u8 { ret (0u32, body[4usize..body.len], NoId) }
    let id = ((u32(body[0usize]) * 256u32 + u32(body[1usize])) * 256u32 + u32(body[2usize])) * 256u32 + u32(body[3usize])
    ret (id, body[4usize..body.len], ok)
}

fn topic_matches(prefix: []const u8, payload: []const u8) -> bool {
    if prefix.len > payload.len { ret false }
    var i = 0usize
    while i < prefix.len {
        if prefix[i] != payload[i] { ret false }
        i += 1usize
    }
    ret true
}

// ---- a blocking connection ----

fn conn(sock: net.Socket, buf: []u8, local: Protocol, first_id: u32) -> Conn {
    var c: Conn = zero
    c.sock = sock
    c.buf = buf
    c.local = local
    c.next_id = first_id
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

fn handshake(c: *Conn) -> err {
    var out: [8]u8 = zero
    let (n, e) = encode_handshake(out[0usize..8usize], c.local)
    if e != ok { ret e }
    try send_all(c.sock, out[0usize..n])
    while c.filled - c.consumed < 8usize { try fill(c) }
    let (p, pe) = decode_handshake(c.buf[c.consumed..c.filled])
    if pe != ok { ret pe }
    c.consumed += 8usize
    if peer_of(c.local) != p { ret Incompatible }
    c.remote = p
    c.ready = true
    ret ok
}

// Sends `payload`; REQ/REP/SURVEY protocols prefix `id` (use `next_question_id` to mint one).
fn send(c: *Conn, id: u32, payload: []const u8) -> err {
    var small: [1500]u8 = zero
    let with_id = carries_id(c.local)
    if payload.len + 12usize <= 1500usize {
        let (n, e) = encode_message(small[0usize..1500usize], with_id, id, payload)
        if e != ok { ret e }
        ret send_all(c.sock, small[0usize..n])
    }
    // large: the header first, then the payload straight from the caller's slice
    let (hn, he) = encode_message(small[0usize..1500usize], with_id, id, payload[0usize..0usize])
    if he != ok { ret he }
    var total = payload.len
    if with_id { total += 4usize }
    var i = 0usize
    while i < 8usize {
        small[i] = u8((u64(total) >> u64((7usize - i) * 8usize)) & 255u64)
        i += 1usize
    }
    var head = 8usize
    if with_id { head = 12usize }
    try send_all(c.sock, small[0usize..head])
    ret send_all(c.sock, payload)
}

// Next message body, valid until the next read from this connection.
fn recv(c: *Conn) -> ([]const u8, err) {
    while true {
        let (body, used, e) = decode_message(c.buf[c.consumed..c.filled])
        if e == NeedMore {
            if c.filled >= c.buf.len && c.consumed > 0usize {
                var i = 0usize
                while i < c.filled - c.consumed {
                    c.buf[i] = c.buf[c.consumed + i]
                    i += 1usize
                }
                c.filled -= c.consumed
                c.consumed = 0usize
            }
            let fe = fill(c)
            if fe != ok { ret (body, fe) }
            continue
        }
        if e != ok { ret (body, e) }
        c.consumed += used
        ret (body, ok)
    }
    var none: []const u8 = zero
    ret (none, Malformed)
}

// A fresh survey or request id: the counter with the high bit set.
fn next_question_id(c: *Conn) -> u32 {
    let id = c.next_id | 2147483648u32
    c.next_id += 1u32
    ret id
}

// Surveyor/Req: the next answer to survey `id`, skipping answers to other ids. Returns the payload.
fn recv_answer(c: *Conn, id: u32) -> ([]const u8, err) {
    while true {
        let (body, e) = recv(c)
        if e != ok { ret (body, e) }
        let (got, payload, se) = split_id(body)
        if se != ok { continue }
        if got == id { ret (payload, ok) }
    }
    var none: []const u8 = zero
    ret (none, Malformed)
}

// Respondent/Rep: the next question as (id, payload).
fn recv_question(c: *Conn) -> (u32, []const u8, err) {
    while true {
        let (body, e) = recv(c)
        if e != ok { ret (0u32, body, e) }
        let (id, payload, se) = split_id(body)
        if se == ok { ret (id, payload, ok) }
    }
    var none: []const u8 = zero
    ret (0u32, none, Malformed)
}
