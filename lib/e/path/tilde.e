// Tilde expansion for paths, the shell and `os.path.expanduser` rule: a leading `~` alone, or
// followed by `/` (or `\`), is the caller's home directory; `~name` is the home of `name`
// when the caller supplies a table (or `/etc/passwd` text) that has it. A tilde anywhere else
// is literal, and an unresolvable `~name` is left as written (no error), as the shell does.
// Trailing slashes of the home are dropped before joining so `~/x` under `/root/` is `/root/x`,
// and an empty home leaves the root `/`.
//
// Nothing here reads the environment or the user database: pass `os.env("HOME")` (or the
// platform's profile directory) as `home`, and `passwd_home` over the text of `/etc/passwd`
// where there is one. `collapse` is the inverse used for display: the home prefix becomes `~`.

error TooSmall

type UserHome = struct { name: str, home: str }

fn is_sep(c: u8) -> bool { ret c == 47u8 || c == 92u8 }

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn put(dst: []u8, n: usize, s: str) -> (usize, bool) {
    if n + s.len > dst.len { ret (n, false) }
    var i = 0usize
    while i < s.len {
        dst[n + i] = s[i]
        i += 1usize
    }
    ret (n + s.len, true)
}

// `expand`: the leading `~`, `~/rest` or `~name/rest` resolved against `home` and `users`.
fn expand(path: str, home: str, users: []const UserHome, dst: []u8) -> (str, err) {
    if path.len == 0usize || path[0usize] != 126u8 {
        let (n, fits) = put(dst, 0usize, path)
        if !fits { ret ("", TooSmall) }
        ret (dst[..n], ok)
    }
    var end = 1usize
    while end < path.len && !is_sep(path[end]) { end += 1usize }
    let name = path[1usize..end]
    var base = home
    var found = true
    if name.len > 0usize {
        found = false
        var i = 0usize
        while i < users.len {
            if same(users[i].name, name) {
                base = users[i].home
                found = true
                break
            }
            i += 1usize
        }
    }
    if !found {
        let (n, fits) = put(dst, 0usize, path)
        if !fits { ret ("", TooSmall) }
        ret (dst[..n], ok)
    }
    var trimmed = base.len
    while trimmed > 0usize && base[trimmed - 1usize] == 47u8 { trimmed -= 1usize }
    let (n, fits) = put(dst, 0usize, base[0usize..trimmed])
    if !fits { ret ("", TooSmall) }
    let (n2, fits2) = put(dst, n, path[end..path.len])
    if !fits2 { ret ("", TooSmall) }
    if n2 == 0usize {
        if dst.len < 1usize { ret ("", TooSmall) }
        dst[0usize] = 47u8
        ret (dst[..1usize], ok)
    }
    ret (dst[..n2], ok)
}

// `/home/ann/src` -> `~/src`, `/home/ann` -> `~`; anything not under `home` is unchanged.
fn collapse(path: str, home: str, dst: []u8) -> (str, err) {
    var trimmed = home.len
    while trimmed > 0usize && home[trimmed - 1usize] == 47u8 { trimmed -= 1usize }
    let base = home[0usize..trimmed]
    if trimmed > 0usize && path.len >= trimmed && same(path[0usize..trimmed], base) && (path.len == trimmed || is_sep(path[trimmed])) {
        let (n, fits) = put(dst, 0usize, "~")
        if !fits { ret ("", TooSmall) }
        let (n2, fits2) = put(dst, n, path[trimmed..path.len])
        if !fits2 { ret ("", TooSmall) }
        ret (dst[..n2], ok)
    }
    let (n, fits) = put(dst, 0usize, path)
    if !fits { ret ("", TooSmall) }
    ret (dst[..n], ok)
}

// The home directory field of `name`'s line in `/etc/passwd` text
// (`name:x:uid:gid:gecos:home:shell`); `false` when there is no such line.
fn passwd_home(passwd: str, name: str) -> (str, bool) {
    var start = 0usize
    var i = 0usize
    while i <= passwd.len {
        if i == passwd.len || passwd[i] == 10u8 {
            let line = passwd[start..i]
            var field = 0usize
            var f_start = 0usize
            var k = 0usize
            var user_ok = false
            while k <= line.len {
                if k == line.len || line[k] == 58u8 {
                    let piece = line[f_start..k]
                    if field == 0usize { user_ok = same(piece, name) && name.len > 0usize }
                    if field == 5usize && user_ok { ret (piece, true) }
                    field += 1usize
                    f_start = k + 1usize
                }
                k += 1usize
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret ("", false)
}
