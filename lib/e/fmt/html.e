// HTML parsed into an arena-owned node table with parent, child and sibling links, by the
// WHATWG parsing algorithm (https://html.spec.whatwg.org/multipage/parsing.html): the
// tokenizer states (data, RCDATA, RAWTEXT, script data with its escape states, PLAINTEXT,
// comments, DOCTYPE with public and system identifiers, CDATA in foreign content, named
// and numeric character references), and tree construction through every insertion mode:
// the adoption agency and the list of active formatting elements, foster parenting, tables,
// select (the current customizable-select rules, `selectedcontent` filled when parsing
// ends), `template` (its content is its children), frameset, SVG and MathML with their
// integration points and name and attribute adjustments (a foreign attribute's prefix is
// its `Namespace`: Xlink, Xml, Xmlns), quirks mode in `Document.quirks`, and fragment parsing
// (`parse_fragment`, innerHTML). Malformed input is recovered, never refused; invalid UTF-8
// is `InvalidEncoding`, and the `Options` limits are `TooLarge` and `TooDeep`.
//
// `parse` has scripting off, so `noscript` holds markup; `parse_with` and
// `parse_fragment_with` take the flag. Conformance: all 1791 html5lib tree-construction
// cases pass (tests/browser/html5lib/run.sh); a DOCTYPE node's identifiers are read with
// `doctype_public` and `doctype_system`.
//
// ponytail: `Options.max_attributes` over 64 is capped at 64 (a tag with more is TooLarge);
// a comment cut off by the end of the input and a DOCTYPE with an empty system identifier
// are read as the spec's missing case.
use e.io
use e.mem
use e.str

type NodeId = u32
const NONE: NodeId = 4294967295u32
type NodeKind = enum u8 { Document, Doctype, Element, Text, Comment }
type Namespace = enum u8 { Html, Svg, MathMl, Xlink, Xml, Xmlns }
type Attribute = struct { namespace: Namespace, name: str, value: str }
// `flags` are dynamic selector states a script keeps (see e.fmt.css.match): checkedness, :popover-open, :defined, focus.
type Node = struct { kind: NodeKind, namespace: Namespace, name: str, value: str, attributes: []const Attribute, parent: NodeId, first_child: NodeId, last_child: NodeId, previous_sibling: NodeId, next_sibling: NodeId, flags: u32 }
type Document = struct { nodes: []const Node, root: NodeId, quirks: u8 }
type Children = struct { document: *const Document, next: NodeId }
type Options = struct { max_bytes: usize, max_nodes: usize, max_attributes: usize, max_depth: u16, preserve_comments: bool }
error InvalidEncoding
error TooDeep
error TooLarge


// --- Names.

fn is_void(name: str) -> bool {
    ret str.eq(name, "area") || str.eq(name, "base") || str.eq(name, "br") || str.eq(name, "col") || str.eq(name, "embed") || str.eq(name, "hr") || str.eq(name, "img") || str.eq(name, "input") || str.eq(name, "link") || str.eq(name, "meta") || str.eq(name, "param") || str.eq(name, "source") || str.eq(name, "track") || str.eq(name, "wbr")
}

fn is_raw_text(name: str) -> bool {
    ret str.eq(name, "script") || str.eq(name, "style") || str.eq(name, "xmp") || str.eq(name, "iframe") || str.eq(name, "noembed") || str.eq(name, "noframes")
}





// --- Nodes.












// --- Character references.


