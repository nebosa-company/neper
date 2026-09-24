// `e.ui.testing` (D800): a harness drives a widget runtime without a window -- a
// synthetic surface of the size and scale given, an offscreen target on the
// renderer's own queue, frames pumped with the time the test supplies, events sent
// straight to dispatch, elements found by key or by text, and the last frame read
// back as an image to compare against a golden within a per-channel tolerance.
// Nothing here sleeps or asks a display server for anything.

use e.mem
use e.time
use e.gpu
use e.gfx.geometry
use e.gfx.image
use e.gfx.scene
use e.gfx.paint
use e.text.layout
use e.ui.accessibility
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.window

type Harness = struct { state: *void }
type Match = struct { element: widget.ElementId, count: usize }
// The gallery's own state (D812, widget plan P0-09): what its controls write.
type Gallery = struct { presses: usize, checked: bool, field: [32]u8, field_len: usize, scrolled: f32 }
error NotFound
error Ambiguous
error GoldenMismatch

type State = struct { runtime: *widget.Runtime, frames: *gpu.Target, drawable: scene.Target, queue: *gpu.Queue, width: u32, height: u32, scale: f32, frame_storage: []u8, closed: bool, capabilities: style.Capabilities, safe: geometry.Insets, keyboard: geometry.Insets, tree_storage: []u8 }

const FRAME_BYTES: usize = 4194304usize
const TREE_BYTES: usize = 262144usize

fn harness(a: *mem.Arena, runtime: *widget.Runtime, width: u32, height: u32, scale: f32) -> (Harness, err) {
    if width == 0u32 || height == 0u32 || !(scale > 0.0) { ret (zero, NotFound) }
    let queue = widget.queue_of(runtime)
    if mem.address_of(queue) == 0usize { ret (zero, NotFound) }
    let (frames, frames_error) = gpu.open_target(queue, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, width, height, .Rgba8)
    if frames_error != ok { ret (zero, NotFound) }
    let (drawable, drawable_error) = scene.target_of(a, frames)
    if drawable_error != ok { ret (zero, NotFound) }
    let (frame_storage, storage_error) = mem.alloc[u8](a, FRAME_BYTES)
    if storage_error != ok { ret (zero, NotFound) }
    let (tree_storage, tree_error) = mem.alloc[u8](a, TREE_BYTES)
    if tree_error != ok { ret (zero, NotFound) }
    let (states, states_error) = mem.alloc[State](a, 1usize)
    if states_error != ok { ret (zero, NotFound) }
    // A desktop host until `fake_host` says otherwise.
    let desktop = style.Capabilities { hover: true, fine_pointer: true, keyboard: true, touch: false, pen: false, resizable: true, multi_window: true, insets: zero }
    states[0usize] = State { runtime: runtime, frames: frames, drawable: drawable, queue: queue, width: width, height: height, scale: scale, frame_storage: frame_storage, closed: false, capabilities: desktop, safe: zero, keyboard: zero, tree_storage: tree_storage }
    ret (Harness { state: mem.cast[*void](&states[0usize]) }, ok)
}

fn state_of(h: *const Harness) -> (*State, err) {
    let s = mem.cast[*State](h.state)
    if mem.address_of(s) == 0usize || s.closed { ret (s, NotFound) }
    ret (s, ok)
}

// One frame: the tree reconciled under the surface's logical size and rendered.
fn pump(h: *Harness, root: widget.Node, now: time.Instant) -> err {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret state_error }
    // The caller builds `root` before this call, so keep any frame request made
    // during that build while making the supplied instant visible to painting.
    widget.set_frame_time(s.runtime, now)
    var frame = mem.arena_from(s.frame_storage)
    let logical_width = f32(s.width) / s.scale
    let logical_height = f32(s.height) / s.scale
    let (compiled, reconcile_error) = widget.reconcile(s.runtime, &frame, root, ui_layout.Constraints { min_width: 0.0, max_width: logical_width, min_height: 0.0, max_height: logical_height })
    if reconcile_error != ok { ret reconcile_error }
    ret scene.render(widget.renderer_of(s.runtime), compiled, s.drawable, geometry.Size { width: logical_width, height: logical_height })
}

// Start a clocked frame before building its tree.
fn begin(h: *Harness, now: time.Instant) -> err {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret state_error }
    widget.begin_frame(s.runtime, now)
    ret ok
}

