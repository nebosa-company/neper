# x.cloud.awssig — 38 of 38 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/cloud/awssig.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/cloud/awssig.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.algo.sync` | source | `lib/e/algo/sync.e` | 5 |
| `e.bytes` | partial | `lib/e/bytes.e` | 1 |
| `e.crypto.hash` | partial | `lib/e/crypto/hash.e` | 2 |
| `e.crypto.mac` | source | `lib/e/crypto/mac.e` | 2 |
| `e.data.list` | source | `lib/e/data/list.e` | 2 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |
| `e.text.utf8` | source | `lib/e/text/utf8.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
fn empty_hash() -> str
fn unsigned_payload() -> str
type Header = struct { name: str, value: str }
fn concat_all(a: *mem.Arena, parts: []const str, sep: str) -> str
fn cat2(a: *mem.Arena, x: str, y: str) -> str
fn lower_ascii_text(a: *mem.Arena, s: str) -> str
fn eq_fold(x: str, y: str) -> bool
fn hex_text(a: *mem.Arena, b: []const u8) -> str
fn sha256_hex(a: *mem.Arena, data: []const u8) -> str
fn quote(a: *mem.Arena, s: str, safe: str) -> str
fn remove_dot_segments(a: *mem.Arena, url: str) -> str
fn normalize_url_path(a: *mem.Arena, path: str) -> str
fn py_space(u: u32) -> bool
fn trimall(a: *mem.Arena, s: str) -> str
type Url = struct { scheme: str, host: str, port: i64, path: str, query: str, ipv6: bool }
fn url_parts(a: *mem.Arena, url: str) -> Url
fn host_from_url(a: *mem.Arena, url: str) -> str
type Pair = struct { key: str, value: str }
fn pair_less(x: Pair, y: Pair) -> bool
fn sort_pairs(p: []Pair)
fn pairs_text(a: *mem.Arena, p: []const Pair) -> str
fn canonical_query(a: *mem.Arena, params: []const Pair, have_params: bool, url_query: str) -> str
fn blacklisted(lname: str) -> bool
type Signed = struct { canonical_request: str, string_to_sign: str, signature: str, authorization: str, headers: []const Header }
fn find_header(h: []const Header, name: str) -> (str, bool)
fn push_header(l: *list.List[Header], name: str, value: str)
fn headers_to_sign(a: *mem.Arena, headers: []const Header, url: str) -> ([]const Pair, str)
fn canonical_headers_text(a: *mem.Arena, p: []const Pair) -> str
fn hmac(a: *mem.Arena, key: []const u8, message: str) -> [32]u8
fn signature(a: *mem.Arena, secret: str, date: str, region: str, service: str, to_sign: str) -> str
fn http_date(a: *mem.Arena, timestamp: str) -> str
type Request = struct  { method: str, url: str, headers: []const Header, params: []const Pair, have_params: bool, body: str, region: str, service: str, access_key: str, secret_key: str, token: str, timestamp: str, s3: bool, payload_signing: bool, streaming_input: bool }
fn sign_request(a: *mem.Arena, r: Request) -> Signed
fn text_of(v: json.Value, key: str) -> str
fn flag_of(v: json.Value, key: str, default_value: bool) -> bool
fn pairs_of(a: *mem.Arena, v: json.Value) -> []const Pair
fn headers_of(a: *mem.Arena, v: json.Value) -> []const Header
fn sign_json(a: *mem.Arena, v: json.Value) -> json.Value
```

## Missing declarations

- [ ] `empty_hash`
- [ ] `unsigned_payload`
- [ ] `Header`
- [ ] `concat_all`
- [ ] `cat2`
- [ ] `lower_ascii_text`
- [ ] `eq_fold`
- [ ] `hex_text`
- [ ] `sha256_hex`
- [ ] `quote`
- [ ] `remove_dot_segments`
- [ ] `normalize_url_path`
- [ ] `py_space`
- [ ] `trimall`
- [ ] `Url`
- [ ] `url_parts`
- [ ] `host_from_url`
- [ ] `Pair`
- [ ] `pair_less`
- [ ] `sort_pairs`
- [ ] `pairs_text`
- [ ] `canonical_query`
- [ ] `blacklisted`
- [ ] `Signed`
- [ ] `find_header`
- [ ] `push_header`
- [ ] `headers_to_sign`
- [ ] `canonical_headers_text`
- [ ] `hmac`
- [ ] `signature`
- [ ] `http_date`
- [ ] `Request`
- [ ] `sign_request`
- [ ] `text_of`
- [ ] `flag_of`
- [ ] `pairs_of`
- [ ] `headers_of`
- [ ] `sign_json`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/cloud/awssig.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/cloud_awssig/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 38.

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
