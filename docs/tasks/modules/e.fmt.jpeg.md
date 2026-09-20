# e.fmt.jpeg — 8 of 8 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/fmt/jpeg.e` |
| plan row | layer 6, surface `partial`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/fmt/jpeg.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Interchange formats:** `e.fmt.uri`, `e.fmt.mime`, `e.fmt.asn1`, `e.fmt.pem`, `e.fmt.multipart`, `e.fmt.mail`, `e.fmt.quoted_printable`, `e.fmt.gzip`, `e.fmt.zstd`, `e.fmt.bzip2`, `e.fmt.lzw`, `e.fmt.zlib`, `e.fmt.zip`, `e.fmt.tar`, `e.fmt.yaml`, `e.fmt.xml`, `e.fmt.html`, `e.fmt.png`, `e.fmt.jpeg`, `e.fmt.webp`, `e.fmt.bson`, `e.fmt.msgpack` and `e.fmt.protobuf`, plus `e.text.template` and its context-safe `e.fmt.html.template` specialization. These consume caller-provided slices/readers and writers, never open resources themselves, and require malformed, streaming, bounds and round-trip corpora in addition to API equality. `e.fmt.html` additionally runs the pinned html5lib tokenizer and tree-construction fixtures for the WHATWG behavior frozen by that toolchain release.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.bytes` | partial | `lib/e/bytes.e` | 1 |
| `e.io` | source | `lib/e/io.e` | 4 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.gfx.image` | partial | `lib/e/gfx/image.e` | 2 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type DecodeOptions = struct { max_width: u32, max_height: u32, max_pixels: u64 }
type EncodeOptions = struct { quality: u8, progressive: bool }
error Invalid
error Unsupported
error TooLarge

fn inspect(source: io.Reader) -> (image.Info, err)
fn decode(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> (image.Image, err)
fn encode(writer: *io.Writer, value: image.ConstImage, options: EncodeOptions) -> err
```

Version 1 supports baseline and progressive Huffman JPEG with bounded dimensions.
Arithmetic coding and embedded color-profile conversion return `Unsupported`.

## Missing declarations

- [ ] `DecodeOptions`
- [ ] `EncodeOptions`
- [ ] `Invalid`
- [ ] `Unsupported`
- [ ] `TooLarge`
- [ ] `inspect`
- [ ] `decode`
- [ ] `encode`

## Contracts that name this module

Read each line in context; they carry obligations (cancellation, bounded buffers, no hidden allocation, standard vectors) that the fence alone does not spell out.

- `docs/stdlib-hardening.md:408` extended `e.fmt.png`, `e.fmt.jpeg` and `e.fmt.webp`. The complete public-type dependency
- `docs/ui-framework.md:79` `e.fmt.png`, `e.fmt.jpeg` or `e.fmt.webp`, while project-specific formats remain separate.
- `docs/ui-framework.md:278` extended and stabilizes together with `e.fmt.png`, `e.fmt.jpeg` and `e.fmt.webp` under

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

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/fmt/jpeg.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/fmt_jpeg/src/main.e` that prints one fixed line on success, registered in both runners.
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
