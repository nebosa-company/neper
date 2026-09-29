// Backtracking regular expressions (`regex.compile_backtracking`): backreferences numbered
// and named, case-insensitive backreferences, lookahead, lookbehind (at the start of the
// text, over multi-byte scalars, multiline), nested lookaround, atomic groups, possessive
// repeats, groups that took no part, replace_all through the backtracker, a table of
// random patterns, `compile` refusing what needs a backtracker, the step budget stopping
// `(a+)+$` quickly, the stack bound, and named groups under the Pike VM. Every expected
// value is from Python 3.12 `re`, written by vectors.py next to this directory's src/.

use e.io
use e.mem
use e.os
use e.text.regex
use e.time

const NONE: usize = 18446744073709551615usize

fn options(flags: u8) -> regex.Options {
    ret regex.Options { case_insensitive: (flags & 1u8) != 0u8, multiline: (flags & 2u8) != 0u8, dot_matches_newline: (flags & 4u8) != 0u8 }
}

fn put_str(buf: []u8, at: usize, s: str) -> usize {
    mem.copy[u8](buf[at..at + s.len], s)
    ret at + s.len
}

fn put_num(buf: []u8, at: usize, v: usize) -> usize {
    if v == NONE { ret put_str(buf, at, "-") }
    var digits: [20]u8 = zero
    var n = 0usize
    var rest = v
    while n == 0usize || rest > 0usize {
        digits[n] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        n += 1usize
    }
    var used = at
    while n > 0usize {
        n -= 1usize
        buf[used] = digits[n]
        used += 1usize
    }
    ret used
}

fn report(pattern: str, got: str, want: str) {
    let _ = io.print(pattern)
    let _ = io.print("\n  got:  ")
    let _ = io.print(got)
    let _ = io.print("\n  want: ")
    let _ = io.print(want)
    let _ = io.print("\n")
}

// The first match of `pattern` in `subject` as "start end g1start g1end ...", `-` for a
// group that took no part, or "none", against Python's answer.
fn m(a: *mem.Arena, flags: u8, pattern: str, subject: str, want: str) -> bool {
    let mark = a.off
    var buf: [512]u8 = zero
    var n = 0usize
    let (r, r_error) = regex.compile_backtracking(a, pattern, options(flags))
    if r_error != ok {
        report(pattern, "compile failed", want)
        ret false
    }
    let (caps, has, caps_error) = regex.captures(a, &r, subject, 0usize)
    if caps_error != ok {
        report(pattern, "captures failed", want)
        ret false
    }
    if !has {
        n = put_str(buf[0..], n, "none")
    } else {
        n = put_num(buf[0..], n, caps.whole.start)
        n = put_str(buf[0..], n, " ")
        n = put_num(buf[0..], n, caps.whole.end)
        var g = 0usize
        while g < caps.groups.len {
            n = put_str(buf[0..], n, " ")
            n = put_num(buf[0..], n, caps.groups[g].start)
            n = put_str(buf[0..], n, " ")
            n = put_num(buf[0..], n, caps.groups[g].end)
            g += 1usize
        }
    }
    let same = mem.eq[u8](buf[..n], want)
    if !same { report(pattern, buf[..n], want) }
    a.off = mark
    ret same
}

fn rep(a: *mem.Arena, flags: u8, pattern: str, subject: str, replacement: str, want: str) -> bool {
    let mark = a.off
    let (r, r_error) = regex.compile_backtracking(a, pattern, options(flags))
    if r_error != ok { ret false }
    let (out, out_error) = regex.replace_all(a, &r, subject, replacement)
    let same = out_error == ok && mem.eq[u8](out, want)
    if !same { report(pattern, out, want) }
    a.off = mark
    ret same
}

