// CommonMark and GitHub Flavored Markdown, as cmark-gfm renders them (R's commonmark package): the text
// parsed into a tree and written as HTML, XML, LaTeX or groff man. `Options` carries R's switches
// (hardbreaks, smart punctuation, source positions, the line width of LaTeX and man) and the five GFM
// extensions (table, strikethrough, autolink, tagfilter, tasklist). Raw HTML is passed through unless
// tagfilter holds it back; unsafe links are kept, as the package does.
//
// Not here: footnotes, the commonmark and plaintext writers, and the `normalize` option (cmark ignores
// it too). Input must be UTF-8; invalid bytes are not replaced.

use e.mem
use e.str
use e.fmt.commonmark_text as ct
use e.fmt.commonmark_tree as tr
use e.fmt.commonmark_block as cb

type Options = struct {
    sourcepos: bool, hardbreaks: bool, smart: bool,
    table: bool, strikethrough: bool, autolink: bool, tagfilter: bool, tasklist: bool,
    width: i32
}

error OutOfMemory

fn ix(i: i32) -> usize { ret usize(i) }

fn parse_doc(a: *mem.Arena, text: str, o: Options) -> (tr.Doc, err) {
    var d: tr.Doc = zero
    d.a = a
    d.sourcepos = o.sourcepos
    d.hardbreaks = o.hardbreaks
    d.smart = o.smart
    d.x_table = o.table
    d.x_strike = o.strikethrough
    d.x_autolink = o.autolink
    d.x_tagfilter = o.tagfilter
    d.x_tasklist = o.tasklist
    d.root = tr.NIL
    d.current = tr.NIL
    d.last_delim = tr.NIL
    d.last_bracket = tr.NIL
    cb.parse(&d, text)
    if d.failed { ret (d, OutOfMemory) }
    ret (d, ok)
}

// --- HTML.

fn render_cr(b: *ct.Buf) {
    if b.n > 0usize && ct.last_byte(b) != 10u8 { ct.putc(b, 10u8) }
}

fn html_sourcepos(d: *const tr.Doc, b: *ct.Buf, n: i32) {
    if !d.sourcepos { ret }
    let nd = &d.nodes[ix(n)]
    ct.put(b, " data-sourcepos=\"")
    ct.put_i32(b, nd.sl)
    ct.putc(b, 58u8)
    ct.put_i32(b, nd.sc)
    ct.putc(b, 45u8)
    ct.put_i32(b, nd.el)
    ct.putc(b, 58u8)
    ct.put_i32(b, nd.ec)
    ct.putc(b, 34u8)
}

fn is_tag(data: str, name: str) -> bool {
    if data.len < 3usize || data[0usize] != 60u8 { ret false }
    var i = 1usize
    if data[i] == 47u8 { i += 1usize }
    var k = 0usize
    while i < data.len {
        if k >= name.len { break }
        if ct.lower(data[i]) != name[k] { ret false }
        i += 1usize
        k += 1usize
    }
    if i == data.len { ret false }
    if ct.is_space(data[i]) || data[i] == 62u8 { ret true }
    if data[i] == 47u8 && data.len >= i + 2usize && data[i + 1usize] == 62u8 { ret true }
    ret false
}

fn tag_filtered(data: str) -> bool {
    ret is_tag(data, "title") || is_tag(data, "textarea") || is_tag(data, "style") || is_tag(data, "xmp") || is_tag(data, "iframe") || is_tag(data, "noembed") || is_tag(data, "noframes") || is_tag(data, "script") || is_tag(data, "plaintext")
}

fn put_filtered_block(b: *ct.Buf, s: str) {
    var at = 0usize
    while at < s.len {
        if s[at] == 60u8 {
            if tag_filtered(s[at..s.len]) { ct.put(b, "&lt;") } else { ct.putc(b, 60u8) }
        } else {
            ct.putc(b, s[at])
        }
        at += 1usize
    }
}

type HtmlState = struct { plain: i32, need_closing_body: bool, in_header: bool }

fn html_heading_open(b: *ct.Buf, level: i32) {
    ct.put(b, "<h")
    ct.put_i32(b, level)
}

