// `e.ui.widget` (D799): the declarative tree, its persistent elements and typed
// state, layout, painting into a scene, and dispatch. A `Node` tree is built in a
// frame arena and handed to `reconcile`, which matches it against the retained
// elements -- siblings by nonzero key and kind, else by position and kind --
// creates and retires elements, lays the tree out under the constraints, paints a
// display list and compiles it into the renderer's scene. Nothing of the frame is
// kept: an element holds its key, kind, bounds, its state cells, an action's
// context and function, a scroll offset and a text copy for hit testing by text.
//
// Layout is downward constraints and upward sizes: a node's style gives its own
// size (`Px`, `Percent` of the parent's bound, `Auto` from its children, `Flex` as
// a share of the parent's main axis), padding and margin; a `Flex` and a `Grid`
// place their children through `e.ui.layout`; a `Stack` overlays them; a `Box` is a
// vertical flex; a `Scroll` gives its child an unbounded main axis and clips.
//
// ponytail: the tree is rebuilt, laid out and painted whole every reconcile --
// `invalidate` records the wish and the next frame honours it, subtree reuse being
// the upgrade the frame-time numbers will ask for; a state cell is reused only by a
// state of the same size and alignment.

use e.gpu
use e.math
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.text.unicode
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.window

type Key = u64
type ElementId = struct { slot: u32, generation: u32 }
type StateId = struct { slot: u32, generation: u32 }
type Action = struct { ctx: *void, invoke: fn(*void, input.Event) -> err }
// A text's wrap, alignment, line budget and ellipsis are the layout's options (D813).
type Text = struct { value: str, style: layout.Style, color: paint.Color, wrap: layout.Wrap, align: layout.Align, max_lines: u32, ellipsis: str }
type Button = struct { action: Action, enabled: bool }
type Image = struct { texture: scene.TextureId, fit: Fit }
// A scroll viewport (D808, widget plan P0-05): its children stacked and clipped,
// moved along `axis` by the wheel, a drag of the content (with momentum after it
// when asked), and `scroll_to`; `offset` follows D807's rule -- taken when the caller
// changes it between frames -- and every move is reported through `change`. Past
// its ends the offset is clamped, or overshoots and springs back. With a
// `virtual_count` the viewport is lazy: `virtual_count` items of `virtual_extent`
// each make the content, and the children are the items from `virtual_first` on --
// the ones `visible_range` names -- keyed by the caller so the reconciler recycles
// the rest. A scrollbar thumb is painted on the trailing edge when asked.
type Overscroll = enum u8 { Clamp, Bounce }
type Scroll = struct { axis: ui_layout.Axis, offset: f32, overscroll: Overscroll, momentum: bool, scrollbar: bool, thumb: paint.Color, change: Change[f32], virtual_first: usize, virtual_count: usize, virtual_extent: f32 }
// A custom's `state` is the bytes its measure and paint read through `ctx` and
// nothing else (D917): with them the runtime can tell an unchanged custom from a
// changed one and skip its subtree; empty, the custom is painted every frame.
type Custom = struct { ctx: *void, measure: fn(*void, ui_layout.Constraints) -> geometry.Size, paint: fn(*void, *scene.Builder, geometry.Rect) -> err, state: []const u8 }
// Typed actions (D806, widget plan P0-02): a change carries a value of its type, a
// submit carries nothing; `ctx` outlives the element and never points into the
// frame arena. An unset action is a no-op.
type Change[T: type] = struct { ctx: *void, invoke: fn(*void, T) -> err }
type Submit = struct { ctx: *void, invoke: fn(*void) -> err }
// A gesture the arena settled on: a tap, a drag from its start through its moves to
// its end, a hover entering and leaving. Positions are logical pixels.
type Drag = struct { start: geometry.Point, position: geometry.Point, delta: geometry.Point }
type Gesture = union enum u8 { Tap: geometry.Point, DoubleTap: geometry.Point, DragStart: geometry.Point, DragMove: Drag, DragEnd: geometry.Point, Hover: geometry.Point, HoverEnd, Drop: Dropped }
type GestureAction = struct { ctx: *void, invoke: fn(*void, Gesture) -> err }
// The gestures a region takes part in, as bits: 1 tap, 2 drag, 4 hover.
type Region = struct { gesture: GestureAction, gestures: u8, enabled: bool, focusable: bool }
type Shortcut = struct { key: u32, modifiers: input.Modifiers, action: Submit }
// A focus and shortcut scope: Tab and Shift+Tab travel its focusable descendants
// (and, trapping, never leave it); a key down that matches one of its shortcuts
// fires it; Enter fires the default action and Escape the cancel one. A scope with
// `keys` set takes every key down that reaches it instead (D830), for a control that
// records keys.
type Scope = struct { traps_focus: bool, shortcuts: []const Shortcut, default_action: Submit, cancel_action: Submit, keys: Change[input.KeyEvent] }
// An editable text (D807, widget plan P0-04): the caller owns `buffer` and `len`
// bytes of it are the value; the runtime edits in place -- caret, selection, typed
// text, IME composition, clipboard, undo -- and reports every change as the new
// value through `change`; Enter in a single-line editor fires `submit`. A `len`
// the caller changes between frames replaces the value; one it leaves alone keeps
// the runtime's edits. (D963) `marked` repaints the selected glyphs (alpha 0:
// they keep `color`); `caret` is a 2px caret's colour (alpha 0: a 1px caret in
// `color`); `untabbed` keeps it out of the Tab order (a press still focuses it);
// `ringed` gives it the focus ring the runtime draws round other controls.
type Edit = struct { buffer: []u8, len: usize, style: layout.Style, color: paint.Color, selection: paint.Color, change: Change[str], submit: Submit, enabled: bool, read_only: bool, multiline: bool, secret: bool, marked: paint.Color, caret: paint.Color, untabbed: bool, ringed: bool }
// Semantics (D809, widget plan P0-06): what an element says of itself to the
// accessibility tree beyond what its kind implies. `role` is `e.ui.accessibility`'s
// role code (0 keeps the kind's); the label, value and hint are copied into the
// element (64, 32 and 32 bytes); `states`, `actions` and `live` are that module's
// bits and codes; relationships name other elements by key (0 for none); `row` and
// `column` place the element in a collection of `row_count` by `column_count`;
// `level` is a heading's or a tree item's depth; a hidden element and its subtree
// leave the tree. A platform action the element offers reaches `on_action` as its bit.
type Semantics = struct { role: u8, label: str, value: str, hint: str, states: u32, actions: u32, live: u8, level: u8, sort: u8, labelled_by: Key, described_by: Key, error_by: Key, controls: Key, active: Key, row: u32, column: u32, row_count: u32, column_count: u32, hidden: bool, on_action: Change[u32] }
// An overlay (D810, widget plan P0-07): its children leave the flow and paint at the
// root level, last, stacked against the element `anchor` names by key (0: the
// window) with `placement` and `offset`, kept inside the window. A modal overlay
// takes the focus when it appears and gives it back when it goes, bounds Tab to its
// subtree, keeps the pointer from what is under it, and a press outside it fires
// `dismiss`. Overlays stack in tree order; the last is on top.
// v2 (D975, docs/ux/components/Menu, Tooltip, ContextMenu): BelowCenter and
// AboveCenter centre the content on the anchor, BelowEnd aligns their ends, At
// puts its top-start corner at `offset` in the window (a context menu at the
// pointer); a side that overflows the window flips to the opposite side, the
// offset mirrored, when that side fits. (D978) TopCenter centres the content
// across the anchor with its top on the anchor's top (a palette 64 down the window).
// BelowMatch and AboveMatch also constrain the content to the anchor's width,
// clamped by pixel min/max widths on the overlay node's style. AbovePoint centres
// content on the point `offset.x` from the anchor's start.
type Placement = enum u8 { Below, Above, Right, Left, Center, BelowCenter, AboveCenter, BelowEnd, At, TopCenter, BelowMatch, AboveMatch, AbovePoint }
type Overlay = struct { anchor: Key, placement: Placement, offset: geometry.Point, modal: bool, dismiss: Submit }
// The layout adapters that need a kind (D816): an aspect box is as wide as it may
// be and as tall as the ratio says; a fitted box scales its content down to fit,
// painting through a transform (its elements' bounds stay unscaled).
type Alignment = enum u8 { Start, Center, End }
// A scrollbar (D817) stands apart from the viewport it moves, named by key: its
// style's background is the track and its border colour the thumb; a drag of it
// moves the viewport by the content's share of the distance.
type Scrollbar = struct { viewport: Key, axis: ui_layout.Axis }
// A slider (D820): a value in `low..high` moved by a press, a drag, the arrow keys
// (a `step`), Home and End, reported through `change`; a range slider has two
// thumbs (`value` and `second`, `second` reported through `change_second`), a
// press taking the nearer. The track, its filled part and the thumbs are painted
// in the colours given; the value follows D807's rule for the caller's copy.
// v2 (D958): the halo round a handle (clear for none), the handle's width (4, or 2
// while pressed; 0 is 4), and the tick dots' colours on the active and inactive
// track (clear for no ticks).
type Slider = struct { value: f32, second: f32, range: bool, low: f32, high: f32, step: f32, vertical: bool, track: paint.Color, fill: paint.Color, thumb: paint.Color, change: Change[f32], change_second: Change[f32], enabled: bool, halo: paint.Color, handle: f32, tick_on: paint.Color, tick_off: paint.Color }
// A zoom view (D844, widget plan P2-11): its children laid out at their natural
// size and painted scaled by `state.scale` and moved by `state.offset` inside its
// own bounds, clipped; the wheel zooms about the pointer within `min_scale` and
// `max_scale`, a drag pans, and the offset is bounded so the content never leaves
// the view; the state follows D807's rule and every move reaches `change`. The
// content is painted, not pressed: a press on it pans.
type ZoomState = struct { scale: f32, offset: geometry.Point }
type Zoom = struct { state: ZoomState, min_scale: f32, max_scale: f32, change: Change[ZoomState] }
// A drop (D844): what a drag begun with `begin_drag` carried, released over a region
// that takes drops.
type Dropped = struct { position: geometry.Point, payload: u64 }
type Kind = union enum u8 { Box, Flex: ui_layout.Flex, Grid: ui_layout.Grid, Stack, Text: Text, Button: Button, Image: Image, Scroll: Scroll, Custom: Custom, Region: Region, Scope: Scope, Edit: Edit, Semantics: Semantics, Overlay: Overlay, Wrap: ui_layout.Wrap, Aspect: f32, Fitted, Scrollbar: Scrollbar, Slider: Slider, Zoom: Zoom }
type Node = struct { key: Key, kind: Kind, style: style.Style, children: []const Node }
type Fit = enum u8 { Fill, Contain, Cover, None }
type BuildContext = struct { runtime: *Runtime, element: ElementId, frame: u64 }
type Runtime = struct { state: *void }
type Limits = struct { max_elements: usize, max_states: usize, state_bytes: usize, state_classes: u16, max_depth: u16, max_commands: usize }
error DuplicateKey
error InvalidTree
error TooDeep
error TooLarge
error StateType

const STATES_PER_ELEMENT: usize = 8usize
const MAX_TEXT: usize = 64usize
// `Kind`'s tags in declaration order; the one a scroll hit test looks for.
const SCROLL_TAG: u8 = 7u8
const REGION_TAG: u8 = 9u8
const SCOPE_TAG: u8 = 10u8
const EDIT_TAG: u8 = 11u8
const SEMANTICS_TAG: u8 = 12u8
const OVERLAY_TAG: u8 = 13u8
const WRAP_TAG: u8 = 14u8
const ASPECT_TAG: u8 = 15u8
const FITTED_TAG: u8 = 16u8
const SCROLLBAR_TAG: u8 = 17u8
const SLIDER_TAG: u8 = 18u8
const ZOOM_TAG: u8 = 19u8
const MAX_OVERLAYS: usize = 8usize
const MAX_SHORT: usize = 32usize
const MAX_HISTORY: usize = 32usize
const HISTORY_BYTES: usize = 1024usize
const MAX_COMPOSE: usize = 64usize
const MAX_CLIP: usize = 256usize
const EDIT_SCRATCH: usize = 65536usize
const MAX_SHORTCUTS: usize = 8usize
const GESTURE_TAP: u8 = 1u8
const GESTURE_DRAG: u8 = 2u8
const GESTURE_HOVER: u8 = 4u8
const GESTURE_DROP: u8 = 8u8

type Cell = struct { live: bool, generation: u32, offset: usize, size: usize, align: usize, owner: u32 }
type Element = struct {
    live: bool,
    generation: u32,
    key: Key,
    kind: u8,
    // The subtree as it was reconciled (D916): its content hash, whether it holds
    // nothing the runtime moves on its own (a scroll, an editor, a slider, a zoom,
    // a custom paint, an overlay), whether this frame's node hashed the same, the
    // rect it was placed in, the commands it painted (in the scene compiled then)
    // and the size its last measure answered under which constraints.
    subtree_hash: u64,
    static_subtree: bool,
    unchanged: bool,
    placed_outer: geometry.Rect,
    replay_from: u32,
    replay_to: u32,
    has_replay: bool,
    sizes: [4]Sized,
    size_next: u8,
    parent: u32,
    has_parent: bool,
    // Children in order, linked; rebuilt every reconcile.
    first_child: u32,
    next_sibling: u32,
    has_child: bool,
    has_sibling: bool,
    visited: bool,
    bounds: geometry.Rect,
    action: Action,
    has_action: bool,
    enabled: bool,
    scroll_offset: f32,
    scroll_axis: ui_layout.Axis,
    // A viewport's last node offset (D807's rule), its extents from the last
    // placement, its momentum, and how it behaves past its ends.
    node_offset: f32,
    content_extent: f32,
    viewport_extent: f32,
    scroll_velocity: f32,
    // A zoom view's scale and offset, the node's last, its limits, its reporter and
    // its content's natural size.
    zoom_scale: f32,
    zoom_offset: geometry.Point,
    node_zoom: ZoomState,
    zoom_min: f32,
    zoom_max: f32,
    zoom_change: Change[ZoomState],
    natural: geometry.Size,
    scroll_change: Change[f32],
    overscroll: Overscroll,
    momentum: bool,
    linked: Key,
    // A slider's values and range, its second thumb, and which thumb a press took.
    slider_value: f32,
    slider_second: f32,
    node_value: f32,
    node_second: f32,
    slider_low: f32,
    slider_high: f32,
    slider_step: f32,
    slider_range: bool,
    slider_vertical: bool,
    slider_change: Change[f32],
    slider_change_second: Change[f32],
    second_held: bool,
    state_keys: [8]Key,
    state_ids: [8]StateId,
    state_count: usize,
    text: [64]u8,
    text_len: usize,
    invalid: bool,
    // A region's gesture action and mask; a scope's shortcuts and its two actions.
    gesture: GestureAction,
    gestures: u8,
    focusable: bool,
    traps_focus: bool,
    shortcuts: [8]Shortcut,
    shortcut_count: usize,
    default_action: Submit,
    cancel_action: Submit,
    keys: Change[input.KeyEvent],
    // An editor's buffer and value length, caret and selection anchor (the selection
    // is between them), text style and actions, and where its text was last placed.
    edit_buffer: []u8,
    edit_len: usize,
    node_len: usize,
    caret: usize,
    anchor: usize,
    edit_style: layout.Style,
    edit_change: Change[str],
    edit_submit: Submit,
    read_only: bool,
    multiline: bool,
    secret: bool,
    untabbed: bool,
    ringed: bool,
    text_origin: geometry.Point,
    text_width: f32,
    // What the element says of itself: its semantics with the label in `text` and
    // the value and hint in their own buffers.
    sem: Semantics,
    has_semantics: bool,
    value: [32]u8,
    value_len: usize,
    hint: [32]u8,
    hint_len: usize,
    // An overlay's content bounds, modality, dismiss action, and the focus it took
    // over when it appeared.
    overlay_bounds: geometry.Rect,
    modal: bool,
    dismiss: Submit,
    saved_focus: u32,
    has_saved: bool,
    overlay_opened: bool,
    wants_focus: bool,
}
// One undoable edit: the bytes it removed and inserted at `at`, in the history pool.
type Undo = struct { element: u32, at: usize, removed_off: usize, removed_len: usize, inserted_off: usize, inserted_len: usize }
// The gesture arena: one pointer, the region it went down on, where, whether it has
// become a drag, and the region hovered last.
type Arena = struct { pressed: bool, candidate: u32, down: geometry.Point, last: geometry.Point, dragging: bool, hovered: u32, has_hovered: bool }
// The logical size of a device pixel, which a scrolled viewport's offset snaps
// to when placed; zero snaps nothing. The application sets it from the window's
// scale (D917).
fn set_snap(widget_runtime: *Runtime, snap: f32) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize { ret }
    s.snap = snap
}

// A measure remembered for the frame: the node (by its address in the frame's
// tree), the constraints it was measured under and the answer (D914). A parent
// measures its children to place them and every ancestor measured them before
// it, so without this a text is shaped once per level of nesting.
type Measured = struct { node: usize, limits: ui_layout.Constraints, size: geometry.Size, laid: layout.Layout, stamp: u32 }
// A node's element for the frame, by the node's address.
type Owner = struct { node: usize, element: u32, stamp: u32 }
// A size an element's measure answered under some constraints; an element keeps its
// last four, since a parent asks under more than one set per frame.
type Sized = struct { limits: ui_layout.Constraints, size: geometry.Size, valid: bool }

type State = struct {
    arena: *mem.Arena,
    renderer: *scene.Renderer,
    limits: Limits,
    elements: []Element,
    focus_order: []u32,
    cells: []Cell,
    storage: []u8,
    measured: []Measured,
    measure_stamp: u32,
    snap: f32,
    replay_scene: scene.SceneId,
    has_replay_scene: bool,
    owners: []Owner,
    storage_used: usize,
    root: u32,
    has_root: bool,
    focus: u32,
    has_focus: bool,
    menu_saved_focus: u32,
    has_menu_saved_focus: bool,
    menu_mode: bool,
    menu_alt_down: bool,
    menu_alt_used: bool,
    menu_hovered_title: u32,
    has_menu_hovered_title: bool,
    menu_hover_target: u32,
    has_menu_hover_target: bool,
    menu_hover_at: i64,
    menu_safe_from: geometry.Point,
    has_menu_safe_from: bool,
    requested_focus_key: Key,
    has_requested_focus_key: bool,
    menu_typeahead: [16]u32,
    menu_typeahead_len: usize,
    menu_typeahead_at: i64,
    typeahead_context: u8,
    tooltip_anchor: Key,
    has_tooltip_anchor: bool,
    tooltip_hover_at: i64,
    tooltip_seen_at: i64,
    tooltip_last_at: i64,
    has_tooltip_last: bool,
    tooltip_touch_anchor: Key,
    has_tooltip_touch: bool,
    tooltip_touch_at: i64,
    tooltip_touch_release_at: i64,
    tooltip_touch_shown: bool,
    tooltip_touch_released: bool,
    long_press_key: Key,
    has_long_press: bool,
    long_press_at: i64,
    long_press_fired: bool,
    long_press_feedback: Submit,
    has_long_press_feedback: bool,
    rich_anchor_key: Key,
    rich_tooltip_key: Key,
    has_rich_tooltip: bool,
    rich_tooltip_shown: bool,
    rich_hover_at: i64,
    rich_leave_at: i64,
    rich_leaving: bool,
    rich_dismissed_key: Key,
    has_rich_dismissed: bool,
    // The focus ring (D940): shown only when the focus came by the keyboard or the
    // program, never by a pointer press; its colour, width and gap outside the
    // element, set from the theme; the clip the element being placed lies within.
    focus_visible: bool,
    ring_color: paint.Color,
    ring_width: f32,
    ring_offset: f32,
    // The press ripple (D983): its colour (clear on a host without one) and how
    // far it has spread, 0 to 1.
    ripple_color: paint.Color,
    ripple_phase: f32,
    // One time for every animation built in this frame, and whether any of them
    // asked the application to keep presenting frames.
    animation_time: time.Instant,
    animation_due: bool,
    clip_rect: geometry.Rect,
    has_clip: bool,
    frame: u64,
    scene_id: scene.SceneId,
    has_scene: bool,
    closed: bool,
    arena_state: Arena,
    has_pointer: bool,
    held_modifiers: input.Modifiers,
    last_tap: ElementId,
    has_last_tap: bool,
    last_tap_at: time.Instant,
    // Editing: a scratch region for hit-test layouts, the composition (preedit) of
    // the focused editor, the fallback clipboard for a host without one, and the
    // undo history -- entries and their byte pool -- with the redo point.
    scratch: []u8,
    compose: [64]u8,
    compose_len: usize,
    clip: [256]u8,
    clip_len: usize,
    clip_hosted: bool,
    // An in-application drag's payload (D844), from `begin_drag` to the drop.
    drag_payload: u64,
    has_drag: bool,
    history: [32]Undo,
    history_count: usize,
    history_at: usize,
    history_bytes: [1024]u8,
    history_used: usize,
    // The overlays placed this frame, in tree order, with their nodes.
    overlays: [8]u32,
    overlay_nodes: [8]*const Node,
    overlay_count: usize,
    window_size: geometry.Size,
}

// ---------------------------------------------------------------- constructors

fn box(key: Key, value_style: style.Style, children: []const Node) -> Node {
    var kind: Kind = .Box
    ret Node { key: key, kind: kind, style: value_style, children: children }
}

fn flex(key: Key, spec: ui_layout.Flex, value_style: style.Style, children: []const Node) -> Node {
    ret Node { key: key, kind: Kind { Flex: spec }, style: value_style, children: children }
}

fn grid(key: Key, spec: ui_layout.Grid, value_style: style.Style, children: []const Node) -> Node {
    ret Node { key: key, kind: Kind { Grid: spec }, style: value_style, children: children }
}

fn stack(key: Key, value_style: style.Style, children: []const Node) -> Node {
    var kind: Kind = .Stack
    ret Node { key: key, kind: kind, style: value_style, children: children }
}

fn text(key: Key, value: Text, value_style: style.Style) -> Node {
    var none: []const Node = zero
    ret Node { key: key, kind: Kind { Text: value }, style: value_style, children: none }
}

fn button(key: Key, value: Button, value_style: style.Style, children: []const Node) -> Node {
    ret Node { key: key, kind: Kind { Button: value }, style: value_style, children: children }
}

fn image(key: Key, value: Image, value_style: style.Style) -> Node {
    var none: []const Node = zero
    ret Node { key: key, kind: Kind { Image: value }, style: value_style, children: none }
}

fn scroll(key: Key, value: Scroll, value_style: style.Style, children: []const Node) -> Node {
    ret Node { key: key, kind: Kind { Scroll: value }, style: value_style, children: children }
}

fn region(key: Key, value: Region, value_style: style.Style, children: []const Node) -> Node {
    ret Node { key: key, kind: Kind { Region: value }, style: value_style, children: children }
}

fn scope(key: Key, value: Scope, value_style: style.Style, children: []const Node) -> Node {
    ret Node { key: key, kind: Kind { Scope: value }, style: value_style, children: children }
}

fn edit(key: Key, value: Edit, value_style: style.Style) -> Node {
    var none: []const Node = zero
    ret Node { key: key, kind: Kind { Edit: value }, style: value_style, children: none }
}

fn semantics(key: Key, value: Semantics, value_style: style.Style, children: []const Node) -> Node {
    ret Node { key: key, kind: Kind { Semantics: value }, style: value_style, children: children }
}

fn overlay(key: Key, value: Overlay, value_style: style.Style, children: []const Node) -> Node {
    ret Node { key: key, kind: Kind { Overlay: value }, style: value_style, children: children }
}

// The primary layouts as constructors (D815): a row and a column are flexes along
// an axis; a wrap breaks lines; a positioned child sits at an offset in a stack --
// its margin, which the stack places it by.
fn row(key: Key, gap: f32, value_style: style.Style, children: []const Node) -> Node {
    ret flex(key, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: gap }, value_style, children)
}

fn column(key: Key, gap: f32, value_style: style.Style, children: []const Node) -> Node {
    ret flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: gap }, value_style, children)
}

fn wrap(key: Key, spec: ui_layout.Wrap, value_style: style.Style, children: []const Node) -> Node {
    ret Node { key: key, kind: Kind { Wrap: spec }, style: value_style, children: children }
}

// The layout adapters (D816): a child aligned in its box, centred, padded, a spacer
// that takes a flex share, a box constrained between sizes, an aspect box, a fitted
// box, and a choice of subtree by the size class of a width.
fn aligned(key: Key, horizontal: Alignment, vertical: Alignment, value_style: style.Style, children: []const Node) -> Node {
    var main: ui_layout.MainAlign = .Start
    if vertical == .Center { main = .Center }
    if vertical == .End { main = .End }
    var cross: ui_layout.CrossAlign = .Start
    if horizontal == .Center { cross = .Center }
    if horizontal == .End { cross = .End }
    ret flex(key, ui_layout.Flex { axis: .Vertical, main: main, cross: cross, gap: 0.0 }, value_style, children)
}

fn center(key: Key, value_style: style.Style, children: []const Node) -> Node {
    ret aligned(key, .Center, .Center, value_style, children)
}

fn padded(key: Key, left: f32, top: f32, right: f32, bottom: f32, value_style: style.Style, children: []const Node) -> Node {
    var inset = value_style
    inset.padding = style.EdgeLengths { left: style.Length { Px: left }, top: style.Length { Px: top }, right: style.Length { Px: right }, bottom: style.Length { Px: bottom } }
    ret box(key, inset, children)
}

fn spacer(key: Key, share: f32) -> Node {
    var s = style.defaults()
    s.width = style.Length { Flex: share }
    s.height = style.Length { Flex: share }
    ret box(key, s, zero)
}

fn constrained(key: Key, min_width: f32, max_width: f32, min_height: f32, max_height: f32, value_style: style.Style, children: []const Node) -> Node {
    var limited = value_style
    limited.min_width = style.Length { Px: min_width }
    limited.max_width = style.Length { Px: max_width }
    limited.min_height = style.Length { Px: min_height }
    limited.max_height = style.Length { Px: max_height }
    ret box(key, limited, children)
}

fn aspect_ratio(key: Key, ratio: f32, value_style: style.Style, children: []const Node) -> Node {
    ret Node { key: key, kind: Kind { Aspect: ratio }, style: value_style, children: children }
}

fn fitted(key: Key, value_style: style.Style, children: []const Node) -> Node {
    var kind: Kind = .Fitted
    ret Node { key: key, kind: kind, style: value_style, children: children }
}

// The subtree for a width's size class, chosen when the tree is built.
fn responsive(width: f32, compact: Node, medium: Node, expanded: Node) -> Node {
    let class = style.size_class(width)
    if class == .Compact { ret compact }
    if class == .Medium { ret medium }
    ret expanded
}

// Scrolling and insets (D817): a scroll view stacks its children along its axis in
// a clamped viewport with momentum and a thumb; a scrollbar moves a viewport by
// key; a safe area and a keyboard-avoiding box pad by the host's insets.
fn scroll_view(a: *mem.Arena, key: Key, axis: ui_layout.Axis, value_style: style.Style, children: []const Node) -> (Node, err) {
    let (stacked, stacked_error) = mem.alloc[Node](a, 1usize)
    if stacked_error != ok { ret (zero, TooLarge) }
    stacked[0usize] = flex(0u64, ui_layout.Flex { axis: axis, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), children)
    let thumb = paint.rgba(0.5, 0.5, 0.5, 0.6)
    ret (scroll(key, Scroll { axis: axis, offset: 0.0, overscroll: .Clamp, momentum: true, scrollbar: true, thumb: thumb, change: zero, virtual_first: 0usize, virtual_count: 0usize, virtual_extent: 0.0 }, value_style, stacked[0usize..1usize]), ok)
}

fn zoom(key: Key, value: Zoom, value_style: style.Style, children: []const Node) -> Node {
    ret Node { key: key, kind: Kind { Zoom: value }, style: value_style, children: children }
}

fn slider(key: Key, value: Slider, value_style: style.Style) -> Node {
    var none: []const Node = zero
    ret Node { key: key, kind: Kind { Slider: value }, style: value_style, children: none }
}

fn scrollbar(key: Key, viewport: Key, axis: ui_layout.Axis, value_style: style.Style) -> Node {
    var none: []const Node = zero
    ret Node { key: key, kind: Kind { Scrollbar: Scrollbar { viewport: viewport, axis: axis } }, style: value_style, children: none }
}

fn safe_area(key: Key, insets: geometry.Insets, value_style: style.Style, children: []const Node) -> Node {
    ret padded(key, insets.left, insets.top, insets.right, insets.bottom, value_style, children)
}

fn keyboard_avoiding(key: Key, keyboard: geometry.Insets, value_style: style.Style, children: []const Node) -> Node {
    ret padded(key, 0.0, 0.0, 0.0, keyboard.bottom, value_style, children)
}

