// `e.fmt.html`: a document with a DOCTYPE, a comment, head elements, attributes in
// every quoting style with references, named and numeric references in text, an
// unclosed `p` closed by a block, `li` siblings, a table row and cells, a void
// element, a script's raw text, an SVG element self-closed, then serialized and read
// back; an implied `html`/`head`/`body` for a bare fragment; `text_content`; and the
// refusals: invalid UTF-8, a source over the byte limit, too many nodes, nesting past
// the depth. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.str
use e.fmt.html as html

fn options(bytes: usize, nodes: usize, depth: u16, comments: bool) -> html.Options {
    ret html.Options { max_bytes: bytes, max_nodes: nodes, max_attributes: 32usize, max_depth: depth, preserve_comments: comments }
}

// The child elements of `parent` named `name`, counted.
fn count_named(document: *const html.Document, parent: html.NodeId, name: str) -> usize {
    var it = html.children(document, parent)
    var count = 0usize
    while true {
        let (id, more) = html.children_next(&it)
        if !more { break }
        let n = html.node(document, id)
        if n.kind == .Element && str.eq(n.name, name) { count += 1usize }
    }
    ret count
}

fn first_named(document: *const html.Document, parent: html.NodeId, name: str) -> html.NodeId {
    var it = html.children(document, parent)
    while true {
        let (id, more) = html.children_next(&it)
        if !more { break }
        let n = html.node(document, id)
        if n.kind == .Element && str.eq(n.name, name) { ret id }
    }
    ret html.NONE
}