fn refuses(a: *mem.Arena, pattern: str, backtracking: bool, expected: err) -> bool {
    let mark = a.off
    var r_error = ok
    if backtracking {
        let (_, e) = regex.compile_backtracking(a, pattern, zero)
        r_error = e
    } else {
        let (_, e) = regex.compile(a, pattern, zero)
        r_error = e
    }
    a.off = mark
    if r_error != expected { report(pattern, "a different answer", "a refusal") }
    ret r_error == expected
}

fn constructs(a: *mem.Arena) -> i32 {
    if !m(a, 0u8, "(\\w+) \\1", "hello hello world", "0 11 0 5") { ret 1i32 }
    if !m(a, 0u8, "(a)(b)?\\2", "ab ab", "none") { ret 2i32 }
    if !m(a, 0u8, "(a|b)\\1+", "abbbab", "1 4 1 2") { ret 3i32 }
    if !m(a, 0u8, "<(\\w+)>.*?</\\1>", "<b>bold</b><i>x</i>", "0 11 1 2") { ret 4i32 }
    if !m(a, 0u8, "(?<q>['\\\"]).*?\\k<q>", "say \"hi\" 'x'", "4 8 4 5") { ret 5i32 }
    if !m(a, 0u8, "(?P<x>[a-z]+)-(?P=x)", "foo-bar bar-bar", "8 15 8 11") { ret 6i32 }
    if !m(a, 1u8, "(ab)\\1", "xabAB", "1 5 1 3") { ret 7i32 }
    if !m(a, 1u8, "(?P<x>[a-z]+)-(?P=x)", "Foo-FOO", "0 7 0 3") { ret 8i32 }
    if !m(a, 1u8, "(?<=A)b", "aB", "1 2") { ret 9i32 }
    if !m(a, 0u8, "\\w+(?=!)", "hey you!", "4 7") { ret 10i32 }
    if !m(a, 0u8, "\\b(?!un)\\w+", "undo redo", "5 9") { ret 11i32 }
    if !m(a, 0u8, "(?=(\\w+))\\w", "abc", "0 1 0 3") { ret 12i32 }
    if !m(a, 0u8, "a(?!b)", "abac", "2 3") { ret 13i32 }
    if !m(a, 0u8, "(?=.*\\d)(?=.*[a-z])\\w{6,}", "abc12 abcdef1", "6 13") { ret 14i32 }
    if !m(a, 0u8, "(?<=\\$)\\d+", "cost: $42", "7 9") { ret 15i32 }
    if !m(a, 0u8, "(?<!\\$)\\b\\d+", "$42 17", "4 6") { ret 16i32 }
    if !m(a, 0u8, "(?<!a)b", "bab", "0 1") { ret 17i32 }
    if !m(a, 0u8, "(?<=a)b", "bab", "2 3") { ret 18i32 }
    if !m(a, 0u8, "(?<=ab|cd)x", "abycdx", "5 6") { ret 19i32 }
    if !m(a, 0u8, "(?<=é)x", "éx", "2 3") { ret 20i32 }
    if !m(a, 0u8, "(?<=^)a", "ba\na", "none") { ret 21i32 }
    if !m(a, 2u8, "(?<=^b)c", "a\nbc", "3 4") { ret 22i32 }
    if !m(a, 0u8, "(?=a(?!b))\\w+", "ab ac", "3 5") { ret 23i32 }
    if !m(a, 0u8, "(?<=(?<!x)a)b", "xab ab", "5 6") { ret 24i32 }
    if !m(a, 0u8, "q(?=u(?!i))", "quit quote", "5 6") { ret 25i32 }
    if !m(a, 0u8, "(?<=(a))(?=(b))", "ab", "1 1 0 1 1 2") { ret 26i32 }
    if !m(a, 0u8, "(?>a+)b", "aaab", "0 4") { ret 27i32 }
    if !m(a, 0u8, "(?>a+)ab", "aaab", "none") { ret 28i32 }
    if !m(a, 0u8, "(?>ab|a)b", "ab abb", "3 6") { ret 29i32 }
    if !m(a, 0u8, "(?>(a)|b)+c", "abac", "0 4 2 3") { ret 30i32 }
    if !m(a, 0u8, "a*+a", "aaaa", "none") { ret 31i32 }
    if !m(a, 0u8, "a++b", "aaab", "0 4") { ret 32i32 }
    if !m(a, 0u8, "\\\"[^\\\"]*+\\\"", "x \"quoted\" y", "2 10") { ret 33i32 }
    if !m(a, 0u8, "a?+a", "a", "none") { ret 34i32 }
    if !m(a, 0u8, "(ab){1,2}+b", "ababb", "0 5 2 4") { ret 35i32 }
    if !m(a, 0u8, "\\d{2,3}+\\d", "12345", "0 4") { ret 36i32 }
    if !m(a, 0u8, "(.?b){2}+", "bbcab", "0 2 1 2") { ret 37i32 }
    if !m(a, 0u8, "(a)|(b)", "b", "0 1 - - 0 1") { ret 38i32 }
    if !m(a, 0u8, "(?:(a)|b)*", "ab", "0 2 0 1") { ret 39i32 }
    if !m(a, 0u8, "(a|)*", "aa", "0 2 2 2") { ret 40i32 }
    if !m(a, 0u8, "(a*)+b", "aab", "0 3 2 2") { ret 41i32 }
    if !m(a, 0u8, "(a+)+$", "aaa", "0 3 0 3") { ret 42i32 }
    if !m(a, 0u8, "(\\d{4})-(\\d{2})(?:-(\\d{2}))?", "on 2027-01 x", "3 10 3 7 8 10 - -") { ret 43i32 }
    if !m(a, 4u8, "a.+?b(?=\\n)", "a\nxb\n", "0 4") { ret 44i32 }
    if !m(a, 2u8, "^(\\w)\\w*$", "ab\ncd", "0 2 0 1") { ret 45i32 }
    ret 0i32
}

