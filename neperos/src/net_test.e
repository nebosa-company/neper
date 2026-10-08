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

// The aux area the kernel fills for a driver server, at USER_BASE + vm.AUX_OFF (D2137).
const AUX: usize = 548682334144usize

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
    ret ok
}
