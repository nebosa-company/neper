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
type Text = struct { value: str, style: layout.Style, color: paint.Color }
type Button = struct { action: Action, enabled: bool }
type Image = struct { texture: scene.TextureId, fit: Fit }
type Scroll = struct { axis: ui_layout.Axis, offset: f32 }
type Custom = struct { ctx: *void, measure: fn(*void, ui_layout.Constraints) -> geometry.Size, paint: fn(*void, *scene.Builder, geometry.Rect) -> err }
type Kind = union enum u8 { Box, Flex: ui_layout.Flex, Grid: ui_layout.Grid, Stack, Text: Text, Button: Button, Image: Image, Scroll: Scroll, Custom: Custom }
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
    state_keys: [8]Key,
    state_ids: [8]StateId,
    state_count: usize,
    text: [64]u8,
    text_len: usize,
    invalid: bool,
}
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
        let (laid, layout_error) = layout.layout(a, t.value, t.style, layout.Options { width: inner.max_width, max_lines: 0u32, align: .Start, wrap: .Word, ellipsis: "" })
        if layout_error != ok { ret (zero, InvalidTree) }
        ret (geometry.Size { width: laid.bounds.width, height: laid.bounds.height }, ok)
    case .Custom as c:
        ret (c.measure(c.ctx, inner), ok)
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
    case .Scroll as sc:
        var open = inner
        if sc.axis == .Vertical { open.max_height = 3.0e38 } else { open.max_width = 3.0e38 }
        let (content, content_error) = measure_stack(s, a, node, open)
        if content_error != ok { ret (zero, content_error) }
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
    if clipped {
        try scene.push(b, save)
        try scene.push(b, scene.Command { Clip: scene.Clip { Rect: bounds } })
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
    if paint_background { try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: bounds, brush: background } }) }
    switch node.kind {
    case .Text as t:
        let (laid, layout_error) = layout.layout(a, t.value, t.style, layout.Options { width: inner.width, max_lines: 0u32, align: .Start, wrap: .Word, ellipsis: "" })
        if layout_error != ok { ret InvalidTree }
        let (copies, copies_error) = mem.alloc[layout.Layout](a, 1usize)
        if copies_error != ok { ret TooLarge }
        copies[0usize] = laid
        try scene.push(b, scene.Command { Text: scene.DrawText { layout: &copies[0usize], origin: geometry.Point { x: inner.x, y: inner.y }, brush: paint.Brush { Solid: t.color } } })
    case .Image as im:
        try scene.push(b, scene.Command { Image: scene.DrawImage { texture: im.texture, source: geometry.Rect { x: 0.0, y: 0.0, width: 1.0, height: 1.0 }, destination: inner, opacity: 1.0 } })
    case .Custom as c:
        try c.paint(c.ctx, b, inner)
    case .Flex as f:
        try place_flex(s, a, node, element, f, inner, inner_limits, b, depth)
    case .Box:
        try place_flex(s, a, node, element, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner, inner_limits, b, depth)
    case .Button as bt:
        try place_flex(s, a, node, element, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, inner, inner_limits, b, depth)
    case .Grid as g:
        try place_grid(s, a, node, element, g, inner, inner_limits, b, depth)
    case .Stack:
        try place_stack(s, a, node, element, inner, inner_limits, b, depth)
    case .Scroll as sc:
        var open = inner_limits
        if sc.axis == .Vertical { open.max_height = 3.0e38 } else { open.max_width = 3.0e38 }
        let offset = s.elements[element].scroll_offset
        var shifted = inner
        if sc.axis == .Vertical { shifted.y = inner.y - offset } else { shifted.x = inner.x - offset }
        try scene.push(b, save)
        try scene.push(b, scene.Command { Clip: scene.Clip { Rect: inner } })
        try place_stack(s, a, node, element, shifted, open, b, depth)
        try scene.push(b, restore)
    }
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
    let place_error = place(s, frame_arena, &root, root_index, geometry.Rect { x: 0.0, y: 0.0, width: size.width, height: size.height }, &builder, 1usize)
    if place_error == scene.TooLarge { ret (zero, TooLarge) }
    if place_error != ok { ret (zero, place_error) }
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

fn dispatch(widget_runtime: *Runtime, event: input.Event) -> err {
    let (s, state_error) = state_of(widget_runtime)
    if state_error != ok { ret state_error }
    if !s.has_root { ret ok }
    switch event {
    case .PointerDown as p:
        let (found, has_found) = hit_action(s, usize(s.root), p.position)
        if has_found {
            s.focus = u32(found)
            s.has_focus = true
            let action = s.elements[found].action
            ret action.invoke(action.ctx, event)
        }
    case .PointerUp as p:
        let (found, has_found) = hit_action(s, usize(s.root), p.position)
        if has_found {
            let action = s.elements[found].action
            ret action.invoke(action.ctx, event)
        }
    case .PointerMove as p:
        let (found, has_found) = hit_action(s, usize(s.root), p.position)
        if has_found {
            let action = s.elements[found].action
            ret action.invoke(action.ctx, event)
        }
    case .Scroll as p:
        let (found, has_found) = hit_scroll(s, usize(s.root), p.position)
        if has_found {
            let e = &s.elements[found]
            // The notch count rides in `device` as its bits (D797); a notch is 40 px.
            let notches = f32(mem.bitcast[i32](p.device)) / 120.0
            e.scroll_offset = max_f(e.scroll_offset - notches * 40.0, 0.0)
            e.invalid = true
        }
    case .KeyDown as k:
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
        if s.has_focus && s.elements[usize(s.focus)].has_action {
            let action = s.elements[usize(s.focus)].action
            ret action.invoke(action.ctx, event)
        }
    case .Composition as c:
        ret ok
    case .Frame as w:
        ret ok
    case .Close as w:
        ret ok
    case .Resize as m:
        ret ok
    case .Focus as w:
        ret ok
    case .Blur as w:
        ret ok
    }
    ret ok
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
