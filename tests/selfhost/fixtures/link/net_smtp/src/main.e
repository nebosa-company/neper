// e.net.smtp (L082, D2275): scripted servers whose replies are fixed and whose received bytes are compared
// exactly (greeting, EHLO and the HELO fallback, AUTH PLAIN, LOGIN and XOAUTH2, MAIL/RCPT/DATA with
// dot-stuffing and CRLF normalisation, partial recipient refusal, SIZE, injection guards, reply parsing), and
// a live STARTTLS session against a server thread over pipes that checks the decrypted commands it receives.
use e.io
use e.mem
use e.net.smtp as smtp
use e.net.tls as tls
use e.os
use e.thread
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
    let _ = io.print("net smtp failed at ")
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

// ---- the live STARTTLS server ----

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

fn starts(line: []const u8, prefix: str) -> bool {
    if line.len < prefix.len { ret false }
    ret same(line[..prefix.len], prefix)
}

fn serve(job: *Job) {
    var storage: [262144]u8 = zero
    var arena = mem.arena_from(storage[0..])
    var source = io.file_reader(job.reading)
    var sink = io.file_writer(job.writing)
    var line: [256]u8 = zero
    if io.write_all(&sink, "220 live.test ESMTP\r\n") != ok { job.failure = 101i32 }
    let (n, line_error) = line_from(&source, line[0..])
    if line_error != ok || !same(line[..n], "EHLO client.test\r") { job.failure = 102i32 }
    if io.write_all(&sink, "250-live.test\r\n250 STARTTLS\r\n") != ok { job.failure = 103i32 }
    let (n2, line2_error) = line_from(&source, line[0..])
    if line2_error != ok || !same(line[..n2], "STARTTLS\r") { job.failure = 104i32 }
    if io.write_all(&sink, "220 2.0.0 ready\r\n") != ok { job.failure = 105i32 }
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
    while step < 7i32 {
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
        if step == 0i32 { reply = "250-live.test\r\n250-AUTH PLAIN\r\n250 8BITMIME\r\n" }
        if step == 1i32 { reply = "235 2.7.0 welcome\r\n" }
        if step == 2i32 { reply = "250 ok\r\n" }
        if step == 3i32 { reply = "250 ok\r\n" }
        if step == 4i32 { reply = "354 end with dot\r\n" }
        if step == 5i32 {
            // the body: lines up to the lone dot
            while true {
                let (b, b_error) = line_from(&secure_source, line[0..])
                if b_error != ok {
                    job.failure = 120i32
                    ret
                }
                if at + b + 1usize <= job.received.len {
                    mem.copy[u8](job.received[at..], line[..b])
                    job.received[at + b] = 10u8
                    at += b + 1usize
                }
                if b == 2usize && line[0] == 46u8 { break }
            }
            reply = "250 2.0.0 queued as 42\r\n"
        }
        if step == 6i32 { reply = "221 bye\r\n" }
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
    let (live0, live_error) = smtp.connect(a, io.file_reader(client_read), io.file_writer(client_write), "client.test")
    if live_error != ok { ret 30i32 }
    var live = live0
    if smtp.ehlo(&live) != ok || !live.caps.starttls { ret 31i32 }
    if smtp.starttls(&live, client_config) != ok { ret 32i32 }
    if !live.secured || !live.caps.auth_plain || !live.caps.eight_bit || live.caps.starttls { ret 33i32 }
    if smtp.starttls(&live, client_config) != smtp.Unsupported { ret 34i32 }
    if smtp.auth(&live, "alice", "secret") != ok { ret 35i32 }
    var live_body = io.SliceReader { data: "To: b@x.test\n\n.hidden\nend", off: 0usize }
    let live_rcpts = [1]str{ "b@x.test" }
    let (live_sent, live_send_error) = smtp.send(&live, "a@x.test", live_rcpts[0..], io.slice_reader(&live_body), 0u64)
    if live_send_error != ok || live_sent.accepted != 1usize || live_sent.reply.code != 250u16 { ret 36i32 }
    if smtp.quit(&live) != ok { ret 37i32 }
    ret 0i32
}

fn run_live(a: *mem.Arena, server_read: *os.File, server_write: *os.File, client_read: *os.File, client_write: *os.File, leaf_der: str, leaf_pkcs8: str, mid_der: str, server_entropy: []const u8, client_entropy: []const u8) -> i32 {
    let none_protocols: [0]str = zero
    var job: Job = zero
    job.reading = server_read
    job.writing = server_write
    job.config = tls.ServerConfig { certificate_chain: leaf_der, private_key: leaf_pkcs8, alpn: none_protocols[0..], entropy: server_entropy[0..] }
    let (server_thread, thread_error) = os.thread_create[Job](serve, &job, 8388608usize)
    if thread_error != ok { ret 29i32 }
    let client_config = tls.ClientConfig { server_name: "example.com", trust_roots: mid_der, alpn: none_protocols[0..], entropy: client_entropy[0..], now: time.Timestamp { nanos: 1780272000000000000i64 } }
    let client_code = client_side(a, client_read, client_write, client_config)
    if client_code != 0i32 { os.exit(client_code) }
    let join_error = os.thread_join(server_thread)
    if join_error != ok { ret 38i32 }
    if job.failure != 0i32 { os.exit(40i32 + job.failure - 100i32) }
    let want_lines = "EHLO client.test\r\nAUTH PLAIN AGFsaWNlAHNlY3JldA==\r\nMAIL FROM:<a@x.test>\r\nRCPT TO:<b@x.test>\r\nDATA\r\nTo: b@x.test\r\n\r\n..hidden\r\nend\r\n.\r\nQUIT\r\n"
    if !same(job.received[..job.received_len], want_lines) { ret 39i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    // ---- a full scripted session ----
    var scene: Scene = zero
    scene.writer = io.SliceWriter { data: scene.sent[0..], off: 0usize }
    let replies = "220 mx.example ESMTP\r\n250-mx.example greets you\r\n250-SIZE 1000\r\n250-8BITMIME\r\n250-ENHANCEDSTATUSCODES\r\n250-AUTH PLAIN LOGIN\r\n250 STARTTLS\r\n235 2.7.0 ok\r\n250 2.1.0 ok\r\n250 2.1.5 ok\r\n550 5.1.1 no such user\r\n354 go\r\n250 2.0.0 queued\r\n221 bye\r\n"
    scene.reader = io.SliceReader { data: replies, off: 0usize }
    let (s0, connect_error) = smtp.connect(a, io.slice_reader(&scene.reader), io.slice_writer(&scene.writer), "client.test")
    if connect_error != ok { ret fail(1i32) }
    var s = s0
    if s.greeting.code != 220u16 || !same(s.greeting.text, "mx.example ESMTP") { ret fail(2i32) }
    if smtp.ehlo(&s) != ok { ret fail(3i32) }
    if !s.caps.starttls || !s.caps.eight_bit || !s.caps.enhanced || !s.caps.auth_plain || !s.caps.auth_login || s.caps.auth_xoauth2 || s.caps.pipelining || s.caps.size != 1000u64 { ret fail(4i32) }
    if smtp.auth(&s, "alice", "secret") != ok { ret fail(5i32) }
    let body = "Subject: hi\n\n.dot\r\nbare\rcr\nlast"
    let rcpts = [2]str{ "b@x.test", "c@x.test" }
    var body_state = io.SliceReader { data: body, off: 0usize }
    let (sent, send_error) = smtp.send(&s, "a@x.test", rcpts[0..], io.slice_reader(&body_state), u64(body.len))
    if send_error != ok || sent.accepted != 1usize || sent.rejected.len != 1usize || !same(sent.rejected[0].address, "c@x.test") || sent.rejected[0].code != 550u16 { ret fail(6i32) }
    if sent.reply.code != 250u16 || !same(smtp.enhanced(sent.reply), "2.0.0") { ret fail(7i32) }
    if smtp.quit(&s) != ok { ret fail(8i32) }
    let want = "EHLO client.test\r\nAUTH PLAIN AGFsaWNlAHNlY3JldA==\r\nMAIL FROM:<a@x.test> SIZE=31\r\nRCPT TO:<b@x.test>\r\nRCPT TO:<c@x.test>\r\nDATA\r\nSubject: hi\r\n\r\n..dot\r\nbare\r\ncr\r\nlast\r\n.\r\nQUIT\r\n"
    if !same(scene.sent[..scene.writer.off], want) { ret fail(9i32) }

    // ---- HELO fallback, LOGIN, a rejected recipient list, and the refusals that never touch the wire ----
    var two: Scene = zero
    two.writer = io.SliceWriter { data: two.sent[0..], off: 0usize }
    let replies2 = "220 old.example\r\n502 5.5.1 EHLO not implemented\r\n250 old.example\r\n"
    two.reader = io.SliceReader { data: replies2, off: 0usize }
    let (t0, t_error) = smtp.connect(a, io.slice_reader(&two.reader), io.slice_writer(&two.writer), "client.test")
    if t_error != ok { ret fail(10i32) }
    var t = t0
    if smtp.ehlo(&t) != ok || t.caps.starttls || t.caps.auth_plain || t.caps.size != 0u64 { ret fail(11i32) }
    if !same(two.sent[..two.writer.off], "EHLO client.test\r\nHELO client.test\r\n") { ret fail(12i32) }
    if smtp.auth(&t, "u", "p") != smtp.Unsupported || smtp.starttls(&t, zero) != smtp.Unsupported { ret fail(13i32) }
    let before = two.writer.off
    let evil = [1]str{ "x@y.test>\r\nRSET" }
    var empty_body = io.SliceReader { data: "", off: 0usize }
    let (_, evil_error) = smtp.send(&t, "a@x.test", evil[0..], io.slice_reader(&empty_body), 0u64)
    let (_, sender_error) = smtp.send(&t, "a b@x.test", rcpts[0..], io.slice_reader(&empty_body), 0u64)
    let (_, none_error) = smtp.send(&t, "a@x.test", rcpts[..0], io.slice_reader(&empty_body), 0u64)
    if evil_error != smtp.Invalid || sender_error != smtp.Invalid || none_error != smtp.Invalid || two.writer.off != before { ret fail(14i32) }

    var three: Scene = zero
    three.writer = io.SliceWriter { data: three.sent[0..], off: 0usize }
    let replies3 = "220 x\r\n250-x\r\n250-SIZE 10\r\n250 AUTH LOGIN XOAUTH2\r\n334 VXNlcm5hbWU6\r\n334 UGFzc3dvcmQ6\r\n235 ok\r\n334 eyJzdGF0dXMiOiI0MDEifQ==\r\n535 5.7.8 bad\r\n"
    three.reader = io.SliceReader { data: replies3, off: 0usize }
    let (u0, u_error) = smtp.connect(a, io.slice_reader(&three.reader), io.slice_writer(&three.writer), "client.test")
    if u_error != ok { ret fail(15i32) }
    var u = u0
    if smtp.ehlo(&u) != ok || !u.caps.auth_login || u.caps.auth_plain || !u.caps.auth_xoauth2 || u.caps.size != 10u64 { ret fail(16i32) }
    if smtp.auth(&u, "alice", "secret") != ok { ret fail(17i32) }
    if smtp.auth_xoauth2(&u, "a@x.test", "tok") != smtp.Rejected || u.last.code != 535u16 { ret fail(18i32) }
    var long_body = io.SliceReader { data: "twelve bytes", off: 0usize }
    let before_size = three.writer.off
    let (_, size_error) = smtp.send(&u, "a@x.test", rcpts[..1], io.slice_reader(&long_body), 12u64)
    if size_error != smtp.TooLarge || three.writer.off != before_size { ret fail(19i32) }
    let want3 = "EHLO client.test\r\nAUTH LOGIN\r\nYWxpY2U=\r\nc2VjcmV0\r\nAUTH XOAUTH2 dXNlcj1hQHgudGVzdAFhdXRoPUJlYXJlciB0b2sBAQ==\r\n\r\n"
    if !same(three.sent[..before_size], want3) { ret fail(20i32) }

    // ---- reply parsing: server refusals, 4xx versus 5xx, malformed and inconsistent lines ----
    var four: Scene = zero
    four.writer = io.SliceWriter { data: four.sent[0..], off: 0usize }
    four.reader = io.SliceReader { data: "421 4.3.2 shutting down\r\n", off: 0usize }
    let (_, closing_error) = smtp.connect(a, io.slice_reader(&four.reader), io.slice_writer(&four.writer), "client.test")
    if closing_error != smtp.Rejected { ret fail(21i32) }
    var five: Scene = zero
    five.writer = io.SliceWriter { data: five.sent[0..], off: 0usize }
    five.reader = io.SliceReader { data: "220 a\r\n250-one\r\n251 two\r\n", off: 0usize }
    let (v0, v_error) = smtp.connect(a, io.slice_reader(&five.reader), io.slice_writer(&five.writer), "client.test")
    var v = v0
    if v_error != ok || smtp.ehlo(&v) != smtp.Protocol { ret fail(22i32) }
    var six: Scene = zero
    six.writer = io.SliceWriter { data: six.sent[0..], off: 0usize }
    six.reader = io.SliceReader { data: "220 a\r\nhello\r\n", off: 0usize }
    let (w0, w_error) = smtp.connect(a, io.slice_reader(&six.reader), io.slice_writer(&six.writer), "client.test")
    var w = w0
    if w_error != ok || smtp.ehlo(&w) != smtp.Protocol { ret fail(23i32) }
    var seven: Scene = zero
    seven.writer = io.SliceWriter { data: seven.sent[0..], off: 0usize }
    seven.reader = io.SliceReader { data: "220 a\r\n450 4.2.1 mailbox busy\r\n", off: 0usize }
    let (x0, x_error) = smtp.connect(a, io.slice_reader(&seven.reader), io.slice_writer(&seven.writer), "client.test")
    var x = x0
    if x_error != ok || smtp.ehlo(&x) != smtp.Rejected || !smtp.transient(x.last) || !same(smtp.enhanced(x.last), "4.2.1") { ret fail(24i32) }
    var eight: Scene = zero
    eight.writer = io.SliceWriter { data: eight.sent[0..], off: 0usize }
    eight.reader = io.SliceReader { data: "220 a\r\n250 only-line\r\n", off: 0usize }
    let (y0, y_error) = smtp.connect(a, io.slice_reader(&eight.reader), io.slice_writer(&eight.writer), "client.test")
    var y = y0
    if y_error != ok || smtp.ehlo(&y) != ok || y.last.lines != 1usize || y.caps.starttls { ret fail(25i32) }
    var nine: Scene = zero
    nine.writer = io.SliceWriter { data: nine.sent[0..], off: 0usize }
    nine.reader = io.SliceReader { data: "220 a\r\n", off: 0usize }
    let (z0, z_error) = smtp.connect(a, io.slice_reader(&nine.reader), io.slice_writer(&nine.writer), "client.test")
    var z = z0
    if z_error != ok || smtp.ehlo(&z) != smtp.Closed { ret fail(26i32) }

    // ---- dot-stuffing and line ends, chunk by chunk (the state crosses chunk edges) ----
    var st = smtp.Stuffer { line_start: true, after_cr: false, wrote: 0usize }
    var out: [64]u8 = zero
    var all: [128]u8 = zero
    var made = 0usize
    let pieces = [5]str{ ".a\r", "\n.", ".b\r", ".c\n", "\r" }
    var p = 0usize
    while p < 5usize {
        let n = smtp.stuff(&st, out[0..], pieces[p])
        mem.copy[u8](all[made..], out[..n])
        made += n
        p += 1usize
    }
    if !same(all[..made], "..a\r\n...b\r\n..c\r\n\r") { ret fail(27i32) }

    // ---- STARTTLS against a live server thread ----
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
    let none_protocols: [0]str = zero
    var server_read: os.File = zero
    var client_write: os.File = zero
    let (sr, cw, c2s_error) = os.pipe()
    if c2s_error != ok { os.exit(27i32) }
    server_read = sr
    client_write = cw
    var client_read: os.File = zero
    var server_write: os.File = zero
    let (cr, sw, s2c_error) = os.pipe()
    if s2c_error != ok { os.exit(28i32) }
    client_read = cr
    server_write = sw
    let live_code = run_live(a, &server_read, &server_write, &client_read, &client_write, leaf_der, leaf_pkcs8, mid_der, server_entropy[0..], client_entropy[0..])
    if live_code != 0i32 { os.exit(live_code) }
    let _ = os.close(server_read)
    let _ = os.close(client_write)
    let _ = os.close(client_read)
    let _ = os.close(server_write)
    try io.print("net smtp ok\n")
    ret ok
}
