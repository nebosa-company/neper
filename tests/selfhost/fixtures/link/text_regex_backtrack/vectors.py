# Writes src/main.e: every expected span, group and replacement comes from Python 3.12 `re`
# (re.ASCII, since `\d \w \s \b` are ASCII in e.text.regex), offsets turned into bytes.
# Run: python vectors.py
import random
import re
import sys
from pathlib import Path

assert sys.version_info >= (3, 11), "atomic groups and possessive repeats need Python 3.11+"

FLAGS = {1: re.IGNORECASE, 2: re.MULTILINE, 4: re.DOTALL}


def py_flags(flags):
    out = re.ASCII
    for bit, flag in FLAGS.items():
        if flags & bit:
            out |= flag
    return out


def py_pattern(pattern):
    # Python spells `(?<name>...)` and `\k<name>` only as `(?P<name>...)` and `(?P=name)`.
    pattern = re.sub(r"\(\?<([A-Za-z_]\w*)>", r"(?P<\1>", pattern)
    return re.sub(r"\\k<(\w+)>", r"(?P=\1)", pattern)


def py_compile(pattern, flags=0):
    return re.compile(py_pattern(pattern), py_flags(flags))


def lit(s):
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 32:
            out.append("\\x%02x" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def byte_at(text, i):
    return len(text[:i].encode("utf-8"))


def describe(flags, pattern, text):
    m = py_compile(pattern, flags).search(text)
    if m is None:
        return "none"
    parts = [str(byte_at(text, m.start())), str(byte_at(text, m.end()))]
    for g in range(1, (m.re.groups) + 1):
        s, e = m.span(g)
        if s < 0:
            parts += ["-", "-"]
        else:
            parts += [str(byte_at(text, s)), str(byte_at(text, e))]
    return " ".join(parts)


def py_replacement(ours):
    out, i = [], 0
    while i < len(ours):
        if ours[i] == "$" and i + 1 < len(ours) and ours[i + 1] == "$":
            out.append("$")
            i += 2
        elif ours[i] == "$" and i + 1 < len(ours) and ours[i + 1].isdigit():
            out.append("\\g<%s>" % ours[i + 1])
            i += 2
        else:
            out.append("\\\\" if ours[i] == "\\" else ours[i])
            i += 1
    return "".join(out)


# (flags, pattern, text): 1 case_insensitive, 2 multiline, 4 dot_matches_newline.
CONSTRUCTS = [
    # Backreferences, numbered and named, including one to a group that took no part.
    (0, r"(\w+) \1", "hello hello world"),
    (0, r"(a)(b)?\2", "ab ab"),
    (0, r"(a|b)\1+", "abbbab"),
    (0, r"<(\w+)>.*?</\1>", "<b>bold</b><i>x</i>"),
    (0, r"(?<q>['\"]).*?\k<q>", "say \"hi\" 'x'"),
    (0, r"(?P<x>[a-z]+)-(?P=x)", "foo-bar bar-bar"),
    # Case-insensitive backreferences and lookbehind.
    (1, r"(ab)\1", "xabAB"),
    (1, r"(?P<x>[a-z]+)-(?P=x)", "Foo-FOO"),
    (1, r"(?<=A)b", "aB"),
    # Lookahead.
    (0, r"\w+(?=!)", "hey you!"),
    (0, r"\b(?!un)\w+", "undo redo"),
    (0, r"(?=(\w+))\w", "abc"),
    (0, r"a(?!b)", "abac"),
    (0, r"(?=.*\d)(?=.*[a-z])\w{6,}", "abc12 abcdef1"),
    # Lookbehind, including at the start of the text and over a multi-byte scalar.
    (0, r"(?<=\$)\d+", "cost: $42"),
    (0, r"(?<!\$)\b\d+", "$42 17"),
    (0, r"(?<!a)b", "bab"),
    (0, r"(?<=a)b", "bab"),
    (0, r"(?<=ab|cd)x", "abycdx"),
    (0, r"(?<=é)x", "éx"),
    (0, r"(?<=^)a", "ba\na"),
    (2, r"(?<=^b)c", "a\nbc"),
    # Nested lookaround.
    (0, r"(?=a(?!b))\w+", "ab ac"),
    (0, r"(?<=(?<!x)a)b", "xab ab"),
    (0, r"q(?=u(?!i))", "quit quote"),
    (0, r"(?<=(a))(?=(b))", "ab"),
    # Atomic groups.
    (0, r"(?>a+)b", "aaab"),
    (0, r"(?>a+)ab", "aaab"),
    (0, r"(?>ab|a)b", "ab abb"),
    (0, r"(?>(a)|b)+c", "abac"),
    # Possessive repeats.
    (0, r"a*+a", "aaaa"),
    (0, r"a++b", "aaab"),
    (0, r"\"[^\"]*+\"", "x \"quoted\" y"),
    (0, r"a?+a", "a"),
    (0, r"(ab){1,2}+b", "ababb"),
    (0, r"\d{2,3}+\d", "12345"),
    # CPython 3.12 does not backtrack into earlier iterations of an exact possessive count
    # (`(.?b){2}+` finds nothing in "bbcab"), against its own documentation that `x{m,n}+`
    # is `(?>x{m,n})`; the documented spelling is the oracle here. Random probes over 3,300
    # patterns disagreed with Python only on such `{n}+` cases.
    (0, r"(.?b){2}+", "bbcab", r"(?>(.?b){2})"),
    # Groups that did not take part, empty iterations, the Pike VM syntax as before.
    (0, r"(a)|(b)", "b"),
    (0, r"(?:(a)|b)*", "ab"),
    (0, r"(a|)*", "aa"),
    (0, r"(a*)+b", "aab"),
    (0, r"(a+)+$", "aaa"),
    (0, r"(\d{4})-(\d{2})(?:-(\d{2}))?", "on 2027-01 x"),
    (4, r"a.+?b(?=\n)", "a\nxb\n"),
    (2, r"^(\w)\w*$", "ab\ncd"),
]

REPLACEMENTS = [
    (0, r"(\w)\1", "aabbcd", "<$1>"),
    (0, r"\b(\w+)\s+\1\b", "the the cat sat sat", "$1"),
    (1, r"(?P<w>ab)\k<w>", "abAB xabab", "[$0]"),
    (0, r"a++", "baaac", "-"),
    (0, r"(?<=\d)(\d{3})(?!\d)", "1234567", ",$1"),
    (0, r"(?<!\w)(\w)(\w*)", "hi there", "$2$1ay"),
]

# Refused by `compile` (NeedsBacktracking) and by both engines (InvalidPattern); Python
# must accept the first list and refuse the second.
NEEDS = [r"(a)\1", r"(?=a)", r"(?!a)", r"(?<=a)", r"(?<!a)", r"(?>a)", r"a*+", r"a{2}+", r"(?<n>a)\k<n>", r"(?P<n>a)(?P=n)"]
INVALID = [r"(?<=a+)b", r"(?<=a|bc)d", r"\2(a)(b)", r"(?<n>a)(?<n>b)", r"\k<zz>", r"(?<1a>x)", r"(?Px)", r"(?<=\1)(a)"]


def random_patterns(count):
    rng = random.Random(352)

    def atom(depth, closed):
        choice = rng.randrange(12 if depth < 2 else 5)
        if choice == 0:
            return "a"
        if choice == 1:
            return "b"
        if choice == 2:
            return "."
        if choice == 3:
            return "[ab]"
        if choice == 4:
            return "\\1" if closed[0] else "c"
        inner = alt(depth + 1, closed)
        if choice in (5, 6):
            text = "(" + inner + ")"
            closed[0] = True
            return text
        if choice == 7:
            return "(?:" + inner + ")"
        if choice == 8:
            return "(?>" + inner + ")"
        if choice == 9:
            return rng.choice(["(?=", "(?!"]) + inner + ")"
        return rng.choice(["(?<=", "(?<!"]) + rng.choice(["a", "b", "ab", "[ab]", "a|b", "."]) + ")"

    def item(depth, closed):
        text = atom(depth, closed)
        if text.startswith("(?=") or text.startswith("(?!") or text.startswith("(?<"):
            return text
        q = rng.choice(["", "", "*", "+", "?", "{1,2}", "{2}"])
        if q:
            q += rng.choice(["", "", "?", "+"])
        return text + q

    def alt(depth, closed):
        branches = []
        for _ in range(rng.choice([1, 1, 2])):
            branches.append("".join(item(depth, closed) for _ in range(rng.randint(1, 3))))
        return "|".join(branches)

    out = []
    while len(out) < count:
        closed = [False]
        pattern = alt(0, closed)
        try:
            re.compile(pattern, re.ASCII)
        except re.error:
            continue
        text = "".join(rng.choice("abc") for _ in range(rng.randint(0, 9)))
        out.append((0, pattern, text))
    return out


def main():
    here = Path(__file__).resolve().parent
    for p in NEEDS:
        py_compile(p)
    for p in INVALID:
        try:
            py_compile(p)
        except re.error:
            continue
        raise SystemExit("Python accepts " + p)

    lines = []
    w = lines.append
    w("// Backtracking regular expressions (`regex.compile_backtracking`): backreferences numbered")
    w("// and named, case-insensitive backreferences, lookahead, lookbehind (at the start of the")
    w("// text, over multi-byte scalars, multiline), nested lookaround, atomic groups, possessive")
    w("// repeats, groups that took no part, replace_all through the backtracker, a table of")
    w("// random patterns, `compile` refusing what needs a backtracker, the step budget stopping")
    w("// `(a+)+$` quickly, the stack bound, and named groups under the Pike VM. Every expected")
    w("// value is from Python 3.12 `re`, written by vectors.py next to this directory's src/.")
    w("")
    w("use e.io")
    w("use e.mem")
    w("use e.os")
    w("use e.text.regex")
    w("use e.time")
    w("")
    w("const NONE: usize = 18446744073709551615usize")
    w("")
    w("fn options(flags: u8) -> regex.Options {")
    w("    ret regex.Options { case_insensitive: (flags & 1u8) != 0u8, multiline: (flags & 2u8) != 0u8, dot_matches_newline: (flags & 4u8) != 0u8 }")
    w("}")
    w("")
    w("fn put_str(buf: []u8, at: usize, s: str) -> usize {")
    w("    mem.copy[u8](buf[at..at + s.len], s)")
    w("    ret at + s.len")
    w("}")
    w("")
    w("fn put_num(buf: []u8, at: usize, v: usize) -> usize {")
    w("    if v == NONE { ret put_str(buf, at, \"-\") }")
    w("    var digits: [20]u8 = zero")
    w("    var n = 0usize")
    w("    var rest = v")
    w("    while n == 0usize || rest > 0usize {")
    w("        digits[n] = u8(rest % 10usize) + 48u8")
    w("        rest = rest / 10usize")
    w("        n += 1usize")
    w("    }")
    w("    var used = at")
    w("    while n > 0usize {")
    w("        n -= 1usize")
    w("        buf[used] = digits[n]")
    w("        used += 1usize")
    w("    }")
    w("    ret used")
    w("}")
    w("")
    w("fn report(pattern: str, got: str, want: str) {")
    w("    let _ = io.print(pattern)")
    w("    let _ = io.print(\"\\n  got:  \")")
    w("    let _ = io.print(got)")
    w("    let _ = io.print(\"\\n  want: \")")
    w("    let _ = io.print(want)")
    w("    let _ = io.print(\"\\n\")")
    w("}")
    w("")
    w("// The first match of `pattern` in `subject` as \"start end g1start g1end ...\", `-` for a")
    w("// group that took no part, or \"none\", against Python's answer.")
    w("fn m(a: *mem.Arena, flags: u8, pattern: str, subject: str, want: str) -> bool {")
    w("    let mark = a.off")
    w("    var buf: [512]u8 = zero")
    w("    var n = 0usize")
    w("    let (r, r_error) = regex.compile_backtracking(a, pattern, options(flags))")
    w("    if r_error != ok {")
    w("        report(pattern, \"compile failed\", want)")
    w("        ret false")
    w("    }")
    w("    let (caps, has, caps_error) = regex.captures(a, &r, subject, 0usize)")
    w("    if caps_error != ok {")
    w("        report(pattern, \"captures failed\", want)")
    w("        ret false")
    w("    }")
    w("    if !has {")
    w("        n = put_str(buf[0..], n, \"none\")")
    w("    } else {")
    w("        n = put_num(buf[0..], n, caps.whole.start)")
    w("        n = put_str(buf[0..], n, \" \")")
    w("        n = put_num(buf[0..], n, caps.whole.end)")
    w("        var g = 0usize")
    w("        while g < caps.groups.len {")
    w("            n = put_str(buf[0..], n, \" \")")
    w("            n = put_num(buf[0..], n, caps.groups[g].start)")
    w("            n = put_str(buf[0..], n, \" \")")
    w("            n = put_num(buf[0..], n, caps.groups[g].end)")
    w("            g += 1usize")
    w("        }")
    w("    }")
    w("    let same = mem.eq[u8](buf[..n], want)")
    w("    if !same { report(pattern, buf[..n], want) }")
    w("    a.off = mark")
    w("    ret same")
    w("}")
    w("")
    w("fn rep(a: *mem.Arena, flags: u8, pattern: str, subject: str, replacement: str, want: str) -> bool {")
    w("    let mark = a.off")
    w("    let (r, r_error) = regex.compile_backtracking(a, pattern, options(flags))")
    w("    if r_error != ok { ret false }")
    w("    let (out, out_error) = regex.replace_all(a, &r, subject, replacement)")
    w("    let same = out_error == ok && mem.eq[u8](out, want)")
    w("    if !same { report(pattern, out, want) }")
    w("    a.off = mark")
    w("    ret same")
    w("}")
    w("")
    w("fn refuses(a: *mem.Arena, pattern: str, backtracking: bool, expected: err) -> bool {")
    w("    let mark = a.off")
    w("    var r_error = ok")
    w("    if backtracking {")
    w("        let (_, e) = regex.compile_backtracking(a, pattern, zero)")
    w("        r_error = e")
    w("    } else {")
    w("        let (_, e) = regex.compile(a, pattern, zero)")
    w("        r_error = e")
    w("    }")
    w("    a.off = mark")
    w("    if r_error != expected { report(pattern, \"a different answer\", \"a refusal\") }")
    w("    ret r_error == expected")
    w("}")
    w("")

    code = [0]

    def check(expr):
        code[0] += 1
        return "    if !%s { ret %di32 }" % (expr, code[0])

    def emit_table(name, rows):
        w("fn %s(a: *mem.Arena) -> i32 {" % name)
        for row in rows:
            w(row)
        w("    ret 0i32")
        w("}")
        w("")

    rows = [check("m(a, %du8, %s, %s, %s)" % (c[0], lit(c[1]), lit(c[2]), lit(describe(c[0], c[-1] if len(c) > 3 else c[1], c[2])))) for c in CONSTRUCTS]
    emit_table("constructs", rows)

    rows = []
    for f, p, t, r in REPLACEMENTS:
        want = py_compile(p, f).sub(py_replacement(r), t)
        rows.append(check("rep(a, %du8, %s, %s, %s, %s)" % (f, lit(p), lit(t), lit(r), lit(want))))
    for p in NEEDS:
        rows.append(check("refuses(a, %s, false, regex.NeedsBacktracking)" % lit(p)))
    for p in INVALID:
        rows.append(check("refuses(a, %s, true, regex.InvalidPattern)" % lit(p)))
    emit_table("replacements_and_refusals", rows)

    rows = [check("m(a, %du8, %s, %s, %s)" % (f, lit(p), lit(t), lit(describe(f, p, t)))) for f, p, t in random_patterns(40)]
    emit_table("random_table", rows)

    base = code[0]
    w("// `(a+)+$` over 40 `a`s and a `b` is exponential for a backtracker; the budget stops it.")
    w("fn budget(a: *mem.Arena) -> i32 {")
    w("    let (r, r_error) = regex.compile_backtracking(a, \"(a+)+$\", zero)")
    w("    if r_error != ok { ret %di32 }" % (base + 1))
    w("    let subject = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab\"")
    w("    let (began, clock_error) = time.monotonic()")
    w("    if clock_error != ok { ret %di32 }" % (base + 2))
    w("    let (_, has, caps_error) = regex.captures(a, &r, subject, 0usize)")
    w("    if has || caps_error != regex.TooManySteps { ret %di32 }" % (base + 3))
    w("    if regex.is_match(&r, subject) || regex.last_error(&r) != regex.TooManySteps { ret %di32 }" % (base + 4))
    w("    let (_, replace_error) = regex.replace_all(a, &r, subject, \"x\")")
    w("    if replace_error != regex.TooManySteps { ret %di32 }" % (base + 5))
    w("    if time.since(began).nanos > 5000000000i64 { ret %di32 }" % (base + 6))
    w("    // The same Regex still answers a text it can settle, and clears the error.")
    w("    let (m1, found) = regex.find(&r, \"xaaa\", 0usize)")
    w("    if !found || m1.start != 1usize || m1.end != 4usize || regex.last_error(&r) != ok { ret %di32 }" % (base + 7))
    w("    ret 0i32")
    w("}")
    w("")
    w("// A greedy loop over more scalars than the backtrack stack holds answers TooDeep, where")
    w("// the Pike VM takes it in stride.")
    w("fn depth(a: *mem.Arena) -> i32 {")
    w("    let (long, long_error) = mem.alloc[u8](a, 40000usize)")
    w("    if long_error != ok { ret %di32 }" % (base + 8))
    w("    var i = 0usize")
    w("    while i < long.len {")
    w("        long[i] = 97u8")
    w("        i += 1usize")
    w("    }")
    w("    let (r, r_error) = regex.compile_backtracking(a, \"(?:a|b)*c\", zero)")
    w("    if r_error != ok || regex.is_match(&r, long) || regex.last_error(&r) != regex.TooDeep { ret %di32 }" % (base + 9))
    w("    let (pike, pike_error) = regex.compile(a, \"(?:a|b)*c\", zero)")
    w("    if pike_error != ok || regex.is_match(&pike, long) || regex.last_error(&pike) != ok { ret %di32 }" % (base + 10))
    w("    ret 0i32")
    w("}")
    w("")
    date = "on 2026-09-29"
    want = describe(0, r"(?<year>\d{4})-(?P<month>\d\d)", date)
    w("// Named groups are regular, so the Pike VM takes them too; group_index finds them.")
    w("fn names(a: *mem.Arena) -> i32 {")
    w("    let (r, r_error) = regex.compile(a, %s, zero)" % lit(r"(?<year>\d{4})-(?P<month>\d\d)"))
    w("    if r_error != ok { ret %di32 }" % (base + 11))
    w("    let (year, has_year) = regex.group_index(&r, \"year\")")
    w("    let (month, has_month) = regex.group_index(&r, \"month\")")
    w("    let (_, has_day) = regex.group_index(&r, \"day\")")
    w("    if !has_year || year != 1usize || !has_month || month != 2usize || has_day { ret %di32 }" % (base + 12))
    w("    let (caps, has, caps_error) = regex.captures(a, &r, %s, 0usize)" % lit(date))
    parts = [int(x) for x in want.split()]
    w("    if caps_error != ok || !has || caps.whole.start != %dusize || caps.whole.end != %dusize { ret %di32 }" % (parts[0], parts[1], base + 13))
    w("    if caps.groups[0].start != %dusize || caps.groups[0].end != %dusize || caps.groups[1].start != %dusize || caps.groups[1].end != %dusize { ret %di32 }" % (parts[2], parts[3], parts[4], parts[5], base + 14))
    w("    let (b, b_error) = regex.compile_backtracking(a, \"(?<w>x)(?<v>y)\\\\k<v>\", zero)")
    w("    let (v, has_v) = regex.group_index(&b, \"v\")")
    w("    if b_error != ok || !has_v || v != 2usize || !regex.is_match(&b, \"xyy\") || regex.is_match(&b, \"xyx\") { ret %di32 }" % (base + 15))
    w("    ret 0i32")
    w("}")
    w("")
    w("fn main(a: *mem.Arena, args: []str) -> err {")
    for fn in ["constructs", "replacements_and_refusals", "random_table", "budget", "depth", "names"]:
        w("    let %s_code = %s(a)" % (fn, fn))
        w("    if %s_code != 0i32 { os.exit(%s_code) }" % (fn, fn))
    w("    try io.print(\"text regex backtrack ok\\n\")")
    w("    ret ok")
    w("}")
    assert code[0] + 15 < 256, "exit codes must stay below 256"
    (here / "src").mkdir(exist_ok=True)
    (here / "src" / "main.e").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


main()
