// The half of `e.str` that only reads: comparison, search, trim, split, and the
// three that allocate a fresh string through a builder. The fixture pins the edges
// the signatures do not show -- what an empty needle matches, where a non-overlapping
// count stops, which byte a trim keeps, and that `lines` takes CRLF but does not
// invent a final empty line.

use e.mem
use e.str

error Failed

fn check_concat(a: *mem.Arena, x: str, y: str, want: str) -> err {
    let (got, got_error) = str.concat(a, x, y)
    if got_error != ok { ret got_error }
    if !str.eq(got, want) { ret Failed }
    ret ok
}

fn check_join(a: *mem.Arena, parts: []const str, sep: str, want: str) -> err {
    let (got, got_error) = str.join(a, parts, sep)
    if got_error != ok { ret got_error }
    if !str.eq(got, want) { ret Failed }
    ret ok
}

fn check_replace(a: *mem.Arena, s: str, needle: str, replacement: str, want: str) -> err {
    let (got, got_error) = str.replace(a, s, needle, replacement)
    if got_error != ok { ret got_error }
    if !str.eq(got, want) { ret Failed }
    ret ok
}

fn check_repeat(a: *mem.Arena, s: str, n: usize, want: str) -> err {
    let (got, got_error) = str.repeat(a, s, n)
    if got_error != ok { ret got_error }
    if !str.eq(got, want) { ret Failed }
    ret ok
}

fn check_find(s: str, needle: str, start: usize, want_at: usize, want_found: bool) -> err {
    let (at, found) = str.find_from(s, needle, start)
    if found != want_found { ret Failed }
    if found && at != want_at { ret Failed }
    ret ok
}

fn check_rfind(s: str, needle: str, want_at: usize, want_found: bool) -> err {
    let (at, found) = str.rfind(s, needle)
    if found != want_found { ret Failed }
    if found && at != want_at { ret Failed }
    ret ok
}

// Walks a split to exhaustion, writing `|` before each field it yields, so one
// comparison covers the field boundaries, the empty fields and the stopping point
// together. The marker leads rather than separates so that no field at all and one
// empty field are different strings.
fn walk(a: *mem.Arena, it: *str.Split, want: str) -> err {
    var (b, builder_error) = str.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var seen = 0usize
    while true {
        let (field, more) = str.split_next(it)
        if !more { break }
        try str.push(&b, "|")
        try str.push(&b, field)
        seen += 1usize
        if seen > 64usize { ret Failed }
    }
    if !str.eq(str.done(&b), want) { ret Failed }
    ret ok
}

fn check_split(a: *mem.Arena, s: str, separator: str, want: str) -> err {
    var (it, split_error) = str.split(s, separator)
    if split_error != ok { ret split_error }
    try walk(a, &it, want)
    ret ok
}