fn positioned(key: Key, x: f32, y: f32, value_style: style.Style, children: []const Node) -> Node {
    var placed = value_style
    placed.position = .Absolute
    placed.margin = style.EdgeLengths { left: style.Length { Px: x }, top: style.Length { Px: y }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    ret box(key, placed, children)
}

// Whether a function value is set: its bits are not zero, read through a pun.
type SubmitBits = union { function: fn(*void) -> err, bits: usize }
type MeasureBits = union { function: fn(*void, ui_layout.Constraints) -> geometry.Size, bits: usize }
type PaintBits = union { function: fn(*void, *scene.Builder, geometry.Rect) -> err, bits: usize }
type GestureBits = union { function: fn(*void, Gesture) -> err, bits: usize }
type ChangeBits[T: type] = union { function: fn(*void, T) -> err, bits: usize }

fn submit_set(f: fn(*void) -> err) -> bool {
    var pun: SubmitBits = zero
    pun.function = f
    ret pun.bits != 0usize
}

fn gesture_set(f: fn(*void, Gesture) -> err) -> bool {
    var pun: GestureBits = zero
    pun.function = f
    ret pun.bits != 0usize
}

fn change_set[T: type](f: fn(*void, T) -> err) -> bool {
    var pun: ChangeBits[T] = zero
    pun.function = f
    ret pun.bits != 0usize
}

// An action fired, or nothing when it is unset.
fn fire_change[T: type](c: Change[T], value: T) -> err {
    if !change_set[T](c.invoke) { ret ok }
    ret c.invoke(c.ctx, value)
}

fn fire_submit(a: Submit) -> err {
    if !submit_set(a.invoke) { ret ok }
    ret a.invoke(a.ctx)
}

fn fire_gesture(a: GestureAction, g: Gesture) -> err {
    if !gesture_set(a.invoke) { ret ok }
    ret a.invoke(a.ctx, g)
}

// ------------------------------------------------------------------ the runtime

fn runtime(a: *mem.Arena, renderer: *scene.Renderer, limits: Limits) -> (Runtime, err) {
    if limits.max_elements == 0usize || limits.max_states == 0usize || limits.state_bytes == 0usize || limits.max_depth == 0u16 || limits.max_commands == 0usize { ret (zero, TooLarge) }
    if limits.max_elements > 65535usize || limits.max_states > 65535usize { ret (zero, TooLarge) }
    let (states, states_error) = mem.alloc[State](a, 1usize)
    if states_error != ok { ret (zero, TooLarge) }
    let (elements, elements_error) = mem.alloc[Element](a, limits.max_elements)
    if elements_error != ok { ret (zero, TooLarge) }
    let (focus_order, focus_order_error) = mem.alloc[u32](a, limits.max_elements)
    if focus_order_error != ok { ret (zero, TooLarge) }
    let (cells, cells_error) = mem.alloc[Cell](a, limits.max_states)
    if cells_error != ok { ret (zero, TooLarge) }
    let (storage, storage_error) = mem.alloc[u8](a, limits.state_bytes + 16usize)
    if storage_error != ok { ret (zero, TooLarge) }
    let (scratch, scratch_error) = mem.alloc[u8](a, EDIT_SCRATCH)
    if scratch_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < elements.len {
        var empty: Element = zero
        elements[i] = empty
        i += 1usize
    }
    i = 0usize
    while i < cells.len {
        var empty_cell: Cell = zero
        cells[i] = empty_cell
        i += 1usize
    }
    let (measured, measured_error) = mem.alloc[Measured](a, limits.max_elements * 4usize)
    if measured_error != ok { ret (zero, TooLarge) }
    let (owners, owners_error) = mem.alloc[Owner](a, limits.max_elements * 4usize)
    if owners_error != ok { ret (zero, TooLarge) }
    var s: State = zero
    s.arena = a
    s.renderer = renderer
    s.limits = limits
    s.elements = elements
    s.focus_order = focus_order
    s.cells = cells
    s.storage = storage
    s.measured = measured
    s.owners = owners
    s.scratch = scratch
    states[0usize] = s
    ret (Runtime { state: mem.cast[*void](&states[0usize]) }, ok)
}

fn state_of(widget_runtime: *Runtime) -> (*State, err) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed { ret (s, InvalidTree) }
    ret (s, ok)
}

// An optional host feedback pulse at the successful long-press boundary.
fn set_long_press_feedback(widget_runtime: *Runtime, feedback: Submit) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    s.long_press_feedback = feedback
    s.has_long_press_feedback = submit_set(feedback.invoke)
    ret ok
}

// Start one animation frame. The application and test harness call this before
// a tree is built or reconciled so every control observes the same instant.
fn begin_frame(widget_runtime: *Runtime, now: time.Instant) {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret }
    s.animation_time = now
    s.animation_due = false
}

fn set_frame_time(widget_runtime: *Runtime, now: time.Instant) {
    let (s, state_error) = state_of(widget_runtime)
    if state_error == ok { s.animation_time = now }
}

fn frame_time(widget_runtime: *Runtime) -> time.Instant {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret time.Instant { nanos: 0i64 } }
    ret s.animation_time
}

// Whether Alt is currently held for an in-window menu bar to reveal access keys.
fn menu_access_keys_visible(widget_runtime: *Runtime) -> bool {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret false }
    ret s.menu_alt_down
}

fn request_animation_frame(widget_runtime: *Runtime) {
    let (s, state_error) = state_of(widget_runtime)
    if state_error == ok { s.animation_due = true }
}

fn animation_frame_requested(widget_runtime: *Runtime) -> bool {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret false }
    ret s.animation_due
}

fn element_of(s: *State, id: ElementId) -> (usize, bool) {
    if usize(id.slot) >= s.elements.len { ret (0usize, false) }
    let e = &s.elements[usize(id.slot)]
    if !e.live || e.generation != id.generation { ret (0usize, false) }
    ret (usize(id.slot), true)
}

fn kind_tag(kind: Kind) -> u8 {
    switch kind {
    case .Box:
        ret 0u8
    case .Flex as f:
        ret 1u8
    case .Grid as g:
        ret 2u8
    case .Stack:
        ret 3u8
    case .Text as t:
        ret 4u8
    case .Button as b:
        ret 5u8
    case .Image as im:
        ret 6u8
    case .Scroll as sc:
        ret SCROLL_TAG
    case .Custom as c:
        ret 8u8
    case .Region as r:
        ret REGION_TAG
    case .Scope as sc:
        ret SCOPE_TAG
    case .Edit as ed:
        ret EDIT_TAG
    case .Semantics as sm:
        ret SEMANTICS_TAG
    case .Overlay as ov:
        ret OVERLAY_TAG
    case .Wrap as w:
        ret WRAP_TAG
    case .Aspect as ratio:
        ret ASPECT_TAG
    case .Fitted:
        ret FITTED_TAG
    case .Scrollbar as bar:
        ret SCROLLBAR_TAG
    case .Slider as sl:
        ret SLIDER_TAG
    case .Zoom as z:
        ret ZOOM_TAG
    }
    ret 0u8
}

// ------------------------------------------------------------------ state cells

fn align_up(value: usize, align: usize) -> usize {
    if align == 0usize { ret value }
    ret (value + align - 1usize) / align * align
}

// A cell of the size and alignment: a retired one of the same class first, else
// carved from the storage; `TooLarge` when neither can be had.
fn take_cell(s: *State, size: usize, align: usize, owner: u32) -> (usize, err) {
    var i = 0usize
    while i < s.cells.len {
        let c = &s.cells[i]
        if !c.live && c.size == size && c.align == align && c.generation != 0u32 {
            c.live = true
            c.owner = owner
            ret (i, ok)
        }
        i += 1usize
    }
    i = 0usize
    while i < s.cells.len && s.cells[i].generation != 0u32 { i += 1usize }
    if i >= s.cells.len { ret (0usize, TooLarge) }
    let start = align_up(s.storage_used, align)
    if start + size > s.limits.state_bytes { ret (0usize, TooLarge) }
    s.storage_used = start + size
    s.cells[i] = Cell { live: true, generation: 1u32, offset: start, size: size, align: align, owner: owner }
    ret (i, ok)
}

fn retire_cell(s: *State, index: usize) {
    let c = &s.cells[index]
    c.live = false
    c.generation += 1u32
}

// The element's state under `key`: the cell it has, or a new one holding `initial`.
fn state[T: type](ctx: *BuildContext, key: Key, initial: T) -> (*T, StateId, err) {
    var none: *T = zero
    let (s, state_error) = state_of(ctx.runtime)
    if state_error != ok { ret (none, zero, state_error) }
    let (index, found) = element_of(s, ctx.element)
    if !found { ret (none, zero, InvalidTree) }
    let e = &s.elements[index]
    let size = mem.size_of[T]()
    let align = mem.align_of[T]()
    var k = 0usize
    while k < e.state_count {
        if e.state_keys[k] == key {
            let id = e.state_ids[k]
            let c = &s.cells[usize(id.slot)]
            if c.size != size || c.align != align { ret (none, zero, StateType) }
            let slot = &s.storage[c.offset]
            // The cell was written as `T` when `key` first asked for it; that one key names
            // one type is the caller's obligation (D919).
            @nocheck { ret (mem.cast[*T](slot), id, ok) }
        }
        k += 1usize
    }
    if e.state_count >= STATES_PER_ELEMENT { ret (none, zero, TooLarge) }
    let (cell, cell_error) = take_cell(s, size, align, u32(index))
    if cell_error != ok { ret (none, zero, cell_error) }
    let id = StateId { slot: u32(cell), generation: s.cells[cell].generation }
    let value = mem.cast[*T](&s.storage[s.cells[cell].offset])
    *value = initial
    e.state_keys[e.state_count] = key
    e.state_ids[e.state_count] = id
    e.state_count += 1usize
    ret (value, id, ok)
}

fn invalidate(widget_runtime: *Runtime, element: ElementId) {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret }
    let (index, found) = element_of(s, element)
    if found { s.elements[index].invalid = true }
}

// The focus ring's look (D940): `width` wide in `color`, `offset` outside the focused
// element's bounds, or inset where a clip would cut it; a zero width draws none.
fn set_focus_ring(widget_runtime: *Runtime, color: paint.Color, width: f32, offset: f32) {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret }
    s.ring_color = color
    s.ring_width = max_f(width, 0.0)
    s.ring_offset = max_f(offset, 0.0)
}

// v2 (D983, docs/ux/components/Button, Row, Card; widget plan P5-02): the press
// ripple of a touch host. The element under a press carries a disc of `color`
// centred on the press point, clipped to the element's shape, whose radius is
// `phase` (0 to 1) of the distance to the element's farthest corner. The
// runtime keeps the press point; the phase is the caller's clock --
// `duration-medium-2` from the press, eased (`e.ui.animation`) -- and a clear
// colour or a phase of 0 draws nothing. The theme sets the colour
// (`control.focus_look`); the app sets the phase each frame.
fn set_ripple(widget_runtime: *Runtime, color: paint.Color) {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret }
    s.ripple_color = color
}

fn set_ripple_phase(widget_runtime: *Runtime, phase: f32) {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret }
    s.ripple_phase = max_f(min_f(phase, 1.0), 0.0)
}

fn focus(widget_runtime: *Runtime, element: ElementId) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (index, found) = element_of(s, element)
    if !found { ret InvalidTree }
    s.focus = u32(index)
    s.has_focus = true
    s.focus_visible = true
    ret ok
}

// Focus the live element keyed `key`, or carry the request across the next
// reconcile when a virtual collection has not built it yet.
fn focus_key(widget_runtime: *Runtime, key: Key) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (element, count) = find_by_key(s, key)
    if count > 0usize { ret focus(widget_runtime, element) }
    s.requested_focus_key = key
    s.has_requested_focus_key = true
    ret ok
}

fn close(widget_runtime: *Runtime) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    if s.has_scene {
        let released = scene.release_scene(s.renderer, s.scene_id)
        s.has_scene = false
    }
    s.closed = true
    ret ok
}

// ---------------------------------------------------------------- reconciling

// An element for the node among `parent`'s previous children, or a new one.
fn match_element(s: *State, parent: usize, has_parent: bool, node: *const Node, position: usize, old_children: []const u32) -> (usize, err) {
    let tag = kind_tag(node.kind)
    var index = 0usize
    while index < old_children.len {
        let at = old_children[index]
        let e = &s.elements[usize(at)]
        if !e.visited && e.kind == tag {
            if node.key != 0u64 && e.key == node.key { ret (usize(at), ok) }
            if node.key == 0u64 && e.key == 0u64 && index == position { ret (usize(at), ok) }
        }
        index += 1usize
    }
    var slot = 0usize
    while slot < s.elements.len && s.elements[slot].live { slot += 1usize }
    if slot >= s.elements.len { ret (0usize, TooLarge) }
    let e = &s.elements[slot]
    let generation = e.generation + 1u32
    var fresh: Element = zero
    fresh.live = true
    fresh.generation = generation
    fresh.key = node.key
    fresh.kind = tag
    fresh.parent = u32(parent)
    fresh.has_parent = has_parent
    fresh.enabled = true
    *e = fresh
    ret (slot, ok)
}

fn retire_element(s: *State, index: usize) {
    let e = &s.elements[index]
    var k = 0usize
    while k < e.state_count {
        retire_cell(s, usize(e.state_ids[k].slot))
        k += 1usize
    }
    e.state_count = 0usize
    e.live = false
    if s.has_focus && usize(s.focus) == index { s.has_focus = false }
    // Its children go with it.
    var at = e.first_child
    var has = e.has_child
    while has {
        let child = &s.elements[usize(at)]
        let next = child.next_sibling
        let more = child.has_sibling
        retire_element(s, usize(at))
        at = next
        has = more
    }
    // An overlay gives back the focus it took, when that element is still here.
    if e.kind == OVERLAY_TAG && e.has_saved && !s.has_focus && s.elements[usize(e.saved_focus)].live {
        s.focus = e.saved_focus
        s.has_focus = true
    }
}

// `from` into `into`, at most `most` bytes; the count.
fn copy_short(into: []u8, from: str, most: usize) -> usize {
    var n = from.len
    if n > most { n = most }
    var i = 0usize
    while i < n {
        into[i] = from[i]
        i += 1usize
    }
    ret n
}

// The node's subtree matched to elements: children rebuilt in the node's order,
// the old children not matched retired.
// ------------------------------------------------------- unchanged subtrees (D916)
//
// A subtree that hashes as it did last frame, holds nothing the runtime moves by
// itself, and is placed in the same rect is neither measured nor painted again:
// its measure is answered from the element and its commands replayed from the
// scene compiled last frame. The hash is over content -- a text's bytes, not its
// slice -- since the build arena hands the same addresses to different frames.

const FNV_OFFSET: u64 = 14695981039346656037u64
const FNV_PRIME: u64 = 1099511628211u64

fn hash_bytes(seed: u64, bytes: []const u8) -> u64 {
    var h = seed
    var i = 0usize
    while i < bytes.len {
        h = (h ^ u64(bytes[i])) *% FNV_PRIME
        i += 1usize
    }
    ret h
}

fn hash_u64(seed: u64, v: u64) -> u64 {
    var h = seed
    var i = 0usize
    while i < 8usize {
        h = (h ^ ((v >> (u64(i) * 8u64)) & 255u64)) *% FNV_PRIME
        i += 1usize
    }
    ret h
}

fn hash_f32(seed: u64, v: f32) -> u64 {
    ret hash_u64(seed, u64(mem.bitcast[u32](v)))
}

fn bytes_of[T: type](p: *const T) -> []const u8 {
    let n = mem.size_of[T]()
    var over: mem.Arena = zero
    over.base = mem.cast[*u8](p)
    over.cap = n
    over.off = n
    ret mem.view(&over, 0usize, n)
}

fn hash_submit(seed: u64, v: Submit) -> u64 {
    var pun: SubmitBits = zero
    pun.function = v.invoke
    ret hash_u64(hash_u64(seed, u64(mem.address_of(v.ctx))), u64(pun.bits))
}

fn hash_text_style(seed: u64, st: layout.Style) -> u64 {
    var h = hash_f32(seed, st.line_height)
    h = hash_bytes(h, st.language)
    var i = 0usize
    while i < st.fonts.len {
        h = hash_u64(h, u64(st.fonts[i].font.id))
        h = hash_f32(h, st.fonts[i].size)
        i += 1usize
    }
    ret h
}

// The node's own content (not its children) into the hash; answers whether the
// node is static -- one the runtime never moves or paints from its own state.
fn hash_node(seed: u64, node: *const Node) -> (u64, bool) {
    var h = hash_u64(seed, node.key)
    h = hash_bytes(h, bytes_of[style.Style](&node.style))
    h = hash_u64(h, u64(kind_tag(node.kind)))
    var static = true
    switch node.kind {
    case .Text as t:
        h = hash_bytes(h, t.value)
        h = hash_text_style(h, t.style)
        h = hash_bytes(h, bytes_of[paint.Color](&t.color))
        if t.wrap == .Word { h = hash_u64(h, 1u64) }
        if t.wrap == .Character { h = hash_u64(h, 2u64) }
        if t.align == .End { h = hash_u64(h, 3u64) }
        if t.align == .Center { h = hash_u64(h, 4u64) }
        if t.align == .Justify { h = hash_u64(h, 5u64) }
        h = hash_u64(h, u64(t.max_lines))
        h = hash_bytes(h, t.ellipsis)
    case .Flex as f:
        h = hash_bytes(h, bytes_of[ui_layout.Flex](&f))
    case .Grid as g:
        h = hash_bytes(h, bytes_of[ui_layout.Grid](&g))
    case .Wrap as w:
        h = hash_bytes(h, bytes_of[ui_layout.Wrap](&w))
    case .Aspect as ratio:
        h = hash_f32(h, ratio)
    case .Button as bt:
        h = hash_bytes(h, bytes_of[Button](&bt))
    case .Image as im:
        h = hash_bytes(h, bytes_of[Image](&im))
    case .Region as r:
        h = hash_bytes(h, bytes_of[Region](&r))
    case .Scope as sc:
        if sc.traps_focus { h = hash_u64(h, 1u64) }
        h = hash_submit(h, sc.default_action)
        h = hash_submit(h, sc.cancel_action)
        h = hash_u64(h, u64(mem.address_of(sc.keys.ctx)))
        var i = 0usize
        while i < sc.shortcuts.len {
            h = hash_u64(h, u64(sc.shortcuts[i].key))
            h = hash_bytes(h, bytes_of[input.Modifiers](&sc.shortcuts[i].modifiers))
            h = hash_submit(h, sc.shortcuts[i].action)
            i += 1usize
        }
    case .Semantics as sm:
        h = hash_bytes(h, sm.label)
        h = hash_bytes(h, sm.value)
        h = hash_bytes(h, sm.hint)
        h = hash_bytes(h, bytes_of[Semantics](&sm))
    case .Custom as c:
        // A custom that names its state is as static as that state (D917).
        if c.state.len > 0usize {
            h = hash_bytes(h, c.state)
            var measure_bits: MeasureBits = zero
            measure_bits.function = c.measure
            var paint_bits: PaintBits = zero
            paint_bits.function = c.paint
            h = hash_u64(hash_u64(h, u64(measure_bits.bits)), u64(paint_bits.bits))
        } else {
            static = false
        }
    case .Box:
        static = true
    case .Stack:
        static = true
    case .Fitted:
        static = true
    default:
        static = false
    }
    ret (h, static)
}

// A replayed subtree's elements keep ranges into the scene compiled from it;
// they now stand `to - from` further along.
fn shift_replay(s: *State, element: usize, to: usize, from: usize) {
    let e = &s.elements[element]
    if e.has_replay {
        e.replay_from = u32(usize(e.replay_from) + to - from)
        e.replay_to = u32(usize(e.replay_to) + to - from)
    }
    var at = e.first_child
    var has = e.has_child
    while has {
        shift_replay(s, usize(at), to, from)
        has = s.elements[usize(at)].has_sibling
        at = s.elements[usize(at)].next_sibling
    }
}

// A moved subtree's elements stand where they did, moved.
fn shift_bounds(s: *State, element: usize, dx: f32, dy: f32) {
    let e = &s.elements[element]
    e.bounds.x = e.bounds.x + dx
    e.bounds.y = e.bounds.y + dy
    e.placed_outer.x = e.placed_outer.x + dx
    e.placed_outer.y = e.placed_outer.y + dy
    var at = e.first_child
    var has = e.has_child
    while has {
        shift_bounds(s, usize(at), dx, dy)
        has = s.elements[usize(at)].has_sibling
        at = s.elements[usize(at)].next_sibling
    }
}

fn owner_store(s: *State, key: usize, element: usize) {
    let cap = s.owners.len
    var slot = (key >> 3usize) % cap
    var probes = 0usize
    while probes < 16usize {
        let entry = &s.owners[slot]
        if entry.stamp != s.measure_stamp || entry.node == key { break }
        slot = (slot + 1usize) % cap
        probes += 1usize
    }
    if probes >= 16usize { slot = (key >> 3usize) % cap }
    s.owners[slot] = Owner { node: key, element: u32(element), stamp: s.measure_stamp }
}

fn owner_of(s: *State, key: usize) -> (usize, bool) {
    let cap = s.owners.len
    var slot = (key >> 3usize) % cap
    var probes = 0usize
    while probes < 16usize {
        let entry = &s.owners[slot]
        if entry.stamp != s.measure_stamp { ret (0usize, false) }
        if entry.node == key { ret (usize(entry.element), true) }
        slot = (slot + 1usize) % cap
        probes += 1usize
    }
    ret (0usize, false)
}

fn reconcile_node(s: *State, node: *const Node, parent: usize, has_parent: bool, position: usize, old_siblings: []const u32, depth: usize) -> (usize, err) {
    if depth > usize(s.limits.max_depth) { ret (0usize, TooDeep) }
    if style.validate(&node.style) != ok { ret (0usize, InvalidTree) }
    let (index, match_error) = match_element(s, parent, has_parent, node, position, old_siblings)
    if match_error != ok { ret (0usize, match_error) }
    let e = &s.elements[index]
    e.visited = true
    e.parent = u32(parent)
    e.has_parent = has_parent
    e.has_action = false
    e.text_len = 0usize
    e.gestures = 0u8
    e.focusable = false
    e.shortcut_count = 0usize
    e.has_semantics = false
    switch node.kind {
    case .Button as b:
        e.action = b.action
        e.has_action = true
        e.enabled = b.enabled
        e.focusable = b.enabled
    case .Text as t:
        var n = t.value.len
        if n > MAX_TEXT { n = MAX_TEXT }
        var i = 0usize
        while i < n {
            e.text[i] = t.value[i]
            i += 1usize
        }
        e.text_len = n
    case .Scroll as sc:
        e.scroll_axis = sc.axis
        if sc.offset != e.node_offset { e.scroll_offset = sc.offset }
        e.node_offset = sc.offset
        e.scroll_change = sc.change
        e.overscroll = sc.overscroll
        e.momentum = sc.momentum
        e.enabled = true
    case .Box:
        e.enabled = true
    case .Flex as f:
        e.enabled = true
    case .Grid as g:
        e.enabled = true
    case .Stack:
        e.enabled = true
    case .Image as im:
        e.enabled = true
    case .Custom as c:
        e.enabled = true
    case .Region as r:
        e.gesture = r.gesture
        e.gestures = r.gestures
        e.enabled = r.enabled
        e.focusable = r.focusable
    case .Scope as sc:
        e.enabled = true
        e.traps_focus = sc.traps_focus
        if sc.shortcuts.len > MAX_SHORTCUTS { ret (0usize, TooLarge) }
        var k = 0usize
        while k < sc.shortcuts.len {
            e.shortcuts[k] = sc.shortcuts[k]
            k += 1usize
        }
        e.shortcut_count = sc.shortcuts.len
        e.default_action = sc.default_action
        e.cancel_action = sc.cancel_action
        e.keys = sc.keys
    case .Edit as ed:
        // The node's length is taken when the caller changed it since the last
        // frame (or the buffer is another); else the runtime's edits stand, so a
        // caller that does not echo the value back keeps what was typed.
        if ed.len != e.node_len || ed.buffer.len != e.edit_buffer.len { e.edit_len = ed.len }
        e.node_len = ed.len
        e.edit_buffer = ed.buffer
        if e.edit_len > ed.buffer.len { e.edit_len = ed.buffer.len }
        if e.caret > e.edit_len { e.caret = e.edit_len }
        if e.anchor > e.edit_len { e.anchor = e.edit_len }
        e.edit_style = ed.style
        e.edit_change = ed.change
        e.edit_submit = ed.submit
        e.enabled = ed.enabled
        e.read_only = ed.read_only
        e.multiline = ed.multiline
        e.secret = ed.secret
        e.untabbed = ed.untabbed
        e.ringed = ed.ringed
        e.focusable = ed.enabled
        e.gestures = GESTURE_TAP | GESTURE_DRAG
    case .Semantics as sm:
        e.enabled = true
        e.sem = sm
        e.has_semantics = true
        e.text_len = copy_short(e.text[..], sm.label, MAX_TEXT)
        e.value_len = copy_short(e.value[..], sm.value, MAX_SHORT)
        e.hint_len = copy_short(e.hint[..], sm.hint, MAX_SHORT)
    case .Wrap as w:
        e.enabled = true
    case .Aspect as ratio:
        e.enabled = true
    case .Fitted:
        e.enabled = true
    case .Scrollbar as bar:
        e.enabled = true
        e.linked = bar.viewport
        e.scroll_axis = bar.axis
        e.gestures = GESTURE_DRAG
    case .Slider as sl:
        e.enabled = sl.enabled
        e.focusable = sl.enabled
        // Hovered too (D958), so its control can round the handle with its halo.
        e.gestures = GESTURE_TAP | GESTURE_DRAG | GESTURE_HOVER
        if sl.value != e.node_value { e.slider_value = sl.value }
        if sl.second != e.node_second { e.slider_second = sl.second }
        e.node_value = sl.value
        e.node_second = sl.second
        e.slider_low = sl.low
        e.slider_high = sl.high
        e.slider_step = sl.step
        e.slider_range = sl.range
        e.slider_vertical = sl.vertical
        e.slider_change = sl.change
        e.slider_change_second = sl.change_second
    case .Zoom as z:
        e.enabled = true
        if z.state.scale != e.node_zoom.scale || z.state.offset.x != e.node_zoom.offset.x || z.state.offset.y != e.node_zoom.offset.y {
            e.zoom_scale = z.state.scale
            e.zoom_offset = z.state.offset
        }
        e.node_zoom = z.state
        e.zoom_min = z.min_scale
        e.zoom_max = z.max_scale
        e.zoom_change = z.change
    case .Overlay as ov:
        e.enabled = true
        e.linked = ov.anchor
        e.modal = ov.modal
        e.dismiss = ov.dismiss
        if !e.overlay_opened {
            e.overlay_opened = true
            e.saved_focus = s.focus
            e.has_saved = s.has_focus
            e.wants_focus = ov.modal
        }
    }
    // Duplicate nonzero keys among siblings are refused.
    var i = 0usize
    while i < node.children.len {
        if node.children[i].key != 0u64 {
            var j = i + 1usize
            while j < node.children.len {
                if node.children[j].key == node.children[i].key { ret (0usize, DuplicateKey) }
                j += 1usize
            }
        }
        i += 1usize
    }
    let previous_first = e.first_child
    let previous_has = e.has_child
    // The old children are gathered and unvisited before the new list is threaded
    // over the same links, so the ones left unmatched can still be found.
    var old_children: [64]u32 = zero
    var old_count = 0usize
    var at = previous_first
    var has = previous_has
    while has {
        let old = &s.elements[usize(at)]
        old.visited = false
        if old_count >= 64usize { ret (0usize, TooLarge) }
        old_children[old_count] = at
        old_count += 1usize
        has = old.has_sibling
        at = old.next_sibling
    }
    var last = 0usize
    var has_last = false
    e.has_child = false
    let (own_hash, own_static) = hash_node(FNV_OFFSET, node)
    var subtree_hash = own_hash
    if ringed(s, index) { subtree_hash = hash_u64(hash_bytes(subtree_hash, bytes_of[paint.Color](&s.ring_color)), u64(u32(s.ring_width * 64.0))) }
    if rippled(s, index) { subtree_hash = hash_f32(hash_f32(hash_f32(hash_bytes(subtree_hash, bytes_of[paint.Color](&s.ripple_color)), s.ripple_phase), s.arena_state.down.x), s.arena_state.down.y) }
    var static_subtree = own_static
    i = 0usize
    while i < node.children.len {
        let (child, child_error) = reconcile_node(s, &node.children[i], index, true, i, old_children[0usize..old_count], depth + 1usize)
        if child_error != ok { ret (0usize, child_error) }
        subtree_hash = hash_u64(subtree_hash, s.elements[child].subtree_hash)
        if !s.elements[child].static_subtree { static_subtree = false }
        let owner = &s.elements[index]
        if has_last {
            s.elements[last].next_sibling = u32(child)
            s.elements[last].has_sibling = true
        } else {
            owner.first_child = u32(child)
            owner.has_child = true
        }
        s.elements[child].has_sibling = false
        last = child
        has_last = true
        i += 1usize
    }
    // Whatever old child was not matched is retired.
    var o = 0usize
    while o < old_count {
        let old = &s.elements[usize(old_children[o])]
        if old.live && !old.visited { retire_element(s, usize(old_children[o])) }
        o += 1usize
    }
    let me = &s.elements[index]
    me.unchanged = me.has_replay && me.static_subtree && static_subtree && me.subtree_hash == subtree_hash && !me.invalid
    me.subtree_hash = subtree_hash
    me.static_subtree = static_subtree
    let key = mem.address_of(node)
    owner_store(s, key, index)
    // An unchanged subtree measures as it did, without a walk.
    if me.unchanged {
        var k = 0usize
        while k < 4usize {
            if me.sizes[k].valid { measured_store(s, key, me.sizes[k].limits, me.sizes[k].size, zero) }
            k += 1usize
        }
    }
    ret (index, ok)
}

