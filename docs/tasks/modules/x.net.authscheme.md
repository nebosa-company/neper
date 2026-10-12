# x.net.authscheme — 49 of 49 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/net/authscheme.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | `x.identity.jose`, `x.net.webhook` |

## Definition of done

Implement **exactly** the public fence below in `lib/e/net/authscheme.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.chain` | source | `lib/e/algo/chain.e` | 5 |
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.fmt.encode` | source | `lib/e/fmt/encode.e` | 6 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |
| `x.identity.jose` | source | missing | 6 |
| `x.net.webhook` | source | missing | 6 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Applied = struct { request: json.Value, message: str, failed: bool }
type Refresh = struct { present: bool, failed: bool, message: str, request: json.Value }
type Token = struct { valid: bool, message: str, value: json.Value }
type Url = struct { valid: bool, message: str, value: str }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn sv(s: str) -> json.Value
fn skew_ms() -> f64
fn js_string(a: *mem.Arena, v: json.Value) -> str
fn or_text(a: *mem.Arena, obj: json.Value, key: str, fallback: str) -> str
fn present(obj: json.Value, key: str) -> bool
fn text_member(a: *mem.Arena, obj: json.Value, key: str) -> str
fn put(o: *ir.Obj, key: str, v: json.Value)
fn new_obj(a: *mem.Arena) -> ir.Obj
fn obj_of(a: *mem.Arena, v: json.Value) -> ir.Obj
fn missing(a: *mem.Arena, scheme: str, field: str) -> str
fn json_quote(a: *mem.Arena, s: str) -> str
fn is_tchar(c: u8) -> bool
fn header_problem(a: *mem.Arena, name: str, value: str, scheme: str) -> str
fn base64(a: *mem.Arena, s: str) -> str
fn uri_component(a: *mem.Arena, s: str) -> str
fn encode_form(a: *mem.Arena, keys: []const str, values: []const json.Value, count: usize) -> str
fn body_text(a: *mem.Arena, request: json.Value) -> str
fn replace_first(a: *mem.Arena, s: str, needle: str, with: str) -> str
fn path_of(url: str) -> str
fn host_of(a: *mem.Arena, url: str) -> str
fn lower(a: *mem.Arena, s: str) -> str
fn infer_aws_service(a: *mem.Arena, url: str) -> str
fn known_scheme(t: str) -> bool
fn with_error(a: *mem.Arena, request: json.Value, message: str) -> json.Value
fn apply_auth(a: *mem.Arena, connection: json.Value, request: json.Value, now_ms: f64) -> json.Value
fn connection_value(connection: json.Value, key: str) -> json.Value
fn upper(a: *mem.Arena, s: str) -> str
fn timestamp_text(a: *mem.Arena, connection: json.Value, now_ms: f64) -> str
fn number_member(connection: json.Value, key: str) -> (f64, bool)
fn needs_refresh(a: *mem.Arena, connection: json.Value, now_ms: f64) -> bool
fn refresh_failed(message: str) -> Refresh
fn form_request(a: *mem.Arena, url: str, headers: json.Value, body: str) -> json.Value
fn build_refresh(a: *mem.Arena, connection: json.Value) -> Refresh
fn parse_token_response(a: *mem.Arena, response: json.Value, connection: json.Value, now_ms: f64, oidc: bool) -> Token
fn is_secret_field(t: str, key: str) -> bool
fn redact_connection(a: *mem.Arena, connection: json.Value) -> json.Value

type Inbound = struct { valid: bool, reason: str }

fn verify_inbound(a: *mem.Arena, connection: json.Value, headers: json.Value, body: json.Value, has_body: bool, now_ms: f64) -> Inbound
fn form_component(a: *mem.Arena, s: str) -> str
fn form_decode(a: *mem.Arena, s: str) -> str
fn hex_val(c: u8) -> i32
fn path_encode(a: *mem.Arena, s: str) -> str
fn build_authorize_url(a: *mem.Arena, connection: json.Value, redirect_uri: str, scope: str, state: str, code_challenge: str, prompt: str) -> Url
fn set_param(names: []str, vals: []str, count: *usize, key: str, value: str)
```

Outbound authentication schemes (L049), after Appdor's `src/auth-schemes/index.js`: fourteen schemes (none, basic, bearer, apiKey, jwt, oauth2, oidc, saml-bearer, hmac, awsSigV4, mtls, session, custom, webhook) turn a stored connection into the headers, query, transport hints and URL a request needs (`apply_auth`, with the reference's refusal tokens as an `error` member), plus `needs_refresh`, `build_refresh` and `parse_token_response` for token renewal as a request and an answer reader, `redact_connection`, `verify_inbound` (HMAC callers) and `build_authorize_url`. No I/O; clocks are parameters. Checked against Appdor's own functions over 649 cases on both hosts (D2355).

## Missing declarations

- [ ] `Applied`
- [ ] `Refresh`
- [ ] `Token`
- [ ] `Url`
- [ ] `join`
- [ ] `sv`
- [ ] `skew_ms`
- [ ] `js_string`
- [ ] `or_text`
- [ ] `present`
- [ ] `text_member`
- [ ] `put`
- [ ] `new_obj`
- [ ] `obj_of`
- [ ] `missing`
- [ ] `json_quote`
- [ ] `is_tchar`
- [ ] `header_problem`
- [ ] `base64`
- [ ] `uri_component`
- [ ] `encode_form`
- [ ] `body_text`
- [ ] `replace_first`
- [ ] `path_of`
- [ ] `host_of`
- [ ] `lower`
- [ ] `infer_aws_service`
- [ ] `known_scheme`
- [ ] `with_error`
- [ ] `apply_auth`
- [ ] `connection_value`
- [ ] `upper`
- [ ] `timestamp_text`
- [ ] `number_member`
- [ ] `needs_refresh`
- [ ] `refresh_failed`
- [ ] `form_request`
- [ ] `build_refresh`
- [ ] `parse_token_response`
- [ ] `is_secret_field`
- [ ] `redact_connection`
- [ ] `Inbound`
- [ ] `verify_inbound`
- [ ] `form_component`
- [ ] `form_decode`
- [ ] `hex_val`
- [ ] `path_encode`
- [ ] `build_authorize_url`
- [ ] `set_param`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/net/auth.e`
- `lib/e/net/auth.linux.e`
- `lib/e/net/auth.windows.e`
- `lib/e/net/balance.e`
- `lib/e/net/cidr.e`
- `lib/e/net/coap.e`
- `lib/e/net/dns.e`
- `lib/e/net/ftp.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/net/authscheme.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/net_authscheme/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 49.

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
