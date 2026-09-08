// `e.os`'s filesystem primitives, which are the ones `e.fs` is built on: `stat`,
// `lstat`, `mkdir`, `remove_file`, `remove_dir` and `rename`. They are written per
// target -- over `os.syscall` on Linux, over `kernel32` on Windows -- so what this
// fixture is for is that both spellings answer the same questions the same way.
//
// Every path is relative, so the runner's working directory decides where the
// scratch entries land and nothing here writes outside it.

use e.mem
use e.os

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
