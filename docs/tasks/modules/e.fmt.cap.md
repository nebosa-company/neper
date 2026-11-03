# e.fmt.cap — 1 of 11 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/fmt/cap.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/fmt/cap.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.fmt.xml` | partial | `lib/e/fmt/xml.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
error NotCap
error TooMany

type Info = struct { language: str, category: str, event: str, urgency: str, severity: str, certainty: str, effective: str, onset: str, expires: str, sender_name: str, headline: str, description: str, instruction: str, web: str, area_description: str, areas: usize }
type Alert = struct { identifier: str, sender: str, sent: str, status: str, message_type: str, scope: str, infos: []Info }

const MAX_INFOS: usize = 16usize

fn local(name: str) -> str
fn is_space(c: u8) -> bool
fn trim(s: str) -> str
fn text_under(a: *mem.Arena, nodes: []const xml.Node, at: usize) -> (str, err)
fn set_field(info: *Info, name: str, value: str)
fn parse(a: *mem.Arena, source: []const u8) -> (Alert, err)
```

Common Alerting Protocol 1.2 (C156): `parse` reads an `<alert>` over `e.fmt.xml` into the message (identifier, sender, sent, status, message type, scope) and each `<info>` block (language, first category, event, urgency, severity, certainty, effective, onset, expires, sender name, headline, description, instruction, web, the first area's description and the number of areas), element names matched without a namespace prefix and text trimmed. No polygons, geocodes, resources or signatures; a document whose root is not `alert` is `NotCap`, malformed XML the parser's error. Checked against an ElementTree walk of two-language, cancel and prefixed documents (`scripts/gen_cap_test.py`).

## Missing declarations

- [ ] `local`

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

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/fmt/cap.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/fmt_cap/src/main.e` that prints one fixed line on success, registered in both runners.
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
