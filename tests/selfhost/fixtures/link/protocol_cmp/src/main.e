use shapes

error Failed

fn smaller[T: type](a: T, b: T) -> bool {
    ret T.cmp(a, b) < 0i32
}

fn order[T: type](a: T, b: T) -> i32 {
    ret T.cmp(a, b)
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
    // Spec section 9 rule 4: shapes with no declaring module use the supplied cmp.
    if order[i64](0i64 - 5i64, 3i64) != 0i32 - 1i32 { ret Failed }
    if order[i64](3i64, 0i64 - 5i64) != 1i32 { ret Failed }
    if order[i64](3i64, 3i64) != 0i32 { ret Failed }
    if order[u32](1u32, 4000000000u32) != 0i32 - 1i32 { ret Failed }
    if order[u32](4000000000u32, 1u32) != 1i32 { ret Failed }
    if order[u8](250u8, 3u8) != 1i32 { ret Failed }
    if order[bool](false, true) != 0i32 - 1i32 { ret Failed }
    if order[bool](true, true) != 0i32 { ret Failed }
    // A declared protocol still wins for a type whose module declares one.
    if order[shapes.Tag](s, t) != 1i32 { ret Failed }
    ret ok
}
