// `e.os`'s `socket_resolve`.
//
// Nothing here needs a network. A literal is answered by parsing it, and the loopback name by
// the hosts file on one host and its own resolver on the other -- so the whole fixture works
// offline, which a test that reaches for DNS would not. The one case that does leave the machine
// only checks that it failed, since offline that is a timeout and online a name that is not
// there, and both are right.

use e.mem
use e.os

fn main(a: *mem.Arena) -> err {
    // --- A literal is not a name and no resolver is asked. The port is the caller's, since a
    // literal carries none.
    let (four, four_error) = os.socket_resolve(a, "127.0.0.1", 8080u16, .Ip4)
    if four_error != ok { os.exit(10i32) }
    if four.len != 1usize { os.exit(11i32) }
    if four[0usize].family != .Ip4 { os.exit(12i32) }
    if four[0usize].port != 8080u16 { os.exit(13i32) }
    if four[0usize].bytes[0usize] != 127u8 { os.exit(14i32) }
    if four[0usize].bytes[1usize] != 0u8 { os.exit(15i32) }
    if four[0usize].bytes[2usize] != 0u8 { os.exit(16i32) }
    if four[0usize].bytes[3usize] != 1u8 { os.exit(17i32) }

    // --- A dotted quad with a part past 255 is not an address, and must not be read as a name
    // either: a resolver that fell through to DNS here would ask the network about digits.
    let (bad, bad_error) = os.socket_resolve(a, "300.1.1.1", 80u16, .Ip4)
    if bad_error == ok { os.exit(18i32) }

    // --- The compressed loopback, which is the shortest form of every rule in the syntax.
    let (six, six_error) = os.socket_resolve(a, "::1", 443u16, .Ip6)
    if six_error != ok { os.exit(20i32) }
    if six.len != 1usize { os.exit(21i32) }
    if six[0usize].family != .Ip6 { os.exit(22i32) }
    if six[0usize].port != 443u16 { os.exit(23i32) }
    var at = 0usize
    while at < 15usize {
        if six[0usize].bytes[at] != 0u8 { os.exit(24i32) }
        at += 1usize
    }
    if six[0usize].bytes[15usize] != 1u8 { os.exit(25i32) }

    // --- A full IPv6 literal, and one with the zeros in the middle rather than at the front.
    let (full, full_error) = os.socket_resolve(a, "2001:db8:0:0:0:0:0:1", 80u16, .Ip6)
    if full_error != ok { os.exit(26i32) }
    if full[0usize].bytes[0usize] != 32u8 { os.exit(27i32) }
    if full[0usize].bytes[1usize] != 1u8 { os.exit(28i32) }
    if full[0usize].bytes[2usize] != 13u8 { os.exit(29i32) }
    if full[0usize].bytes[3usize] != 184u8 { os.exit(30i32) }
    if full[0usize].bytes[15usize] != 1u8 { os.exit(31i32) }
    let (middle, middle_error) = os.socket_resolve(a, "2001:db8::1", 80u16, .Ip6)
    if middle_error != ok { os.exit(32i32) }
    var byte = 0usize
    while byte < 16usize {
        if middle[0usize].bytes[byte] != full[0usize].bytes[byte] { os.exit(33i32) }
        byte += 1usize
    }

    // --- The loopback name. Both hosts answer it without a network, and both answer inside
    // 127.0.0.0/8 -- which is all that is portable, since one of them says 127.0.0.1 and the
    // other is entitled not to.
    let (local, local_error) = os.socket_resolve(a, "localhost", 80u16, .Ip4)
    if local_error != ok { os.exit(40i32) }
    if local.len == 0usize { os.exit(41i32) }
    if local[0usize].family != .Ip4 { os.exit(42i32) }
    if local[0usize].port != 80u16 { os.exit(43i32) }
    if local[0usize].bytes[0usize] != 127u8 { os.exit(44i32) }

    // --- An empty name is not a name.
    let (empty, empty_error) = os.socket_resolve(a, "", 80u16, .Ip4)
    if empty_error != os.NotFound { os.exit(50i32) }

    // --- A name reserved to never exist. Offline that is a timeout and online a name that is
    // not there, so only the failure is portable.
    let (absent, absent_error) = os.socket_resolve(a, "np-nothing-here.invalid", 80u16, .Ip4)
    if absent_error == ok { os.exit(51i32) }
    ret ok
}
