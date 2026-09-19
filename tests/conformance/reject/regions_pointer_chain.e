use e.mem
use e.data.list

// A copied pointer keeps the original container identity (D672).
fn main(a: *mem.Arena, args: []str) -> err {
    var numbers = try list.init[u32](a, 1usize)
    try list.push[u32](&numbers, 1u32)
    let items = list.slice[u32](&numbers)
    let pointer = &numbers
    let copied = pointer
    try list.push[u32](copied, 2u32)
    if items[0usize] != 1u32 { ret mem.Exhausted }
    ret ok
}
