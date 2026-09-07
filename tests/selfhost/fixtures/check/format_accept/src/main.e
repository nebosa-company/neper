// `str.format` and `io.printf` are expanded rather than called, so arity and argument
// types are checked against the format string at compile time. This is the accepting
// half: every verb against a shape section 4 supplies a `format` for. The expansion
// itself is not written yet, so this fixture is checked and not linked.

use e.io
use e.mem
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let count = 42i64
    let narrow = 7u8
    let ratio = 1.5f64
    let flag = true
    let outcome = ok
    let text = "words"
    // One verb of each kind, against a type each accepts.
    let (line, line_error) = str.format["n={} h={x} b={b} f={.2}"](a, count, count, narrow, ratio)
    if line_error != ok { ret line_error }
    if line.len == 0usize { ret ok }
    // `{}` reaches every shape rule 4 supplies.
    let (shapes, shapes_error) = str.format["{} {} {} {} {}"](a, count, ratio, flag, outcome, text)
    if shapes_error != ok { ret shapes_error }
    // A format string with no verbs takes no arguments beyond the arena.
    let (plain, plain_error) = str.format["no verbs at all"](a)
    if plain_error != ok { ret plain_error }
    // Doubled braces are literal text, not verbs.
    let (braced, braced_error) = str.format["{{literal}} {}"](a, flag)
    if braced_error != ok { ret braced_error }
    // The widest precision a literal may carry.
    let (widest, widest_error) = str.format["{.99}"](a, ratio)
    if widest_error != ok { ret widest_error }
    // `printf` has an arena of its own, so it takes only the verb arguments.
    try io.printf["{} and {}"](count, text)
    try io.printf["nothing to say"]()
    ret ok
}
