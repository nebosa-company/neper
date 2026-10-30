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
//                printable and base64 decoded, Latin-1/Windows-1251/Windows-1252 to UTF-8; Subject and From
//   VCard        one line per card: name, organisation, telephone numbers, e-mail addresses
//   Text         the bytes as UTF-8 without a byte-order mark
//
// Not here: OCR and handwriting, encodings other than UTF-8, Latin-1, Windows-1251 and Windows-1252, encrypted or
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
use e.text.utf8

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
    if !utf8.validate(s) { ret false }
    var i = 0usize
    while i < s.len {
        if s[i] == 0u8 { ret false }
        i += 1usize
    }
    ret true
}

fn has_nul(s: str) -> bool {
    var at = 0usize
    while at < s.len {
        if s[at] == 0u8 { ret true }
        at += 1usize
    }
    ret false
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

fn windows1252_scalar(c: u8) -> u32 {
    if c == 128u8 { ret 8364u32 }
    if c == 130u8 { ret 8218u32 }
    if c == 131u8 { ret 402u32 }
    if c == 132u8 { ret 8222u32 }
    if c == 133u8 { ret 8230u32 }
    if c == 134u8 { ret 8224u32 }
    if c == 135u8 { ret 8225u32 }
    if c == 136u8 { ret 710u32 }
    if c == 137u8 { ret 8240u32 }
    if c == 138u8 { ret 352u32 }
    if c == 139u8 { ret 8249u32 }
    if c == 140u8 { ret 338u32 }
    if c == 142u8 { ret 381u32 }
    if c == 145u8 { ret 8216u32 }
    if c == 146u8 { ret 8217u32 }
    if c == 147u8 { ret 8220u32 }
    if c == 148u8 { ret 8221u32 }
    if c == 149u8 { ret 8226u32 }
    if c == 150u8 { ret 8211u32 }
    if c == 151u8 { ret 8212u32 }
    if c == 152u8 { ret 732u32 }
    if c == 153u8 { ret 8482u32 }
    if c == 154u8 { ret 353u32 }
    if c == 155u8 { ret 8250u32 }
    if c == 156u8 { ret 339u32 }
    if c == 158u8 { ret 382u32 }
    if c == 159u8 { ret 376u32 }
    ret u32(c)
}

fn windows1252_to_utf8(a: *mem.Arena, s: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, s.len * 3usize + 1usize)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    var used = 0usize
    while at < s.len {
        let (width, encode_error) = utf8.encode(windows1252_scalar(s[at]), out[used..out.len])
        if encode_error != ok { ret ("", encode_error) }
        used += usize(width)
        at += 1usize
    }
    ret (out[0usize..used], ok)
}

fn windows1251_scalar(c: u8) -> u32 {
    if c >= 192u8 { ret 1040u32 + u32(c - 192u8) }
    if c == 128u8 { ret 1026u32 }
    if c == 129u8 { ret 1027u32 }
    if c == 130u8 { ret 8218u32 }
    if c == 131u8 { ret 1107u32 }
    if c == 132u8 { ret 8222u32 }
    if c == 133u8 { ret 8230u32 }
    if c == 134u8 { ret 8224u32 }
    if c == 135u8 { ret 8225u32 }
    if c == 136u8 { ret 8364u32 }
    if c == 137u8 { ret 8240u32 }
    if c == 138u8 { ret 1033u32 }
    if c == 139u8 { ret 8249u32 }
    if c == 140u8 { ret 1034u32 }
    if c == 141u8 { ret 1036u32 }
    if c == 142u8 { ret 1035u32 }
    if c == 143u8 { ret 1039u32 }
    if c == 144u8 { ret 1106u32 }
    if c == 145u8 { ret 8216u32 }
    if c == 146u8 { ret 8217u32 }
    if c == 147u8 { ret 8220u32 }
    if c == 148u8 { ret 8221u32 }
    if c == 149u8 { ret 8226u32 }
    if c == 150u8 { ret 8211u32 }
    if c == 151u8 { ret 8212u32 }
    if c == 153u8 { ret 8482u32 }
    if c == 154u8 { ret 1113u32 }
    if c == 155u8 { ret 8250u32 }
    if c == 156u8 { ret 1114u32 }
    if c == 157u8 { ret 1116u32 }
    if c == 158u8 { ret 1115u32 }
    if c == 159u8 { ret 1119u32 }
    if c == 160u8 { ret 160u32 }
    if c == 161u8 { ret 1038u32 }
    if c == 162u8 { ret 1118u32 }
    if c == 163u8 { ret 1032u32 }
    if c == 164u8 { ret 164u32 }
    if c == 165u8 { ret 1168u32 }
    if c == 166u8 { ret 166u32 }
    if c == 167u8 { ret 167u32 }
    if c == 168u8 { ret 1025u32 }
    if c == 169u8 { ret 169u32 }
    if c == 170u8 { ret 1028u32 }
    if c == 171u8 { ret 171u32 }
    if c == 172u8 { ret 172u32 }
    if c == 173u8 { ret 173u32 }
    if c == 174u8 { ret 174u32 }
    if c == 175u8 { ret 1031u32 }
    if c == 176u8 { ret 176u32 }
    if c == 177u8 { ret 177u32 }
    if c == 178u8 { ret 1030u32 }
    if c == 179u8 { ret 1110u32 }
    if c == 180u8 { ret 1169u32 }
    if c == 181u8 { ret 181u32 }
    if c == 182u8 { ret 182u32 }
    if c == 183u8 { ret 183u32 }
    if c == 184u8 { ret 1105u32 }
    if c == 185u8 { ret 8470u32 }
    if c == 186u8 { ret 1108u32 }
    if c == 187u8 { ret 187u32 }
    if c == 188u8 { ret 1112u32 }
    if c == 189u8 { ret 1029u32 }
    if c == 190u8 { ret 1109u32 }
    if c == 191u8 { ret 1111u32 }
    ret u32(c)
}

