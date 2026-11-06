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
use e.str

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

    // A recursive watch is either made or refused outright; a host never pretends to watch the tree
    // and watches only the top.
    let (deep, deep_error) = os.watch_open(a, "np-watch", true)
    if deep_error == ok {
        let closed_deep = os.watch_close(deep)
        if closed_deep != ok { os.exit(11i32) }
    } else {
        if deep_error != os.Unsupported { os.exit(11i32) }
    }

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

    // Replacing a watched pathname changes its inode. The next write must still
    // wake the watch, which requires the macOS kqueue registration to move too.
    let (replacing, replacing_error) = os.watch_open(a, "np-watch", false)
    if replacing_error != ok { os.exit(24i32) }
    if write_file_of(a, "np-watch/replacement.txt", 98u8) != ok { os.exit(25i32) }
    if os.replace(a, "np-watch/replacement.txt", "np-watch/seen.txt", true, false) != ok { os.exit(26i32) }
    let (replaced, replaced_error) = saw(a, replacing, .Modified, "seen.txt")
    if replaced_error != ok || !replaced { os.exit(27i32) }
    if write_file_of(a, "np-watch/seen.txt", 99u8) != ok { os.exit(28i32) }
    let (rewritten, rewritten_error) = saw(a, replacing, .Modified, "seen.txt")
    if rewritten_error != ok || !rewritten { os.exit(29i32) }
    if os.watch_close(replacing) != ok { os.exit(30i32) }

    let (removing, removing_error) = os.watch_open(a, "np-watch", false)
    if removing_error != ok { os.exit(31i32) }
    if os.remove_file(a, "np-watch/seen.txt") != ok { os.exit(32i32) }
    let (removed, removed_error) = saw(a, removing, .Removed, "seen.txt")
    if removed_error != ok { os.exit(33i32) }
    if !removed { os.exit(34i32) }
    if os.watch_close(removing) != ok { os.exit(35i32) }

    // #733: a conversion failure must leave the watch armed; the next change
    // still has to arrive.
    let (failing, failing_error) = os.watch_open(a, "np-watch", false)
    if failing_error != ok { os.exit(36i32) }
    if write_file_of(a, "np-watch/before.txt", 120u8) != ok { os.exit(37i32) }
    let mark = mem.mark(a)
    var exhausted = false
    while !exhausted {
        let (chunk, chunk_error) = mem.alloc[u8](a, 1048576usize)
        if chunk_error != ok { exhausted = true }
    }
    var one: [1]os.WatchEvent = zero
    let (failed_count, failed_read) = os.watch_read(a, failing, one[..])
    if failed_read == ok || failed_count != 0usize { os.exit(38i32) }
    mem.reset(a, mark)
    if write_file_of(a, "np-watch/after.txt", 120u8) != ok { os.exit(39i32) }
    let (recovered, recovered_error) = saw(a, failing, .Added, "after.txt")
    if recovered_error != ok || !recovered { os.exit(40i32) }
    if os.watch_close(failing) != ok { os.exit(42i32) }

    // #1585: more entries than the macOS snapshot holds must signal Overflow rather than
    // silently missing a change to an untracked entry.
    if os.mkdir(a, "np-watch/many") != ok { os.exit(43i32) }
    var many_index = 0usize
    while many_index < 300usize {
        let (many_name, many_name_error) = str.builder(a, 64usize)
        if many_name_error != ok { os.exit(43i32) }
        var many_builder = many_name
        if str.push(&many_builder, "np-watch/many/f") != ok || str.push_u64(&many_builder, u64(many_index)) != ok { os.exit(43i32) }
        if write_file_of(a, str.done(&many_builder), 101u8) != ok { os.exit(43i32) }
        many_index += 1usize
    }
    let (many_watch, many_error) = os.watch_open(a, "np-watch", true)
    if many_error == ok {
        if write_file_of(a, "np-watch/many/f299", 102u8) != ok { os.exit(44i32) }
        var saw_many = false
        var saw_overflow = false
        var many_tries = 0usize
        while !saw_many && !saw_overflow && many_tries < 4usize {
            var many_events: [16]os.WatchEvent = zero
            let (many_count, many_read_error) = os.watch_read(a, many_watch, many_events[..])
            if many_read_error != ok { os.exit(44i32) }
            var many_at = 0usize
            while many_at < many_count {
                if many_events[many_at].action == .Overflow { saw_overflow = true }
                if ends_with(many_events[many_at].path, "f299") { saw_many = true }
                many_at += 1usize
            }
            many_tries += 1usize
        }
        if !saw_many && !saw_overflow { os.exit(45i32) }
        if os.watch_close(many_watch) != ok { os.exit(46i32) }
    } else {
        if many_error != os.Unsupported { os.exit(44i32) }
    }
    many_index = 0usize
    while many_index < 300usize {
        let (many_name, many_name_error) = str.builder(a, 64usize)
        if many_name_error != ok { os.exit(43i32) }
        var many_builder = many_name
        if str.push(&many_builder, "np-watch/many/f") != ok || str.push_u64(&many_builder, u64(many_index)) != ok { os.exit(43i32) }
        if os.remove_file(a, str.done(&many_builder)) != ok { os.exit(43i32) }
        many_index += 1usize
    }
    if os.remove_dir(a, "np-watch/many") != ok { os.exit(43i32) }
    if os.remove_dir(a, "np-watch") != ok { os.exit(41i32) }
    ret ok
}
