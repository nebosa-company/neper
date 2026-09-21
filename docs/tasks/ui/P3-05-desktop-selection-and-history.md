# P3-05 — Desktop selection and history (2 components)

| field | value |
|---|---|
| phase | P3 — Productivity controls |
| module | `e.ui.control` |
| module surface | `partial`, layer 6, deps `e.gfx.geometry`, `e.gfx.paint`, `e.gfx.scene`, `e.math`, `e.mem`, `e.text.layout`, `e.text.shape`, `e.ui.accessibility`, `e.ui.input`, `e.ui.layout`, `e.ui.style`, `e.ui.widget` |
| blocked by | `P2` |
| delivered | 0 of 2 |

## Eligibility

`python scripts/check_widget_plan.py --next` names the single eligible component; it currently reports: `NEXT: P2 P2-07 ReorderableList (e.ui.collection)`. An item is eligible only when its phase and item blockers are complete and every earlier item in the phase is delivered or independently blocked. The UI family is blocked as a whole on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives (`docs/roadmap.md`, 'Experimental declarative GPU UI'); the `e.ui.*`, `e.gfx.*` and `e.text.*` modules under `docs/tasks/modules/` come first.

## Definition of done

Every component below is implemented in `e.ui.control`, exercised by a deterministic layout, paint, semantics and input fixture under `e.ui.testing`, recorded in `docs/widget-plan.json` under `delivered` with an `evidence` sentence, and `python scripts/render_progress.py` regenerated in the same commit. Contracts: `docs/ui-framework.md` (lifetime and reconciliation), `docs/widget-library-proposal.md` §5 (value and action contracts), §6 (theme), §7 (accessibility).

Phase exit from the proposal:

> - data grid/tree table with sortable/resizable/reorderable columns and editable cells;
> - tree/outline, property grid, rich selectable text, color/font pickers and command palette;
> - document tabs, wizard, window switcher and docking/resizable workspace patterns if
>   an editor-class reference app proves need;
> - host file dialogs and printing as separate capability-gated work.
> 
> Exit: an editor/database-admin workload passes desktop keyboard, screen-reader,
> multi-window and large-data tests.

## Components

- [ ] `FontPicker`
  - `docs/widget-library-proposal.md:237` | `FontPicker` | family/style/size selection over a caller- or host-supplied font catalogue |
- [ ] `NotificationList`
  - `docs/widget-library-proposal.md:295` `Toast`, `Snackbar`, `Banner` and `NotificationList` are application-owned UI;
  - `docs/widget-library-proposal.md:313` | `NotificationList` | persistent application-owned history behind transient toast/banner UI |

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
