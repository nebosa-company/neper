# P3-01 — Rich tabular data (5 components)

| field | value |
|---|---|
| phase | P3 — Productivity controls |
| module | `e.ui.collection` |
| module surface | candidate identity — its fence is not yet in `module-apis.md`; Phase 0 freezes it before any source |
| blocked by | `P2` |
| delivered | 0 of 5 |

## Eligibility

`python scripts/check_widget_plan.py --next` names the single eligible component; it currently reports: `NEXT: P1 P1-05 ScrollView (e.ui.widget)`. An item is eligible only when its phase and item blockers are complete and every earlier item in the phase is delivered or independently blocked. The UI family is blocked as a whole on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives (`docs/roadmap.md`, 'Experimental declarative GPU UI'); the `e.ui.*`, `e.gfx.*` and `e.text.*` modules under `docs/tasks/modules/` come first.

## Definition of done

Every component below is implemented in `e.ui.collection`, exercised by a deterministic layout, paint, semantics and input fixture under `e.ui.testing`, recorded in `docs/widget-plan.json` under `delivered` with an `evidence` sentence, and `python scripts/render_progress.py` regenerated in the same commit. Contracts: `docs/ui-framework.md` (lifetime and reconciliation), `docs/widget-library-proposal.md` §5 (value and action contracts), §6 (theme), §7 (accessibility).

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

- [ ] `Table`
  - `docs/widget-library-proposal.md:187` | `Table`, `DataGrid` | virtual rows, columns, sort, resize, reorder, pin, select and edit |
  - `docs/widget-library-proposal.md:189` | `TreeTable` | hierarchical rows with sortable/resizable columns |
- [ ] `DataGrid`
  - `docs/widget-library-proposal.md:187` | `Table`, `DataGrid` | virtual rows, columns, sort, resize, reorder, pin, select and edit |
- [ ] `Tree`
  - `docs/widget-library-proposal.md:188` | `Tree`, `Outline` | lazy hierarchical expansion, multi-selection and keyboard traversal |
  - `docs/widget-library-proposal.md:189` | `TreeTable` | hierarchical rows with sortable/resizable columns |
- [ ] `Outline`
  - `docs/widget-library-proposal.md:188` | `Tree`, `Outline` | lazy hierarchical expansion, multi-selection and keyboard traversal |
- [ ] `TreeTable`
  - `docs/widget-library-proposal.md:189` | `TreeTable` | hierarchical rows with sortable/resizable columns |

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
