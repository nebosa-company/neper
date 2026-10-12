// `e.ui.markdown_view` (L066): a safe, structured Markdown viewer model over
// `e.fmt.markdown` and the `e.ui.control` rich-text spans. `build` parses the source into
// caller storage, lays it out at a width on a fixed-advance grid, and answers a flat scene
// item list (words, list markers, rules, quote bars, code backgrounds and lines), an
// accessible node list (heading with level, paragraph, list, list item, quote, code,
// separator, each with the item range it covers and a plain-text label), the links, and
// hit, selection and rich-span queries. Nothing is executed or fetched: the source is data.
//
// Safety: raw HTML, reference links and unknown syntax are not interpreted -- the parser
// reads them as text and the viewer draws that text. A link is display-only unless the
// caller asks for `HostActivated`, and even then only a destination that is relative or
// has the scheme http, https or mailto is `safe`; `activation` answers the destination for
// the host to open and never opens anything. An image is drawn as its alt text; it is never
// loaded. A source the parser or the storage cannot bound is drawn whole as preformatted
// lines (`fallback`), so a hostile document still shows, as text.
//
// Layout (all lengths in the caller's units): a word is `cols * char_w * scale` wide, a line
// `line_h * scale` tall, `scale` 2.0, 1.5, 1.25 for heading levels 1 to 3 and 1.0 otherwise.
// A quote or a list item is one level of `indent`; its content starts at the level times
// `indent`, a list marker sits in the item's own level and a quote bar down the quote's.
// Leaf blocks are `gap` apart, except inside a tight list item where they touch. A word
// wraps to the next line when it does not fit (a word wider than the line stands alone and
// overflows); a hard break starts a line. A code block is `pad` inside a background, one
// unwrapped line per source line.
//
// ponytail: the metric is one advance per code point, so a proportional face needs the
// host's measurement in place of `char_w`; a style change inside a word may break the line
// there; a quote bar is drawn per leaf block, so it is broken at the gaps.

use e.fmt.markdown
use e.ui.control
use e.ui.widget

const BOLD: u8 = 1u8
const ITALIC: u8 = 2u8
const CODE: u8 = 4u8
const LINK: u8 = 8u8
const IMAGE: u8 = 16u8
const GLUED: u8 = 32u8
const HEADING: u8 = 64u8

const E_QUOTE: u8 = 1u8
const E_LIST: u8 = 2u8
const E_ITEM: u8 = 3u8

type ItemKind = enum u8 { Word, Marker, Rule, QuoteBar, CodeBack, CodeLine }
type NodeRole = enum u8 { Heading, Paragraph, List, ListItem, Quote, Code, Separator }
type LinkPolicy = enum u8 { DisplayOnly, HostActivated }

// `style`: the BOLD, ITALIC, CODE, LINK, IMAGE, GLUED (no space before it) and HEADING
// bits. `link` is the link index plus one, zero for none. `node` is the leaf node.
type Item = struct { kind: ItemKind, style: u8, x: f32, y: f32, w: f32, h: f32, start: usize, len: usize, link: u32, node: u32 }
// `level`: a heading's level, an ordered list's first number or an item's number (0 for a
// bullet). `first`/`count`: the items it covers. `label`: plain text in the store (a code
// block's is its info string).
type Node = struct { role: NodeRole, level: u32, depth: u32, first: usize, count: usize, label_start: usize, label_len: usize }
type Link = struct { dest_start: usize, dest_len: usize, safe: bool, mail: bool }
type Word = struct { start: usize, len: usize, cols: usize, style: u8, link: u32, glued: bool, hard: bool }
type Metrics = struct { width: f32, char_w: f32, line_h: f32, gap: f32, indent: f32, pad: f32, bar: f32 }
type Storage = struct { items: []Item, nodes: []Node, links: []Link, store: []u8, scratch: []u8, blocks: []markdown.Block, inlines: []markdown.Inline, words: []Word }
type View = struct { items: []Item, nodes: []Node, links: []Link, store: []u8, item_count: usize, node_count: usize, link_count: usize, store_len: usize, height: f32, fallback: bool, policy: LinkPolicy }

