use e.mem
use e.os
use e.data.list

// What the checker decides here (D359, H06): `Point.eq` is declared and chosen over
// the supplied rule, `Level` has none declared and takes the supplied `eq`, and the
// `list` calls instantiate their templates over `Point` and `u32`; the `err` of a
// close discarded twice, once under `defer`, is listed as the choice it is (D360).
type Point = struct { x: i64, y: i64 }
type Level = enum u8 { Low, High }

fn point_eq(p: Point, q: Point) -> bool {
    ret p.x == q.x
}

fn same[T: type](a: T, b: T) -> bool {
    ret T.eq(a, b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let p = Point { x: 1i64, y: 2i64 }
    let q = Point { x: 1i64, y: 3i64 }
    let same_point = same[Point](p, q)
    let same_level = same[Level](Level.Low, Level.High)
    var points = try list.init[Point](a, 2usize)
    try list.push[Point](&points, p)
    var numbers = try list.init[u32](a, 2usize)
    try list.push[u32](&numbers, 7u32)
    if !same_point || same_level { ret mem.Exhausted }
    let (dir, dir_error) = os.dir_open(a, ".")
    if dir_error != ok { ret dir_error }
    let (again, again_error) = os.dir_open(a, ".")
    if again_error != ok {
        let _ = os.dir_close(dir)
        ret again_error
    }
    defer let _ = os.dir_close(again)
    ret os.dir_close(dir)
}
