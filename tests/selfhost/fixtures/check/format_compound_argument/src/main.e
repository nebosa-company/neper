// An enum is formattable under section 4, but the expansion reaches it only by
// pushing its variant name, which it does not do yet (slices and arrays recurse
// since D189). Rejected at lowering rather than silently formatting nothing.

use e.mem
use e.str

type Color = enum u8 { Red, Green }

fn main(a: *mem.Arena) -> err {
    let shade: Color = .Green
    let (text, text_error) = str.format["{}"](a, shade)
    if text_error != ok { ret text_error }
    ret ok
}