// ---------------------------------------------------------------------- layout

fn length_px(value: style.Length, reference: f32, fallback: f32) -> f32 {
    switch value {
    case .Auto:
        ret fallback
    case .Px as px:
        ret px
    case .Percent as percent:
        if !bounded(reference) { ret fallback }
        ret reference * percent / 100.0
    case .Flex as share:
        ret fallback
    }
    ret fallback
}

fn bounded(v: f32) -> bool {
    ret v == v && v < 3.0e38
}

fn edges_px(edges: style.EdgeLengths, reference: f32) -> geometry.Insets {
    ret geometry.Insets { left: length_px(edges.left, reference, 0.0), top: length_px(edges.top, reference, 0.0), right: length_px(edges.right, reference, 0.0), bottom: length_px(edges.bottom, reference, 0.0) }
}

fn flex_share(value: style.Length) -> f32 {
    switch value {
    case .Auto:
        ret 0.0
    case .Px as px:
        ret 0.0
    case .Percent as percent:
        ret 0.0
    case .Flex as share:
        ret share
    }
    ret 0.0
}

fn max_f(a: f32, b: f32) -> f32 {
    if a > b { ret a }
    ret b
}

fn min_f(a: f32, b: f32) -> f32 {
    if a < b { ret a }
    ret b
}

// The size a node takes under `limits`: its style's own, else its content's,
// then clamped by its min/max and the limits, margins included.
fn same_limits(a: ui_layout.Constraints, b: ui_layout.Constraints) -> bool {
    ret a.min_width == b.min_width && a.max_width == b.max_width && a.min_height == b.min_height && a.max_height == b.max_height
}

fn measured_lookup(s: *State, key: usize, limits: ui_layout.Constraints) -> (geometry.Size, bool) {
    let (entry, found) = measured_entry(s, key, limits, false, 0.0)
    if !found { ret (zero, false) }
    ret (entry.size, true)
}

// The entry for `key` under `limits` exactly, or, `loose`, any single-line entry
// for `key` whose line fits `max_width`.
fn measured_entry(s: *State, key: usize, limits: ui_layout.Constraints, loose: bool, max_width: f32) -> (*Measured, bool) {
    let cap = s.measured.len
    var slot = (key >> 3usize) % cap
    var probes = 0usize
    while probes < 16usize {
        let entry = &s.measured[slot]
        if entry.stamp != s.measure_stamp { ret (entry, false) }
        if entry.node == key {
            if !loose && same_limits(entry.limits, limits) { ret (entry, true) }
            if loose && entry.limits.min_height == 1.0 && entry.size.width <= max_width { ret (entry, true) }
        }
        slot = (slot + 1usize) % cap
        probes += 1usize
    }
    ret (&s.measured[0usize], false)
}

// A single-line measure of the text whose line fits `max_width`.
fn measured_single(s: *State, key: usize, max_width: f32) -> (geometry.Size, bool) {
    let (entry, found) = measured_entry(s, key, zero, true, max_width)
    if !found { ret (zero, false) }
    ret (entry.size, true)
}

fn measured_store(s: *State, key: usize, limits: ui_layout.Constraints, size: geometry.Size, laid: layout.Layout) {
    let cap = s.measured.len
    var slot = (key >> 3usize) % cap
    var probes = 0usize
    while probes < 16usize {
        let entry = &s.measured[slot]
        if entry.stamp != s.measure_stamp || (entry.node == key && same_limits(entry.limits, limits)) { break }
        slot = (slot + 1usize) % cap
        probes += 1usize
    }
    if probes >= 16usize { slot = (key >> 3usize) % cap }
    s.measured[slot] = Measured { node: key, limits: limits, size: size, laid: laid, stamp: s.measure_stamp }
}

fn measure(s: *State, a: *mem.Arena, node: *const Node, limits: ui_layout.Constraints) -> (geometry.Size, err) {
    let key = mem.address_of(node)
    let (known, has_known) = measured_lookup(s, key, limits)
    if has_known { ret (known, ok) }
    let (size, size_error) = measure_uncached(s, a, node, limits)
    if size_error != ok { ret (size, size_error) }
    measured_store(s, key, limits, size, zero)
    let (element, owned) = owner_of(s, key)
    if owned {
        let e = &s.elements[element]
        var k = 0usize
        var found = false
        while k < 4usize {
            if e.sizes[k].valid && same_limits(e.sizes[k].limits, limits) {
                e.sizes[k].size = size
                found = true
            }
            k += 1usize
        }
        if !found {
            e.sizes[usize(e.size_next)] = Sized { limits: limits, size: size, valid: true }
            e.size_next = (e.size_next + 1u8) % 4u8
        }
    }
    ret (size, ok)
}

fn measure_uncached(s: *State, a: *mem.Arena, node: *const Node, limits: ui_layout.Constraints) -> (geometry.Size, err) {
    let margin = edges_px(node.style.margin, limits.max_width)
    let padding = edges_px(node.style.padding, limits.max_width)
    let horizontal_extra = margin.left + margin.right + padding.left + padding.right
    let vertical_extra = margin.top + margin.bottom + padding.top + padding.bottom
    var inner = ui_layout.Constraints { min_width: 0.0, max_width: limits.max_width - horizontal_extra, min_height: 0.0, max_height: limits.max_height - vertical_extra }
    // A fixed size bounds the content too: a wrap 180 px wide in an unbounded row
    // measures its rows at 180 px, not as one row (D913).
    let (own_width, has_own_width) = style.px_of(node.style.width)
    if has_own_width && own_width - padding.left - padding.right < inner.max_width { inner.max_width = own_width - padding.left - padding.right }
    let (own_height, has_own_height) = style.px_of(node.style.height)
    if has_own_height && own_height - padding.top - padding.bottom < inner.max_height { inner.max_height = own_height - padding.top - padding.bottom }
    if inner.max_width < 0.0 { inner.max_width = 0.0 }
    if inner.max_height < 0.0 { inner.max_height = 0.0 }
    let (content, content_error) = measure_content(s, a, node, inner)
    if content_error != ok { ret (zero, content_error) }
    var width = length_px(node.style.width, limits.max_width, content.width + padding.left + padding.right)
    var height = length_px(node.style.height, limits.max_height, content.height + padding.top + padding.bottom)
    width = max_f(width, length_px(node.style.min_width, limits.max_width, 0.0))
    height = max_f(height, length_px(node.style.min_height, limits.max_height, 0.0))
    width = min_f(width, length_px(node.style.max_width, limits.max_width, 3.0e38))
    height = min_f(height, length_px(node.style.max_height, limits.max_height, 3.0e38))
    let size = ui_layout.constrain(geometry.Size { width: width + margin.left + margin.right, height: height + margin.top + margin.bottom }, limits)
    ret (size, ok)
}

// The children's extent, by the node's kind, inside the padding.
fn measure_content(s: *State, a: *mem.Arena, node: *const Node, inner: ui_layout.Constraints) -> (geometry.Size, err) {
    switch node.kind {
    case .Text as t:
        // A text with no font choice measures as nothing and paints nothing: a
        // label that exists for the semantic tree alone.
        if t.style.fonts.len == 0usize { ret (geometry.Size { width: 0.0, height: 0.0 }, ok) }
        // A text's extent depends on its width alone: remembered under the node's
        // odd key, whatever the other constraints (D914).
        let text_key = mem.address_of(node) | 1usize
        let text_limits = ui_layout.Constraints { min_width: 0.0, max_width: inner.max_width, min_height: 0.0, max_height: 0.0 }
        let (known, has_known) = measured_lookup(s, text_key, text_limits)
        if has_known { ret (known, ok) }
        // A text laid on one line under some width is the same under any width
        // that holds that line.
        let (single, has_single) = measured_single(s, text_key, inner.max_width)
        if has_single { ret (single, ok) }
        let (laid, layout_error) = layout.layout(a, t.value, t.style, layout.Options { width: inner.max_width, max_lines: t.max_lines, align: t.align, wrap: t.wrap, ellipsis: t.ellipsis })
        if layout_error != ok { ret (zero, InvalidTree) }
        var remembered = text_limits
        if laid.lines.len <= 1usize { remembered.min_height = 1.0 }
        measured_store(s, text_key, remembered, geometry.Size { width: laid.bounds.width, height: laid.bounds.height }, laid)
        ret (geometry.Size { width: laid.bounds.width, height: laid.bounds.height }, ok)
    case .Custom as c:
        ret (c.measure(c.ctx, inner), ok)
    case .Edit as ed:
        if ed.style.fonts.len == 0usize { ret (geometry.Size { width: 0.0, height: 0.0 }, ok) }
        // An empty value stands one line tall.
        if ed.len == 0usize { ret (geometry.Size { width: 0.0, height: ed.style.line_height }, ok) }
        let (laid, layout_error) = layout.layout(a, ed.buffer[0usize..ed.len], ed.style, edit_options(inner.max_width, ed.multiline))
        if layout_error != ok { ret (zero, InvalidTree) }
        ret (geometry.Size { width: laid.bounds.width, height: laid.bounds.height }, ok)
    case .Image as im:
        ret (geometry.Size { width: 0.0, height: 0.0 }, ok)
    case .Flex as f:
        let (flexed, flex_error) = measure_flex(s, a, node, f, inner)
        ret (flexed, flex_error)
    case .Grid as g:
        let (gridded, grid_error) = measure_grid(s, a, node, g, inner)
        ret (gridded, grid_error)
    case .Stack:
        let (stacked, stack_error) = measure_stack(s, a, node, inner)
        ret (stacked, stack_error)
    case .Box:
        let (boxed, box_error) = measure_flex(s, a, node, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner)
        ret (boxed, box_error)
    case .Button as b:
        let (buttoned, button_error) = measure_flex(s, a, node, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner)
        ret (buttoned, button_error)
    case .Region as r:
        let (regioned, region_error) = measure_flex(s, a, node, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner)
        ret (regioned, region_error)
    case .Scope as sc:
        let (scoped, scope_error) = measure_flex(s, a, node, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner)
        ret (scoped, scope_error)
    case .Semantics as sm:
        let (described, describe_error) = measure_flex(s, a, node, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner)
        ret (described, describe_error)
    case .Overlay as ov:
        ret (geometry.Size { width: 0.0, height: 0.0 }, ok)
    case .Aspect as ratio:
        // As wide as it may be -- or as its content when unbounded -- and the ratio tall.
        let (content, content_error) = measure_flex(s, a, node, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner)
        if content_error != ok { ret (zero, content_error) }
        var width = inner.max_width
        if !(width < 1.0e30) || !(ratio > 0.0) { width = content.width }
        var height = width
        if ratio > 0.0 { height = width / ratio }
        ret (geometry.Size { width: width, height: height }, ok)
    case .Scrollbar as bar:
        ret (geometry.Size { width: 0.0, height: 0.0 }, ok)
    case .Slider as sl:
        ret (geometry.Size { width: 0.0, height: 0.0 }, ok)
    case .Fitted:
        let (natural, natural_error) = measure_flex(s, a, node, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, ui_layout.Constraints { min_width: 0.0, max_width: 3.0e38, min_height: 0.0, max_height: 3.0e38 })
        if natural_error != ok { ret (zero, natural_error) }
        ret (ui_layout.constrain(natural, inner), ok)
    case .Zoom as z:
        let (natural, natural_error) = measure_flex(s, a, node, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, ui_layout.Constraints { min_width: 0.0, max_width: 3.0e38, min_height: 0.0, max_height: 3.0e38 })
        if natural_error != ok { ret (zero, natural_error) }
        ret (ui_layout.constrain(natural, inner), ok)
    case .Wrap as w:
        let (children, children_error) = children_of(s, a, node, inner, w.axis == .Horizontal)
        if children_error != ok { ret (zero, children_error) }
        let (result, layout_error) = ui_layout.wrap(a, w, ui_layout.Constraints { min_width: 0.0, max_width: inner.max_width, min_height: 0.0, max_height: inner.max_height }, children)
        if layout_error != ok { ret (zero, InvalidTree) }
        ret (result.size, ok)
    case .Scroll as sc:
        var open = inner
        if sc.axis == .Vertical { open.max_height = 3.0e38 } else { open.max_width = 3.0e38 }
        let (content, content_error) = measure_stack(s, a, node, open)
        if content_error != ok { ret (zero, content_error) }
        if sc.virtual_count != 0usize {
            let total = f32(sc.virtual_count) * sc.virtual_extent
            if sc.axis == .Vertical { ret (ui_layout.constrain(geometry.Size { width: content.width, height: total }, inner), ok) }
            ret (ui_layout.constrain(geometry.Size { width: total, height: content.height }, inner), ok)
        }
        ret (ui_layout.constrain(content, inner), ok)
    }
    ret (zero, ok)
}

fn children_of(s: *State, a: *mem.Arena, node: *const Node, inner: ui_layout.Constraints, horizontal: bool) -> ([]ui_layout.Child, err) {
    var nothing: []ui_layout.Child = zero
    let (children, children_error) = mem.alloc[ui_layout.Child](a, node.children.len)
    if children_error != ok { ret (nothing, TooLarge) }
    var i = 0usize
    while i < node.children.len {
        let (size, size_error) = measure(s, a, &node.children[i], inner)
        if size_error != ok { ret (nothing, size_error) }
        var share = flex_share(node.children[i].style.height)
        if horizontal { share = flex_share(node.children[i].style.width) }
        children[i] = ui_layout.Child { desired: size, flex: share }
        i += 1usize
    }
    ret (children, ok)
}

fn measure_flex(s: *State, a: *mem.Arena, node: *const Node, spec: ui_layout.Flex, inner: ui_layout.Constraints) -> (geometry.Size, err) {
    let (children, children_error) = children_of(s, a, node, inner, spec.axis == .Horizontal)
    if children_error != ok { ret (zero, children_error) }
    if children.len == 0usize { ret (geometry.Size { width: 0.0, height: 0.0 }, ok) }
    let (result, layout_error) = ui_layout.flex(a, spec, ui_layout.Constraints { min_width: 0.0, max_width: inner.max_width, min_height: 0.0, max_height: inner.max_height }, children)
    if layout_error != ok { ret (zero, InvalidTree) }
    ret (result.size, ok)
}

fn measure_grid(s: *State, a: *mem.Arena, node: *const Node, spec: ui_layout.Grid, inner: ui_layout.Constraints) -> (geometry.Size, err) {
    let (children, children_error) = children_of(s, a, node, inner, false)
    if children_error != ok { ret (zero, children_error) }
    let (result, layout_error) = ui_layout.grid(a, spec, ui_layout.Constraints { min_width: 0.0, max_width: inner.max_width, min_height: 0.0, max_height: inner.max_height }, children)
    if layout_error != ok { ret (zero, InvalidTree) }
    ret (result.size, ok)
}

fn measure_stack(s: *State, a: *mem.Arena, node: *const Node, inner: ui_layout.Constraints) -> (geometry.Size, err) {
    var width: f32 = 0.0
    var height: f32 = 0.0
    var i = 0usize
    while i < node.children.len {
        let (size, size_error) = measure(s, a, &node.children[i], inner)
        if size_error != ok { ret (zero, size_error) }
        width = max_f(width, size.width)
        height = max_f(height, size.height)
        i += 1usize
    }
    ret (geometry.Size { width: width, height: height }, ok)
}

// The node and its subtree placed in `outer` (its margin box) and painted.
fn place(s: *State, a: *mem.Arena, node: *const Node, element: usize, outer: geometry.Rect, b: *scene.Builder, depth: usize) -> err {
    let margin = edges_px(node.style.margin, outer.width)
    let padding = edges_px(node.style.padding, outer.width)
    let bounds = geometry.Rect { x: outer.x + margin.left, y: outer.y + margin.top, width: max_f(outer.width - margin.left - margin.right, 0.0), height: max_f(outer.height - margin.top - margin.bottom, 0.0) }
    let e = &s.elements[element]
    let from = scene.builder_count(b)
    if e.unchanged && e.has_replay && s.has_replay_scene && outer.width == e.placed_outer.width && outer.height == e.placed_outer.height && !(outer.x == e.placed_outer.x && outer.y == e.placed_outer.y) {
        // The same subtree, moved: its commands and its elements' bounds move with it.
        let dx = outer.x - e.placed_outer.x
        let dy = outer.y - e.placed_outer.y
        if scene.replay_shifted(s.renderer, s.replay_scene, usize(e.replay_from), usize(e.replay_to), dx, dy, a, b) {
            shift_replay(s, element, from, usize(e.replay_from))
            shift_bounds(s, element, dx, dy)
            ret ok
        }
    }
    if e.unchanged && e.has_replay && s.has_replay_scene && outer.x == e.placed_outer.x && outer.y == e.placed_outer.y && outer.width == e.placed_outer.width && outer.height == e.placed_outer.height {
        if scene.replay(s.renderer, s.replay_scene, usize(e.replay_from), usize(e.replay_to), b) {
            // The subtree's own ranges move with it.
            shift_replay(s, element, from, usize(e.replay_from))
            ret ok
        }
    }
    e.has_replay = false
    e.bounds = bounds
    e.invalid = false
    e.placed_outer = outer
    let inner = geometry.Rect { x: bounds.x + padding.left, y: bounds.y + padding.top, width: max_f(bounds.width - padding.left - padding.right, 0.0), height: max_f(bounds.height - padding.top - padding.bottom, 0.0) }
    let inner_limits = ui_layout.Constraints { min_width: 0.0, max_width: inner.width, min_height: 0.0, max_height: inner.height }
    var save: scene.Command = .Save
    var restore: scene.Command = .Restore
    var layered = false
    if node.style.opacity < 1.0 {
        try scene.push(b, scene.Command { OpacityLayer: scene.OpacityLayer { bounds: bounds, opacity: node.style.opacity } })
        layered = true
    }
    var clipped = node.style.overflow != .Visible
    let radius = node.style.radius
    let corner = corners_of(&node.style)
    let shaped = corner.top_left > 0.0 || corner.top_right > 0.0 || corner.bottom_right > 0.0 || corner.bottom_left > 0.0
    let outer_clip = s.clip_rect
    let outer_has_clip = s.has_clip
    // The shadow lies under everything, the background's shape at its offset.
    if node.style.shadow.color.alpha > 0.0 {
        let shifted = geometry.Rect { x: bounds.x + node.style.shadow.offset.x, y: bounds.y + node.style.shadow.offset.y, width: bounds.width, height: bounds.height }
        try fill_corners(a, b, shifted, corner, paint.Brush { Solid: node.style.shadow.color })
    }
    if clipped {
        try scene.push(b, save)
        if shaped {
            try scene.push(b, scene.Command { Clip: scene.Clip { Rounded: shape_of(bounds, corner, 0.0) } })
        } else {
            try scene.push(b, scene.Command { Clip: scene.Clip { Rect: bounds } })
        }
        s.clip_rect = bounds
        if outer_has_clip { s.clip_rect = intersect(outer_clip, bounds) }
        s.has_clip = true
    }
    let background = node.style.background
    var paint_background = true
    switch background {
    case .Solid as color:
        paint_background = color.alpha > 0.0
    case .Linear as linear:
        paint_background = true
    case .Radial as radial:
        paint_background = true
    }
    if paint_background { try fill_corners(a, b, bounds, corner, background) }
    // The border is stroked inside the bounds, on the rounded shape when there is one.
    if node.style.border.width > 0.0 && node.style.border.color.alpha > 0.0 {
        let half = node.style.border.width * 0.5
        let inset = geometry.Rect { x: bounds.x + half, y: bounds.y + half, width: max_f(bounds.width - node.style.border.width, 0.0), height: max_f(bounds.height - node.style.border.width, 0.0) }
        let (outline, outline_error) = shape_path(a, shape_of(inset, corner, 0.0 - half))
        if outline_error != ok { ret TooLarge }
        try scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: outline, brush: paint.Brush { Solid: node.style.border.color }, stroke: paint.Stroke { width: node.style.border.width, cap: .Butt, join: .Miter, miter_limit: 4.0 } } })
    }
    switch node.kind {
    case .Text as t:
        if t.style.fonts.len == 0usize {
            s.clip_rect = outer_clip
            s.has_clip = outer_has_clip
            ret finish_place(b, clipped, layered)
        }
        // The measure's layout serves the paint when it was made under this width,
        // or is one start-aligned line that fits it (D914).
        var laid: layout.Layout = zero
        var reused = false
        let text_key = mem.address_of(node) | 1usize
        let (exact, has_exact) = measured_entry(s, text_key, ui_layout.Constraints { min_width: 0.0, max_width: inner.width, min_height: 0.0, max_height: 0.0 }, false, 0.0)
        if has_exact {
            laid = exact.laid
            reused = true
        } else if t.align == .Start {
            let (loose, has_loose) = measured_entry(s, text_key, zero, true, inner.width)
            if has_loose {
                laid = loose.laid
                reused = true
            }
        }
        if !reused {
            let (fresh, layout_error) = layout.layout(a, t.value, t.style, layout.Options { width: inner.width, max_lines: t.max_lines, align: t.align, wrap: t.wrap, ellipsis: t.ellipsis })
            if layout_error != ok { ret InvalidTree }
            laid = fresh
        }
        let (copies, copies_error) = mem.alloc[layout.Layout](a, 1usize)
        if copies_error != ok { ret TooLarge }
        copies[0usize] = laid
        try scene.push(b, scene.Command { Text: scene.DrawText { layout: &copies[0usize], origin: geometry.Point { x: inner.x, y: inner.y }, brush: paint.Brush { Solid: t.color } } })
    case .Image as im:
        try scene.push(b, scene.Command { Image: scene.DrawImage { texture: im.texture, source: geometry.Rect { x: 0.0, y: 0.0, width: 1.0, height: 1.0 }, destination: inner, opacity: 1.0 } })
    case .Custom as c:
        try c.paint(c.ctx, b, inner)
    case .Edit as ed:
        try place_edit(s, a, element, ed, inner, b)
    case .Flex as f:
        try place_flex(s, a, node, element, f, inner, inner_limits, b, depth)
    case .Box:
        try place_flex(s, a, node, element, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner, inner_limits, b, depth)
    case .Button as bt:
        try place_flex(s, a, node, element, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner, inner_limits, b, depth)
    case .Region as r:
        try place_flex(s, a, node, element, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner, inner_limits, b, depth)
    case .Scope as sc:
        try place_flex(s, a, node, element, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner, inner_limits, b, depth)
    case .Semantics as sm:
        try place_flex(s, a, node, element, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner, inner_limits, b, depth)
    case .Wrap as w:
        try place_wrap(s, a, node, element, w, inner, inner_limits, b, depth)
    case .Aspect as ratio:
        try place_flex(s, a, node, element, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner, inner_limits, b, depth)
    case .Fitted:
        try place_fitted(s, a, node, element, inner, b, depth)
    case .Zoom as z:
        try place_zoom(s, a, node, element, inner, b, depth)
    case .Scrollbar as bar:
        try place_scrollbar(s, bar, inner, b, node.style.border.color)
    case .Slider as sl:
        try place_slider(s, a, element, sl, inner, b)
    case .Overlay as ov:
        if s.overlay_count >= MAX_OVERLAYS { ret TooLarge }
        s.overlays[s.overlay_count] = u32(element)
        s.overlay_nodes[s.overlay_count] = node
        s.overlay_count += 1usize
    case .Grid as g:
        try place_grid(s, a, node, element, g, inner, inner_limits, b, depth)
    case .Stack:
        try place_stack(s, a, node, element, inner, inner_limits, b, depth)
    case .Scroll as sc:
        try place_scroll(s, a, node, element, sc, inner, inner_limits, b, depth)
    }
    try finish_place(b, clipped, layered)
    s.clip_rect = outer_clip
    s.has_clip = outer_has_clip
    if rippled(s, element) { try place_ripple(s, a, b, bounds, corner) }
    if ringed(s, element) { try place_ring(s, a, b, element, bounds, corner) }
    let placed = &s.elements[element]
    if placed.static_subtree {
        placed.replay_from = u32(from)
        placed.replay_to = u32(scene.builder_count(b))
        placed.has_replay = true
    }
    ret ok
}

fn edit_options(width: f32, multiline: bool) -> layout.Options {
    var wrapping: layout.Wrap = .None
    if multiline { wrapping = .Word }
    ret layout.Options { width: width, max_lines: 0u32, align: .Start, wrap: wrapping, ellipsis: "" }
}

// The text an editor shows: its value, with the composition at the caret when it is
// the focused one.
fn edit_display(s: *State, a: *mem.Arena, e: *const Element, composing: bool) -> (str, err) {
    var value: str = e.edit_buffer[0usize..e.edit_len]
    if e.secret {
        // A secret shows an asterisk per byte (D823), so every offset the caret,
        // the selection and a hit test use stands where the value's does.
        let (masked, masked_error) = mem.alloc[u8](a, e.edit_len)
        if masked_error != ok { ret ("", TooLarge) }
        var m = 0usize
        while m < e.edit_len {
            masked[m] = 42u8
            m += 1usize
        }
        value = masked[..]
    }
    if !composing || s.compose_len == 0usize { ret (value, ok) }
    let (d, d_error) = mem.alloc[u8](a, e.edit_len + s.compose_len)
    if d_error != ok { ret ("", TooLarge) }
    var i = 0usize
    while i < e.caret {
        d[i] = value[i]
        i += 1usize
    }
    var k = 0usize
    while k < s.compose_len {
        d[e.caret + k] = s.compose[k]
        k += 1usize
    }
    while i < e.edit_len {
        d[i + s.compose_len] = value[i]
        i += 1usize
    }
    ret (d[..], ok)
}

fn push_rect(b: *scene.Builder, r: geometry.Rect, origin: geometry.Point, color: paint.Color) -> err {
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: origin.x + r.x, y: origin.y + r.y, width: r.width, height: r.height }, brush: paint.Brush { Solid: color } } })
}

