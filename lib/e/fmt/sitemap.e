// Sitemaps (sitemaps.org protocol 0.9): read a `urlset` or `sitemapindex` XML document, or a
// plain-text sitemap (one URL per line), into a list of entries; write either XML form.
//
// Reading. Element names are matched by local name, so a prefixed or default namespace is
// fine; elements of extension namespaces (image, video, news, xhtml) and unknown children
// are skipped. Per entry: `loc` is required, non-empty and at most 2048 bytes;
// `lastmod`, `changefreq` and `priority` are kept as the text written, with `changefreq`
// one of always hourly daily weekly monthly yearly never and `priority` a decimal in
// 0.0..1.0 (anything else is `Invalid`). At most 50000 entries (`TooMany`). Entity
// references and CDATA are decoded by `e.fmt.xml`.
//
// Writing. `write_urlset` and `write_index` emit the XML declaration and the `0.9`
// namespace, escaping text; the same limits and value checks apply (`TooMany`, `Invalid`).

use e.io
use e.mem
use e.fmt.xml as xml

type Entry = struct { loc: str, lastmod: str, changefreq: str, priority: str }
type Sitemap = struct { entries: []Entry, index: bool }
error Invalid
error TooMany

const MAX_ENTRIES: usize = 50000usize
const MAX_LOC: usize = 2048usize

fn local(name: str) -> str {
    var i = name.len
    while i > 0usize {
        if name[i - 1usize] == 58u8 { ret name[i..name.len] }
        i -= 1usize
    }
    ret name
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 }

fn trim(s: str) -> str {
    var a = 0usize
    var b = s.len
    while a < b && is_space(s[a]) { a += 1usize }
    while b > a && is_space(s[b - 1usize]) { b -= 1usize }
    ret s[a..b]
}

fn valid_changefreq(s: str) -> bool {
    ret same(s, "always") || same(s, "hourly") || same(s, "daily") || same(s, "weekly") || same(s, "monthly") || same(s, "yearly") || same(s, "never")
}

// `0`, `1`, `0.5`, `1.0`, `.25`: a decimal in [0, 1].
fn valid_priority(s: str) -> bool {
    if s.len == 0usize { ret false }
    var whole = 0usize
    var i = 0usize
    var digits = 0usize
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        whole = whole * 10usize + usize(s[i] - 48u8)
        if whole > 1usize { ret false }
        digits += 1usize
        i += 1usize
    }
    var frac_nonzero = false
    var frac_digits = 0usize
    if i < s.len {
        if s[i] != 46u8 { ret false }
        i += 1usize
        while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
            if s[i] != 48u8 { frac_nonzero = true }
            frac_digits += 1usize
            i += 1usize
        }
        if i != s.len { ret false }
    }
    if digits == 0usize && frac_digits == 0usize { ret false }
    if whole == 1usize && frac_nonzero { ret false }
    ret true
}

fn check_entry(e: Entry) -> err {
    if e.loc.len == 0usize || e.loc.len > MAX_LOC { ret Invalid }
    if e.changefreq.len > 0usize && !valid_changefreq(e.changefreq) { ret Invalid }
    if e.priority.len > 0usize && !valid_priority(e.priority) { ret Invalid }
    ret ok
}

// Concatenated text children of an element node.
fn element_text(a: *mem.Arena, doc: *const xml.Document, id: u32) -> (str, err) {
    var total = 0usize
    var child = doc.nodes[usize(id)].first_child
    while child != xml.NONE {
        if doc.nodes[usize(child)].kind == .Text { total += doc.nodes[usize(child)].value.len }
        child = doc.nodes[usize(child)].next_sibling
    }
    // one text node is the common case and is returned without copying
    child = doc.nodes[usize(id)].first_child
    if child != xml.NONE && doc.nodes[usize(child)].next_sibling == xml.NONE && doc.nodes[usize(child)].kind == .Text { ret (trim(doc.nodes[usize(child)].value), ok) }
    if total == 0usize { ret ("", ok) }
    let (buf, alloc_error) = mem.alloc[u8](a, total)
    if alloc_error != ok { ret ("", alloc_error) }
    var n = 0usize
    child = doc.nodes[usize(id)].first_child
    while child != xml.NONE {
        if doc.nodes[usize(child)].kind == .Text {
            let v = doc.nodes[usize(child)].value
            var k = 0usize
            while k < v.len {
                buf[n + k] = v[k]
                k += 1usize
            }
            n += v.len
        }
        child = doc.nodes[usize(child)].next_sibling
    }
    ret (trim(buf[0usize..n]), ok)
}

