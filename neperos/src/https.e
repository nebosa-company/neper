// TLS 1.3 over the NeperOS TCP client (D2246, C117): `e.net.tls` already speaks the protocol over
// any io.Reader and io.Writer, so the only thing to supply is the pair over a tcp.Conn, plus the
// bundled roots decoded from their embedded hex. The handshake validates the server's chain against
// those roots and its name against the one asked for, at the wall-clock time the kernel reports.
use e.io
use e.mem
use e.net.tls
use e.time
use tcp

error BadHex

fn hex_value(c: u8) -> (u8, bool) {
    if c >= 48u8 && c <= 57u8 { ret (c - 48u8, true) }
    if c >= 97u8 && c <= 102u8 { ret (c - 87u8, true) }
    if c >= 65u8 && c <= 70u8 { ret (c - 55u8, true) }
    ret (0u8, false)
}

// Hex text to bytes, in the arena.
fn decode_hex(a: *mem.Arena, text: str) -> ([]u8, err) {
    if text.len % 2usize != 0usize { ret (zero, BadHex) }
    let (out, alloc_error) = mem.alloc[u8](a, text.len / 2usize)
    if alloc_error != ok { ret (zero, alloc_error) }
    var i = 0usize
    while i < out.len {
        let (high, high_ok) = hex_value(text[2usize * i])
        let (low, low_ok) = hex_value(text[2usize * i + 1usize])
        if !high_ok || !low_ok { ret (zero, BadHex) }
        out[i] = (high << 4u8) | low
        i += 1usize
    }
    ret (out, ok)
}

fn conn_read(ctx: *void, dst: []u8) -> (usize, err) {
    var c = mem.cast[*tcp.Conn](ctx)
    if dst.len == 0usize { ret (0usize, ok) }
    let (n, read_error) = tcp.read(c, mem.address_of(&dst[0usize]), dst.len)
    if read_error != ok { ret (0usize, read_error) }
    if n == 0usize { ret (0usize, io.End) }
    ret (n, ok)
}

fn conn_write(ctx: *void, data: []const u8) -> (usize, err) {
    var c = mem.cast[*tcp.Conn](ctx)
    if data.len == 0usize { ret (0usize, ok) }
    let write_error = tcp.write(c, mem.address_of(&data[0usize]), data.len)
    if write_error != ok { ret (0usize, write_error) }
    ret (data.len, ok)
}

fn conn_flush(ctx: *void) -> err {
    ret ok
}

fn reader(c: *tcp.Conn) -> io.Reader {
    ret io.Reader { ctx: mem.cast[*void](c), read: conn_read }
}

fn writer(c: *tcp.Conn) -> io.Writer {
    ret io.Writer { ctx: mem.cast[*void](c), write: conn_write, flush: conn_flush }
}

// A TLS stream to the peer of `c`, handshake done. `roots_hex` is the trust set, `entropy` the 64
// random bytes the handshake draws its client random and key from.
fn connect(a: *mem.Arena, c: *tcp.Conn, server_name: str, roots_hex: str, entropy: []const u8) -> (tls.Stream, err) {
    let (roots, roots_error) = decode_hex(a, roots_hex)
    if roots_error != ok { ret (zero, roots_error) }
    let (now, now_error) = time.now()
    if now_error != ok { ret (zero, now_error) }
    let (none, none_error) = mem.alloc[str](a, 1usize)
    if none_error != ok { ret (zero, none_error) }
    let config = tls.ClientConfig { server_name: server_name, trust_roots: roots, alpn: none[0usize..0usize], entropy: entropy, now: now }
    let (stream0, create_error) = tls.client(a, reader(c), writer(c), config)
    if create_error != ok { ret (zero, create_error) }
    var stream = stream0
    let handshake_error = tls.handshake(&stream)
    if handshake_error != ok { ret (stream, handshake_error) }
    ret (stream, ok)
}