fn replacements_and_refusals(a: *mem.Arena) -> i32 {
    if !rep(a, 0u8, "(\\w)\\1", "aabbcd", "<$1>", "<a><b>cd") { ret 46i32 }
    if !rep(a, 0u8, "\\b(\\w+)\\s+\\1\\b", "the the cat sat sat", "$1", "the cat sat") { ret 47i32 }
    if !rep(a, 1u8, "(?P<w>ab)\\k<w>", "abAB xabab", "[$0]", "[abAB] x[abab]") { ret 48i32 }
    if !rep(a, 0u8, "a++", "baaac", "-", "b-c") { ret 49i32 }
    if !rep(a, 0u8, "(?<=\\d)(\\d{3})(?!\\d)", "1234567", ",$1", "1234,567") { ret 50i32 }
    if !rep(a, 0u8, "(?<!\\w)(\\w)(\\w*)", "hi there", "$2$1ay", "ihay heretay") { ret 51i32 }
    if !refuses(a, "(a)\\1", false, regex.NeedsBacktracking) { ret 52i32 }
    if !refuses(a, "(?=a)", false, regex.NeedsBacktracking) { ret 53i32 }
    if !refuses(a, "(?!a)", false, regex.NeedsBacktracking) { ret 54i32 }
    if !refuses(a, "(?<=a)", false, regex.NeedsBacktracking) { ret 55i32 }
    if !refuses(a, "(?<!a)", false, regex.NeedsBacktracking) { ret 56i32 }
    if !refuses(a, "(?>a)", false, regex.NeedsBacktracking) { ret 57i32 }
    if !refuses(a, "a*+", false, regex.NeedsBacktracking) { ret 58i32 }
    if !refuses(a, "a{2}+", false, regex.NeedsBacktracking) { ret 59i32 }
    if !refuses(a, "(?<n>a)\\k<n>", false, regex.NeedsBacktracking) { ret 60i32 }
    if !refuses(a, "(?P<n>a)(?P=n)", false, regex.NeedsBacktracking) { ret 61i32 }
    if !refuses(a, "(?<=a+)b", true, regex.InvalidPattern) { ret 62i32 }
    if !refuses(a, "(?<=a|bc)d", true, regex.InvalidPattern) { ret 63i32 }
    if !refuses(a, "\\2(a)(b)", true, regex.InvalidPattern) { ret 64i32 }
    if !refuses(a, "(?<n>a)(?<n>b)", true, regex.InvalidPattern) { ret 65i32 }
    if !refuses(a, "\\k<zz>", true, regex.InvalidPattern) { ret 66i32 }
    if !refuses(a, "(?<1a>x)", true, regex.InvalidPattern) { ret 67i32 }
    if !refuses(a, "(?Px)", true, regex.InvalidPattern) { ret 68i32 }
    if !refuses(a, "(?<=\\1)(a)", true, regex.InvalidPattern) { ret 69i32 }
    ret 0i32
}

