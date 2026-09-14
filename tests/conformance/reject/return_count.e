use e.mem

fn pair() -> (i32, err) {
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (v, e) = pair()
    ret e
}
