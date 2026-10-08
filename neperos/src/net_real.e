// A manual check of the bundled Mozilla roots against the real internet (C117, D2247): boot with
// `-append "net realroots"`, which hands the network server the real trust store alone, and this app
// fetches a page from a public HTTPS site by name. Not part of the suites -- they must not need the
// internet. Build it in place of net_check in the net archive. www.python.org (an RSA-SHA256 chain)
// answers `HTTP/1.1 200 OK`; a chain with an ECDSA-SHA384 signature or a P-384 root, which is most
// modern ECC sites (example.com, github.com, wikipedia.org), is refused for want of those verifiers
// in e.crypto (C144).
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

fn visit(host: str) {
    let r = netclient.connect(host, 443u16, true)
    say("net real ")
    say(host)
    say(" connect result ")
    say_num(r)
    say("\n")
    if r != netproto.R_OK { ret }
    var request: [160]u8 = zero
    let text = "GET / HTTP/1.0\r\nHost: www.python.org\r\nConnection: close\r\n\r\n"
    var i = 0usize
    while i < text.len {
        request[i] = text[i]
        i += 1usize
    }
    if netclient.send(mem.address_of(&request[0usize]), text.len) != netproto.R_OK {
        say("net real send failed\n")
        ret
    }
    var reply: [512]u8 = zero
    let (n, rr) = netclient.recv(mem.address_of(&reply[0usize]), 512usize)
    var line_end = 0usize
    while line_end < n && reply[line_end] != 13u8 { line_end += 1usize }
    say("net real ")
    say(host)
    say(" bytes ")
    say_num(n)
    say(" result ")
    say_num(rr)
    say(" reply ")
    say(reply[0usize..line_end])
    say("\n")
    let closed = netclient.close()
}

fn main(a: *mem.Arena, args: []str) -> err {
    visit("www.python.org")
    netclient.quit()
    ret ok
}
