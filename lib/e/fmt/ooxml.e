// Text out of Office Open XML packages (C123, C142): the paragraphs of a Word document (`.docx`) and the slides of
// a PowerPoint deck (`.pptx`), read over e.fmt.zip and e.fmt.xml from a byte slice. It is a reader for what a
// viewer shows -- the text of each paragraph in order, a paragraph's style name (`Heading1`, `ListParagraph`) and
// whether it is a list item, tabs and line breaks as the characters they are -- not a layout engine: runs,
// tables, images and shapes are not drawn, and the text of a table cell or a slide shape is a paragraph like
// any other, in document order. Namespace prefixes are ignored (`w:p` and `p` are the same element).
//
// Memory: every result lives in the arena passed in.
use e.mem
use e.io
use e.os
use e.str
use e.fmt.zip as zip
use e.fmt.xml as xml

error NotAPackage
error NoMainPart

type Source = struct { data: []const u8, off: usize }

type Paragraph = struct { text: str, style: str, list: bool }

type Slide = struct { paragraphs: []const str }

const LIMIT_ENTRIES: usize = 512usize
const LIMIT_NAME: usize = 256usize
const LIMIT_ENTRY: u64 = 8388608u64
const LIMIT_TOTAL: u64 = 33554432u64

fn source_read(ctx: *void, dst: []u8) -> (usize, err) {
    var s = mem.cast[*Source](ctx)
    if s.off >= s.data.len { ret (0usize, io.End) }
    var take = dst.len
    if s.data.len - s.off < take { take = s.data.len - s.off }
    mem.copy[u8](dst[..take], s.data[s.off..s.off + take])
    s.off += take
    ret (take, ok)
}

fn source_seek(ctx: *void, off: i64, whence: os.SeekWhence) -> (u64, err) {
    var s = mem.cast[*Source](ctx)
    var base = 0i64
    if whence == .Current { base = i64(s.off) }
    if whence == .End { base = i64(s.data.len) }
    let target_at = base + off
    if target_at < 0i64 || target_at > i64(s.data.len) { ret (0u64, io.End) }
    s.off = usize(target_at)
    ret (u64(target_at), ok)
}

// The part of `name` after its namespace prefix: `w:p` is `p`.
fn local(name: str) -> str {
    var i = name.len
    while i > 0usize {
        if name[i - 1usize] == 58u8 { ret name[i..name.len] }
        i -= 1usize
    }
    ret name
}

fn open_package(a: *mem.Arena, data: []const u8) -> (zip.Archive, err) {
    let (cell, cell_error) = mem.alloc[Source](a, 1usize)
    if cell_error != ok { ret (zero, cell_error) }
    cell[0usize] = Source { data: data, off: 0usize }
    let reader = io.Reader { ctx: mem.cast[*void](&cell[0usize]), read: source_read }
    let seeker = io.Seeker { ctx: mem.cast[*void](&cell[0usize]), seek: source_seek }
    var limits: zip.Limits = zero
    limits.entries = LIMIT_ENTRIES
    limits.name_bytes = LIMIT_NAME
    limits.entry_bytes = LIMIT_ENTRY
    limits.total_bytes = LIMIT_TOTAL
    let (archive, open_error) = zip.open(a, reader, seeker, limits)
    if open_error != ok { ret (archive, NotAPackage) }
    ret (archive, ok)
}