fn random_table(a: *mem.Arena) -> i32 {
    if !m(a, 0u8, "(?<=ab)", "caacba", "none") { ret 70i32 }
    if !m(a, 0u8, ".*?|[ab]*?(?<=a)a+", "aabbb", "0 0") { ret 71i32 }
    if !m(a, 0u8, "(?=c+?(?>b+?|a*?)?+a?)", "cb", "0 0") { ret 72i32 }
    if !m(a, 0u8, "b{2}(?:(b{2}|b[ab]+?a{2}+)?)", "aa", "none") { ret 73i32 }
    if !m(a, 0u8, "(?<!a)[ab]*+", "bbb", "0 3") { ret 74i32 }
    if !m(a, 0u8, "a++((?![ab]{2}a*c?)(a*?)){1,2}\\1|.*+(?>(?<=ab))?.?", "caabcccc", "0 8 - - - -") { ret 75i32 }
    if !m(a, 0u8, "(?!b(?<![ab]))", "b", "0 0") { ret 76i32 }
    if !m(a, 0u8, "(b*?){2}[ab]|(?>(?<!a)){1,2}+(\\1{2}+(?:[ab]?+|\\1{1,2}?.+){1,2}+(?>\\1?+.*+|[ab]a{2}){2})", "abc", "0 1 0 0 - -") { ret 77i32 }
    if !m(a, 0u8, "c*(?>(?>[ab][ab]){1,2}+(?>.?+.{1,2}[ab]{2}){2}?(?:a?){1,2}?){1,2}?(?<!.)", "cbbbaa", "none") { ret 78i32 }
    if !m(a, 0u8, "(?:a){2}?b|([ab](?<!ab))++", "accbc", "0 1 0 1") { ret 79i32 }
    if !m(a, 0u8, "([ab]+?.{2}?|c*){2}?", "acccbaa", "0 4 3 4") { ret 80i32 }
    if !m(a, 0u8, "(?=(?>b*b++.{1,2}?){1,2}+b*(?>ca?+[ab]??){2}+).{1,2}?", "bbbcbbcb", "none") { ret 81i32 }
    if !m(a, 0u8, "(?!([ab]{2}+.+)(?<!a))|(a*+b|(.a?[ab]??)([ab]?b{2}+){2}+)+", "", "0 0 - - - - - - - -") { ret 82i32 }
    if !m(a, 0u8, ".{1,2}", "caa", "0 2") { ret 83i32 }
    if !m(a, 0u8, "(?:(?>a*+a*?){1,2}?([ab]*?|.{1,2}+a{1,2}){2}+)", "b", "0 0 0 0") { ret 84i32 }
    if !m(a, 0u8, "(?<!ab)(?<=[ab])(b+)*+", "cac", "2 2 - -") { ret 85i32 }
    if !m(a, 0u8, "bb(?<!a|b)", "acbaacaaa", "none") { ret 86i32 }
    if !m(a, 0u8, "(?<!.)", "bcbcacbb", "0 0") { ret 87i32 }
    if !m(a, 0u8, "(.{2}+(?>a{1,2}a{1,2}b)(a{1,2}))\\1?.?+|(?<!ab)a[ab]", "cbccaba", "4 6 - - - -") { ret 88i32 }
    if !m(a, 0u8, "([ab]c??c{1,2})??", "bbba", "0 0 - -") { ret 89i32 }
    if !m(a, 0u8, "(?:[ab]+(?>a+a?+c|.)|(?<=b)[ab]+b{2}){1,2}+((?>.)*+)?", "acabcbbbb", "0 9 5 9") { ret 90i32 }
    if !m(a, 0u8, "(?!b)", "ab", "0 0") { ret 91i32 }
    if !m(a, 0u8, "(?:(?>c++|c{2}?b{1,2}[ab]+?)*(.{1,2})*\\1)((\\1?+|[ab]{1,2}?\\1){1,2}){2}b{2}", "bbcaba", "none") { ret 92i32 }
    if !m(a, 0u8, "(?!(?>a{1,2})(?<!a)(?>[ab]{2}+c??)+?|(?<=b)(?=[ab]??[ab]a).*)a*+|(?:(?!b*+a*).*|(?<=a|b)(?<=ab))(?>(?<!.)(?:[ab]+|[ab]*c+a)){2}", "ccca", "0 0") { ret 93i32 }
    if !m(a, 0u8, "(.)*", "cb", "0 2 1 2") { ret 94i32 }
    if !m(a, 0u8, "(?=(?<!a|b))((?>.*|b*?c{1,2}a*)?(c{1,2}+){2}?)+", "bbbb", "none") { ret 95i32 }
    if !m(a, 0u8, "(?!c{2}+|(?>.+.?+).)", "abcb", "0 0") { ret 96i32 }
    if !m(a, 0u8, "((?<!a)b{2}?)?", "bccaacccc", "0 0 - -") { ret 97i32 }
    if !m(a, 0u8, "(?<=a|b)(?<=b)[ab]++", "bbccc", "1 2") { ret 98i32 }
    if !m(a, 0u8, "(b??([ab]+[ab]{1,2}+)+)", "cbcccbcb", "none") { ret 99i32 }
    if !m(a, 0u8, "(?<!a|b)", "aabbca", "0 0") { ret 100i32 }
    if !m(a, 0u8, "(?!(.*?c+|.+)a+b)(?=(?:\\1*))|[ab](.*+)*+", "baab", "0 4 - - 4 4") { ret 101i32 }
    if !m(a, 0u8, "(?:(?:[ab]?+|c{2}.++){1,2}|(a+?.*?)([ab]a*+|a{2}){2}?)(?<!a|b)|(?<!b)b*+(?>\\1*[ab](?!.\\1{2}?)|(?:aab{1,2}?|a\\1a{1,2}?)?(\\1*?|b{2}.+?){1,2}+)+?", "bccaaabcb", "0 1 - - - - 1 1") { ret 102i32 }
    if !m(a, 0u8, "(?>c?+){1,2}?b{2}|c*", "b", "0 0") { ret 103i32 }
    if !m(a, 0u8, ".{1,2}", "", "none") { ret 104i32 }
    if !m(a, 0u8, "(b+(?<=a|b)([ab]*|a++)){2}?(b)?", "ccbaacaac", "none") { ret 105i32 }
    if !m(a, 0u8, "c{1,2}", "ab", "none") { ret 106i32 }
    if !m(a, 0u8, ".??", "", "0 0") { ret 107i32 }
    if !m(a, 0u8, "(?<!a|b)(?>b++(b*+.)??|(?<=b)(?<!a))", "", "none") { ret 108i32 }
    if !m(a, 0u8, "b+?(?<!a|b)((?=cb?)|(?<=[ab])a?a?+)*", "", "none") { ret 109i32 }
    ret 0i32
}

