// A program that uses `e.os` and does not open a library needs no loader.
//
// D130 claimed this and D131 had to retract it: dropping a dead function leaves its references
// behind, and the imports an image asks for are enumerated from those, so `DT_NEEDED: libc.so.6`
// came back while the decision row said it could not. Every other mistake in that work was caught
// by a fixture; this was the one property no fixture covered, which is why there is now this one.
//
// It checks itself. The program reads its own image and walks its own program headers, so what is
// asserted is the file that was actually produced rather than anything the compiler reports about
// it -- and no `readelf` has to exist for the suite to run.

use e.mem
use e.os

// `PT_DYNAMIC` and `PT_INTERP`. Either means this image expects a loader: one names the
// interpreter, the other the table it would fill.
const PT_DYNAMIC: u32 = 2u32
const PT_INTERP: u32 = 3u32

// Enough for the header and every program header any of these images has. A file that needs more
// than this to describe itself is not the shape this is asserting about.
const HEADER_BYTES: usize = 4096usize

fn little_u16(bytes: []const u8, at: usize) -> usize {
    ret usize(bytes[at]) + usize(bytes[at + 1usize]) * 256usize
}

fn little_u32(bytes: []const u8, at: usize) -> u32 {
    var value = 0u32
    var index = 4usize
    while index > 0usize {
        index -= 1usize
        value = value * 256u32 + u32(bytes[at + index])
    }
    ret value
}

fn little_u64(bytes: []const u8, at: usize) -> usize {
    var value = 0usize
    var index = 8usize
    while index > 0usize {
        index -= 1usize
        value = value * 256usize + usize(bytes[at + index])
    }
    ret value
}

fn read_own_image(a: *mem.Arena, into: []u8) -> (usize, err) {
    let (path, path_error) = os.executable_path(a)
    if path_error != ok { os.exit(60i32) }
    if path.len == 0usize { os.exit(61i32) }
    var flags: os.OpenFlags = zero
    flags.read = true
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { os.exit(62i32) }
    var filled = 0usize
    while filled < into.len {
        let (taken, read_error) = os.read(file, into[filled..into.len])
        if read_error != ok {
            let unused = os.close(file)
            os.exit(63i32)
        }
        if taken == 0usize { break }
        filled += taken
    }
    let close_error = os.close(file)
    if close_error != ok { ret (0usize, close_error) }
    ret (filled, ok)
}

fn main(a: *mem.Arena) -> err {
    let (bytes, allocation_error) = mem.alloc[u8](a, HEADER_BYTES)
    if allocation_error != ok { os.exit(10i32) }
    let (filled, read_error) = read_own_image(a, bytes)
    if read_error != ok { os.exit(11i32) }
    if filled < 64usize { os.exit(12i32) }

    // The host is told apart the same way `e.fs` tells it apart, since a portable module cannot
    // ask the compiler which target it is.
    if os.NATIVE_SEPARATOR == 92u8 {
        // This image is a PE, and the property does not apply to it: `kernel32.dll` is the one
        // library `os.windows.e` names and every Windows program needs it, so there is no
        // freestanding form to assert. What is checked is that the self-read worked at all --
        // without it, the Linux half below would be trusting a buffer it never filled.
        if bytes[0usize] != 77u8 { os.exit(20i32) }
        if bytes[1usize] != 90u8 { os.exit(21i32) }
        ret ok
    }

    // --- An ELF, and its own program headers.
    if bytes[0usize] != 127u8 { os.exit(30i32) }
    if bytes[1usize] != 69u8 { os.exit(31i32) }
    if bytes[2usize] != 76u8 { os.exit(32i32) }
    if bytes[3usize] != 70u8 { os.exit(33i32) }

    let header_offset = little_u64(bytes, 32usize)
    let header_size = little_u16(bytes, 54usize)
    let header_count = little_u16(bytes, 56usize)
    // A file describing itself with no program headers, or more than fit in what was read, is not
    // something to draw a conclusion from either way.
    if header_count == 0usize { os.exit(40i32) }
    if header_size != 56usize { os.exit(41i32) }
    if header_offset + header_count * header_size > filled { os.exit(42i32) }

    var at = 0usize
    while at < header_count {
        let kind = little_u32(bytes, header_offset + at * header_size)
        // The failure this exists for: a program that opens no library carrying the machinery for
        // one, because a function nobody calls left its imports behind.
        if kind == PT_INTERP { os.exit(50i32) }
        if kind == PT_DYNAMIC { os.exit(51i32) }
        at += 1usize
    }
    ret ok
}
