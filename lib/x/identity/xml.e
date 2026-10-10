// A small XML reader and exclusive canonicalizer for SAML (L045), after Appdor's `src/identity/xml.js`: elements,
// attributes, namespaces, text, CDATA, comments and the declaration -- no DTD and no entity declarations, so there is
// nothing to expand. `parse_xml` keeps the element children and, apart, every text and element node in document order
// (whitespace included, which a digest needs); `resolve_namespace` walks up the tree; `find_elements`/`find_by_id`
// find by namespace and local name or by `ID`; `canonicalize` is Exclusive XML Canonicalization 1.0 for the shapes
// XML-DSig produces, comments dropped and a QName in an attribute value preserved only for `*type` attributes.
//
// ponytail: an error offset is counted in UTF-16 code units as the reference counts it, but a numeric character
// reference past U+10FFFF is kept as written where the reference throws.
//
// Memory: the arena is retained; the tree lives in it.

use e.algo.formula as f
use e.algo.formula.text as tx
use e.mem
use e.str
use e.text.utf8 as utf8

type Entry = struct { is_text: bool, text: str, node: usize }

type Node = struct { name: str, prefix: str, local: str, attr_names: []const str, attr_values: []const str, ns_prefixes: []const str, ns_uris: []const str, children: []const usize, entries: []const Entry, text: str, parent: i64 }

type Doc = struct { valid: bool, message: str, nodes: []Node, root: usize }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn is_name_start(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 || c == 58u8 }

fn is_name_char(c: u8) -> bool { ret is_name_start(c) || (c >= 48u8 && c <= 57u8) || c == 45u8 || c == 46u8 }

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 || c == 11u8 || c == 12u8 }

fn starts_at(s: str, at: usize, prefix: str) -> bool {
    if at + prefix.len > s.len { ret false }
    ret str.eq(s[at..at + prefix.len], prefix)
}

fn find_from(s: str, needle: str, from: usize) -> (usize, bool) {
    var i = from
    while i + needle.len <= s.len {
        if str.eq(s[i..i + needle.len], needle) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// A text with no code point JavaScript's `trim` would keep.
fn blank_text(s: str) -> bool {
    var it = utf8.iterator(s)
    while true {
        let (scalar, got) = utf8.iterator_next(&it)
        if !got { break }
        if !tx.js_space(scalar) { ret false }
    }
    ret true
}

fn js_trim(s: str) -> str {
    var from = 0usize
    var to = s.len
    while from < to && is_space(s[from]) { from += 1usize }
    while to > from && is_space(s[to - 1usize]) { to -= 1usize }
    ret s[from..to]
}

// The offset the reference reports: UTF-16 code units before byte `at`.
fn utf16_offset(s: str, at: usize) -> usize {
    var n = 0usize
    var i = 0usize
    while i < at && i < s.len {
        let c = s[i]
        if c < 128u8 {
            n += 1usize
        } else if (c & 192u8) != 128u8 {
            if c >= 240u8 {
                n += 2usize
            } else {
                n += 1usize
            }
        }
        i += 1usize
    }
    ret n
}

fn push_scalar(buf: []u8, at: usize, code: u32) -> usize {
    if code < 128u32 {
        buf[at] = u8(code)
        ret at + 1usize
    }
    if code < 2048u32 {
        buf[at] = u8(192u32 | (code >> 6u32))
        buf[at + 1usize] = u8(128u32 | (code & 63u32))
        ret at + 2usize
    }
    if code < 65536u32 {
        buf[at] = u8(224u32 | (code >> 12u32))
        buf[at + 1usize] = u8(128u32 | ((code >> 6u32) & 63u32))
        buf[at + 2usize] = u8(128u32 | (code & 63u32))
        ret at + 3usize
    }
    buf[at] = u8(240u32 | (code >> 18u32))
    buf[at + 1usize] = u8(128u32 | ((code >> 12u32) & 63u32))
    buf[at + 2usize] = u8(128u32 | ((code >> 6u32) & 63u32))
    buf[at + 3usize] = u8(128u32 | (code & 63u32))
    ret at + 4usize
}

fn hex_digit_value(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c) - 48i32 }
    if c >= 97u8 && c <= 102u8 { ret i32(c) - 87i32 }
    if c >= 65u8 && c <= 70u8 { ret i32(c) - 55i32 }
    ret -1i32
}

