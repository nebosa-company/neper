# x.net.webhook — 24 of 24 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/net/webhook.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/net/webhook.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.crypto.mac` | source | `lib/e/crypto/mac.e` | 2 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Check = struct { valid: bool, reason: str, secret_index: i64 }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn hex_of(a: *mem.Arena, digest: []const u8) -> str
fn hmac_sha256(a: *mem.Arena, key: str, message: str) -> str
fn sign_body(a: *mem.Arena, body: str, secret: str) -> str
fn floor_text(a: *mem.Arena, x: f64) -> str
fn sign_body_v1(a: *mem.Arena, body: str, secret: str, ts: f64) -> str
fn signature_header_name() -> str
fn timestamp_header_name() -> str
fn legacy_signature_header_name() -> str

type Headers = struct { signature: str, timestamp: str }

fn signature_headers(a: *mem.Arena, body: str, secret: str, ts: f64) -> Headers
fn timing_safe_equal(x: str, y: str) -> bool
fn is_ws(c: u8) -> bool
fn trim(s: str) -> str
fn lower(a: *mem.Arena, s: str) -> str
fn js_number(text: str) -> (f64, bool)
fn abs_f64(x: f64) -> f64
fn refused(reason: str) -> Check
fn tolerance_text(a: *mem.Arena, tolerance: f64) -> str
fn verify_signature_headers(a: *mem.Arena, body: str, secret: str, signature: str, timestamp: str, tolerance: f64, now_ms: f64) -> Check
fn is_hex_digit(c: u8) -> bool
fn verify_v1(a: *mem.Arena, body: str, secret: str, header: str, tolerance: f64, now_ms: f64) -> Check
fn verify_v1_rotated(a: *mem.Arena, body: str, secrets: []const str, header: str, tolerance: f64, now_ms: f64) -> Check
```

Webhook signatures (L049), after Appdor's `src/webhooks/sign.js`: HMAC-SHA-256 over the body (`sign_body`, `sha256=<hex>`), the timestamped v1 envelope `t=<unix>,v1=<hex>` over `"{t}.{body}"` (`sign_body_v1`), the two-header form (`signature_headers`), verification with a replay window and a constant-time comparison (`verify_signature_headers`, `verify_v1`), and current-and-previous secret overlap (`verify_v1_rotated`). The clock is a parameter in milliseconds. Checked against Appdor's own functions over 649 cases with `x.net.authscheme`, `x.mcp.protocol` and `x.api.openapi` on both hosts (D2355).

## Missing declarations

- [ ] `Check`
- [ ] `join`
- [ ] `hex_of`
- [ ] `hmac_sha256`
- [ ] `sign_body`
- [ ] `floor_text`
- [ ] `sign_body_v1`
- [ ] `signature_header_name`
- [ ] `timestamp_header_name`
- [ ] `legacy_signature_header_name`
- [ ] `Headers`
- [ ] `signature_headers`
- [ ] `timing_safe_equal`
- [ ] `is_ws`
- [ ] `trim`
- [ ] `lower`
- [ ] `js_number`
- [ ] `abs_f64`
- [ ] `refused`
- [ ] `tolerance_text`
- [ ] `verify_signature_headers`
- [ ] `is_hex_digit`
- [ ] `verify_v1`
- [ ] `verify_v1_rotated`

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

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/net/webhook.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/net_webhook/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 24.

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
