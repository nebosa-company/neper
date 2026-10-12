#!/usr/bin/env python3
"""Reference layouts for tests/selfhost/fixtures/link/ui_markdown_view_fit (L066, D3603).

The measured-text and content-sized-column layouts of e.ui.markdown_view.build_with against the model of
scripts/gen_markdown_view_test.py (markdown-it-py parse, layout rules coded again) extended with a proportional,
pair-adjusting text measurement and the column rule of the module header. The measurement is a synthetic one with the
shape of a shaper's: a width per character class, bold wider, code monospaced, a ligature and kerning pairs that
change a word's width, so the callback must receive whole words.

    python scripts/gen_markdown_view_fit_test.py
"""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_markdown_view_test as base  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/ui_markdown_view_fit/src/main.e"
EXISTING = pathlib.Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/ui_markdown_view/src/main.e"
CHAR_W, LINE_H, PAD = base.CHAR_W, base.LINE_H, base.PAD
BOLD, CODE = base.BOLD, base.CODE

NARROW = set("ijltfrI.,:;!|'")
WIDE = set("mwMW@%")


def measure(text, style):
    """Width at scale 1 of a run of text in a style (the callback the fixture installs)."""
    if style & CODE:
        return float(8 * len(text))
    total = 0.0
    for ch in text:
        if ord(ch) > 127:
            total += 8
        elif ch == " ":
            total += 4
        elif ch in NARROW:
            total += 3
        elif ch in WIDE:
            total += 12
        elif ch.isupper():
            total += 9
        else:
            total += 7
        if style & BOLD:
            total += 1
    for pair in ("fi", "AV", "VA", "To"):
        total -= 2 * text.count(pair)
    return float(total)