fn write_utf8(scalar: u32, dst: []u8, at: usize) -> usize {
    if scalar < 128u32 {
        dst[at] = u8(scalar)
        ret at + 1usize
    }
    if scalar < 2048u32 {
        dst[at] = u8(192u32 | (scalar >> 6u32))
        dst[at + 1usize] = u8(128u32 | (scalar & 63u32))
        ret at + 2usize
    }
    if scalar < 65536u32 {
        dst[at] = u8(224u32 | (scalar >> 12u32))
        dst[at + 1usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
        dst[at + 2usize] = u8(128u32 | (scalar & 63u32))
        ret at + 3usize
    }
    dst[at] = u8(240u32 | (scalar >> 18u32))
    dst[at + 1usize] = u8(128u32 | ((scalar >> 12u32) & 63u32))
    dst[at + 2usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
    dst[at + 3usize] = u8(128u32 | (scalar & 63u32))
    ret at + 4usize
}

// The Windows-1252 character a numeric reference to U+0080..U+009F stands for.
fn c1_replacement(scalar: u32) -> u32 {
    let table = "20AC0081201A0192201E20262020202102C62030016020390152008D017D008F009020182019201C201D20222013201402DC21220161203A0153009D017E0178"
    let at = usize(scalar - 128u32) * 4usize
    var value = 0u32
    var i = 0usize
    while i < 4usize {
        let c = table[at + i]
        var digit = 0u32
        if c >= 65u8 { digit = u32(c - 55u8) } else { digit = u32(c - 48u8) }
        value = value * 16u32 + digit
        i += 1usize
    }
    ret value
}

// The longest entity name at `text[at..]` (the `&` already behind), with its
// replacement: (replacement, name length, found). Names without a semicolon are
// legacy and, in an attribute, are left alone when followed by `=` or a letter.
fn lookup_entity(text: str, at: usize, in_attribute: bool) -> ([]const u8, usize, bool) {
    let table = entity_table()
    var i = 0usize
    var best_len = 0usize
    var best: []const u8 = zero
    while i < table.len {
        let name_len = usize(table[i])
        let name = table[i + 1usize..i + 1usize + name_len]
        let value_len = usize(table[i + 1usize + name_len])
        let value = table[i + 2usize + name_len..i + 2usize + name_len + value_len]
        i += 2usize + name_len + value_len
        if name_len <= best_len || at + name_len > text.len { continue }
        if !str.eq(text[at..at + name_len], name) { continue }
        if name[name_len - 1usize] != 59u8 && in_attribute && at + name_len < text.len {
            let next = text[at + name_len]
            if next == 61u8 || str.is_ascii_alnum(next) { continue }
        }
        best_len = name_len
        best = value
    }
    ret (best, best_len, best_len > 0usize)
}

// Decodes the reference at `at` (after `&`) into `out`: (bytes written, source used).
fn decode_reference(text: str, at: usize, in_attribute: bool, out: []u8) -> (usize, usize) {
    if at < text.len && text[at] == 35u8 {
        var i = at + 1usize
        var hex = false
        if i < text.len && (text[i] == 120u8 || text[i] == 88u8) {
            hex = true
            i += 1usize
        }
        var scalar = 0u64
        var digits = 0usize
        while i < text.len {
            let c = text[i]
            var digit = 0u64
            if str.is_ascii_digit(c) { digit = u64(c - 48u8) } else {
            if hex && c >= 97u8 && c <= 102u8 { digit = u64(c - 87u8) } else {
            if hex && c >= 65u8 && c <= 70u8 { digit = u64(c - 55u8) } else { break }
            }
            }
            var radix = 10u64
            if hex { radix = 16u64 }
            if scalar < 1114112u64 { scalar = scalar * radix + digit }
            digits += 1usize
            i += 1usize
        }
        if digits == 0usize { ret (0usize, 0usize) }
        if i < text.len && text[i] == 59u8 { i += 1usize }
        if scalar == 0u64 || scalar > 1114111u64 || (scalar >= 55296u64 && scalar <= 57343u64) { scalar = 65533u64 }
        if scalar >= 128u64 && scalar <= 159u64 { scalar = u64(c1_replacement(u32(scalar))) }
        let written = write_utf8(u32(scalar), out, 0usize)
        ret (written, i - at)
    }
    let (value, name_len, found) = lookup_entity(text, at, in_attribute)
    if !found { ret (0usize, 0usize) }
    mem.copy[u8](out[..value.len], value)
    ret (value.len, name_len)
}

// --- Tokens into the tree.





// --- The tokenizer.

fn utf8_valid(text: str) -> bool {
    var i = 0usize
    while i < text.len {
        let b0 = u32(text[i])
        var need = 0usize
        if b0 < 128u32 {
            i += 1usize
            continue
        }
        if b0 >= 194u32 && b0 < 224u32 { need = 1usize } else {
        if b0 >= 224u32 && b0 < 240u32 { need = 2usize } else {
        if b0 >= 240u32 && b0 < 245u32 { need = 3usize } else { ret false }
        }
        }
        if i + need >= text.len { ret false }
        var k = 1usize
        var scalar = b0 & (127u32 >> u32(need + 1usize))
        while k <= need {
            let c = u32(text[i + k])
            if c & 192u32 != 128u32 { ret false }
            scalar = (scalar << 6u32) | (c & 63u32)
            k += 1usize
        }
        if need == 2usize && (scalar < 2048u32 || (scalar >= 55296u32 && scalar <= 57343u32)) { ret false }
        if need == 3usize && (scalar < 65536u32 || scalar > 1114111u32) { ret false }
        i += need + 1usize
    }
    ret true
}






fn parse_reader(a: *mem.Arena, source: io.Reader, options: Options) -> (Document, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, options.max_bytes + 1usize)
    if buffer_error != ok { ret (zero, buffer_error) }
    var input = source
    var filled = 0usize
    while filled < buffer.len {
        let (count, read_error) = io.read(&input, buffer[filled..])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        if count == 0usize { break }
        filled += count
    }
    if filled > options.max_bytes { ret (zero, TooLarge) }
    let (document, parse_error) = parse(a, buffer[..filled], options)
    ret (document, parse_error)
}

// --- Reading the tree.

fn node(document: *const Document, id: NodeId) -> *const Node {
    ret &document.nodes[usize(id)]
}

fn children(document: *const Document, parent: NodeId) -> Children {
    ret Children { document: document, next: document.nodes[usize(parent)].first_child }
}

fn children_next(it: *Children) -> (NodeId, bool) {
    if it.next == NONE { ret (NONE, false) }
    let id = it.next
    it.next = it.document.nodes[usize(id)].next_sibling
    ret (id, true)
}

fn attribute(element: *const Node, name: str) -> (str, bool) {
    var i = 0usize
    while i < element.attributes.len {
        if str.eq(element.attributes[i].name, name) { ret (element.attributes[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

fn text_size(document: *const Document, id: NodeId) -> usize {
    let n = &document.nodes[usize(id)]
    if n.kind == .Text { ret n.value.len }
    var total = 0usize
    var child = n.first_child
    while child != NONE {
        total += text_size(document, child)
        child = document.nodes[usize(child)].next_sibling
    }
    ret total
}

fn text_fill(document: *const Document, id: NodeId, out: []u8, at: usize) -> usize {
    let n = &document.nodes[usize(id)]
    if n.kind == .Text {
        mem.copy[u8](out[at..at + n.value.len], n.value)
        ret at + n.value.len
    }
    var cursor = at
    var child = n.first_child
    while child != NONE {
        cursor = text_fill(document, child, out, cursor)
        child = document.nodes[usize(child)].next_sibling
    }
    ret cursor
}

fn text_content(a: *mem.Arena, document: *const Document, root: NodeId) -> (str, err) {
    let total = text_size(document, root)
    let (out, out_error) = mem.alloc[u8](a, total)
    if out_error != ok { ret ("", out_error) }
    let filled = text_fill(document, root, out, 0usize)
    ret (out[..filled], ok)
}

// --- Serializing.

fn write_escaped(writer: *io.Writer, text: str, in_attribute: bool) -> err {
    var run = 0usize
    var at = 0usize
    while at < text.len {
        let c = text[at]
        var replacement = ""
        if c == 38u8 { replacement = "&amp;" }
        if c == 60u8 && !in_attribute { replacement = "&lt;" }
        if c == 62u8 && !in_attribute { replacement = "&gt;" }
        if c == 34u8 && in_attribute { replacement = "&quot;" }
        if c == 160u8 && at > 0usize && text[at - 1usize] == 194u8 {
            try io.write_all(writer, text[run..at - 1usize])
            try io.write_all(writer, "&nbsp;")
            run = at + 1usize
        } else {
            if replacement.len > 0usize {
                try io.write_all(writer, text[run..at])
                try io.write_all(writer, replacement)
                run = at + 1usize
            }
        }
        at += 1usize
    }
    ret io.write_all(writer, text[run..])
}

fn write_node(writer: *io.Writer, document: *const Document, id: NodeId) -> err {
    let n = &document.nodes[usize(id)]
    if n.kind == .Text {
        let parent = n.parent
        if parent != NONE && document.nodes[usize(parent)].kind == .Element && is_raw_text(document.nodes[usize(parent)].name) { ret io.write_all(writer, n.value) }
        ret write_escaped(writer, n.value, false)
    }
    if n.kind == .Comment {
        try io.write_all(writer, "<!--")
        try io.write_all(writer, n.value)
        ret io.write_all(writer, "-->")
    }
    if n.kind == .Doctype {
        try io.write_all(writer, "<!DOCTYPE ")
        try io.write_all(writer, n.name)
        ret io.write_all(writer, ">")
    }
    if n.kind == .Element {
        try io.write_all(writer, "<")
        try io.write_all(writer, n.name)
        var i = 0usize
        while i < n.attributes.len {
            try io.write_all(writer, " ")
            if n.attributes[i].namespace == .Xlink { try io.write_all(writer, "xlink:") }
            if n.attributes[i].namespace == .Xml { try io.write_all(writer, "xml:") }
            if n.attributes[i].namespace == .Xmlns && !str.eq(n.attributes[i].name, "xmlns") { try io.write_all(writer, "xmlns:") }
            try io.write_all(writer, n.attributes[i].name)
            try io.write_all(writer, "=\"")
            try write_escaped(writer, n.attributes[i].value, true)
            try io.write_all(writer, "\"")
            i += 1usize
        }
        try io.write_all(writer, ">")
        if n.namespace == .Html && is_void(n.name) { ret ok }
    }
    var child = n.first_child
    while child != NONE {
        try write_node(writer, document, child)
        child = document.nodes[usize(child)].next_sibling
    }
    if n.kind == .Element {
        try io.write_all(writer, "</")
        try io.write_all(writer, n.name)
        try io.write_all(writer, ">")
    }
    ret ok
}

fn write(writer: *io.Writer, document: *const Document) -> err {
    ret write_node(writer, document, document.root)
}

// --- Generated (tests/selfhost/fixtures/link/fmt_html/reference.py): the HTML5
// named character references as (name length, name, value length, value) records.
fn entity_table() -> str { ret "\x05AElig\x02\xc3\x86\x06AElig;\x02\xc3\x86\x03AMP\x01&\x04AMP;\x01&\x06Aacute\x02\xc3\x81\x07Aacute;\x02\xc3\x81\x07Abreve;\x02\xc4\x82\x05Acirc\x02\xc3\x82\x06Acirc;\x02\xc3\x82\x04Acy;\x02\xd0\x90\x04Afr;\x04\xf0\x9d\x94\x84\x06Agrave\x02\xc3\x80\x07Agrave;\x02\xc3\x80\x06Alpha;\x02\xce\x91\x06Amacr;\x02\xc4\x80\x04And;\x03\xe2\xa9\x93\x06Aogon;\x02\xc4\x84\x05Aopf;\x04\xf0\x9d\x94\xb8\x0eApplyFunction;\x03\xe2\x81\xa1\x05Aring\x02\xc3\x85\x06Aring;\x02\xc3\x85\x05Ascr;\x04\xf0\x9d\x92\x9c\x07Assign;\x03\xe2\x89\x94\x06Atilde\x02\xc3\x83\x07Atilde;\x02\xc3\x83\x04Auml\x02\xc3\x84\x05Auml;\x02\xc3\x84\x0aBackslash;\x03\xe2\x88\x96\x05Barv;\x03\xe2\xab\xa7\x07Barwed;\x03\xe2\x8c\x86\x04Bcy;\x02\xd0\x91\x08Because;\x03\xe2\x88\xb5\x0bBernoullis;\x03\xe2\x84\xac\x05Beta;\x02\xce\x92\x04Bfr;\x04\xf0\x9d\x94\x85\x05Bopf;\x04\xf0\x9d\x94\xb9\x06Breve;\x02\xcb\x98\x05Bscr;\x03\xe2\x84\xac\x07Bumpeq;\x03\xe2\x89\x8e\x05CHcy;\x02\xd0\xa7\x04COPY\x02\xc2\xa9\x05COPY;\x02\xc2\xa9\x07Cacute;\x02\xc4\x86\x04Cap;\x03\xe2\x8b\x92\x15CapitalDifferentialD;\x03\xe2\x85\x85\x08Cayleys;\x03\xe2\x84\xad\x07Ccaron;\x02\xc4\x8c\x06Ccedil\x02\xc3\x87\x07Ccedil;\x02\xc3\x87\x06Ccirc;\x02\xc4\x88\x08Cconint;\x03\xe2\x88\xb0\x05Cdot;\x02\xc4\x8a\x08Cedilla;\x02\xc2\xb8\x0aCenterDot;\x02\xc2\xb7\x04Cfr;\x03\xe2\x84\xad\x04Chi;\x02\xce\xa7\x0aCircleDot;\x03\xe2\x8a\x99\x0cCircleMinus;\x03\xe2\x8a\x96\x0bCirclePlus;\x03\xe2\x8a\x95\x0cCircleTimes;\x03\xe2\x8a\x97\x19ClockwiseContourIntegral;\x03\xe2\x88\xb2\x16CloseCurlyDoubleQuote;\x03\xe2\x80\x9d\x10CloseCurlyQuote;\x03\xe2\x80\x99\x06Colon;\x03\xe2\x88\xb7\x07Colone;\x03\xe2\xa9\xb4\x0aCongruent;\x03\xe2\x89\xa1\x07Conint;\x03\xe2\x88\xaf\x10ContourIntegral;\x03\xe2\x88\xae\x05Copf;\x03\xe2\x84\x82\x0aCoproduct;\x03\xe2\x88\x90 CounterClockwiseContourIntegral;\x03\xe2\x88\xb3\x06Cross;\x03\xe2\xa8\xaf\x05Cscr;\x04\xf0\x9d\x92\x9e\x04Cup;\x03\xe2\x8b\x93\x07CupCap;\x03\xe2\x89\x8d\x03DD;\x03\xe2\x85\x85\x09DDotrahd;\x03\xe2\xa4\x91\x05DJcy;\x02\xd0\x82\x05DScy;\x02\xd0\x85\x05DZcy;\x02\xd0\x8f\x07Dagger;\x03\xe2\x80\xa1\x05Darr;\x03\xe2\x86\xa1\x06Dashv;\x03\xe2\xab\xa4\x07Dcaron;\x02\xc4\x8e\x04Dcy;\x02\xd0\x94\x04Del;\x03\xe2\x88\x87\x06Delta;\x02\xce\x94\x04Dfr;\x04\xf0\x9d\x94\x87\x11DiacriticalAcute;\x02\xc2\xb4\x0fDiacriticalDot;\x02\xcb\x99\x17DiacriticalDoubleAcute;\x02\xcb\x9d\x11DiacriticalGrave;\x01`\x11DiacriticalTilde;\x02\xcb\x9c\x08Diamond;\x03\xe2\x8b\x84\x0eDifferentialD;\x03\xe2\x85\x86\x05Dopf;\x04\xf0\x9d\x94\xbb\x04Dot;\x02\xc2\xa8\x07DotDot;\x03\xe2\x83\x9c\x09DotEqual;\x03\xe2\x89\x90\x16DoubleContourIntegral;\x03\xe2\x88\xaf\x0aDoubleDot;\x02\xc2\xa8\x10DoubleDownArrow;\x03\xe2\x87\x93\x10DoubleLeftArrow;\x03\xe2\x87\x90\x15DoubleLeftRightArrow;\x03\xe2\x87\x94\x0eDoubleLeftTee;\x03\xe2\xab\xa4\x14DoubleLongLeftArrow;\x03\xe2\x9f\xb8\x19DoubleLongLeftRightArrow;\x03\xe2\x9f\xba\x15DoubleLongRightArrow;\x03\xe2\x9f\xb9\x11DoubleRightArrow;\x03\xe2\x87\x92\x0fDoubleRightTee;\x03\xe2\x8a\xa8\x0eDoubleUpArrow;\x03\xe2\x87\x91\x12DoubleUpDownArrow;\x03\xe2\x87\x95\x12DoubleVerticalBar;\x03\xe2\x88\xa5\x0aDownArrow;\x03\xe2\x86\x93\x0dDownArrowBar;\x03\xe2\xa4\x93\x11DownArrowUpArrow;\x03\xe2\x87\xb5\x0aDownBreve;\x02\xcc\x91\x14DownLeftRightVector;\x03\xe2\xa5\x90\x12DownLeftTeeVector;\x03\xe2\xa5\x9e\x0fDownLeftVector;\x03\xe2\x86\xbd\x12DownLeftVectorBar;\x03\xe2\xa5\x96\x13DownRightTeeVector;\x03\xe2\xa5\x9f\x10DownRightVector;\x03\xe2\x87\x81\x13DownRightVectorBar;\x03\xe2\xa5\x97\x08DownTee;\x03\xe2\x8a\xa4\x0dDownTeeArrow;\x03\xe2\x86\xa7\x0aDownarrow;\x03\xe2\x87\x93\x05Dscr;\x04\xf0\x9d\x92\x9f\x07Dstrok;\x02\xc4\x90\x04ENG;\x02\xc5\x8a\x03ETH\x02\xc3\x90\x04ETH;\x02\xc3\x90\x06Eacute\x02\xc3\x89\x07Eacute;\x02\xc3\x89\x07Ecaron;\x02\xc4\x9a\x05Ecirc\x02\xc3\x8a\x06Ecirc;\x02\xc3\x8a\x04Ecy;\x02\xd0\xad\x05Edot;\x02\xc4\x96\x04Efr;\x04\xf0\x9d\x94\x88\x06Egrave\x02\xc3\x88\x07Egrave;\x02\xc3\x88\x08Element;\x03\xe2\x88\x88\x06Emacr;\x02\xc4\x92\x11EmptySmallSquare;\x03\xe2\x97\xbb\x15EmptyVerySmallSquare;\x03\xe2\x96\xab\x06Eogon;\x02\xc4\x98\x05Eopf;\x04\xf0\x9d\x94\xbc\x08Epsilon;\x02\xce\x95\x06Equal;\x03\xe2\xa9\xb5\x0bEqualTilde;\x03\xe2\x89\x82\x0cEquilibrium;\x03\xe2\x87\x8c\x05Escr;\x03\xe2\x84\xb0\x05Esim;\x03\xe2\xa9\xb3\x04Eta;\x02\xce\x97\x04Euml\x02\xc3\x8b\x05Euml;\x02\xc3\x8b\x07Exists;\x03\xe2\x88\x83\x0dExponentialE;\x03\xe2\x85\x87\x04Fcy;\x02\xd0\xa4\x04Ffr;\x04\xf0\x9d\x94\x89\x12FilledSmallSquare;\x03\xe2\x97\xbc\x16FilledVerySmallSquare;\x03\xe2\x96\xaa\x05Fopf;\x04\xf0\x9d\x94\xbd\x07ForAll;\x03\xe2\x88\x80\x0bFouriertrf;\x03\xe2\x84\xb1\x05Fscr;\x03\xe2\x84\xb1\x05GJcy;\x02\xd0\x83\x02GT\x01>\x03GT;\x01>\x06Gamma;\x02\xce\x93\x07Gammad;\x02\xcf\x9c\x07Gbreve;\x02\xc4\x9e\x07Gcedil;\x02\xc4\xa2\x06Gcirc;\x02\xc4\x9c\x04Gcy;\x02\xd0\x93\x05Gdot;\x02\xc4\xa0\x04Gfr;\x04\xf0\x9d\x94\x8a\x03Gg;\x03\xe2\x8b\x99\x05Gopf;\x04\xf0\x9d\x94\xbe\x0dGreaterEqual;\x03\xe2\x89\xa5\x11GreaterEqualLess;\x03\xe2\x8b\x9b\x11GreaterFullEqual;\x03\xe2\x89\xa7\x0fGreaterGreater;\x03\xe2\xaa\xa2\x0cGreaterLess;\x03\xe2\x89\xb7\x12GreaterSlantEqual;\x03\xe2\xa9\xbe\x0dGreaterTilde;\x03\xe2\x89\xb3\x05Gscr;\x04\xf0\x9d\x92\xa2\x03Gt;\x03\xe2\x89\xab\x07HARDcy;\x02\xd0\xaa\x06Hacek;\x02\xcb\x87\x04Hat;\x01^\x06Hcirc;\x02\xc4\xa4\x04Hfr;\x03\xe2\x84\x8c\x0dHilbertSpace;\x03\xe2\x84\x8b\x05Hopf;\x03\xe2\x84\x8d\x0fHorizontalLine;\x03\xe2\x94\x80\x05Hscr;\x03\xe2\x84\x8b\x07Hstrok;\x02\xc4\xa6\x0dHumpDownHump;\x03\xe2\x89\x8e\x0aHumpEqual;\x03\xe2\x89\x8f\x05IEcy;\x02\xd0\x95\x06IJlig;\x02\xc4\xb2\x05IOcy;\x02\xd0\x81\x06Iacute\x02\xc3\x8d\x07Iacute;\x02\xc3\x8d\x05Icirc\x02\xc3\x8e\x06Icirc;\x02\xc3\x8e\x04Icy;\x02\xd0\x98\x05Idot;\x02\xc4\xb0\x04Ifr;\x03\xe2\x84\x91\x06Igrave\x02\xc3\x8c\x07Igrave;\x02\xc3\x8c\x03Im;\x03\xe2\x84\x91\x06Imacr;\x02\xc4\xaa\x0bImaginaryI;\x03\xe2\x85\x88\x08Implies;\x03\xe2\x87\x92\x04Int;\x03\xe2\x88\xac\x09Integral;\x03\xe2\x88\xab\x0dIntersection;\x03\xe2\x8b\x82\x0fInvisibleComma;\x03\xe2\x81\xa3\x0fInvisibleTimes;\x03\xe2\x81\xa2\x06Iogon;\x02\xc4\xae\x05Iopf;\x04\xf0\x9d\x95\x80\x05Iota;\x02\xce\x99\x05Iscr;\x03\xe2\x84\x90\x07Itilde;\x02\xc4\xa8\x06Iukcy;\x02\xd0\x86\x04Iuml\x02\xc3\x8f\x05Iuml;\x02\xc3\x8f\x06Jcirc;\x02\xc4\xb4\x04Jcy;\x02\xd0\x99\x04Jfr;\x04\xf0\x9d\x94\x8d\x05Jopf;\x04\xf0\x9d\x95\x81\x05Jscr;\x04\xf0\x9d\x92\xa5\x07Jsercy;\x02\xd0\x88\x06Jukcy;\x02\xd0\x84\x05KHcy;\x02\xd0\xa5\x05KJcy;\x02\xd0\x8c\x06Kappa;\x02\xce\x9a\x07Kcedil;\x02\xc4\xb6\x04Kcy;\x02\xd0\x9a\x04Kfr;\x04\xf0\x9d\x94\x8e\x05Kopf;\x04\xf0\x9d\x95\x82\x05Kscr;\x04\xf0\x9d\x92\xa6\x05LJcy;\x02\xd0\x89\x02LT\x01<\x03LT;\x01<\x07Lacute;\x02\xc4\xb9\x07Lambda;\x02\xce\x9b\x05Lang;\x03\xe2\x9f\xaa\x0bLaplacetrf;\x03\xe2\x84\x92\x05Larr;\x03\xe2\x86\x9e\x07Lcaron;\x02\xc4\xbd\x07Lcedil;\x02\xc4\xbb\x04Lcy;\x02\xd0\x9b\x11LeftAngleBracket;\x03\xe2\x9f\xa8\x0aLeftArrow;\x03\xe2\x86\x90\x0dLeftArrowBar;\x03\xe2\x87\xa4\x14LeftArrowRightArrow;\x03\xe2\x87\x86\x0cLeftCeiling;\x03\xe2\x8c\x88\x12LeftDoubleBracket;\x03\xe2\x9f\xa6\x12LeftDownTeeVector;\x03\xe2\xa5\xa1\x0fLeftDownVector;\x03\xe2\x87\x83\x12LeftDownVectorBar;\x03\xe2\xa5\x99\x0aLeftFloor;\x03\xe2\x8c\x8a\x0fLeftRightArrow;\x03\xe2\x86\x94\x10LeftRightVector;\x03\xe2\xa5\x8e\x08LeftTee;\x03\xe2\x8a\xa3\x0dLeftTeeArrow;\x03\xe2\x86\xa4\x0eLeftTeeVector;\x03\xe2\xa5\x9a\x0dLeftTriangle;\x03\xe2\x8a\xb2\x10LeftTriangleBar;\x03\xe2\xa7\x8f\x12LeftTriangleEqual;\x03\xe2\x8a\xb4\x11LeftUpDownVector;\x03\xe2\xa5\x91\x10LeftUpTeeVector;\x03\xe2\xa5\xa0\x0dLeftUpVector;\x03\xe2\x86\xbf\x10LeftUpVectorBar;\x03\xe2\xa5\x98\x0bLeftVector;\x03\xe2\x86\xbc\x0eLeftVectorBar;\x03\xe2\xa5\x92\x0aLeftarrow;\x03\xe2\x87\x90\x0fLeftrightarrow;\x03\xe2\x87\x94\x11LessEqualGreater;\x03\xe2\x8b\x9a\x0eLessFullEqual;\x03\xe2\x89\xa6\x0cLessGreater;\x03\xe2\x89\xb6\x09LessLess;\x03\xe2\xaa\xa1\x0fLessSlantEqual;\x03\xe2\xa9\xbd\x0aLessTilde;\x03\xe2\x89\xb2\x04Lfr;\x04\xf0\x9d\x94\x8f\x03Ll;\x03\xe2\x8b\x98\x0bLleftarrow;\x03\xe2\x87\x9a\x07Lmidot;\x02\xc4\xbf\x0eLongLeftArrow;\x03\xe2\x9f\xb5\x13LongLeftRightArrow;\x03\xe2\x9f\xb7\x0fLongRightArrow;\x03\xe2\x9f\xb6\x0eLongleftarrow;\x03\xe2\x9f\xb8\x13Longleftrightarrow;\x03\xe2\x9f\xba\x0fLongrightarrow;\x03\xe2\x9f\xb9\x05Lopf;\x04\xf0\x9d\x95\x83\x0fLowerLeftArrow;\x03\xe2\x86\x99\x10LowerRightArrow;\x03\xe2\x86\x98\x05Lscr;\x03\xe2\x84\x92\x04Lsh;\x03\xe2\x86\xb0\x07Lstrok;\x02\xc5\x81\x03Lt;\x03\xe2\x89\xaa\x04Map;\x03\xe2\xa4\x85\x04Mcy;\x02\xd0\x9c\x0cMediumSpace;\x03\xe2\x81\x9f\x0aMellintrf;\x03\xe2\x84\xb3\x04Mfr;\x04\xf0\x9d\x94\x90\x0aMinusPlus;\x03\xe2\x88\x93\x05Mopf;\x04\xf0\x9d\x95\x84\x05Mscr;\x03\xe2\x84\xb3\x03Mu;\x02\xce\x9c\x05NJcy;\x02\xd0\x8a\x07Nacute;\x02\xc5\x83\x07Ncaron;\x02\xc5\x87\x07Ncedil;\x02\xc5\x85\x04Ncy;\x02\xd0\x9d\x14NegativeMediumSpace;\x03\xe2\x80\x8b\x13NegativeThickSpace;\x03\xe2\x80\x8b\x12NegativeThinSpace;\x03\xe2\x80\x8b\x16NegativeVeryThinSpace;\x03\xe2\x80\x8b\x15NestedGreaterGreater;\x03\xe2\x89\xab\x0fNestedLessLess;\x03\xe2\x89\xaa\x08NewLine;\x01\x0a\x04Nfr;\x04\xf0\x9d\x94\x91\x08NoBreak;\x03\xe2\x81\xa0\x11NonBreakingSpace;\x02\xc2\xa0\x05Nopf;\x03\xe2\x84\x95\x04Not;\x03\xe2\xab\xac\x0dNotCongruent;\x03\xe2\x89\xa2\x0aNotCupCap;\x03\xe2\x89\xad\x15NotDoubleVerticalBar;\x03\xe2\x88\xa6\x0bNotElement;\x03\xe2\x88\x89\x09NotEqual;\x03\xe2\x89\xa0\x0eNotEqualTilde;\x05\xe2\x89\x82\xcc\xb8\x0aNotExists;\x03\xe2\x88\x84\x0bNotGreater;\x03\xe2\x89\xaf\x10NotGreaterEqual;\x03\xe2\x89\xb1\x14NotGreaterFullEqual;\x05\xe2\x89\xa7\xcc\xb8\x12NotGreaterGreater;\x05\xe2\x89\xab\xcc\xb8\x0fNotGreaterLess;\x03\xe2\x89\xb9\x15NotGreaterSlantEqual;\x05\xe2\xa9\xbe\xcc\xb8\x10NotGreaterTilde;\x03\xe2\x89\xb5\x10NotHumpDownHump;\x05\xe2\x89\x8e\xcc\xb8\x0dNotHumpEqual;\x05\xe2\x89\x8f\xcc\xb8\x10NotLeftTriangle;\x03\xe2\x8b\xaa\x13NotLeftTriangleBar;\x05\xe2\xa7\x8f\xcc\xb8\x15NotLeftTriangleEqual;\x03\xe2\x8b\xac\x08NotLess;\x03\xe2\x89\xae\x0dNotLessEqual;\x03\xe2\x89\xb0\x0fNotLessGreater;\x03\xe2\x89\xb8\x0cNotLessLess;\x05\xe2\x89\xaa\xcc\xb8\x12NotLessSlantEqual;\x05\xe2\xa9\xbd\xcc\xb8\x0dNotLessTilde;\x03\xe2\x89\xb4\x18NotNestedGreaterGreater;\x05\xe2\xaa\xa2\xcc\xb8\x12NotNestedLessLess;\x05\xe2\xaa\xa1\xcc\xb8\x0cNotPrecedes;\x03\xe2\x8a\x80\x11NotPrecedesEqual;\x05\xe2\xaa\xaf\xcc\xb8\x16NotPrecedesSlantEqual;\x03\xe2\x8b\xa0\x12NotReverseElement;\x03\xe2\x88\x8c\x11NotRightTriangle;\x03\xe2\x8b\xab\x14NotRightTriangleBar;\x05\xe2\xa7\x90\xcc\xb8\x16NotRightTriangleEqual;\x03\xe2\x8b\xad\x10NotSquareSubset;\x05\xe2\x8a\x8f\xcc\xb8\x15NotSquareSubsetEqual;\x03\xe2\x8b\xa2\x12NotSquareSuperset;\x05\xe2\x8a\x90\xcc\xb8\x17NotSquareSupersetEqual;\x03\xe2\x8b\xa3\x0aNotSubset;\x06\xe2\x8a\x82\xe2\x83\x92\x0fNotSubsetEqual;\x03\xe2\x8a\x88\x0cNotSucceeds;\x03\xe2\x8a\x81\x11NotSucceedsEqual;\x05\xe2\xaa\xb0\xcc\xb8\x16NotSucceedsSlantEqual;\x03\xe2\x8b\xa1\x11NotSucceedsTilde;\x05\xe2\x89\xbf\xcc\xb8\x0cNotSuperset;\x06\xe2\x8a\x83\xe2\x83\x92\x11NotSupersetEqual;\x03\xe2\x8a\x89\x09NotTilde;\x03\xe2\x89\x81\x0eNotTildeEqual;\x03\xe2\x89\x84\x12NotTildeFullEqual;\x03\xe2\x89\x87\x0eNotTildeTilde;\x03\xe2\x89\x89\x0fNotVerticalBar;\x03\xe2\x88\xa4\x05Nscr;\x04\xf0\x9d\x92\xa9\x06Ntilde\x02\xc3\x91\x07Ntilde;\x02\xc3\x91\x03Nu;\x02\xce\x9d\x06OElig;\x02\xc5\x92\x06Oacute\x02\xc3\x93\x07Oacute;\x02\xc3\x93\x05Ocirc\x02\xc3\x94\x06Ocirc;\x02\xc3\x94\x04Ocy;\x02\xd0\x9e\x07Odblac;\x02\xc5\x90\x04Ofr;\x04\xf0\x9d\x94\x92\x06Ograve\x02\xc3\x92\x07Ograve;\x02\xc3\x92\x06Omacr;\x02\xc5\x8c\x06Omega;\x02\xce\xa9\x08Omicron;\x02\xce\x9f\x05Oopf;\x04\xf0\x9d\x95\x86\x15OpenCurlyDoubleQuote;\x03\xe2\x80\x9c\x0fOpenCurlyQuote;\x03\xe2\x80\x98\x03Or;\x03\xe2\xa9\x94\x05Oscr;\x04\xf0\x9d\x92\xaa\x06Oslash\x02\xc3\x98\x07Oslash;\x02\xc3\x98\x06Otilde\x02\xc3\x95\x07Otilde;\x02\xc3\x95\x07Otimes;\x03\xe2\xa8\xb7\x04Ouml\x02\xc3\x96\x05Ouml;\x02\xc3\x96\x08OverBar;\x03\xe2\x80\xbe\x0aOverBrace;\x03\xe2\x8f\x9e\x0cOverBracket;\x03\xe2\x8e\xb4\x10OverParenthesis;\x03\xe2\x8f\x9c\x09PartialD;\x03\xe2\x88\x82\x04Pcy;\x02\xd0\x9f\x04Pfr;\x04\xf0\x9d\x94\x93\x04Phi;\x02\xce\xa6\x03Pi;\x02\xce\xa0\x0aPlusMinus;\x02\xc2\xb1\x0ePoincareplane;\x03\xe2\x84\x8c\x05Popf;\x03\xe2\x84\x99\x03Pr;\x03\xe2\xaa\xbb\x09Precedes;\x03\xe2\x89\xba\x0ePrecedesEqual;\x03\xe2\xaa\xaf\x13PrecedesSlantEqual;\x03\xe2\x89\xbc\x0ePrecedesTilde;\x03\xe2\x89\xbe\x06Prime;\x03\xe2\x80\xb3\x08Product;\x03\xe2\x88\x8f\x0bProportion;\x03\xe2\x88\xb7\x0dProportional;\x03\xe2\x88\x9d\x05Pscr;\x04\xf0\x9d\x92\xab\x04Psi;\x02\xce\xa8\x04QUOT\x01\x22\x05QUOT;\x01\x22\x04Qfr;\x04\xf0\x9d\x94\x94\x05Qopf;\x03\xe2\x84\x9a\x05Qscr;\x04\xf0\x9d\x92\xac\x06RBarr;\x03\xe2\xa4\x90\x03REG\x02\xc2\xae\x04REG;\x02\xc2\xae\x07Racute;\x02\xc5\x94\x05Rang;\x03\xe2\x9f\xab\x05Rarr;\x03\xe2\x86\xa0\x07Rarrtl;\x03\xe2\xa4\x96\x07Rcaron;\x02\xc5\x98\x07Rcedil;\x02\xc5\x96\x04Rcy;\x02\xd0\xa0\x03Re;\x03\xe2\x84\x9c\x0fReverseElement;\x03\xe2\x88\x8b\x13ReverseEquilibrium;\x03\xe2\x87\x8b\x15ReverseUpEquilibrium;\x03\xe2\xa5\xaf\x04Rfr;\x03\xe2\x84\x9c\x04Rho;\x02\xce\xa1\x12RightAngleBracket;\x03\xe2\x9f\xa9\x0bRightArrow;\x03\xe2\x86\x92\x0eRightArrowBar;\x03\xe2\x87\xa5\x14RightArrowLeftArrow;\x03\xe2\x87\x84\x0dRightCeiling;\x03\xe2\x8c\x89\x13RightDoubleBracket;\x03\xe2\x9f\xa7\x13RightDownTeeVector;\x03\xe2\xa5\x9d\x10RightDownVector;\x03\xe2\x87\x82\x13RightDownVectorBar;\x03\xe2\xa5\x95\x0bRightFloor;\x03\xe2\x8c\x8b\x09RightTee;\x03\xe2\x8a\xa2\x0eRightTeeArrow;\x03\xe2\x86\xa6\x0fRightTeeVector;\x03\xe2\xa5\x9b\x0eRightTriangle;\x03\xe2\x8a\xb3\x11RightTriangleBar;\x03\xe2\xa7\x90\x13RightTriangleEqual;\x03\xe2\x8a\xb5\x12RightUpDownVector;\x03\xe2\xa5\x8f\x11RightUpTeeVector;\x03\xe2\xa5\x9c\x0eRightUpVector;\x03\xe2\x86\xbe\x11RightUpVectorBar;\x03\xe2\xa5\x94\x0cRightVector;\x03\xe2\x87\x80\x0fRightVectorBar;\x03\xe2\xa5\x93\x0bRightarrow;\x03\xe2\x87\x92\x05Ropf;\x03\xe2\x84\x9d\x0dRoundImplies;\x03\xe2\xa5\xb0\x0cRrightarrow;\x03\xe2\x87\x9b\x05Rscr;\x03\xe2\x84\x9b\x04Rsh;\x03\xe2\x86\xb1\x0cRuleDelayed;\x03\xe2\xa7\xb4\x07SHCHcy;\x02\xd0\xa9\x05SHcy;\x02\xd0\xa8\x07SOFTcy;\x02\xd0\xac\x07Sacute;\x02\xc5\x9a\x03Sc;\x03\xe2\xaa\xbc\x07Scaron;\x02\xc5\xa0\x07Scedil;\x02\xc5\x9e\x06Scirc;\x02\xc5\x9c\x04Scy;\x02\xd0\xa1\x04Sfr;\x04\xf0\x9d\x94\x96\x0fShortDownArrow;\x03\xe2\x86\x93\x0fShortLeftArrow;\x03\xe2\x86\x90\x10ShortRightArrow;\x03\xe2\x86\x92\x0dShortUpArrow;\x03\xe2\x86\x91\x06Sigma;\x02\xce\xa3\x0cSmallCircle;\x03\xe2\x88\x98\x05Sopf;\x04\xf0\x9d\x95\x8a\x05Sqrt;\x03\xe2\x88\x9a\x07Square;\x03\xe2\x96\xa1\x13SquareIntersection;\x03\xe2\x8a\x93\x0dSquareSubset;\x03\xe2\x8a\x8f\x12SquareSubsetEqual;\x03\xe2\x8a\x91\x0fSquareSuperset;\x03\xe2\x8a\x90\x14SquareSupersetEqual;\x03\xe2\x8a\x92\x0cSquareUnion;\x03\xe2\x8a\x94\x05Sscr;\x04\xf0\x9d\x92\xae\x05Star;\x03\xe2\x8b\x86\x04Sub;\x03\xe2\x8b\x90\x07Subset;\x03\xe2\x8b\x90\x0cSubsetEqual;\x03\xe2\x8a\x86\x09Succeeds;\x03\xe2\x89\xbb\x0eSucceedsEqual;\x03\xe2\xaa\xb0\x13SucceedsSlantEqual;\x03\xe2\x89\xbd\x0eSucceedsTilde;\x03\xe2\x89\xbf\x09SuchThat;\x03\xe2\x88\x8b\x04Sum;\x03\xe2\x88\x91\x04Sup;\x03\xe2\x8b\x91\x09Superset;\x03\xe2\x8a\x83\x0eSupersetEqual;\x03\xe2\x8a\x87\x07Supset;\x03\xe2\x8b\x91\x05THORN\x02\xc3\x9e\x06THORN;\x02\xc3\x9e\x06TRADE;\x03\xe2\x84\xa2\x06TSHcy;\x02\xd0\x8b\x05TScy;\x02\xd0\xa6\x04Tab;\x01\x09\x04Tau;\x02\xce\xa4\x07Tcaron;\x02\xc5\xa4\x07Tcedil;\x02\xc5\xa2\x04Tcy;\x02\xd0\xa2\x04Tfr;\x04\xf0\x9d\x94\x97\x0aTherefore;\x03\xe2\x88\xb4\x06Theta;\x02\xce\x98\x0bThickSpace;\x06\xe2\x81\x9f\xe2\x80\x8a\x0aThinSpace;\x03\xe2\x80\x89\x06Tilde;\x03\xe2\x88\xbc\x0bTildeEqual;\x03\xe2\x89\x83\x0fTildeFullEqual;\x03\xe2\x89\x85\x0bTildeTilde;\x03\xe2\x89\x88\x05Topf;\x04\xf0\x9d\x95\x8b\x0aTripleDot;\x03\xe2\x83\x9b\x05Tscr;\x04\xf0\x9d\x92\xaf\x07Tstrok;\x02\xc5\xa6\x06Uacute\x02\xc3\x9a\x07Uacute;\x02\xc3\x9a\x05Uarr;\x03\xe2\x86\x9f\x09Uarrocir;\x03\xe2\xa5\x89\x06Ubrcy;\x02\xd0\x8e\x07Ubreve;\x02\xc5\xac\x05Ucirc\x02\xc3\x9b\x06Ucirc;\x02\xc3\x9b\x04Ucy;\x02\xd0\xa3\x07Udblac;\x02\xc5\xb0\x04Ufr;\x04\xf0\x9d\x94\x98\x06Ugrave\x02\xc3\x99\x07Ugrave;\x02\xc3\x99\x06Umacr;\x02\xc5\xaa\x09UnderBar;\x01_\x0bUnderBrace;\x03\xe2\x8f\x9f\x0dUnderBracket;\x03\xe2\x8e\xb5\x11UnderParenthesis;\x03\xe2\x8f\x9d\x06Union;\x03\xe2\x8b\x83\x0aUnionPlus;\x03\xe2\x8a\x8e\x06Uogon;\x02\xc5\xb2\x05Uopf;\x04\xf0\x9d\x95\x8c\x08UpArrow;\x03\xe2\x86\x91\x0bUpArrowBar;\x03\xe2\xa4\x92\x11UpArrowDownArrow;\x03\xe2\x87\x85\x0cUpDownArrow;\x03\xe2\x86\x95\x0eUpEquilibrium;\x03\xe2\xa5\xae\x06UpTee;\x03\xe2\x8a\xa5\x0bUpTeeArrow;\x03\xe2\x86\xa5\x08Uparrow;\x03\xe2\x87\x91\x0cUpdownarrow;\x03\xe2\x87\x95\x0fUpperLeftArrow;\x03\xe2\x86\x96\x10UpperRightArrow;\x03\xe2\x86\x97\x05Upsi;\x02\xcf\x92\x08Upsilon;\x02\xce\xa5\x06Uring;\x02\xc5\xae\x05Uscr;\x04\xf0\x9d\x92\xb0\x07Utilde;\x02\xc5\xa8\x04Uuml\x02\xc3\x9c\x05Uuml;\x02\xc3\x9c\x06VDash;\x03\xe2\x8a\xab\x05Vbar;\x03\xe2\xab\xab\x04Vcy;\x02\xd0\x92\x06Vdash;\x03\xe2\x8a\xa9\x07Vdashl;\x03\xe2\xab\xa6\x04Vee;\x03\xe2\x8b\x81\x07Verbar;\x03\xe2\x80\x96\x05Vert;\x03\xe2\x80\x96\x0cVerticalBar;\x03\xe2\x88\xa3\x0dVerticalLine;\x01|\x12VerticalSeparator;\x03\xe2\x9d\x98\x0eVerticalTilde;\x03\xe2\x89\x80\x0eVeryThinSpace;\x03\xe2\x80\x8a\x04Vfr;\x04\xf0\x9d\x94\x99\x05Vopf;\x04\xf0\x9d\x95\x8d\x05Vscr;\x04\xf0\x9d\x92\xb1\x07Vvdash;\x03\xe2\x8a\xaa\x06Wcirc;\x02\xc5\xb4\x06Wedge;\x03\xe2\x8b\x80\x04Wfr;\x04\xf0\x9d\x94\x9a\x05Wopf;\x04\xf0\x9d\x95\x8e\x05Wscr;\x04\xf0\x9d\x92\xb2\x04Xfr;\x04\xf0\x9d\x94\x9b\x03Xi;\x02\xce\x9e\x05Xopf;\x04\xf0\x9d\x95\x8f\x05Xscr;\x04\xf0\x9d\x92\xb3\x05YAcy;\x02\xd0\xaf\x05YIcy;\x02\xd0\x87\x05YUcy;\x02\xd0\xae\x06Yacute\x02\xc3\x9d\x07Yacute;\x02\xc3\x9d\x06Ycirc;\x02\xc5\xb6\x04Ycy;\x02\xd0\xab\x04Yfr;\x04\xf0\x9d\x94\x9c\x05Yopf;\x04\xf0\x9d\x95\x90\x05Yscr;\x04\xf0\x9d\x92\xb4\x05Yuml;\x02\xc5\xb8\x05ZHcy;\x02\xd0\x96\x07Zacute;\x02\xc5\xb9\x07Zcaron;\x02\xc5\xbd\x04Zcy;\x02\xd0\x97\x05Zdot;\x02\xc5\xbb\x0fZeroWidthSpace;\x03\xe2\x80\x8b\x05Zeta;\x02\xce\x96\x04Zfr;\x03\xe2\x84\xa8\x05Zopf;\x03\xe2\x84\xa4\x05Zscr;\x04\xf0\x9d\x92\xb5\x06aacute\x02\xc3\xa1\x07aacute;\x02\xc3\xa1\x07abreve;\x02\xc4\x83\x03ac;\x03\xe2\x88\xbe\x04acE;\x05\xe2\x88\xbe\xcc\xb3\x04acd;\x03\xe2\x88\xbf\x05acirc\x02\xc3\xa2\x06acirc;\x02\xc3\xa2\x05acute\x02\xc2\xb4\x06acute;\x02\xc2\xb4\x04acy;\x02\xd0\xb0\x05aelig\x02\xc3\xa6\x06aelig;\x02\xc3\xa6\x03af;\x03\xe2\x81\xa1\x04afr;\x04\xf0\x9d\x94\x9e\x06agrave\x02\xc3\xa0\x07agrave;\x02\xc3\xa0\x08alefsym;\x03\xe2\x84\xb5\x06aleph;\x03\xe2\x84\xb5\x06alpha;\x02\xce\xb1\x06amacr;\x02\xc4\x81\x06amalg;\x03\xe2\xa8\xbf\x03amp\x01&\x04amp;\x01&\x04and;\x03\xe2\x88\xa7\x07andand;\x03\xe2\xa9\x95\x05andd;\x03\xe2\xa9\x9c\x09andslope;\x03\xe2\xa9\x98\x05andv;\x03\xe2\xa9\x9a\x04ang;\x03\xe2\x88\xa0\x05ange;\x03\xe2\xa6\xa4\x06angle;\x03\xe2\x88\xa0\x07angmsd;\x03\xe2\x88\xa1\x09angmsdaa;\x03\xe2\xa6\xa8\x09angmsdab;\x03\xe2\xa6\xa9\x09angmsdac;\x03\xe2\xa6\xaa\x09angmsdad;\x03\xe2\xa6\xab\x09angmsdae;\x03\xe2\xa6\xac\x09angmsdaf;\x03\xe2\xa6\xad\x09angmsdag;\x03\xe2\xa6\xae\x09angmsdah;\x03\xe2\xa6\xaf\x06angrt;\x03\xe2\x88\x9f\x08angrtvb;\x03\xe2\x8a\xbe\x09angrtvbd;\x03\xe2\xa6\x9d\x07angsph;\x03\xe2\x88\xa2\x06angst;\x02\xc3\x85\x08angzarr;\x03\xe2\x8d\xbc\x06aogon;\x02\xc4\x85\x05aopf;\x04\xf0\x9d\x95\x92\x03ap;\x03\xe2\x89\x88\x04apE;\x03\xe2\xa9\xb0\x07apacir;\x03\xe2\xa9\xaf\x04ape;\x03\xe2\x89\x8a\x05apid;\x03\xe2\x89\x8b\x05apos;\x01'\x07approx;\x03\xe2\x89\x88\x09approxeq;\x03\xe2\x89\x8a\x05aring\x02\xc3\xa5\x06aring;\x02\xc3\xa5\x05ascr;\x04\xf0\x9d\x92\xb6\x04ast;\x01*\x06asymp;\x03\xe2\x89\x88\x08asympeq;\x03\xe2\x89\x8d\x06atilde\x02\xc3\xa3\x07atilde;\x02\xc3\xa3\x04auml\x02\xc3\xa4\x05auml;\x02\xc3\xa4\x09awconint;\x03\xe2\x88\xb3\x06awint;\x03\xe2\xa8\x91\x05bNot;\x03\xe2\xab\xad\x09backcong;\x03\xe2\x89\x8c\x0cbackepsilon;\x02\xcf\xb6\x0abackprime;\x03\xe2\x80\xb5\x08backsim;\x03\xe2\x88\xbd\x0abacksimeq;\x03\xe2\x8b\x8d\x07barvee;\x03\xe2\x8a\xbd\x07barwed;\x03\xe2\x8c\x85\x09barwedge;\x03\xe2\x8c\x85\x05bbrk;\x03\xe2\x8e\xb5\x09bbrktbrk;\x03\xe2\x8e\xb6\x06bcong;\x03\xe2\x89\x8c\x04bcy;\x02\xd0\xb1\x06bdquo;\x03\xe2\x80\x9e\x07becaus;\x03\xe2\x88\xb5\x08because;\x03\xe2\x88\xb5\x08bemptyv;\x03\xe2\xa6\xb0\x06bepsi;\x02\xcf\xb6\x07bernou;\x03\xe2\x84\xac\x05beta;\x02\xce\xb2\x05beth;\x03\xe2\x84\xb6\x08between;\x03\xe2\x89\xac\x04bfr;\x04\xf0\x9d\x94\x9f\x07bigcap;\x03\xe2\x8b\x82\x08bigcirc;\x03\xe2\x97\xaf\x07bigcup;\x03\xe2\x8b\x83\x08bigodot;\x03\xe2\xa8\x80\x09bigoplus;\x03\xe2\xa8\x81\x0abigotimes;\x03\xe2\xa8\x82\x09bigsqcup;\x03\xe2\xa8\x86\x08bigstar;\x03\xe2\x98\x85\x10bigtriangledown;\x03\xe2\x96\xbd\x0ebigtriangleup;\x03\xe2\x96\xb3\x09biguplus;\x03\xe2\xa8\x84\x07bigvee;\x03\xe2\x8b\x81\x09bigwedge;\x03\xe2\x8b\x80\x07bkarow;\x03\xe2\xa4\x8d\x0dblacklozenge;\x03\xe2\xa7\xab\x0cblacksquare;\x03\xe2\x96\xaa\x0eblacktriangle;\x03\xe2\x96\xb4\x12blacktriangledown;\x03\xe2\x96\xbe\x12blacktriangleleft;\x03\xe2\x97\x82\x13blacktriangleright;\x03\xe2\x96\xb8\x06blank;\x03\xe2\x90\xa3\x06blk12;\x03\xe2\x96\x92\x06blk14;\x03\xe2\x96\x91\x06blk34;\x03\xe2\x96\x93\x06block;\x03\xe2\x96\x88\x04bne;\x04=\xe2\x83\xa5\x08bnequiv;\x06\xe2\x89\xa1\xe2\x83\xa5\x05bnot;\x03\xe2\x8c\x90\x05bopf;\x04\xf0\x9d\x95\x93\x04bot;\x03\xe2\x8a\xa5\x07bottom;\x03\xe2\x8a\xa5\x07bowtie;\x03\xe2\x8b\x88\x06boxDL;\x03\xe2\x95\x97\x06boxDR;\x03\xe2\x95\x94\x06boxDl;\x03\xe2\x95\x96\x06boxDr;\x03\xe2\x95\x93\x05boxH;\x03\xe2\x95\x90\x06boxHD;\x03\xe2\x95\xa6\x06boxHU;\x03\xe2\x95\xa9\x06boxHd;\x03\xe2\x95\xa4\x06boxHu;\x03\xe2\x95\xa7\x06boxUL;\x03\xe2\x95\x9d\x06boxUR;\x03\xe2\x95\x9a\x06boxUl;\x03\xe2\x95\x9c\x06boxUr;\x03\xe2\x95\x99\x05boxV;\x03\xe2\x95\x91\x06boxVH;\x03\xe2\x95\xac\x06boxVL;\x03\xe2\x95\xa3\x06boxVR;\x03\xe2\x95\xa0\x06boxVh;\x03\xe2\x95\xab\x06boxVl;\x03\xe2\x95\xa2\x06boxVr;\x03\xe2\x95\x9f\x07boxbox;\x03\xe2\xa7\x89\x06boxdL;\x03\xe2\x95\x95\x06boxdR;\x03\xe2\x95\x92\x06boxdl;\x03\xe2\x94\x90\x06boxdr;\x03\xe2\x94\x8c\x05boxh;\x03\xe2\x94\x80\x06boxhD;\x03\xe2\x95\xa5\x06boxhU;\x03\xe2\x95\xa8\x06boxhd;\x03\xe2\x94\xac\x06boxhu;\x03\xe2\x94\xb4\x09boxminus;\x03\xe2\x8a\x9f\x08boxplus;\x03\xe2\x8a\x9e\x09boxtimes;\x03\xe2\x8a\xa0\x06boxuL;\x03\xe2\x95\x9b\x06boxuR;\x03\xe2\x95\x98\x06boxul;\x03\xe2\x94\x98\x06boxur;\x03\xe2\x94\x94\x05boxv;\x03\xe2\x94\x82\x06boxvH;\x03\xe2\x95\xaa\x06boxvL;\x03\xe2\x95\xa1\x06boxvR;\x03\xe2\x95\x9e\x06boxvh;\x03\xe2\x94\xbc\x06boxvl;\x03\xe2\x94\xa4\x06boxvr;\x03\xe2\x94\x9c\x07bprime;\x03\xe2\x80\xb5\x06breve;\x02\xcb\x98\x06brvbar\x02\xc2\xa6\x07brvbar;\x02\xc2\xa6\x05bscr;\x04\xf0\x9d\x92\xb7\x06bsemi;\x03\xe2\x81\x8f\x05bsim;\x03\xe2\x88\xbd\x06bsime;\x03\xe2\x8b\x8d\x05bsol;\x01\x5c\x06bsolb;\x03\xe2\xa7\x85\x09bsolhsub;\x03\xe2\x9f\x88\x05bull;\x03\xe2\x80\xa2\x07bullet;\x03\xe2\x80\xa2\x05bump;\x03\xe2\x89\x8e\x06bumpE;\x03\xe2\xaa\xae\x06bumpe;\x03\xe2\x89\x8f\x07bumpeq;\x03\xe2\x89\x8f\x07cacute;\x02\xc4\x87\x04cap;\x03\xe2\x88\xa9\x07capand;\x03\xe2\xa9\x84\x09capbrcup;\x03\xe2\xa9\x89\x07capcap;\x03\xe2\xa9\x8b\x07capcup;\x03\xe2\xa9\x87\x07capdot;\x03\xe2\xa9\x80\x05caps;\x06\xe2\x88\xa9\xef\xb8\x80\x06caret;\x03\xe2\x81\x81\x06caron;\x02\xcb\x87\x06ccaps;\x03\xe2\xa9\x8d\x07ccaron;\x02\xc4\x8d\x06ccedil\x02\xc3\xa7\x07ccedil;\x02\xc3\xa7\x06ccirc;\x02\xc4\x89\x06ccups;\x03\xe2\xa9\x8c\x08ccupssm;\x03\xe2\xa9\x90\x05cdot;\x02\xc4\x8b\x05cedil\x02\xc2\xb8\x06cedil;\x02\xc2\xb8\x08cemptyv;\x03\xe2\xa6\xb2\x04cent\x02\xc2\xa2\x05cent;\x02\xc2\xa2\x0acenterdot;\x02\xc2\xb7\x04cfr;\x04\xf0\x9d\x94\xa0\x05chcy;\x02\xd1\x87\x06check;\x03\xe2\x9c\x93\x0acheckmark;\x03\xe2\x9c\x93\x04chi;\x02\xcf\x87\x04cir;\x03\xe2\x97\x8b\x05cirE;\x03\xe2\xa7\x83\x05circ;\x02\xcb\x86\x07circeq;\x03\xe2\x89\x97\x10circlearrowleft;\x03\xe2\x86\xba\x11circlearrowright;\x03\xe2\x86\xbb\x09circledR;\x02\xc2\xae\x09circledS;\x03\xe2\x93\x88\x0bcircledast;\x03\xe2\x8a\x9b\x0ccircledcirc;\x03\xe2\x8a\x9a\x0ccircleddash;\x03\xe2\x8a\x9d\x05cire;\x03\xe2\x89\x97\x09cirfnint;\x03\xe2\xa8\x90\x07cirmid;\x03\xe2\xab\xaf\x08cirscir;\x03\xe2\xa7\x82\x06clubs;\x03\xe2\x99\xa3\x09clubsuit;\x03\xe2\x99\xa3\x06colon;\x01:\x07colone;\x03\xe2\x89\x94\x08coloneq;\x03\xe2\x89\x94\x06comma;\x01,\x07commat;\x01@\x05comp;\x03\xe2\x88\x81\x07compfn;\x03\xe2\x88\x98\x0bcomplement;\x03\xe2\x88\x81\x0acomplexes;\x03\xe2\x84\x82\x05cong;\x03\xe2\x89\x85\x08congdot;\x03\xe2\xa9\xad\x07conint;\x03\xe2\x88\xae\x05copf;\x04\xf0\x9d\x95\x94\x07coprod;\x03\xe2\x88\x90\x04copy\x02\xc2\xa9\x05copy;\x02\xc2\xa9\x07copysr;\x03\xe2\x84\x97\x06crarr;\x03\xe2\x86\xb5\x06cross;\x03\xe2\x9c\x97\x05cscr;\x04\xf0\x9d\x92\xb8\x05csub;\x03\xe2\xab\x8f\x06csube;\x03\xe2\xab\x91\x05csup;\x03\xe2\xab\x90\x06csupe;\x03\xe2\xab\x92\x06ctdot;\x03\xe2\x8b\xaf\x08cudarrl;\x03\xe2\xa4\xb8\x08cudarrr;\x03\xe2\xa4\xb5\x06cuepr;\x03\xe2\x8b\x9e\x06cuesc;\x03\xe2\x8b\x9f\x07cularr;\x03\xe2\x86\xb6\x08cularrp;\x03\xe2\xa4\xbd\x04cup;\x03\xe2\x88\xaa\x09cupbrcap;\x03\xe2\xa9\x88\x07cupcap;\x03\xe2\xa9\x86\x07cupcup;\x03\xe2\xa9\x8a\x07cupdot;\x03\xe2\x8a\x8d\x06cupor;\x03\xe2\xa9\x85\x05cups;\x06\xe2\x88\xaa\xef\xb8\x80\x07curarr;\x03\xe2\x86\xb7\x08curarrm;\x03\xe2\xa4\xbc\x0ccurlyeqprec;\x03\xe2\x8b\x9e\x0ccurlyeqsucc;\x03\xe2\x8b\x9f\x09curlyvee;\x03\xe2\x8b\x8e\x0bcurlywedge;\x03\xe2\x8b\x8f\x06curren\x02\xc2\xa4\x07curren;\x02\xc2\xa4\x0fcurvearrowleft;\x03\xe2\x86\xb6\x10curvearrowright;\x03\xe2\x86\xb7\x06cuvee;\x03\xe2\x8b\x8e\x06cuwed;\x03\xe2\x8b\x8f\x09cwconint;\x03\xe2\x88\xb2\x06cwint;\x03\xe2\x88\xb1\x07cylcty;\x03\xe2\x8c\xad\x05dArr;\x03\xe2\x87\x93\x05dHar;\x03\xe2\xa5\xa5\x07dagger;\x03\xe2\x80\xa0\x07daleth;\x03\xe2\x84\xb8\x05darr;\x03\xe2\x86\x93\x05dash;\x03\xe2\x80\x90\x06dashv;\x03\xe2\x8a\xa3\x08dbkarow;\x03\xe2\xa4\x8f\x06dblac;\x02\xcb\x9d\x07dcaron;\x02\xc4\x8f\x04dcy;\x02\xd0\xb4\x03dd;\x03\xe2\x85\x86\x08ddagger;\x03\xe2\x80\xa1\x06ddarr;\x03\xe2\x87\x8a\x08ddotseq;\x03\xe2\xa9\xb7\x03deg\x02\xc2\xb0\x04deg;\x02\xc2\xb0\x06delta;\x02\xce\xb4\x08demptyv;\x03\xe2\xa6\xb1\x07dfisht;\x03\xe2\xa5\xbf\x04dfr;\x04\xf0\x9d\x94\xa1\x06dharl;\x03\xe2\x87\x83\x06dharr;\x03\xe2\x87\x82\x05diam;\x03\xe2\x8b\x84\x08diamond;\x03\xe2\x8b\x84\x0cdiamondsuit;\x03\xe2\x99\xa6\x06diams;\x03\xe2\x99\xa6\x04die;\x02\xc2\xa8\x08digamma;\x02\xcf\x9d\x06disin;\x03\xe2\x8b\xb2\x04div;\x02\xc3\xb7\x06divide\x02\xc3\xb7\x07divide;\x02\xc3\xb7\x0edivideontimes;\x03\xe2\x8b\x87\x07divonx;\x03\xe2\x8b\x87\x05djcy;\x02\xd1\x92\x07dlcorn;\x03\xe2\x8c\x9e\x07dlcrop;\x03\xe2\x8c\x8d\x07dollar;\x01$\x05dopf;\x04\xf0\x9d\x95\x95\x04dot;\x02\xcb\x99\x06doteq;\x03\xe2\x89\x90\x09doteqdot;\x03\xe2\x89\x91\x09dotminus;\x03\xe2\x88\xb8\x08dotplus;\x03\xe2\x88\x94\x0adotsquare;\x03\xe2\x8a\xa1\x0fdoublebarwedge;\x03\xe2\x8c\x86\x0adownarrow;\x03\xe2\x86\x93\x0fdowndownarrows;\x03\xe2\x87\x8a\x10downharpoonleft;\x03\xe2\x87\x83\x11downharpoonright;\x03\xe2\x87\x82\x09drbkarow;\x03\xe2\xa4\x90\x07drcorn;\x03\xe2\x8c\x9f\x07drcrop;\x03\xe2\x8c\x8c\x05dscr;\x04\xf0\x9d\x92\xb9\x05dscy;\x02\xd1\x95\x05dsol;\x03\xe2\xa7\xb6\x07dstrok;\x02\xc4\x91\x06dtdot;\x03\xe2\x8b\xb1\x05dtri;\x03\xe2\x96\xbf\x06dtrif;\x03\xe2\x96\xbe\x06duarr;\x03\xe2\x87\xb5\x06duhar;\x03\xe2\xa5\xaf\x08dwangle;\x03\xe2\xa6\xa6\x05dzcy;\x02\xd1\x9f\x09dzigrarr;\x03\xe2\x9f\xbf\x06eDDot;\x03\xe2\xa9\xb7\x05eDot;\x03\xe2\x89\x91\x06eacute\x02\xc3\xa9\x07eacute;\x02\xc3\xa9\x07easter;\x03\xe2\xa9\xae\x07ecaron;\x02\xc4\x9b\x05ecir;\x03\xe2\x89\x96\x05ecirc\x02\xc3\xaa\x06ecirc;\x02\xc3\xaa\x07ecolon;\x03\xe2\x89\x95\x04ecy;\x02\xd1\x8d\x05edot;\x02\xc4\x97\x03ee;\x03\xe2\x85\x87\x06efDot;\x03\xe2\x89\x92\x04efr;\x04\xf0\x9d\x94\xa2\x03eg;\x03\xe2\xaa\x9a\x06egrave\x02\xc3\xa8\x07egrave;\x02\xc3\xa8\x04egs;\x03\xe2\xaa\x96\x07egsdot;\x03\xe2\xaa\x98\x03el;\x03\xe2\xaa\x99\x09elinters;\x03\xe2\x8f\xa7\x04ell;\x03\xe2\x84\x93\x04els;\x03\xe2\xaa\x95\x07elsdot;\x03\xe2\xaa\x97\x06emacr;\x02\xc4\x93\x06empty;\x03\xe2\x88\x85\x09emptyset;\x03\xe2\x88\x85\x07emptyv;\x03\xe2\x88\x85\x07emsp13;\x03\xe2\x80\x84\x07emsp14;\x03\xe2\x80\x85\x05emsp;\x03\xe2\x80\x83\x04eng;\x02\xc5\x8b\x05ensp;\x03\xe2\x80\x82\x06eogon;\x02\xc4\x99\x05eopf;\x04\xf0\x9d\x95\x96\x05epar;\x03\xe2\x8b\x95\x07eparsl;\x03\xe2\xa7\xa3\x06eplus;\x03\xe2\xa9\xb1\x05epsi;\x02\xce\xb5\x08epsilon;\x02\xce\xb5\x06epsiv;\x02\xcf\xb5\x07eqcirc;\x03\xe2\x89\x96\x08eqcolon;\x03\xe2\x89\x95\x06eqsim;\x03\xe2\x89\x82\x0beqslantgtr;\x03\xe2\xaa\x96\x0ceqslantless;\x03\xe2\xaa\x95\x07equals;\x01=\x07equest;\x03\xe2\x89\x9f\x06equiv;\x03\xe2\x89\xa1\x08equivDD;\x03\xe2\xa9\xb8\x09eqvparsl;\x03\xe2\xa7\xa5\x06erDot;\x03\xe2\x89\x93\x06erarr;\x03\xe2\xa5\xb1\x05escr;\x03\xe2\x84\xaf\x06esdot;\x03\xe2\x89\x90\x05esim;\x03\xe2\x89\x82\x04eta;\x02\xce\xb7\x03eth\x02\xc3\xb0\x04eth;\x02\xc3\xb0\x04euml\x02\xc3\xab\x05euml;\x02\xc3\xab\x05euro;\x03\xe2\x82\xac\x05excl;\x01!\x06exist;\x03\xe2\x88\x83\x0cexpectation;\x03\xe2\x84\xb0\x0dexponentiale;\x03\xe2\x85\x87\x0efallingdotseq;\x03\xe2\x89\x92\x04fcy;\x02\xd1\x84\x07female;\x03\xe2\x99\x80\x07ffilig;\x03\xef\xac\x83\x06fflig;\x03\xef\xac\x80\x07ffllig;\x03\xef\xac\x84\x04ffr;\x04\xf0\x9d\x94\xa3\x06filig;\x03\xef\xac\x81\x06fjlig;\x02fj\x05flat;\x03\xe2\x99\xad\x06fllig;\x03\xef\xac\x82\x06fltns;\x03\xe2\x96\xb1\x05fnof;\x02\xc6\x92\x05fopf;\x04\xf0\x9d\x95\x97\x07forall;\x03\xe2\x88\x80\x05fork;\x03\xe2\x8b\x94\x06forkv;\x03\xe2\xab\x99\x09fpartint;\x03\xe2\xa8\x8d\x06frac12\x02\xc2\xbd\x07frac12;\x02\xc2\xbd\x07frac13;\x03\xe2\x85\x93\x06frac14\x02\xc2\xbc\x07frac14;\x02\xc2\xbc\x07frac15;\x03\xe2\x85\x95\x07frac16;\x03\xe2\x85\x99\x07frac18;\x03\xe2\x85\x9b\x07frac23;\x03\xe2\x85\x94\x07frac25;\x03\xe2\x85\x96\x06frac34\x02\xc2\xbe\x07frac34;\x02\xc2\xbe\x07frac35;\x03\xe2\x85\x97\x07frac38;\x03\xe2\x85\x9c\x07frac45;\x03\xe2\x85\x98\x07frac56;\x03\xe2\x85\x9a\x07frac58;\x03\xe2\x85\x9d\x07frac78;\x03\xe2\x85\x9e\x06frasl;\x03\xe2\x81\x84\x06frown;\x03\xe2\x8c\xa2\x05fscr;\x04\xf0\x9d\x92\xbb\x03gE;\x03\xe2\x89\xa7\x04gEl;\x03\xe2\xaa\x8c\x07gacute;\x02\xc7\xb5\x06gamma;\x02\xce\xb3\x07gammad;\x02\xcf\x9d\x04gap;\x03\xe2\xaa\x86\x07gbreve;\x02\xc4\x9f\x06gcirc;\x02\xc4\x9d\x04gcy;\x02\xd0\xb3\x05gdot;\x02\xc4\xa1\x03ge;\x03\xe2\x89\xa5\x04gel;\x03\xe2\x8b\x9b\x04geq;\x03\xe2\x89\xa5\x05geqq;\x03\xe2\x89\xa7\x09geqslant;\x03\xe2\xa9\xbe\x04ges;\x03\xe2\xa9\xbe\x06gescc;\x03\xe2\xaa\xa9\x07gesdot;\x03\xe2\xaa\x80\x08gesdoto;\x03\xe2\xaa\x82\x09gesdotol;\x03\xe2\xaa\x84\x05gesl;\x06\xe2\x8b\x9b\xef\xb8\x80\x07gesles;\x03\xe2\xaa\x94\x04gfr;\x04\xf0\x9d\x94\xa4\x03gg;\x03\xe2\x89\xab\x04ggg;\x03\xe2\x8b\x99\x06gimel;\x03\xe2\x84\xb7\x05gjcy;\x02\xd1\x93\x03gl;\x03\xe2\x89\xb7\x04glE;\x03\xe2\xaa\x92\x04gla;\x03\xe2\xaa\xa5\x04glj;\x03\xe2\xaa\xa4\x04gnE;\x03\xe2\x89\xa9\x05gnap;\x03\xe2\xaa\x8a\x09gnapprox;\x03\xe2\xaa\x8a\x04gne;\x03\xe2\xaa\x88\x05gneq;\x03\xe2\xaa\x88\x06gneqq;\x03\xe2\x89\xa9\x06gnsim;\x03\xe2\x8b\xa7\x05gopf;\x04\xf0\x9d\x95\x98\x06grave;\x01`\x05gscr;\x03\xe2\x84\x8a\x05gsim;\x03\xe2\x89\xb3\x06gsime;\x03\xe2\xaa\x8e\x06gsiml;\x03\xe2\xaa\x90\x02gt\x01>\x03gt;\x01>\x05gtcc;\x03\xe2\xaa\xa7\x06gtcir;\x03\xe2\xa9\xba\x06gtdot;\x03\xe2\x8b\x97\x07gtlPar;\x03\xe2\xa6\x95\x08gtquest;\x03\xe2\xa9\xbc\x0agtrapprox;\x03\xe2\xaa\x86\x07gtrarr;\x03\xe2\xa5\xb8\x07gtrdot;\x03\xe2\x8b\x97\x0agtreqless;\x03\xe2\x8b\x9b\x0bgtreqqless;\x03\xe2\xaa\x8c\x08gtrless;\x03\xe2\x89\xb7\x07gtrsim;\x03\xe2\x89\xb3\x0agvertneqq;\x06\xe2\x89\xa9\xef\xb8\x80\x05gvnE;\x06\xe2\x89\xa9\xef\xb8\x80\x05hArr;\x03\xe2\x87\x94\x07hairsp;\x03\xe2\x80\x8a\x05half;\x02\xc2\xbd\x07hamilt;\x03\xe2\x84\x8b\x07hardcy;\x02\xd1\x8a\x05harr;\x03\xe2\x86\x94\x08harrcir;\x03\xe2\xa5\x88\x06harrw;\x03\xe2\x86\xad\x05hbar;\x03\xe2\x84\x8f\x06hcirc;\x02\xc4\xa5\x07hearts;\x03\xe2\x99\xa5\x0aheartsuit;\x03\xe2\x99\xa5\x07hellip;\x03\xe2\x80\xa6\x07hercon;\x03\xe2\x8a\xb9\x04hfr;\x04\xf0\x9d\x94\xa5\x09hksearow;\x03\xe2\xa4\xa5\x09hkswarow;\x03\xe2\xa4\xa6\x06hoarr;\x03\xe2\x87\xbf\x07homtht;\x03\xe2\x88\xbb\x0ehookleftarrow;\x03\xe2\x86\xa9\x0fhookrightarrow;\x03\xe2\x86\xaa\x05hopf;\x04\xf0\x9d\x95\x99\x07horbar;\x03\xe2\x80\x95\x05hscr;\x04\xf0\x9d\x92\xbd\x07hslash;\x03\xe2\x84\x8f\x07hstrok;\x02\xc4\xa7\x07hybull;\x03\xe2\x81\x83\x07hyphen;\x03\xe2\x80\x90\x06iacute\x02\xc3\xad\x07iacute;\x02\xc3\xad\x03ic;\x03\xe2\x81\xa3\x05icirc\x02\xc3\xae\x06icirc;\x02\xc3\xae\x04icy;\x02\xd0\xb8\x05iecy;\x02\xd0\xb5\x05iexcl\x02\xc2\xa1\x06iexcl;\x02\xc2\xa1\x04iff;\x03\xe2\x87\x94\x04ifr;\x04\xf0\x9d\x94\xa6\x06igrave\x02\xc3\xac\x07igrave;\x02\xc3\xac\x03ii;\x03\xe2\x85\x88\x07iiiint;\x03\xe2\xa8\x8c\x06iiint;\x03\xe2\x88\xad\x07iinfin;\x03\xe2\xa7\x9c\x06iiota;\x03\xe2\x84\xa9\x06ijlig;\x02\xc4\xb3\x06imacr;\x02\xc4\xab\x06image;\x03\xe2\x84\x91\x09imagline;\x03\xe2\x84\x90\x09imagpart;\x03\xe2\x84\x91\x06imath;\x02\xc4\xb1\x05imof;\x03\xe2\x8a\xb7\x06imped;\x02\xc6\xb5\x03in;\x03\xe2\x88\x88\x07incare;\x03\xe2\x84\x85\x06infin;\x03\xe2\x88\x9e\x09infintie;\x03\xe2\xa7\x9d\x07inodot;\x02\xc4\xb1\x04int;\x03\xe2\x88\xab\x07intcal;\x03\xe2\x8a\xba\x09integers;\x03\xe2\x84\xa4\x09intercal;\x03\xe2\x8a\xba\x09intlarhk;\x03\xe2\xa8\x97\x08intprod;\x03\xe2\xa8\xbc\x05iocy;\x02\xd1\x91\x06iogon;\x02\xc4\xaf\x05iopf;\x04\xf0\x9d\x95\x9a\x05iota;\x02\xce\xb9\x06iprod;\x03\xe2\xa8\xbc\x06iquest\x02\xc2\xbf\x07iquest;\x02\xc2\xbf\x05iscr;\x04\xf0\x9d\x92\xbe\x05isin;\x03\xe2\x88\x88\x06isinE;\x03\xe2\x8b\xb9\x08isindot;\x03\xe2\x8b\xb5\x06isins;\x03\xe2\x8b\xb4\x07isinsv;\x03\xe2\x8b\xb3\x06isinv;\x03\xe2\x88\x88\x03it;\x03\xe2\x81\xa2\x07itilde;\x02\xc4\xa9\x06iukcy;\x02\xd1\x96\x04iuml\x02\xc3\xaf\x05iuml;\x02\xc3\xaf\x06jcirc;\x02\xc4\xb5\x04jcy;\x02\xd0\xb9\x04jfr;\x04\xf0\x9d\x94\xa7\x06jmath;\x02\xc8\xb7\x05jopf;\x04\xf0\x9d\x95\x9b\x05jscr;\x04\xf0\x9d\x92\xbf\x07jsercy;\x02\xd1\x98\x06jukcy;\x02\xd1\x94\x06kappa;\x02\xce\xba\x07kappav;\x02\xcf\xb0\x07kcedil;\x02\xc4\xb7\x04kcy;\x02\xd0\xba\x04kfr;\x04\xf0\x9d\x94\xa8\x07kgreen;\x02\xc4\xb8\x05khcy;\x02\xd1\x85\x05kjcy;\x02\xd1\x9c\x05kopf;\x04\xf0\x9d\x95\x9c\x05kscr;\x04\xf0\x9d\x93\x80\x06lAarr;\x03\xe2\x87\x9a\x05lArr;\x03\xe2\x87\x90\x07lAtail;\x03\xe2\xa4\x9b\x06lBarr;\x03\xe2\xa4\x8e\x03lE;\x03\xe2\x89\xa6\x04lEg;\x03\xe2\xaa\x8b\x05lHar;\x03\xe2\xa5\xa2\x07lacute;\x02\xc4\xba\x09laemptyv;\x03\xe2\xa6\xb4\x07lagran;\x03\xe2\x84\x92\x07lambda;\x02\xce\xbb\x05lang;\x03\xe2\x9f\xa8\x06langd;\x03\xe2\xa6\x91\x07langle;\x03\xe2\x9f\xa8\x04lap;\x03\xe2\xaa\x85\x05laquo\x02\xc2\xab\x06laquo;\x02\xc2\xab\x05larr;\x03\xe2\x86\x90\x06larrb;\x03\xe2\x87\xa4\x08larrbfs;\x03\xe2\xa4\x9f\x07larrfs;\x03\xe2\xa4\x9d\x07larrhk;\x03\xe2\x86\xa9\x07larrlp;\x03\xe2\x86\xab\x07larrpl;\x03\xe2\xa4\xb9\x08larrsim;\x03\xe2\xa5\xb3\x07larrtl;\x03\xe2\x86\xa2\x04lat;\x03\xe2\xaa\xab\x07latail;\x03\xe2\xa4\x99\x05late;\x03\xe2\xaa\xad\x06lates;\x06\xe2\xaa\xad\xef\xb8\x80\x06lbarr;\x03\xe2\xa4\x8c\x06lbbrk;\x03\xe2\x9d\xb2\x07lbrace;\x01{\x07lbrack;\x01[\x06lbrke;\x03\xe2\xa6\x8b\x08lbrksld;\x03\xe2\xa6\x8f\x08lbrkslu;\x03\xe2\xa6\x8d\x07lcaron;\x02\xc4\xbe\x07lcedil;\x02\xc4\xbc\x06lceil;\x03\xe2\x8c\x88\x05lcub;\x01{\x04lcy;\x02\xd0\xbb\x05ldca;\x03\xe2\xa4\xb6\x06ldquo;\x03\xe2\x80\x9c\x07ldquor;\x03\xe2\x80\x9e\x08ldrdhar;\x03\xe2\xa5\xa7\x09ldrushar;\x03\xe2\xa5\x8b\x05ldsh;\x03\xe2\x86\xb2\x03le;\x03\xe2\x89\xa4\x0aleftarrow;\x03\xe2\x86\x90\x0eleftarrowtail;\x03\xe2\x86\xa2\x10leftharpoondown;\x03\xe2\x86\xbd\x0eleftharpoonup;\x03\xe2\x86\xbc\x0fleftleftarrows;\x03\xe2\x87\x87\x0fleftrightarrow;\x03\xe2\x86\x94\x10leftrightarrows;\x03\xe2\x87\x86\x12leftrightharpoons;\x03\xe2\x87\x8b\x14leftrightsquigarrow;\x03\xe2\x86\xad\x0fleftthreetimes;\x03\xe2\x8b\x8b\x04leg;\x03\xe2\x8b\x9a\x04leq;\x03\xe2\x89\xa4\x05leqq;\x03\xe2\x89\xa6\x09leqslant;\x03\xe2\xa9\xbd\x04les;\x03\xe2\xa9\xbd\x06lescc;\x03\xe2\xaa\xa8\x07lesdot;\x03\xe2\xa9\xbf\x08lesdoto;\x03\xe2\xaa\x81\x09lesdotor;\x03\xe2\xaa\x83\x05lesg;\x06\xe2\x8b\x9a\xef\xb8\x80\x07lesges;\x03\xe2\xaa\x93\x0blessapprox;\x03\xe2\xaa\x85\x08lessdot;\x03\xe2\x8b\x96\x0alesseqgtr;\x03\xe2\x8b\x9a\x0blesseqqgtr;\x03\xe2\xaa\x8b\x08lessgtr;\x03\xe2\x89\xb6\x08lesssim;\x03\xe2\x89\xb2\x07lfisht;\x03\xe2\xa5\xbc\x07lfloor;\x03\xe2\x8c\x8a\x04lfr;\x04\xf0\x9d\x94\xa9\x03lg;\x03\xe2\x89\xb6\x04lgE;\x03\xe2\xaa\x91\x06lhard;\x03\xe2\x86\xbd\x06lharu;\x03\xe2\x86\xbc\x07lharul;\x03\xe2\xa5\xaa\x06lhblk;\x03\xe2\x96\x84\x05ljcy;\x02\xd1\x99\x03ll;\x03\xe2\x89\xaa\x06llarr;\x03\xe2\x87\x87\x09llcorner;\x03\xe2\x8c\x9e\x07llhard;\x03\xe2\xa5\xab\x06lltri;\x03\xe2\x97\xba\x07lmidot;\x02\xc5\x80\x07lmoust;\x03\xe2\x8e\xb0\x0blmoustache;\x03\xe2\x8e\xb0\x04lnE;\x03\xe2\x89\xa8\x05lnap;\x03\xe2\xaa\x89\x09lnapprox;\x03\xe2\xaa\x89\x04lne;\x03\xe2\xaa\x87\x05lneq;\x03\xe2\xaa\x87\x06lneqq;\x03\xe2\x89\xa8\x06lnsim;\x03\xe2\x8b\xa6\x06loang;\x03\xe2\x9f\xac\x06loarr;\x03\xe2\x87\xbd\x06lobrk;\x03\xe2\x9f\xa6\x0elongleftarrow;\x03\xe2\x9f\xb5\x13longleftrightarrow;\x03\xe2\x9f\xb7\x0blongmapsto;\x03\xe2\x9f\xbc\x0flongrightarrow;\x03\xe2\x9f\xb6\x0elooparrowleft;\x03\xe2\x86\xab\x0flooparrowright;\x03\xe2\x86\xac\x06lopar;\x03\xe2\xa6\x85\x05lopf;\x04\xf0\x9d\x95\x9d\x07loplus;\x03\xe2\xa8\xad\x08lotimes;\x03\xe2\xa8\xb4\x07lowast;\x03\xe2\x88\x97\x07lowbar;\x01_\x04loz;\x03\xe2\x97\x8a\x08lozenge;\x03\xe2\x97\x8a\x05lozf;\x03\xe2\xa7\xab\x05lpar;\x01(\x07lparlt;\x03\xe2\xa6\x93\x06lrarr;\x03\xe2\x87\x86\x09lrcorner;\x03\xe2\x8c\x9f\x06lrhar;\x03\xe2\x87\x8b\x07lrhard;\x03\xe2\xa5\xad\x04lrm;\x03\xe2\x80\x8e\x06lrtri;\x03\xe2\x8a\xbf\x07lsaquo;\x03\xe2\x80\xb9\x05lscr;\x04\xf0\x9d\x93\x81\x04lsh;\x03\xe2\x86\xb0\x05lsim;\x03\xe2\x89\xb2\x06lsime;\x03\xe2\xaa\x8d\x06lsimg;\x03\xe2\xaa\x8f\x05lsqb;\x01[\x06lsquo;\x03\xe2\x80\x98\x07lsquor;\x03\xe2\x80\x9a\x07lstrok;\x02\xc5\x82\x02lt\x01<\x03lt;\x01<\x05ltcc;\x03\xe2\xaa\xa6\x06ltcir;\x03\xe2\xa9\xb9\x06ltdot;\x03\xe2\x8b\x96\x07lthree;\x03\xe2\x8b\x8b\x07ltimes;\x03\xe2\x8b\x89\x07ltlarr;\x03\xe2\xa5\xb6\x08ltquest;\x03\xe2\xa9\xbb\x07ltrPar;\x03\xe2\xa6\x96\x05ltri;\x03\xe2\x97\x83\x06ltrie;\x03\xe2\x8a\xb4\x06ltrif;\x03\xe2\x97\x82\x09lurdshar;\x03\xe2\xa5\x8a\x08luruhar;\x03\xe2\xa5\xa6\x0alvertneqq;\x06\xe2\x89\xa8\xef\xb8\x80\x05lvnE;\x06\xe2\x89\xa8\xef\xb8\x80\x06mDDot;\x03\xe2\x88\xba\x04macr\x02\xc2\xaf\x05macr;\x02\xc2\xaf\x05male;\x03\xe2\x99\x82\x05malt;\x03\xe2\x9c\xa0\x08maltese;\x03\xe2\x9c\xa0\x04map;\x03\xe2\x86\xa6\x07mapsto;\x03\xe2\x86\xa6\x0bmapstodown;\x03\xe2\x86\xa7\x0bmapstoleft;\x03\xe2\x86\xa4\x09mapstoup;\x03\xe2\x86\xa5\x07marker;\x03\xe2\x96\xae\x07mcomma;\x03\xe2\xa8\xa9\x04mcy;\x02\xd0\xbc\x06mdash;\x03\xe2\x80\x94\x0emeasuredangle;\x03\xe2\x88\xa1\x04mfr;\x04\xf0\x9d\x94\xaa\x04mho;\x03\xe2\x84\xa7\x05micro\x02\xc2\xb5\x06micro;\x02\xc2\xb5\x04mid;\x03\xe2\x88\xa3\x07midast;\x01*\x07midcir;\x03\xe2\xab\xb0\x06middot\x02\xc2\xb7\x07middot;\x02\xc2\xb7\x06minus;\x03\xe2\x88\x92\x07minusb;\x03\xe2\x8a\x9f\x07minusd;\x03\xe2\x88\xb8\x08minusdu;\x03\xe2\xa8\xaa\x05mlcp;\x03\xe2\xab\x9b\x05mldr;\x03\xe2\x80\xa6\x07mnplus;\x03\xe2\x88\x93\x07models;\x03\xe2\x8a\xa7\x05mopf;\x04\xf0\x9d\x95\x9e\x03mp;\x03\xe2\x88\x93\x05mscr;\x04\xf0\x9d\x93\x82\x07mstpos;\x03\xe2\x88\xbe\x03mu;\x02\xce\xbc\x09multimap;\x03\xe2\x8a\xb8\x06mumap;\x03\xe2\x8a\xb8\x04nGg;\x05\xe2\x8b\x99\xcc\xb8\x04nGt;\x06\xe2\x89\xab\xe2\x83\x92\x05nGtv;\x05\xe2\x89\xab\xcc\xb8\x0bnLeftarrow;\x03\xe2\x87\x8d\x10nLeftrightarrow;\x03\xe2\x87\x8e\x04nLl;\x05\xe2\x8b\x98\xcc\xb8\x04nLt;\x06\xe2\x89\xaa\xe2\x83\x92\x05nLtv;\x05\xe2\x89\xaa\xcc\xb8\x0cnRightarrow;\x03\xe2\x87\x8f\x07nVDash;\x03\xe2\x8a\xaf\x07nVdash;\x03\xe2\x8a\xae\x06nabla;\x03\xe2\x88\x87\x07nacute;\x02\xc5\x84\x05nang;\x06\xe2\x88\xa0\xe2\x83\x92\x04nap;\x03\xe2\x89\x89\x05napE;\x05\xe2\xa9\xb0\xcc\xb8\x06napid;\x05\xe2\x89\x8b\xcc\xb8\x06napos;\x02\xc5\x89\x08napprox;\x03\xe2\x89\x89\x06natur;\x03\xe2\x99\xae\x08natural;\x03\xe2\x99\xae\x09naturals;\x03\xe2\x84\x95\x04nbsp\x02\xc2\xa0\x05nbsp;\x02\xc2\xa0\x06nbump;\x05\xe2\x89\x8e\xcc\xb8\x07nbumpe;\x05\xe2\x89\x8f\xcc\xb8\x05ncap;\x03\xe2\xa9\x83\x07ncaron;\x02\xc5\x88\x07ncedil;\x02\xc5\x86\x06ncong;\x03\xe2\x89\x87\x09ncongdot;\x05\xe2\xa9\xad\xcc\xb8\x05ncup;\x03\xe2\xa9\x82\x04ncy;\x02\xd0\xbd\x06ndash;\x03\xe2\x80\x93\x03ne;\x03\xe2\x89\xa0\x06neArr;\x03\xe2\x87\x97\x07nearhk;\x03\xe2\xa4\xa4\x06nearr;\x03\xe2\x86\x97\x08nearrow;\x03\xe2\x86\x97\x06nedot;\x05\xe2\x89\x90\xcc\xb8\x07nequiv;\x03\xe2\x89\xa2\x07nesear;\x03\xe2\xa4\xa8\x06nesim;\x05\xe2\x89\x82\xcc\xb8\x07nexist;\x03\xe2\x88\x84\x08nexists;\x03\xe2\x88\x84\x04nfr;\x04\xf0\x9d\x94\xab\x04ngE;\x05\xe2\x89\xa7\xcc\xb8\x04nge;\x03\xe2\x89\xb1\x05ngeq;\x03\xe2\x89\xb1\x06ngeqq;\x05\xe2\x89\xa7\xcc\xb8\x0angeqslant;\x05\xe2\xa9\xbe\xcc\xb8\x05nges;\x05\xe2\xa9\xbe\xcc\xb8\x06ngsim;\x03\xe2\x89\xb5\x04ngt;\x03\xe2\x89\xaf\x05ngtr;\x03\xe2\x89\xaf\x06nhArr;\x03\xe2\x87\x8e\x06nharr;\x03\xe2\x86\xae\x06nhpar;\x03\xe2\xab\xb2\x03ni;\x03\xe2\x88\x8b\x04nis;\x03\xe2\x8b\xbc\x05nisd;\x03\xe2\x8b\xba\x04niv;\x03\xe2\x88\x8b\x05njcy;\x02\xd1\x9a\x06nlArr;\x03\xe2\x87\x8d\x04nlE;\x05\xe2\x89\xa6\xcc\xb8\x06nlarr;\x03\xe2\x86\x9a\x05nldr;\x03\xe2\x80\xa5\x04nle;\x03\xe2\x89\xb0\x0bnleftarrow;\x03\xe2\x86\x9a\x10nleftrightarrow;\x03\xe2\x86\xae\x05nleq;\x03\xe2\x89\xb0\x06nleqq;\x05\xe2\x89\xa6\xcc\xb8\x0anleqslant;\x05\xe2\xa9\xbd\xcc\xb8\x05nles;\x05\xe2\xa9\xbd\xcc\xb8\x06nless;\x03\xe2\x89\xae\x06nlsim;\x03\xe2\x89\xb4\x04nlt;\x03\xe2\x89\xae\x06nltri;\x03\xe2\x8b\xaa\x07nltrie;\x03\xe2\x8b\xac\x05nmid;\x03\xe2\x88\xa4\x05nopf;\x04\xf0\x9d\x95\x9f\x03not\x02\xc2\xac\x04not;\x02\xc2\xac\x06notin;\x03\xe2\x88\x89\x07notinE;\x05\xe2\x8b\xb9\xcc\xb8\x09notindot;\x05\xe2\x8b\xb5\xcc\xb8\x08notinva;\x03\xe2\x88\x89\x08notinvb;\x03\xe2\x8b\xb7\x08notinvc;\x03\xe2\x8b\xb6\x06notni;\x03\xe2\x88\x8c\x08notniva;\x03\xe2\x88\x8c\x08notnivb;\x03\xe2\x8b\xbe\x08notnivc;\x03\xe2\x8b\xbd\x05npar;\x03\xe2\x88\xa6\x0anparallel;\x03\xe2\x88\xa6\x07nparsl;\x06\xe2\xab\xbd\xe2\x83\xa5\x06npart;\x05\xe2\x88\x82\xcc\xb8\x08npolint;\x03\xe2\xa8\x94\x04npr;\x03\xe2\x8a\x80\x07nprcue;\x03\xe2\x8b\xa0\x05npre;\x05\xe2\xaa\xaf\xcc\xb8\x06nprec;\x03\xe2\x8a\x80\x08npreceq;\x05\xe2\xaa\xaf\xcc\xb8\x06nrArr;\x03\xe2\x87\x8f\x06nrarr;\x03\xe2\x86\x9b\x07nrarrc;\x05\xe2\xa4\xb3\xcc\xb8\x07nrarrw;\x05\xe2\x86\x9d\xcc\xb8\x0cnrightarrow;\x03\xe2\x86\x9b\x06nrtri;\x03\xe2\x8b\xab\x07nrtrie;\x03\xe2\x8b\xad\x04nsc;\x03\xe2\x8a\x81\x07nsccue;\x03\xe2\x8b\xa1\x05nsce;\x05\xe2\xaa\xb0\xcc\xb8\x05nscr;\x04\xf0\x9d\x93\x83\x0anshortmid;\x03\xe2\x88\xa4\x0fnshortparallel;\x03\xe2\x88\xa6\x05nsim;\x03\xe2\x89\x81\x06nsime;\x03\xe2\x89\x84\x07nsimeq;\x03\xe2\x89\x84\x06nsmid;\x03\xe2\x88\xa4\x06nspar;\x03\xe2\x88\xa6\x08nsqsube;\x03\xe2\x8b\xa2\x08nsqsupe;\x03\xe2\x8b\xa3\x05nsub;\x03\xe2\x8a\x84\x06nsubE;\x05\xe2\xab\x85\xcc\xb8\x06nsube;\x03\xe2\x8a\x88\x08nsubset;\x06\xe2\x8a\x82\xe2\x83\x92\x0ansubseteq;\x03\xe2\x8a\x88\x0bnsubseteqq;\x05\xe2\xab\x85\xcc\xb8\x06nsucc;\x03\xe2\x8a\x81\x08nsucceq;\x05\xe2\xaa\xb0\xcc\xb8\x05nsup;\x03\xe2\x8a\x85\x06nsupE;\x05\xe2\xab\x86\xcc\xb8\x06nsupe;\x03\xe2\x8a\x89\x08nsupset;\x06\xe2\x8a\x83\xe2\x83\x92\x0ansupseteq;\x03\xe2\x8a\x89\x0bnsupseteqq;\x05\xe2\xab\x86\xcc\xb8\x05ntgl;\x03\xe2\x89\xb9\x06ntilde\x02\xc3\xb1\x07ntilde;\x02\xc3\xb1\x05ntlg;\x03\xe2\x89\xb8\x0entriangleleft;\x03\xe2\x8b\xaa\x10ntrianglelefteq;\x03\xe2\x8b\xac\x0fntriangleright;\x03\xe2\x8b\xab\x11ntrianglerighteq;\x03\xe2\x8b\xad\x03nu;\x02\xce\xbd\x04num;\x01#\x07numero;\x03\xe2\x84\x96\x06numsp;\x03\xe2\x80\x87\x07nvDash;\x03\xe2\x8a\xad\x07nvHarr;\x03\xe2\xa4\x84\x05nvap;\x06\xe2\x89\x8d\xe2\x83\x92\x07nvdash;\x03\xe2\x8a\xac\x05nvge;\x06\xe2\x89\xa5\xe2\x83\x92\x05nvgt;\x04>\xe2\x83\x92\x08nvinfin;\x03\xe2\xa7\x9e\x07nvlArr;\x03\xe2\xa4\x82\x05nvle;\x06\xe2\x89\xa4\xe2\x83\x92\x05nvlt;\x04<\xe2\x83\x92\x08nvltrie;\x06\xe2\x8a\xb4\xe2\x83\x92\x07nvrArr;\x03\xe2\xa4\x83\x08nvrtrie;\x06\xe2\x8a\xb5\xe2\x83\x92\x06nvsim;\x06\xe2\x88\xbc\xe2\x83\x92\x06nwArr;\x03\xe2\x87\x96\x07nwarhk;\x03\xe2\xa4\xa3\x06nwarr;\x03\xe2\x86\x96\x08nwarrow;\x03\xe2\x86\x96\x07nwnear;\x03\xe2\xa4\xa7\x03oS;\x03\xe2\x93\x88\x06oacute\x02\xc3\xb3\x07oacute;\x02\xc3\xb3\x05oast;\x03\xe2\x8a\x9b\x05ocir;\x03\xe2\x8a\x9a\x05ocirc\x02\xc3\xb4\x06ocirc;\x02\xc3\xb4\x04ocy;\x02\xd0\xbe\x06odash;\x03\xe2\x8a\x9d\x07odblac;\x02\xc5\x91\x05odiv;\x03\xe2\xa8\xb8\x05odot;\x03\xe2\x8a\x99\x07odsold;\x03\xe2\xa6\xbc\x06oelig;\x02\xc5\x93\x06ofcir;\x03\xe2\xa6\xbf\x04ofr;\x04\xf0\x9d\x94\xac\x05ogon;\x02\xcb\x9b\x06ograve\x02\xc3\xb2\x07ograve;\x02\xc3\xb2\x04ogt;\x03\xe2\xa7\x81\x06ohbar;\x03\xe2\xa6\xb5\x04ohm;\x02\xce\xa9\x05oint;\x03\xe2\x88\xae\x06olarr;\x03\xe2\x86\xba\x06olcir;\x03\xe2\xa6\xbe\x08olcross;\x03\xe2\xa6\xbb\x06oline;\x03\xe2\x80\xbe\x04olt;\x03\xe2\xa7\x80\x06omacr;\x02\xc5\x8d\x06omega;\x02\xcf\x89\x08omicron;\x02\xce\xbf\x05omid;\x03\xe2\xa6\xb6\x07ominus;\x03\xe2\x8a\x96\x05oopf;\x04\xf0\x9d\x95\xa0\x05opar;\x03\xe2\xa6\xb7\x06operp;\x03\xe2\xa6\xb9\x06oplus;\x03\xe2\x8a\x95\x03or;\x03\xe2\x88\xa8\x06orarr;\x03\xe2\x86\xbb\x04ord;\x03\xe2\xa9\x9d\x06order;\x03\xe2\x84\xb4\x08orderof;\x03\xe2\x84\xb4\x04ordf\x02\xc2\xaa\x05ordf;\x02\xc2\xaa\x04ordm\x02\xc2\xba\x05ordm;\x02\xc2\xba\x07origof;\x03\xe2\x8a\xb6\x05oror;\x03\xe2\xa9\x96\x08orslope;\x03\xe2\xa9\x97\x04orv;\x03\xe2\xa9\x9b\x05oscr;\x03\xe2\x84\xb4\x06oslash\x02\xc3\xb8\x07oslash;\x02\xc3\xb8\x05osol;\x03\xe2\x8a\x98\x06otilde\x02\xc3\xb5\x07otilde;\x02\xc3\xb5\x07otimes;\x03\xe2\x8a\x97\x09otimesas;\x03\xe2\xa8\xb6\x04ouml\x02\xc3\xb6\x05ouml;\x02\xc3\xb6\x06ovbar;\x03\xe2\x8c\xbd\x04par;\x03\xe2\x88\xa5\x04para\x02\xc2\xb6\x05para;\x02\xc2\xb6\x09parallel;\x03\xe2\x88\xa5\x07parsim;\x03\xe2\xab\xb3\x06parsl;\x03\xe2\xab\xbd\x05part;\x03\xe2\x88\x82\x04pcy;\x02\xd0\xbf\x07percnt;\x01%\x07period;\x01.\x07permil;\x03\xe2\x80\xb0\x05perp;\x03\xe2\x8a\xa5\x08pertenk;\x03\xe2\x80\xb1\x04pfr;\x04\xf0\x9d\x94\xad\x04phi;\x02\xcf\x86\x05phiv;\x02\xcf\x95\x07phmmat;\x03\xe2\x84\xb3\x06phone;\x03\xe2\x98\x8e\x03pi;\x02\xcf\x80\x0apitchfork;\x03\xe2\x8b\x94\x04piv;\x02\xcf\x96\x07planck;\x03\xe2\x84\x8f\x08planckh;\x03\xe2\x84\x8e\x07plankv;\x03\xe2\x84\x8f\x05plus;\x01+\x09plusacir;\x03\xe2\xa8\xa3\x06plusb;\x03\xe2\x8a\x9e\x08pluscir;\x03\xe2\xa8\xa2\x07plusdo;\x03\xe2\x88\x94\x07plusdu;\x03\xe2\xa8\xa5\x06pluse;\x03\xe2\xa9\xb2\x06plusmn\x02\xc2\xb1\x07plusmn;\x02\xc2\xb1\x08plussim;\x03\xe2\xa8\xa6\x08plustwo;\x03\xe2\xa8\xa7\x03pm;\x02\xc2\xb1\x09pointint;\x03\xe2\xa8\x95\x05popf;\x04\xf0\x9d\x95\xa1\x05pound\x02\xc2\xa3\x06pound;\x02\xc2\xa3\x03pr;\x03\xe2\x89\xba\x04prE;\x03\xe2\xaa\xb3\x05prap;\x03\xe2\xaa\xb7\x06prcue;\x03\xe2\x89\xbc\x04pre;\x03\xe2\xaa\xaf\x05prec;\x03\xe2\x89\xba\x0bprecapprox;\x03\xe2\xaa\xb7\x0cpreccurlyeq;\x03\xe2\x89\xbc\x07preceq;\x03\xe2\xaa\xaf\x0cprecnapprox;\x03\xe2\xaa\xb9\x09precneqq;\x03\xe2\xaa\xb5\x09precnsim;\x03\xe2\x8b\xa8\x08precsim;\x03\xe2\x89\xbe\x06prime;\x03\xe2\x80\xb2\x07primes;\x03\xe2\x84\x99\x05prnE;\x03\xe2\xaa\xb5\x06prnap;\x03\xe2\xaa\xb9\x07prnsim;\x03\xe2\x8b\xa8\x05prod;\x03\xe2\x88\x8f\x09profalar;\x03\xe2\x8c\xae\x09profline;\x03\xe2\x8c\x92\x09profsurf;\x03\xe2\x8c\x93\x05prop;\x03\xe2\x88\x9d\x07propto;\x03\xe2\x88\x9d\x06prsim;\x03\xe2\x89\xbe\x07prurel;\x03\xe2\x8a\xb0\x05pscr;\x04\xf0\x9d\x93\x85\x04psi;\x02\xcf\x88\x07puncsp;\x03\xe2\x80\x88\x04qfr;\x04\xf0\x9d\x94\xae\x05qint;\x03\xe2\xa8\x8c\x05qopf;\x04\xf0\x9d\x95\xa2\x07qprime;\x03\xe2\x81\x97\x05qscr;\x04\xf0\x9d\x93\x86\x0cquaternions;\x03\xe2\x84\x8d\x08quatint;\x03\xe2\xa8\x96\x06quest;\x01?\x08questeq;\x03\xe2\x89\x9f\x04quot\x01\x22\x05quot;\x01\x22\x06rAarr;\x03\xe2\x87\x9b\x05rArr;\x03\xe2\x87\x92\x07rAtail;\x03\xe2\xa4\x9c\x06rBarr;\x03\xe2\xa4\x8f\x05rHar;\x03\xe2\xa5\xa4\x05race;\x05\xe2\x88\xbd\xcc\xb1\x07racute;\x02\xc5\x95\x06radic;\x03\xe2\x88\x9a\x09raemptyv;\x03\xe2\xa6\xb3\x05rang;\x03\xe2\x9f\xa9\x06rangd;\x03\xe2\xa6\x92\x06range;\x03\xe2\xa6\xa5\x07rangle;\x03\xe2\x9f\xa9\x05raquo\x02\xc2\xbb\x06raquo;\x02\xc2\xbb\x05rarr;\x03\xe2\x86\x92\x07rarrap;\x03\xe2\xa5\xb5\x06rarrb;\x03\xe2\x87\xa5\x08rarrbfs;\x03\xe2\xa4\xa0\x06rarrc;\x03\xe2\xa4\xb3\x07rarrfs;\x03\xe2\xa4\x9e\x07rarrhk;\x03\xe2\x86\xaa\x07rarrlp;\x03\xe2\x86\xac\x07rarrpl;\x03\xe2\xa5\x85\x08rarrsim;\x03\xe2\xa5\xb4\x07rarrtl;\x03\xe2\x86\xa3\x06rarrw;\x03\xe2\x86\x9d\x07ratail;\x03\xe2\xa4\x9a\x06ratio;\x03\xe2\x88\xb6\x0arationals;\x03\xe2\x84\x9a\x06rbarr;\x03\xe2\xa4\x8d\x06rbbrk;\x03\xe2\x9d\xb3\x07rbrace;\x01}\x07rbrack;\x01]\x06rbrke;\x03\xe2\xa6\x8c\x08rbrksld;\x03\xe2\xa6\x8e\x08rbrkslu;\x03\xe2\xa6\x90\x07rcaron;\x02\xc5\x99\x07rcedil;\x02\xc5\x97\x06rceil;\x03\xe2\x8c\x89\x05rcub;\x01}\x04rcy;\x02\xd1\x80\x05rdca;\x03\xe2\xa4\xb7\x08rdldhar;\x03\xe2\xa5\xa9\x06rdquo;\x03\xe2\x80\x9d\x07rdquor;\x03\xe2\x80\x9d\x05rdsh;\x03\xe2\x86\xb3\x05real;\x03\xe2\x84\x9c\x08realine;\x03\xe2\x84\x9b\x09realpart;\x03\xe2\x84\x9c\x06reals;\x03\xe2\x84\x9d\x05rect;\x03\xe2\x96\xad\x03reg\x02\xc2\xae\x04reg;\x02\xc2\xae\x07rfisht;\x03\xe2\xa5\xbd\x07rfloor;\x03\xe2\x8c\x8b\x04rfr;\x04\xf0\x9d\x94\xaf\x06rhard;\x03\xe2\x87\x81\x06rharu;\x03\xe2\x87\x80\x07rharul;\x03\xe2\xa5\xac\x04rho;\x02\xcf\x81\x05rhov;\x02\xcf\xb1\x0brightarrow;\x03\xe2\x86\x92\x0frightarrowtail;\x03\xe2\x86\xa3\x11rightharpoondown;\x03\xe2\x87\x81\x0frightharpoonup;\x03\xe2\x87\x80\x10rightleftarrows;\x03\xe2\x87\x84\x12rightleftharpoons;\x03\xe2\x87\x8c\x11rightrightarrows;\x03\xe2\x87\x89\x10rightsquigarrow;\x03\xe2\x86\x9d\x10rightthreetimes;\x03\xe2\x8b\x8c\x05ring;\x02\xcb\x9a\x0drisingdotseq;\x03\xe2\x89\x93\x06rlarr;\x03\xe2\x87\x84\x06rlhar;\x03\xe2\x87\x8c\x04rlm;\x03\xe2\x80\x8f\x07rmoust;\x03\xe2\x8e\xb1\x0brmoustache;\x03\xe2\x8e\xb1\x06rnmid;\x03\xe2\xab\xae\x06roang;\x03\xe2\x9f\xad\x06roarr;\x03\xe2\x87\xbe\x06robrk;\x03\xe2\x9f\xa7\x06ropar;\x03\xe2\xa6\x86\x05ropf;\x04\xf0\x9d\x95\xa3\x07roplus;\x03\xe2\xa8\xae\x08rotimes;\x03\xe2\xa8\xb5\x05rpar;\x01)\x07rpargt;\x03\xe2\xa6\x94\x09rppolint;\x03\xe2\xa8\x92\x06rrarr;\x03\xe2\x87\x89\x07rsaquo;\x03\xe2\x80\xba\x05rscr;\x04\xf0\x9d\x93\x87\x04rsh;\x03\xe2\x86\xb1\x05rsqb;\x01]\x06rsquo;\x03\xe2\x80\x99\x07rsquor;\x03\xe2\x80\x99\x07rthree;\x03\xe2\x8b\x8c\x07rtimes;\x03\xe2\x8b\x8a\x05rtri;\x03\xe2\x96\xb9\x06rtrie;\x03\xe2\x8a\xb5\x06rtrif;\x03\xe2\x96\xb8\x09rtriltri;\x03\xe2\xa7\x8e\x08ruluhar;\x03\xe2\xa5\xa8\x03rx;\x03\xe2\x84\x9e\x07sacute;\x02\xc5\x9b\x06sbquo;\x03\xe2\x80\x9a\x03sc;\x03\xe2\x89\xbb\x04scE;\x03\xe2\xaa\xb4\x05scap;\x03\xe2\xaa\xb8\x07scaron;\x02\xc5\xa1\x06sccue;\x03\xe2\x89\xbd\x04sce;\x03\xe2\xaa\xb0\x07scedil;\x02\xc5\x9f\x06scirc;\x02\xc5\x9d\x05scnE;\x03\xe2\xaa\xb6\x06scnap;\x03\xe2\xaa\xba\x07scnsim;\x03\xe2\x8b\xa9\x09scpolint;\x03\xe2\xa8\x93\x06scsim;\x03\xe2\x89\xbf\x04scy;\x02\xd1\x81\x05sdot;\x03\xe2\x8b\x85\x06sdotb;\x03\xe2\x8a\xa1\x06sdote;\x03\xe2\xa9\xa6\x06seArr;\x03\xe2\x87\x98\x07searhk;\x03\xe2\xa4\xa5\x06searr;\x03\xe2\x86\x98\x08searrow;\x03\xe2\x86\x98\x04sect\x02\xc2\xa7\x05sect;\x02\xc2\xa7\x05semi;\x01;\x07seswar;\x03\xe2\xa4\xa9\x09setminus;\x03\xe2\x88\x96\x06setmn;\x03\xe2\x88\x96\x05sext;\x03\xe2\x9c\xb6\x04sfr;\x04\xf0\x9d\x94\xb0\x07sfrown;\x03\xe2\x8c\xa2\x06sharp;\x03\xe2\x99\xaf\x07shchcy;\x02\xd1\x89\x05shcy;\x02\xd1\x88\x09shortmid;\x03\xe2\x88\xa3\x0eshortparallel;\x03\xe2\x88\xa5\x03shy\x02\xc2\xad\x04shy;\x02\xc2\xad\x06sigma;\x02\xcf\x83\x07sigmaf;\x02\xcf\x82\x07sigmav;\x02\xcf\x82\x04sim;\x03\xe2\x88\xbc\x07simdot;\x03\xe2\xa9\xaa\x05sime;\x03\xe2\x89\x83\x06simeq;\x03\xe2\x89\x83\x05simg;\x03\xe2\xaa\x9e\x06simgE;\x03\xe2\xaa\xa0\x05siml;\x03\xe2\xaa\x9d\x06simlE;\x03\xe2\xaa\x9f\x06simne;\x03\xe2\x89\x86\x08simplus;\x03\xe2\xa8\xa4\x08simrarr;\x03\xe2\xa5\xb2\x06slarr;\x03\xe2\x86\x90\x0esmallsetminus;\x03\xe2\x88\x96\x07smashp;\x03\xe2\xa8\xb3\x09smeparsl;\x03\xe2\xa7\xa4\x05smid;\x03\xe2\x88\xa3\x06smile;\x03\xe2\x8c\xa3\x04smt;\x03\xe2\xaa\xaa\x05smte;\x03\xe2\xaa\xac\x06smtes;\x06\xe2\xaa\xac\xef\xb8\x80\x07softcy;\x02\xd1\x8c\x04sol;\x01/\x05solb;\x03\xe2\xa7\x84\x07solbar;\x03\xe2\x8c\xbf\x05sopf;\x04\xf0\x9d\x95\xa4\x07spades;\x03\xe2\x99\xa0\x0aspadesuit;\x03\xe2\x99\xa0\x05spar;\x03\xe2\x88\xa5\x06sqcap;\x03\xe2\x8a\x93\x07sqcaps;\x06\xe2\x8a\x93\xef\xb8\x80\x06sqcup;\x03\xe2\x8a\x94\x07sqcups;\x06\xe2\x8a\x94\xef\xb8\x80\x06sqsub;\x03\xe2\x8a\x8f\x07sqsube;\x03\xe2\x8a\x91\x09sqsubset;\x03\xe2\x8a\x8f\x0bsqsubseteq;\x03\xe2\x8a\x91\x06sqsup;\x03\xe2\x8a\x90\x07sqsupe;\x03\xe2\x8a\x92\x09sqsupset;\x03\xe2\x8a\x90\x0bsqsupseteq;\x03\xe2\x8a\x92\x04squ;\x03\xe2\x96\xa1\x07square;\x03\xe2\x96\xa1\x07squarf;\x03\xe2\x96\xaa\x05squf;\x03\xe2\x96\xaa\x06srarr;\x03\xe2\x86\x92\x05sscr;\x04\xf0\x9d\x93\x88\x07ssetmn;\x03\xe2\x88\x96\x07ssmile;\x03\xe2\x8c\xa3\x07sstarf;\x03\xe2\x8b\x86\x05star;\x03\xe2\x98\x86\x06starf;\x03\xe2\x98\x85\x10straightepsilon;\x02\xcf\xb5\x0cstraightphi;\x02\xcf\x95\x06strns;\x02\xc2\xaf\x04sub;\x03\xe2\x8a\x82\x05subE;\x03\xe2\xab\x85\x07subdot;\x03\xe2\xaa\xbd\x05sube;\x03\xe2\x8a\x86\x08subedot;\x03\xe2\xab\x83\x08submult;\x03\xe2\xab\x81\x06subnE;\x03\xe2\xab\x8b\x06subne;\x03\xe2\x8a\x8a\x08subplus;\x03\xe2\xaa\xbf\x08subrarr;\x03\xe2\xa5\xb9\x07subset;\x03\xe2\x8a\x82\x09subseteq;\x03\xe2\x8a\x86\x0asubseteqq;\x03\xe2\xab\x85\x0asubsetneq;\x03\xe2\x8a\x8a\x0bsubsetneqq;\x03\xe2\xab\x8b\x07subsim;\x03\xe2\xab\x87\x07subsub;\x03\xe2\xab\x95\x07subsup;\x03\xe2\xab\x93\x05succ;\x03\xe2\x89\xbb\x0bsuccapprox;\x03\xe2\xaa\xb8\x0csucccurlyeq;\x03\xe2\x89\xbd\x07succeq;\x03\xe2\xaa\xb0\x0csuccnapprox;\x03\xe2\xaa\xba\x09succneqq;\x03\xe2\xaa\xb6\x09succnsim;\x03\xe2\x8b\xa9\x08succsim;\x03\xe2\x89\xbf\x04sum;\x03\xe2\x88\x91\x05sung;\x03\xe2\x99\xaa\x04sup1\x02\xc2\xb9\x05sup1;\x02\xc2\xb9\x04sup2\x02\xc2\xb2\x05sup2;\x02\xc2\xb2\x04sup3\x02\xc2\xb3\x05sup3;\x02\xc2\xb3\x04sup;\x03\xe2\x8a\x83\x05supE;\x03\xe2\xab\x86\x07supdot;\x03\xe2\xaa\xbe\x08supdsub;\x03\xe2\xab\x98\x05supe;\x03\xe2\x8a\x87\x08supedot;\x03\xe2\xab\x84\x08suphsol;\x03\xe2\x9f\x89\x08suphsub;\x03\xe2\xab\x97\x08suplarr;\x03\xe2\xa5\xbb\x08supmult;\x03\xe2\xab\x82\x06supnE;\x03\xe2\xab\x8c\x06supne;\x03\xe2\x8a\x8b\x08supplus;\x03\xe2\xab\x80\x07supset;\x03\xe2\x8a\x83\x09supseteq;\x03\xe2\x8a\x87\x0asupseteqq;\x03\xe2\xab\x86\x0asupsetneq;\x03\xe2\x8a\x8b\x0bsupsetneqq;\x03\xe2\xab\x8c\x07supsim;\x03\xe2\xab\x88\x07supsub;\x03\xe2\xab\x94\x07supsup;\x03\xe2\xab\x96\x06swArr;\x03\xe2\x87\x99\x07swarhk;\x03\xe2\xa4\xa6\x06swarr;\x03\xe2\x86\x99\x08swarrow;\x03\xe2\x86\x99\x07swnwar;\x03\xe2\xa4\xaa\x05szlig\x02\xc3\x9f\x06szlig;\x02\xc3\x9f\x07target;\x03\xe2\x8c\x96\x04tau;\x02\xcf\x84\x05tbrk;\x03\xe2\x8e\xb4\x07tcaron;\x02\xc5\xa5\x07tcedil;\x02\xc5\xa3\x04tcy;\x02\xd1\x82\x05tdot;\x03\xe2\x83\x9b\x07telrec;\x03\xe2\x8c\x95\x04tfr;\x04\xf0\x9d\x94\xb1\x07there4;\x03\xe2\x88\xb4\x0atherefore;\x03\xe2\x88\xb4\x06theta;\x02\xce\xb8\x09thetasym;\x02\xcf\x91\x07thetav;\x02\xcf\x91\x0cthickapprox;\x03\xe2\x89\x88\x09thicksim;\x03\xe2\x88\xbc\x07thinsp;\x03\xe2\x80\x89\x06thkap;\x03\xe2\x89\x88\x07thksim;\x03\xe2\x88\xbc\x05thorn\x02\xc3\xbe\x06thorn;\x02\xc3\xbe\x06tilde;\x02\xcb\x9c\x05times\x02\xc3\x97\x06times;\x02\xc3\x97\x07timesb;\x03\xe2\x8a\xa0\x09timesbar;\x03\xe2\xa8\xb1\x07timesd;\x03\xe2\xa8\xb0\x05tint;\x03\xe2\x88\xad\x05toea;\x03\xe2\xa4\xa8\x04top;\x03\xe2\x8a\xa4\x07topbot;\x03\xe2\x8c\xb6\x07topcir;\x03\xe2\xab\xb1\x05topf;\x04\xf0\x9d\x95\xa5\x08topfork;\x03\xe2\xab\x9a\x05tosa;\x03\xe2\xa4\xa9\x07tprime;\x03\xe2\x80\xb4\x06trade;\x03\xe2\x84\xa2\x09triangle;\x03\xe2\x96\xb5\x0dtriangledown;\x03\xe2\x96\xbf\x0dtriangleleft;\x03\xe2\x97\x83\x0ftrianglelefteq;\x03\xe2\x8a\xb4\x0atriangleq;\x03\xe2\x89\x9c\x0etriangleright;\x03\xe2\x96\xb9\x10trianglerighteq;\x03\xe2\x8a\xb5\x07tridot;\x03\xe2\x97\xac\x05trie;\x03\xe2\x89\x9c\x09triminus;\x03\xe2\xa8\xba\x08triplus;\x03\xe2\xa8\xb9\x06trisb;\x03\xe2\xa7\x8d\x08tritime;\x03\xe2\xa8\xbb\x09trpezium;\x03\xe2\x8f\xa2\x05tscr;\x04\xf0\x9d\x93\x89\x05tscy;\x02\xd1\x86\x06tshcy;\x02\xd1\x9b\x07tstrok;\x02\xc5\xa7\x06twixt;\x03\xe2\x89\xac\x11twoheadleftarrow;\x03\xe2\x86\x9e\x12twoheadrightarrow;\x03\xe2\x86\xa0\x05uArr;\x03\xe2\x87\x91\x05uHar;\x03\xe2\xa5\xa3\x06uacute\x02\xc3\xba\x07uacute;\x02\xc3\xba\x05uarr;\x03\xe2\x86\x91\x06ubrcy;\x02\xd1\x9e\x07ubreve;\x02\xc5\xad\x05ucirc\x02\xc3\xbb\x06ucirc;\x02\xc3\xbb\x04ucy;\x02\xd1\x83\x06udarr;\x03\xe2\x87\x85\x07udblac;\x02\xc5\xb1\x06udhar;\x03\xe2\xa5\xae\x07ufisht;\x03\xe2\xa5\xbe\x04ufr;\x04\xf0\x9d\x94\xb2\x06ugrave\x02\xc3\xb9\x07ugrave;\x02\xc3\xb9\x06uharl;\x03\xe2\x86\xbf\x06uharr;\x03\xe2\x86\xbe\x06uhblk;\x03\xe2\x96\x80\x07ulcorn;\x03\xe2\x8c\x9c\x09ulcorner;\x03\xe2\x8c\x9c\x07ulcrop;\x03\xe2\x8c\x8f\x06ultri;\x03\xe2\x97\xb8\x06umacr;\x02\xc5\xab\x03uml\x02\xc2\xa8\x04uml;\x02\xc2\xa8\x06uogon;\x02\xc5\xb3\x05uopf;\x04\xf0\x9d\x95\xa6\x08uparrow;\x03\xe2\x86\x91\x0cupdownarrow;\x03\xe2\x86\x95\x0eupharpoonleft;\x03\xe2\x86\xbf\x0fupharpoonright;\x03\xe2\x86\xbe\x06uplus;\x03\xe2\x8a\x8e\x05upsi;\x02\xcf\x85\x06upsih;\x02\xcf\x92\x08upsilon;\x02\xcf\x85\x0bupuparrows;\x03\xe2\x87\x88\x07urcorn;\x03\xe2\x8c\x9d\x09urcorner;\x03\xe2\x8c\x9d\x07urcrop;\x03\xe2\x8c\x8e\x06uring;\x02\xc5\xaf\x06urtri;\x03\xe2\x97\xb9\x05uscr;\x04\xf0\x9d\x93\x8a\x06utdot;\x03\xe2\x8b\xb0\x07utilde;\x02\xc5\xa9\x05utri;\x03\xe2\x96\xb5\x06utrif;\x03\xe2\x96\xb4\x06uuarr;\x03\xe2\x87\x88\x04uuml\x02\xc3\xbc\x05uuml;\x02\xc3\xbc\x08uwangle;\x03\xe2\xa6\xa7\x05vArr;\x03\xe2\x87\x95\x05vBar;\x03\xe2\xab\xa8\x06vBarv;\x03\xe2\xab\xa9\x06vDash;\x03\xe2\x8a\xa8\x07vangrt;\x03\xe2\xa6\x9c\x0bvarepsilon;\x02\xcf\xb5\x09varkappa;\x02\xcf\xb0\x0bvarnothing;\x03\xe2\x88\x85\x07varphi;\x02\xcf\x95\x06varpi;\x02\xcf\x96\x0avarpropto;\x03\xe2\x88\x9d\x05varr;\x03\xe2\x86\x95\x07varrho;\x02\xcf\xb1\x09varsigma;\x02\xcf\x82\x0dvarsubsetneq;\x06\xe2\x8a\x8a\xef\xb8\x80\x0evarsubsetneqq;\x06\xe2\xab\x8b\xef\xb8\x80\x0dvarsupsetneq;\x06\xe2\x8a\x8b\xef\xb8\x80\x0evarsupsetneqq;\x06\xe2\xab\x8c\xef\xb8\x80\x09vartheta;\x02\xcf\x91\x10vartriangleleft;\x03\xe2\x8a\xb2\x11vartriangleright;\x03\xe2\x8a\xb3\x04vcy;\x02\xd0\xb2\x06vdash;\x03\xe2\x8a\xa2\x04vee;\x03\xe2\x88\xa8\x07veebar;\x03\xe2\x8a\xbb\x06veeeq;\x03\xe2\x89\x9a\x07vellip;\x03\xe2\x8b\xae\x07verbar;\x01|\x05vert;\x01|\x04vfr;\x04\xf0\x9d\x94\xb3\x06vltri;\x03\xe2\x8a\xb2\x06vnsub;\x06\xe2\x8a\x82\xe2\x83\x92\x06vnsup;\x06\xe2\x8a\x83\xe2\x83\x92\x05vopf;\x04\xf0\x9d\x95\xa7\x06vprop;\x03\xe2\x88\x9d\x06vrtri;\x03\xe2\x8a\xb3\x05vscr;\x04\xf0\x9d\x93\x8b\x07vsubnE;\x06\xe2\xab\x8b\xef\xb8\x80\x07vsubne;\x06\xe2\x8a\x8a\xef\xb8\x80\x07vsupnE;\x06\xe2\xab\x8c\xef\xb8\x80\x07vsupne;\x06\xe2\x8a\x8b\xef\xb8\x80\x08vzigzag;\x03\xe2\xa6\x9a\x06wcirc;\x02\xc5\xb5\x07wedbar;\x03\xe2\xa9\x9f\x06wedge;\x03\xe2\x88\xa7\x07wedgeq;\x03\xe2\x89\x99\x07weierp;\x03\xe2\x84\x98\x04wfr;\x04\xf0\x9d\x94\xb4\x05wopf;\x04\xf0\x9d\x95\xa8\x03wp;\x03\xe2\x84\x98\x03wr;\x03\xe2\x89\x80\x07wreath;\x03\xe2\x89\x80\x05wscr;\x04\xf0\x9d\x93\x8c\x05xcap;\x03\xe2\x8b\x82\x06xcirc;\x03\xe2\x97\xaf\x05xcup;\x03\xe2\x8b\x83\x06xdtri;\x03\xe2\x96\xbd\x04xfr;\x04\xf0\x9d\x94\xb5\x06xhArr;\x03\xe2\x9f\xba\x06xharr;\x03\xe2\x9f\xb7\x03xi;\x02\xce\xbe\x06xlArr;\x03\xe2\x9f\xb8\x06xlarr;\x03\xe2\x9f\xb5\x05xmap;\x03\xe2\x9f\xbc\x05xnis;\x03\xe2\x8b\xbb\x06xodot;\x03\xe2\xa8\x80\x05xopf;\x04\xf0\x9d\x95\xa9\x07xoplus;\x03\xe2\xa8\x81\x07xotime;\x03\xe2\xa8\x82\x06xrArr;\x03\xe2\x9f\xb9\x06xrarr;\x03\xe2\x9f\xb6\x05xscr;\x04\xf0\x9d\x93\x8d\x07xsqcup;\x03\xe2\xa8\x86\x07xuplus;\x03\xe2\xa8\x84\x06xutri;\x03\xe2\x96\xb3\x05xvee;\x03\xe2\x8b\x81\x07xwedge;\x03\xe2\x8b\x80\x06yacute\x02\xc3\xbd\x07yacute;\x02\xc3\xbd\x05yacy;\x02\xd1\x8f\x06ycirc;\x02\xc5\xb7\x04ycy;\x02\xd1\x8b\x03yen\x02\xc2\xa5\x04yen;\x02\xc2\xa5\x04yfr;\x04\xf0\x9d\x94\xb6\x05yicy;\x02\xd1\x97\x05yopf;\x04\xf0\x9d\x95\xaa\x05yscr;\x04\xf0\x9d\x93\x8e\x05yucy;\x02\xd1\x8e\x04yuml\x02\xc3\xbf\x05yuml;\x02\xc3\xbf\x07zacute;\x02\xc5\xba\x07zcaron;\x02\xc5\xbe\x04zcy;\x02\xd0\xb7\x05zdot;\x02\xc5\xbc\x07zeetrf;\x03\xe2\x84\xa8\x05zeta;\x02\xce\xb6\x04zfr;\x04\xf0\x9d\x94\xb7\x05zhcy;\x02\xd0\xb6\x08zigrarr;\x03\xe2\x87\x9d\x05zopf;\x04\xf0\x9d\x95\xab\x05zscr;\x04\xf0\x9d\x93\x8f\x04zwj;\x03\xe2\x80\x8d\x05zwnj;\x03\xe2\x80\x8c" }

// --- Entities by themselves, and the token stream without the tree.

// `& < > " '` replaced by their references (the apostrophe as `&#x27;`, since `&apos;` is
// not HTML 4), the way an attribute or text is made safe to emit.
fn escape(a: *mem.Arena, text: str) -> (str, err) {
    var needed = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c == 38u8 { needed += 5usize } else {
        if c == 60u8 || c == 62u8 { needed += 4usize } else {
        if c == 34u8 || c == 39u8 { needed += 6usize } else { needed += 1usize }
        }
        }
        i += 1usize
    }
    if needed == text.len { ret (text, ok) }
    let (out, out_error) = mem.alloc[u8](a, needed)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    i = 0usize
    while i < text.len {
        let c = text[i]
        var replacement = ""
        if c == 38u8 { replacement = "&amp;" }
        if c == 60u8 { replacement = "&lt;" }
        if c == 62u8 { replacement = "&gt;" }
        if c == 34u8 { replacement = "&quot;" }
        if c == 39u8 { replacement = "&#x27;" }
        if replacement.len == 0usize {
            out[at] = c
            at += 1usize
        } else {
            mem.copy[u8](out[at..at + replacement.len], replacement)
            at += replacement.len
        }
        i += 1usize
    }
    ret (out[..at], ok)
}

// Every named and numeric character reference in `text` decoded, as in character data (a
// legacy name without its semicolon counts).
fn unescape(a: *mem.Arena, text: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, text.len * 2usize + 8usize)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    var used = 0usize
    while at < text.len {
        if text[at] == 38u8 {
            let (written, taken) = decode_reference(text, at + 1usize, false, out[used..])
            if taken > 0usize {
                used += written
                at += 1usize + taken
                continue
            }
        }
        out[used] = text[at]
        used += 1usize
        at += 1usize
    }
    ret (out[..used], ok)
}

type TokenKind = enum u8 { StartTag, EndTag, Text, Comment, Doctype }
// `name` is the tag or DOCTYPE name, lower-cased; `value` the decoded text of a Text token
// or the body of a comment. A void element's start tag is not marked self-closing unless
// it was written with the slash.
type Token = struct { kind: TokenKind, name: str, value: str, attributes: []const Attribute, self_closing: bool }

// The token stream of `source` into `out`: (count, error), from the same tokenizer the tree
// builder uses: references decoded in text and attribute values, tag and attribute names
// lower-cased, a raw text element's body (script, style, ...) kept verbatim and a RCDATA
// one's (title, textarea) decoded. `TooLarge` when `out` fills.
fn tokenize(a: *mem.Arena, source: str, out: []Token) -> (usize, err) {
    let options = Options { max_bytes: source.len, max_nodes: 1usize, max_attributes: 64usize, max_depth: 1u16, preserve_comments: true }
    let (made, made_error) = ps_new(a, source, options)
    if made_error != ok { ret (0usize, made_error) }
    var p = made
    var tk: Tok = zero
    var count = 0usize
    while true {
        let next_error = tk_next(&p, &tk)
        if next_error != ok { ret (count, next_error) }
        if tk.kind == .Eof { break }
        if count >= out.len { ret (count, TooLarge) }
        if tk.kind == .Chars { out[count] = Token { kind: .Text, name: "", value: tk.data, attributes: zero, self_closing: false } }
        if tk.kind == .Comment { out[count] = Token { kind: .Comment, name: "", value: tk.data, attributes: zero, self_closing: false } }
        if tk.kind == .Doctype { out[count] = Token { kind: .Doctype, name: tk.name, value: "", attributes: zero, self_closing: false } }
        if tk.kind == .End { out[count] = Token { kind: .EndTag, name: tk.name, value: "", attributes: zero, self_closing: false } }
        if tk.kind == .Start {
            out[count] = Token { kind: .StartTag, name: tk.name, value: "", attributes: tk.attrs, self_closing: tk.self_closing }
            if nm_in(",title,textarea,", tk.name) { p.ts = TS_RCDATA }
            if nm_in(",style,xmp,iframe,noembed,noframes,", tk.name) { p.ts = TS_RAWTEXT }
            if str.eq(tk.name, "script") { p.ts = TS_SCRIPT }
            if str.eq(tk.name, "plaintext") { p.ts = TS_PLAINTEXT }
        }
        count += 1usize
    }
    ret (count, ok)
}

// ---- HTML as a Markdown-like outline (D4804): what a viewer's reading mode shows of a page.

type MdWriter = struct { out: []u8, n: usize, space: bool, depth_pre: bool, rule_done: bool }

const MD_MAX_DEPTH: usize = 40usize

fn md_put(w: *MdWriter, c: u8) {
    if w.n < w.out.len {
        w.out[w.n] = c
        w.n += 1usize
    }
}

fn md_put_str(w: *MdWriter, text: str) {
    var i = 0usize
    while i < text.len {
        md_put(w, text[i])
        i += 1usize
    }
}

// End the line being written (trailing spaces dropped); nothing when the output is empty or already at a line start.
fn md_end_line(w: *MdWriter) {
    while w.n > 0usize && w.out[w.n - 1usize] == 32u8 { w.n -= 1usize }
    if w.n > 0usize && w.out[w.n - 1usize] != 10u8 { md_put(w, 10u8) }
    w.space = false
}

// End the line and leave one blank line after it.
fn md_blank(w: *MdWriter) {
    md_end_line(w)
    if w.n > 0usize && !(w.n >= 2usize && w.out[w.n - 1usize] == 10u8 && w.out[w.n - 2usize] == 10u8) { md_put(w, 10u8) }
}

// Text with its runs of white space folded to one space (and none at a line start), or verbatim inside `pre`.
fn md_text(w: *MdWriter, text: str) {
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if w.depth_pre {
            md_put(w, c)
        } else if c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 || c == 12u8 {
            w.space = true
        } else {
            if w.space && w.n > 0usize && w.out[w.n - 1usize] != 10u8 && w.out[w.n - 1usize] != 32u8 { md_put(w, 32u8) }
            w.space = false
            md_put(w, c)
        }
        i += 1usize
    }
}

fn md_is(name: str, other: str) -> bool { ret str.eq(name, other) }

fn md_skipped(name: str) -> bool {
    ret md_is(name, "script") || md_is(name, "style") || md_is(name, "head") || md_is(name, "template") || md_is(name, "noscript") || md_is(name, "svg") || md_is(name, "title") || md_is(name, "iframe")
}

fn md_block(name: str) -> bool {
    ret md_is(name, "p") || md_is(name, "div") || md_is(name, "section") || md_is(name, "article") || md_is(name, "header") || md_is(name, "footer") || md_is(name, "nav") || md_is(name, "main") || md_is(name, "aside") || md_is(name, "blockquote") || md_is(name, "figure") || md_is(name, "figcaption") || md_is(name, "form") || md_is(name, "ul") || md_is(name, "ol") || md_is(name, "dl") || md_is(name, "table") || md_is(name, "address") || md_is(name, "details") || md_is(name, "summary")
}

// Write element or text node `id` and what is under it. `row_cells` counts a table row's cells (so the delimiter row
// after a header row has the right width); `ordinal` numbers the items of an `ol`.
fn md_walk(doc: *const Document, id: NodeId, w: *MdWriter, depth: usize) {
    if depth > MD_MAX_DEPTH { ret }
    let n = &doc.nodes[usize(id)]
    if n.kind == .Text {
        md_text(w, n.value)
        ret
    }
    if n.kind != .Element && n.kind != .Document { ret }
    if n.kind == .Element && n.namespace == .Html && md_skipped(n.name) { ret }
    let name = n.name
    var heading = 0usize
    if n.kind == .Element {
        if md_is(name, "h1") { heading = 1usize }
        if md_is(name, "h2") { heading = 2usize }
        if md_is(name, "h3") || md_is(name, "h4") || md_is(name, "h5") || md_is(name, "h6") { heading = 3usize }
    }
    if heading > 0usize {
        md_blank(w)
        if heading == 1usize { md_put_str(w, "# ") } else { md_put_str(w, "## ") }
        w.space = false
    } else if n.kind == .Element && md_is(name, "pre") {
        md_blank(w)
        md_put_str(w, "```\n")
        w.depth_pre = true
    } else if n.kind == .Element && md_is(name, "li") {
        md_end_line(w)
        md_put_str(w, "- ")
        w.space = false
    } else if n.kind == .Element && md_is(name, "tr") {
        md_end_line(w)
        md_put_str(w, "| ")
        w.space = false
    } else if n.kind == .Element && md_is(name, "table") {
        md_blank(w)
        w.rule_done = false
        w.space = false
    } else if n.kind == .Element && (md_is(name, "td") || md_is(name, "th")) {
        w.space = false
    } else if n.kind == .Element && md_is(name, "br") {
        md_end_line(w)
        ret
    } else if n.kind == .Element && md_is(name, "hr") {
        md_blank(w)
        ret
    } else if n.kind == .Element && md_is(name, "img") {
        let (alt, has_alt) = attribute(n, "alt")
        let (src, has_src) = attribute(n, "src")
        if w.space && w.n > 0usize && w.out[w.n - 1usize] != 10u8 { md_put(w, 32u8) }
        w.space = false
        md_put_str(w, "[image: ")
        if has_alt && alt.len > 0usize { md_put_str(w, alt) } else if has_src { md_put_str(w, src) }
        md_put(w, 93u8)
        w.space = true
        ret
    } else if n.kind == .Element && md_block(name) {
        md_blank(w)
    }
    // Children.
    var child = n.first_child
    var first_row = true
    while child != NONE {
        md_walk(doc, child, w, depth + 1usize)
        let c = &doc.nodes[usize(child)]
        // After the first row of a table (in its head, or the first `tr`) a delimiter row.
        if c.kind == .Element && md_is(c.name, "tr") && first_row && !w.rule_done && (md_is(name, "table") || md_is(name, "thead") || md_is(name, "tbody")) {
            var cells = 0usize
            var k = c.first_child
            while k != NONE {
                if doc.nodes[usize(k)].kind == .Element && (md_is(doc.nodes[usize(k)].name, "td") || md_is(doc.nodes[usize(k)].name, "th")) { cells += 1usize }
                k = doc.nodes[usize(k)].next_sibling
            }
            md_end_line(w)
            var d = 0usize
            md_put(w, 124u8)
            while d < cells {
                md_put_str(w, "---|")
                d += 1usize
            }
            md_put(w, 10u8)
            w.rule_done = true
            first_row = false
        }
        child = c.next_sibling
    }
    if heading > 0usize {
        md_blank(w)
    } else if n.kind == .Element && md_is(name, "pre") {
        w.depth_pre = false
        md_end_line(w)
        md_put_str(w, "```\n")
        md_blank(w)
    } else if n.kind == .Element && (md_is(name, "td") || md_is(name, "th")) {
        while w.n > 0usize && w.out[w.n - 1usize] == 32u8 { w.n -= 1usize }
        md_put_str(w, " | ")
        w.space = false
    } else if n.kind == .Element && md_is(name, "a") {
        let (href, has_href) = attribute(n, "href")
        if has_href && href.len > 0usize && href.len <= 80usize && href[0usize] != 35u8 {
            md_put_str(w, " (")
            md_put_str(w, href)
            md_put(w, 41u8)
            w.space = true
        }
    } else if n.kind == .Element && md_is(name, "tr") {
        md_end_line(w)
    } else if n.kind == .Element && md_block(name) {
        md_blank(w)
    }
}

// The text of an HTML page as Markdown the viewers draw: `h1` is `# `, other headings `## `, a list item `- `, a table
// row `| a | b |` with a `|---|---|` row after the first, `pre` a fenced block, an image `[image: alt]`, a link `text (url)`
// (an absolute or relative URL of at most 80 bytes; a fragment link shows its text only); script, style, head,
// template, svg and iframe are dropped; white space is folded outside `pre`. The result is at most 3 x the source.
fn to_markdown(a: *mem.Arena, source: str) -> (str, err) {
    let (doc, parse_error) = parse(a, source, Options { max_bytes: 4194304usize, max_nodes: 65536usize, max_attributes: 32usize, max_depth: 64u16, preserve_comments: false })
    if parse_error != ok { ret ("", parse_error) }
    let (out, out_error) = mem.alloc[u8](a, source.len * 3usize + 64usize)
    if out_error != ok { ret ("", out_error) }
    var w = MdWriter { out: out, n: 0usize, space: false, depth_pre: false, rule_done: false }
    md_walk(&doc, 0u32, &w, 0usize)
    md_end_line(&w)
    while w.n > 0usize && w.out[w.n - 1usize] == 10u8 { w.n -= 1usize }
    ret (out[0usize..w.n], ok)
}

// =====================================================================================
// WHATWG parsing: tokenizer states and tree construction (insertion modes), after
// https://html.spec.whatwg.org/multipage/parsing.html. `parse` and `parse_fragment`
// drive `Ps`; the tokenizer is pulled one token at a time because the tree builder
// switches its state (RCDATA, RAWTEXT, script data, PLAINTEXT) and asks whether the
// adjusted current node is foreign (CDATA).
// =====================================================================================

type TokKind = enum u8 { Chars, Start, End, Comment, Doctype, Eof }
type Tok = struct { kind: TokKind, name: str, data: str, attrs: []const Attribute, self_closing: bool, force_quirks: bool, public_id: str, system_id: str }

const TS_DATA: u8 = 0u8
const TS_RCDATA: u8 = 1u8
const TS_RAWTEXT: u8 = 2u8
const TS_SCRIPT: u8 = 3u8
const TS_PLAINTEXT: u8 = 4u8

const M_INITIAL: u8 = 0u8
const M_BEFORE_HTML: u8 = 1u8
const M_BEFORE_HEAD: u8 = 2u8
const M_IN_HEAD: u8 = 3u8
const M_IN_HEAD_NOSCRIPT: u8 = 4u8
const M_AFTER_HEAD: u8 = 5u8
const M_IN_BODY: u8 = 6u8
const M_TEXT: u8 = 7u8
const M_IN_TABLE: u8 = 8u8
const M_IN_TABLE_TEXT: u8 = 9u8
const M_IN_CAPTION: u8 = 10u8
const M_IN_COLGROUP: u8 = 11u8
const M_IN_TBODY: u8 = 12u8
const M_IN_ROW: u8 = 13u8
const M_IN_CELL: u8 = 14u8
const M_IN_SELECT: u8 = 15u8
const M_IN_SELECT_TABLE: u8 = 16u8
const M_IN_TEMPLATE: u8 = 17u8
const M_AFTER_BODY: u8 = 18u8
const M_IN_FRAMESET: u8 = 19u8
const M_AFTER_FRAMESET: u8 = 20u8
const M_AFTER_AFTER_BODY: u8 = 21u8
const M_AFTER_AFTER_FRAMESET: u8 = 22u8

const Q_NO: u8 = 0u8
const Q_LIMITED: u8 = 1u8
const Q_QUIRKS: u8 = 2u8

const SC_DEFAULT: u8 = 0u8
const SC_LIST: u8 = 1u8
const SC_BUTTON: u8 = 2u8
const SC_TABLE: u8 = 3u8
const SC_SELECT: u8 = 4u8

type Ps = struct {
    a: *mem.Arena, src: str, pos: usize,
    nodes: []Node, used: usize, options: Options,
    ts: u8, last_start: str,
    open: []NodeId, nopen: usize,
    fmt: []NodeId, nfmt: usize,
    tmodes: [64]u8, ntmodes: usize,
    mode: u8, orig_mode: u8,
    head: NodeId, form: NodeId, ctx: NodeId, fragment: bool,
    frameset_ok: bool, foster: bool, quirks: u8, ignore_lf: bool, stopped: bool, scripting: bool,
    pend: []u8, npend: usize, xml: bool
}

fn nm_in(set: str, name: str) -> bool {
    var i = 1usize
    while i < set.len {
        var j = i
        while j < set.len && set[j] != 44u8 { j += 1usize }
        if j - i == name.len && str.eq(set[i..j], name) { ret true }
        i = j + 1usize
    }
    ret false
}

// --- Nodes.

fn pn_new(p: *Ps, kind: NodeKind, ns: Namespace, name: str, value: str) -> (NodeId, err) {
    if p.used >= p.nodes.len { ret (NONE, TooLarge) }
    let id = u32(p.used)
    p.nodes[p.used] = Node { kind: kind, namespace: ns, name: name, value: value, attributes: zero, parent: NONE, first_child: NONE, last_child: NONE, previous_sibling: NONE, next_sibling: NONE, flags: 0u32 }
    p.used += 1usize
    ret (id, ok)
}

fn pn_detach(p: *Ps, id: NodeId) {
    let parent = p.nodes[usize(id)].parent
    if parent == NONE { ret }
    let prev = p.nodes[usize(id)].previous_sibling
    let next = p.nodes[usize(id)].next_sibling
    if prev == NONE { p.nodes[usize(parent)].first_child = next } else { p.nodes[usize(prev)].next_sibling = next }
    if next == NONE { p.nodes[usize(parent)].last_child = prev } else { p.nodes[usize(next)].previous_sibling = prev }
    p.nodes[usize(id)].parent = NONE
    p.nodes[usize(id)].previous_sibling = NONE
    p.nodes[usize(id)].next_sibling = NONE
}

// Inserts the detached `id` under `parent` before `before` (NONE: at the end).
fn pn_insert(p: *Ps, parent: NodeId, id: NodeId, before: NodeId) {
    p.nodes[usize(id)].parent = parent
    if before == NONE {
        let last = p.nodes[usize(parent)].last_child
        p.nodes[usize(id)].previous_sibling = last
        p.nodes[usize(id)].next_sibling = NONE
        if last == NONE { p.nodes[usize(parent)].first_child = id } else { p.nodes[usize(last)].next_sibling = id }
        p.nodes[usize(parent)].last_child = id
        ret
    }
    let prev = p.nodes[usize(before)].previous_sibling
    p.nodes[usize(id)].previous_sibling = prev
    p.nodes[usize(id)].next_sibling = before
    p.nodes[usize(before)].previous_sibling = id
    if prev == NONE { p.nodes[usize(parent)].first_child = id } else { p.nodes[usize(prev)].next_sibling = id }
}

// Text at (parent, before): merges into an adjacent text node.
fn pn_text(p: *Ps, parent: NodeId, before: NodeId, data: str) -> err {
    if data.len == 0usize { ret ok }
    var prev = p.nodes[usize(parent)].last_child
    if before != NONE { prev = p.nodes[usize(before)].previous_sibling }
    if prev != NONE && p.nodes[usize(prev)].kind == .Text {
        let old = p.nodes[usize(prev)].value
        let merged = try mem.alloc[u8](p.a, old.len + data.len)
        mem.copy[u8](merged[..old.len], old)
        mem.copy[u8](merged[old.len..], data)
        p.nodes[usize(prev)].value = merged
        ret ok
    }
    let id = try pn_new(p, .Text, .Html, "", data)
    pn_insert(p, parent, id, before)
    ret ok
}

fn pn_element(p: *Ps, ns: Namespace, name: str, attrs: []const Attribute) -> (NodeId, err) {
    let (id, e) = pn_new(p, .Element, ns, name, "")
    if e != ok { ret (NONE, e) }
    p.nodes[usize(id)].attributes = attrs
    ret (id, ok)
}

fn pn_is(p: *Ps, id: NodeId, name: str) -> bool {
    if id == NONE { ret false }
    ret p.nodes[usize(id)].namespace == .Html && str.eq(p.nodes[usize(id)].name, name)
}

fn pn_in(p: *Ps, id: NodeId, set: str) -> bool {
    if id == NONE { ret false }
    ret p.nodes[usize(id)].namespace == .Html && nm_in(set, p.nodes[usize(id)].name)
}

// --- The tokenizer.

fn ws_byte(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 12u8 || c == 13u8 }

fn ascii_eq_fold(x: str, y: str) -> bool { ret str.compare_ascii_fold(x, y) == 0i32 }

// Copies `s` when it holds an upper-case letter (with `lower_it`) or a NUL (which
// becomes U+FFFD); otherwise returns it unchanged.
fn tk_clean(p: *Ps, s: str, lower_it: bool) -> (str, err) {
    var nuls = 0usize
    var upper = false
    var i = 0usize
    while i < s.len {
        if s[i] == 0u8 { nuls += 1usize }
        if lower_it && s[i] >= 65u8 && s[i] <= 90u8 { upper = true }
        i += 1usize
    }
    if nuls == 0usize && !upper { ret (s, ok) }
    let out = try mem.alloc[u8](p.a, s.len + nuls * 2usize)
    var at = 0usize
    i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 0u8 {
            out[at] = 239u8
            out[at + 1usize] = 191u8
            out[at + 2usize] = 189u8
            at += 3usize
        } else {
            if lower_it && c >= 65u8 && c <= 90u8 { out[at] = c + 32u8 } else { out[at] = c }
            at += 1usize
        }
        i += 1usize
    }
    ret (out[..at], ok)
}

// `s` with references decoded (and NUL as U+FFFD when `nul_fffd`).
fn tk_decode(p: *Ps, s: str, in_attribute: bool, nul_fffd: bool) -> (str, err) {
    var special = false
    var i = 0usize
    while i < s.len {
        if s[i] == 38u8 || (nul_fffd && s[i] == 0u8) { special = true }
        i += 1usize
    }
    if !special { ret (s, ok) }
    let out = try mem.alloc[u8](p.a, s.len * 3usize + 8usize)
    var at = 0usize
    var used = 0usize
    while at < s.len {
        let c = s[at]
        if c == 38u8 {
            let (written, taken) = decode_reference(s, at + 1usize, in_attribute, out[used..])
            if taken > 0usize {
                used += written
                at += 1usize + taken
                continue
            }
        }
        if c == 0u8 && nul_fffd {
            used = write_utf8(65533u32, out, used)
        } else {
            out[used] = c
            used += 1usize
        }
        at += 1usize
    }
    ret (out[..used], ok)
}

fn tk_reset(tk: *Tok) {
    tk.kind = .Eof
    tk.name = ""
    tk.data = ""
    tk.attrs = no_attrs()
    tk.self_closing = false
    tk.force_quirks = false
    tk.public_id = ""
    tk.system_id = ""
}

fn tk_chars(p: *Ps, tk: *Tok, start: usize, stop: usize, decode: bool, nul_fffd: bool) -> err {
    var data = p.src[start..stop]
    if decode {
        data = try tk_decode(p, data, false, nul_fffd)
    } else {
        if nul_fffd { data = try tk_clean(p, data, false) }
    }
    p.pos = stop
    tk.kind = .Chars
    tk.data = data
    ret ok
}

fn tk_comment(p: *Ps, tk: *Tok, start: usize, stop: usize) -> err {
    tk.kind = .Comment
    tk.data = try tk_clean(p, p.src[start..stop], false)
    ret ok
}

// A bogus comment from `start` to the next `>` (or the end); consumes the `>`.
fn tk_bogus(p: *Ps, tk: *Tok, start: usize) -> err {
    let (close, found) = str.find_from(p.src, ">", start)
    if found {
        p.pos = close + 1usize
        ret tk_comment(p, tk, start, close)
    }
    p.pos = p.src.len
    ret tk_comment(p, tk, start, p.src.len)
}

// Skips a DOCTYPE's remains after an error: to the next `>`.
fn tk_skip_gt(p: *Ps, from: usize) -> usize {
    let (close, found) = str.find_from(p.src, ">", from)
    if found { ret close + 1usize }
    ret p.src.len
}

fn tk_skip_ws(s: str, from: usize) -> usize {
    var i = from
    while i < s.len && ws_byte(s[i]) { i += 1usize }
    ret i
}

type Quoted = struct { text: str, next: usize, closed: bool }

// A quoted identifier at `i` (the quote).
fn tk_quoted(p: *Ps, i: usize) -> (Quoted, err) {
    let s = p.src
    let quote = s[i]
    var j = i + 1usize
    while j < s.len && s[j] != quote { j += 1usize }
    let raw = try tk_clean(p, s[i + 1usize..j], false)
    if j >= s.len { ret (Quoted { text: raw, next: s.len, closed: false }, ok) }
    ret (Quoted { text: raw, next: j + 1usize, closed: true }, ok)
}

// `<!DOCTYPE` was matched; `p.pos` is after it.
fn tk_doctype(p: *Ps, tk: *Tok) -> err {
    let s = p.src
    tk.kind = .Doctype
    var i = tk_skip_ws(s, p.pos)
    if i >= s.len {
        tk.force_quirks = true
        p.pos = s.len
        ret ok
    }
    if s[i] == 62u8 {
        tk.force_quirks = true
        p.pos = i + 1usize
        ret ok
    }
    let name_start = i
    while i < s.len && !ws_byte(s[i]) && s[i] != 62u8 { i += 1usize }
    tk.name = try tk_clean(p, s[name_start..i], true)
    i = tk_skip_ws(s, i)
    if i >= s.len {
        tk.force_quirks = true
        p.pos = s.len
        ret ok
    }
    if s[i] == 62u8 {
        p.pos = i + 1usize
        ret ok
    }
    var is_public = false
    var is_system = false
    if i + 6usize <= s.len && ascii_eq_fold(s[i..i + 6usize], "public") { is_public = true }
    if i + 6usize <= s.len && ascii_eq_fold(s[i..i + 6usize], "system") { is_system = true }
    if !is_public && !is_system {
        tk.force_quirks = true
        p.pos = tk_skip_gt(p, i)
        ret ok
    }
    i = tk_skip_ws(s, i + 6usize)
    if i >= s.len {
        tk.force_quirks = true
        p.pos = s.len
        ret ok
    }
    if s[i] != 34u8 && s[i] != 39u8 {
        tk.force_quirks = true
        if s[i] == 62u8 { p.pos = i + 1usize } else { p.pos = tk_skip_gt(p, i) }
        ret ok
    }
    let first = try tk_quoted(p, i)
    if is_public { tk.public_id = first.text } else { tk.system_id = first.text }
    i = first.next
    if !first.closed {
        tk.force_quirks = true
        p.pos = s.len
        ret ok
    }
    i = tk_skip_ws(s, i)
    if i >= s.len {
        tk.force_quirks = true
        p.pos = s.len
        ret ok
    }
    if s[i] == 62u8 {
        p.pos = i + 1usize
        ret ok
    }
    if is_public && (s[i] == 34u8 || s[i] == 39u8) {
        let second = try tk_quoted(p, i)
        tk.system_id = second.text
        if !second.closed {
            tk.force_quirks = true
            p.pos = s.len
            ret ok
        }
        i = tk_skip_ws(s, second.next)
        if i >= s.len {
            tk.force_quirks = true
            p.pos = s.len
            ret ok
        }
        if s[i] == 62u8 { p.pos = i + 1usize } else { p.pos = tk_skip_gt(p, i) }
        ret ok
    }
    if is_public { tk.force_quirks = true }
    p.pos = tk_skip_gt(p, i)
    ret ok
}

// A tag whose name starts at `p.pos`. A tag cut off by the end of the input is dropped (Eof).
fn tk_tag(p: *Ps, tk: *Tok, is_end: bool) -> err {
    let s = p.src
    var i = p.pos
    let name_start = i
    while i < s.len && !ws_byte(s[i]) && s[i] != 47u8 && s[i] != 62u8 { i += 1usize }
    if i >= s.len {
        p.pos = s.len
        tk.kind = .Eof
        ret ok
    }
    tk.name = try tk_clean(p, s[name_start..i], true)
    var buf: [64]Attribute = zero
    var count = 0usize
    var self_closing = false
    while true {
        i = tk_skip_ws(s, i)
        if i >= s.len {
            p.pos = s.len
            tk.kind = .Eof
            tk.name = ""
            ret ok
        }
        let c = s[i]
        if c == 62u8 {
            i += 1usize
            break
        }
        if c == 47u8 {
            i += 1usize
            if i < s.len && s[i] == 62u8 {
                self_closing = true
                i += 1usize
                break
            }
            continue
        }
        let attr_start = i
        i += 1usize
        while i < s.len && !ws_byte(s[i]) && s[i] != 47u8 && s[i] != 62u8 && s[i] != 61u8 { i += 1usize }
        let attr_name = try tk_clean(p, s[attr_start..i], true)
        var value: str = ""
        let after_name = tk_skip_ws(s, i)
        if after_name < s.len && s[after_name] == 61u8 {
            i = tk_skip_ws(s, after_name + 1usize)
            if i >= s.len {
                p.pos = s.len
                tk.kind = .Eof
                tk.name = ""
                ret ok
            }
            var raw: str = ""
            if s[i] == 34u8 || s[i] == 39u8 {
                let quote = s[i]
                let value_start = i + 1usize
                var j = value_start
                while j < s.len && s[j] != quote { j += 1usize }
                if j >= s.len {
                    p.pos = s.len
                    tk.kind = .Eof
                    tk.name = ""
                    ret ok
                }
                raw = s[value_start..j]
                i = j + 1usize
            } else {
                let value_start = i
                while i < s.len && !ws_byte(s[i]) && s[i] != 62u8 { i += 1usize }
                raw = s[value_start..i]
            }
            value = try tk_decode(p, raw, true, true)
        } else {
            i = after_name
        }
        var duplicate = false
        var k = 0usize
        while k < count {
            if str.eq(buf[k].name, attr_name) { duplicate = true }
            k += 1usize
        }
        if duplicate || is_end { continue }
        if count >= p.options.max_attributes || count >= 64usize { ret TooLarge }
        buf[count] = Attribute { namespace: .Html, name: attr_name, value: value }
        count += 1usize
    }
    p.pos = i
    if is_end {
        tk.kind = .End
    } else {
        tk.kind = .Start
        p.last_start = tk.name
    }
    tk.self_closing = self_closing
    if count > 0usize {
        let copy = try mem.alloc[Attribute](p.a, count)
        mem.copy[Attribute](copy, buf[0..count])
        tk.attrs = copy
    }
    ret ok
}

// Text in RCDATA, RAWTEXT, script data: up to the appropriate end tag.
fn tk_special(p: *Ps, tk: *Tok) -> err {
    let s = p.src
    let n = s.len
    let start = p.pos
    var i = start
    var esc = 0u8
    let is_script = p.ts == TS_SCRIPT
    let name_len = p.last_start.len
    while i < n {
        let c = s[i]
        if c == 60u8 {
            if i + 1usize < n && s[i + 1usize] == 47u8 {
                if name_len > 0usize && i + 2usize + name_len < n && ascii_eq_fold(s[i + 2usize..i + 2usize + name_len], p.last_start) {
                    let d = s[i + 2usize + name_len]
                    if ws_byte(d) || d == 47u8 || d == 62u8 {
                        if is_script && esc == 2u8 {
                            esc = 1u8
                            i += 2usize + name_len
                            continue
                        }
                        if i > start { ret tk_chars(p, tk, start, i, p.ts == TS_RCDATA, true) }
                        p.pos = i + 2usize
                        try tk_tag(p, tk, true)
                        p.ts = TS_DATA
                        ret ok
                    }
                }
                i += 1usize
                continue
            }
            if is_script {
                if esc == 0u8 && str.starts_with(s[i..], "<!--") {
                    esc = 1u8
                    i += 4usize
                    if i < n && s[i] == 62u8 { esc = 0u8 }
                    if i + 1usize < n && s[i] == 45u8 && s[i + 1usize] == 62u8 { esc = 0u8 }
                    continue
                }
                if esc == 1u8 && i + 7usize < n && ascii_eq_fold(s[i + 1usize..i + 7usize], "script") {
                    let d = s[i + 7usize]
                    if ws_byte(d) || d == 47u8 || d == 62u8 {
                        esc = 2u8
                        i += 7usize
                        continue
                    }
                }
            }
            i += 1usize
            continue
        }
        if c == 45u8 && is_script && esc >= 1u8 && str.starts_with(s[i..], "-->") {
            esc = 0u8
            i += 3usize
            continue
        }
        i += 1usize
    }
    ret tk_chars(p, tk, start, n, p.ts == TS_RCDATA, true)
}

// A `<` at `i` that opens a tag, an end tag, a declaration or a bogus comment.
fn tk_markup_at(s: str, i: usize) -> bool {
    if s[i] != 60u8 || i + 1usize >= s.len { ret false }
    let d = s[i + 1usize]
    ret str.is_ascii_alpha(d) || d == 33u8 || d == 47u8 || d == 63u8
}

fn tk_next(p: *Ps, tk: *Tok) -> err {
    let s = p.src
    let n = s.len
    while true {
        tk_reset(tk)
        if p.pos >= n { ret ok }
        if p.ts == TS_PLAINTEXT { ret tk_chars(p, tk, p.pos, n, false, true) }
        if p.ts != TS_DATA { ret tk_special(p, tk) }
        let start = p.pos
        if !tk_markup_at(s, start) {
            var i = start + 1usize
            while i < n && !tk_markup_at(s, i) { i += 1usize }
            ret tk_chars(p, tk, start, i, true, false)
        }
        let d = s[start + 1usize]
        if str.is_ascii_alpha(d) {
            p.pos = start + 1usize
            ret tk_tag(p, tk, false)
        }
        if d == 47u8 {
            if start + 2usize >= n { ret tk_chars(p, tk, start, n, false, false) }
            let e = s[start + 2usize]
            if str.is_ascii_alpha(e) {
                p.pos = start + 2usize
                ret tk_tag(p, tk, true)
            }
            if e == 62u8 {
                p.pos = start + 3usize
                continue
            }
            ret tk_bogus(p, tk, start + 2usize)
        }
        if d == 63u8 { ret tk_bogus(p, tk, start + 1usize) }
        // `<!`
        if str.starts_with(s[start..], "<!--") {
            var from = start + 4usize
            if from < n && s[from] == 62u8 {
                p.pos = from + 1usize
                tk.kind = .Comment
                ret ok
            }
            if from + 1usize < n && s[from] == 45u8 && s[from + 1usize] == 62u8 {
                p.pos = from + 2usize
                tk.kind = .Comment
                ret ok
            }
            var j = from
            var stop = n
            var next = n
            while j < n {
                if j + 3usize <= n && s[j] == 45u8 && s[j + 1usize] == 45u8 && s[j + 2usize] == 62u8 {
                    stop = j
                    next = j + 3usize
                    break
                }
                if j + 4usize <= n && s[j] == 45u8 && s[j + 1usize] == 45u8 && s[j + 2usize] == 33u8 && s[j + 3usize] == 62u8 {
                    stop = j
                    next = j + 4usize
                    break
                }
                j += 1usize
            }
            if next == n && stop == n {
                if stop - 3usize >= from && s[stop - 1usize] == 33u8 && s[stop - 2usize] == 45u8 && s[stop - 3usize] == 45u8 { stop -= 3usize } else {
                    if stop - 2usize >= from && s[stop - 1usize] == 45u8 && s[stop - 2usize] == 45u8 { stop -= 2usize } else {
                        if stop - 1usize >= from && s[stop - 1usize] == 45u8 { stop -= 1usize }
                    }
                }
            }
            p.pos = next
            ret tk_comment(p, tk, from, stop)
        }
        if start + 9usize <= n && ascii_eq_fold(s[start + 2usize..start + 9usize], "doctype") {
            p.pos = start + 9usize
            ret tk_doctype(p, tk)
        }
        if start + 9usize <= n && str.starts_with(s[start..], "<![CDATA[") && tb_foreign_adjusted(p) {
            let (close, found) = str.find_from(s, "]]>", start + 9usize)
            var stop = n
            var next = n
            if found {
                stop = close
                next = close + 3usize
            }
            if stop == start + 9usize {
                p.pos = next
                continue
            }
            tk.kind = .Chars
            tk.data = s[start + 9usize..stop]
            p.pos = next
            ret ok
        }
        ret tk_bogus(p, tk, start + 2usize)
    }
    ret ok
}

// --- Tree construction: stack, scope, insertion and the formatting list.

type Place = struct { parent: NodeId, before: NodeId }

fn tb_cur(p: *Ps) -> NodeId {
    if p.nopen == 0usize { ret NONE }
    ret p.open[p.nopen - 1usize]
}

fn tb_push(p: *Ps, id: NodeId) -> err {
    if p.nopen >= p.open.len { ret TooDeep }
    p.open[p.nopen] = id
    p.nopen += 1usize
    ret ok
}

fn tb_pop(p: *Ps) {
    if p.nopen > 0usize { p.nopen -= 1usize }
}

fn tb_open_index(p: *Ps, id: NodeId) -> (usize, bool) {
    var i = p.nopen
    while i > 0usize {
        i -= 1usize
        if p.open[i] == id { ret (i, true) }
    }
    ret (0usize, false)
}

fn tb_open_remove_at(p: *Ps, at: usize) {
    var i = at
    while i + 1usize < p.nopen {
        p.open[i] = p.open[i + 1usize]
        i += 1usize
    }
    p.nopen -= 1usize
}

fn tb_open_has(p: *Ps, name: str) -> bool {
    var i = 0usize
    while i < p.nopen {
        if pn_is(p, p.open[i], name) { ret true }
        i += 1usize
    }
    ret false
}

fn tb_pop_until(p: *Ps, name: str) {
    while p.nopen > 0usize {
        let id = tb_cur(p)
        tb_pop(p)
        if pn_is(p, id, name) { break }
    }
}

fn tb_pop_until_set(p: *Ps, set: str) {
    while p.nopen > 0usize {
        let id = tb_cur(p)
        tb_pop(p)
        if pn_in(p, id, set) { break }
    }
}

fn tb_special(p: *Ps, id: NodeId) -> bool {
    let n = &p.nodes[usize(id)]
    if n.namespace == .Html {
        ret nm_in(",address,applet,area,article,aside,base,basefont,bgsound,blockquote,body,br,button,caption,center,col,colgroup,dd,details,dir,div,dl,dt,embed,fieldset,figcaption,figure,footer,form,frame,frameset,h1,h2,h3,h4,h5,h6,head,header,hgroup,hr,html,iframe,img,input,keygen,li,link,listing,main,marquee,menu,meta,nav,noembed,noframes,noscript,object,ol,p,param,plaintext,pre,script,search,section,select,source,style,summary,table,tbody,td,template,textarea,tfoot,th,thead,title,tr,track,ul,wbr,xmp,", n.name)
    }
    if n.namespace == .MathMl { ret nm_in(",mi,mo,mn,ms,mtext,annotation-xml,", n.name) }
    if n.namespace == .Svg { ret nm_in(",foreignObject,desc,title,", n.name) }
    ret false
}

fn tb_scope_stop(p: *Ps, id: NodeId, kind: u8) -> bool {
    let n = &p.nodes[usize(id)]
    if kind == SC_SELECT { ret !(n.namespace == .Html && (str.eq(n.name, "optgroup") || str.eq(n.name, "option"))) }
    if kind == SC_TABLE { ret n.namespace == .Html && nm_in(",html,table,template,", n.name) }
    if n.namespace == .Html {
        if nm_in(",applet,caption,html,table,td,th,marquee,object,select,template,", n.name) { ret true }
        if kind == SC_LIST && (str.eq(n.name, "ol") || str.eq(n.name, "ul")) { ret true }
        if kind == SC_BUTTON && str.eq(n.name, "button") { ret true }
        ret false
    }
    if n.namespace == .MathMl { ret nm_in(",mi,mo,mn,ms,mtext,annotation-xml,", n.name) }
    ret nm_in(",foreignObject,desc,title,", n.name)
}

fn tb_in_scope(p: *Ps, name: str, kind: u8) -> bool {
    var i = p.nopen
    while i > 0usize {
        i -= 1usize
        let id = p.open[i]
        if pn_is(p, id, name) { ret true }
        if tb_scope_stop(p, id, kind) { ret false }
    }
    ret false
}

fn tb_in_scope_set(p: *Ps, set: str, kind: u8) -> bool {
    var i = p.nopen
    while i > 0usize {
        i -= 1usize
        let id = p.open[i]
        if pn_in(p, id, set) { ret true }
        if tb_scope_stop(p, id, kind) { ret false }
    }
    ret false
}

fn tb_in_scope_id(p: *Ps, wanted: NodeId, kind: u8) -> bool {
    var i = p.nopen
    while i > 0usize {
        i -= 1usize
        let id = p.open[i]
        if id == wanted { ret true }
        if tb_scope_stop(p, id, kind) { ret false }
    }
    ret false
}

// --- Foreign content helpers.

fn tb_adjusted(p: *Ps) -> NodeId {
    if p.fragment && p.nopen == 1usize { ret p.ctx }
    ret tb_cur(p)
}

fn tb_foreign_adjusted(p: *Ps) -> bool {
    let id = tb_adjusted(p)
    ret id != NONE && p.nodes[usize(id)].namespace != .Html
}

fn tb_mathml_text_ip(p: *Ps, id: NodeId) -> bool {
    let n = &p.nodes[usize(id)]
    ret n.namespace == .MathMl && nm_in(",mi,mo,mn,ms,mtext,", n.name)
}

fn tb_html_ip(p: *Ps, id: NodeId) -> bool {
    let n = &p.nodes[usize(id)]
    if n.namespace == .MathMl && str.eq(n.name, "annotation-xml") {
        let (enc, has) = attribute(n, "encoding")
        ret has && (ascii_eq_fold(enc, "text/html") || ascii_eq_fold(enc, "application/xhtml+xml"))
    }
    ret n.namespace == .Svg && nm_in(",foreignObject,desc,title,", n.name)
}

fn adj_lookup(table: str, name: str) -> (str, bool) {
    var i = 1usize
    while i < table.len {
        var j = i
        while j < table.len && table[j] != 44u8 { j += 1usize }
        var eq = i
        while eq < j && table[eq] != 61u8 { eq += 1usize }
        if eq - i == name.len && str.eq(table[i..eq], name) { ret (table[eq + 1usize..j], true) }
        i = j + 1usize
    }
    ret ("", false)
}

fn tb_svg_name(name: str) -> str {
    let (fixed, found) = adj_lookup(",altglyph=altGlyph,altglyphdef=altGlyphDef,altglyphitem=altGlyphItem,animatecolor=animateColor,animatemotion=animateMotion,animatetransform=animateTransform,clippath=clipPath,feblend=feBlend,fecolormatrix=feColorMatrix,fecomponenttransfer=feComponentTransfer,fecomposite=feComposite,feconvolvematrix=feConvolveMatrix,fediffuselighting=feDiffuseLighting,fedisplacementmap=feDisplacementMap,fedistantlight=feDistantLight,fedropshadow=feDropShadow,feflood=feFlood,fefunca=feFuncA,fefuncb=feFuncB,fefuncg=feFuncG,fefuncr=feFuncR,fegaussianblur=feGaussianBlur,feimage=feImage,femerge=feMerge,femergenode=feMergeNode,femorphology=feMorphology,feoffset=feOffset,fepointlight=fePointLight,fespecularlighting=feSpecularLighting,fespotlight=feSpotLight,fetile=feTile,feturbulence=feTurbulence,foreignobject=foreignObject,glyphref=glyphRef,lineargradient=linearGradient,radialgradient=radialGradient,textpath=textPath,", name)
    if found { ret fixed }
    ret name
}

fn tb_svg_attr(name: str) -> str {
    let (fixed, found) = adj_lookup(",attributename=attributeName,attributetype=attributeType,basefrequency=baseFrequency,baseprofile=baseProfile,calcmode=calcMode,clippathunits=clipPathUnits,diffuseconstant=diffuseConstant,edgemode=edgeMode,filterunits=filterUnits,glyphref=glyphRef,gradienttransform=gradientTransform,gradientunits=gradientUnits,kernelmatrix=kernelMatrix,kernelunitlength=kernelUnitLength,keypoints=keyPoints,keysplines=keySplines,keytimes=keyTimes,lengthadjust=lengthAdjust,limitingconeangle=limitingConeAngle,markerheight=markerHeight,markerunits=markerUnits,markerwidth=markerWidth,maskcontentunits=maskContentUnits,maskunits=maskUnits,numoctaves=numOctaves,pathlength=pathLength,patterncontentunits=patternContentUnits,patterntransform=patternTransform,patternunits=patternUnits,pointsatx=pointsAtX,pointsaty=pointsAtY,pointsatz=pointsAtZ,preservealpha=preserveAlpha,preserveaspectratio=preserveAspectRatio,primitiveunits=primitiveUnits,refx=refX,refy=refY,repeatcount=repeatCount,repeatdur=repeatDur,requiredextensions=requiredExtensions,requiredfeatures=requiredFeatures,specularconstant=specularConstant,specularexponent=specularExponent,spreadmethod=spreadMethod,startoffset=startOffset,stddeviation=stdDeviation,stitchtiles=stitchTiles,surfacescale=surfaceScale,systemlanguage=systemLanguage,tablevalues=tableValues,targetx=targetX,targety=targetY,textlength=textLength,viewbox=viewBox,viewtarget=viewTarget,xchannelselector=xChannelSelector,ychannelselector=yChannelSelector,zoomandpan=zoomAndPan,", name)
    if found { ret fixed }
    ret name
}

// Attributes with the foreign adjustments: SVG or MathML case fixes, and the
// xlink, xml and xmlns names split into a namespace and a local name.
fn tb_adjust_attrs(p: *Ps, attrs: []const Attribute, ns: Namespace) -> ([]const Attribute, err) {
    if attrs.len == 0usize { ret (attrs, ok) }
    let out = try mem.alloc[Attribute](p.a, attrs.len)
    var i = 0usize
    while i < attrs.len {
        var name = attrs[i].name
        var space: Namespace = .Html
        if ns == .Svg { name = tb_svg_attr(name) }
        if ns == .MathMl && str.eq(name, "definitionurl") { name = "definitionURL" }
        if nm_in(",xlink:actuate,xlink:arcrole,xlink:href,xlink:role,xlink:show,xlink:title,xlink:type,", name) {
            space = .Xlink
            name = name[6usize..]
        } else {
            if nm_in(",xml:lang,xml:space,", name) {
                space = .Xml
                name = name[4usize..]
            } else {
                if str.eq(name, "xmlns") {
                    space = .Xmlns
                } else {
                    if str.eq(name, "xmlns:xlink") {
                        space = .Xmlns
                        name = name[6usize..]
                    }
                }
            }
        }
        out[i] = Attribute { namespace: space, name: name, value: attrs[i].value }
        i += 1usize
    }
    ret (out, ok)
}

// --- Insertion.

fn tb_place(p: *Ps, override: NodeId) -> Place {
    var anchor = override
    if anchor == NONE { anchor = tb_cur(p) }
    if p.foster && anchor != NONE && pn_in(p, anchor, ",table,tbody,tfoot,thead,tr,") {
        var last_template = NONE
        var last_table = NONE
        var template_at = 0usize
        var table_at = 0usize
        var i = p.nopen
        while i > 0usize {
            i -= 1usize
            let id = p.open[i]
            if last_template == NONE && pn_is(p, id, "template") {
                last_template = id
                template_at = i
            }
            if last_table == NONE && pn_is(p, id, "table") {
                last_table = id
                table_at = i
            }
        }
        if last_template != NONE && (last_table == NONE || template_at > table_at) { ret Place { parent: last_template, before: NONE } }
        if last_table == NONE { ret Place { parent: p.open[0usize], before: NONE } }
        let table_parent = p.nodes[usize(last_table)].parent
        if table_parent != NONE { ret Place { parent: table_parent, before: last_table } }
        ret Place { parent: p.open[table_at - 1usize], before: NONE }
    }
    ret Place { parent: anchor, before: NONE }
}

fn tb_insert_node(p: *Ps, id: NodeId) {
    let place = tb_place(p, NONE)
    pn_insert(p, place.parent, id, place.before)
}

fn tb_insert_chars(p: *Ps, data: str) -> err {
    let place = tb_place(p, NONE)
    if place.parent == 0u32 { ret ok }
    ret pn_text(p, place.parent, place.before, data)
}

// A comment at the current place, or under `parent` when it is not NONE.
fn tb_insert_comment(p: *Ps, data: str, parent: NodeId) -> err {
    if !p.options.preserve_comments { ret ok }
    let id = try pn_new(p, .Comment, .Html, "", data)
    if parent != NONE {
        pn_insert(p, parent, id, NONE)
        ret ok
    }
    tb_insert_node(p, id)
    ret ok
}

// Inserts the element for a start tag and makes it the current node.
fn tb_insert_element(p: *Ps, ns: Namespace, name: str, attrs: []const Attribute) -> (NodeId, err) {
    let id = try pn_element(p, ns, name, attrs)
    tb_insert_node(p, id)
    try tb_push(p, id)
    ret (id, ok)
}

fn tb_insert_html(p: *Ps, tk: *Tok) -> (NodeId, err) {
    let (id, e) = tb_insert_element(p, .Html, tk.name, tk.attrs)
    ret (id, e)
}

// An element with no attributes, as the spec "insert an HTML element for a token whose name is ...".
fn tb_insert_named(p: *Ps, name: str) -> (NodeId, err) {
    let (id, e) = tb_insert_element(p, .Html, name, no_attrs())
    ret (id, e)
}

fn tb_clone(p: *Ps, id: NodeId) -> (NodeId, err) {
    let (copy, e) = pn_element(p, p.nodes[usize(id)].namespace, p.nodes[usize(id)].name, p.nodes[usize(id)].attributes)
    ret (copy, e)
}

// --- The list of active formatting elements; NONE entries are markers.

fn tb_fmt_index(p: *Ps, id: NodeId) -> (usize, bool) {
    var i = p.nfmt
    while i > 0usize {
        i -= 1usize
        if p.fmt[i] == id { ret (i, true) }
    }
    ret (0usize, false)
}

fn tb_fmt_remove_at(p: *Ps, at: usize) {
    var i = at
    while i + 1usize < p.nfmt {
        p.fmt[i] = p.fmt[i + 1usize]
        i += 1usize
    }
    p.nfmt -= 1usize
}

fn tb_fmt_insert_at(p: *Ps, at: usize, id: NodeId) -> err {
    if p.nfmt >= p.fmt.len { ret TooDeep }
    var i = p.nfmt
    while i > at {
        p.fmt[i] = p.fmt[i - 1usize]
        i -= 1usize
    }
    p.fmt[at] = id
    p.nfmt += 1usize
    ret ok
}

fn tb_fmt_marker(p: *Ps) -> err {
    ret tb_fmt_insert_at(p, p.nfmt, NONE)
}

fn tb_fmt_clear_to_marker(p: *Ps) {
    while p.nfmt > 0usize {
        p.nfmt -= 1usize
        if p.fmt[p.nfmt] == NONE { break }
    }
}

fn tb_same_element(p: *Ps, x: NodeId, y: NodeId) -> bool {
    let nx = &p.nodes[usize(x)]
    let ny = &p.nodes[usize(y)]
    if nx.namespace != ny.namespace || !str.eq(nx.name, ny.name) || nx.attributes.len != ny.attributes.len { ret false }
    var i = 0usize
    while i < nx.attributes.len {
        let (other, has) = attribute(ny, nx.attributes[i].name)
        if !has || !str.eq(other, nx.attributes[i].value) { ret false }
        i += 1usize
    }
    ret true
}

fn tb_fmt_push(p: *Ps, id: NodeId) -> err {
    var count = 0usize
    var earliest = 0usize
    var i = p.nfmt
    while i > 0usize {
        i -= 1usize
        let entry = p.fmt[i]
        if entry == NONE { break }
        if tb_same_element(p, entry, id) {
            count += 1usize
            earliest = i
        }
    }
    if count >= 3usize { tb_fmt_remove_at(p, earliest) }
    ret tb_fmt_insert_at(p, p.nfmt, id)
}

fn tb_reconstruct(p: *Ps) -> err {
    if p.nfmt == 0usize { ret ok }
    let last = p.fmt[p.nfmt - 1usize]
    if last == NONE { ret ok }
    let (_, open_already) = tb_open_index(p, last)
    if open_already { ret ok }
    var i = p.nfmt - 1usize
    while i > 0usize {
        let before = p.fmt[i - 1usize]
        if before == NONE { break }
        let (_, in_stack) = tb_open_index(p, before)
        if in_stack { break }
        i -= 1usize
    }
    while i < p.nfmt {
        let entry = p.fmt[i]
        let clone = try tb_clone(p, entry)
        tb_insert_node(p, clone)
        try tb_push(p, clone)
        p.fmt[i] = clone
        i += 1usize
    }
    ret ok
}

// --- End tags that close things.

// Pops while the current node is an implied-end-tag element other than `except`.
fn tb_implied(p: *Ps, except: str) {
    while p.nopen > 0usize {
        let id = tb_cur(p)
        if !pn_in(p, id, ",dd,dt,li,optgroup,option,p,rb,rp,rt,rtc,") || pn_is(p, id, except) { break }
        tb_pop(p)
    }
}

fn tb_implied_all(p: *Ps) {
    while p.nopen > 0usize {
        let id = tb_cur(p)
        if !pn_in(p, id, ",caption,colgroup,dd,dt,li,optgroup,option,p,rb,rp,rt,rtc,tbody,td,tfoot,th,thead,tr,") { break }
        tb_pop(p)
    }
}

fn tb_close_p(p: *Ps) {
    tb_implied(p, "p")
    tb_pop_until(p, "p")
}

fn tb_any_other_end(p: *Ps, name: str) {
    var i = p.nopen
    while i > 0usize {
        i -= 1usize
        let id = p.open[i]
        if pn_is(p, id, name) {
            tb_implied(p, name)
            p.nopen = i
            ret
        }
        if tb_special(p, id) { ret }
    }
}

// The adoption agency algorithm. True: the caller runs "any other end tag".
fn tb_adoption(p: *Ps, subject: str) -> (bool, err) {
    let top = tb_cur(p)
    if top != NONE && pn_is(p, top, subject) {
        let (_, listed) = tb_fmt_index(p, top)
        if !listed {
            tb_pop(p)
            ret (false, ok)
        }
    }
    var outer = 0usize
    while outer < 8usize {
        outer += 1usize
        var idx = p.nfmt
        var found = false
        while idx > 0usize {
            idx -= 1usize
            let entry = p.fmt[idx]
            if entry == NONE { break }
            if pn_is(p, entry, subject) {
                found = true
                break
            }
        }
        if !found { ret (true, ok) }
        let fe = p.fmt[idx]
        let (stack_at, in_stack) = tb_open_index(p, fe)
        if !in_stack {
            tb_fmt_remove_at(p, idx)
            ret (false, ok)
        }
        if !tb_in_scope_id(p, fe, SC_DEFAULT) { ret (false, ok) }
        var fb = NONE
        var fb_at = 0usize
        var k = stack_at + 1usize
        while k < p.nopen {
            if tb_special(p, p.open[k]) {
                fb = p.open[k]
                fb_at = k
                break
            }
            k += 1usize
        }
        if fb == NONE {
            p.nopen = stack_at
            tb_fmt_remove_at(p, idx)
            ret (false, ok)
        }
        let common = p.open[stack_at - 1usize]
        var bookmark = idx
        var last = fb
        var node_at = fb_at
        var inner = 0usize
        while true {
            inner += 1usize
            node_at -= 1usize
            var cur_node = p.open[node_at]
            if cur_node == fe { break }
            let (list_at, listed_now) = tb_fmt_index(p, cur_node)
            var listed = listed_now
            if inner > 3usize && listed {
                tb_fmt_remove_at(p, list_at)
                if list_at < bookmark { bookmark -= 1usize }
                listed = false
            }
            if !listed {
                tb_open_remove_at(p, node_at)
                continue
            }
            let clone = try tb_clone(p, cur_node)
            p.fmt[list_at] = clone
            p.open[node_at] = clone
            cur_node = clone
            if last == fb { bookmark = list_at + 1usize }
            pn_detach(p, last)
            pn_insert(p, cur_node, last, NONE)
            last = cur_node
        }
        pn_detach(p, last)
        let place = tb_place(p, common)
        pn_insert(p, place.parent, last, place.before)
        let fresh = try tb_clone(p, fe)
        while p.nodes[usize(fb)].first_child != NONE {
            let child = p.nodes[usize(fb)].first_child
            pn_detach(p, child)
            pn_insert(p, fresh, child, NONE)
        }
        pn_insert(p, fb, fresh, NONE)
        let (old_at, _) = tb_fmt_index(p, fe)
        tb_fmt_remove_at(p, old_at)
        if old_at < bookmark { bookmark -= 1usize }
        try tb_fmt_insert_at(p, bookmark, fresh)
        let (fe_at, _) = tb_open_index(p, fe)
        tb_open_remove_at(p, fe_at)
        let (fb_now, _) = tb_open_index(p, fb)
        if p.nopen >= p.open.len { ret (false, TooDeep) }
        var m = p.nopen
        while m > fb_now + 1usize {
            p.open[m] = p.open[m - 1usize]
            m -= 1usize
        }
        p.open[fb_now + 1usize] = fresh
        p.nopen += 1usize
    }
    ret (false, ok)
}

// --- Insertion mode bookkeeping.

fn tb_reset_mode(p: *Ps) {
    var i = p.nopen
    while i > 0usize {
        i -= 1usize
        var id = p.open[i]
        let last = i == 0usize
        if last && p.fragment { id = p.ctx }
        if pn_is(p, id, "select") {
            if !last {
                var j = i
                while j > 0usize {
                    j -= 1usize
                    let anc = p.open[j]
                    if pn_is(p, anc, "template") { break }
                    if pn_is(p, anc, "table") {
                        p.mode = M_IN_SELECT_TABLE
                        ret
                    }
                }
            }
            p.mode = M_IN_SELECT
            ret
        }
        if !last && (pn_is(p, id, "td") || pn_is(p, id, "th")) {
            p.mode = M_IN_CELL
            ret
        }
        if pn_is(p, id, "tr") {
            p.mode = M_IN_ROW
            ret
        }
        if pn_in(p, id, ",tbody,thead,tfoot,") {
            p.mode = M_IN_TBODY
            ret
        }
        if pn_is(p, id, "caption") {
            p.mode = M_IN_CAPTION
            ret
        }
        if pn_is(p, id, "colgroup") {
            p.mode = M_IN_COLGROUP
            ret
        }
        if pn_is(p, id, "table") {
            p.mode = M_IN_TABLE
            ret
        }
        if pn_is(p, id, "template") {
            if p.ntmodes > 0usize { p.mode = p.tmodes[p.ntmodes - 1usize] } else { p.mode = M_IN_BODY }
            ret
        }
        if !last && pn_is(p, id, "head") {
            p.mode = M_IN_HEAD
            ret
        }
        if pn_is(p, id, "body") {
            p.mode = M_IN_BODY
            ret
        }
        if pn_is(p, id, "frameset") {
            p.mode = M_IN_FRAMESET
            ret
        }
        if pn_is(p, id, "html") {
            if p.head == NONE { p.mode = M_BEFORE_HEAD } else { p.mode = M_AFTER_HEAD }
            ret
        }
        if last {
            p.mode = M_IN_BODY
            ret
        }
    }
    p.mode = M_IN_BODY
}

fn tb_clear_to(p: *Ps, set: str) {
    while p.nopen > 0usize && !pn_in(p, tb_cur(p), set) { tb_pop(p) }
}

// --- Quirks mode from a DOCTYPE token.

fn starts_any(subject: str, list: str) -> bool {
    var i = 1usize
    while i < list.len {
        var j = i
        while j < list.len && list[j] != 124u8 { j += 1usize }
        if str.starts_with(subject, list[i..j]) { ret true }
        i = j + 1usize
    }
    ret false
}

fn tb_quirks_of(p: *Ps, tk: *Tok) -> (u8, err) {
    if tk.force_quirks || !str.eq(tk.name, "html") { ret (Q_QUIRKS, ok) }
    let pub_id = try tk_clean(p, tk.public_id, true)
    let sys_id = try tk_clean(p, tk.system_id, true)
    if str.eq(pub_id, "-//w3o//dtd w3 html strict 3.0//en//") || str.eq(pub_id, "-/w3c/dtd html 4.0 transitional/en") || str.eq(pub_id, "html") { ret (Q_QUIRKS, ok) }
    if str.eq(sys_id, "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd") { ret (Q_QUIRKS, ok) }
    if starts_any(pub_id, "|+//silmaril//dtd html pro v0r11 19970101//|-//as//dtd html 3.0 aswedit + extensions//|-//advasoft ltd//dtd html 3.0 aswedit + extensions//|-//ietf//dtd html 2.0 level 1//|-//ietf//dtd html 2.0 level 2//|-//ietf//dtd html 2.0 strict level 1//|-//ietf//dtd html 2.0 strict level 2//|-//ietf//dtd html 2.0 strict//|-//ietf//dtd html 2.0//|-//ietf//dtd html 2.1e//|-//ietf//dtd html 3.0//|-//ietf//dtd html 3.2 final//|-//ietf//dtd html 3.2//|-//ietf//dtd html 3//|-//ietf//dtd html level 0//|-//ietf//dtd html level 1//|-//ietf//dtd html level 2//|-//ietf//dtd html level 3//|-//ietf//dtd html strict level 0//|-//ietf//dtd html strict level 1//|-//ietf//dtd html strict level 2//|-//ietf//dtd html strict level 3//|-//ietf//dtd html strict//|-//ietf//dtd html//|-//metrius//dtd metrius presentational//|-//microsoft//dtd internet explorer 2.0 html strict//|-//microsoft//dtd internet explorer 2.0 html//|-//microsoft//dtd internet explorer 2.0 tables//|-//microsoft//dtd internet explorer 3.0 html strict//|-//microsoft//dtd internet explorer 3.0 html//|-//microsoft//dtd internet explorer 3.0 tables//|-//netscape comm. corp.//dtd html//|-//netscape comm. corp.//dtd strict html//|-//o'reilly and associates//dtd html 2.0//|-//o'reilly and associates//dtd html extended 1.0//|-//o'reilly and associates//dtd html extended relaxed 1.0//|-//softquad software//dtd hotmetal pro 6.0::19990601::extensions to html 4.0//|-//softquad//dtd hotmetal pro 4.0::19971010::extensions to html 4.0//|-//spyglass//dtd html 2.0 extended//|-//sq//dtd html 2.0 hotmetal + extensions//|-//sun microsystems corp.//dtd hotjava html//|-//sun microsystems corp.//dtd hotjava strict html//|-//w3c//dtd html 3 1995-03-24//|-//w3c//dtd html 3.2 draft//|-//w3c//dtd html 3.2 final//|-//w3c//dtd html 3.2//|-//w3c//dtd html 3.2s draft//|-//w3c//dtd html 4.0 frameset//|-//w3c//dtd html 4.0 transitional//|-//w3c//dtd html experimental 19960712//|-//w3c//dtd html experimental 970421//|-//w3c//dtd w3 html//|-//w3o//dtd w3 html 3.0//|-//webtechs//dtd mozilla html 2.0//|-//webtechs//dtd mozilla html//|") { ret (Q_QUIRKS, ok) }
    if sys_id.len == 0usize && starts_any(pub_id, "|-//w3c//dtd html 4.01 frameset//|-//w3c//dtd html 4.01 transitional//|") { ret (Q_QUIRKS, ok) }
    if starts_any(pub_id, "|-//w3c//dtd xhtml 1.0 frameset//|-//w3c//dtd xhtml 1.0 transitional//|") { ret (Q_LIMITED, ok) }
    if sys_id.len != 0usize && starts_any(pub_id, "|-//w3c//dtd html 4.01 frameset//|-//w3c//dtd html 4.01 transitional//|") { ret (Q_LIMITED, ok) }
    ret (Q_NO, ok)
}

fn no_attrs() -> []const Attribute {
    var none: []const Attribute = zero
    ret none
}

// --- Insertion modes. Each returns (reprocess, err): true runs the same token again
// in the (possibly changed) current mode.

fn ws_prefix(s: str) -> usize {
    var i = 0usize
    while i < s.len && ws_byte(s[i]) { i += 1usize }
    ret i
}

fn tk_attr(tk: *Tok, name: str) -> (str, bool) {
    var i = 0usize
    while i < tk.attrs.len {
        if str.eq(tk.attrs[i].name, name) { ret (tk.attrs[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

// `attrs` not already on element `id`, appended to it.
fn tb_merge_attrs(p: *Ps, id: NodeId, attrs: []const Attribute) -> err {
    var missing = 0usize
    var i = 0usize
    while i < attrs.len {
        let (_, has) = attribute(&p.nodes[usize(id)], attrs[i].name)
        if !has { missing += 1usize }
        i += 1usize
    }
    if missing == 0usize { ret ok }
    let old = p.nodes[usize(id)].attributes
    let merged = try mem.alloc[Attribute](p.a, old.len + missing)
    mem.copy[Attribute](merged[..old.len], old)
    var at = old.len
    i = 0usize
    while i < attrs.len {
        let (_, has) = attribute(&p.nodes[usize(id)], attrs[i].name)
        if !has {
            merged[at] = attrs[i]
            at += 1usize
        }
        i += 1usize
    }
    p.nodes[usize(id)].attributes = merged
    ret ok
}

fn tb_strip_nul(p: *Ps, s: str) -> (str, err) {
    var nuls = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] == 0u8 { nuls += 1usize }
        i += 1usize
    }
    if nuls == 0usize { ret (s, ok) }
    let out = try mem.alloc[u8](p.a, s.len - nuls)
    var at = 0usize
    i = 0usize
    while i < s.len {
        if s[i] != 0u8 {
            out[at] = s[i]
            at += 1usize
        }
        i += 1usize
    }
    ret (out[..at], ok)
}

fn tb_comment_doc(p: *Ps, tk: *Tok) -> err {
    ret tb_insert_comment(p, tk.data, 0u32)
}

// Raw text / RCDATA element: insert it, switch the tokenizer and the mode.
fn tb_text_element(p: *Ps, tk: *Tok, state: u8) -> err {
    let id = try tb_insert_html(p, tk)
    p.ts = state
    p.orig_mode = p.mode
    p.mode = M_TEXT
    ret ok
}

fn tm_initial(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let w = ws_prefix(tk.data)
        if w == tk.data.len { ret (false, ok) }
        tk.data = tk.data[w..]
    }
    if tk.kind == .Comment {
        try tb_comment_doc(p, tk)
        ret (false, ok)
    }
    if tk.kind == .Doctype {
        var value: str = ""
        if tk.public_id.len > 0usize || tk.system_id.len > 0usize {
            let joined = try str.concat(p.a, tk.public_id, "\x00")
            value = try str.concat(p.a, joined, tk.system_id)
        }
        let id = try pn_new(p, .Doctype, .Html, tk.name, value)
        pn_insert(p, 0u32, id, NONE)
        p.quirks = try tb_quirks_of(p, tk)
        p.mode = M_BEFORE_HTML
        ret (false, ok)
    }
    p.quirks = Q_QUIRKS
    p.mode = M_BEFORE_HTML
    ret (true, ok)
}

fn tm_before_html(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Doctype { ret (false, ok) }
    if tk.kind == .Comment {
        try tb_comment_doc(p, tk)
        ret (false, ok)
    }
    if tk.kind == .Chars {
        let w = ws_prefix(tk.data)
        if w == tk.data.len { ret (false, ok) }
        tk.data = tk.data[w..]
    }
    if tk.kind == .Start && str.eq(tk.name, "html") {
        let id = try pn_element(p, .Html, "html", tk.attrs)
        pn_insert(p, 0u32, id, NONE)
        try tb_push(p, id)
        p.mode = M_BEFORE_HEAD
        ret (false, ok)
    }
    if tk.kind == .End && !nm_in(",head,body,html,br,", tk.name) { ret (false, ok) }
    let id = try pn_element(p, .Html, "html", no_attrs())
    pn_insert(p, 0u32, id, NONE)
    try tb_push(p, id)
    p.mode = M_BEFORE_HEAD
    ret (true, ok)
}

fn tm_before_head(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let w = ws_prefix(tk.data)
        if w == tk.data.len { ret (false, ok) }
        tk.data = tk.data[w..]
    }
    if tk.kind == .Comment {
        try tb_insert_comment(p, tk.data, NONE)
        ret (false, ok)
    }
    if tk.kind == .Doctype { ret (false, ok) }
    if tk.kind == .Start && str.eq(tk.name, "html") {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    if tk.kind == .Start && str.eq(tk.name, "head") {
        let id = try tb_insert_html(p, tk)
        p.head = id
        p.mode = M_IN_HEAD
        ret (false, ok)
    }
    if tk.kind == .End && !nm_in(",head,body,html,br,", tk.name) { ret (false, ok) }
    let id = try tb_insert_named(p, "head")
    p.head = id
    p.mode = M_IN_HEAD
    ret (true, ok)
}

fn tm_in_head(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let w = ws_prefix(tk.data)
        if w > 0usize { try tb_insert_chars(p, tk.data[..w]) }
        if w == tk.data.len { ret (false, ok) }
        tk.data = tk.data[w..]
    }
    if tk.kind == .Comment {
        try tb_insert_comment(p, tk.data, NONE)
        ret (false, ok)
    }
    if tk.kind == .Doctype { ret (false, ok) }
    if tk.kind == .Start {
        let name = tk.name
        if str.eq(name, "html") {
            let again = try tm_in_body(p, tk)
            ret (again, ok)
        }
        if nm_in(",base,basefont,bgsound,link,meta,", name) {
            let id = try tb_insert_html(p, tk)
            tb_pop(p)
            ret (false, ok)
        }
        if str.eq(name, "title") {
            try tb_text_element(p, tk, TS_RCDATA)
            ret (false, ok)
        }
        if nm_in(",noframes,style,", name) {
            try tb_text_element(p, tk, TS_RAWTEXT)
            ret (false, ok)
        }
        if str.eq(name, "noscript") {
            if p.scripting {
                try tb_text_element(p, tk, TS_RAWTEXT)
                ret (false, ok)
            }
            let id = try tb_insert_html(p, tk)
            p.mode = M_IN_HEAD_NOSCRIPT
            ret (false, ok)
        }
        if str.eq(name, "script") {
            try tb_text_element(p, tk, TS_SCRIPT)
            ret (false, ok)
        }
        if str.eq(name, "template") {
            let id = try tb_insert_html(p, tk)
            try tb_fmt_marker(p)
            p.frameset_ok = false
            p.mode = M_IN_TEMPLATE
            if p.ntmodes < 64usize {
                p.tmodes[p.ntmodes] = M_IN_TEMPLATE
                p.ntmodes += 1usize
            }
            ret (false, ok)
        }
        if str.eq(name, "head") { ret (false, ok) }
    }
    if tk.kind == .End {
        let name = tk.name
        if str.eq(name, "head") {
            tb_pop(p)
            p.mode = M_AFTER_HEAD
            ret (false, ok)
        }
        if str.eq(name, "template") {
            if !tb_open_has(p, "template") { ret (false, ok) }
            tb_implied_all(p)
            tb_pop_until(p, "template")
            tb_fmt_clear_to_marker(p)
            if p.ntmodes > 0usize { p.ntmodes -= 1usize }
            tb_reset_mode(p)
            ret (false, ok)
        }
        if !nm_in(",body,html,br,", name) { ret (false, ok) }
    }
    tb_pop(p)
    p.mode = M_AFTER_HEAD
    ret (true, ok)
}

fn tm_in_head_noscript(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Doctype { ret (false, ok) }
    if tk.kind == .Comment {
        let again = try tm_in_head(p, tk)
        ret (again, ok)
    }
    if tk.kind == .Chars {
        let w = ws_prefix(tk.data)
        if w > 0usize { try tb_insert_chars(p, tk.data[..w]) }
        if w == tk.data.len { ret (false, ok) }
        tk.data = tk.data[w..]
    }
    if tk.kind == .Start {
        if str.eq(tk.name, "html") {
            let again = try tm_in_body(p, tk)
            ret (again, ok)
        }
        if nm_in(",basefont,bgsound,link,meta,noframes,style,", tk.name) {
            let again = try tm_in_head(p, tk)
            ret (again, ok)
        }
        if nm_in(",head,noscript,", tk.name) { ret (false, ok) }
    }
    if tk.kind == .End {
        if str.eq(tk.name, "noscript") {
            tb_pop(p)
            p.mode = M_IN_HEAD
            ret (false, ok)
        }
        if !str.eq(tk.name, "br") { ret (false, ok) }
    }
    tb_pop(p)
    p.mode = M_IN_HEAD
    ret (true, ok)
}

fn tm_after_head(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let w = ws_prefix(tk.data)
        if w > 0usize { try tb_insert_chars(p, tk.data[..w]) }
        if w == tk.data.len { ret (false, ok) }
        tk.data = tk.data[w..]
    }
    if tk.kind == .Comment {
        try tb_insert_comment(p, tk.data, NONE)
        ret (false, ok)
    }
    if tk.kind == .Doctype { ret (false, ok) }
    if tk.kind == .Start {
        let name = tk.name
        if str.eq(name, "html") {
            let again = try tm_in_body(p, tk)
            ret (again, ok)
        }
        if str.eq(name, "body") {
            let id = try tb_insert_html(p, tk)
            p.frameset_ok = false
            p.mode = M_IN_BODY
            ret (false, ok)
        }
        if str.eq(name, "frameset") {
            let id = try tb_insert_html(p, tk)
            p.mode = M_IN_FRAMESET
            ret (false, ok)
        }
        if nm_in(",base,basefont,bgsound,link,meta,noframes,script,style,template,title,", name) {
            try tb_push(p, p.head)
            let again = try tm_in_head(p, tk)
            let (head_at, head_open) = tb_open_index(p, p.head)
            if head_open { tb_open_remove_at(p, head_at) }
            ret (again, ok)
        }
        if str.eq(name, "head") { ret (false, ok) }
    }
    if tk.kind == .End {
        if str.eq(tk.name, "template") {
            let again = try tm_in_head(p, tk)
            ret (again, ok)
        }
        if !nm_in(",body,html,br,", tk.name) { ret (false, ok) }
    }
    let id = try tb_insert_named(p, "body")
    p.mode = M_IN_BODY
    ret (true, ok)
}

// --- In body.

fn tm_in_body(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let data = try tb_strip_nul(p, tk.data)
        if data.len == 0usize { ret (false, ok) }
        try tb_reconstruct(p)
        try tb_insert_chars(p, data)
        if ws_prefix(data) != data.len { p.frameset_ok = false }
        ret (false, ok)
    }
    if tk.kind == .Comment {
        try tb_insert_comment(p, tk.data, NONE)
        ret (false, ok)
    }
    if tk.kind == .Doctype { ret (false, ok) }
    if tk.kind == .Eof {
        if p.ntmodes > 0usize {
            let again = try tm_in_template(p, tk)
            ret (again, ok)
        }
        p.stopped = true
        ret (false, ok)
    }
    if tk.kind == .Start {
        let again = try tm_body_start(p, tk)
        ret (again, ok)
    }
    let again = try tm_body_end(p, tk)
    ret (again, ok)
}

fn tm_body_start(p: *Ps, tk: *Tok) -> (bool, err) {
    let name = tk.name
    if str.eq(name, "html") {
        if tb_open_has(p, "template") { ret (false, ok) }
        try tb_merge_attrs(p, p.open[0usize], tk.attrs)
        ret (false, ok)
    }
    if nm_in(",base,basefont,bgsound,link,meta,noframes,script,style,template,title,", name) {
        let again = try tm_in_head(p, tk)
        ret (again, ok)
    }
    if str.eq(name, "body") {
        if p.nopen < 2usize || !pn_is(p, p.open[1usize], "body") || tb_open_has(p, "template") { ret (false, ok) }
        p.frameset_ok = false
        try tb_merge_attrs(p, p.open[1usize], tk.attrs)
        ret (false, ok)
    }
    if str.eq(name, "frameset") {
        if p.nopen < 2usize || !pn_is(p, p.open[1usize], "body") || !p.frameset_ok { ret (false, ok) }
        pn_detach(p, p.open[1usize])
        p.nopen = 1usize
        let id = try tb_insert_html(p, tk)
        p.mode = M_IN_FRAMESET
        ret (false, ok)
    }
    if nm_in(",address,article,aside,blockquote,center,details,dialog,dir,div,dl,fieldset,figcaption,figure,footer,header,hgroup,main,menu,nav,ol,p,search,section,summary,ul,", name) {
        if tb_in_scope(p, "p", SC_BUTTON) { tb_close_p(p) }
        let id = try tb_insert_html(p, tk)
        ret (false, ok)
    }
    if nm_in(",h1,h2,h3,h4,h5,h6,", name) {
        if tb_in_scope(p, "p", SC_BUTTON) { tb_close_p(p) }
        if pn_in(p, tb_cur(p), ",h1,h2,h3,h4,h5,h6,") { tb_pop(p) }
        let id = try tb_insert_html(p, tk)
        ret (false, ok)
    }
    if nm_in(",pre,listing,", name) {
        if tb_in_scope(p, "p", SC_BUTTON) { tb_close_p(p) }
        let id = try tb_insert_html(p, tk)
        p.ignore_lf = true
        p.frameset_ok = false
        ret (false, ok)
    }
    if str.eq(name, "form") {
        let templated = tb_open_has(p, "template")
        if p.form != NONE && !templated { ret (false, ok) }
        if tb_in_scope(p, "p", SC_BUTTON) { tb_close_p(p) }
        let id = try tb_insert_html(p, tk)
        if !templated { p.form = id }
        ret (false, ok)
    }
    if str.eq(name, "li") || nm_in(",dd,dt,", name) {
        p.frameset_ok = false
        var i = p.nopen
        while i > 0usize {
            i -= 1usize
            let nd = p.open[i]
            if str.eq(name, "li") && pn_is(p, nd, "li") {
                tb_implied(p, "li")
                tb_pop_until(p, "li")
                break
            }
            if !str.eq(name, "li") && (pn_is(p, nd, "dd") || pn_is(p, nd, "dt")) {
                let which = p.nodes[usize(nd)].name
                tb_implied(p, which)
                tb_pop_until(p, which)
                break
            }
            if tb_special(p, nd) && !pn_in(p, nd, ",address,div,p,") { break }
        }
        if tb_in_scope(p, "p", SC_BUTTON) { tb_close_p(p) }
        let id = try tb_insert_html(p, tk)
        ret (false, ok)
    }
    if str.eq(name, "plaintext") {
        if tb_in_scope(p, "p", SC_BUTTON) { tb_close_p(p) }
        let id = try tb_insert_html(p, tk)
        p.ts = TS_PLAINTEXT
        ret (false, ok)
    }
    if str.eq(name, "button") {
        if tb_in_scope(p, "button", SC_DEFAULT) {
            tb_implied(p, "")
            tb_pop_until(p, "button")
        }
        try tb_reconstruct(p)
        let id = try tb_insert_html(p, tk)
        p.frameset_ok = false
        ret (false, ok)
    }
    if str.eq(name, "a") {
        var i = p.nfmt
        while i > 0usize {
            i -= 1usize
            let entry = p.fmt[i]
            if entry == NONE { break }
            if pn_is(p, entry, "a") {
                let other = try tb_adoption(p, "a")
                if other { tb_any_other_end(p, "a") }
                let (at, still) = tb_fmt_index(p, entry)
                if still { tb_fmt_remove_at(p, at) }
                let (open_at, open_still) = tb_open_index(p, entry)
                if open_still { tb_open_remove_at(p, open_at) }
                break
            }
        }
        try tb_reconstruct(p)
        let id = try tb_insert_html(p, tk)
        try tb_fmt_push(p, id)
        ret (false, ok)
    }
    if nm_in(",b,big,code,em,font,i,s,small,strike,strong,tt,u,", name) {
        try tb_reconstruct(p)
        let id = try tb_insert_html(p, tk)
        try tb_fmt_push(p, id)
        ret (false, ok)
    }
    if str.eq(name, "nobr") {
        try tb_reconstruct(p)
        if tb_in_scope(p, "nobr", SC_DEFAULT) {
            let other = try tb_adoption(p, "nobr")
            if other { tb_any_other_end(p, "nobr") }
            try tb_reconstruct(p)
        }
        let id = try tb_insert_html(p, tk)
        try tb_fmt_push(p, id)
        ret (false, ok)
    }
    if nm_in(",applet,marquee,object,", name) {
        try tb_reconstruct(p)
        let id = try tb_insert_html(p, tk)
        try tb_fmt_marker(p)
        p.frameset_ok = false
        ret (false, ok)
    }
    if str.eq(name, "table") {
        if p.quirks != Q_QUIRKS && tb_in_scope(p, "p", SC_BUTTON) { tb_close_p(p) }
        let id = try tb_insert_html(p, tk)
        p.frameset_ok = false
        p.mode = M_IN_TABLE
        ret (false, ok)
    }
    if nm_in(",area,br,embed,img,keygen,wbr,", name) {
        try tb_reconstruct(p)
        let id = try tb_insert_html(p, tk)
        tb_pop(p)
        p.frameset_ok = false
        ret (false, ok)
    }
    if str.eq(name, "input") {
        try tb_reconstruct(p)
        let id = try tb_insert_html(p, tk)
        tb_pop(p)
        let (kind, has) = tk_attr(tk, "type")
        if !has || !ascii_eq_fold(kind, "hidden") { p.frameset_ok = false }
        ret (false, ok)
    }
    if nm_in(",param,source,track,", name) {
        let id = try tb_insert_html(p, tk)
        tb_pop(p)
        ret (false, ok)
    }
    if str.eq(name, "hr") {
        if tb_in_scope(p, "p", SC_BUTTON) { tb_close_p(p) }
        let id = try tb_insert_html(p, tk)
        tb_pop(p)
        p.frameset_ok = false
        ret (false, ok)
    }
    if str.eq(name, "image") {
        tk.name = "img"
        let again = try tm_body_start(p, tk)
        ret (again, ok)
    }
    if str.eq(name, "textarea") {
        let id = try tb_insert_html(p, tk)
        p.ignore_lf = true
        p.ts = TS_RCDATA
        p.orig_mode = p.mode
        p.frameset_ok = false
        p.mode = M_TEXT
        ret (false, ok)
    }
    if str.eq(name, "xmp") {
        if tb_in_scope(p, "p", SC_BUTTON) { tb_close_p(p) }
        try tb_reconstruct(p)
        p.frameset_ok = false
        try tb_text_element(p, tk, TS_RAWTEXT)
        ret (false, ok)
    }
    if str.eq(name, "iframe") {
        p.frameset_ok = false
        try tb_text_element(p, tk, TS_RAWTEXT)
        ret (false, ok)
    }
    if str.eq(name, "noembed") || (p.scripting && str.eq(name, "noscript")) {
        try tb_text_element(p, tk, TS_RAWTEXT)
        ret (false, ok)
    }
    if str.eq(name, "select") {
        try tb_reconstruct(p)
        let id = try tb_insert_html(p, tk)
        p.frameset_ok = false
        if p.mode == M_IN_TABLE || p.mode == M_IN_CAPTION || p.mode == M_IN_TBODY || p.mode == M_IN_ROW || p.mode == M_IN_CELL {
            p.mode = M_IN_SELECT_TABLE
        } else {
            p.mode = M_IN_SELECT
        }
        ret (false, ok)
    }
    if nm_in(",optgroup,option,", name) {
        if pn_is(p, tb_cur(p), "option") { tb_pop(p) }
        try tb_reconstruct(p)
        let id = try tb_insert_html(p, tk)
        ret (false, ok)
    }
    if nm_in(",rb,rtc,", name) {
        if tb_in_scope(p, "ruby", SC_DEFAULT) { tb_implied(p, "") }
        let id = try tb_insert_html(p, tk)
        ret (false, ok)
    }
    if nm_in(",rp,rt,", name) {
        if tb_in_scope(p, "ruby", SC_DEFAULT) { tb_implied(p, "rtc") }
        let id = try tb_insert_html(p, tk)
        ret (false, ok)
    }
    if str.eq(name, "math") || str.eq(name, "svg") {
        try tb_reconstruct(p)
        var ns: Namespace = .MathMl
        if str.eq(name, "svg") { ns = .Svg }
        let attrs = try tb_adjust_attrs(p, tk.attrs, ns)
        let id = try tb_insert_element(p, ns, name, attrs)
        if tk.self_closing { tb_pop(p) }
        ret (false, ok)
    }
    if nm_in(",caption,col,colgroup,frame,head,tbody,td,tfoot,th,thead,tr,", name) { ret (false, ok) }
    try tb_reconstruct(p)
    let id = try tb_insert_html(p, tk)
    ret (false, ok)
}

fn tm_body_end(p: *Ps, tk: *Tok) -> (bool, err) {
    let name = tk.name
    if str.eq(name, "template") {
        let again = try tm_in_head(p, tk)
        ret (again, ok)
    }
    if str.eq(name, "body") {
        if tb_in_scope(p, "body", SC_DEFAULT) { p.mode = M_AFTER_BODY }
        ret (false, ok)
    }
    if str.eq(name, "html") {
        if tb_in_scope(p, "body", SC_DEFAULT) {
            p.mode = M_AFTER_BODY
            ret (true, ok)
        }
        ret (false, ok)
    }
    if nm_in(",address,article,aside,blockquote,button,center,details,dialog,dir,div,dl,fieldset,figcaption,figure,footer,header,hgroup,listing,main,menu,nav,ol,pre,search,section,summary,ul,", name) {
        if !tb_in_scope(p, name, SC_DEFAULT) { ret (false, ok) }
        tb_implied(p, "")
        tb_pop_until(p, name)
        ret (false, ok)
    }
    if str.eq(name, "form") {
        if !tb_open_has(p, "template") {
            let node_form = p.form
            p.form = NONE
            if node_form == NONE { ret (false, ok) }
            if !tb_in_scope_id(p, node_form, SC_DEFAULT) { ret (false, ok) }
            tb_implied(p, "")
            let (at, found) = tb_open_index(p, node_form)
            if found { tb_open_remove_at(p, at) }
            ret (false, ok)
        }
        if !tb_in_scope(p, "form", SC_DEFAULT) { ret (false, ok) }
        tb_implied(p, "")
        tb_pop_until(p, "form")
        ret (false, ok)
    }
    if str.eq(name, "p") {
        if !tb_in_scope(p, "p", SC_BUTTON) {
            let id = try tb_insert_named(p, "p")
        }
        tb_close_p(p)
        ret (false, ok)
    }
    if str.eq(name, "li") {
        if !tb_in_scope(p, "li", SC_LIST) { ret (false, ok) }
        tb_implied(p, "li")
        tb_pop_until(p, "li")
        ret (false, ok)
    }
    if nm_in(",dd,dt,", name) {
        if !tb_in_scope(p, name, SC_DEFAULT) { ret (false, ok) }
        tb_implied(p, name)
        tb_pop_until(p, name)
        ret (false, ok)
    }
    if nm_in(",h1,h2,h3,h4,h5,h6,", name) {
        if !tb_in_scope_set(p, ",h1,h2,h3,h4,h5,h6,", SC_DEFAULT) { ret (false, ok) }
        tb_implied(p, "")
        tb_pop_until_set(p, ",h1,h2,h3,h4,h5,h6,")
        ret (false, ok)
    }
    if nm_in(",a,b,big,code,em,font,i,nobr,s,small,strike,strong,tt,u,", name) {
        let other = try tb_adoption(p, name)
        if other { tb_any_other_end(p, name) }
        ret (false, ok)
    }
    if nm_in(",applet,marquee,object,", name) {
        if !tb_in_scope(p, name, SC_DEFAULT) { ret (false, ok) }
        tb_implied(p, "")
        tb_pop_until(p, name)
        tb_fmt_clear_to_marker(p)
        ret (false, ok)
    }
    if str.eq(name, "br") {
        tk.kind = .Start
        tk.attrs = no_attrs()
        let again = try tm_body_start(p, tk)
        ret (again, ok)
    }
    tb_any_other_end(p, name)
    ret (false, ok)
}

// --- Text (RCDATA, RAWTEXT, script data).

fn tm_text(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        try tb_insert_chars(p, tk.data)
        ret (false, ok)
    }
    if tk.kind == .Eof {
        tb_pop(p)
        p.mode = p.orig_mode
        ret (true, ok)
    }
    if tk.kind == .End {
        tb_pop(p)
        p.mode = p.orig_mode
    }
    ret (false, ok)
}

