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
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
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
type Custom = struct { ctx: *void, measure: fn(*void, ui_layout.Constraints) -> geometry.Size, paint: fn(*void, *scene.Builder, geometry.Rect) -> err }
// Typed actions (D806, widget plan P0-02): a change carries a value of its type, a
// submit carries nothing; `ctx` outlives the element and never points into the
// frame arena. An unset action is a no-op.
type Change[T: type] = struct { ctx: *void, invoke: fn(*void, T) -> err }
type Submit = struct { ctx: *void, invoke: fn(*void) -> err }
// A gesture the arena settled on: a tap, a drag from its start through its moves to
// its end, a hover entering and leaving. Positions are logical pixels.
type Drag = struct { start: geometry.Point, position: geometry.Point, delta: geometry.Point }
type Gesture = union enum u8 { Tap: geometry.Point, DragStart: geometry.Point, DragMove: Drag, DragEnd: geometry.Point, Hover: geometry.Point, HoverEnd }
type GestureAction = struct { ctx: *void, invoke: fn(*void, Gesture) -> err }
// The gestures a region takes part in, as bits: 1 tap, 2 drag, 4 hover.
type Region = struct { gesture: GestureAction, gestures: u8, enabled: bool, focusable: bool }
type Shortcut = struct { key: u32, modifiers: input.Modifiers, action: Submit }
// A focus and shortcut scope: Tab and Shift+Tab travel its focusable descendants
// (and, trapping, never leave it); a key down that matches one of its shortcuts
// fires it; Enter fires the default action and Escape the cancel one.
type Scope = struct { traps_focus: bool, shortcuts: []const Shortcut, default_action: Submit, cancel_action: Submit }
// An editable text (D807, widget plan P0-04): the caller owns `buffer` and `len`
// bytes of it are the value; the runtime edits in place -- caret, selection, typed
// text, IME composition, clipboard, undo -- and reports every change as the new
// value through `change`; Enter in a single-line editor fires `submit`. A `len`
// the caller changes between frames replaces the value; one it leaves alone keeps
// the runtime's edits.
type Edit = struct { buffer: []u8, len: usize, style: layout.Style, color: paint.Color, selection: paint.Color, change: Change[str], submit: Submit, enabled: bool, read_only: bool, multiline: bool }
// Semantics (D809, widget plan P0-06): what an element says of itself to the
// accessibility tree beyond what its kind implies. `role` is `e.ui.accessibility`'s
// role code (0 keeps the kind's); the label, value and hint are copied into the
// element (64, 32 and 32 bytes); `states`, `actions` and `live` are that module's
// bits and codes; relationships name other elements by key (0 for none); `row` and
// `column` place the element in a collection of `row_count` by `column_count`;
// `level` is a heading's or a tree item's depth; a hidden element and its subtree
// leave the tree. A platform action the element offers reaches `on_action` as its bit.
type Semantics = struct { role: u8, label: str, value: str, hint: str, states: u32, actions: u32, live: u8, level: u8, labelled_by: Key, described_by: Key, error_by: Key, controls: Key, active: Key, row: u32, column: u32, row_count: u32, column_count: u32, hidden: bool, on_action: Change[u32] }
// An overlay (D810, widget plan P0-07): its children leave the flow and paint at the
// root level, last, stacked against the element `anchor` names by key (0: the
// window) with `placement` and `offset`, kept inside the window. A modal overlay
// takes the focus when it appears and gives it back when it goes, bounds Tab to its
// subtree, keeps the pointer from what is under it, and a press outside it fires
// `dismiss`. Overlays stack in tree order; the last is on top.
type Placement = enum u8 { Below, Above, Right, Left, Center }
type Overlay = struct { anchor: Key, placement: Placement, offset: geometry.Point, modal: bool, dismiss: Submit }
type Kind = union enum u8 { Box, Flex: ui_layout.Flex, Grid: ui_layout.Grid, Stack, Text: Text, Button: Button, Image: Image, Scroll: Scroll, Custom: Custom, Region: Region, Scope: Scope, Edit: Edit, Semantics: Semantics, Overlay: Overlay, Wrap: ui_layout.Wrap }
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

