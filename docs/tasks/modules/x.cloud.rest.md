# x.cloud.rest — 69 of 69 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/cloud/rest.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/cloud/rest.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.chain` | source | `lib/e/algo/chain.e` | 5 |
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Marker = struct { field: str, managed_key: str, name_key: str, pair: bool, key_field: str, value_field: str }
type Pair = struct { key: str, value: str }
type Parent = struct { type_name: str, url_var: str, parent_by_id: bool }
type Def = struct { type_name: str, create_method: str, item_url: str, create_url: str, list_url: str, list_items_field: str, has_marker: bool, marker: Marker, copy_attrs: []const Pair, output_attrs: []const str, real_id_field: str, has_name_field: bool, name_field: str, has_name_value_template: bool, name_value_template: str, has_update_mask: bool, update_mask: str, has_operation_url: bool, operation_url: str, operation_style: u8, has_create_wrapper: bool, wrapper_key: str, has_wrapper_id: bool, wrapper_id_field: str, has_name_suffix: bool, name_suffix: str, has_observed_name_field: bool, observed_name_field: str, create_body_vars: []const Pair }
type Rendered = struct { valid: bool, message: str, value: str }
type Built = struct { valid: bool, message: str, value: json.Value }
type Status = struct { kind: u8, message: str }
type Observed = struct { name: str, type_name: str, attributes: json.Value, has_real_id: bool, real_id: str, managed: bool }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn sv(s: str) -> json.Value
fn doc_error(a: *mem.Arena, message: str) -> str
fn manifest_cloud_for_type(type_name: str) -> (str, bool)
fn type_prefix_for_manifest_cloud(cloud: str) -> (str, bool)
fn get_by_path(body: json.Value, path: str) -> (json.Value, bool)
fn list_items(def: Def, body: json.Value) -> ([]const json.Value, bool)
fn obj_from(a: *mem.Arena, v: json.Value) -> ir.Obj
fn set_path_at(a: *mem.Arena, base: json.Value, segments: []const str, at: usize, value: json.Value, full: str) -> Built
fn split_dots(a: *mem.Arena, path: str) -> []const str
fn set_by_path(a: *mem.Arena, obj: json.Value, path: str, value: json.Value) -> Built
fn scalar_text(a: *mem.Arena, v: json.Value) -> (str, bool)
fn var_lookup(vars: []const Pair, key: str) -> (str, bool)
fn render_with(a: *mem.Arena, template: str, name: str, attrs: json.Value, vars: []const Pair) -> Rendered
fn address(a: *mem.Arena, def: Def, name: str) -> str
fn body_name_value(a: *mem.Arena, def: Def, name: str, vars: []const Pair) -> Rendered
fn user_labels(a: *mem.Arena, attrs: json.Value, field: str) -> json.Value
fn build_body(a: *mem.Arena, def: Def, name: str, name_value: str, attrs: json.Value) -> Built
fn apply_create_body_vars(a: *mem.Arena, def: Def, body: json.Value, name: str, attrs: json.Value, vars: []const Pair) -> Built
fn wrap_create_body(a: *mem.Arena, def: Def, name: str, body: json.Value) -> json.Value
fn scope_from_real_id(a: *mem.Arena, item_url: str, real_id: str, has_real_id: bool) -> json.Value
fn split_slashes(a: *mem.Arena, s: str) -> []const str
fn parse_attrs(a: *mem.Arena, def: Def, body: json.Value) -> json.Value
fn update_url(a: *mem.Arena, item_url: str, mask: str, has_mask: bool) -> str
fn trimmed(s: str) -> str
fn effective_update_mask(a: *mem.Arena, curated: str, has_curated: bool, body: json.Value) -> (str, bool)
fn lro_operation_name(def: Def, body: json.Value) -> (str, bool)
fn replace_all(a: *mem.Arena, s: str, needle: str, with: str) -> str
fn operation_poll_url(a: *mem.Arena, template: str, name: str) -> str
fn status(kind: u8, message: str) -> Status
fn operation_status(a: *mem.Arena, op: json.Value) -> Status
fn is_compute_operation(body: json.Value) -> bool
fn work_request_id(a: *mem.Arena, names: []const str, values: []const str) -> (str, bool)
fn lower(a: *mem.Arena, s: str) -> str
fn work_request_status(a: *mem.Arena, op: json.Value) -> Status
fn compute_operation_status(a: *mem.Arena, op: json.Value) -> Status
fn operation_status_for(a: *mem.Arena, def: Def, op: json.Value) -> Status
fn operation_poll_target(a: *mem.Arena, def: Def, body: json.Value, names: []const str, values: []const str) -> (str, bool)
fn is_async(def: Def) -> bool
fn marker_lookup(m: Marker, body: json.Value, key: str) -> (str, bool)
fn last_segment(s: str) -> str
fn observed_name(a: *mem.Arena, def: Def, body: json.Value) -> (str, bool)
fn is_managed(a: *mem.Arena, def: Def, body: json.Value) -> bool
fn to_observed(a: *mem.Arena, def: Def, body: json.Value) -> (Observed, bool)
fn lro_max_polls(minutes: u32, has_minutes: bool) -> u32
fn settle_waits(a: *mem.Arena, budget_ms: u64) -> []u64

