// A response read a little at a time (C171): the request goes out over the network server's socket capability
// (netclient.e) and the reply is taken with `pump`, one poll per call, so an app can keep answering the compositor's
// ticks (and draw what has arrived) while a model is still writing. The status line and headers are parsed as
// they come; the body is decoded as it comes too -- `Transfer-Encoding: chunked` is joined, anything else is passed
// through to the end of the stream -- into the caller's buffer, which only ever grows, so a reader that keeps its
// own position (e.fmt.sse) sees stable bytes. Not a general client: no redirects, a JSON request body only, and
// a body that outgrows the buffer ends the stream (`overflow`).
use e.mem
use e.os
use netclient
use netproto

const PH_HEAD: usize = 0usize
const PH_BODY: usize = 1usize
const PH_DONE: usize = 2usize
// The chunked decoder's states.
const CK_SIZE: usize = 0usize
const CK_EXT: usize = 1usize
const CK_DATA: usize = 2usize
const CK_CR: usize = 3usize
const CK_LF: usize = 4usize
const CK_TRAILER: usize = 5usize

type Stream = struct {
    head: [2048]u8,
    head_len: usize,
    // The decoded body: `body_addr` is the caller's buffer of `body_cap` bytes, `body_len` how much is in it.
    body_addr: usize,
    body_cap: usize,
    body_len: usize,
    phase: usize,
    status: usize,
    chunked: bool,
    ck: usize,
    left: usize,
    size: usize,
    ended: bool,
    overflow: bool,
    failed: bool,
}

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn has_word(text: []const u8, length: usize, word: str) -> bool {
    var at = 0usize
    while at + word.len <= length {
        var same = true
        var k = 0usize
        while k < word.len {
            if lower(text[at + k]) != lower(word[k]) { same = false }
            k += 1usize
        }
        if same { ret true }
        at += 1usize
    }
    ret false
}

