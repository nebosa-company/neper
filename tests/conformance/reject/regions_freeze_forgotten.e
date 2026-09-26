use e.mem
use e.data.list

// A builder neither frozen nor dropped (D1559, H02): it is a resource owed to
// `freeze` or `builder_drop`, so the exit that forgets it is E-SAFETY-0002.

fn fill(b: *list.Builder[u8]) -> err {
    try list.build_push[u8](b, 1u8)
    try list.build_push[u8](b, 2u8)
    try list.build_push[u8](b, 3u8)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var (b, made) = list.builder[u8](a, 2usize)
    if made != ok {
        list.builder_drop[u8](b)
        ret made
    }
    let filled = fill(&b)
    if filled != ok {
        list.builder_drop[u8](b)
        ret filled
    }
    let frozen = list.built[u8](&b)
    if frozen.len != 3usize || frozen[2usize] != 3u8 { ret mem.Exhausted }
    ret ok
}
