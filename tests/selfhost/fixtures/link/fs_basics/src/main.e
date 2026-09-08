// `e.fs` end to end on a real filesystem. Every path is relative, so the runner's
// working directory decides where these entries land and nothing here writes outside
// it. The same source runs on both hosts: what differs is behind `e.os`, and this
// fixture is what says the two behave alike.

use e.mem
use e.fs
use e.os

// 2020-01-01 and 2100-01-01 in Unix nanoseconds. A timestamp is checked against both:
// against zero it would pass while still carrying the wrong epoch or the wrong scale.
const YEAR_2020_NS: i64 = 1577836800000000000i64
const YEAR_2100_NS: i64 = 4102444800000000000i64

// Whole seconds, so the round trip is exact wherever it runs: one of the filesystems this
// suite uses keeps seconds and drops the nanoseconds, which is precision it never
// promised and not what these assertions are about.
const STAMP_ACCESSED: i64 = 1700000000000000000i64
const STAMP_MODIFIED: i64 = 1700000060000000000i64
const STAMP_SECOND: i64 = 1700000120000000000i64

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
    let link = fs.remove_file(a, "np-fs/link.txt")
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

    // `metadata` is everything the host records about one path, and `follow_symlinks`
    // picks which path that is. With no link in the way the two agree, which is what
    // says the flag reached the call rather than that it changed anything.
    let (described, described_error) = fs.metadata(a, "np-fs/one.txt", true)
    if described_error != ok { os.exit(90i32) }
    if described.kind != .File { os.exit(91i32) }
    if described.size != 11u64 { os.exit(92i32) }
    if described.link_count != 1u64 { os.exit(93i32) }
    if described.file_id == 0u64 { os.exit(94i32) }
    if !described.permissions.owner_read { os.exit(95i32) }
    if !described.permissions.owner_write { os.exit(96i32) }
    if described.modified_ns < YEAR_2020_NS || described.modified_ns > YEAR_2100_NS { os.exit(97i32) }
    if described.created_ns != -1i64 {
        if described.created_ns < YEAR_2020_NS || described.created_ns > YEAR_2100_NS { os.exit(98i32) }
    }
    let (direct, direct_error) = fs.metadata(a, "np-fs/one.txt", false)
    if direct_error != ok { os.exit(99i32) }
    if direct.file_id != described.file_id { os.exit(100i32) }

    // A directory is a directory and is traversable, and it is not the same object as
    // the file -- which is what an identity is for.
    let (folder, folder_error) = fs.metadata(a, "np-fs/deep", true)
    if folder_error != ok { os.exit(101i32) }
    if folder.kind != .Directory { os.exit(102i32) }
    if !folder.permissions.owner_exec { os.exit(103i32) }
    if folder.file_id == described.file_id { os.exit(104i32) }

    // A path that is not there fails the same way the rest of the module does.
    let (absent_metadata, absent_metadata_error) = fs.metadata(a, "np-fs/no-such", true)
    if absent_metadata_error != fs.NotFound { os.exit(105i32) }

    // `set_permissions` and `set_times` are the writing half, and `metadata` is how what
    // they did is read. Both directions of the write bit are checked: a call that changed
    // nothing would pass either one on its own.
    var read_only: fs.Permissions = zero
    read_only.owner_read = true
    if fs.set_permissions(a, "np-fs/one.txt", read_only) != ok { os.exit(110i32) }
    let (locked, locked_error) = fs.metadata(a, "np-fs/one.txt", true)
    if locked_error != ok { os.exit(111i32) }
    if locked.permissions.owner_write { os.exit(112i32) }
    if !locked.permissions.owner_read { os.exit(113i32) }
    var writable: fs.Permissions = zero
    writable.owner_read = true
    writable.owner_write = true
    if fs.set_permissions(a, "np-fs/one.txt", writable) != ok { os.exit(114i32) }
    let (freed, freed_error) = fs.metadata(a, "np-fs/one.txt", true)
    if freed_error != ok { os.exit(115i32) }
    if !freed.permissions.owner_write { os.exit(116i32) }

    if fs.set_times(a, "np-fs/one.txt", STAMP_ACCESSED, STAMP_MODIFIED) != ok { os.exit(117i32) }
    let (stamped, stamped_error) = fs.metadata(a, "np-fs/one.txt", true)
    if stamped_error != ok { os.exit(118i32) }
    if stamped.modified_ns != STAMP_MODIFIED { os.exit(119i32) }
    if stamped.accessed_ns != STAMP_ACCESSED { os.exit(120i32) }

    // One of the two alone: a negative stamp is left as it was.
    if fs.set_times(a, "np-fs/one.txt", -1i64, STAMP_SECOND) != ok { os.exit(121i32) }
    let (restamped, restamped_error) = fs.metadata(a, "np-fs/one.txt", true)
    if restamped_error != ok { os.exit(122i32) }
    if restamped.modified_ns != STAMP_SECOND { os.exit(123i32) }
    if restamped.accessed_ns != STAMP_ACCESSED { os.exit(124i32) }

    // Neither succeeds quietly on a path that is not there.
    if fs.set_permissions(a, "np-fs/no-such", writable) != fs.NotFound { os.exit(125i32) }
    if fs.set_times(a, "np-fs/no-such", STAMP_ACCESSED, STAMP_MODIFIED) != fs.NotFound { os.exit(126i32) }

    // A link through the module. Making one is privileged on some hosts, and `Denied` is
    // the one answer that skips what follows -- any other error, or a target that reads
    // back wrong, still fails.
    let symlink_error = fs.symlink(a, "one.txt", "np-fs/link.txt")
    if symlink_error == ok {
        let (stored, stored_error) = fs.read_link(a, "np-fs/link.txt")
        if stored_error != ok { os.exit(130i32) }
        if !same(stored, "one.txt") { os.exit(131i32) }
        // `follow_symlinks` is what decides which of the two is described.
        let (as_link, as_link_error) = fs.metadata(a, "np-fs/link.txt", false)
        if as_link_error != ok { os.exit(132i32) }
        if as_link.kind != .Symlink { os.exit(133i32) }
        let (through, through_error) = fs.metadata(a, "np-fs/link.txt", true)
        if through_error != ok { os.exit(134i32) }
        if through.kind != .File { os.exit(135i32) }
        if through.size != 11u64 { os.exit(136i32) }
        if through.file_id != described.file_id { os.exit(137i32) }
        if fs.remove_file(a, "np-fs/link.txt") != ok { os.exit(138i32) }
    } else {
        if symlink_error != fs.Denied { os.exit(139i32) }
    }

    // A path that is not a link has no target to give.
    let (not_a_link, not_a_link_error) = fs.read_link(a, "np-fs/one.txt")
    if not_a_link_error != fs.Invalid { os.exit(140i32) }

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