// --- Tables.

fn tb_cell_close(p: *Ps) {
    tb_implied(p, "")
    tb_pop_until_set(p, ",td,th,")
    tb_fmt_clear_to_marker(p)
    p.mode = M_IN_ROW
}

fn tm_in_table(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars && pn_in(p, tb_cur(p), ",table,tbody,template,tfoot,thead,tr,") {
        p.npend = 0usize
        p.orig_mode = p.mode
        p.mode = M_IN_TABLE_TEXT
        ret (true, ok)
    }
    if tk.kind == .Comment {
        try tb_insert_comment(p, tk.data, NONE)
        ret (false, ok)
    }
    if tk.kind == .Doctype { ret (false, ok) }
    if tk.kind == .Start {
        let name = tk.name
        if str.eq(name, "caption") {
            tb_clear_to(p, ",table,template,html,")
            try tb_fmt_marker(p)
            let id = try tb_insert_html(p, tk)
            p.mode = M_IN_CAPTION
            ret (false, ok)
        }
        if str.eq(name, "colgroup") {
            tb_clear_to(p, ",table,template,html,")
            let id = try tb_insert_html(p, tk)
            p.mode = M_IN_COLGROUP
            ret (false, ok)
        }
        if str.eq(name, "col") {
            tb_clear_to(p, ",table,template,html,")
            let id = try tb_insert_named(p, "colgroup")
            p.mode = M_IN_COLGROUP
            ret (true, ok)
        }
        if nm_in(",tbody,tfoot,thead,", name) {
            tb_clear_to(p, ",table,template,html,")
            let id = try tb_insert_html(p, tk)
            p.mode = M_IN_TBODY
            ret (false, ok)
        }
        if nm_in(",td,th,tr,", name) {
            tb_clear_to(p, ",table,template,html,")
            let id = try tb_insert_named(p, "tbody")
            p.mode = M_IN_TBODY
            ret (true, ok)
        }
        if str.eq(name, "table") {
            if !tb_in_scope(p, "table", SC_TABLE) { ret (false, ok) }
            tb_pop_until(p, "table")
            tb_reset_mode(p)
            ret (true, ok)
        }
        if nm_in(",style,script,template,", name) {
            let again = try tm_in_head(p, tk)
            ret (again, ok)
        }
        if str.eq(name, "input") {
            let (kind, has) = tk_attr(tk, "type")
            if has && ascii_eq_fold(kind, "hidden") {
                let id = try tb_insert_html(p, tk)
                tb_pop(p)
                ret (false, ok)
            }
        }
        if str.eq(name, "form") {
            if tb_open_has(p, "template") || p.form != NONE { ret (false, ok) }
            let id = try tb_insert_html(p, tk)
            p.form = id
            tb_pop(p)
            ret (false, ok)
        }
    }
    if tk.kind == .End {
        let name = tk.name
        if str.eq(name, "table") {
            if !tb_in_scope(p, "table", SC_TABLE) { ret (false, ok) }
            tb_pop_until(p, "table")
            tb_reset_mode(p)
            ret (false, ok)
        }
        if nm_in(",body,caption,col,colgroup,html,tbody,td,tfoot,th,thead,tr,", name) { ret (false, ok) }
        if str.eq(name, "template") {
            let again = try tm_in_head(p, tk)
            ret (again, ok)
        }
    }
    if tk.kind == .Eof {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    p.foster = true
    let again = try tm_in_body(p, tk)
    p.foster = false
    ret (again, ok)
}

fn tm_in_table_text(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let data = try tb_strip_nul(p, tk.data)
        if p.pend.len == 0usize { p.pend = try mem.alloc[u8](p.a, p.src.len * 3usize + 16usize) }
        if p.npend + data.len > p.pend.len { ret (false, TooLarge) }
        mem.copy[u8](p.pend[p.npend..p.npend + data.len], data)
        p.npend += data.len
        ret (false, ok)
    }
    if p.npend > 0usize {
        let copy = try mem.alloc[u8](p.a, p.npend)
        mem.copy[u8](copy, p.pend[..p.npend])
        p.npend = 0usize
        if ws_prefix(copy) != copy.len {
            p.foster = true
            try tb_reconstruct(p)
            try tb_insert_chars(p, copy)
            p.foster = false
            p.frameset_ok = false
        } else {
            try tb_insert_chars(p, copy)
        }
    }
    p.mode = p.orig_mode
    ret (true, ok)
}

