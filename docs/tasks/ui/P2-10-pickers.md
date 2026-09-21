# P2-10 — Pickers (6 components)

| field | value |
|---|---|
| phase | P2 — Scalable application UI |
| module | `e.ui.overlay` |
| module surface | candidate identity — its fence is not yet in `module-apis.md`; Phase 0 freezes it before any source |
| blocked by | `P1` |
| delivered | 0 of 6 |

## Eligibility

`python scripts/check_widget_plan.py --next` names the single eligible component; it currently reports: `NEXT: P0 P0-07 OverlayPortal (e.ui.widget)`. An item is eligible only when its phase and item blockers are complete and every earlier item in the phase is delivered or independently blocked. The UI family is blocked as a whole on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives (`docs/roadmap.md`, 'Experimental declarative GPU UI'); the `e.ui.*`, `e.gfx.*` and `e.text.*` modules under `docs/tasks/modules/` come first.

## Definition of done

Every component below is implemented in `e.ui.overlay`, exercised by a deterministic layout, paint, semantics and input fixture under `e.ui.testing`, recorded in `docs/widget-plan.json` under `delivered` with an `evidence` sentence, and `python scripts/render_progress.py` regenerated in the same commit. Contracts: `docs/ui-framework.md` (lifetime and reconciliation), `docs/widget-library-proposal.md` §5 (value and action contracts), §6 (theme), §7 (accessibility).

Phase exit from the proposal:

> - virtual list/grid, sections, multi-selection, reorder, pull-to-refresh and swipe actions;
> - popup/popover, context/menu bar, toast/snackbar/banner and sheets;
> - drawer, rail, bottom navigation, sidebar, breadcrumbs and navigation split;
> - page indicator/pagination, zoom view, autocomplete and token field;
> - date/range/time/duration/calendar pickers, combo box, spin box and segmented controls;
> - drag/drop, shortcut recorder, mnemonics and clipboard command routing.
> 
> Exit: mail/file-manager workloads remain bounded and responsive with 100,000 logical
> items while creating elements only for the visible range plus overscan.

## Components

- [ ] `DatePicker`
  - `docs/widget-library-proposal.md:235` | `DatePicker`, `DateRangePicker`, `TimePicker`, `DurationPicker`, `Calendar` | locale/calendar aware value selection |
- [ ] `DateRangePicker`
  - `docs/widget-library-proposal.md:235` | `DatePicker`, `DateRangePicker`, `TimePicker`, `DurationPicker`, `Calendar` | locale/calendar aware value selection |
- [ ] `TimePicker`
  - `docs/widget-library-proposal.md:235` | `DatePicker`, `DateRangePicker`, `TimePicker`, `DurationPicker`, `Calendar` | locale/calendar aware value selection |
- [ ] `DurationPicker`
  - `docs/widget-library-proposal.md:235` | `DatePicker`, `DateRangePicker`, `TimePicker`, `DurationPicker`, `Calendar` | locale/calendar aware value selection |
- [ ] `Calendar`
  - `docs/widget-library-proposal.md:235` | `DatePicker`, `DateRangePicker`, `TimePicker`, `DurationPicker`, `Calendar` | locale/calendar aware value selection |
- [ ] `ColorPicker`
  - `docs/widget-library-proposal.md:236` | `ColorPicker` | color model plus optional native-host presentation |

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
