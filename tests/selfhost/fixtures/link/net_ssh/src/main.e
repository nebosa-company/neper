// e.net.ssh against a real SSH server (asyncssh, started by drive.py): the version exchange, curve25519-sha256 with
// an ssh-ed25519 host key, chacha20-poly1305@openssh.com, password and public-key authentication, a pty and a shell
// that upper-cases a line and exits with status 7, a wrong password refused, a wrong host key refused.
// Arguments: mode (password, key, badpass, badhost), port, the host key as 64 hex digits.
// Every stage has its own exit code.
use e.io
use e.mem
use e.net
use e.os
use e.str
use e.net.ssh as ssh

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
    if ssh.status(&s) != ssh.READY { os.exit(9i32) }
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
