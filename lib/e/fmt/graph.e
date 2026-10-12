// Graph interchange formats (L155): GraphML, GEXF and GML read and written over one model,
// and `to_csr` to take any graph of it into `e.data.graph`.
//
// The model keeps what the three formats share: a `Document` is a list of `Graph`s, the
// first the root and the rest nested ones, each node naming its subgraph (if it has one) by
// index. A node and an edge carry string identifiers and typed attributes (`Attr`: name,
// kind, text), which is what makes attributes round-trip: GraphML `key`/`data`, GEXF
// `attributes`/`attvalues` and the loose key-value pairs of GML all land in the same list.
// A GEXF label and weight are attributes called `label` and `weight`; so is a GML `label`
// and `weight`.
//
// What each format keeps:
//   GraphML  graphs nested in nodes, per-edge `directed`, key defaults on read, graph/node/
//            edge data of boolean, int, long, float, double and string kind. Hyperedges and
//            ports are `Unsupported`.
//   GEXF     defaultedgetype and per-edge type, node and edge attributes, `label`, `weight`,
//            hierarchy (nodes nested in a node become its subgraph; edges stay in the root).
//            Dynamics (spells, slices) and viz extensions are ignored.
//   GML      `directed`, nodes and edges with scalar keys, a `graph` list nested in a node.
//            On write a node's `id` is its index and its `label` its identifier, which is the
//            convention NetworkX and Gephi read; a node attribute called `label` is therefore
//            not written. Non-ASCII text is written as `&#N;` and read back.
//
// Not here: hypergraphs and hyperedges, ports, GEXF dynamics, GML's nested non-graph lists
// (read as no attribute), and any layout or style data.
//
// Memory: every result lives in the arena passed in.
use e.mem
use e.str
use e.algo.hash as hash
use e.data.list as list
use e.data.graph as graph
use e.fmt.xml as xml

error Malformed
error Dangling
error Unsupported
error TooLarge
error BadName

type AttrKind = enum u8 { String, Boolean, Int, Long, Float, Double }
type Attr = struct { name: str, kind: AttrKind, value: str }
type Node = struct { id: str, attrs: []const Attr, subgraph: u32 }
type Edge = struct { id: str, source: str, target: str, directed: bool, attrs: []const Attr }
type Graph = struct { id: str, directed: bool, nodes: []const Node, edges: []const Edge, attrs: []const Attr }
type Document = struct { graphs: []const Graph }

const NONE: u32 = 4294967295u32
const MAX_GRAPHS: usize = 65536usize
const MAX_DEPTH: usize = 64usize

type Key = struct { id: str, domain: str, name: str, kind: AttrKind, default_value: str, has_default: bool }

// ---- common helpers ----------------------------------------------------------------------

fn local(name: str) -> str {
    var i = name.len
    while i > 0usize {
        if name[i - 1usize] == 58u8 { ret name[i..name.len] }
        i -= 1usize
    }
    ret name
}

