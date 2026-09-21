// Markdown, the CommonMark subset the fence names, as two passes over caller storage.
//
// `parse_blocks` is the line-oriented pass: a stack of open containers -- block quotes, lists
// and their items -- is matched against each line's prefix, then the remainder is looked at
// for what starts a new block, and what is left is text for the paragraph in progress or a
// lazy continuation of it. Every leaf that carries text is a start event, one `Line` event
// per line with the container prefixes already stripped, and an end event; a caller who
// wants a paragraph's text joins its lines with `\n` and hands that to `parse_inlines`.
//
// `parse_inlines` is the delimiter-run pass of the spec: text, code spans, autolinks and
// breaks are placed as they are scanned, brackets and emphasis runs are kept on a stack and
// resolved into `Link`, `Image`, `Emph` and `Strong` spans, and the result is sorted so a
// container precedes what it contains. Every span is over the input; nothing is copied.
//
// ponytail: whitespace and punctuation are ASCII for the flanking rules, a tab is one column,
// and reference links, entities, raw HTML and link destinations needing normalization are
// out of scope -- they read as text.

use e.str

type BlockKind = enum u8 { ParagraphStart, ParagraphEnd, HeadingStart, HeadingEnd, FencedCodeStart, FencedCodeEnd, IndentedCodeStart, IndentedCodeEnd, ThematicBreak, BlockQuoteStart, BlockQuoteEnd, BulletListStart, BulletListEnd, OrderedListStart, OrderedListEnd, ItemStart, ItemEnd, Line }

// `level`: the heading's level, an ordered list's first number or a bullet list's marker
// byte. `indent`: an item's content indent. `loose`: on both events of a list. The fenced
// code start's `extra` is its info string.
type Block = struct { kind: BlockKind, level: u32, start: usize, len: usize, indent: usize, loose: bool, extra_start: usize, extra_len: usize }

type InlineKind = enum u8 { Text, Code, Emph, Strong, Link, Image, Autolink, Email, SoftBreak, HardBreak }

// `start`/`len` is the content: a link's text, an emphasis's inside, a code span's bytes
// after the spec's space stripping. A link's `extra` is its destination and `title` its
// title, `title_len` zero when there is none.
type Inline = struct { kind: InlineKind, start: usize, len: usize, extra_start: usize, extra_len: usize, title_start: usize, title_len: usize }

error TooLarge
error TooDeep

const MAX_DEPTH: usize = 32usize
const MAX_DELIMITERS: usize = 128usize

const TAB: u8 = 9u8
const LF: u8 = 10u8
const CR: u8 = 13u8
const SPACE: u8 = 32u8

const QUOTE: u8 = 1u8
const LIST: u8 = 2u8
const ITEM: u8 = 3u8

const LEAF_NONE: u8 = 0u8
const LEAF_PARAGRAPH: u8 = 1u8
const LEAF_FENCED: u8 = 2u8
const LEAF_INDENTED: u8 = 3u8

type Blocks = struct { text: str, out: []Block, count: usize, kind: [MAX_DEPTH]u8, data: [MAX_DEPTH]usize, marker: [MAX_DEPTH]u8, ordered: [MAX_DEPTH]bool, blank_pending: [MAX_DEPTH]bool, loose: [MAX_DEPTH]bool, open: usize, leaf: u8, leaf_index: usize, fence_char: u8, fence_len: usize, fence_indent: usize, pending_blanks: usize }

fn emit(s: *Blocks, kind: BlockKind, start: usize, len: usize) -> (usize, err) {
    if s.count >= s.out.len { ret (0usize, TooLarge) }
    var b: Block = zero
    b.kind = kind
    b.start = start
    b.len = len
    s.out[s.count] = b
    s.count += 1usize
    ret (s.count - 1usize, ok)
}

fn spaces_from(text: str, at: usize, stop: usize) -> usize {
    var i = at
    while i < stop && (text[i] == SPACE || text[i] == TAB) { i += 1usize }
    ret i - at
}

