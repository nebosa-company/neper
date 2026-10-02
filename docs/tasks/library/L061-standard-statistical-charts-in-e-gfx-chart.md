# L061 — Standard statistical charts in e.gfx.chart

| field | value |
|---|---|
| category | library / Algorithms |
| score | 0.88 of 1 |
| queue position | 1 (the active capability; only position 1 is eligible for the next session) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md`, `docs/stats-coverage.md` §2 and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> `e.gfx.chart` maps borrowed numeric columns into caller-owned scatter, line, bar, grouped/dodged bar, signed stacked bar, 100% stacked bar, step, area, lollipop, error-bar, confidence-band, dumbbell and distribution marks, including frequency polygons and rugs, row-major heatmap and Pearson correlation cells, plus equal facet-panel rectangles. Cartesian `Spec` has independent linear, log10, symmetric-log and reverse scales; caller-owned ticks drive scene and SVG grid/axis strokes. `nice_ticks` selects 1/2/5 linear and logarithmic breaks, falling back to equal transformed-space positions for symmetric-log; `format_ticks` writes shortest-round-trip numeric labels into caller-owned storage. `layout_with_limits` accepts optional caller-borrowed x/y domains for shared or free numeric facet scales, rejecting limits that exclude data. `category_ticks` supplies ordinal bar centers and `legend_items` pairs swatches with borrowed series names; the three bar previews now include category labels and a two-series legend in both formats. `guide_labels` positions tick strings and the scene/SVG adapters render them alongside title labels, with escaped SVG text and a caller-registered TrueType font for scene replay. `e.gfx.chart.svg` streams solid-colour marks and matrix tiles with escaped title/description metadata. `gfx_chart`, `gfx_chart_qq`, `gfx_chart_matrix`, `gfx_chart_cartesian`, `gfx_chart_scale`, `gfx_chart_facet`, `gfx_chart_intervals`, `gfx_chart_labels`, `gfx_chart_nice_ticks`, `gfx_chart_composition`, `gfx_chart_distribution` and `gfx_chart_svg` check statistics, geometry, scales, text, scene/SVG commands and refusal paths; `examples/chart_gallery.e` generated twenty-nine inspected PNG previews and twenty-nine XML-parsed SVG companions. The full registry and staged delivery plan are in `docs/charting-engine-plan.md`. Remaining work includes discrete/date scales, locale/date formatting and label collision/margins, facet strips/automated legend layout and categorical mapping, production PNG/PDF/widget adapters, specialized diagrams and comparative benchmarks. Full evaluation: `docs/stats-coverage.md` §2.

## Remaining work

- [x] **Foundation grammar and marks** — typed `Spec`, numeric Cartesian domain,
  caller-owned `Layout`, scatter/line/bar/step/area/lollipop/error-bar/band/dumbbell
  marks and refusal paths.
- [x] **Core distribution families** — histogram, frequency polygon, rug,
  box, violin, density, ECDF and normal Q-Q have executable fixtures and PNG previews.
- [ ] **Matrix and facets** — heatmap, Pearson correlation matrix, equal-panel
  facet geometry and shared/free numeric x/y domains delivered; ordinal bar
  labels and series-legend geometry delivered; categorical facet mapping,
  strips and automated legend layout remain.
- [ ] **Backends** — scene marks, PNG gallery and streaming solid-colour SVG delivered;
  tick/grid/axis strokes, automatic numeric tick text and caller-supplied titles
  delivered; locale/date formatting and collision-safe margins, production PNG/PDF export and
  `e.ui.widget` embed remain.
- [ ] **Specialized diagrams** — ROC, survival, SPC, scientific, finance, quality,
  operations and network families from `docs/charting-engine-plan.md`.

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
