// e.net.mdns against python-zeroconf (scripts/mdns_reference.py writes this file from
// scripts/mdns_fixture_template.e): announcements and goodbyes equal to bytes zeroconf parses back to the intended
// records, queries equal to the expected wire form, responder answers to queries zeroconf built (suppression, QU,
// legacy unicast, case folding, compressed names), the cache reading zeroconf's own responses (expiry, goodbye,
// cache-flush), and a live exchange over two loopback UDP sockets.
use e.io
use e.mem
use e.net
use e.net.dns as dns
use e.net.mdns as mdns
use e.os
use e.thread

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn fail(code: i32) -> err {
    let _ = io.print("net mdns failed at ")
    var digits: [4]u8 = zero
    digits[0] = u8(48i32 + code / 100i32)
    digits[1] = u8(48i32 + (code / 10i32) % 10i32)
    digits[2] = u8(48i32 + code % 10i32)
    let _ = io.print(digits[..3])
    let _ = io.print("\n")
    os.exit(code)
    ret ok
}

fn has_text(found: mdns.Found, text: str) -> bool {
    var i = 0usize
    while i < found.txt.len {
        if same(found.txt[i], text) { ret true }
        i += 1usize
    }
    ret false
}

fn has_address(found: mdns.Found, v6: bool, first: u8, last: u8) -> bool {
    var i = 0usize
    while i < found.addresses.len {
        let address = found.addresses[i]
        var end = 3usize
        if v6 { end = 15usize }
        if address.v6 == v6 && address.bytes[0] == first && address.bytes[end] == last { ret true }
        i += 1usize
    }
    ret false
}

type Job = struct { socket: net.Socket, services: []const mdns.Service, arena: *mem.Arena, failure: i32 }

fn serve(job: *Job) {
    var none: net.Endpoint = zero
    let status = mdns.serve_once(job.arena, job.socket, job.services, none, false)
    if status != ok { job.failure = 101i32 }
}