fn send(h: *Harness, event: input.Event) -> err {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret state_error }
    ret widget.dispatch(s.runtime, event)
}

fn by_key(h: *const Harness, key: widget.Key) -> Match {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret Match { element: zero, count: 0usize } }
    let (element, count) = widget.find_by_key(mem.cast[*widget.State](s.runtime.state), key)
    ret Match { element: element, count: count }
}

fn by_text(h: *const Harness, text: str) -> Match {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret Match { element: zero, count: 0usize } }
    let (element, count) = widget.find_by_text(mem.cast[*widget.State](s.runtime.state), text)
    ret Match { element: element, count: count }
}

// The last presented frame as premultiplied RGBA8 into `a`.
fn snapshot(h: *Harness, a: *mem.Arena) -> (image.Image, err) {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret (zero, state_error) }
    let (shown, shown_error) = gpu.presented(s.frames)
    if shown_error != ok { ret (zero, NotFound) }
    let count = usize(shown.width) * usize(shown.height)
    let (pixels, pixels_error) = mem.alloc[u32](a, count)
    if pixels_error != ok { ret (zero, pixels_error) }
    if gpu.read_image(s.queue, shown, pixels) != ok { ret (zero, NotFound) }
    let (bytes, bytes_error) = mem.alloc[u8](a, count * 4usize)
    if bytes_error != ok { ret (zero, bytes_error) }
    var i = 0usize
    while i < count {
        let p = pixels[i]
        bytes[i * 4usize] = u8(p & 255u32)
        bytes[i * 4usize + 1usize] = u8((p >> 8u32) & 255u32)
        bytes[i * 4usize + 2usize] = u8((p >> 16u32) & 255u32)
        bytes[i * 4usize + 3usize] = u8((p >> 24u32) & 255u32)
        i += 1usize
    }
    let (made, make_error) = image.make(bytes, shown.width, shown.height, usize(shown.width) * 4usize, .Rgba8, .Premultiplied)
    if make_error != ok { ret (zero, NotFound) }
    ret (made, ok)
}

