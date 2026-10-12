// Document text extraction facade (L153): `detect` names the format of a byte slice from
// its content, with the file name's extension as a tie-breaker, and `extract` returns the
// text a search index wants -- plus title, author and a part count -- through the codec
// that reads that format, so an indexer calls one function per file instead of choosing
// among e.fmt.pdf, e.fmt.ooxml, e.fmt.odf, e.fmt.xlsx.book, e.fmt.html and the rest.
//
//   Pdf          page text, pages separated by a blank line; Title and Author of the Info dictionary
//   Docx, Pptx   paragraphs in document order, slides separated by a blank line; core properties
//   Odt, Odp, Ods   paragraphs (a table cell is a paragraph); meta.xml title and creator
//   Xlsx         per sheet its name then its rows, cells tab separated, as `e.fmt.xlsx` renders them
//   Html         the visible text: script, style, head and template dropped, blocks on their own
//                lines, cells tab separated, whitespace collapsed; the title element
//   Xml          the character data, one text node per line
//   Json         object keys and string values, one per line
//   Markdown     the text with block and inline markup removed (a line-wise reduction, not a
//                CommonMark parse); the first heading as the title
//   Csv, Tsv     rows by lines, fields tab separated
//   Mail         the text/plain body (text/html reduced to text when there is none), quoted-
//                printable and base64 decoded, Latin-1 to UTF-8; Subject and From
//   VCard        one line per card: name, organisation, telephone numbers, e-mail addresses
//   Text         the bytes as UTF-8 without a byte-order mark
//
// Not here: OCR and handwriting, encodings other than UTF-8 and Latin-1, encrypted or
// object-stream PDFs (`NoPages`), legacy binary Office formats, archives, images and audio
// (`Unsupported`), and the wiring into the L034 indexing pipeline.
//
// Memory: every result lives in the arena passed in.
use e.mem
use e.io
use e.str
use e.fmt.html as html
use e.fmt.xml as xml
use e.fmt.json as json
use e.fmt.csv as csv
use e.fmt.pdf as pdf
use e.fmt.ooxml as ooxml
use e.fmt.odf as odf
use e.fmt.zip as zip
use e.fmt.xlsx as xlsx
use e.fmt.xlsx.book as book
use e.fmt.vcard as vcard
use e.fmt.mail as mail
use e.bytes as bytes

error Unsupported
error Corrupt
error TooLarge
error Encoding

type Format = enum u8 { Unknown, Text, Html, Xml, Json, Markdown, Csv, Pdf, Docx, Pptx, Xlsx, Odt, Odp, Ods, Mail, VCard }
type Document = struct { format: Format, text: str, title: str, author: str, parts: usize }

const MAX_INPUT: usize = 67108864usize

fn empty_document(format: Format) -> Document {
    ret Document { format: format, text: "", title: "", author: "", parts: 0usize }
}

// ---- small helpers -----------------------------------------------------------------------

