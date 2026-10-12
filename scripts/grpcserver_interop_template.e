// The live interop server of `e.net.grpcserver` (L164): scripts/grpcserver_vectors.py compiles this with the echo service
// (scripts/grpcserver_app.e) after the marker, runs it on a loopback port and calls it with grpcio. Serves one connection
// at a time until the process is stopped. Generated; do not edit.
use e.io
use e.mem
use e.net
use e.net.grpc as grpc
use e.net.grpcserver as gs
use e.net.http2 as h2
use e.os
use e.str

//__APP__

fn parse_port(s: str) -> u16 {
    var v = 0u32
    var i = 0usize
    while i < s.len {
        if s[i] >= 48u8 && s[i] <= 57u8 { v = v * 10u32 + u32(s[i] - 48u8) }
        i += 1usize
    }
    ret u16(v)
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

fn serve(a: *mem.Arena, sock: net.Socket) -> err {
    let mark = mem.mark(a)
    let (calls, ce) = mem.alloc[gs.Call](a, 6usize)
    if ce != ok { ret ce }
    var c = 0usize
    while c < calls.len {
        let (buf, be) = mem.alloc[u8](a, 262144usize)
        if be != ok { ret be }
        calls[c].buf = buf
        c += 1usize
    }
    let (enc_data, e1) = mem.alloc[u8](a, 8192usize)
    let (enc_lens, e2) = mem.alloc[u32](a, 256usize)
    let (dec_data, e3) = mem.alloc[u8](a, 8192usize)
    let (dec_lens, e4) = mem.alloc[u32](a, 256usize)
    let (block, e5) = mem.alloc[u8](a, 16384usize)
    let (inbuf, e6) = mem.alloc[u8](a, 1048576usize)
    let (out, e7) = mem.alloc[u8](a, 262144usize)
    let (scratch, e8) = mem.alloc[u8](a, 16384usize)
    let (events, e9) = mem.alloc[gs.Event](a, 32usize)
    let (hdr, e10) = mem.alloc[h2.Header](a, 128usize)
    let (acc, e11) = mem.alloc[u8](a, 4096usize)
    let (big, e12) = mem.alloc[u8](a, 70016usize)
    let (slots, e13) = mem.alloc[Slot](a, 6usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret grpc.TooSmall }
    var s = gs.server_new(calls, h2.table_new(enc_data, enc_lens, 4096usize), h2.table_new(dec_data, dec_lens, 4096usize), block, 65535u32, 16384u32)
    var s_slots = 0usize
    while s_slots < slots.len {
        slots[s_slots].used = false
        s_slots += 1usize
    }
    var app = App { srv: &s, slots: slots, acc: acc, big: big }
    let (start_len, start_error) = gs.server_start(&s, out)
    if start_error != ok { ret start_error }
    let sent_start = send_all(sock, out[0usize..start_len])
    if sent_start != ok { ret sent_start }
    var have = 0usize
    while true {
        let (n, re) = net.receive(sock, inbuf[have..])
        if re != ok || n == 0usize { break }
        have += n
        var again = true
        while again {
            let (used, out_n, count, rx) = gs.server_receive(&s, inbuf[0usize..have], out, events, hdr, scratch)
            if rx != ok { ret rx }
            var at = out_n
            var k = 0usize
            while k < count {
                let ae = app_event(&app, events[k], out, &at)
                if ae != ok { ret ae }
                k += 1usize
            }
            let pe = pump_all(&app, out, &at)
            if pe != ok { ret pe }
            if at > 0usize {
                let sent = send_all(sock, out[0usize..at])
                if sent != ok { ret sent }
            }
            // keep what was not consumed
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
    var port = 0u16
    if args.len > 0usize { port = parse_port(args[args.len - 1usize]) }
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
    while true {
        let (sock, peer, ae) = net.tcp_accept(listener)
        if ae != ok { ret ae }
        let served = serve(a, sock)
        let closed = os.socket_close(sock)
    }
    ret ok
}
