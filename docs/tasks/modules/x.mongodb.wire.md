# x.mongodb.wire — 32 of 32 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/mongodb/wire.e` |
| plan row | layer 6, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/mongodb/wire.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.bytes` | partial | `lib/e/bytes.e` | 1 |
| `e.crypto.hash` | partial | `lib/e/crypto/hash.e` | 2 |
| `e.crypto.kdf` | source | `lib/e/crypto/kdf.e` | 2 |
| `e.crypto.mac` | source | `lib/e/crypto/mac.e` | 2 |
| `e.fmt.bson` | partial | `lib/e/fmt/bson.e` | 6 |
| `e.io` | source | `lib/e/io.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
error Truncated
error Invalid
error TooLarge
error Unsupported
error BadChecksum
error TooSmall
error AuthFailed
const OP_MSG: u32 = 2013u32
const OP_COMPRESSED: u32 = 2012u32
const CHECKSUM_PRESENT: u32 = 1u32
const MORE_TO_COME: u32 = 2u32
const EXHAUST_ALLOWED: u32 = 65536u32
const MAX_MESSAGE: usize = 48000000usize
type Sequence = struct { identifier: str, documents: []const u8 }
type Message = struct { length: u32, request_id: i32, response_to: i32, opcode: u32, flags: u32, body: []const u8, sequences: usize, has_checksum: bool, more_to_come: bool, exhaust_allowed: bool }
type Status = struct { good: bool, code: i64, code_name: str, message: str }

fn le32(b: []const u8, at: usize) -> u32
fn put_le32(b: []u8, at: usize, v: u32)
fn crc32c(data: []const u8) -> u32
fn encode_op_msg(dst: []u8, request_id: i32, response_to: i32, flags: u32, body: []const u8, sequences: []const Sequence) -> (usize, err)
fn document_end(buf: []const u8, at: usize, limit: usize) -> (usize, err)
fn next_document(documents: []const u8, at: usize) -> ([]const u8, usize, err)
fn parse(buf: []const u8, seq_out: []Sequence) -> (Message, usize, err)
fn command(a: *mem.Arena, db: str, elements: []const bson.Element) -> ([]const u8, err)
fn status(a: *mem.Arena, body: []const u8) -> (Status, err)
fn put_text(dst: []u8, at: *usize, text: str) -> err
fn ascii_only(s: str) -> bool
fn scram_first(dst: []u8, user: str, nonce: str) -> (usize, err)
fn scram_field(message: str, key: u8) -> (str, bool)
fn parse_u32(s: str) -> (u32, bool)
fn scram_final(dst: []u8, first_bare: str, server_first: str, password: str, nonce: str, expected: []u8) -> (usize, usize, err)
fn scram_verify(server_final: str, expected: str) -> bool
```

The MongoDB wire protocol (L114), OP_MSG only (every server since 3.6), over caller buffers; no sockets or topology monitoring. `encode_op_msg` frames a message (request id, flag bits, the kind 0 body document, any number of kind 1 document sequences, an optional CRC-32C when `CHECKSUM_PRESENT` is set); `parse` reads one message from a stream (`Truncated` until it is all there, `BadChecksum`, `Unsupported` for OP_COMPRESSED and the legacy opcodes or an unknown required flag bit, `Invalid` for a malformed section, every length checked before use) and `next_document` walks a sequence. `command` builds a command document through `e.fmt.bson` with `$db` appended and `status` reads `ok`, `code`, `codeName` and `errmsg` from a reply. SCRAM-SHA-256 is `scram_first`, `scram_final` (PBKDF2-HMAC-SHA-256, the client proof and the server signature to expect) and `scram_verify`; passwords and user names are ASCII (SASLprep of other text is not implemented and answers `Unsupported`). Checked against pymongo's OP_MSG builder, `bson`, pymongo's own SCRAM client run against a scripted server (the RFC 7677 exchange asserted) and the `crc32c` package over 187 vectors on both hosts (D2644). Not done: sockets, server discovery and monitoring, compression, SCRAM-SHA-1 and x.509/AWS/OIDC/Kerberos mechanisms, sessions and transactions, change streams, cursors beyond the getMore command a caller builds with `command`.

## Missing declarations

- [ ] `Truncated`
- [ ] `Invalid`
- [ ] `TooLarge`
- [ ] `Unsupported`
- [ ] `BadChecksum`
- [ ] `TooSmall`
- [ ] `AuthFailed`
- [ ] `OP_MSG`
- [ ] `OP_COMPRESSED`
- [ ] `CHECKSUM_PRESENT`
- [ ] `MORE_TO_COME`
- [ ] `EXHAUST_ALLOWED`
- [ ] `MAX_MESSAGE`
- [ ] `Sequence`
- [ ] `Message`
- [ ] `Status`
- [ ] `le32`
- [ ] `put_le32`
- [ ] `crc32c`
- [ ] `encode_op_msg`
- [ ] `document_end`
- [ ] `next_document`
- [ ] `parse`
- [ ] `command`
- [ ] `status`
- [ ] `put_text`
- [ ] `ascii_only`
- [ ] `scram_first`
- [ ] `scram_field`
- [ ] `parse_u32`
- [ ] `scram_final`
- [ ] `scram_verify`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/mongodb/wire.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/mongodb_wire/src/main.e` that prints one fixed line on success, registered in both runners.
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
