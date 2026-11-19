# L167 — Browser M2: modern CSS layout

| field | value |
|---|---|
| category | library / Library |
| score | 0.35 of 1 |
| queue position | 231 of 477 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Plan docs/browser-progress.html. Needs L166. Acceptance: (1) P2 2.4 to 2.15: floats, positioned and sticky, tables, flex, grid, multicolumn, intrinsic sizing, overflow, transforms, replaced elements, form controls, hit testing and geometry; (2) P3 3.4, 3.5, 3.8, 3.9 gradients, shadows, clip-path, mask, filters; (3) 9.2 WPT CSS reftests reproduce at least Dart's 116 of 122 and the six known failures are triaged; (4) the Dart layout pixel-probe expectations carried over as fixtures and green. Status 2026-11-03 (branch browser-conformance, tracker rows of P2+P3): 4 done, 21 partial, 16 todo of 41; score is the mean with partial counted as half. Handover fold 2026-11-19: the uncommitted sideways-lr frame in lib/e/fmt/css/layout.e (writing-modes 638 to 650) needs flexbox 650 and grid 1038 sweeps with zero new FAIL before commit, else revert and record; then sideways-lr counter-clockwise paint (paint.e ~968), flexbox safe overflow (parse_align drops safe, 001..005), grid rtl subgrid line-names-012, css-text piece loop (break-spaces 210/320, letter-spacing 3/29, hanging-punctuation 6/21), css-content element replacement 6/14, sizing, multicol, css-sizing re-measure. Never build a sub-manifest by grepping MANIFEST.txt (false green); use --only. Failing-cluster leads (handover fold 2026-11-19, leads not a ledger): css-flexbox flexbox-writing-mode 9, balance/* ~20 (balance-002 body max-content 51 vs 60), aspect-ratio-intrinsic-size 6, flexbox-min-width-auto, flexbox-definite-sizes, baseline-*, -left-002/-right-002; css-writing-modes table-cell-align 6, block-plaintext 5, bidi-override 5, bidi-isolate-override 5, ch-units-vrl 4, available-size 4, table-progression-vrl/vlr/slr ~8, vertical-alignment-*; css-grid baseline -002/-008, grid-lanes subgrid ~116, track-sizing 51, alignment 50, abspos 42, intrinsic-sizing 33. Grid baseline (rounds 256-262, REFUTES the earlier claim that the row-baseline pass exists only in layout_lanes_rows): it exists and is correct in layout_grid_inner, so do not build one. The 30 self-baseline files are blocked on vertical-writing-mode inline-block layout in a float (the reference is a different container shape, our grid is right), so no grid-baseline code can flip them. grid-baseline-align-001 is an inline-grid abspos static position lacking bx: guard !pb.inline_level at the static-position code; a plain static_x = pad_x + bb.x collapses css-grid/alignment 96 to 41 because pad_x absorbs the grid-area and root adjustments. The question of recording the baseline family as dropped is open in docs/open-questions.md. Block-ellipsis is decided (D7724: keep the clamped-line prefix, ellipsis-alone references accepted as an older encoding). content: url() on a pseudo-element (css-content 6/14): layout.Measure has no url_size (page, runners and app each construct it); gen_pseudo creates a .Replaced box that paint_atomic would paint with its border, the url resolves and the SVG has a 100x100 intrinsic size, but no IFC container lists the box (no ATOM trace for abh=120), so the next step is to print its parent right after append(l, parent_box, rb) in gen_pseudo. Sideways-lr frame mechanics (flow_frame code 3, remap_rect 3 to 0 with the inline axis reversed, root laid out with fi = ch) live only in the uncommitted layout.e diff: do not discard it; the revert is `git checkout -- lib/e/fmt/css/layout.e` after running flexbox and grid and diffing the FAIL lists. Harness-unmeasurable failure classes are not debt (memory neper-browser-wpt-recipe). A subgrid must ignore its own width: the row axis zeroes rmin/rmax near layout.e 8717, the column axis has no equivalent. grid-lanes is largely implemented (294 of 858); the real cluster is subgrid-inside-lanes (grid-subgridded 134, track-sizing/auto 95, intrinsic-sizing 40, dense 27). line-names-012: an inner subgrid inherits grid-column: 2 / span 2 from a shared stylesheet and an rtl subgrid places it on the physically left track (look at layout_grid_inner placement of a clamped 2 / span 2 child). sideways-lr is approximated (layout runs in frame 2, asymmetric top/bottom edges mapped as vertical-lr); an uncommitted sideways-lr change sits in lib/e/fmt/css/layout.e. Refuted: break-spaces needs a piece-loop redesign shared with letter-spacing (~136 files), hanging-punctuation (U+3000 is not a text piece), the CSS2 syntax family (at-charset/character-encoding need an HTTP header). Still failing: css-overflow line-clamp (113) and scroll-markers (44), css-multicol 186/402, contain-intrinsic-size 008, 012, 014, 017, 020, 023, 025, 027.

## Remaining work

The queue's own gap clause, split into checklist lines. Each line is one session's target.

- [ ] all of it

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