fn windows1251_to_utf8(a: *mem.Arena, s: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, s.len * 3usize + 1usize)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    var used = 0usize
    while at < s.len {
        let (width, encode_error) = utf8.encode(windows1251_scalar(s[at]), out[used..out.len])
        if encode_error != ok { ret ("", encode_error) }
        used += usize(width)
        at += 1usize
    }
    ret (out[0usize..used], ok)
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
        let listed = zip.entries(&ar)
        // `mimetype` is a short ODF discriminator. Avoid allocating an attacker-sized
        // member merely to inspect its fixed prefix.
        if index < listed.len && listed[index].size <= 128u64 {
            let (kind, kind_error) = zip.extract(a, &ar, index)
            if kind_error == ok {
                if str.starts_with(kind, "application/vnd.oasis.opendocument.text") { ret .Odt }
                if str.starts_with(kind, "application/vnd.oasis.opendocument.presentation") { ret .Odp }
                if str.starts_with(kind, "application/vnd.oasis.opendocument.spreadsheet") { ret .Ods }
            }
        }
    }
    ret .Unknown
}

fn looks_like_mail(s: str) -> bool {
    ret starts_fold(s, 0usize, "from:") || starts_fold(s, 0usize, "subject:") || starts_fold(s, 0usize, "received:") || starts_fold(s, 0usize, "message-id:") || starts_fold(s, 0usize, "mime-version:") || starts_fold(s, 0usize, "return-path:") || starts_fold(s, 0usize, "date:") || starts_fold(s, 0usize, "to:")
}

fn extension_format(name: str) -> Format {
    if has_extension(name, ".html") || has_extension(name, ".htm") || has_extension(name, ".xhtml") { ret .Html }
    if has_extension(name, ".xml") || has_extension(name, ".svg") || has_extension(name, ".rss") || has_extension(name, ".atom") { ret .Xml }
    if has_extension(name, ".json") { ret .Json }
    if has_extension(name, ".md") || has_extension(name, ".markdown") { ret .Markdown }
    if has_extension(name, ".csv") || has_extension(name, ".tsv") { ret .Csv }
    if has_extension(name, ".eml") { ret .Mail }
    if has_extension(name, ".vcf") { ret .VCard }
    if has_extension(name, ".txt") || has_extension(name, ".log") { ret .Text }
    ret .Unknown
}

