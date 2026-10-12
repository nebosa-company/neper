// `e.net.http` keep-alive pool (L107): three scripted loopback servers (one thread each) count the connections they
// accept and the requests they serve, and the fixture asserts those counts against the pool's own. Covered: reuse
// across Content-Length, chunked, HEAD and 204 responses, the cases that must not be reused (Connection: close,
// close-delimited, HTTP/1.0 without keep-alive), HTTP/1.0 keep-alive, idle eviction under the caller's clock, a
// stale connection retried for an idempotent method and not for POST, the per-host limit, slot-pressure eviction
// across hosts, and CONNECT refused. Each check has its own exit code.
use e.cancel
use e.mem
use e.net
use e.net.http
use e.os
use e.str
use e.thread

type Server = struct { listener: net.Socket, accepts: usize, requests: usize }

fn find_end(buf: []const u8, used: usize) -> bool {
    if used < 4usize { ret false }
    ret buf[used - 4usize] == 13u8 && buf[used - 3usize] == 10u8 && buf[used - 2usize] == 13u8 && buf[used - 1usize] == 10u8
}

fn target_is(buf: []const u8, used: usize, want: str) -> bool {
    // "<METHOD> <target> HTTP..." : find the first space and compare what follows.
    var i = 0usize
    while i < used && buf[i] != 32u8 { i += 1usize }
    i += 1usize
    if i + want.len + 1usize > used { ret false }
    var j = 0usize
    while j < want.len {
        if buf[i + j] != want[j] { ret false }
        j += 1usize
    }
    ret buf[i + want.len] == 32u8
}

fn send_all(conn: net.Socket, text: str) -> bool {
    var at = 0usize
    while at < text.len {
        let (count, send_error) = net.send(conn, text[at..])
        if send_error != ok || count == 0usize { ret false }
        at += count
    }
    ret true
}