fn close_leaf(s: *Blocks) -> err {
    if s.leaf == LEAF_PARAGRAPH {
        let (_, e) = emit(s, .ParagraphEnd, 0usize, 0usize)
        if e != ok { ret e }
    } else if s.leaf == LEAF_FENCED {
        let (_, e) = emit(s, .FencedCodeEnd, 0usize, 0usize)
        if e != ok { ret e }
    } else if s.leaf == LEAF_INDENTED {
        let (_, e) = emit(s, .IndentedCodeEnd, 0usize, 0usize)
        if e != ok { ret e }
    }
    s.leaf = LEAF_NONE
    s.pending_blanks = 0usize
    ret ok
}

// Everything from container `from` up, innermost first, the leaf before any of them.
fn close_from(s: *Blocks, from: usize) -> err {
    try close_leaf(s)
    while s.open > from {
        s.open -= 1usize
        let k = s.kind[s.open]
        if k == QUOTE {
            let (_, e) = emit(s, .BlockQuoteEnd, 0usize, 0usize)
            if e != ok { ret e }
        } else if k == ITEM {
            let (_, e) = emit(s, .ItemEnd, 0usize, 0usize)
            if e != ok { ret e }
        } else {
            var kind: BlockKind = .BulletListEnd
            if s.ordered[s.open] { kind = .OrderedListEnd }
            let (at, e) = emit(s, kind, 0usize, 0usize)
            if e != ok { ret e }
            s.out[at].loose = s.loose[s.open]
            s.out[s.data[s.open]].loose = s.loose[s.open]
        }
    }
    ret ok
}

// Containers from the first unmatched one up; an unmatched item takes its list with it,
// since a list holds nothing but items.
fn close_unmatched(s: *Blocks, matched: usize) -> err {
    var from = matched
    if from < s.open && s.kind[from] == ITEM { from -= 1usize }
    ret close_from(s, from)
}

fn push(s: *Blocks, kind: u8, data: usize) -> err {
    if s.open >= MAX_DEPTH { ret TooDeep }
    s.kind[s.open] = kind
    s.data[s.open] = data
    s.blank_pending[s.open] = false
    s.loose[s.open] = false
    s.open += 1usize
    ret ok
}

// Content has arrived: a blank line pending on the innermost open list separated two things
// in it, so that list is loose; a blank pending on an outer one was inside a nested list.
fn settle_lists(s: *Blocks) {
    var i = s.open
    var innermost = true
    while i > 0usize {
        i -= 1usize
        if s.kind[i] == LIST {
            if innermost && s.blank_pending[i] { s.loose[i] = true }
            s.blank_pending[i] = false
            innermost = false
        }
    }
}

// A blank line reaches every open list that is not shut off from it by a block quote.
fn note_blank(s: *Blocks) {
    var i = s.open
    var quoted = false
    while i > 0usize {
        i -= 1usize
        if s.kind[i] == QUOTE { quoted = true }
        if s.kind[i] == LIST && !quoted { s.blank_pending[i] = true }
    }
}

fn open_leaf(s: *Blocks, kind: BlockKind, leaf: u8) -> err {
    let (at, e) = emit(s, kind, 0usize, 0usize)
    if e != ok { ret e }
    s.leaf = leaf
    s.leaf_index = at
    ret ok
}

fn is_break_char(c: u8) -> bool {
    ret c == 42u8 || c == 45u8 || c == 95u8
}

// A thematic break: three or more of one of `*-_`, spaces between them, nothing else.
fn is_thematic(text: str, at: usize, stop: usize) -> bool {
    let c = text[at]
    if !is_break_char(c) { ret false }
    var n = 0usize
    var i = at
    while i < stop {
        if text[i] == c {
            n += 1usize
        } else if text[i] != SPACE && text[i] != TAB {
            ret false
        }
        i += 1usize
    }
    ret n >= 3usize
}

fn only_spaces(text: str, at: usize, stop: usize) -> bool {
    ret spaces_from(text, at, stop) == stop - at
}

// The ATX heading's content: the `#`s and the space behind, closing `#`s and blanks off.
fn heading_content(text: str, at: usize, stop: usize) -> (usize, usize) {
    var from = at + spaces_from(text, at, stop)
    var to = stop
    while to > from && (text[to - 1usize] == SPACE || text[to - 1usize] == TAB) { to -= 1usize }
    var hashes = to
    while hashes > from && text[hashes - 1usize] == 35u8 { hashes -= 1usize }
    if hashes < to && (hashes == from || text[hashes - 1usize] == SPACE || text[hashes - 1usize] == TAB) {
        to = hashes
        while to > from && (text[to - 1usize] == SPACE || text[to - 1usize] == TAB) { to -= 1usize }
    }
    ret (from, to - from)
}

