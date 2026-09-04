use e.mem

fn maximum[T: type](left: T, right: T) -> T {
    ret left
}

fn main(a: *mem.Arena, args: []str) -> err {
    let value = maximum(1, 2)
    ret ok
}
