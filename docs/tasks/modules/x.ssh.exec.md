# x.ssh.exec — 16 of 16 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/ssh/exec.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/ssh/exec.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
fn join(a: *mem.Arena, x: str, y: str) -> str
fn resource_error(a: *mem.Arena, logical_id: str, message: str) -> str
fn ssm_document(powershell: bool) -> str
fn ssm_instance_id(a: *mem.Arena, host: str, vars: json.Value) -> (str, bool, str)
fn object_members(v: json.Value) -> []const json.Member
fn ssm_is_terminal(status: str) -> bool

type Sent = struct { good: bool, has_id: bool, id: str, failure: str }
type Invocation = struct { kind: i32, has_status: bool, status: str, code: i32, out: str, err_out: str, failure: str }
type Client = struct { ctx: *void, send: fn(*void, str, str, str) -> Sent, invoke: fn(*void, str, str) -> Invocation }
type Outcome = struct { good: bool, message: str, exit_code: i32, stdout: str, stderr: str, succeeded: bool, polls: usize }

fn failed(message: str, polls: usize) -> Outcome
fn ssm_run(a: *mem.Arena, c: *const Client, host: str, vars: json.Value, command: str, powershell: bool, max_polls: usize) -> Outcome
fn local_argv(a: *mem.Arena, command: str, powershell: bool) -> []const str
fn local_error(a: *mem.Arena, host: str, powershell: bool, message: str) -> str
fn winrm_program(windows: bool) -> str
fn winrm_error(a: *mem.Arena, host: str, program: str, not_found: bool, message: str) -> str
```

The SSM and local transports' decisions (L048), after Petcow's `transport/ssm.rs` and `transport/local.rs`. `ssm_run` is the send-then-poll loop with the two SDK calls injected through a `Client`: the instance id is the host's `resource_id` when it has that variable at all (a non-string value is "no id") else `instance_id`; the document is `AWS-RunShellScript` or `AWS-RunPowerShellScript`; an invocation that does not exist yet is waited out, any other error ends the run with `ssm get_command_invocation: <error>`, a terminal status (`Success`, `Cancelled`, `Failed`, `TimedOut`) answers with the exit code and output and `succeeded` only for `Success`, and running out of polls is an error naming the count. `local_argv` is `sh -c` or `powershell -NoProfile -NonInteractive -Command`; `winrm_program` and the error texts of a failed spawn are here too. The SDK calls, the poll interval and the spawn are host code. Checked against Petcow's own functions over 98 cases on Windows (D3400).

## Missing declarations

- [ ] `join`
- [ ] `resource_error`
- [ ] `ssm_document`
- [ ] `ssm_instance_id`
- [ ] `object_members`
- [ ] `ssm_is_terminal`
- [ ] `Sent`
- [ ] `Invocation`
- [ ] `Client`
- [ ] `Outcome`
- [ ] `failed`
- [ ] `ssm_run`
- [ ] `local_argv`
- [ ] `local_error`
- [ ] `winrm_program`
- [ ] `winrm_error`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/ssh/exec.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/ssh_exec/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 16.

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
