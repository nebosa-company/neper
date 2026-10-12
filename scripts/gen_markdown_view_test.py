"""Reference layouts for tests/selfhost/fixtures/link/ui_markdown_view (L066, D2880).

The oracle shares nothing with e.fmt.markdown: documents are parsed by markdown-it-py
(CommonMark preset, html off, so raw HTML is text as in the viewer) and the token stream
is laid out by the rules written in lib/e/ui/markdown_view.e's header, coded again here.
It rewrites the region between BEGIN DOCS and END DOCS of the fixture's main.e with the
document sources, widths and expected renderings, hit probes, selections and rich spans.

    python scripts/gen_markdown_view_test.py
"""
import pathlib
from markdown_it import MarkdownIt

MAIN = pathlib.Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/ui_markdown_view/src/main.e"

CHAR_W, LINE_H, GAP, INDENT, PAD, BAR = 8, 16, 8, 16, 4, 2
BOLD, ITALIC, CODE, LINK, IMAGE, GLUED, HEADING = 1, 2, 4, 8, 16, 32, 64

DOCS = [
    # 0 headings, wrapping, emphasis, strong, code, link, hard break
    ("# Title of the page\n\nA paragraph with *emphasis*, **strong text**, `inline code` and a [link](https://example.org/a) in it,\nwrapped over several lines of the viewer width.\n\n### Third\n\nfirst line\\\nline two after a hard break\n\n###### six", 240),
    # 1 lists: tight bullets with a nested ordered list, a loose list, a start number
    ("- one\n- two\n  1. nested a\n  2. nested b\n- three\n\ntext between\n\n1. first\n\n   second para\n\n2. second\n\n7. seven\n8. eight", 200),
    # 2 quotes: a quoted paragraph and list, a nested quote, a quote in a list
    ("> quoted line one\n> and two\n>\n> - item in quote\n> - another\n>\n> > nested quote\n\n- list with\n\n  > quote inside", 200),
    # 3 code: markdown syntax and HTML inside code stay literal; indented code; rule
    ("```neper\n# not a heading\n**not bold** <script>alert(1)</script>\n\nfn main() {}\n```\n\n    indented code\n    more\n\n---\n\nafter", 240),
    # 4 links and images: schemes and relative paths, autolinks, an image
    ("[web](http://example.org) [secure](HTTPS://example.org/x) [rel](docs/a.md) [frag](#top) [js](javascript:alert(1)) [data](data:text/html,x) [mail](mailto:a@example.org) <https://example.org/auto> <me@example.org> ![alt text](https://example.org/i.png)", 240),
    # 5 raw HTML and hostile markup stay literal text
    ("<script>alert(1)</script> and <img src=x onerror=alert(1)>\n\n<div>\n**bold in html block**\n</div>\n\n[ref][1] stays\n\n<b>tag</b> stays", 240),
    # 6 narrow width: a word wider than the line stands alone; glued styles
    ("short supercalifragilisticexpialidocious end foo**bar**baz `code` x", 96),
    # 7 deeper nesting and a heading in a quote in a list
    ("1. > ## Heading in quote\n   > text\n\n- - nested bullets\n  - second", 240),
]

SPAN_NODE = {0: 1, 4: 0, 6: 0}

md = MarkdownIt("commonmark", {"html": False})
# the viewer parses every destination as a link and decides at activation time
md.validateLink = lambda url: True


def dest_safe(d):
    if not d or any(ord(c) <= 32 or ord(c) == 127 for c in d):
        return False
    for i, c in enumerate(d):
        if c == ":":
            return d[:i].lower() in ("http", "https", "mailto")
        if c in "/?#":
            return True
    return True


def scale_of(level):
    return {1: 2.0, 2: 1.5, 3: 1.25}.get(level, 1.0)


def split_ws(text):
    """Words of a text node; None marks white space (a word boundary)."""
    out, cur = [], ""
    for ch in text:
        if ch in " \n\t\r":
            if cur:
                out.append(cur)
                cur = ""
            out.append(None)
        else:
            cur += ch
    if cur:
        out.append(cur)
    return out


