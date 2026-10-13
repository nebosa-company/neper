// e.net.ssh against a real SSH server (asyncssh, started by drive.py): the version exchange, curve25519-sha256 with
// an ssh-ed25519 host key, chacha20-poly1305@openssh.com, password and public-key authentication, a pty and a shell
// that upper-cases a line and exits with status 7, a wrong password refused, a wrong host key refused.
// (C155) Two more channel kinds on the same transport, each a session of its own: the `sftp` subsystem (no pty; the
// SFTP packets of e.net.sftp ride the channel: version, realpath, a directory listing, a file read, a file written,
// stat) and a `direct-tcpip` forward to a TCP echo server on the SSH server's side (drive.py), a refused forward
// reported as a channel failure.
// Arguments: mode (password, key, badpass, badhost, gcm256, gcm128, rekey, sftp, forward, forward_refused), port, the
// host key as 64 hex digits, and for the forward modes the target port.
// Every stage has its own exit code.
use e.io
use e.mem
use e.net
use e.os
use e.str
use e.net.ssh as ssh
use e.net.sftp as sftp

fn hex_value(c: u8) -> u8 {
    if c >= 48u8 && c <= 57u8 { ret c - 48u8 }
    ret c - 87u8
}

fn parse_port(text: str) -> u16 {
    var v = 0u32
    var i = 0usize
    while i < text.len {
        v = v * 10u32 + u32(text[i] - 48u8)
        i += 1usize
    }
    ret u16(v)
}

// Send what the session has queued and take one read of the socket's bytes into it; false when the connection
// is gone.
fn pump(sock: net.Socket, s: *ssh.Session) -> bool {
    var more = true
    while more {
        let out = ssh.outgoing(s)
        if out.len == 0usize {
            more = false
        } else {
            let (n, send_error) = net.send(sock, out)
            if send_error != ok || n == 0usize { ret false }
            ssh.sent(s, n)
        }
    }
    if ssh.status(s) == ssh.FAILED { ret true }
    var buf: [4096]u8 = zero
    let (got, receive_error) = net.receive(sock, buf[0usize..4096usize])
    if receive_error != ok || got == 0usize { ret false }
    let fed = ssh.feed(s, buf[0usize..got])
    ret true
}

fn contains(hay: []const u8, needle: str) -> bool {
    if needle.len > hay.len { ret false }
    var i = 0usize
    while i + needle.len <= hay.len {
        var j = 0usize
        while j < needle.len && hay[i + j] == needle[j] { j += 1usize }
        if j == needle.len { ret true }
        i += 1usize
    }
    ret false
}

// (C155) The bytes of the server's SFTP replies not yet decoded, and how many of the front are done with.
type Link = struct { acc: [8192]u8, len: usize, drop: usize }

// An SFTP packet onto the channel (the window may take it in pieces).
fn put_packet(sock: net.Socket, s: *ssh.Session, packet: []const u8) -> bool {
    var at = 0usize
    var spins = 0usize
    while at < packet.len && spins < 200usize {
        let n = ssh.write(s, packet[at..])
        at += n
        spins += 1usize
        if at < packet.len {
            if !pump(sock, s) { ret false }
        }
    }
    ret at == packet.len
}

// The next whole SFTP reply: what the channel holds is taken in, the wire is read when it is not whole yet.
fn next_response(sock: net.Socket, s: *ssh.Session, link: *Link, names: []sftp.Name) -> (sftp.Response, err) {
    var none: sftp.Response = zero
    if link.drop > 0usize {
        var k = link.drop
        while k < link.len {
            link.acc[k - link.drop] = link.acc[k]
            k += 1usize
        }
        link.len -= link.drop
        link.drop = 0usize
    }
    var spins = 0usize
    while spins < 200usize {
        var chunk: [1024]u8 = zero
        let n = ssh.read(s, chunk[0usize..1024usize])
        var k = 0usize
        while k < n && link.len < 8192usize {
            link.acc[link.len] = chunk[k]
            link.len += 1usize
            k += 1usize
        }
        if link.len > 0usize {
            let (used, resp, decode_error) = sftp.decode(link.acc[0usize..link.len], names)
            if decode_error == ok {
                link.drop = used
                ret (resp, ok)
            }
            if decode_error != sftp.Incomplete { ret (none, decode_error) }
        }
        if !pump(sock, s) { ret (none, sftp.Invalid) }
        spins += 1usize
    }
    ret (none, sftp.Incomplete)
}

