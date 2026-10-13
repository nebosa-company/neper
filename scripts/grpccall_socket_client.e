// The socket run of `e.net.grpccall` (L164): the call loop of the module driven over a real loopback TCP connection with the
// real clock against scripts/grpccall_socket_server.e (`e.net.grpcserver`). A START opens a stream on the connection (a new
// connection after a GOAWAY), a CANCEL resets one, a WAIT sleeps until its instant or the next bytes. Prints
// `attempts CODE` for the call.
// Usage: grpccall_socket_client PORT MAX_ATTEMPTS CODES_MASK INITIAL_MS PER_ATTEMPT_MS DEADLINE_MS
use e.io
use e.mem
use e.net
use e.net.grpc as grpc
use e.net.grpccall as gc
use e.net.grpcretry as retry
use e.net.http2 as h2
use e.os
use e.str
use e.sync
use e.time
use e.fmt.json as json

fn parse_number(s: str) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < s.len {
        if s[i] >= 48u8 && s[i] <= 57u8 { v = v * 10u64 + u64(s[i] - 48u8) }
        i += 1usize
    }
    ret v
}

fn new_client(a: *mem.Arena) -> grpc.Conn {
    let (streams, se) = mem.alloc[grpc.Stream](a, 8usize)
    let (enc_data, e1) = mem.alloc[u8](a, 4096usize)
    let (enc_lens, e2) = mem.alloc[u32](a, 256usize)
    let (dec_data, e3) = mem.alloc[u8](a, 4096usize)
    let (dec_lens, e4) = mem.alloc[u32](a, 256usize)
    let (block, e5) = mem.alloc[u8](a, 16384usize)
    if se != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(97i32) }
    ret grpc.conn_new(streams, h2.table_new(enc_data, enc_lens, 4096usize), h2.table_new(dec_data, dec_lens, 4096usize), block, 65535u32, 16384u32)
}

fn send_all(sock: net.Socket, data: []const u8) -> bool {
    var at = 0usize
    while at < data.len {
        let (n, e) = net.send(sock, data[at..])
        if e != ok || n == 0usize { ret false }
        at += n
    }
    ret true
}

fn now_ns() -> u64 {
    let (t, e) = time.monotonic()
    if e != ok { ret 0u64 }
    ret u64(t.nanos)
}