class Layout:
    def __init__(self, width):
        self.width = width
        self.items = []  # (kind, style, x, y, w, h, text, link)
        self.nodes = []  # [role, level, depth, first, count, label]
        self.links = []  # (dest, safe)
        self.hard = set()  # item indexes that follow a hard break
        self.y = 0.0
        self.any = False
        self.fresh = False
        self.stack = []
        self.levels = 0

    def avail(self, x0):
        return max(self.width - x0, CHAR_W)

    def gap(self):
        if not self.any:
            return 0.0
        inner = None
        for d in range(len(self.stack) - 1, -1, -1):
            if self.stack[d]["kind"] == "item":
                inner = d
                break
        if inner is None or not self.stack[inner]["tight"]:
            return GAP
        outer = any(e["kind"] == "item" for e in self.stack[:inner])
        if not self.fresh or outer:
            return 0.0
        return GAP

    def node(self, role, level):
        self.nodes.append([role, level, self.levels, len(self.items), 0, ""])
        return len(self.nodes) - 1

    def close(self, n):
        self.nodes[n][4] = len(self.items) - self.nodes[n][3]

    def begin_leaf(self, scale):
        top = self.y + self.gap()
        for e in self.stack:
            if e["kind"] == "item" and e["marker"]:
                e["marker"] = False
                t = f'{e["number"]}.' if e["ordered"] else "\u2022"
                self.items.append(("M", 0, e["level_at"] * INDENT, top, INDENT, LINE_H * scale, t, 0))
        return top

    def end_leaf(self, top, height):
        for e in self.stack:
            if e["kind"] == "quote":
                self.items.append(("Q", 0, e["level_at"] * INDENT, top, BAR, height, "", 0))
        self.y = top + height
        self.any = True
        self.fresh = False

    def words_of(self, children):
        """Words (text, style, link, glued, hard) of an inline token's children."""
        words = []
        st = {"after_space": True, "hard": False}
        stack = []  # (kind, link)

        def add(text, style, link):
            for part in split_ws(text):
                if part is None:
                    st["after_space"] = True
                    continue
                words.append((part, style, link, (not st["after_space"]) and not st["hard"], st["hard"]))
                st["after_space"] = False
                st["hard"] = False

        def cur():
            style, link = 0, 0
            for k, l in stack:
                if k == "em":
                    style |= ITALIC
                if k == "strong":
                    style |= BOLD
                if k == "image":
                    style |= IMAGE
                if k == "link":
                    style |= LINK
                    link = l
            return style, link

        def walk(items):
            for ch in items:
                t = ch.type
                if t == "em_open":
                    stack.append(("em", 0))
                elif t == "strong_open":
                    stack.append(("strong", 0))
                elif t == "link_open":
                    href = ch.attrGet("href") or ""
                    self.links.append((href, dest_safe(href)))
                    stack.append(("link", len(self.links)))
                elif t in ("em_close", "strong_close", "link_close"):
                    stack.pop()
                elif t == "image":
                    stack.append(("image", 0))
                    walk(ch.children)
                    stack.pop()
                elif t == "text":
                    s0, l0 = cur()
                    add(ch.content, s0, l0)
                elif t == "code_inline":
                    s0, l0 = cur()
                    add(ch.content, s0 | CODE, l0)
                elif t == "softbreak":
                    st["after_space"] = True
                elif t == "hardbreak":
                    st["after_space"] = True
                    st["hard"] = True

        walk(children)
        # adjacent glued pieces in one style and link are one word (as the viewer merges)
        merged = []
        for (text, style, link, glued, hard) in words:
            if merged and glued and merged[-1][1] == style and merged[-1][2] == link:
                merged[-1] = (merged[-1][0] + text, style, link, merged[-1][3], merged[-1][4])
            else:
                merged.append((text, style, link, glued, hard))
        return merged

    def place(self, words, scale, x0, top, node, extra):
        adv = CHAR_W * scale
        lh = LINE_H * scale
        avail = self.avail(x0)
        line, col, first = 0, 0.0, True
        for (text, style, link, glued, hard) in words:
            wide = len(text) * adv
            if hard and not first:
                line += 1
                col = 0.0
                first = True
            sep = 0.0 if first or glued else adv
            if not first and col + sep + wide > avail:
                line += 1
                col = 0.0
                first = True
                sep = 0.0
            st = style | extra | (GLUED if glued else 0)
            if hard:
                self.hard.add(len(self.items))
            self.items.append(("W", st, x0 + col + sep, top + line * lh, wide, lh, text, link))
            col = col + sep + wide
            first = False
        return (line + 1) if words else 0

    def leaf_text(self, children, heading):
        role = "H" if heading else "P"
        scale = scale_of(heading) if heading else 1.0
        extra = HEADING if heading else 0
        n = self.node(role, heading)
        top = self.begin_leaf(scale)
        words = self.words_of(children)
        lines = self.place(words, scale, self.levels * INDENT, top, n, extra)
        label = ""
        for i, w in enumerate(words):
            if i:
                label += "\n" if w[4] else ("" if w[3] else " ")
            label += w[0]
        self.nodes[n][5] = label
        self.end_leaf(top, lines * LINE_H * scale)
        self.close(n)

    def leaf_code(self, content, info):
        n = self.node("C", 0)
        top = self.begin_leaf(1.0)
        lines = content.split("\n")
        if lines and lines[-1] == "":
            lines.pop()
        x0 = self.levels * INDENT
        height = len(lines) * LINE_H + 2 * PAD
        self.items.append(("B", CODE, x0, top, self.avail(x0), height, "", 0))
        for k, line in enumerate(lines):
            self.items.append(("L", CODE, x0 + PAD, top + PAD + k * LINE_H, len(line) * CHAR_W, LINE_H, line, 0))
        self.nodes[n][5] = info
        self.end_leaf(top, height)
        self.close(n)


