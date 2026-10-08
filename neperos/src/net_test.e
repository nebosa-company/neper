// The NeperOS network stack as an EL0 user-mode server under test (C117, D2244; `-append net`): the
// kernel maps the virtio-net device and a DMA pool into this program, which gets a lease over DHCP,
// pings the gateway and resolves a name, printing one line per step for the fixture to check. QEMU
// is started with user-mode networking (-nic user), where the gateway is 10.0.2.2 and the
// resolver 10.0.2.3.
use e.mem
use e.os
use virtio
use inet
use tcp
use https
use roots
use e.io
use e.net.tls

// The aux area the kernel fills for a driver server, at USER_BASE + vm.AUX_OFF (D2137).
const AUX: usize = 548682334144usize
// The random server's endpoints: requests go out on slot 2, words come back on slot 3.
const RNG_REQ: usize = 2usize
const RNG_REP: usize = 3usize
const NO_SLOT: usize = 99usize

fn read_device() -> virtio.Device {
    var device: virtio.Device = zero
    device.common = usize(os.load64(AUX))
    device.notify = usize(os.load64(AUX + 8usize))
    device.notify_multiplier = u32(os.load64(AUX + 16usize))
    virtio.pool_set(usize(os.load64(AUX + 24usize)), usize(os.load64(AUX + 32usize)))
    device.config = usize(os.load64(AUX + 40usize))
    ret device
}

fn main(a: *mem.Arena, args: []str) -> err {
    let device = read_device()
    var (st, open_error) = inet.attach(device)
    if open_error != ok {
        inet.say("net driver failed\n")
        ret ok
    }
    inet.say("net up\n")
    let lease_error = inet.dhcp(&st)
    if lease_error != ok {
        inet.say("net no lease\n")
        ret ok
    }
    inet.say("net lease ")
    inet.say_ip(st.ip)
    inet.say(" gateway ")
    inet.say_ip(st.gw)
    inet.say(" dns ")
    inet.say_ip(st.dns)
    inet.say("\n")
    let ping_error = inet.ping(&st, st.gw, 1u16)
    if ping_error == ok { inet.say("net ping reply\n") } else { inet.say("net ping failed\n") }
    let (found, name_error) = inet.resolve(&st, "example.com")
    if name_error == ok {
        inet.say("net resolved example.com ")
        inet.say_ip(found)
        inet.say("\n")
    } else {
        inet.say("net resolve failed\n")
    }
    // A plain HTTP exchange with the host (10.0.2.2 is the host in user-mode networking).
    var ring_storage: [65536]u8 = zero
    let (c, connect_error) = tcp.connect(&st, 167772674u32, 8081u16, mem.address_of(&ring_storage[0usize]))
    if connect_error != ok {
        inet.say("net tcp connect failed\n")
        ret ok
    }
    inet.say("net tcp connected\n")
    let request = "GET / HTTP/1.0\r\nHost: host\r\n\r\n"
    var conn = c
    var request_copy: [64]u8 = zero
    var k = 0usize
    while k < request.len {
        request_copy[k] = request[k]
        k += 1usize
    }
    let write_error = tcp.write(&conn, mem.address_of(&request_copy[0usize]), request.len)
    if write_error != ok {
        inet.say("net tcp write failed\n")
        ret ok
    }
    var reply: [256]u8 = zero
    let (got, read_error) = tcp.read(&conn, mem.address_of(&reply[0usize]), 256usize)
    if read_error != ok {
        inet.say("net tcp read failed\n")
        ret ok
    }
    inet.say("net tcp reply ")
    var line_end = 0usize
    while line_end < got && reply[line_end] != 13u8 { line_end += 1usize }
    inet.say(reply[0usize..line_end])
    inet.say("\n")
    let close_error = tcp.close(&conn)
    inet.say("net tcp closed\n")
    // The same host over TLS 1.3, its chain checked against the bundled test root.
    let (secure_conn, secure_connect_error) = tcp.connect(&st, 167772674u32, 8443u16, mem.address_of(&ring_storage[0usize]))
    if secure_connect_error != ok {
        inet.say("net tls connect failed\n")
        ret ok
    }
    var secure_tcp = secure_conn
    // 64 random bytes from the random server: the op word, a count of eight-byte words, then the words.
    var entropy: [64]u8 = zero
    let ask = os.send(RNG_REQ, 1usize, NO_SLOT)
    let ask_count = os.send(RNG_REQ, 8usize, NO_SLOT)
    var e = 0usize
    while e < 8usize {
        os.store64(mem.address_of(&entropy[0usize]) + e * 8usize, u64(os.recv(RNG_REP, NO_SLOT)))
        e += 1usize
    }
    let quit = os.send(RNG_REQ, 0usize, NO_SLOT)
    let (stream0, tls_error) = https.connect(a, &secure_tcp, "neper.test", roots.test_root_hex(), entropy[0usize..64usize])
    if tls_error != ok {
        inet.say("net tls failed\n")
        ret ok
    }
    inet.say("net tls handshake ok\n")
    var stream = stream0
    var secure_sink = tls.writer(&stream)
    let secure_request_error = io.write_all(&secure_sink, "GET / HTTP/1.0\r\nHost: neper.test\r\n\r\n")
    var secure_source = tls.reader(&stream)
    var secure_reply: [256]u8 = zero
    let (secure_got, secure_read_error) = io.read(&secure_source, secure_reply[0usize..256usize])
    if secure_read_error != ok {
        inet.say("net tls read failed\n")
        ret ok
    }
    inet.say("net tls reply ")
    var secure_end = 0usize
    while secure_end < secure_got && secure_reply[secure_end] != 13u8 { secure_end += 1usize }
    inet.say(secure_reply[0usize..secure_end])
    inet.say("\n")
    let close_secure = tls.close(&stream)
    // Two connections that must be refused: the right server asked for under the wrong name, and
    // the right name with no trusted root.
    var refusal = 0usize
    while refusal < 2usize {
        let (bad_conn, bad_connect_error) = tcp.connect(&st, 167772674u32, 8443u16, mem.address_of(&ring_storage[0usize]))
        if bad_connect_error != ok {
            inet.say("net tls refusal connect failed\n")
            ret ok
        }
        var bad_tcp = bad_conn
        var bad_name = "neper.test"
        var bad_roots = roots.test_root_hex()
        if refusal == 0usize { bad_name = "wrong.test" } else { bad_roots = "" }
        let (bad_stream, bad_error) = https.connect(a, &bad_tcp, bad_name, bad_roots, entropy[0usize..64usize])
        if bad_error != ok {
            if refusal == 0usize { inet.say("net tls wrong name refused\n") } else { inet.say("net tls untrusted root refused\n") }
        } else {
            inet.say("net tls ACCEPTED A BAD CHAIN\n")
        }
        let bad_close = tcp.close(&bad_tcp)
        refusal += 1usize
    }
    ret ok
}