type Cell = struct { live: bool, generation: u32, offset: usize, size: usize, align: usize, owner: u32 }
type Element = struct {
    live: bool,
    generation: u32,
    key: Key,
    kind: u8,
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
    scroll_change: Change[f32],
    overscroll: Overscroll,
    momentum: bool,
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
type State = struct {
    arena: *mem.Arena,
    renderer: *scene.Renderer,
    limits: Limits,
    elements: []Element,
    cells: []Cell,
    storage: []u8,
    storage_used: usize,
    root: u32,
    has_root: bool,
    focus: u32,
    has_focus: bool,
    frame: u64,
    scene_id: scene.SceneId,
    has_scene: bool,
    closed: bool,
    arena_state: Arena,
    // Editing: a scratch region for hit-test layouts, the composition (preedit) of
    // the focused editor, the fallback clipboard for a host without one, and the
    // undo history -- entries and their byte pool -- with the redo point.
    scratch: []u8,
    compose: [64]u8,
    compose_len: usize,
    clip: [256]u8,
    clip_len: usize,
    clip_hosted: bool,
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

fn positioned(key: Key, x: f32, y: f32, value_style: style.Style, children: []const Node) -> Node {
    var placed = value_style
    placed.position = .Absolute
    placed.margin = style.EdgeLengths { left: style.Length { Px: x }, top: style.Length { Px: y }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    ret box(key, placed, children)
}

// Whether a function value is set: its bits are not zero, read through a pun.
type SubmitBits = union { function: fn(*void) -> err, bits: usize }
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
    var s: State = zero
    s.arena = a
    s.renderer = renderer
    s.limits = limits
    s.elements = elements
    s.cells = cells
    s.storage = storage
    s.scratch = scratch
    states[0usize] = s
    ret (Runtime { state: mem.cast[*void](&states[0usize]) }, ok)
}

fn state_of(widget_runtime: *Runtime) -> (*State, err) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed { ret (s, InvalidTree) }
    ret (s, ok)
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
            ret (mem.cast[*T](&s.storage[c.offset]), id, ok)
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

fn focus(widget_runtime: *Runtime, element: ElementId) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    let (index, found) = element_of(s, element)
    if !found { ret InvalidTree }
    s.focus = u32(index)
    s.has_focus = true
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
    case .Overlay as ov:
        e.enabled = true
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
    i = 0usize
    while i < node.children.len {
        let (child, child_error) = reconcile_node(s, &node.children[i], index, true, i, old_children[0usize..old_count], depth + 1usize)
        if child_error != ok { ret (0usize, child_error) }
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
fn measure(s: *State, a: *mem.Arena, node: *const Node, limits: ui_layout.Constraints) -> (geometry.Size, err) {
    let margin = edges_px(node.style.margin, limits.max_width)
    let padding = edges_px(node.style.padding, limits.max_width)
    let horizontal_extra = margin.left + margin.right + padding.left + padding.right
    let vertical_extra = margin.top + margin.bottom + padding.top + padding.bottom
    var inner = ui_layout.Constraints { min_width: 0.0, max_width: limits.max_width - horizontal_extra, min_height: 0.0, max_height: limits.max_height - vertical_extra }
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
        let (laid, layout_error) = layout.layout(a, t.value, t.style, layout.Options { width: inner.max_width, max_lines: t.max_lines, align: t.align, wrap: t.wrap, ellipsis: t.ellipsis })
        if layout_error != ok { ret (zero, InvalidTree) }
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
    e.bounds = bounds
    e.invalid = false
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
    // The shadow lies under everything, the background's shape at its offset.
    if node.style.shadow.color.alpha > 0.0 {
        let shifted = geometry.Rect { x: bounds.x + node.style.shadow.offset.x, y: bounds.y + node.style.shadow.offset.y, width: bounds.width, height: bounds.height }
        try fill_shape(a, b, shifted, radius, paint.Brush { Solid: node.style.shadow.color })
    }
    if clipped {
        try scene.push(b, save)
        if radius > 0.0 {
            try scene.push(b, scene.Command { Clip: scene.Clip { Rounded: rounded(bounds, radius) } })
        } else {
            try scene.push(b, scene.Command { Clip: scene.Clip { Rect: bounds } })
        }
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
    if paint_background { try fill_shape(a, b, bounds, radius, background) }
    // The border is stroked inside the bounds, on the rounded shape when there is one.
    if node.style.border.width > 0.0 && node.style.border.color.alpha > 0.0 {
        let half = node.style.border.width * 0.5
        let inset = geometry.Rect { x: bounds.x + half, y: bounds.y + half, width: max_f(bounds.width - node.style.border.width, 0.0), height: max_f(bounds.height - node.style.border.width, 0.0) }
        let (outline, outline_error) = rounded_path(a, inset, max_f(radius - half, 0.0))
        if outline_error != ok { ret TooLarge }
        try scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: outline, brush: paint.Brush { Solid: node.style.border.color }, stroke: paint.Stroke { width: node.style.border.width, cap: .Butt, join: .Miter, miter_limit: 4.0 } } })
    }
    switch node.kind {
    case .Text as t:
        if t.style.fonts.len == 0usize { ret finish_place(b, clipped, layered) }
        let (laid, layout_error) = layout.layout(a, t.value, t.style, layout.Options { width: inner.width, max_lines: t.max_lines, align: t.align, wrap: t.wrap, ellipsis: t.ellipsis })
        if layout_error != ok { ret InvalidTree }
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
    ret finish_place(b, clipped, layered)
}

fn edit_options(width: f32, multiline: bool) -> layout.Options {
    var wrapping: layout.Wrap = .None
    if multiline { wrapping = .Word }
    ret layout.Options { width: width, max_lines: 0u32, align: .Start, wrap: wrapping, ellipsis: "" }
}

// The text an editor shows: its value, with the composition at the caret when it is
// the focused one.
fn edit_display(s: *State, a: *mem.Arena, e: *const Element, composing: bool) -> (str, err) {
    let value: str = e.edit_buffer[0usize..e.edit_len]
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
        try push_rect(b, geometry.Rect { x: c.x, y: c.y, width: 1.0, height: c.height }, origin, ed.color)
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
    let offset = e.scroll_offset
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
        let viewport = e.viewport_extent
        var length = viewport * viewport / content
        if length < 8.0 { length = 8.0 }
        var at = offset / content * viewport
        if at > viewport - length { at = viewport - length }
        if at < 0.0 { at = 0.0 }
        var thumb = geometry.Rect { x: inner.x + inner.width - 4.0, y: inner.y + at, width: 4.0, height: length }
        if !vertical { thumb = geometry.Rect { x: inner.x + at, y: inner.y + inner.height - 4.0, width: length, height: 4.0 } }
        try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: thumb, brush: paint.Brush { Solid: sc.thumb } } })
    }
    try scene.push(b, restore)
    ret ok
}

