// The private file-list representation on NSPasteboard must preserve every
// path byte, including empty paths and newlines, and distinguish no paths.
use e.mem
use e.os
use e.os.shell

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var at = 0usize
    while at < a.len {
        if a[at] != b[at] { ret false }
        at += 1usize
    }
    ret true
}

fn round_trip(a: *mem.Arena, expected: []const str) -> bool {
    var item: [1]shell.Content = zero
    item[0usize] = shell.Content { kind: .Files, mime: "", text: "", paths: expected, image: zero, bytes: zero }
    if shell.clipboard_write(a, item[..]) != ok { ret false }
    let (actual, read_error) = shell.clipboard_read(a, .Files, "")
    if read_error != ok || actual.paths.len != expected.len { ret false }
    var at = 0usize
    while at < expected.len {
        if !same(actual.paths[at], expected[at]) { ret false }
        at += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var no_paths: [1]str = zero
    if !round_trip(a, no_paths[0usize..0usize]) { os.exit(1i32) }
    var paths: [3]str = zero
    paths[0usize] = ""
    paths[1usize] = "line one\nline two"
    paths[2usize] = "tail\n"
    if !round_trip(a, paths[..]) { os.exit(2i32) }
    ret ok
}
