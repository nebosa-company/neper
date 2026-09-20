// `printf` and `format` inside a generic of another module (D784): instantiated here
// with three element types, each expansion owned by this module's artifact.

use e.io
use e.mem
use e.os
use show

fn main(a: *mem.Arena, args: []str) -> err {
    try show.line[u32]("n", 42u32)
    try show.line[i64]("m", -7i64)
    try show.line[f64]("x", 2.5)
    let (a_text, a_error) = show.text[u8](a, 9u8)
    if a_error != ok || a_text.len != 3usize || a_text[1] != 57u8 { os.exit(1i32) }
    let (b_text, b_error) = show.text[str](a, "hi")
    if b_error != ok || b_text.len != 4usize || b_text[2] != 105u8 { os.exit(2i32) }
    try io.print("format generic ok\n")
    ret ok
}
