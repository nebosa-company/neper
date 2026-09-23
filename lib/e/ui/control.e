// `e.ui.control` (D813, widget plan P1): the catalogue's controls as ordinary
// functions that return node subtrees under a `Theme` -- the tokens, the fonts and
// the language a page is set in. Nothing here is a new primitive: a control is the
// primitives of `e.ui.widget` composed with the looks `e.ui.style` resolves, its
// internals keyed positionally under the caller's key so reconciliation stays
// deterministic, and its semantics said through a `Semantics` node.
//
// Section 3.1, content: `text` under a text role, `selectable_text` as a read-only
// editor over the caller's buffer, `rich_text` as spans on one line with links,
// `icon` and `image` with a semantic label, `canvas` as custom paint with one.

use e.math
use e.mem
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.text.shape
use e.ui.accessibility
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

// What a page is set in: the theme's tokens, the fonts in preference order, the
// language for shaping, and the page's runtime, from which a control reads what the
// pointer and the focus are doing to it (none: every control is at rest). The fonts
// and the tokens outlive every frame.
type Theme = struct { tokens: *const style.ThemeTokens, fonts: []const shape.Font, language: str, runtime: *widget.Runtime }
// A button's look: its fill, whether it takes presses, and whether it is busy with
// what it started (the label hidden in place under a progress ring, D942).
type ButtonOptions = struct { variant: style.ControlVariant, enabled: bool, loading: bool }
type TextOptions = struct { role: style.TextRole, color: style.ColorRole, align: layout.Align, wrap: layout.Wrap, max_lines: u32, ellipsis: str }
// A span of rich text; a linked span fires `link` when tapped, so the spans must
// outlive the element the way an action's context does.
type Span = struct { value: str, role: style.TextRole, color: style.ColorRole, link: widget.Submit }
error TooLarge

const ROLE_IMAGE: u8 = 8u8
const ROLE_LINK: u8 = 9u8
const ROLE_TEXT: u8 = 6u8

fn text_options() -> TextOptions {
    ret TextOptions { role: .Body, color: .Text, align: .Start, wrap: .Word, max_lines: 0u32, ellipsis: "" }
}

// The layout style of a text role: the theme's fonts at the role's size, its line
// height, the page's language. A theme with no fonts lays out nothing (D802).
fn text_style(a: *mem.Arena, t: *const Theme, role: style.TextRole) -> (layout.Style, err) {
    let sized = style.text_style(t.tokens, role)
    let (choices, choices_error) = mem.alloc[layout.FontChoice](a, t.fonts.len)
    if choices_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < t.fonts.len {
        choices[i] = layout.FontChoice { font: t.fonts[i], size: sized.size }
        i += 1usize
    }
    ret (layout.Style { fonts: choices, language: t.language, line_height: sized.line_height }, ok)
}

fn text_node(a: *mem.Arena, key: widget.Key, value: str, t: *const Theme, options: TextOptions) -> (widget.Node, err) {
    let (node, node_error) = colored_text(a, key, value, t, options, style.color(t.tokens, options.color))
    ret (node, node_error)
}

fn colored_text(a: *mem.Arena, key: widget.Key, value: str, t: *const Theme, options: TextOptions, color: paint.Color) -> (widget.Node, err) {
    let (text_look, style_error) = text_style(a, t, options.role)
    if style_error != ok { ret (zero, style_error) }
    ret (widget.text(key, widget.Text { value: value, style: text_look, color: color, wrap: options.wrap, align: options.align, max_lines: options.max_lines, ellipsis: options.ellipsis }, style.defaults()), ok)
}

// A text: shaped, wrapped and aligned by its options, in the role's style.
fn text(a: *mem.Arena, key: widget.Key, value: str, t: *const Theme, options: TextOptions) -> (widget.Node, err) {
    let (node, node_error) = text_node(a, key, value, t, options)
    ret (node, node_error)
}

// A selectable text: a read-only editor over the caller's buffer, so the caret,
// the selection, Shift+arrows and copy are the editor's (D807).
fn selectable_text(a: *mem.Arena, key: widget.Key, buffer: []u8, len: usize, t: *const Theme, options: TextOptions) -> (widget.Node, err) {
    let (text_look, style_error) = text_style(a, t, options.role)
    if style_error != ok { ret (zero, style_error) }
    ret (widget.edit(key, widget.Edit { buffer: buffer, len: len, style: text_look, color: style.color(t.tokens, options.color), selection: style.color(t.tokens, .Selection), change: zero, submit: zero, enabled: true, read_only: true, multiline: options.wrap != .None, secret: false }, style.defaults()), ok)
}

fn link_tap(ctx: *void, g: widget.Gesture) -> err {
    if g.tag != .Tap { ret ok }
    let action = mem.cast[*widget.Submit](ctx)
    ret widget.fire_submit(*action)
}

// Rich text: the spans laid side by side, each in its own role and colour, a
// linked span a tap region with the link role.
// ponytail: the spans sit on one line; wrapping across spans waits on a span-aware layout.
fn rich_text(a: *mem.Arena, key: widget.Key, spans: []const Span, t: *const Theme) -> (widget.Node, err) {
    let (children, children_error) = mem.alloc[widget.Node](a, spans.len)
    if children_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < spans.len {
        let span = &spans[i]
        var options = text_options()
        options.role = span.role
        options.color = span.color
        options.wrap = .None
        let (piece, piece_error) = text_node(a, 0u64, span.value, t, options)
        if piece_error != ok { ret (zero, piece_error) }
        children[i] = piece
        if widget.submit_set(span.link.invoke) {
            let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
            if body_error != ok { ret (zero, TooLarge) }
            body[0usize] = piece
            var linked: widget.Semantics = zero
            linked.role = ROLE_LINK
            linked.label = span.value
            let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
            if region_error != ok { ret (zero, TooLarge) }
            region[0usize] = widget.region(0u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&span.link), invoke: link_tap }, gestures: 1u8, enabled: true, focusable: true }, style.defaults(), body[0usize..1usize])
            children[i] = widget.semantics(0u64, linked, style.defaults(), region[0usize..1usize])
        }
        i += 1usize
    }
    ret (widget.flex(key, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), children[0usize..spans.len]), ok)
}

fn labelled(a: *mem.Arena, key: widget.Key, role: u8, label: str, inner: widget.Node) -> (widget.Node, err) {
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = inner
    var sem: widget.Semantics = zero
    sem.role = role
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

fn sized_style(width: f32, height: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    ret s
}

// An icon: a square image of `size`, contained, with a semantic label.
// ponytail: an icon is not tinted; a tint waits on the renderer's image brush.
fn icon(a: *mem.Arena, key: widget.Key, texture: scene.TextureId, size: f32, label: str) -> (widget.Node, err) {
    let (node, node_error) = labelled(a, key, ROLE_IMAGE, label, widget.image(0u64, widget.Image { texture: texture, fit: .Contain }, sized_style(size, size)))
    ret (node, node_error)
}

// An image of a size, fitted, with a semantic label; an empty label hides it from
// the tree the way a decoration should be.
fn image(a: *mem.Arena, key: widget.Key, texture: scene.TextureId, width: f32, height: f32, fit: widget.Fit, label: str) -> (widget.Node, err) {
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.image(0u64, widget.Image { texture: texture, fit: fit }, sized_style(width, height))
    var sem: widget.Semantics = zero
    sem.role = ROLE_IMAGE
    sem.label = label
    sem.hidden = label.len == 0usize
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// A canvas: the caller's measure and paint, with a semantic label.
fn canvas(a: *mem.Arena, key: widget.Key, custom: widget.Custom, label: str) -> (widget.Node, err) {
    var none: []const widget.Node = zero
    let (node, node_error) = labelled(a, key, ROLE_IMAGE, label, widget.Node { key: 0u64, kind: widget.Kind { Custom: custom }, style: style.defaults(), children: none })
    ret (node, node_error)
}

// ------------------------------------------------------- surfaces (D814, P1-02)

// A surface's look: its background role, whether it is bordered, its corner radius,
// its elevation level (0 for none, up to 5, the theme's shadow strengths), padding.
type SurfaceOptions = struct { background: style.ColorRole, bordered: bool, radius: f32, elevation: u8, padding: f32 }

fn surface_options(t: *const Theme) -> SurfaceOptions {
    ret SurfaceOptions { background: .Surface, bordered: false, radius: 0.0, elevation: 0u8, padding: t.tokens.spacing.md }
}

fn surface_style(t: *const Theme, options: SurfaceOptions) -> style.Style {
    var s = style.defaults()
    s.background = paint.Brush { Solid: style.color(t.tokens, options.background) }
    if options.bordered { s.border = style.Border { width: t.tokens.borders.regular, color: style.color(t.tokens, .Border) } }
    s.radius = options.radius
    if options.elevation != 0u8 {
        var raised = usize(options.elevation)
        if raised > 5usize { raised = 5usize }
        // The elevation level is the shadow's strength; it falls two pixels a level.
        s.shadow = style.Shadow { offset: geometry.Point { x: 0.0, y: f32(raised) * 2.0 }, color: paint.rgba(0.0, 0.0, 0.0, t.tokens.elevation[raised]) }
    }
    let pad = style.Length { Px: options.padding }
    s.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    if options.radius > 0.0 { s.overflow = .Clip }
    ret s
}

// A surface: a box with the look, its children in a column; a group in the tree.
fn surface(a: *mem.Arena, key: widget.Key, t: *const Theme, options: SurfaceOptions, children: []const widget.Node) -> (widget.Node, err) {
    ret (widget.box(key, surface_style(t, options), children), ok)
}

// A panel: the variant surface, bordered, square.
fn panel(a: *mem.Arena, key: widget.Key, t: *const Theme, children: []const widget.Node) -> (widget.Node, err) {
    var options = surface_options(t)
    options.background = .SurfaceVariant
    options.bordered = true
    ret (widget.box(key, surface_style(t, options), children), ok)
}

// A card: the surface raised one level, rounded, with a hairline border.
fn card(a: *mem.Arena, key: widget.Key, t: *const Theme, children: []const widget.Node) -> (widget.Node, err) {
    var options = surface_options(t)
    options.radius = t.tokens.radii.sm
    options.elevation = 1u8
    let (made, made_error) = surface(a, key, t, options, children)
    if made_error != ok { ret (zero, made_error) }
    var raised = made
    raised.style.border = style.Border { width: t.tokens.borders.hairline, color: style.color(t.tokens, .Border) }
    ret (raised, ok)
}

// A group box: a label above a bordered surface, a labelled group in the tree.
fn group_box(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, children: []const widget.Node) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var caption = text_options()
    caption.role = .Label
    let (heading, heading_error) = text_node(a, 0u64, label, t, caption)
    if heading_error != ok { ret (zero, heading_error) }
    parts[0usize] = heading
    var options = surface_options(t)
    options.bordered = true
    options.radius = t.tokens.radii.xs
    parts[1usize] = widget.box(0u64, surface_style(t, options), children)
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A divider: a hairline in the border colour across the axis, `length` long (0 to
// fill), a decoration the tree leaves out.
fn divider(a: *mem.Arena, key: widget.Key, t: *const Theme, axis: ui_layout.Axis, length: f32) -> (widget.Node, err) {
    var s = style.defaults()
    s.background = paint.Brush { Solid: style.color(t.tokens, .Border) }
    let thick = style.Length { Px: t.tokens.borders.hairline }
    var span: style.Length = style.Length { Percent: 100.0 }
    if length > 0.0 { span = style.Length { Px: length } }
    if axis == .Horizontal {
        s.height = thick
        s.width = span
    } else {
        s.width = thick
        s.height = span
    }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.box(0u64, s, zero)
    var sem: widget.Semantics = zero
    sem.hidden = true
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// A badge: a small pill in the primary colour with a caption, a status in the tree.
fn badge(a: *mem.Arena, key: widget.Key, t: *const Theme, value: str) -> (widget.Node, err) {
    var caption = text_options()
    caption.role = .Caption
    caption.color = .OnPrimary
    let (label, label_error) = text_node(a, 0u64, value, t, caption)
    if label_error != ok { ret (zero, label_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = label
    var options = surface_options(t)
    options.background = .Primary
    options.radius = t.tokens.radii.full
    options.padding = t.tokens.spacing.xs
    let (pill, pill_error) = mem.alloc[widget.Node](a, 1usize)
    if pill_error != ok { ret (zero, TooLarge) }
    pill[0usize] = widget.box(0u64, surface_style(t, options), body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 26u8
    sem.label = value
    ret (widget.semantics(key, sem, style.defaults(), pill[0usize..1usize]), ok)
}

// An avatar: an image clipped to a circle of `size`, an image with a label in the tree.
fn avatar(a: *mem.Arena, key: widget.Key, t: *const Theme, texture: scene.TextureId, size: f32, label: str) -> (widget.Node, err) {
    let (picture, picture_error) = mem.alloc[widget.Node](a, 1usize)
    if picture_error != ok { ret (zero, TooLarge) }
    picture[0usize] = widget.image(0u64, widget.Image { texture: texture, fit: .Cover }, sized_style(size, size))
    var ring = sized_style(size, size)
    ring.radius = size * 0.5
    ring.overflow = .Clip
    ring.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceVariant) }
    let (disc, disc_error) = mem.alloc[widget.Node](a, 1usize)
    if disc_error != ok { ret (zero, TooLarge) }
    disc[0usize] = widget.box(0u64, ring, picture[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = ROLE_IMAGE
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), disc[0usize..1usize]), ok)
}

// A placeholder: a rounded block in the variant surface colour standing in for
// content to come, busy in the tree.
fn placeholder(a: *mem.Arena, key: widget.Key, t: *const Theme, width: f32, height: f32) -> (widget.Node, err) {
    var block = sized_style(width, height)
    block.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceVariant) }
    block.radius = t.tokens.radii.xs
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.box(0u64, block, zero)
    var sem: widget.Semantics = zero
    sem.states = accessibility.STATE_BUSY
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// ------------------------------------------------------- the button family (D818, P1-06)

fn button_options() -> ButtonOptions {
    ret ButtonOptions { variant: .Filled, enabled: true, loading: false }
}

// The control state of a keyed element under the page's runtime, with what the
// caller says of it.
fn control_state(t: *const Theme, key: widget.Key, enabled: bool, selected: bool) -> style.ControlState {
    var state: style.ControlState = zero
    state.disabled = !enabled
    state.selected = selected
    if mem.address_of(t.runtime) != 0usize {
        focus_look(t)
        let now = widget.interaction(t.runtime, key)
        state.hovered = now.hovered
        state.pressed = now.pressed
        state.focused = now.focused
        state.focus_visible = now.focus_visible
    }
    ret state
}

// The theme's focus ring on the page's runtime (D940): the runtime paints it round
// whichever element the keyboard focuses, so a control need only hand it the look.
fn focus_look(t: *const Theme) {
    if mem.address_of(t.runtime) == 0usize { ret }
    widget.set_focus_ring(t.runtime, style.color(t.tokens, .FocusRing), t.tokens.metrics.focus_ring, t.tokens.metrics.focus_offset)
}

fn press_tap(ctx: *void, g: widget.Gesture) -> err {
    if g.tag != .Tap { ret ok }
    let action = mem.cast[*const widget.Submit](ctx)
    ret widget.fire_submit(*action)
}

// The pressable surface every button is: a tap-and-hover region in the resolved
// look, its content centred, the semantics on top. `action` outlives the element.
fn pressable(a: *mem.Arena, key: widget.Key, t: *const Theme, role: u8, label: str, look: style.ResolvedControl, enabled: bool, selected: bool, action: *const widget.Submit, content: widget.Node) -> (widget.Node, err) {
    let (node, node_error) = pressable_states(a, key, t, role, label, look, enabled, selected, 0u32, 0u32, 0u64, action, content)
    ret (node, node_error)
}

// The same with more for the tree: further state bits, further actions, and an
// element the button controls (0 for none).
fn pressable_states(a: *mem.Arena, key: widget.Key, t: *const Theme, role: u8, label: str, look: style.ResolvedControl, enabled: bool, selected: bool, states: u32, actions: u32, controls: widget.Key, action: *const widget.Submit, content: widget.Node) -> (widget.Node, err) {
    var s = style.defaults()
    s.background = paint.Brush { Solid: look.background }
    s.border = style.Border { width: look.border_width, color: look.border }
    s.radius = look.radius
    s.opacity = look.opacity
    s.min_height = style.Length { Px: max_of(t.tokens.metrics.control_height, look.min_height) }
    s.min_width = style.Length { Px: max_of(t.tokens.metrics.hit_target, look.min_width) }
    var end = t.tokens.spacing.md
    if look.padding > 0.0 || look.custom_padding { end = look.padding }
    var start = end
    if look.padding_start > 0.0 { start = look.padding_start }
    var vertical = t.tokens.spacing.xs
    if look.custom_padding { vertical = look.padding_y }
    let pad_y = style.Length { Px: vertical }
    s.padding = style.EdgeLengths { left: style.Length { Px: start }, top: pad_y, right: style.Length { Px: end }, bottom: pad_y }
    if look.elevation != 0u8 {
        var raised = usize(look.elevation)
        if raised > 5usize { raised = 5usize }
        s.shadow = style.Shadow { offset: geometry.Point { x: 0.0, y: f32(raised) }, color: paint.rgba(0.0, 0.0, 0.0, t.tokens.elevation[raised]) }
    }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    inner[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](action), invoke: press_tap }, gestures: 1u8 | 4u8, enabled: enabled, focusable: enabled }, s, body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = role
    sem.label = label
    sem.actions = accessibility.ACTION_PRESS | actions
    sem.states = states
    sem.controls = controls
    if !enabled { sem.states = sem.states | accessibility.STATE_DISABLED }
    if selected { sem.states = sem.states | accessibility.STATE_SELECTED }
    ret (widget.semantics(0u64, sem, style.defaults(), inner[0usize..1usize]), ok)
}

// A button's v2 look (D942, docs/ux/components/Button): fully rounded, 16px sides at
// pointer density (32 tall) and 24 at touch density, the disabled colours of v2.
fn button_look(t: *const Theme, look: style.ResolvedControl, enabled: bool) -> style.ResolvedControl {
    var out = look
    if !enabled { out = style.disabled_look(t.tokens, look) }
    // The sides are the specification's space-4 and space-6 (and space-3 for a
    // text button), which a touch adaptation's wider spacing does not scale.
    out.radius = t.tokens.metrics.control_height * 0.5
    out.padding = 16.0
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { out.padding = 24.0 }
    if options_text(look) { out.padding = 12.0 }
    // The label line centred in the control height (D944).
    out.custom_padding = true
    out.padding_y = max_zero((t.tokens.metrics.control_height - style.text_style(t.tokens, .Label).line_height) * 0.5)
    ret out
}

fn max_of(a: f32, b: f32) -> f32 {
    if a > b { ret a }
    ret b
}

fn max_zero(v: f32) -> f32 {
    if v < 0.0 { ret 0.0 }
    ret v
}

// A text (Plain) button is its label alone: 12px sides.
fn options_text(look: style.ResolvedControl) -> bool {
    ret !(look.background.alpha > 0.0) && !(look.border_width > 0.0)
}

// A button: its label in the resolved foreground; Enter and Space press it too.
fn button(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, action: *const widget.Submit, options: ButtonOptions) -> (widget.Node, err) {
    let look = button_look(t, style.resolve(t.tokens, options.variant, control_state(t, key, options.enabled, false)), options.enabled)
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    if options.loading {
        // The label keeps its place, unseen, so the width does not change; the
        // ring stands centred over it and the tree says busy.
        var hidden = look.foreground
        hidden.alpha = 0.0
        let (kept, kept_error) = colored_text(a, 0u64, label, t, caption, hidden)
        if kept_error != ok { ret (zero, kept_error) }
        let (ring, ring_error) = progress_ring(a, 0u64, t, label, 0.0, true, t.tokens.sizes.icon_sm)
        if ring_error != ok { ret (zero, ring_error) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
        if parts_error != ok { ret (zero, TooLarge) }
        parts[0usize] = ring
        parts[1usize] = kept
        parts[2usize] = widget.aligned(0u64, .Center, .Center, style.defaults(), parts[0usize..1usize])
        let content = widget.stack(0u64, style.defaults(), parts[1usize..3usize])
        let (busy, busy_error) = pressable_states(a, key, t, 3u8, label, look, options.enabled, false, accessibility.STATE_BUSY, 0u32, 0u64, action, content)
        ret (busy, busy_error)
    }
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, look.foreground)
    if label_error != ok { ret (zero, label_error) }
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, options.enabled, false, action, label_node)
    ret (node, node_error)
}

