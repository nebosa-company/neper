// `e.net.h2client.exchange` against a scripted server: the request goes out as the preface, SETTINGS and a HEADERS frame that
// ends the stream (the pseudo headers first, names lowercased, connection-specific headers dropped); the server's SETTINGS is
// acknowledged, a 1xx block is skipped, and the response's HEADERS and DATA frames become a status, headers and body.
use e.io
use e.mem
use e.net.h2client as h2c
use e.net.http as http
use e.net.http2 as h2
use e.os
use e.str

type Cap = struct { data: [8192]u8, len: usize }

fn cap_write(ctx: *void, src: []const u8) -> (usize, err) {
    let c = mem.cast[*Cap](ctx)
    var i = 0usize
    while i < src.len {
        c.data[c.len + i] = src[i]
        i += 1usize
    }
    c.len += src.len
    ret (src.len, ok)
}

fn cap_flush(ctx: *void) -> err { ret ok }

fn frame(cap: *Cap, kind: u8, flags: u8, stream: u32, payload: []const u8) {
    let (n, fe) = h2.frame_encode(cap.data[cap.len..8192usize], kind, flags, stream, payload)
    cap.len += n
}

fn main(a: *mem.Arena, args: []str) -> err {
    // The server's side, as bytes.
    var server: Cap = zero
    let (ed, ede) = mem.alloc[u8](a, 4096usize)
    let (el, ele) = mem.alloc[u32](a, 256usize)
    var enc = h2.table_new(ed, el, 4096usize)
    var blk: [256]u8 = zero
    let none_s: [1]str = zero
    frame(&server, h2.SETTINGS, 0u8, 0u32, "")
    let interim = [1]h2.Header { h2.Header { name: ":status", value: "103" } }
    let (n1, e1) = h2.encode_block(&enc, blk[0usize..256usize], interim[0usize..1usize], none_s[0usize..0usize], false)
    frame(&server, h2.HEADERS, h2.FLAG_END_HEADERS, 1u32, blk[0usize..n1])
    let final = [2]h2.Header { h2.Header { name: ":status", value: "200" }, h2.Header { name: "content-type", value: "text/plain" } }
    let (n2, e2) = h2.encode_block(&enc, blk[0usize..256usize], final[0usize..2usize], none_s[0usize..0usize], true)
    frame(&server, h2.HEADERS, h2.FLAG_END_HEADERS, 1u32, blk[0usize..n2])
    frame(&server, h2.DATA, 0u8, 1u32, "hel")
    frame(&server, h2.DATA, h2.FLAG_END_STREAM, 1u32, "lo")
    var rd = io.SliceReader { data: server.data[0usize..server.len], off: 0usize }
    let src = io.slice_reader(&rd)
    // Ours.
    var ours: Cap = zero
    var csink = io.writer(mem.cast[*void](&ours), cap_write)
    let hs = [3]http.Header { http.Header { name: "Accept", value: "*/*" }, http.Header { name: "Connection", value: "close" }, http.Header { name: "User-Agent", value: "t" } }
    let (resp, e) = h2c.exchange(a, src, csink, "GET", "example.test", "/p?q=1", hs[0usize..3usize], "", 65536usize)
    if e != ok { os.exit(1i32) }
    if resp.status != 200u16 { os.exit(2i32) }
    if !str.eq(resp.body, "hello") { os.exit(3i32) }
    var found = false
    var i = 0usize
    while i < resp.headers.len {
        if str.eq(resp.headers[i].name, "content-type") && str.eq(resp.headers[i].value, "text/plain") { found = true }
        if resp.headers[i].name.len > 0usize && resp.headers[i].name[0usize] == 58u8 { os.exit(4i32) }
        i += 1usize
    }
    if !found { os.exit(5i32) }
    let sent = ours.data[0usize..ours.len]
    if sent.len < 24usize || !str.eq(sent[0usize..24usize], h2.preface()) { os.exit(6i32) }
    // After the preface: our SETTINGS, a WINDOW_UPDATE, then HEADERS on stream 1 with END_STREAM and END_HEADERS.
    var at = 24usize
    var saw_headers = false
    while at < sent.len {
        let (f, used, de) = h2.frame_decode(sent[at..], 65536usize)
        if de != ok { os.exit(7i32) }
        if f.kind == h2.HEADERS {
            saw_headers = true
            if f.stream != 1u32 || (f.flags & h2.FLAG_END_STREAM) == 0u8 || (f.flags & h2.FLAG_END_HEADERS) == 0u8 { os.exit(8i32) }
            var dd: [4096]u8 = zero
            var dl: [256]u32 = zero
            var dec = h2.table_new(dd[0usize..4096usize], dl[0usize..256usize], 4096usize)
            var out: [16]h2.Header = zero
            var scratch: [2048]u8 = zero
            let (cnt, dce) = h2.decode_block(&dec, f.payload, out[0usize..16usize], scratch[0usize..2048usize])
            if dce != ok || cnt != 6usize { os.exit(9i32) }
            if !str.eq(out[0usize].name, ":method") || !str.eq(out[0usize].value, "GET") { os.exit(10i32) }
            if !str.eq(out[3usize].name, ":path") || !str.eq(out[3usize].value, "/p?q=1") { os.exit(11i32) }
            if !str.eq(out[4usize].name, "accept") || !str.eq(out[5usize].name, "user-agent") { os.exit(12i32) }
        }
        at += used
    }
    if !saw_headers { os.exit(13i32) }
    ret ok
}
