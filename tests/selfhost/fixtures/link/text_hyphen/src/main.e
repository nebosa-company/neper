// `e.text.hyphen`: twelve words break where a Python Liang replica over the
// same pattern subset (checked against pyphen's en_US) breaks them at
// minimums 2/3, four of them again at 1/1, an exception overrides the
// patterns, case folds, `hyphenate` writes the hyphens, and the room and
// length limits are refused. Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.str
use e.text.hyphen

fn check(word: str, left: usize, right: usize, expected: []const usize, code: i32) {
    var out: [16]usize = zero
    let (n, e) = hyphen.break_points(hyphen.english(), "", word, left, right, out[..])
    if e != ok || n != expected.len { os.exit(code) }
    var i = 0usize
    while i < n {
        if out[i] != expected[i] { os.exit(code) }
        i += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [4]usize = zero

    // 1: the five words the module is for, at 2/3.
    x[0usize] = 2usize
    x[1usize] = 6usize
    check("hyphenation", 2usize, 3usize, x[..2usize], 1i32)
    x[0usize] = 3usize
    check("computer", 2usize, 3usize, x[..1usize], 1i32)
    x[0usize] = 2usize
    x[1usize] = 4usize
    check("algorithm", 2usize, 3usize, x[..2usize], 1i32)
    x[0usize] = 3usize
    x[1usize] = 7usize
    x[2usize] = 9usize
    check("concatenation", 2usize, 3usize, x[..3usize], 1i32)
    x[0usize] = 3usize
    x[1usize] = 7usize
    check("programming", 2usize, 3usize, x[..2usize], 1i32)

    // 2: seven more at 2/3, including one with no break.
    x[0usize] = 3usize
    x[1usize] = 6usize
    check("dictionary", 2usize, 3usize, x[..2usize], 2i32)
    check("university", 2usize, 3usize, x[..2usize], 2i32)
    x[0usize] = 2usize
    x[1usize] = 5usize
    x[2usize] = 7usize
    check("information", 2usize, 3usize, x[..3usize], 2i32)
    x[0usize] = 4usize
    x[1usize] = 6usize
    check("beautiful", 2usize, 3usize, x[..2usize], 2i32)
    x[0usize] = 3usize
    x[1usize] = 6usize
    x[2usize] = 7usize
    check("philosophy", 2usize, 3usize, x[..3usize], 2i32)
    check("project", 2usize, 3usize, x[..0usize], 2i32)
    x[0usize] = 2usize
    x[1usize] = 4usize
    check("associate", 2usize, 3usize, x[..2usize], 2i32)
    check("zzzzzz", 2usize, 3usize, x[..0usize], 2i32)

    // 3: the minimums at 1/1 admit more.
    x[0usize] = 3usize
    x[1usize] = 6usize
    check("computer", 1usize, 1usize, x[..2usize], 3i32)
    x[0usize] = 2usize
    x[1usize] = 4usize
    x[2usize] = 8usize
    check("algorithm", 1usize, 1usize, x[..3usize], 3i32)
    x[0usize] = 1usize
    x[1usize] = 3usize
    x[2usize] = 6usize
    x[3usize] = 8usize
    check("university", 1usize, 1usize, x[..4usize], 3i32)
    x[0usize] = 6usize
    check("project", 1usize, 1usize, x[..1usize], 3i32)

    // 4: an exception wins over the patterns and ignores the minimums; the
    // other listed word and case folding.
    var out: [16]usize = zero
    let (n4, e4) = hyphen.break_points(hyphen.english(), "as-so-ci-ate hy-phen-a-tion", "Hyphenation", 2usize, 3usize, out[..])
    if e4 != ok || n4 != 3usize || out[0usize] != 2usize || out[1usize] != 6usize || out[2usize] != 7usize { os.exit(4i32) }
    let (n4b, e4b) = hyphen.break_points(hyphen.english(), "as-so-ci-ate hy-phen-a-tion", "associate", 2usize, 3usize, out[..])
    if e4b != ok || n4b != 3usize || out[0usize] != 2usize || out[1usize] != 4usize || out[2usize] != 6usize { os.exit(4i32) }
    let (n4c, e4c) = hyphen.break_points(hyphen.english(), "hy-phen-a-tion", "hyphenate", 2usize, 3usize, out[..])
    if e4c != ok || n4c != 2usize || out[0usize] != 2usize || out[1usize] != 6usize { os.exit(4i32) }
    let (n4d, e4d) = hyphen.break_points(hyphen.english(), "", "COMPUTER", 2usize, 3usize, out[..])
    if e4d != ok || n4d != 1usize || out[0usize] != 3usize { os.exit(4i32) }

    // 5: hyphenate writes the word with hyphens.
    var text: [32]u8 = zero
    let (n5, e5) = hyphen.hyphenate(hyphen.english(), "", "concatenation", 2usize, 3usize, 45u8, text[..])
    if e5 != ok || !str.eq(text[..n5], "con-cate-na-tion") { os.exit(5i32) }
    let (n5b, e5b) = hyphen.hyphenate(hyphen.english(), "", "project", 2usize, 3usize, 45u8, text[..])
    if e5b != ok || !str.eq(text[..n5b], "project") { os.exit(5i32) }

    // 6: limits.
    let (_, e6) = hyphen.break_points(hyphen.english(), "", "concatenation", 2usize, 3usize, out[..2usize])
    if e6 != hyphen.TooSmall { os.exit(6i32) }
    let (_, e6b) = hyphen.break_points(hyphen.english(), "", "", 2usize, 3usize, out[..])
    if e6b != hyphen.Invalid { os.exit(6i32) }
    let (_, e6c) = hyphen.break_points(hyphen.english(), "", "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklm", 2usize, 3usize, out[..])
    if e6c != hyphen.TooLong { os.exit(6i32) }
    let (_, e6d) = hyphen.hyphenate(hyphen.english(), "", "concatenation", 2usize, 3usize, 45u8, text[..15usize])
    if e6d != hyphen.TooSmall { os.exit(6i32) }

    try io.print("text hyphen ok\n")
    ret ok
}