// The five predefined entities and numeric character references; anything else stays as written.
fn decode_entities(a: *mem.Arena, s: str) -> str {
    if !str.contains(s, "&") { ret s }
    let (out, e) = mem.alloc[u8](a, s.len + 8usize)
    if e != ok { ret s }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] != 38u8 {
            out[n] = s[i]
            n += 1usize
            i += 1usize
            continue
        }
        // `&` then `#x?[0-9a-fA-F]+` or `[a-zA-Z]+`, then `;`
        var j = i + 1usize
        var handled = false
        if j < s.len && s[j] == 35u8 {
            j += 1usize
            var hex = false
            if j < s.len && s[j] == 120u8 {
                hex = true
                j += 1usize
            }
            let from = j
            while j < s.len && hex_digit_value(s[j]) >= 0i32 { j += 1usize }
            if j > from && j < s.len && s[j] == 59u8 {
                var code = 0u64
                var valid = false
                var k = from
                if hex {
                    valid = true
                    while k < j && code < 4294967296u64 {
                        code = code * 16u64 + u64(hex_digit_value(s[k]))
                        k += 1usize
                    }
                } else {
                    // parseInt(digits, 10) reads the leading decimal digits
                    while k < j && s[k] >= 48u8 && s[k] <= 57u8 && code < 4294967296u64 {
                        code = code * 10u64 + u64(s[k] - 48u8)
                        k += 1usize
                        valid = true
                    }
                }
                if valid && code <= 1114111u64 && !(code >= 55296u64 && code <= 57343u64) {
                    n = push_scalar(out, n, u32(code))
                    i = j + 1usize
                    handled = true
                }
            }
        } else {
            let from = j
            while j < s.len && ((s[j] >= 65u8 && s[j] <= 90u8) || (s[j] >= 97u8 && s[j] <= 122u8)) { j += 1usize }
            if j > from && j < s.len && s[j] == 59u8 {
                let name = s[from..j]
                var rep = 0u8
                if str.eq(name, "lt") { rep = 60u8 }
                if str.eq(name, "gt") { rep = 62u8 }
                if str.eq(name, "amp") { rep = 38u8 }
                if str.eq(name, "quot") { rep = 34u8 }
                if str.eq(name, "apos") { rep = 39u8 }
                if rep != 0u8 {
                    out[n] = rep
                    n += 1usize
                    i = j + 1usize
                    handled = true
                }
            }
        }
        if !handled {
            out[n] = 38u8
            n += 1usize
            i += 1usize
        }
    }
    ret out[0usize..n]
}