// The format of `data`; `name` is the file name (or "") and breaks ties among text formats.
fn detect(a: *mem.Arena, data: []const u8, name: str) -> Format {
    if data.len == 0usize { ret .Unknown }
    if data.len >= 5usize && data[0usize] == 37u8 && data[1usize] == 80u8 && data[2usize] == 68u8 && data[3usize] == 70u8 && data[4usize] == 45u8 { ret .Pdf }
    if data.len >= 4usize && data[0usize] == 80u8 && data[1usize] == 75u8 && data[2usize] == 3u8 && data[3usize] == 4u8 { ret detect_zip(a, data) }
    let text = strip_bom(data)
    let named = extension_format(name)
    if !valid_utf8(text) {
        if has_nul(text) { ret .Unknown }
        if named != .Unknown { ret named }
        if looks_like_mail(text) { ret .Mail }
        ret .Unknown
    }
    let start = skip_space(text, 0usize)
    if starts_fold(text, start, "<!doctype html") || starts_fold(text, start, "<html") { ret .Html }
    if starts_fold(text, start, "<?xml") {
        if has_extension(name, ".html") || has_extension(name, ".xhtml") || has_extension(name, ".htm") { ret .Html }
        ret .Xml
    }
    if starts_fold(text, start, "begin:vcard") { ret .VCard }
    if named != .Unknown { ret named }
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

fn pdf_digit(c: u8) -> bool {
    ret c >= 48u8 && c <= 57u8
}

fn pdf_delimiter(c: u8) -> bool {
    ret is_space(c) || c == 40u8 || c == 41u8 || c == 60u8 || c == 62u8 || c == 91u8 || c == 93u8 || c == 123u8 || c == 125u8 || c == 47u8 || c == 37u8
}

// A bounded unsigned PDF number. Object and generation ids beyond this reader's
// object limits are not useful metadata and must not overflow while being skipped.
fn pdf_number(data: []const u8, from: usize, until: usize) -> (usize, usize, bool) {
    var at = from
    while at < until && is_space(data[at]) { at += 1usize }
    if at >= until || !pdf_digit(data[at]) { ret (0usize, from, false) }
    var value = 0usize
    while at < until && pdf_digit(data[at]) {
        let digit = usize(data[at] - 48u8)
        if value > (999999999usize - digit) / 10usize { ret (0usize, from, false) }
        value = value * 10usize + digit
        at += 1usize
    }
    ret (value, at, true)
}

fn pdf_word_at(data: []const u8, at: usize, until: usize, word: str) -> bool {
    if at + word.len > until { ret false }
    var i = 0usize
    while i < word.len {
        if data[at + i] != word[i] { ret false }
        i += 1usize
    }
    if at > 0usize && !pdf_delimiter(data[at - 1usize]) { ret false }
    if at + word.len < until && !pdf_delimiter(data[at + word.len]) { ret false }
    ret true
}

fn pdf_object_span(data: []const u8, wanted_number: usize, wanted_generation: usize) -> (usize, usize, bool) {
    var at = 0usize
    while at < data.len {
        if pdf_digit(data[at]) && (at == 0usize || !pdf_digit(data[at - 1usize])) {
            let (number, after_number, have_number) = pdf_number(data, at, data.len)
            if have_number && number == wanted_number {
                let (generation, after_generation, have_generation) = pdf_number(data, after_number, data.len)
                if have_generation && generation == wanted_generation {
                    var object_at = after_generation
                    while object_at < data.len && is_space(data[object_at]) { object_at += 1usize }
                    if pdf_word_at(data, object_at, data.len, "obj") {
                        let content_start = object_at + 3usize
                        let (content_end, found_end) = str.find_from(data, "endobj", content_start)
                        if found_end { ret (content_start, content_end, true) }
                    }
                }
            }
        }
        at += 1usize
    }
    ret (0usize, 0usize, false)
}

// The Info object referenced by the final trailer. It is intentionally a narrow
// reader: page contents are parsed by e.fmt.pdf, while metadata only needs this
// indirect dictionary span.
fn pdf_info_span(data: []const u8) -> (usize, usize, bool) {
    var trailer = data.len
    var at = 0usize
    while at < data.len {
        let (found, have_found) = str.find_from(data, "trailer", at)
        if !have_found { break }
        if pdf_word_at(data, found, data.len, "trailer") { trailer = found + 7usize }
        at = found + 1usize
    }
    if trailer == data.len { ret (0usize, 0usize, false) }
    at = trailer
    while at + 5usize <= data.len {
        if pdf_word_at(data, at, data.len, "/Info") {
            let (object_number, after_object, have_object) = pdf_number(data, at + 5usize, data.len)
            if have_object {
                let (generation, after_generation, have_generation) = pdf_number(data, after_object, data.len)
                if have_generation {
                    var r_at = after_generation
                    while r_at < data.len && is_space(data[r_at]) { r_at += 1usize }
                    if pdf_word_at(data, r_at, data.len, "R") {
                        let (object_start, object_end, object_found) = pdf_object_span(data, object_number, generation)
                        ret (object_start, object_end, object_found)
                    }
                }
            }
        }
        at += 1usize
    }
    ret (0usize, 0usize, false)
}

fn pdf_hex_digit(c: u8) -> u32 {
    if c >= 48u8 && c <= 57u8 { ret u32(c - 48u8) }
    if c >= 65u8 && c <= 70u8 { ret u32(c - 55u8) }
    if c >= 97u8 && c <= 102u8 { ret u32(c - 87u8) }
    ret 255u32
}

fn pdf_hex_bytes(a: *mem.Arena, data: []const u8, from: usize, until: usize) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, (until - from) / 2usize + 2usize)
    if out_error != ok { ret ("", out_error) }
    var at = from + 1usize
    var used = 0usize
    var high = 0u32
    var have_high = false
    while at < until && data[at] != 62u8 {
        let digit = pdf_hex_digit(data[at])
        if digit != 255u32 {
            if have_high {
                out[used] = u8(high * 16u32 + digit)
                used += 1usize
                have_high = false
            } else {
                high = digit
                have_high = true
            }
        }
        at += 1usize
    }
    if have_high {
        out[used] = u8(high * 16u32)
        used += 1usize
    }
    ret (out[0usize..used], ok)
}