// Where an overlay's content of `size` goes against its anchor, kept in the window.
fn overlay_rect(anchor: geometry.Rect, size: geometry.Size, ov: Overlay, window_size: geometry.Size) -> geometry.Rect {
    var x = anchor.x
    var y = anchor.y
    if ov.placement == .Below { y = anchor.y + anchor.height }
    if ov.placement == .Above { y = anchor.y - size.height }
    if ov.placement == .Right { x = anchor.x + anchor.width }
    if ov.placement == .Left { x = anchor.x - size.width }
    if ov.placement == .Center {
        x = (window_size.width - size.width) * 0.5
        y = (window_size.height - size.height) * 0.5
    }
    x += ov.offset.x
    y += ov.offset.y
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
        let open = ui_layout.Constraints { min_width: 0.0, max_width: s.window_size.width, min_height: 0.0, max_height: s.window_size.height }
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

// A rectangle filled, rounded when it has a radius.
fn fill_shape(a: *mem.Arena, b: *scene.Builder, r: geometry.Rect, radius: f32, brush: paint.Brush) -> err {
    if radius <= 0.0 { ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: r, brush: brush } }) }
    let (outline, outline_error) = rounded_path(a, r, radius)
    if outline_error != ok { ret TooLarge }
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: outline, brush: brush } })
}