// The four FAB sizes of the specification (D944, docs/ux/components/Fab).
type FabSize = enum u8 { Small, Default, Large, Extended }

// A floating action button: `primary-container`, casting elevation 3 (4 hovered);
// small 40 with `radius-md`, default 56 with `radius-lg`, large 96 with `radius-xl`
// and a 36 icon, extended 56 tall with the label after the icon, 16 before it and
// 20 after, 12 between; the label names it in the tree.
fn fab(a: *mem.Arena, key: widget.Key, t: *const Theme, texture: scene.TextureId, label: str, action: *const widget.Submit, size: FabSize) -> (widget.Node, err) {
    var look = style.resolve(t.tokens, .Container, control_state(t, key, true, false))
    var side = t.tokens.sizes.control_xl
    var icon_size = t.tokens.sizes.icon_md
    look.radius = t.tokens.radii.lg
    if size == .Small {
        side = t.tokens.sizes.control_md
        look.radius = t.tokens.radii.md
    }
    if size == .Large {
        side = 96.0
        icon_size = t.tokens.sizes.icon_lg
        look.radius = t.tokens.radii.xl
    }
    look.custom_padding = true
    look.padding = (side - icon_size) * 0.5
    look.padding_y = look.padding
    let picture = widget.image(0u64, widget.Image { texture: texture, fit: .Contain }, sized_style(icon_size, icon_size))
    var content = picture
    if size == .Extended {
        look.padding_start = 16.0
        look.padding = 20.0
        var caption = text_options()
        caption.role = .Label
        caption.wrap = .None
        let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, look.foreground)
        if label_error != ok { ret (zero, label_error) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
        if parts_error != ok { ret (zero, TooLarge) }
        parts[0usize] = picture
        parts[1usize] = label_node
        content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, style.defaults(), parts[0usize..2usize])
    }
    look.min_width = side
    look.min_height = side
    if size == .Extended { look.min_width = 80.0 }
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, true, false, action, content)
    ret (node, node_error)
}

// A button with a leading icon (D942): the icon at `sizes.icon_sm`, `spacing.sm` from
// the label, 16px on the icon side.
fn button_with_icon(a: *mem.Arena, key: widget.Key, t: *const Theme, texture: scene.TextureId, label: str, action: *const widget.Submit, options: ButtonOptions) -> (widget.Node, err) {
    var look = button_look(t, style.resolve(t.tokens, options.variant, control_state(t, key, options.enabled, false)), options.enabled)
    look.padding_start = 16.0
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, look.foreground)
    if label_error != ok { ret (zero, label_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let icon_size = t.tokens.sizes.icon_sm
    parts[0usize] = widget.image(0u64, widget.Image { texture: texture, fit: .Contain }, sized_style(icon_size, icon_size))
    parts[1usize] = label_node
    let row = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.sm }, style.defaults(), parts[0usize..2usize])
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, options.enabled, false, action, row)
    ret (node, node_error)
}

// An icon button: the icon in place of the label, the label for the tree alone.
// v2 (D944, docs/ux/components/IconButton): a circle the control height across,
// the icon 18 at pointer density and 24 at touch density centred in it; the
// standard (Plain) one's layer is the icon colour, `on-surface-variant`.
fn icon_look(t: *const Theme, look: style.ResolvedControl, variant: style.ControlVariant, enabled: bool) -> (style.ResolvedControl, f32) {
    var out = look
    if variant == .Plain { out.foreground = style.color(t.tokens, .OnSurfaceVariant) }
    if !enabled { out = style.disabled_look(t.tokens, out) }
    let h = t.tokens.metrics.control_height
    var size = t.tokens.sizes.icon_sm
    if h > t.tokens.sizes.control_sm { size = t.tokens.sizes.icon_md }
    out.radius = h * 0.5
    out.custom_padding = true
    out.padding = max_zero((h - size) * 0.5)
    out.padding_y = out.padding
    ret (out, size)
}

fn icon_button(a: *mem.Arena, key: widget.Key, t: *const Theme, texture: scene.TextureId, label: str, action: *const widget.Submit, options: ButtonOptions) -> (widget.Node, err) {
    var state = control_state(t, key, options.enabled, false)
    let (look, size) = icon_look(t, style.resolve(t.tokens, options.variant, state), options.variant, options.enabled)
    let picture = widget.image(0u64, widget.Image { texture: texture, fit: .Contain }, sized_style(size, size))
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, options.enabled, false, action, picture)
    ret (node, node_error)
}

// A toggle button: pressed to switch `selected`, which the caller keeps and the look
// and the tree show.
// v2 (D944, docs/ux/components/ToggleButton): off is the variant's look, fully
// rounded; on is the filled look with `radius-sm` corners (`radius-md` at touch
// density), keeping that shape when disabled so the state still reads.
fn toggle_button(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, selected: bool, action: *const widget.Submit, options: ButtonOptions) -> (widget.Node, err) {
    var shown: style.ControlVariant = options.variant
    if selected { shown = .Filled }
    var state = control_state(t, key, options.enabled, false)
    var look = button_look(t, style.resolve(t.tokens, shown, state), options.enabled)
    if selected {
        look.radius = t.tokens.radii.sm
        if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { look.radius = t.tokens.radii.md }
    }
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, look.foreground)
    if label_error != ok { ret (zero, label_error) }
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, options.enabled, selected, action, label_node)
    ret (node, node_error)
}

// A link: its text in the primary colour, a tap region with the link role.
// v2 (D944, docs/ux/components/Link, standalone): `label-large` in `primary`; hovered
// or pressed, a `primary` wash at the state's opacity behind it and a 1px underline;
// `radius-xs` corners for the wash and the ring.
fn link(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, action: *const widget.Submit) -> (widget.Node, err) {
    let state = control_state(t, key, true, false)
    var caption = text_options()
    caption.role = .Label
    caption.color = .Primary
    caption.wrap = .None
    let (label_node, label_error) = text_node(a, 0u64, label, t, caption)
    if label_error != ok { ret (zero, label_error) }
    let active = state.hovered || state.pressed
    var count = 1usize
    if active { count = 2usize }
    let (lines, lines_error) = mem.alloc[widget.Node](a, count)
    if lines_error != ok { ret (zero, TooLarge) }
    lines[0usize] = label_node
    if active {
        var under = style.defaults()
        under.width = style.Length { Percent: 100.0 }
        under.height = style.Length { Px: t.tokens.sizes.divider }
        under.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
        lines[1usize] = widget.box(0u64, under, zero)
    }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Start, gap: 0.0 }, style.defaults(), lines[0usize..count])
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    // A link is at least the hit target, so a short one is still reachable.
    var target_style = style.defaults()
    target_style.min_width = style.Length { Px: t.tokens.metrics.hit_target }
    target_style.min_height = style.Length { Px: t.tokens.metrics.hit_target }
    target_style.radius = t.tokens.radii.xs
    if active {
        var opacity = t.tokens.states.hover
        if state.pressed { opacity = t.tokens.states.pressed }
        target_style.background = paint.Brush { Solid: style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), style.color(t.tokens, .Primary), opacity) }
    }
    inner[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](action), invoke: press_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, target_style, body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = ROLE_LINK
    sem.label = label
    sem.actions = accessibility.ACTION_PRESS
    ret (widget.semantics(0u64, sem, style.defaults(), inner[0usize..1usize]), ok)
}

// ------------------------------------------------- discrete selection (D819, P1-07)

// A choosable row: a mark box beside a label, a tap-and-hover region under the
// role, its states from what the caller says. The mark is a square, or a disc when
// `round`, in the outlined look, filled inside when chosen.
fn choosable(a: *mem.Arena, key: widget.Key, t: *const Theme, role: u8, label: str, chosen: bool, mixed: bool, round: bool, action: *const widget.Submit, enabled: bool) -> (widget.Node, err) {
    let state = control_state(t, key, enabled, chosen)
    let look = style.resolve(t.tokens, .Outlined, state)
    let size = t.tokens.metrics.control_height * 0.5
    var mark_style = sized_style(size, size)
    mark_style.background = paint.Brush { Solid: look.background }
    mark_style.border = style.Border { width: t.tokens.borders.regular, color: look.border }
    mark_style.radius = t.tokens.radii.xs
    if round { mark_style.radius = size * 0.5 }
    let pad = style.Length { Px: size * 0.25 }
    mark_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    var mark_count = 0usize
    if chosen || mixed { mark_count = 1usize }
    let (dot, dot_error) = mem.alloc[widget.Node](a, mark_count)
    if dot_error != ok { ret (zero, TooLarge) }
    if mark_count != 0usize {
        var dot_style = style.defaults()
        dot_style.width = style.Length { Percent: 100.0 }
        dot_style.height = style.Length { Percent: 100.0 }
        if mixed { dot_style.height = style.Length { Percent: 30.0 } }
        dot_style.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
        if round { dot_style.radius = size }
        dot[0usize] = widget.box(0u64, dot_style, zero)
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.box(0u64, mark_style, dot[0usize..mark_count])
    var caption = text_options()
    caption.role = .Body
    caption.wrap = .None
    if !enabled { caption.color = .TextMuted }
    let (label_node, label_error) = text_node(a, 0u64, label, t, caption)
    if label_error != ok { ret (zero, label_error) }
    parts[1usize] = label_node
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.sm }, style.defaults(), parts[0usize..2usize])
    // The row is centred in a box at least the hit target, which the region wraps.
    var target_style = style.defaults()
    target_style.min_height = style.Length { Px: t.tokens.metrics.hit_target }
    target_style.min_width = style.Length { Px: t.tokens.metrics.hit_target }
    target_style.opacity = look.opacity
    let (centred, centred_error) = mem.alloc[widget.Node](a, 1usize)
    if centred_error != ok { ret (zero, TooLarge) }
    centred[0usize] = widget.aligned(0u64, .Start, .Center, target_style, row[0usize..1usize])
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    inner[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](action), invoke: press_tap }, gestures: 1u8 | 4u8, enabled: enabled, focusable: enabled }, style.defaults(), centred[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = role
    sem.label = label
    sem.actions = accessibility.ACTION_PRESS
    if chosen { sem.states = accessibility.STATE_CHECKED }
    if mixed { sem.states = sem.states | accessibility.STATE_MIXED }
    if !enabled { sem.states = sem.states | accessibility.STATE_DISABLED }
    ret (widget.semantics(0u64, sem, style.defaults(), inner[0usize..1usize]), ok)
}

// A checkbox: checked, or mixed for a choice made in part; a tap fires `action`.
fn checkbox(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, checked: bool, mixed: bool, action: *const widget.Submit, enabled: bool) -> (widget.Node, err) {
    let (node, node_error) = choosable(a, key, t, 4u8, label, checked, mixed, false, action, enabled)
    ret (node, node_error)
}

// A radio: one of a group, the caller keeping which is selected.
fn radio(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, selected: bool, action: *const widget.Submit, enabled: bool) -> (widget.Node, err) {
    let (node, node_error) = choosable(a, key, t, 5u8, label, selected, false, true, action, enabled)
    ret (node, node_error)
}

// A radio group: a radio per label in a column, keyed `key + 1 + index`, the
// selected one marked, each firing its own action (one per label, caller-owned);
// a group in the tree under `label`.
fn radio_group(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, labels: []const str, selected: usize, actions: []const widget.Submit, enabled: bool) -> (widget.Node, err) {
    if actions.len != labels.len { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[widget.Node](a, labels.len)
    if items_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < labels.len {
        let (item, item_error) = radio(a, key + 1u64 + u64(i), t, labels[i], i == selected, &actions[i], enabled)
        if item_error != ok { ret (zero, item_error) }
        items[i] = item
        i += 1usize
    }
    let (stacked, stacked_error) = mem.alloc[widget.Node](a, 1usize)
    if stacked_error != ok { ret (zero, TooLarge) }
    stacked[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, style.defaults(), items[0usize..labels.len])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), stacked[0usize..1usize]), ok)
}

// A switch: a track with its knob at the right when on, the label beside; a switch
// in the tree, checked when on.
fn switch_control(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, on: bool, action: *const widget.Submit, enabled: bool) -> (widget.Node, err) {
    // On is the filled variant, not the selected tint.
    let state = control_state(t, key, enabled, false)
    var variant: style.ControlVariant = .Outlined
    if on { variant = .Filled }
    let look = style.resolve(t.tokens, variant, state)
    let height = t.tokens.metrics.control_height * 0.5
    let width = height * 1.75
    var track = sized_style(width, height)
    track.background = paint.Brush { Solid: look.background }
    // v2 (D942): the off track is the highest container inside its outline.
    if !on { track.background = paint.Brush { Solid: style.layer(style.color(t.tokens, .SurfaceContainerHighest), look.foreground, look.background.alpha) } }
    track.border = style.Border { width: t.tokens.borders.regular, color: look.border }
    track.radius = height * 0.5
    let knob = height - 4.0
    var knob_style = sized_style(knob, knob)
    knob_style.background = paint.Brush { Solid: look.foreground }
    knob_style.radius = knob * 0.5
    var at: f32 = 2.0
    if on { at = width - knob - 2.0 }
    let (knobs, knobs_error) = mem.alloc[widget.Node](a, 1usize)
    if knobs_error != ok { ret (zero, TooLarge) }
    knobs[0usize] = widget.positioned(0u64, at, 2.0, knob_style, zero)
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.stack(0u64, track, knobs[0usize..1usize])
    var caption = text_options()
    caption.wrap = .None
    if !enabled { caption.color = .TextMuted }
    let (label_node, label_error) = text_node(a, 0u64, label, t, caption)
    if label_error != ok { ret (zero, label_error) }
    parts[1usize] = label_node
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.sm }, style.defaults(), parts[0usize..2usize])
    var target_style = style.defaults()
    target_style.min_height = style.Length { Px: t.tokens.metrics.hit_target }
    target_style.opacity = look.opacity
    let (centred, centred_error) = mem.alloc[widget.Node](a, 1usize)
    if centred_error != ok { ret (zero, TooLarge) }
    centred[0usize] = widget.aligned(0u64, .Start, .Center, target_style, row[0usize..1usize])
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    inner[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](action), invoke: press_tap }, gestures: 1u8 | 4u8, enabled: enabled, focusable: enabled }, style.defaults(), centred[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 18u8
    sem.label = label
    sem.actions = accessibility.ACTION_PRESS
    if on { sem.states = accessibility.STATE_CHECKED }
    if !enabled { sem.states = sem.states | accessibility.STATE_DISABLED }
    ret (widget.semantics(0u64, sem, style.defaults(), inner[0usize..1usize]), ok)
}

