use e.mem
use e.net
use e.str

error Failed

fn roundtrip(text: str, expected: str) -> bool {
    let (address, parse_error) = net.parse_ip(text)
    if parse_error != ok { ret false }
    var output: [64]u8 = zero
    let (formatted, format_error) = net.format_ip(address, output[0..])
    ret format_error == ok && str.eq(formatted, expected)
}

fn main(a: *mem.Arena) -> err {
    if !roundtrip("127.0.0.1", "127.0.0.1") { ret Failed }
    if !roundtrip("255.0.10.42", "255.0.10.42") { ret Failed }
    if !roundtrip("::", "::") { ret Failed }
    if !roundtrip("0:0:0:0:0:0:0:1", "::1") { ret Failed }
    if !roundtrip("2001:0DB8:0:0:1:0:0:1", "2001:db8::1:0:0:1") { ret Failed }
    if !roundtrip("2001:db8:0:1:0:0:0:1", "2001:db8:0:1::1") { ret Failed }
    if !roundtrip("::ffff:127.0.0.1", "::ffff:7f00:1") { ret Failed }
    if !roundtrip("fe80::1%4294967295", "fe80::1%4294967295") { ret Failed }

    let invalid = [10]str{ "", "1.2.3", "1.2.3.256", "111111111111.2.3.4", "01.2.3.4", ":1", "1::2::3", "1:2:3:4:5:6:7:8::", "fe80::1%eth0", "fe80::1%4294967296" }
    var at = 0usize
    while at < invalid.len {
        let (address, parse_error) = net.parse_ip(invalid[at])
        if parse_error != net.Failed { ret Failed }
        at += 1usize
    }

    let (address, parse_error) = net.parse_ip("2001:db8::1")
    if parse_error != ok { ret parse_error }
    var short: [10]u8 = zero
    let (text, short_error) = net.format_ip(address, short[0..])
    if short_error != net.Failed || text.len != 0usize { ret Failed }
    ret ok
}
