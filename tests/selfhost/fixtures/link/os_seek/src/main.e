// `os.seek` moves a file's cursor and reports where it landed. The three whences are
// checked against reads, so the position is confirmed by what comes back rather than
// by the number alone. The path to work in is the first argument, because this module
// reads no environment and picks no temporary directory of its own.

use e.mem
use e.os

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { ret Failed }
    let flags = os.OpenFlags { read: true, write: true, create: true, truncate: true, append: false }
    let (f, open_error) = os.open(a, args[1usize], flags)
    if open_error != ok { ret open_error }
    let (written, write_error) = os.write(f, "hello world")
    if write_error != ok { ret write_error }
    if written != 11usize { ret Failed }

    // Where the writes left the cursor.
    let (here, here_error) = os.seek(f, 0i64, os.SeekWhence.Current)
    if here_error != ok { ret here_error }
    if here != 11u64 { ret Failed }

    // Back to the beginning, then read what was written.
    let (start, start_error) = os.seek(f, 0i64, os.SeekWhence.Start)
    if start_error != ok { ret start_error }
    if start != 0u64 { ret Failed }
    var buffer: [16]u8 = zero
    let (count, read_error) = os.read(f, buffer[0usize..16usize])
    if read_error != ok { ret read_error }
    if count != 11usize { ret Failed }
    if buffer[0usize] != 104u8 || buffer[10usize] != 100u8 { ret Failed }

    // An absolute offset into the middle, and a relative one from there.
    let (middle, middle_error) = os.seek(f, 6i64, os.SeekWhence.Start)
    if middle_error != ok { ret middle_error }
    if middle != 6u64 { ret Failed }
    let (word, word_error) = os.read(f, buffer[0usize..5usize])
    if word_error != ok { ret word_error }
    if word != 5usize { ret Failed }
    if buffer[0usize] != 119u8 { ret Failed }
    let (back, back_error) = os.seek(f, 0i64 - 5i64, os.SeekWhence.Current)
    if back_error != ok { ret back_error }
    if back != 6u64 { ret Failed }

    // From the end, forwards and backwards.
    let (ending, ending_error) = os.seek(f, 0i64, os.SeekWhence.End)
    if ending_error != ok { ret ending_error }
    if ending != 11u64 { ret Failed }
    let (before_end, before_end_error) = os.seek(f, 0i64 - 4i64, os.SeekWhence.End)
    if before_end_error != ok { ret before_end_error }
    if before_end != 7u64 { ret Failed }

    // Seeking past the end is legal and does not extend the file.
    let (beyond, beyond_error) = os.seek(f, 100i64, os.SeekWhence.End)
    if beyond_error != ok { ret beyond_error }
    if beyond != 111u64 { ret Failed }

    // Before the beginning is not.
    let (invalid, invalid_error) = os.seek(f, 0i64 - 1i64, os.SeekWhence.Start)
    if invalid_error == ok { ret Failed }
    ret os.close(f)
}
