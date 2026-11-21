// e.fmt.xml + e.fmt.xpath against R's xml2 (libxml2's XPath 1.0): node-sets, numbers, strings and
// booleans over documents with namespaces, entities, CDATA, comments and processing instructions.
// tests/oracle/xml2.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R xml2`. A
// case holds the document and the expression ("in") and R's answer as text (see the group file); the
// XPath prefixes are the ones xml2's xml_ns() names: a default namespace is d1, d2 ..., a declared
// prefix is itself. An error on either side is ERR.

use e.fmt.xml as xml
use e.fmt.xpath as xp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn put(b: *str.Builder, s: str) {
    let e = str.push(b, s)
    if e != ok {
        let _ = io.print("put failed: ")
        let _ = io.print(s)
        let _ = io.print("\n")
        os.exit(11)
    }
}

fn sepbyte(b: *str.Builder, byte: u8) {
    if str.push_byte(b, byte) != ok { os.exit(12) }
}

// xml_ns(): every xmlns declaration in document order, a default one named d<k>.
fn bindings_of(a: *mem.Arena, d: *const xml.Document) -> []xp.Binding {
    let (out, out_error) = mem.alloc[xp.Binding](a, 8usize)
    if out_error != ok { os.exit(13) }
    var used = 0usize
    var defaults = 0usize
    var i = 0usize
    while i < d.nodes.len {
        if d.nodes[i].kind == .Element {
            var k = 0usize
            while k < d.nodes[i].attributes.len {
                let attribute = d.nodes[i].attributes[k]
                var prefix = ""
                var found = false
                if str.eq(attribute.name, "xmlns") {
                    found = true
                    defaults += 1usize
                    let (b0, be) = str.builder(a, 64usize)
                    if be != ok { os.exit(14) }
                    var b = b0
                    put(&b, "d")
                    if str.push_usize(&b, defaults) != ok { os.exit(15) }
                    prefix = str.done(&b)
                }
                if str.starts_with(attribute.name, "xmlns:") {
                    found = true
                    prefix = attribute.name[6usize..]
                }
                if found && used < 8usize {
                    var seen = false
                    var j = 0usize
                    while j < used {
                        if str.eq(out[j].prefix, prefix) { seen = true }
                        j += 1usize
                    }
                    if !seen {
                        out[used] = xp.Binding { prefix: prefix, uri: attribute.value }
                        used += 1usize
                    }
                }
                k += 1usize
            }
        }
        i += 1usize
    }
    ret out[..used]
}

fn hex64(b: *str.Builder, bits: u64) {
    var shift = 60u64
    var n = 0usize
    while n < 16usize {
        let nibble = u8((bits >> shift) & 15u64)
        var c = 48u8 + nibble
        if nibble > 9u8 { c = 87u8 + nibble }
        if str.push_byte(b, c) != ok { os.exit(16) }
        if shift >= 4u64 { shift -= 4u64 }
        n += 1usize
    }
}

// One node as xml2 reports it: type, local name, namespace URI and string-value.
fn describe(a: *mem.Arena, b: *str.Builder, d: *const xml.Document, n: xp.XNode) -> err {
    let node = d.nodes[usize(n.id)]
    let (text, text_error) = xp.string_of(a, d, n)
    if text_error != ok { ret text_error }
    var kind = "text"
    var name = "text"
    var uri = ""
    if n.attribute != 0u32 {
        kind = "attribute"
        let (u, local) = xp.expanded_name(d, n)
        name = local
        uri = u
    } else {
        if node.kind == .Element {
            kind = "element"
            let (u, local) = xp.expanded_name(d, n)
            name = local
            uri = u
        }
        if node.kind == .Comment {
            kind = "comment"
            name = "comment"
        }
        if node.kind == .Processing {
            kind = "pi"
            name = node.name
        }
        if node.kind == .Document {
            kind = "document"
            name = ""
        }
    }
    put(b, kind)
    sepbyte(b, 2u8)
    put(b, name)
    sepbyte(b, 2u8)
    put(b, uri)
    sepbyte(b, 2u8)
    put(b, text)
    ret ok
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> str {
    let (d, parse_error) = xml.parse_noblanks(a, c.inputs[0usize])
    if parse_error != ok { ret "ERR" }
    let bindings = bindings_of(a, &d)
    let (v, run_error) = xp.run_libxml2(a, &d, c.inputs[1usize], bindings)
    if run_error != ok {
        // xml_find_all swallows an XPath error as an empty node-set; the typed finders raise it.
        if str.eq(c.name, "nodes") { ret "" }
        ret "ERR"
    }
    // The record is built in an arena of its own: evaluating allocates from `a` meanwhile.
    let (space, space_error) = mem.alloc[u8](a, 262144usize)
    if space_error != ok { os.exit(18) }
    var out = mem.arena_from(space)
    let (b0, be) = str.builder(&out, 131072usize)
    if be != ok { os.exit(17) }
    var b = b0
    if str.eq(c.name, "nodes") {
        if v.kind != xp.Kind.NodeSet { ret "ERR" }
        var i = 0usize
        while i < v.nodes.len {
            if i > 0usize { sepbyte(&b, 1u8) }
            if describe(a, &b, &d, v.nodes[i]) != ok { ret "ERR" }
            i += 1usize
        }
        ret str.done(&b)
    }
    if str.eq(c.name, "num") {
        if v.kind != xp.Kind.Number { ret "ERR" }
        if v.number != v.number { ret "NaN" }
        hex64(&b, mem.bitcast[u64](v.number))
        ret str.done(&b)
    }
    if str.eq(c.name, "chr") {
        if v.kind != xp.Kind.String { ret "ERR" }
        ret v.text
    }
    if v.kind != xp.Kind.Boolean { ret "ERR" }
    if v.flag { ret "TRUE" }
    ret "FALSE"
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/xml2.json")
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
                let _ = io.print(c.name)
                let _ = io.print(" ")
                if str.starts_with(c.inputs[1usize], "//node()") { let _ = io.print(c.inputs[0usize]) } else { let _ = io.print(c.inputs[1usize]) }
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
