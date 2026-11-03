# e.algo.writeback — 3 of 60 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/algo/writeback.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/algo/writeback.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.algo.ir` | source | `lib/e/algo/ir.e` | 5 |
| `e.algo.sync` | source | `lib/e/algo/sync.e` | 5 |
| `e.algo.syncjob` | source | `lib/e/algo/syncjob.e` | 5 |
| `e.data.list` | source | `lib/e/data/list.e` | 2 |
| `e.fmt.encode` | source | `lib/e/fmt/encode.e` | 6 |
| `e.fmt.json` | partial | `lib/e/fmt/json.e` | 6 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.net.ssrf` | source | `lib/e/net/ssrf.e` | 6 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
fn rejected_key() -> str
fn default_max_attempts() -> i64
fn js_string(a: *mem.Arena, v: json.Value, present: bool) -> str
fn hash_of(a: *mem.Arena, v: json.Value) -> str
fn strings_of(a: *mem.Arena, v: json.Value) -> []const str
fn array_of(a: *mem.Arena, l: list.List[json.Value]) -> json.Value
fn empty_obj() -> json.Value
fn str_member(v: json.Value, key: str) -> str
fn member_is(v: json.Value, key: str, want: str) -> bool
fn pushes(v: json.Value) -> bool
fn strict_true(v: json.Value, key: str) -> bool
fn copy_of(a: *mem.Arena, v: json.Value) -> ir.Obj
fn create_entry(a: *mem.Arena, opts: json.Value, id: str, now_iso: str) -> json.Value
fn record_delivery(a: *mem.Arena, entry: json.Value, result: json.Value, now_iso: str) -> json.Value
fn plan_reversion(a: *mem.Arena, entry: json.Value) -> json.Value
fn mark_reverted(a: *mem.Arena, entry: json.Value, reverted_fields: json.Value, now_iso: str) -> json.Value
fn status_counter(status: str) -> str
fn summarize_outbox(a: *mem.Arena, entries: []const json.Value) -> json.Value
fn str_less(x: str, y: str) -> bool
fn two_way_fields(a: *mem.Arena, mapping: json.Value) -> json.Value
fn writeback_mapping(a: *mem.Arena, mapping: json.Value) -> json.Value
fn entry_from_row(a: *mem.Arena, row: json.Value, id: str, now_iso: str) -> json.Value
fn put_present(o: *ir.Obj, from: json.Value, key: str, as_key: str)
fn entry_patch(a: *mem.Arena, entry: json.Value) -> json.Value
fn settle_delivery(a: *mem.Arena, entry: json.Value, result: json.Value, now_iso: str) -> json.Value
fn last_error(entry: json.Value) -> json.Value
fn revert_patch(a: *mem.Arena, entry: json.Value, reversion: json.Value, now_iso: str) -> json.Value
fn finish_reversion(a: *mem.Arena, entry: json.Value, patch: json.Value, now_iso: str) -> json.Value
fn echo_hash(a: *mem.Arena, key_text: str, record: json.Value, fields: []const str) -> str
fn has_text(l: list.List[json.Value], s: str) -> bool
fn echo_set(a: *mem.Arena, delivered: []const json.Value, fields: []const str) -> json.Value
fn suppress_echoes(a: *mem.Arena, plan: json.Value, echo: []const json.Value, sync_key: str, fields: []const str) -> json.Value
fn has_text_in(values: []const json.Value, s: str) -> bool
fn outbox_line(a: *mem.Arena, entries: []const json.Value, translate: *const syncjob.Translate) -> json.Value
fn map_remote_to_local(a: *mem.Arena, remote: json.Value, mapping: []const json.Value) -> json.Value
fn map_local_to_remote(a: *mem.Arena, local: json.Value, mapping: []const json.Value) -> json.Value
type Keyed = struct { id: str, key: json.Value, has_key: bool, row: json.Value }
fn index_rows(a: *mem.Arena, rows: []const json.Value, key: str) -> list.List[Keyed]
fn js_identity(a: *mem.Arena, v: json.Value, present: bool) -> str
fn find_row(l: list.List[Keyed], id: str) -> (json.Value, bool)
fn has_id(l: list.List[Keyed], id: str) -> bool
fn fields_changed(a: *mem.Arena, x: json.Value, base: json.Value, fields: []const str) -> bool
type Plan = struct { pulls: list.List[json.Value], pushes: list.List[json.Value], conflicts: list.List[json.Value], echoes: list.List[json.Value], create_local: list.List[json.Value], create_remote: list.List[json.Value], delete_local: list.List[json.Value], delete_remote: list.List[json.Value], noops: i64 }
fn move_entry(a: *mem.Arena, k: Keyed, record: json.Value, via_conflict: bool) -> json.Value
fn add_conflict(a: *mem.Arena, p: *Plan, k: Keyed, local: json.Value, remote: json.Value, base: json.Value, policy: str)
fn plan_two_way_sync(a: *mem.Arena, local_rows: []const json.Value, remote_rows: []const json.Value, base_rows: []const json.Value, key: str, fields: []const str, policy: str, echo: []const json.Value) -> json.Value
fn lower_ascii(a: *mem.Arena, s: str) -> str
fn upper_ascii(a: *mem.Arena, s: str) -> str
fn hex_digit(n: u8) -> u8
fn is_alnum(c: u8) -> bool
fn encode_uri_component(a: *mem.Arena, s: str) -> str
fn form_encode(a: *mem.Arena, s: str) -> str
fn is_digits(s: str) -> bool
fn small_number(s: str) -> i64
fn private_v4(host: str) -> bool
fn is_safe_url(a: *mem.Arena, url: str) -> (bool, str)
fn auth_headers(a: *mem.Arena, o: *ir.Obj, auth: json.Value)
type Param = struct { name: str, value: str }
fn build_request(a: *mem.Arena, connection: json.Value, request: json.Value) -> json.Value
fn build_push_request(a: *mem.Arena, connection: json.Value, entity: str, entry: json.Value, mapping: json.Value) -> json.Value
```

The push half of two-way sync (L037), after appdor's `src/sync/writeback.js` with `src/connectors/writeback-outbox.js`, `sync-engine.js` and `index.js`: the outbox entry and its lifecycle (`create_entry`, `record_delivery`, `plan_reversion`, `mark_reverted`, `summarize_outbox`), the host's judgements (`two_way_fields`, `writeback_mapping`, `entry_from_row`, `entry_patch`, `settle_delivery`, `revert_patch`, `finish_reversion`, `echo_set`, `suppress_echoes`, `outbox_line`), the engine (`map_remote_to_local`, `map_local_to_remote`, `plan_two_way_sync`) and the SSRF-checked `build_request` and `build_push_request`. The clock and the entry id are arguments; words come back through the host's translator.

## Missing declarations

- [ ] `is_digits`
- [ ] `small_number`
- [ ] `private_v4`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/algo/align.e`
- `lib/e/algo/batch.e`
- `lib/e/algo/bdd.e`
- `lib/e/algo/bignum.e`
- `lib/e/algo/bitset.e`
- `lib/e/algo/chain.e`
- `lib/e/algo/check.e`
- `lib/e/algo/checksum.e`†

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/algo/writeback.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/algo_writeback/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 3.

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
