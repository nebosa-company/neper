// Section 13's debug types (D1582, D1585): a debugger stopped in `area` sees a struct,
// an enum, a bare union and a tagged union by their fields and members. The runner
// builds this for each host and runs it (exit 0); on Linux gdb reads the values.
use e.io

error Failed

type Point = struct {
    x: i32,
    y: i32,
}

type Color = enum u8 {
    Red,
    Green,
    Blue,
}

type Bits = union {
    whole: u64,
    halves: [2]u32,
}

type Shape = union enum u8 {
    Circle: f64,
    Square: u32,
    Empty,
}

fn area(shape: Shape, corner: Point) -> usize {
    switch shape {
    case .Circle as r:
        ret 3usize
    case .Square as s:
        ret usize(s) * usize(s) + usize(corner.y)
    case .Empty:
        ret 0usize
    }
}

fn main() -> err {
    var bits: Bits = zero
    bits.whole = 4294967297u64
    let tint = Color.Blue
    let corner = Point { x: 3i32, y: 4i32 }
    let shape = Shape{ Square: 7u32 }
    let total = area(shape, corner)
    if total != 53usize || bits.halves[1usize] != 1u32 || tint != .Blue { ret Failed }
    try io.print("debug types ok\n")
    ret ok
}

