# x.mcp.protocol — 35 of 35 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/mcp/protocol.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/mcp/protocol.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.fmt.encode` | source | `lib/e/fmt/encode.e` | 6 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Classified = struct { valid: bool, code: i64, reason: str, notification: bool, method: str, has_id: bool, id: json.Value }
type Prompt = struct { found: bool, valid: bool, message: str, description: str, text: str }
type Resource = struct { valid: bool, message: str, table_id: str, kind: str }
type Server = struct { initialized: bool, version: str, has_client: bool }
type Handled = struct { kind: u8, response: json.Value }
type Chunk = struct { messages: []const json.Value, errors: []const str, remainder: str }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn sv(s: str) -> json.Value
fn int_value(a: *mem.Arena, n: i64) -> json.Value
fn put(o: *ir.Obj, key: str, v: json.Value)
fn new_obj(a: *mem.Arena) -> ir.Obj
fn parse_error() -> i64
fn invalid_request() -> i64
fn method_not_found() -> i64
fn invalid_params() -> i64
fn internal_error() -> i64
fn supported_versions() -> [3]str
fn rpc_result(a: *mem.Arena, id: json.Value, result: json.Value) -> json.Value
fn rpc_error(a: *mem.Arena, id: json.Value, code: i64, message: str) -> json.Value
fn classify_message(message: json.Value) -> Classified
fn negotiate_version(requested: str) -> str
fn capabilities(a: *mem.Arena, resources: bool, with_prompts: bool, tool_list_changed: bool) -> json.Value
fn argument(a: *mem.Arena, name: str, description: str, required: bool) -> json.Value
fn prompt_entry(a: *mem.Arena, name: str, description: str, arguments: []const json.Value) -> json.Value
fn prompts(a: *mem.Arena) -> json.Value
fn arg_truthy(args: json.Value, name: str) -> bool
fn arg_text(a: *mem.Arena, args: json.Value, name: str) -> str
fn render_prompt(a: *mem.Arena, name: str, args: json.Value) -> Prompt
fn table_resource_uri(a: *mem.Arena, table_id: str) -> str
fn parse_resource_uri(a: *mem.Arena, uri: str) -> Resource
fn encode_stdio_message(a: *mem.Arena, message: json.Value) -> str
fn decode_stdio_chunk(a: *mem.Arena, buffer: str) -> Chunk
fn new_server() -> Server
fn pending(a: *mem.Arena, id: json.Value) -> json.Value
fn handle(a: *mem.Arena, s: *Server, message: json.Value, instructions: str) -> Handled
```

JSON-RPC 2.0 and the Model Context Protocol handshake (L049), after Appdor's `src/mcp/protocol.js`: `classify_message` (request, notification or the reference's refusal tokens), `negotiate_version` over the three supported protocol versions, `capabilities`, `rpc_result`/`rpc_error`, the three built-in `prompts` and `render_prompt`, the `appdor://table/<id>/schema|records` URIs, newline-delimited stdio framing (`encode_stdio_message`, `decode_stdio_chunk`) and the protocol-level server state machine (`handle`: initialize, ping, notifications, prompts, the initialize-first guard, argument checks; accessor-backed methods answer `delegate`). Checked against Appdor's own functions on both hosts (D2355).

## Missing declarations

- [ ] `Classified`
- [ ] `Prompt`
- [ ] `Resource`
- [ ] `Server`
- [ ] `Handled`
- [ ] `Chunk`
- [ ] `join`
- [ ] `sv`
- [ ] `int_value`
- [ ] `put`
- [ ] `new_obj`
- [ ] `parse_error`
- [ ] `invalid_request`
- [ ] `method_not_found`
- [ ] `invalid_params`
- [ ] `internal_error`
- [ ] `supported_versions`
- [ ] `rpc_result`
- [ ] `rpc_error`
- [ ] `classify_message`
- [ ] `negotiate_version`
- [ ] `capabilities`
- [ ] `argument`
- [ ] `prompt_entry`
- [ ] `prompts`
- [ ] `arg_truthy`
- [ ] `arg_text`
- [ ] `render_prompt`
- [ ] `table_resource_uri`
- [ ] `parse_resource_uri`
- [ ] `encode_stdio_message`
- [ ] `decode_stdio_chunk`
- [ ] `new_server`
- [ ] `pending`
- [ ] `handle`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/mcp/protocol.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/mcp_protocol/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 35.

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
