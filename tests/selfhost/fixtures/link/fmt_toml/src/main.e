// `e.fmt.toml`: the event stream over a document that uses every construct is flattened to
// one `absolute.path=K:value` line per leaf and compared with the same flattening of Python's
// `tomllib` result (scratchpad toml_ref.py); floats are compared by their bits. Then the
// refusals tomllib shares, and the corners where the event shape itself is the thing to pin.
// Each check exits with its own code.

use e.fmt.toml
use e.io
use e.mem
use e.os
use e.str

// The trace: a base path that grows as containers open and shrinks as they close, and the
// lines written for every leaf under it.
type Trace = struct {
    base: [512]u8,
    base_len: usize,
    marks: [16]usize,
    index: [16]usize,
    depth: usize,
    out: str.Builder,
    array_table: [128]u8,
    array_table_len: usize,
    array_index: usize,
}

fn append(t: *Trace, s: str) {
    var i = 0usize
    while i < s.len {
        t.base[t.base_len] = s[i]
        t.base_len += 1usize
        i += 1usize
    }
}

fn append_path(t: *Trace, path: []const str) {
    var i = 0usize
    while i < path.len {
        if t.base_len > 0usize { append(t, ".") }
        append(t, path[i])
        i += 1usize
    }
}

fn append_index(t: *Trace, n: usize) {
    var digits: [24]u8 = zero
    var at = 24usize
    var rest = n
    if rest == 0usize {
        at -= 1usize
        digits[at] = 48u8
    }
    while rest > 0usize {
        at -= 1usize
        digits[at] = 48u8 + u8(rest % 10usize)
        rest = rest / 10usize
    }
    if t.base_len > 0usize { append(t, ".") }
    append(t, digits[at..24usize])
}

fn leaf(t: *Trace, v: toml.Value) -> err {
    try str.push(&t.out, t.base[0usize..t.base_len])
    try str.push(&t.out, "=")
    if v.kind == .String {
        try str.push(&t.out, "S:")
        try str.push(&t.out, v.text)
    } else if v.kind == .Integer {
        try str.push(&t.out, "I:")
        try str.push_i64(&t.out, v.integer)
    } else if v.kind == .Float {
        try str.push(&t.out, "F:")
        try str.push_hex_u64(&t.out, mem.bitcast[u64](v.float))
    } else if v.kind == .Bool {
        try str.push(&t.out, "B:")
        if v.boolean { try str.push(&t.out, "true") } else { try str.push(&t.out, "false") }
    } else {
        try str.push(&t.out, "D:")
        try str.push(&t.out, v.text)
    }
    ret str.push(&t.out, "\n")
}

// The base already names the value; a container keeps it as the prefix of its members.
fn on_value(t: *Trace, v: toml.Value, mark: usize) -> err {
    if v.kind == .ArrayStart || v.kind == .InlineTableStart {
        t.marks[t.depth] = mark
        t.index[t.depth] = 0usize
        t.depth += 1usize
        ret ok
    }
    try leaf(t, v)
    t.base_len = mark
    ret ok
}

fn on_event(t: *Trace, ev: toml.Event) -> err {
    if ev.kind == .TableStart {
        t.base_len = 0usize
        append_path(t, ev.path)
        ret ok
    }
    if ev.kind == .ArrayTableStart {
        t.base_len = 0usize
        append_path(t, ev.path)
        if str.eq(t.base[0usize..t.base_len], t.array_table[0usize..t.array_table_len]) {
            t.array_index += 1usize
        } else {
            t.array_index = 0usize
            var i = 0usize
            while i < t.base_len {
                t.array_table[i] = t.base[i]
                i += 1usize
            }
            t.array_table_len = t.base_len
        }
        append_index(t, t.array_index)
        ret ok
    }
    let mark = t.base_len
    if ev.kind == .Key {
        append_path(t, ev.path)
        ret on_value(t, ev.value, mark)
    }
    // A Value event: a member of the innermost array, or the end of a container.
    if ev.value.kind == .ArrayEnd || ev.value.kind == .InlineTableEnd {
        t.depth -= 1usize
        t.base_len = t.marks[t.depth]
        ret ok
    }
    append_index(t, t.index[t.depth - 1usize])
    t.index[t.depth - 1usize] += 1usize
    ret on_value(t, ev.value, mark)
}

