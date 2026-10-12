# x.identity.saml — 58 of 58 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/identity/saml.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | `x.identity.jose`, `x.identity.oidc`, `x.identity.xml` |

## Definition of done

Implement **exactly** the public fence below in `lib/e/identity/saml.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.formula` | source | `lib/e/algo/formula.e` | 4 |
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.crypto.hash` | partial | `lib/e/crypto/hash.e` | 2 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |
| `x.identity.jose` | source | missing | 6 |
| `x.identity.oidc` | source | missing | 6 |
| `x.identity.xml` | source | missing | 6 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Key = struct { has: bool, n: str, e: str }
type Signed = struct { valid: bool, message: str, id: str, assertion: usize, signed_element: str }
type Assertion = struct { present: bool, id: str, issuer: str, has_name_id: bool, name_id: str, name_id_format: str, session_index: str, authn_instant: str, not_before: str, not_on_or_after: str, audiences: []const str, recipient: str, confirmation_not_on_or_after: str, confirmation_in_response_to: str, attr_names: []const str, attr_values: []const []const str }
type Response = struct { valid: bool, message: str, doc: xml.Doc, id: str, in_response_to: str, destination: str, issue_instant: str, issuer: str, status_present: bool, status_has_value: bool, status_code: str, status_message: str, assertion: Assertion }
type Config = struct { issuer: str, audience: str, acs_url: str, key: Key, expected_in_response_to: str, now: f64, has_skew: bool, skew_ms: f64, seen: []const str }
type Validation = struct { valid: bool, message: str, detail: str, has_detail: bool, assertion_id: str, signed_element: str, assertion: Assertion, expires_at: f64, has_expiry: bool }
type Request = struct { valid: bool, missing: []const str, binding: str, xml: str, form_action: str, saml_request: str, relay_state: str, url: str }
type ReplayCache = struct { ids: []str, expiries: []f64, count: usize }

fn join(a: *mem.Arena, x: str, y: str) -> str
fn ns_protocol() -> str
fn ns_assertion() -> str
fn ns_signature() -> str
fn ns_metadata() -> str
fn status_success() -> str
fn binding_post() -> str
fn binding_redirect() -> str
fn nameid_email() -> str
fn to_base64(a: *mem.Arena, bytes: []const u8) -> str
fn from_base64(a: *mem.Arena, s: str) -> []u8
fn xml_escape(a: *mem.Arena, s: str) -> str
fn deflate_raw_stored(a: *mem.Arena, bytes: []const u8) -> []u8
fn saml_id(a: *mem.Arena, seed: str) -> str
fn missing_names(a: *mem.Arena, names: []const str, present: []const bool) -> []const str
fn build_authn_request(a: *mem.Arena, id: str, issue_instant: str, destination: str, issuer: str, acs_url: str, name_id_format: str, force_authn: bool, relay_state: str, binding: str) -> Request
fn split_words(a: *mem.Arena, s: str) -> []const str
fn strip_ws(a: *mem.Arena, s: str) -> str
fn trimmed(s: str) -> str
fn attr_or_undefined(a: *mem.Arena, d: xml.Doc, at: usize, has: bool, name: str) -> str
fn prefixes_of(a: *mem.Arena, d: xml.Doc, at: usize) -> []const str
fn failed(msg: str) -> Signed
fn verify_xml_signature(a: *mem.Arena, d: xml.Doc, signature: usize, has_signature: bool, key: Key) -> Signed
fn extract_signed_assertion(a: *mem.Arena, d: xml.Doc, key: Key) -> Signed
fn empty_assertion() -> Assertion
fn attr_text(d: xml.Doc, at: usize, name: str) -> str
fn bad_response(a: *mem.Arena, message: str) -> Response
fn starts_with_markup(s: str) -> bool
fn parse_saml_response(a: *mem.Arena, encoded: str) -> Response
fn days_from_civil(y_in: i64, m: i64, d: i64) -> i64
fn digits(s: str, at: usize, n: usize) -> (i64, bool)
fn parse_instant(s: str) -> (f64, bool)
fn none_validation(msg: str) -> Validation
fn contains_text(xs: []const str, v: str) -> bool
fn join_list(a: *mem.Arena, xs: []const str) -> str
fn validate_saml_response(a: *mem.Arena, parsed: Response, c: Config) -> Validation
fn new_replay_cache(a: *mem.Arena, capacity: usize) -> ReplayCache
fn replay_prune(c: *ReplayCache, now: f64)
fn replay_has(c: *ReplayCache, id: str, now: f64) -> bool
fn replay_remember(c: *ReplayCache, id: str, expires_at: f64, has_expiry: bool, now: f64)
fn replay_size(c: *ReplayCache, now: f64) -> usize

type Length = struct { length: usize, offset: usize, good: bool }

fn read_length(der: []const u8, index: usize) -> Length

type RsaKey = struct { found: bool, modulus: []const u8, exponent: []const u8 }

fn extract_rsa_public_key(der: []const u8) -> RsaKey
fn certificate_to_jwk(a: *mem.Arena, certificate: str) -> (Key, bool)
fn starts_dashes(s: str, at: usize) -> bool
fn build_sp_metadata(a: *mem.Arena, entity_id: str, acs_url: str, slo_url: str, name_id_format: str, want_signed: bool) -> (str, []const str)

type IdpMetadata = struct { valid: bool, message: str, entity_id: str, sso_url: str, post_url: str, certificates: []const str }

fn parse_idp_metadata(a: *mem.Arena, source: str) -> IdpMetadata
```

