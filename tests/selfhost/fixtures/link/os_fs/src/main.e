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

// A leading separator, or a drive letter and a colon: the two ways a path on either host
// does not depend on where it is read from.
fn rooted_path(text: str) -> bool {
    if text.len == 0usize { ret false }
    if text[0usize] == 47u8 || text[0usize] == 92u8 { ret true }
    if text.len >= 2usize && text[1usize] == 58u8 { ret true }
    ret false
}

// A file of `count` bytes, all the same, so a size is enough to tell two of them apart.
fn write_file_of(a: *mem.Arena, path: str, count: usize, fill: u8) -> err {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.truncate = true
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret open_error }
    var payload: [8]u8 = zero
    var at = 0usize
    while at < count {
        payload[at] = fill
        at += 1usize
    }
    let (written, write_error) = os.write(file, payload[0usize..count])
    let close_error = os.close(file)
    if write_error != ok { ret write_error }
    if written != count { ret os.Failed }
    ret close_error
}

// A run that failed part way leaves its scratch behind, and the very first thing this
// fixture does is make a directory -- which would then fail as `Exists` for a reason that
// has nothing to do with what is being tested. Every name this file creates is removed
// here first, and the results are ignored because most of them are not there.
fn clear(a: *mem.Arena) {
    let note = os.remove_file(a, "np-os-fs-dir/note.txt")
    let moved = os.remove_file(a, "np-os-fs-dir/moved.txt")
    let link = os.remove_file(a, "np-os-fs-dir/link.txt")
    let fresh = os.remove_file(a, "np-os-fs-dir/fresh.txt")
    let source = os.remove_file(a, "np-os-fs-dir/source.txt")
    let destination = os.remove_file(a, "np-os-fs-dir/target.txt")
    let landed = os.remove_file(a, "np-os-fs-dir/landed.txt")
    let inner = os.remove_file(a, "np-os-fs-dir/sub/inner.txt")
    let via_file = os.remove_file(a, "np-os-fs-dir/viasub")
    let via_dir = os.remove_dir(a, "np-os-fs-dir/viasub")
    let sub = os.remove_dir(a, "np-os-fs-dir/sub")
    let gone = os.remove_file(a, "np-os-fs-dir/gone.txt")
    let before = os.remove_file(a, "np-os-fs-dir/before.txt")
    let after = os.remove_file(a, "np-os-fs-dir/after.txt")
    let landed_at = os.remove_file(a, "np-os-fs-dir/landed_at.txt")
    let directory = os.remove_dir(a, "np-os-fs-dir")
}

