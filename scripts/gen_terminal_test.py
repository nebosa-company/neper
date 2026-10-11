"""Regenerates the box and bar tables of lib/e/text/terminal.e and the vectors of
tests/selfhost/fixtures/link/text_terminal/src/main.e (L104).

Oracles: tqdm.format_meter for the progress line, rich's Console markup rendering for
the SGR output and rich.table.Table (rich.box styles) for the tables.

    PYTHONIOENCODING=utf-8 PYTHONPATH=<dir with tqdm and rich> python scripts/gen_terminal_test.py
"""
import io, os, random, sys
from tqdm import tqdm
from rich import box
from rich.console import Console
from rich.table import Table
from rich.text import Text

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(ROOT, "lib", "e", "text", "terminal.e")
FIX = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "text_terminal", "src", "main.e")
STYLES = [("Ascii", box.ASCII), ("Square", box.SQUARE), ("Rounded", box.ROUNDED), ("HeavyHead", box.HEAVY_HEAD)]


def lit(s):
    out = []
    for ch in s:
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ord(ch) < 128:
            out.append(ch)
        else:
            out.append("".join("\\x%02x" % b for b in ch.encode("utf-8")))
    return '"' + "".join(out) + '"'


def parts(bx):
    # rows: top, head, head rule, body, bottom; parts: left, fill, divider, right
    return [
        [bx.top_left, bx.top, bx.top_divider, bx.top_right],
        [bx.head_left, " ", bx.head_vertical, bx.head_right],
        [bx.head_row_left, bx.head_row_horizontal, bx.head_row_cross, bx.head_row_right],
        [bx.mid_left, " ", bx.mid_vertical, bx.mid_right],
        [bx.bottom_left, bx.bottom, bx.bottom_divider, bx.bottom_right],
    ]


def generated():
    o = []
    for name, bx in STYLES:
        o.append("fn box_%s(row: usize, part: usize) -> str {" % name.lower())
        o.append("    let k = row * 4usize + part")
        for i, p in enumerate(sum(parts(bx), [])):
            o.append("    if k == %dusize { ret %s }" % (i, lit(p)))
        o.append('    ret ""')
        o.append("}")
        o.append("")
    o.append("fn box_part(style: BoxStyle, row: usize, part: usize) -> str {")
    for name, _ in STYLES[:-1]:
        o.append("    if style == .%s { ret box_%s(row, part) }" % (name, name.lower()))
    o.append("    ret box_heavyhead(row, part)")
    o.append("}")
    o.append("")
    o.append("// The bar's cells: index 0 is blank, `steps` is the full cell (tqdm's two charsets).")
    o.append("fn bar_char(ascii: bool, k: u64) -> str {")
    asc = " 123456789#"
    uni = " ▏▎▍▌▋▊▉█"
    for i, ch in enumerate(asc):
        o.append("    if ascii && k == %du64 { ret %s }" % (i, lit(ch)))
    for i, ch in enumerate(uni):
        o.append("    if !ascii && k == %du64 { ret %s }" % (i, lit(ch)))
    o.append('    ret " "')
    o.append("}")
    return "\n".join(o) + "\n"


def patch_module():
    s = open(MOD, encoding="utf-8").read()
    a = s.index("// BEGIN generated tables")
    b = s.index("// END generated tables")
    s = s[:a] + "// BEGIN generated tables (scripts/gen_terminal_test.py)\n" + generated() + s[b:]
    open(MOD, "w", encoding="utf-8", newline="\n").write(s)


def hx(s):
    return s.encode("utf-8").hex()


