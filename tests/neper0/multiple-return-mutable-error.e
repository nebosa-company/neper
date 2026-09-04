use e.mem

fn pair() -> (i64, bool) {
    ret (1i64, true)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let value = 0i64
    var found = false
    (value, found) = pair()
    ret ok
}
