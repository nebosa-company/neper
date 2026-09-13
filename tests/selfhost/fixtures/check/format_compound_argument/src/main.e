// A struct whose module declares no `format` is not formattable under section 4:
// rule 4 supplies nothing for it and there is no `point_format` to call, so the
// call is refused rather than silently formatting nothing (D189-D191 cover the
// slices, arrays, enums and declared formats that are).

use e.mem
use e.str

type Point = struct { x: i64, y: i64 }

fn main(a: *mem.Arena) -> err {
    let p = Point { x: 1i64, y: 2i64 }
    let (text, text_error) = str.format["{}"](a, p)
    if text_error != ok { ret text_error }
    ret ok
}
