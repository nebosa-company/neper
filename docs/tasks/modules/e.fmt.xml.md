# e.fmt.xml — 1 of 54 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/fmt/xml.e` |
| plan row | layer 6, surface `partial`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/fmt/xml.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Interchange formats:** `e.fmt.uri`, `e.fmt.mime`, `e.fmt.asn1`, `e.fmt.pem`, `e.fmt.multipart`, `e.fmt.mail`, `e.fmt.quoted_printable`, `e.fmt.gzip`, `e.fmt.zstd`, `e.fmt.bzip2`, `e.fmt.lzw`, `e.fmt.zlib`, `e.fmt.zip`, `e.fmt.tar`, `e.fmt.yaml`, `e.fmt.xml`, `e.fmt.html`, `e.fmt.png`, `e.fmt.jpeg`, `e.fmt.webp`, `e.fmt.bson`, `e.fmt.msgpack` and `e.fmt.protobuf`, plus `e.text.template` and its context-safe `e.fmt.html.template` specialization. These consume caller-provided slices/readers and writers, never open resources themselves, and require malformed, streaming, bounds and round-trip corpora in addition to API equality. `e.fmt.html` additionally runs the pinned html5lib tokenizer and tree-construction fixtures for the WHATWG behavior frozen by that toolchain release.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.io` | source | `lib/e/io.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Attribute = struct { name: str, value: str }
type Event = union enum u8 { Start: StartElement, End: str, Text: str, Comment: str, Processing: Processing }
type StartElement = struct { name: str, attributes: []const Attribute, empty: bool }
type Processing = struct { target: str, data: str }
type Reader = struct { state: *void }
type Writer = struct { sink: io.Writer, depth: u16 }
type Options = struct { max_depth: u16, preserve_comments: bool }
type State = struct { a: *mem.Arena, source: []const u8, at: usize, options: Options, stack: []str, depth: usize, pending_end: str, has_pending: bool, started: bool, finished: bool }
type NodeId = u32
type NodeKind = enum u8 { Document, Element, Text, Comment, Processing }
type Node = struct { kind: NodeKind, name: str, value: str, attributes: []const Attribute, parent: NodeId, first_child: NodeId, last_child: NodeId, next_sibling: NodeId }
type Document = struct { nodes: []const Node, root: NodeId }
type Namespaces = struct { prefixes: []str, uris: []str, count: usize, marks: []usize, depth: usize }
type PathSet = struct { ids: []NodeId, count: usize }
error Invalid
error TooDeep
error Unsupported
error TooLarge
const DEFAULT_MAX_BYTES: usize = 16777216usize
const NONE: NodeId = 4294967295u32

fn slurp(a: *mem.Arena, source: io.Reader) -> ([]u8, err)
fn slurp_with_limit(a: *mem.Arena, source: io.Reader, limit: usize) -> ([]u8, err)
fn reader(a: *mem.Arena, source: io.Reader, options: Options) -> (Reader, err)
fn reader_with_limit(a: *mem.Arena, source: io.Reader, options: Options, limit: usize) -> (Reader, err)
fn is_space(c: u8) -> bool
fn is_name_byte(c: u8) -> bool
fn name_end(source: []const u8, at: usize) -> usize
fn skip_space(source: []const u8, at: usize) -> usize
fn push_scalar(out: []u8, at: usize, scalar: u32) -> usize
fn decode(a: *mem.Arena, raw: []const u8) -> (str, err)
fn reader_next_err(r: *Reader) -> (Event, bool, err)
fn writer(sink: io.Writer) -> Writer
fn write_escaped(sink: *io.Writer, value: str, in_attribute: bool) -> err
fn start(w: *Writer, name: str, attributes: []const Attribute) -> err
fn text(w: *Writer, value: str) -> err
fn comment(w: *Writer, value: str) -> err
fn end(w: *Writer, name: str) -> err
fn stream(a: *mem.Arena, source: []const u8, options: Options) -> (Reader, err)
fn stream_next(r: *Reader) -> (Event, bool, err)
fn add_node(nodes: []Node, used: *usize, kind: NodeKind, name: str, value: str, attributes: []const Attribute, parent: NodeId) -> NodeId
fn parse(a: *mem.Arena, source: []const u8) -> (Document, err)
fn attribute(element: *const Node, name: str) -> (str, bool)
fn namespaces(a: *mem.Arena, max_bindings: usize, max_depth: usize) -> (Namespaces, err)
fn namespaces_push(ns: *Namespaces, attributes: []const Attribute) -> err
fn namespaces_pop(ns: *Namespaces) -> err
fn resolve(ns: *const Namespaces, prefix: str) -> (str, err)
fn expand(ns: *const Namespaces, name: str) -> (str, str, err)
fn set_add(set: *PathSet, id: NodeId)
fn next_in_subtree(document: *const Document, root: NodeId, cursor: NodeId) -> NodeId
fn text_equals(document: *const Document, id: NodeId, want: str) -> bool
fn predicate_holds(document: *const Document, id: NodeId, predicate: str, position: usize) -> (bool, err)
fn push_id(set: *PathSet, id: NodeId)
fn path_step(document: *const Document, from: *const PathSet, into: *PathSet, scratch: *PathSet, step: str) -> err
fn xpath(a: *mem.Arena, document: *const Document, context: NodeId, path: str) -> ([]NodeId, err)
```

XML 1.0 names, namespaces and entity escaping are supported. External entities and
DTDs are always `Unsupported`; the module never performs hidden I/O.
`reader` and `slurp` cap ingestion at 16 MiB and return `TooLarge` without keeping
partial input. Their explicit-limit variants accept an inclusive maximum up to
1 GiB; zero selects the default. `stream` borrows already-buffered bytes, so its
input budget remains the caller's responsibility.

## Missing declarations

- [ ] `is_name_byte`

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

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/fmt/xml.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/fmt_xml/src/main.e` that prints one fixed line on success, registered in both runners.
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