class FitLayout(base.Layout):
    measured = False
    fit = False
    cell_avail = None

    def place(self, words, scale, x0, top, node, extra):
        if not self.measured and self.cell_avail is None:
            return super().place(words, scale, x0, top, node, extra)
        lh = base.LINE_H * scale
        avail = self.avail(x0) if self.cell_avail is None else self.cell_avail
        adv = CHAR_W * scale
        line, col, first = 0, 0.0, True
        for (text, style, link, glued, hard) in words:
            st0 = style | extra
            wide = measure(text, st0) * scale if self.measured else len(text) * adv
            if hard and not first:
                line += 1
                col = 0.0
                first = True
            sep = 0.0 if first or glued else (measure(" ", st0) * scale if self.measured else adv)
            if not first and col + sep + wide > avail:
                line += 1
                col = 0.0
                first = True
                sep = 0.0
            st = st0 | (base.GLUED if glued else 0)
            if hard:
                self.hard.add(len(self.items))
            self.items.append(("W", st, x0 + col + sep, top + line * lh, wide, lh, text, link))
            col = col + sep + wide
            first = False
        return (line + 1) if words else 0

    def width_of(self, text, style):
        return measure(text, style) if self.measured else float(len(text) * CHAR_W)

    def leaf_table(self, rows):
        columns = len(rows[0])
        table = self.node("A", columns)
        top = self.begin_leaf(1.0)
        x0 = self.levels * base.INDENT
        total = self.avail(x0)
        low = [0.0] * columns
        high = [0.0] * columns
        for r, row in enumerate(rows):
            for c, (header, align, children) in enumerate(row):
                extra = BOLD if header else 0
                longest = run = widest = 0.0
                first = True
                for (text, style, link, glued, hard) in self.words_of(children):
                    st = style | extra
                    wide = self.width_of(text, st)
                    longest = max(longest, wide)
                    if hard and not first:
                        widest = max(widest, run)
                        run, first = 0.0, True
                    sep = 0.0 if first or glued else self.width_of(" ", st)
                    run += sep + wide
                    first = False
                widest = max(widest, run)
                low[c] = max(low[c], longest + 2 * PAD)
                high[c] = max(high[c], widest + 2 * PAD)
        high = [max(h, l) for h, l in zip(high, low)]
        if not self.fit:
            widths = [total / columns] * columns
        elif sum(high) <= total:
            widths = high
        elif sum(low) >= total:
            widths = low
        else:
            widths = [l + (h - l) * ((total - sum(low)) / (sum(high) - sum(low))) for l, h in zip(low, high)]
        left, edge = [], x0
        for k, w in enumerate(widths):
            left.append(edge if self.fit else x0 + k * w)
            edge += w
        y = top
        for r, row in enumerate(rows):
            row_node = self.node("O", r)
            backs, most = [], 1
            for c, (header, align, children) in enumerate(row):
                cell = self.node("E" if header else "D", align)
                self.items.append(("T", 0, left[c], y, widths[c], 0.0, "", 0))
                backs.append(len(self.items) - 1)
                self.cell_of[len(self.items) - 1] = (cell, r)
                words = self.words_of(children)
                first = len(self.items)
                inner = max(widths[c] - 2 * PAD, CHAR_W)
                self.cell_avail = inner
                lines = self.place(words, 1.0, left[c] + PAD, y + PAD, cell, BOLD if header else 0)
                self.cell_avail = None
                for k in range(first, len(self.items)):
                    self.cell_of[k] = (cell, r)
                if align >= 2 and lines:
                    k = first
                    while k < len(self.items):
                        j = k + 1
                        while j < len(self.items) and self.items[j][3] == self.items[k][3]:
                            j += 1
                        left_x = self.items[k][2]
                        right = self.items[j - 1][2] + self.items[j - 1][4]
                        shift = inner - (right - left_x)
                        if align == 2:
                            shift = shift / 2.0
                        if shift > 0:
                            for m in range(k, j):
                                it = list(self.items[m])
                                it[2] += shift
                                self.items[m] = tuple(it)
                        k = j
                label = ""
                for i, w in enumerate(words):
                    if i:
                        label += "\n" if w[4] else ("" if w[3] else " ")
                    label += w[0]
                self.nodes[cell][5] = label
                self.close(cell)
                most = max(most, lines)
            row_h = most * LINE_H + 2 * PAD
            for b in backs:
                it = list(self.items[b])
                it[5] = float(row_h)
                self.items[b] = tuple(it)
            self.close(row_node)
            y += row_h
        self.end_leaf(top, y - top)
        self.close(table)

    def leaf_code(self, content, info):
        if not self.measured:
            return super().leaf_code(content, info)
        n = self.node("C", 0)
        top = self.begin_leaf(1.0)
        lines = content.split("\n")
        if lines and lines[-1] == "":
            lines.pop()
        x0 = self.levels * base.INDENT
        height = len(lines) * LINE_H + 2 * PAD
        self.items.append(("B", CODE, x0, top, self.avail(x0), height, "", 0))
        for k, line in enumerate(lines):
            self.items.append(("L", CODE, x0 + PAD, top + PAD + k * LINE_H, measure(line, CODE), LINE_H, line, 0))
        self.nodes[n][5] = info
        self.end_leaf(top, height)
        self.close(n)


def layout(src, width, measured, fit):
    class L(FitLayout):
        pass
    L.measured, L.fit = measured, fit
    old = base.Layout
    base.Layout = L
    try:
        return base.layout(src, width)
    finally:
        base.Layout = old


def trunc(v):
    return int(math.floor(v + 1e-9)) if abs(v - round(v)) < 1e-9 else int(math.floor(v))


def render(lay):
    out = []
    for (k, st, x, y, w, h, t, ln) in lay.items:
        out.append(f"{k} {trunc(x)} {trunc(y)} {trunc(w)} {trunc(h)} {st} {ln} {t}\n")
    for (role, level, depth, first, count, label) in lay.nodes:
        out.append(f"N {role} {level} {depth} {first} {count} {label}\n")
    for dest, safe in lay.links:
        out.append(f"K {1 if safe else 0} {dest}\n")
    out.append(f"H {trunc(lay.y)}\n")
    return "".join(out)


def risky(lay):
    """Coordinates a float32 could land on the other side of an integer from."""
    bad = []
    for (k, st, x, y, w, h, t, ln) in lay.items:
        for v in (x, y, w, h):
            if v != int(v) and min(v - math.floor(v), math.ceil(v) - v) < 0.002:
                bad.append((k, v))
    return bad


