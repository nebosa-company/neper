// `str.format[FMT](a, args...)` expands to a function of its own, one per calling
// module, format string and argument-type list. Its body is a builder, a push per
// piece of the format string, and `done` -- so what this fixture pins is that the
// generated body agrees, byte for byte, with the same pushes written by hand.

use e.mem
use e.str

error Failed

fn main(a: *mem.Arena) -> err {
    // No verbs at all: the expansion is text and nothing else.
    let (plain, plain_error) = str.format["hello"](a)
    if plain_error != ok { ret plain_error }
    if !str.eq(plain, "hello") { ret Failed }

    // An empty format string still builds, and builds the empty string.
    let (nothing, nothing_error) = str.format[""](a)
    if nothing_error != ok { ret nothing_error }
    if nothing.len != 0usize { ret Failed }

    // One verb, and text on both sides of it.
    let (counted, counted_error) = str.format["n={} done"](a, 42i64)
    if counted_error != ok { ret counted_error }
    if !str.eq(counted, "n=42 done") { ret Failed }

    // A verb at each end, with nothing between them.
    let (joined, joined_error) = str.format["{}{}"](a, 1i64, 2i64)
    if joined_error != ok { ret joined_error }
    if !str.eq(joined, "12") { ret Failed }

    // Every scalar the expansion knows a push for.
    let (mixed, mixed_error) = str.format["{} {} {} {} {}"](a, true, "s", 7u8, -3i32, 9usize)
    if mixed_error != ok { ret mixed_error }
    if !str.eq(mixed, "true s 7 -3 9") { ret Failed }

    // The alternate verbs pick a different push for the same argument.
    let (hex, hex_error) = str.format["{x} {b}"](a, 255u32, 5u32)
    if hex_error != ok { ret hex_error }
    if !str.eq(hex, "ff 101") { ret Failed }
    let (wide, wide_error) = str.format["{x}"](a, 255u64)
    if wide_error != ok { ret wide_error }
    if !str.eq(wide, "ff") { ret Failed }

    // Floats, in both the shortest round-trip form and the fixed one.
    let (shortest, shortest_error) = str.format["{}"](a, 1.5f64)
    if shortest_error != ok { ret shortest_error }
    if !str.eq(shortest, "1.5") { ret Failed }
    let (fixed, fixed_error) = str.format["{.2}"](a, 1.005f64)
    if fixed_error != ok { ret fixed_error }
    if !str.eq(fixed, "1.00") { ret Failed }
    let (narrow, narrow_error) = str.format["{}"](a, 0.5f32)
    if narrow_error != ok { ret narrow_error }
    if !str.eq(narrow, "0.5") { ret Failed }

    // `{{` and `}}` are the only way to write a brace that is not a verb, so a format
    // string can name the syntax it is written in.
    let (braced, braced_error) = str.format["{{{}}}"](a, 8i64)
    if braced_error != ok { ret braced_error }
    if !str.eq(braced, "{8}") { ret Failed }

    // Escapes are decoded before the scan, so a `{` reached through one is a verb.
    let (escaped, escaped_error) = str.format["a\nb={}"](a, 1i64)
    if escaped_error != ok { ret escaped_error }
    if !str.eq(escaped, "a\nb=1") { ret Failed }

    // Two calls with the same format string and the same argument types share one
    // instance; a different argument type is a different one. Both must be right.
    let (reused, reused_error) = str.format["n={} done"](a, 7i64)
    if reused_error != ok { ret reused_error }
    if !str.eq(reused, "n=7 done") { ret Failed }
    let (retyped, retyped_error) = str.format["n={} done"](a, 7u16)
    if retyped_error != ok { ret retyped_error }
    if !str.eq(retyped, "n=7 done") { ret Failed }

    // An `err` verb reaches `push_err`, whose body is generated per module rather
    // than exported, so this is the one verb whose call does not go to `e.str`.
    let (failed, failed_error) = str.format["e={}"](a, Failed)
    if failed_error != ok { ret failed_error }
    if !str.eq(failed, "e=main.Failed") { ret Failed }
    let (fine, fine_error) = str.format["e={}"](a, ok)
    if fine_error != ok { ret fine_error }
    if !str.eq(fine, "e=ok") { ret Failed }

    // The expansion is a call like any other, so the value it returns is a `str` the
    // caller can go on using -- including as an argument to another expansion.
    let (nested, nested_error) = str.format["[{}]"](a, counted)
    if nested_error != ok { ret nested_error }
    if !str.eq(nested, "[n=42 done]") { ret Failed }

    // Rule 4's sequences: a slice and an array as `[` elements `]` with `, ` between,
    // an empty one as `[]`, a slice of `str` as its texts, and an array of arrays
    // nesting -- the expansion recurses an element at a time (D189).
    var items: [3]i64 = [3]i64{ 1, -2, 30 }
    let (sequence, sequence_error) = str.format["n={} s={}"](a, items[0..], items)
    if sequence_error != ok { ret sequence_error }
    if !str.eq(sequence, "n=[1, -2, 30] s=[1, -2, 30]") { ret Failed }
    var names: [2]str = [2]str{ "ab", "c" }
    let (names_text, names_error) = str.format["{}"](a, names[0..])
    if names_error != ok { ret names_error }
    if !str.eq(names_text, "[ab, c]") { ret Failed }
    let empty: [0]u8 = zero
    let (empty_text, empty_error) = str.format["<{}>"](a, empty[0..])
    if empty_error != ok { ret empty_error }
    if !str.eq(empty_text, "<[]>") { ret Failed }
    var grid: [2][2]u8 = zero
    grid[1][0] = 7u8
    let (grid_text, grid_error) = str.format["{}"](a, grid)
    if grid_error != ok { ret grid_error }
    if !str.eq(grid_text, "[[0, 0], [7, 0]]") { ret Failed }
    ret ok
}