fn tm_in_caption(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .End && str.eq(tk.name, "caption") {
        if !tb_in_scope(p, "caption", SC_TABLE) { ret (false, ok) }
        tb_implied(p, "")
        tb_pop_until(p, "caption")
        tb_fmt_clear_to_marker(p)
        p.mode = M_IN_TABLE
        ret (false, ok)
    }
    if (tk.kind == .Start && nm_in(",caption,col,colgroup,tbody,td,tfoot,th,thead,tr,", tk.name)) || (tk.kind == .End && str.eq(tk.name, "table")) {
        if !tb_in_scope(p, "caption", SC_TABLE) { ret (false, ok) }
        tb_implied(p, "")
        tb_pop_until(p, "caption")
        tb_fmt_clear_to_marker(p)
        p.mode = M_IN_TABLE
        ret (true, ok)
    }
    if tk.kind == .End && nm_in(",body,col,colgroup,html,tbody,td,tfoot,th,thead,tr,", tk.name) { ret (false, ok) }
    let again = try tm_in_body(p, tk)
    ret (again, ok)
}

fn tm_in_colgroup(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let w = ws_prefix(tk.data)
        if w > 0usize { try tb_insert_chars(p, tk.data[..w]) }
        if w == tk.data.len { ret (false, ok) }
        tk.data = tk.data[w..]
    }
    if tk.kind == .Comment {
        try tb_insert_comment(p, tk.data, NONE)
        ret (false, ok)
    }
    if tk.kind == .Doctype { ret (false, ok) }
    if tk.kind == .Start && str.eq(tk.name, "html") {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    if tk.kind == .Start && str.eq(tk.name, "col") {
        let id = try tb_insert_html(p, tk)
        tb_pop(p)
        ret (false, ok)
    }
    if tk.kind == .End && str.eq(tk.name, "colgroup") {
        if !pn_is(p, tb_cur(p), "colgroup") { ret (false, ok) }
        tb_pop(p)
        p.mode = M_IN_TABLE
        ret (false, ok)
    }
    if tk.kind == .End && str.eq(tk.name, "col") { ret (false, ok) }
    if (tk.kind == .Start || tk.kind == .End) && str.eq(tk.name, "template") {
        let again = try tm_in_head(p, tk)
        ret (again, ok)
    }
    if tk.kind == .Eof {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    if !pn_is(p, tb_cur(p), "colgroup") { ret (false, ok) }
    tb_pop(p)
    p.mode = M_IN_TABLE
    ret (true, ok)
}

fn tm_in_tbody(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Start {
        if str.eq(tk.name, "tr") {
            tb_clear_to(p, ",tbody,tfoot,thead,template,html,")
            let id = try tb_insert_html(p, tk)
            p.mode = M_IN_ROW
            ret (false, ok)
        }
        if nm_in(",th,td,", tk.name) {
            tb_clear_to(p, ",tbody,tfoot,thead,template,html,")
            let id = try tb_insert_named(p, "tr")
            p.mode = M_IN_ROW
            ret (true, ok)
        }
        if nm_in(",caption,col,colgroup,tbody,tfoot,thead,", tk.name) {
            if !tb_in_scope_set(p, ",tbody,thead,tfoot,", SC_TABLE) { ret (false, ok) }
            tb_clear_to(p, ",tbody,tfoot,thead,template,html,")
            tb_pop(p)
            p.mode = M_IN_TABLE
            ret (true, ok)
        }
    }
    if tk.kind == .End {
        if nm_in(",tbody,tfoot,thead,", tk.name) {
            if !tb_in_scope(p, tk.name, SC_TABLE) { ret (false, ok) }
            tb_clear_to(p, ",tbody,tfoot,thead,template,html,")
            tb_pop(p)
            p.mode = M_IN_TABLE
            ret (false, ok)
        }
        if str.eq(tk.name, "table") {
            if !tb_in_scope_set(p, ",tbody,thead,tfoot,", SC_TABLE) { ret (false, ok) }
            tb_clear_to(p, ",tbody,tfoot,thead,template,html,")
            tb_pop(p)
            p.mode = M_IN_TABLE
            ret (true, ok)
        }
        if nm_in(",body,caption,col,colgroup,html,td,th,tr,", tk.name) { ret (false, ok) }
    }
    let again = try tm_in_table(p, tk)
    ret (again, ok)
}

fn tm_in_row(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Start {
        if nm_in(",th,td,", tk.name) {
            tb_clear_to(p, ",tr,template,html,")
            let id = try tb_insert_html(p, tk)
            p.mode = M_IN_CELL
            try tb_fmt_marker(p)
            ret (false, ok)
        }
        if nm_in(",caption,col,colgroup,tbody,tfoot,thead,tr,", tk.name) {
            if !tb_in_scope(p, "tr", SC_TABLE) { ret (false, ok) }
            tb_clear_to(p, ",tr,template,html,")
            tb_pop(p)
            p.mode = M_IN_TBODY
            ret (true, ok)
        }
    }
    if tk.kind == .End {
        if str.eq(tk.name, "tr") {
            if !tb_in_scope(p, "tr", SC_TABLE) { ret (false, ok) }
            tb_clear_to(p, ",tr,template,html,")
            tb_pop(p)
            p.mode = M_IN_TBODY
            ret (false, ok)
        }
        if str.eq(tk.name, "table") {
            if !tb_in_scope(p, "tr", SC_TABLE) { ret (false, ok) }
            tb_clear_to(p, ",tr,template,html,")
            tb_pop(p)
            p.mode = M_IN_TBODY
            ret (true, ok)
        }
        if nm_in(",tbody,tfoot,thead,", tk.name) {
            if !tb_in_scope(p, tk.name, SC_TABLE) { ret (false, ok) }
            if !tb_in_scope(p, "tr", SC_TABLE) { ret (false, ok) }
            tb_clear_to(p, ",tr,template,html,")
            tb_pop(p)
            p.mode = M_IN_TBODY
            ret (true, ok)
        }
        if nm_in(",body,caption,col,colgroup,html,td,th,", tk.name) { ret (false, ok) }
    }
    let again = try tm_in_table(p, tk)
    ret (again, ok)
}

fn tm_in_cell(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .End {
        if nm_in(",td,th,", tk.name) {
            if !tb_in_scope(p, tk.name, SC_TABLE) { ret (false, ok) }
            tb_implied(p, "")
            tb_pop_until(p, tk.name)
            tb_fmt_clear_to_marker(p)
            p.mode = M_IN_ROW
            ret (false, ok)
        }
        if nm_in(",body,caption,col,colgroup,html,", tk.name) { ret (false, ok) }
        if nm_in(",table,tbody,tfoot,thead,tr,", tk.name) {
            if !tb_in_scope(p, tk.name, SC_TABLE) { ret (false, ok) }
            if !tb_in_scope_set(p, ",td,th,", SC_TABLE) { ret (false, ok) }
            tb_cell_close(p)
            ret (true, ok)
        }
    }
    if tk.kind == .Start && nm_in(",caption,col,colgroup,tbody,td,tfoot,th,thead,tr,", tk.name) {
        if !tb_in_scope_set(p, ",td,th,", SC_TABLE) { ret (false, ok) }
        tb_cell_close(p)
        ret (true, ok)
    }
    let again = try tm_in_body(p, tk)
    ret (again, ok)
}

// --- Select.

fn tm_in_select(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let data = try tb_strip_nul(p, tk.data)
        if data.len == 0usize { ret (false, ok) }
        try tb_reconstruct(p)
        try tb_insert_chars(p, data)
        ret (false, ok)
    }
    if tk.kind == .Comment {
        try tb_insert_comment(p, tk.data, NONE)
        ret (false, ok)
    }
    if tk.kind == .Doctype { ret (false, ok) }
    if tk.kind == .Eof {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    if tk.kind == .Start {
        let name = tk.name
        if str.eq(name, "html") {
            let again = try tm_in_body(p, tk)
            ret (again, ok)
        }
        if str.eq(name, "option") {
            if pn_is(p, tb_cur(p), "option") { tb_pop(p) }
            try tb_reconstruct(p)
            let id = try tb_insert_html(p, tk)
            ret (false, ok)
        }
        if str.eq(name, "optgroup") {
            if pn_is(p, tb_cur(p), "option") { tb_pop(p) }
            if pn_is(p, tb_cur(p), "optgroup") { tb_pop(p) }
            try tb_reconstruct(p)
            let id = try tb_insert_html(p, tk)
            ret (false, ok)
        }
        if str.eq(name, "hr") {
            if pn_is(p, tb_cur(p), "option") { tb_pop(p) }
            if pn_is(p, tb_cur(p), "optgroup") { tb_pop(p) }
            let id = try tb_insert_html(p, tk)
            tb_pop(p)
            ret (false, ok)
        }
        if str.eq(name, "select") {
            if !tb_open_has(p, "select") { ret (false, ok) }
            tb_pop_until(p, "select")
            tb_reset_mode(p)
            ret (false, ok)
        }
        if str.eq(name, "input") {
            if !tb_open_has(p, "select") { ret (false, ok) }
            tb_pop_until(p, "select")
            tb_reset_mode(p)
            ret (true, ok)
        }
        if nm_in(",script,template,", name) {
            let again = try tm_in_head(p, tk)
            ret (again, ok)
        }
    }
    if tk.kind == .End {
        let name = tk.name
        if str.eq(name, "optgroup") {
            if pn_is(p, tb_cur(p), "option") && p.nopen >= 2usize && pn_is(p, p.open[p.nopen - 2usize], "optgroup") { tb_pop(p) }
            if pn_is(p, tb_cur(p), "optgroup") { tb_pop(p) }
            ret (false, ok)
        }
        if str.eq(name, "option") {
            if pn_is(p, tb_cur(p), "option") { tb_pop(p) }
            ret (false, ok)
        }
        if str.eq(name, "select") {
            if !tb_open_has(p, "select") { ret (false, ok) }
            tb_pop_until(p, "select")
            tb_reset_mode(p)
            ret (false, ok)
        }
        if str.eq(name, "template") {
            let again = try tm_in_head(p, tk)
            ret (again, ok)
        }
    }
    let again = try tm_in_body(p, tk)
    ret (again, ok)
}

fn tm_in_select_table(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Start && nm_in(",caption,table,tbody,tfoot,thead,tr,td,th,", tk.name) {
        tb_pop_until(p, "select")
        tb_reset_mode(p)
        ret (true, ok)
    }
    if tk.kind == .End && nm_in(",caption,table,tbody,tfoot,thead,tr,td,th,", tk.name) {
        if !tb_in_scope(p, tk.name, SC_TABLE) { ret (false, ok) }
        tb_pop_until(p, "select")
        tb_reset_mode(p)
        ret (true, ok)
    }
    let again = try tm_in_select(p, tk)
    ret (again, ok)
}

// --- Template.

fn tb_template_switch(p: *Ps, mode: u8) {
    if p.ntmodes > 0usize { p.ntmodes -= 1usize }
    if p.ntmodes < 64usize {
        p.tmodes[p.ntmodes] = mode
        p.ntmodes += 1usize
    }
    p.mode = mode
}

fn tm_in_template(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars || tk.kind == .Comment || tk.kind == .Doctype {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    if tk.kind == .Start {
        let name = tk.name
        if nm_in(",base,basefont,bgsound,link,meta,noframes,script,style,template,title,", name) {
            let again = try tm_in_head(p, tk)
            ret (again, ok)
        }
        if nm_in(",caption,colgroup,tbody,tfoot,thead,", name) {
            tb_template_switch(p, M_IN_TABLE)
            ret (true, ok)
        }
        if str.eq(name, "col") {
            tb_template_switch(p, M_IN_COLGROUP)
            ret (true, ok)
        }
        if str.eq(name, "tr") {
            tb_template_switch(p, M_IN_TBODY)
            ret (true, ok)
        }
        if nm_in(",td,th,", name) {
            tb_template_switch(p, M_IN_ROW)
            ret (true, ok)
        }
        tb_template_switch(p, M_IN_BODY)
        ret (true, ok)
    }
    if tk.kind == .End {
        if str.eq(tk.name, "template") {
            let again = try tm_in_head(p, tk)
            ret (again, ok)
        }
        ret (false, ok)
    }
    if !tb_open_has(p, "template") {
        p.stopped = true
        ret (false, ok)
    }
    tb_pop_until(p, "template")
    tb_fmt_clear_to_marker(p)
    if p.ntmodes > 0usize { p.ntmodes -= 1usize }
    tb_reset_mode(p)
    ret (true, ok)
}

// --- After body, framesets.

fn tm_after_body(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let w = ws_prefix(tk.data)
        if w == tk.data.len {
            let again = try tm_in_body(p, tk)
            ret (again, ok)
        }
    }
    if tk.kind == .Comment {
        try tb_insert_comment(p, tk.data, p.open[0usize])
        ret (false, ok)
    }
    if tk.kind == .Doctype { ret (false, ok) }
    if tk.kind == .Start && str.eq(tk.name, "html") {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    if tk.kind == .End && str.eq(tk.name, "html") {
        if !p.fragment { p.mode = M_AFTER_AFTER_BODY }
        ret (false, ok)
    }
    if tk.kind == .Eof {
        p.stopped = true
        ret (false, ok)
    }
    p.mode = M_IN_BODY
    ret (true, ok)
}

fn tm_in_frameset(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let kept = try tb_ws_only(p, tk.data)
        if kept.len > 0usize { try tb_insert_chars(p, kept) }
        ret (false, ok)
    }
    if tk.kind == .Comment {
        try tb_insert_comment(p, tk.data, NONE)
        ret (false, ok)
    }
    if tk.kind == .Start {
        if str.eq(tk.name, "html") {
            let again = try tm_in_body(p, tk)
            ret (again, ok)
        }
        if str.eq(tk.name, "frameset") {
            let id = try tb_insert_html(p, tk)
            ret (false, ok)
        }
        if str.eq(tk.name, "frame") {
            let id = try tb_insert_html(p, tk)
            tb_pop(p)
            ret (false, ok)
        }
        if str.eq(tk.name, "noframes") {
            let again = try tm_in_head(p, tk)
            ret (again, ok)
        }
    }
    if tk.kind == .End && str.eq(tk.name, "frameset") {
        if p.nopen == 1usize { ret (false, ok) }
        tb_pop(p)
        if !p.fragment && !pn_is(p, tb_cur(p), "frameset") { p.mode = M_AFTER_FRAMESET }
        ret (false, ok)
    }
    if tk.kind == .Eof { p.stopped = true }
    ret (false, ok)
}

fn tm_after_frameset(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let kept = try tb_ws_only(p, tk.data)
        if kept.len > 0usize { try tb_insert_chars(p, kept) }
        ret (false, ok)
    }
    if tk.kind == .Comment {
        try tb_insert_comment(p, tk.data, NONE)
        ret (false, ok)
    }
    if tk.kind == .Start && str.eq(tk.name, "html") {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    if tk.kind == .End && str.eq(tk.name, "html") {
        p.mode = M_AFTER_AFTER_FRAMESET
        ret (false, ok)
    }
    if tk.kind == .Start && str.eq(tk.name, "noframes") {
        let again = try tm_in_head(p, tk)
        ret (again, ok)
    }
    if tk.kind == .Eof { p.stopped = true }
    ret (false, ok)
}

fn tm_after_after_body(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Comment {
        try tb_comment_doc(p, tk)
        ret (false, ok)
    }
    if tk.kind == .Doctype || (tk.kind == .Start && str.eq(tk.name, "html")) {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    if tk.kind == .Chars && ws_prefix(tk.data) == tk.data.len {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    if tk.kind == .Eof {
        p.stopped = true
        ret (false, ok)
    }
    p.mode = M_IN_BODY
    ret (true, ok)
}

fn tm_after_after_frameset(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Comment {
        try tb_comment_doc(p, tk)
        ret (false, ok)
    }
    if tk.kind == .Doctype || (tk.kind == .Start && str.eq(tk.name, "html")) {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    if tk.kind == .Chars {
        let kept = try tb_ws_only(p, tk.data)
        if kept.len > 0usize {
            let again = try tm_in_body(p, tk)
            ret (again, ok)
        }
        ret (false, ok)
    }
    if tk.kind == .Start && str.eq(tk.name, "noframes") {
        let again = try tm_in_head(p, tk)
        ret (again, ok)
    }
    if tk.kind == .Eof { p.stopped = true }
    ret (false, ok)
}

// The white space bytes of `s`, in order.
fn tb_ws_only(p: *Ps, s: str) -> (str, err) {
    var count = 0usize
    var i = 0usize
    while i < s.len {
        if ws_byte(s[i]) { count += 1usize }
        i += 1usize
    }
    if count == s.len { ret (s, ok) }
    let out = try mem.alloc[u8](p.a, count)
    var at = 0usize
    i = 0usize
    while i < s.len {
        if ws_byte(s[i]) {
            out[at] = s[i]
            at += 1usize
        }
        i += 1usize
    }
    ret (out[..at], ok)
}

// --- Foreign content.

fn tm_foreign(p: *Ps, tk: *Tok) -> (bool, err) {
    if tk.kind == .Chars {
        let data = try tk_clean(p, tk.data, false)
        try tb_insert_chars(p, data)
        var solid = false
        var k = 0usize
        while k < tk.data.len {
            if tk.data[k] != 0u8 && !ws_byte(tk.data[k]) { solid = true }
            k += 1usize
        }
        if solid { p.frameset_ok = false }
        ret (false, ok)
    }
    if tk.kind == .Comment {
        try tb_insert_comment(p, tk.data, NONE)
        ret (false, ok)
    }
    if tk.kind == .Doctype { ret (false, ok) }
    if tk.kind == .Start {
        var breakout = nm_in(",b,big,blockquote,body,br,center,code,dd,div,dl,dt,em,embed,h1,h2,h3,h4,h5,h6,head,hr,i,img,li,listing,menu,meta,nobr,ol,p,pre,ruby,s,small,span,strong,strike,sub,sup,table,tt,u,ul,var,", tk.name)
        if str.eq(tk.name, "font") {
            let (_, has_color) = tk_attr(tk, "color")
            let (_, has_face) = tk_attr(tk, "face")
            let (_, has_size) = tk_attr(tk, "size")
            if has_color || has_face || has_size { breakout = true }
        }
        if breakout {
            while p.nopen > 0usize {
                let top = tb_cur(p)
                if p.nodes[usize(top)].namespace == .Html || tb_mathml_text_ip(p, top) || tb_html_ip(p, top) { break }
                tb_pop(p)
            }
            if p.fragment && p.nopen == 1usize {
                // Nothing left to pop but the foreign context element: the HTML rules take it.
                let again = try tb_mode(p, tk, p.mode)
                ret (again, ok)
            }
            ret (true, ok)
        }
        let adj = tb_adjusted(p)
        let ns = p.nodes[usize(adj)].namespace
        var name = tk.name
        if ns == .Svg { name = tb_svg_name(name) }
        let attrs = try tb_adjust_attrs(p, tk.attrs, ns)
        let id = try tb_insert_element(p, ns, name, attrs)
        if tk.self_closing { tb_pop(p) }
        ret (false, ok)
    }
    // An end tag.
    if nm_in(",br,p,", tk.name) {
        while p.nopen > 0usize {
            let cur_top = tb_cur(p)
            if p.nodes[usize(cur_top)].namespace == .Html || tb_mathml_text_ip(p, cur_top) || tb_html_ip(p, cur_top) { break }
            tb_pop(p)
        }
        if p.fragment && p.nopen == 1usize {
            let again = try tb_mode(p, tk, p.mode)
            ret (again, ok)
        }
        ret (true, ok)
    }
    let top = tb_cur(p)
    if str.eq(tk.name, "script") && p.nodes[usize(top)].namespace == .Svg && str.eq(p.nodes[usize(top)].name, "script") {
        tb_pop(p)
        ret (false, ok)
    }
    var i = p.nopen - 1usize
    while true {
        if i == 0usize { ret (false, ok) }
        if ascii_eq_fold(p.nodes[usize(p.open[i])].name, tk.name) {
            p.nopen = i
            ret (false, ok)
        }
        i -= 1usize
        if p.nodes[usize(p.open[i])].namespace == .Html { break }
    }
    let again = try tb_mode(p, tk, p.mode)
    ret (again, ok)
}

// --- The dispatcher.

fn tb_mode(p: *Ps, tk: *Tok, mode: u8) -> (bool, err) {
    if mode == M_INITIAL {
        let again = try tm_initial(p, tk)
        ret (again, ok)
    }
    if mode == M_BEFORE_HTML {
        let again = try tm_before_html(p, tk)
        ret (again, ok)
    }
    if mode == M_BEFORE_HEAD {
        let again = try tm_before_head(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_HEAD {
        let again = try tm_in_head(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_HEAD_NOSCRIPT {
        let again = try tm_in_head_noscript(p, tk)
        ret (again, ok)
    }
    if mode == M_AFTER_HEAD {
        let again = try tm_after_head(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_BODY {
        let again = try tm_in_body(p, tk)
        ret (again, ok)
    }
    if mode == M_TEXT {
        let again = try tm_text(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_TABLE {
        let again = try tm_in_table(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_TABLE_TEXT {
        let again = try tm_in_table_text(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_CAPTION {
        let again = try tm_in_caption(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_COLGROUP {
        let again = try tm_in_colgroup(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_TBODY {
        let again = try tm_in_tbody(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_ROW {
        let again = try tm_in_row(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_CELL {
        let again = try tm_in_cell(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_SELECT {
        let again = try tm_in_select(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_SELECT_TABLE {
        let again = try tm_in_select_table(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_TEMPLATE {
        let again = try tm_in_template(p, tk)
        ret (again, ok)
    }
    if mode == M_AFTER_BODY {
        let again = try tm_after_body(p, tk)
        ret (again, ok)
    }
    if mode == M_IN_FRAMESET {
        let again = try tm_in_frameset(p, tk)
        ret (again, ok)
    }
    if mode == M_AFTER_FRAMESET {
        let again = try tm_after_frameset(p, tk)
        ret (again, ok)
    }
    if mode == M_AFTER_AFTER_BODY {
        let again = try tm_after_after_body(p, tk)
        ret (again, ok)
    }
    let again = try tm_after_after_frameset(p, tk)
    ret (again, ok)
}

fn tb_use_foreign(p: *Ps, tk: *Tok) -> bool {
    if p.nopen == 0usize || tk.kind == .Eof { ret false }
    let adj = tb_adjusted(p)
    if p.nodes[usize(adj)].namespace == .Html { ret false }
    if tb_mathml_text_ip(p, adj) {
        if tk.kind == .Start && !nm_in(",mglyph,malignmark,", tk.name) { ret false }
        if tk.kind == .Chars { ret false }
    }
    if p.nodes[usize(adj)].namespace == .MathMl && str.eq(p.nodes[usize(adj)].name, "annotation-xml") && tk.kind == .Start && str.eq(tk.name, "svg") { ret false }
    if tb_html_ip(p, adj) && (tk.kind == .Start || tk.kind == .Chars) { ret false }
    ret true
}

fn tb_process(p: *Ps, tk: *Tok) -> err {
    if p.ignore_lf {
        p.ignore_lf = false
        if tk.kind == .Chars && tk.data.len > 0usize && tk.data[0usize] == 10u8 {
            tk.data = tk.data[1usize..]
            if tk.data.len == 0usize { ret ok }
        }
    }
    var rounds = 0usize
    while rounds < 64usize {
        rounds += 1usize
        var again = false
        if tb_use_foreign(p, tk) {
            again = try tm_foreign(p, tk)
        } else {
            again = try tb_mode(p, tk, p.mode)
        }
        if !again { break }
    }
    ret ok
}

// --- Entry points.

fn normalize_newlines(a: *mem.Arena, s: str) -> (str, err) {
    var has_cr = false
    var i = 0usize
    while i < s.len {
        if s[i] == 13u8 { has_cr = true }
        i += 1usize
    }
    if !has_cr { ret (s, ok) }
    let out = try mem.alloc[u8](a, s.len)
    var at = 0usize
    i = 0usize
    while i < s.len {
        if s[i] == 13u8 {
            out[at] = 10u8
            at += 1usize
            if i + 1usize < s.len && s[i + 1usize] == 10u8 { i += 1usize }
        } else {
            out[at] = s[i]
            at += 1usize
        }
        i += 1usize
    }
    ret (out[..at], ok)
}

fn ps_new(a: *mem.Arena, source: str, options: Options) -> (Ps, err) {
    if source.len > options.max_bytes { ret (zero, TooLarge) }
    if !utf8_valid(source) { ret (zero, InvalidEncoding) }
    var src = source
    if src.len >= 3usize && src[0usize] == 239u8 && src[1usize] == 187u8 && src[2usize] == 191u8 { src = src[3usize..] }
    src = try normalize_newlines(a, src)
    let nodes = try mem.alloc[Node](a, options.max_nodes)
    let open = try mem.alloc[NodeId](a, usize(options.max_depth) + 1usize)
    let fmt_list = try mem.alloc[NodeId](a, usize(options.max_depth) + 1usize)
    var p = Ps { a: a, src: src, pos: 0usize, nodes: nodes, used: 0usize, options: options, ts: TS_DATA, last_start: "", open: open, nopen: 0usize, fmt: fmt_list, nfmt: 0usize, tmodes: zero, ntmodes: 0usize, mode: M_INITIAL, orig_mode: M_INITIAL, head: NONE, form: NONE, ctx: NONE, fragment: false, frameset_ok: true, foster: false, quirks: Q_NO, ignore_lf: false, stopped: false, scripting: false, pend: zero, npend: 0usize, xml: xml_syntax }
    ret (p, ok)
}

// Documents served as XHTML close any element written `<x/>`; set by the host around a parse.
var xml_syntax: bool = false

fn set_xml_syntax(on: bool) { xml_syntax = on }

fn tb_run(p: *Ps) -> err {
    var tk: Tok = zero
    while !p.stopped {
        try tk_next(p, &tk)
        // XHTML written with a prefixed SVG vocabulary (`<svg:svg xmlns:svg=...>`): the prefix names the namespace the foreign
        // content rules already give an `<svg>` element, so it is dropped.
        if p.xml && (tk.kind == .Start || tk.kind == .End) && tk.name.len > 4usize && str.eq(tk.name[0usize..4usize], "svg:") { tk.name = tk.name[4usize..] }
        try tb_process(p, &tk)
        if p.xml && tk.kind == .Start && tk.self_closing && !is_void(tk.name) && p.nopen > 0usize {
            var et: Tok = zero
            et.kind = .End
            et.name = tk.name
            try tb_process(p, &et)
        }
        if tk.kind == .Eof { break }
    }
    ret ok
}

// --- <selectedcontent>: a clone of the selected option's content, filled when parsing ends.

fn tb_clone_deep(p: *Ps, id: NodeId) -> (NodeId, err) {
    let (copy, copy_error) = pn_new(p, p.nodes[usize(id)].kind, p.nodes[usize(id)].namespace, p.nodes[usize(id)].name, p.nodes[usize(id)].value)
    if copy_error != ok { ret (NONE, copy_error) }
    p.nodes[usize(copy)].attributes = p.nodes[usize(id)].attributes
    var child = p.nodes[usize(id)].first_child
    while child != NONE {
        let (inner, inner_error) = tb_clone_deep(p, child)
        if inner_error != ok { ret (NONE, inner_error) }
        pn_insert(p, copy, inner, NONE)
        child = p.nodes[usize(child)].next_sibling
    }
    ret (copy, ok)
}

// The next node after `id` in tree order inside `root`, or NONE.
fn tb_walk_next(p: *Ps, root: NodeId, id: NodeId) -> NodeId {
    let first = p.nodes[usize(id)].first_child
    if first != NONE { ret first }
    var cur = id
    while cur != root && cur != NONE {
        let sibling = p.nodes[usize(cur)].next_sibling
        if sibling != NONE { ret sibling }
        cur = p.nodes[usize(cur)].parent
    }
    ret NONE
}

fn tb_selectedcontent(p: *Ps) -> err {
    let total = p.used
    var i = 0usize
    while i < total {
        let select_id = u32(i)
        i += 1usize
        if p.nodes[usize(select_id)].kind != .Element || !pn_is(p, select_id, "select") { continue }
        var chosen = NONE
        var first_option = NONE
        var cur = tb_walk_next(p, select_id, select_id)
        while cur != NONE {
            if p.nodes[usize(cur)].kind == .Element && pn_is(p, cur, "option") {
                if first_option == NONE { first_option = cur }
                let (_, picked) = attribute(&p.nodes[usize(cur)], "selected")
                if picked { chosen = cur }
            }
            cur = tb_walk_next(p, select_id, cur)
        }
        if chosen == NONE { chosen = first_option }
        if chosen == NONE { continue }
        cur = tb_walk_next(p, select_id, select_id)
        while cur != NONE {
            if p.nodes[usize(cur)].kind == .Element && pn_is(p, cur, "selectedcontent") {
                while p.nodes[usize(cur)].first_child != NONE { pn_detach(p, p.nodes[usize(cur)].first_child) }
                var child = p.nodes[usize(chosen)].first_child
                while child != NONE {
                    let copy = try tb_clone_deep(p, child)
                    pn_insert(p, cur, copy, NONE)
                    child = p.nodes[usize(child)].next_sibling
                }
            }
            cur = tb_walk_next(p, select_id, cur)
        }
    }
    ret ok
}

fn parse(a: *mem.Arena, source: str, options: Options) -> (Document, err) {
    let (parsed, parse_error) = parse_with(a, source, options, false)
    ret (parsed, parse_error)
}

// `scripting`: whether scripting is enabled, which makes `noscript` hold raw text.
fn parse_with(a: *mem.Arena, source: str, options: Options, scripting: bool) -> (Document, err) {
    let (made, made_error) = ps_new(a, source, options)
    if made_error != ok { ret (zero, made_error) }
    var p = made
    p.scripting = scripting
    let (doc, doc_error) = pn_new(&p, .Document, .Html, "", "")
    if doc_error != ok { ret (zero, doc_error) }
    let run_error = tb_run(&p)
    if run_error != ok { ret (zero, run_error) }
    let fill_error = tb_selectedcontent(&p)
    if fill_error != ok { ret (zero, fill_error) }
    ret (Document { nodes: p.nodes[..p.used], root: doc, quirks: p.quirks }, ok)
}

// Parses `source` as the children of an element named `context` in `context_ns`
// (innerHTML). The result's root is a synthetic `html` element holding the fragment.
fn parse_fragment(a: *mem.Arena, source: str, context: str, context_ns: Namespace, options: Options) -> (Document, err) {
    let (parsed, parse_error) = parse_fragment_with(a, source, context, context_ns, options, false)
    ret (parsed, parse_error)
}

fn parse_fragment_with(a: *mem.Arena, source: str, context: str, context_ns: Namespace, options: Options, scripting: bool) -> (Document, err) {
    let (made, made_error) = ps_new(a, source, options)
    if made_error != ok { ret (zero, made_error) }
    var p = made
    p.scripting = scripting
    let (doc, doc_error) = pn_new(&p, .Document, .Html, "", "")
    if doc_error != ok { ret (zero, doc_error) }
    let (root, root_error) = pn_element(&p, .Html, "html", no_attrs())
    if root_error != ok { ret (zero, root_error) }
    pn_insert(&p, doc, root, NONE)
    let push_error = tb_push(&p, root)
    if push_error != ok { ret (zero, push_error) }
    let (ctx_node, ctx_error) = pn_element(&p, context_ns, context, no_attrs())
    if ctx_error != ok { ret (zero, ctx_error) }
    p.ctx = ctx_node
    p.fragment = true
    if context_ns == .Html {
        if nm_in(",title,textarea,", context) { p.ts = TS_RCDATA }
        if nm_in(",style,xmp,iframe,noembed,noframes,", context) { p.ts = TS_RAWTEXT }
        if str.eq(context, "script") { p.ts = TS_SCRIPT }
        if scripting && str.eq(context, "noscript") { p.ts = TS_RAWTEXT }
        if str.eq(context, "plaintext") { p.ts = TS_PLAINTEXT }
        if str.eq(context, "template") {
            p.tmodes[0usize] = M_IN_TEMPLATE
            p.ntmodes = 1usize
        }
    }
    tb_reset_mode(&p)
    let run_error = tb_run(&p)
    if run_error != ok { ret (zero, run_error) }
    let fill_error = tb_selectedcontent(&p)
    if fill_error != ok { ret (zero, fill_error) }
    ret (Document { nodes: p.nodes[..p.used], root: root, quirks: p.quirks }, ok)
}

// A DOCTYPE node's identifiers: its value is the public id, a NUL, then the system id.
fn doctype_public(n: *const Node) -> str {
    let (at, found) = str.find(n.value, "\x00")
    if !found { ret "" }
    ret n.value[..at]
}

fn doctype_system(n: *const Node) -> str {
    let (at, found) = str.find(n.value, "\x00")
    if !found { ret "" }
    ret n.value[at + 1usize..]
}
