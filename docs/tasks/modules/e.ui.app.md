# e.ui.app — 1 of 140 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/ui/app.e` |
| plan row | layer 6, surface `partial`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | `e.os.shell` |

## Definition of done

Implement **exactly** the public fence below in `lib/e/ui/app.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Experimental declarative GPU UI and widget library:** extended pure image/geometry/paint values support experimental `e.text.shape`, `e.text.layout`, `e.ui.style`, `e.ui.layout`, `e.gfx.scene`, `e.asset`, `e.ui.asset`, `e.ui.window`, `e.ui.input`, `e.ui.widget`, `e.ui.animation`, `e.ui.accessibility`, `e.ui.testing` and `e.ui.app`. Delivery follows the staged vertical slice and exact lifetime/reconciliation contracts in [`ui-framework.md`](ui-framework.md) and the cross-platform catalogue in [`widget-library-proposal.md`](widget-library-proposal.md). The machine-readable pickup order is [`widget-plan.json`](widget-plan.json): a harness selects the first incomplete item in the lowest phase whose phase and item blockers are complete, then the first undelivered component in that item; blocked sibling items do not prevent an independent ready item from being selected. `python scripts/check_widget_plan.py --next` reports that blocker or component. Phase 0 freezes the candidate `e.ui.control`, `e.ui.collection`, `e.ui.overlay` and `e.ui.navigation` module identities and their phase-1 API fences before source implementation. Each delivery records evidence in the inventory and regenerates `progress.html`. Implementation remains blocked on reviewed embedded-asset linking, native-window, GPU-presentation and accessibility primitives. Phase 4 host-OS delivery additionally requires the reviewed shell, notification, data-exchange, file-access, activation, lifecycle, printing and permission blockers recorded in the widget plan to be resolved. It includes cross-application/desktop drag and drop, clipboard/share exchange, native file grants, associations and deep links, global shortcuts, background and power/session integration, printing, and permission-gated hardware/security services.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.gfx.geometry` | partial | `lib/e/gfx/geometry.e` | 2 |
| `e.gfx.scene` | partial | `lib/e/gfx/scene.e` | 6 |
| `e.gpu` | partial | `lib/e/gpu.e` | 5 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |
| `e.os` | spec | `lib/e/os.e` | 3 |
| `e.os.shell` | partial | missing | 4 |
| `e.time` | partial | `lib/e/time.e` | 4 |
| `e.ui.accessibility` | partial | `lib/e/ui/accessibility.e` | 6 |
| `e.ui.animation` | partial | `lib/e/ui/animation.e` | 6 |
| `e.ui.input` | partial | `lib/e/ui/input.e` | 6 |
| `e.ui.layout` | partial | `lib/e/ui/layout.e` | 2 |
| `e.ui.widget` | partial | `lib/e/ui/widget.e` | 6 |
| `e.ui.window` | partial | `lib/e/ui/window.e` | 6 |

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
fn frames_of(app: *const App) -> u64
type Debounce = struct { delay: time.Duration, interval: time.Duration, due: time.Instant, last: time.Instant, pending: bool, has_last: bool }
fn debounce(d: *Debounce, now: time.Instant, triggered: bool) -> bool
fn throttle(d: *Debounce, now: time.Instant) -> bool
fn request_frame(app: *App) -> err
fn request_idle(app: *App, work: widget.Submit) -> err
fn window_of(app: *App) -> (*window.Window, err)
type Tray = struct { id: u32, width: u32, height: u32, source: []const u32, composed: []u32, tooltip: str, badge: u32, menu: []const shell.MenuItem, open: bool }
type TrayActivationKind = enum u8 { Select, Open, Command, Dismissed, NoticeSelect, NoticeDismiss }
type Notification = struct { title: str, body: str, silent: bool }
type ContentType = struct { kind: shell.ContentKind, mime: str }
type DataProvider = struct { ctx: *void, provide: fn(*void, *mem.Arena, ContentType, *shell.Content) -> err }
type DataOffer = struct { types: []const ContentType, provider: DataProvider }
type DragOperation = struct { allow_move: bool }
type ClipboardMonitor = struct { sequence: u32 }
type DocumentGrant = struct { path: str }
type FileDialogOptions = struct { title: str, filters: []const shell.FileFilter, initial: str, default_extension: str, folder: str }
type TrayActivation = struct { kind: TrayActivationKind, command: u32, x: i32, y: i32 }
fn tray_supported() -> bool
fn tray_open(a: *mem.Arena, id: u32, icon: shell.Icon, tooltip: str) -> (Tray, err)
fn tray_set_icon(a: *mem.Arena, t: *Tray, icon: shell.Icon) -> err
fn tray_set_tooltip(a: *mem.Arena, t: *Tray, tooltip: str) -> err
fn tray_set_badge(a: *mem.Arena, t: *Tray, count: u32) -> err
fn tray_set_menu(t: *Tray, items: []const shell.MenuItem)
fn tray_poll(a: *mem.Arena, t: *Tray) -> (TrayActivation, bool, err)
fn tray_close(a: *mem.Arena, t: *Tray) -> err
fn taskbar_supported() -> bool
fn jump_list_supported() -> bool
fn taskbar_progress(a: *mem.Arena, app: *App, state: shell.ProgressState, completed: u64, total: u64) -> err
fn taskbar_overlay(a: *mem.Arena, app: *App, icon: shell.Icon, description: str) -> err
fn jump_list(a: *mem.Arena, tasks: []const shell.JumpTask) -> err
fn jump_list_clear(a: *mem.Arena) -> err
fn shell_capabilities() -> shell.Capabilities
fn open_uri(a: *mem.Arena, uri: str) -> err
fn reveal_in_file_manager(a: *mem.Arena, path: str) -> err
fn move_to_trash(a: *mem.Arena, path: str) -> err
fn notification_permission(a: *mem.Arena) -> shell.NoticePermission
fn notification_supported() -> bool
fn notification_actions_supported() -> bool
fn notify(a: *mem.Arena, t: *const Tray, n: Notification) -> (u32, err)
fn notification_update(a: *mem.Arena, t: *const Tray, notice_id: u32, n: Notification) -> err
fn notification_remove(a: *mem.Arena, t: *const Tray, notice_id: u32) -> err
fn content_type_name(t: ContentType) -> str
fn content_type_of(name: str) -> ContentType
fn content_type_of_content(c: shell.Content) -> ContentType
fn same_type(x: ContentType, y: ContentType) -> bool
fn offer_materialize(a: *mem.Arena, offer: DataOffer) -> ([]shell.Content, err)
fn offer_of(a: *mem.Arena, items: []const shell.Content) -> (DataOffer, err)
fn drag_source_supported() -> bool
fn drop_target_supported() -> bool
fn drag_offer(a: *mem.Arena, offer: DataOffer, operation: DragOperation) -> (shell.DragResult, err)
fn drop_target_open(a: *mem.Arena, app: *App, storage: *mem.Arena) -> err
fn drop_target_close(a: *mem.Arena, app: *App) -> err
fn drop_take() -> (shell.Drop, bool)
fn promised_file(name: str, contents: []const u8) -> shell.Content
fn clipboard_supported() -> bool
fn clipboard_offer(a: *mem.Arena, offer: DataOffer) -> err
fn clipboard_holds(a: *mem.Arena, t: ContentType) -> bool
fn clipboard_take(a: *mem.Arena, t: ContentType) -> (shell.Content, err)
fn clipboard_monitor() -> ClipboardMonitor
fn clipboard_changed(m: *ClipboardMonitor) -> bool
fn share_supported() -> bool
fn share_target_supported() -> bool
fn share(a: *mem.Arena, offer: DataOffer) -> err
fn share_target_take() -> (shell.Drop, bool)
fn file_dialogs_supported() -> bool
fn recent_documents_supported() -> bool
fn grant_of(path: str) -> DocumentGrant
fn grant_path(g: DocumentGrant) -> str
fn open_file(a: *mem.Arena, owner: *App, options: FileDialogOptions, multiple: bool) -> ([]DocumentGrant, err)
fn save_file(a: *mem.Arena, owner: *App, options: FileDialogOptions) -> (DocumentGrant, err)
fn pick_folder(a: *mem.Arena, owner: *App, options: FileDialogOptions) -> (DocumentGrant, err)
fn recent_add(a: *mem.Arena, g: DocumentGrant) -> err
fn activation(a: *mem.Arena, args: []const str) -> shell.Activation
fn associations_supported() -> bool
fn startup_supported() -> bool
fn single_instance_supported() -> bool
fn register_file_type(a: *mem.Arena, extension: str, program_id: str, description: str) -> err
fn unregister_file_type(a: *mem.Arena, extension: str, program_id: str) -> err
fn register_protocol(a: *mem.Arena, scheme: str, description: str) -> err
fn unregister_protocol(a: *mem.Arena, scheme: str) -> err
fn startup_registration(a: *mem.Arena, id: str, enabled: bool) -> err
fn startup_registered(a: *mem.Arena, id: str) -> (bool, err)
fn single_instance(a: *mem.Arena, id: str, args: []const str, storage: *mem.Arena) -> (bool, err)
fn desktop_exec(a: *mem.Arena, exe: str) -> (str, err)
fn activation_poll() -> (shell.Activation, bool)
type GlobalShortcutSession = struct { registered: u32 }
type PowerInhibitor = struct { held: bool }
fn global_shortcuts_supported() -> bool
fn power_inhibit_supported() -> bool
fn lifecycle_events_supported() -> bool
fn session_restore_supported() -> bool
fn global_shortcut_session() -> GlobalShortcutSession
fn global_shortcut_add(a: *mem.Arena, session: *GlobalShortcutSession, id: u32, key: shell.Hotkey) -> err
fn global_shortcut_remove(a: *mem.Arena, session: *GlobalShortcutSession, id: u32) -> err
fn global_shortcut_poll() -> (u32, bool)
fn background_permission(a: *mem.Arena) -> shell.Permission
fn login_item_set(a: *mem.Arena, id: str, enabled: bool) -> err
fn login_item_enabled(a: *mem.Arena, id: str) -> (bool, err)
fn power_inhibitor_acquire(a: *mem.Arena, keep_display: bool) -> (PowerInhibitor, err)
fn power_inhibitor_release(a: *mem.Arena, inhibitor: *PowerInhibitor) -> err
fn lifecycle_poll() -> (shell.LifecycleEvent, bool)
fn session_restore_register(a: *mem.Arena, arguments: str) -> err
fn session_restore_unregister(a: *mem.Arena) -> err
fn printing_supported() -> bool
fn print_dialogs_supported() -> bool
fn print_dialog(a: *mem.Arena, owner: *App, min_page: u32, max_page: u32) -> (shell.Printer, err)
fn page_setup_dialog(a: *mem.Arena, owner: *App, current: shell.PageSetup) -> (shell.PageSetup, err)
fn printer_open(a: *mem.Arena, name: str) -> (shell.Printer, err)
fn printer_close(a: *mem.Arena, printer: shell.Printer) -> err
fn printer_page(printer: shell.Printer) -> shell.PrintPage
fn print_job_start(a: *mem.Arena, printer: shell.Printer, document: str, output: str) -> (shell.PrintJob, err)
fn print_job_page(a: *mem.Arena, job: *shell.PrintJob, page: shell.Icon) -> err
fn print_job_end(a: *mem.Arena, job: *shell.PrintJob) -> err
fn print_job_cancel(a: *mem.Arena, job: *shell.PrintJob) -> err
fn permission_status(a: *mem.Arena, c: shell.Capability) -> shell.Permission
fn permission_request(a: *mem.Arena, c: shell.Capability) -> (shell.Permission, err)
fn camera_access(a: *mem.Arena) -> (shell.Permission, err)
fn microphone_access(a: *mem.Arena) -> (shell.Permission, err)
fn location_access(a: *mem.Arena) -> (shell.Permission, err)
fn photo_picker_supported() -> bool
fn pick_photos(a: *mem.Arena, owner: *App, multiple: bool) -> ([]DocumentGrant, err)
fn biometrics_supported() -> bool
fn biometric_verify(a: *mem.Arena, reason: str) -> (shell.Permission, err)
fn credentials_supported() -> bool
fn credential_store(a: *mem.Arena, target_name: str, user: str, secret: []const u8) -> err
fn credential_read(a: *mem.Arena, target_name: str) -> (shell.Credential, err)
fn credential_delete(a: *mem.Arena, target_name: str) -> err
fn screen_capture_supported() -> bool
fn screen_capture(a: *mem.Arena) -> (shell.Icon, err)
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

- [ ] `desktop_exec`

## Contracts that name this module

Read each line in context; they carry obligations (cancellation, bounded buffers, no hidden allocation, standard vectors) that the fence alone does not spell out.

- `docs/ui-framework.md:241` `e.ui.app` publishing and serving every step; screen readers (Narrator, Orca) read

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/ui/accessibility.e`†
- `lib/e/ui/adwicon_l2.e`
- `lib/e/ui/animation.e`
- `lib/e/ui/app.e`†
- `lib/e/ui/asset.e`
- `lib/e/ui/audit.e`
- `lib/e/ui/browser.e`
- `lib/e/ui/code_editor.e`‡

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/ui/app.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/ui_app/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 1.

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