error TooLarge
error TooDeep
error Invalid

type Entry = struct { kind: u8, level_at: usize, tight: bool, ordered: bool, number: u32, marker: bool, node: usize }
type Ctx = struct { st: Storage, m: Metrics, policy: LinkPolicy, items: usize, nodes: usize, links: usize, store_len: usize, y: f32, any: bool, fresh: bool, stack: [32]Entry, depth: usize, levels: usize }

fn utf8_cols(s: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if (s[i] & 192u8) != 128u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn same_scheme(d: str, n: usize, want: str) -> bool {
    if n != want.len { ret false }
    var i = 0usize
    while i < n {
        if lower(d[i]) != want[i] { ret false }
        i += 1usize
    }
    ret true
}

// Whether a destination may be handed to a host: no control or space byte, and either
// relative (no scheme before the first `/`, `?` or `#`) or http, https or mailto.
fn dest_safe(d: str) -> bool {
    if d.len == 0usize { ret false }
    var i = 0usize
    while i < d.len {
        if d[i] <= 32u8 || d[i] == 127u8 { ret false }
        i += 1usize
    }
    i = 0usize
    while i < d.len {
        let ch = d[i]
        if ch == 58u8 {
            ret same_scheme(d, i, "http") || same_scheme(d, i, "https") || same_scheme(d, i, "mailto")
        }
        if ch == 47u8 || ch == 63u8 || ch == 35u8 { ret true }
        i += 1usize
    }
    ret true
}

fn put_item(c: *Ctx, item: Item) -> err {
    if c.items >= c.st.items.len { ret TooLarge }
    c.st.items[c.items] = item
    c.items += 1usize
    ret ok
}

fn put_node(c: *Ctx, role: NodeRole, level: u32) -> (usize, err) {
    if c.nodes >= c.st.nodes.len { ret (0usize, TooLarge) }
    var n: Node = zero
    n.role = role
    n.level = level
    n.depth = u32(c.levels)
    n.first = c.items
    c.st.nodes[c.nodes] = n
    c.nodes += 1usize
    ret (c.nodes - 1usize, ok)
}

fn put_bytes(c: *Ctx, s: str) -> (usize, err) {
    let begin = c.store_len
    if begin + s.len > c.st.store.len { ret (0usize, TooLarge) }
    var i = 0usize
    while i < s.len {
        c.st.store[begin + i] = s[i]
        i += 1usize
    }
    c.store_len += s.len
    ret (begin, ok)
}

// A link whose destination is still at `at` in the leaf's joined text; `commit_links`
// moves it into the store once the leaf's words are there, so the label stays contiguous.
fn put_link(c: *Ctx, at: usize, len: usize, mail: bool) -> (u32, err) {
    if c.links >= c.st.links.len { ret (0u32, TooLarge) }
    c.st.links[c.links] = Link { dest_start: at, dest_len: len, safe: false, mail: mail }
    c.links += 1usize
    ret (u32(c.links), ok)
}

fn commit_links(c: *Ctx, joined: str, from: usize) -> err {
    var i = from
    while i < c.links {
        let l = c.st.links[i]
        var begin = c.store_len
        var total = l.dest_len
        if l.mail {
            let (m, me) = put_bytes(c, "mailto:")
            if me != ok { ret me }
            begin = m
            total += 7usize
        }
        let (body, be) = put_bytes(c, joined[l.dest_start..l.dest_start + l.dest_len])
        if be != ok { ret be }
        if !l.mail { begin = body }
        c.st.links[i] = Link { dest_start: begin, dest_len: total, safe: dest_safe(c.st.store[begin..begin + total]), mail: l.mail }
        i += 1usize
    }
    ret ok
}

// The words into the store as plain text: a space before a word that is not glued, a
// newline before one after a hard break. Returns the label's start and length.
fn commit_words(c: *Ctx, joined: str, count: usize) -> (usize, usize, err) {
    let first = c.store_len
    var i = 0usize
    while i < count {
        let w = c.st.words[i]
        if i > 0usize && (!w.glued || w.hard) {
            var sep = 32u8
            if w.hard { sep = 10u8 }
            if c.store_len >= c.st.store.len { ret (0usize, 0usize, TooLarge) }
            c.st.store[c.store_len] = sep
            c.store_len += 1usize
        }
        let (begin, e) = put_bytes(c, joined[w.start..w.start + w.len])
        if e != ok { ret (0usize, 0usize, e) }
        c.st.words[i].start = begin
        i += 1usize
    }
    ret (first, c.store_len - first, ok)
}

fn heading_scale(level: u32) -> f32 {
    if level == 1u32 { ret 2.0 }
    if level == 2u32 { ret 1.5 }
    if level == 3u32 { ret 1.25 }
    ret 1.0
}

fn avail_width(c: *Ctx, x0: f32) -> f32 {
    var a = c.m.width - x0
    if a < c.m.char_w { a = c.m.char_w }
    ret a
}

// The gap above a leaf block: none for the first, none inside a tight item (but the first
// leaf of a list that is not nested in an item), `gap` otherwise.
fn leaf_gap(c: *Ctx) -> f32 {
    if !c.any { ret 0.0 }
    var d = c.depth
    var inner = 0usize
    var found = false
    while d > 0usize && !found {
        d -= 1usize
        if c.stack[d].kind == E_ITEM {
            inner = d
            found = true
        }
    }
    if !found { ret c.m.gap }
    if !c.stack[inner].tight { ret c.m.gap }
    var outer = false
    var k = 0usize
    while k < inner {
        if c.stack[k].kind == E_ITEM { outer = true }
        k += 1usize
    }
    if !c.fresh || outer { ret 0.0 }
    ret c.m.gap
}

fn decimal(n: u32, out: []u8) -> usize {
    var digits: [12]u8 = zero
    var count = 0usize
    var v = n
    if v == 0u32 {
        digits[0usize] = 48u8
        count = 1usize
    }
    while v > 0u32 {
        digits[count] = 48u8 + u8(v % 10u32)
        v = v / 10u32
        count += 1usize
    }
    var i = 0usize
    while i < count {
        out[i] = digits[count - 1usize - i]
        i += 1usize
    }
    out[count] = 46u8
    ret count + 1usize
}

// Gap, then the markers of the items whose first leaf this is; the top of the leaf.
fn begin_leaf(c: *Ctx, scale: f32) -> (f32, err) {
    let top = c.y + leaf_gap(c)
    var d = 0usize
    while d < c.depth {
        if c.stack[d].kind == E_ITEM && c.stack[d].marker {
            c.stack[d].marker = false
            var buf: [16]u8 = zero
            var n = 0usize
            if c.stack[d].ordered {
                n = decimal(c.stack[d].number, buf[..])
            } else {
                buf[0usize] = 226u8
                buf[1usize] = 128u8
                buf[2usize] = 162u8
                n = 3usize
            }
            let (begin, e) = put_bytes(c, buf[0usize..n])
            if e != ok { ret (0.0, e) }
            let ie = put_item(c, Item { kind: .Marker, style: 0u8, x: f32(c.stack[d].level_at) * c.m.indent, y: top, w: c.m.indent, h: c.m.line_h * scale, start: begin, len: n, link: 0u32, node: 0u32 })
            if ie != ok { ret (0.0, ie) }
        }
        d += 1usize
    }
    ret (top, ok)
}

// The quote bars beside a leaf block that was `height` tall from `top`, and the cursor.
fn end_leaf(c: *Ctx, top: f32, height: f32) -> err {
    var d = 0usize
    while d < c.depth {
        if c.stack[d].kind == E_QUOTE {
            try put_item(c, Item { kind: .QuoteBar, style: 0u8, x: f32(c.stack[d].level_at) * c.m.indent, y: top, w: c.m.bar, h: height, start: 0usize, len: 0usize, link: 0u32, node: 0u32 })
        }
        d += 1usize
    }
    c.y = top + height
    c.any = true
    c.fresh = false
    ret ok
}

// Joins the lines of a leaf by `\n` into the scratch; (length, index of the end event).
fn join_lines(c: *Ctx, src: str, blocks: []const markdown.Block, from: usize) -> (usize, usize, err) {
    var used = 0usize
    var i = from
    while i < blocks.len && blocks[i].kind == .Line {
        if i > from {
            if used >= c.st.scratch.len { ret (0usize, 0usize, TooLarge) }
            c.st.scratch[used] = 10u8
            used += 1usize
        }
        let line = src[blocks[i].start..blocks[i].start + blocks[i].len]
        if used + line.len > c.st.scratch.len { ret (0usize, 0usize, TooLarge) }
        var k = 0usize
        while k < line.len {
            c.st.scratch[used + k] = line[k]
            k += 1usize
        }
        used += line.len
        i += 1usize
    }
    ret (used, i, ok)
}

type Words = struct { count: usize, after_space: bool, hard: bool }

// Appends one word (a run of bytes without white space at `at` in the joined text).
fn add_word(c: *Ctx, w: *Words, at: usize, bytes: str, style: u8, link: u32) -> err {
    if w.count >= c.st.words.len { ret TooLarge }
    let glued = !w.after_space && !w.hard
    if glued && w.count > 0usize {
        // Adjacent pieces of one word in the same style (the parser splits at `[`, `*`
        // and the like) are one word.
        let last = c.st.words[w.count - 1usize]
        if last.style == style && last.link == link && last.start + last.len == at {
            c.st.words[w.count - 1usize].len += bytes.len
            c.st.words[w.count - 1usize].cols += utf8_cols(bytes)
            ret ok
        }
    }
    c.st.words[w.count] = Word { start: at, len: bytes.len, cols: utf8_cols(bytes), style: style, link: link, glued: glued, hard: w.hard }
    w.count += 1usize
    w.after_space = false
    w.hard = false
    ret ok
}

fn add_text(c: *Ctx, w: *Words, base: usize, seg: str, style: u8, link: u32) -> err {
    var i = 0usize
    while i < seg.len {
        let ch = seg[i]
        if ch == 32u8 || ch == 10u8 || ch == 9u8 || ch == 13u8 {
            w.after_space = true
            i += 1usize
            continue
        }
        var j = i
        while j < seg.len && seg[j] != 32u8 && seg[j] != 10u8 && seg[j] != 9u8 && seg[j] != 13u8 { j += 1usize }
        try add_word(c, w, base + i, seg[i..j], style, link)
        i = j
    }
    ret ok
}

// The inline spans of `joined` as words (styles and links resolved) and the plain label.
fn collect_words(c: *Ctx, joined: str, nodes: []const markdown.Inline) -> (Words, err) {
    var w: Words = zero
    w.after_space = true
    var ends: [32]usize = zero
    var kinds: [32]u8 = zero
    var links: [32]u32 = zero
    var depth = 0usize
    var i = 0usize
    while i < nodes.len {
        let n = nodes[i]
        while depth > 0usize && n.start >= ends[depth - 1usize] { depth -= 1usize }
        var style = 0u8
        var link = 0u32
        var k = 0usize
        while k < depth {
            if kinds[k] == BOLD { style = style | BOLD }
            if kinds[k] == ITALIC { style = style | ITALIC }
            if kinds[k] == IMAGE { style = style | IMAGE }
            if kinds[k] == LINK {
                style = style | LINK
                link = links[k]
            }
            k += 1usize
        }
        if n.kind == .Emph || n.kind == .Strong || n.kind == .Link || n.kind == .Image {
            if depth >= 32usize { ret (w, TooDeep) }
            ends[depth] = n.start + n.len
            links[depth] = 0u32
            if n.kind == .Emph { kinds[depth] = ITALIC }
            if n.kind == .Strong { kinds[depth] = BOLD }
            if n.kind == .Image { kinds[depth] = IMAGE }
            if n.kind == .Link {
                kinds[depth] = LINK
                let (made, e) = put_link(c, n.extra_start, n.extra_len, false)
                if e != ok { ret (w, e) }
                links[depth] = made
            }
            depth += 1usize
        } else if n.kind == .Text {
            let e = add_text(c, &w, n.start, joined[n.start..n.start + n.len], style, link)
            if e != ok { ret (w, e) }
        } else if n.kind == .Code {
            let e = add_text(c, &w, n.start, joined[n.start..n.start + n.len], style | CODE, link)
            if e != ok { ret (w, e) }
        } else if n.kind == .Autolink || n.kind == .Email {
            let body = joined[n.start..n.start + n.len]
            let (made, e1) = put_link(c, n.start, n.len, n.kind == .Email)
            if e1 != ok { ret (w, e1) }
            let e = add_text(c, &w, n.start, body, style | LINK, made)
            if e != ok { ret (w, e) }
        } else if n.kind == .SoftBreak {
            w.after_space = true
        } else if n.kind == .HardBreak {
            w.after_space = true
            w.hard = true
        }
        i += 1usize
    }
    ret (w, ok)
}

// Places the words of a leaf; the number of lines.
fn place_words(c: *Ctx, count: usize, scale: f32, x0: f32, avail: f32, top: f32, node: usize, extra: u8) -> (usize, err) {
    let adv = c.m.char_w * scale
    let lh = c.m.line_h * scale
    var line = 0usize
    var col: f32 = 0.0
    var first = true
    var i = 0usize
    while i < count {
        let w = c.st.words[i]
        let wide = f32(w.cols) * adv
        if w.hard && !first {
            line += 1usize
            col = 0.0
            first = true
        }
        var sep: f32 = 0.0
        if !first && !w.glued { sep = adv }
        if !first && col + sep + wide > avail {
            line += 1usize
            col = 0.0
            first = true
            sep = 0.0
        }
        var style = w.style | extra
        if w.glued { style = style | GLUED }
        try put_item(c, Item { kind: .Word, style: style, x: x0 + col + sep, y: top + f32(line) * lh, w: wide, h: lh, start: w.start, len: w.len, link: w.link, node: u32(node) })
        col = col + sep + wide
        first = false
        i += 1usize
    }
    if count == 0usize { ret (0usize, ok) }
    ret (line + 1usize, ok)
}

fn text_leaf(c: *Ctx, src: str, blocks: []const markdown.Block, from: usize, heading: u32) -> (usize, err) {
    let (used, end, join_error) = join_lines(c, src, blocks, from + 1usize)
    if join_error != ok { ret (0usize, join_error) }
    let (count, parse_error) = markdown.parse_inlines(c.st.scratch[0usize..used], c.st.inlines)
    if parse_error != ok { ret (0usize, parse_error) }
    var role: NodeRole = .Paragraph
    var scale: f32 = 1.0
    var extra = 0u8
    if heading > 0u32 {
        role = .Heading
        scale = heading_scale(heading)
        extra = HEADING
    }
    let (node, node_error) = put_node(c, role, heading)
    if node_error != ok { ret (0usize, node_error) }
    let (top, begin_error) = begin_leaf(c, scale)
    if begin_error != ok { ret (0usize, begin_error) }
    let links_before = c.links
    let joined = c.st.scratch[0usize..used]
    let (w, words_error) = collect_words(c, joined, c.st.inlines[0usize..count])
    if words_error != ok { ret (0usize, words_error) }
    let (label_start, label_len, commit_error) = commit_words(c, joined, w.count)
    if commit_error != ok { ret (0usize, commit_error) }
    try commit_links(c, joined, links_before)
    let x0 = f32(c.levels) * c.m.indent
    let (lines, place_error) = place_words(c, w.count, scale, x0, avail_width(c, x0), top, node, extra)
    if place_error != ok { ret (0usize, place_error) }
    let height = f32(lines) * c.m.line_h * scale
    c.st.nodes[node].label_start = label_start
    c.st.nodes[node].label_len = label_len
    try end_leaf(c, top, height)
    c.st.nodes[node].count = c.items - c.st.nodes[node].first
    ret (end, ok)
}

fn code_leaf(c: *Ctx, src: str, blocks: []const markdown.Block, from: usize) -> (usize, err) {
    let info = blocks[from]
    let (node, node_error) = put_node(c, .Code, 0u32)
    if node_error != ok { ret (0usize, node_error) }
    let (top, begin_error) = begin_leaf(c, 1.0)
    if begin_error != ok { ret (0usize, begin_error) }
    let (label, label_error) = put_bytes(c, src[info.extra_start..info.extra_start + info.extra_len])
    if label_error != ok { ret (0usize, label_error) }
    c.st.nodes[node].label_start = label
    c.st.nodes[node].label_len = info.extra_len
    let x0 = f32(c.levels) * c.m.indent
    var lines = 0usize
    var i = from + 1usize
    while i < blocks.len && blocks[i].kind == .Line {
        lines += 1usize
        i += 1usize
    }
    let height = f32(lines) * c.m.line_h + 2.0 * c.m.pad
    try put_item(c, Item { kind: .CodeBack, style: CODE, x: x0, y: top, w: avail_width(c, x0), h: height, start: 0usize, len: 0usize, link: 0u32, node: u32(node) })
    var k = 0usize
    while k < lines {
        let line = src[blocks[from + 1usize + k].start..blocks[from + 1usize + k].start + blocks[from + 1usize + k].len]
        let (begin, e) = put_bytes(c, line)
        if e != ok { ret (0usize, e) }
        try put_item(c, Item { kind: .CodeLine, style: CODE, x: x0 + c.m.pad, y: top + c.m.pad + f32(k) * c.m.line_h, w: f32(utf8_cols(line)) * c.m.char_w, h: c.m.line_h, start: begin, len: line.len, link: 0u32, node: u32(node) })
        k += 1usize
    }
    try end_leaf(c, top, height)
    c.st.nodes[node].count = c.items - c.st.nodes[node].first
    ret (i, ok)
}

fn push_entry(c: *Ctx, e: Entry) -> err {
    if c.depth >= 32usize { ret TooDeep }
    c.stack[c.depth] = e
    c.depth += 1usize
    if e.kind != E_LIST { c.levels += 1usize }
    ret ok
}

fn pop_entry(c: *Ctx) -> Entry {
    c.depth -= 1usize
    let e = c.stack[c.depth]
    if e.kind != E_LIST { c.levels -= 1usize }
    ret e
}

fn close_node(c: *Ctx, node: usize) {
    c.st.nodes[node].count = c.items - c.st.nodes[node].first
}

fn lay_out(c: *Ctx, src: str, blocks: []const markdown.Block) -> err {
    var i = 0usize
    while i < blocks.len {
        let b = blocks[i]
        let kind = b.kind
        if kind == .ParagraphStart {
            let (end, e) = text_leaf(c, src, blocks, i, 0u32)
            if e != ok { ret e }
            i = end + 1usize
            continue
        }
        if kind == .HeadingStart {
            let (end, e) = text_leaf(c, src, blocks, i, b.level)
            if e != ok { ret e }
            i = end + 1usize
            continue
        }
        if kind == .FencedCodeStart || kind == .IndentedCodeStart {
            let (end, e) = code_leaf(c, src, blocks, i)
            if e != ok { ret e }
            i = end + 1usize
            continue
        }
        if kind == .ThematicBreak {
            let (node, node_error) = put_node(c, .Separator, 0u32)
            if node_error != ok { ret node_error }
            let (top, begin_error) = begin_leaf(c, 1.0)
            if begin_error != ok { ret begin_error }
            let x0 = f32(c.levels) * c.m.indent
            try put_item(c, Item { kind: .Rule, style: 0u8, x: x0, y: top, w: avail_width(c, x0), h: 1.0, start: 0usize, len: 0usize, link: 0u32, node: u32(node) })
            try end_leaf(c, top, 1.0)
            close_node(c, node)
        } else if kind == .BlockQuoteStart {
            let (node, node_error) = put_node(c, .Quote, 0u32)
            if node_error != ok { ret node_error }
            try push_entry(c, Entry { kind: E_QUOTE, level_at: c.levels, tight: false, ordered: false, number: 0u32, marker: false, node: node })
        } else if kind == .BlockQuoteEnd {
            let e = pop_entry(c)
            close_node(c, e.node)
        } else if kind == .BulletListStart || kind == .OrderedListStart {
            var ordered = false
            var first_number = 0u32
            if kind == .OrderedListStart {
                ordered = true
                first_number = b.level
            }
            let (node, node_error) = put_node(c, .List, first_number)
            if node_error != ok { ret node_error }
            try push_entry(c, Entry { kind: E_LIST, level_at: c.levels, tight: !b.loose, ordered: ordered, number: first_number, marker: false, node: node })
            c.fresh = true
        } else if kind == .BulletListEnd || kind == .OrderedListEnd {
            let e = pop_entry(c)
            close_node(c, e.node)
        } else if kind == .ItemStart {
            let list = c.stack[c.depth - 1usize]
            var shown = 0u32
            if list.ordered { shown = list.number }
            let (node, node_error) = put_node(c, .ListItem, shown)
            if node_error != ok { ret node_error }
            try push_entry(c, Entry { kind: E_ITEM, level_at: c.levels, tight: list.tight, ordered: list.ordered, number: list.number, marker: true, node: node })
            c.stack[c.depth - 2usize].number += 1u32
        } else if kind == .ItemEnd {
            let e = pop_entry(c)
            close_node(c, e.node)
        }
        i += 1usize
    }
    ret ok
}

fn reset(c: *Ctx) {
    c.items = 0usize
    c.nodes = 0usize
    c.links = 0usize
    c.store_len = 0usize
    c.y = 0.0
    c.any = false
    c.fresh = false
    c.depth = 0usize
    c.levels = 0usize
}

// The whole source as preformatted lines, for a source nothing else could bound.
fn plain(c: *Ctx, src: str) -> err {
    let (node, node_error) = put_node(c, .Code, 0u32)
    if node_error != ok { ret node_error }
    var starts = 0usize
    var lines = 0usize
    var i = 0usize
    while i <= src.len {
        if i == src.len || src[i] == 10u8 {
            var stop = i
            if stop > starts && src[stop - 1usize] == 13u8 { stop -= 1usize }
            if !(i == src.len && starts == src.len && lines > 0usize) {
                let line = src[starts..stop]
                let (begin, e) = put_bytes(c, line)
                if e != ok { ret e }
                try put_item(c, Item { kind: .CodeLine, style: CODE, x: c.m.pad, y: c.m.pad + f32(lines) * c.m.line_h, w: f32(utf8_cols(line)) * c.m.char_w, h: c.m.line_h, start: begin, len: line.len, link: 0u32, node: u32(node) })
                lines += 1usize
            }
            starts = i + 1usize
        }
        i += 1usize
    }
    c.y = f32(lines) * c.m.line_h + 2.0 * c.m.pad
    close_node(c, node)
    ret ok
}

// Lays `src` out. A source the parser, the depth limit or the storage cannot bound is
// drawn whole as preformatted lines with `fallback` set; only a storage too small even
// for that is an error.
fn build(src: str, st: Storage, m: Metrics, policy: LinkPolicy) -> (View, err) {
    var c: Ctx = zero
    c.st = st
    c.m = m
    c.policy = policy
    var done = false
    var fell_back = false
    let (n, parse_error) = markdown.parse_blocks(src, st.blocks)
    if parse_error == ok {
        let layout_error = lay_out(&c, src, st.blocks[0usize..n])
        if layout_error == ok { done = true }
    }
    if !done {
        reset(&c)
        let plain_error = plain(&c, src)
        if plain_error != ok { ret (zero, plain_error) }
        fell_back = true
    }
    let v = View { items: st.items, nodes: st.nodes, links: st.links, store: st.store, item_count: c.items, node_count: c.nodes, link_count: c.links, store_len: c.store_len, height: c.y, fallback: fell_back, policy: policy }
    ret (v, ok)
}

fn inside(it: Item, x: f32, y: f32) -> bool {
    ret x >= it.x && x < it.x + it.w && y >= it.y && y < it.y + it.h
}

// The topmost word, marker or code line under a point.
fn item_at(v: *const View, x: f32, y: f32) -> (usize, bool) {
    var i = v.item_count
    while i > 0usize {
        i -= 1usize
        let it = v.items[i]
        if (it.kind == .Word || it.kind == .Marker || it.kind == .CodeLine) && inside(it, x, y) { ret (i, true) }
    }
    ret (0usize, false)
}

// The link under a point: its index.
fn link_at(v: *const View, x: f32, y: f32) -> (usize, bool) {
    let (i, found) = item_at(v, x, y)
    if !found || v.items[i].link == 0u32 { ret (0usize, false) }
    ret (usize(v.items[i].link) - 1usize, true)
}

// A link's destination for the host to open: only under `HostActivated`, and only if safe.
fn activation(v: *const View, link: usize) -> (str, bool) {
    if link >= v.link_count || v.policy != .HostActivated || !v.links[link].safe { ret ("", false) }
    let l = v.links[link]
    ret (v.store[l.dest_start..l.dest_start + l.dest_len], true)
}

// The text of items `first` to `last` (inclusive) into `out`, words on a line joined by a
// space unless glued, lines by `\n`; the length.
fn selected_text(v: *const View, first: usize, last: usize, out: []u8) -> (usize, err) {
    if first > last || last >= v.item_count { ret (0usize, Invalid) }
    var used = 0usize
    var have = false
    var prev_y: f32 = 0.0
    var i = first
    while i <= last {
        let it = v.items[i]
        if it.kind == .Word || it.kind == .CodeLine {
            if have {
                var sep = 32u8
                if it.y != prev_y { sep = 10u8 }
                if it.kind == .Word && sep == 32u8 && (it.style & GLUED) != 0u8 {
                    sep = 0u8
                }
                if sep != 0u8 {
                    if used >= out.len { ret (0usize, TooLarge) }
                    out[used] = sep
                    used += 1usize
                }
            }
            if used + it.len > out.len { ret (0usize, TooLarge) }
            var k = 0usize
            while k < it.len {
                out[used + k] = v.store[it.start + k]
                k += 1usize
            }
            used += it.len
            have = true
            prev_y = it.y
        }
        i += 1usize
    }
    ret (used, ok)
}

// A text leaf's words as `control.paragraph` spans: bold, italic, code and link kinds, the
// trailing space kept, a link carrying `action` only when it is activatable.
fn rich_spans(v: *const View, node: usize, out: []control.RichSpan, action: widget.Submit) -> (usize, err) {
    if node >= v.node_count { ret (0usize, Invalid) }
    let nd = v.nodes[node]
    if nd.role != .Heading && nd.role != .Paragraph { ret (0usize, Invalid) }
    let limit = nd.label_start + nd.label_len
    var n = 0usize
    var i = nd.first
    while i < nd.first + nd.count {
        let it = v.items[i]
        if it.kind == .Word {
            if n >= out.len { ret (0usize, TooLarge) }
            var stop = it.start + it.len
            if stop < limit && v.store[stop] == 32u8 { stop += 1usize }
            var kind: control.SpanKind = .Plain
            if (it.style & CODE) != 0u8 {
                kind = .Code
            } else if (it.style & LINK) != 0u8 {
                kind = .Link
            } else if (it.style & BOLD) != 0u8 {
                kind = .Strong
            } else if (it.style & ITALIC) != 0u8 {
                kind = .Emphasis
            }
            var s = control.rich_span(v.store[it.start..stop], kind)
            if it.link != 0u32 {
                let (_, live) = activation(v, usize(it.link) - 1usize)
                if live { s.action = action }
            }
            out[n] = s
            n += 1usize
        }
        i += 1usize
    }
    ret (n, ok)
}
