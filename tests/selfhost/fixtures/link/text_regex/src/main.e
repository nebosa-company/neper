// Pike-VM regular expressions: syntax, leftmost-first semantics, captures, options and
// replacement, each pinned by a numbered check.

use e.io
use e.mem
use e.os
use e.text.regex

fn same(a: str, b: str) -> bool {
    ret mem.eq[u8](a, b)
}

fn matches(a: *mem.Arena, pattern: str, text: str) -> bool {
    let (r, r_error) = regex.compile(a, pattern, zero)
    if r_error != ok { ret false }
    ret regex.is_match(&r, text)
}

fn found(a: *mem.Arena, pattern: str, text: str, start: usize, end: usize) -> bool {
    let (r, r_error) = regex.compile(a, pattern, zero)
    if r_error != ok { ret false }
    ret found_in(&r, text, start, end)
}

fn found_in(r: *const regex.Regex, text: str, start: usize, end: usize) -> bool {
    let (m, has) = regex.find(r, text, 0usize)
    ret has && m.start == start && m.end == end
}

fn refused(a: *mem.Arena, pattern: str, expected: err) -> bool {
    let (_, r_error) = regex.compile(a, pattern, zero)
    ret r_error == expected
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Literals, classes, anchors and escapes.
    if !matches(a, "abc", "xxabcxx") || matches(a, "abd", "xxabcxx") { os.exit(1i32) }
    if !found(a, "b+", "abbbc", 1usize, 4usize) || !found(a, "b+?", "abbbc", 1usize, 2usize) { os.exit(2i32) }
    if !found(a, "[a-c]+", "xxcabz", 2usize, 5usize) || !found(a, "[^a-c]+", "abxyc", 2usize, 4usize) { os.exit(3i32) }
    if !found(a, "\\d+", "ab1234c", 2usize, 6usize) || !found(a, "\\D+", "12ab34", 2usize, 4usize) { os.exit(4i32) }
    if !found(a, "\\w+", "  word_1 ", 2usize, 8usize) || !found(a, "\\s+", "ab \t\nc", 2usize, 5usize) { os.exit(5i32) }
    if !found(a, "[\\d_]+", "x1_2y", 1usize, 4usize) || !found(a, "[]a]+", "b]a]c", 1usize, 4usize) { os.exit(6i32) }
    if !matches(a, "^abc$", "abc") || matches(a, "^abc$", "xabc") || matches(a, "^abc$", "abcx") { os.exit(7i32) }
    if !found(a, "\\bcat\\b", "concat cat", 7usize, 10usize) || matches(a, "\\bcat\\b", "concat") || !found(a, "\\Bcat", "concat", 3usize, 6usize) { os.exit(8i32) }
    if !found(a, "a\\.b", "axb a.b", 4usize, 7usize) || !found(a, "a.b", "axb", 0usize, 3usize) || matches(a, "a.b", "a\nb") { os.exit(9i32) }
    if !found(a, "\\t\\n", "x\t\ny", 1usize, 3usize) { os.exit(10i32) }

    // Repeats, alternation, groups and leftmost-first preference.
    if !found(a, "a{3}", "aaaaa", 0usize, 3usize) || !found(a, "a{2,}", "aaaaa", 0usize, 5usize) || !found(a, "a{2,3}", "aaaaa", 0usize, 3usize) { os.exit(11i32) }
    if matches(a, "a{3}", "aa") || !found(a, "a{2,3}?", "aaaaa", 0usize, 2usize) || !found(a, "(ab){2}", "ababab", 0usize, 4usize) { os.exit(12i32) }
    if !found(a, "cat|category", "category", 0usize, 3usize) || !found(a, "category|cat", "category", 0usize, 8usize) { os.exit(13i32) }
    if !found(a, "a*", "baaa", 0usize, 0usize) || !found(a, "a*?b", "aaab", 0usize, 4usize) || !found(a, "(a|ab)(c|bcd)(d*)", "abcd", 0usize, 4usize) { os.exit(14i32) }
    if !found(a, "(?:ab)+", "xababx", 1usize, 5usize) || !found(a, "x?y", "y", 0usize, 1usize) || !found(a, "", "abc", 0usize, 0usize) { os.exit(15i32) }
    if !matches(a, "(a*)*b", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab") || matches(a, "(a*)*b", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") { os.exit(16i32) }

    // Captures: groups, nesting, a group that did not take part, and `find` from an offset.
    let (dated, dated_error) = regex.compile(a, "(\\d{4})-(\\d{2})(?:-(\\d{2}))?", zero)
    if dated_error != ok { os.exit(17i32) }
    let (caps, caps_found, caps_error) = regex.captures(a, &dated, "on 2026-09-20 and 2027-01", 0usize)
    if caps_error != ok || !caps_found || caps.whole.start != 3usize || caps.whole.end != 13usize || caps.groups.len != 3usize { os.exit(18i32) }
    if caps.groups[0].start != 3usize || caps.groups[0].end != 7usize || caps.groups[1].start != 8usize || caps.groups[1].end != 10usize || caps.groups[2].start != 11usize || caps.groups[2].end != 13usize { os.exit(19i32) }
    let (later, later_found, later_error) = regex.captures(a, &dated, "on 2026-09-20 and 2027-01", 13usize)
    if later_error != ok || !later_found || later.whole.start != 18usize || later.whole.end != 25usize { os.exit(20i32) }
    if later.groups[2].start != 18446744073709551615usize || later.groups[2].end != 18446744073709551615usize { os.exit(21i32) }
    let (_, past_found, past_error) = regex.captures(a, &dated, "2026-09", 8usize)
    if past_error != ok || past_found { os.exit(22i32) }
    let (nested, nested_error) = regex.compile(a, "((a)(b)?)+", zero)
    let (nested_caps, nested_found, nested_caps_error) = regex.captures(a, &nested, "aba", 0usize)
    if nested_error != ok || nested_caps_error != ok || !nested_found || nested_caps.whole.end != 3usize || nested_caps.groups[0].start != 2usize || nested_caps.groups[1].start != 2usize || nested_caps.groups[2].start != 1usize { os.exit(23i32) }

    // Options.
    let fold = regex.Options { case_insensitive: true, multiline: false, dot_matches_newline: false }
    let (folded, folded_error) = regex.compile(a, "straße[x-z]", fold)
    if folded_error != ok || !regex.is_match(&folded, "StraßeY") || !regex.is_match(&folded, "STRAßEZ") || regex.is_match(&folded, "straßeq") { os.exit(24i32) }
    let lines = regex.Options { case_insensitive: false, multiline: true, dot_matches_newline: false }
    let (lined, lined_error) = regex.compile(a, "^b$", lines)
    let (plain, plain_error) = regex.compile(a, "^b$", zero)
    if lined_error != ok || plain_error != ok || !found_in(&lined, "a\nb\nc", 2usize, 3usize) || regex.is_match(&plain, "a\nb\nc") { os.exit(25i32) }
    let dotall = regex.Options { case_insensitive: false, multiline: false, dot_matches_newline: true }
    let (spanning, spanning_error) = regex.compile(a, "a.b", dotall)
    if spanning_error != ok || !regex.is_match(&spanning, "a\nb") { os.exit(26i32) }

    // UTF-8: a class over non-ASCII scalars, `.` taking one whole scalar, byte offsets.
    if !found(a, "[é-ë]+", "aéêëz", 1usize, 7usize) || !found(a, "a.b", "a€b", 0usize, 5usize) || !found(a, "€{2}", "x€€€", 1usize, 7usize) { os.exit(27i32) }

    // Refusals.
    if !refused(a, "a(b", regex.InvalidPattern) || !refused(a, "a)", regex.InvalidPattern) || !refused(a, "*a", regex.InvalidPattern) { os.exit(28i32) }
    if !refused(a, "[a-", regex.InvalidPattern) || !refused(a, "[z-a]", regex.InvalidPattern) || !refused(a, "a{3,2}", regex.InvalidPattern) || !refused(a, "\\q", regex.InvalidPattern) { os.exit(29i32) }
    if !refused(a, "a{1001}", regex.TooComplex) || !refused(a, "(((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((a)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))", regex.TooComplex) { os.exit(30i32) }
    if !refused(a, "((a{100}){100}){100}", regex.TooComplex) || !refused(a, "a{2", regex.InvalidPattern) { os.exit(31i32) }

    // replace_all: group references, a literal dollar, empty matches and no match.
    let (words, words_error) = regex.compile(a, "(\\w+)@(\\w+)", zero)
    let (swapped, swapped_error) = regex.replace_all(a, &words, "a@b, c@d!", "$2 at $1 ($$0=$0)")
    if words_error != ok || swapped_error != ok || !same(swapped, "b at a ($0=a@b), d at c ($0=c@d)!") { os.exit(32i32) }
    let (star, star_error) = regex.compile(a, "x*", zero)
    let (dashed, dashed_error) = regex.replace_all(a, &star, "xa", "-")
    let (dashed_empty, dashed_empty_error) = regex.replace_all(a, &star, "", "-")
    let (dashed_bare, dashed_bare_error) = regex.replace_all(a, &star, "ab", "-")
    if star_error != ok || dashed_error != ok || dashed_empty_error != ok || dashed_bare_error != ok || !same(dashed, "-a-") || !same(dashed_empty, "-") || !same(dashed_bare, "-a-b-") { os.exit(33i32) }
    let (untouched, untouched_error) = regex.replace_all(a, &words, "nothing here", "!")
    let (wide, wide_error) = regex.replace_all(a, &star, "é", "-")
    if untouched_error != ok || wide_error != ok || !same(untouched, "nothing here") || !same(wide, "-é-") { os.exit(34i32) }

    try io.print("text regex ok\n")
    ret ok
}
