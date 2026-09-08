// `e.fs` end to end on a real filesystem. Every path is relative, so the runner's
// working directory decides where these entries land and nothing here writes outside
// it. The same source runs on both hosts: what differs is behind `e.os`, and this
// fixture is what says the two behave alike.

use e.mem
use e.fs
use e.os

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

// A previous failing run leaves its scratch behind, and `Exists` from that would fail
// the next run for a reason that is not the one being tested.
fn clear(a: *mem.Arena) {
    let leaf = fs.remove_file(a, "np-fs/deep/leaf.txt")
    let one = fs.remove_file(a, "np-fs/one.txt")
    let two = fs.remove_file(a, "np-fs/two.txt")
    let copy = fs.remove_file(a, "np-fs/copy.txt")
    let deep = fs.remove_dir(a, "np-fs/deep")
    let outer = fs.remove_dir(a, "np-fs")
}

fn main(a: *mem.Arena) -> err {
    clear(a)

    // `exists` answers rather than failing: a missing path is `false` with no error,
    // which is the whole reason it is not just `stat`.
    let (absent, absent_error) = fs.exists(a, "np-fs")
    if absent_error != ok { os.exit(10i32) }
    if absent { os.exit(11i32) }

    // The same missing path is `NotFound` from `stat`, where the question was different.
    let (nothing, nothing_error) = fs.stat(a, "np-fs")
    if nothing_error != fs.NotFound { os.exit(12i32) }

    // `make_dirs` makes every missing component, so one call covers two levels.
    if fs.make_dirs(a, "np-fs/deep") != ok { os.exit(20i32) }
    let (outer, outer_error) = fs.stat(a, "np-fs")
    if outer_error != ok { os.exit(21i32) }
    if outer.kind != .Directory { os.exit(22i32) }
    let (inner, inner_error) = fs.stat(a, "np-fs/deep")
    if inner_error != ok { os.exit(23i32) }
    if inner.kind != .Directory { os.exit(24i32) }

    // Run again: every component is already a directory, which `make_dirs` accepts and
    // `make_dir` does not.
    if fs.make_dirs(a, "np-fs/deep") != ok { os.exit(25i32) }
    if fs.make_dir(a, "np-fs/deep") != fs.Exists { os.exit(26i32) }

    // Write and read back, byte for byte.
    var payload: [11]u8 = zero
    payload[0usize] = 104u8
    payload[1usize] = 101u8
    payload[2usize] = 108u8
    payload[3usize] = 108u8
    payload[4usize] = 111u8
    payload[5usize] = 32u8
    payload[6usize] = 119u8
    payload[7usize] = 111u8
    payload[8usize] = 114u8
    payload[9usize] = 108u8
    payload[10usize] = 100u8
    if fs.write_file(a, "np-fs/one.txt", payload[..]) != ok { os.exit(30i32) }
    let (read_back, read_error) = fs.read_file(a, "np-fs/one.txt", 0usize)
    if read_error != ok { os.exit(31i32) }
    if read_back.len != 11usize { os.exit(32i32) }
    var at = 0usize
    while at < 11usize {
        if read_back[at] != payload[at] { os.exit(33i32) }
        at += 1usize
    }

    // The size the host reports is the size that was written.
    let (written_entry, written_error) = fs.stat(a, "np-fs/one.txt")
    if written_error != ok { os.exit(34i32) }
    if written_entry.kind != .File { os.exit(35i32) }
    if written_entry.size != 11u64 { os.exit(36i32) }

    // A limit smaller than the file is refused rather than silently truncating, and a
    // limit large enough is not.
    let (capped, capped_error) = fs.read_file(a, "np-fs/one.txt", 10usize)
    if capped_error != fs.Invalid { os.exit(37i32) }
    let (allowed, allowed_error) = fs.read_file(a, "np-fs/one.txt", 11usize)
    if allowed_error != ok { os.exit(38i32) }
    if allowed.len != 11usize { os.exit(39i32) }

    // A directory is not a file to read.
    let (as_file, as_file_error) = fs.read_file(a, "np-fs", 0usize)
    if as_file_error != fs.Invalid { os.exit(40i32) }

    // Truncation: a second write replaces what the first put there rather than adding
    // to it.
    var shorter: [3]u8 = zero
    shorter[0usize] = 97u8
    shorter[1usize] = 98u8
    shorter[2usize] = 99u8
    if fs.write_file(a, "np-fs/one.txt", shorter[..]) != ok { os.exit(41i32) }
    let (shortened, shortened_error) = fs.stat(a, "np-fs/one.txt")
    if shortened_error != ok { os.exit(42i32) }
    if shortened.size != 3u64 { os.exit(43i32) }

    // Copy through a buffer smaller than the file, so the loop runs more than once.
    if fs.write_file(a, "np-fs/one.txt", payload[..]) != ok { os.exit(44i32) }
    var scratch: [4]u8 = zero
    if fs.copy_file(a, "np-fs/one.txt", "np-fs/copy.txt", scratch[..]) != ok { os.exit(45i32) }
    let (copied, copied_error) = fs.read_file(a, "np-fs/copy.txt", 0usize)
    if copied_error != ok { os.exit(46i32) }
    if copied.len != 11usize { os.exit(47i32) }
    at = 0usize
    while at < 11usize {
        if copied[at] != payload[at] { os.exit(48i32) }
        at += 1usize
    }
    // A buffer with no room would make no progress, so it is an error and not a hang.
    var empty: []u8 = zero
    if fs.copy_file(a, "np-fs/one.txt", "np-fs/two.txt", empty) != fs.Invalid { os.exit(49i32) }

    // Move: the new name has the bytes and the old name has nothing.
    if fs.move(a, "np-fs/copy.txt", "np-fs/two.txt") != ok { os.exit(50i32) }
    let (moved, moved_error) = fs.stat(a, "np-fs/two.txt")
    if moved_error != ok { os.exit(51i32) }
    if moved.size != 11u64 { os.exit(52i32) }
    let (vanished, vanished_error) = fs.exists(a, "np-fs/copy.txt")
    if vanished_error != ok { os.exit(53i32) }
    if vanished { os.exit(54i32) }

    // A walk of one level: two files and one directory, and nothing from inside it.
    if fs.write_file(a, "np-fs/deep/leaf.txt", shorter[..]) != ok { os.exit(60i32) }
    var flat: fs.WalkOptions = zero
    let (shallow, shallow_error) = fs.walk(a, "np-fs", flat)
    if shallow_error != ok { os.exit(61i32) }
    var shallow_walk = shallow
    var files = 0usize
    var directories = 0usize
    while true {
        let (entry, more, walk_error) = fs.walk_next_err(&shallow_walk)
        if walk_error != ok { os.exit(62i32) }
        if !more { break }
        if entry.kind == .File { files += 1usize }
        if entry.kind == .Directory { directories += 1usize }
    }
    if files != 2usize { os.exit(63i32) }
    if directories != 1usize { os.exit(64i32) }
    if fs.walk_close(&shallow_walk) != ok { os.exit(65i32) }

    // The same tree walked recursively finds the one inside `deep` as well, and its
    // path is the full one rather than the bare name.
    var deep_options: fs.WalkOptions = zero
    deep_options.recursive = true
    let (deep_start, deep_error) = fs.walk(a, "np-fs", deep_options)
    if deep_error != ok { os.exit(70i32) }
    var deep_walk = deep_start
    var deep_files = 0usize
    var leaf_seen = false
    var leaf_size = 0u64
    while true {
        let (entry, more, walk_error) = fs.walk_next_err(&deep_walk)
        if walk_error != ok { os.exit(71i32) }
        if !more { break }
        if entry.kind == .File { deep_files += 1usize }
        if entry.path.len > 8usize {
            let tail = entry.path[entry.path.len - 8usize..entry.path.len]
            if same(tail, "leaf.txt") {
                leaf_seen = true
                leaf_size = entry.size
            }
        }
    }
    if deep_files != 3usize { os.exit(72i32) }
    if !leaf_seen { os.exit(73i32) }
    if leaf_size != 3u64 { os.exit(74i32) }
    if fs.walk_close(&deep_walk) != ok { os.exit(75i32) }

    // A non-empty directory stays, so a recursive delete is the caller's to write.
    if fs.remove_dir(a, "np-fs") == ok { os.exit(80i32) }
    if fs.remove_file(a, "np-fs/deep/leaf.txt") != ok { os.exit(81i32) }
    if fs.remove_dir(a, "np-fs/deep") != ok { os.exit(82i32) }
    if fs.remove_file(a, "np-fs/one.txt") != ok { os.exit(83i32) }
    if fs.remove_file(a, "np-fs/two.txt") != ok { os.exit(84i32) }
    if fs.remove_dir(a, "np-fs") != ok { os.exit(85i32) }
    let (finally, finally_error) = fs.exists(a, "np-fs")
    if finally_error != ok { os.exit(86i32) }
    if finally { os.exit(87i32) }
    ret ok
}
