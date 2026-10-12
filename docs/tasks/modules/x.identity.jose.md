# x.identity.jose — 12 of 12 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/identity/jose.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/identity/jose.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.crypto.sign` | partial | `lib/e/crypto/sign.e` | 2 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Decoded = struct { valid: bool, message: str, header: json.Value, payload: json.Value, signature: str, signing_input: str }

fn b64_index(c: u8) -> i32
fn base64url_decode(a: *mem.Arena, s: str) -> []u8
fn base64url_encode(a: *mem.Arena, bytes: []const u8) -> str
fn failed(msg: str) -> Decoded
fn decode_jwt(a: *mem.Arena, token: str) -> Decoded
fn verify_rs256(a: *mem.Arena, message: []const u8, signature: []const u8, n: str, e: str) -> bool
fn text_of(v: json.Value, key: str) -> (str, bool)
fn js_string(a: *mem.Arena, v: json.Value) -> str
fn lowered_is_none(s: str) -> bool
fn verify_jwt_signature(a: *mem.Arena, token: str, jwk: json.Value, has_jwk: bool) -> (bool, str)
fn select_jwk(jwks: json.Value, header: json.Value) -> (json.Value, bool)
```

The JOSE subset an OpenID Connect relying party needs (L045), after Appdor's `src/identity/jose.js`: lenient base64url (`base64url_decode`, `base64url_encode`), `decode_jwt` without verification, `verify_rs256` over `e.crypto.sign`'s PKCS#1 v1.5 check, `verify_jwt_signature` (`alg: none`, PSS and the EC families refused by name) and `select_jwk`. A verifier only. Checked with `x.identity.oidc` against Appdor's own functions over 536 cases with real RS256 signatures on both hosts (D2348).

## Missing declarations

- [ ] `Decoded`
- [ ] `b64_index`
- [ ] `base64url_decode`
- [ ] `base64url_encode`
- [ ] `failed`
- [ ] `decode_jwt`
- [ ] `verify_rs256`
- [ ] `text_of`
- [ ] `js_string`
- [ ] `lowered_is_none`
- [ ] `verify_jwt_signature`
- [ ] `select_jwk`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/identity/jose.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/identity_jose/src/main.e` that prints one fixed line on success, registered in both runners.
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