// `(a+)+$` over 40 `a`s and a `b` is exponential for a backtracker; the budget stops it.
fn budget(a: *mem.Arena) -> i32 {
    let (r, r_error) = regex.compile_backtracking(a, "(a+)+$", zero)
    if r_error != ok { ret 110i32 }
    let subject = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab"
    let (began, clock_error) = time.monotonic()
    if clock_error != ok { ret 111i32 }
    let (_, has, caps_error) = regex.captures(a, &r, subject, 0usize)
    if has || caps_error != regex.TooManySteps { ret 112i32 }
    if regex.is_match(&r, subject) || regex.last_error(&r) != regex.TooManySteps { ret 113i32 }
    let (_, replace_error) = regex.replace_all(a, &r, subject, "x")
    if replace_error != regex.TooManySteps { ret 114i32 }
    if time.since(began).nanos > 5000000000i64 { ret 115i32 }
    // The same Regex still answers a text it can settle, and clears the error.
    let (m1, found) = regex.find(&r, "xaaa", 0usize)
    if !found || m1.start != 1usize || m1.end != 4usize || regex.last_error(&r) != ok { ret 116i32 }
    ret 0i32
}

// A greedy loop over more scalars than the backtrack stack holds answers TooDeep, where
// the Pike VM takes it in stride.
fn depth(a: *mem.Arena) -> i32 {
    let (long, long_error) = mem.alloc[u8](a, 40000usize)
    if long_error != ok { ret 117i32 }
    var i = 0usize
    while i < long.len {
        long[i] = 97u8
        i += 1usize
    }
    let (r, r_error) = regex.compile_backtracking(a, "(?:a|b)*c", zero)
    if r_error != ok || regex.is_match(&r, long) || regex.last_error(&r) != regex.TooDeep { ret 118i32 }
    let (pike, pike_error) = regex.compile(a, "(?:a|b)*c", zero)
    if pike_error != ok || regex.is_match(&pike, long) || regex.last_error(&pike) != ok { ret 119i32 }
    ret 0i32
}