fn line(s: *Blocks, at: usize, stop: usize) -> err {
    let (_, e) = emit(s, .Line, at, stop - at)
    ret e
}

// One line, `at..stop` without its ending.
fn process(s: *Blocks, at: usize, stop: usize) -> err {
    let text = s.text
    var pos = at
    var matched = 0usize
    while matched < s.open {
        let k = s.kind[matched]
        if k == QUOTE {
            let lead = spaces_from(text, pos, stop)
            if lead <= 3usize && pos + lead < stop && text[pos + lead] == 62u8 {
                pos += lead + 1usize
                if pos < stop && (text[pos] == SPACE || text[pos] == TAB) { pos += 1usize }
            } else {
                break
            }
        } else if k == ITEM {
            let lead = spaces_from(text, pos, stop)
            if pos + lead >= stop {
                // A blank line belongs to the item.
            } else if lead >= s.data[matched] {
                pos += s.data[matched]
            } else {
                break
            }
        }
        matched += 1usize
    }
    var indent = spaces_from(text, pos, stop)
    var rest = pos + indent
    if s.leaf == LEAF_FENCED {
        if matched == s.open {
            if indent <= 3usize && rest < stop && text[rest] == s.fence_char {
                var run = rest
                while run < stop && text[run] == s.fence_char { run += 1usize }
                if run - rest >= s.fence_len && only_spaces(text, run, stop) { ret close_leaf(s) }
            }
            var strip = indent
            if strip > s.fence_indent { strip = s.fence_indent }
            ret line(s, pos + strip, stop)
        }
        try close_unmatched(s, matched)
    }
    if rest >= stop {
        if s.leaf == LEAF_INDENTED && matched == s.open {
            s.pending_blanks += 1usize
            ret ok
        }
        try close_unmatched(s, matched)
        note_blank(s)
        ret ok
    }
    if indent >= 4usize && s.leaf != LEAF_PARAGRAPH {
        if matched < s.open { try close_unmatched(s, matched) }
        settle_lists(s)
        if s.leaf != LEAF_INDENTED {
            try close_leaf(s)
            try open_leaf(s, .IndentedCodeStart, LEAF_INDENTED)
        }
        while s.pending_blanks > 0usize {
            try line(s, pos, pos)
            s.pending_blanks -= 1usize
        }
        ret line(s, pos + 4usize, stop)
    }
    var opened = false
    while true {
        indent = spaces_from(text, pos, stop)
        rest = pos + indent
        if rest >= stop { ret ok }
        if indent >= 4usize {
            if !opened { break }
            try open_leaf(s, .IndentedCodeStart, LEAF_INDENTED)
            ret line(s, pos + 4usize, stop)
        }
        let c = text[rest]
        if c == 35u8 {
            var level = 0usize
            while rest + level < stop && text[rest + level] == 35u8 { level += 1usize }
            if level <= 6usize && (rest + level >= stop || text[rest + level] == SPACE || text[rest + level] == TAB) {
                try close_unmatched(s, matched)
                settle_lists(s)
                let (from, len) = heading_content(text, rest + level, stop)
                let (head, e) = emit(s, .HeadingStart, 0usize, 0usize)
                if e != ok { ret e }
                s.out[head].level = u32(level)
                try line(s, from, from + len)
                let (_, end_error) = emit(s, .HeadingEnd, 0usize, 0usize)
                ret end_error
            }
        }
        if c == 96u8 || c == 126u8 {
            var run = rest
            while run < stop && text[run] == c { run += 1usize }
            let info_from = run + spaces_from(text, run, stop)
            var info_to = stop
            while info_to > info_from && (text[info_to - 1usize] == SPACE || text[info_to - 1usize] == TAB) { info_to -= 1usize }
            var fence = run - rest >= 3usize
            if c == 96u8 {
                var i = info_from
                while i < info_to {
                    if text[i] == 96u8 { fence = false }
                    i += 1usize
                }
            }
            if fence {
                try close_unmatched(s, matched)
                settle_lists(s)
                try open_leaf(s, .FencedCodeStart, LEAF_FENCED)
                s.out[s.leaf_index].extra_start = info_from
                s.out[s.leaf_index].extra_len = info_to - info_from
                s.fence_char = c
                s.fence_len = run - rest
                s.fence_indent = indent
                ret ok
            }
        }
        if s.leaf == LEAF_PARAGRAPH && matched == s.open && !opened && (c == 61u8 || c == 45u8) {
            var run = rest
            while run < stop && text[run] == c { run += 1usize }
            if only_spaces(text, run, stop) {
                s.out[s.leaf_index].kind = .HeadingStart
                s.out[s.leaf_index].level = 2u32
                if c == 61u8 { s.out[s.leaf_index].level = 1u32 }
                s.leaf = LEAF_NONE
                let (_, e) = emit(s, .HeadingEnd, 0usize, 0usize)
                ret e
            }
        }
        if is_thematic(text, rest, stop) {
            try close_unmatched(s, matched)
            settle_lists(s)
            let (_, e) = emit(s, .ThematicBreak, 0usize, 0usize)
            ret e
        }
        if c == 62u8 {
            try close_unmatched(s, matched)
            settle_lists(s)
            try push(s, QUOTE, 0usize)
            let (_, e) = emit(s, .BlockQuoteStart, 0usize, 0usize)
            if e != ok { ret e }
            pos = rest + 1usize
            if pos < stop && (text[pos] == SPACE || text[pos] == TAB) { pos += 1usize }
            matched = s.open
            opened = true
            continue
        }
        // A list marker: a bullet, or up to nine digits and `.` or `)`, then a blank or the end.
        var width = 0usize
        var ordered = false
        var number = 0u32
        var marker = c
        if c == 45u8 || c == 43u8 || c == 42u8 {
            width = 1usize
        } else if str.is_ascii_digit(c) {
            var i = rest
            while i < stop && str.is_ascii_digit(text[i]) && i - rest < 9usize {
                number = number * 10u32 + u32(text[i] - 48u8)
                i += 1usize
            }
            if i < stop && (text[i] == 46u8 || text[i] == 41u8) {
                width = i + 1usize - rest
                ordered = true
                marker = text[i]
            }
        }
        if width > 0usize && (rest + width >= stop || text[rest + width] == SPACE || text[rest + width] == TAB) {
            let after = rest + width
            let gap = spaces_from(text, after, stop)
            let empty = after + gap >= stop
            var taken = gap
            if gap == 0usize || gap >= 5usize || empty { taken = 1usize }
            // Only a non-empty item, and an ordered one starting at 1, may interrupt a paragraph.
            let interrupts = s.leaf == LEAF_PARAGRAPH && !opened && matched == s.open
            if !(interrupts && (empty || (ordered && number != 1u32))) {
                let content = indent + width + taken
                var sibling = matched < s.open && s.kind[matched] == ITEM && matched > 0usize && s.kind[matched - 1usize] == LIST
                if sibling && (s.ordered[matched - 1usize] != ordered || s.marker[matched - 1usize] != marker) { sibling = false }
                if sibling {
                    try close_from(s, matched)
                    settle_lists(s)
                } else {
                    try close_unmatched(s, matched)
                    settle_lists(s)
                    var kind: BlockKind = .BulletListStart
                    if ordered { kind = .OrderedListStart }
                    let (list, e) = emit(s, kind, 0usize, 0usize)
                    if e != ok { ret e }
                    s.out[list].level = u32(marker)
                    if ordered { s.out[list].level = number }
                    try push(s, LIST, list)
                    s.marker[s.open - 1usize] = marker
                    s.ordered[s.open - 1usize] = ordered
                }
                try push(s, ITEM, content)
                let (item, e) = emit(s, .ItemStart, 0usize, 0usize)
                if e != ok { ret e }
                s.out[item].indent = content
                pos = pos + content
                matched = s.open
                opened = true
                if empty { ret ok }
                continue
            }
        }
        break
    }
    if s.leaf == LEAF_PARAGRAPH { ret line(s, rest, stop) }
    try close_unmatched(s, matched)
    settle_lists(s)
    try open_leaf(s, .ParagraphStart, LEAF_PARAGRAPH)
    ret line(s, rest, stop)
}

