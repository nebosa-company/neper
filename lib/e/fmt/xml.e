// XML 1.0 as events: the reader takes the whole source into the arena and walks it
// tag by tag -- Start with its attributes (an empty element is Start with `empty`
// and then its End), End, Text (character data and CDATA, the five named entities
// and numeric references decoded; whitespace outside the root dropped), Comment when
// `preserve_comments`, Processing. The XML declaration is skipped; a DOCTYPE, an
// unknown entity or an external reference is `Unsupported`; a mismatched or missing
// end tag, a malformed tag or a reference is `Invalid`; nesting past `max_depth` is
// `TooDeep`. Names are taken as written, prefix and colon included. The writer
// escapes attribute values and text and refuses `--` in a comment.
use e.io
use e.mem
use e.str

type Attribute = struct { name: str, value: str }
type Event = union enum u8 { Start: StartElement, End: str, Text: str, Comment: str, Processing: Processing }
type StartElement = struct { name: str, attributes: []const Attribute, empty: bool }
type Processing = struct { target: str, data: str }
type Reader = struct { state: *void }
type Writer = struct { sink: io.Writer, depth: u16 }
type Options = struct { max_depth: u16, preserve_comments: bool }
error Invalid
error TooDeep
error Unsupported

// Open element names are kept on a stack of at most `max_depth` entries.
type State = struct { a: *mem.Arena, source: []const u8, at: usize, options: Options, stack: []str, depth: usize, pending_end: str, has_pending: bool, started: bool, finished: bool }

fn slurp(a: *mem.Arena, source: io.Reader) -> ([]u8, err) {
    var capacity = 4096usize
    let (first, first_error) = mem.alloc[u8](a, capacity)
    if first_error != ok { ret (zero, first_error) }
    var buffer = first
    var filled = 0usize
    var input = source
    while true {
        if filled == capacity {
            let (bigger, bigger_error) = mem.alloc[u8](a, capacity * 2usize)
            if bigger_error != ok { ret (zero, bigger_error) }
            mem.copy[u8](bigger[..filled], buffer[..filled])
            buffer = bigger
            capacity = capacity * 2usize
        }
        let (count, read_error) = io.read(&input, buffer[filled..])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        if count == 0usize { break }
        filled += count
    }
    ret (buffer[..filled], ok)
}

fn reader(a: *mem.Arena, source: io.Reader, options: Options) -> (Reader, err) {
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let (contents, slurp_error) = slurp(a, source)
    if slurp_error != ok { ret (zero, slurp_error) }
    let (stack, stack_error) = mem.alloc[str](a, usize(options.max_depth) + 1usize)
    if stack_error != ok { ret (zero, stack_error) }
    let s = &storage[0]
    s.a = a
    s.source = contents
    s.at = 0usize
    s.options = options
    s.stack = stack
    s.depth = 0usize
    s.has_pending = false
    s.started = false
    s.finished = false
    var r: Reader = zero
    r.state = mem.cast[*void](s)
    ret (r, ok)
}

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 }

fn is_name_byte(c: u8) -> bool {
    ret str.is_ascii_alnum(c) || c == 95u8 || c == 45u8 || c == 46u8 || c == 58u8 || c >= 128u8
}

fn name_end(source: []const u8, at: usize) -> usize {
    var stop = at
    while stop < source.len && is_name_byte(source[stop]) { stop += 1usize }
    ret stop
}

fn skip_space(source: []const u8, at: usize) -> usize {
    var stop = at
    while stop < source.len && is_space(source[stop]) { stop += 1usize }
    ret stop
}

