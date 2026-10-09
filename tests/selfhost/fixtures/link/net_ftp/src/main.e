// e.net.ftp (L084, D2277): the PASV and EPSV reply parsers, a scripted control channel compared byte for byte,
// and three live sessions against a server thread on loopback TCP with real data connections: plain FTP with
// EPSV, plain FTP where EPSV is refused and PASV is used, and FTPS (AUTH TLS, PBSZ, PROT P, TLS data). Each
// lists, downloads (into memory, streamed, over a size limit, a missing file), uploads 3000 bytes, renames,
// asks size, mdtm and feat, and quits; the server records every control line it received.
use e.io
use e.mem
use e.net
use e.net.ftp as ftp
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
    let _ = io.print("net ftp failed at ")
    var digits: [4]u8 = zero
    digits[0] = u8(48i32 + code / 100i32)
    digits[1] = u8(48i32 + (code / 10i32) % 10i32)
    digits[2] = u8(48i32 + code % 10i32)
    let _ = io.print(digits[..3])
    let _ = io.print("\n")
    os.exit(code)
    ret ok
}

fn pattern(i: usize) -> u8 { ret u8((i * 7usize + 3usize) % 251usize) }

type Scene = struct { sent: [4096]u8, writer: io.SliceWriter, reader: io.SliceReader }

type Job = struct {
    listener: net.Socket, config: tls.ServerConfig, secure: bool, no_epsv: bool, failure: i32, counter: u8,
    log: [4096]u8, log_len: usize, uploaded: [4096]u8, uploaded_len: usize,
}

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

fn log_line(job: *Job, line: []const u8) {
    if job.log_len + line.len + 1usize <= job.log.len {
        mem.copy[u8](job.log[job.log_len..], line)
        job.log[job.log_len + line.len] = 10u8
        job.log_len += line.len + 1usize
    }
}

fn starts(line: []const u8, prefix: str) -> bool {
    if line.len < prefix.len { ret false }
    ret same(line[..prefix.len], prefix)
}

// The data connection: accept, optionally wrap in TLS, then send a listing or a file, or take an upload.
fn serve_data(job: *Job, arena: *mem.Arena, listener: *net.Socket, protected: bool, kind: u8, arg: []const u8) -> i32 {
    let (accepted, peer, accept_error) = net.tcp_accept(*listener)
    if accept_error != ok { ret 140i32 }
    var connection = accepted
    defer let _ = net.close(connection)
    var source = net.reader(&connection)
    var sink = net.writer(&connection)
    var secure: tls.Stream = zero
    if protected {
        var entropy: [64]u8 = zero
        var e = 0usize
        job.counter += 1u8
        while e < 64usize {
            entropy[e] = u8((e * 5usize + usize(job.counter) * 31usize + 9usize) % 256usize)
            e += 1usize
        }
        var config = job.config
        config.entropy = entropy[0..]
        let (made, make_error) = tls.server(arena, source, sink, config)
        if make_error != ok { ret 141i32 }
        secure = made
        if tls.handshake(&secure) != ok { ret 142i32 }
        source = tls.reader(&secure)
        sink = tls.writer(&secure)
    }
    var code = 0i32
    if kind == 0u8 {
        if io.write_all(&sink, "-rw-r--r-- 1 u g 12 Jan 1 a.txt\r\n") != ok { code = 143i32 }
    } else if kind == 1u8 {
        if same(arg, "big") {
            var block: [1000]u8 = zero
            var b = 0usize
            while b < 10usize && code == 0i32 {
                var j = 0usize
                while j < 1000usize {
                    block[j] = pattern(b * 1000usize + j)
                    j += 1usize
                }
                if io.write_all(&sink, block[0..]) != ok { b = 10usize }
                b += 1usize
            }
        } else {
            if io.write_all(&sink, "hello, world") != ok { code = 145i32 }
        }
    } else {
        var chunk: [512]u8 = zero
        while true {
            let (got, read_error) = io.read(&source, chunk[0..])
            if read_error == io.End { break }
            if read_error != ok {
                code = 146i32
                break
            }
            if job.uploaded_len + got <= job.uploaded.len {
                mem.copy[u8](job.uploaded[job.uploaded_len..], chunk[..got])
                job.uploaded_len += got
            }
        }
    }
    if protected { let _ = tls.close(&secure) }
    ret code
}

