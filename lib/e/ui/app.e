// `e.ui.app` (D802): the scheduling primitive over the whole chain. `init` opens the
// device, the window, the renderer, the widget runtime and the input queue, and
// keeps the application's builder; `step` waits up to the timeout for input, drains
// it into dispatch, and when a frame is due -- the first step, an event delivered,
// an element invalidated, a resize -- resets the frame arena, builds the tree
// through the builder, reconciles it under the window's logical size, renders it
// into the window's target and shows it. `run` repeats `step`; `stop` ends it.
//
// The builder is generic over its context and the app is not: `init[Ctx]` keeps
// the context erased to `*void` and the build function's bits behind a pun a
// per-`Ctx` trampoline reads back, since a function value has no cast.
// ponytail: one window per app; `frame_arena_bytes` is taken whole from the
// application arena at `init`.

use e.gpu
use e.mem
use e.os
use e.os.shell
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.widget
use e.ui.window

type App = struct { state: *void }
type Builder[Ctx: type] = struct { ctx: *Ctx, build: fn(*Ctx, *widget.BuildContext) -> (widget.Node, err) }
type Options = struct { window: window.Options, widget_limits: widget.Limits, frame_arena_bytes: usize, event_capacity: usize, backend: gpu.Backend }
error Closed
error Failed

type Pun[Ctx: type] = union { typed: fn(*Ctx, *widget.BuildContext) -> (widget.Node, err), bits: usize }
type State = struct {
    arena: *mem.Arena,
    device: *gpu.Device,
    win: window.Window,
    renderer: scene.Renderer,
    runtime: widget.Runtime,
    events: input.Queue,
    frame_storage: []u8,
    ctx: *void,
    build_bits: usize,
    trampoline: fn(*void, usize, *widget.BuildContext) -> (widget.Node, err),
    frame_due: bool,
    stopped: bool,
    closed: bool,
    frames: u64,
}

// The per-context trampoline: the erased context and the build function's bits
// become the typed call.
fn call_builder[Ctx: type](ctx: *void, bits: usize, build_context: *widget.BuildContext) -> (widget.Node, err) {
    var pun: Pun[Ctx] = zero
    pun.bits = bits
    let (node, build_error) = pun.typed(mem.cast[*Ctx](ctx), build_context)
    ret (node, build_error)
}

fn init[Ctx: type](a: *mem.Arena, options: Options, builder: Builder[Ctx]) -> (App, err) {
    if options.frame_arena_bytes < 65536usize || options.event_capacity == 0usize { ret (zero, Failed) }
    let (device, open_error) = gpu.open(a, options.backend, 0u32)
    if open_error != ok { ret (zero, Failed) }
    let (win, window_error) = window.open(a, device, options.window)
    if window_error != ok {
        let abandoned = gpu.close(device)
        ret (zero, Failed)
    }
    var opened = win
    let (queue, queue_error) = gpu.queue(device)
    if queue_error != ok { ret (zero, Failed) }
    let (renderer, renderer_error) = scene.renderer(a, device, queue, 4u32, 256u32)
    if renderer_error != ok { ret (zero, Failed) }
    let (states, states_error) = mem.alloc[State](a, 1usize)
    if states_error != ok { ret (zero, Failed) }
    var s: State = zero
    s.arena = a
    s.device = device
    s.win = opened
    s.renderer = renderer
    let (runtime, runtime_error) = widget.runtime(a, &states[0usize].renderer, options.widget_limits)
    if runtime_error != ok { ret (zero, Failed) }
    s.runtime = runtime
    let (events, events_error) = input.queue(a, options.event_capacity)
    if events_error != ok { ret (zero, Failed) }
    s.events = events
    let (frame_storage, storage_error) = mem.alloc[u8](a, options.frame_arena_bytes)
    if storage_error != ok { ret (zero, Failed) }
    s.frame_storage = frame_storage
    s.ctx = mem.cast[*void](builder.ctx)
    var pun: Pun[Ctx] = zero
    pun.typed = builder.build
    s.build_bits = pun.bits
    s.trampoline = call_builder[Ctx]
    s.frame_due = true
    states[0usize] = s
    ret (App { state: mem.cast[*void](&states[0usize]) }, ok)
}

fn state_of(app: *App) -> (*State, err) {
    let s = mem.cast[*State](app.state)
    if mem.address_of(s) == 0usize || s.closed { ret (s, Closed) }
    ret (s, ok)
}

