# x.redis.resp — 38 of 38 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/redis/resp.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/redis/resp.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
error Incomplete
error Invalid
error TooLarge
error TooSmall
type Pair = struct { key: Value, value: Value }
type Verbatim = struct { format: str, data: []const u8 }
type Value = union enum u8 { Null, Simple: str, Error: str, Integer: i64, Bulk: []const u8, Array: []const Value, Bool: bool, Double: f64, Big: str, Map: []const Pair, Set: []const Value, Push: []const Value, Verbatim: Verbatim, BlobError: []const u8 }
type Limits = struct { max_bulk: usize, max_elements: usize, max_depth: u16 }
type ErrorKind = enum u8 { Generic, Moved, Ask, WrongType, NoAuth, ReadOnly, Loading, TryAgain, ClusterDown, MasterDown, NoScript, Busy }
type Redirect = struct { ask: bool, slot: u16, host: str, port: u16 }
type PubSubKind = enum u8 { Message, PMessage, Subscribe, Unsubscribe, PSubscribe, PUnsubscribe }
type PubSub = struct { kind: PubSubKind, pattern: []const u8, channel: []const u8, payload: []const u8, count: i64 }
type Session = struct { protocol: u8, pending: usize, subscriptions: usize }

fn limits() -> Limits
fn put_bytes(dst: []u8, at: *usize, src: []const u8) -> err
fn put_decimal(dst: []u8, at: *usize, value: usize) -> err
fn encode_command(dst: []u8, args: []const []const u8) -> (usize, err)
fn encode_hello(dst: []u8, version: u8, user: str, password: str) -> (usize, err)
fn line_end(buf: []const u8, at: usize) -> (usize, err)
fn parse_integer(s: str) -> (i64, bool)
fn parse_double(s: str) -> (f64, bool)
fn element_slice(a: *mem.Arena, count: usize) -> ([]Value, err)
fn pair_slice(a: *mem.Arena, count: usize) -> ([]Pair, err)
fn read_value(a: *mem.Arena, buf: []const u8, at: *usize, lim: *const Limits, depth: u16) -> (Value, err)
fn parse(a: *mem.Arena, buf: []const u8, lim: *const Limits) -> (Value, usize, err)
fn crc16_step(crc: u16, byte: u8) -> u16
fn key_slot(key: []const u8) -> u16
fn starts(text: str, prefix: str) -> bool
fn error_kind(text: str) -> ErrorKind
fn parse_redirect(text: str) -> (Redirect, bool)
fn bytes_of(v: Value) -> ([]const u8, bool)
fn same_ascii(left: []const u8, right: str) -> bool
fn pubsub_event(items: []const Value) -> (PubSub, bool)
fn session(protocol: u8) -> Session
fn is_reply(s: *const Session, v: Value) -> bool
fn note(s: *Session, v: Value)
fn apply(s: *Session, event: PubSub)
fn send(s: *Session, dst: []u8, args: []const []const u8, replies: usize) -> (usize, err)
```

The Redis serialization protocol (L114), RESP2 and RESP3, over caller buffers (no sockets; the caller moves the bytes, as `e.net.mqtt` does). `encode_command` writes a command as an array of bulk strings and `encode_hello` the RESP3 switch with optional AUTH; `parse` reads one reply from the front of a stream and answers the bytes it used, `Incomplete` until the rest has arrived, `Invalid` for a frame that is not RESP and `TooLarge` past `Limits` (declared sizes are checked before anything is allocated; the arena is left as it was on any error). Reply types: simple string, error, integer, bulk, array and the RESP2 null forms, plus RESP3 null, boolean, double (inf, -inf, nan), big number, blob error, verbatim string, map, set and push; an attribute frame is skipped. Also `key_slot` (CRC-16/XMODEM with hash tags), `parse_redirect` for MOVED/ASK, `error_kind`, `pubsub_event` for RESP2 arrays and RESP3 pushes and a small `Session` that counts pending replies and subscriptions. Checked against redis-py's RESP2 and RESP3 parsers, `pack_command`, `key_slot` and `AskError`/`MovedError` over 381 vectors with every stream re-chunked, plus a scripted pub/sub session on both hosts (D2643). Not done: sockets and connection handling, cluster topology discovery and failover, Sentinel, client-side caching, Lua/script helpers, TLS.

## Missing declarations

- [ ] `Incomplete`
- [ ] `Invalid`
- [ ] `TooLarge`
- [ ] `TooSmall`
- [ ] `Pair`
- [ ] `Verbatim`
- [ ] `Value`
- [ ] `Limits`
- [ ] `ErrorKind`
- [ ] `Redirect`
- [ ] `PubSubKind`
- [ ] `PubSub`
- [ ] `Session`
- [ ] `limits`
- [ ] `put_bytes`
- [ ] `put_decimal`
- [ ] `encode_command`
- [ ] `encode_hello`
- [ ] `line_end`
- [ ] `parse_integer`
- [ ] `parse_double`
- [ ] `element_slice`
- [ ] `pair_slice`
- [ ] `read_value`
- [ ] `parse`
- [ ] `crc16_step`
- [ ] `key_slot`
- [ ] `starts`
- [ ] `error_kind`
- [ ] `parse_redirect`
- [ ] `bytes_of`
- [ ] `same_ascii`
- [ ] `pubsub_event`
- [ ] `session`
- [ ] `is_reply`
- [ ] `note`
- [ ] `apply`
- [ ] `send`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/redis/resp.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/redis_resp/src/main.e` that prints one fixed line on success, registered in both runners.
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
