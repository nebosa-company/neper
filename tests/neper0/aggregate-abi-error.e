use e.mem

type Item = struct {
    value: u64,
}

fn inspect(item: Item) -> u64 {
    ret item.value
}

fn main(a: *mem.Arena, args: []str) -> err {
    ret ok
}
