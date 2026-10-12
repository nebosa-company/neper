// e.os.ident: the host, user, locale and zone lookups answer well-formed values on the running host
// (D2801). The values themselves are machine-specific; the fixture checks their shape: a host name
// is non-empty with no whitespace or control byte, a locale tag is `ll` or `ll-XX...` ASCII, a zone
// id is non-empty printable. On Linux the user, locale and zone come from the environment and may
// legitimately be absent (`NotFound`); anything else is a failure. The pure POSIX-locale rewrite is
// covered by the variant itself on Linux only.
use e.io
use e.mem
use e.os
use e.os.ident

fn printable(s: str) -> bool {
    if s.len == 0usize { ret false }
    var i = 0usize
    while i < s.len {
        if s[i] <= 32u8 && s[i] != 32u8 { ret false }
        if s[i] == 127u8 { ret false }
        i += 1usize
    }
    ret true
}

fn no_space(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] <= 32u8 || s[i] == 127u8 { ret false }
        i += 1usize
    }
    ret s.len > 0usize
}

fn locale_shape(s: str) -> bool {
    if s.len < 2usize { ret false }
    var i = 0usize
    while i < s.len {
        let c = s[i]
        let letter = (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8)
        let digit = c >= 48u8 && c <= 57u8
        if !(letter || digit || c == 45u8) { ret false }
        i += 1usize
    }
    ret s[0usize] != 45u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (host, host_error) = ident.hostname(a)
    if host_error != ok { os.exit(1i32) }
    if !no_space(host) || host.len > 255usize { os.exit(2i32) }
    let (user, user_error) = ident.user_name(a)
    if user_error == ok {
        if !printable(user) { os.exit(3i32) }
    } else if user_error != os.NotFound {
        os.exit(4i32)
    }
    let (locale, locale_error) = ident.locale_name(a)
    if locale_error == ok {
        if !locale_shape(locale) { os.exit(5i32) }
    } else if locale_error != os.NotFound {
        os.exit(6i32)
    }
    let (zone, zone_error) = ident.time_zone_id(a)
    if zone_error == ok {
        if !printable(zone) { os.exit(7i32) }
    } else if zone_error != os.NotFound {
        os.exit(8i32)
    }
    try io.print("os ident ok")
    ret ok
}