fn fold(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn starts_fold(s: str, at: usize, prefix: str) -> bool {
    if at + prefix.len > s.len { ret false }
    var i = 0usize
    while i < prefix.len {
        if fold(s[at + i]) != fold(prefix[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn ends_fold(s: str, suffix: str) -> bool {
    if s.len < suffix.len { ret false }
    ret starts_fold(s, s.len - suffix.len, suffix)
}

fn is_space(c: u8) -> bool {
    ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 || c == 12u8
}

fn skip_space(s: str, at: usize) -> usize {
    var i = at
    while i < s.len && is_space(s[i]) { i += 1usize }
    ret i
}

fn valid_utf8(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        var need = 0usize
        if c < 128u8 {
            if c == 0u8 { ret false }
            i += 1usize
            continue
        } else if c >= 194u8 && c < 224u8 {
            need = 1usize
        } else if c >= 224u8 && c < 240u8 {
            need = 2usize
        } else if c >= 240u8 && c < 245u8 {
            need = 3usize
        } else {
            ret false
        }
        if i + need >= s.len + 0usize && i + need > s.len - 1usize { ret false }
        var k = 1usize
        while k <= need {
            if (s[i + k] & 192u8) != 128u8 { ret false }
            k += 1usize
        }
        i += need + 1usize
    }
    ret true
}

fn strip_bom(s: str) -> str {
    if s.len >= 3usize && s[0usize] == 239u8 && s[1usize] == 187u8 && s[2usize] == 191u8 { ret s[3usize..s.len] }
    ret s
}

// Latin-1 bytes as UTF-8.
fn latin1_to_utf8(a: *mem.Arena, s: str) -> (str, err) {
    var high = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] >= 128u8 { high += 1usize }
        i += 1usize
    }
    if high == 0usize { ret (s, ok) }
    let (out, out_error) = mem.alloc[u8](a, s.len + high)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    i = 0usize
    while i < s.len {
        let c = s[i]
        if c < 128u8 {
            out[at] = c
            at += 1usize
        } else {
            out[at] = 192u8 | (c >> 6u32)
            out[at + 1usize] = 128u8 | (c & 63u8)
            at += 2usize
        }
        i += 1usize
    }
    ret (out[0usize..at], ok)
}

// The text of `parts` joined by `sep`.
fn join(a: *mem.Arena, parts: []const str, sep: str) -> (str, err) {
    let (joined, joined_error) = str.join(a, parts, sep)
    ret (joined, joined_error)
}

// The part of `name` after its last dot, or "" (case preserved; compare with `ends_fold`).
fn has_extension(name: str, ext: str) -> bool {
    ret ends_fold(name, ext)
}

// ---- detect ------------------------------------------------------------------------------

fn find_entry(archive: *zip.Archive, name: str) -> bool {
    let (index, found) = ooxml.find(archive, name)
    ret found
}

fn has_slide(archive: *zip.Archive) -> bool {
    let listed = zip.entries(archive)
    var i = 0usize
    while i < listed.len {
        if ooxml.slide_number(listed[i].name) > 0usize { ret true }
        i += 1usize
    }
    ret false
}

fn detect_zip(a: *mem.Arena, data: []const u8) -> Format {
    let (archive, open_error) = ooxml.open_package(a, data)
    if open_error != ok { ret .Unknown }
    var ar = archive
    if find_entry(&ar, "word/document.xml") { ret .Docx }
    if find_entry(&ar, "xl/workbook.xml") { ret .Xlsx }
    if find_entry(&ar, "ppt/presentation.xml") || has_slide(&ar) { ret .Pptx }
    let (index, has_mimetype) = ooxml.find(&ar, "mimetype")
    if has_mimetype {
        let (kind, kind_error) = zip.extract(a, &ar, index)
        if kind_error == ok {
            if str.starts_with(kind, "application/vnd.oasis.opendocument.text") { ret .Odt }
            if str.starts_with(kind, "application/vnd.oasis.opendocument.presentation") { ret .Odp }
            if str.starts_with(kind, "application/vnd.oasis.opendocument.spreadsheet") { ret .Ods }
        }
    }
    ret .Unknown
}

fn looks_like_mail(s: str) -> bool {
    ret starts_fold(s, 0usize, "from:") || starts_fold(s, 0usize, "subject:") || starts_fold(s, 0usize, "received:") || starts_fold(s, 0usize, "message-id:") || starts_fold(s, 0usize, "mime-version:") || starts_fold(s, 0usize, "return-path:") || starts_fold(s, 0usize, "date:") || starts_fold(s, 0usize, "to:")
}

// The format of `data`; `name` is the file name (or "") and breaks ties among text formats.
fn detect(a: *mem.Arena, data: []const u8, name: str) -> Format {
    if data.len == 0usize { ret .Unknown }
    var head = 0usize
    while head < data.len && head < 1024usize && head < data.len {
        if data[head] == 37u8 && head + 5usize <= data.len && data[head + 1usize] == 80u8 && data[head + 2usize] == 68u8 && data[head + 3usize] == 70u8 && data[head + 4usize] == 45u8 { ret .Pdf }
        head += 1usize
    }
    if data.len >= 4usize && data[0usize] == 80u8 && data[1usize] == 75u8 && data[2usize] == 3u8 && data[3usize] == 4u8 { ret detect_zip(a, data) }
    if !valid_utf8(strip_bom(data)) { ret .Unknown }
    let text = strip_bom(data)
    let start = skip_space(text, 0usize)
    if starts_fold(text, start, "<!doctype html") || starts_fold(text, start, "<html") { ret .Html }
    if starts_fold(text, start, "<?xml") {
        if has_extension(name, ".html") || has_extension(name, ".xhtml") || has_extension(name, ".htm") { ret .Html }
        ret .Xml
    }
    if starts_fold(text, start, "begin:vcard") { ret .VCard }
    if has_extension(name, ".html") || has_extension(name, ".htm") || has_extension(name, ".xhtml") { ret .Html }
    if has_extension(name, ".xml") || has_extension(name, ".svg") || has_extension(name, ".rss") || has_extension(name, ".atom") { ret .Xml }
    if has_extension(name, ".json") { ret .Json }
    if has_extension(name, ".md") || has_extension(name, ".markdown") { ret .Markdown }
    if has_extension(name, ".csv") || has_extension(name, ".tsv") { ret .Csv }
    if has_extension(name, ".eml") { ret .Mail }
    if has_extension(name, ".vcf") { ret .VCard }
    if has_extension(name, ".txt") || has_extension(name, ".log") { ret .Text }
    if start < text.len && (text[start] == 123u8 || text[start] == 91u8) {
        let options = json.Options { allow_duplicate_keys: true, max_depth: 64u16 }
        let (value, parse_error) = json.parse(a, text, options)
        if parse_error == ok { ret .Json }
    }
    if looks_like_mail(text[start..text.len]) { ret .Mail }
    if start < text.len && text[start] == 60u8 && start + 1usize < text.len && (is_alpha(text[start + 1usize]) || text[start + 1usize] == 47u8) {
        // Markup with no declaration: HTML if it opens like a page, XML otherwise.
        if starts_fold(text, start, "<body") || starts_fold(text, start, "<div") || starts_fold(text, start, "<p>") || starts_fold(text, start, "<p ") || starts_fold(text, start, "<h1") || starts_fold(text, start, "<head") { ret .Html }
        ret .Xml
    }
    ret .Text
}

fn is_alpha(c: u8) -> bool {
    ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8)
}

fn media_type(format: Format) -> str {
    if format == .Text { ret "text/plain" }
    if format == .Html { ret "text/html" }
    if format == .Xml { ret "application/xml" }
    if format == .Json { ret "application/json" }
    if format == .Markdown { ret "text/markdown" }
    if format == .Csv { ret "text/csv" }
    if format == .Pdf { ret "application/pdf" }
    if format == .Docx { ret "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }
    if format == .Pptx { ret "application/vnd.openxmlformats-officedocument.presentationml.presentation" }
    if format == .Xlsx { ret "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }
    if format == .Odt { ret "application/vnd.oasis.opendocument.text" }
    if format == .Odp { ret "application/vnd.oasis.opendocument.presentation" }
    if format == .Ods { ret "application/vnd.oasis.opendocument.spreadsheet" }
    if format == .Mail { ret "message/rfc822" }
    if format == .VCard { ret "text/vcard" }
    ret "application/octet-stream"
}

// ---- package metadata --------------------------------------------------------------------

// The text of the first element whose local name is `name` in an XML part of a package.
fn xml_first_text(a: *mem.Arena, part: []const u8, name: str) -> (str, err) {
    let (doc, parse_error) = xml.parse(a, part)
    if parse_error != ok { ret ("", ok) }
    let nodes = doc.nodes
    var i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Element && str.eq(ooxml.local(nodes[i].name), name) {
            var j = i + 1usize
            while j < nodes.len && usize(nodes[j].parent) == i {
                if nodes[j].kind == .Text { ret (nodes[j].value, ok) }
                j += 1usize
            }
            ret ("", ok)
        }
        i += 1usize
    }
    ret ("", ok)
}

// Title and author from a package part (docProps/core.xml or meta.xml).
fn package_meta(a: *mem.Arena, data: []const u8, part_name: str, title_name: str, author_name: str) -> (str, str, err) {
    let (archive, open_error) = ooxml.open_package(a, data)
    if open_error != ok { ret ("", "", ok) }
    var ar = archive
    let (index, found) = ooxml.find(&ar, part_name)
    if !found { ret ("", "", ok) }
    let (part, part_error) = zip.extract(a, &ar, index)
    if part_error != ok { ret ("", "", ok) }
    let (title, title_error) = xml_first_text(a, part, title_name)
    if title_error != ok { ret ("", "", title_error) }
    let (author, author_error) = xml_first_text(a, part, author_name)
    if author_error != ok { ret ("", "", author_error) }
    ret (title, author, ok)
}

// ---- format readers ----------------------------------------------------------------------

fn paragraph_texts(a: *mem.Arena, ps: []const ooxml.Paragraph) -> ([]str, err) {
    let (parts, parts_error) = mem.alloc[str](a, ps.len + 1usize)
    if parts_error != ok { ret (zero, parts_error) }
    var i = 0usize
    while i < ps.len {
        parts[i] = ps[i].text
        i += 1usize
    }
    ret (parts[0usize..ps.len], ok)
}

fn slides_text(a: *mem.Arena, slides: []const ooxml.Slide) -> (str, err) {
    let (parts, parts_error) = mem.alloc[str](a, slides.len + 1usize)
    if parts_error != ok { ret ("", parts_error) }
    var i = 0usize
    while i < slides.len {
        let (one, one_error) = join(a, slides[i].paragraphs, "\n")
        if one_error != ok { ret ("", one_error) }
        parts[i] = one
        i += 1usize
    }
    let (all, all_error) = join(a, parts[0usize..slides.len], "\n\n")
    ret (all, all_error)
}

fn read_pdf_string(a: *mem.Arena, data: []const u8, key: str) -> (str, err) {
    // `/Key <FEFF...>` (UTF-16BE) or `/Key (literal)`, the first of them in the file.
    let (at, found) = str.find(data, key)
    if !found { ret ("", ok) }
    var i = at + key.len
    while i < data.len && is_space(data[i]) { i += 1usize }
    if i >= data.len { ret ("", ok) }
    if data[i] == 60u8 {
        i += 1usize
        let (out, out_error) = mem.alloc[u8](a, 1024usize)
        if out_error != ok { ret ("", out_error) }
        var used = 0usize
        var units = 0usize
        var pending: [2]u32 = zero
        var high = 0u32
        var count = 0usize
        var nibbles = 0usize
        var value = 0u32
        var started = false
        while i < data.len && data[i] != 62u8 {
            let c = data[i]
            var d = 255u32
            if c >= 48u8 && c <= 57u8 { d = u32(c - 48u8) } else if c >= 65u8 && c <= 70u8 { d = u32(c - 55u8) } else if c >= 97u8 && c <= 102u8 { d = u32(c - 87u8) }
            if d != 255u32 {
                value = (value << 4u32) | d
                nibbles += 1usize
                if nibbles == 4usize {
                    nibbles = 0usize
                    if !started {
                        started = true
                        if value != 65279u32 { ret ("", ok) }
                    } else if value >= 55296u32 && value < 56320u32 {
                        high = value
                    } else {
                        var code = value
                        if value >= 56320u32 && value < 57344u32 && high != 0u32 { code = 65536u32 + ((high - 55296u32) << 10u32) + (value - 56320u32) }
                        high = 0u32
                        if used + 4usize > out.len { break }
                        if code < 128u32 {
                            out[used] = u8(code)
                            used += 1usize
                        } else if code < 2048u32 {
                            out[used] = u8(192u32 | (code >> 6u32))
                            out[used + 1usize] = u8(128u32 | (code & 63u32))
                            used += 2usize
                        } else if code < 65536u32 {
                            out[used] = u8(224u32 | (code >> 12u32))
                            out[used + 1usize] = u8(128u32 | ((code >> 6u32) & 63u32))
                            out[used + 2usize] = u8(128u32 | (code & 63u32))
                            used += 3usize
                        } else {
                            out[used] = u8(240u32 | (code >> 18u32))
                            out[used + 1usize] = u8(128u32 | ((code >> 12u32) & 63u32))
                            out[used + 2usize] = u8(128u32 | ((code >> 6u32) & 63u32))
                            out[used + 3usize] = u8(128u32 | (code & 63u32))
                            used += 4usize
                        }
                    }
                    value = 0u32
                }
            }
            i += 1usize
        }
        ret (out[0usize..used], ok)
    }
    if data[i] == 40u8 {
        i += 1usize
        let (out, out_error) = mem.alloc[u8](a, 1024usize * 2usize)
        if out_error != ok { ret ("", out_error) }
        var used = 0usize
        var depth = 1usize
        while i < data.len && depth > 0usize && used + 2usize < out.len {
            let c = data[i]
            if c == 92u8 && i + 1usize < data.len {
                i += 1usize
                let e = data[i]
                var literal = e
                if e == 110u8 { literal = 10u8 } else if e == 114u8 { literal = 13u8 } else if e == 116u8 { literal = 9u8 }
                if e >= 48u8 && e <= 55u8 {
                    var v = u32(e - 48u8)
                    var digits = 1usize
                    while digits < 3usize && i + 1usize < data.len && data[i + 1usize] >= 48u8 && data[i + 1usize] <= 55u8 {
                        i += 1usize
                        v = v * 8u32 + u32(data[i] - 48u8)
                        digits += 1usize
                    }
                    literal = u8(v & 255u32)
                }
                if literal < 128u8 {
                    out[used] = literal
                    used += 1usize
                } else {
                    out[used] = 192u8 | (literal >> 6u32)
                    out[used + 1usize] = 128u8 | (literal & 63u8)
                    used += 2usize
                }
            } else if c == 40u8 {
                depth += 1usize
                out[used] = c
                used += 1usize
            } else if c == 41u8 {
                depth -= 1usize
                if depth > 0usize {
                    out[used] = c
                    used += 1usize
                }
            } else if c < 128u8 {
                out[used] = c
                used += 1usize
            } else {
                out[used] = 192u8 | (c >> 6u32)
                out[used + 1usize] = 128u8 | (c & 63u8)
                used += 2usize
            }
            i += 1usize
        }
        ret (out[0usize..used], ok)
    }
    ret ("", ok)
}

fn html_skipped(name: str) -> bool {
    ret str.eq(name, "script") || str.eq(name, "style") || str.eq(name, "noscript") || str.eq(name, "template") || str.eq(name, "head") || str.eq(name, "title")
}

fn html_block(name: str) -> bool {
    if name.len == 2usize && name[0usize] == 104u8 && name[1usize] >= 49u8 && name[1usize] <= 54u8 { ret true }
    ret str.eq(name, "p") || str.eq(name, "div") || str.eq(name, "br") || str.eq(name, "li") || str.eq(name, "ul") || str.eq(name, "ol") || str.eq(name, "tr") || str.eq(name, "table") || str.eq(name, "section") || str.eq(name, "article") || str.eq(name, "header") || str.eq(name, "footer") || str.eq(name, "blockquote") || str.eq(name, "pre") || str.eq(name, "hr") || str.eq(name, "main") || str.eq(name, "nav") || str.eq(name, "aside") || str.eq(name, "dd") || str.eq(name, "dt") || str.eq(name, "dl") || str.eq(name, "form") || str.eq(name, "figure") || str.eq(name, "figcaption") || str.eq(name, "caption") || str.eq(name, "details") || str.eq(name, "summary") || str.eq(name, "body") || str.eq(name, "address") || str.eq(name, "fieldset")
}

// Output state of the HTML walk: what separates the next word from the last one.
type Flow = struct { pending: u8, wrote: bool }

fn flow_word(b: *str.Builder, f: *Flow, word: str) -> err {
    if f.wrote {
        if f.pending == 2u8 {
            try str.push(b, "\n")
        } else if f.pending == 3u8 {
            try str.push(b, "\t")
        } else if f.pending == 1u8 {
            try str.push(b, " ")
        }
    }
    try str.push(b, word)
    f.wrote = true
    f.pending = 0u8
    ret ok
}

fn flow_text(b: *str.Builder, f: *Flow, s: str) -> err {
    var i = 0usize
    while i < s.len {
        if is_space(s[i]) {
            if s[i] == 10u8 && false { f.pending = 2u8 }
            if f.pending == 0u8 { f.pending = 1u8 }
            i += 1usize
            continue
        }
        var j = i
        while j < s.len && !is_space(s[j]) { j += 1usize }
        try flow_word(b, f, s[i..j])
        i = j
    }
    ret ok
}

fn html_walk(doc: *const html.Document, id: html.NodeId, b: *str.Builder, f: *Flow) -> err {
    let n = &doc.nodes[usize(id)]
    if n.kind == .Text {
        ret flow_text(b, f, n.value)
    }
    if n.kind == .Element {
        if html_skipped(n.name) { ret ok }
        let block = html_block(n.name)
        let cell = str.eq(n.name, "td") || str.eq(n.name, "th")
        if block && f.pending < 2u8 { f.pending = 2u8 }
        if cell && f.pending < 2u8 { f.pending = 3u8 }
        var child = n.first_child
        while child != html.NONE {
            try html_walk(doc, child, b, f)
            child = doc.nodes[usize(child)].next_sibling
        }
        if block && f.pending < 2u8 { f.pending = 2u8 }
        ret ok
    }
    var child = n.first_child
    while child != html.NONE {
        try html_walk(doc, child, b, f)
        child = doc.nodes[usize(child)].next_sibling
    }
    ret ok
}

fn html_title(a: *mem.Arena, doc: *const html.Document) -> (str, err) {
    var i = 0usize
    while i < doc.nodes.len {
        if doc.nodes[i].kind == .Element && str.eq(doc.nodes[i].name, "title") {
            let (raw, raw_error) = html.text_content(a, doc, u32(i))
            if raw_error != ok { ret ("", raw_error) }
            ret (str.trim(raw), ok)
        }
        i += 1usize
    }
    ret ("", ok)
}

fn html_extract(a: *mem.Arena, source: str) -> (Document, err) {
    var cap = source.len + 16usize
    if cap > 400000usize { cap = 400000usize }
    let options = html.Options { max_bytes: source.len + 1usize, max_nodes: cap, max_attributes: 64usize, max_depth: 256u16, preserve_comments: false }
    let (doc, parse_error) = html.parse(a, source, options)
    if parse_error != ok { ret (empty_document(.Html), TooLarge) }
    let (title, title_error) = html_title(a, &doc)
    if title_error != ok { ret (empty_document(.Html), title_error) }
    var (b, builder_error) = str.builder(a, source.len + 16usize)
    if builder_error != ok { ret (empty_document(.Html), builder_error) }
    var f = Flow { pending: 0u8, wrote: false }
    let walk_error = html_walk(&doc, doc.root, &b, &f)
    if walk_error != ok { ret (empty_document(.Html), TooLarge) }
    var d = empty_document(.Html)
    d.text = str.done(&b)
    d.title = title
    ret (d, ok)
}

fn xml_extract(a: *mem.Arena, source: []const u8) -> (Document, err) {
    let (doc, parse_error) = xml.parse(a, source)
    if parse_error != ok { ret (empty_document(.Xml), Corrupt) }
    let nodes = doc.nodes
    let (parts, parts_error) = mem.alloc[str](a, nodes.len + 1usize)
    if parts_error != ok { ret (empty_document(.Xml), parts_error) }
    var count = 0usize
    var i = 0usize
    while i < nodes.len {
        if nodes[i].kind == .Text {
            let t = str.trim(nodes[i].value)
            if t.len > 0usize {
                parts[count] = t
                count += 1usize
            }
        }
        i += 1usize
    }
    let (text, text_error) = join(a, parts[0usize..count], "\n")
    if text_error != ok { ret (empty_document(.Xml), text_error) }
    var d = empty_document(.Xml)
    d.text = text
    d.parts = count
    ret (d, ok)
}

fn markdown_line(b: *str.Builder, line: str) -> err {
    var i = 0usize
    while i < line.len {
        let c = line[i]
        if c == 33u8 && i + 1usize < line.len && line[i + 1usize] == 91u8 {
            // An image: keep the alt text, drop the target.
            i += 1usize
            continue
        }
        if c == 91u8 {
            // A link: `[text](target)` keeps the text.
            let (close, has_close) = str.find_from(line, "](", i + 1usize)
            if has_close {
                let (paren, has_paren) = str.find_from(line, ")", close + 2usize)
                if has_paren {
                    try str.push(b, line[i + 1usize..close])
                    i = paren + 1usize
                    continue
                }
            }
        }
        if c == 42u8 || c == 96u8 || c == 126u8 {
            i += 1usize
            continue
        }
        if c == 60u8 && i + 1usize < line.len && (is_alpha(line[i + 1usize]) || line[i + 1usize] == 47u8) {
            let (gt, has_gt) = str.find_from(line, ">", i + 1usize)
            if has_gt {
                i = gt + 1usize
                continue
            }
        }
        try str.push_byte(b, c)
        i += 1usize
    }
    ret ok
}

fn markdown_extract(a: *mem.Arena, source: str) -> (Document, err) {
    var title = ""
    var (b, builder_error) = str.builder(a, source.len + 16usize)
    if builder_error != ok { ret (empty_document(.Markdown), builder_error) }
    var at = 0usize
    var first = true
    var in_fence = false
    while at <= source.len {
        var end = at
        while end < source.len && source[end] != 10u8 { end += 1usize }
        var line = source[at..end]
        if line.len > 0usize && line[line.len - 1usize] == 13u8 { line = line[0usize..line.len - 1usize] }
        var start = 0usize
        while start < line.len && (line[start] == 32u8 || line[start] == 9u8) { start += 1usize }
        let body = line[start..line.len]
        var skip = false
        var is_heading = false
        var content = body
        if str.starts_with(body, "```") || str.starts_with(body, "~~~") {
            in_fence = !in_fence
            skip = true
        } else if !in_fence {
            var h = 0usize
            while h < content.len && content[h] == 35u8 { h += 1usize }
            if h > 0usize && h <= 6usize && h < content.len && content[h] == 32u8 {
                is_heading = true
                content = str.trim(content[h..content.len])
                var t = content.len
                while t > 0usize && content[t - 1usize] == 35u8 { t -= 1usize }
                content = str.trim_end(content[0usize..t])
            } else if str.starts_with(content, ">") {
                content = str.trim_start(content[1usize..content.len])
            }
            if (str.starts_with(content, "- ") || str.starts_with(content, "* ") || str.starts_with(content, "+ ")) && content.len > 2usize {
                content = content[2usize..content.len]
            } else {
                var d = 0usize
                while d < content.len && content[d] >= 48u8 && content[d] <= 57u8 { d += 1usize }
                if d > 0usize && d + 1usize < content.len && (content[d] == 46u8 || content[d] == 41u8) && content[d + 1usize] == 32u8 { content = content[d + 2usize..content.len] }
            }
            let rule = content.len >= 3usize && (content[0usize] == 45u8 || content[0usize] == 42u8 || content[0usize] == 95u8) && str.trim_bytes(content, content[0usize..1usize]).len == 0usize
            if rule { skip = true }
        }
        if !skip {
            if !first { try str.push(&b, "\n") }
            first = false
            try markdown_line(&b, content)
            if is_heading && title.len == 0usize {
                // The title is the heading as written, markup and all removed the same way.
                title = content
            }
        }
        if end >= source.len { break }
        at = end + 1usize
    }
    var d = empty_document(.Markdown)
    d.text = str.done(&b)
    d.title = title
    ret (d, ok)
}

fn csv_extract(a: *mem.Arena, source: str) -> (Document, err) {
    var dialect = csv.csv()
    // Tab separated when the first line holds more tabs than commas.
    var tabs = 0usize
    var commas = 0usize
    var i = 0usize
    while i < source.len && source[i] != 10u8 {
        if source[i] == 9u8 { tabs += 1usize }
        if source[i] == 44u8 { commas += 1usize }
        i += 1usize
    }
    if tabs > commas { dialect = csv.tsv() }
    let (cell, cell_error) = mem.alloc[ooxml.Source](a, 1usize)
    if cell_error != ok { ret (empty_document(.Csv), cell_error) }
    cell[0usize] = ooxml.Source { data: source, off: 0usize }
    let reader_io = io.Reader { ctx: mem.cast[*void](&cell[0usize]), read: ooxml.source_read }
    var (r, reader_error) = csv.reader(a, reader_io, dialect, 4096usize, 262144usize)
    if reader_error != ok { ret (empty_document(.Csv), Corrupt) }
    var (b, builder_error) = str.builder(a, source.len + 16usize)
    if builder_error != ok { ret (empty_document(.Csv), builder_error) }
    var rows = 0usize
    while true {
        let (row, more, row_error) = csv.reader_next_err(&r)
        if row_error != ok { ret (empty_document(.Csv), Corrupt) }
        if !more { break }
        if rows > 0usize { try str.push(&b, "\n") }
        var f = 0usize
        while f < row.fields.len {
            if f > 0usize { try str.push(&b, "\t") }
            try str.push(&b, row.fields[f])
            f += 1usize
        }
        rows += 1usize
    }
    var d = empty_document(.Csv)
    d.text = str.done(&b)
    d.parts = rows
    ret (d, ok)
}

fn vcard_extract(a: *mem.Arena, source: []const u8) -> (Document, err) {
    let (cards, cards_error) = mem.alloc[vcard.Card](a, 256usize)
    if cards_error != ok { ret (empty_document(.VCard), cards_error) }
    let (count, parse_error) = vcard.parse(a, source, cards)
    if parse_error != ok { ret (empty_document(.VCard), Corrupt) }
    var (b, builder_error) = str.builder(a, source.len + 64usize)
    if builder_error != ok { ret (empty_document(.VCard), builder_error) }
    var i = 0usize
    while i < count {
        if i > 0usize { try str.push(&b, "\n") }
        let card = cards[i]
        try str.push(&b, card.name)
        if card.org.len > 0usize {
            try str.push(&b, "\t")
            try str.push(&b, card.org)
        }
        var t = 0usize
        while t < card.tel_count {
            try str.push(&b, "\t")
            try str.push(&b, card.tel[t])
            t += 1usize
        }
        var m = 0usize
        while m < card.email_count {
            try str.push(&b, "\t")
            try str.push(&b, card.email[m])
            m += 1usize
        }
        i += 1usize
    }
    var d = empty_document(.VCard)
    d.text = str.done(&b)
    d.parts = count
    if count > 0usize { d.title = cards[0usize].name }
    ret (d, ok)
}

// ---- mail --------------------------------------------------------------------------------

// The header block and body of a message: split at the first blank line.
fn split_message(s: str) -> (str, str) {
    var i = 0usize
    while i < s.len {
        if s[i] == 10u8 {
            if i + 1usize < s.len && s[i + 1usize] == 10u8 { ret (s[0usize..i], s[i + 2usize..s.len]) }
            if i + 2usize < s.len && s[i + 1usize] == 13u8 && s[i + 2usize] == 10u8 { ret (s[0usize..i], s[i + 3usize..s.len]) }
        }
        i += 1usize
    }
    ret (s, "")
}

// The unfolded value of header `name` in a block, and whether it is there.
fn header_value(a: *mem.Arena, block: str, name: str) -> (str, bool, err) {
    var at = 0usize
    while at < block.len {
        var end = at
        while end < block.len && block[end] != 10u8 { end += 1usize }
        var line_end = end
        if line_end > at && block[line_end - 1usize] == 13u8 { line_end -= 1usize }
        let matches = starts_fold(block, at, name) && at + name.len < line_end && block[at + name.len] == 58u8
        if matches {
            var value = str.trim(block[at + name.len + 1usize..line_end])
            // Continuation lines start with a space or a tab.
            var next = end + 1usize
            while next < block.len && (block[next] == 32u8 || block[next] == 9u8) {
                var e2 = next
                while e2 < block.len && block[e2] != 10u8 { e2 += 1usize }
                var l2 = e2
                if l2 > next && block[l2 - 1usize] == 13u8 { l2 -= 1usize }
                let (joined, joined_error) = str.concat(a, value, " ")
                if joined_error != ok { ret ("", false, joined_error) }
                let (joined2, joined2_error) = str.concat(a, joined, str.trim(block[next..l2]))
                if joined2_error != ok { ret ("", false, joined2_error) }
                value = joined2
                next = e2 + 1usize
            }
            ret (value, true, ok)
        }
        at = end + 1usize
    }
    ret ("", false, ok)
}

fn hex_digit(c: u8) -> u32 {
    if c >= 48u8 && c <= 57u8 { ret u32(c - 48u8) }
    if c >= 65u8 && c <= 70u8 { ret u32(c - 55u8) }
    if c >= 97u8 && c <= 102u8 { ret u32(c - 87u8) }
    ret 255u32
}

fn quoted_printable(a: *mem.Arena, s: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, s.len + 1usize)
    if out_error != ok { ret ("", out_error) }
    var used = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 61u8 {
            if i + 2usize < s.len + 0usize && hex_digit(s[i + 1usize]) != 255u32 && hex_digit(s[i + 2usize]) != 255u32 {
                out[used] = u8(hex_digit(s[i + 1usize]) * 16u32 + hex_digit(s[i + 2usize]))
                used += 1usize
                i += 3usize
                continue
            }
            // A soft line break: `=` at the end of a line.
            var j = i + 1usize
            if j < s.len && s[j] == 13u8 { j += 1usize }
            if j < s.len && s[j] == 10u8 {
                i = j + 1usize
                continue
            }
            if i + 1usize >= s.len {
                i += 1usize
                continue
            }
        }
        out[used] = c
        used += 1usize
        i += 1usize
    }
    ret (out[0usize..used], ok)
}