def list_tight(tokens, i):
    level = tokens[i].level
    j = i + 1
    paragraphs = []
    while not (tokens[j].type.endswith("list_close") and tokens[j].level == level):
        if tokens[j].type == "paragraph_open" and tokens[j].level == level + 2:
            paragraphs.append(tokens[j].hidden)
        j += 1
    # markdown-it hides a tight item's direct paragraphs; items with none (a quote, a code
    # block) are tight unless the documents here separate them by blank lines, which they
    # do not
    return all(paragraphs)


def layout(src, width):
    lay = Layout(width)
    tokens = md.parse(src)
    pending = None
    for i, tok in enumerate(tokens):
        t = tok.type
        if t == "heading_open":
            pending = int(tok.tag[1])
        elif t == "paragraph_open":
            pending = 0
        elif t == "inline":
            lay.leaf_text(tok.children, pending)
        elif t == "fence":
            lay.leaf_code(tok.content, tok.info.strip())
        elif t == "code_block":
            lay.leaf_code(tok.content, "")
        elif t == "hr":
            n = lay.node("S", 0)
            top = lay.begin_leaf(1.0)
            x0 = lay.levels * INDENT
            lay.items.append(("R", 0, x0, top, lay.avail(x0), 1.0, "", 0))
            lay.end_leaf(top, 1.0)
            lay.close(n)
        elif t == "blockquote_open":
            n = lay.node("Q", 0)
            lay.stack.append({"kind": "quote", "level_at": lay.levels, "node": n})
            lay.levels += 1
        elif t == "blockquote_close":
            e = lay.stack.pop()
            lay.levels -= 1
            lay.close(e["node"])
        elif t in ("bullet_list_open", "ordered_list_open"):
            ordered = t == "ordered_list_open"
            start = int(tok.attrGet("start") or 1) if ordered else 0
            n = lay.node("L", start)
            lay.stack.append({"kind": "list", "ordered": ordered, "number": start, "tight": list_tight(tokens, i), "node": n})
            lay.fresh = True
        elif t in ("bullet_list_close", "ordered_list_close"):
            e = lay.stack.pop()
            lay.close(e["node"])
        elif t == "list_item_open":
            lst = lay.stack[-1]
            n = lay.node("I", lst["number"] if lst["ordered"] else 0)
            lay.stack.append({"kind": "item", "level_at": lay.levels, "tight": lst["tight"], "ordered": lst["ordered"], "number": lst["number"], "marker": True, "node": n})
            lay.levels += 1
            lst["number"] += 1
        elif t == "list_item_close":
            e = lay.stack.pop()
            lay.levels -= 1
            lay.close(e["node"])
    return lay


def fmt(v):
    return str(int(v)) if float(v).is_integer() else repr(float(v))