// The block events of `text` into `out`; how many were written.
fn parse_blocks(text: str, out: []Block) -> (usize, err) {
    var s: Blocks = zero
    s.text = text
    s.out = out
    var at = 0usize
    while at < text.len {
        var stop = at
        while stop < text.len && text[stop] != LF { stop += 1usize }
        var trimmed = stop
        if trimmed > at && text[trimmed - 1usize] == CR { trimmed -= 1usize }
        let e = process(&s, at, trimmed)
        if e != ok { ret (0usize, e) }
        at = stop + 1usize
    }
    let e = close_from(&s, 0usize)
    if e != ok { ret (0usize, e) }
    ret (s.count, ok)
}

// --- Inlines.

type Delimiter = struct { pos: usize, count: usize, original: usize, ch: u8, can_open: bool, can_close: bool, active: bool, removed: bool, node: usize }

type Inlines = struct { text: str, out: []Inline, count: usize, delimiters: [MAX_DELIMITERS]Delimiter, delimiter_count: usize }

fn add(s: *Inlines, kind: InlineKind, start: usize, len: usize) -> (usize, err) {
    if s.count >= s.out.len { ret (0usize, TooLarge) }
    var node: Inline = zero
    node.kind = kind
    node.start = start
    node.len = len
    s.out[s.count] = node
    s.count += 1usize
    ret (s.count - 1usize, ok)
}

