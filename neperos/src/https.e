// TLS 1.3 over the NeperOS TCP client (D2246, C117): `e.net.tls` already speaks the protocol over
// any io.Reader and io.Writer, so the only thing to supply is the pair over a tcp.Conn. The
// handshake validates the server's chain against the trust roots it is given (concatenated DER
// certificates) and its name against the one asked for, at the wall-clock time the kernel reports.
use e.io
use e.mem
use e.net.tls
use e.time
use tcp

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

// A TLS stream to the peer of `c`, handshake done. `roots` is the trust set, `entropy` the 64
// random bytes the handshake draws its client random and key from.
fn connect(a: *mem.Arena, c: *tcp.Conn, server_name: str, roots: str, entropy: []const u8) -> (tls.Stream, err) {
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
