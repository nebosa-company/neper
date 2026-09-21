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
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

// What a page is set in: the theme's tokens, the fonts in preference order, the
// language for shaping, and the page's runtime, from which a control reads what the
// pointer and the focus are doing to it (none: every control is at rest). The fonts
// and the tokens outlive every frame.
type Theme = struct { tokens: *const style.ThemeTokens, fonts: []const shape.Font, language: str, runtime: *widget.Runtime }
// A button's look: its fill, and whether it takes presses.
type ButtonOptions = struct { variant: style.ControlVariant, enabled: bool }
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
// its elevation level (0 for none, up to 3, the theme's shadow strengths), padding.
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
        var level = usize(options.elevation)
        if level > 3usize { level = 3usize }
        // The elevation level is the shadow's strength; it falls two pixels a level.
        s.shadow = style.Shadow { offset: geometry.Point { x: 0.0, y: f32(level) * 2.0 }, color: paint.rgba(0.0, 0.0, 0.0, t.tokens.elevation[level]) }
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
    options.radius = t.tokens.radii.md
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
    options.radius = t.tokens.radii.sm
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
    block.radius = t.tokens.radii.sm
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.box(0u64, block, zero)
    var sem: widget.Semantics = zero
    sem.states = accessibility.STATE_BUSY
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// ------------------------------------------------------- the button family (D818, P1-06)

fn button_options() -> ButtonOptions {
    ret ButtonOptions { variant: .Filled, enabled: true }
}

// The control state of a keyed element under the page's runtime, with what the
// caller says of it.
fn control_state(t: *const Theme, key: widget.Key, enabled: bool, selected: bool) -> style.ControlState {
    var state: style.ControlState = zero
    state.disabled = !enabled
    state.selected = selected
    if mem.address_of(t.runtime) != 0usize {
        let now = widget.interaction(t.runtime, key)
        state.hovered = now.hovered
        state.pressed = now.pressed
        state.focused = now.focused
    }
    ret state
}

fn press_tap(ctx: *void, g: widget.Gesture) -> err {
    if g.tag != .Tap { ret ok }
    let action = mem.cast[*const widget.Submit](ctx)
    ret widget.fire_submit(*action)
}

// The pressable surface every button is: a tap-and-hover region in the resolved
// look, its content centred, the semantics on top. `action` outlives the element.
fn pressable(a: *mem.Arena, key: widget.Key, t: *const Theme, role: u8, label: str, look: style.ResolvedControl, enabled: bool, selected: bool, action: *const widget.Submit, content: widget.Node) -> (widget.Node, err) {
    var s = style.defaults()
    s.background = paint.Brush { Solid: look.background }
    s.border = style.Border { width: look.border_width, color: look.border }
    s.radius = look.radius
    s.opacity = look.opacity
    s.min_height = style.Length { Px: t.tokens.metrics.control_height }
    s.min_width = style.Length { Px: t.tokens.metrics.hit_target }
    let pad_x = style.Length { Px: t.tokens.spacing.md }
    let pad_y = style.Length { Px: t.tokens.spacing.xs }
    s.padding = style.EdgeLengths { left: pad_x, top: pad_y, right: pad_x, bottom: pad_y }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    inner[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](action), invoke: press_tap }, gestures: 1u8 | 4u8, enabled: enabled, focusable: enabled }, s, body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = role
    sem.label = label
    sem.actions = accessibility.ACTION_PRESS
    if !enabled { sem.states = accessibility.STATE_DISABLED }
    if selected { sem.states = sem.states | accessibility.STATE_SELECTED }
    ret (widget.semantics(0u64, sem, style.defaults(), inner[0usize..1usize]), ok)
}

// A button: its label in the resolved foreground; Enter and Space press it too.
fn button(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, action: *const widget.Submit, options: ButtonOptions) -> (widget.Node, err) {
    let look = style.resolve(t.tokens, options.variant, control_state(t, key, options.enabled, false))
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, look.foreground)
    if label_error != ok { ret (zero, label_error) }
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, options.enabled, false, action, label_node)
    ret (node, node_error)
}

// An icon button: the icon in place of the label, the label for the tree alone.
fn icon_button(a: *mem.Arena, key: widget.Key, t: *const Theme, texture: scene.TextureId, label: str, action: *const widget.Submit, options: ButtonOptions) -> (widget.Node, err) {
    let look = style.resolve(t.tokens, options.variant, control_state(t, key, options.enabled, false))
    let size = t.tokens.metrics.control_height - 2.0 * t.tokens.spacing.xs
    let picture = widget.image(0u64, widget.Image { texture: texture, fit: .Contain }, sized_style(size, size))
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, options.enabled, false, action, picture)
    ret (node, node_error)
}

// A toggle button: pressed to switch `selected`, which the caller keeps and the look
// and the tree show.
fn toggle_button(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, selected: bool, action: *const widget.Submit, options: ButtonOptions) -> (widget.Node, err) {
    let look = style.resolve(t.tokens, options.variant, control_state(t, key, options.enabled, selected))
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, look.foreground)
    if label_error != ok { ret (zero, label_error) }
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, options.enabled, selected, action, label_node)
    ret (node, node_error)
}

// A link: its text in the primary colour, a tap region with the link role.
fn link(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, action: *const widget.Submit) -> (widget.Node, err) {
    var caption = text_options()
    caption.role = .Body
    caption.color = .Primary
    caption.wrap = .None
    let (label_node, label_error) = text_node(a, 0u64, label, t, caption)
    if label_error != ok { ret (zero, label_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = label_node
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    // A link is at least the hit target, so a short one is still reachable.
    var target_style = style.defaults()
    target_style.min_width = style.Length { Px: t.tokens.metrics.hit_target }
    target_style.min_height = style.Length { Px: t.tokens.metrics.hit_target }
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
    mark_style.radius = t.tokens.radii.sm
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
    let (pb, pb_error) = geometry.path_builder(a, 12usize, 40usize)
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
    body[0usize] = widget.Node { key: key + 1u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&rings[0usize]), measure: ring_measure, paint: ring_paint } }, style: sized_style(size, size), children: none }
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
    frame_style.radius = t.tokens.radii.sm
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