// The Restores that close what `place` opened.
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
    let (result, layout_error) = ui_layout.flex(a, spec, limits, children)
    if layout_error != ok { ret InvalidTree }
    var i = 0usize
    while i < node.children.len {
        let r = result.children[i]
        try place(s, a, &node.children[i], child_element(s, element, i), geometry.Rect { x: inner.x + r.x, y: inner.y + r.y, width: r.width, height: r.height }, b, depth + 1usize)
        i += 1usize
    }
    ret ok
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
            var order: [64]u32 = zero
            let count = collect_focusable(s, overlay_element, order[..], 0usize)
            if count > 0usize {
                s.focus = order[0usize]
                s.has_focus = true
            }
        }
        o += 1usize
    }
    let (compiled, compile_error) = scene.compile(s.renderer, scene.finish(&builder))
    if compile_error != ok { ret (zero, TooLarge) }
    // The previous frame's scene goes with the new one committed.
    if s.has_scene {
        let released = scene.release_scene(s.renderer, s.scene_id)
    }
    s.scene_id = compiled
    s.has_scene = true
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
    if (e.kind == REGION_TAG || e.kind == EDIT_TAG) && e.enabled && (e.gestures & wanted) != 0u8 { ret (index, true) }
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
    if e.kind == REGION_TAG || e.kind == EDIT_TAG { ret e.focusable }
    ret e.has_action
}

