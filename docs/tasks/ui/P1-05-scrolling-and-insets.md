# P1-05 — Scrolling and insets (4 components)

| field | value |
|---|---|
| phase | P1 — Useful desktop and mobile core |
| module | `e.ui.widget` |
| module surface | `partial`, layer 6, deps `e.data.slot_map`, `e.gfx.geometry`, `e.gfx.paint`, `e.gfx.scene`, `e.gpu`, `e.mem`, `e.text.layout`, `e.ui.input`, `e.ui.layout`, `e.ui.style`, `e.ui.window` |
| blocked by | `P0` |
| delivered | 0 of 4 |

## Eligibility

`python scripts/check_widget_plan.py --next` names the single eligible component; it currently reports: `NEXT: P0 P0-07 OverlayPortal (e.ui.widget)`. An item is eligible only when its phase and item blockers are complete and every earlier item in the phase is delivered or independently blocked. The UI family is blocked as a whole on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives (`docs/roadmap.md`, 'Experimental declarative GPU UI'); the `e.ui.*`, `e.gfx.*` and `e.text.*` modules under `docs/tasks/modules/` come first.

## Definition of done

Every component below is implemented in `e.ui.widget`, exercised by a deterministic layout, paint, semantics and input fixture under `e.ui.testing`, recorded in `docs/widget-plan.json` under `delivered` with an `evidence` sentence, and `python scripts/render_progress.py` regenerated in the same commit. Contracts: `docs/ui-framework.md` (lifetime and reconciliation), `docs/widget-library-proposal.md` §5 (value and action contracts), §6 (theme), §7 (accessibility).

Phase exit from the proposal:

> - content/layout: text, icon, image, surface, flex/grid/stack/wrap, scroll, safe area;
> - controls: button families, link, checkbox, radio, switch, slider, progress;
> - entry/forms: text field, password, search, text area, select, list box and form field;
> - containers: card, group, disclosure, tabs and split view;
> - overlay basics: tooltip, menu, alert/dialog;
> - navigation basics: app bar, toolbar, navigation stack and adaptive destination bar.
> 
> Exit: one codebase implements a settings or CRUD application in a desktop window and
> a synthetic compact touch host, with keyboard, IME and accessibility coverage.

## Components

- [ ] `ScrollView`
  - `docs/widget-library-proposal.md:104` | `ScrollView`, `Scrollbar` | one- or two-axis scrolling with explicit controller/state |
- [ ] `Scrollbar`
  - `docs/widget-library-proposal.md:104` | `ScrollView`, `Scrollbar` | one- or two-axis scrolling with explicit controller/state |
- [ ] `SafeArea`
  - `docs/widget-library-proposal.md:107` | `SafeArea`, `KeyboardAvoiding` | consume system and on-screen-keyboard insets |
- [ ] `KeyboardAvoiding`
  - `docs/widget-library-proposal.md:107` | `SafeArea`, `KeyboardAvoiding` | consume system and on-screen-keyboard insets |

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