def meter_vectors(rnd):
    rows = []
    prefixes = ["", "", "load", "Réseau", "dl"]
    units = ["it", "it", "B", "files"]
    for _ in range(150):
        total = rnd.choice([0, 0, 1, 7, 8, 10, 100, 1000, 12345, 86400])
        n = rnd.randint(0, total + 2) if total else rnd.randint(0, 5000)
        ms = rnd.choice([0, 1, 250, 999, 1500, 5000, 59999, 60000, 3599999, 3600000, 7325500, rnd.randint(0, 20000000)])
        ncols = rnd.choice([0, 40, 60, 80, 120, 25])
        asc = rnd.random() < 0.5
        prefix, unit = rnd.choice(prefixes), rnd.choice(units)
        elapsed = ms / 1000.0
        exp = tqdm.format_meter(n, total or None, elapsed, ncols=ncols or None, prefix=prefix, ascii=asc, unit=unit)
        rows.append("%d %d %d %d %d %s %s %s;" % (n, total, ms, ncols, 1 if asc else 0, hx(prefix), hx(unit), hx(exp)))
    # exact halves of a percentage and rates at the 9.995 / 0.995 boundaries
    for n, total in [(1, 8), (3, 8), (5, 8), (7, 8), (1, 200), (1, 400), (999, 1000)]:
        exp = tqdm.format_meter(n, total, 10.0, ncols=50, ascii=True)
        rows.append("%d %d 10000 50 1 %s %s %s;" % (n, total, hx(""), hx("it"), hx(exp)))
    for n, ms in [(9995, 1000000), (9996, 1000000), (1000, 1000), (1, 1000), (1, 999), (1, 1001), (10, 1000), (100, 1000)]:
        exp = tqdm.format_meter(n, 100000, ms / 1000.0, ncols=70, ascii=False)
        rows.append("%d 100000 %d 70 0 %s %s %s;" % (n, ms, hx(""), hx("it"), hx(exp)))
    return rows


COLORS = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"] + ["bright_" + c for c in ["red", "green", "blue", "cyan", "white"]]
ATTRS = ["bold", "dim", "italic", "underline", "strike", "reverse", "b", "i", "u"]


def rich_render(src, color):
    c = Console(file=io.StringIO(), force_terminal=color, color_system="standard" if color else None, width=400, legacy_windows=False)
    c.print(src, end="", highlight=False, markup=True, emoji=False)
    return c.file.getvalue()


def markup_vectors(rnd):
    rows = []
    words = ["alpha", "beta ", "x", " gamma", "café", "1 + 2", "."]
    for _ in range(140):
        n = rnd.randint(1, 5)
        parts_ = []
        stack = []
        for _ in range(n):
            r = rnd.random()
            if r < 0.4 or not stack:
                tag = " ".join(rnd.sample(ATTRS + COLORS, rnd.randint(1, 3)))
                if rnd.random() < 0.25:
                    tag += " on " + rnd.choice(COLORS)
                # a tag with two foreground colours is rich's problem too; both take the last one
                stack.append(tag)
                parts_.append("[%s]" % tag)
            elif r < 0.7:
                t = stack.pop()
                parts_.append("[/]" if rnd.random() < 0.6 else "[/%s]" % t)
            if rnd.random() < 0.8:
                parts_.append(rnd.choice(words))
        while stack:
            stack.pop()
            parts_.append("[/]")
        if rnd.random() < 0.15:
            parts_.insert(rnd.randint(0, len(parts_)), "\\[bold]")
        src = "".join(parts_)
        for color in (True, False):
            try:
                exp = rich_render(src, color)
            except Exception as e:  # rich rejects it: not a vector
                print("skip", repr(src), e)
                continue
            rows.append("%d %s %s;" % (1 if color else 0, hx(src), hx(exp)))
    for src in ["a [ b", "[bold red", "x [1] y", "5 [ ] 6"]:
        try:
            rows.append("0 %s %s;" % (hx(src), hx(rich_render(src, False))))
        except Exception as e:
            print("skip", repr(src), e)
    for src in ["[bold]x", "[/]x", "[nosuchstyle]x[/]", "[bold]a[/italic]"]:
        rows.append("1 %s ERR;" % hx(src))
    return rows