// Every event until the end or the first error, which is the answer.
fn outcome(source: str) -> err {
    var keys: [8]str = zero
    var scratch: [256]u8 = zero
    var p = toml.parser(source, keys[..], scratch[..])
    while true {
        let (ev, e) = toml.parse(&p)
        if e != ok { ret e }
        if ev.kind == .End { ret ok }
    }
    ret ok
}

// The value of the one key a source holds.
fn only_value(source: str, scratch: []u8) -> (toml.Value, err) {
    var keys: [8]str = zero
    var p = toml.parser(source, keys[..], scratch)
    let (ev, e) = toml.parse(&p)
    if e != ok { ret (zero, e) }
    if ev.kind != .Key { ret (zero, toml.Invalid) }
    ret (ev.value, ok)
}

fn doc() -> str {
    ret "# top comment\ntitle = \"TOML \\\"Example\\\"\"   # trailing comment\nbare-key = 'literal \\n kept'\n\"quoted key\" = 1\nesc = \"tab\\tnl\\nuni\\u00e9\\U0001F600\"\nml = \"\"\"\nRoses are red\nViolets are blue\"\"\"\nmlb = \"\"\"\\\n  The quick brown \\\n  fox.\"\"\"\nmll = '''\nno \\escape here'''\nint1 = +99\nint2 = -17\nint3 = 1_000_000\nhex = 0xDEAD_BEEF\noct = 0o755\nbin = 0b1101\nflt1 = +1.0\nflt2 = 3.1415\nflt3 = -0.01\nflt4 = 5e+22\nflt5 = 6.626E-34\nflt6 = 224_617.445_991_228\ninf1 = inf\ninf2 = -inf\nnan1 = nan\nbools = [true, false]\nodt = 1979-05-27T07:32:00+00:00\nldt = 1979-05-27T00:32:00.999999\nld = 1979-05-27\nlt = 07:32:00\nnested = [[1, 2], [\"a\", \"b\"]]\nmixed = [ 1, 2.5, \"s\", {x = 1, y = [2]}, ]\nempty = []\npoint = { x = 1, y = 2, name = \"p\" }\ndeep = { a = { b = 1 }, c = 2 }\n\n[server]\nhost = \"example.com\"\nports = [ 8000, 8001,\n  8002 ]  # comment inside array\n\n[server.tls]\nenabled = true\n\n[[products]]\nname = \"Hammer\"\nsku = 738594937\n\n[[products]]\n\n[[products]]\nname = \"Nail\"\ncolor = \"gray\"\n\n[dotted]\na.b.c = 1\na . d = 2\n"
}
fn expected() -> str {
    ret "title=S:TOML \"Example\"\nbare-key=S:literal \\n kept\nquoted key=I:1\nesc=S:tab\tnl\nunié😀\nml=S:Roses are red\nViolets are blue\nmlb=S:The quick brown fox.\nmll=S:no \\escape here\nint1=I:99\nint2=I:-17\nint3=I:1000000\nhex=I:3735928559\noct=I:493\nbin=I:13\nflt1=F:3ff0000000000000\nflt2=F:400921cac083126f\nflt3=F:bf847ae147ae147b\nflt4=F:44a52d02c7e14af6\nflt5=F:390b85f8c5445f02\nflt6=F:410b6b4b9163d955\ninf1=F:7ff0000000000000\ninf2=F:fff0000000000000\nnan1=F:7ff8000000000000\nbools.0=B:true\nbools.1=B:false\nodt=D:1979-05-27T07:32:00+00:00\nldt=D:1979-05-27T00:32:00.999999\nld=D:1979-05-27\nlt=D:07:32:00\nnested.0.0=I:1\nnested.0.1=I:2\nnested.1.0=S:a\nnested.1.1=S:b\nmixed.0=I:1\nmixed.1=F:4004000000000000\nmixed.2=S:s\nmixed.3.x=I:1\nmixed.3.y.0=I:2\npoint.x=I:1\npoint.y=I:2\npoint.name=S:p\ndeep.a.b=I:1\ndeep.c=I:2\nserver.host=S:example.com\nserver.ports.0=I:8000\nserver.ports.1=I:8001\nserver.ports.2=I:8002\nserver.tls.enabled=B:true\nproducts.0.name=S:Hammer\nproducts.0.sku=I:738594937\nproducts.2.name=S:Nail\nproducts.2.color=S:gray\ndotted.a.b.c=I:1\ndotted.a.d=I:2\n"
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1-2: the whole document, flattened, against tomllib's reading of it.
    var keys: [16]str = zero
    var scratch: [1024]u8 = zero
    var p = toml.parser(doc(), keys[..], scratch[..])
    var t: Trace = zero
    let (out, out_error) = str.builder(a, 4096usize)
    if out_error != ok { ret out_error }
    t.out = out
    while true {
        let (ev, e) = toml.parse(&p)
        if e != ok {
            try io.print("parse error before offset ")
            try io.print(doc()[0usize..p.at])
            try io.print("\n")
            os.exit(1i32)
        }
        if ev.kind == .End { break }
        try on_event(&t, ev)
    }
    let got = str.done(&t.out)
    if !str.eq(got, expected()) {
        try io.print(got)
        os.exit(2i32)
    }

    // 3-14: what tomllib refuses, refused here too. Each is `Invalid`, since it is a shape the
    // grammar has no reading for.
    if outcome("a = \"abc\n") != toml.Invalid { os.exit(3i32) }
    if outcome("a = \"\\q\"\n") != toml.Invalid { os.exit(4i32) }
    if outcome("a 1\n") != toml.Invalid { os.exit(5i32) }
    if outcome("a = [1, 2\n") != toml.Invalid { os.exit(6i32) }
    if outcome("a = 1 b = 2\n") != toml.Invalid { os.exit(7i32) }
    if outcome("a = 01\n") != toml.Invalid { os.exit(8i32) }
    if outcome("a = 1__2\n") != toml.Invalid { os.exit(9i32) }
    if outcome("[t\n") != toml.Invalid { os.exit(10i32) }
    if outcome("a = {x = 1,}\n") != toml.Invalid { os.exit(11i32) }
    if outcome("a = 'x\n") != toml.Invalid { os.exit(12i32) }
    if outcome("= 1\n") != toml.Invalid { os.exit(13i32) }
    if outcome("a = \"\"\"x\n") != toml.Invalid { os.exit(14i32) }

    // 15: a decoded string that does not fit the scratch is `TooLarge`, not truncated.
    var small: [4]u8 = zero
    let (_, too_large) = only_value("a = \"abcdef\"\n", small[..])
    if too_large != toml.TooLarge { os.exit(15i32) }
    // 16: a literal string borrows the source and needs no scratch at all.
    let (borrowed, borrowed_error) = only_value("a = 'abcdef'\n", small[..])
    if borrowed_error != ok || !str.eq(borrowed.text, "abcdef") { os.exit(16i32) }

    // 17-19: valid datetime spellings retain their original delimiter and offset form.
    var room: [64]u8 = zero
    let (zulu, zulu_error) = only_value("a = 1979-05-27T07:32:00Z\n", room[..])
    if zulu_error != ok || zulu.kind != .Datetime || !str.eq(zulu.text, "1979-05-27T07:32:00Z") { os.exit(17i32) }
    let (spaced, spaced_error) = only_value("a = 1979-05-27 07:32:00Z # c\n", room[..])
    if spaced_error != ok || spaced.kind != .Datetime || !str.eq(spaced.text, "1979-05-27 07:32:00Z") { os.exit(18i32) }
    let (lower, lower_error) = only_value("a = 1979-05-27t07:32:00-07:00\n", room[..])
    if lower_error != ok || lower.kind != .Datetime || !str.eq(lower.text, "1979-05-27t07:32:00-07:00") { os.exit(19i32) }

    // 20-21: a quoted key part keeps its dot; the path is two parts, not three.
    var parts: [8]str = zero
    var q = toml.parser("\"a.b\".c = 1\n", parts[..], room[..])
    let (dotted, dotted_error) = toml.parse(&q)
    if dotted_error != ok || dotted.kind != .Key || dotted.path.len != 2usize { os.exit(20i32) }
    if !str.eq(dotted.path[0usize], "a.b") || !str.eq(dotted.path[1usize], "c") { os.exit(21i32) }

    // 22-23: a multi-line string's closing run may carry two quotes of content, and the whole
    // closing of `''''''` is empty.
    let (quoted, quoted_error) = only_value("a = \"\"\"x\"\"\"\"\"\n", room[..])
    if quoted_error != ok || !str.eq(quoted.text, "x\"\"") { os.exit(22i32) }
    let (nothing, nothing_error) = only_value("a = ''''''\n", room[..])
    if nothing_error != ok || nothing.text.len != 0usize { os.exit(23i32) }

    // 24-25: the extremes of an integer are exact, and one past them is `Invalid`.
    let (least, least_error) = only_value("a = -9_223_372_036_854_775_808\n", room[..])
    if least_error != ok || least.integer != -9223372036854775807i64 - 1i64 { os.exit(24i32) }
    let (_, past) = only_value("a = 9223372036854775808\n", room[..])
    if past != toml.Invalid { os.exit(25i32) }

    // 26: nesting past the parser's stack is `TooDeep` rather than a silent stop.
    if outcome("a = [[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[1]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]\n") != toml.TooDeep { os.exit(26i32) }

    // 27: the top-level statement after a container must still end its line.
    if outcome("a = [1] b = 2\n") != toml.Invalid { os.exit(27i32) }

    // 28-32: invalid UTF-8 is rejected by the first parse, before a raw string or an
    // otherwise-valid prefix can be exposed to the caller.
    let (_, raw_basic_error) = only_value("a = \"\xFF\"\n", room[..])
    if raw_basic_error != toml.Invalid { os.exit(28i32) }
    let (_, raw_literal_error) = only_value("a = '\xFF'\n", room[..])
    if raw_literal_error != toml.Invalid { os.exit(29i32) }
    let (_, raw_multi_basic_error) = only_value("a = \"\"\"\xFF\"\"\"\n", room[..])
    if raw_multi_basic_error != toml.Invalid { os.exit(30i32) }
    let (_, raw_multi_literal_error) = only_value("a = '''\xFF'''\n", room[..])
    if raw_multi_literal_error != toml.Invalid { os.exit(31i32) }
    let (_, comment_error) = only_value("a = 1 # \xFF\n", room[..])
    if comment_error != toml.Invalid { os.exit(32i32) }

    // 33: valid raw UTF-8 still passes; the full-document comparison above retains escaped
    // Unicode coverage.
    let (raw_utf8, raw_utf8_error) = only_value("a = \"é😀\"\n", room[..])
    if raw_utf8_error != ok || !str.eq(raw_utf8.text, "é😀") { os.exit(33i32) }

    // 34-39: leading zeroes remain invalid when an underscore hides the next decimal digit;
    // ordinary zero and a non-decimal spelling retain their own valid forms.
    let (plain_zero, zero_error) = only_value("a = 0\n", room[..])
    if zero_error != ok || plain_zero.kind != .Integer || plain_zero.integer != 0i64 { os.exit(34i32) }
    let (radix, radix_error) = only_value("a = 0x0_1\n", room[..])
    if radix_error != ok || radix.kind != .Integer || radix.integer != 1i64 { os.exit(35i32) }
    if outcome("a = 0_1\n") != toml.Invalid { os.exit(36i32) }
    if outcome("a = 0_1.0\n") != toml.Invalid { os.exit(37i32) }
    if outcome("a = -0_1\n") != toml.Invalid { os.exit(38i32) }
    if outcome("a = +0_1.0\n") != toml.Invalid { os.exit(39i32) }

    // 40-44: quoted TOML strings must not carry raw control bytes other than the
    // line breaks allowed by the multi-line forms and tab.
    let (_, basic_control) = only_value("a = \"\x00\"\n", room[..])
    if basic_control != toml.Invalid { os.exit(40i32) }
    let (_, literal_control) = only_value("a = '\x01'\n", room[..])
    if literal_control != toml.Invalid { os.exit(41i32) }
    let (_, multi_basic_control) = only_value("a = \"\"\"\x0B\"\"\"\n", room[..])
    if multi_basic_control != toml.Invalid { os.exit(42i32) }
    let (_, multi_literal_control) = only_value("a = '''\x7F'''\n", room[..])
    if multi_literal_control != toml.Invalid { os.exit(43i32) }
    let (raw_tab, raw_tab_error) = only_value("a = \"\t\"\n", room[..])
    if raw_tab_error != ok || raw_tab.text.len != 1usize || raw_tab.text[0usize] != 9u8 { os.exit(44i32) }

    // 45-53: numeric separators stay between actual radix digits, signed zero retains
    // its IEEE sign bit, and datetime values have a complete valid calendar shape.
    let (negative_zero, negative_zero_error) = only_value("a = -0.0\n", room[..])
    if negative_zero_error != ok || negative_zero.kind != .Float || mem.bitcast[u64](negative_zero.float) != 9223372036854775808u64 { os.exit(45i32) }
    if outcome("a = 1_e5\n") != toml.Invalid { os.exit(46i32) }
    if outcome("a = 1e_5\n") != toml.Invalid { os.exit(47i32) }
    let (leap_day, leap_day_error) = only_value("a = 2000-02-29\n", room[..])
    if leap_day_error != ok || leap_day.kind != .Datetime { os.exit(48i32) }
    if outcome("a = 2023-02-29\n") != toml.Invalid { os.exit(49i32) }
    if outcome("a = 0000-00-00\n") != toml.Invalid { os.exit(50i32) }
    if outcome("a = 99:99:99\n") != toml.Invalid { os.exit(51i32) }
    if outcome("a = 12:30:::\n") != toml.Invalid { os.exit(52i32) }
    if outcome("a = 1979-05-27T07:32:00+99:00\n") != toml.Invalid { os.exit(53i32) }

    // 54-57: only CRLF and LF are line endings, and comments may contain no raw
    // control byte other than a tab.  A bare CR must not be quietly treated as
    // whitespace or as a multi-line-string continuation.
    if outcome("a = 1 # \x01\n") != toml.Invalid { os.exit(54i32) }
    if outcome("a = [1\r, 2]\n") != toml.Invalid { os.exit(55i32) }
    if outcome("a = \"\"\"x\ry\"\"\"\n") != toml.Invalid { os.exit(56i32) }
    if outcome("a = \"\"\"x\\\ry\"\"\"\n") != toml.Invalid { os.exit(57i32) }

    // 58: the corresponding CRLF forms remain valid.
    if outcome("a = [\r\n  1,\r\n  2\r\n]\r\n") != ok { os.exit(58i32) }

    try io.print("fmt toml ok\n")
    ret ok
}
