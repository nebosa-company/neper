// `e.meta`'s scalar reflection. Section 9 keeps all of it at compile time, so each
// call becomes a constant and the binary carries no type information at all.

use e.mem
use e.meta
use e.str

error Failed

type Point = struct {
    x: i32,
    y: i32,
}

type Colour = enum u8 {
    Red,
    Green,
}

type Shape = union enum u8 {
    Dot: Point,
    Line: i64,
}

fn main(a: *mem.Arena) -> err {
    // Every kind section 9 names, in the order `TypeKind` declares them.
    if meta.kind[i32]() != .Int { ret Failed }
    if meta.kind[usize]() != .Int { ret Failed }
    if meta.kind[f64]() != .Float { ret Failed }
    if meta.kind[bool]() != .Bool { ret Failed }
    if meta.kind[err]() != .Err { ret Failed }
    if meta.kind[*Point]() != .Pointer { ret Failed }
    if meta.kind[[]u8]() != .Slice { ret Failed }
    // A `str` is a slice of bytes and reflects as one.
    if meta.kind[str]() != .Slice { ret Failed }
    if meta.kind[[4]u8]() != .Array { ret Failed }
    if meta.kind[Point]() != .Struct { ret Failed }
    if meta.kind[Colour]() != .Enum { ret Failed }
    if meta.kind[Shape]() != .UnionEnum { ret Failed }

    // A length is the one number the type carries.
    if meta.array_len[[4]u8]() != 4usize { ret Failed }
    if meta.array_len[[0]i64]() != 0usize { ret Failed }
    if meta.array_len[[257]bool]() != 257usize { ret Failed }

    // The name is the one written at the declaration, not a rendering of the type.
    if !str.eq(meta.type_name[i32](), "i32") { ret Failed }
    if !str.eq(meta.type_name[usize](), "usize") { ret Failed }
    if !str.eq(meta.type_name[bool](), "bool") { ret Failed }
    if !str.eq(meta.type_name[Point](), "Point") { ret Failed }
    if !str.eq(meta.type_name[Colour](), "Colour") { ret Failed }

    // The answer is a constant, so it is legal where only a constant is: a `switch`
    // case reached through it has to fold at compile time like any other.
    var seen = 0usize
    switch meta.kind[Point]() {
    case .Struct:
        seen = 1usize
    case .Enum:
        seen = 2usize
    default:
        seen = 3usize
    }
    if seen != 1usize { ret Failed }
    ret ok
}