// The index of the entry called `name`, and whether there is one.
fn find(archive: *zip.Archive, name: str) -> (usize, bool) {
    let listed = zip.entries(archive)
    var i = 0usize
    while i < listed.len {
        if str.eq(listed[i].name, name) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// The text of the elements called `leaf` (`t`) under the paragraph elements called `para` (`p`) of an XML part,
// one string per paragraph, in order. `style_attr` pulls a paragraph's style name when the part has one.
type Collected = struct { texts: []str, styles: []str, lists: []bool }

fn collect(a: *mem.Arena, part: []const u8) -> (Collected, err) {
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret (zero, parse_error) }
    let nodes = doc.nodes
    // Paragraph element indexes, in document order.
    var count = 0usize
    var i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), "p") { count += 1usize }
        i += 1usize
    }
    let (starts, starts_error) = mem.alloc[usize](a, count + 1usize)
    if starts_error != ok { ret (zero, starts_error) }
    var k = 0usize
    i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(local(nodes[i].name), "p") {
            starts[k] = i
            k += 1usize
        }
        i += 1usize
    }
    starts[count] = nodes.len
    let (texts, texts_error) = mem.alloc[str](a, count)
    if texts_error != ok { ret (zero, texts_error) }
    let (styles, styles_error) = mem.alloc[str](a, count)
    if styles_error != ok { ret (zero, styles_error) }
    let (lists, lists_error) = mem.alloc[bool](a, count)
    if lists_error != ok { ret (zero, lists_error) }
    var p = 0usize
    while p < count {
        // The bytes of this paragraph's text: `t` text nodes, a tab for `tab`, a newline for `br`.
        var size = 0usize
        var n = starts[p]
        while n < starts[p + 1usize] {
            if nodes[n].kind == .Text && usize(nodes[n].parent) < nodes.len && str.eq(local(nodes[usize(nodes[n].parent)].name), "t") { size += nodes[n].value.len }
            if nodes[n].kind == .Element && (str.eq(local(nodes[n].name), "tab") || str.eq(local(nodes[n].name), "br")) { size += 1usize }
            n += 1usize
        }
        let (buffer, buffer_error) = mem.alloc[u8](a, size + 1usize)
        if buffer_error != ok { ret (zero, buffer_error) }
        var at = 0usize
        var style = ""
        var is_list = false
        n = starts[p]
        while n < starts[p + 1usize] {
            if nodes[n].kind == .Text && usize(nodes[n].parent) < nodes.len && str.eq(local(nodes[usize(nodes[n].parent)].name), "t") {
                var j = 0usize
                while j < nodes[n].value.len {
                    buffer[at] = nodes[n].value[j]
                    at += 1usize
                    j += 1usize
                }
            }
            if nodes[n].kind == .Element {
                let name = local(nodes[n].name)
                if str.eq(name, "tab") {
                    buffer[at] = 9u8
                    at += 1usize
                }
                if str.eq(name, "br") {
                    buffer[at] = 10u8
                    at += 1usize
                }
                if str.eq(name, "pStyle") {
                    let (value, has_value) = xml.attribute(&nodes[n], "w:val")
                    if has_value { style = value }
                }
                if str.eq(name, "numPr") { is_list = true }
            }
            n += 1usize
        }
        texts[p] = buffer[0usize..at]
        styles[p] = style
        lists[p] = is_list
        p += 1usize
    }
    ret (Collected { texts: texts, styles: styles, lists: lists }, ok)
}

// The paragraphs of a `.docx` held in `data`: its main part `word/document.xml`.
fn paragraphs(a: *mem.Arena, data: []const u8) -> ([]Paragraph, err) {
    let (archive, open_error) = open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    let (index, found) = find(&ar, "word/document.xml")
    if !found { ret (zero, NoMainPart) }
    let (part, extract_error) = zip.extract(a, &ar, index)
    if extract_error != ok { ret (zero, extract_error) }
    let (c, collect_error) = collect(a, part)
    if collect_error != ok { ret (zero, collect_error) }
    let (out, out_error) = mem.alloc[Paragraph](a, c.texts.len)
    if out_error != ok { ret (zero, out_error) }
    var i = 0usize
    while i < c.texts.len {
        out[i] = Paragraph { text: c.texts[i], style: c.styles[i], list: c.lists[i] }
        i += 1usize
    }
    ret (out, ok)
}

// The number in `ppt/slides/slide<N>.xml`, or 0 when `name` is not a slide part.
fn slide_number(name: str) -> usize {
    let prefix = "ppt/slides/slide"
    let suffix = ".xml"
    if name.len <= prefix.len + suffix.len { ret 0usize }
    var i = 0usize
    while i < prefix.len {
        if name[i] != prefix[i] { ret 0usize }
        i += 1usize
    }
    var n = 0usize
    var at = prefix.len
    while at < name.len - suffix.len {
        if name[at] < 48u8 || name[at] > 57u8 { ret 0usize }
        n = n * 10usize + usize(name[at] - 48u8)
        at += 1usize
    }
    i = 0usize
    while i < suffix.len {
        if name[name.len - suffix.len + i] != suffix[i] { ret 0usize }
        i += 1usize
    }
    ret n
}

// The slides of a `.pptx` held in `data`, in slide-number order; each slide's text paragraphs.
fn slides(a: *mem.Arena, data: []const u8) -> ([]Slide, err) {
    let (archive, open_error) = open_package(a, data)
    if open_error != ok { ret (zero, open_error) }
    var ar = archive
    let listed = zip.entries(&ar)
    var total = 0usize
    var i = 0usize
    while i < listed.len {
        if slide_number(listed[i].name) > 0usize { total += 1usize }
        i += 1usize
    }
    if total == 0usize { ret (zero, NoMainPart) }
    let (out, out_error) = mem.alloc[Slide](a, total)
    if out_error != ok { ret (zero, out_error) }
    // Slide k, for k = 1 upward, is the part whose number is k; a missing number is skipped.
    var written = 0usize
    var want = 1usize
    while written < total && want < 10000usize {
        var j = 0usize
        while j < listed.len {
            if slide_number(listed[j].name) == want {
                let (part, extract_error) = zip.extract(a, &ar, j)
                if extract_error != ok { ret (zero, extract_error) }
                let (c, collect_error) = collect(a, part)
                if collect_error != ok { ret (zero, collect_error) }
                out[written] = Slide { paragraphs: c.texts }
                written += 1usize
            }
            j += 1usize
        }
        want += 1usize
    }
    ret (out[0usize..written], ok)
}