fn check_lines(a: *mem.Arena, s: str, want: str) -> err {
    var it = str.lines(s)
    try walk(a, &it, want)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Allocating forms. `concat` and `join` size their claim exactly; `repeat` and
    // `replace` are the two that can outgrow it.
    try check_concat(a, "ab", "cd", "abcd")
    try check_concat(a, "", "cd", "cd")
    try check_concat(a, "ab", "", "ab")
    try check_concat(a, "", "", "")

    var parts: [3]str = zero
    parts[0usize] = "a"
    parts[1usize] = ""
    parts[2usize] = "ccc"
    try check_join(a, parts[0usize..3usize], ", ", "a, , ccc")
    try check_join(a, parts[0usize..3usize], "", "accc")
    try check_join(a, parts[0usize..1usize], ", ", "a")
    try check_join(a, parts[0usize..0usize], ", ", "")

    try check_repeat(a, "ab", 3usize, "ababab")
    try check_repeat(a, "ab", 0usize, "")
    try check_repeat(a, "", 5usize, "")

    // Non-overlapping replacement, on the boundaries `count` reports.
    try check_replace(a, "a-b-c", "-", "+", "a+b+c")
    try check_replace(a, "a-b", "-", " to ", "a to b")
    try check_replace(a, "abc", "-", "+", "abc")
    try check_replace(a, "aaa", "aa", "X", "Xa")
    try check_replace(a, "a-b", "-", "", "ab")
    try check_replace(a, "ab", "", "-", "-a-b-")
    try check_replace(a, "", "", "-", "-")

    // Equality and the two orderings.
    if !str.eq("", "") { ret Failed }
    if !str.eq("abc", "abc") { ret Failed }
    if str.eq("abc", "abd") { ret Failed }
    if str.eq("abc", "ab") { ret Failed }
    if str.compare("abc", "abc") != 0i32 { ret Failed }
    if str.compare("ab", "abc") != -1i32 { ret Failed }
    if str.compare("abc", "ab") != 1i32 { ret Failed }
    if str.compare("abd", "abc") != 1i32 { ret Failed }
    if str.compare("", "a") != -1i32 { ret Failed }
    // Folding changes the answer, not just the spelling: `Z` sorts before `a` by
    // byte and after it by letter.
    if str.compare("Zoo", "apple") != -1i32 { ret Failed }
    if str.compare_ascii_fold("Zoo", "apple") != 1i32 { ret Failed }
    if str.compare_ascii_fold("ABC", "abc") != 0i32 { ret Failed }
    if str.compare_ascii_fold("abc", "ABD") != -1i32 { ret Failed }
    // `_` is 95, between the two cases, and folding must leave it where it is.
    if str.compare_ascii_fold("_", "a") != -1i32 { ret Failed }

    // Affixes. An empty affix is on every string; one longer than the string is on
    // none.
    if !str.starts_with("hello", "he") { ret Failed }
    if !str.starts_with("hello", "") { ret Failed }
    if !str.starts_with("hello", "hello") { ret Failed }
    if str.starts_with("hello", "el") { ret Failed }
    if str.starts_with("he", "hello") { ret Failed }
    if !str.ends_with("hello", "lo") { ret Failed }
    if !str.ends_with("hello", "") { ret Failed }
    if str.ends_with("hello", "ll") { ret Failed }
    if str.ends_with("lo", "hello") { ret Failed }

    // Search. `find` is `find_from` at zero, and `contains` is its second result.
    try check_find("hello", "l", 0usize, 2usize, true)
    try check_find("hello", "l", 3usize, 3usize, true)
    try check_find("hello", "l", 4usize, 0usize, false)
    try check_find("hello", "lo", 0usize, 3usize, true)
    try check_find("hello", "hello", 0usize, 0usize, true)
    try check_find("hello", "hello!", 0usize, 0usize, false)
    try check_find("hello", "z", 0usize, 0usize, false)
    let (first, first_found) = str.find("hello", "l")
    if !first_found || first != 2usize { ret Failed }
    if !str.contains("hello", "ell") { ret Failed }
    if str.contains("hello", "elo") { ret Failed }
    if !str.contains("hello", "") { ret Failed }

    // An empty needle sits at every boundary, including the one past the last byte,
    // and nowhere beyond it.
    try check_find("abc", "", 0usize, 0usize, true)
    try check_find("abc", "", 2usize, 2usize, true)
    try check_find("abc", "", 3usize, 3usize, true)
    try check_find("abc", "", 4usize, 0usize, false)
    try check_find("", "", 0usize, 0usize, true)
    try check_rfind("abc", "", 3usize, true)
    try check_rfind("hello", "l", 3usize, true)
    try check_rfind("hello", "hello", 0usize, true)
    try check_rfind("hello", "z", 0usize, false)
    try check_rfind("he", "hello", 0usize, false)
    if str.count("hello", "l") != 2usize { ret Failed }
    if str.count("aaa", "aa") != 1usize { ret Failed }
    if str.count("aaaa", "aa") != 2usize { ret Failed }
    if str.count("hello", "z") != 0usize { ret Failed }
    if str.count("abc", "") != 4usize { ret Failed }
    if str.count("", "") != 1usize { ret Failed }

    // Trims borrow: every result below is a subslice of its input.
    if !str.eq(str.trim("  a b \t\n"), "a b") { ret Failed }
    if !str.eq(str.trim("abc"), "abc") { ret Failed }
    if !str.eq(str.trim(" \t\r\n\x0b\x0c"), "") { ret Failed }
    if !str.eq(str.trim(""), "") { ret Failed }
    if !str.eq(str.trim_start("  ab  "), "ab  ") { ret Failed }
    if !str.eq(str.trim_end("  ab  "), "  ab") { ret Failed }
    if !str.eq(str.trim_bytes("xxhixx", "x"), "hi") { ret Failed }
    if !str.eq(str.trim_bytes("abcba", "ab"), "c") { ret Failed }
    if !str.eq(str.trim_bytes("abc", ""), "abc") { ret Failed }
    if !str.eq(str.trim_bytes("aaa", "a"), "") { ret Failed }

    // `split_once` splits at the first separator only.
    let (head, tail, split_found) = str.split_once("a=b=c", "=")
    if !split_found || !str.eq(head, "a") || !str.eq(tail, "b=c") { ret Failed }
    let (whole, rest, missing) = str.split_once("abc", "=")
    if missing || !str.eq(whole, "abc") || !str.eq(rest, "") { ret Failed }
    let (before, after, edge) = str.split_once("=b", "=")
    if !edge || !str.eq(before, "") || !str.eq(after, "b") { ret Failed }

    // Splitting preserves empty fields, so a separator at either end is a field.
    try check_split(a, "a,b,c", ",", "|a|b|c")
    try check_split(a, "a,,c", ",", "|a||c")
    try check_split(a, ",a,", ",", "||a|")
    try check_split(a, "abc", ",", "|abc")
    try check_split(a, "", ",", "|")
    try check_split(a, "a::b::c", "::", "|a|b|c")
    var (rejected, rejected_error) = str.split("a,b", "")
    if rejected_error != str.InvalidSeparator { ret Failed }

    // Lines take either terminator, drop it, and do not add a final empty field --
    // but a blank line in the middle is still a field, and a stray CR is data.
    try check_lines(a, "a\nb", "|a|b")
    try check_lines(a, "a\nb\n", "|a|b")
    try check_lines(a, "a\r\nb\r\n", "|a|b")
    try check_lines(a, "a\n\nb", "|a||b")
    try check_lines(a, "\n", "|")
    try check_lines(a, "", "")
    try check_lines(a, "a\r", "|a\r")
    try check_lines(a, "one", "|one")

    // The two in-place mappings, and the four predicates they follow.
    var buffer: [8]u8 = zero
    buffer[0usize] = 65u8
    buffer[1usize] = 98u8
    buffer[2usize] = 90u8
    buffer[3usize] = 55u8
    str.ascii_lower_in_place(buffer[0usize..4usize])
    if !str.eq(buffer[0usize..4usize], "abz7") { ret Failed }
    str.ascii_upper_in_place(buffer[0usize..4usize])
    if !str.eq(buffer[0usize..4usize], "ABZ7") { ret Failed }

    if !str.is_ascii_space(32u8) { ret Failed }
    if !str.is_ascii_space(9u8) { ret Failed }
    if !str.is_ascii_space(13u8) { ret Failed }
    if str.is_ascii_space(8u8) { ret Failed }
    if str.is_ascii_space(14u8) { ret Failed }
    if str.is_ascii_space(97u8) { ret Failed }
    if !str.is_ascii_digit(48u8) { ret Failed }
    if !str.is_ascii_digit(57u8) { ret Failed }
    if str.is_ascii_digit(47u8) { ret Failed }
    if str.is_ascii_digit(58u8) { ret Failed }
    if !str.is_ascii_alpha(65u8) { ret Failed }
    if !str.is_ascii_alpha(122u8) { ret Failed }
    if str.is_ascii_alpha(64u8) { ret Failed }
    if str.is_ascii_alpha(91u8) { ret Failed }
    if str.is_ascii_alpha(48u8) { ret Failed }
    if !str.is_ascii_alnum(48u8) { ret Failed }
    if !str.is_ascii_alnum(90u8) { ret Failed }
    if str.is_ascii_alnum(95u8) { ret Failed }
    ret ok
}