// One frame of the application: input, then a frame when one is due.
fn step(app: *App, timeout: time.Duration) -> (bool, err) {
    let (s, state_error) = state_of(app)
    if state_error != ok { ret (false, state_error) }
    if s.stopped { ret (false, ok) }
    var remaining = timeout
    var drained = 0usize
    while drained < 256usize {
        let (event, any, poll_error) = input.poll(&s.events, remaining)
        if poll_error != ok { ret (false, Failed) }
        if !any { break }
        remaining = time.Duration { nanos: 0i64 }
        drained += 1usize
        if event.tag == .Close {
            s.stopped = true
            ret (false, ok)
        }
        if event.tag == .Resize || event.tag == .Frame { s.frame_due = true }
        let dispatch_error = widget.dispatch(&s.runtime, event)
        if dispatch_error != ok { ret (false, dispatch_error) }
        s.frame_due = true
    }
    if !s.frame_due { ret (true, ok) }
    let frame_error = present_frame(s)
    if frame_error != ok { ret (false, frame_error) }
    ret (true, ok)
}

fn present_frame(s: *State) -> err {
    let (metrics, metrics_error) = window.metrics(&s.win)
    if metrics_error != ok { ret Failed }
    var frame = mem.arena_from(s.frame_storage)
    let (root, has_root) = widget.root_of(&s.runtime)
    var build_context = widget.BuildContext { runtime: &s.runtime, element: root, frame: s.frames }
    let (tree, build_error) = s.trampoline(s.ctx, s.build_bits, &build_context)
    if build_error != ok { ret build_error }
    let limits = ui_layout.Constraints { min_width: 0.0, max_width: metrics.logical_size.width, min_height: 0.0, max_height: metrics.logical_size.height }
    let (compiled, reconcile_error) = widget.reconcile(&s.runtime, &frame, tree, limits)
    if reconcile_error != ok { ret reconcile_error }
    let (canvas, canvas_error) = window.draw_target(&s.win)
    if canvas_error != ok { ret Failed }
    let render_error = scene.render(&s.renderer, compiled, canvas, metrics.logical_size)
    if render_error != ok { ret render_error }
    if window.request_frame(&s.win) != ok { ret Failed }
    s.frames += 1u64
    s.frame_due = false
    ret ok
}

fn run(app: *App) -> err {
    while true {
        let (more, step_error) = step(app, time.millis(16i64))
        if step_error != ok { ret step_error }
        if !more { ret ok }
    }
    ret ok
}

fn stop(app: *App) {
    let (s, state_error) = state_of(app)
    if state_error != ok { ret }
    s.stopped = true
}

fn close(app: *App) -> err {
    let (s, state_error) = state_of(app)
    if state_error != ok { ret state_error }
    let events_closed = input.close(&s.events)
    let runtime_closed = widget.close(&s.runtime)
    let renderer_closed = scene.close(&s.renderer)
    let window_closed = window.close(&s.win)
    let device_closed = gpu.close(s.device)
    s.closed = true
    ret ok
}

// The frames presented so far, for a test that steps by hand.
fn frames_of(app: *const App) -> u64 {
    let s = mem.cast[*State](app.state)
    if mem.address_of(s) == 0usize { ret 0u64 }
    ret s.frames
}

// ---------------------------------------------------------------- tray (D886)
//
// The system tray (widget plan P4-01) as a typed controller over `e.os.shell`: a
// `Tray` is the caller's icon, tooltip, badge and command menu under one id, and
// `tray_poll` turns the shell's activations into the caller's -- a context
// activation with a menu attached becomes the shell's popup menu at the pointer,
// and its choice a `.Command` with the item's id. The badge is composed into the
// icon here, since the shell has no badge of its own: a filled disc in the top
// right corner while the count is not zero. ponytail: a disc, not the number; a
// glyph needs a face the app does not hold at this level. Every call answers
// `shell.Unsupported` where the host has no tray, and `tray_supported` says so
// before one is opened.

type Tray = struct { id: u32, width: u32, height: u32, source: []const u32, composed: []u32, tooltip: str, badge: u32, menu: []const shell.MenuItem, open: bool }
type TrayActivationKind = enum u8 { Select, Open, Command, Dismissed, NoticeSelect, NoticeDismiss }
type TrayActivation = struct { kind: TrayActivationKind, command: u32, x: i32, y: i32 }

const BADGE_COLOUR: u32 = 4293281869u32

fn tray_supported() -> bool {
    ret shell.capabilities().tray
}

fn composed_icon(t: *const Tray) -> shell.Icon {
    ret shell.Icon { width: t.width, height: t.height, pixels: t.composed[0usize..t.composed.len] }
}

