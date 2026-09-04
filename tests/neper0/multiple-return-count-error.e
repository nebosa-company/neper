use e.mem

fn pair() -> (i64, bool) {
    ret (1i64, true)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (only, extra, wrong) = pair()
    ret ok
}