// A segmented control: a segment per label in a row, keyed `key + 1 + index`, the
// selected one filled and the rest outlined, each firing its own action; a group
// in the tree.
fn segmented_control(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, labels: []const str, selected: usize, actions: []const widget.Submit, enabled: bool) -> (widget.Node, err) {
    if actions.len != labels.len { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[widget.Node](a, labels.len)
    if items_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < labels.len {
        var options = button_options()
        options.enabled = enabled
        options.variant = .Outlined
        if i == selected { options.variant = .Filled }
        let (item, item_error) = toggle_button(a, key + 1u64 + u64(i), t, labels[i], i == selected, &actions[i], options)
        if item_error != ok { ret (zero, item_error) }
        items[i] = item
        i += 1usize
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), items[0usize..labels.len])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// --------------------------------------------------- range selection (D820, P1-08)

// A slider in the theme's colours: the track in the border colour, the filled part
// and the thumb in the primary; the label beside it; a slider in the tree. The
// caller keeps the value and passes it back each frame; `change` is caller-owned.
fn slider(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, step: f32, change: widget.Change[f32], enabled: bool) -> (widget.Node, err) {
    let (node, node_error) = ranged(a, key, t, label, value, value, false, low, high, step, change, zero, enabled)
    ret (node, node_error)
}

fn range_slider(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, first: f32, second: f32, low: f32, high: f32, step: f32, change: widget.Change[f32], change_second: widget.Change[f32], enabled: bool) -> (widget.Node, err) {
    let (node, node_error) = ranged(a, key, t, label, first, second, true, low, high, step, change, change_second, enabled)
    ret (node, node_error)
}

fn ranged(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, first: f32, second: f32, range: bool, low: f32, high: f32, step: f32, change: widget.Change[f32], change_second: widget.Change[f32], enabled: bool) -> (widget.Node, err) {
    var track_style = style.defaults()
    track_style.width = style.Length { Px: 120.0 }
    track_style.height = style.Length { Px: t.tokens.metrics.control_height }
    let state = control_state(t, key, enabled, false)
    let look = style.resolve(t.tokens, .Outlined, state)
    track_style.opacity = look.opacity
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.slider(key, widget.Slider { value: first, second: second, range: range, low: low, high: high, step: step, vertical: false, track: style.color(t.tokens, .Border), fill: style.color(t.tokens, .Primary), thumb: style.color(t.tokens, .Primary), change: change, change_second: change_second, enabled: enabled }, track_style)
    var caption = text_options()
    caption.wrap = .None
    if !enabled { caption.color = .TextMuted }
    let (label_node, label_error) = text_node(a, 0u64, label, t, caption)
    if label_error != ok { ret (zero, label_error) }
    parts[1usize] = label_node
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.sm }, style.defaults(), parts[0usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 15u8
    sem.label = label
    sem.actions = accessibility.ACTION_INCREMENT | accessibility.ACTION_DECREMENT | accessibility.ACTION_SET_VALUE
    if !enabled { sem.states = accessibility.STATE_DISABLED }
    ret (widget.semantics(0u64, sem, style.defaults(), row[0usize..1usize]), ok)
}

// ------------------------------------------------------------ progress (D822, P1-09)

// A progress bar: a track in the variant surface, the filled part -- keyed
// `key + 1` -- in the primary colour as wide as `value` (0..1) says; indeterminate,
// a quarter-wide segment sits a quarter in and the tree says busy. A progress role
// in the tree with the label.
fn progress_bar(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, indeterminate: bool, width: f32) -> (widget.Node, err) {
    var share = value
    if share < 0.0 { share = 0.0 }
    if share > 1.0 { share = 1.0 }
    let height = t.tokens.spacing.sm
    var track = sized_style(width, height)
    track.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceVariant) }
    track.radius = height * 0.5
    track.overflow = .Clip
    var filled = style.defaults()
    filled.height = style.Length { Px: height }
    filled.width = style.Length { Percent: share * 100.0 }
    filled.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
    filled.radius = height * 0.5
    if indeterminate {
        filled.width = style.Length { Px: width * 0.25 }
        filled.margin = style.EdgeLengths { left: style.Length { Px: width * 0.25 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    }
    let (fill, fill_error) = mem.alloc[widget.Node](a, 1usize)
    if fill_error != ok { ret (zero, TooLarge) }
    fill[0usize] = widget.box(key + 1u64, filled, zero)
    let (bar, bar_error) = mem.alloc[widget.Node](a, 1usize)
    if bar_error != ok { ret (zero, TooLarge) }
    bar[0usize] = widget.box(0u64, track, fill[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 16u8
    sem.label = label
    if indeterminate { sem.states = accessibility.STATE_BUSY }
    ret (widget.semantics(key, sem, style.defaults(), bar[0usize..1usize]), ok)
}

// What a ring paints: its colours and its share, kept in the frame arena, which
// outlives the paint (a custom node's context is read during placement only), and
// the arena its paths are built in -- the frame's, since the scene copies a path
// when the frame is compiled, after the paint returned.
type Ring = struct { track: paint.Color, fill: paint.Color, share: f32, thickness: f32, arena: *mem.Arena }

fn ring_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

// A circle, or the arc from the top clockwise through `share` of it, as cubic
// quarter turns and one shorter piece; `kappa` puts the control points on the circle.
fn arc_path(a: *mem.Arena, cx: f32, cy: f32, radius: f32, share: f32) -> (geometry.Path, err) {
    // A move, three quarter cubics and a ten-chord fan is fourteen verbs (D913).
    let (pb, pb_error) = geometry.path_builder(a, 16usize, 40usize)
    if pb_error != ok { ret (zero, TooLarge) }
    var builder = pb
    var remaining = share * 4.0
    if remaining > 4.0 { remaining = 4.0 }
    // The quarter turns from the top, clockwise: (0,-1) -> (1,0) -> (0,1) -> (-1,0).
    var xs: [5]f32 = zero
    var ys: [5]f32 = zero
    xs[0usize] = 0.0
    ys[0usize] = 0.0 - 1.0
    xs[1usize] = 1.0
    ys[1usize] = 0.0
    xs[2usize] = 0.0
    ys[2usize] = 1.0
    xs[3usize] = 0.0 - 1.0
    ys[3usize] = 0.0
    xs[4usize] = 0.0
    ys[4usize] = 0.0 - 1.0
    let kappa: f32 = 0.5522847
    let moved = geometry.move_to(&builder, geometry.Point { x: cx, y: cy - radius })
    if moved != ok { ret (zero, TooLarge) }
    var q = 0usize
    while q < 4usize && remaining > 0.0 {
        let x0 = xs[q]
        let y0 = ys[q]
        let x1 = xs[q + 1usize]
        let y1 = ys[q + 1usize]
        // The tangent at the start of a clockwise quarter is the next point's
        // direction; the control points lie kappa along each tangent.
        var part = remaining
        if part > 1.0 { part = 1.0 }
        if part >= 1.0 {
            let c1 = geometry.Point { x: cx + (x0 + kappa * x1) * radius, y: cy + (y0 + kappa * y1) * radius }
            let c2 = geometry.Point { x: cx + (x1 + kappa * x0) * radius, y: cy + (y1 + kappa * y0) * radius }
            let curved = geometry.cubic_to(&builder, c1, c2, geometry.Point { x: cx + x1 * radius, y: cy + y1 * radius })
            if curved != ok { ret (zero, TooLarge) }
        } else {
            // A shorter piece: a fan of short chords through the arc, a chord per tenth.
            var step = 0usize
            let steps = 10usize
            while step < steps {
                let f = f32(step + 1usize) / f32(steps) * part
                // The point at fraction f of the quarter, by the quarter's parametric arc.
                let s = math.sin[f32](f * 1.5707964)
                let c = math.cos[f32](f * 1.5707964)
                let px = x0 * c + x1 * s
                let py = y0 * c + y1 * s
                let lined = geometry.line_to(&builder, geometry.Point { x: cx + px * radius, y: cy + py * radius })
                if lined != ok { ret (zero, TooLarge) }
                step += 1usize
            }
        }
        remaining = remaining - part
        q += 1usize
    }
    ret (geometry.finish(&builder), ok)
}

fn ring_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let ring = mem.cast[*Ring](ctx)
    let scratch = ring.arena
    let cx = area.x + area.width * 0.5
    let cy = area.y + area.height * 0.5
    var radius = area.width
    if area.height < radius { radius = area.height }
    radius = radius * 0.5 - ring.thickness * 0.5
    if radius <= 0.0 { ret ok }
    let stroke = paint.Stroke { width: ring.thickness, cap: .Butt, join: .Round, miter_limit: 4.0 }
    let (track, track_error) = arc_path(scratch, cx, cy, radius, 1.0)
    if track_error != ok { ret track_error }
    try scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: track, brush: paint.Brush { Solid: ring.track }, stroke: stroke } })
    if ring.share <= 0.0 { ret ok }
    let (arc, arc_error) = arc_path(scratch, cx, cy, radius, ring.share)
    if arc_error != ok { ret arc_error }
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: arc, brush: paint.Brush { Solid: ring.fill }, stroke: stroke } })
}

// A progress ring of `size`: the track in the variant surface, the arc from the
// top in the primary colour through `value` of the turn; indeterminate, a quarter
// turn and busy in the tree. A progress role with the label.
fn progress_ring(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, indeterminate: bool, size: f32) -> (widget.Node, err) {
    var share = value
    if share < 0.0 { share = 0.0 }
    if share > 1.0 { share = 1.0 }
    if indeterminate { share = 0.25 }
    let (rings, rings_error) = mem.alloc[Ring](a, 1usize)
    if rings_error != ok { ret (zero, TooLarge) }
    rings[0usize] = Ring { track: style.color(t.tokens, .SurfaceVariant), fill: style.color(t.tokens, .Primary), share: share, thickness: t.tokens.spacing.xs, arena: a }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    var none: []const widget.Node = zero
    body[0usize] = widget.Node { key: key + 1u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&rings[0usize]), measure: ring_measure, paint: ring_paint, state: widget.bytes_of[Ring](&rings[0usize]) } }, style: sized_style(size, size), children: none }
    var sem: widget.Semantics = zero
    sem.role = 16u8
    sem.label = label
    if indeterminate { sem.states = accessibility.STATE_BUSY }
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// ---------------------------------------------------------- text fields (D823, P1-10)

// A field's look and behaviour: the placeholder shown while the value is empty,
// whether it takes input, whether the caller's validation found it invalid, its
// width, and for a text area the rows it shows.
type FieldOptions = struct { placeholder: str, enabled: bool, read_only: bool, invalid: bool, width: f32, rows: u32 }

fn field_options() -> FieldOptions {
    ret FieldOptions { placeholder: "", enabled: true, read_only: false, invalid: false, width: 160.0, rows: 1u32 }
}

// The field every text field is: an outlined surface in the resolved look -- the
// border in the error colour when invalid, the focus ring when focused -- holding
// the editor (keyed `key`) over its placeholder, the label above; the editor says
// text field in the tree, the label names it. The caller owns the buffer and
// keeps the length (D807).
fn field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, change: widget.Change[str], submit: widget.Submit, options: FieldOptions, secret: bool) -> (widget.Node, err) {
    var state = control_state(t, key, options.enabled, false)
    state.invalid = options.invalid
    state.read_only = options.read_only
    let look = style.resolve(t.tokens, .Outlined, state)
    let (text_look, style_error) = text_style(a, t, .Body)
    if style_error != ok { ret (zero, style_error) }
    var multiline = options.rows > 1u32
    // The editor stands its rows tall even before it holds anything (and with no
    // fonts, when it measures as nothing), so a press reaches it.
    var editor_style = style.defaults()
    editor_style.width = style.Length { Percent: 100.0 }
    editor_style.min_height = style.Length { Px: f32(options.rows) * t.tokens.text[0usize].line_height }
    let (editor, editor_error) = mem.alloc[widget.Node](a, 2usize)
    if editor_error != ok { ret (zero, TooLarge) }
    var placeholder_count = 0usize
    if len == 0usize && options.placeholder.len != 0usize { placeholder_count = 1usize }
    var hint = text_options()
    hint.color = .TextMuted
    hint.wrap = .None
    let (hint_node, hint_error) = text_node(a, 0u64, options.placeholder, t, hint)
    if hint_error != ok { ret (zero, hint_error) }
    var at = 0usize
    if placeholder_count != 0usize {
        editor[at] = hint_node
        at += 1usize
    }
    editor[at] = widget.edit(key, widget.Edit { buffer: buffer, len: len, style: text_look, color: look.foreground, selection: style.color(t.tokens, .Selection), change: change, submit: submit, enabled: options.enabled, read_only: options.read_only, multiline: multiline, secret: secret }, editor_style)
    at += 1usize
    var frame_style = style.defaults()
    frame_style.width = style.Length { Px: options.width }
    var height = t.tokens.metrics.control_height
    if multiline { height = f32(options.rows) * t.tokens.text[0usize].line_height + t.tokens.spacing.sm }
    frame_style.min_height = style.Length { Px: height }
    frame_style.background = paint.Brush { Solid: look.background }
    frame_style.border = style.Border { width: look.border_width, color: look.border }
    if look.focus_ring > 0.0 { frame_style.border = style.Border { width: look.focus_ring, color: style.color(t.tokens, .Focus) } }
    frame_style.radius = t.tokens.radii.xs
    frame_style.opacity = look.opacity
    let pad_x = style.Length { Px: t.tokens.spacing.sm }
    let pad_y = style.Length { Px: t.tokens.spacing.xs }
    frame_style.padding = style.EdgeLengths { left: pad_x, top: pad_y, right: pad_x, bottom: pad_y }
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.stack(0u64, frame_style, editor[0usize..at])
    var parts_count = 1usize
    if label.len != 0usize { parts_count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, parts_count)
    if parts_error != ok { ret (zero, TooLarge) }
    if label.len != 0usize {
        var caption = text_options()
        caption.role = .Label
        caption.wrap = .None
        if options.invalid { caption.color = .Error }
        let (label_node, label_error) = text_node(a, 0u64, label, t, caption)
        if label_error != ok { ret (zero, label_error) }
        parts[0usize] = label_node
    }
    parts[parts_count - 1usize] = framed[0usize]
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..parts_count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    if options.invalid { sem.states = accessibility.STATE_INVALID }
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A single-line text field.
fn text_field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, change: widget.Change[str], submit: widget.Submit, options: FieldOptions) -> (widget.Node, err) {
    var single = options
    single.rows = 1u32
    let (node, node_error) = field(a, key, t, label, buffer, len, change, submit, single, false)
    ret (node, node_error)
}

// A password field: the value shown as an asterisk per byte, and never copied.
fn password_field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, change: widget.Change[str], submit: widget.Submit, options: FieldOptions) -> (widget.Node, err) {
    var single = options
    single.rows = 1u32
    let (node, node_error) = field(a, key, t, label, buffer, len, change, submit, single, true)
    ret (node, node_error)
}

// A search field: a single line whose Enter is the search (`submit`), with a clear
// button (keyed `key + 1`, the caller's `clear` action) beside it while it holds
// anything, and "Search" for a placeholder when none is given.
fn search_field(a: *mem.Arena, key: widget.Key, t: *const Theme, buffer: []u8, len: usize, change: widget.Change[str], submit: widget.Submit, clear: *const widget.Submit, options: FieldOptions) -> (widget.Node, err) {
    var single = options
    single.rows = 1u32
    if single.placeholder.len == 0usize { single.placeholder = "Search" }
    let (box_node, box_error) = field(a, key, t, "", buffer, len, change, submit, single, false)
    if box_error != ok { ret (zero, box_error) }
    var count = 1usize
    if len != 0usize { count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = box_node
    if len != 0usize {
        var plain = button_options()
        plain.variant = .Plain
        let (clear_button, clear_error) = button(a, key + 1u64, t, "Clear", clear, plain)
        if clear_error != ok { ret (zero, clear_error) }
        parts[1usize] = clear_button
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..count]), ok)
}

// A text area: a multiline editor `rows` lines tall (two at least).
// ponytail: a text area does not scroll its overflow; a viewport around it waits on the editor reporting its caret's line.
fn text_area(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, change: widget.Change[str], options: FieldOptions) -> (widget.Node, err) {
    var tall = options
    if tall.rows < 2u32 { tall.rows = 2u32 }
    let (node, node_error) = field(a, key, t, label, buffer, len, change, zero, tall, false)
    ret (node, node_error)
}

// -------------------------------------------------------- basic choice (D824, P1-11)