fn main(a: *mem.Arena, args: []str) -> err {
    let source = "<!DOCTYPE html>\n<!-- top -->\n<html lang=en><head><title>T &amp; U</title><meta charset=\"utf-8\"></head>\n<body class='x y' data-v=\"a&quot;b\" flag>\n<p>one &lt;two&gt; &#233;&#x263A; &copy; &notin\n<div>block</div>\n<ul><li>a<li>b</ul>\n<table><tr><td>1<td>2<tr><td>3</table>\n<img src=pic.png alt=\"\">\n<script>if (a < b) { x = \"</p>\"; }</script>\n<svg viewBox=\"0 0 1 1\"><circle r=\"1\"/><rect/></svg>\n</body></html>"
    let (document, e1) = html.parse(a, source, options(65536usize, 256usize, 32u16, true))
    if e1 != ok { os.exit(1) }
    let root = html.node(&document, document.root)
    if root.kind != .Document || document.root != 0u32 { os.exit(2) }
    // Document children: doctype, comment, html.
    var top = html.children(&document, document.root)
    let (doctype_id, has_doctype) = html.children_next(&top)
    if !has_doctype || html.node(&document, doctype_id).kind != .Doctype || !str.eq(html.node(&document, doctype_id).name, "html") { os.exit(3) }
    let (comment_id, has_comment) = html.children_next(&top)
    if !has_comment || html.node(&document, comment_id).kind != .Comment || !str.eq(html.node(&document, comment_id).value, " top ") { os.exit(4) }
    let (html_id, has_html) = html.children_next(&top)
    if !has_html || !str.eq(html.node(&document, html_id).name, "html") { os.exit(5) }
    let (lang, has_lang) = html.attribute(html.node(&document, html_id), "lang")
    if !has_lang || !str.eq(lang, "en") { os.exit(6) }
    let head_id = first_named(&document, html_id, "head")
    let body_id = first_named(&document, html_id, "body")
    if head_id == html.NONE || body_id == html.NONE { os.exit(7) }
    let title_id = first_named(&document, head_id, "title")
    let (title_text, e2) = html.text_content(a, &document, title_id)
    if e2 != ok || !str.eq(title_text, "T & U") { os.exit(8) }
    if count_named(&document, head_id, "meta") != 1usize { os.exit(9) }
    let body = html.node(&document, body_id)
    let (klass, has_class) = html.attribute(body, "class")
    let (data, has_data) = html.attribute(body, "data-v")
    let (flag, has_flag) = html.attribute(body, "flag")
    if !has_class || !str.eq(klass, "x y") || !has_data || !str.eq(data, "a\"b") || !has_flag || flag.len != 0usize { os.exit(10) }
    // The paragraph closed by the div; its references decoded.
    let p_id = first_named(&document, body_id, "p")
    let (p_text, e3) = html.text_content(a, &document, p_id)
    if e3 != ok || !str.eq(p_text, "one <two> \xc3\xa9\xe2\x98\xba \xc2\xa9 \xc2\xacin\n") { os.exit(11) }
    if count_named(&document, p_id, "div") != 0usize || count_named(&document, body_id, "div") != 1usize { os.exit(12) }
    let ul_id = first_named(&document, body_id, "ul")
    if count_named(&document, ul_id, "li") != 2usize { os.exit(13) }
    let table_id = first_named(&document, body_id, "table")
    if count_named(&document, table_id, "tr") != 2usize { os.exit(14) }
    let tr_id = first_named(&document, table_id, "tr")
    if count_named(&document, tr_id, "td") != 2usize { os.exit(15) }
    let img_id = first_named(&document, body_id, "img")
    let (src, has_src) = html.attribute(html.node(&document, img_id), "src")
    if !has_src || !str.eq(src, "pic.png") || html.node(&document, img_id).first_child != html.NONE { os.exit(16) }
    let script_id = first_named(&document, body_id, "script")
    let (script_text, e4) = html.text_content(a, &document, script_id)
    if e4 != ok || !str.eq(script_text, "if (a < b) { x = \"</p>\"; }") { os.exit(17) }
    let svg_id = first_named(&document, body_id, "svg")
    if html.node(&document, svg_id).namespace != .Svg || count_named(&document, svg_id, "circle") != 1usize || count_named(&document, svg_id, "rect") != 1usize { os.exit(18) }
    if html.node(&document, first_named(&document, svg_id, "rect")).namespace != .Svg { os.exit(19) }
    // Serialize and read back.
    let (buffer, b_error) = mem.alloc[u8](a, 4096usize)
    if b_error != ok { os.exit(20) }
    var sink_state = io.SliceWriter { data: buffer, off: 0usize }
    var sink = io.slice_writer(&sink_state)
    if html.write(&sink, &document) != ok { os.exit(21) }
    let written = buffer[..sink_state.off]
    if !str.starts_with(written, "<!DOCTYPE html><!-- top --><html lang=\"en\"><head><title>T &amp; U</title><meta charset=\"utf-8\"></head>") { os.exit(22) }
    if !str.contains(written, "<body class=\"x y\" data-v=\"a&quot;b\" flag=\"\">") || !str.contains(written, "<img src=\"pic.png\" alt=\"\">") || !str.contains(written, "<script>if (a < b) { x = \"</p>\"; }</script>") { os.exit(23) }
    let (again, e5) = html.parse(a, written, options(65536usize, 256usize, 32u16, true))
    if e5 != ok || again.nodes.len != document.nodes.len { os.exit(24) }
    // A bare fragment gets its structure.
    let (fragment, e6) = html.parse(a, "just <b>text</b>", options(1024usize, 64usize, 8u16, false))
    if e6 != ok { os.exit(25) }
    let f_html = first_named(&fragment, fragment.root, "html")
    let f_body = first_named(&fragment, f_html, "body")
    if f_html == html.NONE || first_named(&fragment, f_html, "head") == html.NONE || f_body == html.NONE { os.exit(26) }
    let (f_text, e7) = html.text_content(a, &fragment, f_body)
    if e7 != ok || !str.eq(f_text, "just text") || count_named(&fragment, f_body, "b") != 1usize { os.exit(27) }
    // Refusals.
    let (bad_utf8, e8) = html.parse(a, "<p>\xff</p>", options(1024usize, 64usize, 8u16, false))
    if e8 != html.InvalidEncoding { os.exit(28) }
    let (too_big, e9) = html.parse(a, source, options(100usize, 256usize, 32u16, false))
    if e9 != html.TooLarge { os.exit(29) }
    let (too_many, e10) = html.parse(a, source, options(65536usize, 8usize, 32u16, false))
    if e10 != html.TooLarge { os.exit(30) }
    let (too_deep, e11) = html.parse(a, "<div><div><div><div><span>x</span></div></div></div></div>", options(1024usize, 64usize, 4u16, false))
    if e11 != html.TooDeep { os.exit(31) }
    ret ok
}