fn html_node(d: *tr.Doc, b: *ct.Buf, st: *HtmlState, id: i32, entering: bool) {
    let n = ix(id)
    let kind = d.nodes[n].kind
    if st.plain == id { st.plain = tr.NIL }
    if st.plain != tr.NIL {
        if kind == tr.K_TEXT || kind == tr.K_CODE || kind == tr.K_HTML_INLINE {
            ct.escape_html(b, d.nodes[n].lit)
        } else {
            if kind == tr.K_LINEBREAK || kind == tr.K_SOFTBREAK { ct.putc(b, 32u8) }
        }
        ret
    }
    if kind == tr.K_TABLE {
        if entering {
            render_cr(b)
            ct.put(b, "<table")
            html_sourcepos(d, b, id)
            ct.putc(b, 62u8)
            st.need_closing_body = false
        } else {
            if st.need_closing_body {
                render_cr(b)
                ct.put(b, "</tbody>")
                render_cr(b)
            }
            st.need_closing_body = false
            render_cr(b)
            ct.put(b, "</table>")
            render_cr(b)
        }
        ret
    }
    if kind == tr.K_ROW {
        if entering {
            render_cr(b)
            if d.nodes[n].is_header {
                st.in_header = true
                ct.put(b, "<thead>")
                render_cr(b)
            } else {
                if !st.need_closing_body {
                    ct.put(b, "<tbody>")
                    render_cr(b)
                    st.need_closing_body = true
                }
            }
            ct.put(b, "<tr")
            html_sourcepos(d, b, id)
            ct.putc(b, 62u8)
        } else {
            render_cr(b)
            ct.put(b, "</tr>")
            if d.nodes[n].is_header {
                render_cr(b)
                ct.put(b, "</thead>")
                st.in_header = false
            }
        }
        ret
    }
    if kind == tr.K_CELL {
        if entering {
            render_cr(b)
            if st.in_header { ct.put(b, "<th") } else { ct.put(b, "<td") }
            let par = d.nodes[n].parent
            let table = d.nodes[ix(par)].parent
            let al = ct.pk(d.nodes[ix(table)].aligns, usize(d.nodes[n].cell_index))
            if al == 108u8 { ct.put(b, " align=\"left\"") }
            if al == 99u8 { ct.put(b, " align=\"center\"") }
            if al == 114u8 { ct.put(b, " align=\"right\"") }
            html_sourcepos(d, b, id)
            ct.putc(b, 62u8)
        } else {
            if st.in_header { ct.put(b, "</th>") } else { ct.put(b, "</td>") }
        }
        ret
    }
    if kind == tr.K_STRIKE {
        if entering { ct.put(b, "<del>") } else { ct.put(b, "</del>") }
        ret
    }
    if kind == tr.K_ITEM && d.nodes[n].tasklist {
        if entering {
            render_cr(b)
            ct.put(b, "<li")
            html_sourcepos(d, b, id)
            ct.putc(b, 62u8)
            if d.nodes[n].checked {
                ct.put(b, "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ")
            } else {
                ct.put(b, "<input type=\"checkbox\" disabled=\"\" /> ")
            }
        } else {
            ct.put(b, "</li>\n")
        }
        ret
    }
    if kind == tr.K_DOCUMENT { ret }
    if kind == tr.K_BLOCK_QUOTE {
        render_cr(b)
        if entering {
            ct.put(b, "<blockquote")
            html_sourcepos(d, b, id)
            ct.put(b, ">\n")
        } else {
            ct.put(b, "</blockquote>\n")
        }
        ret
    }
    if kind == tr.K_LIST {
        let bullet = d.nodes[n].list_type == 1u8
        if entering {
            render_cr(b)
            if bullet {
                ct.put(b, "<ul")
                html_sourcepos(d, b, id)
                ct.put(b, ">\n")
            } else {
                if d.nodes[n].start == 1i32 {
                    ct.put(b, "<ol")
                } else {
                    ct.put(b, "<ol start=\"")
                    ct.put_i32(b, d.nodes[n].start)
                    ct.putc(b, 34u8)
                }
                html_sourcepos(d, b, id)
                ct.put(b, ">\n")
            }
        } else {
            if bullet { ct.put(b, "</ul>\n") } else { ct.put(b, "</ol>\n") }
        }
        ret
    }
    if kind == tr.K_ITEM {
        if entering {
            render_cr(b)
            ct.put(b, "<li")
            html_sourcepos(d, b, id)
            ct.putc(b, 62u8)
        } else {
            ct.put(b, "</li>\n")
        }
        ret
    }
    if kind == tr.K_HEADING {
        if entering {
            render_cr(b)
            html_heading_open(b, d.nodes[n].level)
            html_sourcepos(d, b, id)
            ct.putc(b, 62u8)
        } else {
            ct.put(b, "</h")
            ct.put_i32(b, d.nodes[n].level)
            ct.put(b, ">\n")
        }
        ret
    }
    if kind == tr.K_CODE_BLOCK {
        render_cr(b)
        let info = d.nodes[n].info
        if info.len == 0usize {
            ct.put(b, "<pre")
            html_sourcepos(d, b, id)
            ct.put(b, "><code>")
        } else {
            var first_tag = 0usize
            while first_tag < info.len && !ct.is_space(info[first_tag]) { first_tag += 1usize }
            ct.put(b, "<pre")
            html_sourcepos(d, b, id)
            ct.put(b, "><code class=\"language-")
            ct.escape_html(b, info[0usize..first_tag])
            ct.put(b, "\">")
        }
        ct.escape_html(b, d.nodes[n].lit)
        ct.put(b, "</code></pre>\n")
        ret
    }
    if kind == tr.K_HTML_BLOCK {
        render_cr(b)
        if d.x_tagfilter { put_filtered_block(b, d.nodes[n].lit) } else { ct.put(b, d.nodes[n].lit) }
        render_cr(b)
        ret
    }
    if kind == tr.K_THEMATIC {
        render_cr(b)
        ct.put(b, "<hr")
        html_sourcepos(d, b, id)
        ct.put(b, " />\n")
        ret
    }
    if kind == tr.K_PARAGRAPH {
        let parent = d.nodes[n].parent
        var tight = false
        if parent != tr.NIL {
            let gp = d.nodes[ix(parent)].parent
            if gp != tr.NIL && d.nodes[ix(gp)].kind == tr.K_LIST { tight = d.nodes[ix(gp)].tight }
        }
        if !tight {
            if entering {
                render_cr(b)
                ct.put(b, "<p")
                html_sourcepos(d, b, id)
                ct.putc(b, 62u8)
            } else {
                ct.put(b, "</p>\n")
            }
        }
        ret
    }
    if kind == tr.K_TEXT {
        ct.escape_html(b, d.nodes[n].lit)
        ret
    }
    if kind == tr.K_LINEBREAK {
        ct.put(b, "<br />\n")
        ret
    }
    if kind == tr.K_SOFTBREAK {
        if d.hardbreaks { ct.put(b, "<br />\n") } else { ct.putc(b, 10u8) }
        ret
    }
    if kind == tr.K_CODE {
        ct.put(b, "<code>")
        ct.escape_html(b, d.nodes[n].lit)
        ct.put(b, "</code>")
        ret
    }
    if kind == tr.K_HTML_INLINE {
        let raw = d.nodes[n].lit
        if d.x_tagfilter && tag_filtered(raw) {
            ct.put(b, "&lt;")
            ct.put(b, raw[1usize..raw.len])
        } else {
            ct.put(b, raw)
        }
        ret
    }
    if kind == tr.K_STRONG {
        let par = d.nodes[n].parent
        if par == tr.NIL || d.nodes[ix(par)].kind != tr.K_STRONG {
            if entering { ct.put(b, "<strong>") } else { ct.put(b, "</strong>") }
        }
        ret
    }
    if kind == tr.K_EMPH {
        if entering { ct.put(b, "<em>") } else { ct.put(b, "</em>") }
        ret
    }
    if kind == tr.K_LINK {
        if entering {
            ct.put(b, "<a href=\"")
            ct.escape_href(b, d.nodes[n].url)
            if d.nodes[n].title.len > 0usize {
                ct.put(b, "\" title=\"")
                ct.escape_html(b, d.nodes[n].title)
            }
            ct.put(b, "\">")
        } else {
            ct.put(b, "</a>")
        }
        ret
    }
    if kind == tr.K_IMAGE {
        if entering {
            ct.put(b, "<img src=\"")
            ct.escape_href(b, d.nodes[n].url)
            ct.put(b, "\" alt=\"")
            st.plain = id
        } else {
            if d.nodes[n].title.len > 0usize {
                ct.put(b, "\" title=\"")
                ct.escape_html(b, d.nodes[n].title)
            }
            ct.put(b, "\" />")
        }
        ret
    }
}

