// A foreign write of a type that admits only its members (D920, H03): the C side
// of `fill` writes a `Color` through `out`, and whatever byte it leaves enters checked
// code with no check between it and a switch that trusts it. Declaring the byte the
// other side writes, and converting it with `Color(raw)`, is what checks it.
type Color = enum u8 { Red = 1, Green = 2 }

@import("libc", "fill_color")
extern fn fill(out: *Color) -> i32

fn main() -> i32 {
    var color = Color.Red
    if fill(&color) != 0i32 { ret 1i32 }
    ret 0i32
}