fn add_delimiter(s: *Inlines, d: Delimiter) -> err {
    if s.delimiter_count >= MAX_DELIMITERS { ret TooLarge }
    s.delimiters[s.delimiter_count] = d
    s.delimiter_count += 1usize
    ret ok
}

fn is_punct(c: u8) -> bool {
    ret (c >= 33u8 && c <= 47u8) || (c >= 58u8 && c <= 64u8) || (c >= 91u8 && c <= 96u8) || (c >= 123u8 && c <= 126u8)
}

fn is_white(c: u8) -> bool {
    ret c == SPACE || c == TAB || c == LF || c == CR || c == 12u8
}

fn is_scheme_char(c: u8) -> bool {
    ret str.is_ascii_alnum(c) || c == 43u8 || c == 46u8 || c == 45u8
}

// An autolink at `at` (the `<`): where it ends and whether it is an email, or no autolink.
fn autolink(text: str, at: usize) -> (usize, bool, bool) {
    var i = at + 1usize
    var scheme = 0usize
    while i < text.len && is_scheme_char(text[i]) {
        scheme += 1usize
        i += 1usize
    }
    if scheme >= 2usize && scheme <= 32usize && i < text.len && text[i] == 58u8 && str.is_ascii_alpha(text[at + 1usize]) {
        i += 1usize
        while i < text.len && text[i] != 62u8 && text[i] != 60u8 && !is_white(text[i]) && text[i] > 31u8 { i += 1usize }
        if i < text.len && text[i] == 62u8 { ret (i, false, true) }
    }
    i = at + 1usize
    var local = 0usize
    while i < text.len && (str.is_ascii_alnum(text[i]) || (is_punct(text[i]) && text[i] != 62u8 && text[i] != 60u8 && text[i] != 64u8 && text[i] != 34u8 && text[i] != 40u8 && text[i] != 41u8 && text[i] != 44u8 && text[i] != 58u8 && text[i] != 59u8 && text[i] != 91u8 && text[i] != 92u8 && text[i] != 93u8)) {
        local += 1usize
        i += 1usize
    }
    if local == 0usize || i >= text.len || text[i] != 64u8 { ret (0usize, false, false) }
    i += 1usize
    var label = 0usize
    while i < text.len && (str.is_ascii_alnum(text[i]) || text[i] == 45u8 || (text[i] == 46u8 && label > 0usize)) {
        if text[i] == 46u8 { label = 0usize } else { label += 1usize }
        i += 1usize
    }
    if label == 0usize || i >= text.len || text[i] != 62u8 { ret (0usize, false, false) }
    ret (i, true, true)
}

// The code span whose opening run is `at..run_end`: its content, or none when no run of the
// same length closes it.
fn code_span(text: str, at: usize, run_end: usize) -> (usize, usize, usize, bool) {
    let n = run_end - at
    var i = run_end
    while i < text.len {
        if text[i] != 96u8 {
            i += 1usize
            continue
        }
        var j = i
        while j < text.len && text[j] == 96u8 { j += 1usize }
        if j - i == n {
            var from = run_end
            var to = i
            var all_space = true
            var k = from
            while k < to {
                if text[k] != SPACE && text[k] != LF { all_space = false }
                k += 1usize
            }
            if !all_space && to - from >= 2usize && (text[from] == SPACE || text[from] == LF) && (text[to - 1usize] == SPACE || text[to - 1usize] == LF) {
                from += 1usize
                to -= 1usize
            }
            ret (from, to, j, true)
        }
        i = j
    }
    ret (0usize, 0usize, 0usize, false)
}

