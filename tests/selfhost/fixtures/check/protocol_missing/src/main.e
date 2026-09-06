type Point = struct { x: i64, y: i64 }

fn smaller[T: type](a: T, b: T) -> bool {
    ret T.cmp(a, b) < 0i32
}

fn main() -> i64 {
    let p = Point { x: 1i64, y: 2i64 }
    if smaller[Point](p, p) { ret 0i64 }
    ret 1i64
}
