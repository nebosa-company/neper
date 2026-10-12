# x.identity.scim — 77 of 77 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/identity/scim.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/identity/scim.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.chain` | source | `lib/e/algo/chain.e` | 5 |
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.formula.text` | source | `lib/e/algo/formula/text.e` | 4 |
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Token = struct { kind: u8, value: str }
type Node = struct { kind: u8, op: u8, attribute: str, path: str, left: usize, right: usize, value: json.Value }
type Parser = struct { tokens: []const Token, pos: usize, nodes: []Node, count: usize, failed: bool, message: str }
type Filter = struct { valid: bool, message: str, nodes: []const Node, root: usize }
type PatchPath = struct { attribute: str, has_filter: bool, filter: Filter, has_sub: bool, sub: str, has_error: bool, message: str }
type Patched = struct { valid: bool, message: str, resource: json.Value }
type Page = struct { start_index: f64, total: json.Value, resources: []const json.Value }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn sv(s: str) -> json.Value
fn is_sep(c: u8) -> bool
fn lower(a: *mem.Arena, s: str) -> str
fn same_lower(a: *mem.Arena, x: str, y: str) -> bool
fn tokenize(a: *mem.Arena, s: str) -> []const Token
fn fail(p: *Parser, message: str) -> usize
fn new_node(p: *Parser, n: Node) -> usize
fn blank(kind: u8) -> Node
fn is_number_literal(s: str) -> bool
fn literal(t: Token) -> json.Value
fn op_code(a: *mem.Arena, s: str) -> i32
fn peek_value_is(p: *Parser, v: str) -> bool
fn peek_word_is(a: *mem.Arena, p: *Parser, v: str) -> bool
fn parse_value_path(a: *mem.Arena, p: *Parser, attr: str) -> usize
fn parse_primary(a: *mem.Arena, p: *Parser) -> usize
fn parse_and(a: *mem.Arena, p: *Parser) -> usize
fn parse_or(a: *mem.Arena, p: *Parser) -> usize
fn parse_filter(a: *mem.Arena, input: str) -> Filter
fn find_key(a: *mem.Arena, object: json.Value, key: str) -> (json.Value, bool)
fn get_attribute(a: *mem.Arena, resource: json.Value, path: str) -> (json.Value, bool)
fn number_of(v: json.Value) -> f64
fn text_value(a: *mem.Arena, v: json.Value) -> str
fn to_number(v: json.Value) -> f64
fn is_string(v: json.Value) -> bool
fn strict_equal(x: json.Value, y: json.Value) -> bool
fn lowered_value(a: *mem.Arena, v: json.Value) -> json.Value
fn less(x: json.Value, y: json.Value) -> bool
fn compare_values(a: *mem.Arena, actual: json.Value, found: bool, op: u8, expected: json.Value) -> bool
fn eval(a: *mem.Arena, nodes: []const Node, at: usize, resource: json.Value) -> bool
fn evaluate(a: *mem.Arena, filter: Filter, resource: json.Value) -> bool
fn index_of(s: str, c: u8) -> i64
fn last_index_of(s: str, c: u8) -> i64
fn slice_of(s: str, from: i64, to: i64) -> str
fn no_filter() -> Filter
fn parse_patch_path(a: *mem.Arena, raw: str) -> PatchPath
fn object_of(a: *mem.Arena, v: json.Value) -> ir.Obj
fn without(a: *mem.Arena, v: json.Value, key: str) -> json.Value
fn set_path(a: *mem.Arena, base: json.Value, parts: []const str, at: usize, value: json.Value, has_value: bool) -> json.Value
fn split_dots(a: *mem.Arena, attribute: str, sub: str, has_sub: bool) -> []const str
fn patch_failed(msg: str) -> Patched
fn apply_patch_op(a: *mem.Arena, resource: json.Value, operation: json.Value) -> Patched
fn apply_patch(a: *mem.Arena, resource: json.Value, body: json.Value) -> Patched
fn escape_into(a: *mem.Arena, s: str) -> str
fn s_of(c: u8) -> str
fn stringify(a: *mem.Arena, v: json.Value, keys: []const str) -> str
fn hex_text(a: *mem.Arena, x: u32) -> str
fn resource_version(a: *mem.Arena, resource: json.Value) -> str
fn truthy_text(v: json.Value, key: str) -> (str, bool)
fn put_opt(o: *ir.Obj, key: str, v: json.Value, has: bool)
fn sub_text(a: *mem.Arena, v: json.Value, key: str) -> str
fn first_truthy(a: *mem.Arena, v: json.Value, k1: str, k2: str, k3: str) -> (json.Value, bool)
fn to_scim_user(a: *mem.Arena, user: json.Value, base_url: str) -> json.Value
fn id_or_self(a: *mem.Arena, m: json.Value) -> (json.Value, str)
fn to_scim_group(a: *mem.Arena, group: json.Value, base_url: str) -> json.Value
fn split_list(a: *mem.Arena, v: json.Value) -> []const str
fn js_trim(s: str) -> str
fn listed(names: []const str, key: str) -> bool
fn head_of(s: str) -> str
fn project_attributes(a: *mem.Arena, resource: json.Value, attributes: json.Value, excluded: json.Value) -> json.Value
fn trunc_f64(x: f64) -> f64
fn list_response(a: *mem.Arena, resources: []const json.Value, start_index: json.Value, has_start: bool, count: json.Value, has_count: bool, total_results: json.Value, has_total: bool) -> json.Value
fn scim_error(a: *mem.Arena, status: str, detail: str, scim_type: str) -> json.Value
fn one_array(a: *mem.Arena, s: str) -> json.Value
fn flag(a: *mem.Arena, supported: bool) -> json.Value
fn int_value(a: *mem.Arena, n: i64) -> json.Value
fn service_provider_config(a: *mem.Arena, base_url: str, documentation_uri: str) -> json.Value
fn resource_type(a: *mem.Arena, base_url: str, name: str, endpoint: str, schema: str) -> json.Value
fn resource_types(a: *mem.Arena, base_url: str) -> json.Value
fn sort_resources(a: *mem.Arena, resources: []const json.Value, sort_by: str, descending: bool) -> []const json.Value
```

