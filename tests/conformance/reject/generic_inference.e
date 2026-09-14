use e.mem

fn first[T: type]() -> usize {
    ret 0usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    let n = first()
    ret ok
}
