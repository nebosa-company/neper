use e.mem

// A dispatch the supplied rule refuses (D430, H06): `Shape` is a tagged union whose
// arm `Dot` carries a struct, and a struct has no `cmp` of its own.
type Point = struct { x: i64, y: i64 }
type Shape = union enum u8 { Dot: Point, Empty }

fn least[T: type](a: T, b: T) -> T {
    if T.cmp(a, b) < 0i32 { ret a }
    ret b
}

fn main(a: *mem.Arena, args: []str) -> err {
    let s = least[Shape](Shape{ Empty }, Shape{ Empty })
    ret ok
}
