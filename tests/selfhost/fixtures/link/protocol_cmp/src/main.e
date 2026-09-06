use shapes

error Failed

fn smaller[T: type](a: T, b: T) -> bool {
    ret T.cmp(a, b) < 0i32
}

fn main() -> err {
    let p = shapes.Point { x: 1i64, y: 0i64 }
    let q = shapes.Point { x: 3i64, y: 0i64 }
    let s = shapes.Tag { id: 1i64 }
    let t = shapes.Tag { id: 3i64 }
    if !smaller[shapes.Point](p, q) { ret Failed }
    if smaller[shapes.Point](q, p) { ret Failed }
    if smaller[shapes.Point](p, p) { ret Failed }
    if smaller[shapes.Tag](s, t) { ret Failed }
    if !smaller[shapes.Tag](t, s) { ret Failed }
    ret ok
}