// EPSV or PASV: open a listener, answer with its port, then handle the one transfer command that follows.
fn data_command(job: *Job, arena: *mem.Arena, source: *io.Reader, sink: *io.Writer, passive_verb: []const u8, protected: bool) -> i32 {
    if same(passive_verb, "EPSV") && job.no_epsv {
        if io.write_all(sink, "502 EPSV not implemented\r\n") != ok { ret 150i32 }
        ret 0i32
    }
    let (loopback, ip_error) = net.parse_ip("127.0.0.1")
    if ip_error != ok { ret 151i32 }
    let (listener0, listen_error) = net.tcp_listen(net.Endpoint { address: loopback, port: 0u16 }, 1u32)
    if listen_error != ok { ret 152i32 }
    var listener = listener0
    defer let _ = net.close(listener)
    let (bound, bound_error) = os.socket_local_address(listener)
    if bound_error != ok { ret 153i32 }
    var reply: [96]u8 = zero
    var r = 0usize
    if same(passive_verb, "EPSV") {
        let head = "229 Entering Extended Passive Mode (|||"
        mem.copy[u8](reply[0..], head)
        r = head.len
        r += put_port(reply[r..], bound.port)
        reply[r] = 124u8
        reply[r + 1usize] = 41u8
        reply[r + 2usize] = 13u8
        reply[r + 3usize] = 10u8
        r += 4usize
    } else {
        let head = "227 Entering Passive Mode (127,0,0,1,"
        mem.copy[u8](reply[0..], head)
        r = head.len
        r += put_port(reply[r..], bound.port / 256u16)
        reply[r] = 44u8
        r += 1usize
        r += put_port(reply[r..], bound.port % 256u16)
        reply[r] = 41u8
        reply[r + 1usize] = 13u8
        reply[r + 2usize] = 10u8
        r += 3usize
    }
    if io.write_all(sink, reply[..r]) != ok { ret 154i32 }
    var line: [256]u8 = zero
    let (n, line_error) = line_from(source, line[0..])
    if line_error != ok { ret 155i32 }
    log_line(job, line[..n])
    var kind = 2u8
    var arg_start = 0usize
    if starts(line[..n], "LIST ") || starts(line[..n], "NLST ") {
        kind = 0u8
        arg_start = 5usize
    } else if starts(line[..n], "RETR ") {
        kind = 1u8
        arg_start = 5usize
    } else if starts(line[..n], "STOR ") {
        arg_start = 5usize
    } else {
        ret 156i32
    }
    var arg_end = n
    if arg_end > arg_start && line[arg_end - 1usize] == 13u8 { arg_end -= 1usize }
    let arg = line[arg_start..arg_end]
    if kind == 1u8 && same(arg, "missing") {
        if io.write_all(sink, "550 No such file\r\n") != ok { ret 157i32 }
        ret 0i32
    }
    if io.write_all(sink, "150 Opening data connection\r\n") != ok { ret 158i32 }
    let code = serve_data(job, arena, &listener, protected, kind, arg)
    if code != 0i32 { ret code }
    if io.write_all(sink, "226 Transfer complete\r\n") != ok { ret 159i32 }
    ret 0i32
}

fn put_port(out: []u8, value: u16) -> usize {
    var digits: [5]u8 = zero
    var count = 0usize
    var rest = value
    if rest == 0u16 {
        digits[0] = 48u8
        count = 1usize
    }
    while rest > 0u16 {
        digits[count] = u8(rest % 10u16) + 48u8
        rest = rest / 10u16
        count += 1usize
    }
    var i = 0usize
    while i < count {
        out[i] = digits[count - 1usize - i]
        i += 1usize
    }
    ret count
}

