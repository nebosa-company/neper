// A one-request HTTP/2 client (RFC 9113) over TLS: ALPN picks `h2`, the connection preface and SETTINGS are exchanged, one
// request goes out on stream 1 and the response is read to its END_STREAM. The framing and HPACK are `e.net.http2`; this module
// is the connection state machine for a single exchange: flow control in both directions, SETTINGS and PING answers, header
// blocks split over CONTINUATION, 1xx responses skipped, trailers ignored.
//
// `NotH2` means the server did not choose `h2`; the caller then retries over HTTP/1.1.
//
// Ceiling: every request opens its own connection (no multiplexing across requests, no server push, no priority).
use e.io
use e.mem
use e.net
use e.net.http as http
use e.net.http2 as h2
use e.net.tls
use e.str

error NotH2
error Protocol
error Refused
error TooLarge

const BUF_BYTES: usize = 65536usize
const SCRATCH_BYTES: usize = 131072usize
const MAX_HEADERS: usize = 512usize
const RECV_WINDOW: u32 = 4194304u32

type Conn = struct {
    a: *mem.Arena, sink: io.Writer, src: io.Reader, buf: []u8, fill: usize,
    send_conn: i64, send_stream: i64, peer_max_frame: usize, peer_initial: i64,
    recv_conn_left: i64, recv_stream_left: i64
}

fn put_frame(c: *Conn, kind: u8, flags: u8, stream: u32, payload: []const u8) -> err {
    let (out, oe) = mem.alloc[u8](c.a, 9usize + payload.len)
    if oe != ok { ret oe }
    let (n, fe) = h2.frame_encode(out, kind, flags, stream, payload)
    if fe != ok { ret fe }
    let we = io.write_all(&c.sink, out[0usize..n])
    ret we
}

fn put_window_update(c: *Conn, stream: u32, inc: u32) -> err {
    var p: [4]u8 = zero
    h2.put32(p[0usize..4usize], 0usize, inc)
    ret put_frame(c, h2.WINDOW_UPDATE, 0u8, stream, p[0usize..4usize])
}

// The next complete frame, reading more from the connection as needed. The frame's payload is valid until the next call.
fn next_frame(c: *Conn) -> (h2.Frame, err) {
    var f: h2.Frame = zero
    // Drop the previous frame that `consume` marked.
    while true {
        let (fr, used, de) = h2.frame_decode(c.buf[0usize..c.fill], BUF_BYTES - 9usize)
        if de == ok {
            // The frame stays at the front; the caller calls `consume(used)` after reading the payload.
            c.fill = c.fill
            ret (fr, ok)
        }
        if de != h2.Incomplete { ret (f, de) }
        if c.fill >= c.buf.len { ret (f, h2.FrameSize) }
        let (n, re) = io.read(&c.src, c.buf[c.fill..])
        if re != ok { ret (f, re) }
        c.fill += n
    }
    ret (f, Protocol)
}

fn consume(c: *Conn, payload_len: usize) {
    let used = 9usize + payload_len
    var i = 0usize
    while i + used < c.fill {
        c.buf[i] = c.buf[i + used]
        i += 1usize
    }
    c.fill = c.fill - used
}

fn lower(a: *mem.Arena, s: str) -> (str, err) {
    let (out, oe) = mem.alloc[u8](a, s.len + 1usize)
    if oe != ok { ret ("", oe) }
    var i = 0usize
    while i < s.len {
        var ch = s[i]
        if ch >= 65u8 && ch <= 90u8 { ch = ch + 32u8 }
        out[i] = ch
        i += 1usize
    }
    ret (out[0usize..s.len], ok)
}

fn eq_fold_name(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        var a = x[i]
        var b = y[i]
        if a >= 65u8 && a <= 90u8 { a = a + 32u8 }
        if b >= 65u8 && b <= 90u8 { b = b + 32u8 }
        if a != b { ret false }
        i += 1usize
    }
    ret true
}

fn skip_request_header(name: str) -> bool {
    ret eq_fold_name(name, "host") || eq_fold_name(name, "connection") || eq_fold_name(name, "keep-alive") || eq_fold_name(name, "proxy-connection") || eq_fold_name(name, "transfer-encoding") || eq_fold_name(name, "upgrade")
}

type Growing = struct { data: []u8, len: usize }