// An editor paints its selection under the text, then the text, then -- focused --
// an underline beneath the composition and a one-pixel caret.
fn place_edit(s: *State, a: *mem.Arena, element: usize, ed: Edit, inner: geometry.Rect, b: *scene.Builder) -> err {
    let e = &s.elements[element]
    let origin = geometry.Point { x: inner.x, y: inner.y }
    e.text_origin = origin
    e.text_width = inner.width
    if ed.style.fonts.len == 0usize { ret ok }
    let focused_here = s.has_focus && usize(s.focus) == element
    let (shown, shown_error) = edit_display(s, a, e, focused_here)
    if shown_error != ok { ret shown_error }
    if shown.len == 0usize {
        // Nothing to lay out: the caret alone, one line tall.
        if focused_here { try push_rect(b, geometry.Rect { x: 0.0, y: 0.0, width: 1.0, height: ed.style.line_height }, origin, ed.color) }
        ret ok
    }
    let (laid, layout_error) = layout.layout(a, shown, ed.style, edit_options(inner.width, ed.multiline))
    if layout_error != ok { ret InvalidTree }
    let (copies, copies_error) = mem.alloc[layout.Layout](a, 1usize)
    if copies_error != ok { ret TooLarge }
    copies[0usize] = laid
    if focused_here {
        let (lo, hi) = selection_of(e)
        if lo < hi {
            let (rects, rects_error) = layout.selection(a, &copies[0usize], lo, hi)
            if rects_error != ok { ret InvalidTree }
            var i = 0usize
            while i < rects.len {
                try push_rect(b, rects[i], origin, ed.selection)
                i += 1usize
            }
        }
    }
    try scene.push(b, scene.Command { Text: scene.DrawText { layout: &copies[0usize], origin: origin, brush: paint.Brush { Solid: ed.color } } })
    if focused_here && ed.marked.alpha > 0.0 {
        // The selected glyphs again in their own colour, clipped to the selection.
        let (lo, hi) = selection_of(e)
        if lo < hi {
            let (marks, marks_error) = layout.selection(a, &copies[0usize], lo, hi)
            if marks_error != ok { ret InvalidTree }
            var m = 0usize
            while m < marks.len {
                let r = marks[m]
                var save: scene.Command = .Save
                var restore: scene.Command = .Restore
                try scene.push(b, save)
                try scene.push(b, scene.Command { Clip: scene.Clip { Rect: geometry.Rect { x: origin.x + r.x, y: origin.y + r.y, width: r.width, height: r.height } } })
                try scene.push(b, scene.Command { Text: scene.DrawText { layout: &copies[0usize], origin: origin, brush: paint.Brush { Solid: ed.marked } } })
                try scene.push(b, restore)
                m += 1usize
            }
        }
    }
    if focused_here {
        if s.compose_len != 0usize {
            let (under, under_error) = layout.selection(a, &copies[0usize], e.caret, e.caret + s.compose_len)
            if under_error != ok { ret InvalidTree }
            var k = 0usize
            while k < under.len {
                let r = under[k]
                try push_rect(b, geometry.Rect { x: r.x, y: r.y + r.height - 1.0, width: r.width, height: 1.0 }, origin, ed.color)
                k += 1usize
            }
        }
        let c = layout.caret(&copies[0usize], e.caret + s.compose_len)
        var caret_color = ed.color
        var caret_width: f32 = 1.0
        if ed.caret.alpha > 0.0 {
            caret_color = ed.caret
            caret_width = 2.0
        }
        try push_rect(b, geometry.Rect { x: c.x, y: c.y, width: caret_width, height: c.height }, origin, caret_color)
    }
    ret ok
}

// A viewport: its content measured for the extents, the offset clamped to them
// (unless it may overshoot), the children placed shifted and clipped -- a lazy
// viewport's at their item positions -- and the scrollbar thumb over them.
fn place_scroll(s: *State, a: *mem.Arena, node: *const Node, element: usize, sc: Scroll, inner: geometry.Rect, limits: ui_layout.Constraints, b: *scene.Builder, depth: usize) -> err {
    var save: scene.Command = .Save
    var restore: scene.Command = .Restore
    let vertical = sc.axis == .Vertical
    var open = limits
    if vertical { open.max_height = 3.0e38 } else { open.max_width = 3.0e38 }
    var content: f32 = 0.0
    if sc.virtual_count != 0usize {
        content = f32(sc.virtual_count) * sc.virtual_extent
    } else {
        let (measured, measure_error) = measure_stack(s, a, node, open)
        if measure_error != ok { ret measure_error }
        if vertical { content = measured.height } else { content = measured.width }
    }
    let e = &s.elements[element]
    e.content_extent = content
    if vertical { e.viewport_extent = inner.height } else { e.viewport_extent = inner.width }
    let most = max_f(content - e.viewport_extent, 0.0)
    if e.overscroll == .Clamp {
        if e.scroll_offset > most { e.scroll_offset = most }
        if e.scroll_offset < 0.0 { e.scroll_offset = 0.0 }
    }
    // The content is placed at a whole device pixel (D917): a fractional offset
    // -- momentum, a drag -- would keep the renderer from moving pixels.
    var offset = e.scroll_offset
    if s.snap > 0.0 { offset = math.round[f32](offset / s.snap) * s.snap }
    try scene.push(b, save)
    try scene.push(b, scene.Command { Clip: scene.Clip { Rect: inner } })
    if sc.virtual_count != 0usize {
        var i = 0usize
        while i < node.children.len {
            let at = f32(sc.virtual_first + i) * sc.virtual_extent - offset
            var slot = geometry.Rect { x: inner.x, y: inner.y + at, width: inner.width, height: sc.virtual_extent }
            if !vertical { slot = geometry.Rect { x: inner.x + at, y: inner.y, width: sc.virtual_extent, height: inner.height } }
            try place(s, a, &node.children[i], child_element(s, element, i), slot, b, depth + 1usize)
            i += 1usize
        }
    } else {
        var shifted = inner
        if vertical { shifted.y = inner.y - offset } else { shifted.x = inner.x - offset }
        try place_stack(s, a, node, element, shifted, open, b, depth)
    }
    if sc.scrollbar && content > e.viewport_extent {
        // ponytail: the thumb is painted, not dragged; a press on it scrolls the content.
        // v2 (D979, docs/ux/components/VirtualList): 4 wide, fully rounded, 2 from
        // the trailing edge, viewport squared over the content long, 32 at least.
        // ponytail: no widening to 8 on hover, fade after 1.5 s or touch handle.
        let viewport = e.viewport_extent
        var length = viewport * viewport / content
        if length < 32.0 { length = min_f(32.0, viewport) }
        var at = offset / content * viewport
        if at > viewport - length { at = viewport - length }
        if at < 0.0 { at = 0.0 }
        var thumb = geometry.Rect { x: inner.x + inner.width - 6.0, y: inner.y + at, width: 4.0, height: length }
        if !vertical { thumb = geometry.Rect { x: inner.x + at, y: inner.y + inner.height - 6.0, width: length, height: 4.0 } }
        try fill_shape(a, b, thumb, 2.0, paint.Brush { Solid: sc.thumb })
    }
    try scene.push(b, restore)
    ret ok
}

// Where an overlay's content of `size` goes against its anchor, kept in the window.
fn overlay_rect(anchor: geometry.Rect, size: geometry.Size, ov: Overlay, window_size: geometry.Size) -> geometry.Rect {
    var x = anchor.x
    var y = anchor.y
    let p = ov.placement
    let below = p == .Below || p == .BelowCenter || p == .BelowEnd || p == .BelowMatch
    let above = p == .Above || p == .AboveCenter || p == .AboveMatch || p == .AbovePoint
    if p == .BelowCenter || p == .AboveCenter || p == .TopCenter { x = anchor.x + (anchor.width - size.width) * 0.5 }
    if p == .BelowEnd { x = anchor.x + anchor.width - size.width }
    if p == .AbovePoint { x = anchor.x - size.width * 0.5 }
    if below { y = anchor.y + anchor.height }
    if above { y = anchor.y - size.height }
    if p == .Right { x = anchor.x + anchor.width }
    if p == .Left { x = anchor.x - size.width }
    if p == .Center {
        x = (window_size.width - size.width) * 0.5
        y = (window_size.height - size.height) * 0.5
    }
    if p == .At {
        x = 0.0
        y = 0.0
    }
    x += ov.offset.x
    y += ov.offset.y
    // Flip to the other side when this one overflows and that one fits (D975).
    if below && y + size.height > window_size.height && anchor.y - size.height - ov.offset.y >= 0.0 { y = anchor.y - size.height - ov.offset.y }
    if above && y < 0.0 && anchor.y + anchor.height - ov.offset.y + size.height <= window_size.height { y = anchor.y + anchor.height - ov.offset.y }
    if p == .Right && x + size.width > window_size.width && anchor.x - size.width - ov.offset.x >= 0.0 { x = anchor.x - size.width - ov.offset.x }
    if p == .Left && x < 0.0 && anchor.x + anchor.width - ov.offset.x + size.width <= window_size.width { x = anchor.x + anchor.width - ov.offset.x }
    if p == .At && x + size.width > window_size.width && ov.offset.x - size.width >= 0.0 { x = ov.offset.x - size.width }
    if p == .At && y + size.height > window_size.height && ov.offset.y - size.height >= 0.0 { y = ov.offset.y - size.height }
    if x + size.width > window_size.width { x = window_size.width - size.width }
    if y + size.height > window_size.height { y = window_size.height - size.height }
    if x < 0.0 { x = 0.0 }
    if y < 0.0 { y = 0.0 }
    ret geometry.Rect { x: x, y: y, width: size.width, height: size.height }
}

// The overlays placed after the tree, in order, each against its anchor's bounds
// (the window when it names none), its children stacked in the content rect.
fn place_overlays(s: *State, a: *mem.Arena, b: *scene.Builder) -> err {
    var i = 0usize
    while i < s.overlay_count {
        let element = usize(s.overlays[i])
        let node = s.overlay_nodes[i]
        var spec: Overlay = zero
        switch node.kind {
        case .Overlay as ov:
            spec = ov
        default:
            spec = spec
        }
        var anchor = geometry.Rect { x: 0.0, y: 0.0, width: s.window_size.width, height: s.window_size.height }
        if spec.anchor != 0u64 {
            let (found, count) = find_by_key(s, spec.anchor)
            if count != 0usize { anchor = s.elements[usize(found.slot)].bounds }
        }
        var open = ui_layout.Constraints { min_width: 0.0, max_width: s.window_size.width, min_height: 0.0, max_height: s.window_size.height }
        if spec.placement == .BelowMatch || spec.placement == .AboveMatch {
            var width = anchor.width
            let (minimum, has_minimum) = style.px_of(node.style.min_width)
            let (maximum, has_maximum) = style.px_of(node.style.max_width)
            if has_minimum && width < minimum { width = minimum }
            if has_maximum && width > maximum { width = maximum }
            if width > s.window_size.width { width = s.window_size.width }
            open.min_width = width
            open.max_width = width
        }
        let (size, size_error) = measure_stack(s, a, node, open)
        if size_error != ok { ret size_error }
        let rect = overlay_rect(anchor, size, spec, s.window_size)
        s.elements[element].overlay_bounds = rect
        s.elements[element].bounds = rect
        try place_stack(s, a, node, element, rect, open, b, 2usize)
        i += 1usize
    }
    ret ok
}

// The topmost overlay under `p`, or the topmost modal one that keeps `p` from
// what is under it: (element, inside, found).
// The topmost live modal overlay, if any.
fn topmost_modal(s: *State) -> (usize, bool) {
    var i = s.overlay_count
    while i > 0usize {
        i -= 1usize
        let element = usize(s.overlays[i])
        if s.elements[element].live && s.elements[element].modal { ret (element, true) }
    }
    ret (0usize, false)
}

// Whether `top` is an ancestor of `index`.
fn descends_from(s: *State, index: usize, top: usize) -> bool {
    var at = index
    while s.elements[at].has_parent {
        at = usize(s.elements[at].parent)
        if at == top { ret true }
    }
    ret false
}

// The first live scope in the subtree of `top`, if any.
fn scope_under(s: *State, top: usize) -> (usize, bool) {
    var i = 0usize
    while i < s.elements.len {
        if s.elements[i].live && s.elements[i].kind == SCOPE_TAG && descends_from(s, i, top) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn overlay_at(s: *State, p: geometry.Point) -> (usize, bool, bool) {
    var i = s.overlay_count
    while i > 0usize {
        i -= 1usize
        let element = usize(s.overlays[i])
        let e = &s.elements[element]
        if e.live && geometry.contains(e.overlay_bounds, p) { ret (element, true, true) }
        if e.live && e.modal { ret (element, false, true) }
    }
    ret (0usize, false, false)
}

fn rounded(r: geometry.Rect, radius: f32) -> geometry.RRect {
    var c = radius
    if c > r.width * 0.5 { c = r.width * 0.5 }
    if c > r.height * 0.5 { c = r.height * 0.5 }
    let corner = geometry.Radius { x: c, y: c }
    ret geometry.RRect { rect: r, top_left: corner, top_right: corner, bottom_right: corner, bottom_left: corner }
}

// A rectangle with rounded corners as a closed path of lines and quadratic corners.
fn trace_rounded(builder: *geometry.PathBuilder, r: geometry.Rect, c: f32) -> err {
    let x0 = r.x
    let y0 = r.y
    let x1 = r.x + r.width
    let y1 = r.y + r.height
    try geometry.move_to(builder, geometry.Point { x: x0 + c, y: y0 })
    try geometry.line_to(builder, geometry.Point { x: x1 - c, y: y0 })
    if c > 0.0 { try geometry.quad_to(builder, geometry.Point { x: x1, y: y0 }, geometry.Point { x: x1, y: y0 + c }) }
    try geometry.line_to(builder, geometry.Point { x: x1, y: y1 - c })
    if c > 0.0 { try geometry.quad_to(builder, geometry.Point { x: x1, y: y1 }, geometry.Point { x: x1 - c, y: y1 }) }
    try geometry.line_to(builder, geometry.Point { x: x0 + c, y: y1 })
    if c > 0.0 { try geometry.quad_to(builder, geometry.Point { x: x0, y: y1 }, geometry.Point { x: x0, y: y1 - c }) }
    try geometry.line_to(builder, geometry.Point { x: x0, y: y0 + c })
    if c > 0.0 { try geometry.quad_to(builder, geometry.Point { x: x0, y: y0 }, geometry.Point { x: x0 + c, y: y0 }) }
    ret geometry.close_path(builder)
}

fn rounded_path(a: *mem.Arena, r: geometry.Rect, radius: f32) -> (geometry.Path, err) {
    let rr = rounded(r, radius)
    let (pb, pb_error) = geometry.path_builder(a, 10usize, 16usize)
    if pb_error != ok { ret (zero, TooLarge) }
    var builder = pb
    let traced = trace_rounded(&builder, r, rr.top_left.x)
    if traced != ok { ret (zero, TooLarge) }
    ret (geometry.finish(&builder), ok)
}

// A style's corner radii: its own when it names any, else `radius` at every corner.
fn corners_of(st: *const style.Style) -> style.Corners {
    let c = st.corners
    if c.top_left > 0.0 || c.top_right > 0.0 || c.bottom_right > 0.0 || c.bottom_left > 0.0 { ret c }
    ret style.Corners { top_left: st.radius, top_right: st.radius, bottom_right: st.radius, bottom_left: st.radius }
}

// A rectangle's shape with each rounded corner grown by `grow` (a square corner
// stays square), each clamped to half the rectangle's sides.
fn shape_of(r: geometry.Rect, c: style.Corners, grow: f32) -> geometry.RRect {
    let limit = min_f(r.width, r.height) * 0.5
    ret geometry.RRect { rect: r, top_left: corner_at(c.top_left, grow, limit), top_right: corner_at(c.top_right, grow, limit), bottom_right: corner_at(c.bottom_right, grow, limit), bottom_left: corner_at(c.bottom_left, grow, limit) }
}

fn corner_at(radius: f32, grow: f32, limit: f32) -> geometry.Radius {
    var v: f32 = 0.0
    if radius > 0.0 { v = min_f(max_f(radius + grow, 0.0), max_f(limit, 0.0)) }
    ret geometry.Radius { x: v, y: v }
}

// A shape as a closed path: lines and a quadratic per rounded corner.
fn shape_path(a: *mem.Arena, rr: geometry.RRect) -> (geometry.Path, err) {
    let (pb, pb_error) = geometry.path_builder(a, 10usize, 16usize)
    if pb_error != ok { ret (zero, TooLarge) }
    var builder = pb
    let r = rr.rect
    let x0 = r.x
    let y0 = r.y
    let x1 = r.x + r.width
    let y1 = r.y + r.height
    let tl = rr.top_left.x
    let tr = rr.top_right.x
    let br = rr.bottom_right.x
    let bl = rr.bottom_left.x
    if geometry.move_to(&builder, geometry.Point { x: x0 + tl, y: y0 }) != ok { ret (zero, TooLarge) }
    if geometry.line_to(&builder, geometry.Point { x: x1 - tr, y: y0 }) != ok { ret (zero, TooLarge) }
    if tr > 0.0 && geometry.quad_to(&builder, geometry.Point { x: x1, y: y0 }, geometry.Point { x: x1, y: y0 + tr }) != ok { ret (zero, TooLarge) }
    if geometry.line_to(&builder, geometry.Point { x: x1, y: y1 - br }) != ok { ret (zero, TooLarge) }
    if br > 0.0 && geometry.quad_to(&builder, geometry.Point { x: x1, y: y1 }, geometry.Point { x: x1 - br, y: y1 }) != ok { ret (zero, TooLarge) }
    if geometry.line_to(&builder, geometry.Point { x: x0 + bl, y: y1 }) != ok { ret (zero, TooLarge) }
    if bl > 0.0 && geometry.quad_to(&builder, geometry.Point { x: x0, y: y1 }, geometry.Point { x: x0, y: y1 - bl }) != ok { ret (zero, TooLarge) }
    if geometry.line_to(&builder, geometry.Point { x: x0, y: y0 + tl }) != ok { ret (zero, TooLarge) }
    if tl > 0.0 && geometry.quad_to(&builder, geometry.Point { x: x0, y: y0 }, geometry.Point { x: x0 + tl, y: y0 }) != ok { ret (zero, TooLarge) }
    if geometry.close_path(&builder) != ok { ret (zero, TooLarge) }
    ret (geometry.finish(&builder), ok)
}

// A rectangle filled on its shape: a plain rectangle when no corner is rounded.
fn fill_corners(a: *mem.Arena, b: *scene.Builder, r: geometry.Rect, c: style.Corners, brush: paint.Brush) -> err {
    if !(c.top_left > 0.0) && !(c.top_right > 0.0) && !(c.bottom_right > 0.0) && !(c.bottom_left > 0.0) { ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: r, brush: brush } }) }
    let (outline, outline_error) = shape_path(a, shape_of(r, c, 0.0))
    if outline_error != ok { ret TooLarge }
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: outline, brush: brush } })
}

// A rectangle filled, rounded when it has a radius.
fn fill_shape(a: *mem.Arena, b: *scene.Builder, r: geometry.Rect, radius: f32, brush: paint.Brush) -> err {
    if radius <= 0.0 { ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: r, brush: brush } }) }
    let (outline, outline_error) = rounded_path(a, r, radius)
    if outline_error != ok { ret TooLarge }
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: outline, brush: brush } })
}

// The Restores that close what `place` opened.
// Whether the element shows the focus ring: focused by the keyboard or the program,
// focusable, not an editor (a field shows its focus by its own outline), and a
// ring to draw.
fn ringed(s: *const State, element: usize) -> bool {
    if !s.has_focus || !s.focus_visible || usize(s.focus) != element || !(s.ring_width > 0.0) { ret false }
    let e = &s.elements[element]
    ret e.focusable && (e.kind != EDIT_TAG || e.ringed)
}

// Whether the element carries the press ripple (D983): pressed, with a colour
// and a phase to draw.
fn rippled(s: *const State, element: usize) -> bool {
    ret s.arena_state.pressed && usize(s.arena_state.candidate) == element && s.ripple_phase > 0.0 && s.ripple_color.alpha > 0.0
}

// The ripple (D983): a disc from the press point, clipped to the element.
fn place_ripple(s: *State, a: *mem.Arena, b: *scene.Builder, bounds: geometry.Rect, corner: style.Corners) -> err {
    let p = s.arena_state.down
    let dx = max_f(p.x - bounds.x, bounds.x + bounds.width - p.x)
    let dy = max_f(p.y - bounds.y, bounds.y + bounds.height - p.y)
    let reach = math.sqrt[f32](dx * dx + dy * dy) * s.ripple_phase
    if !(reach > 0.0) { ret ok }
    var save: scene.Command = .Save
    var restore: scene.Command = .Restore
    try scene.push(b, save)
    if corner.top_left > 0.0 || corner.top_right > 0.0 || corner.bottom_right > 0.0 || corner.bottom_left > 0.0 {
        try scene.push(b, scene.Command { Clip: scene.Clip { Rounded: shape_of(bounds, corner, 0.0) } })
    } else {
        try scene.push(b, scene.Command { Clip: scene.Clip { Rect: bounds } })
    }
    let (disc, disc_error) = rounded_path(a, geometry.Rect { x: p.x - reach, y: p.y - reach, width: 2.0 * reach, height: 2.0 * reach }, reach)
    if disc_error != ok { ret TooLarge }
    try scene.push(b, scene.Command { FillPath: scene.FillPath { path: disc, brush: paint.Brush { Solid: s.ripple_color } } })
    ret scene.push(b, restore)
}

fn intersect(a: geometry.Rect, b: geometry.Rect) -> geometry.Rect {
    let x0 = max_f(a.x, b.x)
    let y0 = max_f(a.y, b.y)
    let x1 = min_f(a.x + a.width, b.x + b.width)
    let y1 = min_f(a.y + a.height, b.y + b.height)
    ret geometry.Rect { x: x0, y: y0, width: max_f(x1 - x0, 0.0), height: max_f(y1 - y0, 0.0) }
}

// The ring: a stroke `ring_width` wide whose outer edge is `ring_offset + ring_width`
// outside the bounds, on the element's shape grown by the same. Menu rows put its
// outer edge 3px inside their edge-to-edge bounds; otherwise a clip that would cut
// the outside ring moves it just inside the bounds.
fn place_ring(s: *State, a: *mem.Arena, b: *scene.Builder, element: usize, bounds: geometry.Rect, corner: style.Corners) -> err {
    let w = s.ring_width
    var grow = s.ring_offset + w * 0.5
    let reach = s.ring_offset + w
    let outer = geometry.Rect { x: bounds.x - reach, y: bounds.y - reach, width: bounds.width + 2.0 * reach, height: bounds.height + 2.0 * reach }
    let (_, menu_item) = menu_item_owner(s, element)
    if menu_item {
        grow = 0.0 - 3.0 - w * 0.5
    } else if s.has_clip {
        let c = s.clip_rect
        if outer.x < c.x || outer.y < c.y || outer.x + outer.width > c.x + c.width || outer.y + outer.height > c.y + c.height { grow = 0.0 - w * 0.5 }
    }
    let r = geometry.Rect { x: bounds.x - grow, y: bounds.y - grow, width: max_f(bounds.width + 2.0 * grow, 0.0), height: max_f(bounds.height + 2.0 * grow, 0.0) }
    let (outline, outline_error) = shape_path(a, shape_of(r, corner, grow))
    if outline_error != ok { ret TooLarge }
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: outline, brush: paint.Brush { Solid: s.ring_color }, stroke: paint.Stroke { width: w, cap: .Butt, join: .Miter, miter_limit: 4.0 } } })
}

fn finish_place(b: *scene.Builder, clipped: bool, layered: bool) -> err {
    var restore: scene.Command = .Restore
    if clipped { try scene.push(b, restore) }
    if layered { try scene.push(b, restore) }
    ret ok
}

// The i-th child's element: the linked list walked from the element's first.
fn child_element(s: *State, element: usize, i: usize) -> usize {
    var at = s.elements[element].first_child
    var k = 0usize
    while k < i {
        at = s.elements[usize(at)].next_sibling
        k += 1usize
    }
    ret usize(at)
}

fn place_flex(s: *State, a: *mem.Arena, node: *const Node, element: usize, spec: ui_layout.Flex, inner: geometry.Rect, limits: ui_layout.Constraints, b: *scene.Builder, depth: usize) -> err {
    if node.children.len == 0usize { ret ok }
    let (children, children_error) = children_of(s, a, node, limits, spec.axis == .Horizontal)
    if children_error != ok { ret children_error }
    // The box's size is settled by now: the children are aligned within all of it.
    let tight = ui_layout.Constraints { min_width: inner.width, max_width: inner.width, min_height: inner.height, max_height: inner.height }
    let (result, layout_error) = ui_layout.flex(a, spec, tight, children)
    if layout_error != ok { ret InvalidTree }
    var i = 0usize
    while i < node.children.len {
        let r = result.children[i]
        try place(s, a, &node.children[i], child_element(s, element, i), geometry.Rect { x: inner.x + r.x, y: inner.y + r.y, width: r.width, height: r.height }, b, depth + 1usize)
        i += 1usize
    }
    ret ok
}

// Where a slider value sits along its track, 0..1.
fn slider_share(e: *const Element, value: f32) -> f32 {
    let span = e.slider_high - e.slider_low
    if !(span > 0.0) { ret 0.0 }
    var t = (value - e.slider_low) / span
    if t < 0.0 { t = 0.0 }
    if t > 1.0 { t = 1.0 }
    ret t
}

// The track along the middle of the box, filled between the low end (or the first
// thumb of a range) and the value, a handle at each value.
// v2 (D956, docs/ux/components/Slider): the track is 4 thick, `fill` up to the value
// (between the values of a range) and `track` beyond, each part stopping 6 short of
// a handle; a handle is a 4-wide bar in `thumb` across the track, as long as the box
// is deep, 44 at most. The ends stay 8 in (half of D820's thumb), where
// `slider_at` measures from.
fn place_slider(s: *State, a: *mem.Arena, element: usize, sl: Slider, inner: geometry.Rect, b: *scene.Builder) -> err {
    let e = &s.elements[element]
    var inset = inner.height
    var along = inner.width
    if sl.vertical {
        inset = inner.width
        along = inner.height
    }
    if inset > 16.0 { inset = 16.0 }
    let start = inset * 0.5
    let length = max_f(along - inset, 0.0)
    let first = slider_share(e, e.slider_value) * length
    let clear: f32 = 8.0
    var width = sl.handle
    if !(width > 0.0) { width = 4.0 }
    var near_end: f32 = 0.0
    var far_end = first
    if sl.range {
        let other = slider_share(e, e.slider_second) * length
        near_end = min_f(first, other)
        far_end = max_f(first, other)
        try slider_run(a, b, sl.vertical, inner, start, 0.0, near_end - clear, sl.track)
        try slider_run(a, b, sl.vertical, inner, start, near_end + clear, far_end - clear, sl.fill)
    } else {
        try slider_run(a, b, sl.vertical, inner, start, 0.0, first - clear, sl.fill)
    }
    try slider_run(a, b, sl.vertical, inner, start, far_end + clear, length, sl.track)
    // The ticks: a 4 dot at each step, none within the clearance of a handle, and
    // none when the steps would stand closer than 16 apart.
    if sl.step > 0.0 && (sl.tick_on.alpha > 0.0 || sl.tick_off.alpha > 0.0) && sl.high > sl.low {
        let count = (sl.high - sl.low) / sl.step
        if count >= 1.0 && length / count >= 16.0 {
            var k = 0usize
            while f32(k) <= count + 0.001 {
                let spot = length * f32(k) / count
                let off_first = spot < far_end - clear || spot > far_end + clear
                let off_second = !sl.range || spot < near_end - clear || spot > near_end + clear
                if off_first && off_second {
                    var color = sl.tick_off
                    if spot >= near_end && spot <= far_end { color = sl.tick_on }
                    try slider_run(a, b, sl.vertical, inner, start, spot - 2.0, spot + 2.0, color)
                }
                k += 1usize
            }
        }
    }
    if sl.range { try slider_handle(a, b, sl.vertical, inner, start, near_end, width, sl.halo, sl.thumb) }
    ret slider_handle(a, b, sl.vertical, inner, start, far_end, width, sl.halo, sl.thumb)
}

// A part of the track from `from` to `to` along it (from the bottom when vertical).
fn slider_run(a: *mem.Arena, b: *scene.Builder, vertical: bool, inner: geometry.Rect, start: f32, from: f32, to: f32, color: paint.Color) -> err {
    if !(to > from) { ret ok }
    let thickness: f32 = 4.0
    var r = geometry.Rect { x: inner.x + start + from, y: inner.y + inner.height * 0.5 - thickness * 0.5, width: to - from, height: thickness }
    if vertical { r = geometry.Rect { x: inner.x + inner.width * 0.5 - thickness * 0.5, y: inner.y + inner.height - start - to, width: thickness, height: to - from } }
    ret fill_shape(a, b, r, thickness * 0.5, paint.Brush { Solid: color })
}

// A handle `width` across and the box's depth long (44 at most), with its halo 6
// out on each side when there is one.
fn slider_handle(a: *mem.Arena, b: *scene.Builder, vertical: bool, inner: geometry.Rect, start: f32, spot: f32, width: f32, halo: paint.Color, color: paint.Color) -> err {
    var depth = inner.height
    if vertical { depth = inner.width }
    if depth > 44.0 { depth = 44.0 }
    var r = geometry.Rect { x: inner.x + start + spot - width * 0.5, y: inner.y + inner.height * 0.5 - depth * 0.5, width: width, height: depth }
    if vertical { r = geometry.Rect { x: inner.x + inner.width * 0.5 - depth * 0.5, y: inner.y + inner.height - start - spot - width * 0.5, width: depth, height: width } }
    if halo.alpha > 0.0 {
        let glow = geometry.Rect { x: r.x - 6.0, y: r.y - 6.0, width: r.width + 12.0, height: r.height + 12.0 }
        try fill_shape(a, b, glow, (width + 12.0) * 0.5, paint.Brush { Solid: halo })
    }
    ret fill_shape(a, b, r, width * 0.5, paint.Brush { Solid: color })
}