fn serve(job: *Job) {
    var storage: [1048576]u8 = zero
    var arena = mem.arena_from(storage[0..])
    let (accepted, peer, accept_error) = net.tcp_accept(job.listener)
    if accept_error != ok {
        job.failure = 101i32
        ret
    }
    var connection = accepted
    defer let _ = net.close(connection)
    var source = net.reader(&connection)
    var sink = net.writer(&connection)
    var secure: tls.Stream = zero
    var protected = false
    var line: [256]u8 = zero
    if io.write_all(&sink, "220-Welcome\r\n220 neper test ftpd ready\r\n") != ok {
        job.failure = 102i32
        ret
    }
    while true {
        let (n, line_error) = line_from(&source, line[0..])
        if line_error != ok { break }
        log_line(job, line[..n])
        let text = line[..n]
        var reply = ""
        var quit = false
        if starts(text, "AUTH TLS") {
            if !job.secure {
                reply = "504 no TLS\r\n"
            } else {
                if io.write_all(&sink, "234 Proceed with negotiation\r\n") != ok {
                    job.failure = 104i32
                    ret
                }
                let (made, make_error) = tls.server(&arena, source, sink, job.config)
                if make_error != ok {
                    job.failure = 105i32
                    ret
                }
                secure = made
                if tls.handshake(&secure) != ok {
                    job.failure = 106i32
                    ret
                }
                source = tls.reader(&secure)
                sink = tls.writer(&secure)
                continue
            }
        } else if starts(text, "PBSZ") {
            reply = "200 PBSZ=0\r\n"
        } else if starts(text, "PROT P") {
            protected = true
            reply = "200 Protection level set to Private\r\n"
        } else if starts(text, "USER") {
            reply = "331 Password required\r\n"
        } else if starts(text, "PASS") {
            reply = "230 Logged in\r\n"
        } else if starts(text, "TYPE") {
            reply = "200 Type set\r\n"
        } else if starts(text, "PWD") {
            reply = "257 \"/home/a \"\"q\"\" b\" is the current directory\r\n"
        } else if starts(text, "CWD") {
            reply = "250 Directory changed\r\n"
        } else if starts(text, "SIZE") {
            reply = "213 12\r\n"
        } else if starts(text, "MDTM") {
            reply = "213 20260102030405\r\n"
        } else if starts(text, "FEAT") {
            reply = "211-Features:\r\n EPSV\r\n SIZE\r\n MDTM\r\n211 End\r\n"
        } else if starts(text, "RNFR") {
            reply = "350 Ready for RNTO\r\n"
        } else if starts(text, "RNTO") {
            reply = "250 Renamed\r\n"
        } else if starts(text, "NOOP") {
            reply = "200 OK\r\n"
        } else if starts(text, "EPSV") || starts(text, "PASV") {
            let code = data_command(job, &arena, &source, &sink, text[..4], protected)
            if code != 0i32 {
                job.failure = code
                ret
            }
            continue
        } else if starts(text, "QUIT") {
            reply = "221 Goodbye\r\n"
            quit = true
        } else {
            reply = "500 Unknown command\r\n"
        }
        if io.write_all(&sink, reply) != ok {
            job.failure = 107i32
            ret
        }
        if quit { break }
    }
    if protected { let _ = tls.close(&secure) }
}

