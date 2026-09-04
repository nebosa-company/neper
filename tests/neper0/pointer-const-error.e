use e.mem

type Item = struct {
    value: u64,
}

fn main(a: *mem.Arena, args: []str) -> err {
    let item = Item{ value: 1u64 }
    let pointer = &item
    pointer.value = 2u64
    ret ok
}
