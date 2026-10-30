// `e.os`'s directory watch past the first event: a file rewritten in place is a `Modified`, and a removal and an addition
// made together are both reported, however many reads it takes a host to hand them over. (`os_watch` is a creation and a
// removal, each read straight after.) Names are scanned by their ending because the path is the watched directory and a name.

use e.mem
use e.os

fn ends_with(text: str, tail: str) -> bool {
    if text.len < tail.len { ret false }
    var at = 0usize
    while at < tail.len {
        if text[text.len - tail.len + at] != tail[at] { ret false }
        at += 1usize
    }
    ret true
}

fn write_file_of(a: *mem.Arena, path: str, bytes: str) -> err {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.truncate = true
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret open_error }
    let (written, write_error) = os.write(file, bytes)
    let close_error = os.close(file)
    if write_error != ok { ret write_error }
    ret close_error
}

// Reads until `wanted` events (action, name ending) have all been seen, at most eight reads.
fn saw_all(a: *mem.Arena, w: os.Watch, first_action: os.WatchAction, first_name: str, second_action: os.WatchAction, second_name: str) -> bool {
    var first = false
    var second = false
    var reads = 0usize
    while reads < 8usize && !(first && second) {
        var events: [16]os.WatchEvent = zero
        let (count, read_error) = os.watch_read(a, w, events[..])
        if read_error != ok { ret false }
        var at = 0usize
        while at < count {
            if events[at].action == first_action && ends_with(events[at].path, first_name) { first = true }
            if events[at].action == second_action && ends_with(events[at].path, second_name) { second = true }
            at += 1usize
        }
        reads += 1usize
    }
    ret first && second
}

fn main(a: *mem.Arena) -> err {
    let stale_file = os.remove_file(a, "np-watch-mod/file.txt")
    let stale_other = os.remove_file(a, "np-watch-mod/other.txt")
    let stale_dir = os.remove_dir(a, "np-watch-mod")
    if os.mkdir(a, "np-watch-mod") != ok { os.exit(10i32) }
    if write_file_of(a, "np-watch-mod/file.txt", "ab") != ok { os.exit(11i32) }

    // Rewritten in place, with a different length: the entry was there when the watch opened, so only a modification is news.
    let (modifying, modifying_error) = os.watch_open(a, "np-watch-mod", false)
    if modifying_error != ok { os.exit(20i32) }
    if write_file_of(a, "np-watch-mod/file.txt", "abcdefgh") != ok { os.exit(21i32) }
    if !saw_all(a, modifying, .Modified, "file.txt", .Modified, "file.txt") { os.exit(22i32) }
    if os.watch_close(modifying) != ok { os.exit(23i32) }

    // One removal and one addition between two reads: both come out.
    let (both, both_error) = os.watch_open(a, "np-watch-mod", false)
    if both_error != ok { os.exit(30i32) }
    if os.remove_file(a, "np-watch-mod/file.txt") != ok { os.exit(31i32) }
    if write_file_of(a, "np-watch-mod/other.txt", "x") != ok { os.exit(32i32) }
    if !saw_all(a, both, .Removed, "file.txt", .Added, "other.txt") { os.exit(33i32) }
    if os.watch_close(both) != ok { os.exit(34i32) }

    if os.remove_file(a, "np-watch-mod/other.txt") != ok { os.exit(40i32) }
    if os.remove_dir(a, "np-watch-mod") != ok { os.exit(41i32) }
    ret ok
}