fn escape_text(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len * 5usize + 1usize)
    if e != ok { ret s }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        var rep = ""
        if c == 38u8 { rep = "&amp;" }
        if c == 60u8 { rep = "&lt;" }
        if c == 62u8 { rep = "&gt;" }
        if c == 13u8 { rep = "&#xD;" }
        if rep.len == 0usize {
            out[n] = c
            n += 1usize
        } else {
            var k = 0usize
            while k < rep.len {
                out[n] = rep[k]
                n += 1usize
                k += 1usize
            }
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn escape_attribute(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len * 6usize + 1usize)
    if e != ok { ret s }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        var rep = ""
        if c == 38u8 { rep = "&amp;" }
        if c == 60u8 { rep = "&lt;" }
        if c == 34u8 { rep = "&quot;" }
        if c == 9u8 { rep = "&#x9;" }
        if c == 10u8 { rep = "&#xA;" }
        if c == 13u8 { rep = "&#xD;" }
        if rep.len == 0usize {
            out[n] = c
            n += 1usize
        } else {
            var k = 0usize
            while k < rep.len {
                out[n] = rep[k]
                n += 1usize
                k += 1usize
            }
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn bad(a: *mem.Arena, source: str, at: usize, message: str) -> Doc {
    let none: []Node = zero
    let shown = join(a, join(a, message, " at offset "), f.number_text(a, f64(utf16_offset(source, at))))
    ret Doc { valid: false, message: shown, nodes: none, root: 0usize }
}

fn bare(message: str) -> Doc {
    let none: []Node = zero
    ret Doc { valid: false, message: message, nodes: none, root: 0usize }
}

// Parses a document; `valid` false carries the reference's message.
fn parse_xml(a: *mem.Arena, source: str) -> Doc {
    var lt = 1usize
    var q = 0usize
    while q < source.len {
        if source[q] == 60u8 { lt += 1usize }
        q += 1usize
    }
    let cap = lt + 1usize
    let (nodes, ne) = mem.alloc[Node](a, cap)
    if ne != ok { ret bare("out of memory") }
    let (stack, se) = mem.alloc[usize](a, cap)
    if se != ok { ret bare("out of memory") }
    let ent_cap = cap * 2usize + 2usize
    let (ent_parent, e1) = mem.alloc[usize](a, ent_cap)
    let (ent_is_text, e2) = mem.alloc[bool](a, ent_cap)
    let (ent_text, e3) = mem.alloc[str](a, ent_cap)
    let (ent_node, e4) = mem.alloc[usize](a, ent_cap)
    let (texts, e5) = mem.alloc[str](a, cap)
    let attr_cap = source.len / 2usize + 2usize
    let (an_s, e6) = mem.alloc[str](a, attr_cap)
    let (av_s, e7) = mem.alloc[str](a, attr_cap)
    let (np_s, e8) = mem.alloc[str](a, attr_cap)
    let (nu_s, e9) = mem.alloc[str](a, attr_cap)
    var count = 0usize
    var depth = 0usize
    var ents = 0usize
    var have_root = false
    var root = 0usize
    var i = 0usize
    while i < source.len {
        if source[i] != 60u8 {
            let start = i
            while i < source.len && source[i] != 60u8 { i += 1usize }
            let chunk = source[start..i]
            if depth > 0usize {
                let parent = stack[depth - 1usize]
                let decoded = decode_entities(a, chunk)
                ent_parent[ents] = parent
                ent_is_text[ents] = true
                ent_text[ents] = decoded
                ent_node[ents] = 0usize
                ents += 1usize
                if !blank_text(chunk) { texts[parent] = join(a, texts[parent], decoded) }
            }
            continue
        }
        if starts_at(source, i, "<?") {
            let (end, found) = find_from(source, "?>", i)
            if !found { ret bad(a, source, i, "unterminated processing instruction") }
            i = end + 2usize
            continue
        }
        if starts_at(source, i, "<!--") {
            let (end, found) = find_from(source, "-->", i)
            if !found { ret bad(a, source, i, "unterminated comment") }
            i = end + 3usize
            continue
        }
        if starts_at(source, i, "<![CDATA[") {
            let (end, found) = find_from(source, "]]>", i)
            if !found { ret bad(a, source, i, "unterminated CDATA") }
            let chunk = source[i + 9usize..end]
            if depth > 0usize {
                let parent = stack[depth - 1usize]
                ent_parent[ents] = parent
                ent_is_text[ents] = true
                ent_text[ents] = chunk
                ent_node[ents] = 0usize
                ents += 1usize
                texts[parent] = join(a, texts[parent], chunk)
            }
            i = end + 3usize
            continue
        }
        if starts_at(source, i, "<!") {
            let (end, found) = find_from(source, ">", i)
            if !found { ret bad(a, source, i, "unterminated declaration") }
            i = end + 1usize
            continue
        }
        if i + 1usize < source.len && source[i + 1usize] == 47u8 {
            let (end, found) = find_from(source, ">", i)
            if !found { ret bad(a, source, i, "unterminated end tag") }
            let name = js_trim(source[i + 2usize..end])
            if depth == 0usize { ret bad(a, source, i, join(a, join(a, "end tag </", name), "> with no open element")) }
            let open = stack[depth - 1usize]
            depth -= 1usize
            if !str.eq(nodes[open].name, name) {
                ret bad(a, source, i, join(a, join(a, join(a, "end tag </", name), "> does not match <"), join(a, nodes[open].name, ">")))
            }
            i = end + 1usize
            continue
        }
        // start tag
        i += 1usize
        let name_start = i
        if i >= source.len || !is_name_start(source[i]) { ret bad(a, source, i, "expected element name") }
        while i < source.len && is_name_char(source[i]) { i += 1usize }
        let name = source[name_start..i]
        var attrs = 0usize
        var nss = 0usize
        var stop = false
        while i < source.len && !stop {
            while i < source.len && is_space(source[i]) { i += 1usize }
            if i < source.len && (source[i] == 62u8 || starts_at(source, i, "/>")) { break }
            let attr_start = i
            while i < source.len && is_name_char(source[i]) { i += 1usize }
            let attr_name = source[attr_start..i]
            if attr_name.len == 0usize { ret bad(a, source, i, "expected attribute name") }
            while i < source.len && is_space(source[i]) { i += 1usize }
            if i >= source.len || source[i] != 61u8 { ret bad(a, source, i, join(a, join(a, "attribute ", attr_name), " has no value")) }
            i += 1usize
            while i < source.len && is_space(source[i]) { i += 1usize }
            if i >= source.len || (source[i] != 34u8 && source[i] != 39u8) {
                ret bad(a, source, i, join(a, join(a, "attribute ", attr_name), " value is not quoted"))
            }
            let quote = source[i]
            i += 1usize
            let value_start = i
            while i < source.len && source[i] != quote { i += 1usize }
            let value = decode_entities(a, source[value_start..i])
            i += 1usize
            if str.eq(attr_name, "xmlns") {
                np_s[nss] = ""
                nu_s[nss] = value
                nss += 1usize
            } else if str.starts_with(attr_name, "xmlns:") {
                np_s[nss] = attr_name[6usize..]
                nu_s[nss] = value
                nss += 1usize
            } else {
                an_s[attrs] = attr_name
                av_s[attrs] = value
                attrs += 1usize
            }
        }
        var self_closing = false
        if starts_at(source, i, "/>") { self_closing = true }
        if self_closing {
            i += 2usize
        } else {
            i += 1usize
        }
        var colon = -1i64
        var k = 0usize
        while k < name.len {
            if name[k] == 58u8 {
                colon = i64(k)
                break
            }
            k += 1usize
        }
        var prefix = ""
        var local = name
        if colon >= 0i64 {
            prefix = name[0usize..usize(colon)]
            local = name[usize(colon) + 1usize..]
        }
        let (an, ea) = mem.alloc[str](a, attrs + 1usize)
        let (av, eb) = mem.alloc[str](a, attrs + 1usize)
        let (np, ec) = mem.alloc[str](a, nss + 1usize)
        let (nu, ed) = mem.alloc[str](a, nss + 1usize)
        var c = 0usize
        while c < attrs {
            an[c] = an_s[c]
            av[c] = av_s[c]
            c += 1usize
        }
        c = 0usize
        while c < nss {
            np[c] = np_s[c]
            nu[c] = nu_s[c]
            c += 1usize
        }
        var parent = -1i64
        if depth > 0usize { parent = i64(stack[depth - 1usize]) }
        let none_children: []const usize = zero
        let none_entries: []const Entry = zero
        let index = count
        nodes[index] = Node {
            name: name,
            prefix: prefix,
            local: local,
            attr_names: an[0usize..attrs],
            attr_values: av[0usize..attrs],
            ns_prefixes: np[0usize..nss],
            ns_uris: nu[0usize..nss],
            children: none_children,
            entries: none_entries,
            text: "",
            parent: parent,
        }
        texts[index] = ""
        count += 1usize
        if depth > 0usize {
            ent_parent[ents] = stack[depth - 1usize]
            ent_is_text[ents] = false
            ent_text[ents] = ""
            ent_node[ents] = index
            ents += 1usize
        } else if have_root {
            ret bad(a, source, i, "more than one root element")
        } else {
            root = index
            have_root = true
        }
        if !self_closing {
            stack[depth] = index
            depth += 1usize
        }
    }
    if depth > 0usize {
        ret bare(join(a, join(a, "unclosed element <", nodes[stack[depth - 1usize]].name), ">"))
    }
    if !have_root { ret bare("no root element") }
    // Attach the text and the children and entries lists, in document order.
    var n = 0usize
    while n < count {
        nodes[n].text = texts[n]
        var ce = 0usize
        var ee = 0usize
        var z = 0usize
        while z < ents {
            if ent_parent[z] == n {
                ee += 1usize
                if !ent_is_text[z] { ce += 1usize }
            }
            z += 1usize
        }
        let (ch, ca) = mem.alloc[usize](a, ce + 1usize)
        let (en, cb) = mem.alloc[Entry](a, ee + 1usize)
        var ci = 0usize
        var ei = 0usize
        z = 0usize
        while z < ents {
            if ent_parent[z] == n {
                en[ei] = Entry { is_text: ent_is_text[z], text: ent_text[z], node: ent_node[z] }
                ei += 1usize
                if !ent_is_text[z] {
                    ch[ci] = ent_node[z]
                    ci += 1usize
                }
            }
            z += 1usize
        }
        nodes[n].children = ch[0usize..ce]
        nodes[n].entries = en[0usize..ee]
        n += 1usize
    }
    ret Doc { valid: true, message: "", nodes: nodes[0usize..count], root: root }
}

// The attribute's value (the last of that name), or false.
fn attribute_of(n: Node, name: str) -> (str, bool) {
    var i = n.attr_names.len
    while i > 0usize {
        if str.eq(n.attr_names[i - 1usize], name) { ret (n.attr_values[i - 1usize], true) }
        i -= 1usize
    }
    ret ("", false)
}

// A prefix resolved by walking up from `at`; false when no ancestor declares it.
fn resolve_namespace(d: Doc, at: usize, prefix: str) -> (str, bool) {
    var cur = i64(at)
    while cur >= 0i64 {
        let n = d.nodes[usize(cur)]
        var i = n.ns_prefixes.len
        while i > 0usize {
            if str.eq(n.ns_prefixes[i - 1usize], prefix) { ret (n.ns_uris[i - 1usize], true) }
            i -= 1usize
        }
        cur = n.parent
    }
    ret ("", false)
}

fn collect(d: Doc, at: usize, ns: str, local: str, out: []usize, n: *usize) {
    let node = d.nodes[at]
    let (uri, found) = resolve_namespace(d, at, node.prefix)
    var ns_ok = ns.len == 0usize
    if !ns_ok && found && str.eq(uri, ns) { ns_ok = true }
    if ns_ok && str.eq(node.local, local) {
        out[*n] = at
        *n += 1usize
    }
    var i = 0usize
    while i < node.children.len {
        collect(d, node.children[i], ns, local, out, n)
        i += 1usize
    }
}

// Every element in the subtree at `at` (itself included) with that namespace (empty: any) and local name.
fn find_elements(a: *mem.Arena, d: Doc, at: usize, ns: str, local: str) -> []const usize {
    let (out, e) = mem.alloc[usize](a, d.nodes.len + 1usize)
    if e != ok { ret zero }
    var n = 0usize
    collect(d, at, ns, local, out, &n)
    ret out[0usize..n]
}

// The first such element, or false.
fn find_element(a: *mem.Arena, d: Doc, at: usize, ns: str, local: str) -> (usize, bool) {
    let all = find_elements(a, d, at, ns, local)
    if all.len == 0usize { ret (0usize, false) }
    ret (all[0], true)
}

fn id_of(n: Node) -> (str, bool) {
    let (v, has) = attribute_of(n, "ID")
    if has { ret (v, true) }
    let (w, has_w) = attribute_of(n, "Id")
    if has_w { ret (w, true) }
    let (x, has_x) = attribute_of(n, "id")
    ret (x, has_x)
}

// The first element in the subtree carrying `ID`, `Id` or `id` equal to `id`.
fn find_by_id(d: Doc, at: usize, id: str) -> (usize, bool) {
    let n = d.nodes[at]
    let (v, has) = id_of(n)
    if has && str.eq(v, id) { ret (at, true) }
    var i = 0usize
    while i < n.children.len {
        let (hit, found) = find_by_id(d, n.children[i], id)
        if found { ret (hit, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn is_word(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) || c == 95u8 }

// `^[A-Za-z_][-\w.]*:[A-Za-z_]`
fn looks_like_qname(s: str) -> bool {
    if s.len < 3usize { ret false }
    let c = s[0]
    if !((c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8) { ret false }
    var i = 1usize
    while i < s.len && (is_word(s[i]) || s[i] == 45u8 || s[i] == 46u8) { i += 1usize }
    if i >= s.len || s[i] != 58u8 || i + 1usize >= s.len { ret false }
    let d = s[i + 1usize]
    ret (d >= 65u8 && d <= 90u8) || (d >= 97u8 && d <= 122u8) || d == 95u8
}

fn colon_at(s: str) -> i64 {
    var i = 0usize
    while i < s.len {
        if s[i] == 58u8 { ret i64(i) }
        i += 1usize
    }
    ret -1i64
}

// Prefix declarations already rendered on the way down: parallel arrays, newest last.
type Rendered = struct { prefixes: []str, uris: []str, count: usize }

fn rendered_get(r: Rendered, prefix: str) -> (str, bool) {
    var i = r.count
    while i > 0usize {
        if str.eq(r.prefixes[i - 1usize], prefix) { ret (r.uris[i - 1usize], true) }
        i -= 1usize
    }
    ret ("", false)
}

fn render(a: *mem.Arena, d: Doc, at: usize, inherited: Rendered, inclusive: []const str) -> str {
    let n = d.nodes[at]
    let (used, ue) = mem.alloc[str](a, n.attr_names.len * 2usize + inclusive.len + 2usize)
    var u = 0usize
    used[u] = n.prefix
    u += 1usize
    var i = 0usize
    while i < n.attr_names.len {
        let c = colon_at(n.attr_names[i])
        if c >= 0i64 {
            used[u] = n.attr_names[i][0usize..usize(c)]
            u += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n.attr_names.len {
        let v = n.attr_values[i]
        if looks_like_qname(v) && str.ends_with(n.attr_names[i], "type") {
            used[u] = v[0usize..usize(colon_at(v))]
            u += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < inclusive.len {
        used[u] = inclusive[i]
        u += 1usize
        i += 1usize
    }
    // unique, sorted
    let (uniq, qe) = mem.alloc[str](a, u + 1usize)
    var m = 0usize
    i = 0usize
    while i < u {
        var seen = false
        var k = 0usize
        while k < m {
            if str.eq(uniq[k], used[i]) { seen = true }
            k += 1usize
        }
        if !seen {
            uniq[m] = used[i]
            m += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < m {
        let cur = uniq[i]
        var j = i
        while j > 0usize && str.compare(uniq[j - 1usize], cur) > 0i32 {
            uniq[j] = uniq[j - 1usize]
            j -= 1usize
        }
        uniq[j] = cur
        i += 1usize
    }
    let (next_p, pe) = mem.alloc[str](a, inherited.count + m + 1usize)
    let (next_u, pu) = mem.alloc[str](a, inherited.count + m + 1usize)
    var next = Rendered { prefixes: next_p, uris: next_u, count: inherited.count }
    i = 0usize
    while i < inherited.count {
        next_p[i] = inherited.prefixes[i]
        next_u[i] = inherited.uris[i]
        i += 1usize
    }
    var declarations = ""
    i = 0usize
    while i < m {
        let prefix = uniq[i]
        let (uri, found) = resolve_namespace(d, at, prefix)
        if !found {
            i += 1usize
            continue
        }
        let (old, had) = rendered_get(inherited, prefix)
        if prefix.len == 0usize && uri.len == 0usize && !had {
            i += 1usize
            continue
        }
        if had && str.eq(old, uri) {
            i += 1usize
            continue
        }
        if prefix.len == 0usize {
            declarations = join(a, declarations, join(a, " xmlns=\"", join(a, escape_attribute(a, uri), "\"")))
        } else {
            declarations = join(a, declarations, join(a, join(a, " xmlns:", prefix), join(a, "=\"", join(a, escape_attribute(a, uri), "\""))))
        }
        next_p[next.count] = prefix
        next_u[next.count] = uri
        next.count += 1usize
        i += 1usize
    }
    // attributes sorted by namespace URI then local name
    let (order, oe) = mem.alloc[usize](a, n.attr_names.len + 1usize)
    let (uris, ae) = mem.alloc[str](a, n.attr_names.len + 1usize)
    let (locals, le) = mem.alloc[str](a, n.attr_names.len + 1usize)
    i = 0usize
    while i < n.attr_names.len {
        order[i] = i
        let c = colon_at(n.attr_names[i])
        var uri = ""
        var local = n.attr_names[i]
        if c >= 0i64 {
            let prefix = n.attr_names[i][0usize..usize(c)]
            local = n.attr_names[i][usize(c) + 1usize..]
            if prefix.len > 0usize {
                let (found_uri, has) = resolve_namespace(d, at, prefix)
                if has { uri = found_uri }
            }
        }
        uris[i] = uri
        locals[i] = local
        i += 1usize
    }
    i = 1usize
    while i < n.attr_names.len {
        let cur = order[i]
        var j = i
        while j > 0usize {
            let prev = order[j - 1usize]
            var c = str.compare(uris[prev], uris[cur])
            if c == 0i32 { c = str.compare(locals[prev], locals[cur]) }
            if c > 0i32 {
                order[j] = order[j - 1usize]
                j -= 1usize
            } else {
                break
            }
        }
        order[j] = cur
        i += 1usize
    }
    var attributes = ""
    i = 0usize
    while i < n.attr_names.len {
        let k = order[i]
        attributes = join(a, attributes, join(a, join(a, " ", n.attr_names[k]), join(a, "=\"", join(a, escape_attribute(a, n.attr_values[k]), "\""))))
        i += 1usize
    }
    var out = join(a, join(a, "<", n.name), join(a, declarations, join(a, attributes, ">")))
    i = 0usize
    while i < n.entries.len {
        let en = n.entries[i]
        if en.is_text {
            out = join(a, out, escape_text(a, en.text))
        } else {
            out = join(a, out, render(a, d, en.node, next, inclusive))
        }
        i += 1usize
    }
    ret join(a, out, join(a, join(a, "</", n.name), ">"))
}

// The subtree at `at` as Exclusive XML Canonicalization 1.0; `inclusive` is the PrefixList.
fn canonicalize(a: *mem.Arena, d: Doc, at: usize, inclusive: []const str) -> str {
    let (p, pe) = mem.alloc[str](a, 1usize)
    let (u, ue) = mem.alloc[str](a, 1usize)
    ret render(a, d, at, Rendered { prefixes: p, uris: u, count: 0usize }, inclusive)
}

// The tree as `canonicalize` sees it with every `Signature` element removed from the subtree at `at`
// (the enveloped-signature transform): returns a new document whose subtree root keeps the original parent chain.
fn without_signature(a: *mem.Arena, d: Doc, at: usize) -> (Doc, usize) {
    let (nodes, e) = mem.alloc[Node](a, d.nodes.len + 1usize)
    var i = 0usize
    while i < d.nodes.len {
        nodes[i] = d.nodes[i]
        i += 1usize
    }
    // Entries and children that are `Signature` elements are dropped along the subtree below `at`.
    var stack = at
    let (todo, te) = mem.alloc[usize](a, d.nodes.len + 1usize)
    var head = 0usize
    var tail = 0usize
    todo[tail] = at
    tail += 1usize
    while head < tail {
        let cur = todo[head]
        head += 1usize
        let n = nodes[cur]
        let (ch, ca) = mem.alloc[usize](a, n.children.len + 1usize)
        let (en, cb) = mem.alloc[Entry](a, n.entries.len + 1usize)
        var cn = 0usize
        var ec = 0usize
        var k = 0usize
        while k < n.entries.len {
            let entry = n.entries[k]
            if entry.is_text {
                en[ec] = entry
                ec += 1usize
            } else if !str.eq(nodes[entry.node].local, "Signature") {
                en[ec] = entry
                ec += 1usize
                ch[cn] = entry.node
                cn += 1usize
                todo[tail] = entry.node
                tail += 1usize
            }
            k += 1usize
        }
        nodes[cur].children = ch[0usize..cn]
        nodes[cur].entries = en[0usize..ec]
        stack = cur
    }
    ret (Doc { valid: true, message: "", nodes: nodes[0usize..d.nodes.len], root: d.root }, at)
}
