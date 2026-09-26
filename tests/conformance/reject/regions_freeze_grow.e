use e.mem
use e.data.list

// A builder grown after its freeze (D1559, H02): `freeze` consumed it, so the
// push is E-SAFETY-0001.

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
    let again = list.build_push[u8](&b, 4u8)
    if again != ok || frozen.len != 3usize { ret mem.Exhausted }
    ret ok
}
