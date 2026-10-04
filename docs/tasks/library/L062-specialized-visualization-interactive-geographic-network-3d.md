# L062 — Specialized visualization (interactive, geographic, network, 3D)

| field | value |
|---|---|
| category | library / Algorithms |
| score | 0.00 of 1 |
| queue position | appended at the end (only position 1 is eligible for the next session; see README) |
| difficulty | medium — rated for a mid-size model; one or two checklist lines per session |

## Definition of done

See `docs/roadmap.md`, `docs/stats-coverage.md` §2 and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Standard charts are L060. The specialized layers are all missing: no plotly/bokeh-style interactive chart layer (`e.ui` native widgets plus `e.ui.animation/input` are the base for hover/select/zoom); geographic math without a renderer (`e.algo.geo` S2 cells, haversine, bearing); graph algorithms without layout/draw (`e.algo.graph` plus centrality/community/cut/iso); low-level 3D only (`e.gfx.mesh/scene/trace/shade`, `e.gpu`). Build interactive selection/zoom over L060 charts, a geographic renderer atop `e.algo.geo`, a network layout (e.g. force-directed) atop `e.algo.graph`, and 3D surfaces atop `e.gfx.mesh/scene`. Dashboards (shiny/streamlit/dash) are a non-goal (D1773): hand-build on `e.ui.app` + `e.net.http`. Full evaluation: `docs/stats-coverage.md` §2.

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
