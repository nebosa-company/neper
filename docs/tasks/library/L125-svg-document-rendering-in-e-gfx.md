# L125 — SVG document rendering in e.gfx

| field | value |
|---|---|
| category | library / Formats |
| score | 0.95 of 1 |
| queue position | 47 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Planning only (D1881). resvg parity gap (verified: SVG output exists, render does not): SVG path/shape/text document rendering into the scene backend over e.gfx.geometry and text layout. Fixtures against reference rasters with tolerance bounds; filters and scripting stay out. PART (D2843): linear/radial gradients (user-space and box units, gradientTransform, stop-opacity, href stops) on fill and stroke, defs/use/symbol, clip-path over the first shape, units (px pt pc mm cm in em, %), checked against cairosvg (10 documents, mean difference 3/255). NOT DONE: text, <style> sheets, pattern/mask/marker, dashes and even-odd fills (need a scene change: FillPath/StrokePath carry neither), spread other than pad, radial focal point, preserveAspectRatio other than meet. PART (D3100): <style> sheets (simple selectors, specificity), preserveAspectRatio, spreadMethod reflect/repeat, stroke-dasharray/offset, evenodd by nesting depth, pattern fills, markers; gfx_svg_render 22 cairosvg-referenced documents pass (mean diff <= 0.75/255). Missing: text, mask, filters, radial focal point, selector combinators, pattern viewBox/href, group opacity layers. PART (D3701): opacity layers, selector combinators, pattern viewBox/href, radial focal point, luminance masks, text via e.text.layout; gfx_svg_render 36 documents and gfx_svg_text 7 against FreeType. Missing: filters, mask units, font-family and weight, text on a path. PART (D4503-D4504): SVG filters (blur, offset, flood, blend, composite, colour matrix, merge, drop shadow) in scratch targets, mask units and region, font-family/weight/style, textPath; gfx_svg_filter 33 documents (mean <= 0.3/255 vs numpy over cairosvg), gfx_svg_text_faces 14 vs Pillow/FreeType. Missing: feMorphology/Turbulence/Image/Tile/ComponentTransfer/lighting/ConvolveMatrix/DisplacementMap, filter shorthand, nested filters in replays.

## Remaining work

- [ ] (no gap clause in the queue — see the notes below)

## Verification

- Every named fixture above must keep passing; add one fixture per checklist line (README §Fixture template).
- Both suites: `tests/selfhost/run.ps1` on Windows, `tests/selfhost/run.sh` on Linux through WSL (README §Build and verify).
- `python scripts/render_progress.py` must run clean after the queue edit.

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
