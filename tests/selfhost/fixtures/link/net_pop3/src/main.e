// e.net.pop3 (L083, D2276): a scripted POP3 server compared byte for byte (USER/PASS, STAT, LIST, UIDL, RETR with
// dot-unstuffing, TOP, DELE, RSET, NOOP, QUIT, CAPA, -ERR answers, size limit, injection guard, malformed status)
// and a live STLS session against a server thread over pipes that checks the decrypted commands it receives.
use e.io
use e.mem
use e.net.pop3 as pop3
use e.net.tls as tls
use e.os
use e.time

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
    let _ = io.print("net pop3 failed at ")
    var digits: [4]u8 = zero
    digits[0] = u8(48i32 + code / 100i32)
    digits[1] = u8(48i32 + (code / 10i32) % 10i32)
    digits[2] = u8(48i32 + code % 10i32)
    let _ = io.print(digits[..3])
    let _ = io.print("\n")
    os.exit(code)
    ret ok
}

type Scene = struct { sent: [4096]u8, writer: io.SliceWriter, reader: io.SliceReader }

type Job = struct { reading: *os.File, writing: *os.File, config: tls.ServerConfig, failure: i32, received: [2048]u8, received_len: usize }

fn line_from(source: *io.Reader, buf: []u8) -> (usize, err) {
    var n = 0usize
    var one: [1]u8 = zero
    while true {
        let (got, read_error) = io.read(source, one[0..])
        if read_error != ok { ret (0usize, read_error) }
        if got == 0usize { continue }
        if one[0] == 10u8 { break }
        if n < buf.len {
            buf[n] = one[0]
            n += 1usize
        }
    }
    ret (n, ok)
}

fn serve(job: *Job) {
    var storage: [262144]u8 = zero
    var arena = mem.arena_from(storage[0..])
    var source = io.file_reader(job.reading)
    var sink = io.file_writer(job.writing)
    var line: [256]u8 = zero
    if io.write_all(&sink, "+OK live ready\r\n") != ok { job.failure = 101i32 }
    let (n, line_error) = line_from(&source, line[0..])
    if line_error != ok || !same(line[..n], "STLS\r") { job.failure = 102i32 }
    if io.write_all(&sink, "+OK begin TLS negotiation\r\n") != ok { job.failure = 103i32 }
    let (secure0, create_error) = tls.server(&arena, source, sink, job.config)
    if create_error != ok { job.failure = 106i32 }
    if job.failure != 0i32 { ret }
    var secure = secure0
    if tls.handshake(&secure) != ok {
        job.failure = 107i32
        ret
    }
    var secure_source = tls.reader(&secure)
    var secure_sink = tls.writer(&secure)
    var step = 0i32
    var at = 0usize
    while step < 5i32 {
        let (m, m_error) = line_from(&secure_source, line[0..])
        if m_error != ok {
            job.failure = 110i32 + step
            ret
        }
        if at + m + 1usize <= job.received.len {
            mem.copy[u8](job.received[at..], line[..m])
            job.received[at + m] = 10u8
            at += m + 1usize
        }
        var reply = ""
        if step == 0i32 { reply = "+OK send PASS\r\n" }
        if step == 1i32 { reply = "+OK welcome\r\n" }
        if step == 2i32 { reply = "+OK 2 120\r\n" }
        if step == 3i32 { reply = "+OK 52 octets\r\nSubject: a\r\n\r\n..dot\r\nend\r\n.\r\n" }
        if step == 4i32 { reply = "+OK bye\r\n" }
        if io.write_all(&secure_sink, reply) != ok {
            job.failure = 130i32 + step
            ret
        }
        step += 1i32
    }
    job.received_len = at
    let _ = tls.close(&secure)
}

