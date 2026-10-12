# x.ssh.args — 7 of 7 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/ssh/args.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/ssh/args.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
fn join(a: *mem.Arena, x: str, y: str) -> str
fn trimmed_empty(s: str) -> bool
fn host_str(vars: json.Value, keys: []const str) -> (str, bool)
fn lower_trim(a: *mem.Arena, s: str) -> str
fn host_bool(a: *mem.Arena, vars: json.Value, key: str) -> (bool, bool)
fn remote_command(a: *mem.Arena, command: str, powershell: bool) -> str
fn ssh_args(a: *mem.Arena, address: str, vars: json.Value, command: str, powershell: bool) -> []const str
```

The OpenSSH command line a host's variables describe (L048), after Petcow's `transport/ssh.rs`: `ssh_args` builds key-based, never-prompting arguments (`BatchMode=yes`, a 15-second connect timeout, host-key checking on unless the host says otherwise, an optional pinned known-hosts file, identity file with `IdentitiesOnly=yes`, port, `user@address`) and the remote command, wrapped for PowerShell on a Windows target; host variables answer to PetCow's and Ansible's names. Checked against Petcow's own Rust with `x.cloud.aws` on both hosts (D2354).

## Missing declarations

- [ ] `join`
- [ ] `trimmed_empty`
- [ ] `host_str`
- [ ] `lower_trim`
- [ ] `host_bool`
- [ ] `remote_command`
- [ ] `ssh_args`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/ssh/args.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/ssh_args/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 7.

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
