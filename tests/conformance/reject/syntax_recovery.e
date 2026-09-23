// D954: a check goes on past a syntax failure. The tokens recovery skips to
// resynchronize are notes under it, and so is a use of the declaration it broke; a
// failure in a body leaves the interface whole, and an independent failure is an error.
use e.mem

fn shape(x: , y: i64) -> i64 {
    ret y
}

fn user(n: i64) -> i64 {
    ret shape(n, n)
}

fn body(n: i64) -> i64 {
    let m = n +
    ret m
}

fn caller(n: i64) -> i64 {
    ret body(n)
}

fn other(n: i64) -> bool {
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    let v = user(1i64) + caller(2i64)
    ret ok
}
