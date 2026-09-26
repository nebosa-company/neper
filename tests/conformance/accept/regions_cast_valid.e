use e.mem

// Casts of addresses (D1558, H02): one out of a region value used before the
// reset, and one of a frame local's whole struct, are both valid.

type Pair = struct { a: u32, b: u32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let mark = mem.mark(a)
    let (bytes, alloc_error) = mem.alloc[u8](a, 8usize)
    if alloc_error != ok { ret alloc_error }
    let raw = mem.cast[*u32](&bytes[0usize])
    *raw = 7u32
    let seen = *raw
    mem.reset(a, mark)
    var pair = Pair { a: 1u32, b: 2u32 }
    let whole = mem.cast[*u64](&pair)
    let both = *whole
    if seen != 7u32 || both == 0u64 { ret mem.Exhausted }
    ret ok
}
