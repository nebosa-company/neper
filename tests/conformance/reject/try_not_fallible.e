use e.mem

fn helper() -> err {
    ret ok
}

fn plain() -> i32 {
    try helper()
    ret 1i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let v = plain()
    ret ok
}
