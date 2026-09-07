// Section 4 calls `err` formattable, but the expansion has no push to reach for: the
// merged error table is not something `e.str` can name yet. Rejected at lowering
// rather than silently printing nothing.

use e.mem
use e.str

error Boom

fn main(a: *mem.Arena) -> err {
    let (text, text_error) = str.format["{}"](a, Boom)
    if text_error != ok { ret text_error }
    ret ok
}