SCIM 2.0 protocol core, RFC 7643 and RFC 7644 (L045), after Appdor's `src/identity/scim-protocol.js`, over JSON values: the filter grammar (`parse_filter`, `evaluate`: `eq ne co sw ew gt ge lt le pr`, `and`, `or`, `not`, groups and value paths, case-insensitive, with the reference's own error messages), `get_attribute`, the PATCH path grammar and `add`/`replace`/`remove` applied immutably (`parse_patch_path`, `apply_patch_op`, `apply_patch`), `project_attributes`, `list_response`, `scim_error`, the content-derived `resource_version`, `to_scim_user` and `to_scim_group`, `service_provider_config`, `resource_types` and `sort_resources`. Checked against Appdor's own functions over 594 cases on both hosts (D2349).

## Missing declarations

- [ ] `Token`
- [ ] `Node`
- [ ] `Parser`
- [ ] `Filter`
- [ ] `PatchPath`
- [ ] `Patched`
- [ ] `Page`
- [ ] `join`
- [ ] `sv`
- [ ] `is_sep`
- [ ] `lower`
- [ ] `same_lower`
- [ ] `tokenize`
- [ ] `fail`
- [ ] `new_node`
- [ ] `blank`
- [ ] `is_number_literal`
- [ ] `literal`
- [ ] `op_code`
- [ ] `peek_value_is`
- [ ] `peek_word_is`
- [ ] `parse_value_path`
- [ ] `parse_primary`
- [ ] `parse_and`
- [ ] `parse_or`
- [ ] `parse_filter`
- [ ] `find_key`
- [ ] `get_attribute`
- [ ] `number_of`
- [ ] `text_value`
- [ ] `to_number`
- [ ] `is_string`
- [ ] `strict_equal`
- [ ] `lowered_value`
- [ ] `less`
- [ ] `compare_values`
- [ ] `eval`
- [ ] `evaluate`
- [ ] `index_of`
- [ ] `last_index_of`
- [ ] `slice_of`
- [ ] `no_filter`
- [ ] `parse_patch_path`
- [ ] `object_of`
- [ ] `without`
- [ ] `set_path`
- [ ] `split_dots`
- [ ] `patch_failed`
- [ ] `apply_patch_op`
- [ ] `apply_patch`
- [ ] `escape_into`
- [ ] `s_of`
- [ ] `stringify`
- [ ] `hex_text`
- [ ] `resource_version`
- [ ] `truthy_text`
- [ ] `put_opt`
- [ ] `sub_text`
- [ ] `first_truthy`
- [ ] `to_scim_user`
- [ ] `id_or_self`
- [ ] `to_scim_group`
- [ ] `split_list`
- [ ] `js_trim`
- [ ] `listed`
- [ ] `head_of`
- [ ] `project_attributes`
- [ ] `trunc_f64`
- [ ] `list_response`
- [ ] `scim_error`
- [ ] `one_array`
- [ ] `flag`
- [ ] `int_value`
- [ ] `service_provider_config`
- [ ] `resource_type`
- [ ] `resource_types`
- [ ] `sort_resources`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/identity/scim.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/identity_scim/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 77.

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