fn live(a: *mem.Arena, services: []const mdns.Service) -> i32 {
    let (loopback, ip_error) = net.parse_ip("127.0.0.1")
    if ip_error != ok { ret 20i32 }
    let (server, server_error) = net.udp_bind(net.Endpoint { address: loopback, port: 0u16 })
    if server_error != ok { ret 21i32 }
    let (bound, bound_error) = os.socket_local_address(server)
    if bound_error != ok { os.exit(23i32) }
    var arena_storage: [262144]u8 = zero
    var server_arena = mem.arena_from(arena_storage[0..])
    var job = Job { socket: server, services: services, arena: &server_arena, failure: 0i32 }
    let (client0, client_error) = net.udp_bind(net.Endpoint { address: loopback, port: 0u16 })
    if client_error != ok { os.exit(22i32) }
    var client = client0
    defer let _ = net.close(client)
    let (worker, thread_error) = thread.spawn[Job](serve, &job, 4194304usize)
    if thread_error != ok { os.exit(24i32) }
    var question: [512]u8 = zero
    let (q_len, q_error) = mdns.query(question[0..], "_ipp._tcp.local", 12u16, false, zero)
    if q_error != ok { os.exit(25i32) }
    let (_, send_error) = net.send_to(client, net.Endpoint { address: loopback, port: bound.port }, question[..q_len])
    if send_error != ok { os.exit(26i32) }
    var reply: [1500]u8 = zero
    let (n, from, receive_error) = net.receive_from(client, reply[0..])
    let join_error = thread.join(worker)
    if receive_error != ok || join_error != ok { os.exit(27i32) }
    if job.failure != 0i32 || from.port != bound.port { os.exit(28i32) }
    if net.close(job.socket) != ok { os.exit(32i32) }
    let (cache, cache_error) = mdns.cache_new(a)
    if cache_error != ok { ret 29i32 }
    var live_cache = cache
    let (seen, learn_error) = mdns.learn(&live_cache, reply[..n], 1000u64)
    if learn_error != ok || seen != 6usize { ret 30i32 }
    let (found, discover_error) = mdns.discover(&live_cache, a, "_ipp._tcp", "local", 2000u64)
    if discover_error != ok || found.len != 1usize || found[0].port != 631u16 || !found[0].resolved { ret 31i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
@@SETUP@@
@@CASES@@
    var out: [9000]u8 = zero

    // ---- announcements and goodbyes ----
    let (n1, e1) = mdns.announce(a, out[0..], services[0..], false)
    if e1 != ok || !same(out[..n1], @@D_ANNOUNCE_ALL@@) { ret fail(1i32) }
    let (n2, e2) = mdns.announce(a, out[0..], services[..1], false)
    if e2 != ok || !same(out[..n2], @@D_ANNOUNCE_ONE@@) { ret fail(2i32) }
    let (n3, e3) = mdns.announce(a, out[0..], services[0..], true)
    if e3 != ok || !same(out[..n3], @@D_GOODBYE_ALL@@) { ret fail(3i32) }
    let (_, e4) = mdns.announce(a, out[..20], services[0..], false)
    if e4 != mdns.TooSmall { ret fail(4i32) }
    let (_, e5) = mdns.announce(a, out[0..], services[..0], false)
    if e5 != mdns.Invalid { ret fail(5i32) }

    // ---- queries ----
    let (q1, qe1) = mdns.query(out[0..], "_ipp._tcp.local", 12u16, false, zero)
    if qe1 != ok || !same(out[..q1], @@D_QUERY_PTR@@) { ret fail(6i32) }
    let (q2, qe2) = mdns.query(out[0..], "_ipp._tcp.local.", 12u16, true, zero)
    if qe2 != ok || !same(out[..q2], @@D_QUERY_PTR_QU@@) { ret fail(7i32) }
    let known = [1]mdns.Known{ mdns.Known { target: @@D_INST_WIRE@@, ttl: 4000u32 } }
    let (q3, qe3) = mdns.query(out[0..], "_ipp._tcp.local", 12u16, false, known[0..])
    if qe3 != ok || !same(out[..q3], @@D_QUERY_KNOWN@@) { ret fail(8i32) }
    let (q4, qe4) = mdns.query(out[0..], "My Printer._ipp._tcp.local", 33u16, false, zero)
    if qe4 != ok || !same(out[..q4], @@D_QUERY_SRV@@) { ret fail(9i32) }
    let (_, qe5) = mdns.query(out[0..], "bad..name", 12u16, false, zero)
    if qe5 != mdns.Invalid { ret fail(10i32) }

    // ---- the responder against queries zeroconf built ----
    var c = 0usize
    while c < case_count {
        let mark = mem.mark(a)
        let (reply, answer_error) = mdns.answer(a, out[0..], services[0..], case_queries[c], case_legacy[c])
        if answer_error != ok { ret fail(100i32 + i32(c)) }
        if !same(out[..reply.len], case_wants[c]) { ret fail(200i32 + i32(c)) }
        if case_wants[c].len > 0usize && reply.unicast != case_unicast[c] { ret fail(300i32 + i32(c)) }
        mem.reset(a, mark)
        c += 1usize
    }
    let (_, malformed) = mdns.answer(a, out[0..], services[0..], "\x00\x00", false)
    if malformed != mdns.Malformed { ret fail(11i32) }

    // ---- the cache against zeroconf's own responses ----
    let (cache0, cache_error) = mdns.cache_new(a)
    if cache_error != ok { ret fail(12i32) }
    var cache = cache0
    let (seen, learn_error) = mdns.learn(&cache, @@D_ZC_PRINTER@@, 1000u64)
    if learn_error != ok || seen != 6usize { ret fail(13i32) }
    let (found, found_error) = mdns.discover(&cache, a, "_ipp._tcp", "local", 2000u64)
    if found_error != ok || found.len != 1usize { ret fail(14i32) }
    let ipp = found[0]
    if !ipp.resolved || !same(ipp.instance, "My Printer") || !same(ipp.host, "printer.local.") || ipp.port != 631u16 || ipp.priority != 0u16 { ret fail(15i32) }
    if ipp.txt.len != 3usize || !has_text(ipp, "rp=ipp/print") || !has_text(ipp, "ty=Acme X") || !has_text(ipp, "note=caf\xc3\xa9") { ret fail(16i32) }
    if ipp.addresses.len != 3usize || !has_address(ipp, false, 192u8, 20u8) || !has_address(ipp, false, 10u8, 7u8) || !has_address(ipp, true, 254u8, 240u8) { ret fail(17i32) }
    let (none_found, none_error) = mdns.discover(&cache, a, "_http._tcp", "local", 2000u64)
    if none_error != ok || none_found.len != 0usize { ret fail(18i32) }
    let (both, both_error) = mdns.learn(&cache, @@D_ZC_BOTH@@, 3000u64)
    if both_error != ok || both < 7usize { ret fail(19i32) }
    let (web, web_error) = mdns.discover(&cache, a, "_http._tcp", "local", 3500u64)
    if web_error != ok || web.len != 1usize || !same(web[0].instance, "Web Server") || web[0].port != 80u16 || web[0].priority != 1u16 || web[0].weight != 5u16 || web[0].txt.len != 0usize || web[0].addresses.len != 3usize { ret fail(20i32) }
    // TTLs: hosts live 120 s, PTR and TXT 4500 s
    let (later, later_error) = mdns.discover(&cache, a, "_ipp._tcp", "local", 1000u64 + 121000u64 + 2000u64)
    if later_error != ok || later.len != 1usize || later[0].resolved { ret fail(21i32) }
    let (expired, expired_error) = mdns.discover(&cache, a, "_ipp._tcp", "local", 3000u64 + 4500000u64 + 1u64)
    if expired_error != ok || expired.len != 0usize { ret fail(22i32) }

    // a goodbye leaves the record one more second
    let (cache1, cache1_error) = mdns.cache_new(a)
    if cache1_error != ok { ret fail(23i32) }
    var goodbye_cache = cache1
    let (_, g1) = mdns.learn(&goodbye_cache, @@D_ZC_PRINTER@@, 1000u64)
    let (_, g2) = mdns.learn(&goodbye_cache, @@D_ZC_GOODBYE@@, 5000u64)
    if g1 != ok || g2 != ok { ret fail(24i32) }
    let (during, during_error) = mdns.discover(&goodbye_cache, a, "_ipp._tcp", "local", 5500u64)
    let (after, after_error) = mdns.discover(&goodbye_cache, a, "_ipp._tcp", "local", 6001u64)
    if during_error != ok || during.len != 1usize || after_error != ok || after.len != 0usize { ret fail(25i32) }

    // cache-flush: a changed TXT and address replace the old ones a second later; the IPv6 address was not resent and stays
    let (cache2, cache2_error) = mdns.cache_new(a)
    if cache2_error != ok { ret fail(26i32) }
    var flush_cache = cache2
    let (_, f1) = mdns.learn(&flush_cache, @@D_ZC_PRINTER@@, 1000u64)
    let (_, f2) = mdns.learn(&flush_cache, @@D_ZC_CHANGED@@, 3000u64)
    if f1 != ok || f2 != ok { ret fail(27i32) }
    let (flushed, flushed_error) = mdns.discover(&flush_cache, a, "_ipp._tcp", "local", 4500u64)
    if flushed_error != ok || flushed.len != 1usize { ret fail(28i32) }
    if flushed[0].txt.len != 2usize || !has_text(flushed[0], "ty=Acme Y") || has_text(flushed[0], "ty=Acme X") { ret fail(29i32) }
    if flushed[0].addresses.len != 2usize || !has_address(flushed[0], false, 192u8, 99u8) || !has_address(flushed[0], true, 254u8, 240u8) { ret fail(30i32) }

    // a query is not learned from, a truncated packet is Malformed
    let (zero_seen, zero_error) = mdns.learn(&flush_cache, @@D_QUERY_KNOWN@@, 5000u64)
    if zero_error != ok || zero_seen != 0usize { ret fail(31i32) }
    let (_, cut_error) = mdns.learn(&flush_cache, "\x00\x00\x84\x00\x00\x00\x00\x02\x00\x00\x00\x00\x03abc", 5000u64)
    if cut_error != mdns.Malformed { ret fail(32i32) }

    // ---- a live exchange over loopback UDP ----
    let live_code = live(a, services[0..])
    if live_code != 0i32 { ret fail(400i32 + live_code) }
    try io.print("net mdns ok\n")
    ret ok
}
