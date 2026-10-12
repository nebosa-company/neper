# x.identity.xml — 35 of 35 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/identity/xml.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/identity/xml.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.formula.text` | source | `lib/e/algo/formula/text.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |
| `e.text.utf8` | source | `lib/e/text/utf8.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Entry = struct { is_text: bool, text: str, node: usize }
type Node = struct { name: str, prefix: str, local: str, attr_names: []const str, attr_values: []const str, ns_prefixes: []const str, ns_uris: []const str, children: []const usize, entries: []const Entry, text: str, parent: i64 }
type Doc = struct { valid: bool, message: str, nodes: []Node, root: usize }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn is_name_start(c: u8) -> bool
fn is_name_char(c: u8) -> bool
fn is_space(c: u8) -> bool
fn starts_at(s: str, at: usize, prefix: str) -> bool
fn find_from(s: str, needle: str, from: usize) -> (usize, bool)
fn blank_text(s: str) -> bool
fn js_trim(s: str) -> str
fn utf16_offset(s: str, at: usize) -> usize
fn push_scalar(buf: []u8, at: usize, code: u32) -> usize
fn hex_digit_value(c: u8) -> i32
fn decode_entities(a: *mem.Arena, s: str) -> str
fn escape_text(a: *mem.Arena, s: str) -> str
fn escape_attribute(a: *mem.Arena, s: str) -> str
fn bad(a: *mem.Arena, source: str, at: usize, message: str) -> Doc
fn bare(message: str) -> Doc
fn parse_xml(a: *mem.Arena, source: str) -> Doc
fn attribute_of(n: Node, name: str) -> (str, bool)
fn resolve_namespace(d: Doc, at: usize, prefix: str) -> (str, bool)
fn collect(d: Doc, at: usize, ns: str, local: str, out: []usize, n: *usize)
fn find_elements(a: *mem.Arena, d: Doc, at: usize, ns: str, local: str) -> []const usize
fn find_element(a: *mem.Arena, d: Doc, at: usize, ns: str, local: str) -> (usize, bool)
fn id_of(n: Node) -> (str, bool)
fn find_by_id(d: Doc, at: usize, id: str) -> (usize, bool)
fn is_word(c: u8) -> bool
fn looks_like_qname(s: str) -> bool
fn colon_at(s: str) -> i64

type Rendered = struct { prefixes: []str, uris: []str, count: usize }

fn rendered_get(r: Rendered, prefix: str) -> (str, bool)
fn render(a: *mem.Arena, d: Doc, at: usize, inherited: Rendered, inclusive: []const str) -> str
fn canonicalize(a: *mem.Arena, d: Doc, at: usize, inclusive: []const str) -> str
fn without_signature(a: *mem.Arena, d: Doc, at: usize) -> (Doc, usize)
```

A small XML reader and Exclusive XML Canonicalization 1.0 for SAML (L045), after Appdor's `src/identity/xml.js`: `parse_xml` (elements, attributes, namespaces, text, CDATA, comments and the declaration; no DTD, so no entity expansion; the reference's own error messages and UTF-16 offsets), `decode_entities`, `resolve_namespace`, `find_elements`/`find_element`/`find_by_id`, `canonicalize` (visibly-utilised namespace declarations, attributes sorted by namespace then local name, text kept with its whitespace, the C14N escapes, `InclusiveNamespaces` prefixes) and `without_signature` (the enveloped-signature transform). Checked against Appdor's own functions over 416 cases with `x.identity.saml` on both hosts (D2350).

## Missing declarations

- [ ] `Entry`
- [ ] `Node`
- [ ] `Doc`
- [ ] `join`
- [ ] `is_name_start`
- [ ] `is_name_char`
- [ ] `is_space`
- [ ] `starts_at`
- [ ] `find_from`
- [ ] `blank_text`
- [ ] `js_trim`
- [ ] `utf16_offset`
- [ ] `push_scalar`
- [ ] `hex_digit_value`
- [ ] `decode_entities`
- [ ] `escape_text`
- [ ] `escape_attribute`
- [ ] `bad`
- [ ] `bare`
- [ ] `parse_xml`
- [ ] `attribute_of`
- [ ] `resolve_namespace`
- [ ] `collect`
- [ ] `find_elements`
- [ ] `find_element`
- [ ] `id_of`
- [ ] `find_by_id`
- [ ] `is_word`
- [ ] `looks_like_qname`
- [ ] `colon_at`
- [ ] `Rendered`
- [ ] `rendered_get`
- [ ] `render`
- [ ] `canonicalize`
- [ ] `without_signature`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/identity/xml.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/identity_xml/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 35.

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
