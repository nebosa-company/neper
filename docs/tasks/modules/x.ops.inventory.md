# x.ops.inventory — 26 of 26 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/ops/inventory.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/ops/inventory.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.fmt.yaml` | partial | `lib/e/fmt/yaml.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Doc = struct { valid: bool, message: str, names: []const str, addresses: []const str, host_groups: []const []const str, host_vars: []const json.Value, group_names: []const str, group_vars: []const json.Value }
type Host = struct { name: str, address: str, groups: []const str, vars: json.Value }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn sv(s: str) -> json.Value
fn put(o: *ir.Obj, key: str, v: json.Value)
fn new_obj(a: *mem.Arena) -> ir.Obj
fn is_ws(c: u8) -> bool
fn trim(s: str) -> str
fn parse_i64(s: str) -> (i64, bool)
fn parse_facts(a: *mem.Arena, stdout: str) -> json.Value
fn custom_fact_script(a: *mem.Arena, names: []const str, commands: []const str) -> str
fn sanitize(a: *mem.Arena, token: str) -> str
fn bad(a: *mem.Arena, what: str) -> Doc
fn key_text(v: yaml.Value) -> (str, bool)
fn to_json(a: *mem.Arena, v: yaml.Value) -> json.Value
fn mapping_of(v: yaml.Value) -> ([]const yaml.Pair, bool)
fn find(m: []const yaml.Pair, name: str) -> (yaml.Value, bool)
fn sort_indexes(a: *mem.Arena, names: []const str) -> []usize
fn parse_inventory(a: *mem.Arena, source: str) -> Doc
fn q_noop()
fn resolve(a: *mem.Arena, d: Doc) -> []Host
fn scalar_text(a: *mem.Arena, v: json.Value) -> str
fn select(a: *mem.Arena, d: Doc, group: str, has_group: bool, var_key: str, var_value: str, has_var: bool) -> []const Host

type Source = struct { type_name: str, address_from: str, has_group: bool, group: str, has_group_from_tag: bool, group_from_tag: str }
type Observed = struct { name: str, attributes: json.Value, has_real_id: bool, real_id: str }

fn synthesize_hosts(a: *mem.Arena, source: Source, observed: []const Observed) -> ([]const str, []const Host)
```

Host facts and inventory helpers (L050), after Petcow's `facts.rs`, `inventory.rs` and `naming.rs`: `parse_facts` (key=value lines, CRLF-safe, integers coerced, the text after the first `=` kept), `custom_fact_script` (first-line-only capture), `parse_inventory` with `resolve` and `select` (hosts sorted by name, group variables merged in listed order under host variables, optional group and variable filters; unknown keys refused), `synthesize_hosts` (observed cloud resources as hosts: address attribute, type/group/tag-derived groups, scalar attributes and string tags as variables, resource id passed through, no-address skipped) and `sanitize`. Checked against Petcow's own Rust over 140 cases on both hosts (D2356).

## Missing declarations

- [ ] `Doc`
- [ ] `Host`
- [ ] `join`
- [ ] `sv`
- [ ] `put`
- [ ] `new_obj`
- [ ] `is_ws`
- [ ] `trim`
- [ ] `parse_i64`
- [ ] `parse_facts`
- [ ] `custom_fact_script`
- [ ] `sanitize`
- [ ] `bad`
- [ ] `key_text`
- [ ] `to_json`
- [ ] `mapping_of`
- [ ] `find`
- [ ] `sort_indexes`
- [ ] `parse_inventory`
- [ ] `q_noop`
- [ ] `resolve`
- [ ] `scalar_text`
- [ ] `select`
- [ ] `Source`
- [ ] `Observed`
- [ ] `synthesize_hosts`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/ops/inventory.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/ops_inventory/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 26.

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
