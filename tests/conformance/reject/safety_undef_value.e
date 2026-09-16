// `undef` of a type that admits only its members (D475, H03): `Box` holds a `Color`,
// whose bytes name a member or nothing, so a read of the undefined value would be
// an `invalid` check -- which a release build does not keep -- and is refused here.
type Color = enum u8 { Red = 1, Green = 2 }
type Box = struct { n: u32, c: Color }

fn main() -> i32 {
    var b: Box = undef
    b.n = 1u32
    ret i32(b.n) - 1i32
}