// A value snapped to the step and kept in the range, set on the thumb held and
// reported when it changed.
fn slider_set(s: *State, element: usize, raw: f32, second: bool) -> err {
    let e = &s.elements[element]
    var value = raw
    if e.slider_step > 0.0 {
        let steps = (value - e.slider_low) / e.slider_step
        var nearest = steps + 0.5
        if nearest < 0.0 { nearest = nearest - 1.0 }
        value = e.slider_low + f32(i64(nearest)) * e.slider_step
    }
    if value < e.slider_low { value = e.slider_low }
    if value > e.slider_high { value = e.slider_high }
    if second {
        if value == e.slider_second { ret ok }
        e.slider_second = value
        e.invalid = true
        ret fire_change[f32](e.slider_change_second, value)
    }
    if value == e.slider_value { ret ok }
    e.slider_value = value
    e.invalid = true
    ret fire_change[f32](e.slider_change, value)
}

// The value under a point on the slider's track.
fn slider_at(e: *const Element, p: geometry.Point) -> f32 {
    var thumb = e.bounds.height
    if e.slider_vertical { thumb = e.bounds.width }
    if thumb > 16.0 { thumb = 16.0 }
    var t: f32 = 0.0
    if e.slider_vertical {
        let length = max_f(e.bounds.height - thumb, 1.0)
        t = 1.0 - (p.y - e.bounds.y - thumb * 0.5) / length
    } else {
        let length = max_f(e.bounds.width - thumb, 1.0)
        t = (p.x - e.bounds.x - thumb * 0.5) / length
    }
    if t < 0.0 { t = 0.0 }
    if t > 1.0 { t = 1.0 }
    ret e.slider_low + t * (e.slider_high - e.slider_low)
}

// A press on a slider: the nearer thumb of a range is taken, and the value set.
fn slider_press(s: *State, element: usize, p: geometry.Point) -> err {
    let e = &s.elements[element]
    let value = slider_at(e, p)
    var second = false
    if e.slider_range {
        var d1 = value - e.slider_value
        if d1 < 0.0 { d1 = 0.0 - d1 }
        var d2 = value - e.slider_second
        if d2 < 0.0 { d2 = 0.0 - d2 }
        second = d2 < d1
    }
    e.second_held = second
    ret slider_set(s, element, value, second)
}

// The arrow keys, Home and End on a focused slider move its first thumb.
fn slider_key(s: *State, element: usize, code: u32) -> (bool, err) {
    let e = &s.elements[element]
    if !e.enabled { ret (false, ok) }
    var step = e.slider_step
    if !(step > 0.0) { step = (e.slider_high - e.slider_low) / 100.0 }
    if code == 37u32 || code == 40u32 {
        let moved = slider_set(s, element, e.slider_value - step, false)
        ret (true, moved)
    }
    if code == 39u32 || code == 38u32 {
        let moved = slider_set(s, element, e.slider_value + step, false)
        ret (true, moved)
    }
    if code == 36u32 {
        let moved = slider_set(s, element, e.slider_low, false)
        ret (true, moved)
    }
    if code == 35u32 {
        let moved = slider_set(s, element, e.slider_high, false)
        ret (true, moved)
    }
    ret (false, ok)
}

// The thumb of the viewport the scrollbar names, in the border colour, over the
// track the background painted; nothing when the content fits.
fn place_scrollbar(s: *State, bar: Scrollbar, inner: geometry.Rect, b: *scene.Builder, color: paint.Color) -> err {
    let (found, count) = find_by_key(s, bar.viewport)
    if count == 0usize { ret ok }
    let v = &s.elements[usize(found.slot)]
    if v.kind != SCROLL_TAG || v.content_extent <= v.viewport_extent || v.content_extent <= 0.0 { ret ok }
    let vertical = bar.axis == .Vertical
    var track = inner.height
    if !vertical { track = inner.width }
    var length = track * v.viewport_extent / v.content_extent
    if length < 8.0 { length = 8.0 }
    var at = v.scroll_offset / v.content_extent * track
    if at > track - length { at = track - length }
    if at < 0.0 { at = 0.0 }
    var thumb = geometry.Rect { x: inner.x, y: inner.y + at, width: inner.width, height: length }
    if !vertical { thumb = geometry.Rect { x: inner.x + at, y: inner.y, width: length, height: inner.height } }
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: thumb, brush: paint.Brush { Solid: color } } })
}

// The content at its natural size, painted scaled down about the box's origin to
// fit it; the scale is never more than one.
fn place_fitted(s: *State, a: *mem.Arena, node: *const Node, element: usize, inner: geometry.Rect, b: *scene.Builder, depth: usize) -> err {
    if node.children.len == 0usize { ret ok }
    let open = ui_layout.Constraints { min_width: 0.0, max_width: 3.0e38, min_height: 0.0, max_height: 3.0e38 }
    let (natural, natural_error) = measure_flex(s, a, node, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, open)
    if natural_error != ok { ret natural_error }
    var scale: f32 = 1.0
    if natural.width > 0.0 && inner.width / natural.width < scale { scale = inner.width / natural.width }
    if natural.height > 0.0 && inner.height / natural.height < scale { scale = inner.height / natural.height }
    var save: scene.Command = .Save
    var restore: scene.Command = .Restore
    try scene.push(b, save)
    let about = geometry.transform_multiply(geometry.transform_translate(inner.x, inner.y), geometry.transform_multiply(geometry.transform_scale(scale, scale), geometry.transform_translate(0.0 - inner.x, 0.0 - inner.y)))
    try scene.push(b, scene.Command { Transform: about })
    try place_flex(s, a, node, element, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, geometry.Rect { x: inner.x, y: inner.y, width: natural.width, height: natural.height }, open, b, depth)
    try scene.push(b, restore)
    ret ok
}

// The zoom view's offset kept within its bounds: the content may not leave the
// view on either side (it sits at the origin while smaller than the view).
fn zoom_clamp(e: *Element, inner: geometry.Rect) {
    if e.zoom_scale < e.zoom_min { e.zoom_scale = e.zoom_min }
    if e.zoom_scale > e.zoom_max { e.zoom_scale = e.zoom_max }
    let shown_width = e.natural.width * e.zoom_scale
    let shown_height = e.natural.height * e.zoom_scale
    var low_x = inner.width - shown_width
    if low_x > 0.0 { low_x = 0.0 }
    var low_y = inner.height - shown_height
    if low_y > 0.0 { low_y = 0.0 }
    if e.zoom_offset.x < low_x { e.zoom_offset.x = low_x }
    if e.zoom_offset.y < low_y { e.zoom_offset.y = low_y }
    if e.zoom_offset.x > 0.0 { e.zoom_offset.x = 0.0 }
    if e.zoom_offset.y > 0.0 { e.zoom_offset.y = 0.0 }
}

fn place_zoom(s: *State, a: *mem.Arena, node: *const Node, element: usize, inner: geometry.Rect, b: *scene.Builder, depth: usize) -> err {
    if node.children.len == 0usize { ret ok }
    let open = ui_layout.Constraints { min_width: 0.0, max_width: 3.0e38, min_height: 0.0, max_height: 3.0e38 }
    let (natural, natural_error) = measure_flex(s, a, node, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, open)
    if natural_error != ok { ret natural_error }
    let e = &s.elements[element]
    e.natural = natural
    zoom_clamp(e, inner)
    let scale = e.zoom_scale
    var save: scene.Command = .Save
    var restore: scene.Command = .Restore
    try scene.push(b, save)
    try scene.push(b, scene.Command { Clip: scene.Clip { Rect: inner } })
    let about = geometry.transform_multiply(geometry.transform_translate(inner.x + e.zoom_offset.x, inner.y + e.zoom_offset.y), geometry.transform_multiply(geometry.transform_scale(scale, scale), geometry.transform_translate(0.0 - inner.x, 0.0 - inner.y)))
    try scene.push(b, scene.Command { Transform: about })
    try place_flex(s, a, node, element, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, geometry.Rect { x: inner.x, y: inner.y, width: natural.width, height: natural.height }, open, b, depth)
    try scene.push(b, restore)
    ret ok
}

// The deepest zoom view under `p`, if any.
fn hit_zoom(s: *State, index: usize, p: geometry.Point) -> (usize, bool) {
    let e = &s.elements[index]
    if !e.live || !geometry.contains(e.bounds, p) { ret (0usize, false) }
    var order: [64]u32 = zero
    var count = 0usize
    var at = e.first_child
    var has = e.has_child
    while has && count < 64usize {
        order[count] = at
        count += 1usize
        let child = &s.elements[usize(at)]
        has = child.has_sibling
        at = child.next_sibling
    }
    while count > 0usize {
        count = count - 1usize
        let (found, has_found) = hit_zoom(s, usize(order[count]), p)
        if has_found { ret (found, true) }
    }
    if e.kind == ZOOM_TAG { ret (index, true) }
    ret (0usize, false)
}

// The zoom view scaled by `factor` about `p` (kept where it is under the pointer),
// then bounded and reported.
fn zoom_by(s: *State, element: usize, factor: f32, p: geometry.Point) -> err {
    let e = &s.elements[element]
    var next = e.zoom_scale * factor
    if next < e.zoom_min { next = e.zoom_min }
    if next > e.zoom_max { next = e.zoom_max }
    let ratio = next / e.zoom_scale
    let px = p.x - e.bounds.x
    let py = p.y - e.bounds.y
    e.zoom_offset = geometry.Point { x: px - (px - e.zoom_offset.x) * ratio, y: py - (py - e.zoom_offset.y) * ratio }
    e.zoom_scale = next
    zoom_clamp(e, e.bounds)
    e.invalid = true
    ret fire_change[ZoomState](e.zoom_change, ZoomState { scale: e.zoom_scale, offset: e.zoom_offset })
}

// The zoom view panned by `delta`, bounded and reported.
fn pan_by(s: *State, element: usize, delta: geometry.Point) -> err {
    let e = &s.elements[element]
    e.zoom_offset = geometry.Point { x: e.zoom_offset.x + delta.x, y: e.zoom_offset.y + delta.y }
    zoom_clamp(e, e.bounds)
    e.invalid = true
    ret fire_change[ZoomState](e.zoom_change, ZoomState { scale: e.zoom_scale, offset: e.zoom_offset })
}

fn place_wrap(s: *State, a: *mem.Arena, node: *const Node, element: usize, spec: ui_layout.Wrap, inner: geometry.Rect, limits: ui_layout.Constraints, b: *scene.Builder, depth: usize) -> err {
    if node.children.len == 0usize { ret ok }
    let (children, children_error) = children_of(s, a, node, limits, spec.axis == .Horizontal)
    if children_error != ok { ret children_error }
    let (result, layout_error) = ui_layout.wrap(a, spec, limits, children)
    if layout_error != ok { ret InvalidTree }
    var i = 0usize
    while i < node.children.len {
        let r = result.children[i]
        try place(s, a, &node.children[i], child_element(s, element, i), geometry.Rect { x: inner.x + r.x, y: inner.y + r.y, width: r.width, height: r.height }, b, depth + 1usize)
        i += 1usize
    }
    ret ok
}

fn place_grid(s: *State, a: *mem.Arena, node: *const Node, element: usize, spec: ui_layout.Grid, inner: geometry.Rect, limits: ui_layout.Constraints, b: *scene.Builder, depth: usize) -> err {
    if node.children.len == 0usize { ret ok }
    let (children, children_error) = children_of(s, a, node, limits, false)
    if children_error != ok { ret children_error }
    let (result, layout_error) = ui_layout.grid(a, spec, limits, children)
    if layout_error != ok { ret InvalidTree }
    var i = 0usize
    while i < node.children.len {
        let r = result.children[i]
        try place(s, a, &node.children[i], child_element(s, element, i), geometry.Rect { x: inner.x + r.x, y: inner.y + r.y, width: r.width, height: r.height }, b, depth + 1usize)
        i += 1usize
    }
    ret ok
}

fn place_stack(s: *State, a: *mem.Arena, node: *const Node, element: usize, inner: geometry.Rect, limits: ui_layout.Constraints, b: *scene.Builder, depth: usize) -> err {
    var i = 0usize
    while i < node.children.len {
        let (size, size_error) = measure(s, a, &node.children[i], limits)
        if size_error != ok { ret size_error }
        try place(s, a, &node.children[i], child_element(s, element, i), geometry.Rect { x: inner.x, y: inner.y, width: size.width, height: size.height }, b, depth + 1usize)
        i += 1usize
    }
    ret ok
}

fn reconcile(widget_runtime: *Runtime, frame_arena: *mem.Arena, root: Node, constraints: ui_layout.Constraints) -> (scene.SceneId, err) {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret (zero, state_error) }
    let hover_error = menu_hover_tick(s)
    if hover_error != ok { ret (zero, hover_error) }
    s.frame += 1u64
    // The whole tree is unvisited, then the root matched against the previous root.
    var old_roots: [1]u32 = zero
    var old_root_count = 0usize
    if s.has_root {
        s.elements[usize(s.root)].visited = false
        old_roots[0] = s.root
        old_root_count = 1usize
    }
    let old_root = s.root
    let old_has = s.has_root
    s.measure_stamp += 1u32
    if s.measure_stamp == 0u32 { s.measure_stamp = 1u32 }
    let (root_index, reconcile_error) = reconcile_node(s, &root, 0usize, false, 0usize, old_roots[0usize..old_root_count], 1usize)
    if reconcile_error != ok { ret (zero, reconcile_error) }
    if old_has && usize(old_root) != root_index { retire_element(s, usize(old_root)) }
    s.root = u32(root_index)
    s.has_root = true
    s.elements[root_index].has_sibling = false
    // Layout and paint into a fresh list, compiled into the renderer.
    let (size, size_error) = measure(s, frame_arena, &root, constraints)
    if size_error != ok { ret (zero, size_error) }
    let (b, builder_error) = scene.builder(frame_arena, s.limits.max_commands)
    if builder_error != ok { ret (zero, TooLarge) }
    var builder = b
    s.overlay_count = 0usize
    s.window_size = size
    var place_error = place(s, frame_arena, &root, root_index, geometry.Rect { x: 0.0, y: 0.0, width: size.width, height: size.height }, &builder, 1usize)
    if place_error == ok { place_error = place_overlays(s, frame_arena, &builder) }
    if place_error == scene.TooLarge { ret (zero, TooLarge) }
    if place_error != ok { ret (zero, place_error) }
    var o = 0usize
    while o < s.overlay_count {
        let overlay_element = usize(s.overlays[o])
        if s.elements[overlay_element].wants_focus {
            s.elements[overlay_element].wants_focus = false
            let order = s.focus_order
            let count = collect_focusable(s, overlay_element, order, 0usize)
            if count > 0usize {
                s.focus = order[0usize]
                s.has_focus = true
            }
        }
        o += 1usize
    }
    if s.has_requested_focus_key {
        let (wanted, count) = find_by_key(s, s.requested_focus_key)
        if count == 1usize {
            s.focus = wanted.slot
            s.has_focus = true
            s.focus_visible = true
        }
        s.has_requested_focus_key = false
    }
    let (compiled, compile_error) = scene.compile(s.renderer, scene.finish(&builder))
    if compile_error != ok { ret (zero, TooLarge) }
    // The previous frame's scene goes with the new one committed.
    if s.has_scene {
        let released = scene.release_scene(s.renderer, s.scene_id)
    }
    s.scene_id = compiled
    s.has_scene = true
    s.replay_scene = compiled
    s.has_replay_scene = true
    ret (compiled, ok)
}

// -------------------------------------------------------------------- dispatch

// The deepest element under `p` with an action, front to back.
fn hit_action(s: *State, index: usize, p: geometry.Point) -> (usize, bool) {
    let e = &s.elements[index]
    if !e.live || !geometry.contains(e.bounds, p) { ret (0usize, false) }
    // Children after their siblings are in front; the last is tried first.
    var order: [64]u32 = zero
    var count = 0usize
    var at = e.first_child
    var has = e.has_child
    while has && count < 64usize {
        order[count] = at
        count += 1usize
        let child = &s.elements[usize(at)]
        has = child.has_sibling
        at = child.next_sibling
    }
    while count > 0usize {
        count = count - 1usize
        let (found, has_found) = hit_action(s, usize(order[count]), p)
        if has_found { ret (found, true) }
    }
    if e.has_action && e.enabled { ret (index, true) }
    ret (0usize, false)
}

// The deepest scroll element under `p`.
fn hit_scroll(s: *State, index: usize, p: geometry.Point) -> (usize, bool) {
    let e = &s.elements[index]
    if !e.live || !geometry.contains(e.bounds, p) { ret (0usize, false) }
    var order: [64]u32 = zero
    var count = 0usize
    var at = e.first_child
    var has = e.has_child
    while has && count < 64usize {
        order[count] = at
        count += 1usize
        let child = &s.elements[usize(at)]
        has = child.has_sibling
        at = child.next_sibling
    }
    while count > 0usize {
        count = count - 1usize
        let (found, has_found) = hit_scroll(s, usize(order[count]), p)
        if has_found { ret (found, true) }
    }
    if e.kind == SCROLL_TAG { ret (index, true) }
    ret (0usize, false)
}

// The deepest region under `p` whose mask has one of `wanted`, front to back.
fn hit_region(s: *State, index: usize, p: geometry.Point, wanted: u8) -> (usize, bool) {
    let e = &s.elements[index]
    if !e.live || !geometry.contains(e.bounds, p) { ret (0usize, false) }
    var order: [64]u32 = zero
    var count = 0usize
    var at = e.first_child
    var has = e.has_child
    while has && count < 64usize {
        order[count] = at
        count += 1usize
        let child = &s.elements[usize(at)]
        has = child.has_sibling
        at = child.next_sibling
    }
    while count > 0usize {
        count = count - 1usize
        let (found, has_found) = hit_region(s, usize(order[count]), p, wanted)
        if has_found { ret (found, true) }
    }
    if (e.kind == REGION_TAG || e.kind == EDIT_TAG || e.kind == SCROLLBAR_TAG || e.kind == SLIDER_TAG) && e.enabled && (e.gestures & wanted) != 0u8 { ret (index, true) }
    ret (0usize, false)
}

// The slop a press may wander before it is a drag, in logical pixels; a function,
// since a module-scope constant has no float form.
fn gesture_slop() -> f32 {
    ret 8.0
}

// The offset moved by `delta`: clamped to the content, or -- a soft move past an
// end of a bouncing viewport -- at half speed up to half the viewport; reported.
fn scroll_by(s: *State, element: usize, delta: f32, soft: bool) -> err {
    let e = &s.elements[element]
    let most = max_f(e.content_extent - e.viewport_extent, 0.0)
    var next = e.scroll_offset + delta
    if e.overscroll == .Bounce && soft {
        let give = e.viewport_extent * 0.5
        if next < 0.0 || next > most { next = e.scroll_offset + delta * 0.5 }
        if next < 0.0 - give { next = 0.0 - give }
        if next > most + give { next = most + give }
    } else {
        if next > most { next = most }
        if next < 0.0 { next = 0.0 }
    }
    if next == e.scroll_offset { ret ok }
    e.scroll_offset = next
    e.invalid = true
    ret fire_change[f32](e.scroll_change, next)
}

// The nearest scroll viewport at or above `index`, or none.
fn scroll_ancestor(s: *State, index: usize) -> (usize, bool) {
    var at = index
    while true {
        let e = &s.elements[at]
        if e.kind == SCROLL_TAG { ret (at, true) }
        if !e.has_parent { ret (0usize, false) }
        at = usize(e.parent)
    }
    ret (0usize, false)
}

fn axis_of(e: *const Element, p: geometry.Point) -> f32 {
    if e.scroll_axis == .Vertical { ret p.y }
    ret p.x
}

// A frame's step for every viewport: momentum carries the offset and decays, an
// offset past an end springs back once the pointer has let go.
fn settle_scrolls(s: *State) -> err {
    var i = 0usize
    while i < s.elements.len {
        let e = &s.elements[i]
        if e.live && e.kind == SCROLL_TAG {
            if e.scroll_velocity != 0.0 {
                try scroll_by(s, i, e.scroll_velocity, e.overscroll == .Bounce)
                e.scroll_velocity = e.scroll_velocity * 0.9
                if e.scroll_velocity < 0.25 && e.scroll_velocity > -0.25 { e.scroll_velocity = 0.0 }
            }
            let held = s.arena_state.pressed && usize(s.arena_state.candidate) == i
            if !held {
                let most = max_f(e.content_extent - e.viewport_extent, 0.0)
                var bound = e.scroll_offset
                if e.scroll_offset < 0.0 { bound = 0.0 }
                if e.scroll_offset > most { bound = most }
                if bound != e.scroll_offset {
                    var next = e.scroll_offset + (bound - e.scroll_offset) * 0.3
                    if next - bound < 0.5 && bound - next < 0.5 { next = bound }
                    e.scroll_velocity = 0.0
                    e.scroll_offset = next
                    e.invalid = true
                    try fire_change[f32](e.scroll_change, next)
                }
            }
        }
        i += 1usize
    }
    ret ok
}

fn distance_sq(a: geometry.Point, b: geometry.Point) -> f32 {
    let dx = a.x - b.x
    let dy = a.y - b.y
    ret dx * dx + dy * dy
}

// The nearest scope at or above `index`, or none.
fn scope_of(s: *State, index: usize) -> (usize, bool) {
    var at = index
    while true {
        let e = &s.elements[at]
        if e.kind == SCOPE_TAG { ret (at, true) }
        if !e.has_parent { ret (0usize, false) }
        at = usize(e.parent)
    }
    ret (0usize, false)
}

// The nearest overlay at or above `index`, or none.
fn overlay_of(s: *State, index: usize) -> (usize, bool) {
    var at = index
    while true {
        let e = &s.elements[at]
        if e.kind == OVERLAY_TAG { ret (at, true) }
        if !e.has_parent { ret (0usize, false) }
        at = usize(e.parent)
    }
    ret (0usize, false)
}

fn focusable(e: *const Element) -> bool {
    if !e.live || !e.enabled { ret false }
    // A slider is a tab stop too (D958): its keys move it once it has focus.
    if e.kind == REGION_TAG || e.kind == EDIT_TAG || e.kind == SLIDER_TAG { ret e.focusable }
    ret e.has_action
}

// The focusable elements of a subtree in preorder, into `out`; the count.
fn collect_focusable(s: *State, index: usize, out: []u32, count: usize) -> usize {
    var n = count
    let e = &s.elements[index]
    if !e.live { ret n }
    if focusable(e) && !(e.kind == EDIT_TAG && e.untabbed) && n < out.len {
        out[n] = u32(index)
        n += 1usize
    }
    var at = e.first_child
    var has = e.has_child
    while has {
        n = collect_focusable(s, usize(at), out, n)
        let child = &s.elements[usize(at)]
        has = child.has_sibling
        at = child.next_sibling
    }
    ret n
}

// Where Tab walks: the trapping scope or modal overlay the focus sits in, or the tree.
fn focus_root(s: *State) -> usize {
    var root = usize(s.root)
    if s.has_focus {
        let (found_scope, has_scope) = scope_of(s, usize(s.focus))
        if has_scope && s.elements[found_scope].traps_focus { root = found_scope }
        let (found_overlay, has_overlay) = overlay_of(s, usize(s.focus))
        if has_overlay && s.elements[found_overlay].modal { root = found_overlay }
    }
    ret root
}

fn semantic_role_under(s: *State, index: usize, role: u8) -> (usize, bool) {
    let e = &s.elements[index]
    if !e.live { ret (0usize, false) }
    if e.has_semantics && e.sem.role == role { ret (index, true) }
    var at = e.first_child
    var has = e.has_child
    while has {
        let (found, has_found) = semantic_role_under(s, usize(at), role)
        if has_found { ret (found, true) }
        let child = &s.elements[usize(at)]
        has = child.has_sibling
        at = child.next_sibling
    }
    ret (0usize, false)
}

fn collect_menu_titles(s: *State, index: usize, targets: []u32, owners: []u32, count: usize) -> usize {
    var n = count
    let e = &s.elements[index]
    if !e.live || e.kind == OVERLAY_TAG { ret n }
    if e.has_semantics && (e.sem.actions & 1024u32) != 0u32 {
        var one: [1]u32 = zero
        if collect_focusable(s, index, one[..], 0usize) != 0usize && n < targets.len {
            targets[n] = one[0usize]
            owners[n] = u32(index)
            n += 1usize
        }
        ret n
    }
    var at = e.first_child
    var has = e.has_child
    while has {
        n = collect_menu_titles(s, usize(at), targets, owners, n)
        let child = &s.elements[usize(at)]
        has = child.has_sibling
        at = child.next_sibling
    }
    ret n
}

fn menu_alt_key(code: u32) -> bool {
    ret code == 18u32 || code == 65513u32 || code == 65514u32
}

fn leave_menu_mode(s: *State) {
    s.menu_typeahead_len = 0usize
    s.typeahead_context = 0u8
    if !s.menu_mode { ret }
    if s.has_menu_saved_focus && s.elements[usize(s.menu_saved_focus)].live {
        s.focus = s.menu_saved_focus
        s.has_focus = true
        s.focus_visible = true
    } else {
        s.has_focus = false
    }
    s.menu_mode = false
    s.has_menu_saved_focus = false
}

// Alt plus a menu title's initial enters menu mode on that title and opens it.
fn menu_bar_access_key(s: *State, logical: u32) -> (bool, err) {
    let typed = unicode.to_lower_simple(logical)
    if !unicode.is_alphabetic(typed) { ret (false, ok) }
    let (bar, has_bar) = semantic_role_under(s, usize(s.root), 41u8)
    if !has_bar { ret (false, ok) }
    var targets: [32]u32 = zero
    var owners: [32]u32 = zero
    let count = collect_menu_titles(s, bar, targets[..], owners[..], 0usize)
    var i = 0usize
    while i < count {
        let owner = &s.elements[usize(owners[i])]
        if owner.text_len != 0usize {
            let (first, _) = unicode.read_utf8(owner.text[0usize..owner.text_len], 0usize)
            if unicode.to_lower_simple(first) == typed {
                s.menu_typeahead_len = 0usize
                if !s.menu_mode {
                    s.menu_saved_focus = s.focus
                    s.has_menu_saved_focus = s.has_focus
                }
                s.focus = targets[i]
                s.has_focus = true
                s.focus_visible = true
                s.menu_mode = true
                let title = &s.elements[usize(targets[i])]
                let fired = fire_gesture(title.gesture, Gesture { Tap: geometry.Point { x: title.bounds.x + title.bounds.width * 0.5, y: title.bounds.y + title.bounds.height * 0.5 } })
                ret (true, fired)
            }
        }
        i += 1usize
    }
    ret (false, ok)
}

// F10 enters the first MenuBar title. Left and Right walk titles, following an
// open menu; Down opens the focused title; Escape leaves title mode.
fn menu_bar_key(s: *State, code: u32, k: input.KeyEvent) -> (bool, err) {
    if code != 121u32 && code != 37u32 && code != 39u32 && code != 40u32 && code != 27u32 { ret (false, ok) }
    let plain = !k.modifiers.shift && !k.modifiers.control && !k.modifiers.alt && !k.modifiers.meta
    if s.has_focus && plain {
        let (item_owner, has_item) = menu_item_owner(s, usize(s.focus))
        if has_item && code == 39u32 && (s.elements[item_owner].sem.actions & 1024u32) != 0u32 {
            let item = &s.elements[usize(s.focus)]
            let fired = fire_gesture(item.gesture, Gesture { Tap: geometry.Point { x: item.bounds.x + item.bounds.width * 0.5, y: item.bounds.y + item.bounds.height * 0.5 } })
            if fired == ok {
                s.requested_focus_key = s.elements[item_owner].sem.controls + 1u64
                s.has_requested_focus_key = true
            }
            ret (true, fired)
        }
        if has_item && (code == 37u32 || code == 27u32) {
            let (back_owner, back_region, has_back) = menu_back_region(s, usize(s.focus))
            if has_back {
                let back = &s.elements[back_region]
                let fired = fire_gesture(back.gesture, Gesture { Tap: geometry.Point { x: back.bounds.x + back.bounds.width * 0.5, y: back.bounds.y + back.bounds.height * 0.5 } })
                if fired == ok {
                    s.requested_focus_key = s.elements[back_owner].sem.controls
                    s.has_requested_focus_key = true
                }
                ret (true, fired)
            }
        }
        if has_item && code == 37u32 {
            var modal_count = 0usize
            var top = 0usize
            var m = 0usize
            while m < s.overlay_count {
                let over = usize(s.overlays[m])
                if s.elements[over].modal && descends_from(s, usize(s.focus), over) {
                    modal_count += 1usize
                    top = over
                }
                m += 1usize
            }
            if modal_count > 1usize { ret (true, fire_submit(s.elements[top].dismiss)) }
        }
    }
    let (bar, has_bar) = semantic_role_under(s, usize(s.root), 41u8)
    if !has_bar { ret (false, ok) }
    var targets: [32]u32 = zero
    var owners: [32]u32 = zero
    let count = collect_menu_titles(s, bar, targets[..], owners[..], 0usize)
    if count == 0usize { ret (false, ok) }
    if code == 121u32 && plain {
        s.menu_typeahead_len = 0usize
        if !s.menu_mode {
            s.menu_saved_focus = s.focus
            s.has_menu_saved_focus = s.has_focus
        }
        s.focus = targets[0usize]
        s.has_focus = true
        s.focus_visible = true
        s.menu_mode = true
        ret (true, ok)
    }
    if !s.has_focus || !plain || !descends_from(s, usize(s.focus), bar) { ret (false, ok) }
    var current = count
    var opened = count
    var i = 0usize
    while i < count {
        let owner = usize(owners[i])
        if usize(s.focus) == usize(targets[i]) || descends_from(s, usize(s.focus), owner) { current = i }
        if (s.elements[owner].sem.states & 16u32) != 0u32 { opened = i }
        i += 1usize
    }
    if current == count && opened < count { current = opened }
    if current == count { ret (false, ok) }
    if code == 37u32 || code == 39u32 {
        s.menu_typeahead_len = 0usize
        var next = (current + 1usize) % count
        if code == 37u32 { next = (current + count - 1usize) % count }
        s.focus = targets[next]
        s.focus_visible = true
        if opened < count {
            let title = &s.elements[usize(targets[next])]
            let fired = fire_gesture(title.gesture, Gesture { Tap: geometry.Point { x: title.bounds.x + title.bounds.width * 0.5, y: title.bounds.y + title.bounds.height * 0.5 } })
            ret (true, fired)
        }
        ret (true, ok)
    }
    if code == 40u32 && usize(s.focus) == usize(targets[current]) {
        s.menu_typeahead_len = 0usize
        let title = &s.elements[usize(targets[current])]
        let fired = fire_gesture(title.gesture, Gesture { Tap: geometry.Point { x: title.bounds.x + title.bounds.width * 0.5, y: title.bounds.y + title.bounds.height * 0.5 } })
        ret (true, fired)
    }
    if code == 27u32 && s.menu_mode && usize(s.focus) == usize(targets[current]) {
        leave_menu_mode(s)
        ret (true, ok)
    }
    ret (false, ok)
}