// Serve one connection until its peer closes or a response asks the server to close.
fn serve_connection(s: *Server, conn: net.Socket) -> bool {
    var buf: [512]u8 = zero
    var used = 0usize
    while true {
        let (count, receive_error) = net.receive(conn, buf[used..])
        if receive_error != ok || count == 0usize { ret false }
        used += count
        if !find_end(buf[0usize..], used) { continue }
        var close_after = false
        if target_is(buf[0usize..], used, "/quit") { ret true }
        s.requests += 1usize
        if target_is(buf[0usize..], used, "/chunk") {
            if !send_all(conn, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n") { ret false }
        } else if target_is(buf[0usize..], used, "/close") {
            if !send_all(conn, "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 1\r\n\r\nx") { ret false }
            close_after = true
        } else if target_is(buf[0usize..], used, "/eof") {
            if !send_all(conn, "HTTP/1.1 200 OK\r\n\r\nrest") { ret false }
            close_after = true
        } else if target_is(buf[0usize..], used, "/h10") {
            if !send_all(conn, "HTTP/1.0 200 OK\r\nContent-Length: 1\r\n\r\nz") { ret false }
        } else if target_is(buf[0usize..], used, "/h10ka") {
            if !send_all(conn, "HTTP/1.0 200 OK\r\nConnection: keep-alive\r\nContent-Length: 1\r\n\r\nk") { ret false }
        } else if target_is(buf[0usize..], used, "/head") {
            if !send_all(conn, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n") { ret false }
        } else if target_is(buf[0usize..], used, "/nocontent") {
            if !send_all(conn, "HTTP/1.1 204 No Content\r\n\r\n") { ret false }
        } else if target_is(buf[0usize..], used, "/drop") {
            if !send_all(conn, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok") { ret false }
            close_after = true
        } else {
            if !send_all(conn, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok") { ret false }
        }
        used = 0usize
        if close_after { ret false }
    }
}

fn serve(s: *Server) {
    while true {
        let (accepted, peer, accept_error) = net.tcp_accept(s.listener)
        if accept_error != ok { ret }
        var conn = accepted
        s.accepts += 1usize
        let quit = serve_connection(s, conn)
        let unused_close = net.close(conn)
        if quit {
            s.accepts -= 1usize
            ret
        }
    }
}

fn bind() -> (net.Socket, net.Endpoint, err) {
    let (loopback, parse_error) = net.parse_ip("127.0.0.1")
    var endpoint = net.Endpoint { address: loopback, port: 0u16 }
    var none: net.Socket = zero
    if parse_error != ok { ret (none, endpoint, parse_error) }
    let (listener, listen_error) = net.tcp_listen(endpoint, 8u32)
    if listen_error != ok { ret (none, endpoint, listen_error) }
    let (bound, bound_error) = os.socket_local_address(listener)
    if bound_error != ok {
        let unused = net.close(listener)
        ret (none, endpoint, bound_error)
    }
    endpoint.port = bound.port
    ret (listener, endpoint, ok)
}

fn wake(endpoint: net.Endpoint) {
    let (conn, connect_error) = net.tcp_connect(endpoint)
    if connect_error == ok {
        let sent = send_all(conn, "GET /quit HTTP/1.1\r\n\r\n")
        let unused = net.close(conn)
    }
}

fn limits() -> http.Limits {
    ret http.Limits { start_line: 128usize, header_bytes: 512usize, header_count: 16usize, body_bytes: 256usize }
}

fn get(p: *http.Pool, a: *mem.Arena, endpoint: net.Endpoint, method: http.Method, path: str, now: u64) -> (http.Response, err) {
    var headers: [1]http.Header = zero
    headers[0usize] = http.Header { name: "Host", value: "local" }
    let req = http.Request { method: method, target: path, version: .Http11, headers: headers[0usize..], body: "" }
    var none: cancel.Control = zero
    let (response, request_error) = http.pool_request(p, a, endpoint, &req, now, none)
    ret (response, request_error)
}

fn expect(p: *http.Pool, a: *mem.Arena, endpoint: net.Endpoint, method: http.Method, path: str, now: u64, status: u16, body: str, code: i32) {
    let (response, request_error) = get(p, a, endpoint, method, path, now)
    if request_error != ok { os.exit(code) }
    if response.status != status || !str.eq(response.body, body) { os.exit(code + 1i32) }
}

fn main(a: *mem.Arena) -> err {
    let (listen_a, endpoint_a, bind_a) = bind()
    if bind_a != ok { os.exit(2i32) }
    let (listen_b, endpoint_b, bind_b) = bind()
    if bind_b != ok { os.exit(2i32) }
    let (listen_c, endpoint_c, bind_c) = bind()
    if bind_c != ok { os.exit(2i32) }
    var server_a = Server { listener: listen_a, accepts: 0usize, requests: 0usize }
    var server_b = Server { listener: listen_b, accepts: 0usize, requests: 0usize }
    var server_c = Server { listener: listen_c, accepts: 0usize, requests: 0usize }
    let (worker_a, spawn_a) = thread.spawn[Server](serve, &server_a, 0usize)
    if spawn_a != ok { os.exit(3i32) }
    let (worker_b, spawn_b) = thread.spawn[Server](serve, &server_b, 0usize)
    if spawn_b != ok { os.exit(3i32) }
    let (worker_c, spawn_c) = thread.spawn[Server](serve, &server_c, 0usize)
    if spawn_c != ok { os.exit(3i32) }

    var slots: [4]http.PoolSlot = zero
    var pool = http.pool_new(a, slots[0usize..], limits(), 2usize, 1000u64)

    // Reuse: Content-Length, chunked, HEAD and 204 all keep the one connection.
    expect(&pool, a, endpoint_a, .Get, "/a", 0u64, 200u16, "ok", 10i32)
    expect(&pool, a, endpoint_a, .Get, "/a", 10u64, 200u16, "ok", 12i32)
    expect(&pool, a, endpoint_a, .Get, "/chunk", 20u64, 200u16, "abc", 14i32)
    expect(&pool, a, endpoint_a, .Head, "/head", 30u64, 200u16, "", 16i32)
    expect(&pool, a, endpoint_a, .Get, "/nocontent", 40u64, 204u16, "", 18i32)
    if pool.opened != 1usize || pool.reused != 4usize { os.exit(20i32) }
    if http.pool_idle(&pool) != 1usize || http.pool_open(&pool) != 1usize { os.exit(21i32) }

    // Not reusable: Connection: close, a close-delimited body, HTTP/1.0 without keep-alive.
    expect(&pool, a, endpoint_a, .Get, "/close", 50u64, 200u16, "x", 22i32)
    if http.pool_open(&pool) != 0usize { os.exit(24i32) }
    expect(&pool, a, endpoint_a, .Get, "/eof", 60u64, 200u16, "rest", 25i32)
    if pool.opened != 2usize || http.pool_open(&pool) != 0usize { os.exit(27i32) }
    expect(&pool, a, endpoint_a, .Get, "/h10", 70u64, 200u16, "z", 28i32)
    if pool.opened != 3usize || http.pool_open(&pool) != 0usize { os.exit(30i32) }
    // HTTP/1.0 with Connection: keep-alive is kept and then reused.
    expect(&pool, a, endpoint_a, .Get, "/h10ka", 80u64, 200u16, "k", 31i32)
    if pool.opened != 4usize || http.pool_idle(&pool) != 1usize { os.exit(33i32) }
    expect(&pool, a, endpoint_a, .Get, "/a", 90u64, 200u16, "ok", 34i32)
    if pool.opened != 4usize || pool.reused != 6usize { os.exit(36i32) }

    // Idle eviction: the connection last used at 90 is past idle_ms (1000) at 1091.
    let before_evicted = pool.evicted
    expect(&pool, a, endpoint_a, .Get, "/a", 1091u64, 200u16, "ok", 37i32)
    if pool.evicted != before_evicted + 1usize || pool.opened != 5usize { os.exit(39i32) }
    // Exactly at the limit is not past it.
    expect(&pool, a, endpoint_a, .Get, "/a", 2091u64, 200u16, "ok", 40i32)
    if pool.evicted != before_evicted + 1usize || pool.opened != 5usize { os.exit(42i32) }
    if http.pool_evict(&pool, 3092u64) != 1usize || http.pool_open(&pool) != 0usize { os.exit(43i32) }

    // A stale connection (the server closed it after answering): GET is retried on a fresh one, POST is not.
    expect(&pool, a, endpoint_a, .Get, "/drop", 4000u64, 200u16, "ok", 44i32)
    var closed_probe: [1]u8 = zero
    let (probe_count, probe_error) = net.receive(pool.slots[0usize].network.socket, closed_probe[0usize..])
    if probe_error == ok && probe_count != 0usize { os.exit(46i32) }
    let retried_before = pool.retried
    let opened_before = pool.opened
    expect(&pool, a, endpoint_a, .Get, "/drop", 4001u64, 200u16, "ok", 47i32)
    if pool.retried != retried_before + 1usize || pool.opened != opened_before + 1usize { os.exit(49i32) }
    let (probe2_count, probe2_error) = net.receive(pool.slots[0usize].network.socket, closed_probe[0usize..])
    if probe2_error == ok && probe2_count != 0usize { os.exit(50i32) }
    let (post_response, post_error) = get(&pool, a, endpoint_a, .Post, "/a", 4002u64)
    if post_error == ok || pool.retried != retried_before + 1usize { os.exit(51i32) }
    http.pool_close(&pool)
    if http.pool_open(&pool) != 0usize { os.exit(52i32) }

    // Per-host limit (2): two held connections, the third is refused; another host is unaffected.
    var no_control: cancel.Control = zero
    let (hold1, reused1, hold1_error) = http.pool_hold(&pool, endpoint_b, 5000u64, no_control)
    let (hold2, reused2, hold2_error) = http.pool_hold(&pool, endpoint_b, 5000u64, no_control)
    if hold1_error != ok || hold2_error != ok || reused1 || reused2 || hold1 == hold2 { os.exit(53i32) }
    let (hold3, reused3, hold3_error) = http.pool_hold(&pool, endpoint_b, 5000u64, no_control)
    if hold3_error != http.PoolFull { os.exit(54i32) }
    let (hold4, reused4, hold4_error) = http.pool_hold(&pool, endpoint_c, 5000u64, no_control)
    if hold4_error != ok || reused4 { os.exit(55i32) }
    http.pool_release(&pool, hold1, 5001u64, false)
    http.pool_release(&pool, hold2, 5001u64, true)
    http.pool_release(&pool, hold4, 5001u64, false)
    // The kept one is handed out again, marked as a reuse.
    let (hold5, reused5, hold5_error) = http.pool_hold(&pool, endpoint_b, 5002u64, no_control)
    if hold5_error != ok || !reused5 || hold5 != hold2 { os.exit(56i32) }
    http.pool_release(&pool, hold5, 5003u64, false)
    if http.pool_open(&pool) != 0usize { os.exit(57i32) }

    // Slot pressure: two slots, three hosts; the oldest idle connection (host A) is closed to make room for C.
    var small_slots: [2]http.PoolSlot = zero
    var small = http.pool_new(a, small_slots[0usize..], limits(), 2usize, 100000u64)
    expect(&small, a, endpoint_a, .Get, "/a", 6000u64, 200u16, "ok", 58i32)
    expect(&small, a, endpoint_b, .Get, "/a", 6001u64, 200u16, "ok", 60i32)
    expect(&small, a, endpoint_c, .Get, "/a", 6002u64, 200u16, "ok", 62i32)
    if small.evicted != 1usize || small.opened != 3usize || http.pool_idle(&small) != 2usize { os.exit(64i32) }
    // C and B are kept: requesting them again reuses; A needs a new connection and evicts B (older than C).
    expect(&small, a, endpoint_c, .Get, "/a", 6003u64, 200u16, "ok", 65i32)
    if small.reused != 1usize { os.exit(67i32) }
    expect(&small, a, endpoint_a, .Get, "/a", 6004u64, 200u16, "ok", 68i32)
    if small.evicted != 2usize || small.opened != 4usize { os.exit(70i32) }

    // CONNECT is not a pooled exchange.
    let (tunnel, tunnel_error) = get(&small, a, endpoint_a, .Connect, "/a", 6005u64)
    if tunnel_error != http.Unsupported { os.exit(71i32) }

    // The keep-alive rules on their own.
    var close_headers: [1]http.Header = zero
    close_headers[0usize] = http.Header { name: "connection", value: "Upgrade, CLOSE" }
    if http.keeps_alive(.Http11, close_headers[0usize..]) { os.exit(72i32) }
    close_headers[0usize] = http.Header { name: "Connection", value: "keep-alive, Upgrade" }
    if !http.keeps_alive(.Http11, close_headers[0usize..]) || !http.keeps_alive(.Http10, close_headers[0usize..]) { os.exit(73i32) }
    if http.keeps_alive(.Http10, close_headers[0usize..0usize]) { os.exit(74i32) }

    http.pool_close(&small)

    // Server-side counts agree with the pool: every connection the pool opened was accepted once.
    wake(endpoint_a)
    wake(endpoint_b)
    wake(endpoint_c)
    if thread.join(worker_a) != ok || thread.join(worker_b) != ok || thread.join(worker_c) != ok { os.exit(75i32) }
    // A: first, /eof, /h10, /h10ka, post-eviction, /drop, its retry = 7, then the small pool opened it twice.
    if server_a.accepts != 9usize { os.exit(76i32) }
    // B: two held, the small pool once; C: one held, the small pool once.
    if server_b.accepts != 3usize { os.exit(77i32) }
    if server_c.accepts != 2usize { os.exit(78i32) }
    if server_a.requests != 16usize { os.exit(79i32) }
    let unused_a = net.close(server_a.listener)
    let unused_b = net.close(server_b.listener)
    let unused_c = net.close(server_c.listener)
    ret ok
}
