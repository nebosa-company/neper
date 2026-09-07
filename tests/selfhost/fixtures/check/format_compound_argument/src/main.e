// A slice is formattable under section 4, but the expansion reaches it only by
// recursing into an element at a time, which it does not do yet. Rejected at
// lowering rather than silently formatting nothing.

use e.mem
use e.str

fn main(a: *mem.Arena) -> err {
    var bytes: [3]u8 = zero
    let (text, text_error) = str.format["{}"](a, bytes[..])
    if text_error != ok { ret text_error }
    ret ok
}