fn connect(port: u16) -> net.Socket {
    var address_bytes: [4]u8 = zero
    address_bytes[0usize] = 127u8
    address_bytes[3usize] = 1u8
    let endpoint = net.Endpoint { address: net.Address{ Ip4: net.Ip4{ bytes: address_bytes } }, port: port }
    let (sock, e) = net.tcp_connect(endpoint)
    if e != ok { os.exit(90i32) }
    let nb = os.socket_set_nonblocking(sock, true)
    ret sock
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 6usize { os.exit(91i32) }
    let base = args.len - 6usize
    let port = u16(parse_number(args[base]))
    let policy = retry.Policy { max_attempts: u32(parse_number(args[base + 1usize])), initial_ns: parse_number(args[base + 3usize]) * 1000000u64, max_ns: parse_number(args[base + 3usize]) * 4000000u64, multiplier: 2.0f64, codes: u32(parse_number(args[base + 2usize])) }
    let per_attempt = parse_number(args[base + 4usize]) * 1000000u64
    let deadline_ms = parse_number(args[base + 5usize])
    let (throttle_value, tpe) = json.parse(a, "{\"maxTokens\":10,\"tokenRatio\":0.1}", json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
    let (throttle, te) = retry.throttle_parse(throttle_value)
    if tpe != ok || te != ok { os.exit(92i32) }
    var bucket = throttle
    let t0 = now_ns()
    var deadline = 0u64
    if deadline_ms > 0u64 { deadline = deadline_ms * 1000000u64 }
    var call = gc.call_retry(policy, &bucket, per_attempt, deadline, 0u64)

    let (events, ee) = mem.alloc[grpc.Event](a, 16usize)
    let (hdr, he) = mem.alloc[h2.Header](a, 64usize)
    let (scratch, sc) = mem.alloc[u8](a, 8192usize)
    let (inbuf, ie) = mem.alloc[u8](a, 65536usize)
    if ee != ok || he != ok || sc != ok || ie != ok { os.exit(93i32) }
    var conn = new_client(a)
    var sock = connect(port)
    var open: [256]u8 = zero
    let (opened, oe) = grpc.conn_start(&conn, open[0usize..])
    if oe != ok { os.exit(94i32) }
    if !send_all(sock, open[0usize..opened]) { os.exit(95i32) }
    var nap = sync.semaphore(0u32)
    var have = 0usize
    var attempts = 0u32
    var code = 99u32
    var steps = 0u32
    while steps < 20000u32 {
        steps += 1u32
        // what has arrived
        let (n, re) = os.socket_receive(sock, inbuf[have..])
        if re == ok && n > 0usize {
            have += n
            var again = true
            while again {
                var reply: [512]u8 = zero
                let (used, out_n, count, e) = grpc.conn_receive(&conn, inbuf[0usize..have], reply[0usize..], events, hdr, scratch)
                if e != ok { os.exit(96i32) }
                var k = 0usize
                while k < count {
                    gc.call_event(&call, &events[k], now_ns() - t0, 0.5f64)
                    k += 1usize
                }
                if out_n > 0usize {
                    if !send_all(sock, reply[0usize..out_n]) { os.exit(95i32) }
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
        let now = now_ns() - t0
        let act = gc.call_poll(&call, now, 0.5f64)
        if act.kind == gc.ACTION_START {
            if conn.goaway {
                let closed = os.socket_close(sock)
                conn = new_client(a)
                sock = connect(port)
                var reopen: [256]u8 = zero
                let (reopened, roe) = grpc.conn_start(&conn, reopen[0usize..])
                if roe != ok { os.exit(94i32) }
                if !send_all(sock, reopen[0usize..reopened]) { os.exit(95i32) }
                have = 0usize
            }
            attempts += 1u32
            var wire: [1024]u8 = zero
            var none: [1]h2.Header = zero
            let (rb, rbe) = mem.alloc[u8](a, 1024usize)
            if rbe != ok { os.exit(116i32) }
            let (id, n1, e1) = grpc.call_start(&conn, wire[0usize..], "h", "/t.S/M", 0u64, none[0usize..0usize], rb)
            if e1 != ok { os.exit(117i32) }
            let (n2, e2) = grpc.call_send(&conn, wire[n1..], id, "ping", false, true)
            if e2 != ok { os.exit(118i32) }
            gc.call_opened(&call, act.attempt, id, now)
            if !send_all(sock, wire[0usize..n1 + n2]) { os.exit(95i32) }
        } else if act.kind == gc.ACTION_CANCEL {
            var wire: [64]u8 = zero
            let (cn, ce) = grpc.call_cancel(&conn, wire[0usize..], act.stream)
            if ce != ok { os.exit(119i32) }
            if !send_all(sock, wire[0usize..cn]) { os.exit(95i32) }
        } else if act.kind == gc.ACTION_WAIT {
            let woke = sync.semaphore_wait_for(&nap, time.millis(1i64))
        } else if act.kind == gc.ACTION_DONE {
            code = act.code
            break
        }
    }
    let closed = os.socket_close(sock)
    try io.print(grpc_line(a, attempts, code))
    ret ok
}

fn grpc_line(a: *mem.Arena, attempts: u32, code: u32) -> str {
    let (b, be) = str.builder(a, 64usize)
    if be != ok { ret "error\n" }
    var builder = b
    let e0 = str.push(&builder, "result ")
    let e1 = str.push_u32(&builder, attempts)
    let e2 = str.push(&builder, " ")
    let e3 = str.push_u32(&builder, code)
    let e4 = str.push(&builder, "\n")
    ret str.done(&builder)
}
