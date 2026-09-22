// What may cross the C ABI next to a type that admits only its members (D920, H03):
// a value or a `*const` pointer the neper side hands over, which the other side only
// reads; and the integer the other side writes, converted on this side, where the
// conversion checks it.
type Color = enum u8 { Red = 1, Green = 2 }

@import("libc", "show_color")
extern fn show(color: Color, also: *const Color) -> i32

@import("libc", "read_color")
extern fn read(out: *u8) -> i32

@cc(c)
fn on_ready(ready: i32) -> i32 {
    if ready != 0i32 { ret 1i32 }
    ret 0i32
}

fn main() -> i32 {
    let color = Color.Green
    if show(color, &color) != 0i32 { ret 1i32 }
    var raw: u8 = 0u8
    if read(&raw) != 0i32 { ret 2i32 }
    let written = Color(raw)
    if written == .Red { ret on_ready(1i32) }
    ret 0i32
}
