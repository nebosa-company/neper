# x.migrate.typemaps — 5 of 5 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/migrate/typemaps.e` |
| plan row | layer 3, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/migrate/typemaps.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 3 may depend on layers [0, 1, 2, 3].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
fn monday_type(key: str) -> (str, bool)
fn airtable_type(key: str) -> (str, bool)
fn quickbase_type(key: str) -> (str, bool)
fn airtable_view_type(key: str) -> str
fn monday_view_type(key: str) -> str
```

The importer type maps (L044), generated from Appdor's `src/importers` by `scripts/typemaps_gen.mjs`: `monday_type`, `airtable_type` and `quickbase_type` map a source field type to an Appdor field type (false when unlisted, where the importer falls back to text), and `monday_view_type` and `airtable_view_type` map a view type, anything unlisted being a `grid`. Checked against the maps themselves on both hosts (D2347).

## Missing declarations

- [ ] `monday_type`
- [ ] `airtable_type`
- [ ] `quickbase_type`
- [ ] `airtable_view_type`
- [ ] `monday_view_type`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/migrate/typemaps.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/migrate_typemaps/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 5.

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