fn pdf_literal_bytes(a: *mem.Arena, data: []const u8, from: usize, until: usize) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, until - from + 1usize)
    if out_error != ok { ret ("", out_error) }
    var at = from + 1usize
    var used = 0usize
    var depth = 1usize
    while at < until && depth > 0usize {
        let c = data[at]
        if c == 92u8 && at + 1usize < until {
            at += 1usize
            let escaped = data[at]
            if escaped == 10u8 {
                at += 1usize
                continue
            }
            if escaped == 13u8 {
                if at + 1usize < until && data[at + 1usize] == 10u8 { at += 1usize }
                at += 1usize
                continue
            }
            var byte = escaped
            if escaped == 110u8 { byte = 10u8 }
            if escaped == 114u8 { byte = 13u8 }
            if escaped == 116u8 { byte = 9u8 }
            if escaped == 98u8 { byte = 8u8 }
            if escaped == 102u8 { byte = 12u8 }
            if escaped >= 48u8 && escaped <= 55u8 {
                var value = u32(escaped - 48u8)
                var digits = 1usize
                while digits < 3usize && at + 1usize < until && data[at + 1usize] >= 48u8 && data[at + 1usize] <= 55u8 {
                    at += 1usize
                    value = value * 8u32 + u32(data[at] - 48u8)
                    digits += 1usize
                }
                byte = u8(value & 255u32)
            }
            out[used] = byte
            used += 1usize
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
        } else {
            out[used] = c
            used += 1usize
        }
        at += 1usize
    }
    ret (out[0usize..used], ok)
}

fn pdf_utf16be(a: *mem.Arena, raw: []const u8) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, raw.len * 2usize + 1usize)
    if out_error != ok { ret ("", out_error) }
    var at = 2usize
    var used = 0usize
    while at + 1usize < raw.len {
        let unit = u32(raw[at]) * 256u32 + u32(raw[at + 1usize])
        var scalar = unit
        if unit >= 55296u32 && unit < 56320u32 {
            if at + 3usize < raw.len {
                let low = u32(raw[at + 2usize]) * 256u32 + u32(raw[at + 3usize])
                if low >= 56320u32 && low < 57344u32 {
                    scalar = 65536u32 + ((unit - 55296u32) << 10u32) + (low - 56320u32)
                    at += 2usize
                } else {
                    scalar = 65533u32
                }
            } else {
                scalar = 65533u32
            }
        } else if unit >= 56320u32 && unit < 57344u32 {
            scalar = 65533u32
        }
        let (width, encode_error) = utf8.encode(scalar, out[used..out.len])
        if encode_error != ok { ret ("", encode_error) }
        used += usize(width)
        at += 2usize
    }
    ret (out[0usize..used], ok)
}