// One client run against the server on `port`; 0 when every check holds.
fn client_run(a: *mem.Arena, port: u16, secure: bool, config: tls.ClientConfig) -> i32 {
    let (loopback, ip_error) = net.parse_ip("127.0.0.1")
    if ip_error != ok { ret 40i32 }
    let (opened, connect_error) = net.tcp_connect(net.Endpoint { address: loopback, port: port })
    if connect_error != ok { ret 41i32 }
    var connection = opened
    defer let _ = net.close(connection)
    let (c0, c_error) = ftp.connect(a, net.reader(&connection), net.writer(&connection), loopback)
    if c_error != ok { ret 42i32 }
    var c = c0
    if c.greeting.code != 220u16 || c.greeting.lines != 2usize || !same(c.greeting.text, "Welcome\nneper test ftpd ready") { ret 43i32 }
    if secure {
        if ftp.auth_tls(&c, config) != ok || !c.secured || !c.protected { ret 44i32 }
    }
    if ftp.login(&c, "alice", "secret") != ok { ret 45i32 }
    if ftp.binary(&c) != ok { ret 46i32 }
    let (dir, pwd_error) = ftp.pwd(&c)
    if pwd_error != ok || !same(dir, "/home/a \"q\" b") { ret 47i32 }
    if ftp.cwd(&c, "pub") != ok { ret 48i32 }
    let (bytes, size_error) = ftp.size(&c, "a.txt")
    if size_error != ok || bytes != 12u64 { ret 49i32 }
    let (stamp, mdtm_error) = ftp.mdtm(&c, "a.txt")
    if mdtm_error != ok || !same(stamp, "20260102030405") { ret 50i32 }
    let (features, feat_error) = ftp.feat(&c)
    if feat_error != ok || !same(features, " EPSV\n SIZE\n MDTM\nEnd") { ret 51i32 }
    let (listing, list_error) = ftp.list(&c, "/", false, 4096usize)
    if list_error != ok || !same(listing, "-rw-r--r-- 1 u g 12 Jan 1 a.txt\r\n") { ret 52i32 }
    let (file, retr_error) = ftp.retrieve(&c, "a.txt", 4096usize)
    if retr_error != ok || !same(file, "hello, world") { ret 53i32 }
    let (big, big_error) = ftp.retrieve(&c, "big", 20000usize)
    if big_error != ok || big.len != 10000usize { ret 54i32 }
    var i = 0usize
    while i < big.len {
        if big[i] != pattern(i) { ret 55i32 }
        i += 1usize
    }
    if ftp.noop(&c) != ok { ret 57i32 }
    let (_, missing_error) = ftp.retrieve(&c, "missing", 4096usize)
    if missing_error != ftp.Rejected || c.last.code != 550u16 { ret 58i32 }
    var upload: [3000]u8 = zero
    var u = 0usize
    while u < upload.len {
        upload[u] = pattern(u)
        u += 1usize
    }
    var upload_state = io.SliceReader { data: upload[0..], off: 0usize }
    if ftp.store(&c, "up.bin", io.slice_reader(&upload_state)) != ok { ret 59i32 }
    if ftp.rename(&c, "up.bin", "final.bin") != ok { ret 60i32 }
    let (_, limited_error) = ftp.retrieve(&c, "big", 5000usize)
    if limited_error != ftp.TooLarge { ret 56i32 }
    if ftp.noop(&c) != ftp.Closed { ret 61i32 }
    ret 0i32
}

