// `mem.view` turns an arena base pointer and an offset into a slice, which is the
// one arena operation the language cannot express in source. It aliases storage the
// caller already owns rather than allocating.

use e.mem

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    // Allocate, remember only the offset, then reach the bytes back through `view`.
    let before = mem.mark(a)
    let (buf, alloc_error) = mem.alloc[u8](a, 8usize)
    if alloc_error != ok { ret alloc_error }
    buf[0usize] = 65u8
    buf[7usize] = 90u8

    let seen = mem.view(a, before, 8usize)
    if seen.len != 8usize { ret Failed }
    if seen[0usize] != 65u8 || seen[7usize] != 90u8 { ret Failed }

    // The view aliases the same storage, so writing through it is visible.
    seen[3usize] = 42u8
    if buf[3usize] != 42u8 { ret Failed }

    // A sub-range starts where it is asked to.
    let tail = mem.view(a, before + 4usize, 4usize)
    if tail.len != 4usize { ret Failed }
    if tail[3usize] != 90u8 { ret Failed }
    tail[0usize] = 7u8
    if buf[4usize] != 7u8 { ret Failed }
    ret ok
}