fn strip_spaces(a: *mem.Arena, s: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, s.len + 1usize)
    if out_error != ok { ret ("", out_error) }
    var used = 0usize
    var i = 0usize
    while i < s.len {
        if !is_space(s[i]) {
            out[used] = s[i]
            used += 1usize
        }
        i += 1usize
    }
    ret (out[0usize..used], ok)
}

// A parameter (`charset`, `boundary`) of a Content-Type value, unquoted, or "".
fn parameter_of(value: str, name: str) -> str {
    var i = 0usize
    while i < value.len {
        if value[i] == 59u8 || i == 0usize {
            var j = i
            if value[i] == 59u8 { j = i + 1usize }
            j = skip_space(value, j)
            if starts_fold(value, j, name) && j + name.len < value.len && value[j + name.len] == 61u8 {
                var v = j + name.len + 1usize
                if v < value.len && value[v] == 34u8 {
                    var e = v + 1usize
                    while e < value.len && value[e] != 34u8 { e += 1usize }
                    ret value[v + 1usize..e]
                }
                var e2 = v
                while e2 < value.len && value[e2] != 59u8 && !is_space(value[e2]) { e2 += 1usize }
                ret value[v..e2]
            }
        }
        i += 1usize
    }
    ret ""
}

// The decoded text of one body given its Content-Type and Content-Transfer-Encoding values.
fn decode_body(a: *mem.Arena, body: str, content_type: str, encoding: str) -> (str, err) {
    var decoded = body
    if starts_fold(encoding, 0usize, "quoted-printable") {
        let (qp, qp_error) = quoted_printable(a, body)
        if qp_error != ok { ret ("", qp_error) }
        decoded = qp
    } else if starts_fold(encoding, 0usize, "base64") {
        let (clean, clean_error) = strip_spaces(a, body)
        if clean_error != ok { ret ("", clean_error) }
        let (room, room_error) = mem.alloc[u8](a, clean.len / 4usize * 3usize + 3usize)
        if room_error != ok { ret ("", room_error) }
        let (raw, raw_error) = bytes.base64_decode(room, clean, .Standard)
        if raw_error != ok { ret ("", Corrupt) }
        decoded = raw
    }
    let charset = parameter_of(content_type, "charset")
    if !valid_utf8(decoded) || starts_fold(charset, 0usize, "iso-8859") || starts_fold(charset, 0usize, "windows-125") || starts_fold(charset, 0usize, "latin") {
        let (utf, utf_error) = latin1_to_utf8(a, decoded)
        if utf_error != ok { ret ("", utf_error) }
        decoded = utf
    }
    ret (decoded, ok)
}