fn live(a: *mem.Arena, secure: bool, no_epsv: bool, leaf_der: str, leaf_pkcs8: str, mid_der: str, seed: usize) -> i32 {
    let (loopback, ip_error) = net.parse_ip("127.0.0.1")
    if ip_error != ok { ret 20i32 }
    let (listener, listen_error) = net.tcp_listen(net.Endpoint { address: loopback, port: 0u16 }, 1u32)
    if listen_error != ok { ret 21i32 }
    var server_entropy: [64]u8 = zero
    var client_entropy: [64]u8 = zero
    var e = 0usize
    while e < 64usize {
        server_entropy[e] = u8((e * 3usize + seed) % 256usize)
        client_entropy[e] = u8((e * 7usize + seed + 5usize) % 256usize)
        e += 1usize
    }
    let none_protocols: [0]str = zero
    var job: Job = zero
    job.listener = listener
    job.secure = secure
    job.no_epsv = no_epsv
    job.config = tls.ServerConfig { certificate_chain: leaf_der, private_key: leaf_pkcs8, alpn: none_protocols[0..], entropy: server_entropy[0..] }
    let (bound, bound_error) = os.socket_local_address(job.listener)
    if bound_error != ok { os.exit(22i32) }
    let (server_thread, thread_error) = thread.spawn[Job](serve, &job, 8388608usize)
    if thread_error != ok { os.exit(23i32) }
    let config = tls.ClientConfig { server_name: "example.com", trust_roots: mid_der, alpn: none_protocols[0..], entropy: client_entropy[0..], now: time.Timestamp { nanos: 1780272000000000000i64 } }
    let code = client_run(a, bound.port, secure, config)
    if code != 0i32 { os.exit(code) }
    let join_error = thread.join(server_thread)
    if join_error != ok { os.exit(24i32) }
    if job.failure != 0i32 { os.exit(job.failure) }
    if net.close(job.listener) != ok { os.exit(25i32) }
    let seen = job.log[..job.log_len]
    var expect_buf: [1024]u8 = zero
    var x = 0usize
    var passive = "EPSV\r\n"
    if no_epsv { passive = "EPSV\r\nPASV\r\n" }
    let pieces = [16]str{ "USER alice\r\nPASS secret\r\nTYPE I\r\nPWD\r\nCWD pub\r\nSIZE a.txt\r\nMDTM a.txt\r\nFEAT\r\n", "*LIST /\r\n", "*RETR a.txt\r\n", "*RETR big\r\n", "NOOP\r\n", "*RETR missing\r\n", "*STOR up.bin\r\n", "RNFR up.bin\r\nRNTO final.bin\r\n", "*RETR big\r\n", "", "", "", "", "", "", "" }
    if secure {
        let head = "AUTH TLS\r\nPBSZ 0\r\nPROT P\r\n"
        mem.copy[u8](expect_buf[x..], head)
        x += head.len
    }
    var step = 0usize
    while step < 9usize {
        var piece = pieces[step]
        if piece.len > 0usize && piece[0] == 42u8 {
            mem.copy[u8](expect_buf[x..], passive)
            x += passive.len
            piece = piece[1usize..]
        }
        mem.copy[u8](expect_buf[x..], piece)
        x += piece.len
        step += 1usize
    }
    if !same(seen, expect_buf[..x]) { os.exit(27i32) }
    if job.uploaded_len != 3000usize { os.exit(28i32) }
    var k = 0usize
    while k < 3000usize {
        if job.uploaded[k] != pattern(k) { os.exit(29i32) }
        k += 1usize
    }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    // ---- reply parsers ----
    let (p1, p1_ok) = ftp.parse_pasv("Entering Passive Mode (192,168,0,1,19,137).")
    if !p1_ok || p1 != 5001u16 { ret fail(1i32) }
    let (p2, p2_ok) = ftp.parse_pasv("=10,0,0,5,0,21")
    if !p2_ok || p2 != 21u16 { ret fail(2i32) }
    let (_, p3_ok) = ftp.parse_pasv("Entering Passive Mode (1,2,3,4,5)")
    let (_, p4_ok) = ftp.parse_pasv("Entering Passive Mode (1,2,3,4,5,300)")
    if p3_ok || p4_ok { ret fail(3i32) }
    let (e1, e1_ok) = ftp.parse_epsv("Entering Extended Passive Mode (|||6446|)")
    if !e1_ok || e1 != 6446u16 { ret fail(4i32) }
    let (e2, e2_ok) = ftp.parse_epsv("Extended Passive (!!!2121!)")
    if !e2_ok || e2 != 2121u16 { ret fail(5i32) }
    let (_, e3_ok) = ftp.parse_epsv("(|||0|)")
    let (_, e4_ok) = ftp.parse_epsv("(|1|2|3|)")
    let (_, e5_ok) = ftp.parse_epsv("(|||70000|)")
    let (_, e6_ok) = ftp.parse_epsv("no parens")
    if e3_ok || e4_ok || e5_ok || e6_ok { ret fail(6i32) }

    // ---- a scripted control channel ----
    var scene: Scene = zero
    scene.writer = io.SliceWriter { data: scene.sent[0..], off: 0usize }
    scene.reader = io.SliceReader { data: "120 wait\r\n220 hello\r\n331 pw\r\n530 Login incorrect\r\n230 ok\r\n250-multi\r\nsecond line\r\n250 done\r\n257 \"/a\"\r\n213 99\r\n550 nope\r\n421 closing\r\n", off: 0usize }
    let (loopback, loopback_error) = net.parse_ip("127.0.0.1")
    if loopback_error != ok { ret fail(7i32) }
    let (s0, connect_error) = ftp.connect(a, io.slice_reader(&scene.reader), io.slice_writer(&scene.writer), loopback)
    if connect_error != ok { ret fail(8i32) }
    var s = s0
    if !same(s.greeting.text, "hello") { ret fail(9i32) }
    if ftp.login(&s, "u", "bad") != ftp.Rejected || s.last.code != 530u16 || ftp.transient(s.last) { ret fail(10i32) }
    if ftp.login(&s, "u", "") != ok { ret fail(11i32) }
    if ftp.cwd(&s, "x") != ok || s.last.lines != 3usize || !same(s.last.text, "multi\nsecond line\ndone") { ret fail(12i32) }
    let (dir, dir_error) = ftp.pwd(&s)
    if dir_error != ok || !same(dir, "/a") { ret fail(13i32) }
    let (n, size_error) = ftp.size(&s, "f")
    if size_error != ok || n != 99u64 { ret fail(14i32) }
    if ftp.dele(&s, "g") != ftp.Rejected || s.last.code != 550u16 { ret fail(15i32) }
    if ftp.noop(&s) != ftp.Rejected || !ftp.transient(s.last) { ret fail(16i32) }
    let wrote = scene.writer.off
    var upload_none = io.SliceReader { data: "", off: 0usize }
    if ftp.cwd(&s, "a\r\nDELE b") != ftp.Invalid || ftp.mkd(&s, "x\x00y") != ftp.Invalid || ftp.store(&s, "", io.slice_reader(&upload_none)) != ftp.Invalid { ret fail(17i32) }
    if scene.writer.off != wrote { ret fail(18i32) }
    if !same(scene.sent[..wrote], "USER u\r\nPASS bad\r\nUSER u\r\nCWD x\r\nPWD\r\nSIZE f\r\nDELE g\r\nNOOP\r\n") { ret fail(19i32) }

    // ---- live sessions ----
    let mid_der = "0\x82\x01\x130\x81\xc6\xa0\x03\x02\x01\x02\x02\x01\x020\x05\x06\x03+ep0%1\x130\x11\x06\x03U\x04\x03\x0c\x0aNeper Root1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0*0\x05\x06\x03+ep\x03!\x00\x819w\x0e\xa8}\x17_V\xa3Tf\xc3L~\xcc\xcb\x8d\x8a\x91\xb4\xee7\xa2]\xf6\x0f[\x8f\xc9\xb3\x94\xa3\x130\x110\x0f\x06\x03U\x1d\x13\x01\x01\xff\x04\x050\x03\x01\x01\xff0\x05\x06\x03+ep\x03A\x00R^\x187\xb39[\xa4N\xc4\x83\x10\xde\xfc\x7f\xa0\xbfF[\xa8^\x04S\xa1\xb2\xf8\xbcM\xc7\xfb\xf1t\x89\xa0\x0e\x07\xcc\xbf\x8f6R\x16\x15\xab\x99\x0e\xdd\xc1,\x8d\x8f*\xd4\xaf\x97\xaae\x8b\xab\xe5\x0d\x8e'\x08"
    let leaf_der = "0\x82\x01=0\x81\xf0\xa0\x03\x02\x01\x02\x02\x01\x030\x05\x06\x03+ep0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x161\x140\x12\x06\x03U\x04\x03\x0c\x0bexample.com0*0\x05\x06\x03+ep\x03!\x00\xedI(\xc6(\xd1\xc2\xc6\xea\xe9\x038\x90Y\x95a)Y':\\c\xf966\xc1F\x14\xac\x877\xd1\xa3L0J0\x0c\x06\x03U\x1d\x13\x01\x01\xff\x04\x020\x000%\x06\x03U\x1d\x11\x04\x1e0\x1c\x82\x0bexample.com\x82\x0d*.example.org0\x13\x06\x03U\x1d%\x04\x0c0\x0a\x06\x08+\x06\x01\x05\x05\x07\x03\x010\x05\x06\x03+ep\x03A\x00\x84Pf\xea\x11\xb7\xdb-w\xdf\xd2\xa8\xden\xd3\xbey|r`B'h\xfc\x22\x08\xca\x8e%u\xa8\xa7)\xd3\xb3\x15Tc\xc8\x10\xa0\x97\x84C\xaaU4\xf0>\x00\x0f\xfau\xe7\xaa\xb9\xae\x9e\x9br\xe8Bv\x09"
    let leaf_pkcs8 = "0.\x02\x01\x000\x05\x06\x03+ep\x04\x22\x04\x20\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03"
    let plain_code = live(a, false, false, leaf_der, leaf_pkcs8, mid_der, 1usize)
    if plain_code != 0i32 { ret fail(100i32 + plain_code) }
    let pasv_code = live(a, false, true, leaf_der, leaf_pkcs8, mid_der, 11usize)
    if pasv_code != 0i32 { ret fail(200i32 + pasv_code) }
    let tls_code = live(a, true, false, leaf_der, leaf_pkcs8, mid_der, 21usize)
    if tls_code != 0i32 { ret fail(300i32 + tls_code) }
    try io.print("net ftp ok\n")
    ret ok
}
