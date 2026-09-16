use e.mem
use e.os

// The resource rules' valid shapes (D341): a `try`d acquisition closed on every exit,
// an `own` parameter that takes the handle and its obligation, a `defer` that
// reserves, an error test against one error and against ok, each narrowing,
// and a handle moved into an array a loop closes.
fn take(f: own os.File) -> err {
    ret os.close(f)
}

fn count_bytes(a: *mem.Arena, path: str) -> (usize, err) {
    let flags = os.OpenFlags {
        read: true,
        write: false,
        create: false,
        truncate: false,
        append: false,
    }
    let f = try os.open(a, path, flags)
    defer let _ = os.close(f)
    var buffer: [16]u8 = zero
    var total = 0usize
    while true {
        let (n, read_error) = os.read(f, buffer[..])
        if read_error != ok { ret (0usize, read_error) }
        if n == 0usize { break }
        total += n
    }
    ret (total, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags {
        read: true,
        write: false,
        create: false,
        truncate: false,
        append: false,
    }
    let f = try os.open(a, args[0usize], flags)
    try take(f)
    let (g, open_error) = os.open(a, args[0usize], flags)
    if open_error != ok { ret open_error }
    let (total, count_error) = count_bytes(a, args[0usize])
    let close_error = os.close(g)
    if count_error != ok { ret count_error }
    let (maybe, maybe_error) = os.open(a, "np-absent", flags)
    if maybe_error == os.NotFound { ret close_error }
    if maybe_error != ok { ret maybe_error }
    try os.close(maybe)
    var files: [2]os.File = zero
    var at = 0usize
    while at < 2usize {
        files[at] = try os.open(a, args[0usize], flags)
        at += 1usize
    }
    at = 0usize
    while at < 2usize {
        let one = files[at]
        try os.close(one)
        at += 1usize
    }
    ret close_error
}
