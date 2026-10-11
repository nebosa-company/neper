// A buffered `io.Reader` and `io.Writer` over the network server's connection (C134), for the library's protocol
// clients (WebSocket, and any other that takes a reader and a writer). The buffer lets an app ask the server for
// whatever has arrived (`poll`) and then hand it to a client that reads in small pieces; a read that finds the buffer
// empty asks the server and waits (the app only does that mid-frame, when the rest is on its way).
use e.io
use e.mem
use netclient
use netproto

type NetBuf = struct { data: [4096]u8, len: usize, pos: usize, closed: bool }

// Take what the server has for us (a short wait): the number of bytes now buffered. The peer's close sets `closed`.
fn poll(b: *NetBuf) -> usize {
    if b.pos < b.len { ret b.len - b.pos }
    b.pos = 0usize
    b.len = 0usize
    let (n, r) = netclient.poll(mem.address_of(&b.data[0usize]), 4096usize)
    if r == netproto.R_OK {
        if n == 0usize { b.closed = true }
        b.len = n
    }
    ret b.len
}

fn net_read(ctx: *void, dst: []u8) -> (usize, err) {
    var b = mem.cast[*NetBuf](ctx)
    if dst.len == 0usize { ret (0usize, ok) }
    if b.pos >= b.len {
        if b.closed { ret (0usize, io.End) }
        b.pos = 0usize
        b.len = 0usize
        let (n, r) = netclient.recv(mem.address_of(&b.data[0usize]), 4096usize)
        if r != netproto.R_OK { ret (0usize, io.NoProgress) }
        if n == 0usize {
            b.closed = true
            ret (0usize, io.End)
        }
        b.len = n
    }
    var take = b.len - b.pos
    if take > dst.len { take = dst.len }
    var i = 0usize
    while i < take {
        dst[i] = b.data[b.pos + i]
        i += 1usize
    }
    b.pos += take
    ret (take, ok)
}

fn net_write(ctx: *void, src: []const u8) -> (usize, err) {
    if src.len == 0usize { ret (0usize, ok) }
    let r = netclient.send(mem.address_of(&src[0usize]), src.len)
    if r != netproto.R_OK { ret (0usize, io.NoProgress) }
    ret (src.len, ok)
}

fn net_flush(ctx: *void) -> err { ret ok }

fn reader(b: *NetBuf) -> io.Reader { ret io.Reader { ctx: mem.cast[*void](b), read: net_read } }

fn writer() -> io.Writer { ret io.Writer { ctx: nil, write: net_write, flush: net_flush } }