// A link destination and optional title after `(`; where the `)` is, or none.
fn link_tail(text: str, at: usize) -> (usize, usize, usize, usize, usize, bool) {
    var i = at
    while i < text.len && is_white(text[i]) { i += 1usize }
    var dest_from = i
    var dest_to = i
    if i < text.len && text[i] == 60u8 {
        i += 1usize
        dest_from = i
        while i < text.len && text[i] != 62u8 && text[i] != 60u8 && text[i] != LF {
            if text[i] == 92u8 && i + 1usize < text.len && is_punct(text[i + 1usize]) { i += 1usize }
            i += 1usize
        }
        if i >= text.len || text[i] != 62u8 { ret (0usize, 0usize, 0usize, 0usize, 0usize, false) }
        dest_to = i
        i += 1usize
    } else {
        var depth = 0usize
        while i < text.len && !is_white(text[i]) && text[i] > 31u8 {
            let c = text[i]
            if c == 92u8 && i + 1usize < text.len && is_punct(text[i + 1usize]) {
                i += 2usize
                continue
            }
            if c == 40u8 { depth += 1usize }
            if c == 41u8 {
                if depth == 0usize { break }
                depth -= 1usize
            }
            i += 1usize
        }
        if depth != 0usize { ret (0usize, 0usize, 0usize, 0usize, 0usize, false) }
        dest_to = i
    }
    let after_dest = i
    while i < text.len && is_white(text[i]) { i += 1usize }
    var title_from = 0usize
    var title_to = 0usize
    if i < text.len && i > after_dest && (text[i] == 34u8 || text[i] == 39u8 || text[i] == 40u8) {
        var closer = text[i]
        if closer == 40u8 { closer = 41u8 }
        i += 1usize
        title_from = i
        while i < text.len && text[i] != closer {
            if closer == 41u8 && text[i] == 40u8 { ret (0usize, 0usize, 0usize, 0usize, 0usize, false) }
            if text[i] == 92u8 && i + 1usize < text.len && is_punct(text[i + 1usize]) { i += 1usize }
            i += 1usize
        }
        if i >= text.len { ret (0usize, 0usize, 0usize, 0usize, 0usize, false) }
        title_to = i
        i += 1usize
        while i < text.len && is_white(text[i]) { i += 1usize }
    }
    if i >= text.len || text[i] != 41u8 { ret (0usize, 0usize, 0usize, 0usize, 0usize, false) }
    ret (dest_from, dest_to, title_from, title_to, i, true)
}

// The spec's algorithm over the delimiters from `bottom` up: each closer looks back for an
// opener of its byte, and the pair becomes a `Strong` when both have two to spare, else an
// `Emph`; the bytes used come off the text nodes the runs were placed as.
fn process_emphasis(s: *Inlines, bottom: usize) -> err {
    var closer = bottom
    while closer < s.delimiter_count {
        let c = s.delimiters[closer]
        if c.removed || !c.can_close || (c.ch != 42u8 && c.ch != 95u8) {
            closer += 1usize
            continue
        }
        var opener = closer
        var found = false
        while opener > bottom {
            opener -= 1usize
            let o = s.delimiters[opener]
            if o.removed || o.ch != c.ch || !o.can_open { continue }
            if (o.can_close || c.can_open) && (o.original + c.original) % 3usize == 0usize && !(o.original % 3usize == 0usize && c.original % 3usize == 0usize) { continue }
            found = true
            break
        }
        if !found {
            if !c.can_open { s.delimiters[closer].removed = true }
            closer += 1usize
            continue
        }
        var take = 1usize
        if s.delimiters[opener].count >= 2usize && s.delimiters[closer].count >= 2usize { take = 2usize }
        var kind: InlineKind = .Emph
        if take == 2usize { kind = .Strong }
        s.delimiters[opener].count -= take
        let content_from = s.delimiters[opener].pos + s.delimiters[opener].count
        let content_to = s.delimiters[closer].pos
        let (_, e) = add(s, kind, content_from, content_to - content_from)
        if e != ok { ret e }
        s.out[s.delimiters[opener].node].len -= take
        s.delimiters[closer].pos += take
        s.delimiters[closer].count -= take
        s.out[s.delimiters[closer].node].start += take
        s.out[s.delimiters[closer].node].len -= take
        var between = opener + 1usize
        while between < closer {
            s.delimiters[between].removed = true
            between += 1usize
        }
        if s.delimiters[opener].count == 0usize { s.delimiters[opener].removed = true }
        if s.delimiters[closer].count == 0usize {
            s.delimiters[closer].removed = true
            closer += 1usize
        }
    }
    ret ok
}