DOCS = [
    # (source, width, measured, fit)
    (base.DOCS[0][0], 240, True, False),
    (base.DOCS[6][0], 120, True, False),
    (base.DOCS[3][0], 240, True, False),
    # tables: content-sized with room to spare, shared between low and high, narrower than every longest word
    ("| Name | Qty | Note |\n|:-----|:---:|-----:|\n| apple | 3 | **fresh** and *sweet* fruit |\n| fig | 12 |\n| `code` | 7 | a |", 400, False, True),
    ("| Name | Qty | Note |\n|:-----|:---:|-----:|\n| apple | 3 | **fresh** and *sweet* fruit from the market |\n| fig | 12 |\n| `code` | 7 | a |", 150, False, True),
    ("| Name | Qty | Note |\n|:-----|:---:|-----:|\n| apple | 3 | **fresh** and *sweet* fruit from the market |\n| fig | 12 |\n| `code` | 7 | a |", 400, True, True),
    ("| Name | Qty | Note |\n|:-----|:---:|-----:|\n| apple | 3 | **fresh** and *sweet* fruit from the market |\n| fig | 12 |\n| `code` | 7 | a |", 130, True, True),
    ("| alpha | beta |\n|---|---|\n| supercalifragilistic | b |\n| c | d |", 60, True, True),
    ("- item\n\n  a | b\n  --|--\n  1 | 2222\n\n> | x | y |\n> |---|---|\n> | left \\| pipe | z |\n", 240, True, True),
    ("| T | |\n|---|---|\n| | |", 200, True, True),
    ("| AVA Tofu | office |\n|---|---:|\n| fifi | W@m |", 200, True, True),
    # the equal-share layout is what build still gives without the option
    (base.DOCS[8][0], 240, False, False),
]


