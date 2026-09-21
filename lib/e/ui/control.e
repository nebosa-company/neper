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
// language for shaping. The fonts and the tokens outlive every frame.
type Theme = struct { tokens: *const style.ThemeTokens, fonts: []const shape.Font, language: str }
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
    let (text_look, style_error) = text_style(a, t, options.role)
    if style_error != ok { ret (zero, style_error) }
    ret (widget.text(key, widget.Text { value: value, style: text_look, color: style.color(t.tokens, options.color), wrap: options.wrap, align: options.align, max_lines: options.max_lines, ellipsis: options.ellipsis }, style.defaults()), ok)
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
    ret (widget.edit(key, widget.Edit { buffer: buffer, len: len, style: text_look, color: style.color(t.tokens, options.color), selection: style.color(t.tokens, .Selection), change: zero, submit: zero, enabled: true, read_only: true, multiline: options.wrap != .None }, style.defaults()), ok)
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
            var link: widget.Semantics = zero
            link.role = ROLE_LINK
            link.label = span.value
            let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
            if region_error != ok { ret (zero, TooLarge) }
            region[0usize] = widget.region(0u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&span.link), invoke: link_tap }, gestures: 1u8, enabled: true, focusable: true }, style.defaults(), body[0usize..1usize])
            children[i] = widget.semantics(0u64, link, style.defaults(), region[0usize..1usize])
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
