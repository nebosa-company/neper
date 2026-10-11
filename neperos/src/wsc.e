// A small WebSocket client for NeperOS apps (C134): the upgrade handshake and unfragmented text frames over the
// buffered network reader of netio.e. (The library's e.net.ws needs e.net.http and so e.net, which is not on this
// platform yet; this is the part an app needs.) Client frames are masked with a fixed mask: the standard asks for a
// random one so a proxy cannot be fooled, and there is no proxy between the app and its server here.
use e.mem
use netclient
use netproto
use netio

// Read one byte from the buffered connection: false at the end or on a failure.
fn byte(b: *netio.NetBuf) -> (u8, bool) {
    var one: [1]u8 = zero
    let (n, e) = netio.net_read(mem.cast[*void](b), one[0usize..1usize])
    if e != ok || n == 0usize { ret (0u8, false) }
    ret (one[0usize], true)
}

// The Sec-WebSocket-Key is not verified against the accept value: the exchange is over TLS or loopback here and the
// server's 101 answer is what is checked.
fn upgrade(b: *netio.NetBuf, host: str, path: str) -> bool {
    var request: [320]u8 = zero
    var n = 0usize
    let parts: [7]str = [7]str{ "GET ", path, " HTTP/1.1\r\nHost: ", host, "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: AQIDBAUGBwgJCgsMDQ4PEA==\r\nSec-WebSocket-Version: 13\r\n\r\n", "", "" }
    var p = 0usize
    while p < 5usize {
        var i = 0usize
        while i < parts[p].len && n < 320usize {
            request[n] = parts[p][i]
            n += 1usize
            i += 1usize
        }
        p += 1usize
    }
    if netclient.send(mem.address_of(&request[0usize]), n) != netproto.R_OK { ret false }
    // The response header ends at a blank line; it has to start "HTTP/1.1 101".
    var seen = 0usize
    var first: [12]u8 = zero
    var last4: [4]u8 = zero
    var guard = 0usize
    while guard < 1024usize {
        let (c, got) = byte(b)
        if !got { ret false }
        if seen < 12usize { first[seen] = c }
        seen += 1usize
        last4[0usize] = last4[1usize]
        last4[1usize] = last4[2usize]
        last4[2usize] = last4[3usize]
        last4[3usize] = c
        if seen >= 4usize && last4[0usize] == 13u8 && last4[1usize] == 10u8 && last4[2usize] == 13u8 && last4[3usize] == 10u8 {
            ret seen >= 12usize && first[9usize] == 49u8 && first[10usize] == 48u8 && first[11usize] == 49u8
        }
        guard += 1usize
    }
    ret false
}

// Send `payload` (at most 125 bytes... or 65535) as one masked text frame.
fn send_text(payload: []const u8) -> bool {
    var frame: [140]u8 = zero
    if payload.len > 125usize { ret false }
    frame[0usize] = 129u8
    frame[1usize] = u8(128usize + payload.len)
    let mask: [4]u8 = [4]u8{ 55u8, 250u8, 33u8, 61u8 }
    frame[2usize] = mask[0usize]
    frame[3usize] = mask[1usize]
    frame[4usize] = mask[2usize]
    frame[5usize] = mask[3usize]
    var i = 0usize
    while i < payload.len {
        frame[6usize + i] = payload[i] ^ mask[i % 4usize]
        i += 1usize
    }
    ret netclient.send(mem.address_of(&frame[0usize]), 6usize + payload.len) == netproto.R_OK
}

// Read one frame: its opcode and the payload (up to out.len bytes, the rest dropped); false at the end.
fn receive(b: *netio.NetBuf, out: []u8) -> (u8, usize, bool) {
    let (h0, ok0) = byte(b)
    if !ok0 { ret (0u8, 0usize, false) }
    let (h1, ok1) = byte(b)
    if !ok1 { ret (0u8, 0usize, false) }
    var length = usize(h1 & 127u8)
    if length == 126usize {
        let (hi, okh) = byte(b)
        let (lo, okl) = byte(b)
        if !okh || !okl { ret (0u8, 0usize, false) }
        length = usize(hi) * 256usize + usize(lo)
    } else if length == 127usize {
        // A frame this large is not for a chat.
        ret (0u8, 0usize, false)
    }
    var mask: [4]u8 = zero
    let masked = (h1 & 128u8) != 0u8
    if masked {
        var m = 0usize
        while m < 4usize {
            let (mb, okm) = byte(b)
            if !okm { ret (0u8, 0usize, false) }
            mask[m] = mb
            m += 1usize
        }
    }
    var kept = 0usize
    var i = 0usize
    while i < length {
        let (c, got) = byte(b)
        if !got { ret (0u8, 0usize, false) }
        if kept < out.len {
            var v = c
            if masked { v = c ^ mask[i % 4usize] }
            out[kept] = v
            kept += 1usize
        }
        i += 1usize
    }
    ret (h0 & 15u8, kept, true)
}
