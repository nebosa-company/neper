use e.mem
use e.data.list

// A callee keeping what it was lent (D1565, H02): `remember` takes a pointer beside
// a list of pointers of that type, without `own` and without `@noescape`, so the list
// may hold it; a pointer into a region value given to it leaves the list in that
// region, and reading the list after the reset is E-SAFETY-0013 naming the list.
fn remember(kept: *list.List[*u8], p: *u8) -> err {
    try list.push[*u8](kept, p)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var (kept, made) = list.init[*u8](a, 4usize)
    if made != ok { ret made }
    let mark = mem.mark(a)
    let (bytes, alloc_error) = mem.alloc[u8](a, 8usize)
    if alloc_error != ok { ret alloc_error }
    let first = &bytes[0usize]
    try remember(&kept, first)
    mem.reset(a, mark)
    let (back, found) = list.pop[*u8](&kept)
    if found && *back == 7u8 { ret mem.Exhausted }
    ret ok
}