// A modal menu normally owns pointer hit testing. Its bar is the one exception:
// entering another title follows the open menu to that title.
fn menu_bar_hover(s: *State, point: geometry.Point) -> (bool, err) {
    let (bar, has_bar) = semantic_role_under(s, usize(s.root), 41u8)
    if !has_bar { ret (false, ok) }
    var targets: [32]u32 = zero
    var owners: [32]u32 = zero
    let count = collect_menu_titles(s, bar, targets[..], owners[..], 0usize)
    var opened = count
    var hit = count
    var i = 0usize
    while i < count {
        if (s.elements[usize(owners[i])].sem.states & 16u32) != 0u32 { opened = i }
        if geometry.contains(s.elements[usize(targets[i])].bounds, point) { hit = i }
        i += 1usize
    }
    if opened == count || hit == count {
        s.has_menu_hovered_title = false
        ret (false, ok)
    }
    let hovered_title = targets[hit]
    if s.has_menu_hovered_title && s.menu_hovered_title == hovered_title { ret (true, ok) }
    s.menu_hovered_title = hovered_title
    s.has_menu_hovered_title = true
    if hit == opened { ret (true, ok) }
    s.menu_typeahead_len = 0usize
    let title = &s.elements[usize(hovered_title)]
    let fired = fire_gesture(title.gesture, Gesture { Tap: geometry.Point { x: title.bounds.x + title.bounds.width * 0.5, y: title.bounds.y + title.bounds.height * 0.5 } })
    ret (true, fired)
}

fn menu_item_owner(s: *State, index: usize) -> (usize, bool) {
    var at = index
    while true {
        let e = &s.elements[at]
        if e.has_semantics && (e.sem.role == 22u8 || e.sem.role == 37u8 || e.sem.role == 42u8) { ret (at, true) }
        if !e.has_parent { ret (0usize, false) }
        at = usize(e.parent)
    }
}

fn menu_item_region(s: *State, owner: usize) -> (usize, bool) {
    var one: [1]u32 = zero
    if collect_focusable(s, owner, one[..], 0usize) == 0usize { ret (0usize, false) }
    ret (usize(one[0usize]), true)
}

// The Back/Collapse row in the same modal menu as `index`, if a compact touch
// submenu page is showing.
fn menu_back_region(s: *State, index: usize) -> (usize, usize, bool) {
    let (surface, has_surface) = overlay_of(s, index)
    if !has_surface { ret (0usize, 0usize, false) }
    var i = 0usize
    while i < s.elements.len {
        let e = &s.elements[i]
        if e.live && e.has_semantics && (e.sem.actions & 256u32) != 0u32 && descends_from(s, i, surface) {
            let (region_at, has_region) = menu_item_region(s, i)
            if has_region { ret (i, region_at, true) }
        }
        i += 1usize
    }
    ret (0usize, 0usize, false)
}

// Hover may move between the two modal overlays in a cascading menu. Other
// modal overlays still block everything below their topmost surface.
fn menu_hover_overlay_at(s: *State, p: geometry.Point) -> (usize, bool, bool) {
    var blocker = 0usize
    var has_blocker = false
    var i = s.overlay_count
    while i > 0usize {
        i -= 1usize
        let element = usize(s.overlays[i])
        let e = &s.elements[element]
        if !e.live { continue }
        let (_, is_menu) = semantic_role_under(s, element, 21u8)
        if geometry.contains(e.overlay_bounds, p) { ret (element, true, true) }
        if e.modal && !has_blocker {
            blocker = element
            has_blocker = true
        }
        if e.modal && !is_menu { ret (element, false, true) }
    }
    ret (blocker, false, has_blocker)
}

fn triangle_side(a: geometry.Point, b: geometry.Point, p: geometry.Point) -> f32 {
    ret (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
}

fn in_triangle(p: geometry.Point, a: geometry.Point, b: geometry.Point, c: geometry.Point) -> bool {
    let ab = triangle_side(a, b, p)
    let bc = triangle_side(b, c, p)
    let ca = triangle_side(c, a, p)
    let negative = ab < 0.0 || bc < 0.0 || ca < 0.0
    let positive = ab > 0.0 || bc > 0.0 || ca > 0.0
    ret !(negative && positive)
}

// The one expanded submenu parent, its tap region and controlled overlay.
fn open_submenu(s: *State) -> (usize, usize, usize, bool) {
    var i = 0usize
    while i < s.elements.len {
        let e = &s.elements[i]
        if e.live && e.has_semantics && (e.sem.role == 22u8 || e.sem.role == 37u8 || e.sem.role == 42u8) && (e.sem.actions & 1024u32) != 0u32 && (e.sem.states & 16u32) != 0u32 && e.sem.controls != 0u64 {
            let (item_region, has_region) = menu_item_region(s, i)
            let (controlled, count) = find_by_key(s, e.sem.controls)
            if has_region && count != 0usize && s.elements[usize(controlled.slot)].kind == OVERLAY_TAG { ret (i, item_region, usize(controlled.slot), true) }
        }
        i += 1usize
    }
    ret (0usize, 0usize, 0usize, false)
}

fn menu_safe_triangle(s: *State, submenu: usize, point: geometry.Point) -> bool {
    if !s.has_menu_safe_from { ret false }
    let from = s.menu_safe_from
    let bounds = s.elements[submenu].overlay_bounds
    var edge = bounds.x
    if bounds.x + bounds.width <= from.x { edge = bounds.x + bounds.width }
    ret in_triangle(point, from, geometry.Point { x: edge, y: bounds.y }, geometry.Point { x: edge, y: bounds.y + bounds.height })
}

fn schedule_menu_hover(s: *State, candidate: usize) {
    if !s.has_menu_hover_target || usize(s.menu_hover_target) != candidate {
        s.menu_hover_target = u32(candidate)
        s.has_menu_hover_target = true
        s.menu_hover_at = s.animation_time.nanos
    }
    s.animation_due = true
}

// Submenus open after 200 ms. An open parent's action is also its close action;
// the safe triangle suppresses that close while the pointer heads into the child.
fn menu_submenu_hover(s: *State, point: geometry.Point, surface: usize, inside_surface: bool, over: usize, has_over: bool) {
    let (open_owner, open_region, open_overlay, has_open) = open_submenu(s)
    if has_open && inside_surface && surface == open_overlay {
        s.has_menu_hover_target = false
        ret
    }
    var owner = 0usize
    var has_owner = false
    if has_over {
        let (found_owner, found) = menu_item_owner(s, over)
        owner = found_owner
        has_owner = found
    }
    if has_owner && owner == open_owner {
        s.menu_safe_from = point
        s.has_menu_safe_from = true
        s.has_menu_hover_target = false
        ret
    }
    if has_open && menu_safe_triangle(s, open_overlay, point) {
        s.has_menu_hover_target = false
        ret
    }
    if has_owner && (s.elements[owner].sem.actions & 1024u32) != 0u32 {
        schedule_menu_hover(s, over)
        ret
    }
    if has_open && inside_surface {
        schedule_menu_hover(s, open_region)
        ret
    }
    s.has_menu_hover_target = false
}

fn menu_hover_tick(s: *State) -> err {
    if !s.has_menu_hover_target { ret ok }
    let candidate = usize(s.menu_hover_target)
    if candidate >= s.elements.len || !s.elements[candidate].live || s.elements[candidate].kind != REGION_TAG {
        s.has_menu_hover_target = false
        ret ok
    }
    if s.animation_time.nanos < s.menu_hover_at || s.animation_time.nanos - s.menu_hover_at < 200000000i64 {
        s.animation_due = true
        ret ok
    }
    s.has_menu_hover_target = false
    s.menu_safe_from = s.arena_state.last
    s.has_menu_safe_from = true
    let e = &s.elements[candidate]
    let (candidate_owner, has_candidate_owner) = menu_item_owner(s, candidate)
    let (open_owner, open_region, _, has_open) = open_submenu(s)
    if has_candidate_owner && has_open && candidate_owner != open_owner && (s.elements[candidate_owner].sem.actions & 1024u32) != 0u32 {
        let closed = fire_gesture(s.elements[open_region].gesture, Gesture { Tap: geometry.Point { x: s.elements[open_region].bounds.x + s.elements[open_region].bounds.width * 0.5, y: s.elements[open_region].bounds.y + s.elements[open_region].bounds.height * 0.5 } })
        if closed != ok { ret closed }
    }
    let fired = fire_gesture(e.gesture, Gesture { Tap: geometry.Point { x: e.bounds.x + e.bounds.width * 0.5, y: e.bounds.y + e.bounds.height * 0.5 } })
    if fired == ok { s.animation_due = true }
    ret fired
}

fn semantic_label_element(s: *State, index: usize) -> (usize, bool) {
    let e = &s.elements[index]
    if e.text_len > 0usize && (!e.has_semantics || e.sem.role != 14u8) { ret (index, true) }
    var child = e.first_child
    var has_child = e.has_child
    while has_child {
        let (found, has_found) = semantic_label_element(s, usize(child))
        if has_found { ret (found, true) }
        let next = &s.elements[usize(child)]
        has_child = next.has_sibling
        child = next.next_sibling
    }
    ret (0usize, false)
}

fn semantic_label_starts(s: *State, owner: usize, prefix: []const u32) -> bool {
    let (label_at, has_label) = semantic_label_element(s, owner)
    if !has_label { ret false }
    let label = &s.elements[label_at]
    var at = 0usize
    var i = 0usize
    while i < prefix.len {
        if at >= label.text_len { ret false }
        let (scalar, width) = unicode.read_utf8(label.text[0usize..label.text_len], at)
        if unicode.to_lower_simple(scalar) != prefix[i] { ret false }
        at += width
        i += 1usize
    }
    ret true
}

fn focus_menu_prefix(s: *State, order: []const u32, count: usize, current: usize, prefix: []const u32) -> bool {
    var step = 1usize
    while step <= count {
        let candidate = usize(order[(current + step) % count])
        let (owner_at, has_owner) = menu_item_owner(s, candidate)
        if has_owner && semantic_label_starts(s, owner_at, prefix) {
            s.focus = u32(candidate)
            ret true
        }
        step += 1usize
    }
    ret false
}

// A menu's keys (D975, D997): with a menu item (plain, checkbox or radio)
// focused, Down and Up move the focus as Tab and Shift+Tab do (wrapping,
// disabled items skipped), Home and End jump, and a letter moves to the next
// item whose label starts with it; whether the key was taken.
fn menu_key(s: *State, code: u32, k: input.KeyEvent) -> bool {
    if !s.has_focus || k.modifiers.shift || k.modifiers.control || k.modifiers.alt || k.modifiers.meta { ret false }
    let navigation = code == 40u32 || code == 38u32 || code == 36u32 || code == 35u32
    let typed = unicode.to_lower_simple(k.key.logical)
    if !navigation && !unicode.is_alphabetic(typed) { ret false }
    let (_, has_item) = menu_item_owner(s, usize(s.focus))
    if !has_item { ret false }
    if code == 40u32 || code == 38u32 {
        s.menu_typeahead_len = 0usize
        move_focus(s, code == 38u32)
        ret true
    }
    let order = s.focus_order
    let count = collect_focusable(s, focus_root(s), order, 0usize)
    if count == 0usize { ret true }
    if code == 36u32 || code == 35u32 {
        s.menu_typeahead_len = 0usize
        s.focus = order[0usize]
        if code == 35u32 { s.focus = order[count - 1usize] }
    } else {
        if s.typeahead_context != 1u8 { s.menu_typeahead_len = 0usize }
        s.typeahead_context = 1u8
        var current = 0usize
        var i = 0usize
        while i < count {
            if usize(order[i]) == usize(s.focus) { current = i }
            i += 1usize
        }
        let now = s.animation_time.nanos
        if s.menu_typeahead_len == 16usize || now < s.menu_typeahead_at || now - s.menu_typeahead_at >= 500000000i64 {
            s.menu_typeahead_len = 0usize
        }
        s.menu_typeahead_at = now
        s.menu_typeahead[s.menu_typeahead_len] = typed
        s.menu_typeahead_len += 1usize
        if !focus_menu_prefix(s, order[..], count, current, s.menu_typeahead[0usize..s.menu_typeahead_len]) && s.menu_typeahead_len > 1usize {
            s.menu_typeahead[0usize] = typed
            s.menu_typeahead_len = 1usize
            let _ = focus_menu_prefix(s, order[..], count, current, s.menu_typeahead[0usize..1usize])
        }
    }
    s.focus_visible = true
    ret true
}

fn collection_item_owner(s: *State, index: usize) -> (usize, u8, bool) {
    var at = index
    while true {
        let e = &s.elements[at]
        if e.has_semantics && (e.sem.role == 11u8 || (e.sem.role == 13u8 && e.sem.level > 0u8) || e.sem.role == 14u8 || e.sem.role == 29u8) { ret (at, e.sem.role, true) }
        if !e.has_parent { ret (0usize, 0u8, false) }
        at = usize(e.parent)
    }
}

fn collection_root(s: *State, owner: usize, item_role: u8) -> (usize, u8, bool) {
    var at = owner
    while true {
        let e = &s.elements[at]
        if item_role == 11u8 && e.has_semantics && e.sem.role == 10u8 { ret (at, 2u8, true) }
        if item_role == 14u8 && e.has_semantics && e.sem.role == 30u8 { ret (at, 3u8, true) }
        if item_role == 29u8 && e.has_semantics && e.sem.role == 28u8 { ret (at, 4u8, true) }
        if item_role == 13u8 && e.has_semantics && e.sem.role == 43u8 { ret (at, 4u8, true) }
        if !e.has_parent { ret (0usize, 0u8, false) }
        at = usize(e.parent)
    }
}

fn focus_collection_prefix(s: *State, order: []const u32, count: usize, current: usize, root: usize, item_role: u8, prefix: []const u32) -> bool {
    var step = 1usize
    while step <= count {
        let candidate = usize(order[(current + step) % count])
        let (owner, role, has_owner) = collection_item_owner(s, candidate)
        if has_owner && role == item_role {
            let (candidate_root, _, has_root) = collection_root(s, owner, role)
            if has_root && candidate_root == root && semantic_label_starts(s, owner, prefix) {
                s.focus = u32(candidate)
                ret true
            }
        }
        step += 1usize
    }
    ret false
}

// Buffered typeahead for built List, GridView and Tree items.
// ponytail: virtual sources need a source-level lookup beyond their built rows.
fn collection_typeahead_key(s: *State, code: u32, k: input.KeyEvent) -> bool {
    if !s.has_focus || k.modifiers.shift || k.modifiers.control || k.modifiers.alt || k.modifiers.meta { ret false }
    let (owner, item_role, has_owner) = collection_item_owner(s, usize(s.focus))
    if !has_owner { ret false }
    let (root, context, has_root) = collection_root(s, owner, item_role)
    if !has_root { ret false }
    let typed = unicode.to_lower_simple(k.key.logical)
    if !unicode.is_alphabetic(typed) {
        s.menu_typeahead_len = 0usize
        s.typeahead_context = 0u8
        ret false
    }
    let order = s.focus_order
    let count = collect_focusable(s, root, order, 0usize)
    if count == 0usize { ret true }
    var current = 0usize
    var i = 0usize
    while i < count {
        if usize(order[i]) == usize(s.focus) { current = i }
        i += 1usize
    }
    let now = s.animation_time.nanos
    if s.typeahead_context != context || s.menu_typeahead_len == 16usize || now < s.menu_typeahead_at || now - s.menu_typeahead_at >= 500000000i64 {
        s.menu_typeahead_len = 0usize
    }
    s.typeahead_context = context
    s.menu_typeahead_at = now
    s.menu_typeahead[s.menu_typeahead_len] = typed
    s.menu_typeahead_len += 1usize
    if !focus_collection_prefix(s, order[..], count, current, root, item_role, s.menu_typeahead[0usize..s.menu_typeahead_len]) && s.menu_typeahead_len > 1usize {
        s.menu_typeahead[0usize] = typed
        s.menu_typeahead_len = 1usize
        let _ = focus_collection_prefix(s, order[..], count, current, root, item_role, s.menu_typeahead[0usize..1usize])
    }
    s.focus_visible = true
    ret true
}

// A chosen menu command closes its modal menu and gives keyboard menu mode's
// saved focus back. The command action runs first, so a failed command remains
// visible and focused for recovery.
fn menu_tap(s: *State, index: usize, point: geometry.Point) -> err {
    let fired = fire_gesture(s.elements[index].gesture, Gesture { Tap: point })
    if fired != ok { ret fired }
    let (owner_at, item) = menu_item_owner(s, index)
    if !item { ret ok }
    if (s.elements[owner_at].sem.actions & 256u32) != 0u32 {
        s.requested_focus_key = s.elements[owner_at].sem.controls
        s.has_requested_focus_key = true
        ret ok
    }
    if (s.elements[owner_at].sem.actions & 1024u32) != 0u32 { ret ok }
    let (_, back_region, has_back) = menu_back_region(s, index)
    if has_back {
        let back = &s.elements[back_region]
        let closed = fire_gesture(back.gesture, Gesture { Tap: geometry.Point { x: back.bounds.x + back.bounds.width * 0.5, y: back.bounds.y + back.bounds.height * 0.5 } })
        if closed != ok { ret closed }
    }
    s.menu_typeahead_len = 0usize
    var i = s.overlay_count
    while i > 0usize {
        i -= 1usize
        let modal = usize(s.overlays[i])
        if s.elements[modal].modal && descends_from(s, index, modal) {
            let dismissed = fire_submit(s.elements[modal].dismiss)
            if dismissed != ok { ret dismissed }
        }
    }
    leave_menu_mode(s)
    ret ok
}

// A pointer's second tap still runs the ordinary Tap path, then additionally
// offers DoubleTap to the same region within the platform-neutral 500 ms window.
fn pointer_tap(s: *State, index: usize, point: geometry.Point) -> err {
    let fired = menu_tap(s, index, point)
    if fired != ok { ret fired }
    let elapsed = s.animation_time.nanos - s.last_tap_at.nanos
    let current = ElementId { slot: u32(index), generation: s.elements[index].generation }
    let doubled = s.has_last_tap && s.last_tap.slot == current.slot && s.last_tap.generation == current.generation && elapsed >= 0i64 && elapsed <= 500000000i64
    s.last_tap = current
    s.has_last_tap = !doubled
    s.last_tap_at = s.animation_time
    if doubled { ret fire_gesture(s.elements[index].gesture, Gesture { DoubleTap: point }) }
    ret ok
}

// While a menu owns focus, Alt plus an item's initial runs that item.
fn menu_item_access_key(s: *State, logical: u32) -> (bool, err) {
    if !s.has_focus { ret (false, ok) }
    let (_, focused_item) = menu_item_owner(s, usize(s.focus))
    if !focused_item { ret (false, ok) }
    let typed = unicode.to_lower_simple(logical)
    if !unicode.is_alphabetic(typed) { ret (false, ok) }
    let order = s.focus_order
    let count = collect_focusable(s, focus_root(s), order, 0usize)
    var i = 0usize
    while i < count {
        let candidate = usize(order[i])
        let (owner_at, has_owner) = menu_item_owner(s, candidate)
        if has_owner && s.elements[owner_at].text_len != 0usize {
            let owner = &s.elements[owner_at]
            let (first, _) = unicode.read_utf8(owner.text[0usize..owner.text_len], 0usize)
            if unicode.to_lower_simple(first) == typed {
                let e = &s.elements[candidate]
                ret (true, menu_tap(s, candidate, geometry.Point { x: e.bounds.x + e.bounds.width * 0.5, y: e.bounds.y + e.bounds.height * 0.5 }))
            }
        }
        i += 1usize
    }
    ret (false, ok)
}

// Tab and Shift+Tab: the next or previous focusable element in preorder, within
// the trapping scope's subtree when the focus sits in one, wrapping at the ends.
fn move_focus(s: *State, backward: bool) {
    let root = focus_root(s)
    let order = s.focus_order
    let count = collect_focusable(s, root, order, 0usize)
    if count == 0usize { ret }
    var current = count
    if s.has_focus {
        var i = 0usize
        while i < count {
            if usize(order[i]) == usize(s.focus) { current = i }
            i += 1usize
        }
    }
    var next = 0usize
    if current < count {
        if backward {
            next = (current + count - 1usize) % count
        } else {
            next = (current + 1usize) % count
        }
    } else {
        if backward { next = count - 1usize }
    }
    s.focus = order[next]
    s.has_focus = true
    s.focus_visible = true
}

fn semantic_target(e: *const Element, roles: []const u8) -> bool {
    if !e.live || !e.has_semantics { ret false }
    var i = 0usize
    while i < roles.len {
        if roles[i] != 0u8 && e.sem.role == roles[i] { ret true }
        i += 1usize
    }
    ret false
}

fn collect_semantic_targets(s: *State, index: usize, roles: []const u8, out: []u32, count: usize) -> usize {
    var n = count
    let e = &s.elements[index]
    if !e.live { ret n }
    if semantic_target(e, roles) && n < out.len {
        out[n] = u32(index)
        n += 1usize
    }
    var at = e.first_child
    var has = e.has_child
    while has {
        n = collect_semantic_targets(s, usize(at), roles, out, n)
        let child = &s.elements[usize(at)]
        has = child.has_sibling
        at = child.next_sibling
    }
    ret n
}

// Move focus among semantic landmarks in tree order. A focused descendant
// counts as its containing landmark; zero role codes are ignored.
fn focus_semantics(widget_runtime: *Runtime, roles: []const u8, backward: bool) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let order = s.focus_order
    let count = collect_semantic_targets(s, usize(s.root), roles, order, 0usize)
    if count == 0usize { ret ok }
    var current = count
    if s.has_focus {
        var i = 0usize
        while i < count {
            let candidate = usize(order[i])
            if usize(s.focus) == candidate || descends_from(s, usize(s.focus), candidate) { current = i }
            i += 1usize
        }
    }
    var next = 0usize
    if current < count {
        if backward {
            next = (current + count - 1usize) % count
        } else {
            next = (current + 1usize) % count
        }
    } else if backward {
        next = count - 1usize
    }
    s.focus = order[next]
    s.has_focus = true
    s.focus_visible = true
    ret ok
}

// ---------------------------------------------------------------------- editing

// The host's key as a Windows virtual code: an X keysym for the keys the editor
// and the scopes read maps onto it, a Latin letter onto its upper case.
fn key_code(physical: u32) -> u32 {
    if physical >= 97u32 && physical <= 122u32 { ret physical - 32u32 }
    if physical == 65361u32 { ret 37u32 }
    if physical == 65362u32 { ret 38u32 }
    if physical == 65363u32 { ret 39u32 }
    if physical == 65364u32 { ret 40u32 }
    if physical == 65360u32 { ret 36u32 }
    if physical == 65367u32 { ret 35u32 }
    if physical == 65365u32 { ret 33u32 }
    if physical == 65366u32 { ret 34u32 }
    if physical == 65288u32 { ret 8u32 }
    if physical == 65535u32 { ret 46u32 }
    if physical == 65293u32 || physical == 65421u32 { ret 13u32 }
    if physical == 65307u32 { ret 27u32 }
    if physical == 65289u32 { ret 9u32 }
    if physical == 65505u32 || physical == 65506u32 { ret 16u32 }
    if physical == 65507u32 || physical == 65508u32 { ret 17u32 }
    if physical == 65513u32 || physical == 65514u32 { ret 18u32 }
    if physical == 65515u32 || physical == 65516u32 { ret 91u32 }
    if physical >= 65470u32 && physical <= 65493u32 { ret physical - 65358u32 }
    ret physical
}

fn hold_modifier(s: *State, code: u32, down: bool) {
    if code == 16u32 { s.held_modifiers.shift = down }
    if code == 17u32 { s.held_modifiers.control = down }
    if code == 18u32 { s.held_modifiers.alt = down }
    if code == 91u32 || code == 92u32 { s.held_modifiers.meta = down }
}

fn selection_of(e: *const Element) -> (usize, usize) {
    if e.anchor <= e.caret { ret (e.anchor, e.caret) }
    ret (e.caret, e.anchor)
}

fn prev_char(e: *const Element, at: usize) -> usize {
    var i = at
    if i == 0usize { ret 0usize }
    i -= 1usize
    while i > 0usize && (u32(e.edit_buffer[i]) & 192u32) == 128u32 { i -= 1usize }
    ret i
}

fn next_char(e: *const Element, at: usize) -> usize {
    var i = at
    if i >= e.edit_len { ret e.edit_len }
    i += 1usize
    while i < e.edit_len && (u32(e.edit_buffer[i]) & 192u32) == 128u32 { i += 1usize }
    ret i
}

fn line_start(e: *const Element, at: usize) -> usize {
    var i = at
    while i > 0usize && e.edit_buffer[i - 1usize] != 10u8 { i -= 1usize }
    ret i
}

fn line_end(e: *const Element, at: usize) -> usize {
    var i = at
    while i < e.edit_len && e.edit_buffer[i] != 10u8 { i += 1usize }
    ret i
}

// The editor's value laid out in the scratch region, for a hit test or a caret.
fn edit_layout(s: *State, e: *const Element) -> (layout.Layout, err) {
    if e.edit_style.fonts.len == 0usize || e.edit_len == 0usize { ret (zero, InvalidTree) }
    var scratch = mem.arena_from(s.scratch)
    let (shown, shown_error) = edit_display(s, &scratch, e, false)
    if shown_error != ok { ret (zero, InvalidTree) }
    let (laid, layout_error) = layout.layout(&scratch, shown, e.edit_style, edit_options(e.text_width, e.multiline))
    if layout_error != ok { ret (zero, InvalidTree) }
    ret (laid, ok)
}

fn edit_hit(s: *State, element: usize, p: geometry.Point) -> usize {
    let e = &s.elements[element]
    let (laid, laid_error) = edit_layout(s, e)
    if laid_error != ok { ret 0usize }
    ret layout.hit_test(&laid, geometry.Point { x: p.x - e.text_origin.x, y: p.y - e.text_origin.y })
}

// The caret one line up or down, by its x in the layout; the ends past the first
// and last lines.
fn edit_vertical(s: *State, element: usize, down: bool) -> usize {
    let e = &s.elements[element]
    let (laid, laid_error) = edit_layout(s, e)
    if laid_error != ok { ret e.caret }
    let line = layout.line_of_offset(&laid, e.caret)
    if line >= laid.lines.len { ret e.caret }
    if down && line + 1usize >= laid.lines.len { ret e.edit_len }
    if !down && line == 0usize { ret 0usize }
    let c = layout.caret(&laid, e.caret)
    var y = c.y - 1.0
    if down { y = c.y + c.height + 1.0 }
    ret layout.hit_test(&laid, geometry.Point { x: c.x, y: y })
}

