// A small HTTPS GET for apps (D2251, C118): one request over the network server's socket capability
// (netclient.e), the reply read to its end into the caller's arena and split into the status and the
// body. The request asks for `Accept-Encoding: identity` and `Connection: close`, so the reply is plain
// bytes that end when the peer closes; a chunked body (HTTP/1.1 servers answer that way) is joined in
// place. Not a general client: no redirects, no cookies, no request bodies, 96 KB of reply at most.
use e.mem
use e.os
use netclient
use netproto

error NoNetwork
error Unreachable
error TlsFailed
error Io
error Malformed
error TooLarge

const REPLY_MAX: usize = 98304usize

type Reply = struct { status: usize, body: str }

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

// Whether `text` holds `word` (compared without regard to case) starting at `at`.
fn matches_at(text: []const u8, at: usize, word: str) -> bool {
    if at + word.len > text.len { ret false }
    var i = 0usize
    while i < word.len {
        if lower(text[at + i]) != lower(word[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn find_text(text: []const u8, word: str, from: usize, until: usize) -> usize {
    var at = from
    while at + word.len <= until {
        if matches_at(text, at, word) { ret at }
        at += 1usize
    }
    ret until
}

fn hex_digit(c: u8) -> usize {
    if c >= 48u8 && c <= 57u8 { ret usize(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret usize(c - 87u8) }
    if c >= 65u8 && c <= 70u8 { ret usize(c - 55u8) }
    ret 99usize
}

// Join the chunks of `raw[start..end]` to the front of `raw`; the joined length, or `end + 1` when malformed.
fn dechunk(raw: []u8, start: usize, end: usize) -> usize {
    var at = start
    var out = 0usize
    while true {
        var size = 0usize
        var digits = 0usize
        while at < end && hex_digit(raw[at]) != 99usize {
            size = size * 16usize + hex_digit(raw[at])
            at += 1usize
            digits += 1usize
            if digits > 8usize { ret end + 1usize }
        }
        // A chunk extension, if any, runs to the end of the line.
        while at < end && raw[at] != 13u8 { at += 1usize }
        if digits == 0usize || at + 2usize > end || raw[at + 1usize] != 10u8 { ret end + 1usize }
        at += 2usize
        if size == 0usize { ret out }
        if at + size > end { ret end + 1usize }
        var i = 0usize
        while i < size {
            raw[out + i] = raw[at + i]
            i += 1usize
        }
        out += size
        at += size
        if at + 2usize > end || raw[at] != 13u8 || raw[at + 1usize] != 10u8 { ret end + 1usize }
        at += 2usize
    }
    ret out
}

// GET https://`host``path`, with `extra` appended to the request's headers (each ending in CRLF).
fn get(a: *mem.Arena, host: str, path: str, extra: str) -> (Reply, err) {
    var empty: Reply = zero
    let (raw, alloc_error) = mem.alloc[u8](a, REPLY_MAX)
    if alloc_error != ok { ret (empty, TooLarge) }
    let connected = netclient.connect(host, 443u16, true)
    if connected == netproto.R_NO_NETWORK { ret (empty, NoNetwork) }
    if connected == netproto.R_RESOLVE || connected == netproto.R_CONNECT { ret (empty, Unreachable) }
    if connected == netproto.R_TLS { ret (empty, TlsFailed) }
    if connected != netproto.R_OK { ret (empty, Io) }
    // The request goes into the same buffer; the reply overwrites it once the request is sent.
    var n = 0usize
    n = put(raw, n, "GET ")
    n = put(raw, n, path)
    n = put(raw, n, " HTTP/1.1\r\nHost: ")
    n = put(raw, n, host)
    n = put(raw, n, "\r\nUser-Agent: NeperOS/1.0\r\nAccept: application/json\r\nAccept-Encoding: identity\r\nConnection: close\r\n")
    n = put(raw, n, extra)
    n = put(raw, n, "\r\n")
    if netclient.send(mem.address_of(&raw[0usize]), n) != netproto.R_OK {
        let closed = netclient.close()
        ret (empty, Io)
    }
    var total = 0usize
    var done = false
    var failed = false
    while !done {
        if total >= REPLY_MAX {
            let closed = netclient.close()
            ret (empty, TooLarge)
        }
        var want = REPLY_MAX - total
        if want > netproto.CHUNK { want = netproto.CHUNK }
        let (got, result) = netclient.recv(mem.address_of(&raw[0usize]) + total, want)
        if result != netproto.R_OK {
            failed = true
            done = true
        } else if got == 0usize {
            done = true
        } else {
            total += got
        }
    }
    let closed = netclient.close()
    // A reply cut short by an error is still usable if it holds a whole message; judged below.
    if total < 12usize { ret (empty, Io) }
    if !matches_at(raw, 0usize, "HTTP/1.") { ret (empty, Malformed) }
    var status = 0usize
    var digit = 9usize
    while digit < 12usize {
        if raw[digit] < 48u8 || raw[digit] > 57u8 { ret (empty, Malformed) }
        status = status * 10usize + usize(raw[digit] - 48u8)
        digit += 1usize
    }
    let head_end = find_text(raw, "\r\n\r\n", 0usize, total)
    if head_end == total { ret (empty, Malformed) }
    let body_start = head_end + 4usize
    let chunked = find_text(raw, "transfer-encoding: chunked", 0usize, head_end) != head_end
    var body_len = total - body_start
    if chunked {
        let joined = dechunk(raw, body_start, total)
        if joined > total - body_start { ret (empty, Malformed) }
        // The joined body is at the front of the buffer, ahead of the headers' old place.
        body_len = joined
        ret (Reply { status: status, body: raw[0usize..joined] }, ok)
    }
    // A Content-Length says how much body to expect: a reply that has all of it is whole even when the
    // peer closed the stream without a close_notify; one without the header can only be trusted if the
    // stream ended cleanly.
    let length_at = find_text(raw, "content-length:", 0usize, head_end)
    if length_at != head_end {
        var at = length_at + 15usize
        while at < head_end && raw[at] == 32u8 { at += 1usize }
        var declared = 0usize
        var seen = 0usize
        while at < head_end && raw[at] >= 48u8 && raw[at] <= 57u8 && seen < 9usize {
            declared = declared * 10usize + usize(raw[at] - 48u8)
            at += 1usize
            seen += 1usize
        }
        if seen > 0usize {
            if body_len < declared { ret (empty, Io) }
            ret (Reply { status: status, body: raw[body_start..body_start + declared] }, ok)
        }
    }
    if failed { ret (empty, Io) }
    ret (Reply { status: status, body: raw[body_start..body_start + body_len] }, ok)
}

// Append `piece` to `buffer` at `at`; the new end.
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
