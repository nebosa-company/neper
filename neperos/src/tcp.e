// The NeperOS TCP client (D2245, C117): one active connection over the inet stack. It is
// stop-and-wait on the way out -- a segment is sent and retransmitted until it is acknowledged --
// and takes data in order only on the way in, into a 64 KB ring it advertises the free space of;
// an out-of-order segment is answered with the ACK that asks for the missing one again. That is
// all a request/response client needs, and it keeps the state small enough to read at a glance.
// Sequence numbers wrap, so every comparison goes through a difference.
use e.os
use e.mem
use inet

error Reset
error Timeout

const FIN: u8 = 1u8
const SYN: u8 = 2u8
const RST: u8 = 4u8
const PSH: u8 = 8u8
const ACK: u8 = 16u8

const TCP_HDR: usize = 20usize
const MSS: usize = 1400usize
const RING: usize = 65536usize

const CLOSED: u8 = 0u8
const SYN_SENT: u8 = 1u8
const ESTABLISHED: u8 = 2u8

type Conn = struct { st: *inet.Stack, lport: u16, rip: u32, rport: u16, snd_nxt: u32, snd_una: u32, rcv_nxt: u32, ring: usize, head: usize, count: usize, state: u8, peer_fin: bool, reset: bool, peer_window: usize }

var next_port: u16 = 49152u16
var next_iss: u32 = 1000u32

// True when sequence number `a` is at or after `b` (within half the sequence space).
fn at_or_after(a: u32, b: u32) -> bool {
    ret (a -% b) < 2147483648u32
}

// Send one segment of this connection: `flags`, sequence number `seq`, `len` bytes from `data`.
// A SYN carries the MSS option.
fn emit(c: *Conn, flags: u8, seq: u32, data: usize, len: usize) -> err {
    let st = c.st
    let at = inet.ip_payload(st)
    var header = TCP_HDR
    if (flags & SYN) != 0u8 { header = TCP_HDR + 4usize }
    inet.put16(at, c.lport)
    inet.put16(at + 2usize, c.rport)
    inet.put32(at + 4usize, seq)
    var ack_number = 0u32
    if (flags & ACK) != 0u8 { ack_number = c.rcv_nxt }
    inet.put32(at + 8usize, ack_number)
    os.store8(at + 12usize, u8(header / 4usize) << 4u8)
    os.store8(at + 13usize, flags)
    var window = RING - c.count
    if window > 65535usize { window = 65535usize }
    inet.put16(at + 14usize, u16(window))
    inet.put16(at + 16usize, 0u16)
    inet.put16(at + 18usize, 0u16)
    if (flags & SYN) != 0u8 {
        os.store8(at + 20usize, 2u8)
        os.store8(at + 21usize, 4u8)
        inet.put16(at + 22usize, u16(MSS))
    }
    inet.copy(at + header, data, len)
    inet.put16(at + 16usize, inet.checksum(at, header + len, inet.pseudo(st.ip, c.rip, inet.PROTO_TCP, header + len)))
    ret inet.ip_send(st, inet.PROTO_TCP, c.rip, header + len)
}

fn ack_now(c: *Conn) {
    let sent = emit(c, ACK, c.snd_nxt, 0usize, 0usize)
}

// Take one received TCP segment for this connection into account.
fn handle(c: *Conn, seg: usize, seg_len: usize) {
    if seg_len < TCP_HDR || inet.get16(seg) != c.rport || inet.get16(seg + 2usize) != c.lport { ret }
    let flags = os.load8(seg + 13usize)
    let seq = inet.get32(seg + 4usize)
    let ack_number = inet.get32(seg + 8usize)
    let header = usize(os.load8(seg + 12usize) >> 4u8) * 4usize
    if header < TCP_HDR || header > seg_len { ret }
    var data_len = seg_len - header
    if (flags & RST) != 0u8 {
        c.reset = true
        c.state = CLOSED
        ret
    }
    if c.state == SYN_SENT {
        if (flags & (SYN | ACK)) == (SYN | ACK) && ack_number == c.snd_nxt {
            c.rcv_nxt = seq +% 1u32
            c.snd_una = ack_number
            c.state = ESTABLISHED
            c.peer_window = usize(inet.get16(seg + 14usize))
            ack_now(c)
        }
        ret
    }
    if (flags & ACK) != 0u8 && at_or_after(ack_number, c.snd_una) && at_or_after(c.snd_nxt, ack_number) {
        c.snd_una = ack_number
        c.peer_window = usize(inet.get16(seg + 14usize))
    }
    if data_len > 0usize {
        if seq == c.rcv_nxt {
            var take = data_len
            if take > RING - c.count { take = RING - c.count }
            var i = 0usize
            while i < take {
                os.store8(c.ring + (c.head + c.count + i) % RING, os.load8(seg + header + i))
                i += 1usize
            }
            c.count += take
            c.rcv_nxt = c.rcv_nxt +% u32(take)
            data_len = take
        }
        ack_now(c)
    }
    if (flags & FIN) != 0u8 && (seq +% u32(seg_len - header)) == c.rcv_nxt && !c.peer_fin {
        c.peer_fin = true
        c.rcv_nxt = c.rcv_nxt +% 1u32
        ack_now(c)
    }
}