def render(lay):
    out = []
    for (k, st, x, y, w, h, t, ln) in lay.items:
        out.append(f"{k} {fmt(x)} {fmt(y)} {fmt(w)} {fmt(h)} {st} {ln} {t}\n")
    for (role, level, depth, first, count, label) in lay.nodes:
        out.append(f"N {role} {level} {depth} {first} {count} {label}\n")
    for dest, safe in lay.links:
        out.append(f"K {1 if safe else 0} {dest}\n")
    out.append(f"H {fmt(lay.y)}\n")
    return "".join(out)


def selection(lay):
    out, have, prev = "", False, 0
    for (k, st, x, y, w, h, t, ln) in lay.items:
        if k in ("W", "L"):
            if have:
                if y != prev:
                    out += "\n"
                elif not (k == "W" and st & GLUED):
                    out += " "
            out += t
            have = True
            prev = y
    return out


def spans(lay, node):
    first, count = lay.nodes[node][3], lay.nodes[node][4]
    idx = [i for i in range(first, first + count) if lay.items[i][0] == "W"]
    out = []
    for n, i in enumerate(idx):
        k, st, x, y, w, h, t, ln = lay.items[i]
        kind = "c" if st & CODE else "l" if st & LINK else "b" if st & BOLD else "i" if st & ITALIC else "p"
        # the viewer stores one space before a word that is neither glued nor after a hard break
        if n + 1 < len(idx):
            nxt = lay.items[idx[n + 1]]
            if not nxt[1] & GLUED and idx[n + 1] not in lay.hard:
                t += " "
        # an activatable link carries the action (HostActivated, safe destination)
        live = 1 if ln and lay.links[ln - 1][1] else 0
        out.append((kind, t, live))
    return out


def probes(lay):
    """Points on every word, marker and code line, and two outside: the topmost hit."""
    pts = [(it[2] + 1.0, it[3] + 1.0) for it in lay.items if it[0] in ("W", "M", "L")]
    pts.append((lay.width + 50.0, 3.0))
    pts.append((1.0, lay.y + 50.0))
    out = []
    for (px, py) in pts:
        found = -1
        for i in range(len(lay.items) - 1, -1, -1):
            k, st, x, y, w, h, t, ln = lay.items[i]
            if k in ("W", "M", "L") and x <= px < x + w and y <= py < y + h:
                found = i
                break
        out.append((px, py, found))
    return out


def nlit(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def chain(name, ret, rows, conv):
    s = f"fn {name}(i: usize) -> {ret} {{\n"
    for n, v in rows:
        s += f"    if i == {n}usize {{ ret {conv(v)} }}\n"
    s += "    ret " + ('""' if ret == "str" else "0.0") + "\n}\n"
    return s


def main():
    parts = ["fn doc_count() -> usize { ret %dusize }\n" % len(DOCS)]
    srcs, wids, exps, sels, prb, spn = [], [], [], [], [], []
    for n, (src, width) in enumerate(DOCS):
        lay = layout(src, width)
        srcs.append((n, src))
        wids.append((n, width))
        exps.append((n, render(lay)))
        sels.append((n, selection(lay)))
        prb.append((n, ";".join(f"{fmt(x)},{fmt(y)},{i}" for x, y, i in probes(lay))))
        # doc 0's paragraph is node 1 (a heading comes first); doc 4 is one paragraph
        spn.append((n, "".join(f"{k}:{t}:{ln};" for k, t, ln in spans(lay, SPAN_NODE[n])) if n in SPAN_NODE else "-"))
    parts.append(chain("doc_src", "str", srcs, nlit))
    parts.append(chain("doc_width", "f32", wids, lambda v: repr(float(v))))
    parts.append(chain("doc_expected", "str", exps, nlit))
    parts.append(chain("doc_selection", "str", sels, nlit))
    parts.append(chain("doc_probes", "str", prb, nlit))
    parts.append(chain("doc_spans", "str", spn, nlit))
    text = MAIN.read_text(encoding="utf-8")
    a = text.index("// BEGIN DOCS\n") + len("// BEGIN DOCS\n")
    b = text.index("// END DOCS")
    MAIN.write_text(text[:a] + "\n".join(parts) + text[b:], encoding="utf-8")
    for n, (src, width) in enumerate(DOCS):
        print(n, width, len(exps[n][1].splitlines()), "rows")


if __name__ == "__main__":
    main()
