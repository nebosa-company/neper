# L165 — UI looks: one widget set in a Windows (MTG Studio v3) look, then macOS/iOS and Android

| field | value |
|---|---|
| category | library / Library |
| score | 0.40 of 1 |
| queue position | 95 of 106 (only position 1 is eligible for the next session; see README) |
| difficulty | high — rated for a frontier model; one checklist line per session, thinking budget unlimited |

## Definition of done

See `docs/roadmap.md` and the evidence below.

## Already delivered

Verbatim from `docs/work-queue.json`; every `D<n>` is a row in `docs/decisions.md`. This is the ground truth of what exists — do not re-implement any of it.

> Plan docs/ui/looks-plan.md, decision D5108, progress docs/ui/looks-progress.html (docs/ui/looks/status.json). Acceptance: (1) Profile.Windows and style.windows from the v3 captures; (2) e.ui.looks renders every control's states offscreen per look at 100% and 150% into docs/ui/looks/<look>/<control>.png beside the v3 reference; (3) the ~30 controls of the plan each reach ready (Windows PNG within tolerance of docs/ui/looks/ref/windows at both scales); (4) CupertinoLike and MaterialLike get tokens and idiom branches (later); (5) controls with no Neper equivalent are listed, not built. PART (D5108, D5109 to D5113; state at audit 2, 2026-10-16): items 1 and 2 done. All 30 controls render under Neper and Windows at 100% and 150% (45 sheet apps in examples/looks, scripts/render_looks_all.sh). The v3 reference is now captured live from a launched copy of v3 by posted window messages (scripts/grab_v3_*.ps1, about 250 state and dialog captures in docs/ui/looks/ref/windows). Audit 2 (docs/ui/looks/audit.md, an independent recompute against those captures, tolerance 2 levels per channel) counts 0 matched, 0 ready, 25 review and 5 started (date_edit, memo, token_edit, progress_bar, hint have no v3 capture); six controls self-reported matched were downgraded. Known gaps: hover and toolbar states cannot be captured without the real pointer (the optional GetCursorPos hook is not done), 81 of 200 captured states have no sheet cell, the baked button ring and edit chrome tiles go dotted at 1.5x, open-list sheets and the data grid are far off. IN FLIGHT: hover captures and round 5 matching. NOT DONE: any control at matched or ready, dark and high-contrast sheets beyond the button, Cupertino and Material.

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
