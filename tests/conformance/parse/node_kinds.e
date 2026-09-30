// the syntax node kinds every_kind leaves out (T008): an attribute, a tagged union and
// its members, a parenthesised expression, and an aggregate literal with its items
use e.mem

type Shape = union enum u8 { Empty, Circle: f64, Box: Size }

type Size = struct { w: f64, h: f64 }

@test
fn area(a: *mem.Arena) -> err {
    let s = Size { w: 2.0, h: (1.0 + 2.0) * 3.0 }
    let shape = Shape { Box: s }
    ret ok
}