// A select: an outlined button showing the chosen option's label (keyed `key`),
// which fires `toggle` -- the caller opens or closes it; open, a modal overlay
// below the button (keyed `key + 1`) lists the options as menu items keyed
// `key + 2 + index`, each firing its own action, and a press outside fires
// `toggle` again to close. The caller keeps `selected` and `open`.
fn select(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, selected: usize, open: bool, toggle: *const widget.Submit, picks: []const widget.Submit) -> (widget.Node, err) {
    if picks.len != options.len { ret (zero, TooLarge) }
    var shown = label
    if selected < options.len { shown = options[selected] }
    var outlined = button_options()
    outlined.variant = .Outlined
    let (head, head_error) = button(a, key, t, shown, toggle, outlined)
    if head_error != ok { ret (zero, head_error) }
    var count = 1usize
    if open { count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    if open {
        let (items, items_error) = mem.alloc[widget.Node](a, options.len)
        if items_error != ok { ret (zero, TooLarge) }
        var i = 0usize
        while i < options.len {
            var plain = button_options()
            plain.variant = .Plain
            if i == selected { plain.variant = .Filled }
            let (item, item_error) = button(a, key + 2u64 + u64(i), t, options[i], &picks[i], plain)
            if item_error != ok { ret (zero, item_error) }
            var entry: widget.Semantics = zero
            entry.role = 22u8
            entry.label = options[i]
            if i == selected { entry.states = accessibility.STATE_SELECTED }
            let (wrapped, wrapped_error) = mem.alloc[widget.Node](a, 1usize)
            if wrapped_error != ok { ret (zero, TooLarge) }
            wrapped[0usize] = item
            items[i] = widget.semantics(0u64, entry, style.defaults(), wrapped[0usize..1usize])
            i += 1usize
        }
        var sheet = surface_options(t)
        sheet.bordered = true
        sheet.elevation = 2u8
        sheet.radius = t.tokens.radii.xs
        sheet.padding = t.tokens.spacing.xs
        let (menu, menu_error) = mem.alloc[widget.Node](a, 1usize)
        if menu_error != ok { ret (zero, TooLarge) }
        menu[0usize] = widget.box(0u64, surface_style(t, sheet), items[0usize..options.len])
        var menu_sem: widget.Semantics = zero
        menu_sem.role = 21u8
        menu_sem.label = label
        let (popup, popup_error) = mem.alloc[widget.Node](a, 1usize)
        if popup_error != ok { ret (zero, TooLarge) }
        popup[0usize] = widget.semantics(0u64, menu_sem, style.defaults(), menu[0usize..1usize])
        parts[1usize] = widget.overlay(key + 1u64, widget.Overlay { anchor: key, placement: .Below, offset: geometry.Point { x: 0.0, y: t.tokens.spacing.xs }, modal: true, dismiss: *toggle }, style.defaults(), popup[0usize..1usize])
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    if open { sem.states = accessibility.STATE_EXPANDED }
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A list box: the options as rows in a clamped viewport `rows` tall (keyed `key`),
// each a tap region keyed `key + 1 + index` firing its own action, the selected
// one in the selection colour; the viewport is a list of list items in the tree,
// the group above it labelled.
fn list_box(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, selected: usize, picks: []const widget.Submit, rows: u32, width: f32) -> (widget.Node, err) {
    let (chosen, chosen_error) = mem.alloc[bool](a, options.len)
    if chosen_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < options.len {
        chosen[i] = i == selected
        i += 1usize
    }
    let (made, made_error) = listed(a, key, t, label, options, chosen, picks, rows, width)
    ret (made, made_error)
}

// The rows of a list box or a multi-select list: `chosen` says which are selected.
fn listed(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, chosen: []const bool, picks: []const widget.Submit, rows: u32, width: f32) -> (widget.Node, err) {
    if picks.len != options.len || chosen.len != options.len { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[widget.Node](a, options.len)
    if items_error != ok { ret (zero, TooLarge) }
    let row_height = t.tokens.metrics.control_height
    var i = 0usize
    while i < options.len {
        var state = control_state(t, key + 1u64 + u64(i), true, chosen[i])
        let look = style.resolve(t.tokens, .Plain, state)
        var row_style = style.defaults()
        row_style.width = style.Length { Px: width }
        row_style.height = style.Length { Px: row_height }
        var background = look.background
        if chosen[i] { background = style.color(t.tokens, .Selection) }
        row_style.background = paint.Brush { Solid: background }
        let pad = style.Length { Px: t.tokens.spacing.sm }
        row_style.padding = style.EdgeLengths { left: pad, top: style.Length { Px: t.tokens.spacing.xs }, right: pad, bottom: style.Length { Px: t.tokens.spacing.xs } }
        var caption = text_options()
        caption.wrap = .None
        let (text_item, text_error) = text_node(a, 0u64, options[i], t, caption)
        if text_error != ok { ret (zero, text_error) }
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = text_item
        let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
        if region_error != ok { ret (zero, TooLarge) }
        region[0usize] = widget.region(key + 1u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[i]), invoke: press_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, row_style, body[0usize..1usize])
        var entry: widget.Semantics = zero
        entry.role = 11u8
        entry.label = options[i]
        entry.row = u32(i + 1usize)
        entry.row_count = u32(options.len)
        if chosen[i] { entry.states = accessibility.STATE_SELECTED }
        items[i] = widget.semantics(0u64, entry, style.defaults(), region[0usize..1usize])
        i += 1usize
    }
    var view_style = style.defaults()
    view_style.width = style.Length { Px: width }
    view_style.height = style.Length { Px: f32(rows) * row_height }
    view_style.border = style.Border { width: t.tokens.borders.regular, color: style.color(t.tokens, .Border) }
    view_style.radius = t.tokens.radii.xs
    view_style.overflow = .Clip
    let (view, view_error) = widget.scroll_view(a, key, .Vertical, view_style, items[0usize..options.len])
    if view_error != ok { ret (zero, TooLarge) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = view
    // The viewport is the list in the tree; the group above it carries the label.
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    sem.row_count = u32(options.len)
    ret (widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize]), ok)
}


// ---------------------------------------------------------------- forms (D825, P1-12)

// Validation is data: how a field stands and what to tell the person.
type Validity = enum u8 { Valid, Warning, Invalid }
type Message = struct { validity: Validity, text: str }

// A field's label: the label role, an asterisk after a required one, controlling
// the field it is for (by key).
fn field_label(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, for_key: widget.Key, required: bool) -> (widget.Node, err) {
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    var parts_count = 1usize
    if required { parts_count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, parts_count)
    if parts_error != ok { ret (zero, TooLarge) }
    let (label_node, label_error) = text_node(a, 0u64, label, t, caption)
    if label_error != ok { ret (zero, label_error) }
    parts[0usize] = label_node
    if required {
        caption.color = .Error
        let (star, star_error) = text_node(a, 0u64, "*", t, caption)
        if star_error != ok { ret (zero, star_error) }
        parts[1usize] = star
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..parts_count])
    var sem: widget.Semantics = zero
    sem.role = 6u8
    sem.label = label
    sem.controls = for_key
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// A field's message: the caption in the error colour when invalid, muted when
// valid or a warning; a status in the tree, controlling the field, live so a
// reader hears it change. Nothing at all for an empty text.
fn field_message(a: *mem.Arena, key: widget.Key, t: *const Theme, message: Message, for_key: widget.Key) -> (widget.Node, err) {
    var caption = text_options()
    caption.role = .Caption
    caption.color = .TextMuted
    if message.validity == .Invalid { caption.color = .Error }
    if message.validity == .Warning { caption.color = .Text }
    let (text_item, text_error) = text_node(a, 0u64, message.text, t, caption)
    if text_error != ok { ret (zero, text_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = text_item
    var sem: widget.Semantics = zero
    sem.role = 26u8
    sem.label = message.text
    sem.controls = for_key
    sem.live = 1u8
    if message.validity == .Invalid {
        sem.live = 2u8
        sem.states = accessibility.STATE_INVALID
    }
    sem.hidden = message.text.len == 0usize
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// A form field: the label (keyed `key + 1`) above the control, the help or the
// message (keyed `key + 2`) below; a group in the tree labelled by the label,
// described by the help, its error the message when invalid, required and invalid
// as states. `control_key` is the control's own key, for the relationships.
fn form_field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, control_key: widget.Key, control_node: widget.Node, help: str, message: Message, required: bool) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (label_node, label_error) = field_label(a, key + 1u64, t, label, control_key, required)
    if label_error != ok { ret (zero, label_error) }
    parts[0usize] = label_node
    parts[1usize] = control_node
    var shown = message
    if shown.text.len == 0usize { shown = Message { validity: .Valid, text: help } }
    let (message_node, message_error) = field_message(a, key + 2u64, t, shown, control_key)
    if message_error != ok { ret (zero, message_error) }
    parts[2usize] = message_node
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..3usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    sem.labelled_by = key + 1u64
    if help.len != 0usize && message.text.len == 0usize { sem.described_by = key + 2u64 }
    if message.validity == .Invalid && message.text.len != 0usize { sem.error_by = key + 2u64 }
    if required { sem.states = accessibility.STATE_REQUIRED }
    if message.validity == .Invalid { sem.states = sem.states | accessibility.STATE_INVALID }
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A form: its fields in a column -- or, wide enough for the expanded size class,
// in a wrap of two-column width -- under a scope whose Enter is `submit` and whose
// Escape is `cancel`; a group in the tree.
fn form(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, width: f32, fields: []const widget.Node, submit: widget.Submit, cancel: widget.Submit) -> (widget.Node, err) {
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    var layout_style = style.defaults()
    layout_style.width = style.Length { Px: width }
    if style.size_class(width) == .Expanded {
        body[0usize] = widget.wrap(0u64, ui_layout.Wrap { axis: .Horizontal, main_gap: t.tokens.spacing.lg, cross_gap: t.tokens.spacing.md }, layout_style, fields)
    } else {
        body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.md }, layout_style, fields)
    }
    var none: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(key, widget.Scope { traps_focus: false, shortcuts: none, default_action: submit, cancel_action: cancel, keys: zero }, style.defaults(), body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// A validation summary: the invalid messages as links, each firing the caller's
// action for its field (one per message) and controlling that field; an alert in
// the tree, assertive, and nothing when every message is valid.
fn validation_summary(a: *mem.Arena, key: widget.Key, t: *const Theme, messages: []const Message, field_keys: []const widget.Key, jumps: []const widget.Submit) -> (widget.Node, err) {
    if field_keys.len != messages.len || jumps.len != messages.len { ret (zero, TooLarge) }
    var count = 0usize
    var i = 0usize
    while i < messages.len {
        if messages[i].validity == .Invalid && messages[i].text.len != 0usize { count += 1usize }
        i += 1usize
    }
    let (items, items_error) = mem.alloc[widget.Node](a, count)
    if items_error != ok { ret (zero, TooLarge) }
    var at = 0usize
    i = 0usize
    while i < messages.len {
        if messages[i].validity == .Invalid && messages[i].text.len != 0usize {
            let (item, item_error) = link(a, key + 1u64 + u64(i), t, messages[i].text, &jumps[i])
            if item_error != ok { ret (zero, item_error) }
            var entry: widget.Semantics = zero
            entry.controls = field_keys[i]
            let (wrapped, wrapped_error) = mem.alloc[widget.Node](a, 1usize)
            if wrapped_error != ok { ret (zero, TooLarge) }
            wrapped[0usize] = item
            items[at] = widget.semantics(0u64, entry, style.defaults(), wrapped[0usize..1usize])
            at += 1usize
        }
        i += 1usize
    }
    var options = surface_options(t)
    options.bordered = true
    options.radius = t.tokens.radii.xs
    options.padding = t.tokens.spacing.sm
    var sheet = surface_style(t, options)
    sheet.border = style.Border { width: t.tokens.borders.regular, color: style.color(t.tokens, .Error) }
    if count == 0usize { sheet = style.defaults() }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, sheet, items[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 24u8
    sem.live = 2u8
    sem.hidden = count == 0usize
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// ------------------------------------------- disclosure and panes (D826, P1-13)

// The disclosure mark: a triangle pointing right, or down when expanded, in the
// text colour, painted into the frame arena.
type Mark = struct { color: paint.Color, expanded: bool, arena: *mem.Arena }

fn mark_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

fn mark_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let m = mem.cast[*Mark](ctx)
    let (pb, pb_error) = geometry.path_builder(m.arena, 4usize, 4usize)
    if pb_error != ok { ret TooLarge }
    var builder = pb
    let inset = area.width * 0.25
    let x0 = area.x + inset
    let y0 = area.y + inset
    let x1 = area.x + area.width - inset
    let y1 = area.y + area.height - inset
    let xm = area.x + area.width * 0.5
    let ym = area.y + area.height * 0.5
    if m.expanded {
        try geometry.move_to(&builder, geometry.Point { x: x0, y: y0 })
        try geometry.line_to(&builder, geometry.Point { x: x1, y: y0 })
        try geometry.line_to(&builder, geometry.Point { x: xm, y: y1 })
    } else {
        try geometry.move_to(&builder, geometry.Point { x: x0, y: y0 })
        try geometry.line_to(&builder, geometry.Point { x: x1, y: ym })
        try geometry.line_to(&builder, geometry.Point { x: x0, y: y1 })
    }
    try geometry.close_path(&builder)
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&builder), brush: paint.Brush { Solid: m.color } } })
}

// A disclosure: a plain header button of the mark and the label firing `toggle`,
// the content below it only while `expanded` (the caller keeps that); the header
// says expanded or not in the tree, offers the other, and controls the content,
// a group keyed `key + 1`.
fn disclosure(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, expanded: bool, toggle: *const widget.Submit, content: widget.Node) -> (widget.Node, err) {
    let look = style.resolve(t.tokens, .Plain, control_state(t, key, true, false))
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, TooLarge) }
    marks[0usize] = Mark { color: look.foreground, expanded: expanded, arena: a }
    let (head, head_error) = mem.alloc[widget.Node](a, 2usize)
    if head_error != ok { ret (zero, TooLarge) }
    let size = t.tokens.text[0usize].line_height
    var none: []const widget.Node = zero
    head[0usize] = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: sized_style(size, size), children: none }
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, look.foreground)
    if label_error != ok { ret (zero, label_error) }
    head[1usize] = label_node
    let header = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), head[0usize..2usize])
    var states = 0u32
    var actions = accessibility.ACTION_EXPAND
    if expanded {
        states = accessibility.STATE_EXPANDED
        actions = accessibility.ACTION_COLLAPSE
    }
    let (button_node, button_error) = pressable_states(a, key, t, 3u8, label, look, true, false, states, actions, key + 1u64, toggle, header)
    if button_error != ok { ret (zero, button_error) }
    var count = 1usize
    if expanded { count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = button_node
    if expanded {
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = content
        var sem: widget.Semantics = zero
        sem.role = 2u8
        sem.labelled_by = key
        var padded = style.defaults()
        padded.padding = style.EdgeLengths { left: style.Length { Px: size + t.tokens.spacing.xs }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
        parts[1usize] = widget.semantics(key + 1u64, sem, padded, body[0usize..1usize])
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..count]), ok)
}

// An expander: a disclosure on a bordered, rounded, padded surface.
fn expander(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, expanded: bool, toggle: *const widget.Submit, content: widget.Node) -> (widget.Node, err) {
    let (opened, opened_error) = disclosure(a, key, t, label, expanded, toggle, content)
    if opened_error != ok { ret (zero, opened_error) }
    let (sheet, sheet_error) = mem.alloc[widget.Node](a, 1usize)
    if sheet_error != ok { ret (zero, TooLarge) }
    sheet[0usize] = opened
    var options = surface_options(t)
    options.bordered = true
    options.radius = t.tokens.radii.xs
    options.padding = t.tokens.spacing.sm
    ret (widget.box(0u64, surface_style(t, options), sheet[0usize..1usize]), ok)
}