def table_vectors(rnd):
    rows = []
    cells_pool = ["", "a", "foo", "barbaz", "12", "3456", "café", "über", "x y", "Nº 7"]
    for si, (name, bx) in enumerate(STYLES):
        for _ in range(16):
            n = rnd.randint(1, 4)
            nrows = rnd.randint(0, 4)
            aligns = "".join(rnd.choice("lrc") for _ in range(n))
            heads = [rnd.choice(["Name", "Qty", "id", "Price", "x", "Description"]) for _ in range(n)]
            cells = [rnd.choice(cells_pool) for _ in range(n * nrows)]
            t = Table(box=bx, show_header=True)
            for h, a in zip(heads, aligns):
                t.add_column(Text(h), justify={"l": "left", "r": "right", "c": "center"}[a])
            for r in range(nrows):
                t.add_row(*[Text(c) for c in cells[r * n:(r + 1) * n]])
            c = Console(file=io.StringIO(), width=400, color_system=None, force_terminal=False, legacy_windows=False)
            c.print(t)
            exp = c.file.getvalue()
            toks = [str(si), str(n), aligns, str(nrows)] + [hx(h) if h else "-" for h in heads] + [hx(x) if x else "-" for x in cells] + [hx(exp)]
            rows.append(" ".join(toks) + ";")
    return rows


