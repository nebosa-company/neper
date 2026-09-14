// A second accepted program (D284): structs, an enum, a generic function and a switch,
// all of which check clean -- the stream is the header and a passing result.
use e.mem

type Pair = struct { a: i32, b: i32 }
type Colour = enum u8 { Red, Green, Blue }

fn first[T: type](values: []const T) -> T {
    ret values[0usize]
}

fn name(colour: Colour) -> str {
    switch colour {
    case .Red:
        ret "red"
    case .Green:
        ret "green"
    case .Blue:
        ret "blue"
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var pairs: [2]Pair = zero
    pairs[0usize] = Pair { a: 1i32, b: 2i32 }
    let head = first[Pair](pairs[..])
    if head.a + head.b == 3i32 && name(.Green).len == 5usize { ret ok }
    ret ok
}
