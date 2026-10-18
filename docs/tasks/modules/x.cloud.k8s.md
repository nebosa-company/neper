# x.cloud.k8s — 22 of 22 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/cloud/k8s.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/cloud/k8s.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.chain` | source | `lib/e/algo/chain.e` | 5 |
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.fmt.yaml` | partial | `lib/e/fmt/yaml.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Def = struct { petcow_type: str, api_version: str, kind: str, namespaced: bool }
type Defs = struct { valid: bool, message: str, defs: []const Def }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn managed_label() -> str
fn name_label() -> str
fn last_applied_key() -> str
fn def(petcow_type: str, api_version: str, kind: str, namespaced: bool) -> Def
fn default_defs(a: *mem.Arena) -> []const Def
fn failed_defs(a: *mem.Arena, what: str) -> Defs
fn string_value(a: *mem.Arena, v: yaml.Value) -> (str, bool)
fn def_of(a: *mem.Arena, v: yaml.Value) -> (Def, str, bool)
fn parse_defs(a: *mem.Arena, source: str) -> Defs
fn merge_defs(a: *mem.Arena, defaults: []const Def, extra: []const Def) -> []const Def
fn selector(a: *mem.Arena, d: Def) -> str
fn ns_args(a: *mem.Arena, d: Def, namespace: str, has_namespace: bool) -> []const str
fn lower_ascii(a: *mem.Arena, s: str) -> str
fn is_not_found(a: *mem.Arena, stderr: str) -> bool
fn text(s: str) -> json.Value
fn obj(a: *mem.Arena) -> ir.Obj
fn is_managed_item(item: json.Value) -> bool
fn apply_manifest(a: *mem.Arena, d: Def, name: str, attrs: json.Value) -> str
fn observed(a: *mem.Arena, type_: str, live: json.Value) -> json.Value
```

The Kubernetes provider's identity and drift rules (L048), after Petcow's `provider/k8s/mod.rs`: the fourteen built-in kinds and an operator manifest of more merged over them by type (`default_defs`, `parse_defs`, `merge_defs`), the kubectl selector and `-n` arguments (`selector`, `ns_args`), the apply manifest with `metadata.name` forced and the `petcow.io/managed` and `petcow.io/name` labels injected over a user's own (`apply_manifest`), the observed state taken from the `last-applied-configuration` annotation when it parses and from the live object otherwise (`observed`), and whether an object is managed or a kubectl error means not found (`is_managed_item`, `is_not_found`). A string field accepts a plain scalar as its text, as the reference's YAML reader does; a number written with a trailing zero or an exponent is read as its shortest text. The kubectl process is host code. Checked against Petcow's own functions, extracted unchanged, with the S3, IAM, EC2, Lightsail and transport helpers, over 600 inputs on Windows (D2922).

## Missing declarations

- [ ] `Def`
- [ ] `Defs`
- [ ] `join`
- [ ] `managed_label`
- [ ] `name_label`
- [ ] `last_applied_key`
- [ ] `def`
- [ ] `default_defs`
- [ ] `failed_defs`
- [ ] `string_value`
- [ ] `def_of`
- [ ] `parse_defs`
- [ ] `merge_defs`
- [ ] `selector`
- [ ] `ns_args`
- [ ] `lower_ascii`
- [ ] `is_not_found`
- [ ] `text`
- [ ] `obj`
- [ ] `is_managed_item`
- [ ] `apply_manifest`
- [ ] `observed`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/cloud/k8s.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/cloud_k8s/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 22.

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
