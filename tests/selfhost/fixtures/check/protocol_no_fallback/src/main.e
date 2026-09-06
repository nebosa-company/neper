error Failed

type Pair = struct { a: i64, b: i64 }

fn order[T: type](a: T, b: T) -> i32 {
    ret T.cmp(a, b)
}

fn main() -> err {
    let p = Pair { a: 1i64, b: 2i64 }
    if order[Pair](p, p) != 0i32 { ret Failed }
    ret ok
}
