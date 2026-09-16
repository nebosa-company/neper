// `e.os`'s directory watch: a real change to a real directory, reported with a path.
//
// The change is made before the read, which is the case that says watching begins when the
// watch opens rather than when it is first read -- one host queues from the moment the watch
// exists and the other had to be armed at open to agree.
//
// This must run on a filesystem that reports changes. A 9p or DrvFS mount accepts a watch and
// then never reports anything, so `watch_read` would wait forever -- the runners put this on a
// local filesystem for that reason, and it is not something the fixture can detect for itself.
//
// Every event that a single action produces is scanned rather than only the first, because
// how many a host reports for one change is its own business: creating a file is one event on
// one and can be two on the other.

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

// One read, and then a look through everything it gave for the change that was made.
fn saw(a: *mem.Arena, w: os.Watch, action: os.WatchAction, name: str) -> (bool, err) {
    var events: [16]os.WatchEvent = zero
    let (count, read_error) = os.watch_read(a, w, events[..])
    if read_error != ok { ret (false, read_error) }
    var at = 0usize
    while at < count {
        if events[at].action == action && ends_with(events[at].path, name) {
            // The host reports a name relative to the directory, so a path is only a path if
            // the watch prepended what it is watching -- a bare name ends the same way.
            if events[at].path.len <= name.len { ret (false, os.Failed) }
            ret (true, ok)
        }
        at += 1usize
    }
    ret (false, ok)
}

fn write_file_of(a: *mem.Arena, path: str, fill: u8) -> err {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.truncate = true
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret open_error }
    var payload: [4]u8 = zero
    payload[0usize] = fill
    payload[1usize] = fill
    payload[2usize] = fill
    payload[3usize] = fill
    let (written, write_error) = os.write(file, payload[..])
    let close_error = os.close(file)
    if write_error != ok { ret write_error }
    ret close_error
}

fn main(a: *mem.Arena) -> err {
    let stale_file = os.remove_file(a, "np-watch/seen.txt")
    let stale_dir = os.remove_dir(a, "np-watch")
    if os.mkdir(a, "np-watch") != ok { os.exit(10i32) }

    // A recursive watch is refused by both hosts, so a program written against one behaves
    // the same on the other.
    let (deep, deep_error) = os.watch_open(a, "np-watch", true)
    if deep_error != os.Unsupported { os.exit(11i32) }

    // A directory that is not there cannot be watched.
    let (missing, missing_error) = os.watch_open(a, "np-watch-absent", false)
    if missing_error != os.NotFound { os.exit(12i32) }

    // One watch per action, and a read straight after it. A single change is not one event
    // everywhere -- creating a file is an addition on both hosts and a modification as well on
    // at least one -- so a watch that had seen two actions would leave a read holding
    // whichever came first. A fresh watch has an empty queue, which makes one read exact.
    let (creating, creating_error) = os.watch_open(a, "np-watch", false)
    if creating_error != ok { os.exit(13i32) }
    // Created before the read: the event has to have been queued from the watch's opening.
    if write_file_of(a, "np-watch/seen.txt", 97u8) != ok { os.exit(20i32) }
    let (added, added_error) = saw(a, creating, .Added, "seen.txt")
    if added_error != ok { os.exit(21i32) }
    if !added { os.exit(22i32) }
    if os.watch_close(creating) != ok { os.exit(23i32) }

    let (removing, removing_error) = os.watch_open(a, "np-watch", false)
    if removing_error != ok { os.exit(30i32) }
    if os.remove_file(a, "np-watch/seen.txt") != ok { os.exit(31i32) }
    let (removed, removed_error) = saw(a, removing, .Removed, "seen.txt")
    if removed_error != ok { os.exit(32i32) }
    if !removed { os.exit(33i32) }
    if os.watch_close(removing) != ok { os.exit(34i32) }
    if os.remove_dir(a, "np-watch") != ok { os.exit(41i32) }
    ret ok
}
