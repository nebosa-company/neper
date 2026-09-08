// `e.os`'s filesystem primitives, which are the ones `e.fs` is built on: `stat`,
// `lstat`, `mkdir`, `remove_file`, `remove_dir` and `rename`. They are written per
// target -- over `os.syscall` on Linux, over `kernel32` on Windows -- so what this
// fixture is for is that both spellings answer the same questions the same way.
//
// Every path is relative, so the runner's working directory decides where the
// scratch entries land and nothing here writes outside it.

use e.mem
use e.os

// 2020-01-01 and 2100-01-01 in Unix nanoseconds. Every timestamp is checked against
// both, because the interesting failures are not zero: a `FILETIME` that kept its
// 1601 epoch lands past 2100 or wraps negative, and one that was not scaled from
// 100-nanosecond ticks lands in 1970.
const YEAR_2020_NS: i64 = 1577836800000000000i64
const YEAR_2100_NS: i64 = 4102444800000000000i64

// Whole seconds, so the round trip is exact wherever it runs: one of the filesystems this
// suite uses keeps seconds and drops the nanoseconds, which is precision it never
// promised and not what these assertions are about.
const STAMP_ACCESSED: i64 = 1700000000000000000i64
const STAMP_MODIFIED: i64 = 1700000060000000000i64
const STAMP_SECOND: i64 = 1700000120000000000i64

