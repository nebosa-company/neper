use e.mem
use e.data.list

// What a callee cannot keep (D1565, H02): a list used after the reset of a region
// whose pointer a callee was given beside it -- one that declares the pointer
// `@noescape`, one whose body only reads it, and one whose list has nowhere to put
// a `*u8` (a `List[u32]`).
fn peek(kept: *list.List[*u8], p: *u8) -> bool {
    let value = *p
    ret kept.len == 0usize && value == 7u8
}

@noescape("p")
fn seen(kept: *list.List[*u8], p: *u8) -> bool {
    ret kept.len == 0usize && *p == 7u8
}

fn tally(counts: *list.List[u32], p: *u8) -> err {
    try list.push[u32](counts, u32(*p))
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var (kept, made) = list.init[*u8](a, 4usize)
    if made != ok { ret made }
    var (counts, counts_made) = list.init[u32](a, 4usize)
    if counts_made != ok { ret counts_made }
    let mark = mem.mark(a)
    let (bytes, alloc_error) = mem.alloc[u8](a, 8usize)
    if alloc_error != ok { ret alloc_error }
    bytes[0usize] = 7u8
    let first = &bytes[0usize]
    let was_seen = seen(&kept, first) && peek(&kept, first)
    try tally(&counts, first)
    mem.reset(a, mark)
    let (kept_back, kept_found) = list.pop[*u8](&kept)
    let (count, counted) = list.pop[u32](&counts)
    if !was_seen || kept_found || !counted || count != 7u32 { ret mem.Exhausted }
    ret ok
}
