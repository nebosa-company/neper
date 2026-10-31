# e.fmt.graph — 1 of 71 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/fmt/graph.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/fmt/graph.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.hash` | source | `lib/e/algo/hash.e` | 2 |
| `e.data.graph` | source | `lib/e/data/graph.e` | 2 |
| `e.data.list` | source | `lib/e/data/list.e` | 2 |
| `e.fmt.xml` | partial | `lib/e/fmt/xml.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
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

fn local(name: str) -> str
fn attr_of(node: *const xml.Node, name: str) -> (str, bool)
fn kind_from_name(name: str) -> AttrKind
fn graphml_type(kind: AttrKind) -> str
fn gexf_type(kind: AttrKind) -> str
fn element_text(a: *mem.Arena, doc: *const xml.Document, id: usize) -> (str, err)
fn is_element(doc: *const xml.Document, id: usize, name: str) -> bool

type Reader = struct { a: *mem.Arena, graphs: list.List[Graph], keys: []Key, key_count: usize }

fn blank_graph() -> Graph
fn find_key(r: *const Reader, id: str, domain: str) -> (usize, bool)
fn has_attr(attrs: []const Attr, name: str) -> bool
fn validate(a: *mem.Arena, d: Document) -> err
fn graphml_data(r: *Reader, doc: *const xml.Document, element: usize, domain: str, into: *list.List[Attr]) -> err
fn graphml_graph(r: *Reader, doc: *const xml.Document, element: usize, depth: usize) -> (u32, err)
fn try_list_attr(a: *mem.Arena) -> list.List[Attr]
fn try_list_node(a: *mem.Arena) -> list.List[Node]
fn try_list_edge(a: *mem.Arena) -> list.List[Edge]
fn new_reader(a: *mem.Arena, nodes: usize) -> (Reader, err)
fn read_graphml(a: *mem.Arena, source: str) -> (Document, err)

type Def = struct { class: str, id: str, title: str, kind: AttrKind }

fn gexf_values(a: *mem.Arena, doc: *const xml.Document, element: usize, defs: []const Def, count: usize, class: str, into: *list.List[Attr]) -> err
fn gexf_nodes(r: *Reader, doc: *const xml.Document, container: usize, defs: []const Def, count: usize, directed: bool, depth: usize, into: *list.List[Node]) -> err
fn read_gexf(a: *mem.Arena, source: str) -> (Document, err)

type Item = struct { key: str, text: str, is_list: bool, is_string: bool, first: u32, next: u32 }
type GmlParser = struct { a: *mem.Arena, source: str, at: usize, items: []Item, used: usize }

fn gml_skip(p: *GmlParser)
fn is_key_byte(c: u8) -> bool
fn gml_unescape(a: *mem.Arena, raw: str) -> (str, err)
fn gml_list(p: *GmlParser, top: bool, depth: usize) -> (u32, err)
fn gml_kind_of(item: Item) -> AttrKind
fn gml_graph(r: *Reader, p: *GmlParser, first: u32, depth: usize, names: []str, name_count: *usize, name_ids: []str) -> (u32, err)
fn read_gml(a: *mem.Arena, source: str) -> (Document, err)
fn push_escaped(b: *str.Builder, s: str, attribute: bool) -> err
fn xml_clean(s: str) -> bool
fn check_names(d: Document) -> err

type OutKey = struct { domain: str, name: str, kind: AttrKind }

fn out_key_index(keys: []const OutKey, count: usize, domain: str, name: str, kind: AttrKind) -> (usize, bool)
fn add_out_keys(keys: []OutKey, count: *usize, domain: str, attrs: []const Attr)
fn graphml_data_out(b: *str.Builder, keys: []const OutKey, count: usize, domain: str, attrs: []const Attr) -> err
fn graphml_graph_out(b: *str.Builder, d: Document, index: usize, keys: []const OutKey, count: usize, depth: usize) -> err
fn count_attrs(d: Document) -> usize
fn write_graphml(a: *mem.Arena, d: Document) -> (str, err)
fn attr_value(attrs: []const Attr, name: str) -> (str, bool)
fn write_gexf(a: *mem.Arena, d: Document) -> (str, err)
fn gexf_edge_values(b: *str.Builder, keys: []const OutKey, ids: []const usize, count: usize, attrs: []const Attr) -> err
fn gexf_nodes_out(b: *str.Builder, d: Document, index: usize, keys: []const OutKey, ids: []const usize, count: usize, depth: usize) -> err
fn push_gml_string(b: *str.Builder, s: str) -> err
fn push_gml_value(b: *str.Builder, a: Attr) -> err
fn gml_key_ok(name: str) -> bool
fn push_spaces(b: *str.Builder, n: usize) -> err
fn gml_attrs(b: *str.Builder, attrs: []const Attr, spaces: usize, skip_label: bool) -> err
fn node_index(g: Graph, name: str) -> u32
fn gml_base(d: Document, index: usize) -> u32
fn gml_graph_out(b: *str.Builder, d: Document, index: usize, spaces: usize, depth: usize) -> err
fn write_gml(a: *mem.Arena, d: Document) -> (str, err)
fn to_csr(a: *mem.Arena, d: Document, index: usize) -> (graph.Graph[f64], err)
```

Graph interchange (L155): GraphML, GEXF and GML read and written over one model, and `to_csr` into `e.data.graph`. A `Document` is a list of `Graph`s, the first the root and the rest nested ones, each `Node` naming its subgraph by index (`NONE` for none); nodes and edges carry string identifiers and typed `Attr`s (name, `AttrKind` of String, Boolean, Int, Long, Float or Double, text), which is what round-trips: GraphML `key`/`data` with key defaults on read, GEXF `attributes`/`attvalues` with `label`, `weight` and the graph `name`, and the scalar key-value pairs of GML. `read_graphml`, `read_gexf` and `read_gml` take text and return the document (`Malformed`, `Dangling` for an edge naming no node or a duplicate id found by `validate`, `Unsupported` for hyperedges and ports, `TooLarge`); `write_graphml`, `write_gexf` and `write_gml` write it (`BadName` for a key GML cannot spell or a control character, `Unsupported` for edges in a GEXF hierarchy subgraph). GraphML keeps nested graphs in nodes and per-edge `directed`; GEXF keeps hierarchy as `nodes` nested in a node and a per-edge `type`; GML keeps a `graph` list nested in a node, writes a node's `id` as its index over all graphs and its identifier as `label` (the NetworkX and Gephi convention, so a node attribute called `label` is not written) and non-ASCII text as `&#N;`. `to_csr(a, d, i)` builds graph `i` as `e.data.graph.Graph[f64]` with node `n` the graph's n-th node and the `weight` attribute (default 1) as the edge value, an undirected edge becoming two directed ones. Not here: hypergraphs, ports, GEXF dynamics and viz data, layout and style, and a typed GML beyond integer, real and string. Checked on files written by NetworkX (types and values derived from the NetworkX graph), the GraphML primer's nested example, a GEXF hierarchy and a GML nested graph, and on writers compared byte for byte with independent ones that NetworkX read back (`scripts/gen_graph_test.py`).

## Missing declarations

- [ ] `gml_base`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/fmt/arrow.e`
- `lib/e/fmt/asn1.e`
- `lib/e/fmt/avro.e`
- `lib/e/fmt/bincode.e`
- `lib/e/fmt/bmp.e`
- `lib/e/fmt/brotli.e`‡
- `lib/e/fmt/bson.e`
- `lib/e/fmt/bzip2.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/fmt/graph.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/fmt_graph/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 1.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