fn same_text(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn main(a: *mem.Arena) -> err {
    // A directory that does not exist is `NotFound`, not a crash and not a zeroed
    // answer that a caller could mistake for an empty file.
    let (absent, absent_error) = os.stat(a, "np-os-fs-absent")
    if absent_error != os.NotFound { os.exit(10i32) }

    // The current directory is a directory. Reading `kind` at all proves the mode
    // came out of the right place: on Linux that is offset 24 of the kernel's
    // 144-byte buffer, on Windows the attribute word.
    let (here, here_error) = os.stat(a, ".")
    if here_error != ok { os.exit(11i32) }
    if here.kind != .Dir { os.exit(12i32) }

    // mkdir, and the same call again reporting `Exists` rather than succeeding.
    if os.mkdir(a, "np-os-fs-dir") != ok { os.exit(20i32) }
    if os.mkdir(a, "np-os-fs-dir") != os.Exists { os.exit(21i32) }
    let (made, made_error) = os.stat(a, "np-os-fs-dir")
    if made_error != ok { os.exit(22i32) }
    if made.kind != .Dir { os.exit(23i32) }

    // A directory is not a file: removing it as one fails, which is what keeps
    // `remove_file` and `remove_dir` two calls rather than one.
    if os.remove_file(a, "np-os-fs-dir") == ok { os.exit(24i32) }

    // A file with known contents, so `size` is checkable rather than merely present.
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.truncate = true
    let (file, open_error) = os.open(a, "np-os-fs-dir/note.txt", flags)
    if open_error != ok { os.exit(30i32) }
    var payload: [5]u8 = zero
    payload[0usize] = 104u8
    payload[1usize] = 101u8
    payload[2usize] = 108u8
    payload[3usize] = 108u8
    payload[4usize] = 111u8
    let (written, write_error) = os.write(file, payload[..])
    if write_error != ok { os.exit(31i32) }
    if written != 5usize { os.exit(32i32) }
    if os.close(file) != ok { os.exit(33i32) }

    let (note, note_error) = os.stat(a, "np-os-fs-dir/note.txt")
    if note_error != ok { os.exit(34i32) }
    if note.kind != .File { os.exit(35i32) }
    if note.size != 5u64 { os.exit(36i32) }

    // With no symlink in the way, `lstat` and `stat` agree -- which is the case that
    // says the flag reached the call rather than that it changed anything.
    let (note_link, note_link_error) = os.lstat(a, "np-os-fs-dir/note.txt")
    if note_link_error != ok { os.exit(37i32) }
    if note_link.kind != .File { os.exit(38i32) }
    if note_link.size != 5u64 { os.exit(39i32) }

    // The widened `FileInfo`. A fresh file has exactly one link and an identity, and its
    // times are real Unix nanosecond counts -- on Linux read off the kernel's structure,
    // on Windows converted from a 1601-based tick count, which is where an epoch that
    // was not translated would show up.
    if note.link_count != 1u64 { os.exit(60i32) }
    if note.file_id == 0u64 { os.exit(61i32) }
    if note.modified_ns < YEAR_2020_NS || note.modified_ns > YEAR_2100_NS { os.exit(62i32) }
    if note.accessed_ns < YEAR_2020_NS || note.accessed_ns > YEAR_2100_NS { os.exit(63i32) }
    // Owner read and write, which both hosts agree on. The group and other bits do not
    // survive the translation -- one host has no such notion -- so they are not asserted.
    if note.mode & 256u32 == 0u32 { os.exit(64i32) }
    if note.mode & 128u32 == 0u32 { os.exit(65i32) }
    // A creation time is either recorded or `-1`. It is never a zero, which a caller
    // would read as 1970 rather than as absent.
    if note.created_ns != -1i64 {
        if note.created_ns < YEAR_2020_NS || note.created_ns > YEAR_2100_NS { os.exit(66i32) }
    }

    // The identity belongs to the file and not to the call: the same path twice, and the
    // link and its target where there is no link, all give one answer.
    let (again, again_error) = os.stat(a, "np-os-fs-dir/note.txt")
    if again_error != ok { os.exit(67i32) }
    if again.file_id != note.file_id { os.exit(68i32) }
    if note_link.file_id != note.file_id { os.exit(69i32) }
    // Two different objects are two different identities.
    if here.file_id == note.file_id { os.exit(70i32) }

    // A directory is traversable, which is the one permission bit a host with no POSIX
    // mode still has to synthesise.
    if made.mode & 64u32 == 0u32 { os.exit(71i32) }

    // Writing the stamps back, and reading them through the same `stat` that reported
    // them: on Linux a `timespec` pair the kernel reads at an address, on Windows two
    // `FILETIME`s through a handle opened for writing attributes.
    if os.set_times(a, "np-os-fs-dir/note.txt", STAMP_ACCESSED, STAMP_MODIFIED) != ok { os.exit(72i32) }
    let (stamped, stamped_error) = os.stat(a, "np-os-fs-dir/note.txt")
    if stamped_error != ok { os.exit(73i32) }
    if stamped.modified_ns != STAMP_MODIFIED { os.exit(74i32) }
    if stamped.accessed_ns != STAMP_ACCESSED { os.exit(75i32) }

    // A negative stamp leaves that one as it was, which is how one of the two is set by
    // itself -- `UTIME_OMIT` on one host, a null pointer on the other.
    if os.set_times(a, "np-os-fs-dir/note.txt", -1i64, STAMP_SECOND) != ok { os.exit(76i32) }
    let (restamped, restamped_error) = os.stat(a, "np-os-fs-dir/note.txt")
    if restamped_error != ok { os.exit(77i32) }
    if restamped.modified_ns != STAMP_SECOND { os.exit(78i32) }
    if restamped.accessed_ns != STAMP_ACCESSED { os.exit(79i32) }

    // Taking the write bit away and giving it back. Both directions are checked, because
    // a call that did nothing at all would pass either one alone.
    if os.set_mode(a, "np-os-fs-dir/note.txt", 256u32) != ok { os.exit(80i32) }
    let (locked, locked_error) = os.stat(a, "np-os-fs-dir/note.txt")
    if locked_error != ok { os.exit(81i32) }
    if locked.mode & 128u32 != 0u32 { os.exit(82i32) }
    if locked.mode & 256u32 == 0u32 { os.exit(83i32) }
    if os.set_mode(a, "np-os-fs-dir/note.txt", 438u32) != ok { os.exit(84i32) }
    let (freed, freed_error) = os.stat(a, "np-os-fs-dir/note.txt")
    if freed_error != ok { os.exit(85i32) }
    if freed.mode & 128u32 == 0u32 { os.exit(86i32) }

    // Neither call succeeds quietly on a path that is not there.
    if os.set_times(a, "np-os-fs-absent", STAMP_ACCESSED, STAMP_MODIFIED) != os.NotFound { os.exit(87i32) }
    if os.set_mode(a, "np-os-fs-absent", 438u32) != os.NotFound { os.exit(88i32) }

    // A symbolic link, where the host lets one be made at all. On Windows that needs
    // developer mode or an elevated process, and a refusal comes back as `Denied` rather
    // than as a broken call -- so that one answer, and only that one, skips what follows.
    // Any other error still fails, and so does a link that reads back wrong.
    let link_error = os.symlink(a, "note.txt", "np-os-fs-dir/link.txt")
    if link_error == ok {
        // `lstat` describes the link and `stat` describes what it leads to, which is the
        // pair that has no meaning until there is a link to try it on.
        let (as_link, as_link_error) = os.lstat(a, "np-os-fs-dir/link.txt")
        if as_link_error != ok { os.exit(89i32) }
        if as_link.kind != .Symlink { os.exit(90i32) }
        let (through, through_error) = os.stat(a, "np-os-fs-dir/link.txt")
        if through_error != ok { os.exit(91i32) }
        if through.kind != .File { os.exit(92i32) }
        if through.size != 5u64 { os.exit(93i32) }
        // The identity is the target's: following the link reaches the same object.
        if through.file_id != again.file_id { os.exit(94i32) }

        // The target is the string that was stored, not a path that was resolved.
        let (stored, stored_error) = os.read_link(a, "np-os-fs-dir/link.txt")
        if stored_error != ok { os.exit(95i32) }
        if !same_text(stored, "note.txt") { os.exit(96i32) }

        // Removing a link removes the link and leaves what it pointed at.
        if os.remove_file(a, "np-os-fs-dir/link.txt") != ok { os.exit(97i32) }
        let (survivor, survivor_error) = os.stat(a, "np-os-fs-dir/note.txt")
        if survivor_error != ok { os.exit(98i32) }
        if survivor.size != 5u64 { os.exit(99i32) }
    } else {
        if link_error != os.Denied { os.exit(100i32) }
    }

    // Asking a plain file what it links to is refused, and refused the same way on both
    // hosts -- EINVAL on one, ERROR_NOT_A_REPARSE_POINT on the other.
    let (not_a_link, not_a_link_error) = os.read_link(a, "np-os-fs-dir/note.txt")
    if not_a_link_error != os.Unsupported { os.exit(101i32) }
    // And so is one that is not there at all, which is a different answer again.
    let (no_link, no_link_error) = os.read_link(a, "np-os-fs-absent")
    if no_link_error != os.NotFound { os.exit(102i32) }

    // A non-empty directory does not go away, so the file is removed first.
    if os.remove_dir(a, "np-os-fs-dir") == ok { os.exit(40i32) }

    // Renaming a file: the new name has it, the old name has nothing.
    if os.rename(a, "np-os-fs-dir/note.txt", "np-os-fs-dir/moved.txt") != ok { os.exit(41i32) }
    let (moved, moved_error) = os.stat(a, "np-os-fs-dir/moved.txt")
    if moved_error != ok { os.exit(42i32) }
    if moved.size != 5u64 { os.exit(43i32) }
    let (gone, gone_error) = os.stat(a, "np-os-fs-dir/note.txt")
    if gone_error != os.NotFound { os.exit(44i32) }

    // Renaming from a name that is not there fails, and fails as `NotFound`.
    if os.rename(a, "np-os-fs-absent", "np-os-fs-dir/other.txt") != os.NotFound { os.exit(45i32) }

    // Clean up, and the removals report what they did rather than being assumed.
    if os.remove_file(a, "np-os-fs-dir/moved.txt") != ok { os.exit(50i32) }
    if os.remove_file(a, "np-os-fs-dir/moved.txt") != os.NotFound { os.exit(51i32) }
    if os.remove_dir(a, "np-os-fs-dir") != ok { os.exit(52i32) }
    if os.remove_dir(a, "np-os-fs-dir") != os.NotFound { os.exit(53i32) }
    ret ok
}