// The focusable elements of a subtree in preorder, into `out`; the count.
fn collect_focusable(s: *State, index: usize, out: []u32, count: usize) -> usize {
    var n = count
    let e = &s.elements[index]
    if !e.live { ret n }
    if focusable(e) && n < out.len {
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

// Tab and Shift+Tab: the next or previous focusable element in preorder, within
// the trapping scope's subtree when the focus sits in one, wrapping at the ends.
fn move_focus(s: *State, backward: bool) {
    var root = usize(s.root)
    if s.has_focus {
        let (found_scope, has_scope) = scope_of(s, usize(s.focus))
        if has_scope && s.elements[found_scope].traps_focus { root = found_scope }
        let (found_overlay, has_overlay) = overlay_of(s, usize(s.focus))
        if has_overlay && s.elements[found_overlay].modal { root = found_overlay }
    }
    var order: [256]u32 = zero
    let count = collect_focusable(s, root, order[..], 0usize)
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
    if physical == 65288u32 { ret 8u32 }
    if physical == 65535u32 { ret 46u32 }
    if physical == 65293u32 || physical == 65421u32 { ret 13u32 }
    if physical == 65307u32 { ret 27u32 }
    if physical == 65289u32 { ret 9u32 }
    ret physical
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
    let (laid, layout_error) = layout.layout(&scratch, e.edit_buffer[0usize..e.edit_len], e.edit_style, edit_options(e.text_width, e.multiline))
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
// fires, Enter is the default action, Escape the cancel one; Tab moves focus first.
fn dispatch_key(s: *State, k: input.KeyEvent) -> (bool, err) {
    let code = key_code(k.key.physical)
    if code == 9u32 {
        move_focus(s, k.modifiers.shift)
        ret (true, ok)
    }
    let (editor, has_editor) = focused_edit(s)
    if has_editor {
        let (edited, edit_error) = edit_key(s, editor, k)
        if edited || edit_error != ok { ret (true, edit_error) }
    }
    var at = usize(s.root)
    if s.has_focus { at = usize(s.focus) }
    while true {
        let e = &s.elements[at]
        if e.kind == SCOPE_TAG {
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
    ret (false, ok)
}

fn dispatch(widget_runtime: *Runtime, event: input.Event) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    if !s.has_root { ret ok }
    switch event {
    case .PointerDown as p:
        // The topmost overlay under the pointer is the tree the press is in; a modal
        // one the press misses is dismissed and keeps the press from what is under.
        var from = usize(s.root)
        let (over, inside, has_over) = overlay_at(s, p.position)
        if has_over {
            if !inside { ret fire_submit(s.elements[over].dismiss) }
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
            }
            if s.elements[region_index].kind == EDIT_TAG {
                s.compose_len = 0usize
                let at = edit_hit(s, region_index, p.position)
                edit_move(&s.elements[region_index], at, false)
            }
            ret ok
        }
        let (found, has_found) = hit_action(s, from, p.position)
        if has_found {
            s.focus = u32(found)
            s.has_focus = true
            let action = s.elements[found].action
            ret action.invoke(action.ctx, event)
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
        if s.arena_state.pressed {
            s.arena_state.pressed = false
            let candidate = usize(s.arena_state.candidate)
            let e = &s.elements[candidate]
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
                if (e.gestures & GESTURE_TAP) != 0u8 && geometry.contains(e.bounds, p.position) { ret fire_gesture(e.gesture, Gesture { Tap: p.position }) }
            }
            ret ok
        }
        let (found, has_found) = hit_action(s, usize(s.root), p.position)
        if has_found {
            let action = s.elements[found].action
            ret action.invoke(action.ctx, event)
        }
    case .PointerMove as p:
        if s.arena_state.pressed {
            let candidate = usize(s.arena_state.candidate)
            let e = &s.elements[candidate]
            if e.live && e.kind == EDIT_TAG {
                let at = edit_hit(s, candidate, p.position)
                edit_move(e, at, true)
                ret ok
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
        // Hover: entering one region leaves the last; a modal overlay keeps the
        // pointer from what is under it.
        var from = usize(s.root)
        let (top, top_inside, has_top) = overlay_at(s, p.position)
        if has_top {
            if !top_inside { ret ok }
            from = top
        }
        let (over, has_over) = hit_region(s, from, p.position, GESTURE_HOVER)
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
        let (found, has_found) = hit_scroll(s, usize(s.root), p.position)
        if has_found {
            // The notch count rides in `device` as its bits (D797); a notch is 40 px.
            let notches = f32(mem.bitcast[i32](p.device)) / 120.0
            ret scroll_by(s, found, 0.0 - notches * 40.0, false)
        }
    case .KeyDown as k:
        let (taken, key_error) = dispatch_key(s, k)
        if taken || key_error != ok { ret key_error }
        if s.has_focus && s.elements[usize(s.focus)].has_action {
            let action = s.elements[usize(s.focus)].action
            ret action.invoke(action.ctx, event)
        }
    case .KeyUp as k:
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
        ret ok
    case .Focus as w:
        ret ok
    case .Blur as w:
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

// An overlay's content bounds, for a harness.
fn overlay_bounds_of(widget_runtime: *const Runtime, element: ElementId) -> (geometry.Rect, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || s.closed { ret (zero, false) }
    let (index, found) = element_of(s, element)
    if !found || s.elements[index].kind != OVERLAY_TAG { ret (zero, false) }
    ret (s.elements[index].overlay_bounds, true)
}

// The element that has the focus, for a harness or a control.
fn focused(widget_runtime: *const Runtime) -> (ElementId, bool) {
    let s = mem.cast[*State](widget_runtime.state)
    if mem.address_of(s) == 0usize || !s.has_focus { ret (zero, false) }
    ret (ElementId { slot: s.focus, generation: s.elements[usize(s.focus)].generation }, true)
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
type Summary = struct { id: ElementId, kind: u8, parent: ElementId, has_parent: bool, bounds: geometry.Rect, has_action: bool, enabled: bool, focused: bool, text: str, first_child: ElementId, has_child: bool, next_sibling: ElementId, has_sibling: bool, semantics: Semantics, has_semantics: bool, value: str, selection_start: usize, selection_end: usize, read_only: bool }

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