// The text of one MIME entity: a text/plain body, a multipart's text parts, or html reduced.
fn entity_text(a: *mem.Arena, entity: str, depth: usize) -> (str, bool, err) {
    let (block, body) = split_message(entity)
    let (content_type, has_type, type_error) = header_value(a, block, "content-type")
    if type_error != ok { ret ("", false, type_error) }
    let (encoding, has_encoding, encoding_error) = header_value(a, block, "content-transfer-encoding")
    if encoding_error != ok { ret ("", false, encoding_error) }
    var kind = "text/plain"
    if has_type { kind = content_type }
    if starts_fold(kind, 0usize, "multipart/") && depth < 4usize {
        let boundary = parameter_of(kind, "boundary")
        if boundary.len == 0usize { ret ("", false, ok) }
        let (marker, marker_error) = str.concat(a, "--", boundary)
        if marker_error != ok { ret ("", false, marker_error) }
        var plain = ""
        var have_plain = false
        var markup = ""
        var have_markup = false
        var at = 0usize
        let (first, has_first) = str.find_from(body, marker, 0usize)
        if !has_first { ret ("", false, ok) }
        at = first + marker.len
        while at < body.len {
            // Skip to the end of the boundary line, then take the part up to the next boundary.
            var line_end = at
            while line_end < body.len && body[line_end] != 10u8 { line_end += 1usize }
            if line_end >= body.len { break }
            let part_start = line_end + 1usize
            let (next, has_next) = str.find_from(body, marker, part_start)
            var part_end = body.len
            if has_next { part_end = next }
            let (piece, piece_html, piece_error) = part_text(a, body[part_start..part_end], depth + 1usize)
            if piece_error != ok { ret ("", false, piece_error) }
            if piece.len > 0usize {
                if piece_html {
                    if !have_markup {
                        markup = piece
                        have_markup = true
                    }
                } else if !have_plain {
                    plain = piece
                    have_plain = true
                } else {
                    let (joined, joined_error) = str.concat(a, plain, "\n")
                    if joined_error != ok { ret ("", false, joined_error) }
                    let (joined2, joined2_error) = str.concat(a, joined, piece)
                    if joined2_error != ok { ret ("", false, joined2_error) }
                    plain = joined2
                }
            }
            if !has_next { break }
            at = next + marker.len
            if at + 1usize < body.len && body[at] == 45u8 && body[at + 1usize] == 45u8 { break }
        }
        if have_plain { ret (plain, false, ok) }
        ret (markup, have_markup, ok)
    }
    let (decoded, decode_error) = decode_body(a, body, kind, encoding)
    if decode_error != ok { ret ("", false, decode_error) }
    if starts_fold(kind, 0usize, "text/html") {
        let (reduced, reduce_error) = html_extract(a, decoded)
        if reduce_error != ok { ret ("", false, reduce_error) }
        ret (reduced.text, true, ok)
    }
    if starts_fold(kind, 0usize, "text/") || !has_type {
        ret (decoded, false, ok)
    }
    ret ("", false, ok)
}

