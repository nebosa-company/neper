// e.fmt.html4 against R's xml2::read_html (libxml2's HTML 4 parser with recovery): the node dump of
// the tree built for ill-formed markup -- implied html/head/body, paragraphs closed by blocks, list and
// table rows closed by their siblings, unmatched end tags, entities, boolean attributes, whitespace.
// tests/oracle/xml2_html.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R
// xml2_html`. A case holds the markup ("in") and the dump: every node and attribute in document order as
// type, name, string-value and parent element name joined by U+0002, records joined by U+0001 (a CDATA node is text). An
// error on either side is ERR.

use e.fmt.html4 as html4
use e.fmt.xml as xml
use e.fmt.xpath as xp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn put(b: *str.Builder, s: str) {
    if str.push(b, s) != ok { os.exit(11) }
}

fn sepbyte(b: *str.Builder, byte: u8) {
    if str.push_byte(b, byte) != ok { os.exit(12) }
}

fn describe(a: *mem.Arena, b: *str.Builder, d: *const xml.Document, n: xp.XNode) -> err {
    let node = d.nodes[usize(n.id)]
    let (text, text_error) = xp.string_of(a, d, n)
    if text_error != ok { ret text_error }
    var kind = "text"
    var name = "text"
    if n.attribute != 0u32 {
        kind = "attribute"
        let (u, local) = xp.expanded_name(d, n)
        name = local
    } else {
        if node.kind == .Element {
            kind = "element"
            name = node.name
        }
        if node.kind == .Comment {
            kind = "comment"
            name = "comment"
        }
        if node.kind == .Processing {
            kind = "pi"
            name = node.name
        }
    }
    put(b, kind)
    sepbyte(b, 2u8)
    put(b, name)
    sepbyte(b, 2u8)
    put(b, text)
    sepbyte(b, 2u8)
    // The parent element's name (an attribute's is its owner; the document's is empty).
    var owner = node.parent
    if n.attribute != 0u32 { owner = n.id }
    if owner != xml.NONE { put(b, d.nodes[usize(owner)].name) }
    ret ok
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> str {
    let (d, parse_error) = html4.parse(a, c.inputs[0usize])
    if parse_error != ok { ret "ERR" }
    let (v, run_error) = xp.run_libxml2(a, &d, "//node() | //@*", zero)
    if run_error != ok { ret "ERR" }
    if v.kind != xp.Kind.NodeSet { ret "ERR" }
    let (space, space_error) = mem.alloc[u8](a, 262144usize)
    if space_error != ok { os.exit(18) }
    var out = mem.arena_from(space)
    let (b0, be) = str.builder(&out, 131072usize)
    if be != ok { os.exit(17) }
    var b = b0
    var i = 0usize
    while i < v.nodes.len {
        if i > 0usize { sepbyte(&b, 1u8) }
        if describe(a, &b, &d, v.nodes[i]) != ok { ret "ERR" }
        i += 1usize
    }
    ret str.done(&b)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/xml2_html.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let text = answer(a, c)
        if !oracle.agrees_text(text, c) {
            failures += 1usize
            if failures <= 14usize {
                let _ = io.print(c.inputs[0usize])
                let _ = io.print("\n got ")
                let _ = io.print(text)
                let _ = io.print("\n  R  ")
                let _ = io.print(c.text)
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