fn main(a: *mem.Arena) -> err {
    clear(a)

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

        // Resolving is what `canonical` is for, and a link is the only thing that makes
        // the question interesting: naming the link and naming its target are one answer.
        let (through_link, through_link_error) = os.canonical(a, "np-os-fs-dir/link.txt")
        if through_link_error != ok { os.exit(139i32) }
        let (through_name, through_name_error) = os.canonical(a, "np-os-fs-dir/note.txt")
        if through_name_error != ok { os.exit(140i32) }
        if !same_text(through_link, through_name) { os.exit(141i32) }

        // A link that leads out of the directory is what `Beneath` is for. The host
        // enforces it while it walks, or says it cannot -- and either is an answer. What
        // would not be an answer is opening it.
        if os.symlink(a, "../np-os-fs-absent", "np-os-fs-dir/escape.txt") == ok {
            let (escape_root, escape_root_error) = os.dir_open(a, "np-os-fs-dir")
            if escape_root_error != ok { os.exit(189i32) }
            var escape_flags: os.OpenFlags = zero
            escape_flags.read = true
            let (escaped, escaped_error) = os.open_at(a, escape_root, "escape.txt", escape_flags, .Beneath)
            if escaped_error == ok { os.exit(190i32) }
            if escaped_error != os.Denied && escaped_error != os.Unsupported { os.exit(191i32) }
            // And a link is refused outright under `NoSymlinks`, on every host.
            let (linked, linked_error) = os.open_at(a, escape_root, "link.txt", escape_flags, .NoSymlinks)
            if linked_error != os.Denied { os.exit(192i32) }
            if os.dir_close(escape_root) != ok { os.exit(193i32) }
            if os.remove_file(a, "np-os-fs-dir/escape.txt") != ok { os.exit(194i32) }
        }

        // A link in the middle of a path is refused by the calls that act on a name, which
        // is the whole reason those calls resolve the parent separately: the walk to the
        // final component follows nothing, even though the final component itself may be a
        // link and is removed as one.
        if os.mkdir(a, "np-os-fs-dir/sub") == ok {
            if write_file_of(a, "np-os-fs-dir/sub/inner.txt", 3usize, 105u8) != ok { os.exit(220i32) }
            if os.symlink(a, "sub", "np-os-fs-dir/viasub") == ok {
                let (via_root, via_root_error) = os.dir_open(a, "np-os-fs-dir")
                if via_root_error != ok { os.exit(221i32) }

                // Straight through the real directory is fine, so the refusal below is
                // about the link and not about the depth.
                if os.remove_at(a, via_root, "sub/inner.txt", false) != ok { os.exit(222i32) }
                if write_file_of(a, "np-os-fs-dir/sub/inner.txt", 3usize, 105u8) != ok { os.exit(223i32) }

                // The same file named through the link is refused, by both calls.
                if os.remove_at(a, via_root, "viasub/inner.txt", false) != os.Denied { os.exit(224i32) }
                if os.rename_at(a, via_root, "viasub/inner.txt", via_root, "escaped.txt", true, false) != os.Denied { os.exit(225i32) }
                // And the file is still there, which says the refusal happened before
                // anything was done rather than after.
                let (still_inner, still_inner_error) = os.stat(a, "np-os-fs-dir/sub/inner.txt")
                if still_inner_error != ok { os.exit(226i32) }
                if still_inner.size != 3u64 { os.exit(227i32) }

                if os.dir_close(via_root) != ok { os.exit(228i32) }
                // A link to a directory is removed as a directory on one host and as a
                // file on the other, which is a difference in what the name is rather than
                // in what is being asked for.
                if os.remove_file(a, "np-os-fs-dir/viasub") != ok {
                    if os.remove_dir(a, "np-os-fs-dir/viasub") != ok { os.exit(229i32) }
                }
            }
            if os.remove_file(a, "np-os-fs-dir/sub/inner.txt") != ok { os.exit(230i32) }
            if os.remove_dir(a, "np-os-fs-dir/sub") != ok { os.exit(231i32) }
        }

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

    // The working directory: absolute, and the one the relative paths above have been
    // resolving against. It is process-wide state rather than anything about a path, so
    // everything here puts it back before moving on.
    let (base, base_error) = os.current_dir(a)
    if base_error != ok { os.exit(103i32) }
    if base.len == 0usize { os.exit(104i32) }
    var absolute = false
    if base[0usize] == 47u8 || base[0usize] == 92u8 { absolute = true }
    if base.len >= 2usize && base[1usize] == 58u8 { absolute = true }
    if !absolute { os.exit(105i32) }

    // Moving into the directory made above: `current_dir` follows, and it follows by
    // naming that directory rather than by changing length.
    if os.set_current_dir(a, "np-os-fs-dir") != ok { os.exit(106i32) }
    let (inside, inside_error) = os.current_dir(a)
    if inside_error != ok { os.exit(107i32) }
    if inside.len < 12usize { os.exit(108i32) }
    if inside.len <= base.len { os.exit(109i32) }
    if !same_text(inside[inside.len - 12usize..inside.len], "np-os-fs-dir") { os.exit(110i32) }

    // And the relative paths really did move with it: this is the file made earlier,
    // named without its directory this time.
    let (from_inside, from_inside_error) = os.stat(a, "note.txt")
    if from_inside_error != ok { os.exit(111i32) }
    if from_inside.size != 5u64 { os.exit(112i32) }

    // Back, by the absolute path the first call gave -- which is the round trip that says
    // what `current_dir` returns is something `set_current_dir` accepts.
    if os.set_current_dir(a, base) != ok { os.exit(113i32) }
    let (restored, restored_error) = os.current_dir(a)
    if restored_error != ok { os.exit(114i32) }
    if !same_text(restored, base) { os.exit(115i32) }

    // A directory that is not there is not entered, and the failure leaves us where we
    // were rather than somewhere unnamed.
    if os.set_current_dir(a, "np-os-fs-absent") != os.NotFound { os.exit(116i32) }
    let (unmoved, unmoved_error) = os.current_dir(a)
    if unmoved_error != ok { os.exit(117i32) }
    if !same_text(unmoved, base) { os.exit(118i32) }

    // The path of the running program. It is the one answer here the fixture cannot know
    // in advance, so what it checks is what has to be true of it whatever it is: absolute,
    // stable, and naming a file that is there and has bytes -- this one.
    let (program, program_error) = os.executable_path(a)
    if program_error != ok { os.exit(119i32) }
    if program.len == 0usize { os.exit(120i32) }
    var program_absolute = false
    if program[0usize] == 47u8 || program[0usize] == 92u8 { program_absolute = true }
    if program.len >= 2usize && program[1usize] == 58u8 { program_absolute = true }
    if !program_absolute { os.exit(121i32) }
    let (image, image_error) = os.stat(a, program)
    if image_error != ok { os.exit(122i32) }
    if image.kind != .File { os.exit(123i32) }
    if image.size == 0u64 { os.exit(124i32) }
    let (program_again, program_again_error) = os.executable_path(a)
    if program_again_error != ok { os.exit(125i32) }
    if !same_text(program_again, program) { os.exit(126i32) }

    // The environment, which is where the two directories `e.fs` names come from. `PATH`
    // is set for every process on both hosts, so it is the one name that can be asked for
    // without arranging anything first.
    let (search_path, search_path_error) = os.env(a, "PATH")
    if search_path_error != ok { os.exit(127i32) }
    if search_path.len == 0usize { os.exit(128i32) }

    // A name nothing set is `NotFound` and not an empty answer, which is the whole reason
    // this returns an error rather than a string.
    let (unset, unset_error) = os.env(a, "NP_OS_FS_NOT_SET_ANYWHERE")
    if unset_error != os.NotFound { os.exit(129i32) }

    // A longer name that begins with a real one is not that one: a lookup that compared
    // only as far as the stored name reaches would answer this with `PATH`'s value.
    let (overrun, overrun_error) = os.env(a, "PATHH")
    if overrun_error != os.NotFound { os.exit(130i32) }

    // And the empty name matches nothing, where a record split at the first `=` with no
    // length check would match the first entry.
    let (empty_name, empty_name_error) = os.env(a, "")
    if empty_name_error != os.NotFound { os.exit(131i32) }

    // The resolved path. The fixture cannot know what it is, so it checks what has to be
    // true of it: absolute, in a form anyone would call a path, and the same for two
    // spellings of one place.
    let (resolved_dir, resolved_dir_error) = os.canonical(a, "np-os-fs-dir")
    if resolved_dir_error != ok { os.exit(132i32) }
    if !rooted_path(resolved_dir) { os.exit(133i32) }
    // Not the extended-length form one host answers in, which is correct and is not what
    // anybody means by a path.
    if resolved_dir.len >= 4usize {
        if resolved_dir[0usize] == 92u8 && resolved_dir[1usize] == 92u8 {
            if resolved_dir[2usize] == 63u8 && resolved_dir[3usize] == 92u8 { os.exit(134i32) }
        }
    }

    // The same directory named the long way round is the same directory.
    let (resolved_round, resolved_round_error) = os.canonical(a, "np-os-fs-dir/../np-os-fs-dir")
    if resolved_round_error != ok { os.exit(135i32) }
    if !same_text(resolved_round, resolved_dir) { os.exit(136i32) }

    // A file inside it resolves to something longer that begins with it.
    let (resolved_note, resolved_note_error) = os.canonical(a, "np-os-fs-dir/note.txt")
    if resolved_note_error != ok { os.exit(137i32) }
    if resolved_note.len <= resolved_dir.len { os.exit(138i32) }
    if !same_text(resolved_note[0usize..resolved_dir.len], resolved_dir) { os.exit(142i32) }

    // A name that leads nowhere has nothing to resolve.
    let (no_resolve, no_resolve_error) = os.canonical(a, "np-os-fs-absent")
    if no_resolve_error != os.NotFound { os.exit(143i32) }

    // Randomness, which is what keeps a temporary name from being guessable. Two draws
    // differ, and neither is the zeroed buffer a call that wrote nothing would leave.
    var first_draw: [16]u8 = zero
    var second_draw: [16]u8 = zero
    if os.random(first_draw[..]) != ok { os.exit(144i32) }
    if os.random(second_draw[..]) != ok { os.exit(145i32) }
    var identical = true
    var draw_at = 0usize
    while draw_at < 16usize {
        if first_draw[draw_at] != second_draw[draw_at] { identical = false }
        draw_at += 1usize
    }
    if identical { os.exit(146i32) }
    var all_zero = true
    draw_at = 0usize
    while draw_at < 16usize {
        if first_draw[draw_at] != 0u8 { all_zero = false }
        draw_at += 1usize
    }
    if all_zero { os.exit(147i32) }
    // Asking for nothing is not a failure.
    var no_bytes: []u8 = zero
    if os.random(no_bytes) != ok { os.exit(148i32) }

    // `create_new` makes a file that was not there and refuses one that was, which is the
    // pair of answers that makes a name safe to hand out only after it has been taken.
    let (fresh, fresh_error) = os.create_new(a, "np-os-fs-dir/fresh.txt")
    if fresh_error != ok { os.exit(149i32) }
    // The handle it gives back is one the ordinary calls accept.
    var mark: [2]u8 = zero
    mark[0usize] = 111u8
    mark[1usize] = 107u8
    let (marked, marked_error) = os.write(fresh, mark[..])
    if marked_error != ok { os.exit(150i32) }
    if marked != 2usize { os.exit(151i32) }
    if os.close(fresh) != ok { os.exit(152i32) }
    let (taken, taken_error) = os.create_new(a, "np-os-fs-dir/fresh.txt")
    if taken_error != os.Exists { os.exit(153i32) }
    // And the second call left the first call's bytes alone rather than truncating them.
    let (fresh_entry, fresh_entry_error) = os.stat(a, "np-os-fs-dir/fresh.txt")
    if fresh_entry_error != ok { os.exit(154i32) }
    if fresh_entry.size != 2u64 { os.exit(155i32) }
    if os.remove_file(a, "np-os-fs-dir/fresh.txt") != ok { os.exit(156i32) }

    // `replace`. Two files of different sizes, so which one ended up where is readable
    // from the size alone.
    if write_file_of(a, "np-os-fs-dir/source.txt", 3usize, 115u8) != ok { os.exit(157i32) }
    if write_file_of(a, "np-os-fs-dir/target.txt", 6usize, 116u8) != ok { os.exit(158i32) }

    // Without overwriting, a destination that is there is refused -- and the source is
    // still where it was, because a refusal is not a partial move.
    if os.replace(a, "np-os-fs-dir/source.txt", "np-os-fs-dir/target.txt", false, false) != os.Exists { os.exit(159i32) }
    let (kept, kept_error) = os.stat(a, "np-os-fs-dir/source.txt")
    if kept_error != ok { os.exit(160i32) }
    if kept.size != 3u64 { os.exit(161i32) }
    let (untouched, untouched_error) = os.stat(a, "np-os-fs-dir/target.txt")
    if untouched_error != ok { os.exit(162i32) }
    if untouched.size != 6u64 { os.exit(163i32) }

    // With overwriting, the destination becomes the source and the source is gone.
    if os.replace(a, "np-os-fs-dir/source.txt", "np-os-fs-dir/target.txt", true, false) != ok { os.exit(164i32) }
    let (replaced, replaced_error) = os.stat(a, "np-os-fs-dir/target.txt")
    if replaced_error != ok { os.exit(165i32) }
    if replaced.size != 3u64 { os.exit(166i32) }
    let (moved_away, moved_away_error) = os.stat(a, "np-os-fs-dir/source.txt")
    if moved_away_error != os.NotFound { os.exit(167i32) }

    // Onto a free name without overwriting: the path a filesystem that does not know
    // `RENAME_NOREPLACE` has to reach by another route, so this is the case that says the
    // fallback works rather than that the flag does.
    if write_file_of(a, "np-os-fs-dir/source.txt", 5usize, 117u8) != ok { os.exit(168i32) }
    if os.replace(a, "np-os-fs-dir/source.txt", "np-os-fs-dir/landed.txt", false, false) != ok { os.exit(169i32) }
    let (landed, landed_error) = os.stat(a, "np-os-fs-dir/landed.txt")
    if landed_error != ok { os.exit(170i32) }
    if landed.size != 5u64 { os.exit(171i32) }
    let (source_gone, source_gone_error) = os.stat(a, "np-os-fs-dir/source.txt")
    if source_gone_error != os.NotFound { os.exit(172i32) }

    // Durable: the same move, waiting for the disk. What cannot be checked from here is
    // that it survives a crash; what can is that asking for it is not an error and does
    // not change where anything ended up.
    if os.replace(a, "np-os-fs-dir/landed.txt", "np-os-fs-dir/target.txt", true, true) != ok { os.exit(173i32) }
    let (durable_entry, durable_entry_error) = os.stat(a, "np-os-fs-dir/target.txt")
    if durable_entry_error != ok { os.exit(174i32) }
    if durable_entry.size != 5u64 { os.exit(175i32) }

    // A source that is not there is `NotFound` whichever way it is asked for.
    if os.replace(a, "np-os-fs-absent", "np-os-fs-dir/nowhere.txt", true, false) != os.NotFound { os.exit(176i32) }
    if os.replace(a, "np-os-fs-absent", "np-os-fs-dir/nowhere.txt", false, false) != os.NotFound { os.exit(177i32) }

    if os.remove_file(a, "np-os-fs-dir/target.txt") != ok { os.exit(178i32) }

    // A directory root_handle open, and names resolved against that handle rather than against a
    // string. This is the only family here whose guarantee is about what a name cannot
    // reach, so the refusals matter as much as the opens.
    let (root_handle, held_error) = os.dir_open(a, "np-os-fs-dir")
    if held_error != ok { os.exit(179i32) }
    var root_open_flags: os.OpenFlags = zero
    root_open_flags.read = true

    // A plain name under the directory opens, and reads what was written through it.
    let (under_root, under_root_error) = os.open_at(a, root_handle, "note.txt", root_open_flags, .NoSymlinks)
    if under_root_error != ok { os.exit(180i32) }
    var root_read_bytes: [8]u8 = zero
    let (root_read, root_read_error) = os.read(under_root, root_read_bytes[..])
    if root_read_error != ok { os.exit(181i32) }
    if root_read != 5usize { os.exit(182i32) }
    if os.close(under_root) != ok { os.exit(183i32) }

    // The three shapes that are refused before the host is asked at all: a name that
    // ignores the directory, one that leaves it, and one that is not a name.
    let (root_absolute, absolute_error) = os.open_at(a, root_handle, "/etc/hosts", root_open_flags, .NoSymlinks)
    if absolute_error != os.Denied { os.exit(184i32) }
    let (root_upward, upward_error) = os.open_at(a, root_handle, "../np-os-fs-absent", root_open_flags, .NoSymlinks)
    if upward_error != os.Denied { os.exit(185i32) }
    let (root_nameless, nameless_error) = os.open_at(a, root_handle, "", root_open_flags, .NoSymlinks)
    if nameless_error != os.Denied { os.exit(186i32) }

    // A name that is simply not there is `NotFound`, which is how the shape check is told
    // apart from the host's own answer.
    let (root_missing, missing_error) = os.open_at(a, root_handle, "not-here.txt", root_open_flags, .NoSymlinks)
    if missing_error != os.NotFound { os.exit(187i32) }

    // `..` inside a longer name is refused too, not only at the front.
    let (root_buried, buried_error) = os.open_at(a, root_handle, "sub/../../note.txt", root_open_flags, .NoSymlinks)
    if buried_error != os.Denied { os.exit(188i32) }


    // Removing and renaming through the handle. The same shape check applies, and the same
    // policy walks the path -- what is different is that the final component is acted on
    // rather than opened.
    if write_file_of(a, "np-os-fs-dir/gone.txt", 4usize, 103u8) != ok { os.exit(196i32) }
    if os.remove_at(a, root_handle, "gone.txt", false) != ok { os.exit(197i32) }
    let (removed, removed_error) = os.stat(a, "np-os-fs-dir/gone.txt")
    if removed_error != os.NotFound { os.exit(198i32) }

    // A file is not a directory and the call says so rather than removing it anyway.
    if write_file_of(a, "np-os-fs-dir/gone.txt", 4usize, 103u8) != ok { os.exit(199i32) }
    if os.remove_at(a, root_handle, "gone.txt", true) == ok { os.exit(200i32) }
    if os.remove_at(a, root_handle, "gone.txt", false) != ok { os.exit(201i32) }

    // The shapes are refused here too, before the host is asked.
    if os.remove_at(a, root_handle, "../np-os-fs-absent", false) != os.Denied { os.exit(202i32) }

    // Renaming within one root: the new name has it, the old name has nothing.
    if write_file_of(a, "np-os-fs-dir/before.txt", 7usize, 98u8) != ok { os.exit(203i32) }
    if os.rename_at(a, root_handle, "before.txt", root_handle, "after.txt", true, false) != ok { os.exit(204i32) }
    let (after_entry, after_entry_error) = os.stat(a, "np-os-fs-dir/after.txt")
    if after_entry_error != ok { os.exit(205i32) }
    if after_entry.size != 7u64 { os.exit(206i32) }
    let (before_entry, before_entry_error) = os.stat(a, "np-os-fs-dir/before.txt")
    if before_entry_error != os.NotFound { os.exit(207i32) }

    // Without overwriting, a destination that is there is refused and nothing moves.
    if write_file_of(a, "np-os-fs-dir/before.txt", 2usize, 99u8) != ok { os.exit(208i32) }
    if os.rename_at(a, root_handle, "before.txt", root_handle, "after.txt", false, false) != os.Exists { os.exit(209i32) }
    let (kept_after, kept_after_error) = os.stat(a, "np-os-fs-dir/after.txt")
    if kept_after_error != ok { os.exit(210i32) }
    if kept_after.size != 7u64 { os.exit(211i32) }

    // Onto a free name without overwriting, and durably -- the path that has to work where
    // the flag that says "refuse" is not understood.
    if os.rename_at(a, root_handle, "before.txt", root_handle, "landed_at.txt", false, true) != ok { os.exit(212i32) }
    let (landed_at, landed_at_error) = os.stat(a, "np-os-fs-dir/landed_at.txt")
    if landed_at_error != ok { os.exit(213i32) }
    if landed_at.size != 2u64 { os.exit(214i32) }

    // A source that is not there, and a shape that is refused.
    if os.rename_at(a, root_handle, "not-here.txt", root_handle, "x.txt", true, false) != os.NotFound { os.exit(215i32) }
    if os.rename_at(a, root_handle, "before.txt", root_handle, "/x.txt", true, false) != os.Denied { os.exit(216i32) }

    if os.remove_at(a, root_handle, "after.txt", false) != ok { os.exit(217i32) }
    if os.remove_at(a, root_handle, "landed_at.txt", false) != ok { os.exit(218i32) }

    if os.dir_close(root_handle) != ok { os.exit(195i32) }

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