// The history: an edit is remembered as what it removed and inserted, a typed byte
// onto the last typed run; an edit drops the redo tail.
// ponytail: the byte pool is never compacted; when it is full the history is forgotten.
fn history_push(s: *State, element: usize, at: usize, removed: []const u8, inserted: []const u8) {
    s.history_count = s.history_at
    if s.history_count > 0usize && removed.len == 0usize && inserted.len == 1usize {
        let last = &s.history[s.history_count - 1usize]
        if usize(last.element) == element && last.removed_len == 0usize && last.at + last.inserted_len == at && last.inserted_off + last.inserted_len == s.history_used && s.history_used < HISTORY_BYTES {
            s.history_bytes[s.history_used] = inserted[0usize]
            s.history_used += 1usize
            last.inserted_len += 1usize
            ret
        }
    }
    if s.history_used + removed.len + inserted.len > HISTORY_BYTES {
        s.history_used = 0usize
        s.history_count = 0usize
        s.history_at = 0usize
        if removed.len + inserted.len > HISTORY_BYTES { ret }
    }
    if s.history_count == MAX_HISTORY {
        var i = 1usize
        while i < MAX_HISTORY {
            s.history[i - 1usize] = s.history[i]
            i += 1usize
        }
        s.history_count -= 1usize
    }
    var entry = Undo { element: u32(element), at: at, removed_off: s.history_used, removed_len: removed.len, inserted_off: s.history_used + removed.len, inserted_len: inserted.len }
    var k = 0usize
    while k < removed.len {
        s.history_bytes[s.history_used + k] = removed[k]
        k += 1usize
    }
    k = 0usize
    while k < inserted.len {
        s.history_bytes[entry.inserted_off + k] = inserted[k]
        k += 1usize
    }
    s.history_used += removed.len + inserted.len
    s.history[s.history_count] = entry
    s.history_count += 1usize
    s.history_at = s.history_count
}

// The one edit: `start..end` of the value becomes `inserted`, the caret after it, the
// change reported. A value that would not fit its buffer is left as it is.
fn edit_replace(s: *State, element: usize, start: usize, end: usize, inserted: []const u8, remember: bool) -> err {
    let e = &s.elements[element]
    if start > end || end > e.edit_len { ret InvalidTree }
    let removed = end - start
    let new_len = e.edit_len - removed + inserted.len
    if new_len > e.edit_buffer.len { ret ok }
    if remember { history_push(s, element, start, e.edit_buffer[start..end], inserted) }
    if inserted.len > removed {
        var i = e.edit_len
        while i > end {
            i -= 1usize
            e.edit_buffer[i + inserted.len - removed] = e.edit_buffer[i]
        }
    } else if inserted.len < removed {
        var i = end
        while i < e.edit_len {
            e.edit_buffer[i - removed + inserted.len] = e.edit_buffer[i]
            i += 1usize
        }
    }
    var k = 0usize
    while k < inserted.len {
        e.edit_buffer[start + k] = inserted[k]
        k += 1usize
    }
    e.edit_len = new_len
    e.caret = start + inserted.len
    e.anchor = e.caret
    e.invalid = true
    let value: str = e.edit_buffer[0usize..new_len]
    ret fire_change[str](e.edit_change, value)
}

fn edit_undo(s: *State) -> err {
    if s.history_at == 0usize { ret ok }
    let u = s.history[s.history_at - 1usize]
    s.history_at -= 1usize
    let element = usize(u.element)
    let e = &s.elements[element]
    if !e.live || e.kind != EDIT_TAG || u.at + u.inserted_len > e.edit_len { ret ok }
    ret edit_replace(s, element, u.at, u.at + u.inserted_len, s.history_bytes[u.removed_off..u.removed_off + u.removed_len], false)
}

fn edit_redo(s: *State) -> err {
    if s.history_at >= s.history_count { ret ok }
    let u = s.history[s.history_at]
    s.history_at += 1usize
    let element = usize(u.element)
    let e = &s.elements[element]
    if !e.live || e.kind != EDIT_TAG || u.at + u.removed_len > e.edit_len { ret ok }
    ret edit_replace(s, element, u.at, u.at + u.removed_len, s.history_bytes[u.inserted_off..u.inserted_off + u.inserted_len], false)
}

// The selection to the host's clipboard, and to the fallback for a host without one.
fn edit_copy(s: *State, e: *const Element) {
    // A secret is never copied.
    if e.secret { ret }
    let (lo, hi) = selection_of(e)
    var n = hi - lo
    if n > MAX_CLIP { n = MAX_CLIP }
    var k = 0usize
    while k < n {
        s.clip[k] = e.edit_buffer[lo + k]
        k += 1usize
    }
    s.clip_len = n
    s.clip_hosted = os.set_clipboard_text(e.edit_buffer[lo..hi]) == ok
}

fn edit_paste(s: *State, element: usize) -> err {
    let e = &s.elements[element]
    let (lo, hi) = selection_of(e)
    if s.clip_hosted || s.clip_len == 0usize {
        var scratch = mem.arena_from(s.scratch)
        let (host_text, host_error) = os.clipboard_text(&scratch)
        if host_error == ok { ret edit_replace(s, element, lo, hi, host_text, true) }
    }
    ret edit_replace(s, element, lo, hi, s.clip[0usize..s.clip_len], true)
}

fn edit_move(e: *Element, to: usize, extend: bool) {
    e.caret = to
    if !extend { e.anchor = to }
    e.invalid = true
}

// A key down in the focused editor: movement (Shift extends the selection), Home
// and End within the line, Backspace and Delete, Enter, and the Control chords for
// select all, copy, cut, paste, undo and redo. Anything else is not the editor's.
fn edit_key(s: *State, element: usize, k: input.KeyEvent) -> (bool, err) {
    let e = &s.elements[element]
    if !e.enabled { ret (false, ok) }
    let code = key_code(k.key.physical)
    let (lo, hi) = selection_of(e)
    let writable = !e.read_only
    let extend = k.modifiers.shift
    if k.modifiers.control {
        if code == 65u32 {
            e.anchor = 0usize
            e.caret = e.edit_len
            ret (true, ok)
        }
        if code == 67u32 {
            edit_copy(s, e)
            ret (true, ok)
        }
        if code == 88u32 && writable {
            edit_copy(s, e)
            let cut = edit_replace(s, element, lo, hi, "", true)
            ret (true, cut)
        }
        if code == 86u32 && writable {
            let pasted = edit_paste(s, element)
            ret (true, pasted)
        }
        if code == 90u32 && writable {
            if extend {
                let redone = edit_redo(s)
                ret (true, redone)
            }
            let undone = edit_undo(s)
            ret (true, undone)
        }
        if code == 89u32 && writable {
            let redone = edit_redo(s)
            ret (true, redone)
        }
        ret (false, ok)
    }
    if code == 37u32 {
        if !extend && lo < hi { edit_move(e, lo, false) } else { edit_move(e, prev_char(e, e.caret), extend) }
        ret (true, ok)
    }
    if code == 39u32 {
        if !extend && lo < hi { edit_move(e, hi, false) } else { edit_move(e, next_char(e, e.caret), extend) }
        ret (true, ok)
    }
    if code == 36u32 {
        edit_move(e, line_start(e, e.caret), extend)
        ret (true, ok)
    }
    if code == 35u32 {
        edit_move(e, line_end(e, e.caret), extend)
        ret (true, ok)
    }
    if code == 38u32 && e.multiline {
        edit_move(e, edit_vertical(s, element, false), extend)
        ret (true, ok)
    }
    if code == 40u32 && e.multiline {
        edit_move(e, edit_vertical(s, element, true), extend)
        ret (true, ok)
    }
    if code == 8u32 {
        if !writable { ret (true, ok) }
        if lo < hi {
            let erased = edit_replace(s, element, lo, hi, "", true)
            ret (true, erased)
        }
        let before = prev_char(e, e.caret)
        let erased = edit_replace(s, element, before, e.caret, "", true)
        ret (true, erased)
    }
    if code == 46u32 {
        // An enclosing control may own Delete (for example, closing the active
        // switcher item). Yield only when that exact unmodified shortcut exists;
        // otherwise Delete keeps editing text as usual.
        var at = element
        while s.elements[at].has_parent {
            at = usize(s.elements[at].parent)
            let parent = &s.elements[at]
            if parent.kind == SCOPE_TAG {
                var shortcut = 0usize
                while shortcut < parent.shortcut_count {
                    let bound = parent.shortcuts[shortcut]
                    if key_code(bound.key) == code && !bound.modifiers.shift && !bound.modifiers.control && !bound.modifiers.alt && !bound.modifiers.meta && !k.modifiers.shift && !k.modifiers.control && !k.modifiers.alt && !k.modifiers.meta { ret (false, ok) }
                    shortcut += 1usize
                }
            }
        }
        if !writable { ret (true, ok) }
        if lo < hi {
            let erased = edit_replace(s, element, lo, hi, "", true)
            ret (true, erased)
        }
        let after = next_char(e, e.caret)
        let erased = edit_replace(s, element, e.caret, after, "", true)
        ret (true, erased)
    }
    if code == 13u32 {
        if e.multiline {
            if !writable { ret (true, ok) }
            let broken = edit_replace(s, element, lo, hi, "\n", true)
            ret (true, broken)
        }
        // No submit of its own: Enter is the enclosing scope's default action (D825).
        if !submit_set(e.edit_submit.invoke) { ret (false, ok) }
        let submitted = fire_submit(e.edit_submit)
        ret (true, submitted)
    }
    ret (false, ok)
}

// Typed text replaces the selection and ends any composition; a control character
// is a key, not text.
fn edit_text_input(s: *State, element: usize, typed: str) -> err {
    let e = &s.elements[element]
    if !e.enabled || e.read_only { ret ok }
    s.compose_len = 0usize
    if typed.len == 0usize || (typed.len == 1usize && typed[0usize] < 32u8) { ret ok }
    let (lo, hi) = selection_of(e)
    ret edit_replace(s, element, lo, hi, typed, true)
}

fn edit_compose(s: *State, element: usize, preedit: str) {
    let e = &s.elements[element]
    if !e.enabled || e.read_only { ret }
    var n = preedit.len
    if n > MAX_COMPOSE { n = MAX_COMPOSE }
    var k = 0usize
    while k < n {
        s.compose[k] = preedit[k]
        k += 1usize
    }
    s.compose_len = n
    e.invalid = true
}

fn focused_edit(s: *State) -> (usize, bool) {
    if !s.has_focus { ret (0usize, false) }
    let e = &s.elements[usize(s.focus)]
    if !e.live || e.kind != EDIT_TAG { ret (0usize, false) }
    ret (usize(s.focus), true)
}

fn same_modifiers(a: input.Modifiers, b: input.Modifiers) -> bool {
    ret a.shift == b.shift && a.control == b.control && a.alt == b.alt && a.meta == b.meta
}

// A key down walks the scopes from the focused element up: a matching shortcut
// fires, Enter is the default action, Escape the cancel one; Tab moves focus first
// -- plain or with Shift only (D969): Ctrl+Tab is a shortcut, a workspace's
// most-recently-used switch.
fn dispatch_key(s: *State, k: input.KeyEvent) -> (bool, err) {
    let code = key_code(k.key.physical)
    let (barred, bar_error) = menu_bar_key(s, code, k)
    if barred || bar_error != ok { ret (true, bar_error) }
    let (editor, has_editor) = focused_edit(s)
    if has_editor {
        let (edited, edit_error) = edit_key(s, editor, k)
        if edited || edit_error != ok { ret (true, edit_error) }
    }
    if menu_key(s, code, k) { ret (true, ok) }
    if collection_typeahead_key(s, code, k) { ret (true, ok) }
    if s.has_focus && s.elements[usize(s.focus)].live && s.elements[usize(s.focus)].kind == SLIDER_TAG {
        let (slid, slide_error) = slider_key(s, usize(s.focus), code)
        if slid || slide_error != ok { ret (true, slide_error) }
    }
    var at = usize(s.root)
    if s.has_focus { at = usize(s.focus) }
    // A modal overlay bounds the keyboard to itself: with nothing focused under it
    // (its content may not be focusable), or the focus left outside it, the walk
    // starts at its scope, so its Escape still dismisses it (D841).
    let (modal, has_modal) = topmost_modal(s)
    if has_modal && (!s.has_focus || !descends_from(s, usize(s.focus), modal)) {
        let (inner, has_inner) = scope_under(s, modal)
        if has_inner { at = inner }
    }
    while true {
        let e = &s.elements[at]
        if e.kind == SCOPE_TAG {
            // A scope that takes every key (D830) takes this one before its shortcuts.
            if change_set[input.KeyEvent](e.keys.invoke) {
                let taken = fire_change[input.KeyEvent](e.keys, k)
                ret (true, taken)
            }
            var i = 0usize
            while i < e.shortcut_count {
                let shortcut = e.shortcuts[i]
                if key_code(shortcut.key) == code && same_modifiers(shortcut.modifiers, k.modifiers) {
                    let fired = fire_submit(shortcut.action)
                    ret (true, fired)
                }
                i += 1usize
            }
            if code == 13u32 && submit_set(e.default_action.invoke) {
                let fired = fire_submit(e.default_action)
                ret (true, fired)
            }
            if code == 27u32 && submit_set(e.cancel_action.invoke) {
                let fired = fire_submit(e.cancel_action)
                ret (true, fired)
            }
        }
        if !e.has_parent { break }
        at = usize(e.parent)
    }
    if code == 9u32 && !k.modifiers.control && !k.modifiers.alt && !k.modifiers.meta {
        move_focus(s, k.modifiers.shift)
        ret (true, ok)
    }
    ret (false, ok)
}

fn dispatch(widget_runtime: *Runtime, event: input.Event) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    if !s.has_root { ret ok }
    switch event {
    case .PointerDown as p:
        s.has_pointer = true
        s.arena_state.last = p.position
        s.has_tooltip_touch = false
        s.tooltip_touch_shown = false
        s.tooltip_touch_released = false
        s.has_long_press = false
        s.long_press_fired = false
        // The topmost overlay under the pointer is the tree the press is in; a modal
        // one the press misses is dismissed and keeps the press from what is under.
        var from = usize(s.root)
        let (over, inside, has_over) = overlay_at(s, p.position)
        if has_over {
            if !inside {
                s.menu_typeahead_len = 0usize
                ret fire_submit(s.elements[over].dismiss)
            }
            from = over
        }
        // The arena takes the pointer for the deepest region that taps or drags; an
        // action element under it is the old contract and still answers.
        let (region_index, has_region) = hit_region(s, from, p.position, GESTURE_TAP | GESTURE_DRAG)
        if has_region {
            s.arena_state.pressed = true
            s.arena_state.candidate = u32(region_index)
            s.arena_state.down = p.position
            s.arena_state.last = p.position
            s.arena_state.dragging = false
            if s.elements[region_index].focusable {
                s.focus = u32(region_index)
                s.has_focus = true
                s.focus_visible = false
            }
            if s.elements[region_index].kind == EDIT_TAG {
                s.compose_len = 0usize
                let at = edit_hit(s, region_index, p.position)
                edit_move(&s.elements[region_index], at, false)
            }
            if s.elements[region_index].kind == SLIDER_TAG { ret slider_press(s, region_index, p.position) }
            ret ok
        }
        let (found, has_found) = hit_action(s, from, p.position)
        if has_found {
            s.focus = u32(found)
            s.has_focus = true
            s.focus_visible = false
            let action = s.elements[found].action
            ret action.invoke(action.ctx, event)
        }
        let (zoomed, has_zoomed) = hit_zoom(s, from, p.position)
        if has_zoomed {
            s.arena_state.pressed = true
            s.arena_state.candidate = u32(zoomed)
            s.arena_state.down = p.position
            s.arena_state.last = p.position
            s.arena_state.dragging = false
            ret ok
        }
        let (viewport, has_viewport) = hit_scroll(s, from, p.position)
        if has_viewport {
            s.arena_state.pressed = true
            s.arena_state.candidate = u32(viewport)
            s.arena_state.down = p.position
            s.arena_state.last = p.position
            s.arena_state.dragging = false
            s.elements[viewport].scroll_velocity = 0.0
        }
    case .PointerUp as p:
        s.has_pointer = true
        s.arena_state.last = p.position
        if s.has_tooltip_touch && s.tooltip_touch_shown {
            s.tooltip_touch_released = true
            s.tooltip_touch_release_at = s.animation_time.nanos
            s.arena_state.pressed = false
            s.arena_state.dragging = false
            ret ok
        }
        if s.long_press_fired {
            var chosen = 0usize
            var has_chosen = false
            if s.arena_state.pressed {
                let candidate = usize(s.arena_state.candidate)
                let (_, is_item) = menu_item_owner(s, candidate)
                if is_item {
                    chosen = candidate
                    has_chosen = true
                }
            }
            if !has_chosen {
                let (over, inside, has_over) = overlay_at(s, p.position)
                if has_over && inside {
                    let (candidate, has_candidate) = hit_region(s, over, p.position, GESTURE_TAP)
                    if has_candidate {
                        let (_, is_item) = menu_item_owner(s, candidate)
                        if is_item {
                            chosen = candidate
                            has_chosen = true
                        }
                    }
                }
            }
            s.long_press_fired = false
            s.has_long_press = false
            s.arena_state.pressed = false
            s.arena_state.dragging = false
            if has_chosen { ret menu_tap(s, chosen, p.position) }
            ret ok
        }
        s.has_long_press = false
        // A drag with a payload dropped: the deepest region under the pointer that
        // takes drops hears it (after the source's own drag end).
        var dropped_on = 0usize
        var has_drop = false
        if s.has_drag {
            let (found_drop, has_found_drop) = hit_region(s, usize(s.root), p.position, GESTURE_DROP)
            dropped_on = found_drop
            has_drop = has_found_drop
        }
        let payload = s.drag_payload
        s.has_drag = false
        if s.arena_state.pressed {
            s.arena_state.pressed = false
            let candidate = usize(s.arena_state.candidate)
            let e = &s.elements[candidate]
            if e.live && e.kind == ZOOM_TAG {
                s.arena_state.dragging = false
                ret ok
            }
            if e.live && e.kind == REGION_TAG && s.arena_state.dragging {
                s.arena_state.dragging = false
                let ended = fire_gesture(e.gesture, Gesture { DragEnd: p.position })
                if ended != ok { ret ended }
                if has_drop { ret fire_gesture(s.elements[dropped_on].gesture, Gesture { Drop: Dropped { position: p.position, payload: payload } }) }
                ret ok
            }
            if e.live && e.kind == SCROLL_TAG {
                if !e.momentum { e.scroll_velocity = 0.0 }
                s.arena_state.dragging = false
                ret ok
            }
            if e.live && e.kind == REGION_TAG {
                if s.arena_state.dragging {
                    s.arena_state.dragging = false
                    ret fire_gesture(e.gesture, Gesture { DragEnd: p.position })
                }
                if (e.gestures & GESTURE_TAP) != 0u8 && geometry.contains(e.bounds, p.position) { ret pointer_tap(s, candidate, p.position) }
            }
            ret ok
        }
        let (found, has_found) = hit_action(s, usize(s.root), p.position)
        if has_found {
            let action = s.elements[found].action
            ret action.invoke(action.ctx, event)
        }
    case .PointerMove as p:
        s.has_pointer = true
        if s.long_press_fired {
            s.arena_state.last = p.position
            s.arena_state.pressed = false
            let (over, inside, has_over) = overlay_at(s, p.position)
            if has_over && inside {
                let (candidate, has_candidate) = hit_region(s, over, p.position, GESTURE_TAP)
                if has_candidate {
                    let (_, is_item) = menu_item_owner(s, candidate)
                    if is_item {
                        s.arena_state.candidate = u32(candidate)
                        s.arena_state.pressed = true
                    }
                }
            }
            ret ok
        }
        if s.has_long_press && !s.long_press_fired && distance_sq(p.position, s.arena_state.down) > gesture_slop() * gesture_slop() {
            s.has_long_press = false
            s.long_press_fired = false
        }
        if s.has_tooltip_touch && !s.tooltip_touch_shown && distance_sq(p.position, s.arena_state.down) > gesture_slop() * gesture_slop() { s.has_tooltip_touch = false }
        if s.arena_state.pressed {
            let candidate = usize(s.arena_state.candidate)
            let e = &s.elements[candidate]
            if e.live && e.kind == EDIT_TAG {
                let at = edit_hit(s, candidate, p.position)
                edit_move(e, at, true)
                ret ok
            }
            if e.live && e.kind == SLIDER_TAG {
                let value = slider_at(e, p.position)
                ret slider_set(s, candidate, value, e.second_held)
            }
            if e.live && e.kind == SCROLLBAR_TAG {
                // The thumb follows the pointer: the viewport moves by the content's
                // share of the distance along the bar.
                let moved = axis_of(e, p.position) - axis_of(e, s.arena_state.last)
                s.arena_state.last = p.position
                let (found, count) = find_by_key(s, e.linked)
                if count == 0usize { ret ok }
                let v = &s.elements[usize(found.slot)]
                if v.kind != SCROLL_TAG || v.viewport_extent <= 0.0 { ret ok }
                var track = e.bounds.height
                if e.scroll_axis == .Horizontal { track = e.bounds.width }
                if track <= 0.0 { ret ok }
                ret scroll_by(s, usize(found.slot), moved * v.content_extent / track, false)
            }
            if e.live && e.kind == ZOOM_TAG {
                if !s.arena_state.dragging {
                    if distance_sq(p.position, s.arena_state.down) <= gesture_slop() * gesture_slop() { ret ok }
                    s.arena_state.dragging = true
                }
                let delta = geometry.Point { x: p.position.x - s.arena_state.last.x, y: p.position.y - s.arena_state.last.y }
                s.arena_state.last = p.position
                ret pan_by(s, candidate, delta)
            }
            if e.live && e.kind == SCROLL_TAG {
                if !s.arena_state.dragging {
                    if distance_sq(p.position, s.arena_state.down) <= gesture_slop() * gesture_slop() { ret ok }
                    s.arena_state.dragging = true
                }
                let moved = axis_of(e, s.arena_state.last) - axis_of(e, p.position)
                s.arena_state.last = p.position
                e.scroll_velocity = moved
                ret scroll_by(s, candidate, moved, true)
            }
            if !e.live || e.kind != REGION_TAG {
                s.arena_state.pressed = false
                ret ok
            }
            if !s.arena_state.dragging {
                // Past the slop the gesture is a drag, if the region takes one; else
                // the pointer is released to whatever scrolls.
                if distance_sq(p.position, s.arena_state.down) > gesture_slop() * gesture_slop() {
                    if (e.gestures & GESTURE_DRAG) == 0u8 {
                        // Released to the viewport above the region, which drags from here.
                        let (viewport, has_viewport) = scroll_ancestor(s, candidate)
                        s.arena_state.pressed = false
                        if has_viewport {
                            s.arena_state.pressed = true
                            s.arena_state.candidate = u32(viewport)
                            s.arena_state.dragging = true
                            let moved = axis_of(&s.elements[viewport], s.arena_state.last) - axis_of(&s.elements[viewport], p.position)
                            s.arena_state.last = p.position
                            s.elements[viewport].scroll_velocity = moved
                            ret scroll_by(s, viewport, moved, true)
                        }
                        ret ok
                    }
                    s.arena_state.dragging = true
                    s.arena_state.last = p.position
                    ret fire_gesture(e.gesture, Gesture { DragStart: s.arena_state.down })
                }
                ret ok
            }
            let delta = geometry.Point { x: p.position.x - s.arena_state.last.x, y: p.position.y - s.arena_state.last.y }
            s.arena_state.last = p.position
            ret fire_gesture(e.gesture, Gesture { DragMove: Drag { start: s.arena_state.down, position: p.position, delta: delta } })
        }
        s.arena_state.last = p.position
        let (barred, bar_error) = menu_bar_hover(s, p.position)
        if barred || bar_error != ok { ret bar_error }
        // Hover: entering one region leaves the last; a modal overlay keeps the
        // pointer from what is under it. Cascading menus may move between their
        // two modal surfaces.
        var from = usize(s.root)
        let (top, top_inside, has_top) = menu_hover_overlay_at(s, p.position)
        if has_top {
            if !top_inside {
                menu_submenu_hover(s, p.position, top, false, 0usize, false)
                ret ok
            }
            from = top
        }
        let (over, has_over) = hit_region(s, from, p.position, GESTURE_HOVER)
        menu_submenu_hover(s, p.position, from, true, over, has_over)
        if s.arena_state.has_hovered && (!has_over || over != usize(s.arena_state.hovered)) {
            let previous = usize(s.arena_state.hovered)
            s.arena_state.has_hovered = false
            if s.elements[previous].live && s.elements[previous].kind == REGION_TAG {
                var leave: Gesture = .HoverEnd
                try fire_gesture(s.elements[previous].gesture, leave)
            }
        }
        if has_over {
            s.arena_state.hovered = u32(over)
            s.arena_state.has_hovered = true
            ret fire_gesture(s.elements[over].gesture, Gesture { Hover: p.position })
        }
        let (found, has_found) = hit_action(s, usize(s.root), p.position)
        if has_found {
            let action = s.elements[found].action
            ret action.invoke(action.ctx, event)
        }
    case .Scroll as p:
        s.has_long_press = false
        s.long_press_fired = false
        s.has_tooltip_touch = false
        s.has_rich_tooltip = false
        let (zoomed, has_zoomed) = hit_zoom(s, usize(s.root), p.position)
        if has_zoomed {
            // A notch scales by a tenth either way.
            let notches = f32(mem.bitcast[i32](p.device)) / 120.0
            var factor: f32 = 1.0
            if notches > 0.0 { factor = 1.1 }
            if notches < 0.0 { factor = 1.0 / 1.1 }
            ret zoom_by(s, zoomed, factor, p.position)
        }
        let (found, has_found) = hit_scroll(s, usize(s.root), p.position)
        if has_found {
            // The notch count rides in `device` as its bits (D797); a notch is 40 px.
            let notches = f32(mem.bitcast[i32](p.device)) / 120.0
            ret scroll_by(s, found, 0.0 - notches * 40.0, false)
        }
    case .KeyDown as k:
        // Enter or Space on a focused tap region is a tap at its centre.
        let code = key_code(k.key.physical)
        hold_modifier(s, code, true)
        if code == 27u32 && s.has_rich_tooltip {
            s.rich_dismissed_key = s.rich_anchor_key
            s.has_rich_dismissed = true
            s.has_rich_tooltip = false
        }
        if code == 27u32 { s.has_tooltip_touch = false }
        if menu_alt_key(code) {
            if !k.repeat {
                s.menu_alt_down = true
                s.menu_alt_used = false
            }
            ret ok
        }
        if s.menu_alt_down {
            s.menu_alt_used = true
            let (item_accessed, item_access_error) = menu_item_access_key(s, k.key.logical)
            if item_accessed || item_access_error != ok { ret item_access_error }
            let (accessed, access_error) = menu_bar_access_key(s, k.key.logical)
            if accessed || access_error != ok { ret access_error }
        }
        if s.has_focus {
            let f = &s.elements[usize(s.focus)]
            if f.live && f.kind == REGION_TAG && f.enabled && (f.gestures & GESTURE_TAP) != 0u8 && (code == 13u32 || code == 32u32) {
                ret menu_tap(s, usize(s.focus), geometry.Point { x: f.bounds.x + f.bounds.width * 0.5, y: f.bounds.y + f.bounds.height * 0.5 })
            }
        }
        let (taken, key_error) = dispatch_key(s, k)
        if taken || key_error != ok { ret key_error }
        if s.has_focus && s.elements[usize(s.focus)].has_action {
            let action = s.elements[usize(s.focus)].action
            ret action.invoke(action.ctx, event)
        }
    case .KeyUp as k:
        let code = key_code(k.key.physical)
        hold_modifier(s, code, false)
        if menu_alt_key(code) {
            let enter = s.menu_alt_down && !s.menu_alt_used
            s.menu_alt_down = false
            s.menu_alt_used = false
            if enter {
                var f10: input.KeyEvent = zero
                f10.key.physical = 121u32
                let (_, menu_error) = menu_bar_key(s, 121u32, f10)
                ret menu_error
            }
            ret ok
        }
        if s.has_focus && s.elements[usize(s.focus)].has_action {
            let action = s.elements[usize(s.focus)].action
            ret action.invoke(action.ctx, event)
        }
    case .Text as t:
        let (editor, has_editor) = focused_edit(s)
        if has_editor { ret edit_text_input(s, editor, t.text) }
        if s.has_focus && s.elements[usize(s.focus)].has_action {
            let action = s.elements[usize(s.focus)].action
            ret action.invoke(action.ctx, event)
        }
    case .Composition as c:
        let (editor, has_editor) = focused_edit(s)
        if has_editor { edit_compose(s, editor, c.text) }
        ret ok
    case .Frame as w:
        ret settle_scrolls(s)
    case .Close as w:
        ret ok
    case .Resize as m:
        s.has_tooltip_touch = false
        s.has_rich_tooltip = false
        ret ok
    case .Focus as w:
        ret ok
    case .Blur as w:
        s.held_modifiers.shift = false
        s.held_modifiers.control = false
        s.held_modifiers.alt = false
        s.held_modifiers.meta = false
        s.has_long_press = false
        s.long_press_fired = false
        s.has_tooltip_touch = false
        s.has_rich_tooltip = false
        ret ok
    case .Lifecycle as l:
        ret ok
    case .Insets as n:
        ret ok
    case .Back as w:
        // The mobile back gesture is Escape: the nearest cancel action from the focus.
        let (taken, back_error) = dispatch_key(s, input.KeyEvent { window: w, key: input.Key { physical: 27u32, logical: 27u32 }, modifiers: zero, repeat: false })
        ret back_error
    }
    ret ok
}

