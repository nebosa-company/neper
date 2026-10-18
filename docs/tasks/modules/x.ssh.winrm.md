# x.ssh.winrm — 7 of 7 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/ssh/winrm.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | `x.ssh.args` |

## Definition of done

Implement **exactly** the public fence below in `lib/e/ssh/winrm.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.bytes` | partial | `lib/e/bytes.e` | 1 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |
| `e.text.utf8` | source | `lib/e/text/utf8.e` | 2 |
| `x.ssh.args` | source | missing | 6 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
fn join(a: *mem.Arena, x: str, y: str) -> str
fn https_port() -> str
fn http_port() -> str
fn password_env() -> str
fn encode_command(a: *mem.Arena, script: str) -> str
fn driver_script(a: *mem.Arena, address: str, vars: json.Value, command: str) -> str
fn winrm_args(a: *mem.Arena, address: str, vars: json.Value, command: str) -> []const str
```

The PowerShell command line a Windows host's variables describe (L048), after Petcow's `transport/winrm.rs`: `winrm_args` answers `-NoProfile -NonInteractive -EncodedCommand <base64>` whose program is the driver script `driver_script` writes, TLS on port 5986 unless `winrm_allow_http` asks for 5985 (an explicit `winrm_port`, `ansible_port` or `port` wins and keeps TLS), the CA and CN checks waived one at a time by `winrm_skip_ca_check` and `winrm_skip_cn_check`, the password never an argument (a named user reads `$env:PETCOW_WINRM_PASSWORD` in the session and throws when it is unset, no user passes no credential), `-Authentication` from `winrm_auth`, and the payload as UTF-16LE base64 (`encode_command`). The spawn is host code. Checked against Petcow's own functions over 79 cases on Windows (D3400).

## Missing declarations

- [ ] `join`
- [ ] `https_port`
- [ ] `http_port`
- [ ] `password_env`
- [ ] `encode_command`
- [ ] `driver_script`
- [ ] `winrm_args`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/ssh/winrm.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/ssh_winrm/src/main.e` that prints one fixed line on success, registered in both runners.
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