SAML 2.0 service provider, Web Browser SSO (L045), after Appdor's `src/identity/saml.js`: `build_authn_request` (HTTP-Redirect with stored-block deflate, or HTTP-POST), XML-DSig verification (`verify_xml_signature`: RSA-SHA256 over the canonical SignedInfo, SHA-256 digest of the referenced element with the enveloped-signature transform, SHA-1 refused by name), the wrapping defence (`extract_signed_assertion`: one Assertion, covered by the signature's Reference or an ancestor), `parse_saml_response`, `validate_saml_response` in the reference's order of checks (signature, status, issuer, conditions, audience, subject confirmation, `InResponseTo`, destination, replay), a replay cache, `certificate_to_jwk`, `build_sp_metadata` and `parse_idp_metadata`. There is no switch that turns verification off. Checked against Appdor's own functions over 416 cases, with responses really signed with RSA-SHA256, on both hosts (D2350).

## Missing declarations

- [ ] `Key`
- [ ] `Signed`
- [ ] `Assertion`
- [ ] `Response`
- [ ] `Config`
- [ ] `Validation`
- [ ] `Request`
- [ ] `ReplayCache`
- [ ] `join`
- [ ] `ns_protocol`
- [ ] `ns_assertion`
- [ ] `ns_signature`
- [ ] `ns_metadata`
- [ ] `status_success`
- [ ] `binding_post`
- [ ] `binding_redirect`
- [ ] `nameid_email`
- [ ] `to_base64`
- [ ] `from_base64`
- [ ] `xml_escape`
- [ ] `deflate_raw_stored`
- [ ] `saml_id`
- [ ] `missing_names`
- [ ] `build_authn_request`
- [ ] `split_words`
- [ ] `strip_ws`
- [ ] `trimmed`
- [ ] `attr_or_undefined`
- [ ] `prefixes_of`
- [ ] `failed`
- [ ] `verify_xml_signature`
- [ ] `extract_signed_assertion`
- [ ] `empty_assertion`
- [ ] `attr_text`
- [ ] `bad_response`
- [ ] `starts_with_markup`
- [ ] `parse_saml_response`
- [ ] `days_from_civil`
- [ ] `digits`
- [ ] `parse_instant`
- [ ] `none_validation`
- [ ] `contains_text`
- [ ] `join_list`
- [ ] `validate_saml_response`
- [ ] `new_replay_cache`
- [ ] `replay_prune`
- [ ] `replay_has`
- [ ] `replay_remember`
- [ ] `replay_size`
- [ ] `Length`
- [ ] `read_length`
- [ ] `RsaKey`
- [ ] `extract_rsa_public_key`
- [ ] `certificate_to_jwk`
- [ ] `starts_dashes`
- [ ] `build_sp_metadata`
- [ ] `IdpMetadata`
- [ ] `parse_idp_metadata`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/identity/saml.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/identity_saml/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 58.

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