// An in-application drag (D844): a drag source's handler begins one with a
// payload on its drag start; the region under the release that takes drops
// (GESTURE_DROP) hears `Drop` with it; a drag is over at the release either way.
fn begin_drag(widget_runtime: *Runtime, payload: u64) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    s.drag_payload = payload
    s.has_drag = true
    ret ok
}

fn dragging(widget_runtime: *const Runtime) -> (u64, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize { ret (0u64, false) }
    ret (s.drag_payload, s.has_drag)
}

// A zoom view's scale and offset, for a harness or a caller.
fn zoom_state_of(widget_runtime: *const Runtime, element: ElementId) -> (ZoomState, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize { ret (zero, false) }
    let (index, found) = element_of(s, element)
    if !found || s.elements[index].kind != ZOOM_TAG { ret (zero, false) }
    ret (ZoomState { scale: s.elements[index].zoom_scale, offset: s.elements[index].zoom_offset }, true)
}

// The clipboard commands (D844) as an application's menu runs them: on the
// focused editor, copy and cut its selection and paste over it; `clipboard_commands`
// says which apply now; `clipboard_set` and `clipboard_get` move any text through
// the host's clipboard (the runtime's own fallback on a host without one).
type ClipboardCommands = struct { copy: bool, cut: bool, paste: bool }

fn clipboard_commands(widget_runtime: *Runtime) -> ClipboardCommands {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret zero }
    let (editor, has_editor) = focused_edit(s)
    if !has_editor { ret zero }
    let e = &s.elements[editor]
    let (lo, hi) = selection_of(e)
    let selected = hi > lo && !e.secret
    ret ClipboardCommands { copy: selected, cut: selected && !e.read_only, paste: !e.read_only }
}

fn clipboard_copy(widget_runtime: *Runtime) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (editor, has_editor) = focused_edit(s)
    if !has_editor { ret InvalidTree }
    edit_copy(s, &s.elements[editor])
    ret ok
}

fn clipboard_cut(widget_runtime: *Runtime) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (editor, has_editor) = focused_edit(s)
    if !has_editor { ret InvalidTree }
    let e = &s.elements[editor]
    if e.read_only { ret InvalidTree }
    edit_copy(s, e)
    let (lo, hi) = selection_of(e)
    ret edit_replace(s, editor, lo, hi, "", true)
}

fn clipboard_paste(widget_runtime: *Runtime) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (editor, has_editor) = focused_edit(s)
    if !has_editor { ret InvalidTree }
    if s.elements[editor].read_only { ret InvalidTree }
    ret edit_paste(s, editor)
}

fn clipboard_set(widget_runtime: *Runtime, value: str) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    var n = value.len
    if n > MAX_CLIP { n = MAX_CLIP }
    var k = 0usize
    while k < n {
        s.clip[k] = value[k]
        k += 1usize
    }
    s.clip_len = n
    s.clip_hosted = os.set_clipboard_text(value) == ok
    ret ok
}

fn clipboard_get(widget_runtime: *Runtime, a: *mem.Arena) -> (str, err) {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret ("", state_error) }
    if s.clip_hosted || s.clip_len == 0usize {
        let (host_text, host_error) = os.clipboard_text(a)
        if host_error == ok { ret (host_text, ok) }
    }
    let (copy, copy_error) = mem.alloc[u8](a, s.clip_len)
    if copy_error != ok { ret ("", copy_error) }
    var k = 0usize
    while k < s.clip_len {
        copy[k] = s.clip[k]
        k += 1usize
    }
    ret (copy[0usize..s.clip_len], ok)
}

// An editor's value and selection, for a harness.
fn edit_value(widget_runtime: *const Runtime, element: ElementId) -> (str, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || usize(element.slot) >= s.elements.len { ret ("", false) }
    let e = &s.elements[usize(element.slot)]
    if !e.live || e.generation != element.generation || e.kind != EDIT_TAG { ret ("", false) }
    let value: str = e.edit_buffer[0usize..e.edit_len]
    ret (value, true)
}

fn edit_selection(widget_runtime: *const Runtime, element: ElementId) -> (usize, usize, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || usize(element.slot) >= s.elements.len { ret (0usize, 0usize, false) }
    let e = &s.elements[usize(element.slot)]
    if !e.live || e.generation != element.generation || e.kind != EDIT_TAG { ret (0usize, 0usize, false) }
    let (lo, hi) = selection_of(e)
    ret (lo, hi, true)
}

// A viewport's offset, set (clamped to what was last placed) or read.
fn scroll_to(widget_runtime: *Runtime, element: ElementId, offset: f32) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (index, found) = element_of(s, element)
    if !found || s.elements[index].kind != SCROLL_TAG { ret InvalidTree }
    let e = &s.elements[index]
    var next = offset
    let most = max_f(e.content_extent - e.viewport_extent, 0.0)
    if next > most { next = most }
    if next < 0.0 { next = 0.0 }
    e.scroll_offset = next
    e.scroll_velocity = 0.0
    e.invalid = true
    ret ok
}

fn scroll_offset_of(widget_runtime: *const Runtime, element: ElementId) -> (f32, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed { ret (0.0, false) }
    let (index, found) = element_of(s, element)
    if !found || s.elements[index].kind != SCROLL_TAG { ret (0.0, false) }
    ret (s.elements[index].scroll_offset, true)
}

// The items of a lazy viewport worth building at `offset`: the first and how many,
// one beyond each end of the view for overscan.
fn visible_range(offset: f32, viewport: f32, count: usize, extent: f32) -> (usize, usize) {
    if count == 0usize || extent <= 0.0 { ret (0usize, 0usize) }
    var first = 0usize
    if offset > extent { first = usize(offset / extent) - 1usize }
    var end = usize((offset + viewport) / extent) + 2usize
    if end > count { end = count }
    if first >= end { ret (first, 0usize) }
    ret (first, end - first)
}

// A platform action performed on an element that offers it: its bit to `on_action`.
fn semantic_action(widget_runtime: *Runtime, element: ElementId, bit: u32) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (index, found) = element_of(s, element)
    if !found { ret InvalidTree }
    let e = &s.elements[index]
    if !e.has_semantics || (e.sem.actions & bit) == 0u32 { ret InvalidTree }
    ret fire_change[u32](e.sem.on_action, bit)
}

// An editor's value replaced, and its selection set, by the platform.
fn edit_set(widget_runtime: *Runtime, element: ElementId, value: str) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (index, found) = element_of(s, element)
    if !found || s.elements[index].kind != EDIT_TAG || s.elements[index].read_only { ret InvalidTree }
    if value.len > s.elements[index].edit_buffer.len { ret TooLarge }
    s.compose_len = 0usize
    ret edit_replace(s, index, 0usize, s.elements[index].edit_len, value, true)
}

fn edit_select(widget_runtime: *Runtime, element: ElementId, start: usize, end: usize) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (index, found) = element_of(s, element)
    if !found || s.elements[index].kind != EDIT_TAG { ret InvalidTree }
    let e = &s.elements[index]
    if start > end || end > e.edit_len { ret InvalidTree }
    e.anchor = start
    e.caret = end
    e.invalid = true
    ret ok
}

// Copy an editor, or the direct editor child of a semantic wrapper.
fn edit_copy_child(widget_runtime: *Runtime, element: ElementId) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (index, found) = element_of(s, element)
    if !found { ret InvalidTree }
    var at = index
    if s.elements[at].kind != EDIT_TAG {
        if !s.elements[at].has_child { ret InvalidTree }
        at = usize(s.elements[at].first_child)
    }
    if s.elements[at].kind != EDIT_TAG { ret InvalidTree }
    edit_copy(s, &s.elements[at])
    ret ok
}

// An overlay's content bounds, for a harness.
fn overlay_bounds_of(widget_runtime: *const Runtime, element: ElementId) -> (geometry.Rect, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed { ret (zero, false) }
    let (index, found) = element_of(s, element)
    if !found || s.elements[index].kind != OVERLAY_TAG { ret (zero, false) }
    ret (s.elements[index].overlay_bounds, true)
}

// What the pointer and the focus are doing to an element, for the look a control
// resolves from its state (D818): hovered, pressed (the arena's candidate while the
// pointer is down) and focused; nothing for an element that is not there.
type Interaction = struct { hovered: bool, pressed: bool, focused: bool, focus_visible: bool }

fn interaction(widget_runtime: *const Runtime, key: Key) -> Interaction {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed { ret zero }
    let (found, count) = find_by_key(s, key)
    if count == 0usize { ret zero }
    let index = usize(found.slot)
    ret Interaction { hovered: s.arena_state.has_hovered && usize(s.arena_state.hovered) == index, pressed: s.arena_state.pressed && usize(s.arena_state.candidate) == index, focused: s.has_focus && usize(s.focus) == index, focus_visible: s.has_focus && s.focus_visible && usize(s.focus) == index }
}

// Plain tooltips wait 500 ms for the first hovered anchor. Once one has shown,
// another hovered within 1500 ms appears immediately (the toolbar sweep).
// Keyboard focus remains immediate; pressing hides the tooltip.
fn touch_tooltip_wanted(s: *State, key: Key) -> bool {
    let now = s.animation_time.nanos
    if s.has_tooltip_touch && s.tooltip_touch_anchor == key {
        if s.tooltip_touch_shown {
            if !s.tooltip_touch_released { ret true }
            if now >= s.tooltip_touch_release_at && now - s.tooltip_touch_release_at >= 1500000000i64 {
                s.has_tooltip_touch = false
                s.tooltip_touch_shown = false
                ret false
            }
            s.animation_due = true
            ret true
        }
        if !s.arena_state.pressed || s.arena_state.dragging {
            s.has_tooltip_touch = false
            ret false
        }
    }
    let (found, count) = find_by_key(s, key)
    if count != 1usize || !s.arena_state.pressed || s.arena_state.dragging || !geometry.contains(s.elements[usize(found.slot)].bounds, s.arena_state.down) { ret false }
    if !s.has_tooltip_touch || s.tooltip_touch_anchor != key {
        s.tooltip_touch_anchor = key
        s.has_tooltip_touch = true
        s.tooltip_touch_at = now
        s.tooltip_touch_shown = false
        s.tooltip_touch_released = false
    }
    if now < s.tooltip_touch_at || now - s.tooltip_touch_at < 500000000i64 {
        s.animation_due = true
        ret false
    }
    s.tooltip_touch_shown = true
    ret true
}

fn tooltip_wanted(widget_runtime: *Runtime, key: Key, touch: bool) -> bool {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret false }
    if touch { ret touch_tooltip_wanted(s, key) }
    let current = interaction(widget_runtime, key)
    let now = s.animation_time.nanos
    if current.focus_visible {
        s.tooltip_anchor = key
        s.has_tooltip_anchor = true
        s.tooltip_hover_at = now - 500000000i64
        s.tooltip_seen_at = now
        ret true
    }
    if !current.hovered || current.pressed {
        if s.has_tooltip_anchor && s.tooltip_anchor == key {
            if now >= s.tooltip_hover_at && now - s.tooltip_hover_at >= 500000000i64 {
                s.tooltip_last_at = now
                s.has_tooltip_last = true
            }
            s.has_tooltip_anchor = false
        }
        ret false
    }
    if !s.has_tooltip_anchor || s.tooltip_anchor != key {
        var sweep = s.has_tooltip_last && now >= s.tooltip_last_at && now - s.tooltip_last_at <= 1500000000i64
        if s.has_tooltip_anchor && now >= s.tooltip_hover_at && now - s.tooltip_hover_at >= 500000000i64 && now >= s.tooltip_seen_at && now - s.tooltip_seen_at <= 1500000000i64 { sweep = true }
        s.tooltip_anchor = key
        s.has_tooltip_anchor = true
        s.tooltip_hover_at = now
        if sweep { s.tooltip_hover_at = now - 500000000i64 }
    }
    s.tooltip_seen_at = now
    if now < s.tooltip_hover_at || now - s.tooltip_hover_at < 500000000i64 {
        s.animation_due = true
        ret false
    }
    ret true
}

fn pointer_within_key(s: *State, key: Key) -> bool {
    if !s.has_pointer { ret false }
    let (found, count) = find_by_key(s, key)
    if count != 1usize { ret false }
    ret geometry.contains(s.elements[usize(found.slot)].bounds, s.arena_state.last)
}

// Rich tooltips use the same 500 ms first-hover delay as plain ones, remain
// while the pointer is over either surface or focus is within either, and keep
// a 300 ms bridge while the pointer crosses their 4px gap.
fn rich_tooltip_wanted(widget_runtime: *Runtime, anchor: Key, tooltip: Key) -> bool {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret false }
    let now = s.animation_time.nanos
    let anchor_pointed = pointer_within_key(s, anchor)
    let tooltip_pointed = pointer_within_key(s, tooltip)
    let anchor_focused = s.focus_visible && focus_within(widget_runtime, anchor)
    let tooltip_focused = focus_within(widget_runtime, tooltip)
    if s.has_rich_dismissed && s.rich_dismissed_key == anchor {
        if anchor_pointed || anchor_focused { ret false }
        s.has_rich_dismissed = false
    }
    if !s.has_rich_tooltip || s.rich_anchor_key != anchor || s.rich_tooltip_key != tooltip {
        s.rich_anchor_key = anchor
        s.rich_tooltip_key = tooltip
        s.has_rich_tooltip = anchor_pointed || anchor_focused
        s.rich_tooltip_shown = anchor_focused
        s.rich_hover_at = now
        s.rich_leaving = false
    }
    if !s.has_rich_tooltip { ret false }
    if !s.rich_tooltip_shown {
        if anchor_focused { s.rich_tooltip_shown = true }
        if !anchor_pointed && !anchor_focused {
            s.has_rich_tooltip = false
            ret false
        }
        if !s.rich_tooltip_shown && (now < s.rich_hover_at || now - s.rich_hover_at < 500000000i64) {
            s.animation_due = true
            ret false
        }
        s.rich_tooltip_shown = true
    }
    if anchor_pointed || tooltip_pointed || anchor_focused || tooltip_focused {
        s.rich_leaving = false
        ret true
    }
    if !s.rich_leaving {
        s.rich_leave_at = now
        s.rich_leaving = true
    }
    if now >= s.rich_leave_at && now - s.rich_leave_at >= 300000000i64 {
        s.has_rich_tooltip = false
        s.rich_tooltip_shown = false
        s.rich_leaving = false
        ret false
    }
    s.animation_due = true
    ret true
}

// Fire `action` once when a primary press has stayed inside `key` for 500 ms.
// The caller asks during each build; the runtime requests those builds and then
// consumes the release so the target's ordinary tap does not also run.
fn long_press(widget_runtime: *Runtime, key: Key, action: *const Submit) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (found, count) = find_by_key(s, key)
    if count == 0usize || !s.arena_state.pressed || s.arena_state.dragging || !geometry.contains(s.elements[usize(found.slot)].bounds, s.arena_state.down) {
        if s.has_long_press && s.long_press_key == key {
            s.has_long_press = false
            s.long_press_fired = false
        }
        ret ok
    }
    let now = s.animation_time.nanos
    if !s.has_long_press || s.long_press_key != key {
        s.long_press_key = key
        s.has_long_press = true
        s.long_press_at = now
        s.long_press_fired = false
    }
    if s.long_press_fired { ret ok }
    if now < s.long_press_at || now - s.long_press_at < 500000000i64 {
        s.animation_due = true
        ret ok
    }
    s.long_press_fired = true
    s.animation_due = true
    if s.has_long_press_feedback { let _ = fire_submit(s.long_press_feedback) }
    ret fire_submit(*action)
}

// Whether focus is on the keyed element or one of its descendants.
fn focus_within(widget_runtime: *const Runtime, key: Key) -> bool {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed || !s.has_focus { ret false }
    let (found, count) = find_by_key(s, key)
    if count == 0usize { ret false }
    let root = usize(found.slot)
    ret usize(s.focus) == root || descends_from(s, usize(s.focus), root)
}

// A slider's values, for a harness.
fn slider_value_of(widget_runtime: *const Runtime, element: ElementId) -> (f32, f32, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed { ret (0.0, 0.0, false) }
    let (index, found) = element_of(s, element)
    if !found || s.elements[index].kind != SLIDER_TAG { ret (0.0, 0.0, false) }
    ret (s.elements[index].slider_value, s.elements[index].slider_second, true)
}

// The element that has the focus, for a harness or a control.
fn focused(widget_runtime: *const Runtime) -> (ElementId, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || !s.has_focus { ret (zero, false) }
    ret (ElementId { slot: s.focus, generation: s.elements[usize(s.focus)].generation }, true)
}

// Modifier keys currently held by the host, for pointer gestures whose compact
// event payload is only a position.
fn modifiers(widget_runtime: *const Runtime) -> input.Modifiers {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed { ret zero }
    ret s.held_modifiers
}

// ---------------------------------------------------------- the harness's view

// The element whose key or text matches, for `e.ui.testing`: a preorder walk.
fn find_by_key(s: *State, key: Key) -> (ElementId, usize) {
    var count = 0usize
    var found: ElementId = zero
    var i = 0usize
    while i < s.elements.len {
        let e = &s.elements[i]
        if e.live && e.key == key {
            if count == 0usize { found = ElementId { slot: u32(i), generation: e.generation } }
            count += 1usize
        }
        i += 1usize
    }
    ret (found, count)
}

fn find_by_text(s: *State, value: str) -> (ElementId, usize) {
    var count = 0usize
    var found: ElementId = zero
    var i = 0usize
    while i < s.elements.len {
        let e = &s.elements[i]
        if e.live && e.text_len == value.len && e.text_len != 0usize {
            var same = true
            var k = 0usize
            while k < value.len {
                if e.text[k] != value[k] { same = false }
                k += 1usize
            }
            if same {
                if count == 0usize { found = ElementId { slot: u32(i), generation: e.generation } }
                count += 1usize
            }
        }
        i += 1usize
    }
    ret (found, count)
}

// What an accessibility tree needs of an element: its identity, kind tag, parent,
// bounds, action, enabling, focus and text, the text borrowed from the runtime
// until the element changes. `false` for a slot that holds no live element.
type Summary = struct { id: ElementId, kind: u8, parent: ElementId, has_parent: bool, bounds: geometry.Rect, has_action: bool, enabled: bool, focused: bool, text: str, first_child: ElementId, has_child: bool, next_sibling: ElementId, has_sibling: bool, semantics: Semantics, has_semantics: bool, value: str, selection_start: usize, selection_end: usize, read_only: bool, focusable: bool }

// The visible tooltip that describes this semantic element through an anchored
// overlay, if any. This keeps the relation with the tooltip instead of every caller.
fn tooltip_description(widget_runtime: *const Runtime, slot: usize) -> (ElementId, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || slot >= s.elements.len { ret (zero, false) }
    var i = 0usize
    while i < s.overlay_count {
        let layer_slot = usize(s.overlays[i])
        let layer = &s.elements[layer_slot]
        if layer.live && layer.kind == OVERLAY_TAG && layer.linked != 0u64 {
            let (anchor, count) = find_by_key(s, layer.linked)
            let anchor_slot = usize(anchor.slot)
            if count == 1usize && (anchor_slot == slot || descends_from(s, anchor_slot, slot)) {
                let (description, found) = semantic_role_under(s, layer_slot, 27u8)
                if found { ret (ElementId { slot: u32(description), generation: s.elements[description].generation }, true) }
            }
        }
        i += 1usize
    }
    ret (zero, false)
}

fn element_count(widget_runtime: *const Runtime) -> usize {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize { ret 0usize }
    ret s.elements.len
}

fn root_of(widget_runtime: *const Runtime) -> (ElementId, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || !s.has_root { ret (zero, false) }
    ret (ElementId { slot: s.root, generation: s.elements[usize(s.root)].generation }, true)
}

fn summary_at(widget_runtime: *const Runtime, slot: usize) -> (Summary, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || slot >= s.elements.len { ret (zero, false) }
    let e = &s.elements[slot]
    if !e.live { ret (zero, false) }
    var summary: Summary = zero
    summary.id = ElementId { slot: u32(slot), generation: e.generation }
    summary.kind = e.kind
    summary.has_parent = e.has_parent
    if e.has_parent { summary.parent = ElementId { slot: e.parent, generation: s.elements[usize(e.parent)].generation } }
    summary.bounds = e.bounds
    summary.has_action = e.has_action
    summary.enabled = e.enabled
    summary.focusable = focusable(e)
    summary.focused = s.has_focus && usize(s.focus) == slot
    summary.text = e.text[0usize..e.text_len]
    summary.has_semantics = e.has_semantics
    if e.has_semantics {
        summary.semantics = e.sem
        summary.semantics.label = e.text[0usize..e.text_len]
        summary.semantics.value = e.value[0usize..e.value_len]
        summary.semantics.hint = e.hint[0usize..e.hint_len]
    }
    if e.kind == EDIT_TAG {
        summary.value = e.edit_buffer[0usize..e.edit_len]
        let (lo, hi) = selection_of(e)
        summary.selection_start = lo
        summary.selection_end = hi
        summary.read_only = e.read_only
    }
    summary.has_child = e.has_child
    if e.has_child { summary.first_child = ElementId { slot: e.first_child, generation: s.elements[usize(e.first_child)].generation } }
    summary.has_sibling = e.has_sibling
    if e.has_sibling { summary.next_sibling = ElementId { slot: e.next_sibling, generation: s.elements[usize(e.next_sibling)].generation } }
    ret (summary, true)
}

// The renderer and its queue, for a harness that draws without a window.
fn renderer_of(widget_runtime: *Runtime) -> *scene.Renderer {
    let s = mem.cast[*State](widget_runtime.state)
    ret s.renderer
}

fn queue_of(widget_runtime: *Runtime) -> *gpu.Queue {
    let s = mem.cast[*State](widget_runtime.state)
    ret scene.queue_of(s.renderer)
}

// The bounds of an element, for a harness or an accessibility tree.
fn bounds_of(widget_runtime: *const Runtime, element: ElementId) -> (geometry.Rect, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed { ret (zero, false) }
    let (index, found) = element_of(s, element)
    if !found { ret (zero, false) }
    ret (s.elements[index].bounds, true)
}

// Last reconciled bounds for a key, and the current logical surface size.
fn bounds_for_key(widget_runtime: *const Runtime, key: Key) -> (geometry.Rect, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed { ret (zero, false) }
    let (found, count) = find_by_key(s, key)
    if count != 1usize { ret (zero, false) }
    ret (s.elements[usize(found.slot)].bounds, true)
}

fn surface_size(widget_runtime: *const Runtime) -> geometry.Size {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed { ret zero }
    ret s.window_size
}

// ------------------------------------------------ the algorithms of the tree (D904)
//
// Five of docs/algos.md's names over the runtime's element tree: the topmost
// element under a point, a scroll anchor held across a rebuild, a keyed
// reconciliation as a pure match of old keys to new, an intersection test for
// lazy loading, and the row window of a virtualised list.

fn hit_deepest(s: *State, index: usize, p: geometry.Point) -> (usize, bool) {
    let e = &s.elements[index]
    if !e.live || !geometry.contains(e.bounds, p) { ret (0usize, false) }
    var order: [64]u32 = zero
    var count = 0usize
    var at = e.first_child
    var has = e.has_child
    while has && count < 64usize {
        order[count] = at
        count += 1usize
        let child = &s.elements[usize(at)]
        has = child.has_sibling
        at = child.next_sibling
    }
    while count > 0usize {
        count = count - 1usize
        let (found, has_found) = hit_deepest(s, usize(order[count]), p)
        if has_found { ret (found, true) }
    }
    ret (index, true)
}

// The topmost live element under `p`: the front overlay first, the root last,
// and within each the deepest child drawn last.
fn hit_test(widget_runtime: *const Runtime, p: geometry.Point) -> (ElementId, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed || !s.has_root { ret (zero, false) }
    var o = s.overlay_count
    while o > 0usize {
        o -= 1usize
        let (found, has_found) = hit_deepest(s, usize(s.overlays[o]), p)
        if has_found { ret (ElementId { slot: u32(found), generation: s.elements[found].generation }, true) }
    }
    let (found, has_found) = hit_deepest(s, usize(s.root), p)
    if !has_found { ret (zero, false) }
    ret (ElementId { slot: u32(found), generation: s.elements[found].generation }, true)
}

// The anchor kept where it was: after a rebuild moved content above it, the
// viewport scrolls by the anchor's displacement from `previous_top` (its top
// relative to the viewport before the rebuild); the displacement is answered.
fn scroll_anchor(widget_runtime: *Runtime, viewport: ElementId, anchor: ElementId, previous_top: f32) -> (f32, err) {
    let (viewport_bounds, has_viewport) = bounds_of(widget_runtime, viewport)
    let (anchor_bounds, has_anchor) = bounds_of(widget_runtime, anchor)
    if !has_viewport || !has_anchor { ret (0.0, InvalidTree) }
    let (offset, has_offset) = scroll_offset_of(widget_runtime, viewport)
    if !has_offset { ret (0.0, InvalidTree) }
    let delta = (anchor_bounds.y - viewport_bounds.y) - previous_top
    if delta == 0.0 { ret (0.0, ok) }
    let scrolled = scroll_to(widget_runtime, viewport, offset + delta)
    if scrolled != ok { ret (0.0, scrolled) }
    ret (delta, ok)
}

// For each new key, the old index it matches, so that a node moves rather than
// being remade; a key without a match is new. ponytail: a quadratic scan, which
// the lists this serves (hundreds) never notice; a map when one does.
type KeyedMatch = struct { old_index: usize, found: bool }

fn reconcile_keyed(a: *mem.Arena, old: []const Key, new: []const Key) -> ([]KeyedMatch, err) {
    var nothing: []KeyedMatch = zero
    let (matches, allocation_error) = mem.alloc[KeyedMatch](a, new.len)
    if allocation_error != ok { ret (nothing, allocation_error) }
    var at = 0usize
    while at < new.len {
        matches[at] = KeyedMatch { old_index: 0usize, found: false }
        var o = 0usize
        while o < old.len {
            if old[o] == new[at] {
                matches[at] = KeyedMatch { old_index: o, found: true }
                break
            }
            o += 1usize
        }
        at += 1usize
    }
    ret (matches[0usize..new.len], ok)
}

// Whether an element is within `margin` of a viewport, which is when its
// resource is worth loading.
fn lazy_load(widget_runtime: *const Runtime, element: ElementId, viewport: ElementId, margin: f32) -> bool {
    let (element_bounds, has_element) = bounds_of(widget_runtime, element)
    let (viewport_bounds, has_viewport) = bounds_of(widget_runtime, viewport)
    if !has_element || !has_viewport { ret false }
    let near = geometry.Rect { x: viewport_bounds.x - margin, y: viewport_bounds.y - margin, width: viewport_bounds.width + margin * 2.0, height: viewport_bounds.height + margin * 2.0 }
    let overlap = geometry.intersect(near, element_bounds)
    ret overlap.width > 0.0 && overlap.height > 0.0
}

// The rows a viewport of `extent` at `offset` shows, `overscan` more on each
// side, as `first` up to `end`; every row is `row_height` tall.
type RowRange = struct { first: usize, end: usize }

fn virtual_list(extent: f32, offset: f32, row_height: f32, count: usize, overscan: usize) -> RowRange {
    if count == 0usize || !(row_height > 0.0) || !(extent >= 0.0) { ret RowRange { first: 0usize, end: 0usize } }
    var top = offset
    if top < 0.0 { top = 0.0 }
    var first = usize(top / row_height)
    var end = usize((top + extent) / row_height) + 1usize
    if first > overscan { first -= overscan } else { first = 0usize }
    end += overscan
    if end > count { end = count }
    if first > end { first = end }
    ret RowRange { first: first, end: end }
}
