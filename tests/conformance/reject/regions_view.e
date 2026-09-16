use e.mem
use e.data.list

// A view of a list's items dangles once the list grows (D354): E-SAFETY-0014.
fn main(a: *mem.Arena, args: []str) -> err {
    var numbers = try list.init[u32](a, 1usize)
    try list.push[u32](&numbers, 1u32)
    let items = list.slice[u32](&numbers)
    try list.push[u32](&numbers, 2u32)
    if items[0usize] != 1u32 { ret mem.Exhausted }
    ret ok
}