// Every channel of every pixel within `tolerance` of the golden's; a different
// size or format is a mismatch too.
fn compare(actual: image.ConstImage, expected: image.ConstImage, tolerance: u8) -> err {
    if actual.width != expected.width || actual.height != expected.height || actual.format != expected.format { ret GoldenMismatch }
    let bytes = image.bytes_per_pixel(actual.format)
    var y = 0usize
    while y < usize(actual.height) {
        var x = 0usize
        while x < usize(actual.width) * bytes {
            let a = actual.pixels[y * actual.stride + x]
            let e = expected.pixels[y * expected.stride + x]
            var d = 0u8
            if a > e { d = a - e } else { d = e - a }
            if d > tolerance { ret GoldenMismatch }
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// ------------------------------------------------------ the widget harness (D812)

fn no_window() -> window.Id {
    ret window.Id { slot: 0u32, generation: 0u32 }
}

fn pointer_at(x: f32, y: f32) -> input.Pointer {
    ret input.Pointer { window: no_window(), device: 0u32, pointer: 0u32, kind: .Mouse, position: geometry.Point { x: x, y: y }, buttons: 1u32, changed: .Primary }
}

// Gesture sequences: a tap is a press and a release at one point; a drag presses,
// moves in `steps` and releases; a hover moves with nothing pressed; a wheel turns
// `notches` (positive away from the user) at a point.
fn tap(h: *Harness, x: f32, y: f32) -> err {
    try send(h, input.Event { PointerDown: pointer_at(x, y) })
    ret send(h, input.Event { PointerUp: pointer_at(x, y) })
}

fn drag(h: *Harness, from: geometry.Point, to: geometry.Point, steps: usize) -> err {
    try send(h, input.Event { PointerDown: pointer_at(from.x, from.y) })
    var count = steps
    if count == 0usize { count = 1usize }
    var i = 1usize
    while i <= count {
        let t = f32(i) / f32(count)
        try send(h, input.Event { PointerMove: pointer_at(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t) })
        i += 1usize
    }
    ret send(h, input.Event { PointerUp: pointer_at(to.x, to.y) })
}

fn hover(h: *Harness, x: f32, y: f32) -> err {
    var moved = pointer_at(x, y)
    moved.buttons = 0u32
    ret send(h, input.Event { PointerMove: moved })
}

fn wheel(h: *Harness, x: f32, y: f32, notches: i32) -> err {
    var turned = pointer_at(x, y)
    turned.buttons = 0u32
    turned.device = mem.bitcast[u32](notches * 120i32)
    ret send(h, input.Event { Scroll: turned })
}

// A key pressed and released with the modifiers, as the host's virtual code.
fn press_key(h: *Harness, code: u32, modifiers: input.Modifiers) -> err {
    try send(h, input.Event { KeyDown: input.KeyEvent { window: no_window(), key: input.Key { physical: code, logical: code }, modifiers: modifiers, repeat: false } })
    ret send(h, input.Event { KeyUp: input.KeyEvent { window: no_window(), key: input.Key { physical: code, logical: code }, modifiers: modifiers, repeat: false } })
}

// Focus traversal: Tab or Shift+Tab, and who has the focus.
fn tab(h: *Harness, backward: bool) -> err {
    var modifiers: input.Modifiers = zero
    modifiers.shift = backward
    ret press_key(h, 9u32, modifiers)
}

fn focused(h: *const Harness) -> (widget.ElementId, bool) {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret (zero, false) }
    let (element, has_focus) = widget.focused(s.runtime)
    ret (element, has_focus)
}

// The fake IME: text typed one code point at a time, and a composition shown
// then committed by its text.
fn type_text(h: *Harness, text: str) -> err {
    var i = 0usize
    while i < text.len {
        var n = 1usize
        while i + n < text.len && (u32(text[i + n]) & 192u32) == 128u32 { n += 1usize }
        try send(h, input.Event { Text: input.TextEvent { window: no_window(), text: text[i..i + n] } })
        i += n
    }
    ret ok
}

fn compose(h: *Harness, text: str) -> err {
    ret send(h, input.Event { Composition: input.Composition { window: no_window(), text: text, selection_start: 0usize, selection_end: text.len } })
}

fn commit(h: *Harness, text: str) -> err {
    ret send(h, input.Event { Text: input.TextEvent { window: no_window(), text: text } })
}

// Semantic queries over the tree built now: the first element of a role, of a
// label; the tree itself, in the harness's own storage until the next query.
fn semantics(h: *const Harness) -> (accessibility.Tree, err) {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret (zero, state_error) }
    var tree_arena = mem.arena_from(s.tree_storage)
    let (tree, tree_error) = accessibility.build(&tree_arena, s.runtime)
    if tree_error != ok { ret (zero, NotFound) }
    ret (tree, ok)
}

fn by_role(h: *const Harness, role: accessibility.Role) -> Match {
    let (tree, tree_error) = semantics(h)
    if tree_error != ok { ret Match { element: zero, count: 0usize } }
    var found: widget.ElementId = zero
    var count = 0usize
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role {
            if count == 0usize { found = tree.nodes[i].id }
            count += 1usize
        }
        i += 1usize
    }
    ret Match { element: found, count: count }
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

fn by_label(h: *const Harness, label: str) -> Match {
    let (tree, tree_error) = semantics(h)
    if tree_error != ok { ret Match { element: zero, count: 0usize } }
    var found: widget.ElementId = zero
    var count = 0usize
    var i = 0usize
    while i < tree.nodes.len {
        if same_text(tree.nodes[i].label, label) {
            if count == 0usize { found = tree.nodes[i].id }
            count += 1usize
        }
        i += 1usize
    }
    ret Match { element: found, count: count }
}

// Overlay lookup: the content bounds of the overlay an element is.
fn overlay_of(h: *const Harness, element: widget.ElementId) -> (geometry.Rect, bool) {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret (zero, false) }
    let (bounds, has_bounds) = widget.overlay_bounds_of(s.runtime, element)
    ret (bounds, has_bounds)
}

// Viewport visibility: whether any of the element shows -- inside the surface and
// inside every scroll viewport above it.
fn visible(h: *const Harness, element: widget.ElementId) -> bool {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret false }
    let (bounds, has_bounds) = widget.bounds_of(s.runtime, element)
    if !has_bounds { ret false }
    var shown = geometry.intersect(bounds, geometry.Rect { x: 0.0, y: 0.0, width: f32(s.width) / s.scale, height: f32(s.height) / s.scale })
    var at = usize(element.slot)
    while true {
        let (summary, live) = widget.summary_at(s.runtime, at)
        if !live || !summary.has_parent { break }
        at = usize(summary.parent.slot)
        let (above, above_live) = widget.summary_at(s.runtime, at)
        if !above_live { break }
        if above.kind == 7u8 { shown = geometry.intersect(shown, above.bounds) }
    }
    ret shown.width > 0.0 && shown.height > 0.0
}

