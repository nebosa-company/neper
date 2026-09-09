// `e.os`'s file mapping: a real file read through memory, written through memory, and the
// change seen by an ordinary read afterwards. That last step is what says a mapping is the
// file rather than a copy of it.
//
// Every path is relative, so the runner's working directory decides where this lands.

use e.mem
use e.os

fn open_for(a: *mem.Arena, path: str, writable: bool) -> (os.File, err) {
    var flags: os.OpenFlags = zero
    flags.read = true
    flags.write = writable
    let (file, open_error) = os.open(a, path, flags)
    ret (file, open_error)
}

fn write_whole(a: *mem.Arena, path: str, bytes: []const u8) -> err {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.truncate = true
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret open_error }
    let (written, write_error) = os.write(file, bytes)
    if write_error != ok { ret write_error }
    if written != bytes.len { ret os.Failed }
    ret os.close(file)
}

fn main(a: *mem.Arena) -> err {
    let leftover = os.remove_file(a, "np-map.bin")

    // Sixteen bytes, each its own value, so any misplaced offset is visible.
    var original: [16]u8 = zero
    var at = 0usize
    while at < 16usize {
        original[at] = u8(at) + 65u8
        at += 1usize
    }
    if write_whole(a, "np-map.bin", original[..]) != ok { os.exit(10i32) }

    // --- Read through a mapping.
    let (reader, reader_error) = open_for(a, "np-map.bin", false)
    if reader_error != ok { os.exit(11i32) }
    let (read_only, read_only_error) = os.map_file(reader, 0u64, 16usize, false)
    if read_only_error != ok { os.exit(12i32) }
    let seen = os.mapping_bytes(read_only)
    if seen.len != 16usize { os.exit(13i32) }
    at = 0usize
    while at < 16usize {
        if seen[at] != original[at] { os.exit(14i32) }
        at += 1usize
    }

    // A mapping that was not opened for writing refuses to hand back a writable slice,
    // rather than handing one back whose first write would fault.
    let (refused, refused_error) = os.mapping_bytes_mut(read_only)
    if refused_error != os.Unsupported { os.exit(15i32) }

    if os.mapping_close(read_only) != ok { os.exit(16i32) }
    if os.close(reader) != ok { os.exit(17i32) }

    // --- Write through a mapping, and see it in the file.
    let (writer, writer_error) = open_for(a, "np-map.bin", true)
    if writer_error != ok { os.exit(20i32) }
    let (writable, writable_error) = os.map_file(writer, 0u64, 16usize, true)
    if writable_error != ok { os.exit(21i32) }
    let (region, region_error) = os.mapping_bytes_mut(writable)
    if region_error != ok { os.exit(22i32) }
    if region.len != 16usize { os.exit(23i32) }
    // The first and last bytes, so a length that came out short would be caught as well as
    // an offset that came out wrong.
    region[0usize] = 122u8
    region[15usize] = 121u8
    if os.mapping_flush(writable) != ok { os.exit(24i32) }
    if os.mapping_close(writable) != ok { os.exit(25i32) }
    if os.close(writer) != ok { os.exit(26i32) }

    // An ordinary read of the file, which is the only thing that can say the write reached
    // it rather than only the memory it was made through.
    let (checker, checker_error) = open_for(a, "np-map.bin", false)
    if checker_error != ok { os.exit(30i32) }
    var reread: [16]u8 = zero
    let (taken, take_error) = os.read(checker, reread[..])
    if take_error != ok { os.exit(31i32) }
    if taken != 16usize { os.exit(32i32) }
    if os.close(checker) != ok { os.exit(33i32) }
    if reread[0usize] != 122u8 { os.exit(34i32) }
    if reread[15usize] != 121u8 { os.exit(35i32) }
    // And nothing between them moved.
    at = 1usize
    while at < 15usize {
        if reread[at] != original[at] { os.exit(36i32) }
        at += 1usize
    }

    // A mapping of part of the file starts where it was asked to, not at the beginning.
    let (partial_file, partial_file_error) = open_for(a, "np-map.bin", false)
    if partial_file_error != ok { os.exit(40i32) }
    let (partial, partial_error) = os.map_file(partial_file, 0u64, 8usize, false)
    if partial_error != ok { os.exit(41i32) }
    let short_view = os.mapping_bytes(partial)
    if short_view.len != 8usize { os.exit(42i32) }
    if short_view[0usize] != 122u8 { os.exit(43i32) }
    if short_view[7usize] != original[7usize] { os.exit(44i32) }
    if os.mapping_close(partial) != ok { os.exit(45i32) }
    if os.close(partial_file) != ok { os.exit(46i32) }

    // A length of nothing is refused rather than mapping something.
    let (empty_file, empty_file_error) = open_for(a, "np-map.bin", false)
    if empty_file_error != ok { os.exit(50i32) }
    let (empty, empty_error) = os.map_file(empty_file, 0u64, 0usize, false)
    if empty_error == ok { os.exit(51i32) }
    if os.close(empty_file) != ok { os.exit(52i32) }

    if os.remove_file(a, "np-map.bin") != ok { os.exit(60i32) }
    ret ok
}