FIXTURE = """// `e.text.terminal` against tqdm.format_meter and rich (scripts/gen_terminal_test.py): the progress line, the
// markup-to-SGR renderer and the boxed tables, vector by vector. Every check has its own exit code.
use e.io
use e.mem
use e.os
use e.str
use e.text.terminal as term

fn nib(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

// Next token of a record: [start, end) up to a space or the `;` record end.
fn token_end(v: str, from: usize) -> usize {
    var i = from
    while v[i] != 32u8 && v[i] != 59u8 { i += 1usize }
    ret i
}

fn number(v: str, from: usize, end: usize) -> u64 {
    var out = 0u64
    var i = from
    while i < end {
        out = out * 10u64 + u64(v[i] - 48u8)
        i += 1usize
    }
    ret out
}

fn unhex(a: *mem.Arena, v: str, from: usize, end: usize) -> str {
    if end - from == 1usize && v[from] == 45u8 { ret "" }
    let count = (end - from) / 2usize
    let (buf, e) = mem.alloc[u8](a, count + 1usize)
    if e != ok { os.exit(80i32) }
    var k = 0usize
    while k < count {
        buf[k] = (nib(v[from + 2usize * k]) << 4u8) | nib(v[from + 2usize * k + 1usize])
        k += 1usize
    }
    ret buf[0usize..count]
}

fn show(got: str, want: str) {
    let p = io.print("\\nGOT  ")
    let q = io.print(got)
    let r = io.print("\\nWANT ")
    let s = io.print(want)
}

// 0 when every meter record agrees, else 1 + the record's index.
fn meters(a: *mem.Arena, v: str) -> u32 {
    var i = 0usize
    var seen = 0u32
    while i < v.len {
        var e = token_end(v, i)
        let n = number(v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let total = number(v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let ms = number(v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let ncols = number(v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let asc = number(v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let prefix = unhex(a, v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let unit = unhex(a, v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let want = unhex(a, v, i, e)
        i = e + 1usize
        let (got, ge) = term.render_meter(a, n, total, f64(ms) / 1000.0, usize(ncols), prefix, unit, asc == 1u64)
        if ge != ok || !str.eq(got, want) {
            show(got, want)
            ret seen + 1u32
        }
        seen += 1u32
    }
    ret 0u32
}

fn markups(a: *mem.Arena, v: str) -> u32 {
    var i = 0usize
    var seen = 0u32
    while i < v.len {
        var e = token_end(v, i)
        let color = number(v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let src = unhex(a, v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let is_error = e - i == 3usize && v[i] == 69u8
        var want = ""
        if !is_error { want = unhex(a, v, i, e) }
        i = e + 1usize
        let (got, ge) = term.render_markup(a, src, color == 1u64)
        if is_error {
            if ge != term.BadMarkup { ret seen + 1u32 }
        } else {
            if ge != ok || !str.eq(got, want) {
                show(got, want)
                ret seen + 1u32
            }
        }
        seen += 1u32
    }
    ret 0u32
}

fn tables(a: *mem.Arena, v: str) -> u32 {
    var i = 0usize
    var seen = 0u32
    while i < v.len {
        var e = token_end(v, i)
        let si = number(v, i, e)
        i = e + 1usize
        e = token_end(v, i)
        let n = usize(number(v, i, e))
        i = e + 1usize
        e = token_end(v, i)
        let aligns_at = i
        i = e + 1usize
        e = token_end(v, i)
        let nrows = usize(number(v, i, e))
        i = e + 1usize
        let (cols, ce) = mem.alloc[term.Column](a, n)
        let (cells, xe) = mem.alloc[str](a, n * nrows + 1usize)
        if ce != ok || xe != ok { ret 1000u32 }
        var k = 0usize
        while k < n {
            e = token_end(v, i)
            var al = term.Align.Left
            if v[aligns_at + k] == 114u8 { al = term.Align.Right }
            if v[aligns_at + k] == 99u8 { al = term.Align.Center }
            cols[k] = term.Column{ header: unhex(a, v, i, e), align: al }
            i = e + 1usize
            k += 1usize
        }
        k = 0usize
        while k < n * nrows {
            e = token_end(v, i)
            cells[k] = unhex(a, v, i, e)
            i = e + 1usize
            k += 1usize
        }
        e = token_end(v, i)
        let want = unhex(a, v, i, e)
        i = e + 1usize
        var style = term.BoxStyle.Ascii
        if si == 1u64 { style = term.BoxStyle.Square }
        if si == 2u64 { style = term.BoxStyle.Rounded }
        if si == 3u64 { style = term.BoxStyle.HeavyHead }
        let (got, ge) = term.render_table(a, cols[0usize..n], cells[0usize..n * nrows], style)
        if ge != ok || !str.eq(got, want) {
            show(got, want)
            ret seen + 1u32
        }
        seen += 1u32
    }
    ret 0u32
}

%(chunks)s
fn main(a: *mem.Arena, args: []str) -> err {
%(calls)s
    // shape errors
    let one: [1]term.Column = [1]term.Column{ term.Column{ header: "h", align: term.Align.Left } }
    let two: [2]str = [2]str{ "a", "b" }
    let (_, se) = term.render_table(a, one[0..], two[0..1], term.BoxStyle.Ascii)
    let (zero_text, ze) = term.render_table(a, one[0..0], two[0..0], term.BoxStyle.Ascii)
    if se != ok { os.exit(90i32) }
    if ze != term.BadShape { os.exit(91i32) }
    if term.display_width("caf\\xc3\\xa9") != 4usize { os.exit(92i32) }
    try io.print("terminal ok")
    ret ok
}
"""


def write_fixture(meter, mark, table):
    chunks, calls = [], []
    code = 1
    for kind, rows, fn, per in (("meter", meter, "meters", 50), ("markup", mark, "markups", 40), ("table", table, "tables", 20)):
        for k in range(0, len(rows), per):
            name = "%s_%d" % (kind, k // per)
            chunks.append('fn %s() -> str {\n    ret "%s"\n}\n' % (name, "".join(rows[k:k + per])))
            calls.append("    let r%d = %s(a, %s())\n    if r%d != 0u32 { os.exit(%di32) }" % (code, fn, name, code, code))
            code += 1
    src = FIXTURE % {"chunks": "\n".join(chunks), "calls": "\n".join(calls)}
    os.makedirs(os.path.dirname(FIX), exist_ok=True)
    open(FIX, "w", encoding="utf-8", newline="\n").write(src)
    return len(meter) + len(mark) + len(table)


def main():
    patch_module()
    rnd = random.Random(104)
    m, k, t = meter_vectors(rnd), markup_vectors(rnd), table_vectors(rnd)
    print("vectors:", write_fixture(m, k, t), "(meter %d, markup %d, table %d)" % (len(m), len(k), len(t)))


main()