fn client_side(a: *mem.Arena, client_read: *os.File, client_write: *os.File, client_config: tls.ClientConfig) -> i32 {
    let (live0, live_error) = pop3.connect(a, io.file_reader(client_read), io.file_writer(client_write))
    if live_error != ok { ret 30i32 }
    var live = live0
    if !same(live.greeting, "live ready") { ret 31i32 }
    if pop3.starttls(&live, client_config) != ok { ret 32i32 }
    if !live.secured { ret 33i32 }
    if pop3.starttls(&live, client_config) != pop3.Unsupported { ret 34i32 }
    if pop3.login(&live, "alice", "secret") != ok { ret 35i32 }
    let (counts, stat_error) = pop3.stat(&live)
    if stat_error != ok || counts.count != 2usize || counts.octets != 120u64 { ret 36i32 }
    let (message, retr_error) = pop3.retr(&live, 1usize, 4096usize)
    if retr_error != ok || !same(message, "Subject: a\r\n\r\n.dot\r\nend\r\n") { ret 37i32 }
    if pop3.quit(&live) != ok { ret 38i32 }
    ret 0i32
}

fn run_live(a: *mem.Arena, server_read: *os.File, server_write: *os.File, client_read: *os.File, client_write: *os.File, leaf_der: str, leaf_pkcs8: str, mid_der: str, server_entropy: []const u8, client_entropy: []const u8) -> i32 {
    let none_protocols: [0]str = zero
    var job: Job = zero
    job.reading = server_read
    job.writing = server_write
    job.config = tls.ServerConfig { certificate_chain: leaf_der, private_key: leaf_pkcs8, alpn: none_protocols[0..], entropy: server_entropy }
    let (server_thread, thread_error) = os.thread_create[Job](serve, &job, 8388608usize)
    if thread_error != ok { ret 29i32 }
    let client_config = tls.ClientConfig { server_name: "example.com", trust_roots: mid_der, alpn: none_protocols[0..], entropy: client_entropy, now: time.Timestamp { nanos: 1780272000000000000i64 } }
    let client_code = client_side(a, client_read, client_write, client_config)
    if client_code != 0i32 { os.exit(client_code) }
    let join_error = os.thread_join(server_thread)
    if join_error != ok { ret 28i32 }
    if job.failure != 0i32 { ret job.failure }
    let want = "STLS\r\nUSER alice\r\nPASS secret\r\nSTAT\r\nRETR 1\r\nQUIT\r\n"
    let seen = job.received[..job.received_len]
    // the server records everything after the handshake: USER, PASS, STAT, RETR, QUIT
    if !same(seen, "USER alice\r\nPASS secret\r\nSTAT\r\nRETR 1\r\nQUIT\r\n") { ret 39i32 }
    if want.len == 0usize { ret 27i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    var scene: Scene = zero
    scene.writer = io.SliceWriter { data: scene.sent[0..], off: 0usize }
    let replies = "+OK POP3 server ready <1896.697170952@dbc.mtview.ca.us>\r\n+OK\r\n+OK logged in\r\n+OK 2 460\r\n+OK 2 messages\r\n1 120\r\n2 340\r\n.\r\n+OK\r\n1 abc\r\n2 def\r\n.\r\n+OK 340 octets\r\nFrom: a\r\n\r\n..hidden\r\nbody\r\n.\r\n+OK\r\nSubject: x\r\n\r\n.\r\n+OK deleted\r\n-ERR no such message\r\n+OK\r\n+OK\r\n+OK\r\nTOP\r\nUSER\r\n.\r\n+OK bye\r\n"
    scene.reader = io.SliceReader { data: replies, off: 0usize }
    let (s0, connect_error) = pop3.connect(a, io.slice_reader(&scene.reader), io.slice_writer(&scene.writer))
    if connect_error != ok { ret fail(1i32) }
    var s = s0
    if !same(s.greeting, "POP3 server ready <1896.697170952@dbc.mtview.ca.us>") { ret fail(2i32) }
    if pop3.login(&s, "mrose", "tanstaaf") != ok { ret fail(3i32) }
    let (counts, stat_error) = pop3.stat(&s)
    if stat_error != ok || counts.count != 2usize || counts.octets != 460u64 { ret fail(4i32) }
    let (sizes, list_error) = pop3.list(&s, 1024usize)
    if list_error != ok || sizes.len != 2usize || sizes[0].number != 1usize || sizes[0].size != 120u64 || sizes[1].number != 2usize || sizes[1].size != 340u64 { ret fail(5i32) }
    let (ids, uidl_error) = pop3.uidl(&s, 1024usize)
    if uidl_error != ok || ids.len != 2usize || !same(ids[0].id, "abc") || ids[1].number != 2usize || !same(ids[1].id, "def") { ret fail(6i32) }
    let (message, retr_error) = pop3.retr(&s, 2usize, 4096usize)
    if retr_error != ok || !same(message, "From: a\r\n\r\n.hidden\r\nbody\r\n") { ret fail(7i32) }
    let (head, top_error) = pop3.top(&s, 1usize, 0usize, 4096usize)
    if top_error != ok || !same(head, "Subject: x\r\n\r\n") { ret fail(8i32) }
    if pop3.dele(&s, 1usize) != ok { ret fail(9i32) }
    let (_, missing_error) = pop3.retr(&s, 9usize, 4096usize)
    if missing_error != pop3.Rejected || !same(s.last, "no such message") { ret fail(10i32) }
    if pop3.rset(&s) != ok || pop3.noop(&s) != ok { ret fail(11i32) }
    let (capabilities, capa_error) = pop3.capa(&s, 1024usize)
    if capa_error != ok || !same(capabilities, "TOP\r\nUSER\r\n") { ret fail(12i32) }
    if pop3.quit(&s) != ok { ret fail(13i32) }
    let want = "USER mrose\r\nPASS tanstaaf\r\nSTAT\r\nLIST\r\nUIDL\r\nRETR 2\r\nTOP 1 0\r\nDELE 1\r\nRETR 9\r\nRSET\r\nNOOP\r\nCAPA\r\nQUIT\r\n"
    if !same(scene.sent[..scene.writer.off], want) { ret fail(14i32) }

    // refusals: -ERR on PASS, an oversized message, a command carrying CRLF, a malformed status line, 0 as a number
    var two: Scene = zero
    two.writer = io.SliceWriter { data: two.sent[0..], off: 0usize }
    two.reader = io.SliceReader { data: "+OK hi\r\n+OK\r\n-ERR [AUTH] invalid password\r\n+OK 10 octets\r\n0123456789\r\nabcdefghij\r\n.\r\ngarbage\r\n", off: 0usize }
    let (t0, t_error) = pop3.connect(a, io.slice_reader(&two.reader), io.slice_writer(&two.writer))
    if t_error != ok { ret fail(15i32) }
    var t = t0
    if pop3.login(&t, "u", "wrong") != pop3.Rejected || !same(t.last, "[AUTH] invalid password") { ret fail(16i32) }
    let (_, big_error) = pop3.retr(&t, 1usize, 8usize)
    if big_error != pop3.TooLarge { ret fail(17i32) }
    let wrote = two.writer.off
    if pop3.login(&t, "bad\r\nuser", "x") != pop3.Invalid || pop3.dele(&t, 0usize) != pop3.Invalid { ret fail(18i32) }
    if two.writer.off != wrote { ret fail(19i32) }
    var three: Scene = zero
    three.writer = io.SliceWriter { data: three.sent[0..], off: 0usize }
    three.reader = io.SliceReader { data: "+OK hi\r\nhello\r\n", off: 0usize }
    let (u0, u_error) = pop3.connect(a, io.slice_reader(&three.reader), io.slice_writer(&three.writer))
    var u = u0
    if u_error != ok || pop3.noop(&u) != pop3.Protocol { ret fail(20i32) }
    var four: Scene = zero
    four.writer = io.SliceWriter { data: four.sent[0..], off: 0usize }
    four.reader = io.SliceReader { data: "-ERR mailbox locked\r\n", off: 0usize }
    let (_, locked_error) = pop3.connect(a, io.slice_reader(&four.reader), io.slice_writer(&four.writer))
    if locked_error != pop3.Rejected { ret fail(21i32) }
    var five: Scene = zero
    five.writer = io.SliceWriter { data: five.sent[0..], off: 0usize }
    five.reader = io.SliceReader { data: "+OK hi\r\n+OK\r\nline\r\n", off: 0usize }
    let (v0, v_error) = pop3.connect(a, io.slice_reader(&five.reader), io.slice_writer(&five.writer))
    var v = v0
    let (_, cut_error) = pop3.retr(&v, 1usize, 4096usize)
    if v_error != ok || cut_error != pop3.Closed { ret fail(22i32) }

    // ---- STLS against a live server thread ----
    let mid_der = "0\x82\x01\x130\x81\xc6\xa0\x03\x02\x01\x02\x02\x01\x020\x05\x06\x03+ep0%1\x130\x11\x06\x03U\x04\x03\x0c\x0aNeper Root1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0*0\x05\x06\x03+ep\x03!\x00\x819w\x0e\xa8}\x17_V\xa3Tf\xc3L~\xcc\xcb\x8d\x8a\x91\xb4\xee7\xa2]\xf6\x0f[\x8f\xc9\xb3\x94\xa3\x130\x110\x0f\x06\x03U\x1d\x13\x01\x01\xff\x04\x050\x03\x01\x01\xff0\x05\x06\x03+ep\x03A\x00R^\x187\xb39[\xa4N\xc4\x83\x10\xde\xfc\x7f\xa0\xbfF[\xa8^\x04S\xa1\xb2\xf8\xbcM\xc7\xfb\xf1t\x89\xa0\x0e\x07\xcc\xbf\x8f6R\x16\x15\xab\x99\x0e\xdd\xc1,\x8d\x8f*\xd4\xaf\x97\xaae\x8b\xab\xe5\x0d\x8e'\x08"
    let leaf_der = "0\x82\x01=0\x81\xf0\xa0\x03\x02\x01\x02\x02\x01\x030\x05\x06\x03+ep0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x161\x140\x12\x06\x03U\x04\x03\x0c\x0bexample.com0*0\x05\x06\x03+ep\x03!\x00\xedI(\xc6(\xd1\xc2\xc6\xea\xe9\x038\x90Y\x95a)Y':\\c\xf966\xc1F\x14\xac\x877\xd1\xa3L0J0\x0c\x06\x03U\x1d\x13\x01\x01\xff\x04\x020\x000%\x06\x03U\x1d\x11\x04\x1e0\x1c\x82\x0bexample.com\x82\x0d*.example.org0\x13\x06\x03U\x1d%\x04\x0c0\x0a\x06\x08+\x06\x01\x05\x05\x07\x03\x010\x05\x06\x03+ep\x03A\x00\x84Pf\xea\x11\xb7\xdb-w\xdf\xd2\xa8\xden\xd3\xbey|r`B'h\xfc\x22\x08\xca\x8e%u\xa8\xa7)\xd3\xb3\x15Tc\xc8\x10\xa0\x97\x84C\xaaU4\xf0>\x00\x0f\xfau\xe7\xaa\xb9\xae\x9e\x9br\xe8Bv\x09"
    let leaf_pkcs8 = "0.\x02\x01\x000\x05\x06\x03+ep\x04\x22\x04\x20\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03"
    var server_entropy: [64]u8 = zero
    var client_entropy: [64]u8 = zero
    var e = 0usize
    while e < 64usize {
        server_entropy[e] = u8((e * 3usize + 1usize) % 256usize)
        client_entropy[e] = u8((e * 7usize + 5usize) % 256usize)
        e += 1usize
    }
    var server_read: os.File = zero
    var client_write: os.File = zero
    let (sr, cw, c2s_error) = os.pipe()
    if c2s_error != ok { os.exit(23i32) }
    server_read = sr
    client_write = cw
    var client_read: os.File = zero
    var server_write: os.File = zero
    let (cr, sw, s2c_error) = os.pipe()
    if s2c_error != ok { os.exit(24i32) }
    client_read = cr
    server_write = sw
    let live_code = run_live(a, &server_read, &server_write, &client_read, &client_write, leaf_der, leaf_pkcs8, mid_der, server_entropy[0..], client_entropy[0..])
    if live_code != 0i32 { os.exit(live_code) }
    let _ = os.close(server_read)
    let _ = os.close(client_write)
    let _ = os.close(client_read)
    let _ = os.close(server_write)
    try io.print("net pop3 ok\n")
    ret ok
}
