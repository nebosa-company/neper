// Bytes cast to a pointer to a type that admits only its members (D919, H03): a
// `Color` names a member or nothing, and a `*Color` made from a `*u8` reads whatever
// byte is there -- a representation no check validates, the `invalid` row a release
// build does not keep. `Color(raw)` is the conversion that checks it.
use e.mem

type Color = enum u8 { Red = 1, Green = 2 }

fn main() -> i32 {
    var raw: u8 = 7u8
    let color = mem.cast[*Color](&raw)
    if *color == .Red { ret 1i32 }
    ret 0i32
}
