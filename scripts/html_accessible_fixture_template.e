// `e.fmt.html.accessible` against Vaper's own accessibility tree builder (accessibility_builder.dart):
// scripts/html_accessible_vectors.mjs writes random HTML documents with the canonical JSON of Vaper's tree for the
// `<body>` subtree (`e`); the fixture parses the document with `e.fmt.html`, builds the same tree and compares the
// canonical text.
use e.algo.chain as chain
use e.algo.ir as ir
use e.data.list as list
use e.fmt.html as html
use e.fmt.html.accessible as acc
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str

fn text_field(v: json.Value, key: str) -> str {
    let (x, found) = ir.get(v, key)
    if !found { ret "" }
    let (s, is_text) = ir.string_of(x)
    if !is_text { ret "" }
    ret s
}

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

fn obj(a: *mem.Arena) -> ir.Obj {
    let (o, e) = ir.new_obj(a)
    if e != ok { os.exit(81i32) }
    ret o
}

fn put(o: *ir.Obj, key: str, v: json.Value) {
    let e = ir.put(o, key, v)
}

fn int_value(a: *mem.Arena, n: i64) -> json.Value {
    let (v, e) = json.number_from_i64(a, n)
    if e != ok { os.exit(82i32) }
    ret json.Value{ Number: v }
}

fn real_value(a: *mem.Arena, x: f64) -> json.Value {
    let (v, e) = json.number_from_f64(a, x)
    if e != ok { os.exit(83i32) }
    ret json.Value{ Number: v }
}

fn encode(a: *mem.Arena, n: acc.Node) -> json.Value {
    var o = obj(a)
    put(&o, "r", json.Value{ String: acc.role_name(n.role) })
    put(&o, "i", int_value(a, n.node_id))
    if n.name.len > 0usize { put(&o, "n", json.Value{ String: n.name }) }
    if n.has_value { put(&o, "v", json.Value{ String: n.value }) }
    if n.has_level { put(&o, "l", int_value(a, n.level)) }
    if n.has_checked { put(&o, "c", json.Value{ Bool: n.checked }) }
    if n.checked_mixed { put(&o, "cm", json.Value{ Bool: true }) }
    if n.disabled { put(&o, "d", json.Value{ Bool: true }) }
    if n.has_expanded { put(&o, "x", json.Value{ Bool: n.expanded }) }
    if n.has_selected { put(&o, "s", json.Value{ Bool: n.selected }) }
    if n.required { put(&o, "q", json.Value{ Bool: true }) }
    if n.invalid { put(&o, "iv", json.Value{ Bool: true }) }
    if n.has_now { put(&o, "vn", real_value(a, n.now)) }
    if n.has_min { put(&o, "vmin", real_value(a, n.min)) }
    if n.has_max { put(&o, "vmax", real_value(a, n.max)) }
    if n.has_url { put(&o, "u", json.Value{ String: n.url }) }
    if n.focusable { put(&o, "f", json.Value{ Bool: true }) }
    let (kids, ke) = mem.alloc[json.Value](a, n.children.len + 1usize)
    if ke != ok { os.exit(84i32) }
    var at = 0usize
    while at < n.children.len {
        kids[at] = encode(a, n.children[at])
        at += 1usize
    }
    put(&o, "k", json.Value{ Array: kids[0usize..n.children.len] })
    ret ir.obj_value(&o)
}

// The `<body>` element: the html element's child named body.
fn find_body(doc: *const html.Document) -> html.NodeId {
    var top = doc.nodes[usize(doc.root)].first_child
    while top != html.NONE {
        if doc.nodes[usize(top)].kind == .Element {
            var c = doc.nodes[usize(top)].first_child
            while c != html.NONE {
                if doc.nodes[usize(c)].kind == .Element && str.eq(doc.nodes[usize(c)].name, "body") { ret c }
                c = doc.nodes[usize(c)].next_sibling
            }
        }
        top = doc.nodes[usize(top)].next_sibling
    }
    ret html.NONE
}

fn run_one(a: *mem.Arena, root: json.Value) -> bool {
    let options = html.Options { max_bytes: 4194304usize, max_nodes: 100000usize, max_attributes: 64usize, max_depth: 256u16, preserve_comments: true }
    let (doc, de) = html.parse(a, text_field(root, "html"), options)
    if de != ok { os.exit(85i32) }
    let body = find_body(&doc)
    if body == html.NONE { ret false }
    let tree = acc.build_tree(a, &doc, body)
    let (text, ce) = chain.canonical_json(a, encode(a, tree))
    if ce != ok { os.exit(86i32) }
    let want = text_field(root, "e")
    if !str.eq(text, want) {
        let shown = io.print(join(a, join(a, "got ", text), "\n"))
        ret false
    }
    ret true
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 60u16 })
            if parse_error != ok || !run_one(a, root) {
                let shown = io.print(join(a, "want ", line))
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("html accessible ok")
    ret ok
}
