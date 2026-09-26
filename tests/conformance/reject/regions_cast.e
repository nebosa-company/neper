use e.mem

// A pointer cast out of a region value (D1558, H02): the cast is the address it
// was given, so it is in the region too, and a use of it after the reset is
// E-SAFETY-0013 as the uncast pointer's would be.

fn main(a: *mem.Arena, args: []str) -> err {
    let mark = mem.mark(a)
    let (bytes, alloc_error) = mem.alloc[u8](a, 8usize)
    if alloc_error != ok { ret alloc_error }
    let raw = mem.cast[*u32](&bytes[0usize])
    mem.reset(a, mark)
    let seen = *raw
    if seen == 7u32 { ret mem.Exhausted }
    ret ok
}
