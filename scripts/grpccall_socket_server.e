// A scripted gRPC server on a loopback port for the socket run of `e.net.grpccall` (L164): scripts/grpccall_socket.py builds
// this and scripts/grpccall_socket_client.e and runs them against each other. It is `e.net.grpcserver` over the sockets of
// `e.net`, answering each request (counted across connections, in arrival order) as its script says:
//   `0` OK, a number a trailers-only status, `r` a RST_STREAM(REFUSED_STREAM), `g` a GOAWAY whose last stream is below the
//   request followed by closing the connection, `s` no answer (the client's per-attempt timeout or deadline ends it).
// The last token repeats. Usage: grpccall_socket_server PORT TOKENS (comma separated, e.g. `r,0` or `g,g,14,0`).
use e.io
use e.mem
use e.net
use e.net.grpc as grpc
use e.net.grpcserver as gs
use e.net.http2 as h2
use e.os
use e.str

fn parse_number(s: str) -> u32 {
    var v = 0u32
    var i = 0usize
    while i < s.len {
        if s[i] >= 48u8 && s[i] <= 57u8 { v = v * 10u32 + u32(s[i] - 48u8) }
        i += 1usize
    }
    ret v
}

// Behaviour `ordinal` of the script: 0..16 a status, 100 refuse, 101 goaway, 102 silence.
fn behaviour(script: str, ordinal: u32) -> u32 {
    var index = 0u32
    var start = 0usize
    var chosen = 0u32
    var i = 0usize
    while i <= script.len {
        if i == script.len || script[i] == 44u8 {
            var token = script[start..i]
            var value = 0u32
            if token.len > 0usize && token[0usize] == 114u8 {
                value = 100u32
            } else if token.len > 0usize && token[0usize] == 103u8 {
                value = 101u32
            } else if token.len > 0usize && token[0usize] == 115u8 {
                value = 102u32
            } else {
                value = parse_number(token)
            }
            chosen = value
            if index == ordinal { ret value }
            index += 1u32
            start = i + 1usize
        }
        i += 1usize
    }
    ret chosen
}

fn send_all(sock: net.Socket, data: []const u8) -> err {
    var at = 0usize
    while at < data.len {
        let (n, e) = net.send(sock, data[at..])
        if e != ok { ret e }
        if n == 0usize { ret grpc.Protocol }
        at += n
    }
    ret ok
}

fn serve(a: *mem.Arena, sock: net.Socket, script: str, ordinal: *u32) -> err {
    let mark = mem.mark(a)
    let (calls, ce) = mem.alloc[gs.Call](a, 8usize)
    if ce != ok { ret ce }
    var c = 0usize
    while c < calls.len {
        let (buf, be) = mem.alloc[u8](a, 4096usize)
        if be != ok { ret be }
        calls[c].buf = buf
        c += 1usize
    }
    let (enc_data, e1) = mem.alloc[u8](a, 4096usize)
    let (enc_lens, e2) = mem.alloc[u32](a, 256usize)
    let (dec_data, e3) = mem.alloc[u8](a, 4096usize)
    let (dec_lens, e4) = mem.alloc[u32](a, 256usize)
    let (block, e5) = mem.alloc[u8](a, 16384usize)
    let (inbuf, e6) = mem.alloc[u8](a, 65536usize)
    let (out, e7) = mem.alloc[u8](a, 16384usize)
    let (scratch, e8) = mem.alloc[u8](a, 16384usize)
    let (events, e9) = mem.alloc[gs.Event](a, 32usize)
    let (hdr, e10) = mem.alloc[h2.Header](a, 128usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret grpc.TooSmall }
    var s = gs.server_new(calls, h2.table_new(enc_data, enc_lens, 4096usize), h2.table_new(dec_data, dec_lens, 4096usize), block, 65535u32, 16384u32)
    let (start_len, start_error) = gs.server_start(&s, out)
    if start_error != ok { ret start_error }
    let sent_start = send_all(sock, out[0usize..start_len])
    if sent_start != ok { ret sent_start }
    var have = 0usize
    var closing = false
    while !closing {
        let (n, re) = net.receive(sock, inbuf[have..])
        if re != ok || n == 0usize { break }
        have += n
        var again = true
        while again && !closing {
            let (used, out_n, count, rx) = gs.server_receive(&s, inbuf[0usize..have], out, events, hdr, scratch)
            if rx != ok { ret rx }
            var at = out_n
            var k = 0usize
            while k < count && !closing {
                let ev = events[k]
                if ev.kind == gs.EVENT_REQUEST {
                    let b = behaviour(script, *ordinal)
                    *ordinal += 1u32
                    let none: []const h2.Header = zero
                    if b == 100u32 {
                        let (rn, re2) = gs.response_reset(&s, out[at..], ev.stream, 7u32)
                        if re2 != ok { ret re2 }
                        at += rn
                    } else if b == 101u32 {
                        // GOAWAY: stream 0, the last stream id below the request, NO_ERROR; then the connection ends
                        var frame: [17]u8 = zero
                        frame[2usize] = 8u8
                        frame[3usize] = 7u8
                        var last = 0u32
                        if ev.stream > 2u32 { last = ev.stream - 2u32 }
                        frame[9usize] = u8(last >> 24u32)
                        frame[10usize] = u8((last >> 16u32) & 255u32)
                        frame[11usize] = u8((last >> 8u32) & 255u32)
                        frame[12usize] = u8(last & 255u32)
                        let mut_sent = send_all(sock, out[0usize..at])
                        at = 0usize
                        let goaway_sent = send_all(sock, frame[0usize..17usize])
                        closing = true
                    } else if b == 102u32 {
                        let nothing = 0u8
                    } else {
                        if b == 0u32 {
                            let (mn, me) = gs.response_message(&s, out[at..], ev.stream, "ok", false)
                            if me != ok { ret me }
                            at += mn
                        }
                        let (fnn, fe) = gs.response_finish(&s, out[at..], ev.stream, b, "", none)
                        if fe != ok { ret fe }
                        at += fnn
                    }
                }
                k += 1usize
            }
            if at > 0usize {
                let sent = send_all(sock, out[0usize..at])
                if sent != ok { ret sent }
            }
            var m = 0usize
            while m + used < have {
                inbuf[m] = inbuf[m + used]
                m += 1usize
            }
            have -= used
            again = used > 0usize || count > 0usize
        }
    }
    mem.reset(a, mark)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { ret grpc.Protocol }
    let port = u16(parse_number(args[args.len - 2usize]))
    let script = args[args.len - 1usize]
    var address_bytes: [4]u8 = zero
    address_bytes[0usize] = 127u8
    address_bytes[3usize] = 1u8
    let endpoint = net.Endpoint { address: net.Address{ Ip4: net.Ip4{ bytes: address_bytes } }, port: port }
    let (listener, le) = net.tcp_listen(endpoint, 8u32)
    if le != ok { ret le }
    defer {
        let closed_listener = os.socket_close(listener)
    }
    try io.print("listening\n")
    var ordinal = 0u32
    while true {
        let (sock, peer, ae) = net.tcp_accept(listener)
        if ae != ok { ret ae }
        let served = serve(a, sock, script, &ordinal)
        let closed = os.socket_close(sock)
    }
    ret ok
}
