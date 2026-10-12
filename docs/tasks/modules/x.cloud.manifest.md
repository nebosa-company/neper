# x.cloud.manifest — 32 of 32 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/cloud/manifest.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | `x.cloud.rest` |

## Definition of done

Implement **exactly** the public fence below in `lib/e/cloud/manifest.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.fmt.yaml` | partial | `lib/e/fmt/yaml.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |
| `x.cloud.rest` | source | missing | 6 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Resource = struct { type_name: str, cloud: str, create_method: str, item_url: str, create_url: str, list_url: str, list_items_field: str, has_marker: bool, marker: rest.Marker, copy_attrs: []const rest.Pair, output_attrs: []const str, real_id_field: str, has_name_field: bool, name_field: str, has_name_value_template: bool, name_value_template: str, has_update_method: bool, update_method: str, has_update_mask: bool, update_mask: str, has_operation_url: bool, operation_url: str, has_timeout: bool, timeout_minutes: u32, operation_style: u8, has_create_wrapper: bool, wrapper_key: str, has_wrapper_id: bool, wrapper_id_field: str, server_named: bool, has_name_suffix: bool, name_suffix: str, has_read_method: bool, read_method: str, has_list_method: bool, list_method: str, has_delete_method: bool, delete_method: str, has_update_target_url: bool, update_target_url: str, has_delete_url: bool, delete_url: str, has_parent: bool, parent: rest.Parent, create_body_vars: []const rest.Pair, has_observed_name_field: bool, observed_name_field: str }
type Manifest = struct { valid: bool, message: str, resources: []const Resource }
type Rpc = struct { endpoint: str, version: str, method: str, create_action: str, create_params: []const rest.Pair, read_action: str, read_params: []const rest.Pair, list_action: str, list_params: []const rest.Pair, delete_action: str, delete_params: []const rest.Pair, has_update: bool, update_action: str, update_params: []const rest.Pair }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn shape_error(a: *mem.Arena, what: str) -> str
fn doc_error(a: *mem.Arena, what: str) -> str
fn failed(message: str) -> Manifest
fn key_text(v: yaml.Value) -> (str, bool)
fn scalar_text(a: *mem.Arena, v: yaml.Value) -> (str, bool)

type Reader = struct { a: *mem.Arena, message: str, failed: bool }

fn bad(r: *Reader, what: str)
fn mapping(v: yaml.Value) -> ([]const yaml.Pair, bool)
fn sequence(v: yaml.Value) -> ([]const yaml.Value, bool)
fn is_null(v: yaml.Value) -> bool
fn opt_text(r: *Reader, m: []const yaml.Pair, name: str) -> (str, bool)
fn req_text(r: *Reader, m: []const yaml.Pair, name: str) -> str
fn text_or(r: *Reader, m: []const yaml.Pair, name: str, fallback: str) -> str
fn find(m: []const yaml.Pair, name: str) -> (yaml.Value, bool)
fn text_map(r: *Reader, m: []const yaml.Pair, name: str) -> []const rest.Pair
fn allowed_keys(r: *Reader, m: []const yaml.Pair, allowed: []const str, owner: str)
fn op_of(r: *Reader, v: yaml.Value, owner: str) -> (str, []const rest.Pair)
fn debug_char(a: *mem.Arena, c: u8) -> str
fn str_of_byte(c: u8) -> str
fn check_query_safe(a: *mem.Arena, kind: str, text: str) -> (str, bool)

type Url = struct { valid: bool, message: str, value: str }

fn rpc_url(a: *mem.Arena, rpc: Rpc, action: str, params: []const rest.Pair) -> Url
fn rsplit_dot(s: str) -> (str, bool)
fn check_pair_marker_stamped(a: *mem.Arena, type_name: str, managed_key: str, name_key: str, params: []const rest.Pair) -> (str, bool)
fn empty_marker() -> rest.Marker
fn declarative_clouds() -> str
fn convert(a: *mem.Arena, r: *Reader, m: []const yaml.Pair) -> (Resource, str, bool)
fn parse_manifest(a: *mem.Arena, source: str) -> Manifest
```

External resource manifests (L047), after Petcow's `provider/manifest.rs`: `parse_manifest` reads a YAML file of `resources:` (known keys only, typed values, string maps in key order) into definitions bound to a cloud, with the reference's validations in its order: the cloud must be declarative and agree with the type's prefix; an `rpc:` block lowers to the item, list, create, delete and update URLs and the verbs (and refuses explicit URLs beside it; each action, version and parameter is checked for characters that would split the query string); a marker and `observed_name_field` cannot both name the resource; `create_body_vars` may not collide with what `copy_attrs` or `name_field` writes; a pair-list marker must be stamped by the RPC create's params. Checked against Petcow's own `manifest.rs` over 117 manifests on both hosts (D2353).

## Missing declarations

- [ ] `Resource`
- [ ] `Manifest`
- [ ] `Rpc`
- [ ] `join`
- [ ] `shape_error`
- [ ] `doc_error`
- [ ] `failed`
- [ ] `key_text`
- [ ] `scalar_text`
- [ ] `Reader`
- [ ] `bad`
- [ ] `mapping`
- [ ] `sequence`
- [ ] `is_null`
- [ ] `opt_text`
- [ ] `req_text`
- [ ] `text_or`
- [ ] `find`
- [ ] `text_map`
- [ ] `allowed_keys`
- [ ] `op_of`
- [ ] `debug_char`
- [ ] `str_of_byte`
- [ ] `check_query_safe`
- [ ] `Url`
- [ ] `rpc_url`
- [ ] `rsplit_dot`
- [ ] `check_pair_marker_stamped`
- [ ] `empty_marker`
- [ ] `declarative_clouds`
- [ ] `convert`
- [ ] `parse_manifest`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/cloud/manifest.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/cloud_manifest/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 32.

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
