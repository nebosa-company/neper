# e.ui.app — 10 of 10 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/ui/app.e` |
| plan row | layer 6, surface `planned`, milestone none, schedule `later` |
| blocked by | `native-accessibility-api` |
| unmet dependencies | `e.ui.accessibility`, `e.ui.animation`, `e.ui.input`, `e.ui.widget`, `e.ui.window` |

## Definition of done

Implement **exactly** the public fence below in `lib/e/ui/app.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Experimental declarative GPU UI and widget library:** extended pure image/geometry/paint values support experimental `e.text.shape`, `e.text.layout`, `e.ui.style`, `e.ui.layout`, `e.gfx.scene`, `e.asset`, `e.ui.asset`, `e.ui.window`, `e.ui.input`, `e.ui.widget`, `e.ui.animation`, `e.ui.accessibility`, `e.ui.testing` and `e.ui.app`. Delivery follows the staged vertical slice and exact lifetime/reconciliation contracts in [`ui-framework.md`](ui-framework.md) and the cross-platform catalogue in [`widget-library-proposal.md`](widget-library-proposal.md). The machine-readable pickup order is [`widget-plan.json`](widget-plan.json): a harness selects the first incomplete item in the lowest phase whose phase and item blockers are complete, then the first undelivered component in that item; blocked sibling items do not prevent an independent ready item from being selected. `python scripts/check_widget_plan.py --next` reports that blocker or component. Phase 0 freezes the candidate `e.ui.control`, `e.ui.collection`, `e.ui.overlay` and `e.ui.navigation` module identities and their phase-1 API fences before source implementation. Each delivery records evidence in the inventory and regenerates `progress.html`. Implementation remains blocked on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives. Phase 4 host-OS delivery additionally requires the reviewed shell, notification, data-exchange, file-access, activation, lifecycle, printing and permission blockers recorded in the widget plan to be resolved. It includes cross-application/desktop drag and drop, clipboard/share exchange, native file grants, associations and deep links, global shortcuts, background and power/session integration, printing, and permission-gated hardware/security services.

Blockers named in the plan must be resolved first; a blocked module is not eligible. Search `docs/roadmap.md` and `docs/decisions.md` for each blocker id.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.gpu` | partial | `lib/e/gpu.e` | 5 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.os` | spec | `lib/e/os.e` | 3 |
| `e.time` | partial | `lib/e/time.e` | 4 |
| `e.gfx.scene` | partial | `lib/e/gfx/scene.e` | 6 |
| `e.ui.accessibility` | planned | missing | 6 |
| `e.ui.animation` | planned | missing | 6 |
| `e.ui.input` | planned | missing | 6 |
| `e.ui.widget` | planned | missing | 6 |
| `e.ui.window` | planned | missing | 6 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 6 may depend on layers [0, 1, 2, 3, 4, 5, 6].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type App = struct { state: *void }
type Builder[Ctx: type] = struct { ctx: *Ctx, build: fn(*Ctx, *widget.BuildContext) -> (widget.Node, err) }
type Options = struct { window: window.Options, widget_limits: widget.Limits, frame_arena_bytes: usize, event_capacity: usize, backend: gpu.Backend }
error Closed
error Failed

fn init[Ctx: type](a: *mem.Arena, options: Options, builder: Builder[Ctx]) -> (App, err)
fn step(app: *App, timeout: time.Duration) -> (bool, err)
fn run(app: *App) -> err
fn stop(app: *App)
fn close(app: *App) -> err
```

`step` drains ordered input, rebuilds only invalidated subtrees, reconciles, lays out,
compiles a scene and presents when a frame is due. It returns `false` after the last
window closes or `stop` is called. `run` is exactly a loop over `step`; applications
retain control by calling `step` themselves. All memory comes from the application
arena plus a bounded frame arena reset after presentation.

All document decoders allocate retained strings and nodes in the arena passed to the
call. Streaming readers retain only their documented scratch state. Every writer uses
`io.Writer`; no format module opens files.

---

## 9. Interchange formats

## Missing declarations

- [ ] `App`
- [ ] `Builder`
- [ ] `Options`
- [ ] `Closed`
- [ ] `Failed`
- [ ] `init`
- [ ] `step`
- [ ] `run`
- [ ] `stop`
- [ ] `close`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/ui/layout.e`
- `lib/e/ui/style.e`

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/ui/app.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/ui_app/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 10.

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