// The source pixels, and the badge over them when the count is not zero: a disc
// of a quarter of the shorter side, its centre a radius in from the top right.
fn compose(t: *Tray) {
    let count = usize(t.width) * usize(t.height)
    var at = 0usize
    while at < count {
        t.composed[at] = t.source[at]
        at += 1usize
    }
    if t.badge == 0u32 { ret }
    var side = t.width
    if t.height < side { side = t.height }
    let radius = i32(side / 4u32)
    if radius == 0i32 { ret }
    let centre_x = i32(t.width) - radius
    let centre_y = radius
    var y = 0i32
    while y < i32(t.height) {
        var x = 0i32
        while x < i32(t.width) {
            let dx = x - centre_x
            let dy = y - centre_y
            if dx * dx + dy * dy <= radius * radius { t.composed[usize(y) * usize(t.width) + usize(x)] = BADGE_COLOUR }
            x += 1i32
        }
        y += 1i32
    }
}

fn tray_open(a: *mem.Arena, id: u32, icon: shell.Icon, tooltip: str) -> (Tray, err) {
    var t: Tray = zero
    if !tray_supported() { ret (t, shell.Unsupported) }
    if icon.width == 0u32 || icon.height == 0u32 || icon.pixels.len < usize(icon.width) * usize(icon.height) { ret (t, shell.Invalid) }
    let (composed, allocation_error) = mem.alloc[u32](a, usize(icon.width) * usize(icon.height))
    if allocation_error != ok { ret (t, allocation_error) }
    t.id = id
    t.width = icon.width
    t.height = icon.height
    t.source = icon.pixels
    t.composed = composed
    t.tooltip = tooltip
    compose(&t)
    let added = shell.tray_add(a, id, composed_icon(&t), tooltip)
    if added != ok { ret (t, added) }
    t.open = true
    ret (t, ok)
}

fn tray_push(a: *mem.Arena, t: *Tray) -> err {
    if !t.open { ret shell.NotFound }
    compose(t)
    ret shell.tray_update(a, t.id, composed_icon(t), t.tooltip)
}

// A new icon has to be the size the tray was opened with, since the composed
// pixels are allocated once.
fn tray_set_icon(a: *mem.Arena, t: *Tray, icon: shell.Icon) -> err {
    if icon.width != t.width || icon.height != t.height || icon.pixels.len < usize(icon.width) * usize(icon.height) { ret shell.Invalid }
    t.source = icon.pixels
    ret tray_push(a, t)
}

fn tray_set_tooltip(a: *mem.Arena, t: *Tray, tooltip: str) -> err {
    t.tooltip = tooltip
    ret tray_push(a, t)
}

fn tray_set_badge(a: *mem.Arena, t: *Tray, count: u32) -> err {
    t.badge = count
    ret tray_push(a, t)
}

// The menu the next context activation shows; the items are the caller's and
// have to outlive the tray. An empty menu means a context activation is reported
// as such and nothing is shown.
fn tray_set_menu(t: *Tray, items: []const shell.MenuItem) {
    t.menu = items
}

// The oldest activation of this tray, with a context activation resolved through
// the menu when one is attached: `.Command` names the chosen item, `.Dismissed`
// a menu closed without a choice. Activations of other trays are left in the queue's
// order and dropped, since a tray is the whole of its id.
fn tray_poll(a: *mem.Arena, t: *Tray) -> (TrayActivation, bool, err) {
    var none: TrayActivation = zero
    if !t.open { ret (none, false, shell.NotFound) }
    while true {
        let (event, any) = shell.tray_poll()
        if !any { ret (none, false, ok) }
        if event.id != t.id { continue }
        var reported: TrayActivation = zero
        reported.x = event.x
        reported.y = event.y
        if event.kind == .Select {
            reported.kind = .Select
            ret (reported, true, ok)
        }
        if event.kind == .Open {
            reported.kind = .Open
            ret (reported, true, ok)
        }
        if event.kind == .NoticeSelect {
            reported.kind = .NoticeSelect
            ret (reported, true, ok)
        }
        if event.kind == .NoticeDismiss {
            reported.kind = .NoticeDismiss
            ret (reported, true, ok)
        }
        if t.menu.len == 0usize {
            reported.kind = .Dismissed
            ret (reported, true, ok)
        }
        let (chosen, has_chosen, menu_error) = shell.popup_menu(a, t.menu, event.x, event.y)
        if menu_error != ok { ret (none, false, menu_error) }
        reported.kind = .Dismissed
        if has_chosen {
            reported.kind = .Command
            reported.command = chosen
        }
        ret (reported, true, ok)
    }
    ret (none, false, ok)
}

