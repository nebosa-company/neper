// Who and where this process is, on macOS: the host name (gethostname), the user's name (`USER`,
// then `LOGNAME`), the locale as a BCP 47 tag from the POSIX variables (`LC_ALL`, `LC_MESSAGES`,
// `LANG`: `de_DE.UTF-8` becomes `de-DE`; `C` and `POSIX` are `NotFound`) and the time zone as an
// IANA id (`TZ`, then the link `/etc/localtime` points through). The hardware address is not
// offered: Darwin has no sysfs, and getifaddrs would be the only way to read one.


use e.mem
use e.os

fn is_blank(c: u8) -> bool { ret c == 32u8 || c == 10u8 || c == 13u8 || c == 9u8 }

fn trim(s: str) -> str {
    var a = 0usize
    var b = s.len
    while a < b && is_blank(s[a]) { a += 1usize }
    while b > a && is_blank(s[b - 1usize]) { b -= 1usize }
    ret s[a..b]
}

// A file read whole, at most `cap` bytes.
fn read_small(a: *mem.Arena, path: str, cap: usize) -> (str, err) {
    var flags: os.OpenFlags = zero
    flags.read = true
    let (f, open_error) = os.open(a, path, flags)
    if open_error != ok { ret ("", open_error) }
    let (buf, alloc_error) = mem.alloc[u8](a, cap)
    if alloc_error != ok {
        let closed = os.close(f)
        ret ("", alloc_error)
    }
    var n = 0usize
    while n < cap {
        let (got, read_error) = os.read(f, buf[n..cap])
        if read_error != ok {
            let closed = os.close(f)
            ret ("", read_error)
        }
        if got == 0usize { break }
        n += got
    }
    let closed = os.close(f)
    ret (buf[0usize..n], ok)
}

// A non-empty environment value, or `NotFound`.
fn env_value(a: *mem.Arena, name: str) -> (str, err) {
    let (value, value_error) = os.env(a, name)
    if value_error != ok { ret ("", os.NotFound) }
    let t = trim(value)
    if t.len == 0usize { ret ("", os.NotFound) }
    ret (t, ok)
}


@import("c", "gethostname")
extern fn raw_gethostname(name: usize, length: usize) -> i32

fn hostname(a: *mem.Arena) -> (str, err) {
    let (buffer, allocation_error) = mem.alloc[u8](a, 256usize)
    if allocation_error != ok { ret ("", allocation_error) }
    if raw_gethostname(mem.address_of(&buffer[0usize]), 255usize) != 0i32 { ret ("", os.NotFound) }
    buffer[255usize] = 0u8
    var length = 0usize
    while length < 255usize && buffer[length] != 0u8 { length += 1usize }
    let name = trim(buffer[0usize..length])
    if name.len == 0usize { ret ("", os.NotFound) }
    ret (name, ok)
}

fn user_name(a: *mem.Arena) -> (str, err) {
    let (user, user_error) = env_value(a, "USER")
    if user_error == ok { ret (user, ok) }
    let (login, login_error) = env_value(a, "LOGNAME")
    if login_error == ok { ret (login, ok) }
    ret ("", os.NotFound)
}

fn locale_tag(a: *mem.Arena, raw: str) -> (str, err) {
    var end = 0usize
    while end < raw.len && raw[end] != 46u8 && raw[end] != 64u8 { end += 1usize }
    let base = raw[0usize..end]
    if base.len == 0usize { ret ("", os.NotFound) }
    if base.len == 1usize && base[0usize] == 67u8 { ret ("", os.NotFound) }
    if base.len == 5usize && base[0usize] == 80u8 && base[1usize] == 79u8 && base[2usize] == 83u8 && base[3usize] == 73u8 && base[4usize] == 88u8 { ret ("", os.NotFound) }
    let (out, alloc_error) = mem.alloc[u8](a, base.len)
    if alloc_error != ok { ret ("", alloc_error) }
    var i = 0usize
    while i < base.len {
        var c = base[i]
        if c == 95u8 { c = 45u8 }
        out[i] = c
        i += 1usize
    }
    ret (out[0usize..base.len], ok)
}

fn locale_name(a: *mem.Arena) -> (str, err) {
    var raw = ""
    let (all, all_error) = env_value(a, "LC_ALL")
    if all_error == ok {
        raw = all
    } else {
        let (messages, messages_error) = env_value(a, "LC_MESSAGES")
        if messages_error == ok {
            raw = messages
        } else {
            let (lang, lang_error) = env_value(a, "LANG")
            if lang_error == ok { raw = lang }
        }
    }
    if raw.len == 0usize { ret ("", os.NotFound) }
    let (tag, tag_error) = locale_tag(a, raw)
    ret (tag, tag_error)
}


// The zone is the name after `zoneinfo/` in the path `/etc/localtime` links to.
fn time_zone_id(a: *mem.Arena) -> (str, err) {
    let (tz, tz_error) = env_value(a, "TZ")
    if tz_error == ok {
        if tz[0usize] == 58u8 { ret (tz[1usize..tz.len], ok) }
        ret (tz, ok)
    }
    let (link_target, link_error) = os.read_link(a, "/etc/localtime")
    if link_error != ok { ret ("", os.NotFound) }
    let marker = "zoneinfo/"
    var at = 0usize
    while at + marker.len <= link_target.len {
        var matched = true
        var offset = 0usize
        while offset < marker.len {
            if link_target[at + offset] != marker[offset] { matched = false }
            offset += 1usize
        }
        if matched {
            let name = link_target[at + marker.len..link_target.len]
            if name.len == 0usize { ret ("", os.NotFound) }
            ret (name, ok)
        }
        at += 1usize
    }
    ret ("", os.NotFound)
}

fn mac_address(a: *mem.Arena) -> (str, err) { ret ("", os.NotFound) }