fn same_bytes(x: []const u8, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// An SFTP session over the open subsystem channel; the exit code of the first stage that is wrong, or 0.
fn sftp_session(sock: net.Socket, s: *ssh.Session) -> i32 {
    var link: Link = zero
    var names: [16]sftp.Name = zero
    var req: [1200]u8 = zero
    let (n0, e0) = sftp.encode_init(req[0usize..1200usize], 3u32)
    if e0 != ok || !put_packet(sock, s, req[0usize..n0]) { ret 20i32 }
    let (r0, re0) = next_response(sock, s, &link, names[0usize..16usize])
    if re0 != ok || r0.kind != sftp.FXP_VERSION || r0.version != 3u32 { ret 21i32 }
    // realpath of "." is the server's root.
    let (n1, e1) = sftp.encode_path(req[0usize..1200usize], sftp.FXP_REALPATH, 1u32, ".")
    if e1 != ok || !put_packet(sock, s, req[0usize..n1]) { ret 22i32 }
    let (r1, re1) = next_response(sock, s, &link, names[0usize..16usize])
    if re1 != ok || r1.kind != sftp.FXP_NAME || r1.id != 1u32 || r1.count != 1usize { ret 23i32 }
    if !same_bytes(names[0].filename, "/") { ret 24i32 }
    // The directory: hello.txt is in it.
    let (n2, e2) = sftp.encode_path(req[0usize..1200usize], sftp.FXP_OPENDIR, 2u32, "/")
    if e2 != ok || !put_packet(sock, s, req[0usize..n2]) { ret 25i32 }
    let (r2, re2) = next_response(sock, s, &link, names[0usize..16usize])
    if re2 != ok || r2.kind != sftp.FXP_HANDLE { ret 26i32 }
    var dir_handle: [64]u8 = zero
    var dir_len = r2.handle.len
    if dir_len > 64usize { ret 27i32 }
    var h = 0usize
    while h < dir_len {
        dir_handle[h] = r2.handle[h]
        h += 1usize
    }
    let (n3, e3) = sftp.encode_handle(req[0usize..1200usize], sftp.FXP_READDIR, 3u32, dir_handle[0usize..dir_len])
    if e3 != ok || !put_packet(sock, s, req[0usize..n3]) { ret 28i32 }
    let (r3, re3) = next_response(sock, s, &link, names[0usize..16usize])
    if re3 != ok || r3.kind != sftp.FXP_NAME || r3.count < 1usize { ret 29i32 }
    var found_hello = false
    var f = 0usize
    while f < r3.count {
        if same_bytes(names[f].filename, "hello.txt") { found_hello = true }
        f += 1usize
    }
    if !found_hello { ret 30i32 }
    let (n4, e4) = sftp.encode_handle(req[0usize..1200usize], sftp.FXP_CLOSE, 4u32, dir_handle[0usize..dir_len])
    if e4 != ok || !put_packet(sock, s, req[0usize..n4]) { ret 31i32 }
    let (r4, re4) = next_response(sock, s, &link, names[0usize..16usize])
    if re4 != ok || r4.kind != sftp.FXP_STATUS || r4.status != sftp.FX_OK { ret 32i32 }
    // A file read: its bytes, then the end of file.
    let (n5, e5) = sftp.encode_open(req[0usize..1200usize], 5u32, "/hello.txt", sftp.OPEN_READ, sftp.no_attrs())
    if e5 != ok || !put_packet(sock, s, req[0usize..n5]) { ret 33i32 }
    let (r5, re5) = next_response(sock, s, &link, names[0usize..16usize])
    if re5 != ok || r5.kind != sftp.FXP_HANDLE { ret 34i32 }
    var file_handle: [64]u8 = zero
    let file_len = r5.handle.len
    if file_len > 64usize { ret 35i32 }
    h = 0usize
    while h < file_len {
        file_handle[h] = r5.handle[h]
        h += 1usize
    }
    let (n6, e6) = sftp.encode_read(req[0usize..1200usize], 6u32, file_handle[0usize..file_len], 0u64, 100u32)
    if e6 != ok || !put_packet(sock, s, req[0usize..n6]) { ret 36i32 }
    let (r6, re6) = next_response(sock, s, &link, names[0usize..16usize])
    if re6 != ok || r6.kind != sftp.FXP_DATA || !same_bytes(r6.data, "hello sftp\n") { ret 37i32 }
    let (n7, e7) = sftp.encode_read(req[0usize..1200usize], 7u32, file_handle[0usize..file_len], 11u64, 100u32)
    if e7 != ok || !put_packet(sock, s, req[0usize..n7]) { ret 38i32 }
    let (r7, re7) = next_response(sock, s, &link, names[0usize..16usize])
    if re7 != ok || r7.kind != sftp.FXP_STATUS || r7.status != sftp.FX_EOF { ret 39i32 }
    let (n8, e8) = sftp.encode_handle(req[0usize..1200usize], sftp.FXP_CLOSE, 8u32, file_handle[0usize..file_len])
    if e8 != ok || !put_packet(sock, s, req[0usize..n8]) { ret 40i32 }
    let (r8, re8) = next_response(sock, s, &link, names[0usize..16usize])
    if re8 != ok || r8.kind != sftp.FXP_STATUS || r8.status != sftp.FX_OK { ret 41i32 }
    // A file written: 200 bytes, 0 to 199, which the server's side checks afterwards.
    let (n9, e9) = sftp.encode_open(req[0usize..1200usize], 9u32, "/up.bin", sftp.OPEN_WRITE | sftp.OPEN_CREAT | sftp.OPEN_TRUNC, sftp.no_attrs())
    if e9 != ok || !put_packet(sock, s, req[0usize..n9]) { ret 42i32 }
    let (r9, re9) = next_response(sock, s, &link, names[0usize..16usize])
    if re9 != ok || r9.kind != sftp.FXP_HANDLE { ret 43i32 }
    var up_handle: [64]u8 = zero
    let up_len = r9.handle.len
    if up_len > 64usize { ret 44i32 }
    h = 0usize
    while h < up_len {
        up_handle[h] = r9.handle[h]
        h += 1usize
    }
    var payload: [200]u8 = zero
    h = 0usize
    while h < 200usize {
        payload[h] = u8(h)
        h += 1usize
    }
    let (n10, e10) = sftp.encode_write(req[0usize..1200usize], 10u32, up_handle[0usize..up_len], 0u64, payload[0usize..200usize])
    if e10 != ok || !put_packet(sock, s, req[0usize..n10]) { ret 45i32 }
    let (r10, re10) = next_response(sock, s, &link, names[0usize..16usize])
    if re10 != ok || r10.kind != sftp.FXP_STATUS || r10.status != sftp.FX_OK { ret 46i32 }
    let (n11, e11) = sftp.encode_handle(req[0usize..1200usize], sftp.FXP_CLOSE, 11u32, up_handle[0usize..up_len])
    if e11 != ok || !put_packet(sock, s, req[0usize..n11]) { ret 47i32 }
    let (r11, re11) = next_response(sock, s, &link, names[0usize..16usize])
    if re11 != ok || r11.kind != sftp.FXP_STATUS || r11.status != sftp.FX_OK { ret 48i32 }
    // The size the server reports for it.
    let (n12, e12) = sftp.encode_path(req[0usize..1200usize], sftp.FXP_STAT, 12u32, "/up.bin")
    if e12 != ok || !put_packet(sock, s, req[0usize..n12]) { ret 49i32 }
    let (r12, re12) = next_response(sock, s, &link, names[0usize..16usize])
    if re12 != ok || r12.kind != sftp.FXP_ATTRS || (r12.attrs.flags & sftp.ATTR_SIZE) == 0u32 || r12.attrs.size != 200u64 { ret 50i32 }
    // A file that is not there is a status, not a failure of the session.
    let (n13, e13) = sftp.encode_open(req[0usize..1200usize], 13u32, "/missing.txt", sftp.OPEN_READ, sftp.no_attrs())
    if e13 != ok || !put_packet(sock, s, req[0usize..n13]) { ret 51i32 }
    let (r13, re13) = next_response(sock, s, &link, names[0usize..16usize])
    if re13 != ok || r13.kind != sftp.FXP_STATUS || r13.status != sftp.FX_NO_SUCH_FILE { ret 52i32 }
    ret 0i32
}

// A forwarded TCP connection: the echo server on the other side answers a line with the line in capitals.
fn forward_session(sock: net.Socket, s: *ssh.Session) -> i32 {
    let taken = ssh.write(s, "ping over the tunnel\n")
    if taken != 21usize { ret 60i32 }
    var got: [128]u8 = zero
    var got_len = 0usize
    var rounds = 0usize
    while rounds < 60usize && !contains(got[0usize..got_len], "PING OVER THE TUNNEL") {
        if !pump(sock, s) { break }
        var chunk: [64]u8 = zero
        let n = ssh.read(s, chunk[0usize..64usize])
        var k = 0usize
        while k < n && got_len < 128usize {
            got[got_len] = chunk[k]
            got_len += 1usize
            k += 1usize
        }
        rounds += 1usize
    }
    if !contains(got[0usize..got_len], "PING OVER THE TUNNEL") { ret 61i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 4usize { os.exit(90i32) }
    let mode = args[1]
    let port = parse_port(args[2])
    let hex = args[3]
    var expected: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        expected[i] = hex_value(hex[2usize * i]) * 16u8 + hex_value(hex[2usize * i + 1usize])
        i += 1usize
    }
    var random: [64]u8 = zero
    i = 0usize
    while i < 64usize {
        random[i] = u8((i * 53usize + 11usize) % 251usize)
        i += 1usize
    }
    var password = "secret"
    if str.eq(mode, "badpass") { password = "wrong" }
    let (s_value, open_error) = ssh.open(a, random[0usize..64usize], "neper", password, 80u32, 24u32)
    if open_error != ok { os.exit(1i32) }
    var s = s_value
    if str.eq(mode, "sftp") { ssh.set_subsystem(&s, "sftp") }
    if str.eq(mode, "forward") || str.eq(mode, "forward_refused") {
        if args.len < 5usize { os.exit(91i32) }
        ssh.set_forward(&s, "127.0.0.1", u32(parse_port(args[4])))
    }
    if str.eq(mode, "key") {
        var seed: [32]u8 = zero
        i = 0usize
        while i < 32usize {
            seed[i] = u8(i + 1usize)
            i += 1usize
        }
        ssh.use_key(&s, seed)
    }
    let address = net.Address { Ip4: net.Ip4 { bytes: [4]u8{ 127u8, 0u8, 0u8, 1u8 } } }
    let (sock, connect_error) = net.tcp_connect(net.Endpoint { address: address, port: port })
    if connect_error != ok { os.exit(2i32) }
    defer let _ = net.close(sock)
    // Until the host key is offered.
    var rounds = 0usize
    while ssh.status(&s) != ssh.HOST_KEY_PENDING && ssh.status(&s) != ssh.FAILED && rounds < 50usize {
        if !pump(sock, &s) { os.exit(3i32) }
        rounds += 1usize
    }
    if ssh.status(&s) != ssh.HOST_KEY_PENDING { os.exit(4i32) }
    let key = ssh.host_key(&s)
    var same = true
    i = 0usize
    while i < 32usize {
        if key[i] != expected[i] { same = false }
        i += 1usize
    }
    if str.eq(mode, "badhost") {
        // The key is not the one the user trusted: the session is not continued.
        if same { os.exit(5i32) }
        ret ok
    }
    if !same { os.exit(6i32) }
    var fingerprint: [64]u8 = zero
    let fp_len = ssh.host_fingerprint(&s, fingerprint[0usize..64usize])
    if fp_len != 50usize || fingerprint[0usize] != 83u8 || fingerprint[5usize] != 54u8 || fingerprint[6usize] != 58u8 { os.exit(7i32) }
    ssh.trust(&s)
    rounds = 0usize
    while ssh.status(&s) != ssh.READY && ssh.status(&s) != ssh.FAILED && rounds < 60usize {
        if !pump(sock, &s) { break }
        rounds += 1usize
    }
    if str.eq(mode, "badpass") {
        if ssh.status(&s) != ssh.FAILED || s.failure != ssh.FAIL_AUTH { os.exit(8i32) }
        ret ok
    }
    if str.eq(mode, "forward_refused") {
        // Nothing listens at the target: the server refuses the channel, which is a channel failure, not a hang.
        if ssh.status(&s) != ssh.FAILED || s.failure != ssh.FAIL_CHANNEL { os.exit(62i32) }
        ret ok
    }
    if ssh.status(&s) != ssh.READY { os.exit(9i32) }
    if str.eq(mode, "sftp") {
        let code = sftp_session(sock, &s)
        if code != 0i32 { os.exit(code) }
        ret ok
    }
    if str.eq(mode, "forward") {
        let code = forward_session(sock, &s)
        if code != 0i32 { os.exit(code) }
        ret ok
    }
    // The shell greets us; send a line and read the answer.
    var got: [512]u8 = zero
    var got_len = 0usize
    rounds = 0usize
    var sent_line = false
    var answered = false
    while !answered && rounds < 60usize {
        var chunk: [128]u8 = zero
        let n = ssh.read(&s, chunk[0usize..128usize])
        i = 0usize
        while i < n && got_len < 512usize {
            got[got_len] = chunk[i]
            got_len += 1usize
            i += 1usize
        }
        if !sent_line && contains(got[0usize..got_len], "ready") {
            let taken = ssh.write(&s, "hello\r")
            sent_line = true
        }
        if contains(got[0usize..got_len], "HELLO") {
            answered = true
        } else {
            if !pump(sock, &s) { break }
        }
        rounds += 1usize
    }
    if !answered { os.exit(10i32) }
    // (C155) The cipher the server left us with.
    if str.eq(mode, "gcm256") && (s.cipher_out != ssh.CIPHER_AES256_GCM || s.cipher_in != ssh.CIPHER_AES256_GCM) { os.exit(14i32) }
    if str.eq(mode, "gcm128") && (s.cipher_out != ssh.CIPHER_AES128_GCM || s.cipher_in != ssh.CIPHER_AES128_GCM) { os.exit(15i32) }
    if str.eq(mode, "password") && (s.cipher_out != ssh.CIPHER_CHACHA || s.cipher_in != ssh.CIPHER_CHACHA) { os.exit(16i32) }
    if str.eq(mode, "rekey") {
        // Enough traffic that the server asks for new keys (its limit is set low): forty lines, each echoed in
        // capitals, written whenever a key exchange is not holding the session.
        let line = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghij\r"
        var written = 0usize
        var echoed = 0usize
        var spins = 0usize
        while echoed < 40usize && spins < 800usize {
            if written < 40usize {
                let taken_line = ssh.write(&s, line)
                if taken_line == line.len { written += 1usize }
            }
            var bunch: [256]u8 = zero
            let m = ssh.read(&s, bunch[0usize..256usize])
            var k = 0usize
            while k < m {
                if bunch[k] == 10u8 { echoed += 1usize }
                k += 1usize
            }
            if echoed < 40usize || written < 40usize {
                if !pump(sock, &s) { break }
            }
            spins += 1usize
        }
        if written != 40usize || echoed < 40usize { os.exit(12i32) }
        if s.rekeys < 1u32 { os.exit(13i32) }
        if s.cipher_out != ssh.CIPHER_AES256_GCM { os.exit(17i32) }
    }
    ssh.resize(&s, 100u32, 30u32)
    let taken_exit = ssh.write(&s, "exit\r")
    rounds = 0usize
    while ssh.status(&s) != ssh.CLOSED && ssh.status(&s) != ssh.FAILED && rounds < 60usize {
        if !pump(sock, &s) { break }
        rounds += 1usize
    }
    if !s.has_exit_status || s.exit_status != 7u32 { os.exit(11i32) }
    ret ok
}