fn render_html(a: *mem.Arena, text: str, o: Options) -> (str, err) {
    let (d0, pe) = parse_doc(a, text, o)
    if pe != ok { ret ("", pe) }
    var d = d0
    var b = ct.buf_new(a, text.len * 2usize + 64usize)
    var st: HtmlState = zero
    st.plain = tr.NIL
    var it = tr.iter_new(d.root)
    while tr.iter_next(&d, &it) { html_node(&d, &b, &st, it.node, it.enter) }
    if b.failed { ret ("", OutOfMemory) }
    ret (ct.view(&b), ok)
}

// --- XML.

fn type_string(d: *const tr.Doc, n: i32) -> str {
    let nd = &d.nodes[ix(n)]
    let k = nd.kind
    if k == tr.K_DOCUMENT { ret "document" }
    if k == tr.K_BLOCK_QUOTE { ret "block_quote" }
    if k == tr.K_LIST { ret "list" }
    if k == tr.K_ITEM {
        if nd.tasklist { ret "tasklist" }
        ret "item"
    }
    if k == tr.K_CODE_BLOCK { ret "code_block" }
    if k == tr.K_HTML_BLOCK { ret "html_block" }
    if k == tr.K_PARAGRAPH { ret "paragraph" }
    if k == tr.K_HEADING { ret "heading" }
    if k == tr.K_THEMATIC { ret "thematic_break" }
    if k == tr.K_TABLE { ret "table" }
    if k == tr.K_ROW {
        if nd.is_header { ret "table_header" }
        ret "table_row"
    }
    if k == tr.K_CELL { ret "table_cell" }
    if k == tr.K_TEXT { ret "text" }
    if k == tr.K_SOFTBREAK { ret "softbreak" }
    if k == tr.K_LINEBREAK { ret "linebreak" }
    if k == tr.K_CODE { ret "code" }
    if k == tr.K_HTML_INLINE { ret "html_inline" }
    if k == tr.K_EMPH { ret "emph" }
    if k == tr.K_STRONG { ret "strong" }
    if k == tr.K_LINK { ret "link" }
    if k == tr.K_IMAGE { ret "image" }
    if k == tr.K_STRIKE { ret "strikethrough" }
    ret "unknown"
}

fn xml_indent(b: *ct.Buf, indent: i32) {
    var i = 0i32
    while i < indent && i < 40i32 {
        ct.putc(b, 32u8)
        i += 1i32
    }
}