fn flush_text(s: *Inlines, from: usize, to: usize) -> err {
    if to <= from { ret ok }
    let (_, e) = add(s, .Text, from, to - from)
    ret e
}

fn parse_inlines(text: str, out: []Inline) -> (usize, err) {
    var s: Inlines = zero
    s.text = text
    s.out = out
    var i = 0usize
    var text_start = 0usize
    while i < text.len {
        let c = text[i]
        if c == 92u8 {
            if i + 1usize < text.len && text[i + 1usize] == LF {
                let e = flush_text(&s, text_start, i)
                if e != ok { ret (0usize, e) }
                let (_, break_error) = add(&s, .HardBreak, i, 2usize)
                if break_error != ok { ret (0usize, break_error) }
                i += 2usize
                while i < text.len && (text[i] == SPACE || text[i] == TAB) { i += 1usize }
                text_start = i
                continue
            }
            if i + 1usize < text.len && is_punct(text[i + 1usize]) {
                let e = flush_text(&s, text_start, i)
                if e != ok { ret (0usize, e) }
                text_start = i + 1usize
                i += 2usize
                continue
            }
            i += 1usize
            continue
        }
        if c == LF {
            var to = i
            while to > text_start && text[to - 1usize] == SPACE { to -= 1usize }
            let e = flush_text(&s, text_start, to)
            if e != ok { ret (0usize, e) }
            var kind: InlineKind = .SoftBreak
            if i - to >= 2usize { kind = .HardBreak }
            let (_, break_error) = add(&s, kind, to, i + 1usize - to)
            if break_error != ok { ret (0usize, break_error) }
            i += 1usize
            while i < text.len && (text[i] == SPACE || text[i] == TAB) { i += 1usize }
            text_start = i
            continue
        }
        if c == 96u8 {
            var run = i
            while run < text.len && text[run] == 96u8 { run += 1usize }
            let (from, to, after, closed) = code_span(text, i, run)
            if closed {
                let flush_error = flush_text(&s, text_start, i)
                if flush_error != ok { ret (0usize, flush_error) }
                let (_, code_error) = add(&s, .Code, from, to - from)
                if code_error != ok { ret (0usize, code_error) }
                i = after
                text_start = i
                continue
            }
            i = run
            continue
        }
        if c == 60u8 {
            let (stop, email, is_link) = autolink(text, i)
            if is_link {
                let e = flush_text(&s, text_start, i)
                if e != ok { ret (0usize, e) }
                var kind: InlineKind = .Autolink
                if email { kind = .Email }
                let (_, link_error) = add(&s, kind, i + 1usize, stop - i - 1usize)
                if link_error != ok { ret (0usize, link_error) }
                i = stop + 1usize
                text_start = i
                continue
            }
            i += 1usize
            continue
        }
        if c == 42u8 || c == 95u8 {
            var run = i
            while run < text.len && text[run] == c { run += 1usize }
            var before = SPACE
            if i > 0usize { before = text[i - 1usize] }
            var after = SPACE
            if run < text.len { after = text[run] }
            let left = !is_white(after) && (!is_punct(after) || is_white(before) || is_punct(before))
            let right = !is_white(before) && (!is_punct(before) || is_white(after) || is_punct(after))
            var d: Delimiter = zero
            d.pos = i
            d.count = run - i
            d.original = run - i
            d.ch = c
            d.active = true
            if c == 42u8 {
                d.can_open = left
                d.can_close = right
            } else {
                d.can_open = left && (!right || is_punct(before))
                d.can_close = right && (!left || is_punct(after))
            }
            let e = flush_text(&s, text_start, i)
            if e != ok { ret (0usize, e) }
            let (node, node_error) = add(&s, .Text, i, run - i)
            if node_error != ok { ret (0usize, node_error) }
            d.node = node
            let delimiter_error = add_delimiter(&s, d)
            if delimiter_error != ok { ret (0usize, delimiter_error) }
            i = run
            text_start = i
            continue
        }
        if c == 91u8 || (c == 33u8 && i + 1usize < text.len && text[i + 1usize] == 91u8) {
            var width = 1usize
            if c == 33u8 { width = 2usize }
            let e = flush_text(&s, text_start, i)
            if e != ok { ret (0usize, e) }
            let (node, node_error) = add(&s, .Text, i, width)
            if node_error != ok { ret (0usize, node_error) }
            var d: Delimiter = zero
            d.pos = i
            d.count = width
            d.ch = c
            d.active = true
            d.node = node
            let delimiter_error = add_delimiter(&s, d)
            if delimiter_error != ok { ret (0usize, delimiter_error) }
            i += width
            text_start = i
            continue
        }
        if c == 93u8 {
            var opener = s.delimiter_count
            var found = false
            while opener > 0usize {
                opener -= 1usize
                let d = s.delimiters[opener]
                if !d.removed && (d.ch == 91u8 || d.ch == 33u8) {
                    found = true
                    break
                }
            }
            if !found {
                i += 1usize
                continue
            }
            s.delimiters[opener].removed = true
            if !s.delimiters[opener].active {
                i += 1usize
                continue
            }
            var matched = false
            if i + 1usize < text.len && text[i + 1usize] == 40u8 {
                let (dest_from, dest_to, title_from, title_to, close, is_link) = link_tail(text, i + 2usize)
                if is_link {
                    matched = true
                    let e = flush_text(&s, text_start, i)
                    if e != ok { ret (0usize, e) }
                    let d = s.delimiters[opener]
                    var kind: InlineKind = .Link
                    if d.ch == 33u8 { kind = .Image }
                    let content = d.pos + d.count
                    let (node, node_error) = add(&s, kind, content, i - content)
                    if node_error != ok { ret (0usize, node_error) }
                    s.out[node].extra_start = dest_from
                    s.out[node].extra_len = dest_to - dest_from
                    s.out[node].title_start = title_from
                    s.out[node].title_len = title_to - title_from
                    s.out[d.node].len = 0usize
                    let emphasis_error = process_emphasis(&s, opener + 1usize)
                    if emphasis_error != ok { ret (0usize, emphasis_error) }
                    if d.ch == 91u8 {
                        var j = opener
                        while j > 0usize {
                            j -= 1usize
                            if s.delimiters[j].ch == 91u8 { s.delimiters[j].active = false }
                        }
                    }
                    i = close + 1usize
                    text_start = i
                }
            }
            if !matched { i += 1usize }
            continue
        }
        i += 1usize
    }
    let tail_error = flush_text(&s, text_start, text.len)
    if tail_error != ok { ret (0usize, tail_error) }
    let final_error = process_emphasis(&s, 0usize)
    if final_error != ok { ret (0usize, final_error) }
    // Drop what emptied, then order by start, the wider first at a tie, and a container before
    // a leaf that begins where it does.
    var kept = 0usize
    var k = 0usize
    while k < s.count {
        if s.out[k].len > 0usize || (s.out[k].kind != .Text && s.out[k].kind != .Emph && s.out[k].kind != .Strong) {
            s.out[kept] = s.out[k]
            kept += 1usize
        }
        k += 1usize
    }
    var n = 1usize
    while n < kept {
        let node = s.out[n]
        var m = n
        while m > 0usize && later(s.out[m - 1usize], node) {
            s.out[m] = s.out[m - 1usize]
            m -= 1usize
        }
        s.out[m] = node
        n += 1usize
    }
    ret (kept, ok)
}

fn is_container(kind: InlineKind) -> bool {
    ret kind == .Emph || kind == .Strong || kind == .Link || kind == .Image
}

fn later(a: Inline, b: Inline) -> bool {
    if a.start != b.start { ret a.start > b.start }
    if a.len != b.len { ret a.len < b.len }
    ret !is_container(a.kind) && is_container(b.kind)
}
