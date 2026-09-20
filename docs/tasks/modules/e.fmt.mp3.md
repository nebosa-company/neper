# e.fmt.mp3 — 8 of 8 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/fmt/mp3.e` |
| plan row | layer 6, surface `planned`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/fmt/mp3.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.io` | source | `lib/e/io.e` | 4 |
| `e.bytes` | partial | `lib/e/bytes.e` | 1 |
| `e.math` | partial | `lib/e/math.e` | 0 |
| `e.audio` | partial | `lib/e/audio.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Decoder = struct { bytes: []const u8, at: usize, format: audio.Format, frames: usize, granule: usize }
error Invalid
error Unsupported

fn open(a: *mem.Arena, source_bytes: []const u8) -> (Decoder, err)
fn format(d: Decoder) -> audio.Format
fn frame_count(d: Decoder) -> usize
fn decode_into(d: *Decoder, out: *audio.Frames) -> (usize, err)
fn seek(d: *Decoder, frame: usize) -> err
```

## Missing declarations

- [ ] `Decoder`
- [ ] `Invalid`
- [ ] `Unsupported`
- [ ] `open`
- [ ] `format`
- [ ] `frame_count`
- [ ] `decode_into`
- [ ] `seek`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/fmt/asn1.e`
- `lib/e/fmt/bson.e`
- `lib/e/fmt/bzip2.e`
- `lib/e/fmt/csv.e`
- `lib/e/fmt/gzip.e`
- `lib/e/fmt/html.e`†
- `lib/e/fmt/ini.e`
- `lib/e/fmt/json.e`†

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/fmt/mp3.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/fmt_mp3/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 8.

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
