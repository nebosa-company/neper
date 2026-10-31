# e.fmt.soap — 1 of 60 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/fmt/soap.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/fmt/soap.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.fmt.xml` | partial | `lib/e/fmt/xml.e` | 6 |
| `e.io` | source | `lib/e/io.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
error Invalid
error NotSoap
error VersionMismatch
error MustUnderstand
error DataEncodingUnknown
error Sender
error Receiver
error OtherFault
error TooLarge

type Version = enum u8 { Soap11, Soap12 }
type FaultCode = enum u8 { VersionMismatch, MustUnderstand, DataEncodingUnknown, Sender, Receiver, Other }

fn namespace(v: Version) -> str
fn content_type(a: *mem.Arena, v: Version, action: str) -> (str, err)

type Builder = struct { w: xml.Writer, version: Version, prefix: str, scratch: *mem.Arena }

fn builder(a: *mem.Arena, sink: io.Writer, version: Version, prefix: str) -> (Builder, err)
fn qualified(b: *const Builder, local: str) -> (str, err)
fn begin(b: *Builder) -> err
fn open_part(b: *Builder, local: str) -> err
fn close_part(b: *Builder, local: str) -> err
fn header_start(b: *Builder) -> err
fn header_end(b: *Builder) -> err
fn body_start(b: *Builder) -> err
fn must_understand_attribute(b: *const Builder) -> (xml.Attribute, err)
fn finish(b: *Builder) -> err

type FaultOut = struct { code: FaultCode, reason: str, language: str, actor: str, detail: str, subcode: str }

fn code_local(v: Version, code: FaultCode) -> str
fn simple_element(b: *Builder, name: str, value: str) -> err
fn fault_write(b: *Builder, f: FaultOut) -> err

type Envelope = struct { version: Version, document: xml.Document, root: xml.NodeId, header: xml.NodeId, body: xml.NodeId }

fn node(d: *const xml.Document, id: xml.NodeId) -> xml.Node
fn split_name(name: str) -> (str, str)
fn declares(attribute_name: str, prefix: str) -> bool
fn resolve(d: *const xml.Document, id: xml.NodeId, prefix: str) -> (str, err)
fn expand(d: *const xml.Document, id: xml.NodeId) -> (str, str, err)
fn is_named(d: *const xml.Document, id: xml.NodeId, uri: str, local: str) -> bool
fn next_element(d: *const xml.Document, from: xml.NodeId) -> xml.NodeId
fn first_child_element(d: *const xml.Document, parent: xml.NodeId) -> xml.NodeId
fn next_sibling_element(d: *const xml.Document, id: xml.NodeId) -> xml.NodeId
fn element_text(a: *mem.Arena, d: *const xml.Document, id: xml.NodeId) -> (str, err)
fn parse(a: *mem.Arena, source: []const u8) -> (Envelope, err)
fn payload(e: *const Envelope) -> xml.NodeId
fn is_fault(e: *const Envelope) -> bool
fn must_understand_blocks(a: *mem.Arena, e: *const Envelope, out: []xml.NodeId) -> (usize, err)

type Fault = struct { version: Version, code: FaultCode, code_text: str, subcode: str, reason: str, language: str, actor: str, detail: xml.NodeId }

fn child_named(d: *const xml.Document, parent: xml.NodeId, uri: str, local: str) -> xml.NodeId
fn code_of(d: *const xml.Document, at: xml.NodeId, raw: str, v: Version) -> (FaultCode, err)
fn parse_fault(a: *mem.Arena, e: *const Envelope) -> (Fault, err)
fn fault_error(code: FaultCode) -> err

type Part = struct { name: str, type_name: str, element: str }
type Operation = struct { name: str, action: str, style: str, input: str, output: str, input_parts: []Part, output_parts: []Part }
type Wsdl = struct { target_namespace: str, location: str, soap: Version, operations: []Operation }

fn wsdl_namespace() -> str
fn wsdl_soap11() -> str
fn wsdl_soap12() -> str
fn attr(d: *const xml.Document, id: xml.NodeId, name: str) -> str
fn local_of(qname: str) -> str
fn collect_parts(a: *mem.Arena, d: *const xml.Document, definitions: xml.NodeId, message: str) -> ([]Part, err)
fn wsdl_parse(a: *mem.Arena, source: []const u8) -> (Wsdl, err)
fn xsd_neper_type(local: str) -> (str, bool)
fn parse_xsd_boolean(text: str) -> (bool, err)
```

SOAP 1.1 and 1.2 envelopes, faults and a WSDL 1.1 operation reader over `e.fmt.xml`, with no HTTP
(the caller sends `content_type` and, for 1.1, the SOAPAction header) and no schema validation. The
builder writes `<p:Envelope>`, an optional header and the body, and `fault_write` writes a whole fault
(1.1 faultcode/faultstring/faultactor/detail; 1.2 Code with an optional Subcode, Reason/Text with
xml:lang, Role, Detail). `parse` resolves namespaces through the document's own xmlns bindings, so any
prefix works, and answers `NotSoap`, `VersionMismatch` (an Envelope in another namespace) or `Invalid`;
`parse_fault` decodes a fault and `fault_error` maps its code (Client and Sender, Server and Receiver)
to a typed error. `wsdl_parse` joins port-type operations with their SOAP binding (action, style) and
message parts, and `xsd_neper_type` maps an XSD built-in type name to a Neper type.

## Missing declarations

- [ ] `collect_parts`

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

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/fmt/soap.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/fmt_soap/src/main.e` that prints one fixed line on success, registered in both runners.
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