// The host fixture: the capabilities and insets the harness stands in for, the
// insets sent to the widgets as their event.
fn fake_host(h: *Harness, host: style.Capabilities, safe: geometry.Insets, keyboard: geometry.Insets) -> err {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret state_error }
    s.capabilities = host
    s.capabilities.insets = safe
    s.safe = safe
    s.keyboard = keyboard
    ret send(h, input.Event { Insets: input.InsetsEvent { window: no_window(), safe: safe, keyboard: keyboard } })
}

fn capabilities(h: *const Harness) -> style.Capabilities {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret zero }
    ret s.capabilities
}

fn insets(h: *const Harness) -> (geometry.Insets, geometry.Insets) {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret (zero, zero) }
    ret (s.safe, s.keyboard)
}

// ------------------------------------------------------------ the gallery (D812)

fn on_gallery_press(ctx: *void, g: widget.Gesture) -> err {
    let gallery_state = mem.cast[*Gallery](ctx)
    if g.tag == .Tap { gallery_state.presses += 1usize }
    ret ok
}

fn on_gallery_check(ctx: *void, g: widget.Gesture) -> err {
    let gallery_state = mem.cast[*Gallery](ctx)
    if g.tag == .Tap { gallery_state.checked = !gallery_state.checked }
    ret ok
}

fn on_gallery_check_action(ctx: *void, bit: u32) -> err {
    let gallery_state = mem.cast[*Gallery](ctx)
    gallery_state.checked = !gallery_state.checked
    ret ok
}

fn on_gallery_field(ctx: *void, value: str) -> err {
    let gallery_state = mem.cast[*Gallery](ctx)
    gallery_state.field_len = value.len
    ret ok
}

fn on_gallery_scroll(ctx: *void, offset: f32) -> err {
    let gallery_state = mem.cast[*Gallery](ctx)
    gallery_state.scrolled = offset
    ret ok
}

fn gallery_box(t: *const style.ThemeTokens, width: f32, height: f32, look: style.ResolvedControl) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    s.background = paint.Brush { Solid: look.background }
    ret s
}