fn part_text(a: *mem.Arena, part: str, depth: usize) -> (str, bool, err) {
    let (text, is_html, text_error) = entity_text(a, part, depth)
    ret (text, is_html, text_error)
}

fn mail_extract(a: *mem.Arena, source: str) -> (Document, err) {
    let (block, body) = split_message(source)
    let (subject, has_subject, subject_error) = header_value(a, block, "subject")
    if subject_error != ok { ret (empty_document(.Mail), subject_error) }
    let (from, has_from, from_error) = header_value(a, block, "from")
    if from_error != ok { ret (empty_document(.Mail), from_error) }
    var d = empty_document(.Mail)
    if has_subject {
        let (decoded, decode_error) = mail.decode_header(a, subject, 2048usize)
        if decode_error == ok { d.title = decoded } else { d.title = subject }
    }
    if has_from {
        let (decoded, decode_error) = mail.decode_header(a, from, 2048usize)
        if decode_error == ok { d.author = decoded } else { d.author = from }
    }
    let (text, is_html, text_error) = entity_text(a, source, 0usize)
    if text_error != ok { ret (empty_document(.Mail), text_error) }
    let (unix, unix_error) = str.replace(a, text, "\r\n", "\n")
    if unix_error != ok { ret (empty_document(.Mail), unix_error) }
    d.text = str.trim_end(unix)
    d.parts = 1usize
    ret (d, ok)
}