// Receive one frame and, if it is a TCP segment from the peer, handle it.
fn pump(c: *Conn) {
    let (proto, src, payload, len) = inet.poll(c.st)
    if proto == inet.PROTO_TCP && src == c.rip { handle(c, payload, len) }
}

// Open a connection to `rip`:`rport`, with `ring` the address of a RING-byte buffer for incoming data.
fn connect(st: *inet.Stack, rip: u32, rport: u16, ring: usize) -> (Conn, err) {
    var c = Conn { st: st, lport: next_port, rip: rip, rport: rport, snd_nxt: next_iss, snd_una: next_iss, rcv_nxt: 0u32, ring: ring, head: 0usize, count: 0usize, state: SYN_SENT, peer_fin: false, reset: false, peer_window: 0usize }
    next_port += 1u16
    next_iss = next_iss +% 64000u32
    var attempt = 0usize
    while attempt < 4usize {
        let send_error = emit(&c, SYN, c.snd_una, 0usize, 0usize)
        if send_error != ok { ret (c, send_error) }
        c.snd_nxt = c.snd_una +% 1u32
        var spins = 0usize
        while spins < inet.POLLS && c.state == SYN_SENT {
            pump(&c)
            spins += 1usize
        }
        if c.state == ESTABLISHED { ret (c, ok) }
        if c.reset { ret (c, Reset) }
        attempt += 1usize
    }
    ret (c, Timeout)
}

// Send `len` bytes from `data`: one segment at a time, each retransmitted until acknowledged.
fn write(c: *Conn, data: usize, len: usize) -> err {
    var sent = 0usize
    while sent < len {
        if c.state != ESTABLISHED { ret Reset }
        var chunk = len - sent
        if chunk > MSS { chunk = MSS }
        let seq = c.snd_nxt
        let done = seq +% u32(chunk)
        var attempt = 0usize
        var acked = false
        while attempt < 6usize && !acked {
            let send_error = emit(c, ACK | PSH, seq, data + sent, chunk)
            if send_error != ok { ret send_error }
            c.snd_nxt = done
            var spins = 0usize
            while spins < inet.POLLS && !at_or_after(c.snd_una, done) && c.state == ESTABLISHED {
                pump(c)
                spins += 1usize
            }
            if at_or_after(c.snd_una, done) { acked = true }
            attempt += 1usize
        }
        if !acked { ret Timeout }
        sent += chunk
    }
    ret ok
}

// Read up to `max` bytes into `dst`. Zero bytes with ok is the peer's close; Timeout is silence.
fn read(c: *Conn, dst: usize, max: usize) -> (usize, err) {
    var spins = 0usize
    while c.count == 0usize && !c.peer_fin && !c.reset && spins < inet.POLLS * 8usize {
        pump(c)
        spins += 1usize
    }
    if c.count == 0usize {
        if c.reset { ret (0usize, Reset) }
        if c.peer_fin { ret (0usize, ok) }
        ret (0usize, Timeout)
    }
    var n = c.count
    if n > max { n = max }
    var i = 0usize
    while i < n {
        os.store8(dst + i, os.load8(c.ring + (c.head + i) % RING))
        i += 1usize
    }
    let was_full = RING - c.count < 4usize * MSS
    c.head = (c.head + n) % RING
    c.count -= n
    // A window that had nearly closed is told it has reopened.
    if was_full { ack_now(c) }
    ret (n, ok)
}

// Close our side and give the peer a moment to answer.
fn close(c: *Conn) -> err {
    if c.state != ESTABLISHED { ret ok }
    let fin_seq = c.snd_nxt
    let fin_end = fin_seq +% 1u32
    var attempt = 0usize
    while attempt < 3usize && !at_or_after(c.snd_una, fin_end) {
        let send_error = emit(c, FIN | ACK, fin_seq, 0usize, 0usize)
        if send_error != ok { ret send_error }
        c.snd_nxt = fin_end
        var spins = 0usize
        while spins < inet.POLLS && !at_or_after(c.snd_una, fin_end) && !c.reset {
            pump(c)
            spins += 1usize
        }
        attempt += 1usize
    }
    c.state = CLOSED
    ret ok
}