fn tray_close(a: *mem.Arena, t: *Tray) -> err {
    if !t.open { ret shell.NotFound }
    t.open = false
    ret shell.tray_remove(a, t.id)
}

// ------------------------------------------------- taskbar and jump list (D887)
//
// Widget plan P4-02, three thin controllers over `e.os.shell` for the app's own
// window: the taskbar button's progress and overlay, and the jump list's tasks.
// Each answers `shell.Unsupported` where the host has no taskbar or jump list,
// which `taskbar_supported` and `jump_list_supported` say first.

fn taskbar_supported() -> bool {
    ret shell.capabilities().taskbar
}

fn jump_list_supported() -> bool {
    ret shell.capabilities().jump_list
}

fn host_window(app: *App) -> (os.Window, err) {
    let (s, state_error) = state_of(app)
    if state_error != ok { ret (zero, state_error) }
    let (handle, host_error) = window.host_window(&s.win)
    if host_error != ok { ret (zero, Failed) }
    ret (handle, ok)
}

fn taskbar_progress(a: *mem.Arena, app: *App, state: shell.ProgressState, completed: u64, total: u64) -> err {
    let (handle, handle_error) = host_window(app)
    if handle_error != ok { ret handle_error }
    ret shell.taskbar_progress(a, handle, state, completed, total)
}

// An icon of no width clears the overlay.
fn taskbar_overlay(a: *mem.Arena, app: *App, icon: shell.Icon, description: str) -> err {
    let (handle, handle_error) = host_window(app)
    if handle_error != ok { ret handle_error }
    ret shell.taskbar_overlay(a, handle, icon, description)
}

// The application's jump list tasks, replaced whole; `jump_list_clear` removes it.
fn jump_list(a: *mem.Arena, tasks: []const shell.JumpTask) -> err {
    ret shell.jump_list(a, tasks)
}

fn jump_list_clear(a: *mem.Arena) -> err {
    ret shell.jump_list_clear(a)
}

// ---------------------------------------------- shell file operations (D888)
//
// Widget plan P4-09: the host shell's open verb, file-manager reveal and
// recoverable deletion, delegated as they are. Each is the shell's answer --
// `shell.Invalid` for an empty argument, `shell.NotFound` for a missing item,
// `shell.Unsupported` where the host has no such verb -- and `shell_capabilities`
// says beforehand which verbs this host has.

fn shell_capabilities() -> shell.Capabilities {
    ret shell.capabilities()
}

fn open_uri(a: *mem.Arena, uri: str) -> err {
    ret shell.open_uri(a, uri)
}

fn reveal_in_file_manager(a: *mem.Arena, path: str) -> err {
    ret shell.reveal(a, path)
}

fn move_to_trash(a: *mem.Arena, path: str) -> err {
    ret shell.trash(a, path)
}

// ------------------------------------------------------- notifications (D889)
//
// Widget plan P4-03 over `e.os.shell`'s notices: a `Notification` published on
// the app's tray item (the shell's balloon on Windows; the desktop's daemon on
// Linux, where the tray is not consulted), updated in place by its id and
// removed where the host can. Its activation and dismissal come back through
// `tray_poll` as `.NoticeSelect` and `.NoticeDismiss`. Buttons on a notice are
// what neither host offers this way, so `notification_actions_supported` is
// false and the record says so before a caller designs for them; the permission
// is the host's answer, asked before the first notice.

type Notification = struct { title: str, body: str, silent: bool }

fn notification_permission(a: *mem.Arena) -> shell.NoticePermission {
    ret shell.notice_permission(a)
}

fn notification_supported() -> bool {
    ret shell.capabilities().notices
}

fn notification_actions_supported() -> bool {
    ret shell.capabilities().notice_actions
}

fn notify(a: *mem.Arena, t: *const Tray, n: Notification) -> (u32, err) {
    let (id, publish_error) = shell.notice_publish(a, t.id, n.title, n.body, n.silent)
    ret (id, publish_error)
}

fn notification_update(a: *mem.Arena, t: *const Tray, notice_id: u32, n: Notification) -> err {
    ret shell.notice_update(a, t.id, notice_id, n.title, n.body, n.silent)
}

fn notification_remove(a: *mem.Arena, t: *const Tray, notice_id: u32) -> err {
    ret shell.notice_remove(a, t.id, notice_id)
}

