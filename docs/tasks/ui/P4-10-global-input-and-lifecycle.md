# P4-10 — Global input and lifecycle (6 components)

| field | value |
|---|---|
| phase | P4 — Host OS integration |
| module | `e.ui.app` |
| module surface | `partial`, layer 6, deps `e.gfx.geometry`, `e.gfx.scene`, `e.gpu`, `e.mem`, `e.os`, `e.time`, `e.ui.accessibility`, `e.ui.animation`, `e.ui.input`, `e.ui.layout`, `e.ui.widget`, `e.ui.window` |
| blocked by | `P3`, `native-lifecycle-api`, `native-shell-api` |
| delivered | 0 of 6 |

## Eligibility

`python scripts/check_widget_plan.py --next` names the single eligible component; it currently reports: `NEXT: P2 P2-07 ReorderableList (e.ui.collection)`. An item is eligible only when its phase and item blockers are complete and every earlier item in the phase is delivered or independently blocked. The UI family is blocked as a whole on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives (`docs/roadmap.md`, 'Experimental declarative GPU UI'); the `e.ui.*`, `e.gfx.*` and `e.text.*` modules under `docs/tasks/modules/` come first.

## Definition of done

Every component below is implemented in `e.ui.app`, exercised by a deterministic layout, paint, semantics and input fixture under `e.ui.testing`, recorded in `docs/widget-plan.json` under `delivered` with an `evidence` sentence, and `python scripts/render_progress.py` regenerated in the same commit. Contracts: `docs/ui-framework.md` (lifetime and reconciliation), `docs/widget-library-proposal.md` §5 (value and action contracts), §6 (theme), §7 (accessibility).

Phase exit from the proposal:

> - system tray/status items with command menus and badge state;
> - Windows Jump Lists, taskbar progress and taskbar overlay icons;
> - operating-system notifications, actions, activation routing and permission state;
> - typed clipboard, sharing and cross-application/desktop drag and drop;
> - native file/folder dialogs, sandbox document grants and recent documents;
> - file/protocol/startup associations, deep links and single-instance activation;
> - URI opening, file-manager reveal and recoverable trash/recycle operations;
> - global shortcuts, login/background permission, lifecycle restoration and power inhibition;
> - native printing, page setup and cancellable print jobs;
> - capability-gated camera, microphone, photo library, location, biometric,
>   credential-store and screen-capture services.
> 
> Its individual work items are blocked on the reviewed `native-shell-api`,
> `native-notification-api`, `native-data-exchange-api`, `native-file-access-api`,
> `native-activation-api`, `native-lifecycle-api`, `native-print-api` or
> `native-permission-api` host primitive they require. Unrelated items can proceed when
> their own primitive is ready. Unsupported platforms must return an
> explicit capability result; they must not silently emulate protected OS integration
> with in-app UI.
> 
> Exit: desktop and mobile reference apps exercise data exchange, file grants,
> activation, lifecycle, shell, notification and permission flows on each supported
> host, with deterministic unsupported/denied tests elsewhere.

## Components

- [ ] `GlobalShortcutSession`
  - `docs/widget-library-proposal.md:291` | `GlobalShortcutSession`, `BackgroundPermission`, `LoginItem`, `PowerInhibitor`, `SessionLifecycle`, `SessionRestore` | permission-aware gl
- [ ] `BackgroundPermission`
  - `docs/widget-library-proposal.md:291` | `GlobalShortcutSession`, `BackgroundPermission`, `LoginItem`, `PowerInhibitor`, `SessionLifecycle`, `SessionRestore` | permission-aware gl
- [ ] `LoginItem`
  - `docs/widget-library-proposal.md:291` | `GlobalShortcutSession`, `BackgroundPermission`, `LoginItem`, `PowerInhibitor`, `SessionLifecycle`, `SessionRestore` | permission-aware gl
- [ ] `PowerInhibitor`
  - `docs/widget-library-proposal.md:291` | `GlobalShortcutSession`, `BackgroundPermission`, `LoginItem`, `PowerInhibitor`, `SessionLifecycle`, `SessionRestore` | permission-aware gl
- [ ] `SessionLifecycle`
  - `docs/widget-library-proposal.md:291` | `GlobalShortcutSession`, `BackgroundPermission`, `LoginItem`, `PowerInhibitor`, `SessionLifecycle`, `SessionRestore` | permission-aware gl
- [ ] `SessionRestore`
  - `docs/widget-library-proposal.md:291` | `GlobalShortcutSession`, `BackgroundPermission`, `LoginItem`, `PowerInhibitor`, `SessionLifecycle`, `SessionRestore` | permission-aware gl

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
