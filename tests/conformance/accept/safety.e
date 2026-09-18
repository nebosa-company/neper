use e.mem
use e.os

// The resource rules' valid shapes (D345): a `try`d acquisition closed on every exit,
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

// A duplicate is a second handle with its own obligation (D349); the borrowed
// parameter is read, never closed, and a field of a borrowed struct is a view.
type Pair = struct { first: os.File, second: os.File }

fn twice(f: os.File) -> (usize, err) {
    let d = try os.dup(f)
    var buffer: [16]u8 = zero
    let (n, read_error) = os.read(d, buffer[..])
    let close_error = os.close(d)
    if read_error != ok { ret (0usize, read_error) }
    ret (n, close_error)
}

// A handle beside a flag (D353): null on the false path, owned once the flag is
// tested, the way an `err` is.
fn maybe_open(a: *mem.Arena, path: str, wanted: bool) -> (os.File, bool) {
    if !wanted { ret (zero, false) }
    let flags = os.OpenFlags {
        read: true,
        write: false,
        create: false,
        truncate: false,
        append: false,
    }
    let (f, open_error) = os.open(a, path, flags)
    if open_error != ok { ret (zero, false) }
    ret (f, true)
}

fn close_if_open(a: *mem.Arena, path: str) -> err {
    let (first, has_first) = maybe_open(a, path, true)
    if has_first { try os.close(first) } else { ret os.NotFound }
    let (second, has_second) = maybe_open(a, path, false)
    if !has_second { ret ok }
    ret os.close(second)
}

fn peek(p: Pair) -> usize {
    let first = p.first
    if os.file_handle(first).raw == os.file_handle(p.second).raw { ret 0usize }
    ret 1usize
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
    let (dup_read, dup_error) = twice(f)
    if dup_error != ok {
        let _ = os.close(f)
        ret dup_error
    }
    let (second, second_error) = os.open(a, args[0usize], flags)
    if second_error != ok {
        let _ = os.close(f)
        ret second_error
    }
    let pair = Pair { first: f, second: second }
    let distinct = peek(pair)
    let second_close = os.close(pair.second)
    if distinct != 1usize || second_close != ok {
        let _ = os.close(pair.first)
        if second_close != ok { ret second_close }
        ret os.Failed
    }
    try take(pair.first)
    try close_if_open(a, args[0usize])
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
