// Compiler-origin references (T009): the calls the compiler makes for the source are
// `protocol` references with origin `compiler`, at the source that caused each and
// naming the concrete function -- `T.eq` in a template once per instance that declares
// one (`u8`'s is supplied, and names none), and the `next` a `for` calls.
type Point = struct { x: i32, y: i32 }

fn point_eq(a: Point, b: Point) -> bool {
    ret a.x == b.x && a.y == b.y
}

type Count = struct { at: u32, end: u32 }

fn count_next(it: *Count) -> (u32, bool) {
    if it.at >= it.end { ret (0u32, false) }
    it.at += 1u32
    ret (it.at, true)
}

fn same[T: type](a: T, b: T) -> bool {
    ret T.eq(a, b)
}

fn main() {
    let p: Point = zero
    let equal = same[Point](p, p)
    let flag = same[u8](1u8, 1u8)
    var c = Count { at: 0u32, end: 3u32 }
    for n in c {
        let m = n
    }
}
