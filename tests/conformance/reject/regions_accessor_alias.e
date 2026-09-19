use e.mem
use e.data.list

// A view returned through a pointer alias still belongs to the container (D678).
fn main(a: *mem.Arena, args: []str) -> err {
    var numbers = try list.init[u32](a, 1usize)
    try list.push[u32](&numbers, 1u32)
    let pointer = &numbers
    let items = list.slice[u32](pointer)
    try list.push[u32](&numbers, 2u32)
    if items[0usize] != 1u32 { ret mem.Exhausted }
    ret ok
}
