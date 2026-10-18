# x.cloud.awsreq — 43 of 43 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/cloud/awsreq.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/cloud/awsreq.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.algo.sync` | source | `lib/e/algo/sync.e` | 5 |
| `e.bytes` | partial | `lib/e/bytes.e` | 1 |
| `e.data.list` | source | `lib/e/data/list.e` | 2 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Pair = struct { key: str, value: str }
type Out = struct { a: *mem.Arena, pairs: list.List[Pair], ec2: bool, shapes: json.Value, bad: bool }
fn cat2(a: *mem.Arena, x: str, y: str) -> str
fn text_of(v: json.Value, key: str) -> str
fn flag_of(v: json.Value, key: str) -> bool
fn attr_text(o: *const Out, ref: json.Value, key: str) -> (str, bool)
fn attr_flag(o: *const Out, ref: json.Value, key: str) -> bool
fn shape_of(o: *const Out, ref: json.Value) -> json.Value
fn type_of(o: *const Out, ref: json.Value) -> str
fn put(o: *Out, key: str, value: str)
fn capitalize(a: *mem.Arena, s: str) -> str
fn wire_name(o: *Out, ref: json.Value, default_name: str) -> str
fn scalar_text(a: *mem.Arena, v: json.Value) -> str
fn base64_text(a: *mem.Arena, s: str) -> str
fn pad2(b: *str.Builder, n: i64)
fn iso8601(a: *mem.Arena, secs: i64) -> str
fn number_i64(v: json.Value) -> i64
fn query_value(o: *Out, v: json.Value, ref: json.Value, prefix: str)
fn index_text(a: *mem.Arena, n: usize) -> str
fn quote_plus(a: *mem.Arena, s: str) -> str
fn form_body(a: *mem.Arena, pairs: []const Pair) -> str
type Buf = struct { data: []u8, n: usize }
fn pct(a: *mem.Arena, s: str, safe: str) -> str
fn rfc822(a: *mem.Arena, secs: i64) -> str
fn located_text(o: *Out, v: json.Value, ref: json.Value, ts_default: str) -> str
fn xml_text(b: *Buf, s: str, attribute: bool)
fn xml_namespace(o: *Out, b: *Buf, ref: json.Value)
fn attr_value(o: *const Out, ref: json.Value, key: str) -> (json.Value, bool)
fn xml_scalar(o: *Out, b: *Buf, name: str, ref: json.Value, text: str)
fn xml_value(o: *Out, b: *Buf, v: json.Value, ref: json.Value, name: str)
fn render_uri(a: *mem.Arena, template: str, uri: []const Pair) -> str
fn escape_header_item(a: *mem.Arena, s: str) -> str
fn join_commas(a: *mem.Arena, parts: []const str) -> str
fn header_value(o: *Out, v: json.Value, ref: json.Value) -> str
fn rest_xml(o: *Out, call: json.Value, params: json.Value, out: *ir.Obj) -> bool
fn bput(b: *Buf, s: str)
fn bbyte(b: *Buf, c: u8)
fn bint(b: *Buf, v: i64)
fn dump_string(b: *Buf, s: str)
fn dump_u16(b: *Buf, v: u32)
fn dump_value(o: *Out, b: *Buf, v: json.Value, ref: json.Value)
fn header(a: *mem.Arena, name: str, value: str) -> json.Value
fn build(a: *mem.Arena, call: json.Value, params: json.Value) -> (json.Value, bool)
```

## Missing declarations

- [ ] `Pair`
- [ ] `Out`
- [ ] `cat2`
- [ ] `text_of`
- [ ] `flag_of`
- [ ] `attr_text`
- [ ] `attr_flag`
- [ ] `shape_of`
- [ ] `type_of`
- [ ] `put`
- [ ] `capitalize`
- [ ] `wire_name`
- [ ] `scalar_text`
- [ ] `base64_text`
- [ ] `pad2`
- [ ] `iso8601`
- [ ] `number_i64`
- [ ] `query_value`
- [ ] `index_text`
- [ ] `quote_plus`
- [ ] `form_body`
- [ ] `Buf`
- [ ] `pct`
- [ ] `rfc822`
- [ ] `located_text`
- [ ] `xml_text`
- [ ] `xml_namespace`
- [ ] `attr_value`
- [ ] `xml_scalar`
- [ ] `xml_value`
- [ ] `render_uri`
- [ ] `escape_header_item`
- [ ] `join_commas`
- [ ] `header_value`
- [ ] `rest_xml`
- [ ] `bput`
- [ ] `bbyte`
- [ ] `bint`
- [ ] `dump_string`
- [ ] `dump_u16`
- [ ] `dump_value`
- [ ] `header`
- [ ] `build`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/cloud/awsreq.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/cloud_awsreq/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 43.

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