// ---- the facade --------------------------------------------------------------------------

fn text_extract(source: str) -> (Document, err) {
    let t = strip_bom(source)
    if !valid_utf8(t) { ret (empty_document(.Text), Encoding) }
    var d = empty_document(.Text)
    d.text = t
    ret (d, ok)
}

// The document of `data` read as `format`.
fn extract_as(a: *mem.Arena, data: []const u8, format: Format) -> (Document, err) {
    if data.len > MAX_INPUT { ret (empty_document(format), TooLarge) }
    if format == .Pdf {
        let (pages, pages_error) = pdf.pages(a, data)
        if pages_error != ok { ret (empty_document(format), Corrupt) }
        let (text, text_error) = join(a, pages, "\n\n")
        if text_error != ok { ret (empty_document(format), text_error) }
        let (title, title_error) = read_pdf_string(a, data, "/Title")
        if title_error != ok { ret (empty_document(format), title_error) }
        let (author, author_error) = read_pdf_string(a, data, "/Author")
        if author_error != ok { ret (empty_document(format), author_error) }
        ret (Document { format: format, text: text, title: title, author: author, parts: pages.len }, ok)
    }
    if format == .Docx {
        let (ps, ps_error) = ooxml.paragraphs(a, data)
        if ps_error != ok { ret (empty_document(format), Corrupt) }
        let (texts, texts_error) = paragraph_texts(a, ps)
        if texts_error != ok { ret (empty_document(format), texts_error) }
        let (text, text_error) = join(a, texts, "\n")
        if text_error != ok { ret (empty_document(format), text_error) }
        let (title, author, meta_error) = package_meta(a, data, "docProps/core.xml", "title", "creator")
        if meta_error != ok { ret (empty_document(format), meta_error) }
        ret (Document { format: format, text: text, title: title, author: author, parts: ps.len }, ok)
    }
    if format == .Pptx {
        let (slides, slides_error) = ooxml.slides(a, data)
        if slides_error != ok { ret (empty_document(format), Corrupt) }
        let (text, text_error) = slides_text(a, slides)
        if text_error != ok { ret (empty_document(format), text_error) }
        let (title, author, meta_error) = package_meta(a, data, "docProps/core.xml", "title", "creator")
        if meta_error != ok { ret (empty_document(format), meta_error) }
        ret (Document { format: format, text: text, title: title, author: author, parts: slides.len }, ok)
    }
    if format == .Odt || format == .Ods {
        let (ps, ps_error) = odf.paragraphs(a, data)
        if ps_error != ok { ret (empty_document(format), Corrupt) }
        let (texts, texts_error) = paragraph_texts(a, ps)
        if texts_error != ok { ret (empty_document(format), texts_error) }
        let (text, text_error) = join(a, texts, "\n")
        if text_error != ok { ret (empty_document(format), text_error) }
        let (title, author, meta_error) = package_meta(a, data, "meta.xml", "title", "creator")
        if meta_error != ok { ret (empty_document(format), meta_error) }
        ret (Document { format: format, text: text, title: title, author: author, parts: ps.len }, ok)
    }
    if format == .Odp {
        let (slides, slides_error) = odf.slides(a, data)
        if slides_error != ok { ret (empty_document(format), Corrupt) }
        let (text, text_error) = slides_text(a, slides)
        if text_error != ok { ret (empty_document(format), text_error) }
        let (title, author, meta_error) = package_meta(a, data, "meta.xml", "title", "creator")
        if meta_error != ok { ret (empty_document(format), meta_error) }
        ret (Document { format: format, text: text, title: title, author: author, parts: slides.len }, ok)
    }
    if format == .Xlsx {
        let (sheets, sheets_error) = book.decode(a, data)
        if sheets_error != ok { ret (empty_document(format), Corrupt) }
        var (b, builder_error) = str.builder(a, data.len * 2usize + 64usize)
        if builder_error != ok { ret (empty_document(format), builder_error) }
        var s = 0usize
        while s < sheets.len {
            if s > 0usize { try str.push(&b, "\n") }
            try str.push(&b, sheets[s].name)
            var r = 0usize
            while r < sheets[s].grid.len {
                try str.push(&b, "\n")
                var c = 0usize
                while c < sheets[s].grid[r].len {
                    if c > 0usize { try str.push(&b, "\t") }
                    let cell = sheets[s].grid[r][c]
                    if cell.kind == .Text {
                        try str.push(&b, cell.text)
                    } else if cell.kind == .Number {
                        if cell.number == f64(i64(cell.number)) {
                            try str.push_i64(&b, i64(cell.number))
                        } else {
                            try str.push_f64(&b, cell.number)
                        }
                    } else if cell.kind == .Bool {
                        if cell.flag { try str.push(&b, "true") } else { try str.push(&b, "false") }
                    } else if cell.kind == .Date {
                        try str.push_i64(&b, cell.year)
                        try str.push(&b, "-")
                        if cell.month < 10u32 { try str.push(&b, "0") }
                        try str.push_u32(&b, cell.month)
                        try str.push(&b, "-")
                        if cell.day < 10u32 { try str.push(&b, "0") }
                        try str.push_u32(&b, cell.day)
                    }
                    c += 1usize
                }
                r += 1usize
            }
            s += 1usize
        }
        var d = empty_document(format)
        d.text = str.done(&b)
        d.parts = sheets.len
        ret (d, ok)
    }
    if format == .Unknown { ret (empty_document(format), Unsupported) }
    // The text formats: UTF-8, optionally with a byte-order mark.
    var source = strip_bom(data)
    if format == .Mail {
        if !valid_utf8(source) {
            let (utf, utf_error) = latin1_to_utf8(a, source)
            if utf_error != ok { ret (empty_document(format), utf_error) }
            source = utf
        }
        let (tuple_value, tuple_error) = mail_extract(a, source)
        ret (tuple_value, tuple_error)
    }
    if !valid_utf8(source) { ret (empty_document(format), Encoding) }
    if format == .Html {
        let (html_doc, html_error) = html_extract(a, source)
        ret (html_doc, html_error)
    }
    if format == .Xml {
        let (xml_doc, xml_error) = xml_extract(a, source)
        ret (xml_doc, xml_error)
    }
    if format == .Markdown {
        let (md_doc, md_error) = markdown_extract(a, source)
        ret (md_doc, md_error)
    }
    if format == .Csv {
        let (csv_doc, csv_error) = csv_extract(a, source)
        ret (csv_doc, csv_error)
    }
    if format == .VCard {
        let (card_doc, card_error) = vcard_extract(a, source)
        ret (card_doc, card_error)
    }
    if format == .Json {
        let options = json.Options { allow_duplicate_keys: true, max_depth: 64u16 }
        let (value, parse_error) = json.parse(a, source, options)
        if parse_error != ok { ret (empty_document(format), Corrupt) }
        let (tuple_value, tuple_error) = json_extract_value(a, &value, source.len)
        ret (tuple_value, tuple_error)
    }
    let (tuple_value, tuple_error) = text_extract(source)
    ret (tuple_value, tuple_error)
}