fn pdf_text(a: *mem.Arena, raw: []const u8) -> (str, err) {
    if raw.len >= 2usize && raw[0usize] == 254u8 && raw[1usize] == 255u8 {
        let (text, text_error) = pdf_utf16be(a, raw)
        ret (text, text_error)
    }
    let (text, text_error) = latin1_to_utf8(a, raw)
    ret (text, text_error)
}

fn read_pdf_string(a: *mem.Arena, data: []const u8, from: usize, until: usize, key: str) -> (str, err) {
    var at = from
    while at + key.len <= until {
        if pdf_word_at(data, at, until, key) {
            var value_at = at + key.len
            while value_at < until && is_space(data[value_at]) { value_at += 1usize }
            if value_at < until && data[value_at] == 60u8 {
                let (raw, raw_error) = pdf_hex_bytes(a, data, value_at, until)
                if raw_error != ok { ret ("", raw_error) }
                let (text, text_error) = pdf_text(a, raw)
                ret (text, text_error)
            }
            if value_at < until && data[value_at] == 40u8 {
                let (raw, raw_error) = pdf_literal_bytes(a, data, value_at, until)
                if raw_error != ok { ret ("", raw_error) }
                let (text, text_error) = pdf_text(a, raw)
                ret (text, text_error)
            }
            ret ("", ok)
        }
        at += 1usize
    }
    ret ("", ok)
}

fn pdf_metadata(a: *mem.Arena, data: []const u8) -> (str, str, err) {
    let (from, until, found) = pdf_info_span(data)
    if !found { ret ("", "", ok) }
    let (title, title_error) = read_pdf_string(a, data, from, until, "/Title")
    if title_error != ok { ret ("", "", title_error) }
    let (author, author_error) = read_pdf_string(a, data, from, until, "/Author")
    if author_error != ok { ret ("", "", author_error) }
    ret (title, author, ok)
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

fn markdown_word(c: u8) -> bool {
    ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) || c == 95u8
}

fn markdown_marker_slot(c: u8, count: usize) -> usize {
    if count == 1usize && c == 42u8 { ret 0usize }
    if count == 2usize && c == 42u8 { ret 1usize }
    if count == 1usize && c == 126u8 { ret 2usize }
    if count == 2usize && c == 126u8 { ret 3usize }
    if count == 1usize && c == 96u8 { ret 4usize }
    ret 5usize
}

fn markdown_marker_close(line: str, from: usize, marker: u8, count: usize) -> bool {
    var at = from
    while at < line.len {
        if line[at] == marker {
            var after = at
            while after < line.len && line[after] == marker { after += 1usize }
            if after - at == count && at > 0usize && markdown_word(line[at - 1usize]) && (after == line.len || !markdown_word(line[after])) { ret true }
            at = after
        } else {
            at += 1usize
        }
    }
    ret false
}

fn markdown_line(b: *str.Builder, line: str) -> err {
    var i = 0usize
    var active: [5]bool = zero
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
            var after = i
            while after < line.len && line[after] == c { after += 1usize }
            let count = after - i
            let slot = markdown_marker_slot(c, count)
            let opening = (i == 0usize || !markdown_word(line[i - 1usize])) && after < line.len && markdown_word(line[after])
            let closing = i > 0usize && markdown_word(line[i - 1usize]) && (after == line.len || !markdown_word(line[after]))
            if slot < active.len {
                if active[slot] && closing {
                    active[slot] = false
                    i = after
                    continue
                }
                if !active[slot] && opening && markdown_marker_close(line, after, c, count) {
                    active[slot] = true
                    i = after
                    continue
                }
            }
            try str.push(b, line[i..after])
            i = after
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
    var (b, builder_error) = str.builder(a, source.len + 16usize)
    if builder_error != ok { ret (empty_document(.Markdown), builder_error) }
    var title_start = 0usize
    var title_len = 0usize
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
            let content_start = b.len
            try markdown_line(&b, content)
            if is_heading && title_len == 0usize {
                // Slice the same reduced bytes that went into the body; a second
                // builder would displace this builder's arena claim.
                title_start = content_start
                title_len = b.len - content_start
            }
        }
        if end >= source.len { break }
        at = end + 1usize
    }
    let text = str.done(&b)
    var d = empty_document(.Markdown)
    d.text = text
    d.title = text[title_start..title_start + title_len]
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