// A tab list: a row of plain tab buttons keyed `key + 1 + index`, the selected one
// underlined in the primary colour and selected in the tree, each firing its own
// pick; Left and Right on a focused tab pick its neighbours.
fn tabs(a: *mem.Arena, key: widget.Key, t: *const Theme, labels: []const str, selected: usize, picks: []const widget.Submit) -> (widget.Node, err) {
    if picks.len != labels.len { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[widget.Node](a, labels.len)
    if items_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < labels.len {
        let chosen = i == selected
        let tab_key = key + 1u64 + u64(i)
        let look = style.resolve(t.tokens, .Plain, control_state(t, tab_key, true, chosen))
        let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
        if parts_error != ok { ret (zero, TooLarge) }
        var caption = text_options()
        caption.role = .Label
        caption.wrap = .None
        var ink = look.foreground
        if chosen { ink = style.color(t.tokens, .Primary) }
        let (label_node, label_error) = colored_text(a, 0u64, labels[i], t, caption, ink)
        if label_error != ok { ret (zero, label_error) }
        parts[0usize] = label_node
        var line = style.defaults()
        line.width = style.Length { Percent: 100.0 }
        line.height = style.Length { Px: t.tokens.borders.thick }
        if chosen { line.background = paint.Brush { Solid: style.color(t.tokens, .Primary) } }
        parts[1usize] = widget.box(0u64, line, zero)
        let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .End, cross: .Stretch, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..2usize])
        let (tab, tab_error) = pressable_states(a, tab_key, t, 19u8, labels[i], look, true, chosen, 0u32, 0u32, 0u64, &picks[i], column)
        if tab_error != ok { ret (zero, tab_error) }
        items[i] = tab
        i += 1usize
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .End, gap: 0.0 }, style.defaults(), items[0usize..labels.len])
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    var bound = 0usize
    if selected > 0usize && selected < labels.len {
        shortcuts[bound] = widget.Shortcut { key: 37u32, modifiers: zero, action: picks[selected - 1usize] }
        bound += 1usize
    }
    if selected + 1usize < labels.len {
        shortcuts[bound] = widget.Shortcut { key: 39u32, modifiers: zero, action: picks[selected + 1usize] }
        bound += 1usize
    }
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..bound], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), row[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 20u8
    sem.column_count = u32(labels.len)
    ret (widget.semantics(key, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// A tab view: the tab list (keyed `key + 1`) above the selected page alone, a group
// labelled by the selected tab.
fn tab_view(a: *mem.Arena, key: widget.Key, t: *const Theme, labels: []const str, selected: usize, picks: []const widget.Submit, pages: []const widget.Node) -> (widget.Node, err) {
    if pages.len != labels.len || selected >= labels.len { ret (zero, TooLarge) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (strip, strip_error) = tabs(a, key + 1u64, t, labels, selected, picks)
    if strip_error != ok { ret (zero, strip_error) }
    parts[0usize] = strip
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = pages[selected]
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.labelled_by = key + 2u64 + u64(selected)
    parts[1usize] = widget.semantics(key, sem, style.defaults(), body[0usize..1usize])
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: t.tokens.spacing.sm }, style.defaults(), parts[0usize..2usize]), ok)
}

// A pane handle's state for the frame: where the pane is, its limits, and whom to
// tell. A drag reports the pointer's distance from the pane's origin, the pointer
// taken as the handle's middle; a nudge
// reports the size moved by a step; both are clamped to `low..high`, and with no
// `high` to the extent of the element `bound` names less `reserve` (no bound: no
// upper limit).
type Handle = struct { runtime: *widget.Runtime, pane: widget.Key, bound: widget.Key, vertical: bool, size: f32, thick: f32, low: f32, high: f32, reserve: f32, change: widget.Change[f32] }
type Nudge = struct { handle: *Handle, amount: f32 }

fn keyed_bounds(runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (s, state_error) = widget.state_of(runtime)
    if state_error != ok { ret (zero, false) }
    let (id, count) = widget.find_by_key(s, key)
    if count == 0usize { ret (zero, false) }
    let (area, has_area) = widget.bounds_of(runtime, id)
    ret (area, has_area)
}

fn handle_report(h: *const Handle, wanted: f32) -> err {
    var value = wanted
    if h.high > 0.0 {
        if value > h.high { value = h.high }
    } else {
        if h.bound != 0u64 {
            let (area, has_area) = keyed_bounds(h.runtime, h.bound)
            if has_area {
                var extent = area.width
                if h.vertical { extent = area.height }
                if value > extent - h.reserve { value = extent - h.reserve }
            }
        }
    }
    if value < h.low { value = h.low }
    ret widget.fire_change[f32](h.change, value)
}

fn handle_drag(ctx: *void, g: widget.Gesture) -> err {
    let h = mem.cast[*Handle](ctx)
    switch g {
    case .DragMove as d:
        let (area, has_area) = keyed_bounds(h.runtime, h.pane)
        if !has_area { ret ok }
        if h.vertical { ret handle_report(h, d.position.y - area.y - h.thick * 0.5) }
        ret handle_report(h, d.position.x - area.x - h.thick * 0.5)
    default:
        ret ok
    }
}

fn handle_nudge(ctx: *void) -> err {
    let n = mem.cast[*Nudge](ctx)
    ret handle_report(n.handle, n.handle.size + n.amount)
}

// A resizable pane: the content sized `size` along `axis` (the caller keeps the
// size and hears each change), a handle after it in the border colour, focusable,
// dragged or moved by the arrow keys a medium space at a time, between `low` and
// `high` (0: no limit). The handle is a slider in the
// tree named `label`. The pane is keyed `key + 1`, the handle `key + 2`.
fn resizable_pane(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, axis: ui_layout.Axis, size: f32, low: f32, high: f32, change: widget.Change[f32], content: widget.Node) -> (widget.Node, err) {
    let (made, made_error) = pane_with_reserve(a, key, t, label, axis, size, low, high, 0u64, 0.0, change, content)
    ret (made, made_error)
}

fn pane_with_reserve(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, axis: ui_layout.Axis, size: f32, low: f32, high: f32, bound: widget.Key, reserve: f32, change: widget.Change[f32], content: widget.Node) -> (widget.Node, err) {
    let vertical = axis == .Vertical
    let (handles, handles_error) = mem.alloc[Handle](a, 1usize)
    if handles_error != ok { ret (zero, TooLarge) }
    handles[0usize] = Handle { runtime: t.runtime, pane: key, bound: bound, vertical: vertical, size: size, thick: t.tokens.spacing.xs, low: low, high: high, reserve: reserve, change: change }
    let (nudges, nudges_error) = mem.alloc[Nudge](a, 2usize)
    if nudges_error != ok { ret (zero, TooLarge) }
    nudges[0usize] = Nudge { handle: &handles[0usize], amount: 0.0 - t.tokens.spacing.md }
    nudges[1usize] = Nudge { handle: &handles[0usize], amount: t.tokens.spacing.md }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var pane_style = style.defaults()
    pane_style.overflow = .Clip
    var grip = style.defaults()
    grip.background = paint.Brush { Solid: style.color(t.tokens, .Border) }
    let thick = style.Length { Px: t.tokens.spacing.xs }
    let full = style.Length { Percent: 100.0 }
    if vertical {
        pane_style.height = style.Length { Px: size }
        pane_style.width = full
        grip.height = thick
        grip.width = full
    } else {
        pane_style.width = style.Length { Px: size }
        pane_style.height = full
        grip.width = thick
        grip.height = full
    }
    parts[0usize] = widget.box(key + 1u64, pane_style, body[0usize..1usize])
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    var less = 37u32
    var more = 39u32
    if vertical {
        less = 38u32
        more = 40u32
    }
    shortcuts[0usize] = widget.Shortcut { key: less, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&nudges[0usize]), invoke: handle_nudge } }
    shortcuts[1usize] = widget.Shortcut { key: more, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&nudges[1usize]), invoke: handle_nudge } }
    let (grip_node, grip_error) = mem.alloc[widget.Node](a, 1usize)
    if grip_error != ok { ret (zero, TooLarge) }
    grip_node[0usize] = widget.region(key + 2u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&handles[0usize]), invoke: handle_drag }, gestures: 2u8 | 4u8, enabled: true, focusable: true }, grip, zero)
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..2usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), grip_node[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 15u8
    sem.label = label
    sem.actions = accessibility.ACTION_INCREMENT | accessibility.ACTION_DECREMENT
    sem.controls = key + 1u64
    parts[1usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    ret (widget.flex(key, ui_layout.Flex { axis: axis, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

// A split view: `first` in a resizable pane sized `position` along `axis`, then
// `second` filling the rest; the handle between them keeps `min_first` and
// `min_second` of each. The pane is keyed `key + 1` (its content `key + 2`, its
// handle `key + 3`); a group in the tree.
fn split_view(a: *mem.Arena, key: widget.Key, t: *const Theme, axis: ui_layout.Axis, first: widget.Node, second: widget.Node, position: f32, min_first: f32, min_second: f32, change: widget.Change[f32], width: f32, height: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (pane, pane_error) = pane_with_reserve(a, key + 1u64, t, "Divider", axis, position, min_first, 0.0, key, min_second, change, first)
    if pane_error != ok { ret (zero, pane_error) }
    parts[0usize] = pane
    let (rest, rest_error) = mem.alloc[widget.Node](a, 1usize)
    if rest_error != ok { ret (zero, TooLarge) }
    rest[0usize] = second
    var rest_style = style.defaults()
    rest_style.overflow = .Clip
    if axis == .Vertical {
        rest_style.height = style.Length { Flex: 1.0 }
        rest_style.width = style.Length { Percent: 100.0 }
    } else {
        rest_style.width = style.Length { Flex: 1.0 }
        rest_style.height = style.Length { Percent: 100.0 }
    }
    parts[1usize] = widget.box(0u64, rest_style, rest[0usize..1usize])
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: axis, main: .Start, cross: .Stretch, gap: 0.0 }, sized_style(width, height), parts[0usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// ------------------------------------------------- advanced actions (D829, P2-01)

// A split button: the primary action as a filled button keyed `key`, joined to a
// narrower filled button keyed `key + 1` firing `toggle` for the menu the caller
// places (D827's `overlay.menu`, anchored to `key + 1` and keyed `key + 2`); the
// second says expanded while `open`, offers the menu and controls it.
fn split_button(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, action: *const widget.Submit, open: bool, toggle: *const widget.Submit) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (head, head_error) = button(a, key, t, label, action, button_options())
    if head_error != ok { ret (zero, head_error) }
    parts[0usize] = head
    let look = style.resolve(t.tokens, .Filled, control_state(t, key + 1u64, true, false))
    var states = 0u32
    if open { states = accessibility.STATE_EXPANDED }
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, TooLarge) }
    marks[0usize] = Mark { color: look.foreground, expanded: true, arena: a }
    let size = t.tokens.spacing.md
    var none: []const widget.Node = zero
    let chevron = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: sized_style(size, size), children: none }
    let (tail, tail_error) = pressable_states(a, key + 1u64, t, 3u8, "More", look, true, false, states, accessibility.ACTION_SHOW_MENU, key + 2u64, toggle, chevron)
    if tail_error != ok { ret (zero, tail_error) }
    parts[1usize] = tail
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: t.tokens.borders.hairline }, style.defaults(), parts[0usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(0u64, sem, style.defaults(), row[0usize..1usize]), ok)
}

// A speed dial: a round filled button keyed `key` firing `toggle`, and while
// `open` a modal overlay above it (keyed `key + 1`) of the actions as filled
// buttons keyed `key + 2 + index`, a press outside firing `toggle` again. The
// button says expanded in the tree and controls the list.
fn speed_dial(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, labels: []const str, actions: []const widget.Submit, open: bool, toggle: *const widget.Submit) -> (widget.Node, err) {
    if actions.len != labels.len { ret (zero, TooLarge) }
    // v2 (D944, docs/ux/components/SpeedDial): the head is the FAB -- 56 tall,
    // `radius-lg`, `primary-container`, elevation 3 -- and, open, the `primary`
    // close circle; the items are 56-tall `primary-container` pills at elevation 2,
    // 16 before the label and 24 after, 4 apart and 8 above the head.
    var head_variant: style.ControlVariant = .Container
    if open { head_variant = .Filled }
    var look = style.resolve(t.tokens, head_variant, control_state(t, key, true, false))
    let side = t.tokens.sizes.control_xl
    look.radius = t.tokens.radii.lg
    if open {
        look.radius = side * 0.5
        look.elevation = 3u8
    }
    look.custom_padding = true
    look.padding = 16.0
    look.padding_y = max_zero((side - style.text_style(t.tokens, .Label).line_height) * 0.5)
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, look.foreground)
    if label_error != ok { ret (zero, label_error) }
    var states = 0u32
    if open { states = accessibility.STATE_EXPANDED }
    look.min_width = side
    look.min_height = side
    let (head, head_error) = pressable_states(a, key, t, 3u8, label, look, true, false, states, accessibility.ACTION_EXPAND, key + 1u64, toggle, label_node)
    if head_error != ok { ret (zero, head_error) }
    var count = 1usize
    if open { count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    if open {
        let (items, items_error) = mem.alloc[widget.Node](a, labels.len)
        if items_error != ok { ret (zero, TooLarge) }
        var i = 0usize
        while i < labels.len {
            let item_key = key + 2u64 + u64(i)
            var pill = style.resolve(t.tokens, .Container, control_state(t, item_key, true, false))
            pill.elevation = 2u8
            pill.radius = side * 0.5
            pill.custom_padding = true
            pill.padding_start = 16.0
            pill.padding = 24.0
            pill.padding_y = max_zero((side - style.text_style(t.tokens, .TitleMedium).line_height) * 0.5)
            var words = text_options()
            words.role = .TitleMedium
            words.wrap = .None
            let (word, word_error) = colored_text(a, 0u64, labels[i], t, words, pill.foreground)
            if word_error != ok { ret (zero, word_error) }
            pill.min_height = side
            let (item, item_error) = pressable(a, item_key, t, 3u8, labels[i], pill, true, false, &actions[i], word)
            if item_error != ok { ret (zero, item_error) }
            items[i] = item
            i += 1usize
        }
        let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
        if column_error != ok { ret (zero, TooLarge) }
        column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .End, cross: .End, gap: 4.0 }, style.defaults(), items[0usize..labels.len])
        var sem: widget.Semantics = zero
        sem.role = 2u8
        sem.label = label
        let (lifted, lifted_error) = mem.alloc[widget.Node](a, 1usize)
        if lifted_error != ok { ret (zero, TooLarge) }
        lifted[0usize] = widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize])
        parts[1usize] = widget.overlay(key + 1u64, widget.Overlay { anchor: key, placement: .Above, offset: geometry.Point { x: 0.0, y: 0.0 - 8.0 }, modal: true, dismiss: *toggle }, style.defaults(), lifted[0usize..1usize])
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..count]), ok)
}

// What a chip does: an assist chip is a small button, a filter chip a toggle the
// caller keeps `selected`, an input chip a label with a remove button (keyed
// `key + 1`, firing `remove`), a suggestion chip a plain button.
type ChipKind = enum u8 { Assist, Filter, Input, Suggestion }

fn chip(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, kind: ChipKind, selected: bool, action: *const widget.Submit, remove: *const widget.Submit) -> (widget.Node, err) {
    var variant: style.ControlVariant = .Outlined
    if kind == .Suggestion { variant = .Plain }
    var chosen = false
    if kind == .Filter && selected {
        chosen = true
        variant = .Filled
    }
    var look = style.resolve(t.tokens, variant, control_state(t, key, true, chosen))
    look.radius = t.tokens.metrics.control_height * 0.5
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, look.foreground)
    if label_error != ok { ret (zero, label_error) }
    var states = 0u32
    if kind == .Filter && selected { states = accessibility.STATE_CHECKED }
    var content = label_node
    if kind == .Input {
        let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
        if parts_error != ok { ret (zero, TooLarge) }
        parts[0usize] = label_node
        var cross = text_options()
        cross.role = .Label
        cross.wrap = .None
        let (cross_node, cross_error) = colored_text(a, 0u64, "x", t, cross, look.foreground)
        if cross_error != ok { ret (zero, cross_error) }
        let (removed, removed_error) = mem.alloc[widget.Node](a, 1usize)
        if removed_error != ok { ret (zero, TooLarge) }
        removed[0usize] = cross_node
        let (hit, hit_error) = mem.alloc[widget.Node](a, 1usize)
        if hit_error != ok { ret (zero, TooLarge) }
        var small = style.defaults()
        small.min_width = style.Length { Px: t.tokens.spacing.lg }
        small.min_height = style.Length { Px: t.tokens.spacing.lg }
        hit[0usize] = widget.region(key + 1u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](remove), invoke: press_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, small, removed[0usize..1usize])
        var remove_sem: widget.Semantics = zero
        remove_sem.role = 3u8
        remove_sem.label = "Remove"
        remove_sem.actions = accessibility.ACTION_PRESS
        parts[1usize] = widget.semantics(0u64, remove_sem, style.defaults(), hit[0usize..1usize])
        content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..2usize])
    }
    var role = 3u8
    if kind == .Filter { role = 4u8 }
    let (node, node_error) = pressable_states(a, key, t, role, label, look, true, chosen, states, 0u32, 0u64, action, content)
    ret (node, node_error)
}

// A rating's star, painted: five points about the middle, filled or outlined in
// the primary colour.
type Star = struct { color: paint.Color, filled: bool, arena: *mem.Arena }

fn star_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let star = mem.cast[*Star](ctx)
    let (pb, pb_error) = geometry.path_builder(star.arena, 12usize, 12usize)
    if pb_error != ok { ret TooLarge }
    var builder = pb
    let cx = area.x + area.width * 0.5
    let cy = area.y + area.height * 0.5
    var outer = area.width
    if area.height < outer { outer = area.height }
    outer = outer * 0.5 - 1.0
    let inner = outer * 0.4
    var i = 0usize
    while i < 10usize {
        // Ten vertices, from the top, alternating the outer and inner radius.
        let angle = 0.0 - 1.5707964 + f32(i) * 0.62831855
        var radius = outer
        if i % 2usize == 1usize { radius = inner }
        let p = geometry.Point { x: cx + math.cos[f32](angle) * radius, y: cy + math.sin[f32](angle) * radius }
        if i == 0usize {
            try geometry.move_to(&builder, p)
        } else {
            try geometry.line_to(&builder, p)
        }
        i += 1usize
    }
    try geometry.close_path(&builder)
    let path = geometry.finish(&builder)
    if star.filled { ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: star.color } } }) }
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: path, brush: paint.Brush { Solid: star.color }, stroke: paint.Stroke { width: 1.0, cap: .Butt, join: .Miter, miter_limit: 4.0 } } })
}

// A rating's keyboard: Left and Right move the value by one within `0..max`.
type Rate = struct { value: u32, max: u32, up: bool, change: widget.Change[u32] }

fn rate_step(ctx: *void) -> err {
    let r = mem.cast[*Rate](ctx)
    var next = r.value
    if r.up {
        if next < r.max { next += 1u32 }
    } else {
        if next > 0u32 { next = next - 1u32 }
    }
    ret widget.fire_change[u32](r.change, next)
}

// A tap on the star `index` sets the rating to it.
type Rated = struct { value: u32, change: widget.Change[u32] }

fn rate_tap(ctx: *void, g: widget.Gesture) -> err {
    if g.tag != .Tap { ret ok }
    let r = mem.cast[*Rated](ctx)
    ret widget.fire_change[u32](r.change, r.value)
}

// A rating: `max` stars in a row, the first `value` filled, each a tap region
// keyed `key + 1 + index` setting the value to its number; the row a focus
// target whose Left and Right step the value; a slider in the tree named `label`
// with the value as digits.
fn rating(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: u32, max: u32, change: widget.Change[u32]) -> (widget.Node, err) {
    if max == 0u32 || max > 32u32 { ret (zero, TooLarge) }
    let count = usize(max)
    let (stars, stars_error) = mem.alloc[Star](a, count)
    if stars_error != ok { ret (zero, TooLarge) }
    let (rated, rated_error) = mem.alloc[Rated](a, count)
    if rated_error != ok { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[widget.Node](a, count)
    if items_error != ok { ret (zero, TooLarge) }
    let size = t.tokens.metrics.control_height - 2.0 * t.tokens.spacing.xs
    var none: []const widget.Node = zero
    var i = 0usize
    while i < count {
        stars[i] = Star { color: style.color(t.tokens, .Primary), filled: u32(i) < value, arena: a }
        rated[i] = Rated { value: u32(i) + 1u32, change: change }
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&stars[i]), measure: mark_measure, paint: star_paint, state: widget.bytes_of[Star](&stars[i]) } }, style: sized_style(size, size), children: none }
        items[i] = widget.region(key + 1u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&rated[i]), invoke: rate_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: false }, style.defaults(), body[0usize..1usize])
        i += 1usize
    }
    let (steps, steps_error) = mem.alloc[Rate](a, 2usize)
    if steps_error != ok { ret (zero, TooLarge) }
    steps[0usize] = Rate { value: value, max: max, up: false, change: change }
    steps[1usize] = Rate { value: value, max: max, up: true, change: change }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 37u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&steps[0usize]), invoke: rate_step } }
    shortcuts[1usize] = widget.Shortcut { key: 39u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&steps[1usize]), invoke: rate_step } }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), items[0usize..count])
    // The row is one focus target so the keyboard reaches it; a press on a star
    // lands on the star, whose region is under it.
    var none_gesture: widget.GestureAction = zero
    let (focus, focus_error) = mem.alloc[widget.Node](a, 1usize)
    if focus_error != ok { ret (zero, TooLarge) }
    focus[0usize] = widget.region(key, widget.Region { gesture: none_gesture, gestures: 0u8, enabled: true, focusable: true }, style.defaults(), row[0usize..1usize])
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..2usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), focus[0usize..1usize])
    let (digits, digits_error) = mem.alloc[u8](a, 2usize)
    if digits_error != ok { ret (zero, TooLarge) }
    var digit_count = 0usize
    if value >= 10u32 {
        digits[0usize] = u8(48u32 + value / 10u32)
        digit_count = 1usize
    }
    digits[digit_count] = u8(48u32 + value % 10u32)
    digit_count += 1usize
    var sem: widget.Semantics = zero
    sem.role = 15u8
    sem.label = label
    sem.value = digits[0usize..digit_count]
    sem.actions = accessibility.ACTION_INCREMENT | accessibility.ACTION_DECREMENT | accessibility.ACTION_SET_VALUE
    ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// ------------------------------------------ numeric and shortcut input (D830, P2-02)