fn xml_node(d: *tr.Doc, b: *ct.Buf, indent: *i32, id: i32, entering: bool) {
    let n = ix(id)
    let kind = d.nodes[n].kind
    if entering {
        xml_indent(b, *indent)
        ct.putc(b, 60u8)
        ct.put(b, type_string(d, id))
        if d.sourcepos && d.nodes[n].sl != 0i32 {
            ct.put(b, " sourcepos=\"")
            ct.put_i32(b, d.nodes[n].sl)
            ct.putc(b, 58u8)
            ct.put_i32(b, d.nodes[n].sc)
            ct.putc(b, 45u8)
            ct.put_i32(b, d.nodes[n].el)
            ct.putc(b, 58u8)
            ct.put_i32(b, d.nodes[n].ec)
            ct.putc(b, 34u8)
        }
        if kind == tr.K_CELL {
            let par = d.nodes[n].parent
            if d.nodes[ix(par)].is_header {
                let table = d.nodes[ix(par)].parent
                let al = ct.pk(d.nodes[ix(table)].aligns, usize(d.nodes[n].cell_index))
                if al == 108u8 { ct.put(b, " align=\"left\"") }
                if al == 99u8 { ct.put(b, " align=\"center\"") }
                if al == 114u8 { ct.put(b, " align=\"right\"") }
            }
        }
        if kind == tr.K_ITEM && d.nodes[n].tasklist {
            if d.nodes[n].checked { ct.put(b, " completed=\"true\"") } else { ct.put(b, " completed=\"false\"") }
        }
        var literal = false
        if kind == tr.K_DOCUMENT {
            ct.put(b, " xmlns=\"http://commonmark.org/xml/1.0\"")
        } else {
            if kind == tr.K_TEXT || kind == tr.K_CODE || kind == tr.K_HTML_BLOCK || kind == tr.K_HTML_INLINE {
                ct.put(b, " xml:space=\"preserve\">")
                ct.escape_xml(b, d.nodes[n].lit)
                ct.put(b, "</")
                ct.put(b, type_string(d, id))
                literal = true
            } else {
                if kind == tr.K_LIST {
                    if d.nodes[n].list_type == 2u8 {
                        ct.put(b, " type=\"ordered\"")
                        ct.put(b, " start=\"")
                        ct.put_i32(b, d.nodes[n].start)
                        ct.putc(b, 34u8)
                        if d.nodes[n].delim == 2u8 { ct.put(b, " delim=\"paren\"") }
                        if d.nodes[n].delim == 1u8 { ct.put(b, " delim=\"period\"") }
                    } else {
                        ct.put(b, " type=\"bullet\"")
                    }
                    if d.nodes[n].tight { ct.put(b, " tight=\"true\"") } else { ct.put(b, " tight=\"false\"") }
                } else {
                    if kind == tr.K_HEADING {
                        ct.put(b, " level=\"")
                        ct.put_i32(b, d.nodes[n].level)
                        ct.putc(b, 34u8)
                    } else {
                        if kind == tr.K_CODE_BLOCK {
                            if d.nodes[n].info.len > 0usize {
                                ct.put(b, " info=\"")
                                ct.escape_xml(b, d.nodes[n].info)
                                ct.putc(b, 34u8)
                            }
                            ct.put(b, " xml:space=\"preserve\">")
                            ct.escape_xml(b, d.nodes[n].lit)
                            ct.put(b, "</")
                            ct.put(b, type_string(d, id))
                            literal = true
                        } else {
                            if kind == tr.K_LINK || kind == tr.K_IMAGE {
                                ct.put(b, " destination=\"")
                                ct.escape_xml(b, d.nodes[n].url)
                                ct.putc(b, 34u8)
                                ct.put(b, " title=\"")
                                ct.escape_xml(b, d.nodes[n].title)
                                ct.putc(b, 34u8)
                            }
                        }
                    }
                }
            }
        }
        if d.nodes[n].first != tr.NIL {
            *indent += 2i32
        } else {
            if !literal { ct.put(b, " /") }
        }
        ct.put(b, ">\n")
    } else {
        if d.nodes[n].first != tr.NIL {
            *indent -= 2i32
            xml_indent(b, *indent)
            ct.put(b, "</")
            ct.put(b, type_string(d, id))
            ct.put(b, ">\n")
        }
    }
}