fn vcard_count(source: []const u8) -> usize {
    var count = 0usize
    var at = 0usize
    while at < source.len {
        var end = at
        while end < source.len && source[end] != 10u8 { end += 1usize }
        var line_end = end
        if line_end > at && source[line_end - 1usize] == 13u8 { line_end -= 1usize }
        if line_end - at == 11usize && starts_fold(source, at, "begin:vcard") { count += 1usize }
        if end >= source.len { break }
        at = end + 1usize
    }
    ret count
}

fn vcard_extract(a: *mem.Arena, source: []const u8) -> (Document, err) {
    let expected = vcard_count(source)
    let (cards, cards_error) = mem.alloc[vcard.Card](a, expected)
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
    if s.len >= 2usize && s[0usize] == 13u8 && s[1usize] == 10u8 { ret ("", s[2usize..s.len]) }
    if s.len >= 1usize && s[0usize] == 10u8 { ret ("", s[1usize..s.len]) }
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
            var (b, builder_error) = str.builder(a, 0usize)
            if builder_error != ok { ret ("", false, builder_error) }
            let initial = str.trim(block[at + name.len + 1usize..line_end])
            let initial_error = str.push(&b, initial)
            if initial_error != ok { ret ("", false, initial_error) }
            // Continuation lines start with a space or a tab.
            var next = end + 1usize
            while next < block.len && (block[next] == 32u8 || block[next] == 9u8) {
                var e2 = next
                while e2 < block.len && block[e2] != 10u8 { e2 += 1usize }
                var l2 = e2
                if l2 > next && block[l2 - 1usize] == 13u8 { l2 -= 1usize }
                let continuation = str.trim(block[next..l2])
                if continuation.len > 0usize {
                    if b.len > 0usize {
                        let space_error = str.push(&b, " ")
                        if space_error != ok { ret ("", false, space_error) }
                    }
                    let continuation_error = str.push(&b, continuation)
                    if continuation_error != ok { ret ("", false, continuation_error) }
                }
                next = e2 + 1usize
            }
            ret (str.done(&b), true, ok)
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
    if starts_fold(charset, 0usize, "windows-1252") {
        let (utf, utf_error) = windows1252_to_utf8(a, decoded)
        if utf_error != ok { ret ("", utf_error) }
        decoded = utf
    } else if starts_fold(charset, 0usize, "windows-1251") {
        let (utf, utf_error) = windows1251_to_utf8(a, decoded)
        if utf_error != ok { ret ("", utf_error) }
        decoded = utf
    } else if !valid_utf8(decoded) || starts_fold(charset, 0usize, "iso-8859") || starts_fold(charset, 0usize, "latin") {
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
        // Parse every nested part before joining: repeatedly concatenating `plain`
        // retains a full copy of the prior text in the arena for every MIME part.
        var part_slots = 0usize
        var slot_at = 0usize
        while slot_at < body.len {
            let (boundary_at, have_boundary) = str.find_from(body, marker, slot_at)
            if !have_boundary { break }
            part_slots += 1usize
            slot_at = boundary_at + marker.len
        }
        let (plain_parts, parts_error) = mem.alloc[str](a, part_slots + 1usize)
        if parts_error != ok { ret ("", false, parts_error) }
        var plain_count = 0usize
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
                } else {
                    plain_parts[plain_count] = piece
                    plain_count += 1usize
                }
            }
            if !has_next { break }
            at = next + marker.len
            if at + 1usize < body.len && body[at] == 45u8 && body[at + 1usize] == 45u8 { break }
        }
        if plain_count > 0usize {
            let (plain, plain_error) = join(a, plain_parts[0usize..plain_count], "\n")
            ret (plain, false, plain_error)
        }
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
        let (title, author, metadata_error) = pdf_metadata(a, data)
        if metadata_error != ok { ret (empty_document(format), metadata_error) }
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
                        if cell.number > -9.0e18 && cell.number < 9.0e18 && cell.number == f64(i64(cell.number)) {
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
    var source = data
    // `extract_as` keeps its explicit-API UTF-8 contract. The facade, however,
    // promises Latin-1 handling for named text formats, so normalize once here.
    if format != .Mail && format != .Pdf && format != .Docx && format != .Pptx && format != .Xlsx && format != .Odt && format != .Odp && format != .Ods && !valid_utf8(strip_bom(data)) {
        let (utf, utf_error) = latin1_to_utf8(a, data)
        if utf_error != ok { ret (empty_document(format), utf_error) }
        source = utf
    }
    let (d, extract_error) = extract_as(a, source, format)
    ret (d, extract_error)
}