// A signed integer as decimal digits into `out`; the length written (0 when it
// does not fit).
fn write_i64(out: []u8, value: i64) -> usize {
    var digits: [20]u8 = zero
    var count = 0usize
    var magnitude = value
    let negative = value < 0i64
    if negative { magnitude = 0i64 - value }
    if magnitude == 0i64 {
        digits[0usize] = 48u8
        count = 1usize
    }
    while magnitude > 0i64 {
        digits[count] = u8(48i64 + magnitude % 10i64)
        magnitude = magnitude / 10i64
        count += 1usize
    }
    var needed = count
    if negative { needed += 1usize }
    if needed > out.len { ret 0usize }
    var at = 0usize
    if negative {
        out[0usize] = 45u8
        at = 1usize
    }
    while count > 0usize {
        count = count - 1usize
        out[at] = digits[count]
        at += 1usize
    }
    ret at
}

// A step of an integer value: what it is, its limits, the amount, whom to tell.
type Step = struct { value: i64, low: i64, high: i64, amount: i64, change: widget.Change[i64] }

fn step_fire(ctx: *void) -> err {
    let s = mem.cast[*Step](ctx)
    var next = s.value + s.amount
    if next > s.high { next = s.high }
    if next < s.low { next = s.low }
    if next == s.value { ret ok }
    ret widget.fire_change[i64](s.change, next)
}

// The two step buttons (keyed `less` and `more`) and the Up/Down shortcuts of a
// stepper or a spin box, the steps allocated for the frame.
fn step_pair(a: *mem.Arena, t: *const Theme, less: widget.Key, more: widget.Key, value: i64, low: i64, high: i64, step: i64, change: widget.Change[i64]) -> ([]widget.Node, []widget.Shortcut, err) {
    let (steps, steps_error) = mem.alloc[Step](a, 2usize)
    if steps_error != ok { ret (zero, zero, TooLarge) }
    steps[0usize] = Step { value: value, low: low, high: high, amount: 0i64 - step, change: change }
    steps[1usize] = Step { value: value, low: low, high: high, amount: step, change: change }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { ret (zero, zero, TooLarge) }
    actions[0usize] = widget.Submit { ctx: mem.cast[*void](&steps[0usize]), invoke: step_fire }
    actions[1usize] = widget.Submit { ctx: mem.cast[*void](&steps[1usize]), invoke: step_fire }
    let (buttons, buttons_error) = mem.alloc[widget.Node](a, 2usize)
    if buttons_error != ok { ret (zero, zero, TooLarge) }
    var down = button_options()
    down.variant = .Outlined
    down.enabled = value > low
    let (minus, minus_error) = button(a, less, t, "-", &actions[0usize], down)
    if minus_error != ok { ret (zero, zero, minus_error) }
    buttons[0usize] = minus
    var up = button_options()
    up.variant = .Outlined
    up.enabled = value < high
    let (plus, plus_error) = button(a, more, t, "+", &actions[1usize], up)
    if plus_error != ok { ret (zero, zero, plus_error) }
    buttons[1usize] = plus
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if shortcuts_error != ok { ret (zero, zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 40u32, modifiers: zero, action: actions[0usize] }
    shortcuts[1usize] = widget.Shortcut { key: 38u32, modifiers: zero, action: actions[1usize] }
    ret (buttons, shortcuts, ok)
}

// The row of a stepper or a spin box under its scope and its slider semantics.
fn stepped(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: i64, middle: widget.Node, buttons: []widget.Node, shortcuts: []widget.Shortcut, role: u8) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = buttons[0usize]
    parts[1usize] = middle
    parts[2usize] = buttons[1usize]
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..3usize])
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..2usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), row[0usize..1usize])
    let (digits, digits_error) = mem.alloc[u8](a, 21usize)
    if digits_error != ok { ret (zero, TooLarge) }
    let digit_count = write_i64(digits, value)
    var sem: widget.Semantics = zero
    sem.role = role
    sem.label = label
    sem.value = digits[0usize..digit_count]
    sem.actions = accessibility.ACTION_INCREMENT | accessibility.ACTION_DECREMENT
    ret (widget.semantics(key, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// A stepper: the value as text between a "-" button (keyed `key + 1`) and a "+"
// button (`key + 2`), each disabled at its bound, moving the caller's `value` by
// `step` within `low..high`; Up and Down from either do the same. A slider in the
// tree named `label` with the value as digits.
fn stepper(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: i64, low: i64, high: i64, step: i64, change: widget.Change[i64]) -> (widget.Node, err) {
    let (buttons, shortcuts, pair_error) = step_pair(a, t, key + 1u64, key + 2u64, value, low, high, step, change)
    if pair_error != ok { ret (zero, pair_error) }
    let (digits, digits_error) = mem.alloc[u8](a, 21usize)
    if digits_error != ok { ret (zero, TooLarge) }
    let digit_count = write_i64(digits, value)
    var caption = text_options()
    caption.role = .Body
    caption.wrap = .None
    caption.align = .Center
    let (shown, shown_error) = text_node(a, 0u64, digits[0usize..digit_count], t, caption)
    if shown_error != ok { ret (zero, shown_error) }
    var fixed = shown
    fixed.style.min_width = style.Length { Px: t.tokens.metrics.hit_target }
    let (made, made_error) = stepped(a, key, t, label, value, fixed, buttons, shortcuts, 15u8)
    ret (made, made_error)
}

// A spin box: a text field (keyed `key`) over the caller's `buffer` showing
// `value` as digits, between the stepper's buttons (`key + 1`, `key + 2`); typed
// text reaches `typed` for the caller to parse, the buttons and Up/Down move
// `value` through `change`. A group in the tree named `label`, the field inside
// it labelled the same.
fn spin_box(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, value: i64, low: i64, high: i64, step: i64, change: widget.Change[i64], typed: widget.Change[str]) -> (widget.Node, err) {
    let (buttons, shortcuts, pair_error) = step_pair(a, t, key + 1u64, key + 2u64, value, low, high, step, change)
    if pair_error != ok { ret (zero, pair_error) }
    let len = write_i64(buffer, value)
    var options = field_options()
    options.width = 4.0 * t.tokens.spacing.lg
    let (editor, editor_error) = text_field(a, key, t, label, buffer, len, typed, zero, options)
    if editor_error != ok { ret (zero, editor_error) }
    let (made, made_error) = stepped(a, key + 3u64, t, label, value, editor, buttons, shortcuts, 2u8)
    ret (made, made_error)
}

// A dial's paint and pointer: the value's share of the turn, where it is, whom to
// tell. The knob is a stroked circle with a line from the middle at the share's
// angle, which runs three quarters of a turn from the lower left clockwise.
type Knob = struct { runtime: *widget.Runtime, key: widget.Key, track: paint.Color, fill: paint.Color, share: f32, low: f32, high: f32, change: widget.Change[f32], arena: *mem.Arena }

fn knob_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let k = mem.cast[*Knob](ctx)
    let cx = area.x + area.width * 0.5
    let cy = area.y + area.height * 0.5
    var radius = area.width
    if area.height < radius { radius = area.height }
    radius = radius * 0.5 - 2.0
    if radius <= 0.0 { ret ok }
    let (ring, ring_error) = arc_path(k.arena, cx, cy, radius, 1.0)
    if ring_error != ok { ret ring_error }
    let stroke = paint.Stroke { width: 2.0, cap: .Round, join: .Round, miter_limit: 4.0 }
    try scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: ring, brush: paint.Brush { Solid: k.track }, stroke: stroke } })
    let angle = 0.0 - 2.3561945 + k.share * 4.712389
    let (pb, pb_error) = geometry.path_builder(k.arena, 2usize, 2usize)
    if pb_error != ok { ret TooLarge }
    var builder = pb
    try geometry.move_to(&builder, geometry.Point { x: cx, y: cy })
    try geometry.line_to(&builder, geometry.Point { x: cx + math.sin[f32](angle) * radius, y: cy - math.cos[f32](angle) * radius })
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: geometry.finish(&builder), brush: paint.Brush { Solid: k.fill }, stroke: stroke } })
}

// The pointer's angle about the knob's middle, clockwise from the top, becomes
// the share of the three-quarter turn; outside the turn the share is the nearer end.
fn knob_at(k: *const Knob, p: geometry.Point) -> err {
    let (area, has_area) = keyed_bounds(k.runtime, k.key)
    if !has_area { ret ok }
    let dx = p.x - (area.x + area.width * 0.5)
    let dy = p.y - (area.y + area.height * 0.5)
    var angle = math.atan2[f32](dx, 0.0 - dy)
    if angle < 0.0 - 2.3561945 { angle = 0.0 - 2.3561945 }
    if angle > 2.3561945 { angle = 2.3561945 }
    let share = (angle + 2.3561945) / 4.712389
    ret widget.fire_change[f32](k.change, k.low + share * (k.high - k.low))
}

fn knob_gesture(ctx: *void, g: widget.Gesture) -> err {
    let k = mem.cast[*Knob](ctx)
    switch g {
    case .Tap as p:
        ret knob_at(k, p)
    case .DragMove as d:
        ret knob_at(k, d.position)
    default:
        ret ok
    }
}

// A dial's keyboard: a hundredth of the range either way.
type Turn = struct { knob: *Knob, up: bool }

fn turn_fire(ctx: *void) -> err {
    let turn = mem.cast[*Turn](ctx)
    let k = turn.knob
    var share = k.share
    if turn.up {
        share += 0.01
    } else {
        share = share - 0.01
    }
    if share > 1.0 { share = 1.0 }
    if share < 0.0 { share = 0.0 }
    ret widget.fire_change[f32](k.change, k.low + share * (k.high - k.low))
}

// A dial: a knob of `size` whose pointer stands at `value` within `low..high`;
// a press or a drag turns it to where the pointer points, the arrow keys turn it
// a hundredth of the range. A slider in the tree named `label` with the value as
// digits (rounded).
fn dial(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, change: widget.Change[f32], size: f32) -> (widget.Node, err) {
    if high <= low { ret (zero, TooLarge) }
    var share = (value - low) / (high - low)
    if share < 0.0 { share = 0.0 }
    if share > 1.0 { share = 1.0 }
    let (knobs, knobs_error) = mem.alloc[Knob](a, 1usize)
    if knobs_error != ok { ret (zero, TooLarge) }
    knobs[0usize] = Knob { runtime: t.runtime, key: key, track: style.color(t.tokens, .Border), fill: style.color(t.tokens, .Primary), share: share, low: low, high: high, change: change, arena: a }
    let (turns, turns_error) = mem.alloc[Turn](a, 2usize)
    if turns_error != ok { ret (zero, TooLarge) }
    turns[0usize] = Turn { knob: &knobs[0usize], up: false }
    turns[1usize] = Turn { knob: &knobs[0usize], up: true }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 4usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    let less = widget.Submit { ctx: mem.cast[*void](&turns[0usize]), invoke: turn_fire }
    let more = widget.Submit { ctx: mem.cast[*void](&turns[1usize]), invoke: turn_fire }
    shortcuts[0usize] = widget.Shortcut { key: 37u32, modifiers: zero, action: less }
    shortcuts[1usize] = widget.Shortcut { key: 40u32, modifiers: zero, action: less }
    shortcuts[2usize] = widget.Shortcut { key: 39u32, modifiers: zero, action: more }
    shortcuts[3usize] = widget.Shortcut { key: 38u32, modifiers: zero, action: more }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    var none: []const widget.Node = zero
    body[0usize] = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&knobs[0usize]), measure: mark_measure, paint: knob_paint, state: zero } }, style: sized_style(size, size), children: none }
    let (hit, hit_error) = mem.alloc[widget.Node](a, 1usize)
    if hit_error != ok { ret (zero, TooLarge) }
    hit[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&knobs[0usize]), invoke: knob_gesture }, gestures: 1u8 | 2u8 | 4u8, enabled: true, focusable: true }, sized_style(size, size), body[0usize..1usize])
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..4usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), hit[0usize..1usize])
    let (digits, digits_error) = mem.alloc[u8](a, 21usize)
    if digits_error != ok { ret (zero, TooLarge) }
    var rounded = value + 0.5
    if value < 0.0 { rounded = value - 0.5 }
    let digit_count = write_i64(digits, i64(rounded))
    var sem: widget.Semantics = zero
    sem.role = 15u8
    sem.label = label
    sem.value = digits[0usize..digit_count]
    sem.actions = accessibility.ACTION_INCREMENT | accessibility.ACTION_DECREMENT | accessibility.ACTION_SET_VALUE
    ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// A keyboard chord: a key code as `widget.key_code` normalises it (0 for none)
// and its modifiers.
type Chord = struct { key: u32, modifiers: input.Modifiers }

// The chord as text into `out`: the modifiers first, then the key by name.
fn write_chord(out: []u8, chord: Chord) -> usize {
    var at = 0usize
    if chord.key == 0u32 { ret write_word(out, at, "None") }
    if chord.modifiers.control { at = write_word(out, at, "Ctrl+") }
    if chord.modifiers.shift { at = write_word(out, at, "Shift+") }
    if chord.modifiers.alt { at = write_word(out, at, "Alt+") }
    if chord.modifiers.meta { at = write_word(out, at, "Meta+") }
    let code = chord.key
    if (code >= 65u32 && code <= 90u32) || (code >= 48u32 && code <= 57u32) {
        if at < out.len {
            out[at] = u8(code)
            at += 1usize
        }
        ret at
    }
    if code == 13u32 { ret write_word(out, at, "Enter") }
    if code == 27u32 { ret write_word(out, at, "Escape") }
    if code == 32u32 { ret write_word(out, at, "Space") }
    if code == 9u32 { ret write_word(out, at, "Tab") }
    if code == 8u32 { ret write_word(out, at, "Backspace") }
    if code == 46u32 { ret write_word(out, at, "Delete") }
    if code == 37u32 { ret write_word(out, at, "Left") }
    if code == 38u32 { ret write_word(out, at, "Up") }
    if code == 39u32 { ret write_word(out, at, "Right") }
    if code == 40u32 { ret write_word(out, at, "Down") }
    if code == 36u32 { ret write_word(out, at, "Home") }
    if code == 35u32 { ret write_word(out, at, "End") }
    at = write_word(out, at, "Key")
    let wrote = write_i64(out[at..out.len], i64(code))
    ret at + wrote
}

fn write_word(out: []u8, at: usize, word: str) -> usize {
    var n = at
    var i = 0usize
    while i < word.len && n < out.len {
        out[n] = word[i]
        n += 1usize
        i += 1usize
    }
    ret n
}

// A recorder's capture: every key down while recording reaches it; a modifier on
// its own is waited through, Escape captures nothing (a chord with no key), any
// other key captures itself with the modifiers held.
type Recorder = struct { capture: widget.Change[Chord] }

fn record_key(ctx: *void, k: input.KeyEvent) -> err {
    let r = mem.cast[*Recorder](ctx)
    let physical = k.key.physical
    if physical >= 65505u32 && physical <= 65518u32 { ret ok }
    let code = widget.key_code(physical)
    if code == 27u32 { ret widget.fire_change[Chord](r.capture, Chord { key: 0u32, modifiers: zero }) }
    ret widget.fire_change[Chord](r.capture, Chord { key: code, modifiers: k.modifiers })
}

// A shortcut recorder: an outlined field (keyed `key`) showing `chord` by name,
// or "Press keys" while `recording`; a press fires `start` (the caller then
// records, and the focus is on the field), and while recording every key down
// reaches `capture` as a chord -- Escape as none -- for the caller to keep and
// stop on. A button in the tree named `label` with the chord as its value.
fn shortcut_recorder(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, chord: Chord, recording: bool, start: *const widget.Submit, capture: widget.Change[Chord]) -> (widget.Node, err) {
    let (text_bytes, text_error) = mem.alloc[u8](a, 48usize)
    if text_error != ok { ret (zero, TooLarge) }
    var shown_len = write_chord(text_bytes, chord)
    if recording { shown_len = write_word(text_bytes, 0usize, "Press keys") }
    let shown: str = text_bytes[0usize..shown_len]
    var state = control_state(t, key, true, recording)
    let look = style.resolve(t.tokens, .Outlined, state)
    var caption = text_options()
    caption.role = .Body
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, shown, t, caption, look.foreground)
    if label_error != ok { ret (zero, label_error) }
    let (field_node, field_error) = pressable_states(a, key, t, 3u8, label, look, true, recording, 0u32, 0u32, 0u64, start, label_node)
    if field_error != ok { ret (zero, field_error) }
    var keys: widget.Change[input.KeyEvent] = zero
    if recording {
        let (recorders, recorders_error) = mem.alloc[Recorder](a, 1usize)
        if recorders_error != ok { ret (zero, TooLarge) }
        recorders[0usize] = Recorder { capture: capture }
        keys = widget.Change[input.KeyEvent] { ctx: mem.cast[*void](&recorders[0usize]), invoke: record_key }
    }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = field_node
    var none: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: none, default_action: zero, cancel_action: zero, keys: keys }, style.defaults(), body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    sem.value = shown
    ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// ------------------------------------- advanced text and choice input (D831, P2-03)

