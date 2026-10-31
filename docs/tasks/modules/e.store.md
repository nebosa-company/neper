# e.store — 1 of 36 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/store.e` |
| plan row | layer 4, surface `source`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/store.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.fs` | partial | `lib/e/fs.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.str` | source | `lib/e/str.e` | 1 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 4 may depend on layers [0, 1, 2, 3, 4].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
error NotFound
error Invalid
error TooLarge
error Failed
type Entry = struct { key: str, size: u64 }
type Store = struct { ctx: *void, put: fn(*void, *mem.Arena, str, []const u8) -> err, get: fn(*void, *mem.Arena, str, usize) -> ([]u8, err), stat: fn(*void, *mem.Arena, str) -> (u64, err), delete: fn(*void, *mem.Arena, str) -> err, list: fn(*void, *mem.Arena, str, []Entry) -> (usize, err) }
type MemoryStore = struct { keys: []str, values: []str, count: usize }
type FsStore = struct { root: str }

fn valid_key(key: str) -> bool
fn has_prefix(key: str, prefix: str) -> bool
fn key_less(x: str, y: str) -> bool
fn put(s: *Store, a: *mem.Arena, key: str, data: []const u8) -> err
fn get(s: *Store, a: *mem.Arena, key: str, limit: usize) -> ([]u8, err)
fn stat(s: *Store, a: *mem.Arena, key: str) -> (u64, err)
fn exists(s: *Store, a: *mem.Arena, key: str) -> (bool, err)
fn delete(s: *Store, a: *mem.Arena, key: str) -> err
fn list(s: *Store, a: *mem.Arena, prefix: str, out: []Entry) -> (usize, err)
fn memory(a: *mem.Arena, capacity: usize) -> (MemoryStore, err)
fn memory_store(m: *MemoryStore) -> Store
fn memory_find(m: *MemoryStore, key: str) -> (usize, bool)
fn copy_str(a: *mem.Arena, s: str) -> (str, err)
fn memory_put(ctx: *void, a: *mem.Arena, key: str, data: []const u8) -> err
fn memory_get(ctx: *void, a: *mem.Arena, key: str, limit: usize) -> ([]u8, err)
fn memory_stat(ctx: *void, a: *mem.Arena, key: str) -> (u64, err)
fn memory_delete(ctx: *void, a: *mem.Arena, key: str) -> err
fn memory_list(ctx: *void, a: *mem.Arena, prefix: str, out: []Entry) -> (usize, err)
fn fs_store(f: *FsStore) -> Store
fn fs_error(e: err) -> err
fn fs_path(a: *mem.Arena, f: *FsStore, key: str) -> (str, err)
fn fs_put(ctx: *void, a: *mem.Arena, key: str, data: []const u8) -> err
fn fs_get(ctx: *void, a: *mem.Arena, key: str, limit: usize) -> ([]u8, err)
fn fs_stat(ctx: *void, a: *mem.Arena, key: str) -> (u64, err)
fn fs_delete(ctx: *void, a: *mem.Arena, key: str) -> err
fn fs_list(ctx: *void, a: *mem.Arena, prefix: str, out: []Entry) -> (usize, err)
fn bytes_equal(x: []const u8, y: []const u8) -> bool
fn conformance(s: *Store, a: *mem.Arena) -> u32
```

One put/get/stat/delete/list surface over places that hold named blobs (opendal and fsspec at the portable layer). A `Store` is a context pointer plus five function pointers, so a backend is whatever fills them in; `memory_store` (a sorted table copied into the arena, at most `capacity` keys, `TooLarge` past it) and `fs_store` (a root directory; `/`-separated keys become nested files and parent directories are made) ship here, `e.store.http` is the third. A key has no empty, `.` or `..` segment, no leading or trailing `/`, no backslash and no NUL (`Invalid`), so it cannot leave its store; `list` is a byte prefix over keys in byte order (`TooLarge` when `out` is full); reading an absent key is `NotFound` and deleting one is `ok`. `conformance` is the one script every backend runs: overwrite, binary and empty values, nested and non-ASCII keys, read bounds, ordering, prefix listing, absent keys, idempotent delete, escaping keys, a 70000-byte value; it answers 0 or the first failing step. A filesystem backend cannot hold a key and a key beneath it at once (`a` and `a/b`); object stores can. Not here: streaming reads and writes, ranges, metadata beyond size, conditional writes, multipart, and the virtual-filesystem overlay and union mounts of L119.

## Missing declarations

- [ ] `fs_path`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/asset.e`
- `lib/e/async.e`
- `lib/e/atomic.e`
- `lib/e/audio.e`
- `lib/e/barcode.e`†
- `lib/e/bytes.e`
- `lib/e/cancel.e`
- `lib/e/channel.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/store.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/store/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 1.

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
