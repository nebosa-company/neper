# x.identity.oidc — 43 of 43 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/identity/oidc.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | `x.identity.jose` |

## Definition of done

Implement **exactly** the public fence below in `lib/e/identity/oidc.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.chain` | source | `lib/e/algo/chain.e` | 5 |
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.crypto.hash` | partial | `lib/e/crypto/hash.e` | 2 |
| `e.fmt.encode` | source | `lib/e/fmt/encode.e` | 6 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |
| `x.identity.jose` | source | missing | 6 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
fn default_skew_seconds() -> f64

type Config = struct { issuer: str, authorization_endpoint: str, token_endpoint: str, jwks_uri: str, has_userinfo: bool, userinfo_endpoint: str, has_end_session: bool, end_session_endpoint: str, scopes_supported: []const str, response_types_supported: []const str, id_token_signing_alg_values_supported: []const str, code_challenge_methods_supported: []const str }
type Discovery = struct { valid: bool, missing: []const str, config: Config }
type Pair = struct { key: str, value: str }
type AuthRequest = struct { client_id: str, redirect_uri: str, scope: str, state: str, nonce: str, code_challenge: str, prompt: str, login_hint: str, extra: []const Pair }
type Url = struct { valid: bool, missing: []const str, url: str }
type Callback = struct { valid: bool, error_code: str, has_description: bool, description: str, code: str, state: str }
type TokenRequest = struct { valid: bool, missing: []const str, url: str, body: str, has_authorization: bool, authorization: str }
type Expectations = struct { issuer: str, client_id: str, nonce: str, jwks: json.Value, now_ms: f64, has_max_age: bool, max_age_seconds: f64, has_skew: bool, skew_seconds: f64 }
type Validation = struct { valid: bool, message: str, claims: json.Value }
type Profile = struct { has_subject: bool, subject: str, has_email: bool, email: str, email_verified: bool, has_name: bool, name: str, has_given_name: bool, given_name: str, has_family_name: bool, family_name: str, groups: []const str, has_issuer: bool, issuer: str }
type Link = struct { action: str, reason: str }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn text_of(v: json.Value, key: str) -> (str, bool)
fn strings_or(a: *mem.Arena, v: json.Value, key: str, fallback: []const str) -> []const str
fn list_of(a: *mem.Arena, xs: []const str) -> []const str
fn parse_discovery(a: *mem.Arena, document: json.Value) -> Discovery
fn discovery_url(a: *mem.Arena, issuer: str) -> str
fn pkce_challenge(a: *mem.Arena, verifier: str) -> str
fn same_text(x: str, y: str) -> bool
fn verify_pkce(a: *mem.Arena, code_verifier: str, code_challenge: str) -> bool
fn create_pkce_pair(a: *mem.Arena, random: []const u8) -> Pair
fn form_hex(n: u8) -> u8
fn form_encode(a: *mem.Arena, s: str) -> str

type Params = struct { keys: []str, values: []str, count: usize }

fn params_new(a: *mem.Arena, capacity: usize) -> Params
fn params_set(p: *Params, key: str, value: str)
fn params_text(a: *mem.Arena, p: *const Params) -> str
fn missing_list(a: *mem.Arena, names: []const str, present: []const bool) -> []const str
fn build_authorization_url(a: *mem.Arena, config: Config, r: AuthRequest) -> Url
fn parse_callback(a: *mem.Arena, params: json.Value, expected_state: str) -> Callback
fn build_token_request(a: *mem.Arena, config: Config, client_id: str, client_secret: str, code: str, redirect_uri: str, code_verifier: str) -> TokenRequest
fn absent_or(a: *mem.Arena, v: json.Value, key: str) -> str
fn rejected(msg: str) -> Validation
fn number_claim(v: json.Value, key: str) -> (f64, bool)
fn floor_f64(x: f64) -> f64
fn validate_id_token(a: *mem.Arena, id_token: str, ex: Expectations) -> Validation
fn mapped(claims: json.Value, mapping: []const Pair, key: str, fallback: str) -> (str, bool)
fn truthy_text(claims: json.Value, name: str) -> (str, bool)
fn profile_from_claims(a: *mem.Arena, claims: json.Value, mapping: []const Pair) -> Profile
fn lower_ascii(a: *mem.Arena, s: str) -> str
fn link_policy(a: *mem.Arena, p: Profile, verified_domains: []const str, existing_account: bool, allow_unverified_email_link: bool) -> Link
fn build_logout_url(a: *mem.Arena, config: Config, id_token_hint: str, post_logout_redirect_uri: str, state: str) -> Url
```

OpenID Connect relying party with PKCE (L045), after Appdor's `src/identity/oidc.js`: `parse_discovery` and `discovery_url`, `pkce_challenge`/`verify_pkce`/`create_pkce_pair`, `build_authorization_url` and `build_token_request` (values, form-urlencoded in the reference's parameter order, `client_secret_basic` when a secret is given), `parse_callback`, `validate_id_token` in the order of OpenID Connect Core 3.1.3.7 (signature, issuer, audience and `azp`, time, nonce, `max_age`), `profile_from_claims`, `link_policy` and `build_logout_url`. Checked against Appdor's own functions over 536 cases on both hosts (D2348).

## Missing declarations

- [ ] `default_skew_seconds`
- [ ] `Config`
- [ ] `Discovery`
- [ ] `Pair`
- [ ] `AuthRequest`
- [ ] `Url`
- [ ] `Callback`
- [ ] `TokenRequest`
- [ ] `Expectations`
- [ ] `Validation`
- [ ] `Profile`
- [ ] `Link`
- [ ] `join`
- [ ] `text_of`
- [ ] `strings_or`
- [ ] `list_of`
- [ ] `parse_discovery`
- [ ] `discovery_url`
- [ ] `pkce_challenge`
- [ ] `same_text`
- [ ] `verify_pkce`
- [ ] `create_pkce_pair`
- [ ] `form_hex`
- [ ] `form_encode`
- [ ] `Params`
- [ ] `params_new`
- [ ] `params_set`
- [ ] `params_text`
- [ ] `missing_list`
- [ ] `build_authorization_url`
- [ ] `parse_callback`
- [ ] `build_token_request`
- [ ] `absent_or`
- [ ] `rejected`
- [ ] `number_claim`
- [ ] `floor_f64`
- [ ] `validate_id_token`
- [ ] `mapped`
- [ ] `truthy_text`
- [ ] `profile_from_claims`
- [ ] `lower_ascii`
- [ ] `link_policy`
- [ ] `build_logout_url`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/identity/oidc.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/identity_oidc/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 43.

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
