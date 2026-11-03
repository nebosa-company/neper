# BL-04 — Windows resources: `.rc` compiler and `.rsrc` linking

| field | value |
|---|---|
| roadmap section | Backlog — recorded, not scheduled |
| queue row | none — this bullet has no `docs/work-queue.json` row yet; the first session adds one (README §Adding a queue row) |
| difficulty | very high — a milestone bullet, not a capability; split it into queue rows of one capability each before any code |

## Definition of done

> **Windows resources: `.rc` compiler and `.rsrc` linking (D471).** The PE emitter writes `.text` and `.idata` and nothing the shell or loader can read about the program. This wave adds `neper rc FILE.rc -o FILE.res` and a `.rsrc` section in the own linker, so an executable carries its icon, `VERSIONINFO`, application manifest, images and custom resource types, and `project.yaml` names the `.rc` per Windows target. The compiler covers the RC statements those need — `ICON`, `CURSOR`, `BITMAP`, `VERSIONINFO`, `STRINGTABLE`, `RCDATA`, `24 RT_MANIFEST`, `LANGUAGE`, and `NAME TYPE "file"` for user-defined types — with `#define NAME integer` as its whole preprocessor: no `#include`, no expressions, no C. The linker builds the type → name → language directory the loader expects (names before ids, both ascending), splits an `.ico`/`.cur` into its `RT_ICON`/`RT_GROUP_ICON` entries, serialises `VERSIONINFO` as the UTF-16, DWORD-padded `VS_VERSIONINFO` tree, and places a manifest at id 1. The section is byte-deterministic and every input's path, size and SHA-256 goes in the build manifest. A `.res` compiled elsewhere links the same way, which is the first increment; the own `rc` is the second. Runtime access is `os.resource(kind, name)` on Windows only; `.rsrc` is for what Windows reads — application data keeps going through `e.asset`, which is the same on every target, and a Linux build records the `.rc` as not applicable rather than failing.

## Decisions to read first

- `D471` — Windows resources: an `.rc` compiler and a `.rsrc` section (`docs/decisions.md:10220`)

## Code anchors

- `.text`: `src/check.e`×143‡, `lib/e/js/parser.e`×114†, `lib/e/ui/navigation.e`×97‡, `lib/e/js/interp.e`×95‡, `lib/e/ui/collection.e`×91‡, `lib/e/ui/overlay.e`×79‡, `lib/e/ui/control.e`×73‡, `lib/e/ui/style.e`×62†
- `.idata`: `src/link_pe.e`×4
- `project.yaml`: `src/main.e`×8‡, `src/assets.e`×5, `lib/e/asset.e`×1, `src/graph.e`×1†
- `ICON`: `lib/e/os/shell.windows.e`×10‡, `scripts/material/gen_glyphs.py`×4, `scripts/linux_cmp_l3.py`×3, `scripts/material/gallery.html`×3, `scripts/winnative/gallery.c`×3†, `scripts/linux_cmp_lc.py`×2, `scripts/linux_flat_la.py`×2, `lib/e/algo/transpile.e`×1
- `CURSOR`: `lib/e/ui/terminal.e`×5†, `lib/e/os/shell.windows.e`×2‡, `lib/wasm/window.js`×2, `scripts/syncpull_reference.mjs`×2, `scripts/khronos/eglext.h`×1†, `src/main.e`×1‡
- `BITMAP`: `scripts/khronos/eglext.h`×9†, `scripts/winnative/glyphs.c`×9, `scripts/winnative/gallery.c`×6†, `lib/e/gfx/cleartype.e`×3, `scripts/material/ftprobe.py`×2, `lib/e/os.windows.e`×1‡
- `RCDATA`: `lib/e/fmt/html.e`×13‡
- `LANGUAGE`: `benchmarks/llm_edit/hard_context.py`×5, `scripts/gen_highlight.py`×3, `scripts/source_metrics.py`×3, `lib/e/js/intl.e`×2‡, `lib/e/js/intl/82_displaynames.js`×2, `lib/e/text/highlight.e`×2, `lib/x/khronos/gl.e`×2‡, `scripts/khronos/glcorearb.h`×2‡
- `.ico`: `lib/e/ui/control.e`×74‡, `lib/e/ui/navigation.e`×52‡, `lib/e/ui/collection.e`×37‡, `lib/e/ui/overlay.e`×21‡, `lib/e/ui/datagrid.e`×4‡, `lib/e/ui/window.e`×3, `lib/e/fmt/brotli.e`×2‡, `lib/e/ui/gridrules.e`×2
- `.cur`: `src/parse.e`×204†, `lib/e/text/tthint.e`×58†, `scripts/line_vectors.py`×49, `lib/e/cli/line.e`×44, `src/tool.e`×43‡, `lib/e/text/ttglyph.e`×38, `lib/e/ui/undo.e`×32, `src/lower.e`×32‡
- nearest existing implementation: `src/link_pe.e`, `src/object_coff.e`, `src/main.e`‡ († over 40 KB, ‡ over 120 KB — read by region)

## First session

1. Read the spec sections and decisions above in full.
2. Write the queue row: `id` (next free `C`/`T` number), `title`, `score: 0`, `evidence: ""`, `model`, `thinking`, placed by `order`; add a `## D<n>` row that records the split.
3. Freeze any public API before source: a fence in `docs/module-apis.md` and a `docs/modules.json` row, validated by `python tests/test_module_plan.py`.
4. Then follow README §Session procedure for the first capability.
