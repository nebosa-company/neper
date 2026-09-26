use e.mem
use e.data.list

// Containers and region values (D1562, H02): a list that keeps a pointer into a
// region value, read back before the reset; and a list given a region slice only to
// copy out of, which keeps nothing and is used after the reset.
fn copy_into(out: *list.List[u8], from: []const u8) -> err {
    var at = 0usize
    while at < from.len {
        try list.push[u8](out, from[at])
        at += 1usize
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var (kept, made) = list.init[*u8](a, 4usize)
    if made != ok { ret made }
    var (copied, copied_made) = list.init[u8](a, 8usize)
    if copied_made != ok { ret copied_made }
    let mark = mem.mark(a)
    let (bytes, alloc_error) = mem.alloc[u8](a, 8usize)
    if alloc_error != ok { ret alloc_error }
    bytes[0usize] = 7u8
    let first = &bytes[0usize]
    try list.push[*u8](&kept, first)
    let (back, found) = list.pop[*u8](&kept)
    let seen = found && *back == 7u8
    try copy_into(&copied, bytes[0usize..2usize])
    mem.reset(a, mark)
    let (last, has_last) = list.pop[u8](&copied)
    if !seen || !has_last || last != 0u8 { ret mem.Exhausted }
    ret ok
}