fn hex_value(c: u8) -> usize {
    if c >= 48u8 && c <= 57u8 { ret usize(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret usize(c - 87u8) }
    if c >= 65u8 && c <= 70u8 { ret usize(c - 55u8) }
    ret 99usize
}

fn put(buffer: []u8, at: usize, piece: str) -> usize {
    var n = at
    var i = 0usize
    while i < piece.len && n < buffer.len {
        buffer[n] = piece[i]
        n += 1usize
        i += 1usize
    }
    ret n
}

fn put_number(buffer: []u8, at: usize, value: usize) -> usize {
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = value
    if rest == 0usize {
        digits[0usize] = 48u8
        count = 1usize
    }
    while rest > 0usize {
        digits[count] = u8(48usize + rest % 10usize)
        rest = rest / 10usize
        count += 1usize
    }
    var n = at
    while count > 0usize && n < buffer.len {
        count -= 1usize
        buffer[n] = digits[count]
        n += 1usize
    }
    ret n
}

// A stream that will decode into [body_addr, body_addr + body_cap).
fn begin(st: *Stream, body_addr: usize, body_cap: usize) {
    var fresh: Stream = zero
    fresh.body_addr = body_addr
    fresh.body_cap = body_cap
    *st = fresh
}

fn emit_byte(st: *Stream, b: u8) {
    if st.body_len >= st.body_cap {
        st.overflow = true
        st.ended = true
        st.phase = PH_DONE
        ret
    }
    os.store8(st.body_addr + st.body_len, b)
    st.body_len += 1usize
}

// One body byte through the transfer decoding.
fn body_byte(st: *Stream, b: u8) {
    if !st.chunked {
        emit_byte(st, b)
        ret
    }
    if st.ck == CK_SIZE {
        let v = hex_value(b)
        if v != 99usize {
            st.size = st.size * 16usize + v
            if st.size > 16777216usize {
                st.failed = true
                st.phase = PH_DONE
            }
        } else if b == 59u8 || b == 13u8 || b == 10u8 || b == 32u8 {
            st.ck = CK_EXT
            if b == 10u8 { chunk_header_done(st) }
        } else {
            st.failed = true
            st.phase = PH_DONE
        }
    } else if st.ck == CK_EXT {
        if b == 10u8 { chunk_header_done(st) }
    } else if st.ck == CK_DATA {
        emit_byte(st, b)
        st.left -= 1usize
        if st.left == 0usize { st.ck = CK_CR }
    } else if st.ck == CK_CR {
        // The CR after a chunk's data (a bare LF is tolerated).
        if b == 10u8 { st.ck = CK_SIZE } else { st.ck = CK_LF }
        st.size = 0usize
    } else if st.ck == CK_LF {
        st.ck = CK_SIZE
        st.size = 0usize
    } else {
        // After the last chunk the trailer is read to the end of the stream and ignored.
    }
}

fn chunk_header_done(st: *Stream) {
    if st.size == 0usize {
        st.ck = CK_TRAILER
        st.ended = true
        st.phase = PH_DONE
    } else {
        st.left = st.size
        st.ck = CK_DATA
    }
}

// The status line and headers are complete in st.head[..st.head_len].
fn headers_done(st: *Stream) {
    st.status = 0usize
    var d = 9usize
    var good = st.head_len >= 12usize
    while good && d < 12usize {
        if st.head[d] < 48u8 || st.head[d] > 57u8 { good = false } else { st.status = st.status * 10usize + usize(st.head[d] - 48u8) }
        d += 1usize
    }
    if !good {
        st.failed = true
        st.phase = PH_DONE
        ret
    }
    st.chunked = has_word(st.head[0usize..], st.head_len, "transfer-encoding: chunked")
    st.phase = PH_BODY
}

// Feed `n` bytes at `addr` (what the network server answered).
fn feed(st: *Stream, addr: usize, n: usize) {
    var i = 0usize
    while i < n && st.phase != PH_DONE {
        let b = os.load8(addr + i)
        if st.phase == PH_HEAD {
            if st.head_len < 2048usize {
                st.head[st.head_len] = b
                st.head_len += 1usize
            }
            if st.head_len >= 4usize && st.head[st.head_len - 4usize] == 13u8 && st.head[st.head_len - 3usize] == 10u8 && st.head[st.head_len - 2usize] == 13u8 && st.head[st.head_len - 1usize] == 10u8 {
                headers_done(st)
            } else if st.head_len == 2048usize {
                st.failed = true
                st.phase = PH_DONE
            }
        } else {
            body_byte(st, b)
        }
        i += 1usize
    }
}

// Connect to `host`:`port` and send the request; a netproto.R_* result (R_OK when the request is out).
fn start(a: *mem.Arena, st: *Stream, method: str, host: str, path: str, extra: str, body: str, port: u16, secure: bool) -> usize {
    let (raw, alloc_error) = mem.alloc[u8](a, body.len + 1024usize)
    if alloc_error != ok { ret netproto.R_IO }
    let connected = netclient.connect(host, port, secure)
    if connected != netproto.R_OK { ret connected }
    var n = 0usize
    n = put(raw, n, method)
    n = put(raw, n, " ")
    n = put(raw, n, path)
    n = put(raw, n, " HTTP/1.1\r\nHost: ")
    n = put(raw, n, host)
    n = put(raw, n, "\r\nUser-Agent: NeperOS/1.0\r\nAccept: text/event-stream\r\nAccept-Encoding: identity\r\nConnection: close\r\n")
    n = put(raw, n, extra)
    if body.len > 0usize {
        n = put(raw, n, "Content-Type: application/json\r\nContent-Length: ")
        n = put_number(raw, n, body.len)
        n = put(raw, n, "\r\n")
    }
    n = put(raw, n, "\r\n")
    n = put(raw, n, body)
    let sent = netclient.send(mem.address_of(&raw[0usize]), n)
    if sent != netproto.R_OK {
        let closed = netclient.close()
        ret sent
    }
    ret netproto.R_OK
}

// Take what has arrived (at most 2 KB, waiting only a moment): R_OK with `got` bytes fed to the decoder, R_EMPTY when
// nothing has, or an error. A peer's close ends the stream (`ended`).
fn pump(st: *Stream) -> usize {
    var chunk: [2048]u8 = zero
    let (got, result) = netclient.poll(mem.address_of(&chunk[0usize]), 2048usize)
    if result == netproto.R_EMPTY { ret netproto.R_EMPTY }
    if result != netproto.R_OK {
        st.failed = true
        st.ended = true
        st.phase = PH_DONE
        let closed = netclient.close()
        ret result
    }
    if got == 0usize {
        st.ended = true
        st.phase = PH_DONE
        let closed = netclient.close()
        ret netproto.R_OK
    }
    feed(st, mem.address_of(&chunk[0usize]), got)
    if st.phase == PH_DONE && !st.ended { st.ended = true }
    if st.ended {
        let closed = netclient.close()
    }
    ret netproto.R_OK
}

fn abort(st: *Stream) {
    if st.phase != PH_DONE {
        let closed = netclient.close()
    }
    st.ended = true
    st.phase = PH_DONE
}