type Registry = struct { types: []str, type_count: usize, aliased: []str, aliased_count: usize, bridged: []str, bridged_count: usize, equiv_native: []str, equiv_bridged: []str, equiv_count: usize, preferred: []str, preferred_count: usize }

fn new_registry(a: *mem.Arena) -> Registry
fn contains_at(xs: []const str, n: usize, v: str) -> bool
fn alias_key(a: *mem.Arena, alias: str, type_name: str) -> str
fn register(r: *Registry, type_name: str) -> bool
fn register_aliased(a: *mem.Arena, r: *Registry, alias: str, type_name: str) -> bool
fn register_bridged(r: *Registry, type_name: str, native_equivalent: str) -> bool
fn prefer_bridged(r: *Registry, native_type: str)
fn is_bridged(r: Registry, type_name: str) -> bool
fn has_equivalent(r: Registry, native: str) -> (str, bool)
fn source_of(r: Registry, type_name: str) -> (str, bool)
fn resolve(r: Registry, type_name: str) -> (str, str, bool)
fn supports(r: Registry, type_name: str) -> bool
fn supports_aliased(a: *mem.Arena, r: Registry, type_name: str, alias: str, has_alias: bool) -> bool
fn registered_types(a: *mem.Arena, r: Registry) -> []const str
```

Declarative REST resources and the provider registry (L047), after Petcow's `provider/declarative.rs` (its pure half) and `provider/mod.rs`: a `Def` describes a CRUD-shaped REST resource, and `render_with` (placeholders from the resource name, its scalar attributes, then the cloud context), `get_by_path`/`set_by_path`/`list_items`, `build_body`/`apply_create_body_vars`/`wrap_create_body`, `parse_attrs`, `scope_from_real_id`, `update_url`/`effective_update_mask`, the three operation dialects (`lro_operation_name`, `operation_status_for`, `operation_poll_target`: Google long-running, Compute self-link, OCI work request), `observed_name`/`is_managed`/`to_observed`, `lro_max_polls`/`settle_waits` and a `Registry` with alias keys and native-versus-bridged precedence are everything that needs no network. Checked against Petcow's own Rust (compiled with thin shims) over 1,051 cases on both hosts (D2352).

## Missing declarations

- [ ] `Marker`
- [ ] `Pair`
- [ ] `Parent`
- [ ] `Def`
- [ ] `Rendered`
- [ ] `Built`
- [ ] `Status`
- [ ] `Observed`
- [ ] `join`
- [ ] `sv`
- [ ] `doc_error`
- [ ] `manifest_cloud_for_type`
- [ ] `type_prefix_for_manifest_cloud`
- [ ] `get_by_path`
- [ ] `list_items`
- [ ] `obj_from`
- [ ] `set_path_at`
- [ ] `split_dots`
- [ ] `set_by_path`
- [ ] `scalar_text`
- [ ] `var_lookup`
- [ ] `render_with`
- [ ] `address`
- [ ] `body_name_value`
- [ ] `user_labels`
- [ ] `build_body`
- [ ] `apply_create_body_vars`
- [ ] `wrap_create_body`
- [ ] `scope_from_real_id`
- [ ] `split_slashes`
- [ ] `parse_attrs`
- [ ] `update_url`
- [ ] `trimmed`
- [ ] `effective_update_mask`
- [ ] `lro_operation_name`
- [ ] `replace_all`
- [ ] `operation_poll_url`
- [ ] `status`
- [ ] `operation_status`
- [ ] `is_compute_operation`
- [ ] `work_request_id`
- [ ] `lower`
- [ ] `work_request_status`
- [ ] `compute_operation_status`
- [ ] `operation_status_for`
- [ ] `operation_poll_target`
- [ ] `is_async`
- [ ] `marker_lookup`
- [ ] `last_segment`
- [ ] `observed_name`
- [ ] `is_managed`
- [ ] `to_observed`
- [ ] `lro_max_polls`
- [ ] `settle_waits`
- [ ] `Registry`
- [ ] `new_registry`
- [ ] `contains_at`
- [ ] `alias_key`
- [ ] `register`
- [ ] `register_aliased`
- [ ] `register_bridged`
- [ ] `prefer_bridged`
- [ ] `is_bridged`
- [ ] `has_equivalent`
- [ ] `source_of`
- [ ] `resolve`
- [ ] `supports`
- [ ] `supports_aliased`
- [ ] `registered_types`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/cloud/rest.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/cloud_rest/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 69.

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
