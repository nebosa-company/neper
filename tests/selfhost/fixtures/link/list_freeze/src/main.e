// Build, then freeze (D1559, H02): a `list.Builder` grows while it is built, and
// `list.freeze` consumes it and hands back the elements read-only; a builder that
// cannot be filled is dropped instead. The frozen slice lives in the arena.
use e.mem
use e.data.list

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
    let frozen = list.freeze[u8](b)
    if frozen.len != 3usize || frozen[2usize] != 3u8 { ret mem.Exhausted }
    ret ok
}
