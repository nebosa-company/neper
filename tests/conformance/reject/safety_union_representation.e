// An untagged union puns a byte into a member (D921, H03): `Pun` lets `byte` be
// written and `color` read, and the read finds a `Color` no member names -- the
// `invalid` row, with no check at the read. Hold the byte and convert it with
// `Color(raw)`, which checks it, or say which field is live with a `union enum`.
type Color = enum u8 { Red = 1, Green = 2 }
type Pun = union { color: Color, byte: u8 }

fn main() -> i32 {
    var pun = Pun { byte: 7u8 }
    if pun.color == .Red { ret 1i32 }
    ret 0i32
}