fn append(a: *mem.Arena, g: *Growing, more: []const u8, limit: usize) -> err {
    if g.len + more.len > limit { ret TooLarge }
    if g.len + more.len > g.data.len {
        var cap = g.data.len
        if cap < 4096usize { cap = 4096usize }
        while cap < g.len + more.len { cap = cap * 2usize }
        let (grown, ge) = mem.alloc[u8](a, cap)
        if ge != ok { ret ge }
        var i = 0usize
        while i < g.len {
            grown[i] = g.data[i]
            i += 1usize
        }
        g.data = grown
    }
    var j = 0usize
    while j < more.len {
        g.data[g.len + j] = more[j]
        j += 1usize
    }
    g.len += more.len
    ret ok
}

fn parse_status(s: str) -> u16 {
    var v = 0u32
    var i = 0usize
    while i < s.len && i < 3usize {
        if s[i] < 48u8 || s[i] > 57u8 { ret 0u16 }
        v = v * 10u32 + u32(s[i] - 48u8)
        i += 1usize
    }
    ret u16(v)
}

fn request(a: *mem.Arena, endpoint: net.Endpoint, config: tls.ClientConfig, method: str, authority: str, path: str, headers: []const http.Header, body: []const u8, body_limit: usize) -> (http.Response, err) {
    var out: http.Response = zero
    let (opened, ce) = net.tcp_connect(endpoint)
    if ce != ok { ret (out, ce) }
    var connection = opened
    defer let _ = net.close(connection)
    let mark = mem.mark(a)
    let source = net.reader(&connection)
    let sink = net.writer(&connection)
    let (secure0, se) = tls.client(a, source, sink, config)
    if se != ok {
        mem.reset(a, mark)
        ret (out, se)
    }
    var secure = secure0
    let he = tls.handshake(&secure)
    if he != ok {
        let _ = tls.close(&secure)
        mem.reset(a, mark)
        ret (out, he)
    }
    if !str.eq(tls.negotiated_protocol(&secure), "h2") {
        let _ = tls.close(&secure)
        mem.reset(a, mark)
        ret (out, NotH2)
    }
    let (resp, xe) = exchange(a, tls.reader(&secure), tls.writer(&secure), method, authority, path, headers, body, body_limit)
    let _ = tls.close(&secure)
    if xe != ok { ret (out, xe) }
    ret (resp, ok)
}

