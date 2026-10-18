# x.elastic.rest — 32 of 32 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/elastic/rest.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/elastic/rest.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
error TooSmall
error Invalid
type Meta = struct { id: str, index: str, if_seq_no: i64, if_primary_term: i64, retry_on_conflict: i64, routing: str, version: i64, version_type: str, pipeline: str }
type Param = struct { name: str, value: str }
type BulkItem = struct { op: str, index: str, id: str, status: i64, result: str, error_type: str, error_reason: str, version: i64 }
type BulkResult = struct { took: i64, errors: bool, items: []const BulkItem }
type Hit = struct { index: str, id: str, score: f64, has_score: bool, source: json.Value }
type SearchResult = struct { took: i64, timed_out: bool, total: i64, relation: str, hits: []const Hit, scroll_id: str, shards_failed: i64 }
type ErrorInfo = struct { status: i64, kind: str, reason: str, root_kind: str, root_reason: str }

fn meta() -> Meta
fn put_text(dst: []u8, at: *usize, text: str) -> err
fn put_byte(dst: []u8, at: *usize, b: u8) -> err
fn hex_upper(v: u8) -> u8
fn plain(c: u8, safe: str) -> bool
fn quote(dst: []u8, at: *usize, value: str, safe: str) -> err
fn path(dst: []u8, segments: []const str) -> (usize, err)
fn query(dst: []u8, params: []const Param) -> (usize, err)
fn put_decimal(dst: []u8, at: *usize, value: i64) -> err
fn put_string(dst: []u8, at: *usize, value: str) -> err
fn put_key_string(dst: []u8, at: *usize, first: *bool, key: str, value: str) -> err
fn put_key_number(dst: []u8, at: *usize, first: *bool, key: str, value: i64) -> err
fn bulk_meta(dst: []u8, op: str, m: *const Meta) -> (usize, err)
fn bulk_line(dst: []u8, op: str, m: *const Meta, source: str) -> (usize, err)
fn member(v: json.Value, key: str) -> (json.Value, bool)
fn text_of(v: json.Value, key: str) -> str
fn int_of(v: json.Value, key: str, fallback: i64) -> i64
fn bool_of(v: json.Value, key: str) -> bool
fn array_of(v: json.Value, key: str) -> ([]const json.Value, bool)
fn options() -> json.Options
fn parse_bulk(a: *mem.Arena, body: str) -> (BulkResult, err)
fn parse_search(a: *mem.Arena, body: str) -> (SearchResult, err)
fn parse_error(a: *mem.Arena, body: str) -> (ErrorInfo, err)
```

The Elasticsearch REST codecs (L114): the parts of a client that are not sockets. `quote`, `path` and `query` percent-encode URL parts and query strings as elasticsearch-py does (`urllib.parse.quote` with `,` and `*` safe, empty path segments skipped); `bulk_meta` and `bulk_line` write the `_bulk` NDJSON action line with the metadata keys in the driver's order (`_id`, `_index`, `if_seq_no`, `if_primary_term`, `retry_on_conflict`, `routing`, `version`, `version_type`, `pipeline`; -1 and empty strings are absent) and the source line (none for delete, no raw newline allowed). `parse_bulk`, `parse_search` and `parse_error` read the documented response shapes (per-item status, error type and reason; total as an object or a plain integer; the new and the legacy error forms) over `e.fmt.json`, hit sources left as JSON values. HTTP, headers (`application/x-ndjson`), retry and cluster sniffing are the caller's (`e.net.http`, `http.pool_request`). Checked against elasticsearch-py's `_quote`, `_quote_query`, `expand_action` and elastic-transport's NDJSON serializer, with response shapes from a model, over 171 vectors on both hosts (D2645). Not done: a typed query DSL, scroll and point-in-time management, the async search and ingest APIs, ES|QL, cluster sniffing and node health, TLS and API-key header helpers.

## Missing declarations

- [ ] `TooSmall`
- [ ] `Invalid`
- [ ] `Meta`
- [ ] `Param`
- [ ] `BulkItem`
- [ ] `BulkResult`
- [ ] `Hit`
- [ ] `SearchResult`
- [ ] `ErrorInfo`
- [ ] `meta`
- [ ] `put_text`
- [ ] `put_byte`
- [ ] `hex_upper`
- [ ] `plain`
- [ ] `quote`
- [ ] `path`
- [ ] `query`
- [ ] `put_decimal`
- [ ] `put_string`
- [ ] `put_key_string`
- [ ] `put_key_number`
- [ ] `bulk_meta`
- [ ] `bulk_line`
- [ ] `member`
- [ ] `text_of`
- [ ] `int_of`
- [ ] `bool_of`
- [ ] `array_of`
- [ ] `options`
- [ ] `parse_bulk`
- [ ] `parse_search`
- [ ] `parse_error`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/elastic/rest.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/elastic_rest/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 32.

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