def nlit(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


def chain(name, ret, rows, conv):
    s = f"fn {name}(i: usize) -> {ret} {{\n"
    for n, v in rows:
        s += f"    if i == {n}usize {{ ret {conv(v)} }}\n"
    s += "    ret " + {"str": '""', "f32": "0.0", "bool": "false"}[ret] + "\n}\n"
    return s


HEADER = """// `e.ui.markdown_view` build_with (L066, D3603): a host text measurement and content-sized table columns against
// the layout scripts/gen_markdown_view_fit_test.py computes (a markdown-it-py parse laid out by the module header's
// rules with a proportional, ligature- and kerning-aware synthetic measurement). Each check exits with its own code.

use e.fmt.markdown
use e.io
use e.mem
use e.os
use e.str
use e.ui.markdown_view as mv

// The measurement the model uses: a width per character class (narrow 3, wide 12, capitals 9, other 7, other scripts
// 8, a space 4), one more per character in bold, code monospaced at 8, and the pairs fi, AV, VA, To two narrower.
fn measure_text(state: *void, text: str, style: u8) -> f32 {
    var total: f32 = 0.0
    var i = 0usize
    if (style & 4u8) != 0u8 {
        var cps = 0usize
        while i < text.len {
            if (text[i] & 192u8) != 128u8 { cps += 1usize }
            i += 1usize
        }
        ret f32(cps) * 8.0
    }
    while i < text.len {
        let ch = text[i]
        if ch >= 128u8 {
            if (ch & 192u8) != 128u8 { total += 8.0 }
        } else {
            if ch == 32u8 {
                total += 4.0
            } else if ch == 105u8 || ch == 106u8 || ch == 108u8 || ch == 116u8 || ch == 102u8 || ch == 114u8 || ch == 73u8 || ch == 46u8 || ch == 44u8 || ch == 58u8 || ch == 59u8 || ch == 33u8 || ch == 124u8 || ch == 39u8 {
                total += 3.0
            } else if ch == 109u8 || ch == 119u8 || ch == 77u8 || ch == 87u8 || ch == 64u8 || ch == 37u8 {
                total += 12.0
            } else if ch >= 65u8 && ch <= 90u8 {
                total += 9.0
            } else {
                total += 7.0
            }
            if (style & 1u8) != 0u8 { total += 1.0 }
        }
        if i + 1usize < text.len {
            let next = text[i + 1usize]
            if (ch == 102u8 && next == 105u8) || (ch == 65u8 && next == 86u8) || (ch == 86u8 && next == 65u8) || (ch == 84u8 && next == 111u8) {
                total -= 2.0
            }
        }
        i += 1usize
    }
    ret total
}

fn letter(k: mv.ItemKind) -> str {
    if k == .Word { ret "W" }
    if k == .Marker { ret "M" }
    if k == .Rule { ret "R" }
    if k == .QuoteBar { ret "Q" }
    if k == .CodeBack { ret "B" }
    if k == .CellBack { ret "T" }
    ret "L"
}

fn role_letter(r: mv.NodeRole) -> str {
    if r == .Heading { ret "H" }
    if r == .Paragraph { ret "P" }
    if r == .List { ret "L" }
    if r == .ListItem { ret "I" }
    if r == .Quote { ret "Q" }
    if r == .Code { ret "C" }
    if r == .Table { ret "A" }
    if r == .Row { ret "O" }
    if r == .Cell { ret "D" }
    if r == .HeaderCell { ret "E" }
    ret "S"
}

fn number(b: *str.Builder, v: f32) -> err {
    ret str.push_u32(b, u32(v))
}

"""

MAIN = """fn metrics(width: f32) -> mv.Metrics {
    ret mv.Metrics { width: width, char_w: 8.0, line_h: 16.0, gap: 8.0, indent: 16.0, pad: 4.0, bar: 2.0 }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var items: [512]mv.Item = zero
    var nodes: [64]mv.Node = zero
    var links: [16]mv.Link = zero
    var store: [4096]u8 = zero
    var scratch: [1024]u8 = zero
    var blocks: [128]markdown.Block = zero
    var inlines: [128]markdown.Inline = zero
    var words: [128]mv.Word = zero
    let st = mv.Storage { items: items[..], nodes: nodes[..], links: links[..], store: store[..], scratch: scratch[..], blocks: blocks[..], inlines: inlines[..], words: words[..] }
    var d = 0usize
    while d < doc_count() {
        let mark = mem.mark(a)
        var opts: mv.Options = zero
        opts.measure = mv.Measure { state: zero, width: measure_text }
        opts.measured = doc_measured(d)
        opts.fit_columns = doc_fit(d)
        let (v, build_error) = mv.build_with(doc_src(d), st, metrics(doc_width(d)), .HostActivated, opts)
        if build_error != ok || v.fallback { os.exit(1) }
        let (b, b_error) = str.builder(a, 16384usize)
        if b_error != ok { os.exit(2) }
        var bb = b
        if render(&bb, &v) != ok { os.exit(3) }
        let got = str.done(&bb)
        if !str.eq(got, doc_expected(d)) {
            try io.print(got)
            os.exit(10 + i32(d))
        }
        mem.reset(a, mark)
        d += 1usize
    }
    // Without options `build` is the fixed grid and equal columns, and `build_with` of the zero options is `build`.
    let (plain_view, plain_error) = mv.build("| a | b |\\n|---|---|\\n| 1 | 2 |", st, metrics(160.0), .DisplayOnly)
    if plain_error != ok { os.exit(80) }
    var none: mv.Options = zero
    let (again, again_error) = mv.build_with("| a | b |\\n|---|---|\\n| 1 | 2 |", st, metrics(160.0), .DisplayOnly, none)
    if again_error != ok || again.item_count != plain_view.item_count { os.exit(81) }
    try io.print("markdown view fit ok")
    ret ok
}
"""


def main():
    srcs, wids, exps, meas, fits = [], [], [], [], []
    for n, (src, width, measured, fit) in enumerate(DOCS):
        lay = layout(src, width, measured, fit)
        r = risky(lay)
        if r:
            print("doc", n, "near-integer coordinates", r[:4])
        srcs.append((n, src))
        wids.append((n, width))
        exps.append((n, render(lay)))
        meas.append((n, measured))
        fits.append((n, fit))
    parts = ["fn doc_count() -> usize { ret %dusize }\n" % len(DOCS)]
    parts.append(chain("doc_src", "str", srcs, nlit))
    parts.append(chain("doc_width", "f32", wids, lambda v: repr(float(v))))
    parts.append(chain("doc_expected", "str", exps, nlit))
    parts.append(chain("doc_measured", "bool", meas, lambda v: "true" if v else "false"))
    parts.append(chain("doc_fit", "bool", fits, lambda v: "true" if v else "false"))
    text = EXISTING.read_text(encoding="utf-8")
    a = text.index("// The view in the generator's row format.")
    b = text.index("fn kind_letter(")
    render_fn = text[a:b]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(HEADER + "\n".join(parts) + "\n" + render_fn + MAIN, encoding="utf-8", newline="\n")
    for n, (src, width, measured, fit) in enumerate(DOCS):
        print(n, width, measured, fit, len(exps[n][1].splitlines()), "rows")


if __name__ == "__main__":
    main()
