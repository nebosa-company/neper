// A small WebSocket client for NeperOS apps (C134): the upgrade handshake and unfragmented text frames over the
// buffered network reader of netio.e. (The library's e.net.ws needs e.net.http and so e.net, which is not on this
// platform yet; this is the part an app needs.) Client frames are masked with a fixed mask: the standard asks for a
// random one so a proxy cannot be fooled, and there is no proxy between the app and its server here.
use e.mem
use e.bytes
use e.crypto.hash
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

fn client_key() -> str { ret "dGhlIHNhbXBsZSBub25jZQ==" }
fn accept_guid() -> str { ret "258EAFA5-E914-47DA-95CA-C5AB0DC85B11" }

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// base64(sha1(key ++ GUID)), the accept value RFC 6455 requires.
fn expected_accept(a: *mem.Arena, key: str) -> (str, bool) {
    let (joined, joined_error) = mem.alloc[u8](a, key.len + accept_guid().len)
    if joined_error != ok { ret ("", false) }
    var i = 0usize
    while i < key.len {
        joined[i] = key[i]
        i += 1usize
    }
    var j = 0usize
    while j < accept_guid().len {
        joined[key.len + j] = accept_guid()[j]
        j += 1usize
    }
    let digest = hash.sha1(joined)
    let (encoded, encoded_error) = mem.alloc[u8](a, 32usize)
    if encoded_error != ok { ret ("", false) }
    let (text, encode_error) = bytes.base64_encode(encoded, digest[0usize..20usize], .Standard, true)
    if encode_error != ok { ret ("", false) }
    ret (text, true)
}

// The 101 response must carry Sec-WebSocket-Accept for the key this client sent.
fn accept_ok(a: *mem.Arena, header: str, key: str) -> bool {
    let marker = "sec-websocket-accept:"
    let (want, has_want) = expected_accept(a, key)
    if !has_want { ret false }
    var at = 0usize
    while at + marker.len < header.len {
        var hit = true
        var k = 0usize
        while k < marker.len {
            var c = header[at + k]
            if c >= 65u8 && c <= 90u8 { c += 32u8 }
            if c != marker[k] { hit = false }
            k += 1usize
        }
        if hit {
            var start = at + marker.len
            while start < header.len && (header[start] == 32u8 || header[start] == 9u8) { start += 1usize }
            var stop = start
            while stop < header.len && header[stop] != 13u8 && header[stop] != 10u8 && header[stop] != 32u8 { stop += 1usize }
            ret same(header[start..stop], want)
        }
        at += 1usize
    }
    ret false
}

fn upgrade(a: *mem.Arena, b: *netio.NetBuf, host: str, path: str) -> bool {
    var request: [512]u8 = zero
    var n = 0usize
    let parts: [7]str = [7]str{ "GET ", path, " HTTP/1.1\r\nHost: ", host, "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ", client_key(), "\r\nSec-WebSocket-Version: 13\r\n\r\n" }
    var p = 0usize
    while p < 7usize {
        var i = 0usize
        while i < parts[p].len {
            if n >= 512usize { ret false }
            request[n] = parts[p][i]
            n += 1usize
            i += 1usize
        }
        p += 1usize
    }
    if netclient.send(mem.address_of(&request[0usize]), n) != netproto.R_OK { ret false }
    var header: [1024]u8 = zero
    var seen = 0usize
    var last4: [4]u8 = zero
    var guard = 0usize
    var done = false
    while guard < 1024usize && !done {
        let (c, got) = byte(b)
        if !got { ret false }
        if seen < 1024usize { header[seen] = c }
        seen += 1usize
        last4[0usize] = last4[1usize]
        last4[1usize] = last4[2usize]
        last4[2usize] = last4[3usize]
        last4[3usize] = c
        if seen >= 4usize && last4[0usize] == 13u8 && last4[1usize] == 10u8 && last4[2usize] == 13u8 && last4[3usize] == 10u8 { done = true }
        guard += 1usize
    }
    if !done || seen < 12usize { ret false }
    if header[9usize] != 49u8 || header[10usize] != 48u8 || header[11usize] != 49u8 { ret false }
    ret accept_ok(a, header[0usize..seen], client_key())
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
        // A 64-bit length: consume it and the payload so the stream stays framed; keep
        // only what fits in `out` (a chat frame this large is dropped, not desynced).
        length = 0usize
        var lb = 0usize
        while lb < 8usize {
            let (size_byte, size_ok) = byte(b)
            if !size_ok { ret (0u8, 0usize, false) }
            length = length * 256usize + usize(size_byte)
            lb += 1usize
        }
        if length > 33554432usize { ret (0u8, 0usize, false) }
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





