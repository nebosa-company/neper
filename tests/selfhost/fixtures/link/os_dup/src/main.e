// `os.dup` (D349) asks the OS for a second identity of an open file: the duplicate
// shares the description's offset, so a read through it moves the original's cursor,
// and each handle is closed once, on its own. The path to work in is the first argument.

use e.mem
use e.os

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { ret Failed }
    let flags = os.OpenFlags { read: true, write: true, create: true, truncate: true, append: false }
    let (f, open_error) = os.open(a, args[1usize], flags)
    if open_error != ok { ret open_error }
    let (written, write_error) = os.write(f, "hello!")
    if write_error != ok {
        let _ = os.close(f)
        ret write_error
    }
    let (start, seek_error) = os.seek(f, 0i64, os.SeekWhence.Start)
    if seek_error != ok {
        let _ = os.close(f)
        ret seek_error
    }
    let (d, dup_error) = os.dup(f)
    if dup_error != ok {
        let _ = os.close(f)
        ret dup_error
    }
    var buffer: [4]u8 = zero
    let (n, read_error) = os.read(d, buffer[..])
    let first_close = os.close(d)
    // The duplicate is gone; the original still reads, from where the duplicate left it.
    let (m, again_error) = os.read(f, buffer[..])
    let second_close = os.close(f)
    if read_error != ok { ret read_error }
    if again_error != ok { ret again_error }
    if first_close != ok { ret first_close }
    if second_close != ok { ret second_close }
    if written != 6usize || start != 0u64 { ret Failed }
    if n != 4usize || m != 2usize { ret Failed }
    if buffer[0usize] != 111u8 || buffer[1usize] != 33u8 { ret Failed }
    ret ok
}