// Keys and string values of a parsed JSON value, one per line.
fn json_extract_value(a: *mem.Arena, v: *const json.Value, size: usize) -> (Document, err) {
    var (b, builder_error) = str.builder(a, size + 64usize)
    if builder_error != ok { ret (empty_document(.Json), builder_error) }
    var lines = 0usize
    try json_emit(&b, v, &lines)
    var d = empty_document(.Json)
    d.text = str.done(&b)
    d.parts = lines
    ret (d, ok)
}

fn json_line(b: *str.Builder, lines: *usize, s: str) -> err {
    if *lines > 0usize { try str.push(b, "\n") }
    try str.push(b, s)
    *lines = *lines + 1usize
    ret ok
}

fn json_emit(b: *str.Builder, v: *const json.Value, lines: *usize) -> err {
    switch *v {
    case .String as text:
        ret json_line(b, lines, text)
    case .Array as items:
        var at = 0usize
        while at < items.len {
            try json_emit(b, &items[at], lines)
            at += 1usize
        }
        ret ok
    case .Object as members:
        var at = 0usize
        while at < members.len {
            try json_line(b, lines, members[at].key)
            try json_emit(b, &members[at].value, lines)
            at += 1usize
        }
        ret ok
    default:
        ret ok
    }
}

// Detect, then extract: the one call an indexer needs.
fn extract(a: *mem.Arena, data: []const u8, name: str) -> (Document, err) {
    let format = detect(a, data, name)
    if format == .Unknown { ret (empty_document(.Unknown), Unsupported) }
    let (d, extract_error) = extract_as(a, data, format)
    ret (d, extract_error)
}