fn attr_of(node: *const xml.Node, name: str) -> (str, bool) {
    var i = 0usize
    while i < node.attributes.len {
        if str.eq(node.attributes[i].name, name) { ret (node.attributes[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

fn kind_from_name(name: str) -> AttrKind {
    if str.eq(name, "boolean") { ret .Boolean }
    if str.eq(name, "int") || str.eq(name, "integer") { ret .Int }
    if str.eq(name, "long") { ret .Long }
    if str.eq(name, "float") { ret .Float }
    if str.eq(name, "double") { ret .Double }
    ret .String
}

fn graphml_type(kind: AttrKind) -> str {
    if kind == .Boolean { ret "boolean" }
    if kind == .Int { ret "int" }
    if kind == .Long { ret "long" }
    if kind == .Float { ret "float" }
    if kind == .Double { ret "double" }
    ret "string"
}

fn gexf_type(kind: AttrKind) -> str {
    if kind == .Int { ret "integer" }
    ret graphml_type(kind)
}

fn element_text(a: *mem.Arena, doc: *const xml.Document, id: usize) -> (str, err) {
    var text = ""
    var child = doc.nodes[id].first_child
    var first = true
    while usize(child) < doc.nodes.len {
        if doc.nodes[usize(child)].kind == .Text {
            if first {
                text = doc.nodes[usize(child)].value
                first = false
            } else {
                let (joined, joined_error) = str.concat(a, text, doc.nodes[usize(child)].value)
                if joined_error != ok { ret ("", joined_error) }
                text = joined
            }
        }
        child = doc.nodes[usize(child)].next_sibling
    }
    ret (text, ok)
}

fn is_element(doc: *const xml.Document, id: usize, name: str) -> bool {
    ret doc.nodes[id].kind == .Element && str.eq(local(doc.nodes[id].name), name)
}

// ---- reading state -----------------------------------------------------------------------

type Reader = struct { a: *mem.Arena, graphs: list.List[Graph], keys: []Key, key_count: usize }

fn blank_graph() -> Graph {
    ret Graph { id: "", directed: false, nodes: zero, edges: zero, attrs: zero }
}

fn find_key(r: *const Reader, id: str, domain: str) -> (usize, bool) {
    var i = 0usize
    while i < r.key_count {
        if str.eq(r.keys[i].id, id) && (str.eq(r.keys[i].domain, domain) || str.eq(r.keys[i].domain, "all")) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn has_attr(attrs: []const Attr, name: str) -> bool {
    var i = 0usize
    while i < attrs.len {
        if str.eq(attrs[i].name, name) { ret true }
        i += 1usize
    }
    ret false
}

// Every node id of every graph is defined once, and every edge names two of them.
fn validate(a: *mem.Arena, d: Document) -> err {
    var total = 0usize
    var g = 0usize
    while g < d.graphs.len {
        total += d.graphs[g].nodes.len
        g += 1usize
    }
    var slots = 16usize
    while slots < total * 2usize { slots *= 2usize }
    let (table, table_error) = mem.alloc[u32](a, slots)
    if table_error != ok { ret table_error }
    let (names, names_error) = mem.alloc[str](a, total + 1usize)
    if names_error != ok { ret names_error }
    var i = 0usize
    while i < slots {
        table[i] = NONE
        i += 1usize
    }
    var count = 0usize
    let mask = u32(slots - 1usize)
    g = 0usize
    while g < d.graphs.len {
        var n = 0usize
        while n < d.graphs[g].nodes.len {
            let id = d.graphs[g].nodes[n].id
            var at = hash.fnv1a32(id) & mask
            while table[usize(at)] != NONE {
                if str.eq(names[usize(table[usize(at)])], id) { ret Malformed }
                at = (at + 1u32) & mask
            }
            table[usize(at)] = u32(count)
            names[count] = id
            count += 1usize
            n += 1usize
        }
        g += 1usize
    }
    g = 0usize
    while g < d.graphs.len {
        var e = 0usize
        while e < d.graphs[g].edges.len {
            var side = 0usize
            while side < 2usize {
                var endpoint = d.graphs[g].edges[e].source
                if side == 1usize { endpoint = d.graphs[g].edges[e].target }
                var at = hash.fnv1a32(endpoint) & mask
                var found = false
                while table[usize(at)] != NONE {
                    if str.eq(names[usize(table[usize(at)])], endpoint) {
                        found = true
                        break
                    }
                    at = (at + 1u32) & mask
                }
                if !found { ret Dangling }
                side += 1usize
            }
            e += 1usize
        }
        g += 1usize
    }
    ret ok
}

// ---- GraphML read ------------------------------------------------------------------------

fn graphml_data(r: *Reader, doc: *const xml.Document, element: usize, domain: str, into: *list.List[Attr]) -> err {
    var child = doc.nodes[element].first_child
    while usize(child) < doc.nodes.len {
        let c = usize(child)
        if is_element(doc, c, "data") {
            let (key_id, has_key) = attr_of(&doc.nodes[c], "key")
            if !has_key { ret Malformed }
            let (index, found) = find_key(r, key_id, domain)
            if !found { ret Malformed }
            let (text, text_error) = element_text(r.a, doc, c)
            if text_error != ok { ret text_error }
            try list.push[Attr](into, Attr { name: r.keys[index].name, kind: r.keys[index].kind, value: text })
        }
        child = doc.nodes[c].next_sibling
    }
    // Defaults the element did not override.
    var k = 0usize
    while k < r.key_count {
        let key = r.keys[k]
        if key.has_default && (str.eq(key.domain, domain) || str.eq(key.domain, "all")) {
            var present = false
            var i = 0usize
            while i < into.len {
                if str.eq(into.items[i].name, key.name) { present = true }
                i += 1usize
            }
            if !present { try list.push[Attr](into, Attr { name: key.name, kind: key.kind, value: key.default_value }) }
        }
        k += 1usize
    }
    ret ok
}

fn graphml_graph(r: *Reader, doc: *const xml.Document, element: usize, depth: usize) -> (u32, err) {
    if depth > MAX_DEPTH || r.graphs.len >= MAX_GRAPHS { ret (NONE, TooLarge) }
    var g = blank_graph()
    let (gid, has_gid) = attr_of(&doc.nodes[element], "id")
    if has_gid { g.id = gid }
    let (edge_default, has_default) = attr_of(&doc.nodes[element], "edgedefault")
    g.directed = has_default && str.eq(edge_default, "directed")
    let index = u32(r.graphs.len)
    try list.push[Graph](&r.graphs, g)
    var nodes_l = try_list_node(r.a)
    var edges_l = try_list_edge(r.a)
    var attrs_l = try_list_attr(r.a)
    var child = doc.nodes[element].first_child
    while usize(child) < doc.nodes.len {
        let c = usize(child)
        if is_element(doc, c, "node") {
            let (id, has_id) = attr_of(&doc.nodes[c], "id")
            if !has_id { ret (NONE, Malformed) }
            var node_attrs = try_list_attr(r.a)
            try graphml_data(r, doc, c, "node", &node_attrs)
            var sub = NONE
            var inner = doc.nodes[c].first_child
            while usize(inner) < doc.nodes.len {
                if is_element(doc, usize(inner), "graph") {
                    let (s, s_error) = graphml_graph(r, doc, usize(inner), depth + 1usize)
                    if s_error != ok { ret (NONE, s_error) }
                    sub = s
                }
                inner = doc.nodes[usize(inner)].next_sibling
            }
            try list.push[Node](&nodes_l, Node { id: id, attrs: list.slice_const[Attr](&node_attrs), subgraph: sub })
        } else if is_element(doc, c, "edge") {
            let (source_id, has_source) = attr_of(&doc.nodes[c], "source")
            let (target_id, has_target) = attr_of(&doc.nodes[c], "target")
            if !has_source || !has_target { ret (NONE, Malformed) }
            let (eid, has_eid) = attr_of(&doc.nodes[c], "id")
            var directed = g.directed
            let (dir_text, has_dir) = attr_of(&doc.nodes[c], "directed")
            if has_dir { directed = str.eq(dir_text, "true") }
            var edge_attrs = try_list_attr(r.a)
            try graphml_data(r, doc, c, "edge", &edge_attrs)
            var id = ""
            if has_eid { id = eid }
            try list.push[Edge](&edges_l, Edge { id: id, source: source_id, target: target_id, directed: directed, attrs: list.slice_const[Attr](&edge_attrs) })
        } else if is_element(doc, c, "hyperedge") || is_element(doc, c, "port") {
            ret (NONE, Unsupported)
        }
        child = doc.nodes[c].next_sibling
    }
    try graphml_data(r, doc, element, "graph", &attrs_l)
    g.nodes = list.slice_const[Node](&nodes_l)
    g.edges = list.slice_const[Edge](&edges_l)
    g.attrs = list.slice_const[Attr](&attrs_l)
    r.graphs.items[usize(index)] = g
    ret (index, ok)
}

fn try_list_attr(a: *mem.Arena) -> list.List[Attr] {
    let (l, e) = list.init[Attr](a, 4usize)
    ret l
}

fn try_list_node(a: *mem.Arena) -> list.List[Node] {
    let (l, e) = list.init[Node](a, 8usize)
    ret l
}

fn try_list_edge(a: *mem.Arena) -> list.List[Edge] {
    let (l, e) = list.init[Edge](a, 8usize)
    ret l
}

fn new_reader(a: *mem.Arena, nodes: usize) -> (Reader, err) {
    var r: Reader = zero
    r.a = a
    let (graphs, graphs_error) = list.init[Graph](a, 4usize)
    if graphs_error != ok { ret (zero, graphs_error) }
    r.graphs = graphs
    let (keys, keys_error) = mem.alloc[Key](a, nodes + 1usize)
    if keys_error != ok { ret (zero, keys_error) }
    r.keys = keys
    r.key_count = 0usize
    ret (r, ok)
}

fn read_graphml(a: *mem.Arena, source: str) -> (Document, err) {
    let (doc, parse_error) = xml.parse(a, source)
    if parse_error != ok { ret (zero, Malformed) }
    if usize(doc.root) >= doc.nodes.len || !is_element(&doc, usize(doc.root), "graphml") { ret (zero, Malformed) }
    var (r, r_error) = new_reader(a, doc.nodes.len)
    if r_error != ok { ret (zero, r_error) }
    var i = 0usize
    while i < doc.nodes.len {
        if is_element(&doc, i, "key") {
            let (id, has_id) = attr_of(&doc.nodes[i], "id")
            if !has_id { ret (zero, Malformed) }
            var domain = "all"
            let (for_text, has_for) = attr_of(&doc.nodes[i], "for")
            if has_for { domain = for_text }
            var name = id
            let (name_text, has_name) = attr_of(&doc.nodes[i], "attr.name")
            if has_name { name = name_text }
            var kind: AttrKind = .String
            let (type_text, has_type) = attr_of(&doc.nodes[i], "attr.type")
            if has_type { kind = kind_from_name(type_text) }
            var key = Key { id: id, domain: domain, name: name, kind: kind, default_value: "", has_default: false }
            var inner = doc.nodes[i].first_child
            while usize(inner) < doc.nodes.len {
                if is_element(&doc, usize(inner), "default") {
                    let (text, text_error) = element_text(a, &doc, usize(inner))
                    if text_error != ok { ret (zero, text_error) }
                    key.default_value = text
                    key.has_default = true
                }
                inner = doc.nodes[usize(inner)].next_sibling
            }
            r.keys[r.key_count] = key
            r.key_count += 1usize
        }
        i += 1usize
    }
    var first_graph = NONE
    var child = doc.nodes[usize(doc.root)].first_child
    while usize(child) < doc.nodes.len {
        if is_element(&doc, usize(child), "graph") && first_graph == NONE { first_graph = child }
        child = doc.nodes[usize(child)].next_sibling
    }
    if first_graph == NONE { ret (zero, Malformed) }
    let (root_index, graph_error) = graphml_graph(&r, &doc, usize(first_graph), 0usize)
    if graph_error != ok { ret (zero, graph_error) }
    let result = Document { graphs: list.slice_const[Graph](&r.graphs) }
    let check_error = validate(a, result)
    if check_error != ok { ret (zero, check_error) }
    ret (result, ok)
}

// ---- GEXF read ---------------------------------------------------------------------------

type Def = struct { class: str, id: str, title: str, kind: AttrKind }

fn gexf_values(a: *mem.Arena, doc: *const xml.Document, element: usize, defs: []const Def, count: usize, class: str, into: *list.List[Attr]) -> err {
    var child = doc.nodes[element].first_child
    while usize(child) < doc.nodes.len {
        let c = usize(child)
        if is_element(doc, c, "attvalues") {
            var v = doc.nodes[c].first_child
            while usize(v) < doc.nodes.len {
                if is_element(doc, usize(v), "attvalue") {
                    let (for_id, has_for) = attr_of(&doc.nodes[usize(v)], "for")
                    let (value, has_value) = attr_of(&doc.nodes[usize(v)], "value")
                    if has_for && has_value {
                        var matched = -1i64
                        var k = 0usize
                        while k < count {
                            if str.eq(defs[k].class, class) && str.eq(defs[k].id, for_id) { matched = i64(k) }
                            k += 1usize
                        }
                        if matched >= 0i64 {
                            let def = defs[usize(matched)]
                            try list.push[Attr](into, Attr { name: def.title, kind: def.kind, value: value })
                        } else {
                            try list.push[Attr](into, Attr { name: for_id, kind: .String, value: value })
                        }
                    }
                }
                v = doc.nodes[usize(v)].next_sibling
            }
        }
        child = doc.nodes[c].next_sibling
    }
    ret ok
}

fn gexf_nodes(r: *Reader, doc: *const xml.Document, container: usize, defs: []const Def, count: usize, directed: bool, depth: usize, into: *list.List[Node]) -> err {
    if depth > MAX_DEPTH { ret TooLarge }
    var child = doc.nodes[container].first_child
    while usize(child) < doc.nodes.len {
        let c = usize(child)
        if is_element(doc, c, "node") {
            let (id, has_id) = attr_of(&doc.nodes[c], "id")
            if !has_id { ret Malformed }
            var attrs = try_list_attr(r.a)
            let (label, has_label) = attr_of(&doc.nodes[c], "label")
            if has_label { try list.push[Attr](&attrs, Attr { name: "label", kind: .String, value: label }) }
            try gexf_values(r.a, doc, c, defs, count, "node", &attrs)
            var sub = NONE
            var inner = doc.nodes[c].first_child
            while usize(inner) < doc.nodes.len {
                if is_element(doc, usize(inner), "nodes") {
                    if r.graphs.len >= MAX_GRAPHS { ret TooLarge }
                    var g = blank_graph()
                    g.id = id
                    g.directed = directed
                    let slot = u32(r.graphs.len)
                    try list.push[Graph](&r.graphs, g)
                    var sub_nodes = try_list_node(r.a)
                    try gexf_nodes(r, doc, usize(inner), defs, count, directed, depth + 1usize, &sub_nodes)
                    g.nodes = list.slice_const[Node](&sub_nodes)
                    r.graphs.items[usize(slot)] = g
                    sub = slot
                }
                inner = doc.nodes[usize(inner)].next_sibling
            }
            try list.push[Node](into, Node { id: id, attrs: list.slice_const[Attr](&attrs), subgraph: sub })
        }
        child = doc.nodes[c].next_sibling
    }
    ret ok
}

fn read_gexf(a: *mem.Arena, source: str) -> (Document, err) {
    let (doc, parse_error) = xml.parse(a, source)
    if parse_error != ok { ret (zero, Malformed) }
    if usize(doc.root) >= doc.nodes.len || !is_element(&doc, usize(doc.root), "gexf") { ret (zero, Malformed) }
    var graph_element = NONE
    var child = doc.nodes[usize(doc.root)].first_child
    while usize(child) < doc.nodes.len {
        if is_element(&doc, usize(child), "graph") && graph_element == NONE { graph_element = child }
        child = doc.nodes[usize(child)].next_sibling
    }
    if graph_element == NONE { ret (zero, Malformed) }
    let ge = usize(graph_element)
    var directed = false
    let (edge_type, has_type) = attr_of(&doc.nodes[ge], "defaultedgetype")
    if has_type { directed = str.eq(edge_type, "directed") }
    // Attribute definitions.
    let (defs, defs_error) = mem.alloc[Def](a, doc.nodes.len + 1usize)
    if defs_error != ok { ret (zero, defs_error) }
    var def_count = 0usize
    var i = 0usize
    while i < doc.nodes.len {
        if is_element(&doc, i, "attributes") {
            var class = "node"
            let (class_text, has_class) = attr_of(&doc.nodes[i], "class")
            if has_class { class = class_text }
            var inner = doc.nodes[i].first_child
            while usize(inner) < doc.nodes.len {
                if is_element(&doc, usize(inner), "attribute") {
                    let (id, has_id) = attr_of(&doc.nodes[usize(inner)], "id")
                    let (title, has_title) = attr_of(&doc.nodes[usize(inner)], "title")
                    let (type_text, has_attr_type) = attr_of(&doc.nodes[usize(inner)], "type")
                    if !has_id { ret (zero, Malformed) }
                    var name = id
                    if has_title { name = title }
                    var kind: AttrKind = .String
                    if has_attr_type { kind = kind_from_name(type_text) }
                    defs[def_count] = Def { class: class, id: id, title: name, kind: kind }
                    def_count += 1usize
                }
                inner = doc.nodes[usize(inner)].next_sibling
            }
        }
        i += 1usize
    }
    var (r, r_error) = new_reader(a, 0usize)
    if r_error != ok { ret (zero, r_error) }
    var root = blank_graph()
    let (graph_id, has_graph_id) = attr_of(&doc.nodes[ge], "id")
    if has_graph_id { root.id = graph_id }
    root.directed = directed
    var root_attrs = try_list_attr(a)
    let (graph_name, has_graph_name) = attr_of(&doc.nodes[ge], "name")
    if has_graph_name { try list.push[Attr](&root_attrs, Attr { name: "name", kind: .String, value: graph_name }) }
    root.attrs = list.slice_const[Attr](&root_attrs)
    try list.push[Graph](&r.graphs, root)
    var nodes_l = try_list_node(a)
    var edges_l = try_list_edge(a)
    child = doc.nodes[ge].first_child
    while usize(child) < doc.nodes.len {
        let c = usize(child)
        if is_element(&doc, c, "nodes") {
            try gexf_nodes(&r, &doc, c, defs, def_count, directed, 0usize, &nodes_l)
        } else if is_element(&doc, c, "edges") {
            var e = doc.nodes[c].first_child
            var ordinal = 0usize
            while usize(e) < doc.nodes.len {
                let ec = usize(e)
                if is_element(&doc, ec, "edge") {
                    let (source_id, has_source) = attr_of(&doc.nodes[ec], "source")
                    let (target_id, has_target) = attr_of(&doc.nodes[ec], "target")
                    if !has_source || !has_target { ret (zero, Malformed) }
                    var edge_directed = directed
                    let (kind_text, has_kind) = attr_of(&doc.nodes[ec], "type")
                    if has_kind { edge_directed = str.eq(kind_text, "directed") }
                    var attrs = try_list_attr(a)
                    let (label, has_label) = attr_of(&doc.nodes[ec], "label")
                    if has_label { try list.push[Attr](&attrs, Attr { name: "label", kind: .String, value: label }) }
                    let (weight, has_weight) = attr_of(&doc.nodes[ec], "weight")
                    if has_weight { try list.push[Attr](&attrs, Attr { name: "weight", kind: .Double, value: weight }) }
                    try gexf_values(a, &doc, ec, defs, def_count, "edge", &attrs)
                    let (eid, has_eid) = attr_of(&doc.nodes[ec], "id")
                    var id = ""
                    if has_eid { id = eid }
                    try list.push[Edge](&edges_l, Edge { id: id, source: source_id, target: target_id, directed: edge_directed, attrs: list.slice_const[Attr](&attrs) })
                    ordinal += 1usize
                }
                e = doc.nodes[ec].next_sibling
            }
        }
        child = doc.nodes[c].next_sibling
    }
    root.nodes = list.slice_const[Node](&nodes_l)
    root.edges = list.slice_const[Edge](&edges_l)
    r.graphs.items[0usize] = root
    let result = Document { graphs: list.slice_const[Graph](&r.graphs) }
    let check_error = validate(a, result)
    if check_error != ok { ret (zero, check_error) }
    ret (result, ok)
}

// ---- GML read ----------------------------------------------------------------------------

// One `key value` pair of a GML list; a list value has `first` set to its first pair.
type Item = struct { key: str, text: str, is_list: bool, is_string: bool, first: u32, next: u32 }

type GmlParser = struct { a: *mem.Arena, source: str, at: usize, items: []Item, used: usize }

fn gml_skip(p: *GmlParser) {
    while p.at < p.source.len {
        let c = p.source[p.at]
        if c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 {
            p.at += 1usize
        } else if c == 35u8 {
            while p.at < p.source.len && p.source[p.at] != 10u8 { p.at += 1usize }
        } else {
            break
        }
    }
}

fn is_key_byte(c: u8) -> bool {
    ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) || c == 95u8
}

// Decode `&amp; &lt; &gt; &quot; &apos; &#N;` in a quoted string.
fn gml_unescape(a: *mem.Arena, raw: str) -> (str, err) {
    let (amp, has_amp) = str.find(raw, "&")
    if !has_amp { ret (raw, ok) }
    let (out, out_error) = mem.alloc[u8](a, raw.len + 1usize)
    if out_error != ok { ret ("", out_error) }
    var used = 0usize
    var i = 0usize
    while i < raw.len {
        if raw[i] == 38u8 {
            let (semi, has_semi) = str.find_from(raw, ";", i + 1usize)
            if has_semi && semi - i <= 8usize {
                let name = raw[i + 1usize..semi]
                var code = 0u32
                var known = true
                if str.eq(name, "amp") {
                    code = 38u32
                } else if str.eq(name, "lt") {
                    code = 60u32
                } else if str.eq(name, "gt") {
                    code = 62u32
                } else if str.eq(name, "quot") {
                    code = 34u32
                } else if str.eq(name, "apos") {
                    code = 39u32
                } else if name.len > 1usize && name[0usize] == 35u8 {
                    var k = 1usize
                    while k < name.len && name[k] >= 48u8 && name[k] <= 57u8 {
                        code = code * 10u32 + u32(name[k] - 48u8)
                        k += 1usize
                    }
                    if k != name.len || code == 0u32 || code > 1114111u32 { known = false }
                } else {
                    known = false
                }
                if known {
                    // Up to four UTF-8 bytes; the output is never longer than the entity.
                    if code < 128u32 {
                        out[used] = u8(code)
                        used += 1usize
                    } else if code < 2048u32 {
                        out[used] = u8(192u32 | (code >> 6u32))
                        out[used + 1usize] = u8(128u32 | (code & 63u32))
                        used += 2usize
                    } else if code < 65536u32 {
                        out[used] = u8(224u32 | (code >> 12u32))
                        out[used + 1usize] = u8(128u32 | ((code >> 6u32) & 63u32))
                        out[used + 2usize] = u8(128u32 | (code & 63u32))
                        used += 3usize
                    } else {
                        out[used] = u8(240u32 | (code >> 18u32))
                        out[used + 1usize] = u8(128u32 | ((code >> 12u32) & 63u32))
                        out[used + 2usize] = u8(128u32 | ((code >> 6u32) & 63u32))
                        out[used + 3usize] = u8(128u32 | (code & 63u32))
                        used += 4usize
                    }
                    i = semi + 1usize
                    continue
                }
            }
        }
        out[used] = raw[i]
        used += 1usize
        i += 1usize
    }
    ret (out[0usize..used], ok)
}

// Parses pairs until `]` (or the end when `top`), chaining them; the index of the first.
fn gml_list(p: *GmlParser, top: bool, depth: usize) -> (u32, err) {
    if depth > MAX_DEPTH { ret (NONE, TooLarge) }
    var first = NONE
    var last = NONE
    while true {
        gml_skip(p)
        if p.at >= p.source.len {
            if top { break }
            ret (NONE, Malformed)
        }
        if p.source[p.at] == 93u8 {
            if top { ret (NONE, Malformed) }
            p.at += 1usize
            break
        }
        let key_start = p.at
        while p.at < p.source.len && is_key_byte(p.source[p.at]) { p.at += 1usize }
        if p.at == key_start { ret (NONE, Malformed) }
        let key = p.source[key_start..p.at]
        gml_skip(p)
        if p.at >= p.source.len { ret (NONE, Malformed) }
        if p.used >= p.items.len { ret (NONE, TooLarge) }
        let slot = p.used
        p.used += 1usize
        var item = Item { key: key, text: "", is_list: false, is_string: false, first: NONE, next: NONE }
        let c = p.source[p.at]
        if c == 91u8 {
            p.at += 1usize
            let (inner, inner_error) = gml_list(p, false, depth + 1usize)
            if inner_error != ok { ret (NONE, inner_error) }
            item.is_list = true
            item.first = inner
        } else if c == 34u8 {
            let start = p.at + 1usize
            var end = start
            while end < p.source.len && p.source[end] != 34u8 { end += 1usize }
            if end >= p.source.len { ret (NONE, Malformed) }
            let (decoded, decode_error) = gml_unescape(p.a, p.source[start..end])
            if decode_error != ok { ret (NONE, decode_error) }
            item.text = decoded
            item.is_string = true
            p.at = end + 1usize
        } else {
            let start = p.at
            while p.at < p.source.len && !(p.source[p.at] == 32u8 || p.source[p.at] == 9u8 || p.source[p.at] == 10u8 || p.source[p.at] == 13u8 || p.source[p.at] == 93u8) { p.at += 1usize }
            if p.at == start { ret (NONE, Malformed) }
            item.text = p.source[start..p.at]
        }
        p.items[slot] = item
        if first == NONE { first = u32(slot) } else { p.items[usize(last)].next = u32(slot) }
        last = u32(slot)
    }
    ret (first, ok)
}

fn gml_kind_of(item: Item) -> AttrKind {
    if item.is_string { ret .String }
    var i = 0usize
    var digits = 0usize
    var real = false
    if item.text.len > 0usize && (item.text[0usize] == 45u8 || item.text[0usize] == 43u8) { i = 1usize }
    while i < item.text.len {
        let c = item.text[i]
        if c >= 48u8 && c <= 57u8 {
            digits += 1usize
        } else if c == 46u8 || c == 101u8 || c == 69u8 || c == 45u8 || c == 43u8 {
            real = true
        } else {
            ret .String
        }
        i += 1usize
    }
    if digits == 0usize { ret .String }
    if real { ret .Double }
    ret .Int
}

// Interprets the graph list starting at pair `first`; returns its index in the reader.
fn gml_graph(r: *Reader, p: *GmlParser, first: u32, depth: usize, names: []str, name_count: *usize, name_ids: []str) -> (u32, err) {
    if depth > MAX_DEPTH || r.graphs.len >= MAX_GRAPHS { ret (NONE, TooLarge) }
    var g = blank_graph()
    let index = u32(r.graphs.len)
    try list.push[Graph](&r.graphs, g)
    var nodes_l = try_list_node(r.a)
    var edges_l = try_list_edge(r.a)
    var attrs_l = try_list_attr(r.a)
    var it = first
    while it != NONE {
        let item = p.items[usize(it)]
        if str.eq(item.key, "directed") && !item.is_list {
            g.directed = str.eq(item.text, "1")
        } else if str.eq(item.key, "node") && item.is_list {
            var id = ""
            var label = ""
            var has_label = false
            var attrs = try_list_attr(r.a)
            var sub = NONE
            var field = item.first
            // First pass: id and label, which name the node.
            while field != NONE {
                let f = p.items[usize(field)]
                if str.eq(f.key, "id") && !f.is_list { id = f.text }
                if str.eq(f.key, "label") && !f.is_list {
                    label = f.text
                    has_label = true
                }
                field = f.next
            }
            if id.len == 0usize && !has_label { ret (NONE, Malformed) }
            var name = id
            if has_label { name = label }
            field = item.first
            while field != NONE {
                let f = p.items[usize(field)]
                if f.is_list && str.eq(f.key, "graph") {
                    let (s, s_error) = gml_graph(r, p, f.first, depth + 1usize, names, name_count, name_ids)
                    if s_error != ok { ret (NONE, s_error) }
                    sub = s
                } else if !f.is_list && !str.eq(f.key, "id") && !str.eq(f.key, "label") {
                    try list.push[Attr](&attrs, Attr { name: f.key, kind: gml_kind_of(f), value: f.text })
                }
                field = f.next
            }
            if *name_count < names.len && id.len > 0usize {
                names[*name_count] = name
                name_ids[*name_count] = id
                *name_count = *name_count + 1usize
            }
            try list.push[Node](&nodes_l, Node { id: name, attrs: list.slice_const[Attr](&attrs), subgraph: sub })
        } else if str.eq(item.key, "edge") && item.is_list {
            var source_id = ""
            var target_id = ""
            var attrs = try_list_attr(r.a)
            var field = item.first
            while field != NONE {
                let f = p.items[usize(field)]
                if str.eq(f.key, "source") && !f.is_list {
                    source_id = f.text
                } else if str.eq(f.key, "target") && !f.is_list {
                    target_id = f.text
                } else if !f.is_list {
                    try list.push[Attr](&attrs, Attr { name: f.key, kind: gml_kind_of(f), value: f.text })
                }
                field = f.next
            }
            if source_id.len == 0usize || target_id.len == 0usize { ret (NONE, Malformed) }
            try list.push[Edge](&edges_l, Edge { id: "", source: source_id, target: target_id, directed: g.directed, attrs: list.slice_const[Attr](&attrs) })
        } else if !item.is_list {
            if str.eq(item.key, "id") || str.eq(item.key, "label") || !str.eq(item.key, "directed") {
                try list.push[Attr](&attrs_l, Attr { name: item.key, kind: gml_kind_of(item), value: item.text })
            }
        }
        it = item.next
    }
    g.nodes = list.slice_const[Node](&nodes_l)
    g.edges = list.slice_const[Edge](&edges_l)
    g.attrs = list.slice_const[Attr](&attrs_l)
    r.graphs.items[usize(index)] = g
    ret (index, ok)
}

fn read_gml(a: *mem.Arena, source: str) -> (Document, err) {
    var bound = source.len / 2usize + 8usize
    let (items, items_error) = mem.alloc[Item](a, bound)
    if items_error != ok { ret (zero, items_error) }
    var p = GmlParser { a: a, source: source, at: 0usize, items: items, used: 0usize }
    let (top, top_error) = gml_list(&p, true, 0usize)
    if top_error != ok { ret (zero, top_error) }
    var graph_item = NONE
    var it = top
    while it != NONE {
        if str.eq(p.items[usize(it)].key, "graph") && p.items[usize(it)].is_list && graph_item == NONE { graph_item = it }
        it = p.items[usize(it)].next
    }
    if graph_item == NONE { ret (zero, Malformed) }
    var (r, r_error) = new_reader(a, 0usize)
    if r_error != ok { ret (zero, r_error) }
    let (names, names_error) = mem.alloc[str](a, p.used + 1usize)
    if names_error != ok { ret (zero, names_error) }
    let (name_ids, ids_error) = mem.alloc[str](a, p.used + 1usize)
    if ids_error != ok { ret (zero, ids_error) }
    var name_count = 0usize
    let (index, graph_error) = gml_graph(&r, &p, p.items[usize(graph_item)].first, 0usize, names, &name_count, name_ids)
    if graph_error != ok { ret (zero, graph_error) }
    // Edges name nodes by `id`; the model names them by label-or-id, so map each endpoint.
    var g = 0usize
    while g < r.graphs.len {
        var e = 0usize
        var edges = r.graphs.items[g].edges
        let (rewritten, rewritten_error) = mem.alloc[Edge](a, edges.len + 1usize)
        if rewritten_error != ok { ret (zero, rewritten_error) }
        while e < edges.len {
            var edge = edges[e]
            var k = 0usize
            while k < name_count {
                if str.eq(name_ids[k], edge.source) {
                    edge.source = names[k]
                    break
                }
                k += 1usize
            }
            k = 0usize
            while k < name_count {
                if str.eq(name_ids[k], edge.target) {
                    edge.target = names[k]
                    break
                }
                k += 1usize
            }
            rewritten[e] = edge
            e += 1usize
        }
        r.graphs.items[g].edges = rewritten[0usize..edges.len]
        g += 1usize
    }
    let result = Document { graphs: list.slice_const[Graph](&r.graphs) }
    let check_error = validate(a, result)
    if check_error != ok { ret (zero, check_error) }
    ret (result, ok)
}

// ---- writing -----------------------------------------------------------------------------

fn push_escaped(b: *str.Builder, s: str, attribute: bool) -> err {
    var i = 0usize
    var from = 0usize
    while i < s.len {
        let c = s[i]
        var rep = ""
        if c == 38u8 {
            rep = "&amp;"
        } else if c == 60u8 {
            rep = "&lt;"
        } else if c == 62u8 {
            rep = "&gt;"
        } else if attribute && c == 34u8 {
            rep = "&quot;"
        }
        if rep.len > 0usize {
            try str.push(b, s[from..i])
            try str.push(b, rep)
            from = i + 1usize
        }
        i += 1usize
    }
    ret str.push(b, s[from..s.len])
}

fn xml_clean(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c < 32u8 && c != 9u8 && c != 10u8 && c != 13u8 { ret false }
        i += 1usize
    }
    ret true
}

fn check_names(d: Document) -> err {
    if d.graphs.len == 0usize || d.graphs.len > MAX_GRAPHS { ret TooLarge }
    var g = 0usize
    while g < d.graphs.len {
        let graph_ref = d.graphs[g]
        if !xml_clean(graph_ref.id) { ret BadName }
        var n = 0usize
        while n < graph_ref.nodes.len {
            let node = graph_ref.nodes[n]
            if !xml_clean(node.id) || (node.subgraph != NONE && usize(node.subgraph) >= d.graphs.len) { ret BadName }
            var k = 0usize
            while k < node.attrs.len {
                if node.attrs[k].name.len == 0usize || !xml_clean(node.attrs[k].name) || !xml_clean(node.attrs[k].value) { ret BadName }
                k += 1usize
            }
            n += 1usize
        }
        var e = 0usize
        while e < graph_ref.edges.len {
            let edge = graph_ref.edges[e]
            if !xml_clean(edge.id) || !xml_clean(edge.source) || !xml_clean(edge.target) { ret BadName }
            var k = 0usize
            while k < edge.attrs.len {
                if edge.attrs[k].name.len == 0usize || !xml_clean(edge.attrs[k].name) || !xml_clean(edge.attrs[k].value) { ret BadName }
                k += 1usize
            }
            e += 1usize
        }
        var k = 0usize
        while k < graph_ref.attrs.len {
            if graph_ref.attrs[k].name.len == 0usize || !xml_clean(graph_ref.attrs[k].name) || !xml_clean(graph_ref.attrs[k].value) { ret BadName }
            k += 1usize
        }
        g += 1usize
    }
    ret ok
}

// ---- GraphML write -----------------------------------------------------------------------

type OutKey = struct { domain: str, name: str, kind: AttrKind }

fn out_key_index(keys: []const OutKey, count: usize, domain: str, name: str, kind: AttrKind) -> (usize, bool) {
    var i = 0usize
    while i < count {
        if str.eq(keys[i].domain, domain) && str.eq(keys[i].name, name) && keys[i].kind == kind { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn add_out_keys(keys: []OutKey, count: *usize, domain: str, attrs: []const Attr) {
    var i = 0usize
    while i < attrs.len {
        let (index, found) = out_key_index(keys, *count, domain, attrs[i].name, attrs[i].kind)
        if !found {
            keys[*count] = OutKey { domain: domain, name: attrs[i].name, kind: attrs[i].kind }
            *count = *count + 1usize
        }
        i += 1usize
    }
}

fn graphml_data_out(b: *str.Builder, keys: []const OutKey, count: usize, domain: str, attrs: []const Attr) -> err {
    var i = 0usize
    while i < attrs.len {
        let (index, found) = out_key_index(keys, count, domain, attrs[i].name, attrs[i].kind)
        try str.push(b, "<data key=\"d")
        try str.push_usize(b, index)
        try str.push(b, "\">")
        try push_escaped(b, attrs[i].value, false)
        try str.push(b, "</data>\n")
        i += 1usize
    }
    ret ok
}

fn graphml_graph_out(b: *str.Builder, d: Document, index: usize, keys: []const OutKey, count: usize, depth: usize) -> err {
    if depth > MAX_DEPTH { ret TooLarge }
    let g = d.graphs[index]
    try str.push(b, "<graph id=\"")
    try push_escaped(b, g.id, true)
    if g.directed {
        try str.push(b, "\" edgedefault=\"directed\">\n")
    } else {
        try str.push(b, "\" edgedefault=\"undirected\">\n")
    }
    try graphml_data_out(b, keys, count, "graph", g.attrs)
    var n = 0usize
    while n < g.nodes.len {
        let node = g.nodes[n]
        try str.push(b, "<node id=\"")
        try push_escaped(b, node.id, true)
        try str.push(b, "\">\n")
        try graphml_data_out(b, keys, count, "node", node.attrs)
        if node.subgraph != NONE { try graphml_graph_out(b, d, usize(node.subgraph), keys, count, depth + 1usize) }
        try str.push(b, "</node>\n")
        n += 1usize
    }
    var e = 0usize
    while e < g.edges.len {
        let edge = g.edges[e]
        try str.push(b, "<edge")
        if edge.id.len > 0usize {
            try str.push(b, " id=\"")
            try push_escaped(b, edge.id, true)
            try str.push(b, "\"")
        }
        try str.push(b, " source=\"")
        try push_escaped(b, edge.source, true)
        try str.push(b, "\" target=\"")
        try push_escaped(b, edge.target, true)
        try str.push(b, "\"")
        if edge.directed != g.directed {
            if edge.directed {
                try str.push(b, " directed=\"true\"")
            } else {
                try str.push(b, " directed=\"false\"")
            }
        }
        try str.push(b, ">\n")
        try graphml_data_out(b, keys, count, "edge", edge.attrs)
        try str.push(b, "</edge>\n")
        e += 1usize
    }
    ret str.push(b, "</graph>\n")
}

fn count_attrs(d: Document) -> usize {
    var total = 0usize
    var g = 0usize
    while g < d.graphs.len {
        total += d.graphs[g].attrs.len
        var n = 0usize
        while n < d.graphs[g].nodes.len {
            total += d.graphs[g].nodes[n].attrs.len
            n += 1usize
        }
        var e = 0usize
        while e < d.graphs[g].edges.len {
            total += d.graphs[g].edges[e].attrs.len
            e += 1usize
        }
        g += 1usize
    }
    ret total
}

fn write_graphml(a: *mem.Arena, d: Document) -> (str, err) {
    try check_names(d)
    let (keys, keys_error) = mem.alloc[OutKey](a, count_attrs(d) + 1usize)
    if keys_error != ok { ret ("", keys_error) }
    var count = 0usize
    var g = 0usize
    while g < d.graphs.len {
        add_out_keys(keys, &count, "graph", d.graphs[g].attrs)
        var n = 0usize
        while n < d.graphs[g].nodes.len {
            add_out_keys(keys, &count, "node", d.graphs[g].nodes[n].attrs)
            n += 1usize
        }
        var e = 0usize
        while e < d.graphs[g].edges.len {
            add_out_keys(keys, &count, "edge", d.graphs[g].edges[e].attrs)
            e += 1usize
        }
        g += 1usize
    }
    var (b, b_error) = str.builder(a, 0usize)
    if b_error != ok { ret ("", b_error) }
    try str.push(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\">\n")
    var k = 0usize
    while k < count {
        try str.push(&b, "<key id=\"d")
        try str.push_usize(&b, k)
        try str.push(&b, "\" for=\"")
        try str.push(&b, keys[k].domain)
        try str.push(&b, "\" attr.name=\"")
        try push_escaped(&b, keys[k].name, true)
        try str.push(&b, "\" attr.type=\"")
        try str.push(&b, graphml_type(keys[k].kind))
        try str.push(&b, "\"/>\n")
        k += 1usize
    }
    try graphml_graph_out(&b, d, 0usize, keys, count, 0usize)
    try str.push(&b, "</graphml>\n")
    ret (str.done(&b), ok)
}

// ---- GEXF write --------------------------------------------------------------------------

fn attr_value(attrs: []const Attr, name: str) -> (str, bool) {
    var i = 0usize
    while i < attrs.len {
        if str.eq(attrs[i].name, name) { ret (attrs[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

fn write_gexf(a: *mem.Arena, d: Document) -> (str, err) {
    try check_names(d)
    let (keys, keys_error) = mem.alloc[OutKey](a, count_attrs(d) + 1usize)
    if keys_error != ok { ret ("", keys_error) }
    var count = 0usize
    // Attribute definitions: node attributes of every graph (hierarchy nodes included), and
    // the root's edge attributes; `label` and `weight` are first-class and not listed.
    var g = 0usize
    while g < d.graphs.len {
        var n = 0usize
        while n < d.graphs[g].nodes.len {
            var i = 0usize
            let attrs = d.graphs[g].nodes[n].attrs
            while i < attrs.len {
                if !str.eq(attrs[i].name, "label") {
                    let (index, found) = out_key_index(keys, count, "node", attrs[i].name, attrs[i].kind)
                    if !found {
                        keys[count] = OutKey { domain: "node", name: attrs[i].name, kind: attrs[i].kind }
                        count += 1usize
                    }
                }
                i += 1usize
            }
            n += 1usize
        }
        g += 1usize
    }
    let root = d.graphs[0usize]
    var e = 0usize
    while e < root.edges.len {
        let attrs = root.edges[e].attrs
        var i = 0usize
        while i < attrs.len {
            if !str.eq(attrs[i].name, "label") && !str.eq(attrs[i].name, "weight") {
                let (index, found) = out_key_index(keys, count, "edge", attrs[i].name, attrs[i].kind)
                if !found {
                    keys[count] = OutKey { domain: "edge", name: attrs[i].name, kind: attrs[i].kind }
                    count += 1usize
                }
            }
            i += 1usize
        }
        e += 1usize
    }
    // Ids within a class are counted from zero, so give each class its own numbering.
    let (node_ids, node_ids_error) = mem.alloc[usize](a, count + 1usize)
    if node_ids_error != ok { ret ("", node_ids_error) }
    var c = 0usize
    var node_n = 0usize
    var edge_n = 0usize
    while c < count {
        if str.eq(keys[c].domain, "node") {
            node_ids[c] = node_n
            node_n += 1usize
        } else {
            node_ids[c] = edge_n
            edge_n += 1usize
        }
        c += 1usize
    }
    var (b, b_error) = str.builder(a, 0usize)
    if b_error != ok { ret ("", b_error) }
    try str.push(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gexf xmlns=\"http://gexf.net/1.3\" version=\"1.3\">\n<graph")
    if root.id.len > 0usize {
        try str.push(&b, " id=\"")
        try push_escaped(&b, root.id, true)
        try str.push(&b, "\"")
    }
    let (graph_name, has_graph_name) = attr_value(root.attrs, "name")
    if has_graph_name {
        try str.push(&b, " name=\"")
        try push_escaped(&b, graph_name, true)
        try str.push(&b, "\"")
    }
    if root.directed {
        try str.push(&b, " defaultedgetype=\"directed\" mode=\"static\">\n")
    } else {
        try str.push(&b, " defaultedgetype=\"undirected\" mode=\"static\">\n")
    }
    var class_index = 0usize
    while class_index < 2usize {
        var cls = "node"
        if class_index == 1usize { cls = "edge" }
        var listed = false
        c = 0usize
        while c < count {
            if str.eq(keys[c].domain, cls) {
                if !listed {
                    try str.push(&b, "<attributes class=\"")
                    try str.push(&b, cls)
                    try str.push(&b, "\" mode=\"static\">\n")
                    listed = true
                }
                try str.push(&b, "<attribute id=\"")
                try str.push_usize(&b, node_ids[c])
                try str.push(&b, "\" title=\"")
                try push_escaped(&b, keys[c].name, true)
                try str.push(&b, "\" type=\"")
                try str.push(&b, gexf_type(keys[c].kind))
                try str.push(&b, "\"/>\n")
            }
            c += 1usize
        }
        if listed { try str.push(&b, "</attributes>\n") }
        class_index += 1usize
    }
    try gexf_nodes_out(&b, d, 0usize, keys, node_ids, count, 0usize)
    try str.push(&b, "<edges>\n")
    e = 0usize
    while e < root.edges.len {
        let edge = root.edges[e]
        try str.push(&b, "<edge id=\"")
        if edge.id.len > 0usize {
            try push_escaped(&b, edge.id, true)
        } else {
            try str.push_usize(&b, e)
        }
        try str.push(&b, "\" source=\"")
        try push_escaped(&b, edge.source, true)
        try str.push(&b, "\" target=\"")
        try push_escaped(&b, edge.target, true)
        try str.push(&b, "\"")
        if edge.directed != root.directed {
            if edge.directed {
                try str.push(&b, " type=\"directed\"")
            } else {
                try str.push(&b, " type=\"undirected\"")
            }
        }
        let (weight, has_weight) = attr_value(edge.attrs, "weight")
        if has_weight {
            try str.push(&b, " weight=\"")
            try push_escaped(&b, weight, true)
            try str.push(&b, "\"")
        }
        let (label, has_label) = attr_value(edge.attrs, "label")
        if has_label {
            try str.push(&b, " label=\"")
            try push_escaped(&b, label, true)
            try str.push(&b, "\"")
        }
        try str.push(&b, ">")
        try gexf_edge_values(&b, keys, node_ids, count, edge.attrs)
        try str.push(&b, "</edge>\n")
        e += 1usize
    }
    try str.push(&b, "</edges>\n</graph>\n</gexf>\n")
    ret (str.done(&b), ok)
}

fn gexf_edge_values(b: *str.Builder, keys: []const OutKey, ids: []const usize, count: usize, attrs: []const Attr) -> err {
    var any = false
    var i = 0usize
    while i < attrs.len {
        if !str.eq(attrs[i].name, "label") && !str.eq(attrs[i].name, "weight") {
            if !any {
                try str.push(b, "<attvalues>")
                any = true
            }
            let (index, found) = out_key_index(keys, count, "edge", attrs[i].name, attrs[i].kind)
            try str.push(b, "<attvalue for=\"")
            try str.push_usize(b, ids[index])
            try str.push(b, "\" value=\"")
            try push_escaped(b, attrs[i].value, true)
            try str.push(b, "\"/>")
        }
        i += 1usize
    }
    if any { try str.push(b, "</attvalues>") }
    ret ok
}

fn gexf_nodes_out(b: *str.Builder, d: Document, index: usize, keys: []const OutKey, ids: []const usize, count: usize, depth: usize) -> err {
    if depth > MAX_DEPTH { ret TooLarge }
    let g = d.graphs[index]
    try str.push(b, "<nodes>\n")
    var n = 0usize
    while n < g.nodes.len {
        let node = g.nodes[n]
        try str.push(b, "<node id=\"")
        try push_escaped(b, node.id, true)
        try str.push(b, "\"")
        let (label, has_label) = attr_value(node.attrs, "label")
        if has_label {
            try str.push(b, " label=\"")
            try push_escaped(b, label, true)
            try str.push(b, "\"")
        }
        try str.push(b, ">")
        var any = false
        var i = 0usize
        while i < node.attrs.len {
            if !str.eq(node.attrs[i].name, "label") {
                if !any {
                    try str.push(b, "<attvalues>")
                    any = true
                }
                let (k, found) = out_key_index(keys, count, "node", node.attrs[i].name, node.attrs[i].kind)
                try str.push(b, "<attvalue for=\"")
                try str.push_usize(b, ids[k])
                try str.push(b, "\" value=\"")
                try push_escaped(b, node.attrs[i].value, true)
                try str.push(b, "\"/>")
            }
            i += 1usize
        }
        if any { try str.push(b, "</attvalues>") }
        if node.subgraph != NONE {
            if d.graphs[usize(node.subgraph)].edges.len > 0usize { ret Unsupported }
            try gexf_nodes_out(b, d, usize(node.subgraph), keys, ids, count, depth + 1usize)
        }
        try str.push(b, "</node>\n")
        n += 1usize
    }
    ret str.push(b, "</nodes>\n")
}

// ---- GML write ---------------------------------------------------------------------------

fn push_gml_string(b: *str.Builder, s: str) -> err {
    try str.push(b, "\"")
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 38u8 {
            try str.push(b, "&amp;")
            i += 1usize
        } else if c == 34u8 {
            try str.push(b, "&quot;")
            i += 1usize
        } else if c < 128u8 {
            try str.push_byte(b, c)
            i += 1usize
        } else {
            var code = 0u32
            var length = 1usize
            if c >= 240u8 {
                code = u32(c & 7u8)
                length = 4usize
            } else if c >= 224u8 {
                code = u32(c & 15u8)
                length = 3usize
            } else {
                code = u32(c & 31u8)
                length = 2usize
            }
            var k = 1usize
            while k < length && i + k < s.len {
                code = (code << 6u32) | u32(s[i + k] & 63u8)
                k += 1usize
            }
            try str.push(b, "&#")
            try str.push_u32(b, code)
            try str.push(b, ";")
            i += length
        }
    }
    ret str.push(b, "\"")
}

fn push_gml_value(b: *str.Builder, a: Attr) -> err {
    if a.kind == .Int || a.kind == .Long || a.kind == .Float || a.kind == .Double {
        if a.value.len > 0usize { ret str.push(b, a.value) }
    }
    if a.kind == .Boolean {
        if str.eq(a.value, "true") { ret str.push(b, "1") }
        if str.eq(a.value, "false") { ret str.push(b, "0") }
    }
    ret push_gml_string(b, a.value)
}

fn gml_key_ok(name: str) -> bool {
    if name.len == 0usize { ret false }
    var i = 0usize
    while i < name.len {
        if !is_key_byte(name[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn push_spaces(b: *str.Builder, n: usize) -> err {
    var i = 0usize
    while i < n {
        try str.push(b, " ")
        i += 1usize
    }
    ret ok
}

fn gml_attrs(b: *str.Builder, attrs: []const Attr, spaces: usize, skip_label: bool) -> err {
    var i = 0usize
    while i < attrs.len {
        let at = attrs[i]
        let skipped = skip_label && str.eq(at.name, "label")
        if !skipped {
            if !gml_key_ok(at.name) { ret BadName }
            try push_spaces(b, spaces)
            try str.push(b, at.name)
            try str.push(b, " ")
            try push_gml_value(b, at)
            try str.push(b, "\n")
        }
        i += 1usize
    }
    ret ok
}

// The index, among the graph's own nodes, of the node called `name`, or all ones.
fn node_index(g: Graph, name: str) -> u32 {
    var i = 0usize
    while i < g.nodes.len {
        if str.eq(g.nodes[i].id, name) { ret u32(i) }
        i += 1usize
    }
    ret NONE
}

// Node ids are indexes over all graphs in array order, so nested graphs never collide.
fn gml_base(d: Document, index: usize) -> u32 {
    var total = 0usize
    var i = 0usize
    while i < index {
        total += d.graphs[i].nodes.len
        i += 1usize
    }
    ret u32(total)
}

// `spaces` is the indentation of the `graph [` line; its contents sit two columns in.
fn gml_graph_out(b: *str.Builder, d: Document, index: usize, spaces: usize, depth: usize) -> err {
    if depth > MAX_DEPTH { ret TooLarge }
    let g = d.graphs[index]
    let base = gml_base(d, index)
    try push_spaces(b, spaces)
    try str.push(b, "graph [\n")
    try push_spaces(b, spaces + 2usize)
    if g.directed {
        try str.push(b, "directed 1\n")
    } else {
        try str.push(b, "directed 0\n")
    }
    var n = 0usize
    while n < g.nodes.len {
        let node = g.nodes[n]
        try push_spaces(b, spaces + 2usize)
        try str.push(b, "node [\n")
        try push_spaces(b, spaces + 4usize)
        try str.push(b, "id ")
        try str.push_u32(b, base + u32(n))
        try str.push(b, "\n")
        try push_spaces(b, spaces + 4usize)
        try str.push(b, "label ")
        try push_gml_string(b, node.id)
        try str.push(b, "\n")
        try gml_attrs(b, node.attrs, spaces + 4usize, true)
        if node.subgraph != NONE { try gml_graph_out(b, d, usize(node.subgraph), spaces + 4usize, depth + 1usize) }
        try push_spaces(b, spaces + 2usize)
        try str.push(b, "]\n")
        n += 1usize
    }
    var e = 0usize
    while e < g.edges.len {
        let edge = g.edges[e]
        let s = node_index(g, edge.source)
        let t = node_index(g, edge.target)
        if s == NONE || t == NONE { ret Dangling }
        try push_spaces(b, spaces + 2usize)
        try str.push(b, "edge [\n")
        try push_spaces(b, spaces + 4usize)
        try str.push(b, "source ")
        try str.push_u32(b, base + s)
        try str.push(b, "\n")
        try push_spaces(b, spaces + 4usize)
        try str.push(b, "target ")
        try str.push_u32(b, base + t)
        try str.push(b, "\n")
        try gml_attrs(b, edge.attrs, spaces + 4usize, false)
        try push_spaces(b, spaces + 2usize)
        try str.push(b, "]\n")
        e += 1usize
    }
    try gml_attrs(b, g.attrs, spaces + 2usize, false)
    try push_spaces(b, spaces)
    ret str.push(b, "]\n")
}

fn write_gml(a: *mem.Arena, d: Document) -> (str, err) {
    try check_names(d)
    var (b, b_error) = str.builder(a, 0usize)
    if b_error != ok { ret ("", b_error) }
    try str.push(&b, "Creator \"Neper e.fmt.graph\"\n")
    try gml_graph_out(&b, d, 0usize, 0usize, 0usize)
    ret (str.done(&b), ok)
}

// ---- into e.data.graph -------------------------------------------------------------------

// Graph `index` of `d` as a CSR graph of f64 weights (the `weight` attribute, else 1): node
// `n` is the graph's n-th node, an undirected edge is two directed ones. An edge naming a
// node outside the graph is `Dangling`.
fn to_csr(a: *mem.Arena, d: Document, index: usize) -> (graph.Graph[f64], err) {
    if index >= d.graphs.len { ret (zero, Dangling) }
    let g = d.graphs[index]
    let (b0, b_error) = graph.builder[f64](a, g.nodes.len, g.edges.len * 2usize)
    if b_error != ok { ret (zero, b_error) }
    var b = b0
    var e = 0usize
    while e < g.edges.len {
        let edge = g.edges[e]
        let s = node_index(g, edge.source)
        let t = node_index(g, edge.target)
        if s == NONE || t == NONE { ret (zero, Dangling) }
        var weight = 1.0f64
        let (text, has_weight) = attr_value(edge.attrs, "weight")
        if has_weight {
            let (parsed, parse_error) = str.parse_f64(text)
            if parse_error == ok { weight = parsed }
        }
        if edge.directed {
            let add_error = graph.add_directed[f64](&b, s, t, weight)
            if add_error != ok { ret (zero, add_error) }
        } else {
            let add_error = graph.add_undirected[f64](&b, s, t, weight)
            if add_error != ok { ret (zero, add_error) }
        }
        e += 1usize
    }
    let (result, finish_error) = graph.finish[f64](a, &b)
    ret (result, finish_error)
}
