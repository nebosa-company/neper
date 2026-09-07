use e.mem

fn take[N: usize]() -> usize {
    ret N
}

fn main(a: *mem.Arena, args: []str) -> err {
    if take["ab"]() != 2usize { ret ok }
    ret ok
}
