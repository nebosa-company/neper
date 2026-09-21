// `e.text.wrap`: greedy and optimal breaking agree on the fox where the
// greedy choice is already even, differ where a short second line would
// cost (checked by exhaustive search in Python), an overlong word stands
// alone, and justification spreads the extra spaces from the left. Each
// check exits with its own code.

use e.io
use e.mem
use e.os
use e.text.wrap

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn line(text: str, lines: []const usize, i: usize) -> str { ret text[lines[2usize * i]..lines[2usize * i + 1usize]] }

fn main(a: *mem.Arena, args: []str) -> err {
    var lines: [16]usize = zero
    var scratch: [64]usize = zero
    let fox = "the quick brown fox jumps over the lazy dog"

    // 1: greedy.
    let (g, g_error) = wrap.greedy(fox, 10usize, lines[..], scratch[..])
    if g_error != ok || g != 5usize { os.exit(1i32) }
    if !same(line(fox, lines[..], 0usize), "the quick") || !same(line(fox, lines[..], 2usize), "jumps over") || !same(line(fox, lines[..], 4usize), "dog") { os.exit(1i32) }
    let (g2, g2_error) = wrap.greedy("aaa bb cc ddddd", 6usize, lines[..], scratch[..])
    if g2_error != ok || g2 != 3usize || !same(line("aaa bb cc ddddd", lines[..], 0usize), "aaa bb") { os.exit(1i32) }
    let (_, g_room) = wrap.greedy(fox, 10usize, lines[..4usize], scratch[..])
    if g_room != wrap.TooSmall { os.exit(1i32) }
    let (_, g_invalid) = wrap.greedy(fox, 0usize, lines[..], scratch[..])
    if g_invalid != wrap.Invalid { os.exit(1i32) }
    let (empty, empty_error) = wrap.greedy("   ", 10usize, lines[..], scratch[..])
    if empty_error != ok || empty != 0usize { os.exit(1i32) }

    // 2: optimal.
    let (o, o_error) = wrap.optimal(fox, 10usize, lines[..], scratch[..])
    if o_error != ok || o != 5usize || !same(line(fox, lines[..], 1usize), "brown fox") || !same(line(fox, lines[..], 3usize), "the lazy") { os.exit(2i32) }
    let text = "aaa bb cc ddddd eee f gggg hh"
    let (o2, o2_error) = wrap.optimal(text, 6usize, lines[..], scratch[..])
    if o2_error != ok || o2 != 6usize { os.exit(2i32) }
    if !same(line(text, lines[..], 0usize), "aaa") || !same(line(text, lines[..], 1usize), "bb cc") || !same(line(text, lines[..], 2usize), "ddddd") { os.exit(2i32) }
    if !same(line(text, lines[..], 3usize), "eee f") || !same(line(text, lines[..], 4usize), "gggg") || !same(line(text, lines[..], 5usize), "hh") { os.exit(2i32) }
    let long = "word longerthanwidth ok"
    let (o3, o3_error) = wrap.optimal(long, 6usize, lines[..], scratch[..])
    if o3_error != ok || o3 != 3usize || !same(line(long, lines[..], 1usize), "longerthanwidth") { os.exit(2i32) }
    let (_, o_room) = wrap.optimal(fox, 10usize, lines[..], scratch[..20usize])
    if o_room != wrap.TooSmall { os.exit(2i32) }
    let (_, o_lines) = wrap.optimal(fox, 10usize, lines[..6usize], scratch[..])
    if o_lines != wrap.TooSmall { os.exit(2i32) }

    // 3: justification.
    var out: [32]u8 = zero
    let (j1, j1_error) = wrap.justify("the quick", 10usize, out[..], scratch[..])
    if j1_error != ok || !same(j1, "the  quick") { os.exit(3i32) }
    let (j2, j2_error) = wrap.justify("a b c", 9usize, out[..], scratch[..])
    if j2_error != ok || !same(j2, "a   b   c") { os.exit(3i32) }
    let (j3, j3_error) = wrap.justify("a b c", 8usize, out[..], scratch[..])
    if j3_error != ok || !same(j3, "a   b  c") { os.exit(3i32) }
    let (j4, j4_error) = wrap.justify("hello", 10usize, out[..], scratch[..])
    if j4_error != ok || !same(j4, "hello") { os.exit(3i32) }
    let (j5, j5_error) = wrap.justify("  too   long  line ", 8usize, out[..], scratch[..])
    if j5_error != ok || !same(j5, "too long line") { os.exit(3i32) }
    let (j6, j6_error) = wrap.justify("", 8usize, out[..], scratch[..])
    if j6_error != ok || j6.len != 0usize { os.exit(3i32) }
    let (_, j_room) = wrap.justify("a b", 8usize, out[..7usize], scratch[..])
    if j_room != wrap.TooSmall { os.exit(3i32) }

    try io.print("text wrap ok\n")
    ret ok
}
