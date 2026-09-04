use e.mem

error Boom

fn fail() -> err {
    ret Boom
}

fn main(a: *mem.Arena, args: []str) -> err {
    try fail()
    ret ok
}