fn parse(a: *mem.Arena, source: []const u8) -> (Sitemap, err) {
    var out: Sitemap = zero
    let (doc, parse_error) = xml.parse(a, source)
    if parse_error != ok { ret (out, Invalid) }
    let root = doc.root
    if root == xml.NONE { ret (out, Invalid) }
    let root_name = local(doc.nodes[usize(root)].name)
    var entry_name = "url"
    if same(root_name, "sitemapindex") {
        out.index = true
        entry_name = "sitemap"
    } else if !same(root_name, "urlset") {
        ret (out, Invalid)
    }
    var count = 0usize
    var child = doc.nodes[usize(root)].first_child
    while child != xml.NONE {
        if doc.nodes[usize(child)].kind == .Element && same(local(doc.nodes[usize(child)].name), entry_name) { count += 1usize }
        child = doc.nodes[usize(child)].next_sibling
    }
    if count > MAX_ENTRIES { ret (out, TooMany) }
    let (entries, entries_error) = mem.alloc[Entry](a, count + 1usize)
    if entries_error != ok { ret (out, entries_error) }
    var n = 0usize
    child = doc.nodes[usize(root)].first_child
    while child != xml.NONE {
        if doc.nodes[usize(child)].kind == .Element && same(local(doc.nodes[usize(child)].name), entry_name) {
            var e: Entry = zero
            var field = doc.nodes[usize(child)].first_child
            while field != xml.NONE {
                if doc.nodes[usize(field)].kind == .Element {
                    let name = local(doc.nodes[usize(field)].name)
                    let (text, text_error) = element_text(a, &doc, field)
                    if text_error != ok { ret (out, text_error) }
                    if same(name, "loc") {
                        e.loc = text
                    } else if same(name, "lastmod") {
                        e.lastmod = text
                    } else if same(name, "changefreq") {
                        e.changefreq = text
                    } else if same(name, "priority") {
                        e.priority = text
                    }
                }
                field = doc.nodes[usize(field)].next_sibling
            }
            if check_entry(e) != ok { ret (out, Invalid) }
            entries[n] = e
            n += 1usize
        }
        child = doc.nodes[usize(child)].next_sibling
    }
    out.entries = entries[0usize..n]
    ret (out, ok)
}

// Plain-text sitemap: one absolute URL per line, blank lines skipped, UTF-8.
fn parse_text(a: *mem.Arena, source: []const u8) -> (Sitemap, err) {
    var out: Sitemap = zero
    var lines = 1usize
    var i = 0usize
    while i < source.len {
        if source[i] == 10u8 { lines += 1usize }
        i += 1usize
    }
    let (entries, entries_error) = mem.alloc[Entry](a, lines)
    if entries_error != ok { ret (out, entries_error) }
    var n = 0usize
    var start = 0usize
    i = 0usize
    while i <= source.len {
        if i == source.len || source[i] == 10u8 {
            let line = trim(source[start..i])
            if line.len > 0usize {
                if n >= MAX_ENTRIES { ret (out, TooMany) }
                if line.len > MAX_LOC { ret (out, Invalid) }
                var e: Entry = zero
                e.loc = line
                entries[n] = e
                n += 1usize
            }
            start = i + 1usize
        }
        i += 1usize
    }
    out.entries = entries[0usize..n]
    ret (out, ok)
}

fn leaf(w: *xml.Writer, name: str, value: str) -> err {
    var none: [0]xml.Attribute = zero
    try xml.start(w, name, none[0usize..0usize])
    try xml.text(w, value)
    ret xml.end(w, name)
}

fn write_document(sink: io.Writer, entries: []const Entry, index: bool) -> err {
    if entries.len > MAX_ENTRIES { ret TooMany }
    var i = 0usize
    while i < entries.len {
        try check_entry(entries[i])
        i += 1usize
    }
    var out = sink
    try io.write_all(&out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
    var w = xml.writer(sink)
    var root = "urlset"
    var item = "url"
    if index {
        root = "sitemapindex"
        item = "sitemap"
    }
    var attrs: [1]xml.Attribute = zero
    attrs[0usize] = xml.Attribute { name: "xmlns", value: "http://www.sitemaps.org/schemas/sitemap/0.9" }
    try xml.start(&w, root, attrs[0usize..1usize])
    var none: [0]xml.Attribute = zero
    i = 0usize
    while i < entries.len {
        try xml.start(&w, item, none[0usize..0usize])
        try leaf(&w, "loc", entries[i].loc)
        if entries[i].lastmod.len > 0usize { try leaf(&w, "lastmod", entries[i].lastmod) }
        if !index && entries[i].changefreq.len > 0usize { try leaf(&w, "changefreq", entries[i].changefreq) }
        if !index && entries[i].priority.len > 0usize { try leaf(&w, "priority", entries[i].priority) }
        try xml.end(&w, item)
        i += 1usize
    }
    try xml.end(&w, root)
    ret ok
}

fn write_urlset(sink: io.Writer, entries: []const Entry) -> err { ret write_document(sink, entries, false) }

fn write_index(sink: io.Writer, entries: []const Entry) -> err { ret write_document(sink, entries, true) }