// Appends the UTF-8 of `scalar` to `out`.
fn push_scalar(out: []u8, at: usize, scalar: u32) -> usize {
    if scalar < 128u32 {
        out[at] = u8(scalar)
        ret at + 1usize
    }
    if scalar < 2048u32 {
        out[at] = u8(192u32 | (scalar >> 6u32))
        out[at + 1usize] = u8(128u32 | (scalar & 63u32))
        ret at + 2usize
    }
    if scalar < 65536u32 {
        out[at] = u8(224u32 | (scalar >> 12u32))
        out[at + 1usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
        out[at + 2usize] = u8(128u32 | (scalar & 63u32))
        ret at + 3usize
    }
    out[at] = u8(240u32 | (scalar >> 18u32))
    out[at + 1usize] = u8(128u32 | ((scalar >> 12u32) & 63u32))
    out[at + 2usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
    out[at + 3usize] = u8(128u32 | (scalar & 63u32))
    ret at + 4usize
}

// Decodes the references in `raw`; borrowed back when it holds none.
fn decode(a: *mem.Arena, raw: []const u8) -> (str, err) {
    let (amp, has_amp) = str.find(raw, "&")
    if !has_amp { ret (raw, ok) }
    let (out, out_error) = mem.alloc[u8](a, raw.len)
    if out_error != ok { ret ("", out_error) }
    var at = 0usize
    var used = 0usize
    while at < raw.len {
        if raw[at] != 38u8 {
            out[used] = raw[at]
            used += 1usize
            at += 1usize
            continue
        }
        let (semi, has_semi) = str.find_from(raw, ";", at)
        if !has_semi { ret ("", Invalid) }
        let name = raw[at + 1usize..semi]
        if str.eq(name, "lt") {
            out[used] = 60u8
            used += 1usize
        } else {
        if str.eq(name, "gt") {
            out[used] = 62u8
            used += 1usize
        } else {
        if str.eq(name, "amp") {
            out[used] = 38u8
            used += 1usize
        } else {
        if str.eq(name, "apos") {
            out[used] = 39u8
            used += 1usize
        } else {
        if str.eq(name, "quot") {
            out[used] = 34u8
            used += 1usize
        } else {
        if name.len > 1usize && name[0] == 35u8 {
            var scalar = 0u64
            var parse_error = ok
            if name[1] == 120u8 {
                let (hex, hex_error) = str.parse_u64_radix(name[2usize..], 16u8)
                scalar = hex
                parse_error = hex_error
            } else {
                let (dec, dec_error) = str.parse_u64(name[1usize..])
                scalar = dec
                parse_error = dec_error
            }
            if parse_error != ok || scalar > 1114111u64 || scalar == 0u64 || (scalar >= 55296u64 && scalar <= 57343u64) { ret ("", Invalid) }
            used = push_scalar(out, used, u32(scalar))
        } else {
            ret ("", Unsupported)
        }
        }
        }
        }
        }
        }
        at = semi + 1usize
    }
    ret (out[..used], ok)
}

fn reader_next_err(r: *Reader) -> (Event, bool, err) {
    let s = mem.cast[*State](r.state)
    if s.has_pending {
        s.has_pending = false
        ret (Event{ End: s.pending_end }, true, ok)
    }
    while true {
        if s.at >= s.source.len {
            if s.depth != 0usize { ret (zero, false, Invalid) }
            if !s.started { ret (zero, false, Invalid) }
            ret (zero, false, ok)
        }
        let source = s.source
        if source[s.at] != 60u8 {
            // Character data up to the next tag.
            let (lt, has_lt) = str.find_from(source, "<", s.at)
            var stop = source.len
            if has_lt { stop = lt }
            let raw = source[s.at..stop]
            s.at = stop
            if s.depth == 0usize {
                if str.trim(raw).len != 0usize { ret (zero, false, Invalid) }
                continue
            }
            let (decoded, decode_error) = decode(s.a, raw)
            if decode_error != ok { ret (zero, false, decode_error) }
            ret (Event{ Text: decoded }, true, ok)
        }
        if str.starts_with(source[s.at..], "<!--") {
            let (close, has_close) = str.find_from(source, "-->", s.at + 4usize)
            if !has_close { ret (zero, false, Invalid) }
            let body = source[s.at + 4usize..close]
            s.at = close + 3usize
            if s.options.preserve_comments { ret (Event{ Comment: body }, true, ok) }
            continue
        }
        if str.starts_with(source[s.at..], "<![CDATA[") {
            if s.depth == 0usize { ret (zero, false, Invalid) }
            let (close, has_close) = str.find_from(source, "]]>", s.at + 9usize)
            if !has_close { ret (zero, false, Invalid) }
            let body = source[s.at + 9usize..close]
            s.at = close + 3usize
            ret (Event{ Text: body }, true, ok)
        }
        if str.starts_with(source[s.at..], "<!") { ret (zero, false, Unsupported) }
        if str.starts_with(source[s.at..], "<?") {
            let (close, has_close) = str.find_from(source, "?>", s.at + 2usize)
            if !has_close { ret (zero, false, Invalid) }
            let target_end = name_end(source, s.at + 2usize)
            if target_end == s.at + 2usize { ret (zero, false, Invalid) }
            let target_name = source[s.at + 2usize..target_end]
            let data = str.trim(source[target_end..close])
            s.at = close + 2usize
            if str.eq(target_name, "xml") { continue }
            ret (Event{ Processing: Processing { target: target_name, data: data } }, true, ok)
        }
        if str.starts_with(source[s.at..], "</") {
            let stop = name_end(source, s.at + 2usize)
            let name = source[s.at + 2usize..stop]
            let close = skip_space(source, stop)
            if name.len == 0usize || close >= source.len || source[close] != 62u8 { ret (zero, false, Invalid) }
            if s.depth == 0usize || !str.eq(s.stack[s.depth - 1usize], name) { ret (zero, false, Invalid) }
            s.depth -= 1usize
            s.at = close + 1usize
            ret (Event{ End: name }, true, ok)
        }
        // A start tag.
        let stop = name_end(source, s.at + 1usize)
        let name = source[s.at + 1usize..stop]
        if name.len == 0usize { ret (zero, false, Invalid) }
        if s.started && s.depth == 0usize { ret (zero, false, Invalid) }
        var at = stop
        var count = 0usize
        // Count the attributes, then fill them.
        var probe = at
        while true {
            probe = skip_space(source, probe)
            if probe >= source.len { ret (zero, false, Invalid) }
            if source[probe] == 62u8 || source[probe] == 47u8 { break }
            let attribute_end = name_end(source, probe)
            if attribute_end == probe { ret (zero, false, Invalid) }
            var eq = skip_space(source, attribute_end)
            if eq >= source.len || source[eq] != 61u8 { ret (zero, false, Invalid) }
            eq = skip_space(source, eq + 1usize)
            if eq >= source.len || (source[eq] != 34u8 && source[eq] != 39u8) { ret (zero, false, Invalid) }
            let quote = source[eq]
            var value_end = eq + 1usize
            while value_end < source.len && source[value_end] != quote && source[value_end] != 60u8 { value_end += 1usize }
            if value_end >= source.len || source[value_end] != quote { ret (zero, false, Invalid) }
            count += 1usize
            probe = value_end + 1usize
        }
        let (attributes, attributes_error) = mem.alloc[Attribute](s.a, count)
        if attributes_error != ok { ret (zero, false, attributes_error) }
        var index = 0usize
        while index < count {
            at = skip_space(source, at)
            let attribute_end = name_end(source, at)
            var eq = skip_space(source, attribute_end)
            eq = skip_space(source, eq + 1usize)
            let quote = source[eq]
            var value_end = eq + 1usize
            while source[value_end] != quote { value_end += 1usize }
            let (value, value_error) = decode(s.a, source[eq + 1usize..value_end])
            if value_error != ok { ret (zero, false, value_error) }
            attributes[index].name = source[at..attribute_end]
            attributes[index].value = value
            var j = 0usize
            while j < index {
                if str.eq(attributes[j].name, attributes[index].name) { ret (zero, false, Invalid) }
                j += 1usize
            }
            index += 1usize
            at = value_end + 1usize
        }
        at = skip_space(source, at)
        var empty = false
        if source[at] == 47u8 {
            empty = true
            at += 1usize
            if at >= source.len || source[at] != 62u8 { ret (zero, false, Invalid) }
        }
        s.at = at + 1usize
        s.started = true
        if empty {
            s.pending_end = name
            s.has_pending = true
        } else {
            if s.depth >= usize(s.options.max_depth) { ret (zero, false, TooDeep) }
            s.stack[s.depth] = name
            s.depth += 1usize
        }
        ret (Event{ Start: StartElement { name: name, attributes: attributes, empty: empty } }, true, ok)
    }
}

fn writer(sink: io.Writer) -> Writer {
    ret Writer { sink: sink, depth: 0u16 }
}

fn write_escaped(sink: *io.Writer, value: str, in_attribute: bool) -> err {
    var at = 0usize
    var from = 0usize
    while at < value.len {
        let c = value[at]
        var replacement = ""
        if c == 60u8 { replacement = "&lt;" }
        if c == 62u8 { replacement = "&gt;" }
        if c == 38u8 { replacement = "&amp;" }
        if in_attribute && c == 34u8 { replacement = "&quot;" }
        if replacement.len > 0usize {
            try io.write_all(sink, value[from..at])
            try io.write_all(sink, replacement)
            from = at + 1usize
        }
        at += 1usize
    }
    ret io.write_all(sink, value[from..])
}

fn start(w: *Writer, name: str, attributes: []const Attribute) -> err {
    if name.len == 0usize { ret Invalid }
    try io.write_all(&w.sink, "<")
    try io.write_all(&w.sink, name)
    var i = 0usize
    while i < attributes.len {
        try io.write_all(&w.sink, " ")
        try io.write_all(&w.sink, attributes[i].name)
        try io.write_all(&w.sink, "=\"")
        try write_escaped(&w.sink, attributes[i].value, true)
        try io.write_all(&w.sink, "\"")
        i += 1usize
    }
    try io.write_all(&w.sink, ">")
    if w.depth == 65535u16 { ret TooDeep }
    w.depth += 1u16
    ret ok
}

fn text(w: *Writer, value: str) -> err {
    ret write_escaped(&w.sink, value, false)
}

fn comment(w: *Writer, value: str) -> err {
    if str.contains(value, "--") { ret Invalid }
    try io.write_all(&w.sink, "<!--")
    try io.write_all(&w.sink, value)
    ret io.write_all(&w.sink, "-->")
}

fn end(w: *Writer, name: str) -> err {
    if w.depth == 0u16 { ret Invalid }
    try io.write_all(&w.sink, "</")
    try io.write_all(&w.sink, name)
    try io.write_all(&w.sink, ">")
    w.depth -= 1u16
    ret ok
}

// --- The planned names: `stream` (the pull reader over bytes), `parse` (a DOM in an
// arena-owned node table linked like `e.fmt.html`), `namespaces` (XML Namespaces 1.0
// through a scope stack) and `xpath` (an XPath 1.0 subset over the tree).

type NodeId = u32
const NONE: NodeId = 4294967295u32
type NodeKind = enum u8 { Document, Element, Text, Comment, Processing }
type Node = struct { kind: NodeKind, name: str, value: str, attributes: []const Attribute, parent: NodeId, first_child: NodeId, last_child: NodeId, next_sibling: NodeId }
type Document = struct { nodes: []const Node, root: NodeId }

// A pull reader straight over `source`, no `io.Reader` in between.
fn stream(a: *mem.Arena, source: []const u8, options: Options) -> (Reader, err) {
    let (storage, storage_error) = mem.alloc[State](a, 1usize)
    if storage_error != ok { ret (zero, storage_error) }
    let (stack, stack_error) = mem.alloc[str](a, usize(options.max_depth) + 1usize)
    if stack_error != ok { ret (zero, stack_error) }
    let s = &storage[0]
    s.a = a
    s.source = source
    s.at = 0usize
    s.options = options
    s.stack = stack
    s.depth = 0usize
    s.has_pending = false
    s.started = false
    s.finished = false
    var r: Reader = zero
    r.state = mem.cast[*void](s)
    ret (r, ok)
}

// The next event; `false` at the end of a well-formed document.
fn stream_next(r: *Reader) -> (Event, bool, err) {
    let (event, more, next_error) = reader_next_err(r)
    ret (event, more, next_error)
}

fn add_node(nodes: []Node, used: *usize, kind: NodeKind, name: str, value: str, attributes: []const Attribute, parent: NodeId) -> NodeId {
    let id = u32(*used)
    nodes[*used] = Node { kind: kind, name: name, value: value, attributes: attributes, parent: parent, first_child: NONE, last_child: NONE, next_sibling: NONE }
    *used += 1usize
    if parent != NONE {
        let last = nodes[usize(parent)].last_child
        if last == NONE { nodes[usize(parent)].first_child = id } else { nodes[usize(last)].next_sibling = id }
        nodes[usize(parent)].last_child = id
    }
    ret id
}

// The whole document as a tree: node 0 is the document, `root` its element;
// comments and processing instructions are kept, text nodes hold decoded data.
// Nesting past 256 is `TooDeep`; a DOCTYPE stays `Unsupported` (no entity expansion,
// no external references -- the XXE-safe reading is the only one there is).
fn parse(a: *mem.Arena, source: []const u8) -> (Document, err) {
    // Every `<` opens at most one node and at most one text node precedes it.
    let bound = str.count(source, "<") * 2usize + 2usize
    let (nodes, nodes_error) = mem.alloc[Node](a, bound)
    if nodes_error != ok { ret (zero, nodes_error) }
    let (r0, r_error) = stream(a, source, Options { max_depth: 256u16, preserve_comments: true })
    if r_error != ok { ret (zero, r_error) }
    var r = r0
    var used = 0usize
    var current = add_node(nodes, &used, .Document, "", "", zero, NONE)
    var root = NONE
    while true {
        let (event, more, next_error) = reader_next_err(&r)
        if next_error != ok { ret (zero, next_error) }
        if !more { break }
        switch event {
        case .Start as element:
            let id = add_node(nodes, &used, .Element, element.name, "", element.attributes, current)
            if root == NONE { root = id }
            current = id
        case .End as name:
            current = nodes[usize(current)].parent
        case .Text as data:
            let _ = add_node(nodes, &used, .Text, "", data, zero, current)
        case .Comment as body:
            let _ = add_node(nodes, &used, .Comment, "", body, zero, current)
        case .Processing as pi:
            let _ = add_node(nodes, &used, .Processing, pi.target, pi.data, zero, current)
        }
    }
    ret (Document { nodes: nodes[..used], root: root }, ok)
}

fn attribute(element: *const Node, name: str) -> (str, bool) {
    var i = 0usize
    while i < element.attributes.len {
        if str.eq(element.attributes[i].name, name) { ret (element.attributes[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

// --- Namespaces: a stack of (prefix, uri) bindings with a mark per open element.

type Namespaces = struct { prefixes: []str, uris: []str, count: usize, marks: []usize, depth: usize }

fn namespaces(a: *mem.Arena, max_bindings: usize, max_depth: usize) -> (Namespaces, err) {
    let (prefixes, p_error) = mem.alloc[str](a, max_bindings)
    if p_error != ok { ret (zero, p_error) }
    let (uris, u_error) = mem.alloc[str](a, max_bindings)
    if u_error != ok { ret (zero, u_error) }
    let (marks, m_error) = mem.alloc[usize](a, max_depth)
    if m_error != ok { ret (zero, m_error) }
    ret (Namespaces { prefixes: prefixes, uris: uris, count: 0usize, marks: marks, depth: 0usize }, ok)
}

// Enters an element: its `xmlns` and `xmlns:p` attributes bind until the matching
// `namespaces_pop`. `xmlns:p=""` is `Invalid` (Namespaces 1.0 has no undeclaration
// of a prefix); `xmlns=""` undeclares the default namespace.
fn namespaces_push(ns: *Namespaces, attributes: []const Attribute) -> err {
    if ns.depth >= ns.marks.len { ret TooDeep }
    ns.marks[ns.depth] = ns.count
    ns.depth += 1usize
    var i = 0usize
    while i < attributes.len {
        let name = attributes[i].name
        var prefix = ""
        var declares = false
        if str.eq(name, "xmlns") { declares = true }
        if str.starts_with(name, "xmlns:") {
            prefix = name[6usize..]
            declares = true
            if attributes[i].value.len == 0usize || str.eq(prefix, "xmlns") { ret Invalid }
        }
        if declares {
            if ns.count >= ns.prefixes.len { ret TooDeep }
            ns.prefixes[ns.count] = prefix
            ns.uris[ns.count] = attributes[i].value
            ns.count += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn namespaces_pop(ns: *Namespaces) -> err {
    if ns.depth == 0usize { ret Invalid }
    ns.depth -= 1usize
    ns.count = ns.marks[ns.depth]
    ret ok
}

// The URI a prefix is bound to in the current scope; "" for an element with no
// default namespace; `Invalid` for an undeclared prefix. `xml` is always bound.
fn resolve(ns: *const Namespaces, prefix: str) -> (str, err) {
    var i = ns.count
    while i > 0usize {
        i -= 1usize
        if str.eq(ns.prefixes[i], prefix) { ret (ns.uris[i], ok) }
    }
    if prefix.len == 0usize { ret ("", ok) }
    if str.eq(prefix, "xml") { ret ("http://www.w3.org/XML/1998/namespace", ok) }
    ret ("", Invalid)
}

// A qualified name as its expanded (uri, local) pair.
fn expand(ns: *const Namespaces, name: str) -> (str, str, err) {
    let (colon, has_colon) = str.find(name, ":")
    var prefix = ""
    var local = name
    if has_colon {
        prefix = name[..colon]
        local = name[colon + 1usize..]
        if prefix.len == 0usize || local.len == 0usize { ret ("", "", Invalid) }
    }
    let (uri, uri_error) = resolve(ns, prefix)
    if uri_error != ok { ret ("", "", uri_error) }
    ret (uri, local, ok)
}

// --- XPath: `/a/b`, `//b`, `*`, `.`, `..`, `text()`, `@attr` (the elements carrying
// it), `child::` and `descendant-or-self::node()` spelled out, and the predicates
// `[n]`, `[@a]`, `[@a='v']`, `[name]`, `[name='text']`, in document order without
// duplicates.
//
// ponytail: node sets are arrays the size of the tree and the duplicate check is a
// scan, so a path of nested `//` steps is quadratic; no `or`/`and`, `last()`,
// functions or other axes.

type PathSet = struct { ids: []NodeId, count: usize }

fn set_add(set: *PathSet, id: NodeId) {
    var i = 0usize
    while i < set.count {
        if set.ids[i] == id { ret }
        i += 1usize
    }
    set.ids[set.count] = id
    set.count += 1usize
}

// The pre-order successor of `cursor` inside the subtree of `root`, NONE at the end.
fn next_in_subtree(document: *const Document, root: NodeId, cursor: NodeId) -> NodeId {
    if document.nodes[usize(cursor)].first_child != NONE { ret document.nodes[usize(cursor)].first_child }
    var c = cursor
    while c != root {
        let sibling = document.nodes[usize(c)].next_sibling
        if sibling != NONE { ret sibling }
        c = document.nodes[usize(c)].parent
    }
    ret NONE
}

// Whether the text of `id` and its descendants, in order, spells `want`.
fn text_equals(document: *const Document, id: NodeId, want: str) -> bool {
    var matched = 0usize
    var cursor = id
    while cursor != NONE {
        let n = &document.nodes[usize(cursor)]
        if n.kind == .Text {
            if matched + n.value.len > want.len || !str.eq(want[matched..matched + n.value.len], n.value) { ret false }
            matched += n.value.len
        }
        cursor = next_in_subtree(document, id, cursor)
    }
    ret matched == want.len
}

fn predicate_holds(document: *const Document, id: NodeId, predicate: str, position: usize) -> (bool, err) {
    let body = str.trim(predicate)
    if body.len == 0usize { ret (false, Invalid) }
    if str.is_ascii_digit(body[0]) {
        let (n, n_error) = str.parse_u64(body)
        if n_error != ok { ret (false, Invalid) }
        ret (u64(position) == n, ok)
    }
    let (eq, has_eq) = str.find(body, "=")
    var name = body
    var want = ""
    var compares = false
    if has_eq {
        name = str.trim(body[..eq])
        let quoted = str.trim(body[eq + 1usize..])
        if quoted.len < 2usize || (quoted[0] != 39u8 && quoted[0] != 34u8) || quoted[quoted.len - 1usize] != quoted[0] { ret (false, Invalid) }
        want = quoted[1usize..quoted.len - 1usize]
        compares = true
    }
    let node = &document.nodes[usize(id)]
    if name.len > 0usize && name[0] == 64u8 {
        let (value, has_value) = attribute(node, name[1usize..])
        if !has_value { ret (false, ok) }
        ret (!compares || str.eq(value, want), ok)
    }
    var child = node.first_child
    while child != NONE {
        let c = &document.nodes[usize(child)]
        if c.kind == .Element && str.eq(c.name, name) {
            if !compares || text_equals(document, child, want) { ret (true, ok) }
        }
        child = c.next_sibling
    }
    ret (false, ok)
}

fn push_id(set: *PathSet, id: NodeId) {
    set.ids[set.count] = id
    set.count += 1usize
}

// One step from every node of `from` into `into`.
fn path_step(document: *const Document, from: *const PathSet, into: *PathSet, scratch: *PathSet, step: str) -> err {
    var test = step
    var predicates = ""
    let (bracket, has_bracket) = str.find(step, "[")
    if has_bracket {
        test = step[..bracket]
        predicates = step[bracket..]
    }
    if str.starts_with(test, "child::") { test = test[7usize..] }
    if test.len == 0usize { ret Invalid }
    into.count = 0usize
    var i = 0usize
    while i < from.count {
        let context = from.ids[i]
        let node = &document.nodes[usize(context)]
        scratch.count = 0usize
        if str.eq(test, ".") { push_id(scratch, context) } else {
        if str.eq(test, "..") {
            if node.parent != NONE { push_id(scratch, node.parent) }
        } else {
        if str.eq(test, "descendant-or-self::node()") {
            var cursor = context
            while cursor != NONE {
                push_id(scratch, cursor)
                cursor = next_in_subtree(document, context, cursor)
            }
        } else {
        if test[0] == 64u8 {
            let (_, has_value) = attribute(node, test[1usize..])
            if has_value { push_id(scratch, context) }
        } else {
            var child = node.first_child
            while child != NONE {
                let c = &document.nodes[usize(child)]
                var taken = false
                if str.eq(test, "text()") { taken = c.kind == .Text } else {
                if str.eq(test, "*") { taken = c.kind == .Element } else {
                    taken = c.kind == .Element && str.eq(c.name, test)
                }
                }
                if taken { push_id(scratch, child) }
                child = c.next_sibling
            }
        }
        }
        }
        }
        // Each predicate in turn filters the candidates, positions counted per pass.
        var rest = predicates
        while rest.len > 0usize {
            if rest[0] != 91u8 { ret Invalid }
            let (close, has_close) = str.find(rest, "]")
            if !has_close { ret Invalid }
            let predicate = rest[1usize..close]
            rest = rest[close + 1usize..]
            var kept = 0usize
            var k = 0usize
            while k < scratch.count {
                let (holds, holds_error) = predicate_holds(document, scratch.ids[k], predicate, k + 1usize)
                if holds_error != ok { ret holds_error }
                if holds {
                    scratch.ids[kept] = scratch.ids[k]
                    kept += 1usize
                }
                k += 1usize
            }
            scratch.count = kept
        }
        var k = 0usize
        while k < scratch.count {
            set_add(into, scratch.ids[k])
            k += 1usize
        }
        i += 1usize
    }
    ret ok
}

// The nodes `path` selects from `context` (the document node for an absolute path).
fn xpath(a: *mem.Arena, document: *const Document, context: NodeId, path: str) -> ([]NodeId, err) {
    let size = document.nodes.len + 1usize
    let (ids_a, a_error) = mem.alloc[NodeId](a, size)
    if a_error != ok { ret (zero, a_error) }
    let (ids_b, b_error) = mem.alloc[NodeId](a, size)
    if b_error != ok { ret (zero, b_error) }
    let (ids_c, c_error) = mem.alloc[NodeId](a, size)
    if c_error != ok { ret (zero, c_error) }
    var from = PathSet { ids: ids_a, count: 1usize }
    var into = PathSet { ids: ids_b, count: 0usize }
    var scratch = PathSet { ids: ids_c, count: 0usize }
    var rest = str.trim(path)
    if rest.len == 0usize { ret (zero, Invalid) }
    from.ids[0] = context
    if rest[0] == 47u8 {
        from.ids[0] = 0u32
        rest = rest[1usize..]
        if rest.len == 0usize { ret (from.ids[..1], ok) }
    }
    while true {
        var step = rest
        var more = false
        if rest.len > 0usize && rest[0] == 47u8 {
            // `//`: descendant-or-self, then the step that follows.
            step = "descendant-or-self::node()"
            rest = rest[1usize..]
            more = true
        } else {
            let (slash, has_slash) = str.find(rest, "/")
            if has_slash {
                step = rest[..slash]
                rest = rest[slash + 1usize..]
                more = true
            }
        }
        let step_error = path_step(document, &from, &into, &scratch, step)
        if step_error != ok { ret (zero, step_error) }
        let swap = from
        from = into
        into = swap
        if !more { break }
        if rest.len == 0usize { ret (zero, Invalid) }
    }
    ret (from.ids[..from.count], ok)
}
