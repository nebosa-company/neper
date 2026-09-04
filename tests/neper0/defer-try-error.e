fn fail() -> err {
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    defer {
        try fail()
    }
    ret ok
}