// A formatted field's adapter: whether a text is acceptable, and how to write it
// back formatted (into `out`, the length written). Both are the caller's.
type Format = struct { ctx: *void, accept: fn(*void, str) -> bool, format: fn(*void, []u8, str) -> usize }

// What a formatted field's submit needs: where the text is, the adapter, whom to
// tell once formatted.
type Formatting = struct { runtime: *widget.Runtime, key: widget.Key, buffer: []u8, adapter: Format, change: widget.Change[str], arena: *mem.Arena }

fn format_submit(ctx: *void) -> err {
    let f = mem.cast[*Formatting](ctx)
    let (s, state_error) = widget.state_of(f.runtime)
    if state_error != ok { ret ok }
    let (id, count) = widget.find_by_key(s, f.key)
    if count == 0usize { ret ok }
    let (current, has_current) = widget.edit_value(f.runtime, id)
    if !has_current { ret ok }
    if !f.adapter.accept(f.adapter.ctx, current) { ret ok }
    let (scratch, scratch_error) = mem.alloc[u8](f.arena, f.buffer.len)
    if scratch_error != ok { ret TooLarge }
    let n = f.adapter.format(f.adapter.ctx, scratch, current)
    if n > f.buffer.len { ret TooLarge }
    var i = 0usize
    while i < n {
        f.buffer[i] = scratch[i]
        i += 1usize
    }
    ret widget.fire_change[str](f.change, f.buffer[0usize..n])
}

// A formatted field: D823's text field whose text is invalid while the adapter
// does not accept it, and whose Enter, when it does, writes the formatted text
// into the caller's buffer and reports it through `change` (the caller takes the
// new length from there). A mask edit is this with an adapter that formats.
fn formatted_field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, adapter: Format, typed: widget.Change[str], change: widget.Change[str], options: FieldOptions) -> (widget.Node, err) {
    let (formats, formats_error) = mem.alloc[Formatting](a, 1usize)
    if formats_error != ok { ret (zero, TooLarge) }
    formats[0usize] = Formatting { runtime: t.runtime, key: key, buffer: buffer, adapter: adapter, change: change, arena: a }
    var shown = options
    shown.invalid = options.invalid || !adapter.accept(adapter.ctx, buffer[0usize..len])
    let (made, made_error) = text_field(a, key, t, label, buffer, len, typed, widget.Submit { ctx: mem.cast[*void](&formats[0usize]), invoke: format_submit }, shown)
    ret (made, made_error)
}

// A move of the active suggestion, for Up and Down.
type Move = struct { index: usize, activate: widget.Change[usize] }

fn move_fire(ctx: *void) -> err {
    let m = mem.cast[*Move](ctx)
    ret widget.fire_change[usize](m.activate, m.index)
}

// A field with suggestions: the field (keyed `key`) and, while `open`, a
// non-modal overlay (keyed `list_key`) below it of the suggestions as plain
// buttons keyed `first + index`, the active one filled; under a scope whose Up
// and Down move the active one through `activate`, whose Enter is the active
// pick and whose Escape is `dismiss`. A group in the tree named `label`, expanded
// while open, its active descendant the active suggestion.
fn suggesting(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, field_node: widget.Node, extra: []const widget.Node, list_key: widget.Key, first: widget.Key, suggestions: []const str, active: usize, open: bool, picks: []const widget.Submit, activate: widget.Change[usize], dismiss: *const widget.Submit) -> (widget.Node, err) {
    if picks.len != suggestions.len { ret (zero, TooLarge) }
    let listing = open && suggestions.len > 0usize
    var count = 1usize + extra.len
    if listing { count += 1usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = field_node
    var i = 0usize
    while i < extra.len {
        parts[1usize + i] = extra[i]
        i += 1usize
    }
    var default_action: widget.Submit = zero
    if listing {
        let (items, items_error) = mem.alloc[widget.Node](a, suggestions.len)
        if items_error != ok { ret (zero, TooLarge) }
        i = 0usize
        while i < suggestions.len {
            var plain = button_options()
            plain.variant = .Plain
            if i == active { plain.variant = .Filled }
            let (item, item_error) = button(a, first + u64(i), t, suggestions[i], &picks[i], plain)
            if item_error != ok { ret (zero, item_error) }
            var entry: widget.Semantics = zero
            entry.role = 11u8
            entry.label = suggestions[i]
            if i == active { entry.states = accessibility.STATE_SELECTED }
            let (wrapped, wrapped_error) = mem.alloc[widget.Node](a, 1usize)
            if wrapped_error != ok { ret (zero, TooLarge) }
            wrapped[0usize] = item
            var stretched = style.defaults()
            stretched.width = style.Length { Percent: 100.0 }
            items[i] = widget.semantics(0u64, entry, stretched, wrapped[0usize..1usize])
            i += 1usize
        }
        var sheet = surface_options(t)
        sheet.bordered = true
        sheet.elevation = 2u8
        sheet.radius = t.tokens.radii.xs
        sheet.padding = t.tokens.spacing.xs
        let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
        if column_error != ok { ret (zero, TooLarge) }
        column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, surface_style(t, sheet), items[0usize..suggestions.len])
        var list_sem: widget.Semantics = zero
        list_sem.role = 10u8
        list_sem.label = label
        list_sem.row_count = u32(suggestions.len)
        let (popup, popup_error) = mem.alloc[widget.Node](a, 1usize)
        if popup_error != ok { ret (zero, TooLarge) }
        popup[0usize] = widget.semantics(0u64, list_sem, style.defaults(), column[0usize..1usize])
        parts[count - 1usize] = widget.overlay(list_key, widget.Overlay { anchor: key, placement: .Below, offset: geometry.Point { x: 0.0, y: t.tokens.spacing.xs }, modal: false, dismiss: zero }, style.defaults(), popup[0usize..1usize])
        if active < picks.len { default_action = picks[active] }
    }
    let (moves, moves_error) = mem.alloc[Move](a, 2usize)
    if moves_error != ok { ret (zero, TooLarge) }
    var previous = active
    if active > 0usize { previous = active - 1usize }
    var next = active
    if active + 1usize < suggestions.len { next = active + 1usize }
    moves[0usize] = Move { index: previous, activate: activate }
    moves[1usize] = Move { index: next, activate: activate }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 38u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[0usize]), invoke: move_fire } }
    shortcuts[1usize] = widget.Shortcut { key: 40u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[1usize]), invoke: move_fire } }
    var bound = 0usize
    if listing { bound = 2usize }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..count])
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..bound], default_action: default_action, cancel_action: *dismiss, keys: zero }, style.defaults(), row[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    if listing {
        sem.states = accessibility.STATE_EXPANDED
        sem.active = first + u64(active)
    }
    ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// An autocomplete: a text field (keyed `key`) with the caller's filtered
// suggestions below it (list `key + 1`, items `key + 2 + index`) while `open`.
fn autocomplete(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], suggestions: []const str, active: usize, open: bool, picks: []const widget.Submit, activate: widget.Change[usize], dismiss: *const widget.Submit, options: FieldOptions) -> (widget.Node, err) {
    let (field_node, field_error) = text_field(a, key, t, label, buffer, len, typed, zero, options)
    if field_error != ok { ret (zero, field_error) }
    var none: []const widget.Node = zero
    let (made, made_error) = suggesting(a, key, t, label, field_node, none, key + 1u64, key + 2u64, suggestions, active, open, picks, activate, dismiss)
    ret (made, made_error)
}

// A combo box: an autocomplete with a chevron button (keyed `key + 1`) firing
// `toggle` beside the field; the list is `key + 2`, its items `key + 3 + index`.
fn combo_box(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], choices: []const str, active: usize, open: bool, picks: []const widget.Submit, activate: widget.Change[usize], toggle: *const widget.Submit, options: FieldOptions) -> (widget.Node, err) {
    let (field_node, field_error) = text_field(a, key, t, label, buffer, len, typed, zero, options)
    if field_error != ok { ret (zero, field_error) }
    let look = style.resolve(t.tokens, .Outlined, control_state(t, key + 1u64, true, false))
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, TooLarge) }
    marks[0usize] = Mark { color: look.foreground, expanded: true, arena: a }
    let size = t.tokens.spacing.md
    var none: []const widget.Node = zero
    let chevron = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: sized_style(size, size), children: none }
    var states = 0u32
    if open { states = accessibility.STATE_EXPANDED }
    let (opener, opener_error) = pressable_states(a, key + 1u64, t, 3u8, "Choices", look, true, false, states, accessibility.ACTION_SHOW_MENU, key + 2u64, toggle, chevron)
    if opener_error != ok { ret (zero, opener_error) }
    let (extra, extra_error) = mem.alloc[widget.Node](a, 1usize)
    if extra_error != ok { ret (zero, TooLarge) }
    extra[0usize] = opener
    let (made, made_error) = suggesting(a, key, t, label, field_node, extra[0usize..1usize], key + 2u64, key + 3u64, choices, active, open, picks, activate, toggle)
    ret (made, made_error)
}

// A token field: the tokens as input chips (keyed `key + 1 + 2 * index`, their
// remove buttons `key + 2 + 2 * index`, at most 30) before a text field (keyed
// `key`) whose Enter is `add` (the caller pushes the typed text and clears it),
// wrapped to `width`; suggestions as an autocomplete's (list `key + 62`, items
// `key + 63 + index`).
fn token_field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, tokens: []const str, removes: []const widget.Submit, buffer: []u8, len: usize, typed: widget.Change[str], add: widget.Submit, suggestions: []const str, active: usize, open: bool, picks: []const widget.Submit, activate: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if removes.len != tokens.len || tokens.len > 30usize { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[widget.Node](a, tokens.len + 1usize)
    if items_error != ok { ret (zero, TooLarge) }
    var none_action: widget.Submit = zero
    let (still, still_error) = mem.alloc[widget.Submit](a, 1usize)
    if still_error != ok { ret (zero, TooLarge) }
    still[0usize] = none_action
    var i = 0usize
    while i < tokens.len {
        let (token, token_error) = chip(a, key + 1u64 + 2u64 * u64(i), t, tokens[i], .Input, false, &still[0usize], &removes[i])
        if token_error != ok { ret (zero, token_error) }
        items[i] = token
        i += 1usize
    }
    var options = field_options()
    options.width = 4.0 * t.tokens.spacing.lg
    let (field_node, field_error) = text_field(a, key, t, label, buffer, len, typed, add, options)
    if field_error != ok { ret (zero, field_error) }
    items[tokens.len] = field_node
    var wrapped = style.defaults()
    wrapped.width = style.Length { Px: width }
    let flow = widget.wrap(0u64, ui_layout.Wrap { axis: .Horizontal, main_gap: t.tokens.spacing.xs, cross_gap: t.tokens.spacing.xs }, wrapped, items[0usize..tokens.len + 1usize])
    var none: []const widget.Node = zero
    let (made, made_error) = suggesting(a, key, t, label, flow, none, key + 62u64, key + 63u64, suggestions, active, open, picks, activate, dismiss)
    ret (made, made_error)
}

// How a picker presents its choice: D824's popup select, or a sheet -- a modal
// overlay in the middle of the window listing the options as full-width rows
// under a title, for a touch host.
type PickerForm = enum u8 { Popup, Sheet }

fn picker(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, selected: usize, open: bool, toggle: *const widget.Submit, picks: []const widget.Submit, presentation: PickerForm) -> (widget.Node, err) {
    if presentation == .Popup {
        let (popup, popup_error) = select(a, key, t, label, options, selected, open, toggle, picks)
        ret (popup, popup_error)
    }
    if picks.len != options.len { ret (zero, TooLarge) }
    var shown = label
    if selected < options.len { shown = options[selected] }
    var outlined = button_options()
    outlined.variant = .Outlined
    let (head, head_error) = button(a, key, t, shown, toggle, outlined)
    if head_error != ok { ret (zero, head_error) }
    var count = 1usize
    if open { count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    if open {
        let (rows, rows_error) = mem.alloc[widget.Node](a, options.len + 1usize)
        if rows_error != ok { ret (zero, TooLarge) }
        var heading = text_options()
        heading.role = .Title
        let (title_node, title_error) = text_node(a, 0u64, label, t, heading)
        if title_error != ok { ret (zero, title_error) }
        rows[0usize] = title_node
        var i = 0usize
        while i < options.len {
            var plain = button_options()
            plain.variant = .Plain
            if i == selected { plain.variant = .Filled }
            let (item, item_error) = button(a, key + 2u64 + u64(i), t, options[i], &picks[i], plain)
            if item_error != ok { ret (zero, item_error) }
            var entry: widget.Semantics = zero
            entry.role = 11u8
            entry.label = options[i]
            if i == selected { entry.states = accessibility.STATE_SELECTED }
            let (wrapped, wrapped_error) = mem.alloc[widget.Node](a, 1usize)
            if wrapped_error != ok { ret (zero, TooLarge) }
            wrapped[0usize] = item
            var stretched = style.defaults()
            stretched.width = style.Length { Percent: 100.0 }
            rows[1usize + i] = widget.semantics(0u64, entry, stretched, wrapped[0usize..1usize])
            i += 1usize
        }
        var sheet = surface_options(t)
        sheet.bordered = true
        sheet.elevation = 3u8
        sheet.radius = t.tokens.radii.sm
        sheet.padding = t.tokens.spacing.md
        var sheet_style = surface_style(t, sheet)
        sheet_style.min_width = style.Length { Px: 8.0 * t.tokens.spacing.lg }
        let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
        if column_error != ok { ret (zero, TooLarge) }
        column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: t.tokens.spacing.xs }, sheet_style, rows[0usize..options.len + 1usize])
        var none: []const widget.Shortcut = zero
        let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
        if scoped_error != ok { ret (zero, TooLarge) }
        scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: zero, cancel_action: *toggle, keys: zero }, style.defaults(), column[0usize..1usize])
        var list_sem: widget.Semantics = zero
        list_sem.role = 23u8
        list_sem.label = label
        list_sem.states = accessibility.STATE_MODAL
        let (dialog, dialog_error) = mem.alloc[widget.Node](a, 1usize)
        if dialog_error != ok { ret (zero, TooLarge) }
        dialog[0usize] = widget.semantics(0u64, list_sem, style.defaults(), scoped[0usize..1usize])
        parts[1usize] = widget.overlay(key + 1u64, widget.Overlay { anchor: 0u64, placement: .Center, offset: zero, modal: true, dismiss: *toggle }, style.defaults(), dialog[0usize..1usize])
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    if open { sem.states = accessibility.STATE_EXPANDED }
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A multi-select list: D824's list box with any number of rows selected, each
// row's tap firing its own toggle; the caller keeps `selected`, one flag a row.
fn multi_select_list(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, selected: []const bool, toggles: []const widget.Submit, rows: u32, width: f32) -> (widget.Node, err) {
    let (made, made_error) = listed(a, key, t, label, options, selected, toggles, rows, width)
    ret (made, made_error)
}

// ------------------------------------------ feedback and disclosure (D832, P2-04)