// Named groups are regular, so the Pike VM takes them too; group_index finds them.
fn names(a: *mem.Arena) -> i32 {
    let (r, r_error) = regex.compile(a, "(?<year>\\d{4})-(?P<month>\\d\\d)", zero)
    if r_error != ok { ret 120i32 }
    let (year, has_year) = regex.group_index(&r, "year")
    let (month, has_month) = regex.group_index(&r, "month")
    let (_, has_day) = regex.group_index(&r, "day")
    if !has_year || year != 1usize || !has_month || month != 2usize || has_day { ret 121i32 }
    let (caps, has, caps_error) = regex.captures(a, &r, "on 2026-09-29", 0usize)
    if caps_error != ok || !has || caps.whole.start != 3usize || caps.whole.end != 10usize { ret 122i32 }
    if caps.groups[0].start != 3usize || caps.groups[0].end != 7usize || caps.groups[1].start != 8usize || caps.groups[1].end != 10usize { ret 123i32 }
    let (b, b_error) = regex.compile_backtracking(a, "(?<w>x)(?<v>y)\\k<v>", zero)
    let (v, has_v) = regex.group_index(&b, "v")
    if b_error != ok || !has_v || v != 2usize || !regex.is_match(&b, "xyy") || regex.is_match(&b, "xyx") { ret 124i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let constructs_code = constructs(a)
    if constructs_code != 0i32 { os.exit(constructs_code) }
    let replacements_and_refusals_code = replacements_and_refusals(a)
    if replacements_and_refusals_code != 0i32 { os.exit(replacements_and_refusals_code) }
    let random_table_code = random_table(a)
    if random_table_code != 0i32 { os.exit(random_table_code) }
    let budget_code = budget(a)
    if budget_code != 0i32 { os.exit(budget_code) }
    let depth_code = depth(a)
    if depth_code != 0i32 { os.exit(depth_code) }
    let names_code = names(a)
    if names_code != 0i32 { os.exit(names_code) }
    try io.print("text regex backtrack ok\n")
    ret ok
}
