fn value() -> i64 {
    ret 1i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    defer value()
    ret ok
}