// -------------------------------------------------- typed data exchange (D891)
//
// Widget plan P4-04: one typed model over `e.os.shell`'s representations. A
// `ContentType` is a kind and, for bytes, the MIME name the other side registers
// the same way; its name is the MIME name the kind maps to, and `content_type_of`
// reads one back. A `DataOffer` is the types on offer and a `DataProvider` that
// produces each representation when a hand-off asks -- the clipboard write or
// the drag start, not the offer's construction -- so a large representation is
// built only for a receiver that takes it. `offer_of` is the eager case: an
// offer over representations already in hand. The representation itself is
// `shell.Content`; there is no second type for it.

type ContentType = struct { kind: shell.ContentKind, mime: str }
type DataProvider = struct { ctx: *void, provide: fn(*void, *mem.Arena, ContentType, *shell.Content) -> err }
type DataOffer = struct { types: []const ContentType, provider: DataProvider }
type Held = struct { items: []const shell.Content }

fn content_type_name(t: ContentType) -> str {
    if t.kind == .Text { ret "text/plain;charset=utf-8" }
    if t.kind == .Files { ret "text/uri-list" }
    if t.kind == .Image { ret "image/bmp" }
    ret t.mime
}

fn same_text(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// The type a MIME name means here; any other name is bytes under that name.
fn content_type_of(name: str) -> ContentType {
    if same_text(name, "text/plain;charset=utf-8") || same_text(name, "text/plain") { ret ContentType { kind: .Text, mime: "" } }
    if same_text(name, "text/uri-list") { ret ContentType { kind: .Files, mime: "" } }
    if same_text(name, "image/bmp") { ret ContentType { kind: .Image, mime: "" } }
    ret ContentType { kind: .Bytes, mime: name }
}

fn content_type_of_content(c: shell.Content) -> ContentType {
    ret ContentType { kind: c.kind, mime: c.mime }
}

fn same_type(x: ContentType, y: ContentType) -> bool {
    if x.kind != y.kind { ret false }
    if x.kind != .Bytes { ret true }
    ret same_text(x.mime, y.mime)
}

// Every representation on offer, produced now, in the offer's order.
fn offer_materialize(a: *mem.Arena, offer: DataOffer) -> ([]shell.Content, err) {
    var nothing: []shell.Content = zero
    if offer.types.len == 0usize { ret (nothing, shell.Invalid) }
    let (items, allocation_error) = mem.alloc[shell.Content](a, offer.types.len)
    if allocation_error != ok { ret (nothing, allocation_error) }
    var at = 0usize
    while at < offer.types.len {
        var produced: shell.Content = zero
        let provide_error = offer.provider.provide(offer.provider.ctx, a, offer.types[at], &produced)
        if provide_error != ok { ret (nothing, provide_error) }
        if !same_type(content_type_of_content(produced), offer.types[at]) { ret (nothing, shell.Invalid) }
        items[at] = produced
        at += 1usize
    }
    ret (items[0usize..offer.types.len], ok)
}

fn provide_held(ctx: *void, a: *mem.Arena, t: ContentType, out: *shell.Content) -> err {
    let held = mem.cast[*Held](ctx)
    var at = 0usize
    while at < held.items.len {
        if same_type(content_type_of_content(held.items[at]), t) {
            *out = held.items[at]
            ret ok
        }
        at += 1usize
    }
    ret shell.NotFound
}

// An offer over representations in hand; the slice has to outlive the offer.
fn offer_of(a: *mem.Arena, items: []const shell.Content) -> (DataOffer, err) {
    var nothing: DataOffer = zero
    if items.len == 0usize { ret (nothing, shell.Invalid) }
    let (types, types_error) = mem.alloc[ContentType](a, items.len)
    if types_error != ok { ret (nothing, types_error) }
    let (holders, holder_error) = mem.alloc[Held](a, 1usize)
    if holder_error != ok { ret (nothing, holder_error) }
    var at = 0usize
    while at < items.len {
        types[at] = content_type_of_content(items[at])
        at += 1usize
    }
    holders[0usize] = Held { items: items }
    ret (DataOffer { types: types[0usize..items.len], provider: DataProvider { ctx: mem.cast[*void](&holders[0usize]), provide: provide_held } }, ok)
}

// ---------------------------------------- cross-application drag and drop (D892)
//
// Widget plan P4-05 over `e.os.shell`: a drag from this program offers a
// `DataOffer`, materialised at the start (the shell copies each block only when
// the receiver asks for it) and blocks until the receiver copies, moves or the
// drag is cancelled -- the `DragOperation` the caller allowed and the result it
// got; a drop target is the app's own window, with the drops copied into the
// caller's storage arena and taken in order by `drop_take`; a `PromisedFile`
// is a representation the receiver writes out itself, its name and its
// contents, which Explorer takes as a file. Both sides say `shell.Unsupported`
// where the host has neither, and the two predicates say so first.

type DragOperation = struct { allow_move: bool }

fn drag_source_supported() -> bool {
    ret shell.capabilities().drag_source
}

fn drop_target_supported() -> bool {
    ret shell.capabilities().drop_target
}

// The drag, from a pointer-down of the caller's; the answer is what the receiver did.
fn drag_offer(a: *mem.Arena, offer: DataOffer, operation: DragOperation) -> (shell.DragResult, err) {
    let (items, materialize_error) = offer_materialize(a, offer)
    if materialize_error != ok { ret (.Cancelled, materialize_error) }
    let (result, drag_error) = shell.drag_start(a, items, operation.allow_move)
    ret (result, drag_error)
}

fn drop_target_open(a: *mem.Arena, app: *App, storage: *mem.Arena) -> err {
    let (handle, handle_error) = host_window(app)
    if handle_error != ok { ret handle_error }
    ret shell.drop_target_register(a, handle, storage)
}

fn drop_target_close(a: *mem.Arena, app: *App) -> err {
    let (handle, handle_error) = host_window(app)
    if handle_error != ok { ret handle_error }
    ret shell.drop_target_unregister(a, handle)
}

fn drop_take() -> (shell.Drop, bool) {
    let (landed, any) = shell.drop_poll()
    ret (landed, any)
}

// A file the receiver will write: its name and its contents, as one representation.
fn promised_file(name: str, contents: []const u8) -> shell.Content {
    ret shell.Content { kind: .Promise, mime: "", text: name, paths: zero, image: zero, bytes: contents }
}

// ------------------------------------------- system clipboard and sharing (D893)
//
// Widget plan P4-06. The clipboard takes a `DataOffer` -- materialised at the
// write, one representation each -- and gives one representation back by its
// type; `clipboard_holds` asks without reading. A `ClipboardMonitor` is the
// shell's change counter remembered, and `clipboard_changed` compares it, so a
// program learns of a change without reading anyone's clipboard unasked.
// Sharing -- the share sheet and being a share target -- is a WinRT flow on
// Windows and a portal on Linux, neither of which this library speaks, so both
// are `shell.Unsupported` and the predicates say so first.

type ClipboardMonitor = struct { sequence: u32 }

fn clipboard_supported() -> bool {
    ret shell.capabilities().clipboard_text
}

fn clipboard_offer(a: *mem.Arena, offer: DataOffer) -> err {
    let (items, materialize_error) = offer_materialize(a, offer)
    if materialize_error != ok { ret materialize_error }
    ret shell.clipboard_write(a, items)
}

fn clipboard_holds(a: *mem.Arena, t: ContentType) -> bool {
    ret shell.clipboard_has(a, t.kind, t.mime)
}

fn clipboard_take(a: *mem.Arena, t: ContentType) -> (shell.Content, err) {
    let (item, read_error) = shell.clipboard_read(a, t.kind, t.mime)
    ret (item, read_error)
}

fn clipboard_monitor() -> ClipboardMonitor {
    ret ClipboardMonitor { sequence: shell.clipboard_sequence() }
}

// Whether the clipboard changed since the last ask; the monitor moves with it.
fn clipboard_changed(m: *ClipboardMonitor) -> bool {
    let now = shell.clipboard_sequence()
    if now == m.sequence { ret false }
    m.sequence = now
    ret true
}

fn share_supported() -> bool {
    ret false
}

fn share_target_supported() -> bool {
    ret false
}

fn share(a: *mem.Arena, offer: DataOffer) -> err {
    if offer.types.len == 0usize { ret shell.Invalid }
    ret shell.Unsupported
}

fn share_target_take() -> (shell.Drop, bool) {
    var none: shell.Drop = zero
    ret (none, false)
}

// --------------------------------------------- file and document access (D895)
//
// Widget plan P4-07 over `e.os.shell`'s dialogs: the native open, save and
// folder dialogs over the app's window (or none), each answering a
// `DocumentGrant`. On the desktop hosts a grant is the path itself -- nothing
// sandboxes them -- and it is a type of its own so that a sandboxed host can
// carry its bookmark in it later without the callers changing. The recent list
// takes a grant. Every dialog is `shell.Cancelled` when the user closes it
// without a choice and `shell.Unsupported` where the host has none, which the
// predicates say first.

type DocumentGrant = struct { path: str }
type FileDialogOptions = struct { title: str, filters: []const shell.FileFilter, initial: str, default_extension: str }

fn file_dialogs_supported() -> bool {
    ret shell.capabilities().file_dialogs
}

fn recent_documents_supported() -> bool {
    ret shell.capabilities().recent_documents
}

fn grant_of(path: str) -> DocumentGrant {
    ret DocumentGrant { path: path }
}

fn grant_path(g: DocumentGrant) -> str {
    ret g.path
}

fn owner_window(owner: *App) -> (os.Window, err) {
    var none: os.Window = zero
    if mem.address_of(owner) == 0usize { ret (none, ok) }
    let (handle, handle_error) = host_window(owner)
    ret (handle, handle_error)
}

fn show_dialog(a: *mem.Arena, owner: *App, kind: shell.DialogKind, options: FileDialogOptions, multiple: bool) -> ([]const str, err) {
    var nothing: []const str = zero
    let (window_handle, owner_error) = owner_window(owner)
    if owner_error != ok { ret (nothing, owner_error) }
    let dialog = shell.FileDialog { kind: kind, title: options.title, filters: options.filters, multiple: multiple, initial: options.initial, default_extension: options.default_extension }
    let (paths, dialog_error) = shell.file_dialog(a, window_handle, dialog)
    ret (paths, dialog_error)
}

fn grants_of(a: *mem.Arena, paths: []const str) -> ([]DocumentGrant, err) {
    var nothing: []DocumentGrant = zero
    let (grants, allocation_error) = mem.alloc[DocumentGrant](a, paths.len)
    if allocation_error != ok { ret (nothing, allocation_error) }
    var at = 0usize
    while at < paths.len {
        grants[at] = DocumentGrant { path: paths[at] }
        at += 1usize
    }
    ret (grants[0usize..paths.len], ok)
}

// The open dialog: one grant, or every chosen one when `multiple`.
fn open_file(a: *mem.Arena, owner: *App, options: FileDialogOptions, multiple: bool) -> ([]DocumentGrant, err) {
    var nothing: []DocumentGrant = zero
    let (paths, dialog_error) = show_dialog(a, owner, .Open, options, multiple)
    if dialog_error != ok { ret (nothing, dialog_error) }
    let (grants, grants_error) = grants_of(a, paths)
    ret (grants, grants_error)
}

fn save_file(a: *mem.Arena, owner: *App, options: FileDialogOptions) -> (DocumentGrant, err) {
    var nothing: DocumentGrant = zero
    let (paths, dialog_error) = show_dialog(a, owner, .Save, options, false)
    if dialog_error != ok { ret (nothing, dialog_error) }
    if paths.len != 1usize { ret (nothing, shell.Failed) }
    ret (DocumentGrant { path: paths[0usize] }, ok)
}

fn pick_folder(a: *mem.Arena, owner: *App, options: FileDialogOptions) -> (DocumentGrant, err) {
    var nothing: DocumentGrant = zero
    let (paths, dialog_error) = show_dialog(a, owner, .Folder, options, false)
    if dialog_error != ok { ret (nothing, dialog_error) }
    if paths.len != 1usize { ret (nothing, shell.Failed) }
    ret (DocumentGrant { path: paths[0usize] }, ok)
}

fn recent_add(a: *mem.Arena, g: DocumentGrant) -> err {
    ret shell.recent_add(a, g.path)
}

// --------------------------------------------- activation and associations (D897)
//
// Widget plan P4-08 over `e.os.shell`: what the command line means as an
// `Activation`, file and protocol associations registered for this user and
// removed again, the program started at login or not, and a single instance --
// the first under an id receives the later ones' arguments through
// `activation_poll`, a later one hands its own over and is told to exit.
// Declarative package registration is a packaging matter this library does
// not have; the runtime routing is here. The predicates say what the host has.

fn activation(a: *mem.Arena, args: []const str) -> shell.Activation {
    ret shell.activation_of(a, args)
}

fn associations_supported() -> bool {
    ret shell.capabilities().associations
}

fn startup_supported() -> bool {
    ret shell.capabilities().startup
}

fn single_instance_supported() -> bool {
    ret shell.capabilities().single_instance
}

fn register_file_type(a: *mem.Arena, extension: str, program_id: str, description: str) -> err {
    ret shell.associate_file(a, extension, program_id, description)
}

fn unregister_file_type(a: *mem.Arena, extension: str, program_id: str) -> err {
    ret shell.dissociate_file(a, extension, program_id)
}

fn register_protocol(a: *mem.Arena, scheme: str, description: str) -> err {
    ret shell.associate_protocol(a, scheme, description)
}

fn unregister_protocol(a: *mem.Arena, scheme: str) -> err {
    ret shell.dissociate_protocol(a, scheme)
}

fn startup_registration(a: *mem.Arena, id: str, enabled: bool) -> err {
    ret shell.startup_set(a, id, enabled)
}

fn startup_registered(a: *mem.Arena, id: str) -> (bool, err) {
    let (enabled, query_error) = shell.startup_enabled(a, id)
    ret (enabled, query_error)
}

fn single_instance(a: *mem.Arena, id: str, args: []const str, storage: *mem.Arena) -> (bool, err) {
    let (first, instance_error) = shell.single_instance(a, id, args, storage)
    ret (first, instance_error)
}

fn activation_poll() -> (shell.Activation, bool) {
    let (received, any) = shell.activation_poll()
    ret (received, any)
}

// ------------------------------------------- global input and lifecycle (D899)
//
// Widget plan P4-10 over `e.os.shell`: a `GlobalShortcutSession` holds the
// shortcuts registered for the whole desktop under the caller's ids and drains
// their presses; the background permission is the host's answer; a login item
// is D897's startup registration under another name, since that is what a login
// item is on both hosts; a `PowerInhibitor` keeps the system (and the display,
// when asked) awake until released; the session's shutdown, suspend and resume
// come through `lifecycle_poll`; and session restore is the host relaunching
// the program with the arguments it registered, which `activation` then reads.
// The predicates say what the host has; the rest is `shell.Unsupported`.

type GlobalShortcutSession = struct { registered: u32 }
type PowerInhibitor = struct { held: bool }

fn global_shortcuts_supported() -> bool {
    ret shell.capabilities().hotkeys
}

fn power_inhibit_supported() -> bool {
    ret shell.capabilities().power_inhibit
}

fn lifecycle_events_supported() -> bool {
    ret shell.capabilities().lifecycle_events
}

fn session_restore_supported() -> bool {
    ret shell.capabilities().restart
}

fn global_shortcut_session() -> GlobalShortcutSession {
    ret GlobalShortcutSession { registered: 0u32 }
}

fn global_shortcut_add(a: *mem.Arena, session: *GlobalShortcutSession, id: u32, key: shell.Hotkey) -> err {
    let added = shell.hotkey_register(a, id, key)
    if added != ok { ret added }
    session.registered += 1u32
    ret ok
}

fn global_shortcut_remove(a: *mem.Arena, session: *GlobalShortcutSession, id: u32) -> err {
    let removed = shell.hotkey_unregister(a, id)
    if removed != ok { ret removed }
    if session.registered != 0u32 { session.registered -= 1u32 }
    ret ok
}

// The oldest press of a registered shortcut, by its id.
fn global_shortcut_poll() -> (u32, bool) {
    let (id, any) = shell.hotkey_poll()
    ret (id, any)
}

fn background_permission(a: *mem.Arena) -> shell.Permission {
    ret shell.background_permission(a)
}

fn login_item_set(a: *mem.Arena, id: str, enabled: bool) -> err {
    ret shell.startup_set(a, id, enabled)
}

fn login_item_enabled(a: *mem.Arena, id: str) -> (bool, err) {
    let (enabled, query_error) = shell.startup_enabled(a, id)
    ret (enabled, query_error)
}

fn power_inhibitor_acquire(a: *mem.Arena, keep_display: bool) -> (PowerInhibitor, err) {
    let held = shell.power_inhibit(a, keep_display)
    if held != ok { ret (PowerInhibitor { held: false }, held) }
    ret (PowerInhibitor { held: true }, ok)
}

fn power_inhibitor_release(a: *mem.Arena, inhibitor: *PowerInhibitor) -> err {
    if !inhibitor.held { ret shell.NotFound }
    let released = shell.power_release(a)
    if released != ok { ret released }
    inhibitor.held = false
    ret ok
}

fn lifecycle_poll() -> (shell.LifecycleEvent, bool) {
    let (event, any) = shell.lifecycle_poll()
    ret (event, any)
}

// The host restarts the program with these arguments after a crash or an
// update; `activation` reads them on the way back in.
fn session_restore_register(a: *mem.Arena, arguments: str) -> err {
    ret shell.restart_register(a, arguments)
}

fn session_restore_unregister(a: *mem.Arena) -> err {
    ret shell.restart_unregister(a)
}
