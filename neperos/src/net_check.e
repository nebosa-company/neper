// An app of the NeperOS network (C117, D2247; `-append net`): it holds only the two endpoint
// capabilities and uses the network by host name -- resolve, plain TCP, TLS with the chain and the name
// checked, a refused name, a refused port -- printing one line per step for the fixture. The host
// (10.0.2.2 in QEMU user-mode networking) runs the DNS responder, an HTTP server and an HTTPS server.
use e.mem
use e.os
use netclient
use netproto

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn say_num(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    say(digits[at..20usize])
}

// GET / on the open connection and the reply's first line and body.
fn get(host: str, label: str) {
    var request: [128]u8 = zero
    let text = "GET / HTTP/1.0\r\nHost: neper.test\r\n\r\n"
    var i = 0usize
    while i < text.len {
        request[i] = text[i]
        i += 1usize
    }
    if netclient.send(mem.address_of(&request[0usize]), text.len) != netproto.R_OK {
        say(label)
        say(" send failed\n")
        ret
    }
    var reply: [2048]u8 = zero
    var total = 0usize
    var done = false
    while !done && total < 1900usize {
        let (n, r) = netclient.recv(mem.address_of(&reply[0usize]) + total, 2048usize - total)
        if r != netproto.R_OK || n == 0usize { done = true } else { total += n }
    }
    var line_end = 0usize
    while line_end < total && reply[line_end] != 13u8 { line_end += 1usize }
    say(label)
    say(" ")
    say(reply[0usize..line_end])
    say("\n")
    var body = 0usize
    while body + 3usize < total && !(reply[body] == 13u8 && reply[body + 1usize] == 10u8 && reply[body + 2usize] == 13u8 && reply[body + 3usize] == 10u8) { body += 1usize }
    say(label)
    say(" body ")
    if body + 4usize <= total { say(reply[body + 4usize..total]) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let dns = netclient.set_dns(167772674u32, 5300u16)
    // The name resolves through the host's DNS responder; TLS validates the chain and "neper.test".
    let secure = netclient.connect("neper.test", 8443u16, true)
    if secure == netproto.R_OK {
        say("net check tls connected\n")
        get("neper.test", "net check tls")
        let closed = netclient.close()
    } else {
        say("net check tls failed ")
        say_num(secure)
        say("\n")
    }
    // The same server under a name the certificate does not carry: resolved, connected, refused.
    let wrong = netclient.connect("wrong.test", 8443u16, true)
    say("net check wrong name result ")
    say_num(wrong)
    say("\n")
    let plain = netclient.connect("neper.test", 8081u16, false)
    if plain == netproto.R_OK {
        say("net check plain connected\n")
        get("neper.test", "net check plain")
        let closed = netclient.close()
    } else {
        say("net check plain failed ")
        say_num(plain)
        say("\n")
    }
    // A port nothing listens on.
    let refused = netclient.connect("10.0.2.2", 9u16, false)
    say("net check closed port result ")
    say_num(refused)
    say("\n")
    netclient.quit()
    ret ok
}