// One request/response over an established h2 byte stream (already past ALPN): `src` carries the server's frames, `sink` ours.
fn exchange(a: *mem.Arena, src: io.Reader, sink: io.Writer, method: str, authority: str, path: str, headers: []const http.Header, body: []const u8, body_limit: usize) -> (http.Response, err) {
    var out: http.Response = zero
    let (buf, be) = mem.alloc[u8](a, BUF_BYTES)
    if be != ok { ret (out, be) }
    var c = Conn {
        a: a, sink: sink, src: src, buf: buf, fill: 0usize,
        send_conn: 65535i64, send_stream: 65535i64, peer_max_frame: 16384usize, peer_initial: 65535i64,
        recv_conn_left: i64(RECV_WINDOW), recv_stream_left: i64(RECV_WINDOW)
    }
    // Preface, our SETTINGS (no push, a large stream window), and a connection window to match.
    let pe = io.write_all(&c.sink, h2.preface())
    if pe != ok { ret (out, pe) }
    var sp: [12]u8 = zero
    let settings = [2]h2.Setting { h2.Setting { id: 2u16, value: 0u32 }, h2.Setting { id: 4u16, value: RECV_WINDOW } }
    let (sn, sne) = h2.settings_encode(sp[0usize..12usize], settings[0usize..2usize])
    if sne != ok { ret (out, sne) }
    let sfe = put_frame(&c, h2.SETTINGS, 0u8, 0u32, sp[0usize..sn])
    if sfe != ok { ret (out, sfe) }
    let wue = put_window_update(&c, 0u32, RECV_WINDOW - 65535u32)
    if wue != ok { ret (out, wue) }
    // The request header block.
    let (enc_data, ede) = mem.alloc[u8](a, 4096usize)
    let (enc_lens, ele) = mem.alloc[u32](a, 256usize)
    if ede != ok || ele != ok { ret (out, TooLarge) }
    var enc = h2.table_new(enc_data, enc_lens, 4096usize)
    let (hl, hle) = mem.alloc[h2.Header](a, headers.len + 8usize)
    if hle != ok { ret (out, hle) }
    hl[0usize] = h2.Header { name: ":method", value: method }
    hl[1usize] = h2.Header { name: ":scheme", value: "https" }
    hl[2usize] = h2.Header { name: ":authority", value: authority }
    hl[3usize] = h2.Header { name: ":path", value: path }
    var hn = 4usize
    var i = 0usize
    while i < headers.len {
        if !skip_request_header(headers[i].name) {
            let (ln, lne) = lower(a, headers[i].name)
            if lne != ok { ret (out, lne) }
            hl[hn] = h2.Header { name: ln, value: headers[i].value }
            hn += 1usize
        }
        i += 1usize
    }
    let (block, bke) = mem.alloc[u8](a, 131072usize)
    if bke != ok { ret (out, bke) }
    let none_s: [1]str = zero
    let (blen, ble) = h2.encode_block(&enc, block, hl[0usize..hn], none_s[0usize..0usize], true)
    if ble != ok { ret (out, ble) }
    var flags = h2.FLAG_END_HEADERS
    if body.len == 0usize { flags = flags | h2.FLAG_END_STREAM }
    // A block larger than a frame goes out as HEADERS then CONTINUATION frames.
    var at = 0usize
    var first = true
    while at < blen || first {
        var take = blen - at
        if take > c.peer_max_frame { take = c.peer_max_frame }
        let last = at + take >= blen
        var kind = h2.CONTINUATION
        var fl = 0u8
        if first {
            kind = h2.HEADERS
            fl = flags & h2.FLAG_END_STREAM
        }
        if last { fl = fl | h2.FLAG_END_HEADERS }
        let fe = put_frame(&c, kind, fl, 1u32, block[at..at + take])
        if fe != ok { ret (out, fe) }
        first = false
        at += take
        if last { break }
    }
    var sent = 0usize
    var status = 0u16
    var got_status = false
    var done = false
    var body_acc = Growing { data: zero, len: 0usize }
    var rheaders: []h2.Header = zero
    var nrh = 0usize
    var hacc = Growing { data: zero, len: 0usize }
    var in_headers = false
    var headers_end_stream = false
    let (dec_data, dde) = mem.alloc[u8](a, 4096usize)
    let (dec_lens, dle) = mem.alloc[u32](a, 256usize)
    if dde != ok || dle != ok { ret (out, TooLarge) }
    var dec = h2.table_new(dec_data, dec_lens, 4096usize)
    var settings_buf: [16]h2.Setting = zero
    while !done {
        // Send as much of the body as the windows allow.
        while sent < body.len {
            var room = c.send_conn
            if c.send_stream < room { room = c.send_stream }
            if room <= 0i64 { break }
            var take = body.len - sent
            if take > c.peer_max_frame { take = c.peer_max_frame }
            if i64(take) > room { take = usize(room) }
            var fl = 0u8
            if sent + take >= body.len { fl = h2.FLAG_END_STREAM }
            let de = put_frame(&c, h2.DATA, fl, 1u32, body[sent..sent + take])
            if de != ok { ret (out, de) }
            sent += take
            c.send_conn -= i64(take)
            c.send_stream -= i64(take)
        }
        let (f, fe) = next_frame(&c)
        if fe != ok { ret (out, fe) }
        let plen = f.payload.len
        if f.kind == h2.SETTINGS {
            if (f.flags & h2.FLAG_ACK) == 0u8 {
                let (cnt, sde) = h2.settings_decode(f.payload, settings_buf[0usize..16usize])
                if sde != ok { ret (out, sde) }
                var k = 0usize
                while k < cnt {
                    if settings_buf[k].id == 4u16 {
                        c.send_stream = c.send_stream + (i64(settings_buf[k].value) - c.peer_initial)
                        c.peer_initial = i64(settings_buf[k].value)
                    }
                    if settings_buf[k].id == 5u16 && usize(settings_buf[k].value) >= 16384usize && usize(settings_buf[k].value) <= 65000usize { c.peer_max_frame = usize(settings_buf[k].value) }
                    k += 1usize
                }
                consume(&c, plen)
                let ae = put_frame(&c, h2.SETTINGS, h2.FLAG_ACK, 0u32, "")
                if ae != ok { ret (out, ae) }
            } else {
                consume(&c, plen)
            }
        } else if f.kind == h2.WINDOW_UPDATE {
            if plen != 4usize { ret (out, Protocol) }
            let inc = i64(h2.be32(f.payload, 0usize) & 2147483647u32)
            if f.stream == 0u32 { c.send_conn += inc } else if f.stream == 1u32 { c.send_stream += inc }
            consume(&c, plen)
        } else if f.kind == h2.PING {
            if (f.flags & h2.FLAG_ACK) == 0u8 && plen == 8usize {
                var pp: [8]u8 = zero
                var q = 0usize
                while q < 8usize {
                    pp[q] = f.payload[q]
                    q += 1usize
                }
                consume(&c, plen)
                let ke = put_frame(&c, h2.PING, h2.FLAG_ACK, 0u32, pp[0usize..8usize])
                if ke != ok { ret (out, ke) }
            } else {
                consume(&c, plen)
            }
        } else if f.kind == h2.GOAWAY || f.kind == h2.RST_STREAM {
            if f.kind == h2.RST_STREAM && f.stream != 1u32 {
                consume(&c, plen)
            } else {
                ret (out, Refused)
            }
        } else if f.kind == h2.HEADERS && f.stream == 1u32 {
            let (frag, fge) = h2.headers_fragment(f)
            if fge != ok { ret (out, fge) }
            let app = append(a, &hacc, frag, 262144usize)
            if app != ok { ret (out, app) }
            in_headers = true
            headers_end_stream = (f.flags & h2.FLAG_END_STREAM) != 0u8
            let end_headers = (f.flags & h2.FLAG_END_HEADERS) != 0u8
            consume(&c, plen)
            if end_headers { in_headers = false }
        } else if f.kind == h2.CONTINUATION && f.stream == 1u32 {
            if !in_headers { ret (out, Protocol) }
            let app = append(a, &hacc, f.payload, 262144usize)
            if app != ok { ret (out, app) }
            let end_headers = (f.flags & h2.FLAG_END_HEADERS) != 0u8
            consume(&c, plen)
            if end_headers { in_headers = false }
        } else if f.kind == h2.DATA && f.stream == 1u32 {
            let (payload, upe) = h2.unpad(f)
            if upe != ok { ret (out, upe) }
            let app = append(a, &body_acc, payload, body_limit)
            if app != ok { ret (out, app) }
            let received = plen
            let end_stream = (f.flags & h2.FLAG_END_STREAM) != 0u8
            consume(&c, plen)
            c.recv_conn_left -= i64(received)
            c.recv_stream_left -= i64(received)
            if received > 0usize && !end_stream {
                if c.recv_conn_left < i64(RECV_WINDOW) / 2i64 {
                    let ue = put_window_update(&c, 0u32, u32(i64(RECV_WINDOW) - c.recv_conn_left))
                    if ue != ok { ret (out, ue) }
                    c.recv_conn_left = i64(RECV_WINDOW)
                }
                if c.recv_stream_left < i64(RECV_WINDOW) / 2i64 {
                    let ue2 = put_window_update(&c, 1u32, u32(i64(RECV_WINDOW) - c.recv_stream_left))
                    if ue2 != ok { ret (out, ue2) }
                    c.recv_stream_left = i64(RECV_WINDOW)
                }
            }
            if end_stream { done = true }
        } else {
            consume(&c, plen)
        }
        // A completed header block: decode it; a 1xx response (or a trailer block) is not the response.
        if !in_headers && hacc.len > 0usize {
            let (hh, hhe) = mem.alloc[h2.Header](a, MAX_HEADERS)
            let (scratch, sce) = mem.alloc[u8](a, SCRATCH_BYTES)
            if hhe != ok || sce != ok { ret (out, TooLarge) }
            let (cnt, dce) = h2.decode_block(&dec, hacc.data[0usize..hacc.len], hh, scratch)
            if dce != ok { ret (out, dce) }
            hacc.len = 0usize
            if !got_status {
                var k = 0usize
                var st = 0u16
                while k < cnt {
                    if str.eq(hh[k].name, ":status") { st = parse_status(hh[k].value) }
                    k += 1usize
                }
                if st >= 200u16 {
                    status = st
                    got_status = true
                    rheaders = hh[0usize..cnt]
                    nrh = cnt
                    if headers_end_stream { done = true }
                }
            } else if headers_end_stream {
                done = true
            }
        }
    }
    if !got_status { ret (out, Protocol) }
    let (outh, oe) = mem.alloc[http.Header](a, nrh + 1usize)
    if oe != ok { ret (out, oe) }
    var on = 0usize
    var k = 0usize
    while k < nrh {
        if rheaders[k].name.len > 0usize && rheaders[k].name[0usize] != 58u8 {
            outh[on] = http.Header { name: rheaders[k].name, value: rheaders[k].value }
            on += 1usize
        }
        k += 1usize
    }
    out = http.Response { version: http.Version.Http11, status: status, reason: "", headers: outh[0usize..on], body: body_acc.data[0usize..body_acc.len] }
    ret (out, ok)
}
