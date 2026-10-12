# x.api.openapi — 12 of 12 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/api/openapi.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/api/openapi.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Validation = struct { valid: bool, errors: []const str }

fn sv(s: str) -> json.Value
fn put(o: *ir.Obj, key: str, v: json.Value)
fn new_obj(a: *mem.Arena) -> ir.Obj
fn obj_of(a: *mem.Arena, v: json.Value) -> ir.Obj
fn or_text(info: json.Value, key: str, fallback: str) -> json.Value
fn create_spec(a: *mem.Arena, info: json.Value) -> json.Value
fn lower(a: *mem.Arena, s: str) -> str
fn add_path(a: *mem.Arena, spec: json.Value, path: str, method: str, operation: json.Value) -> json.Value
fn add_schema(a: *mem.Arena, spec: json.Value, name: str, schema: json.Value) -> json.Value
fn is_object(v: json.Value) -> bool
fn validate_spec(a: *mem.Arena, spec: json.Value) -> Validation
```

OpenAPI 3.0.3 document builder (L049), after Appdor's `src/api/openapi-builder.js`: `create_spec` (skeleton with `info`, empty `paths` and `components.schemas`, optional `servers`, `tags` and `securitySchemes`), `add_path`, `add_schema` and `validate_spec`; documents are JSON values and each call returns a new one. Checked against Appdor's own functions on both hosts (D2355).

## Missing declarations

- [ ] `Validation`
- [ ] `sv`
- [ ] `put`
- [ ] `new_obj`
- [ ] `obj_of`
- [ ] `or_text`
- [ ] `create_spec`
- [ ] `lower`
- [ ] `add_path`
- [ ] `add_schema`
- [ ] `is_object`
- [ ] `validate_spec`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/api/openapi.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/api_openapi/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 12.

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