fn render_xml(a: *mem.Arena, text: str, o: Options) -> (str, err) {
    let (d0, pe) = parse_doc(a, text, o)
    if pe != ok { ret ("", pe) }
    var d = d0
    var b = ct.buf_new(a, text.len * 3usize + 256usize)
    ct.put(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
    ct.put(&b, "<!DOCTYPE document SYSTEM \"CommonMark.dtd\">\n")
    var indent = 0i32
    var it = tr.iter_new(d.root)
    while tr.iter_next(&d, &it) { xml_node(&d, &b, &indent, it.node, it.enter) }
    if b.failed { ret ("", OutOfMemory) }
    ret (ct.view(&b), ok)
}

// --- LaTeX and man: cmark's generic renderer with a line-width wrap.

const ESC_LITERAL: u8 = 0u8
const ESC_NORMAL: u8 = 1u8
const ESC_URL: u8 = 3u8

type R = struct {
    b: ct.Buf, column: i32, width: i32, need_cr: i32, last_breakable: i32,
    begin_line: bool, begin_content: bool, man: bool, esc_pipe: bool
}

fn r_ascii(r: *R, s: str) {
    ct.put(&r.b, s)
    r.column += i32(s.len)
}

fn r_code_point(r: *R, c: u32) {
    ct.put_scalar(&r.b, c)
    r.column += 1i32
}

fn latex_outc(r: *R, escape: u8, c: u32, nextc: u8) {
    if escape == ESC_LITERAL {
        r_code_point(r, c)
        ret
    }
    if c == 123u32 || c == 125u32 || c == 35u32 || c == 37u32 || c == 38u32 {
        r_ascii(r, "\\")
        r_code_point(r, c)
        ret
    }
    if c == 36u32 || c == 95u32 {
        if escape == ESC_NORMAL { r_ascii(r, "\\") }
        r_code_point(r, c)
        ret
    }
    if c == 45u32 {
        if nextc == 45u8 { r_ascii(r, "-{}") } else { r_ascii(r, "-") }
        ret
    }
    if c == 126u32 {
        if escape == ESC_NORMAL { r_ascii(r, "\\textasciitilde{}") } else { r_code_point(r, c) }
        ret
    }
    if c == 94u32 {
        r_ascii(r, "\\^{}")
        ret
    }
    if c == 92u32 {
        if escape == ESC_URL { r_ascii(r, "/") } else { r_ascii(r, "\\textbackslash{}") }
        ret
    }
    if c == 124u32 {
        r_ascii(r, "\\textbar{}")
        ret
    }
    if c == 60u32 {
        r_ascii(r, "\\textless{}")
        ret
    }
    if c == 62u32 {
        r_ascii(r, "\\textgreater{}")
        ret
    }
    if c == 91u32 || c == 93u32 {
        r_ascii(r, "{")
        r_code_point(r, c)
        r_ascii(r, "}")
        ret
    }
    if c == 34u32 {
        r_ascii(r, "\\textquotedbl{}")
        ret
    }
    if c == 39u32 {
        r_ascii(r, "\\textquotesingle{}")
        ret
    }
    if c == 160u32 {
        r_ascii(r, "~")
        ret
    }
    if c == 8230u32 {
        r_ascii(r, "\\ldots{}")
        ret
    }
    if c == 8216u32 {
        if escape == ESC_NORMAL { r_ascii(r, "`") } else { r_code_point(r, c) }
        ret
    }
    if c == 8217u32 {
        if escape == ESC_NORMAL { r_ascii(r, "'") } else { r_code_point(r, c) }
        ret
    }
    if c == 8220u32 {
        if escape == ESC_NORMAL { r_ascii(r, "``") } else { r_code_point(r, c) }
        ret
    }
    if c == 8221u32 {
        if escape == ESC_NORMAL { r_ascii(r, "''") } else { r_code_point(r, c) }
        ret
    }
    if c == 8212u32 {
        if escape == ESC_NORMAL { r_ascii(r, "---") } else { r_code_point(r, c) }
        ret
    }
    if c == 8211u32 {
        if escape == ESC_NORMAL { r_ascii(r, "--") } else { r_code_point(r, c) }
        ret
    }
    r_code_point(r, c)
}

fn man_outc(r: *R, escape: u8, c: u32) {
    if escape == ESC_LITERAL {
        r_code_point(r, c)
        ret
    }
    if c == 46u32 {
        if r.begin_line { r_ascii(r, "\\&.") } else { r_code_point(r, c) }
        ret
    }
    if c == 39u32 {
        if r.begin_line { r_ascii(r, "\\&'") } else { r_code_point(r, c) }
        ret
    }
    if c == 45u32 {
        r_ascii(r, "\\-")
        ret
    }
    if c == 92u32 {
        r_ascii(r, "\\e")
        ret
    }
    if c == 8216u32 {
        r_ascii(r, "\\[oq]")
        ret
    }
    if c == 8217u32 {
        r_ascii(r, "\\[cq]")
        ret
    }
    if c == 8220u32 {
        r_ascii(r, "\\[lq]")
        ret
    }
    if c == 8221u32 {
        r_ascii(r, "\\[rq]")
        ret
    }
    if c == 8212u32 {
        r_ascii(r, "\\[em]")
        ret
    }
    if c == 8211u32 {
        r_ascii(r, "\\[en]")
        ret
    }
    r_code_point(r, c)
}

fn r_cr(r: *R) {
    if r.need_cr < 1i32 { r.need_cr = 1i32 }
}

fn r_blankline(r: *R) {
    if r.need_cr < 2i32 { r.need_cr = 2i32 }
}

fn utf8_len(s: str, i: usize) -> (u32, usize) {
    let b0 = u32(s[i])
    if b0 < 128u32 { ret (b0, 1usize) }
    var need = 0usize
    var sc = 0u32
    if b0 >= 194u32 && b0 < 224u32 {
        need = 1usize
        sc = b0 & 31u32
    } else {
        if b0 >= 224u32 && b0 < 240u32 {
            need = 2usize
            sc = b0 & 15u32
        } else {
            if b0 >= 240u32 && b0 < 245u32 {
                need = 3usize
                sc = b0 & 7u32
            } else {
                ret (65533u32, 1usize)
            }
        }
    }
    if i + need >= s.len { ret (65533u32, 1usize) }
    var k = 1usize
    while k <= need {
        sc = (sc << 6u32) | (u32(s[i + k]) & 63u32)
        k += 1usize
    }
    ret (sc, need + 1usize)
}

fn r_out(r: *R, source: str, wrap: bool, escape: u8) {
    var k = i32(r.b.n) - 1i32
    while r.need_cr > 0i32 {
        if k < 0i32 || r.b.d[ix(k)] == 10u8 {
            k -= 1i32
        } else {
            ct.putc(&r.b, 10u8)
        }
        r.column = 0i32
        r.last_breakable = 0i32
        r.begin_line = true
        r.begin_content = true
        r.need_cr -= 1i32
    }
    var i = 0usize
    while i < source.len {
        if r.begin_line { r.column = 0i32 }
        let (c, len) = utf8_len(source, i)
        let nextc = ct.pk(source, i + len)
        if r.esc_pipe && c == 124u32 { ct.putc(&r.b, 92u8) }
        if c == 32u32 && wrap {
            if !r.begin_line {
                let last_nonspace = i32(r.b.n)
                ct.putc(&r.b, 32u8)
                r.column += 1i32
                r.begin_line = false
                r.begin_content = false
                while ct.pk(source, i + 1usize) == 32u8 { i += 1usize }
                if !ct.is_digit(ct.pk(source, i + 1usize)) { r.last_breakable = last_nonspace }
            }
        } else {
            if escape == ESC_LITERAL {
                if c == 10u32 {
                    ct.putc(&r.b, 10u8)
                    r.column = 0i32
                    r.begin_line = true
                    r.begin_content = true
                    r.last_breakable = 0i32
                } else {
                    r_code_point(r, c)
                    r.begin_line = false
                    r.begin_content = r.begin_content && c < 128u32 && ct.is_digit(u8(c))
                }
            } else {
                if r.man { man_outc(r, escape, c) } else { latex_outc(r, escape, c, nextc) }
                r.begin_line = false
                r.begin_content = r.begin_content && c < 128u32 && ct.is_digit(u8(c))
            }
        }
        if r.width > 0i32 && r.column > r.width && !r.begin_line && r.last_breakable > 0i32 {
            let lb = ix(r.last_breakable)
            let rem_len = r.b.n - (lb + 1usize)
            var remainder = ct.buf_new(r.b.a, rem_len + 1usize)
            ct.put(&remainder, r.b.d[lb + 1usize..r.b.n])
            r.b.n = lb
            ct.putc(&r.b, 10u8)
            ct.put(&r.b, ct.view(&remainder))
            r.column = i32(rem_len)
            r.last_breakable = 0i32
            r.begin_line = false
            r.begin_content = false
        }
        i += len
    }
}

fn lit(r: *R, s: str) { r_out(r, s, false, ESC_LITERAL) }

fn item_index(d: *const tr.Doc, id: i32) -> i32 {
    var idx = 0i32
    var p = d.nodes[ix(id)].prev
    while p != tr.NIL {
        idx += 1i32
        p = d.nodes[ix(p)].prev
    }
    let par = d.nodes[ix(id)].parent
    ret d.nodes[ix(par)].start + idx
}

// 0 none, 1 url autolink, 2 e-mail autolink, 3 normal, 4 internal.
fn latex_link_type(d: *tr.Doc, id: i32) -> i32 {
    let n = ix(id)
    let url = d.nodes[n].url
    if url.len > 0usize && url[0usize] == 35u8 { ret 4i32 }
    if url.len == 0usize || ct.scan_scheme(url, 0usize) == 0usize { ret 0i32 }
    if d.nodes[n].title.len == 0usize {
        let link_text = d.nodes[n].first
        if link_text == tr.NIL { ret 0i32 }
        tr.consolidate_text(d, link_text)
        var realurl = url
        var isemail = false
        if str.starts_with(url, "mailto:") {
            realurl = url[7usize..url.len]
            isemail = true
        }
        if d.nodes[ix(link_text)].kind == tr.K_TEXT && str.eq(realurl, d.nodes[ix(link_text)].lit) {
            if isemail { ret 2i32 }
            ret 1i32
        }
    }
    ret 3i32
}

fn latex_enumlevel(d: *const tr.Doc, id: i32) -> i32 {
    var level = 0i32
    var t = id
    while t != tr.NIL {
        if d.nodes[ix(t)].kind == tr.K_LIST && d.nodes[ix(id)].list_type == 2u8 { level += 1i32 }
        t = d.nodes[ix(t)].parent
    }
    ret level
}

fn num_str(a: *mem.Arena, v: i32) -> str {
    var b = ct.buf_new(a, 16usize)
    ct.put_i32(&b, v)
    ret ct.view(&b)
}

// Returns false to skip the node's children.
fn gen_node(d: *tr.Doc, r: *R, id: i32, entering: bool, o: *const Options) -> bool {
    let n = ix(id)
    let kind = d.nodes[n].kind
    let allow_wrap = r.width > 0i32
    if kind == tr.K_TABLE {
        if r.man {
            if entering {
                r_cr(r)
                lit(r, ".TS")
                r_cr(r)
                lit(r, "tab(@);")
                r_cr(r)
                let al = d.nodes[n].aligns
                var i = 0usize
                while i < al.len {
                    if al[i] == 108u8 { lit(r, "l") } else {
                    if al[i] == 114u8 { lit(r, "r") } else { lit(r, "c") }
                    }
                    i += 1usize
                }
                if al.len > 0usize {
                    lit(r, ".")
                    r_cr(r)
                }
            } else {
                lit(r, ".TE")
                r_cr(r)
            }
        } else {
            if entering {
                r_cr(r)
                lit(r, "\\begin{table}")
                r_cr(r)
                lit(r, "\\begin{tabular}{")
                let al = d.nodes[n].aligns
                var i = 0usize
                while i < al.len {
                    if al[i] == 99u8 { lit(r, "c") } else {
                    if al[i] == 114u8 { lit(r, "r") } else { lit(r, "l") }
                    }
                    i += 1usize
                }
                lit(r, "}")
                r_cr(r)
            } else {
                lit(r, "\\end{tabular}")
                r_cr(r)
                lit(r, "\\end{table}")
                r_cr(r)
            }
        }
        ret true
    }
    if kind == tr.K_ROW {
        if !entering { r_cr(r) }
        ret true
    }
    if kind == tr.K_CELL {
        if !entering {
            if r.man {
                if d.nodes[n].next != tr.NIL { lit(r, "@") }
            } else {
                if d.nodes[n].next != tr.NIL { lit(r, " & ") } else { lit(r, " \\\\") }
            }
        }
        ret true
    }
    if kind == tr.K_STRIKE {
        if r.man {
            if entering {
                r_cr(r)
                lit(r, ".ST \"")
            } else {
                lit(r, "\"")
                r_cr(r)
            }
        } else {
            if entering { lit(r, "\\sout{") } else { lit(r, "}") }
        }
        ret true
    }
    if kind == tr.K_DOCUMENT { ret true }
    if kind == tr.K_BLOCK_QUOTE {
        if r.man {
            if entering {
                r_cr(r)
                lit(r, ".RS")
                r_cr(r)
            } else {
                r_cr(r)
                lit(r, ".RE")
                r_cr(r)
            }
        } else {
            if entering {
                lit(r, "\\begin{quote}")
                r_cr(r)
            } else {
                lit(r, "\\end{quote}")
                r_blankline(r)
            }
        }
        ret true
    }
    if kind == tr.K_LIST {
        if r.man { ret true }
        let ordered = d.nodes[n].list_type == 2u8
        if entering {
            lit(r, "\\begin{")
            if ordered { lit(r, "enumerate") } else { lit(r, "itemize") }
            lit(r, "}")
            r_cr(r)
            let list_number = d.nodes[n].start
            if list_number > 1i32 {
                let level = latex_enumlevel(d, id)
                if level >= 1i32 && level <= 5i32 {
                    lit(r, "\\setcounter{enum")
                    if level == 1i32 { lit(r, "i") } else {
                    if level == 2i32 { lit(r, "ii") } else {
                    if level == 3i32 { lit(r, "iii") } else {
                    if level == 4i32 { lit(r, "iv") } else { lit(r, "v") }
                    }
                    }
                    }
                    lit(r, "}{")
                    r_out(r, num_str(d.a, list_number), false, ESC_NORMAL)
                    lit(r, "}")
                }
                r_cr(r)
            }
        } else {
            lit(r, "\\end{")
            if ordered { lit(r, "enumerate") } else { lit(r, "itemize") }
            lit(r, "}")
            r_blankline(r)
        }
        ret true
    }
    if kind == tr.K_ITEM {
        if r.man {
            if entering {
                r_cr(r)
                lit(r, ".IP ")
                let par = d.nodes[n].parent
                if d.nodes[ix(par)].list_type == 1u8 {
                    lit(r, "\\[bu] 2")
                } else {
                    var b = ct.buf_new(d.a, 24usize)
                    ct.putc(&b, 34u8)
                    ct.put_i32(&b, item_index(d, id))
                    ct.put(&b, ".\" 4")
                    lit(r, ct.view(&b))
                }
                r_cr(r)
            } else {
                r_cr(r)
            }
        } else {
            if entering { lit(r, "\\item ") } else { r_cr(r) }
        }
        ret true
    }
    if kind == tr.K_HEADING {
        if r.man {
            if entering {
                r_cr(r)
                if d.nodes[n].level == 1i32 { lit(r, ".SH") } else { lit(r, ".SS") }
                r_cr(r)
            } else {
                r_cr(r)
            }
        } else {
            if entering {
                let lv = d.nodes[n].level
                if lv == 1i32 { lit(r, "\\section") }
                if lv == 2i32 { lit(r, "\\subsection") }
                if lv == 3i32 { lit(r, "\\subsubsection") }
                if lv == 4i32 { lit(r, "\\paragraph") }
                if lv == 5i32 { lit(r, "\\subparagraph") }
                lit(r, "{")
            } else {
                lit(r, "}")
                r_blankline(r)
            }
        }
        ret true
    }
    if kind == tr.K_CODE_BLOCK {
        if r.man {
            r_cr(r)
            lit(r, ".IP\n.nf\n\\f[C]\n")
            r_out(r, d.nodes[n].lit, false, ESC_NORMAL)
            r_cr(r)
            lit(r, "\\f[]\n.fi")
            r_cr(r)
        } else {
            r_cr(r)
            lit(r, "\\begin{verbatim}")
            r_cr(r)
            r_out(r, d.nodes[n].lit, false, ESC_LITERAL)
            r_cr(r)
            lit(r, "\\end{verbatim}")
            r_blankline(r)
        }
        ret true
    }
    if kind == tr.K_HTML_BLOCK { ret true }
    if kind == tr.K_THEMATIC {
        if r.man {
            r_cr(r)
            lit(r, ".PP\n  *  *  *  *  *")
            r_cr(r)
        } else {
            r_blankline(r)
            lit(r, "\\begin{center}\\rule{0.5\\linewidth}{\\linethickness}\\end{center}")
            r_blankline(r)
        }
        ret true
    }
    if kind == tr.K_PARAGRAPH {
        if r.man {
            if entering {
                let par = d.nodes[n].parent
                if par != tr.NIL && d.nodes[ix(par)].kind == tr.K_ITEM && d.nodes[n].prev == tr.NIL {
                    // no blank line or .PP
                } else {
                    r_cr(r)
                    lit(r, ".PP")
                    r_cr(r)
                }
            } else {
                r_cr(r)
            }
        } else {
            if !entering { r_blankline(r) }
        }
        ret true
    }
    if kind == tr.K_TEXT {
        r_out(r, d.nodes[n].lit, allow_wrap, ESC_NORMAL)
        ret true
    }
    if kind == tr.K_LINEBREAK {
        if r.man {
            lit(r, ".PD 0\n.P\n.PD")
            r_cr(r)
        } else {
            lit(r, "\\\\")
            r_cr(r)
        }
        ret true
    }
    if kind == tr.K_SOFTBREAK {
        if o.hardbreaks {
            if r.man {
                lit(r, ".PD 0\n.P\n.PD")
                r_cr(r)
            } else {
                lit(r, "\\\\")
                r_cr(r)
            }
        } else {
            if r.width == 0i32 {
                r_cr(r)
            } else {
                if r.man { r_out(r, " ", allow_wrap, ESC_LITERAL) } else { r_out(r, " ", allow_wrap, ESC_NORMAL) }
            }
        }
        ret true
    }
    if kind == tr.K_CODE {
        if r.man {
            lit(r, "\\f[C]")
            r_out(r, d.nodes[n].lit, allow_wrap, ESC_NORMAL)
            lit(r, "\\f[]")
        } else {
            lit(r, "\\texttt{")
            r_out(r, d.nodes[n].lit, false, ESC_NORMAL)
            lit(r, "}")
        }
        ret true
    }
    if kind == tr.K_HTML_INLINE { ret true }
    if kind == tr.K_STRONG {
        let par = d.nodes[n].parent
        if par == tr.NIL || d.nodes[ix(par)].kind != tr.K_STRONG {
            if r.man {
                if entering { lit(r, "\\f[B]") } else { lit(r, "\\f[]") }
            } else {
                if entering { lit(r, "\\textbf{") } else { lit(r, "}") }
            }
        }
        ret true
    }
    if kind == tr.K_EMPH {
        if r.man {
            if entering { lit(r, "\\f[I]") } else { lit(r, "\\f[]") }
        } else {
            if entering { lit(r, "\\emph{") } else { lit(r, "}") }
        }
        ret true
    }
    if kind == tr.K_LINK {
        if r.man {
            if !entering {
                lit(r, " (")
                r_out(r, d.nodes[n].url, allow_wrap, ESC_URL)
                lit(r, ")")
            }
            ret true
        }
        if entering {
            let url = d.nodes[n].url
            let lt = latex_link_type(d, id)
            if lt == 1i32 {
                lit(r, "\\url{")
                r_out(r, url, false, ESC_URL)
                lit(r, "}")
                ret false
            }
            if lt == 2i32 {
                lit(r, "\\href{")
                r_out(r, url, false, ESC_URL)
                lit(r, "}\\nolinkurl{")
            }
            if lt == 3i32 {
                lit(r, "\\href{")
                r_out(r, url, false, ESC_URL)
                lit(r, "}{")
            }
            if lt == 4i32 {
                lit(r, "\\protect\\hyperlink{")
                r_out(r, url[1usize..url.len], false, ESC_URL)
                lit(r, "}{")
            }
            if lt == 0i32 { lit(r, "{") }
        } else {
            lit(r, "}")
        }
        ret true
    }
    if kind == tr.K_IMAGE {
        if r.man {
            if entering { lit(r, "[IMAGE: ") } else { lit(r, "]") }
        } else {
            if entering {
                lit(r, "\\protect\\includegraphics{")
                r_out(r, d.nodes[n].url, false, ESC_URL)
                lit(r, "}")
                ret false
            }
        }
        ret true
    }
    ret true
}

// Text in a table cell escapes `|`: the table extension owns the nearest extension node above it.
fn pipes_escaped(d: *const tr.Doc, id: i32) -> bool {
    let k0 = d.nodes[ix(id)].kind
    if k0 == tr.K_TABLE || k0 == tr.K_ROW || k0 == tr.K_CELL { ret false }
    var t = id
    while t != tr.NIL {
        let k = d.nodes[ix(t)].kind
        if k == tr.K_TABLE || k == tr.K_ROW || k == tr.K_CELL { ret true }
        if k == tr.K_STRIKE || (k == tr.K_ITEM && d.nodes[ix(t)].tasklist) { ret false }
        t = d.nodes[ix(t)].parent
    }
    ret false
}

fn render_generic(a: *mem.Arena, text: str, o: Options, man: bool) -> (str, err) {
    let (d0, pe) = parse_doc(a, text, o)
    if pe != ok { ret ("", pe) }
    var d = d0
    var r: R = zero
    r.b = ct.buf_new(a, text.len * 3usize + 256usize)
    r.width = o.width
    r.begin_line = true
    r.begin_content = true
    r.man = man
    var it = tr.iter_new(d.root)
    while tr.iter_next(&d, &it) {
        r.esc_pipe = pipes_escaped(&d, it.node)
        if !gen_node(&d, &r, it.node, it.enter, &o) { tr.iter_skip(&d, &it) }
    }
    if r.b.n == 0usize || ct.last_byte(&r.b) != 10u8 { ct.putc(&r.b, 10u8) }
    if r.b.failed { ret ("", OutOfMemory) }
    ret (ct.view(&r.b), ok)
}

fn render_latex(a: *mem.Arena, text: str, o: Options) -> (str, err) {
    let (s, e) = render_generic(a, text, o, false)
    ret (s, e)
}

fn render_man(a: *mem.Arena, text: str, o: Options) -> (str, err) {
    let (s, e) = render_generic(a, text, o, true)
    ret (s, e)
}
