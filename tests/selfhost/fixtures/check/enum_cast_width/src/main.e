// An integer-to-enum cast takes the backing width alone (section 4): a `u32` into an
// `enum u8` has to go through `u8` first, so the direct cast is refused.
type Color = enum u8 { Red, Green, Blue }

fn main() -> err {
    let wide = 2u32
    let c = Color(wide)
    if c == .Red { ret ok }
    ret ok
}
