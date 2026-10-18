# x.ssh.transport — 12 of 12 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/ssh/transport.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/ssh/transport.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.data.list` | source | `lib/e/data/list.e` | 2 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |
| `e.text.utf8` | source | `lib/e/text/utf8.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Factory = struct { ctx: *void, build: fn(*void, str) -> (bool, str) }
type Table = struct { a: *mem.Arena, default_kind: str, built: list.List[str], factory: Factory }
type Resolution = struct { kind: str, good: bool, failure: str }

fn new_table(a: *mem.Arena, default_kind: str, factory: Factory) -> Table
fn name(t: *const Table) -> str
fn is_white(c: u32) -> bool
fn trim(s: str) -> str
fn kind_for(default_kind: str, vars: json.Value) -> str
fn members_of(v: json.Value) -> ([]const json.Member, bool)
fn is_built(t: *const Table, kind: str) -> bool
fn cat(a: *mem.Arena, x: str, y: str) -> str
fn resolve(t: *Table, host: str, vars: json.Value) -> Resolution
```

Per-host transport selection (L048), after Petcow's `transport/mod.rs` `PerHostTransport`: `kind_for` reads a host's `transport` variable (a string with something in it, trimmed as Rust's `str::trim` does) and falls back to the run's default; `resolve` builds that kind through an injected `Factory` the first time a host asks for it and keeps it, so a run over three WinRM hosts never builds the SSM transport and five hosts on one kind build it once, and a factory failure is reported with the host's name and the kind. A failed kind is not kept. Running a command is host code. Checked against Petcow's own selection logic over 40 mixed-estate runs on Windows (D2922).

## Missing declarations

- [ ] `Factory`
- [ ] `Table`
- [ ] `Resolution`
- [ ] `new_table`
- [ ] `name`
- [ ] `is_white`
- [ ] `trim`
- [ ] `kind_for`
- [ ] `members_of`
- [ ] `is_built`
- [ ] `cat`
- [ ] `resolve`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/ssh/transport.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/ssh_transport/src/main.e` that prints one fixed line on success, registered in both runners.
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
