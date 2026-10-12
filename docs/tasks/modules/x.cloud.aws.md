# x.cloud.aws — 34 of 34 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/cloud/aws.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/cloud/aws.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

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
type Parent = struct { petcow_type: str, property: str }
type Def = struct { petcow_type: str, cfn_type: str, has_name_property: bool, name_property: str, tag_map: bool, has_tag_property: bool, tag_property: str, has_identity: bool, identity: []const str, has_derived: bool, derived: []const str, has_parent: bool, parent: Parent }
type Defs = struct { valid: bool, message: str, defs: []const Def }
type Text = struct { valid: bool, message: str, value: str }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn sv(s: str) -> json.Value
fn managed_tag() -> str
fn name_tag() -> str
fn is_throttle(msg: str) -> bool
fn failed_defs(a: *mem.Arena, what: str) -> Defs
fn text_field(v: yaml.Value) -> (str, bool, bool)
fn map_find(m: []const yaml.Pair, name: str) -> (yaml.Value, bool)
fn string_list(a: *mem.Arena, v: yaml.Value) -> ([]const str, bool)
fn def_of(a: *mem.Arena, v: yaml.Value) -> (Def, str, bool)
fn parse_defs(a: *mem.Arena, source: str) -> Defs
fn merge_defs(a: *mem.Arena, defaults: []const Def, extra: []const Def) -> []const Def
fn scalar_string(v: json.Value) -> (str, bool)
fn compose_identifier(a: *mem.Arena, identity: []const str, name_property: str, name: str, attrs: json.Value, petcow_type: str) -> Text
fn name_from_identifier(a: *mem.Arena, identity: []const str, name_property: str, identifier: str) -> (str, bool)
fn compact(a: *mem.Arena, v: json.Value) -> str
fn copy_without(a: *mem.Arena, attrs: json.Value, skip: str) -> ir.Obj
fn desired_state_json(a: *mem.Arena, name_property: str, name: str, attrs: json.Value) -> str
fn merged_tags(a: *mem.Arena, name: str, user_tags: json.Value, has_user: bool, map_shape: bool) -> json.Value
fn desired_state_tagged(a: *mem.Arena, name: str, attrs: json.Value, map_shape: bool, tag_prop: str) -> str
fn managed_name_from_attrs(attrs: json.Value, map_shape: bool, tag_prop: str) -> (str, bool)
fn sorted_members(a: *mem.Arena, attrs: json.Value) -> []const json.Member
fn patch_op(a: *mem.Arena, key: str, value: json.Value) -> json.Value
fn patch_document(a: *mem.Arena, name_property: str, has_name_property: bool, attrs: json.Value) -> str
fn listed(xs: []const str, key: str) -> bool
fn patch_document_skipping(a: *mem.Arena, identity: []const str, attrs: json.Value) -> str
fn patch_document_tagged(a: *mem.Arena, name: str, attrs: json.Value, map_shape: bool, tag_prop: str) -> str
fn strip_petcow_tags(a: *mem.Arena, attrs: json.Value, map_shape: bool, tag_prop: str) -> json.Value
fn properties_have_key(a: *mem.Arena, props: str, has_props: bool, key: str) -> bool
fn parse_properties(a: *mem.Arena, props: str, has_props: bool) -> (json.Value, str, bool)
```

AWS Cloud Control identity and request shaping (L048), after Petcow's `provider/aws/cloudcontrol.rs`: the catalogue `Def` read from an operator manifest and merged over the built-ins by type (`parse_defs`, `merge_defs`); the composite identifier joined with `|` in schema order and read back (`compose_identifier`, `name_from_identifier`); the `DesiredState` documents for name-addressable and tag-indexed types; tags with the `petcow:managed`/`petcow:name` identity stamped in under both tag shapes (`merged_tags`, `managed_name_from_attrs`, `strip_petcow_tags`); the RFC 6902 patch documents for update; `properties_have_key`, `parse_properties` and `is_throttle`. The SDK calls are host code. Checked against Petcow's own Rust (extracted behind thin shims) over 311 cases with `x.ssh.args` on both hosts (D2354).

## Missing declarations

- [ ] `Parent`
- [ ] `Def`
- [ ] `Defs`
- [ ] `Text`
- [ ] `join`
- [ ] `sv`
- [ ] `managed_tag`
- [ ] `name_tag`
- [ ] `is_throttle`
- [ ] `failed_defs`
- [ ] `text_field`
- [ ] `map_find`
- [ ] `string_list`
- [ ] `def_of`
- [ ] `parse_defs`
- [ ] `merge_defs`
- [ ] `scalar_string`
- [ ] `compose_identifier`
- [ ] `name_from_identifier`
- [ ] `compact`
- [ ] `copy_without`
- [ ] `desired_state_json`
- [ ] `merged_tags`
- [ ] `desired_state_tagged`
- [ ] `managed_name_from_attrs`
- [ ] `sorted_members`
- [ ] `patch_op`
- [ ] `patch_document`
- [ ] `listed`
- [ ] `patch_document_skipping`
- [ ] `patch_document_tagged`
- [ ] `strip_petcow_tags`
- [ ] `properties_have_key`
- [ ] `parse_properties`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/cloud/aws.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/cloud_aws/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 34.

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
