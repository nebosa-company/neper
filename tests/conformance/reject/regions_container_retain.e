use e.mem
use e.data.list

// A view kept in a container (D1562, H02): a pointer into a region value pushed
// into a list leaves the list in that region, so reading it back after the reset
// is E-SAFETY-0013 naming the list.

fn main(a: *mem.Arena, args: []str) -> err {
    var (kept, made) = list.init[*u8](a, 4usize)
    if made != ok { ret made }
    let mark = mem.mark(a)
    let (bytes, alloc_error) = mem.alloc[u8](a, 8usize)
    if alloc_error != ok { ret alloc_error }
    let first = &bytes[0usize]
    try list.push[*u8](&kept, first)
    mem.reset(a, mark)
    let (back, found) = list.pop[*u8](&kept)
    if found && *back == 7u8 { ret mem.Exhausted }
    ret ok
}