// A gauge: a read-only ring through `value`'s share of `low..high` with the value
// written under it as digits (rounded); a progress in the tree named `label`
// with those digits as its value.
fn gauge(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, size: f32) -> (widget.Node, err) {
    if high <= low { ret (zero, TooLarge) }
    let share = (value - low) / (high - low)
    let (ring, ring_error) = progress_ring(a, key + 1u64, t, label, share, false, size)
    if ring_error != ok { ret (zero, ring_error) }
    let (digits, digits_error) = mem.alloc[u8](a, 21usize)
    if digits_error != ok { ret (zero, TooLarge) }
    var rounded = value + 0.5
    if value < 0.0 { rounded = value - 0.5 }
    let digit_count = write_i64(digits, i64(rounded))
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    let (reading, reading_error) = text_node(a, 0u64, digits[0usize..digit_count], t, caption)
    if reading_error != ok { ret (zero, reading_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = ring
    parts[1usize] = reading
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 16u8
    sem.label = label
    sem.value = digits[0usize..digit_count]
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A level: a read-only bar filled through `value`'s share of `low..high`, in the
// primary colour, the secondary from `warn` and the error colour from `danger`
// (shares of the range; 1 or more for never); a progress in the tree named
// `label` with the value as digits.
fn level(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, warn: f32, danger: f32, width: f32) -> (widget.Node, err) {
    if high <= low { ret (zero, TooLarge) }
    var share = (value - low) / (high - low)
    if share < 0.0 { share = 0.0 }
    if share > 1.0 { share = 1.0 }
    var tone: style.ColorRole = .Primary
    if share >= warn { tone = .Secondary }
    if share >= danger { tone = .Error }
    let height = t.tokens.spacing.sm
    var track = sized_style(width, height)
    track.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceVariant) }
    track.radius = height * 0.5
    var filled = style.defaults()
    filled.height = style.Length { Px: height }
    filled.width = style.Length { Percent: share * 100.0 }
    filled.background = paint.Brush { Solid: style.color(t.tokens, tone) }
    filled.radius = height * 0.5
    let (fill, fill_error) = mem.alloc[widget.Node](a, 1usize)
    if fill_error != ok { ret (zero, TooLarge) }
    fill[0usize] = widget.box(key + 1u64, filled, zero)
    let (bar, bar_error) = mem.alloc[widget.Node](a, 1usize)
    if bar_error != ok { ret (zero, TooLarge) }
    bar[0usize] = widget.box(0u64, track, fill[0usize..1usize])
    let (digits, digits_error) = mem.alloc[u8](a, 21usize)
    if digits_error != ok { ret (zero, TooLarge) }
    var rounded = value + 0.5
    if value < 0.0 { rounded = value - 0.5 }
    let digit_count = write_i64(digits, i64(rounded))
    var sem: widget.Semantics = zero
    sem.role = 16u8
    sem.label = label
    sem.value = digits[0usize..digit_count]
    if share >= danger { sem.states = accessibility.STATE_INVALID }
    ret (widget.semantics(key, sem, style.defaults(), bar[0usize..1usize]), ok)
}

// A transient notice: its text, an optional action (an empty label for none) and
// what dismisses it. The caller keeps the queue; a snackbar or a toast shows its
// head.
type Notice = struct { text: str, action_label: str, action: widget.Submit, dismiss: widget.Submit }

// The head of a queue of notices on a raised surface `width` wide as a non-modal
// overlay against the window: at the bottom (`bottom`) or the top right; the
// text, the action as a plain button (keyed `key + 1`) when there is one, and a
// close button (`key + 2`) firing the notice's dismiss; a polite status in the
// tree named by the text. Nothing while the queue is empty.
fn noticed(a: *mem.Arena, key: widget.Key, t: *const Theme, notices: []const Notice, width: f32, bottom: bool) -> (widget.Node, err) {
    if notices.len == 0usize { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let head = &notices[0usize]
    var count = 2usize
    if head.action_label.len != 0usize { count = 3usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    var caption = text_options()
    caption.role = .Body
    caption.color = .OnPrimary
    let (text_item, text_error) = text_node(a, 0u64, head.text, t, caption)
    if text_error != ok { ret (zero, text_error) }
    var grown = text_item
    grown.style.width = style.Length { Flex: 1.0 }
    parts[0usize] = grown
    var at = 1usize
    if head.action_label.len != 0usize {
        var plain = button_options()
        plain.variant = .Plain
        let (act, act_error) = button(a, key + 1u64, t, head.action_label, &head.action, plain)
        if act_error != ok { ret (zero, act_error) }
        parts[at] = act
        at += 1usize
    }
    var plain_close = button_options()
    plain_close.variant = .Plain
    let (close, close_error) = button(a, key + 2u64, t, "x", &head.dismiss, plain_close)
    if close_error != ok { ret (zero, close_error) }
    parts[at] = close
    var sheet = style.defaults()
    sheet.background = paint.Brush { Solid: style.color(t.tokens, .Text) }
    sheet.radius = t.tokens.radii.xs
    sheet.width = style.Length { Px: width }
    let pad = style.Length { Px: t.tokens.spacing.sm }
    sheet.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.sm }, sheet, parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 26u8
    sem.label = head.text
    sem.live = 1u8
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.semantics(0u64, sem, style.defaults(), row[0usize..1usize])
    var placement: widget.Placement = .Right
    if bottom { placement = .Below }
    let margin = t.tokens.spacing.md
    var offset = geometry.Point { x: 0.0 - margin, y: margin }
    if bottom { offset = geometry.Point { x: margin, y: 0.0 - margin } }
    ret (widget.overlay(key, widget.Overlay { anchor: 0u64, placement: placement, offset: offset, modal: false, dismiss: zero }, style.defaults(), body[0usize..1usize]), ok)
}

// A snackbar: the queue's head along the bottom of the window.
fn snackbar(a: *mem.Arena, key: widget.Key, t: *const Theme, notices: []const Notice, width: f32) -> (widget.Node, err) {
    let (made, made_error) = noticed(a, key, t, notices, width, true)
    ret (made, made_error)
}

// A toast: the queue's head at the top right of the window.
fn toast(a: *mem.Arena, key: widget.Key, t: *const Theme, notices: []const Notice, width: f32) -> (widget.Node, err) {
    let (made, made_error) = noticed(a, key, t, notices, width, false)
    ret (made, made_error)
}

// How serious a banner is: the colour it takes and how the tree announces it.
type Severity = enum u8 { Info, Success, Warning, Error }

// A banner: a persistent inline notice `width` wide in the severity's colour,
// its text and its actions as plain buttons keyed `key + 2 + index`; a status in
// the tree for information and success, an alert for a warning or an error.
fn banner(a: *mem.Arena, key: widget.Key, t: *const Theme, severity: Severity, message: str, labels: []const str, actions: []const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = noted(a, key, t, severity, message, labels, actions, width, zero)
    ret (made, made_error)
}

// An info bar: a banner with a close button (keyed `key + 1`) firing `dismiss`.
fn info_bar(a: *mem.Arena, key: widget.Key, t: *const Theme, severity: Severity, message: str, labels: []const str, actions: []const widget.Submit, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = noted(a, key, t, severity, message, labels, actions, width, *dismiss)
    ret (made, made_error)
}

fn noted(a: *mem.Arena, key: widget.Key, t: *const Theme, severity: Severity, message: str, labels: []const str, actions: []const widget.Submit, width: f32, dismiss: widget.Submit) -> (widget.Node, err) {
    if labels.len != actions.len { ret (zero, TooLarge) }
    let closable = widget.submit_set(dismiss.invoke)
    var count = 1usize + labels.len
    if closable { count += 1usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    var background: style.ColorRole = .SurfaceVariant
    var foreground: style.ColorRole = .Text
    if severity == .Success { background = .Primary }
    if severity == .Success { foreground = .OnPrimary }
    if severity == .Warning { background = .Secondary }
    if severity == .Warning { foreground = .OnSecondary }
    if severity == .Error { background = .Error }
    if severity == .Error { foreground = .OnError }
    var caption = text_options()
    caption.role = .Body
    caption.color = foreground
    let (text_item, text_error) = text_node(a, 0u64, message, t, caption)
    if text_error != ok { ret (zero, text_error) }
    var grown = text_item
    grown.style.width = style.Length { Flex: 1.0 }
    parts[0usize] = grown
    var i = 0usize
    while i < labels.len {
        var plain = button_options()
        plain.variant = .Plain
        let (act, act_error) = button(a, key + 2u64 + u64(i), t, labels[i], &actions[i], plain)
        if act_error != ok { ret (zero, act_error) }
        parts[1usize + i] = act
        i += 1usize
    }
    if closable {
        let (closes, closes_error) = mem.alloc[widget.Submit](a, 1usize)
        if closes_error != ok { ret (zero, TooLarge) }
        closes[0usize] = dismiss
        var plain = button_options()
        plain.variant = .Plain
        let (close, close_error) = button(a, key + 1u64, t, "x", &closes[0usize], plain)
        if close_error != ok { ret (zero, close_error) }
        parts[count - 1usize] = close
    }
    var sheet = style.defaults()
    sheet.background = paint.Brush { Solid: style.color(t.tokens, background) }
    sheet.width = style.Length { Px: width }
    let pad = style.Length { Px: t.tokens.spacing.sm }
    sheet.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.sm }, sheet, parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 26u8
    sem.live = 1u8
    if severity == .Warning || severity == .Error {
        sem.role = 24u8
        sem.live = 2u8
    }
    sem.label = message
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// A skeleton: a rounded placeholder of `width` by `height` in the surface variant
// whose opacity breathes with `phase` (the caller's clock, in radians) unless the
// theme's motion is reduced; busy and unnamed in the tree.
fn skeleton(a: *mem.Arena, key: widget.Key, t: *const Theme, width: f32, height: f32, phase: f32) -> (widget.Node, err) {
    var block = sized_style(width, height)
    block.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceVariant) }
    block.radius = t.tokens.radii.xs
    block.opacity = 1.0
    if !t.tokens.motion.reduced { block.opacity = 0.7 + 0.3 * math.sin[f32](phase) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.box(0u64, block, zero)
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.states = accessibility.STATE_BUSY
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// An empty state: an icon (a zero texture for none), a title, a muted message
// and a filled button (keyed `key + 1`, none for an empty label) in a centred
// column `width` wide; a group in the tree named by the title.
fn empty_state(a: *mem.Arena, key: widget.Key, t: *const Theme, icon_texture: scene.TextureId, title: str, message: str, action_label: str, action: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let pictured = icon_texture.slot != 0u32 || icon_texture.generation != 0u32
    var count = 2usize
    if pictured { count += 1usize }
    if action_label.len != 0usize { count += 1usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    var at = 0usize
    if pictured {
        let (picture, picture_error) = icon(a, 0u64, icon_texture, 2.0 * t.tokens.metrics.hit_target, title)
        if picture_error != ok { ret (zero, picture_error) }
        parts[at] = picture
        at += 1usize
    }
    var heading = text_options()
    heading.role = .Title
    heading.align = .Center
    let (title_node, title_error) = text_node(a, 0u64, title, t, heading)
    if title_error != ok { ret (zero, title_error) }
    parts[at] = title_node
    at += 1usize
    var body_text = text_options()
    body_text.color = .TextMuted
    body_text.align = .Center
    let (message_node, message_error) = text_node(a, 0u64, message, t, body_text)
    if message_error != ok { ret (zero, message_error) }
    parts[at] = message_node
    at += 1usize
    if action_label.len != 0usize {
        let (act, act_error) = button(a, key + 1u64, t, action_label, action, button_options())
        if act_error != ok { ret (zero, act_error) }
        parts[at] = act
        at += 1usize
    }
    var column_style = style.defaults()
    column_style.width = style.Length { Px: width }
    let pad = style.Length { Px: t.tokens.spacing.lg }
    column_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Center, gap: t.tokens.spacing.sm }, column_style, parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = title
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// An accordion: D826's disclosures in a column, keyed `key + 1 + 2 * index` (their
// content groups `key + 2 + 2 * index`), the one at `expanded` open and the others
// shut (an index past the end for none), each header firing its own toggle; a
// group in the tree named `label`.
fn accordion(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, labels: []const str, contents: []const widget.Node, expanded: usize, toggles: []const widget.Submit) -> (widget.Node, err) {
    if contents.len != labels.len || toggles.len != labels.len { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[widget.Node](a, labels.len)
    if items_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < labels.len {
        let (opened, opened_error) = disclosure(a, key + 1u64 + 2u64 * u64(i), t, labels[i], i == expanded, &toggles[i], contents[i])
        if opened_error != ok { ret (zero, opened_error) }
        items[i] = opened
        i += 1usize
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, style.defaults(), items[0usize..labels.len])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// ------------------------------------- desktop selection and history (D854, P3-05)

// An index reported through a change, for a row or a segment.
type Chosen = struct { index: usize, change: widget.Change[usize] }

fn chosen_fire(ctx: *void) -> err {
    let c = mem.cast[*Chosen](ctx)
    ret widget.fire_change[usize](c.change, c.index)
}

// One submit an index, over `change`, for controls that take a submit a choice.
fn chosen_actions(a: *mem.Arena, count: usize, change: widget.Change[usize]) -> ([]widget.Submit, err) {
    var none: []widget.Submit = zero
    let (picks, picks_error) = mem.alloc[Chosen](a, count)
    if picks_error != ok { ret (none, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, count)
    if actions_error != ok { ret (none, TooLarge) }
    var i = 0usize
    while i < count {
        picks[i] = Chosen { index: i, change: change }
        actions[i] = widget.Submit { ctx: mem.cast[*void](&picks[i]), invoke: chosen_fire }
        i += 1usize
    }
    ret (actions[0usize..count], ok)
}

// A font picker over the caller's catalogue: the families in D824's list box
// (keyed `key + 1`, its rows `key + 2 + index`, `rows` tall), the styles as a
// segmented control (`key + 64`, its segments after), the size as D830's stepper
// (`key + 80`) and a preview of `sample` (keyed `key + 81`) in the theme's face --
// the picked family's face is the caller's to supply through the theme's fonts;
// each choice reaches its change with the index or the size. A group in the tree
// named `label` whose value is the picked family.
fn font_picker(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, families: []const str, family: usize, styles: []const str, style_index: usize, size: i64, sample: str, pick_family: widget.Change[usize], pick_style: widget.Change[usize], change_size: widget.Change[i64], rows: u32, width: f32) -> (widget.Node, err) {
    if families.len == 0usize || styles.len == 0usize { ret (zero, TooLarge) }
    let (family_actions, family_error) = chosen_actions(a, families.len, pick_family)
    if family_error != ok { ret (zero, family_error) }
    let (style_actions, style_error) = chosen_actions(a, styles.len, pick_style)
    if style_error != ok { ret (zero, style_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (listed_families, listed_error) = list_box(a, key + 1u64, t, "Family", families, family, family_actions, rows, width)
    if listed_error != ok { ret (zero, listed_error) }
    parts[0usize] = listed_families
    let (segments, segments_error) = segmented_control(a, key + 64u64, t, "Style", styles, style_index, style_actions, true)
    if segments_error != ok { ret (zero, segments_error) }
    parts[1usize] = segments
    let (sized, sized_error) = stepper(a, key + 80u64, t, "Size", size, 4i64, 288i64, 1i64, change_size)
    if sized_error != ok { ret (zero, sized_error) }
    parts[2usize] = sized
    var caption = text_options()
    caption.role = .Body
    caption.wrap = .None
    caption.ellipsis = "..."
    caption.max_lines = 1u32
    let (preview, preview_error) = text_node(a, key + 81u64, sample, t, caption)
    if preview_error != ok { ret (zero, preview_error) }
    let (previewed, previewed_error) = mem.alloc[widget.Node](a, 1usize)
    if previewed_error != ok { ret (zero, TooLarge) }
    previewed[0usize] = preview
    var frame_options = surface_options(t)
    frame_options.bordered = true
    frame_options.padding = t.tokens.spacing.sm
    var frame_style = surface_style(t, frame_options)
    frame_style.width = style.Length { Px: width }
    frame_style.min_height = style.Length { Px: 2.0 * t.tokens.text[0usize].line_height }
    parts[3usize] = widget.box(0u64, frame_style, previewed[0usize..1usize])
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.sm }, style.defaults(), parts[0usize..4usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    sem.value = families[family]
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A notification list: D832's notices, newest first as the caller orders them,
// each a row (keyed `key + 2 + 3 * index`) of its text, its action as a plain
// button (`key + 3 + 3 * index`) when it has one and a close (`key + 4 + 3 * index`)
// firing its dismiss, in a
// viewport (keyed `key`) `height` tall with a Clear all button (`key + 1`) firing
// `clear` above; a list of list items in the tree named `label`, polite.
fn notification_list(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, notices: []const Notice, clear: *const widget.Submit, width: f32, height: f32) -> (widget.Node, err) {
    if notices.len > 64usize { ret (zero, TooLarge) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, notices.len)
    if rows_error != ok { ret (zero, TooLarge) }
    let row_height = t.tokens.metrics.control_height + t.tokens.spacing.sm
    var i = 0usize
    while i < notices.len {
        let n = &notices[i]
        var count = 2usize
        if n.action_label.len != 0usize { count = 3usize }
        let (cells, cells_error) = mem.alloc[widget.Node](a, count)
        if cells_error != ok { ret (zero, TooLarge) }
        var caption = text_options()
        caption.wrap = .None
        caption.ellipsis = "..."
        caption.max_lines = 1u32
        let (text_item, text_error) = text_node(a, 0u64, n.text, t, caption)
        if text_error != ok { ret (zero, text_error) }
        var grown = text_item
        grown.style.width = style.Length { Flex: 1.0 }
        cells[0usize] = grown
        var at = 1usize
        if n.action_label.len != 0usize {
            var plain = button_options()
            plain.variant = .Plain
            let (act, act_error) = button(a, key + 3u64 + 3u64 * u64(i), t, n.action_label, &n.action, plain)
            if act_error != ok { ret (zero, act_error) }
            cells[at] = act
            at += 1usize
        }
        var plain_close = button_options()
        plain_close.variant = .Plain
        let (close, close_error) = button(a, key + 4u64 + 3u64 * u64(i), t, "x", &n.dismiss, plain_close)
        if close_error != ok { ret (zero, close_error) }
        cells[at] = close
        var row_style = style.defaults()
        row_style.width = style.Length { Px: width }
        row_style.height = style.Length { Px: row_height }
        let pad = style.Length { Px: t.tokens.spacing.xs }
        row_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
        let (lined, lined_error) = mem.alloc[widget.Node](a, 1usize)
        if lined_error != ok { ret (zero, TooLarge) }
        lined[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, row_style, cells[0usize..count])
        var entry: widget.Semantics = zero
        entry.role = 11u8
        entry.label = n.text
        entry.row = u32(i + 1usize)
        entry.row_count = u32(notices.len)
        rows[i] = widget.semantics(key + 2u64 + 3u64 * u64(i), entry, style.defaults(), lined[0usize..1usize])
        i += 1usize
    }
    var view_style = style.defaults()
    view_style.width = style.Length { Px: width }
    view_style.height = style.Length { Px: height }
    view_style.border = style.Border { width: t.tokens.borders.regular, color: style.color(t.tokens, .Border) }
    view_style.radius = t.tokens.radii.xs
    view_style.overflow = .Clip
    let (view, view_error) = widget.scroll_view(a, key, .Vertical, view_style, rows[0usize..notices.len])
    if view_error != ok { ret (zero, TooLarge) }
    var outlined = button_options()
    outlined.variant = .Outlined
    outlined.enabled = notices.len > 0usize
    let (cleared, cleared_error) = button(a, key + 1u64, t, "Clear all", clear, outlined)
    if cleared_error != ok { ret (zero, cleared_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = cleared
    parts[1usize] = view
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .End, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    sem.live = 1u8
    sem.row_count = u32(notices.len)
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}
