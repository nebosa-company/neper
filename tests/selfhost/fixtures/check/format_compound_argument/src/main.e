// A struct with a `format` of its own is formattable under section 4, but the
// expansion reaches it only by calling that format, which it does not do yet
// (slices, arrays and enums are expanded since D189 and D190). Refused rather
// than silently formatting nothing.

use e.mem
use e.str

type Point = struct { x: i64, y: i64 }

fn main(a: *mem.Arena) -> err {
    let p = Point { x: 1i64, y: 2i64 }
    let (text, text_error) = str.format["{}"](a, p)
    if text_error != ok { ret text_error }
    ret ok
}