// The reference gallery: one of each primitive under the theme -- a heading, a
// filled button, an outlined text field, a checkbox, a list in a viewport, and a
// tooltip overlay below the button -- with stable keys 1..9 and its state in
// `gallery_state`; a text style with no fonts leaves the labels to the semantics.
fn gallery(a: *mem.Arena, t: *const style.ThemeTokens, text_style: layout.Style, gallery_state: *Gallery) -> (widget.Node, err) {
    let ctx = mem.cast[*void](gallery_state)
    var rest: style.ControlState = zero
    var checked: style.ControlState = zero
    checked.selected = gallery_state.checked
    let filled = style.resolve(t, .Filled, rest)
    let outlined = style.resolve(t, .Outlined, rest)
    let check_look = style.resolve(t, .Outlined, checked)
    let (labels, labels_error) = mem.alloc[widget.Node](a, 3usize)
    if labels_error != ok { ret (zero, labels_error) }
    labels[0usize] = widget.text(11u64, widget.Text { value: "Gallery", style: text_style, color: style.color(t, .Text), wrap: .Word, align: .Start, max_lines: 0u32, ellipsis: "" }, style.defaults())
    labels[1usize] = widget.text(12u64, widget.Text { value: "Save", style: text_style, color: filled.foreground, wrap: .Word, align: .Start, max_lines: 0u32, ellipsis: "" }, style.defaults())
    labels[2usize] = widget.text(13u64, widget.Text { value: "Tip", style: text_style, color: style.color(t, .Text), wrap: .Word, align: .Start, max_lines: 0u32, ellipsis: "" }, style.defaults())
    let (rows, rows_error) = mem.alloc[widget.Node](a, 6usize)
    if rows_error != ok { ret (zero, rows_error) }
    var i = 0usize
    while i < 6usize {
        var row: widget.Semantics = zero
        row.role = 11u8
        row.row = u32(i + 1usize)
        row.row_count = 6u32
        rows[i] = widget.semantics(20u64 + u64(i), row, gallery_box(t, 120.0, t.metrics.control_height, outlined), zero)
        i += 1usize
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, column_error) }
    column[0usize] = widget.flex(19u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.spacing.xs }, style.defaults(), rows[0usize..6usize])
    let (items, items_error) = mem.alloc[widget.Node](a, 6usize)
    if items_error != ok { ret (zero, items_error) }
    var heading: widget.Semantics = zero
    heading.role = 25u8
    heading.level = 1u8
    heading.label = "Gallery"
    items[0usize] = widget.semantics(1u64, heading, style.defaults(), labels[0usize..1usize])
    var button: widget.Semantics = zero
    button.role = 3u8
    button.label = "Save"
    let (button_body, button_body_error) = mem.alloc[widget.Node](a, 1usize)
    if button_body_error != ok { ret (zero, button_body_error) }
    button_body[0usize] = widget.region(3u64, widget.Region { gesture: widget.GestureAction { ctx: ctx, invoke: on_gallery_press }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, gallery_box(t, 80.0, t.metrics.control_height, filled), labels[1usize..2usize])
    items[1usize] = widget.semantics(2u64, button, style.defaults(), button_body[0usize..1usize])
    items[2usize] = widget.edit(4u64, widget.Edit { buffer: gallery_state.field[..], len: gallery_state.field_len, style: text_style, color: outlined.foreground, selection: style.color(t, .Selection), change: widget.Change[str] { ctx: ctx, invoke: on_gallery_field }, submit: zero, enabled: true, read_only: false, multiline: false, secret: false, marked: zero, caret: zero, untabbed: false, ringed: false }, gallery_box(t, 120.0, t.metrics.control_height, outlined))
    var checkbox: widget.Semantics = zero
    checkbox.role = 4u8
    checkbox.label = "Notify"
    if gallery_state.checked { checkbox.states = accessibility.STATE_CHECKED }
    checkbox.actions = accessibility.ACTION_PRESS
    checkbox.on_action = widget.Change[u32] { ctx: ctx, invoke: on_gallery_check_action }
    let (check_body, check_body_error) = mem.alloc[widget.Node](a, 1usize)
    if check_body_error != ok { ret (zero, check_body_error) }
    check_body[0usize] = widget.region(6u64, widget.Region { gesture: widget.GestureAction { ctx: ctx, invoke: on_gallery_check }, gestures: 1u8, enabled: true, focusable: true }, gallery_box(t, t.metrics.control_height, t.metrics.control_height, check_look), zero)
    items[3usize] = widget.semantics(5u64, checkbox, style.defaults(), check_body[0usize..1usize])
    var viewport = style.defaults()
    viewport.width = style.Length { Px: 120.0 }
    viewport.height = style.Length { Px: t.metrics.control_height * 2.0 }
    items[4usize] = widget.scroll(7u64, widget.Scroll { axis: .Vertical, offset: 0.0, overscroll: .Clamp, momentum: false, scrollbar: true, thumb: style.color(t, .Border), change: widget.Change[f32] { ctx: ctx, invoke: on_gallery_scroll }, virtual_first: 0usize, virtual_count: 0usize, virtual_extent: 0.0 }, viewport, column[0usize..1usize])
    items[5usize] = widget.overlay(8u64, widget.Overlay { anchor: 3u64, placement: .Below, offset: geometry.Point { x: 0.0, y: t.spacing.xs }, modal: false, dismiss: zero }, style.defaults(), labels[2usize..3usize])
    var page = style.defaults()
    page.background = paint.Brush { Solid: style.color(t, .Background) }
    page.padding = style.EdgeLengths { left: style.Length { Px: t.spacing.md }, top: style.Length { Px: t.spacing.md }, right: style.Length { Px: t.spacing.md }, bottom: style.Length { Px: t.spacing.md } }
    ret (widget.flex(9u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.spacing.sm }, page, items[0usize..6usize]), ok)
}

fn close(h: *Harness) -> err {
    let (s, state_error) = state_of(h)
    if state_error != ok { ret state_error }
    let closed = gpu.close_target(s.frames)
    s.closed = true
    ret ok
}
