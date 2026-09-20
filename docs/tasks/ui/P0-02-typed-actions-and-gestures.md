# P0-02 — Typed actions and gestures (3 components)

| field | value |
|---|---|
| phase | P0 — Contracts and reference theme |
| module | `e.ui.widget` |
| module surface | `planned`, layer 6, deps `e.data.slot_map`, `e.mem`, `e.gfx.geometry`, `e.gfx.paint`, `e.gfx.scene`, `e.text.layout`, `e.ui.input`, `e.ui.layout`, `e.ui.style`, `e.ui.window` |
| blocked by | `e.gfx.scene`, `e.text.layout`, `e.ui.input` |
| delivered | 0 of 3 |

## Eligibility

`python scripts/check_widget_plan.py --next` names the single eligible component; it currently reports: `BLOCKED: P0 by e.gfx.scene, e.text.layout, e.ui.input`. An item is eligible only when its phase and item blockers are complete and every earlier item in the phase is delivered or independently blocked. The UI family is blocked as a whole on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives (`docs/roadmap.md`, 'Experimental declarative GPU UI'); the `e.ui.*`, `e.gfx.*` and `e.text.*` modules under `docs/tasks/modules/` come first.

## Definition of done

Every component below is implemented in `e.ui.widget`, exercised by a deterministic layout, paint, semantics and input fixture under `e.ui.testing`, recorded in `docs/widget-plan.json` under `delivered` with an `evidence` sentence, and `python scripts/render_progress.py` regenerated in the same commit. Contracts: `docs/ui-framework.md` (lifetime and reconciliation), `docs/widget-library-proposal.md` §5 (value and action contracts), §6 (theme), §7 (accessibility).

Phase exit from the proposal:

> - finish focus, semantics, typed actions, gestures, editable text and overlay design;
> - add theme tokens and normal/hover/press/focus/disabled/invalid resolution;
> - build a CPU-rendered reference theme and a widget gallery test application.
> 
> Exit: every primitive has deterministic layout, paint, semantics and input fixtures.
> The candidate `e.ui.control`, `e.ui.collection`, `e.ui.overlay` and
> `e.ui.navigation` identities and their phase-1 public fences are now frozen in the
> module plan; later phases extend those fences only with an explicit compatibility
> decision.

## Components

- [ ] `TypedAction`
- [ ] `ActionGestureRegion`
- [ ] `GestureArena`

## Verification

- `python scripts/check_widget_plan.py` passes and `--next` moves past this item's components.
- `python tests/test_widget_plan.py` passes.
- Both self-host suites green; `docs/progress.html` regenerated.

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
