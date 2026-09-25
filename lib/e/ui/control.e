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
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.text.shape
use e.ui.accessibility
use e.ui.animation
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
// v2 (D962, docs/ux/components/Text): a headline or title role also reports a
// Heading with its level (headline-large 1, headline-medium and -small 2,
// title-large 3, title-medium 4, title-small 5), named by the full value.
fn text(a: *mem.Arena, key: widget.Key, value: str, t: *const Theme, options: TextOptions) -> (widget.Node, err) {
    var depth = 0u8
    if options.role == .HeadlineLarge { depth = 1u8 }
    if options.role == .HeadlineMedium || options.role == .HeadlineSmall { depth = 2u8 }
    if options.role == .TitleLarge { depth = 3u8 }
    if options.role == .TitleMedium { depth = 4u8 }
    if options.role == .TitleSmall { depth = 5u8 }
    if depth == 0u8 {
        let (node, node_error) = text_node(a, key, value, t, options)
        ret (node, node_error)
    }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    let (words, words_error) = text_node(a, 0u64, value, t, options)
    if words_error != ok { ret (zero, words_error) }
    body[0usize] = words
    var sem: widget.Semantics = zero
    sem.role = 25u8
    sem.label = value
    sem.level = depth
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// A selectable text: a read-only editor over the caller's buffer, so the caret,
// the selection, Shift+arrows and copy are the editor's (D807).
// v2 (D963, docs/ux/components/SelectableText): the inline value or message --
// the selection filled `primary-container` with the selected glyphs repainted
// `on-primary-container`, a 2px `primary` caret, and no Tab stop (a press still
// focuses it); `selectable_block` is the block form.
fn selectable_text(a: *mem.Arena, key: widget.Key, buffer: []u8, len: usize, t: *const Theme, options: TextOptions) -> (widget.Node, err) {
    let (node, node_error) = selectable(a, key, buffer, len, t, options, false)
    ret (node, node_error)
}

// v2 (D963): the block form for logs and output -- `surface-container-high`,
// `radius-sm` 8, padding 12 by 16, in the `code` role, a Tab stop with the focus
// ring round the block.
fn selectable_block(a: *mem.Arena, key: widget.Key, buffer: []u8, len: usize, t: *const Theme, options: TextOptions) -> (widget.Node, err) {
    var coded = options
    coded.role = .Code
    let (node, node_error) = selectable(a, key, buffer, len, t, coded, true)
    ret (node, node_error)
}

// ponytail: the unfocused-window colour, the context menu, touch handles and
// toolbar, word selection, and `align`/`max_lines` are not yet the editor's.
fn selectable(a: *mem.Arena, key: widget.Key, buffer: []u8, len: usize, t: *const Theme, options: TextOptions, block: bool) -> (widget.Node, err) {
    let (text_look, style_error) = text_style(a, t, options.role)
    if style_error != ok { ret (zero, style_error) }
    var look = style.defaults()
    if block {
        focus_look(t)
        look.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) }
        look.radius = t.tokens.radii.sm
        let side = style.Length { Px: 16.0 }
        let top = style.Length { Px: 12.0 }
        look.padding = style.EdgeLengths { left: side, top: top, right: side, bottom: top }
    }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.edit(key, widget.Edit { buffer: buffer, len: len, style: text_look, color: style.color(t.tokens, options.color), selection: style.color(t.tokens, .PrimaryContainer), change: zero, submit: zero, enabled: true, read_only: true, multiline: options.wrap != .None || block, secret: false, marked: style.color(t.tokens, .OnPrimaryContainer), caret: style.color(t.tokens, .Primary), untabbed: !block, ringed: block }, look)
    var sem: widget.Semantics = zero
    sem.role = ROLE_TEXT
    sem.label = buffer[0usize..len]
    sem.actions = accessibility.ACTION_COPY
    ret (widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize]), ok)
}

fn link_tap(ctx: *void, g: widget.Gesture) -> err {
    if g.tag != .Tap { ret ok }
    let action = mem.cast[*widget.Submit](ctx)
    ret widget.fire_submit(*action)
}

// Rich text: the spans laid side by side, each in its own role and colour, a
// linked span a tap region with the link role. `paragraph` is the v2 rich text
// (D964).
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

// What a span of a v2 paragraph is (D964): plain, strong (weight 600), emphasis,
// inline code, a keyboard key, a mention, or a link.
type SpanKind = enum u8 { Plain, Strong, Emphasis, Code, Key, Mention, Link }
// A span of a paragraph: its words, its kind, its colour role (plain, strong,
// emphasis and code), the action a link or mention fires when pressed (unset: a
// mention is not pressable), and whether a link was visited. The spans outlive
// the element, as an action's context does.
type RichSpan = struct { value: str, kind: SpanKind, color: style.ColorRole, action: widget.Submit, visited: bool }
// A paragraph's base role (it sets every line's height), the width it wraps in
// (0: one line), the most lines it shows (0: all) and the mark a cut line ends in.
type RichOptions = struct { role: style.TextRole, width: f32, max_lines: u32, ellipsis: str }
// A laid piece: a word (with its trailing spaces) or a whole code, key, mention or
// link span; its width, the width that must fit (no trailing spaces), and the
// baseline of its text inside its box.
type Piece = struct { span: usize, start: usize, end: usize, width: f32, fit: f32, baseline: f32 }

fn rich_span(value: str, kind: SpanKind) -> RichSpan {
    ret RichSpan { value: value, kind: kind, color: .OnSurface, action: zero, visited: false }
}

// `body-medium` on pointer hosts, `body-large` on touch.
fn rich_options(t: *const Theme) -> RichOptions {
    var base: style.TextRole = .BodyMedium
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { base = .BodyLarge }
    ret RichOptions { role: base, width: 0.0, max_lines: 0u32, ellipsis: "…" }
}

// A span kind's text role under a base role.
fn span_role(kind: SpanKind, base: style.TextRole) -> style.TextRole {
    if kind == .Code || kind == .Key { ret .Code }
    if kind == .Strong || kind == .Mention {
        if base == .BodyLarge { ret .TitleMedium }
        ret .TitleSmall
    }
    ret base
}

// Whether a span is laid as one piece that never breaks inside.
fn span_whole(kind: SpanKind) -> bool {
    ret kind == .Code || kind == .Key || kind == .Mention || kind == .Link
}

// The advance of a run of text in a role (its trailing spaces included), the width
// that must fit (without them) and its first baseline; nothing without fonts.
fn run_metrics(a: *mem.Arena, t: *const Theme, role: style.TextRole, words: str) -> (f32, f32, f32, err) {
    if t.fonts.len == 0usize || words.len == 0usize { ret (0.0, 0.0, 0.0, ok) }
    let (look, look_error) = text_style(a, t, role)
    if look_error != ok { ret (0.0, 0.0, 0.0, look_error) }
    let (laid, laid_error) = layout.layout(a, words, look, layout.Options { width: 0.0, max_lines: 0u32, align: .Start, wrap: .None, ellipsis: "" })
    if laid_error != ok { ret (0.0, 0.0, 0.0, laid_error) }
    let (laids, laids_error) = mem.alloc[layout.Layout](a, 1usize)
    if laids_error != ok { ret (0.0, 0.0, 0.0, TooLarge) }
    laids[0usize] = laid
    var baseline: f32 = 0.0
    if laid.lines.len != 0usize { baseline = laid.lines[0usize].baseline - laid.bounds.y }
    let tail = layout.caret(&laids[0usize], words.len)
    ret (max_of(tail.x - laid.bounds.x, laid.bounds.width), laid.bounds.width, baseline, ok)
}

// v2 (D964, docs/ux/components/RichText): one paragraph of spans in a base role
// (`body-medium`, `body-large` on touch) whose line height every line keeps. Plain
// spans break at word boundaries across spans; code, key, mention and link spans
// never break inside. Every piece of a line sits on the line's baseline. Strong
// and mentions take the weight-600 title role of the base size, mentions in
// `primary`; code is the `code` role on `surface-container-high` with `radius-xs`
// and 4 sides; a key is the `code` role on `surface-container-lowest` in a 1px
// `outline-variant` edge. A link is `primary` (`link-visited` once visited) with a
// 1px underline 3 below the baseline; hovered, the underline is 2px over a
// `primary` 8% wash, pressed a 10% wash; its tall_target is `tall_target-pointer` 32 tall
// (48 on touch) without moving the text, so a paragraph with a pressable span
// reserves the overhang above and below. `max_lines` cuts the paragraph with the
// ellipsis after the last whole piece that fits, so a link is never cut. Links
// and mentions are Link nodes keyed `key + 1 + span index`; the paragraph is a
// Text named by all its words.
// ponytail: emphasis is upright (no italic face), a key is the code line's
// height with a 1px edge (not 24 with a 2px foot), and the word pieces are also
// Text nodes of their own; a Custom paragraph node would fold them into one.
fn paragraph(a: *mem.Arena, key: widget.Key, t: *const Theme, spans: []const RichSpan, options: RichOptions) -> (widget.Node, err) {
    focus_look(t)
    // The pieces: whole spans, or words with their trailing spaces.
    var count = 0usize
    var i = 0usize
    while i < spans.len {
        let v = spans[i].value
        if span_whole(spans[i].kind) {
            count += 1usize
        } else {
            var k = 0usize
            while k < v.len {
                if k == 0usize || (v[k] != 32u8 && v[k - 1usize] == 32u8) { count += 1usize }
                k += 1usize
            }
        }
        i += 1usize
    }
    let (pieces, pieces_error) = mem.alloc[Piece](a, count + 1usize)
    if pieces_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    var pressable_seen = false
    i = 0usize
    while i < spans.len {
        let span = &spans[i]
        let role = span_role(span.kind, options.role)
        if (span.kind == .Link || span.kind == .Mention) && widget.submit_set(span.action.invoke) { pressable_seen = true }
        var k = 0usize
        while k < span.value.len {
            var end = span.value.len
            if !span_whole(span.kind) {
                end = k
                while end < span.value.len && span.value[end] != 32u8 { end += 1usize }
                while end < span.value.len && span.value[end] == 32u8 { end += 1usize }
            }
            let (width, fit, baseline, width_error) = run_metrics(a, t, role, span.value[k..end])
            if width_error != ok { ret (zero, width_error) }
            var sides: f32 = 0.0
            if span.kind == .Code || span.kind == .Key { sides = 2.0 * t.tokens.spacing.xs }
            pieces[n] = Piece { span: i, start: k, end: end, width: width + sides, fit: fit + sides, baseline: baseline }
            n += 1usize
            k = end
        }
        i += 1usize
    }
    // The lines: a piece that would pass the width starts the next one.
    let (starts, starts_error) = mem.alloc[usize](a, n + 1usize)
    if starts_error != ok { ret (zero, TooLarge) }
    var line_count = 0usize
    var x: f32 = 0.0
    i = 0usize
    while i < n {
        if i == 0usize || (options.width > 0.0 && x > 0.0 && x + pieces[i].fit > options.width) {
            starts[line_count] = i
            line_count += 1usize
            x = 0.0
        }
        x += pieces[i].width
        i += 1usize
    }
    starts[line_count] = n
    // The cut: the last kept line ends with the ellipsis after the last whole
    // piece before which it fits.
    var shown = n
    var cut = false
    var dots: f32 = 0.0
    if options.max_lines != 0u32 && line_count > usize(options.max_lines) {
        line_count = usize(options.max_lines)
        cut = true
        let (dots_width, dots_fit, dots_baseline, dots_error) = run_metrics(a, t, options.role, options.ellipsis)
        if dots_error != ok { ret (zero, dots_error) }
        dots = dots_width
        shown = starts[line_count]
        let first = starts[line_count - 1usize]
        while shown > first + 1usize {
            var end_x: f32 = 0.0
            var p = first
            while p + 1usize < shown {
                end_x += pieces[p].width
                p += 1usize
            }
            end_x += pieces[shown - 1usize].fit
            if !(options.width > 0.0) || end_x + dots <= options.width { break }
            shown -= 1usize
        }
        starts[line_count] = shown
    }
    let line_h = style.text_style(t.tokens, options.role).line_height
    var tall_target = t.tokens.sizes.target_pointer
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { tall_target = t.tokens.sizes.target_touch }
    var overhang: f32 = 0.0
    if pressable_seen && tall_target > line_h { overhang = (tall_target - line_h) * 0.5 }
    // The pieces placed on their lines' baselines.
    let (placed, placed_error) = mem.alloc[widget.Node](a, shown + 2usize)
    if placed_error != ok { ret (zero, TooLarge) }
    var widest: f32 = 0.0
    var line = 0usize
    var p_at = 0usize
    while line < line_count {
        var lb: f32 = 0.0
        var p = starts[line]
        while p < starts[line + 1usize] {
            if pieces[p].baseline > lb { lb = pieces[p].baseline }
            p += 1usize
        }
        let top = overhang + f32(line) * line_h
        x = 0.0
        p = starts[line]
        while p < starts[line + 1usize] {
            let (made, made_error) = rich_piece(a, key, t, spans, &pieces[p], options, line_h, lb, tall_target, overhang, x, top)
            if made_error != ok { ret (zero, made_error) }
            placed[p_at] = made
            p_at += 1usize
            x += pieces[p].width
            p += 1usize
        }
        if cut && line + 1usize == line_count {
            var marked = text_options()
            marked.role = options.role
            marked.wrap = .None
            let (mark, mark_error) = colored_text(a, 0u64, options.ellipsis, t, marked, style.color(t.tokens, .OnSurface))
            if mark_error != ok { ret (zero, mark_error) }
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (zero, TooLarge) }
            held[0usize] = mark
            placed[p_at] = widget.positioned(0u64, x, top, style.defaults(), held[0usize..1usize])
            p_at += 1usize
            x += dots
        }
        if x > widest { widest = x }
        line += 1usize
    }
    var box_width = widest
    if options.width > 0.0 { box_width = options.width }
    placed[p_at] = widget.stack(0u64, sized_style(box_width, f32(line_count) * line_h + 2.0 * overhang), placed[0usize..p_at])
    // The paragraph's name: every word of every span.
    var total = 0usize
    i = 0usize
    while i < spans.len {
        total += spans[i].value.len
        i += 1usize
    }
    let (named, named_error) = mem.alloc[u8](a, total)
    if named_error != ok { ret (zero, TooLarge) }
    var at = 0usize
    i = 0usize
    while i < spans.len {
        at += copy_text(named[at..total], spans[i].value)
        i += 1usize
    }
    var sem: widget.Semantics = zero
    sem.role = ROLE_TEXT
    sem.label = named[0usize..at]
    ret (widget.semantics(key, sem, style.defaults(), placed[p_at..p_at + 1usize]), ok)
}

// One piece at `x` on the line whose top is `top` and baseline `lb` below it.
fn rich_piece(a: *mem.Arena, key: widget.Key, t: *const Theme, spans: []const RichSpan, piece: *const Piece, options: RichOptions, line_h: f32, lb: f32, tall_target: f32, overhang: f32, x: f32, top: f32) -> (widget.Node, err) {
    let span = &spans[piece.span]
    let role = span_role(span.kind, options.role)
    var ink = style.color(t.tokens, span.color)
    if span.kind == .Mention || span.kind == .Link { ink = style.color(t.tokens, .Primary) }
    if span.kind == .Link && span.visited { ink = style.color(t.tokens, .LinkVisited) }
    var said = text_options()
    said.role = role
    said.wrap = .None
    let (words, words_error) = colored_text(a, 0u64, span.value[piece.start..piece.end], t, said, ink)
    if words_error != ok { ret (zero, words_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 6usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = words
    let drop = lb - piece.baseline
    var look = style.defaults()
    if span.kind == .Code || span.kind == .Key {
        let side = style.Length { Px: t.tokens.spacing.xs }
        let none = style.Length { Px: 0.0 }
        look.padding = style.EdgeLengths { left: side, top: none, right: side, bottom: none }
        look.radius = t.tokens.radii.xs
        look.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) }
        if span.kind == .Key {
            look.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLowest) }
            look.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .OutlineVariant) }
        }
    }
    let live_link = (span.kind == .Link || span.kind == .Mention) && widget.submit_set(span.action.invoke)
    if !live_link && span.kind != .Link {
        ret (widget.positioned(0u64, x, top + drop, look, parts[0usize..1usize]), ok)
    }
    // A link: the words over the wash with the underline 3 below the baseline,
    // on a whole pixel.
    let link_key = key + 1u64 + u64(piece.span)
    var state: style.ControlState = zero
    if live_link { state = control_state(t, link_key, true, false) }
    var body = sized_style(piece.width, line_h)
    if state.pressed { body.background = paint.Brush { Solid: with_alpha(style.color(t.tokens, .Primary), t.tokens.states.pressed) } }
    if state.hovered && !state.pressed { body.background = paint.Brush { Solid: with_alpha(style.color(t.tokens, .Primary), t.tokens.states.hover) } }
    parts[1usize] = widget.positioned(0u64, 0.0, drop, style.defaults(), parts[0usize..1usize])
    var count = 1usize
    if span.kind == .Link {
        var thick = t.tokens.sizes.divider
        if state.hovered { thick = 2.0 }
        var rule = sized_style(piece.fit, thick)
        rule.background = paint.Brush { Solid: ink }
        parts[2usize] = widget.positioned(0u64, 0.0, math.round[f32](lb + 3.0), rule, zero)
        count = 2usize
    }
    parts[3usize] = widget.stack(0u64, body, parts[1usize..1usize + count])
    if !live_link {
        ret (widget.positioned(0u64, x, top, style.defaults(), parts[3usize..4usize]), ok)
    }
    let lift = (tall_target - line_h) * 0.5
    let reach = max_of(tall_target, line_h)
    var reach_style = sized_style(piece.width, reach)
    reach_style.padding = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: max_zero(lift) }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    parts[4usize] = widget.region(link_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&span.action), invoke: link_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, reach_style, parts[3usize..4usize])
    var linked: widget.Semantics = zero
    linked.role = ROLE_LINK
    linked.label = span.value
    linked.actions = accessibility.ACTION_PRESS
    let (outer, outer_error) = mem.alloc[widget.Node](a, 1usize)
    if outer_error != ok { ret (zero, TooLarge) }
    outer[0usize] = widget.semantics(0u64, linked, style.defaults(), parts[4usize..5usize])
    ret (widget.positioned(0u64, x, top - max_zero(lift), style.defaults(), outer[0usize..1usize]), ok)
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

// An icon: a square image of `size`, contained, with a semantic label; an empty
// label leaves it out of the tree as a decoration (D962). `icon_of` draws the
// v2 icon, tinted, from the shared set.
// ponytail: an icon is not tinted; a tint waits on the renderer's image brush.
fn icon(a: *mem.Arena, key: widget.Key, texture: scene.TextureId, size: f32, label: str) -> (widget.Node, err) {
    let (node, node_error) = image(a, key, texture, size, size, .Contain, label)
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

// ------------------------------------------------ content, v2 (D962, P5-07)

// An icon's look: its size (snapped to `icon-sm` 18, `icon-md` 24 or `icon-lg`
// 36), its colour role, whether it is enabled, and its name (empty: decorative).
type IconOptions = struct { size: f32, color: style.ColorRole, enabled: bool, label: str }

fn icon_options() -> IconOptions {
    ret IconOptions { size: 24.0, color: .OnSurfaceVariant, enabled: true, label: "" }
}

// The token size nearest a requested icon size.
fn icon_token_size(t: *const Theme, size: f32) -> f32 {
    if size < 21.0 { ret t.tokens.sizes.icon_sm }
    if size < 30.0 { ret t.tokens.sizes.icon_md }
    ret t.tokens.sizes.icon_lg
}

// A drawn glyph in its square: the live area 2/24 in on every side, stroked 1.75
// at 24 and in proportion at other sizes, round caps and joins.
fn icon_square(a: *mem.Arena, color: paint.Color, kind: GlyphKind, size: f32) -> (widget.Node, err) {
    let inset = size * 2.0 / 24.0
    let (marks, marks_error) = mem.alloc[widget.Node](a, 1usize)
    if marks_error != ok { ret (zero, TooLarge) }
    let (mark, mark_error) = stroked_glyph(a, color, kind, size - 2.0 * inset, size * 1.75 / 24.0)
    if mark_error != ok { ret (zero, mark_error) }
    marks[0usize] = mark
    ret (widget.padded(0u64, inset, inset, inset, inset, sized_style(size, size), marks[0usize..1usize]), ok)
}

// v2 (D962, docs/ux/components/Icon): a glyph of the shared set as vector strokes
// tinted by a colour role (`on-surface-variant` by default), at a token size;
// disabled it is `on-surface` at 38%. Named, it is an Image; unnamed, it is left
// out of the tree as a decoration.
// ponytail: outline forms only; filled "on" forms wait on the full 49-icon set.
fn icon_of(a: *mem.Arena, key: widget.Key, t: *const Theme, kind: GlyphKind, options: IconOptions) -> (widget.Node, err) {
    var tint = style.color(t.tokens, options.color)
    if !options.enabled { tint = with_alpha(style.color(t.tokens, .OnSurface), t.tokens.states.disabled_content) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    var shown = kind
    if t.tokens.direction == .RightToLeft {
        if kind == .ChevronLeft { shown = .ChevronRight }
        if kind == .ChevronRight { shown = .ChevronLeft }
        if kind == .ArrowBack { shown = .ArrowForward }
        if kind == .ArrowForward { shown = .ArrowBack }
    }
    let (square, square_error) = icon_square(a, tint, shown, icon_token_size(t, options.size))
    if square_error != ok { ret (zero, square_error) }
    body[0usize] = square
    var sem: widget.Semantics = zero
    sem.role = ROLE_IMAGE
    sem.label = options.label
    sem.hidden = options.label.len == 0usize
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// What an image frame shows: the picture, its loading ground, or the error or
// empty message.
type ImageStatus = enum u8 { Loaded, Loading, Failed, Empty }
// An image's frame: its width and aspect ratio (width over height), the fit of
// the picture, whether it meets its container's edge square, its status, its alt
// text (empty: decorative), a caption, and the Retry action an error offers (none
// when unset).
type ImageOptions = struct { width: f32, aspect: f32, fit: widget.Fit, full_bleed: bool, status: ImageStatus, label: str, caption: str, retry: *const widget.Submit }

fn image_options() -> ImageOptions {
    var out: ImageOptions = zero
    out.width = 160.0
    out.aspect = 16.0 / 9.0
    out.fit = .Cover
    out.status = .Loaded
    ret out
}

// v2 (D962, docs/ux/components/Image): a frame `width` wide and `width / aspect`
// tall, `radius-md` 12 (`radius-sm` 8 under 48 wide, none full-bleed), clipping
// the picture over the `surface-container-highest` ground, so the space is held
// before the texture exists. Loading shows the ground; an error shows the `alert`
// mark, "Couldn't load" in `body-small` and a small Retry text button; empty
// shows the `picture` mark and "No preview" -- the mark `icon-md` 24 (`icon-lg` 36
// from 120 wide) in `on-surface-variant`, the message 4 below it. A caption in
// `body-small` `on-surface-variant` stands 8 below the frame.
// ponytail: no pressable form (state layers, focus ring, Button role) and no fade.
fn framed_image(a: *mem.Arena, key: widget.Key, t: *const Theme, texture: scene.TextureId, options: ImageOptions) -> (widget.Node, err) {
    var ratio = options.aspect
    if !(ratio > 0.0) { ratio = 1.0 }
    let width = options.width
    let height = width / ratio
    var frame = sized_style(width, height)
    frame.radius = t.tokens.radii.md
    if width < 48.0 { frame.radius = t.tokens.radii.sm }
    if options.full_bleed { frame.radius = 0.0 }
    frame.overflow = .Clip
    frame.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
    let (inside, inside_error) = mem.alloc[widget.Node](a, 3usize)
    if inside_error != ok { ret (zero, TooLarge) }
    var inside_count = 0usize
    var message: str = ""
    if options.status == .Loaded {
        inside[0usize] = widget.image(0u64, widget.Image { texture: texture, fit: options.fit }, sized_style(width, height))
        inside_count = 1usize
    }
    if options.status == .Failed || options.status == .Empty {
        var kind: GlyphKind = .Picture
        message = "No preview"
        if options.status == .Failed {
            kind = .Alert
            message = "Couldn't load"
        }
        var mark: f32 = t.tokens.sizes.icon_md
        if width >= 120.0 { mark = t.tokens.sizes.icon_lg }
        let muted = style.color(t.tokens, .OnSurfaceVariant)
        let (square, square_error) = icon_square(a, muted, kind, mark)
        if square_error != ok { ret (zero, square_error) }
        inside[0usize] = square
        var said = text_options()
        said.role = .BodySmall
        said.align = .Center
        said.max_lines = 2u32
        let (words, words_error) = colored_text(a, 0u64, message, t, said, muted)
        if words_error != ok { ret (zero, words_error) }
        inside[1usize] = words
        inside_count = 2usize
        if options.status == .Failed && mem.address_of(options.retry) != 0usize {
            var plain = button_options()
            plain.variant = .Plain
            let (again, again_error) = button(a, 0u64, t, "Retry", options.retry, plain)
            if again_error != ok { ret (zero, again_error) }
            inside[2usize] = again
            inside_count = 3usize
        }
    }
    let (framed, framed_error) = mem.alloc[widget.Node](a, 3usize)
    if framed_error != ok { ret (zero, TooLarge) }
    if options.status == .Loaded {
        framed[1usize] = widget.box(0u64, frame, inside[0usize..inside_count])
    } else {
        framed[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Center, gap: t.tokens.spacing.xs }, frame, inside[0usize..inside_count])
    }
    framed[0usize] = framed[1usize]
    if options.caption.len != 0usize {
        var caption_look = text_options()
        caption_look.role = .BodySmall
        let (under, under_error) = colored_text(a, 0u64, options.caption, t, caption_look, style.color(t.tokens, .OnSurfaceVariant))
        if under_error != ok { ret (zero, under_error) }
        framed[2usize] = under
        framed[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.sm }, style.defaults(), framed[1usize..3usize])
    }
    var sem: widget.Semantics = zero
    sem.role = ROLE_IMAGE
    sem.label = options.label
    sem.value = message
    sem.hidden = options.label.len == 0usize && message.len == 0usize
    if options.status == .Loading { sem.states = accessibility.STATE_BUSY }
    ret (widget.semantics(key, sem, style.defaults(), framed[0usize..1usize]), ok)
}

// A canvas's frame: its size (at least 48 each way), whether it is bare (no frame,
// no radius: a card's media), the padding the paint is inset by, whether it is
// enabled, and the takeaway it is named by.
type CanvasOptions = struct { width: f32, height: f32, bare: bool, padding: f32, enabled: bool, label: str }

fn canvas_options() -> CanvasOptions {
    ret CanvasOptions { width: 240.0, height: 120.0, bare: false, padding: 0.0, enabled: true, label: "" }
}

// v2 (D962, docs/ux/components/Canvas): the caller's paint in a frame of
// `surface-container-lowest` with a 1px `outline-variant` edge and `radius-md` 12,
// clipping the paint, sized by the options (48 x 48 at least) and inset by their
// padding (`space-4` 16 for a chart); bare, the paint alone. Disabled, the paint
// is at 38% opacity. It is an Image named by its takeaway.
// ponytail: static only; the interactive form (focus, keyboard, point children),
// the loading, empty and error content and the chart overlays and series tokens
// are not drawn.
fn framed_canvas(a: *mem.Arena, key: widget.Key, t: *const Theme, custom: widget.Custom, options: CanvasOptions) -> (widget.Node, err) {
    var frame = sized_style(max_of(options.width, 48.0), max_of(options.height, 48.0))
    if !options.bare {
        frame.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLowest) }
        frame.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .OutlineVariant) }
        frame.radius = t.tokens.radii.md
    }
    frame.overflow = .Clip
    let pad = style.Length { Px: options.padding }
    frame.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    var paint_style = style.defaults()
    paint_style.width = style.Length { Percent: 100.0 }
    paint_style.height = style.Length { Percent: 100.0 }
    if !options.enabled { paint_style.opacity = t.tokens.states.disabled_content }
    var none: []const widget.Node = zero
    let (inside, inside_error) = mem.alloc[widget.Node](a, 2usize)
    if inside_error != ok { ret (zero, TooLarge) }
    inside[0usize] = widget.Node { key: 0u64, kind: widget.Kind { Custom: custom }, style: paint_style, children: none }
    inside[1usize] = widget.box(0u64, frame, inside[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = ROLE_IMAGE
    sem.label = options.label
    if !options.enabled { sem.states = accessibility.STATE_DISABLED }
    ret (widget.semantics(key, sem, style.defaults(), inside[1usize..2usize]), ok)
}

// An avatar's presence mark.
type Presence = enum u8 { None, Online, Away, Busy, Offline }
// An avatar: its picture (a zero texture for none), the initials shown without
// one, the account id whose stable hash picks the initials' container, its size
// (snapped to 24, 32, 40, 56 or 72), whether it is the square team form, its
// presence, the colour it sits on (for the presence ring), and the person's name
// (empty: decorative, beside the name).
type AvatarOptions = struct { initials: str, account: str, size: f32, square: bool, presence: Presence, ground: style.ColorRole, label: str }

fn avatar_options() -> AvatarOptions {
    ret AvatarOptions { initials: "", account: "", size: 40.0, square: false, presence: .None, ground: .Background, label: "" }
}

// The avatar size nearest a requested one.
fn avatar_size(size: f32) -> f32 {
    if size < 28.0 { ret 24.0 }
    if size < 36.0 { ret 32.0 }
    if size < 48.0 { ret 40.0 }
    if size < 64.0 { ret 56.0 }
    ret 72.0
}

// A stable hash of an account id (FNV-1a), so its colour never changes per render.
fn account_hash(id: str) -> u32 {
    var h = 2166136261u32
    var i = 0usize
    while i < id.len {
        h = (h ^ u32(id[i])) *% 16777619u32
        i += 1usize
    }
    ret h
}

// v2 (D962, docs/ux/components/Avatar): a disc (`radius-full`, or `radius-sm` 8
// square for a team) of 24, 32, 40, 56 or 72. With a picture it is cover-fitted
// over `surface-container-highest`; without one the initials stand centred on
// `primary-`, `secondary-` or `tertiary-container` by the account's stable hash in
// the matching `on-*-container`, in `label-small` at 24, `label-large` at 32,
// `title-medium` at 40, `title-large` at 56 and `headline-medium` at 72; with
// neither, the `person` mark (16, 18, 24, 36, 36) in `on-surface-variant` on
// `surface-container-highest`. Presence is a 8, 10, 12, 14 or 16 mark at the
// bottom end, ringed 2 in the ground: online a `success` disc, away a hollow
// `warning` ring 2.5 wide, busy an `error` disc with an `on-error` bar, offline a
// hollow `outline` ring 2 wide. The name carries the presence ("Ada, online").
// (D1227) `avatar_group` overlaps several.
// ponytail: 32's initials are label-large 14 (the ramp has no 13); no pressable
// form of a single avatar, no cross-fade from initials to the photo.
// (D1227, docs/ux/components/Avatar, group) Up to three of `faces` (pictured
// by `textures` where given) overlapped by a quarter of their size, each ringed 2
// in the first face's ground, then, when `total` counts more, a neutral "+n" disc
// of the same size (`surface-container-highest`, `on-surface-variant`). One node
// in the tree named for the people -- "Ada, Mina and Jon", "Ada, Mina, Jon and 4
// others" -- a Button opening the full list when `open` is set, else a Group.
fn avatar_group(a: *mem.Arena, key: widget.Key, t: *const Theme, faces: []const AvatarOptions, textures: []const scene.TextureId, total: usize, size: f32, open: *const widget.Submit) -> (widget.Node, err) {
    let side = avatar_size(size)
    var shown = faces.len
    if shown > 3usize { shown = 3usize }
    var everyone = total
    if everyone < faces.len { everyone = faces.len }
    let more = everyone - shown
    var discs = shown
    if more > 0usize { discs += 1usize }
    if discs == 0usize { ret (zero, TooLarge) }
    let ringed = side + 4.0
    let step = ringed - side * 0.25
    var ground = style.color(t.tokens, .Background)
    if shown > 0usize { ground = style.color(t.tokens, faces[0usize].ground) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, discs)
    if layers_error != ok { ret (zero, TooLarge) }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 2usize * discs)
    if inner_error != ok { ret (zero, TooLarge) }
    var none: scene.TextureId = zero
    var i = 0usize
    while i < discs {
        if i < shown {
            var face = faces[i]
            face.label = ""
            face.presence = .None
            face.size = side
            var texture = none
            if i < textures.len { texture = textures[i] }
            let (made, made_error) = avatar_of(a, 0u64, t, texture, face)
            if made_error != ok { ret (zero, made_error) }
            inner[2usize * i] = made
        } else {
            var caption = text_options()
            caption.role = .LabelLarge
            if side < 28.0 { caption.role = .LabelSmall }
            caption.wrap = .None
            let (digits, digits_error) = mem.alloc[u8](a, 24usize)
            if digits_error != ok { ret (zero, TooLarge) }
            digits[0usize] = 43u8
            let n = 1usize + write_i64(digits[1usize..24usize], i64(more))
            let (said, said_error) = colored_text(a, 0u64, digits[0usize..n], t, caption, style.color(t.tokens, .OnSurfaceVariant))
            if said_error != ok { ret (zero, said_error) }
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (zero, TooLarge) }
            held[0usize] = said
            var neutral = sized_style(side, side)
            neutral.radius = side * 0.5
            neutral.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
            inner[2usize * i] = widget.aligned(0u64, .Center, .Center, neutral, held[0usize..1usize])
        }
        var ring = sized_style(ringed, ringed)
        ring.radius = ringed * 0.5
        ring.background = paint.Brush { Solid: ground }
        inner[2usize * i + 1usize] = widget.aligned(0u64, .Center, .Center, ring, inner[2usize * i..2usize * i + 1usize])
        layers[i] = widget.positioned(0u64, f32(i) * step, 0.0, style.defaults(), inner[2usize * i + 1usize..2usize * i + 2usize])
        i += 1usize
    }
    let width = f32(discs - 1usize) * step + ringed
    let group = widget.stack(0u64, sized_style(width, ringed), layers[0usize..discs])
    // The name: the shown faces' labels, "and" before the last, or "and N others".
    var spelled = 32usize
    i = 0usize
    while i < shown {
        spelled += faces[i].label.len + 2usize
        i += 1usize
    }
    let (named, named_error) = mem.alloc[u8](a, spelled)
    if named_error != ok { ret (zero, TooLarge) }
    var at = 0usize
    i = 0usize
    while i < shown {
        if i > 0usize && (i + 1usize < shown || more > 0usize) { at += copy_text(named[at..named.len], ", ") }
        if i > 0usize && i + 1usize == shown && more == 0usize { at += copy_text(named[at..named.len], " and ") }
        at += copy_text(named[at..named.len], faces[i].label)
        i += 1usize
    }
    if more > 0usize {
        at += copy_text(named[at..named.len], " and ")
        at += write_i64(named[at..named.len], i64(more))
        if more == 1usize { at += copy_text(named[at..named.len], " other") } else { at += copy_text(named[at..named.len], " others") }
    }
    let name = named[0usize..at]
    if mem.address_of(open) != 0usize {
        let state = control_state(t, key, true, false)
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = with_alpha(style.color(t.tokens, .OnSurface), state_opacity(t, state))
        look.border_width = 0.0
        look.radius = ringed * 0.5
        look.opacity = 1.0
        look.custom_padding = true
        look.padding = 0.0
        look.padding_y = 0.0
        look.min_height = ringed
        look.min_width = width
        let (pressed, pressed_error) = pressable_states(a, key, t, 3u8, name, look, true, false, 0u32, 0u32, 0u64, open, group)
        ret (pressed, pressed_error)
    }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = group
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = name
    ret (widget.semantics(key, sem, style.defaults(), held[0usize..1usize]), ok)
}

fn avatar_of(a: *mem.Arena, key: widget.Key, t: *const Theme, texture: scene.TextureId, options: AvatarOptions) -> (widget.Node, err) {
    let size = avatar_size(options.size)
    let pictured = texture.slot != 0u32 || texture.generation != 0u32
    var disc = sized_style(size, size)
    disc.radius = size * 0.5
    if options.square { disc.radius = t.tokens.radii.sm }
    disc.overflow = .Clip
    var ground: style.ColorRole = .SurfaceContainerHighest
    var ink: style.ColorRole = .OnSurfaceVariant
    let (content, content_error) = mem.alloc[widget.Node](a, 2usize)
    if content_error != ok { ret (zero, TooLarge) }
    if pictured {
        content[0usize] = widget.image(0u64, widget.Image { texture: texture, fit: .Cover }, sized_style(size, size))
    } else {
        if options.initials.len != 0usize {
            let pick = account_hash(options.account) % 3u32
            ground = .PrimaryContainer
            ink = .OnPrimaryContainer
            if pick == 1u32 {
                ground = .SecondaryContainer
                ink = .OnSecondaryContainer
            }
            if pick == 2u32 {
                ground = .TertiaryContainer
                ink = .OnTertiaryContainer
            }
            var said = text_options()
            said.wrap = .None
            said.role = .LabelSmall
            if size > 24.0 { said.role = .LabelLarge }
            if size > 32.0 { said.role = .TitleMedium }
            if size > 40.0 { said.role = .TitleLarge }
            if size > 56.0 { said.role = .HeadlineMedium }
            let (words, words_error) = colored_text(a, 0u64, options.initials, t, said, style.color(t.tokens, ink))
            if words_error != ok { ret (zero, words_error) }
            content[1usize] = words
        } else {
            var mark: f32 = 16.0
            if size > 24.0 { mark = 18.0 }
            if size > 32.0 { mark = 24.0 }
            if size > 40.0 { mark = 36.0 }
            let (square, square_error) = icon_square(a, style.color(t.tokens, ink), .Person, mark)
            if square_error != ok { ret (zero, square_error) }
            content[1usize] = square
        }
        content[0usize] = widget.aligned(0u64, .Center, .Center, sized_style(size, size), content[1usize..2usize])
    }
    disc.background = paint.Brush { Solid: style.color(t.tokens, ground) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 4usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[0usize] = widget.box(0u64, disc, content[0usize..1usize])
    var count = 1usize
    var word: str = ""
    if options.presence != .None {
        var mark: f32 = 8.0
        if size > 24.0 { mark = 10.0 }
        if size > 32.0 { mark = 12.0 }
        if size > 40.0 { mark = 14.0 }
        if size > 56.0 { mark = 16.0 }
        let ring_color = style.color(t.tokens, options.ground)
        var dot = sized_style(mark, mark)
        dot.radius = mark * 0.5
        dot.background = paint.Brush { Solid: ring_color }
        var bars: []const widget.Node = zero
        if options.presence == .Online {
            word = "online"
            dot.background = paint.Brush { Solid: style.color(t.tokens, .Success) }
        }
        if options.presence == .Away {
            word = "away"
            dot.border = style.Border { width: 2.5, color: style.color(t.tokens, .Warning) }
        }
        if options.presence == .Offline {
            word = "offline"
            dot.border = style.Border { width: 2.0, color: style.color(t.tokens, .Outline) }
        }
        if options.presence == .Busy {
            word = "do not disturb"
            dot.background = paint.Brush { Solid: style.color(t.tokens, .Error) }
            var bar = sized_style(mark * 0.5, max_of(2.0, mark * 0.2))
            bar.background = paint.Brush { Solid: style.color(t.tokens, .OnError) }
            layers[3usize] = widget.box(0u64, bar, zero)
            bars = layers[3usize..4usize]
        }
        let (marks, marks_error) = mem.alloc[widget.Node](a, 2usize)
        if marks_error != ok { ret (zero, TooLarge) }
        marks[0usize] = widget.aligned(0u64, .Center, .Center, dot, bars)
        var ring = sized_style(mark + 4.0, mark + 4.0)
        ring.radius = (mark + 4.0) * 0.5
        ring.background = paint.Brush { Solid: ring_color }
        marks[1usize] = widget.padded(0u64, 2.0, 2.0, 2.0, 2.0, ring, marks[0usize..1usize])
        layers[1usize] = widget.positioned(0u64, size - mark - 4.0, size - mark - 4.0, style.defaults(), marks[1usize..2usize])
        count = 2usize
    }
    layers[2usize] = widget.stack(0u64, sized_style(size, size), layers[0usize..count])
    var name = options.label
    if word.len != 0usize && name.len != 0usize {
        let (named, named_error) = mem.alloc[u8](a, name.len + 2usize + word.len)
        if named_error != ok { ret (zero, TooLarge) }
        var at = copy_text(named, name)
        at += copy_text(named[at..named.len], ", ")
        at += copy_text(named[at..named.len], word)
        name = named[0usize..at]
    }
    var sem: widget.Semantics = zero
    sem.role = ROLE_IMAGE
    sem.label = name
    sem.hidden = options.label.len == 0usize
    ret (widget.semantics(key, sem, style.defaults(), layers[2usize..3usize]), ok)
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

// A card: the elevated card of D965 below, its children in a column.
fn card(a: *mem.Arena, key: widget.Key, t: *const Theme, children: []const widget.Node) -> (widget.Node, err) {
    let (made, made_error) = card_of(a, key, t, card_options(), children)
    ret (made, made_error)
}

// A card's treatment (D965): lifted, filled or outlined.
type CardVariant = enum u8 { Elevated, Filled, Outlined }

// A card's options: its treatment, its width (0: its content's), the dense grid's
// padding, whether it is enabled, selected or loading, the loading media height
// and shimmer phase, the title and supporting text it is named and described by,
// the actions that open and select the card (both absent: a static card).
type CardOptions = struct { variant: CardVariant, width: f32, dense: bool, enabled: bool, selected: bool, dragged: bool, loading: bool, phase: f32, media_height: f32, title: str, description: str, action: *const widget.Submit, select: *const widget.Submit, range_select: *const widget.Submit }

fn card_options() -> CardOptions {
    var out: CardOptions = zero
    out.enabled = true
    out.media_height = 112.0
    ret out
}

// v2 (D965, docs/ux/components/Card): `radius-md` 12 (`radius-sm` 8 under 120
// wide), `space-4` 16 padding (12 dense), clipping its children in a column.
// Elevated is `surface-container-low` at `elevation-1`, filled
// `surface-container-highest` with no shadow, outlined `surface` in a 1px
// `outline-variant` edge. A pressable card is one Button named by the title under
// the `on-surface` state layer, hover lifting it a level (to `elevation-2`
// elevated); a static one is a Group named by the title. Selected draws the 2px
// `primary` outline inside the edge and a 24 `primary` check disc 8 in from the
// top end (with a width to place it). Disabled is `on-surface` 12% with the
// content at 38%, no shadow, not focusable. Loading replaces the content with
// synchronised media, title (60%) and supporting-line (90%) skeletons, and marks
// the non-interactive Card busy; the caller owns the 300ms delay and phase.
fn card_of(a: *mem.Arena, key: widget.Key, t: *const Theme, options: CardOptions, children: []const widget.Node) -> (widget.Node, err) {
    let (made, made_error) = card_render(a, key, t, options, false, children)
    ret (made, made_error)
}

type CardCommands = struct { runtime: *widget.Runtime, open: *const widget.Submit, select: *const widget.Submit, range_select: *const widget.Submit }

fn card_gesture(ctx: *void, gesture: widget.Gesture) -> err {
    let commands = mem.cast[*CardCommands](ctx)
    if gesture.tag != .Tap { ret ok }
    if widget.space_activation(commands.runtime) && mem.address_of(commands.select) != 0usize { ret widget.fire_submit(*commands.select) }
    let held = widget.modifiers(commands.runtime)
    if held.shift && mem.address_of(commands.range_select) != 0usize { ret widget.fire_submit(*commands.range_select) }
    if (held.control || held.meta) && mem.address_of(commands.select) != 0usize { ret widget.fire_submit(*commands.select) }
    if mem.address_of(commands.open) != 0usize { ret widget.fire_submit(*commands.open) }
    if mem.address_of(commands.select) != 0usize { ret widget.fire_submit(*commands.select) }
    ret ok
}

fn card_semantic_action(ctx: *void, action: u32) -> err {
    let commands = mem.cast[*CardCommands](ctx)
    if action == accessibility.ACTION_SELECT && mem.address_of(commands.select) != 0usize { ret widget.fire_submit(*commands.select) }
    if action == accessibility.ACTION_PRESS && mem.address_of(commands.open) != 0usize { ret widget.fire_submit(*commands.open) }
    ret ok
}

fn card_render(a: *mem.Arena, key: widget.Key, t: *const Theme, options: CardOptions, flush: bool, children: []const widget.Node) -> (widget.Node, err) {
    let opens = mem.address_of(options.action) != 0usize
    let can_select = mem.address_of(options.select) != 0usize
    let interactive = (opens || can_select) && !options.loading
    let state = control_state(t, key, options.enabled && interactive, options.selected)
    if can_select && options.enabled && !options.loading {
        let hold_error = widget.long_press_touch(t.runtime, key, options.select)
        if hold_error != ok { ret (zero, hold_error) }
    }
    var ground = style.color(t.tokens, .SurfaceContainerLow)
    var raised = 1usize
    if options.variant == .Filled {
        ground = style.color(t.tokens, .SurfaceContainerHighest)
        raised = 0usize
    }
    if options.variant == .Outlined {
        ground = style.color(t.tokens, .Background)
        raised = 0usize
    }
    if options.dragged && options.enabled {
        ground = style.layer(ground, style.color(t.tokens, .OnSurface), t.tokens.states.dragged)
        raised = 4usize
    } else if interactive && options.enabled {
        ground = style.layer(ground, style.color(t.tokens, .OnSurface), state_opacity(t, state))
        if state.hovered { raised += 1usize }
    }
    var s = style.defaults()
    if !options.enabled {
        ground = with_alpha(style.color(t.tokens, .OnSurface), t.tokens.states.disabled_container)
        raised = 0usize
    }
    s.background = paint.Brush { Solid: ground }
    s.radius = t.tokens.radii.md
    if options.width > 0.0 {
        s.width = style.Length { Px: options.width }
        if options.width < 120.0 { s.radius = t.tokens.radii.sm }
    }
    var pad_px: f32 = 16.0
    if options.dense { pad_px = 12.0 }
    if flush { pad_px = 0.0 }
    let pad = style.Length { Px: pad_px }
    s.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    s.overflow = .Clip
    if options.variant == .Outlined { s.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .OutlineVariant) } }
    if options.selected { s.border = style.Border { width: t.tokens.sizes.outline_focused, color: style.color(t.tokens, .Primary) } }
    if raised > 0usize { s.shadow = style.Shadow { offset: geometry.Point { x: 0.0, y: f32(raised) * 2.0 }, color: paint.rgba(0.0, 0.0, 0.0, t.tokens.elevation[raised]) } }
    var column_style = style.defaults()
    if !options.enabled { column_style.opacity = t.tokens.states.disabled_content }
    var card_children = children
    if options.loading {
        var inner_width: f32 = 168.0
        if options.width > pad_px * 2.0 { inner_width = options.width - pad_px * 2.0 }
        let (sweep, sweep_error) = placeholder_sweep(a, t, options.phase / 6.2831855, inner_width, 0.4)
        if sweep_error != ok { ret (zero, sweep_error) }
        var media_options = skeleton_options()
        media_options.radius = t.tokens.radii.sm
        media_options.sweep = sweep
        media_options.on_highest = options.variant == .Filled
        var line_options = media_options
        line_options.shape = .Line
        let (loading_shapes, loading_shapes_error) = mem.alloc[widget.Node](a, 2usize)
        let (content_parts, content_parts_error) = mem.alloc[widget.Node](a, 2usize)
        let (probe_parts, probe_parts_error) = mem.alloc[widget.Node](a, 1usize)
        let (loading_layers, loading_layers_error) = mem.alloc[widget.Node](a, 3usize)
        if loading_shapes_error != ok || content_parts_error != ok || probe_parts_error != ok || loading_layers_error != ok { ret (zero, TooLarge) }
        let (media_node, media_error) = skeleton_of(a, 0u64, t, inner_width, options.media_height, media_options)
        let (title_node, title_error) = skeleton_of(a, 0u64, t, inner_width * 0.6, 14.0, line_options)
        let (supporting_node, supporting_error) = skeleton_of(a, 0u64, t, inner_width * 0.9, 12.0, line_options)
        if media_error != ok || title_error != ok || supporting_error != ok { ret (zero, TooLarge) }
        loading_shapes[0usize] = title_node
        loading_shapes[1usize] = supporting_node
        content_parts[0usize] = media_node
        content_parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, style.defaults(), loading_shapes[0usize..2usize])
        probe_parts[0usize] = sweep_node(sweep, probe_paint, 1.0, 1.0)
        loading_layers[0usize] = widget.positioned(0u64, 0.0, 0.0, style.defaults(), probe_parts)
        loading_layers[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, style.defaults(), content_parts)
        loading_layers[2usize] = widget.stack(0u64, style.defaults(), loading_layers[0usize..2usize])
        card_children = loading_layers[2usize..3usize]
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column_style, card_children)
    var count = 1usize
    if options.selected && options.width > 0.0 {
        // The check disc, placed from the start: the stack has no end anchor.
        var disc = sized_style(24.0, 24.0)
        disc.radius = 12.0
        disc.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
        disc.padding = style.EdgeLengths { left: style.Length { Px: 4.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 4.0 }, bottom: style.Length { Px: 4.0 } }
        let (tick, tick_error) = mark_glyph(a, style.color(t.tokens, .OnPrimary), .Check, 16.0)
        if tick_error != ok { ret (zero, tick_error) }
        parts[3usize] = tick
        parts[2usize] = widget.box(0u64, disc, parts[3usize..4usize])
        parts[1usize] = widget.positioned(0u64, options.width - 8.0 - 24.0 - pad_px, 8.0 - pad_px, style.defaults(), parts[2usize..3usize])
        count = 2usize
    }
    let (holder, holder_error) = mem.alloc[widget.Node](a, 4usize)
    if holder_error != ok { ret (zero, TooLarge) }
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = options.title
    sem.hint = options.description
    if options.selected { sem.states = accessibility.STATE_SELECTED }
    if options.loading { sem.states = sem.states | accessibility.STATE_BUSY }
    if !options.enabled { sem.states = sem.states | accessibility.STATE_DISABLED }
    if interactive {
        let (commands, commands_error) = mem.alloc[CardCommands](a, 1usize)
        if commands_error != ok { ret (zero, TooLarge) }
        commands[0usize] = CardCommands { runtime: t.runtime, open: options.action, select: options.select, range_select: options.range_select }
        sem.role = 3u8
        if opens { sem.actions = accessibility.ACTION_PRESS }
        if can_select { sem.actions = sem.actions | accessibility.ACTION_SELECT }
        sem.promote_actions = true
        sem.on_action = widget.Change[u32] { ctx: mem.cast[*void](&commands[0usize]), invoke: card_semantic_action }
        var press_children = parts[0usize..1usize]
        if count > 1usize {
            holder[1usize] = widget.stack(0u64, style.defaults(), parts[0usize..count])
            press_children = holder[1usize..2usize]
        }
        holder[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&commands[0usize]), invoke: card_gesture }, gestures: 1u8 | 4u8 | 16u8, enabled: options.enabled, focusable: options.enabled }, s, press_children)
        holder[2usize] = widget.semantics(0u64, sem, style.defaults(), holder[0usize..1usize])
        if options.dragged && options.enabled && !t.tokens.motion.reduced {
            holder[3usize] = holder[2usize]
            ret (widget.transformed(0u64, widget.VisualTransform { scale: 1.02, rotation: 0.02617994, offset: zero }, style.defaults(), holder[3usize..4usize]), ok)
        }
        ret (holder[2usize], ok)
    }
    if count == 1usize {
        holder[0usize] = widget.box(0u64, s, parts[0usize..1usize])
    } else {
        holder[0usize] = widget.stack(0u64, s, parts[0usize..count])
    }
    holder[2usize] = widget.semantics(key, sem, style.defaults(), holder[0usize..1usize])
    if options.dragged && options.enabled && !t.tokens.motion.reduced {
        holder[3usize] = holder[2usize]
        ret (widget.transformed(0u64, widget.VisualTransform { scale: 1.02, rotation: 0.02617994, offset: zero }, style.defaults(), holder[3usize..4usize]), ok)
    }
    ret (holder[2usize], ok)
}

// A Card's standard content slots: optional full-bleed media, an optional
// header, caller-composed supporting/meta content, and end-aligned actions.
type CardSlots = struct { media: widget.Node, has_media: bool, header: widget.Node, has_header: bool, content: []const widget.Node, actions: []const widget.Node }

fn card_slots() -> CardSlots {
    var out: CardSlots = zero
    ret out
}

// The slot layout keeps media flush with the clipped top corners, then pads the
// header/content/actions by 16 (12 dense); actions share an 8-pixel end row.
fn card_with_slots(a: *mem.Arena, key: widget.Key, t: *const Theme, options: CardOptions, slots: CardSlots) -> (widget.Node, err) {
    var count = slots.content.len
    if slots.has_header { count += 1usize }
    if slots.actions.len != 0usize { count += 1usize }
    let (body_parts, body_parts_error) = mem.alloc[widget.Node](a, count)
    if body_parts_error != ok { ret (zero, TooLarge) }
    var at = 0usize
    if slots.has_header {
        body_parts[at] = slots.header
        at += 1usize
    }
    var i = 0usize
    while i < slots.content.len {
        body_parts[at] = slots.content[i]
        at += 1usize
        i += 1usize
    }
    if slots.actions.len != 0usize {
        var action_style = style.defaults()
        action_style.width = style.Length { Percent: 100.0 }
        body_parts[at] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: 8.0 }, action_style, slots.actions)
    }
    var body_style = style.defaults()
    body_style.width = style.Length { Percent: 100.0 }
    var pad_px: f32 = 16.0
    if options.dense { pad_px = 12.0 }
    let pad = style.Length { Px: pad_px }
    body_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    let (root_parts, root_parts_error) = mem.alloc[widget.Node](a, 2usize)
    if root_parts_error != ok { ret (zero, TooLarge) }
    var root_count = 0usize
    if slots.has_media {
        root_parts[root_count] = slots.media
        root_count += 1usize
    }
    root_parts[root_count] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, body_style, body_parts)
    root_count += 1usize
    let (made, made_error) = card_render(a, key, t, options, true, root_parts[0usize..root_count])
    ret (made, made_error)
}

// A group box: the outlined group box of D965 below.
fn group_box(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, children: []const widget.Node) -> (widget.Node, err) {
    let (made, made_error) = group_box_of(a, key, t, label, group_options(), children)
    ret (made, made_error)
}

// A group box's box (D965): outlined, filled, or none.
type GroupVariant = enum u8 { Outlined, Filled, Plain }

// A group box's options: its box, the description under the title, the
// group-level message (set: the group is invalid), whether it is enabled, its
// width (0: its widest row's), and an optional caller-owned collapsed form.
type GroupOptions = struct { variant: GroupVariant, description: str, message: str, enabled: bool, width: f32, expanded: bool, summary: str, toggle: *const widget.Submit }

fn group_options() -> GroupOptions {
    var out: GroupOptions = zero
    out.enabled = true
    ret out
}

// v2 (D965, docs/ux/components/GroupBox): the title in `title-small`
// `on-surface` 4 in from the box edge, the description in `body-small`
// `on-surface-variant` 2 under it, the box 8 below: outlined `surface` in a 1px
// `outline-variant` edge, filled `surface-container-low`, both `radius-md` 12
// clipping their rows; each child a row at least 48 tall (56 on touch) padded 4 by
// 16, 1px `outline-variant` dividers between them (plain: no box and no
// dividers). Invalid, the edge is 2px `error` and the message stands 8 below in
// `body-small` `error` after a 16 `alert` mark 4 from it. Disabled, the title and
// rows are at 38% and the edge `on-surface` 12%, the description kept. With a
// toggle, the title is an inset-ring Button with Expanded/Controls, a trailing
// chevron and the caller's collapsed summary. A Group named by the title.
fn group_box_of(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: GroupOptions, children: []const widget.Node) -> (widget.Node, err) {
    let plain = options.variant == .Plain
    let collapsible = mem.address_of(options.toggle) != 0usize
    var row_h: f32 = t.tokens.sizes.control_lg
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { row_h = t.tokens.sizes.control_xl }
    var fade: f32 = 1.0
    if !options.enabled { fade = t.tokens.states.disabled_content }
    let n = children.len
    let (rows, rows_error) = mem.alloc[widget.Node](a, 2usize * n + 1usize)
    if rows_error != ok { ret (zero, TooLarge) }
    var count = 0usize
    var i = 0usize
    while i < n {
        if i > 0usize && !plain {
            var line = style.defaults()
            line.height = style.Length { Px: t.tokens.sizes.divider }
            if options.width > 0.0 { line.width = style.Length { Px: options.width } }
            line.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
            rows[count] = widget.box(0u64, line, zero)
            count += 1usize
        }
        var row_style = style.defaults()
        row_style.min_height = style.Length { Px: row_h }
        if options.width > 0.0 { row_style.width = style.Length { Px: options.width } }
        row_style.opacity = fade
        var side: f32 = 16.0
        if plain { side = 4.0 }
        row_style.padding = style.EdgeLengths { left: style.Length { Px: side }, top: style.Length { Px: 4.0 }, right: style.Length { Px: side }, bottom: style.Length { Px: 4.0 } }
        rows[count] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 16.0 }, row_style, children[i..i + 1usize])
        count += 1usize
        i += 1usize
    }
    var box_style = style.defaults()
    if !plain {
        box_style.radius = t.tokens.radii.md
        box_style.overflow = .Clip
        if options.variant == .Filled {
            box_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
        } else {
            box_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
            box_style.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .OutlineVariant) }
        }
        if !options.enabled { box_style.border = style.Border { width: t.tokens.sizes.divider, color: with_alpha(style.color(t.tokens, .OnSurface), t.tokens.states.disabled_container) } }
        if options.message.len != 0usize { box_style.border = style.Border { width: t.tokens.sizes.outline_focused, color: style.color(t.tokens, .Error) } }
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    // The title and the description.
    let (heads, heads_error) = mem.alloc[widget.Node](a, 2usize)
    if heads_error != ok { ret (zero, TooLarge) }
    var caption = text_options()
    caption.role = .TitleSmall
    caption.wrap = .None
    let (heading, heading_error) = colored_text(a, 0u64, label, t, caption, with_alpha(style.color(t.tokens, .OnSurface), fade))
    if heading_error != ok { ret (zero, heading_error) }
    heads[0usize] = heading
    if collapsible {
        let (title_bits, title_bits_error) = mem.alloc[widget.Node](a, 3usize)
        if title_bits_error != ok { ret (zero, TooLarge) }
        title_bits[0usize] = heading
        title_bits[1usize] = widget.spacer(0u64, 1.0)
        var chevron: GlyphKind = .ChevronRight
        if t.tokens.direction == .RightToLeft { chevron = .ChevronLeft }
        if options.expanded { chevron = .ChevronDown }
        let (mark, mark_error) = icon_square(a, with_alpha(style.color(t.tokens, .OnSurfaceVariant), fade), chevron, t.tokens.sizes.icon_sm)
        if mark_error != ok { ret (zero, mark_error) }
        title_bits[2usize] = mark
        var title_style = style.defaults()
        if options.width > 0.0 { title_style.width = style.Length { Px: options.width } }
        let title_line = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, title_style, title_bits[0usize..3usize])
        let title_state = control_state(t, key + 1u64, options.enabled, false)
        var look = style.resolve(t.tokens, .Plain, title_state)
        look.background = style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), style.color(t.tokens, .OnSurface), state_opacity(t, title_state))
        look.foreground = style.color(t.tokens, .OnSurface)
        look.border_width = 0.0
        look.custom_padding = true
        look.padding = 4.0
        look.padding_y = 2.0
        look.min_height = 24.0
        if options.width > 0.0 { look.min_width = options.width }
        var states = 0u32
        var actions = accessibility.ACTION_EXPAND
        if options.expanded {
            states = accessibility.STATE_EXPANDED
            actions = accessibility.ACTION_COLLAPSE
        }
        let (built, button_error) = pressable_states(a, key + 1u64, t, 3u8, label, look, options.enabled, false, states, actions, key + 2u64, options.toggle, title_line)
        if button_error != ok { ret (zero, button_error) }
        var title_button = built
        switch title_button.kind {
        case .Semantics as button_sem:
            var inset_sem = button_sem
            inset_sem.focus_inset = 3.0
            title_button.kind = widget.Kind { Semantics: inset_sem }
        default:
            title_button = built
        }
        let (keyed, keyed_error) = toggle_keys(a, options.expanded, t.tokens.direction == .RightToLeft, options.toggle, title_button)
        if keyed_error != ok { ret (zero, keyed_error) }
        heads[0usize] = keyed
    }
    var head_count = 1usize
    var note = options.description
    if collapsible && !options.expanded && options.summary.len > 0usize { note = options.summary }
    if note.len != 0usize {
        var said = text_options()
        said.role = .BodySmall
        said.max_lines = 2u32
        let (described, described_error) = colored_text(a, 0u64, note, t, said, style.color(t.tokens, .OnSurfaceVariant))
        if described_error != ok { ret (zero, described_error) }
        heads[1usize] = described
        head_count = 2usize
    }
    var head_style = style.defaults()
    head_style.padding = style.EdgeLengths { left: style.Length { Px: 4.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    if collapsible { head_style.padding.left = style.Length { Px: 0.0 } }
    parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 2.0 }, head_style, heads[0usize..head_count])
    var part_count = 1usize
    if !collapsible || options.expanded {
        var box_key = 0u64
        if collapsible { box_key = key + 2u64 }
        parts[part_count] = widget.flex(box_key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, box_style, rows[0usize..count])
        part_count += 1usize
    }
    if options.message.len != 0usize {
        let alarm = style.color(t.tokens, .Error)
        let (said, said_error) = mem.alloc[widget.Node](a, 2usize)
        if said_error != ok { ret (zero, TooLarge) }
        let (mark, mark_error) = icon_square(a, alarm, .Alert, 16.0)
        if mark_error != ok { ret (zero, mark_error) }
        said[0usize] = mark
        var words = text_options()
        words.role = .BodySmall
        let (message_node, message_error) = colored_text(a, 0u64, options.message, t, words, alarm)
        if message_error != ok { ret (zero, message_error) }
        said[1usize] = message_node
        let (announced, announced_error) = mem.alloc[widget.Node](a, 1usize)
        if announced_error != ok { ret (zero, TooLarge) }
        announced[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), said[0usize..2usize])
        var alert: widget.Semantics = zero
        alert.role = 24u8
        alert.label = options.message
        alert.states = accessibility.STATE_INVALID
        alert.live = 2u8
        parts[part_count] = widget.semantics(0u64, alert, style.defaults(), announced[0usize..1usize])
        part_count += 1usize
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, style.defaults(), parts[0usize..part_count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    sem.hint = note
    if options.message.len != 0usize {
        sem.hint = options.message
        sem.states = accessibility.STATE_INVALID
    }
    if !options.enabled { sem.states = sem.states | accessibility.STATE_DISABLED }
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A divider across `axis`, `length` long (0 to fill): the full-width divider of
// D965 below.
fn divider(a: *mem.Arena, key: widget.Key, t: *const Theme, axis: ui_layout.Axis, length: f32) -> (widget.Node, err) {
    var options = divider_options()
    options.axis = axis
    options.length = length
    let (made, made_error) = divider_of(a, key, t, options)
    ret (made, made_error)
}

// A divider's geometry (D965): its axis and length (0 to fill), the start and
// end insets (56 or 72 for an inset divider, 16 each for a middle inset), the
// label splitting it (and whether the label leads after a 16 line), and whether it
// must be seen (`outline` in high contrast).
type DividerOptions = struct { axis: ui_layout.Axis, length: f32, start: f32, end: f32, label: str, label_start: bool, strong: bool }

fn divider_options() -> DividerOptions {
    var out: DividerOptions = zero
    out.axis = .Horizontal
    ret out
}

// v2 (D965, docs/ux/components/Divider): a 1px (`divider`) line in
// `outline-variant` (`outline` when strong) across the axis, inset by the start
// and end margins; labelled, the line, the label in `label-medium`
// `on-surface-variant` 12 from each line, and the line again (a 16 lead line
// for a start label). Horizontal start/end insets follow reading direction
// (D1159). Decorative, it is left out of the tree; labelled, it is a Group
// named by its label.
fn divider_of(a: *mem.Arena, key: widget.Key, t: *const Theme, options: DividerOptions) -> (widget.Node, err) {
    var ink = style.color(t.tokens, .OutlineVariant)
    if options.strong { ink = style.color(t.tokens, .Outline) }
    let horizontal = options.axis == .Horizontal
    let thick = style.Length { Px: t.tokens.sizes.divider }
    var span: style.Length = style.Length { Percent: 100.0 }
    if options.length > 0.0 { span = style.Length { Px: options.length } }
    var outer = style.defaults()
    var line = style.defaults()
    line.background = paint.Brush { Solid: ink }
    let none = style.Length { Px: 0.0 }
    let lead = style.Length { Px: options.start }
    let tail = style.Length { Px: options.end }
    if horizontal {
        outer.width = span
        line.height = thick
        line.width = style.Length { Flex: 1.0 }
        outer.padding = style.EdgeLengths { left: lead, top: none, right: tail, bottom: none }
        if t.tokens.direction == .RightToLeft { outer.padding = style.EdgeLengths { left: tail, top: none, right: lead, bottom: none } }
    } else {
        outer.height = span
        line.width = thick
        line.height = style.Length { Flex: 1.0 }
        outer.padding = style.EdgeLengths { left: none, top: lead, right: none, bottom: tail }
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.box(0u64, line, zero)
    var count = 1usize
    if options.label.len != 0usize {
        var caption = text_options()
        caption.role = .LabelMedium
        caption.wrap = .None
        let (said, said_error) = colored_text(a, 0u64, options.label, t, caption, style.color(t.tokens, .OnSurfaceVariant))
        if said_error != ok { ret (zero, said_error) }
        parts[1usize] = said
        parts[2usize] = parts[0usize]
        if options.label_start {
            var short = line
            short.width = style.Length { Px: 16.0 }
            parts[0usize] = widget.box(0u64, short, zero)
        }
        count = 3usize
    }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    var gap: f32 = 0.0
    if count > 1usize { gap = 12.0 }
    body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: options.axis, main: .Start, cross: .Center, gap: gap }, outer, parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.hidden = true
    if options.label.len != 0usize {
        sem.hidden = false
        sem.role = 2u8
        sem.label = options.label
    }
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// A badge's kind (D971): a 6 dot, or a count that is urgent (`error`, the
// default), emphasis (`primary`) or neutral (`surface-container-highest`).
type BadgeKind = enum u8 { Urgent, Emphasis, Neutral, Dot }

// A badge: a count of the urgent kind, a status in the tree labelled by the value.
fn badge(a: *mem.Arena, key: widget.Key, t: *const Theme, value: str) -> (widget.Node, err) {
    let (pill, pill_error) = badge_of(a, 0u64, t, value, .Urgent)
    if pill_error != ok { ret (zero, pill_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = pill
    var sem: widget.Semantics = zero
    sem.role = 26u8
    sem.label = value
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// A count as a badge shows it (D971): "99+" above 99.
fn badge_count(a: *mem.Arena, count: i64) -> (str, err) {
    if count > 99i64 { ret ("99+", ok) }
    let (digits, digits_error) = mem.alloc[u8](a, 21usize)
    if digits_error != ok { ret (zero, TooLarge) }
    let n = write_i64(digits, count)
    ret (digits[0usize..n], ok)
}

// v2 (D971, docs/ux/components/Badge): a count 16 tall and at least 16 wide, 4 at
// the sides, fully rounded, its value in `label-small` centred -- urgent `error` /
// `on-error`, emphasis `primary` / `on-primary`, neutral
// `surface-container-highest` / `on-surface-variant` -- or a 6 `error` dot. Not in
// the tree: its meaning belongs in the anchor's name (`badge_name`).
fn badge_of(a: *mem.Arena, key: widget.Key, t: *const Theme, value: str, kind: BadgeKind) -> (widget.Node, err) {
    if kind == .Dot {
        var dot = sized_style(6.0, 6.0)
        dot.background = paint.Brush { Solid: style.color(t.tokens, .Error) }
        dot.radius = 3.0
        ret (widget.box(key, dot, zero), ok)
    }
    var ground: style.ColorRole = .Error
    var ink: style.ColorRole = .OnError
    if kind == .Emphasis {
        ground = .Primary
        ink = .OnPrimary
    }
    if kind == .Neutral {
        ground = .SurfaceContainerHighest
        ink = .OnSurfaceVariant
    }
    var caption = text_options()
    caption.role = .LabelSmall
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, value, t, caption, style.color(t.tokens, ink))
    if label_error != ok { ret (zero, label_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = label_node
    var pill = style.defaults()
    pill.height = style.Length { Px: 16.0 }
    pill.min_width = style.Length { Px: 16.0 }
    pill.background = paint.Brush { Solid: style.color(t.tokens, ground) }
    pill.radius = 8.0
    let side = style.Length { Px: 4.0 }
    let flat = style.Length { Px: 0.0 }
    pill.padding = style.EdgeLengths { left: side, top: flat, right: side, bottom: flat }
    ret (widget.flex(key, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, pill, body[0usize..1usize]), ok)
}

// v2 (D971): a badge on the top end corner of an anchor `side` square (an icon or
// an avatar): a dot with its centre 3 in from the corner, a count 2 above the top
// and starting 12 before the end; the stack stands 2 taller to hold it.
fn badge_anchor(a: *mem.Arena, key: widget.Key, anchor: widget.Node, side: f32, mark: widget.Node, dot: bool) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[2usize] = anchor
    parts[3usize] = mark
    parts[0usize] = widget.positioned(0u64, 0.0, 2.0, style.defaults(), parts[2usize..3usize])
    if dot {
        parts[1usize] = widget.positioned(0u64, side - 6.0, 2.0, style.defaults(), parts[3usize..4usize])
    } else {
        parts[1usize] = widget.positioned(0u64, side - 12.0, 0.0, style.defaults(), parts[3usize..4usize])
    }
    ret (widget.stack(key, sized_style(side, side + 2.0), parts[0usize..2usize]), ok)
}

// An anchor's name with its badge's meaning (D971): "Builds, 2 failed".
fn badge_name(a: *mem.Arena, name: str, suffix: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, name.len + suffix.len + 2usize)
    if out_error != ok { ret (zero, TooLarge) }
    var n = copy_text(out, name)
    out[n] = 44u8
    out[n + 1usize] = 32u8
    n += 2usize
    n += copy_text(out[n..out.len], suffix)
    ret (out[0usize..n], ok)
}

// The tone of a status label (D971).
type StatusTone = enum u8 { Success, Warning, Error, New, Neutral }

// v2 (D971, docs/ux/components/Badge, status label): a word 24 tall in its tone's
// container pair -- success, warning, error, tertiary (new) or secondary
// (neutral) -- `radius-xs`, 8 at the sides, `label-medium`, with a 14 mark 4
// before it when `marked` (check for success, alert otherwise); a text in the
// tree with the word.
fn status_label(a: *mem.Arena, key: widget.Key, t: *const Theme, word: str, tone: StatusTone, marked: bool) -> (widget.Node, err) {
    var ground: style.ColorRole = .SecondaryContainer
    var ink: style.ColorRole = .OnSecondaryContainer
    var kind: GlyphKind = .Alert
    if tone == .Success {
        ground = .SuccessContainer
        ink = .OnSuccessContainer
        kind = .Check
    }
    if tone == .Warning {
        ground = .WarningContainer
        ink = .OnWarningContainer
    }
    if tone == .Error {
        ground = .ErrorContainer
        ink = .OnErrorContainer
    }
    if tone == .New {
        ground = .TertiaryContainer
        ink = .OnTertiaryContainer
    }
    let (bits, bits_error) = mem.alloc[widget.Node](a, 2usize)
    if bits_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    if marked {
        let (mark, mark_error) = stroked_glyph(a, style.color(t.tokens, ink), kind, 14.0, 1.5)
        if mark_error != ok { ret (zero, mark_error) }
        bits[n] = mark
        n += 1usize
    }
    var caption = text_options()
    caption.role = .LabelMedium
    caption.wrap = .None
    let (said, said_error) = colored_text(a, 0u64, word, t, caption, style.color(t.tokens, ink))
    if said_error != ok { ret (zero, said_error) }
    bits[n] = said
    n += 1usize
    var tag = style.defaults()
    tag.height = style.Length { Px: 24.0 }
    tag.background = paint.Brush { Solid: style.color(t.tokens, ground) }
    tag.radius = t.tokens.radii.xs
    let side = style.Length { Px: 8.0 }
    let flat = style.Length { Px: 0.0 }
    tag.padding = style.EdgeLengths { left: side, top: flat, right: side, bottom: flat }
    ret (widget.flex(key, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, tag, bits[0usize..n]), ok)
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

// A loading region's sweep (D970, docs/ux/components/Placeholder and Skeleton):
// the band's phase (the caller's clock, in turns; below zero, or under reduced
// motion, none), the region's width, the band's share of it and its colour, and
// where the region stands on the page -- learnt when the region's probe paints,
// which is before its shapes, so every shape's band is the same band.
type Sweep = struct { x: f32, y: f32, known: bool, angled: bool, phase: f32, span: f32, band: f32, stops: [3]paint.Stop }

// A sweep for a region `span` wide at `phase`, its band `band` of the width
// (Placeholder 45%, Skeleton 40%) in `surface-container-high`.
fn placeholder_sweep(a: *mem.Arena, t: *const Theme, phase: f32, span: f32, band: f32) -> (*Sweep, err) {
    let (sweeps, sweeps_error) = mem.alloc[Sweep](a, 1usize)
    if sweeps_error != ok { ret (zero, TooLarge) }
    var s: Sweep = zero
    s.phase = phase
    if t.tokens.motion.reduced { s.phase = 0.0 - 1.0 }
    s.span = span
    s.band = band
    let high = style.color(t.tokens, .SurfaceContainerHigh)
    s.stops[0usize] = paint.Stop { offset: 0.0, color: with_alpha(high, 0.0) }
    s.stops[1usize] = paint.Stop { offset: 0.5, color: high }
    s.stops[2usize] = paint.Stop { offset: 1.0, color: with_alpha(high, 0.0) }
    sweeps[0usize] = s
    ret (&sweeps[0usize], ok)
}

fn probe_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let s = mem.cast[*Sweep](ctx)
    s.x = area.x
    s.y = area.y
    s.known = true
    ret ok
}

fn band_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let s = mem.cast[*Sweep](ctx)
    if !s.known || s.phase < 0.0 { ret ok }
    let width = s.span * s.band
    let turn = s.phase - f32(i64(s.phase))
    let left = s.x - width + turn * (s.span + width)
    var lean: f32 = 0.0
    if s.angled { lean = width * 0.17632698 }
    let brush = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: left, y: s.y }, end: geometry.Point { x: left + width, y: s.y - lean }, stops: s.stops[0usize..3usize] } }
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: area, brush: brush } })
}

fn sweep_node(sweep: *Sweep, draw: fn(*void, *scene.Builder, geometry.Rect) -> err, width: f32, height: f32) -> widget.Node {
    var none: []const widget.Node = zero
    ret widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](sweep), measure: ring_measure, paint: draw, state: widget.bytes_of[Sweep](sweep) } }, style: sized_style(width, height), children: none }
}

// A loading shape: a `width` by `height` block in `color` with `radius`,
// clipping the region's band when there is a sweep; not in the tree.
fn loading_shape(a: *mem.Arena, key: widget.Key, width: f32, height: f32, radius: f32, color: paint.Color, sweep: *Sweep) -> (widget.Node, err) {
    var block = sized_style(width, height)
    block.background = paint.Brush { Solid: color }
    block.radius = radius
    block.overflow = .Clip
    if mem.address_of(sweep) == 0usize { ret (widget.box(key, block, zero), ok) }
    let (bands, bands_error) = mem.alloc[widget.Node](a, 1usize)
    if bands_error != ok { ret (zero, TooLarge) }
    bands[0usize] = sweep_node(sweep, band_paint, width, height)
    ret (widget.box(key, block, bands[0usize..1usize]), ok)
}

// v2 (D970, docs/ux/components/Placeholder): the region being loaded, named
// `label` and busy, its shapes (in `content`) left out of the tree; its probe
// learns where it stands so the sweep crosses every shape together.
fn placeholder_region(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, sweep: *Sweep, content: widget.Node) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var count = 0usize
    if mem.address_of(sweep) != 0usize {
        parts[2usize] = sweep_node(sweep, probe_paint, 1.0, 1.0)
        parts[0usize] = widget.positioned(0u64, 0.0, 0.0, style.defaults(), parts[2usize..3usize])
        count = 1usize
    }
    parts[count] = content
    count += 1usize
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.stack(0u64, style.defaults(), parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    sem.states = accessibility.STATE_BUSY
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// A placeholder's shape (D970): a text line, a block with the content's radius,
// or a circle.
type PlaceholderShape = enum u8 { Block, Line, Circle }
type PlaceholderOptions = struct { shape: PlaceholderShape, radius: f32, sweep: *Sweep }

fn placeholder_options(t: *const Theme) -> PlaceholderOptions {
    var out: PlaceholderOptions = zero
    out.shape = .Block
    out.radius = t.tokens.radii.md
    ret out
}

// v2 (D970, docs/ux/components/Placeholder): a shape in `surface-container-highest`
// -- a block `width` by `height` with `options.radius` (`radius-md` by default), a
// text line `height` tall (12 when 0) and fully rounded, or a circle `width`
// across -- carrying its region's sweep, a band 45% of the region wide fading to
// `surface-container-high`; it is not in the tree (its region is).
fn placeholder_of(a: *mem.Arena, key: widget.Key, t: *const Theme, width: f32, height: f32, options: PlaceholderOptions) -> (widget.Node, err) {
    var h = height
    var radius = options.radius
    if options.shape == .Line {
        if h <= 0.0 { h = 12.0 }
        radius = h * 0.5
    }
    if options.shape == .Circle {
        h = width
        radius = width * 0.5
    }
    let (node, node_error) = loading_shape(a, key, width, h, radius, style.color(t.tokens, .SurfaceContainerHighest), options.sweep)
    ret (node, node_error)
}

// A placeholder standing alone: a `radius-xs` block that is its own busy node.
fn placeholder(a: *mem.Arena, key: widget.Key, t: *const Theme, width: f32, height: f32) -> (widget.Node, err) {
    var options = placeholder_options(t)
    options.radius = t.tokens.radii.xs
    let (shape_node, shape_error) = placeholder_of(a, 0u64, t, width, height, options)
    if shape_error != ok { ret (zero, shape_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = shape_node
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
    // v2 (D983, widget plan P5-02): a touch theme's press ripple is `on-surface`
    // at the `state-pressed` opacity; a pointer theme has none.
    var ripple = with_alpha(style.color(t.tokens, .OnSurface), t.tokens.states.pressed)
    if !(t.tokens.metrics.control_height > t.tokens.sizes.control_sm) { ripple = with_alpha(ripple, 0.0) }
    widget.set_ripple(t.runtime, ripple)
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
    let (node, node_error) = pressable_states_fill(a, key, t, role, label, look, enabled, selected, states, actions, controls, action, false, content)
    ret (node, node_error)
}

// A pressable whose hit region may fill the width offered by its parent.
fn pressable_states_fill(a: *mem.Arena, key: widget.Key, t: *const Theme, role: u8, label: str, look: style.ResolvedControl, enabled: bool, selected: bool, states: u32, actions: u32, controls: widget.Key, action: *const widget.Submit, fill: bool, content: widget.Node) -> (widget.Node, err) {
    var s = style.defaults()
    if fill { s.width = style.Length { Percent: 100.0 } }
    s.background = paint.Brush { Solid: look.background }
    s.border = style.Border { width: look.border_width, color: look.border }
    s.radius = look.radius
    s.corners = look.corners
    s.opacity = look.opacity
    s.min_height = style.Length { Px: max_of(t.tokens.metrics.control_height, look.min_height) }
    s.min_width = style.Length { Px: max_of(t.tokens.metrics.hit_target, look.min_width) }
    // A look with its own box states its own minimum, smaller ones included (D952).
    if look.custom_padding && look.min_height > 0.0 { s.min_height = style.Length { Px: look.min_height } }
    if look.custom_padding && look.min_width > 0.0 { s.min_width = style.Length { Px: look.min_width } }
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
        // v2 (D970, docs/ux/components/ProgressRing): the 18 ring takes the content colour.
        var inked = progress_options()
        inked.content = look.foreground
        let (ring, ring_error) = progress_ring_of(a, 0u64, t, label, 0.0, true, t.tokens.sizes.icon_sm, inked)
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

// The state layer's opacity a control's state asks for (D955): pressed over hover
// over keyboard focus, none at rest or disabled.
fn state_opacity(t: *const Theme, state: style.ControlState) -> f32 {
    if state.disabled { ret 0.0 }
    if state.pressed { ret t.tokens.states.pressed }
    if state.hovered { ret t.tokens.states.hover }
    if state.focus_visible { ret t.tokens.states.focus }
    ret 0.0
}

// A drawn glyph (D955): the tick, the dash and the close cross the selection
// controls mark themselves with, stroked 2px round in `color` across the area;
// and (D956) the chevrons a menu's opener points with; (D959) the chevrons a
// calendar turns its months with and the calendar a date field ends in; (D960)
// the clock a time or duration field ends in.
// (D962) The person, picture and alert marks an avatar, an image and a status
// fall back to, and a stroke width per glyph so an icon strokes 1.75 at 24.
// (D967) The drag handle, dock-left, maximise, more-horiz and arrow-back marks a
// dock panel's and a workspace's header actions draw.
// (D980) The arrow-up and arrow-down a sorted table column's header shows.
// (D982) The refresh a pull to refresh's command shows.
type GlyphKind = enum u8 { Check, Dash, Cross, ChevronDown, ChevronUp, ChevronLeft, ChevronRight, Calendar, Clock, Search, Person, Picture, Alert, DragHandle, DockLeft, Maximize, MoreHoriz, ArrowBack, ArrowForward, Info, CheckCircle, Warning, MoreVert, Menu, ArrowUp, ArrowDown, Refresh }
type Glyph = struct { color: paint.Color, kind: GlyphKind, arena: *mem.Arena, stroke: f32 }

// An ellipse of four quarter arcs about a centre.
fn oval(b: *geometry.PathBuilder, cx: f32, cy: f32, rx: f32, ry: f32) -> err {
    let kx = rx * 0.5523
    let ky = ry * 0.5523
    try geometry.move_to(b, geometry.Point { x: cx, y: cy - ry })
    try geometry.cubic_to(b, geometry.Point { x: cx + kx, y: cy - ry }, geometry.Point { x: cx + rx, y: cy - ky }, geometry.Point { x: cx + rx, y: cy })
    try geometry.cubic_to(b, geometry.Point { x: cx + rx, y: cy + ky }, geometry.Point { x: cx + kx, y: cy + ry }, geometry.Point { x: cx, y: cy + ry })
    try geometry.cubic_to(b, geometry.Point { x: cx - kx, y: cy + ry }, geometry.Point { x: cx - rx, y: cy + ky }, geometry.Point { x: cx - rx, y: cy })
    try geometry.cubic_to(b, geometry.Point { x: cx - rx, y: cy - ky }, geometry.Point { x: cx - kx, y: cy - ry }, geometry.Point { x: cx, y: cy - ry })
    ret geometry.close_path(b)
}

fn glyph_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let g = mem.cast[*Glyph](ctx)
    let (pb, pb_error) = geometry.path_builder(g.arena, 16usize, 24usize)
    if pb_error != ok { ret TooLarge }
    var builder = pb
    let x = area.x
    let y = area.y
    let w = area.width
    let h = area.height
    if g.kind == .Check {
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.18, y: y + h * 0.52 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.40, y: y + h * 0.74 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.82, y: y + h * 0.30 })
    }
    if g.kind == .Dash {
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.22, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.78, y: y + h * 0.5 })
    }
    if g.kind == .ChevronDown {
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.29, y: y + h * 0.40 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.61 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.71, y: y + h * 0.40 })
    }
    if g.kind == .ChevronUp {
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.29, y: y + h * 0.60 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.39 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.71, y: y + h * 0.60 })
    }
    if g.kind == .ChevronLeft {
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.60, y: y + h * 0.29 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.39, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.60, y: y + h * 0.71 })
    }
    if g.kind == .ChevronRight {
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.40, y: y + h * 0.29 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.61, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.40, y: y + h * 0.71 })
    }
    if g.kind == .Calendar {
        // A page with a rule under its head and two rings above it.
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.17, y: y + h * 0.25 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.83, y: y + h * 0.25 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.83, y: y + h * 0.85 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.17, y: y + h * 0.85 })
        try geometry.close_path(&builder)
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.17, y: y + h * 0.42 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.83, y: y + h * 0.42 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.35, y: y + h * 0.12 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.35, y: y + h * 0.30 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.65, y: y + h * 0.12 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.65, y: y + h * 0.30 })
    }
    if g.kind == .Clock {
        // A face of four quarter arcs, its hands at three o'clock.
        let cx = x + w * 0.5
        let cy = y + h * 0.5
        let rx = w * 0.40
        let ry = h * 0.40
        let kx = rx * 0.5523
        let ky = ry * 0.5523
        try geometry.move_to(&builder, geometry.Point { x: cx, y: cy - ry })
        try geometry.cubic_to(&builder, geometry.Point { x: cx + kx, y: cy - ry }, geometry.Point { x: cx + rx, y: cy - ky }, geometry.Point { x: cx + rx, y: cy })
        try geometry.cubic_to(&builder, geometry.Point { x: cx + rx, y: cy + ky }, geometry.Point { x: cx + kx, y: cy + ry }, geometry.Point { x: cx, y: cy + ry })
        try geometry.cubic_to(&builder, geometry.Point { x: cx - kx, y: cy + ry }, geometry.Point { x: cx - rx, y: cy + ky }, geometry.Point { x: cx - rx, y: cy })
        try geometry.cubic_to(&builder, geometry.Point { x: cx - rx, y: cy - ky }, geometry.Point { x: cx - kx, y: cy - ry }, geometry.Point { x: cx, y: cy - ry })
        try geometry.close_path(&builder)
        try geometry.move_to(&builder, geometry.Point { x: cx, y: y + h * 0.26 })
        try geometry.line_to(&builder, geometry.Point { x: cx, y: cy })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.68, y: cy })
    }
    if g.kind == .Search {
        // A lens of four quarter arcs and its handle to the lower right (D961).
        let cx = x + w * 0.42
        let cy = y + h * 0.42
        let rx = w * 0.25
        let ry = h * 0.25
        let kx = rx * 0.5523
        let ky = ry * 0.5523
        try geometry.move_to(&builder, geometry.Point { x: cx, y: cy - ry })
        try geometry.cubic_to(&builder, geometry.Point { x: cx + kx, y: cy - ry }, geometry.Point { x: cx + rx, y: cy - ky }, geometry.Point { x: cx + rx, y: cy })
        try geometry.cubic_to(&builder, geometry.Point { x: cx + rx, y: cy + ky }, geometry.Point { x: cx + kx, y: cy + ry }, geometry.Point { x: cx, y: cy + ry })
        try geometry.cubic_to(&builder, geometry.Point { x: cx - kx, y: cy + ry }, geometry.Point { x: cx - rx, y: cy + ky }, geometry.Point { x: cx - rx, y: cy })
        try geometry.cubic_to(&builder, geometry.Point { x: cx - rx, y: cy - ky }, geometry.Point { x: cx - kx, y: cy - ry }, geometry.Point { x: cx, y: cy - ry })
        try geometry.close_path(&builder)
        try geometry.move_to(&builder, geometry.Point { x: cx + rx * 0.72, y: cy + ry * 0.72 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.84, y: y + h * 0.84 })
    }
    if g.kind == .Person {
        // A head over the curve of the shoulders.
        try oval(&builder, x + w * 0.5, y + h * 0.33, w * 0.17, h * 0.17)
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.18, y: y + h * 0.86 })
        try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.18, y: y + h * 0.58 }, geometry.Point { x: x + w * 0.82, y: y + h * 0.58 }, geometry.Point { x: x + w * 0.82, y: y + h * 0.86 })
    }
    if g.kind == .Picture {
        // A frame with a range of hills across its foot.
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.15, y: y + h * 0.2 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.85, y: y + h * 0.2 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.85, y: y + h * 0.8 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.15, y: y + h * 0.8 })
        try geometry.close_path(&builder)
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.15, y: y + h * 0.7 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.4, y: y + h * 0.46 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.6, y: y + h * 0.64 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.7, y: y + h * 0.56 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.85, y: y + h * 0.68 })
    }
    if g.kind == .Alert {
        // A ring round an exclamation mark.
        try oval(&builder, x + w * 0.5, y + h * 0.5, w * 0.4, h * 0.4)
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.3 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.54 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.69 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.70 })
    }
    if g.kind == .Cross {
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.28, y: y + h * 0.28 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.72, y: y + h * 0.72 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.72, y: y + h * 0.28 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.28, y: y + h * 0.72 })
    }
    if g.kind == .DragHandle {
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.2, y: y + h * 0.4 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.8, y: y + h * 0.4 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.2, y: y + h * 0.6 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.8, y: y + h * 0.6 })
    }
    if g.kind == .DockLeft || g.kind == .Maximize {
        // A window; dock-left adds its docked strip at the start.
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.17, y: y + h * 0.2 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.83, y: y + h * 0.2 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.83, y: y + h * 0.8 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.17, y: y + h * 0.8 })
        try geometry.close_path(&builder)
        if g.kind == .DockLeft {
            try geometry.move_to(&builder, geometry.Point { x: x + w * 0.4, y: y + h * 0.2 })
            try geometry.line_to(&builder, geometry.Point { x: x + w * 0.4, y: y + h * 0.8 })
        }
    }
    if g.kind == .MoreHoriz {
        // Three dots as round-capped strokes of no length.
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.25, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.26, y: y + h * 0.5 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.51, y: y + h * 0.5 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.75, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.76, y: y + h * 0.5 })
    }
    if g.kind == .ArrowBack {
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.8, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.2, y: y + h * 0.5 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.45, y: y + h * 0.25 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.2, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.45, y: y + h * 0.75 })
    }
    if g.kind == .ArrowForward {
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.2, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.8, y: y + h * 0.5 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.55, y: y + h * 0.25 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.8, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.55, y: y + h * 0.75 })
    }
    if g.kind == .Refresh {
        // (D982) Three quarters of a ring from the east round to the north, the
        // head at its end pointing on round.
        let cx = x + w * 0.5
        let cy = y + h * 0.5
        let r = w * 0.32
        let k = r * 0.5523
        try geometry.move_to(&builder, geometry.Point { x: cx + r, y: cy })
        try geometry.cubic_to(&builder, geometry.Point { x: cx + r, y: cy + k }, geometry.Point { x: cx + k, y: cy + r }, geometry.Point { x: cx, y: cy + r })
        try geometry.cubic_to(&builder, geometry.Point { x: cx - k, y: cy + r }, geometry.Point { x: cx - r, y: cy + k }, geometry.Point { x: cx - r, y: cy })
        try geometry.cubic_to(&builder, geometry.Point { x: cx - r, y: cy - k }, geometry.Point { x: cx - k, y: cy - r }, geometry.Point { x: cx, y: cy - r })
        try geometry.move_to(&builder, geometry.Point { x: cx - r * 0.45, y: cy - r * 1.45 })
        try geometry.line_to(&builder, geometry.Point { x: cx, y: cy - r })
        try geometry.line_to(&builder, geometry.Point { x: cx - r * 0.45, y: cy - r * 0.55 })
    }
    if g.kind == .ArrowUp || g.kind == .ArrowDown {
        // (D980) A shaft and a head, pointing up or down.
        var tip: f32 = 0.2
        var tail: f32 = 0.8
        if g.kind == .ArrowDown {
            tip = 0.8
            tail = 0.2
        }
        let back = tip + (tail - tip) * 0.42
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * tail })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * tip })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.25, y: y + h * back })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * tip })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.75, y: y + h * back })
    }
    if g.kind == .Info {
        // A ring round an i (D971): the dot above, the stem below.
        try oval(&builder, x + w * 0.5, y + h * 0.5, w * 0.4, h * 0.4)
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.46 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.70 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.31 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.32 })
    }
    if g.kind == .CheckCircle {
        try oval(&builder, x + w * 0.5, y + h * 0.5, w * 0.4, h * 0.4)
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.32, y: y + h * 0.51 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.45, y: y + h * 0.64 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.69, y: y + h * 0.39 })
    }
    if g.kind == .Warning {
        // A triangle round an exclamation mark.
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.14 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.9, y: y + h * 0.84 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.1, y: y + h * 0.84 })
        try geometry.close_path(&builder)
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.40 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.60 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.72 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.73 })
    }
    if g.kind == .MoreVert {
        // (D972) The app bar's More: three dots down the middle.
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.25 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.26 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.51 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.75 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.5, y: y + h * 0.76 })
    }
    if g.kind == .Menu {
        // (D972) Open navigation: three rules.
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.2, y: y + h * 0.3 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.8, y: y + h * 0.3 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.2, y: y + h * 0.5 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.8, y: y + h * 0.5 })
        try geometry.move_to(&builder, geometry.Point { x: x + w * 0.2, y: y + h * 0.7 })
        try geometry.line_to(&builder, geometry.Point { x: x + w * 0.8, y: y + h * 0.7 })
    }
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: geometry.finish(&builder), brush: paint.Brush { Solid: g.color }, stroke: paint.Stroke { width: g.stroke, cap: .Round, join: .Round, miter_limit: 4.0 } } })
}

fn mark_glyph(a: *mem.Arena, color: paint.Color, kind: GlyphKind, size: f32) -> (widget.Node, err) {
    let (node, node_error) = stroked_glyph(a, color, kind, size, 2.0)
    ret (node, node_error)
}

fn stroked_glyph(a: *mem.Arena, color: paint.Color, kind: GlyphKind, size: f32, stroke: f32) -> (widget.Node, err) {
    let (glyphs, glyphs_error) = mem.alloc[Glyph](a, 1usize)
    if glyphs_error != ok { ret (zero, TooLarge) }
    glyphs[0usize] = Glyph { color: color, kind: kind, arena: a, stroke: stroke }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&glyphs[0usize]), measure: mark_measure, paint: glyph_paint, state: widget.bytes_of[Glyph](&glyphs[0usize]) } }, style: sized_style(size, size), children: none }, ok)
}

// A popover's beak (D976, docs/ux/components/Popover): the 6 of its rotated 12
// square that stands outside the container's edge, a filled triangle `width` by
// `height` in `color`, its tip toward `pointing` (ChevronLeft, ChevronRight,
// ChevronUp or ChevronDown).
fn beak(a: *mem.Arena, color: paint.Color, pointing: GlyphKind, width: f32, height: f32) -> (widget.Node, err) {
    let (made, made_error) = stroked_glyph(a, color, pointing, width, 0.0)
    if made_error != ok { ret (zero, made_error) }
    var out = made
    switch out.kind {
    case .Custom as c:
        var filled = c
        filled.paint = beak_paint
        out.kind = widget.Kind { Custom: filled }
    default:
        out = out
    }
    out.style = sized_style(width, height)
    ret (out, ok)
}

fn beak_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let g = mem.cast[*Glyph](ctx)
    let (pb, pb_error) = geometry.path_builder(g.arena, 4usize, 4usize)
    if pb_error != ok { ret TooLarge }
    var builder = pb
    let x0 = area.x
    let y0 = area.y
    let x1 = area.x + area.width
    let y1 = area.y + area.height
    let xm = area.x + area.width * 0.5
    let ym = area.y + area.height * 0.5
    if g.kind == .ChevronLeft {
        try geometry.move_to(&builder, geometry.Point { x: x1, y: y0 })
        try geometry.line_to(&builder, geometry.Point { x: x0, y: ym })
        try geometry.line_to(&builder, geometry.Point { x: x1, y: y1 })
    }
    if g.kind == .ChevronRight {
        try geometry.move_to(&builder, geometry.Point { x: x0, y: y0 })
        try geometry.line_to(&builder, geometry.Point { x: x1, y: ym })
        try geometry.line_to(&builder, geometry.Point { x: x0, y: y1 })
    }
    if g.kind == .ChevronUp {
        try geometry.move_to(&builder, geometry.Point { x: x0, y: y1 })
        try geometry.line_to(&builder, geometry.Point { x: xm, y: y0 })
        try geometry.line_to(&builder, geometry.Point { x: x1, y: y1 })
    }
    if g.kind == .ChevronDown {
        try geometry.move_to(&builder, geometry.Point { x: x0, y: y0 })
        try geometry.line_to(&builder, geometry.Point { x: xm, y: y1 })
        try geometry.line_to(&builder, geometry.Point { x: x1, y: y0 })
    }
    try geometry.close_path(&builder)
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&builder), brush: paint.Brush { Solid: g.color } } })
}

// A choice's mark in its state circle (D956): the box or ring, filled or dotted
// once chosen, under the circle's state layer.
fn choice_mark(a: *mem.Arena, t: *const Theme, state: style.ControlState, chosen: bool, mixed: bool, round: bool, enabled: bool) -> (widget.Node, err) {
    let h = t.tokens.metrics.control_height
    var circle = t.tokens.sizes.control_md
    var mark: f32 = 18.0
    if round { mark = 20.0 }
    if h < t.tokens.sizes.control_sm {
        circle = t.tokens.sizes.control_sm
        mark = 16.0
    }
    let filled = chosen || mixed
    let primary = style.color(t.tokens, .Primary)
    let quiet = with_alpha(style.color(t.tokens, .OnSurface), t.tokens.states.disabled_content)
    var edge = style.color(t.tokens, .OnSurfaceVariant)
    if filled { edge = primary }
    if !enabled { edge = quiet }
    var mark_style = sized_style(mark, mark)
    mark_style.border = style.Border { width: 2.0, color: edge }
    mark_style.radius = 2.0
    let (inside, inside_error) = mem.alloc[widget.Node](a, 1usize)
    if inside_error != ok { ret (zero, TooLarge) }
    var inside_count = 0usize
    if round {
        mark_style.radius = mark * 0.5
        if chosen {
            var dot = sized_style(mark * 0.5, mark * 0.5)
            dot.radius = mark * 0.25
            dot.background = paint.Brush { Solid: edge }
            inside[0usize] = widget.box(0u64, dot, zero)
            inside_count = 1usize
        }
    } else {
        if filled {
            mark_style.background = paint.Brush { Solid: edge }
            var tick = style.color(t.tokens, .OnPrimary)
            if !enabled { tick = style.color(t.tokens, .Background) }
            var kind: GlyphKind = .Check
            if mixed { kind = .Dash }
            let (drawn, drawn_error) = mark_glyph(a, tick, kind, mark - 4.0)
            if drawn_error != ok { ret (zero, drawn_error) }
            inside[0usize] = drawn
            inside_count = 1usize
        }
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.aligned(0u64, .Center, .Center, mark_style, inside[0usize..inside_count])
    var ink = style.color(t.tokens, .OnSurface)
    if filled { ink = primary }
    var circle_style = sized_style(circle, circle)
    circle_style.radius = circle * 0.5
    circle_style.background = paint.Brush { Solid: with_alpha(ink, state_opacity(t, state)) }
    ret (widget.aligned(0u64, .Center, .Center, circle_style, parts[0usize..1usize]), ok)
}

// A choosable row: a mark in a state circle beside a label, a tap-and-hover region
// under the role, its states from what the caller says.
// v2 (D955, docs/ux/components/Choice): the circle is 40 across (32 dense) under the
// state layer of `on-surface`, or `primary` once chosen; a checkbox is an 18 box (16
// dense) in a 2px `on-surface-variant` outline with 2 corners, filled `primary`
// when checked or mixed with the tick or dash in `on-primary`; a radio is a 20 ring
// (16 dense), `primary` round its 10 dot when selected. The label is `body-medium`
// (`body-large` on touch) in `on-surface`, 4 after the circle; the row is at least
// 40 tall (48 on touch, 32 dense). Disabled is `on-surface` at 38%, a checked box
// keeping its fill in that with a `surface` tick.
fn choosable(a: *mem.Arena, key: widget.Key, t: *const Theme, role: u8, label: str, chosen: bool, mixed: bool, round: bool, action: *const widget.Submit, enabled: bool) -> (widget.Node, err) {
    let state = control_state(t, key, enabled, false)
    let h = t.tokens.metrics.control_height
    let touch = h > t.tokens.sizes.control_sm
    var row_min = t.tokens.sizes.control_md
    if touch { row_min = t.tokens.sizes.target_touch }
    if h < t.tokens.sizes.control_sm { row_min = t.tokens.sizes.control_sm }
    let quiet = with_alpha(style.color(t.tokens, .OnSurface), t.tokens.states.disabled_content)
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (mark_node, mark_error) = choice_mark(a, t, state, chosen, mixed, round, enabled)
    if mark_error != ok { ret (zero, mark_error) }
    parts[0usize] = mark_node
    var caption = text_options()
    caption.role = .BodyMedium
    if touch { caption.role = .BodyLarge }
    caption.wrap = .None
    var words = style.color(t.tokens, .OnSurface)
    if !enabled { words = quiet }
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, words)
    if label_error != ok { ret (zero, label_error) }
    parts[1usize] = label_node
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..2usize])
    // The row is centred in a box at least the row height, which the region wraps.
    var target_style = style.defaults()
    target_style.min_height = style.Length { Px: row_min }
    target_style.min_width = style.Length { Px: row_min }
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
    // v2 (D955): the rows abut.
    stacked[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), items[0usize..labels.len])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), stacked[0usize..1usize]), ok)
}

// A switch: a track with its thumb at the end when on, the label beside; a switch
// in the tree, checked when on.
// v2 (D955, docs/ux/components/Switch): a 52 x 32 fully rounded track, off the
// highest container in a 2px `outline` edge with a 16 `outline` thumb 8 in, on
// `primary` with a 24 `on-primary` thumb 4 in; hovered or pressed the thumb darkens
// (`on-surface-variant` off, `primary-container` on), pressed it grows to 28, and
// the 40 circle round it takes the state layer of `on-surface` (`primary` on). The
// switch stands in 4 each way so the circle has room; the label 12 after the track.
fn switch_control(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, on: bool, action: *const widget.Submit, enabled: bool) -> (widget.Node, err) {
    let state = control_state(t, key, enabled, false)
    let ink = style.color(t.tokens, .OnSurface)
    let highest = style.color(t.tokens, .SurfaceContainerHighest)
    var track_fill = highest
    var edge = style.color(t.tokens, .Outline)
    var edge_width: f32 = 2.0
    var thumb = edge
    var halo = ink
    var d: f32 = 16.0
    var cx: f32 = 16.0
    let active = state.hovered || state.pressed
    if active { thumb = style.color(t.tokens, .OnSurfaceVariant) }
    if on {
        track_fill = style.color(t.tokens, .Primary)
        edge_width = 0.0
        thumb = style.color(t.tokens, .OnPrimary)
        if active { thumb = style.color(t.tokens, .PrimaryContainer) }
        halo = track_fill
        d = 24.0
        cx = 36.0
    }
    if state.pressed && enabled { d = 28.0 }
    if !enabled {
        let faint = with_alpha(ink, t.tokens.states.disabled_container)
        track_fill = with_alpha(highest, t.tokens.states.disabled_container)
        edge = faint
        thumb = with_alpha(ink, t.tokens.states.disabled_content)
        if on {
            track_fill = faint
            thumb = style.color(t.tokens, .Background)
        }
    }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 3usize)
    if layers_error != ok { ret (zero, TooLarge) }
    var track = sized_style(52.0, 32.0)
    track.radius = 16.0
    track.background = paint.Brush { Solid: track_fill }
    track.border = style.Border { width: edge_width, color: edge }
    layers[0usize] = widget.positioned(0u64, 4.0, 4.0, track, zero)
    var circle = sized_style(40.0, 40.0)
    circle.radius = 20.0
    circle.background = paint.Brush { Solid: with_alpha(halo, state_opacity(t, state)) }
    layers[1usize] = widget.positioned(0u64, 4.0 + cx - 20.0, 0.0, circle, zero)
    var knob = sized_style(d, d)
    knob.radius = d * 0.5
    knob.background = paint.Brush { Solid: thumb }
    layers[2usize] = widget.positioned(0u64, 4.0 + cx - d * 0.5, 20.0 - d * 0.5, knob, zero)
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.stack(0u64, sized_style(60.0, 40.0), layers[0usize..3usize])
    var caption = text_options()
    caption.role = .BodyMedium
    caption.wrap = .None
    var words = ink
    if !enabled { words = with_alpha(ink, t.tokens.states.disabled_content) }
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, words)
    if label_error != ok { ret (zero, label_error) }
    parts[1usize] = label_node
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, style.defaults(), parts[0usize..2usize])
    var target_style = style.defaults()
    target_style.min_height = style.Length { Px: t.tokens.sizes.target_pointer }
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { target_style.min_height = style.Length { Px: t.tokens.sizes.target_touch } }
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
// selected one marked, each firing its own action; a group in the tree.
// v2 (D955, docs/ux/components/SegmentedControl): one 1px `outline` edge round
// joined segments with 1px dividers, 32 tall with `radius-sm` corners (40 and fully
// rounded on touch); a segment at least 72 wide (88 on touch), 12 each side, its
// `label-large` in `on-surface` centred, under the state layer of its label colour;
// the selected one `secondary-container` with its label in
// `on-secondary-container` after an 18 check, 8 between. Disabled, the labels are
// `on-surface` at 38%, the edge, dividers and selected fill at 12%.
fn segmented_control(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, labels: []const str, selected: usize, actions: []const widget.Submit, enabled: bool) -> (widget.Node, err) {
    if actions.len != labels.len || labels.len == 0usize { ret (zero, TooLarge) }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var height = t.tokens.sizes.control_sm
    var outer = t.tokens.radii.sm
    var least: f32 = 72.0
    if touch {
        height = t.tokens.sizes.control_md
        outer = height * 0.5
        least = 88.0
    }
    let ink = style.color(t.tokens, .OnSurface)
    let quiet = with_alpha(ink, t.tokens.states.disabled_content)
    let faint = with_alpha(ink, t.tokens.states.disabled_container)
    var edge = style.color(t.tokens, .Outline)
    if !enabled { edge = faint }
    let inner = max_zero(outer - 1.0)
    let last = labels.len - 1usize
    let count = labels.len * 2usize - 1usize
    let (items, items_error) = mem.alloc[widget.Node](a, count)
    if items_error != ok { ret (zero, TooLarge) }
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    let line = style.text_style(t.tokens, .Label).line_height
    var i = 0usize
    while i < labels.len {
        let item_key = key + 1u64 + u64(i)
        let chosen = i == selected
        let state = control_state(t, item_key, enabled, false)
        var fill = paint.rgba(0.0, 0.0, 0.0, 0.0)
        var words = ink
        if chosen {
            fill = style.color(t.tokens, .SecondaryContainer)
            words = style.color(t.tokens, .OnSecondaryContainer)
        }
        if !enabled {
            words = quiet
            if chosen { fill = faint }
        }
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = style.layer(fill, words, state_opacity(t, state))
        look.foreground = words
        look.border_width = 0.0
        look.opacity = 1.0
        look.radius = 0.0
        var left: f32 = 0.0
        var right: f32 = 0.0
        if i == 0usize { left = inner }
        if i == last { right = inner }
        look.corners = style.Corners { top_left: left, top_right: right, bottom_right: right, bottom_left: left }
        look.custom_padding = true
        look.padding = 12.0
        look.padding_y = max_zero((height - 2.0 - line) * 0.5)
        look.min_height = height - 2.0
        look.min_width = least
        let (word, word_error) = colored_text(a, 0u64, labels[i], t, caption, words)
        if word_error != ok { ret (zero, word_error) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
        if parts_error != ok { ret (zero, TooLarge) }
        var used = 1usize
        parts[0usize] = word
        if chosen {
            let (check, check_error) = mark_glyph(a, words, .Check, t.tokens.sizes.icon_sm)
            if check_error != ok { ret (zero, check_error) }
            parts[0usize] = check
            parts[1usize] = word
            used = 2usize
        }
        parts[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, style.defaults(), parts[0usize..used])
        // Centred in the least width the sides leave.
        var middle = style.defaults()
        middle.min_width = style.Length { Px: least - 24.0 }
        let content = widget.aligned(0u64, .Center, .Center, middle, parts[2usize..3usize])
        let (item, item_error) = pressable(a, item_key, t, 3u8, labels[i], look, enabled, chosen, &actions[i], content)
        if item_error != ok { ret (zero, item_error) }
        items[i * 2usize] = item
        if i != last {
            var rule = sized_style(1.0, height - 2.0)
            rule.background = paint.Brush { Solid: edge }
            items[i * 2usize + 1usize] = widget.box(0u64, rule, zero)
        }
        i += 1usize
    }
    var frame = style.defaults()
    frame.border = style.Border { width: 1.0, color: edge }
    frame.radius = outer
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, frame, items[0usize..count])
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

// A slider's value in its pill (D958): rounded digits in `label-large`
// `inverse-on-surface` on `inverse-surface`, fully rounded.
fn value_pill(a: *mem.Arena, t: *const Theme, value: f32) -> (widget.Node, err) {
    let (digits, digits_error) = mem.alloc[u8](a, 21usize)
    if digits_error != ok { ret (zero, TooLarge) }
    var rounded = value + 0.5
    if value < 0.0 { rounded = value - 0.5 }
    let digit_count = write_i64(digits, i64(rounded))
    var caption = text_options()
    caption.role = .LabelLarge
    caption.wrap = .None
    let (reading, reading_error) = colored_text(a, 0u64, digits[0usize..digit_count], t, caption, style.color(t.tokens, .InverseOnSurface))
    if reading_error != ok { ret (zero, reading_error) }
    let (inside, inside_error) = mem.alloc[widget.Node](a, 1usize)
    if inside_error != ok { ret (zero, TooLarge) }
    inside[0usize] = reading
    let line = style.text_style(t.tokens, .LabelLarge).line_height
    var bubble = style.defaults()
    bubble.min_width = style.Length { Px: 48.0 }
    bubble.background = paint.Brush { Solid: style.color(t.tokens, .InverseSurface) }
    bubble.radius = (line + 24.0) * 0.5
    let sides = style.Length { Px: 16.0 }
    let ends = style.Length { Px: 12.0 }
    bubble.padding = style.EdgeLengths { left: sides, top: ends, right: sides, bottom: ends }
    ret (widget.aligned(0u64, .Center, .Center, bubble, inside[0usize..1usize]), ok)
}

fn ranged(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, first: f32, second: f32, range: bool, low: f32, high: f32, step: f32, change: widget.Change[f32], change_second: widget.Change[f32], enabled: bool) -> (widget.Node, err) {
    // v2 (D956, docs/ux/components/Slider): 44 deep for its handle, the active part
    // and the handles `primary`, the rest `secondary-container`; disabled, those are
    // `on-surface` at 38% and 12%.
    // (D958) Hovered, a 6px `primary` halo at the hover opacity rounds the handle;
    // pressed, the handle is 2 wide; a stepped slider shows 4 dots, `on-primary` on
    // the active part and `on-secondary-container` beyond (38% disabled). While
    // dragged or keyboard-focused, a single slider's value stands in an
    // `inverse-surface` pill 8 above the handle, `label-large` in
    // `inverse-on-surface`, at least 48 wide with 16 sides and 12 above and below.
    var track_style = style.defaults()
    track_style.width = style.Length { Px: 120.0 }
    track_style.height = style.Length { Px: 44.0 }
    let ink = style.color(t.tokens, .OnSurface)
    var fill = style.color(t.tokens, .Primary)
    var rest = style.color(t.tokens, .SecondaryContainer)
    var words = ink
    var tick_on = style.color(t.tokens, .OnPrimary)
    var tick_off = style.color(t.tokens, .OnSecondaryContainer)
    if !enabled {
        fill = with_alpha(ink, t.tokens.states.disabled_content)
        rest = with_alpha(ink, t.tokens.states.disabled_container)
        words = fill
        tick_on = fill
        tick_off = fill
    }
    let state = control_state(t, key, enabled, false)
    var halo = paint.rgba(0.0, 0.0, 0.0, 0.0)
    if enabled && state.hovered && !state.pressed { halo = with_alpha(style.color(t.tokens, .Primary), t.tokens.states.hover) }
    var handle: f32 = 4.0
    if enabled && state.pressed { handle = 2.0 }
    let showing = enabled && !range && (state.pressed || state.focus_visible)
    var count = 2usize
    if showing { count = 3usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.slider(key, widget.Slider { value: first, second: second, range: range, low: low, high: high, step: step, vertical: false, rtl: t.tokens.direction == .RightToLeft, track: rest, fill: fill, thumb: fill, change: change, change_second: change_second, enabled: enabled, halo: halo, handle: handle, tick_on: tick_on, tick_off: tick_off }, track_style)
    if showing {
        let (pill, pill_error) = value_pill(a, t, first)
        if pill_error != ok { ret (zero, pill_error) }
        let (lifted, lifted_error) = mem.alloc[widget.Node](a, 1usize)
        if lifted_error != ok { ret (zero, TooLarge) }
        lifted[0usize] = pill
        var share: f32 = 0.0
        if high > low { share = (first - low) / (high - low) }
        if share < 0.0 { share = 0.0 }
        if share > 1.0 { share = 1.0 }
        if t.tokens.direction == .RightToLeft { share = 1.0 - share }
        parts[2usize] = widget.overlay(key + 1u64, widget.Overlay { anchor: key, placement: .AbovePoint, offset: geometry.Point { x: 8.0 + share * 104.0, y: 0.0 - 8.0 }, modal: false, dismiss: zero }, style.defaults(), lifted[0usize..1usize])
    }
    var caption = text_options()
    caption.role = .BodyMedium
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, words)
    if label_error != ok { ret (zero, label_error) }
    parts[1usize] = label_node
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.sm }, style.defaults(), parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 15u8
    sem.label = label
    // D1170: a single slider's semantic value follows its visible rounded value.
    if !range {
        let (said, said_error) = mem.alloc[u8](a, 21usize)
        if said_error != ok { ret (zero, TooLarge) }
        var rounded = first + 0.5
        if first < 0.0 { rounded = first - 0.5 }
        let said_len = write_i64(said, i64(rounded))
        sem.value = said[0usize..said_len]
    }
    sem.actions = accessibility.ACTION_INCREMENT | accessibility.ACTION_DECREMENT | accessibility.ACTION_SET_VALUE
    if !enabled { sem.states = accessibility.STATE_DISABLED }
    ret (widget.semantics(0u64, sem, style.defaults(), row[0usize..1usize]), ok)
}

// ------------------------------------------------------------ progress (D822, P1-09)

// How a progress indicator reads (D970): active, failed, or paused.
type ProgressTone = enum u8 { Active, Error, Paused }
// A progress indicator's look (D970): the thick (8) bar, the full-bleed bar
// (square, no gaps), the buffered share (0 for none), the tone, the phase of the
// indeterminate motion (negative: the shared clock; otherwise an exact turn),
// and a content colour for a ring inside a button (alpha 0: the tone's colours).
type ProgressOptions = struct { thick: bool, full_bleed: bool, buffer: f32, tone: ProgressTone, phase: f32, content: paint.Color }

fn progress_options() -> ProgressOptions {
    var out: ProgressOptions = zero
    out.tone = .Active
    out.phase = 0.0 - 1.0
    ret out
}

// The indicator and track colours of a tone: `primary` on `secondary-container`,
// `error` on `error-container`, paused `on-surface-variant` on
// `surface-container-highest`.
fn progress_ink(t: *const Theme, tone: ProgressTone) -> paint.Color {
    if tone == .Error { ret style.color(t.tokens, .Error) }
    if tone == .Paused { ret style.color(t.tokens, .OnSurfaceVariant) }
    ret style.color(t.tokens, .Primary)
}

fn progress_ground(t: *const Theme, tone: ProgressTone) -> paint.Color {
    if tone == .Error { ret style.color(t.tokens, .ErrorContainer) }
    if tone == .Paused { ret style.color(t.tokens, .SurfaceContainerHighest) }
    ret style.color(t.tokens, .SecondaryContainer)
}

fn clamp_share(value: f32) -> f32 {
    if value < 0.0 { ret 0.0 }
    if value > 1.0 { ret 1.0 }
    ret value
}

fn progress_turn(t: *const Theme, phase: f32, period: time.Duration) -> f32 {
    if phase < 0.0 { ret animation.cycle(t.runtime, period) }
    var turn = phase - f32(i64(phase))
    if turn < 0.0 { turn += 1.0 }
    ret turn
}

// A share as whole percent ("30%"), in the arena.
fn percent_text(a: *mem.Arena, share: f32) -> (str, err) {
    let (digits, digits_error) = mem.alloc[u8](a, 24usize)
    if digits_error != ok { ret (zero, TooLarge) }
    let count = write_i64(digits, i64(share * 100.0 + 0.5))
    digits[count] = 37u8
    ret (digits[0usize..count + 1usize], ok)
}

// A solid rounded piece of a bar.
fn bar_piece(key: widget.Key, width: f32, height: f32, color: paint.Color, radius: f32) -> widget.Node {
    var s = sized_style(width, height)
    s.background = paint.Brush { Solid: color }
    s.radius = radius
    ret widget.box(key, s, zero)
}

// A progress bar `width` wide: the v2 look with the default options.
fn progress_bar(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, indeterminate: bool, width: f32) -> (widget.Node, err) {
    let (node, node_error) = progress_bar_of(a, key, t, label, value, indeterminate, width, progress_options())
    ret (node, node_error)
}

// v2 (D970, docs/ux/components/ProgressBar): 4 tall (8 thick), fully rounded; the
// active indicator (keyed `key + 1`) as long as `value`'s share, 4 apart from the
// `secondary-container` track (and from the buffered segment, `primary` 32% over
// the track), a 4 `primary` stop dot at the track's end (2 in on the thick bar);
// full-bleed square with no gaps. Error is `error` on `error-container`, paused
// `on-surface-variant` on `surface-container-highest`. Indeterminate, two
// growing segments travel the track on the shared two-second clock and the tree
// says busy; under reduced motion two fixed segments pulse in place. Determinate,
// the value is the percent ("30%"). A progress role named `label`.
// ponytail: the label row, detail line and completion icon compose with Text
// beside the bar.
fn progress_bar_of(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, indeterminate: bool, width: f32, options: ProgressOptions) -> (widget.Node, err) {
    let share = clamp_share(value)
    let h: f32 = if_else(options.thick, 8.0, 4.0)
    let gap: f32 = if_else(options.full_bleed, 0.0, 4.0)
    let r: f32 = if_else(options.full_bleed, 0.0, h * 0.5)
    let ink = progress_ink(t, options.tone)
    let ground = progress_ground(t, options.tone)
    let (parts, parts_error) = mem.alloc[widget.Node](a, 6usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    if indeterminate {
        var track = sized_style(width, h)
        track.background = paint.Brush { Solid: ground }
        track.radius = r
        track.overflow = .Clip
        parts[n] = widget.box(0u64, track, zero)
        n += 1usize
        let turn = progress_turn(t, options.phase, time.seconds(2i64))
        if t.tokens.motion.reduced {
            let alpha = 0.38 + 0.62 * animation.triangle(turn)
            let faded = with_alpha(ink, alpha)
            let first = bar_piece(key + 1u64, width * 0.25, h, faded, r)
            let second = bar_piece(key + 2u64, width * 0.25, h, faded, r)
            let (held, held_error) = mem.alloc[widget.Node](a, 2usize)
            if held_error != ok { ret (zero, TooLarge) }
            held[0usize] = first
            held[1usize] = second
            parts[n] = widget.positioned(0u64, width * 0.15, 0.0, style.defaults(), held[0usize..1usize])
            n += 1usize
            parts[n] = widget.positioned(0u64, width * 0.60, 0.0, style.defaults(), held[1usize..2usize])
            n += 1usize
        } else {
            var phases: [2]f32 = zero
            phases[0usize] = turn
            phases[1usize] = turn + 0.5
            if phases[1usize] >= 1.0 { phases[1usize] = phases[1usize] - 1.0 }
            var i = 0usize
            while i < 2usize {
                let wave = animation.triangle(phases[i])
                let length = width * (0.15 + 0.25 * wave)
                let centre = width * (0.0 - 0.2 + 1.4 * phases[i])
                var left = centre - length * 0.5
                var right = centre + length * 0.5
                if left < 0.0 { left = 0.0 }
                if right > width { right = width }
                if right > left {
                    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
                    if held_error != ok { ret (zero, TooLarge) }
                    held[0usize] = bar_piece(key + 1u64 + u64(i), right - left, h, ink, r)
                    parts[n] = widget.positioned(0u64, left, 0.0, style.defaults(), held[0usize..1usize])
                    n += 1usize
                }
                i += 1usize
            }
        }
    } else {
        var rest = width
        let done = share * width
        if done > 0.0 {
            parts[n] = bar_piece(key + 1u64, done, h, ink, r)
            n += 1usize
            rest = rest - done - gap
        }
        let buffered = clamp_share(options.buffer)
        if buffered > share && rest > 0.0 {
            let piece = (buffered - share) * width - gap
            if piece > 0.0 {
                parts[n] = bar_piece(0u64, piece, h, style.layer(ground, ink, 0.32), r)
                n += 1usize
                rest = rest - piece - gap
            }
        }
        if rest > 0.0 {
            // The track holds the stop dot at its end, centred, 2 in on the thick bar.
            let (dots, dots_error) = mem.alloc[widget.Node](a, 1usize)
            if dots_error != ok { ret (zero, TooLarge) }
            dots[0usize] = bar_piece(0u64, 4.0, 4.0, ink, 2.0)
            var track = sized_style(rest, h)
            track.background = paint.Brush { Solid: ground }
            track.radius = r
            let inset = style.Length { Px: (h - 4.0) * 0.5 }
            let flat = style.Length { Px: 0.0 }
            track.padding = style.EdgeLengths { left: flat, top: flat, right: inset, bottom: flat }
            parts[n] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: 0.0 }, track, dots[0usize..1usize])
            n += 1usize
        }
    }
    let (bar, bar_error) = mem.alloc[widget.Node](a, 1usize)
    if bar_error != ok { ret (zero, TooLarge) }
    if indeterminate {
        bar[0usize] = widget.stack(0u64, sized_style(width, h), parts[0usize..n])
    } else {
        bar[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: gap }, sized_style(width, h), parts[0usize..n])
    }
    var sem: widget.Semantics = zero
    sem.role = 16u8
    sem.label = label
    if indeterminate {
        sem.states = accessibility.STATE_BUSY
    } else {
        let (shown, shown_error) = percent_text(a, share)
        if shown_error != ok { ret (zero, shown_error) }
        sem.value = shown
    }
    ret (widget.semantics(key, sem, style.defaults(), bar[0usize..1usize]), ok)
}

// What a ring paints (v2, D970): the track over `sweep` radians clockwise from
// `start` (radians from the top), the value arc through `share` of it, the gap in
// pixels kept clear between cap ends on either side of the value (0: the track
// runs under it), and a band in its own colour from `band_from` of the sweep to
// the end (1 or more: none). Kept in the frame arena, which outlives the paint (a
// custom node's context is read during placement only), with the arena its paths
// are built in -- the frame's, since the scene copies a path when the frame is
// compiled, after the paint returned.
type Ring = struct { track: paint.Color, fill: paint.Color, share: f32, thickness: f32, arena: *mem.Arena, start: f32, sweep: f32, gap: f32, band: paint.Color, band_from: f32 }

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
    let stroke = paint.Stroke { width: ring.thickness, cap: .Round, join: .Round, miter_limit: 4.0 }
    let value = ring.share * ring.sweep
    var from = ring.start
    var to = ring.start + ring.sweep
    if ring.gap > 0.0 && value > 0.0 {
        // Round caps reach half a stroke past each end, so the gap between cap
        // ends is the gap plus a stroke of arc.
        let cut = (ring.gap + ring.thickness) / radius
        from = ring.start + value + cut
        to = ring.start + ring.sweep - cut
    }
    if ring.track.alpha > 0.0 && to > from {
        let (track, track_error) = sweep_path(scratch, cx, cy, radius, from, to - from)
        if track_error != ok { ret track_error }
        try scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: track, brush: paint.Brush { Solid: ring.track }, stroke: stroke } })
    }
    if ring.band_from < 1.0 {
        let band_start = ring.start + ring.band_from * ring.sweep
        let (band, band_error) = sweep_path(scratch, cx, cy, radius, band_start, ring.start + ring.sweep - band_start)
        if band_error != ok { ret band_error }
        try scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: band, brush: paint.Brush { Solid: ring.band }, stroke: stroke } })
    }
    if value <= 0.0 { ret ok }
    let (arc, arc_error) = sweep_path(scratch, cx, cy, radius, ring.start, value)
    if arc_error != ok { ret arc_error }
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: arc, brush: paint.Brush { Solid: ring.fill }, stroke: stroke } })
}

// A ring as a custom node of `side`, keyed `key`, painting `ring`.
fn ring_node(a: *mem.Arena, key: widget.Key, ring: Ring, side: f32) -> (widget.Node, err) {
    let (rings, rings_error) = mem.alloc[Ring](a, 1usize)
    if rings_error != ok { ret (zero, TooLarge) }
    rings[0usize] = ring
    var none: []const widget.Node = zero
    ret (widget.Node { key: key, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&rings[0usize]), measure: ring_measure, paint: ring_paint, state: widget.bytes_of[Ring](&rings[0usize]) } }, style: sized_style(side, side), children: none }, ok)
}

// A progress ring of `size`: the v2 look with the default options.
fn progress_ring(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, indeterminate: bool, size: f32) -> (widget.Node, err) {
    let (node, node_error) = progress_ring_of(a, key, t, label, value, indeterminate, size, progress_options())
    ret (node, node_error)
}

// v2 (D970, docs/ux/components/ProgressRing): the ring (keyed `key + 1`) strokes
// its `primary` arc with round caps clockwise from 12 o'clock through `value` of
// the turn (at least 4% once above zero), over a `secondary-container` track kept
// a gap clear of either cap end; the stroke scales with the size -- 4 at 48 (gap
// 4), 3 at 36, 2 at 24, 2.25 under 22 (no gap), 4.5 from 64, where the percent
// stands inside in `label-medium` `on-surface`. Error is `error` on
// `error-container`; a content colour (a ring inside a button) draws the arc
// alone in it. Indeterminate, an arc spins once per 1.5 seconds while growing
// from 10% to 75% and shrinking; under reduced motion a still 75% arc pulses
// from 38% to full opacity every two seconds. The tree says busy; determinate,
// the value is the percent.
fn progress_ring_of(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, indeterminate: bool, size: f32, options: ProgressOptions) -> (widget.Node, err) {
    var share = clamp_share(value)
    if share > 0.0 && share < 0.04 { share = 0.04 }
    var stroke = size / 12.0
    var gap = stroke
    if size < 22.0 {
        stroke = 2.25
        gap = 0.0
    }
    if size >= 64.0 {
        stroke = 4.5
        gap = 4.0
    }
    var ring = Ring { track: progress_ground(t, options.tone), fill: progress_ink(t, options.tone), share: share, thickness: stroke, arena: a, start: 0.0, sweep: 6.2831855, gap: gap, band: zero, band_from: 2.0 }
    if options.content.alpha > 0.0 {
        ring.fill = options.content
        ring.track = paint.rgba(0.0, 0.0, 0.0, 0.0)
    }
    if indeterminate {
        ring.track = paint.rgba(0.0, 0.0, 0.0, 0.0)
        ring.gap = 0.0
        if t.tokens.motion.reduced {
            let turn = progress_turn(t, options.phase, time.seconds(2i64))
            ring.share = 0.75
            ring.fill = with_alpha(ring.fill, 0.38 + 0.62 * animation.triangle(turn))
            ring.start = 0.0
        } else {
            let turn = progress_turn(t, options.phase, time.millis(1500i64))
            ring.share = 0.10 + 0.65 * animation.triangle(turn)
            ring.start = turn * 6.2831855
        }
    }
    let (painted, painted_error) = ring_node(a, key + 1u64, ring, size)
    if painted_error != ok { ret (zero, painted_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 3usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = painted
    var count = 1usize
    var sem: widget.Semantics = zero
    sem.role = 16u8
    sem.label = label
    if indeterminate {
        sem.states = accessibility.STATE_BUSY
    } else {
        let (shown, shown_error) = percent_text(a, share)
        if shown_error != ok { ret (zero, shown_error) }
        sem.value = shown
        if size >= 64.0 {
            var inside = text_options()
            inside.role = .LabelMedium
            inside.wrap = .None
            let (reading, reading_error) = colored_text(a, 0u64, shown, t, inside, style.color(t.tokens, .OnSurface))
            if reading_error != ok { ret (zero, reading_error) }
            body[2usize] = reading
            body[1usize] = widget.aligned(0u64, .Center, .Center, sized_style(size, size), body[2usize..3usize])
            let (layered, layered_error) = mem.alloc[widget.Node](a, 1usize)
            if layered_error != ok { ret (zero, TooLarge) }
            layered[0usize] = widget.stack(0u64, sized_style(size, size), body[0usize..2usize])
            ret (widget.semantics(key, sem, style.defaults(), layered[0usize..1usize]), ok)
        }
    }
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..count]), ok)
}

// ---------------------------------------------------------- text fields (D823, P1-10)

// A field's look and behaviour: the placeholder shown while the value is empty,
// whether it takes input, whether the caller's validation found it invalid, its
// width, and for a text area the rows it shows.
// v2 (D951): filled or outlined, and the fixed text before and after the value;
// (D956) room kept clear at the end for a control standing inside it; (D960) a
// height other than the density's (0 keeps it), `body-medium` at 40 or less.
type FieldOptions = struct { placeholder: str, enabled: bool, read_only: bool, invalid: bool, width: f32, rows: u32, filled: bool, prefix: str, suffix: str, end_space: f32, height: f32, start_space: f32 }

fn field_options() -> FieldOptions {
    ret FieldOptions { placeholder: "", enabled: true, read_only: false, invalid: false, width: 160.0, rows: 1u32, filled: false, prefix: "", suffix: "", end_space: 0.0, height: 0.0, start_space: 0.0 }
}

// The field every text field is, v2 (D951, docs/ux/components/TextField): outlined
// (the pointer hosts' default) or filled (`FieldOptions.filled`, the touch hosts'),
// 16 taller than the control height -- 48 at pointer density, 56 at touch -- with
// 16px sides. The label rests inside the box in `body-large` and floats, in
// `body-small`, while the field is focused or holds a value: into a notch of the
// outline, or to the top of a filled box. At dense density (24-tall controls) the
// box is 40 and the label stands above it. The value is `body-large` in
// `on-surface`; a placeholder shows only while the empty field is focused, or at
// rest when there is no label. Focus is the 2px `primary` outline or indicator,
// invalid the 2px `error` one, hover the `on-surface` outline or layer; disabled
// dims to 4% / 38%; read-only has no fill and an `outline-variant` edge. The editor
// (keyed `key`) says text field in the tree and the label names the group. The
// caller owns the buffer and keeps the length (D807).
fn field(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, change: widget.Change[str], submit: widget.Submit, options: FieldOptions, secret: bool) -> (widget.Node, err) {
    let state = control_state(t, key, options.enabled, false)
    let focused = state.focused && options.enabled
    let hovered = state.hovered && options.enabled
    let dense = t.tokens.metrics.control_height < t.tokens.sizes.control_sm
    var h = t.tokens.metrics.control_height + 16.0
    if options.height > 0.0 { h = options.height }
    let pad_x: f32 = if_else(dense, 12.0, 16.0)
    let ink = style.color(t.tokens, .OnSurface)
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    // The edge (outline or indicator) and the label's colour by state.
    var edge = style.color(t.tokens, .Outline)
    var edge_width = t.tokens.sizes.divider
    var label_color = muted
    if options.filled { edge = muted }
    if hovered { edge = ink }
    if focused {
        edge = style.color(t.tokens, .Primary)
        edge_width = t.tokens.sizes.outline_focused
        label_color = edge
    }
    if options.invalid {
        edge = style.color(t.tokens, .Error)
        edge_width = t.tokens.sizes.outline_focused
        label_color = edge
    }
    if options.read_only && !options.invalid {
        edge = style.color(t.tokens, .OutlineVariant)
        edge_width = t.tokens.sizes.divider
    }
    var value_color = ink
    if !options.enabled {
        edge = with_alpha(ink, t.tokens.states.disabled_content)
        edge_width = t.tokens.sizes.divider
        label_color = edge
        value_color = edge
    }
    var value_role: style.TextRole = .BodyLarge
    if dense || h <= t.tokens.sizes.control_md { value_role = .BodyMedium }
    let line = style.text_style(t.tokens, value_role).line_height
    let (text_look, style_error) = text_style(a, t, value_role)
    if style_error != ok { ret (zero, style_error) }
    let multiline = options.rows > 1u32
    let floated = label.len != 0usize && !dense && (focused || len != 0usize)
    let resting = label.len != 0usize && !dense && !floated
    // The editor stands its rows tall even before it holds anything (and with no
    // fonts, when it measures as nothing), so a press reaches it.
    var editor_style = style.defaults()
    editor_style.width = style.Length { Percent: 100.0 }
    editor_style.min_height = style.Length { Px: f32(options.rows) * line }
    let (editor, editor_error) = mem.alloc[widget.Node](a, 2usize)
    if editor_error != ok { ret (zero, TooLarge) }
    var at = 0usize
    let show_hint = len == 0usize && options.placeholder.len != 0usize && (focused || label.len == 0usize)
    if show_hint || resting {
        var hint = text_options()
        hint.role = value_role
        hint.wrap = .None
        var hint_text = options.placeholder
        if resting { hint_text = label }
        let (hint_node, hint_error) = colored_text(a, 0u64, hint_text, t, hint, with_alpha(muted, value_color.alpha))
        if hint_error != ok { ret (zero, hint_error) }
        editor[at] = hint_node
        at += 1usize
    }
    editor[at] = widget.edit(key, widget.Edit { buffer: buffer, len: len, style: text_look, color: value_color, selection: style.color(t.tokens, .TextSelection), change: change, submit: submit, enabled: options.enabled, read_only: options.read_only, multiline: multiline, secret: secret, marked: zero, caret: zero, untabbed: false, ringed: false }, editor_style)
    at += 1usize
    let (lines, lines_error) = mem.alloc[widget.Node](a, 4usize)
    if lines_error != ok { ret (zero, TooLarge) }
    var parts_at = 0usize
    // The floated label on a filled box rides at the top, inside.
    if floated && options.filled {
        var small = text_options()
        small.role = .BodySmall
        small.wrap = .None
        let (small_node, small_error) = colored_text(a, 0u64, label, t, small, label_color)
        if small_error != ok { ret (zero, small_error) }
        lines[parts_at] = small_node
        parts_at += 1usize
    }
    var grow = style.defaults()
    grow.width = style.Length { Flex: 1.0 }
    let value_stack = widget.stack(0u64, grow, editor[0usize..at])
    // The prefix and suffix around the value, in `on-surface-variant`.
    let (row_parts, row_error) = mem.alloc[widget.Node](a, 3usize)
    if row_error != ok { ret (zero, TooLarge) }
    var row_at = 0usize
    var affix = text_options()
    affix.role = value_role
    affix.wrap = .None
    if options.prefix.len != 0usize && (floated || label.len == 0usize) {
        let (pre, pre_error) = colored_text(a, 0u64, options.prefix, t, affix, with_alpha(muted, value_color.alpha))
        if pre_error != ok { ret (zero, pre_error) }
        row_parts[row_at] = pre
        row_at += 1usize
    }
    row_parts[row_at] = value_stack
    row_at += 1usize
    if options.suffix.len != 0usize && (floated || label.len == 0usize) {
        let (post, post_error) = colored_text(a, 0u64, options.suffix, t, affix, with_alpha(muted, value_color.alpha))
        if post_error != ok { ret (zero, post_error) }
        row_parts[row_at] = post
        row_at += 1usize
    }
    var row_style = style.defaults()
    row_style.width = style.Length { Percent: 100.0 }
    lines[parts_at] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, row_style, row_parts[0usize..row_at])
    parts_at += 1usize
    // The frame: its height, sides, fill and edge.
    var frame_style = style.defaults()
    frame_style.width = style.Length { Px: options.width }
    var body_height = line
    if floated && options.filled { body_height = line + style.text_style(t.tokens, .BodySmall).line_height }
    var pad_top = max_zero((h - body_height) * 0.5)
    var height = h
    if multiline {
        pad_top = 12.0
        height = max_of(h, f32(options.rows) * line + 24.0)
    }
    frame_style.min_height = style.Length { Px: height }
    let side = style.Length { Px: pad_x }
    frame_style.padding = style.EdgeLengths { left: style.Length { Px: pad_x + options.start_space }, top: style.Length { Px: pad_top }, right: style.Length { Px: pad_x + options.end_space }, bottom: style.Length { Px: pad_top } }
    if options.filled {
        var fill = style.color(t.tokens, .SurfaceContainerHighest)
        if hovered { fill = style.layer(fill, ink, t.tokens.states.hover) }
        if !options.enabled { fill = with_alpha(ink, 0.04) }
        if options.read_only { fill = paint.rgba(0.0, 0.0, 0.0, 0.0) }
        frame_style.background = paint.Brush { Solid: fill }
        frame_style.corners = style.Corners { top_left: t.tokens.radii.xs, top_right: t.tokens.radii.xs, bottom_right: 0.0, bottom_left: 0.0 }
        // The indicator along the bottom edge, as wide as the box.
        frame_style.padding.bottom = style.Length { Px: 0.0 }
        var indicator = style.defaults()
        indicator.width = style.Length { Percent: 100.0 }
        indicator.height = style.Length { Px: edge_width }
        indicator.background = paint.Brush { Solid: edge }
        indicator.margin = style.EdgeLengths { left: style.Length { Px: 0.0 - pad_x }, top: style.Length { Px: max_zero(pad_top - edge_width) }, right: style.Length { Px: 0.0 - pad_x }, bottom: style.Length { Px: 0.0 } }
        lines[parts_at] = widget.box(0u64, indicator, zero)
        parts_at += 1usize
    } else {
        if !options.enabled { frame_style.background = paint.Brush { Solid: with_alpha(ink, 0.04) } }
        frame_style.border = style.Border { width: edge_width, color: edge }
        frame_style.radius = t.tokens.radii.xs
    }
    let frame = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, frame_style, lines[0usize..parts_at])
    // The outlined field's floated label sits in a notch over its top edge.
    var boxed = frame
    if floated && !options.filled {
        let (notched_node, notched_error) = notched(a, t, frame, label, label_color, pad_x)
        if notched_error != ok { ret (zero, notched_error) }
        boxed = notched_node
    }
    // Dense: the label above the box, as a field label.
    var column_count = 1usize
    if dense && label.len != 0usize { column_count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, column_count)
    if parts_error != ok { ret (zero, TooLarge) }
    if column_count == 2usize {
        var caption = text_options()
        caption.role = .TitleSmall
        caption.wrap = .None
        let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, label_color)
        if label_error != ok { ret (zero, label_error) }
        parts[0usize] = label_node
    }
    parts[column_count - 1usize] = boxed
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..column_count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    if options.invalid { sem.states = accessibility.STATE_INVALID }
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// An outlined box with its floated label in a notch over its top edge, `pad_x` in.
fn notched(a: *mem.Arena, t: *const Theme, frame: widget.Node, label: str, color: paint.Color, pad_x: f32) -> (widget.Node, err) {
    var notch = text_options()
    notch.role = .BodySmall
    notch.wrap = .None
    let (notch_node, notch_error) = colored_text(a, 0u64, label, t, notch, color)
    if notch_error != ok { ret (zero, notch_error) }
    let (notch_parts, notch_parts_error) = mem.alloc[widget.Node](a, 3usize)
    if notch_parts_error != ok { ret (zero, TooLarge) }
    notch_parts[0usize] = notch_node
    var cut = style.defaults()
    cut.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let four = style.Length { Px: 4.0 }
    let none = style.Length { Px: 0.0 }
    cut.padding = style.EdgeLengths { left: four, top: none, right: four, bottom: none }
    notch_parts[1usize] = frame
    notch_parts[2usize] = widget.positioned(0u64, pad_x - 4.0, 0.0 - style.text_style(t.tokens, .BodySmall).line_height * 0.5, cut, notch_parts[0usize..1usize])
    ret (widget.stack(0u64, style.defaults(), notch_parts[1usize..3usize]), ok)
}

fn with_alpha(c: paint.Color, alpha: f32) -> paint.Color {
    ret paint.Color { red: c.red, green: c.green, blue: c.blue, alpha: alpha }
}

fn if_else(choice: bool, yes: f32, no: f32) -> f32 {
    if choice { ret yes }
    ret no
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
    // v2 (D952, docs/ux/components/SearchBar): a pill on `surface-container-high`
    // (the hover layer of `on-surface` over it), 40 tall with a pointer and 56 on
    // touch, 12 before the query and 4 after it (16 and 8 on touch); the query in
    // `body-medium` (`body-large` on touch) and `on-surface`, the placeholder in
    // `on-surface-variant`; a clear button at the end while it holds text.
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    let state = control_state(t, key, options.enabled, false)
    var h = t.tokens.sizes.control_md
    var lead: f32 = 12.0
    var trail: f32 = 4.0
    var role: style.TextRole = .BodyMedium
    if touch {
        h = t.tokens.sizes.control_xl
        lead = 16.0
        trail = 8.0
        role = .BodyLarge
    }
    var prompt = options.placeholder
    if prompt.len == 0usize { prompt = "Search" }
    let (text_look, style_error) = text_style(a, t, role)
    if style_error != ok { ret (zero, style_error) }
    let line = style.text_style(t.tokens, role).line_height
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, TooLarge) }
    var at = 0usize
    if len == 0usize {
        var hint = text_options()
        hint.role = role
        hint.color = .OnSurfaceVariant
        hint.wrap = .None
        let (hint_node, hint_error) = text_node(a, 0u64, prompt, t, hint)
        if hint_error != ok { ret (zero, hint_error) }
        layers[at] = hint_node
        at += 1usize
    }
    var editor_style = style.defaults()
    editor_style.width = style.Length { Percent: 100.0 }
    editor_style.min_height = style.Length { Px: line }
    layers[at] = widget.edit(key, widget.Edit { buffer: buffer, len: len, style: text_look, color: style.color(t.tokens, .OnSurface), selection: style.color(t.tokens, .TextSelection), change: change, submit: submit, enabled: options.enabled, read_only: false, multiline: false, secret: false, marked: zero, caret: zero, untabbed: false, ringed: false }, editor_style)
    at += 1usize
    var count = 1usize
    if len != 0usize { count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    var grow = style.defaults()
    grow.width = style.Length { Flex: 1.0 }
    parts[0usize] = widget.stack(0u64, grow, layers[0usize..at])
    if len != 0usize {
        var plain = button_options()
        plain.variant = .Plain
        let (clear_button, clear_error) = button(a, key + 1u64, t, "Clear", clear, plain)
        if clear_error != ok { ret (zero, clear_error) }
        parts[1usize] = clear_button
    }
    var bar = style.defaults()
    bar.width = style.Length { Px: options.width }
    bar.min_height = style.Length { Px: h }
    var fill = style.color(t.tokens, .SurfaceContainerHigh)
    if state.hovered { fill = style.layer(fill, style.color(t.tokens, .OnSurface), t.tokens.states.hover) }
    bar.background = paint.Brush { Solid: fill }
    bar.radius = h * 0.5
    let pad_y = style.Length { Px: max_zero((h - line) * 0.5) }
    bar.padding = style.EdgeLengths { left: style.Length { Px: lead }, top: pad_y, right: style.Length { Px: trail }, bottom: pad_y }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, bar, parts[0usize..count]), ok)
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

// A read-only field's box that opens something (D956's select head, D959): `h`
// tall, 12 sides at 40 or less and 16 above, `radius-xs`, the 1px `outline`
// (`on-surface` hovered, 2px `primary` open), the value in `body-large` (`body-medium`
// at 40) or the label resting in `on-surface-variant` before a choice, the label in
// the notch once chosen when `notch`; the trailing `closed` mark (`opened` while
// open) 24 (18 at 40) in `on-surface-variant`, `primary` while open; a press fires
// `toggle`, and the head says Expanded while open.
fn field_head(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, shown: str, chosen: bool, open: bool, toggle: *const widget.Submit, h: f32, closed: GlyphKind, opened: GlyphKind, notch: bool) -> (widget.Node, err) {
    var none: []const widget.Node = zero
    let (made, made_error) = led_head(a, key, t, label, shown, chosen, open, toggle, h, closed, opened, notch, none)
    ret (made, made_error)
}

// The same head with `lead` (at most one node) before the value, 12 in and 12
// before it (D961: the colour picker's 20 swatch).
fn led_head(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, shown: str, chosen: bool, open: bool, toggle: *const widget.Submit, h: f32, closed: GlyphKind, opened: GlyphKind, notch: bool, lead: []const widget.Node) -> (widget.Node, err) {
    let state = control_state(t, key, true, false)
    let dense = h <= t.tokens.sizes.control_md
    let pad_x: f32 = if_else(dense, 12.0, 16.0)
    let ink = style.color(t.tokens, .OnSurface)
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var edge = style.color(t.tokens, .Outline)
    var edge_width = t.tokens.sizes.divider
    if state.hovered { edge = ink }
    var point = muted
    var label_color = muted
    if open {
        edge = style.color(t.tokens, .Primary)
        edge_width = t.tokens.sizes.outline_focused
        point = edge
        label_color = edge
    }
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = paint.rgba(0.0, 0.0, 0.0, 0.0)
    look.foreground = ink
    look.border = edge
    look.border_width = edge_width
    look.radius = t.tokens.radii.xs
    var mark: f32 = 24.0
    if dense { mark = t.tokens.sizes.icon_sm }
    look.custom_padding = true
    look.padding_start = pad_x
    look.padding = 12.0
    look.padding_y = max_zero((h - mark) * 0.5)
    look.min_height = h
    look.min_width = 112.0
    var value_role: style.TextRole = .BodyLarge
    if dense { value_role = .BodyMedium }
    var words = text_options()
    words.role = value_role
    words.wrap = .None
    var value_color = ink
    if !chosen { value_color = muted }
    let (value_node, value_error) = colored_text(a, 0u64, shown, t, words, value_color)
    if value_error != ok { ret (zero, value_error) }
    var kind = closed
    if open { kind = opened }
    let (chevron, chevron_error) = mark_glyph(a, point, kind, mark)
    if chevron_error != ok { ret (zero, chevron_error) }
    let (bits, bits_error) = mem.alloc[widget.Node](a, 4usize)
    if bits_error != ok { ret (zero, TooLarge) }
    bits[0usize] = value_node
    if lead.len == 1usize {
        // The lead is at most 20 tall, and the head keeps `h`.
        look.padding_start = 12.0
        look.padding_y = max_zero((h - max_of(mark, 20.0)) * 0.5)
        bits[2usize] = lead[0usize]
        bits[3usize] = value_node
        bits[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, style.defaults(), bits[2usize..4usize])
    }
    bits[1usize] = chevron
    // The chevron at the end of the least width.
    var spread = style.defaults()
    spread.min_width = style.Length { Px: 112.0 - pad_x - 12.0 }
    let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 12.0 }, spread, bits[0usize..2usize])
    var states = 0u32
    if open { states = accessibility.STATE_EXPANDED }
    let (head_node, head_error) = pressable_states(a, key, t, 3u8, shown, look, true, false, states, accessibility.ACTION_SHOW_MENU, key + 1u64, toggle, content)
    if head_error != ok { ret (zero, head_error) }
    var framed = head_node
    if chosen && label.len != 0usize && notch {
        let (notched_node, notched_error) = notched(a, t, head_node, label, label_color, pad_x)
        if notched_error != ok { ret (zero, notched_error) }
        framed = notched_node
    }
    ret (framed, ok)
}

// A select: a field showing the chosen option's label (keyed `key`), which fires
// `toggle` -- the caller opens or closes it; open, a modal overlay below it (keyed
// `key + 1`) lists the options as menu items keyed `key + 2 + index`, each firing
// its own action, and a press outside fires `toggle` again to close. The caller
// keeps `selected` and `open`.
// v2 (D956, docs/ux/components/Select): the outlined text field's box -- 48 tall
// with a pointer, 56 on touch, 40 dense, 16 sides (12 dense), `radius-xs`, the 1px
// `outline` (`on-surface` hovered, 2px `primary` open) -- read-only, the value in
// `body-large` `on-surface` and the label in the notch above it, or the label
// resting in `on-surface-variant` before a choice; a trailing 24 chevron (18
// dense) in `on-surface-variant`, pointing up in `primary` while open. The menu is
// `surface-container` with 8 corners and elevation 2, 8 above and below its rows,
// 4 below the field, matching its width; its rows are `menu_row`s.
fn select(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, selected: usize, open: bool, toggle: *const widget.Submit, picks: []const widget.Submit) -> (widget.Node, err) {
    if picks.len != options.len { ret (zero, TooLarge) }
    let chosen = selected < options.len
    var shown = label
    if chosen { shown = options[selected] }
    let dense = t.tokens.metrics.control_height < t.tokens.sizes.control_sm
    let (head, head_error) = field_head(a, key, t, label, shown, chosen, open, toggle, t.tokens.metrics.control_height + 16.0, .ChevronDown, .ChevronUp, !dense)
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
            let (item, item_error) = menu_row(a, key + 2u64 + u64(i), t, options[i], i == selected, &picks[i])
            if item_error != ok { ret (zero, item_error) }
            var entry: widget.Semantics = zero
            entry.role = accessibility.ROLE_OPTION
            entry.label = options[i]
            if i == selected { entry.states = accessibility.STATE_SELECTED }
            let (wrapped, wrapped_error) = mem.alloc[widget.Node](a, 1usize)
            if wrapped_error != ok { ret (zero, TooLarge) }
            wrapped[0usize] = item
            var stretched = style.defaults()
            stretched.width = style.Length { Percent: 100.0 }
            items[i] = widget.semantics(0u64, entry, stretched, wrapped[0usize..1usize])
            i += 1usize
        }
        var sheet = surface_options(t)
        sheet.background = .SurfaceContainer
        sheet.elevation = 2u8
        sheet.radius = t.tokens.radii.sm
        sheet.padding = 0.0
        var sheet_style = surface_style(t, sheet)
        sheet_style.padding.top = style.Length { Px: 8.0 }
        sheet_style.padding.bottom = style.Length { Px: 8.0 }
        sheet_style.min_width = style.Length { Px: 112.0 }
        let (menu, menu_error) = mem.alloc[widget.Node](a, 1usize)
        if menu_error != ok { ret (zero, TooLarge) }
        menu[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, sheet_style, items[0usize..options.len])
        var menu_sem: widget.Semantics = zero
        menu_sem.role = accessibility.ROLE_LISTBOX
        menu_sem.label = label
        let (popup, popup_error) = mem.alloc[widget.Node](a, 1usize)
        if popup_error != ok { ret (zero, TooLarge) }
        popup[0usize] = widget.semantics(0u64, menu_sem, style.defaults(), menu[0usize..1usize])
        parts[1usize] = widget.overlay(key + 1u64, widget.Overlay { anchor: key, placement: .BelowMatch, offset: geometry.Point { x: 0.0, y: 4.0 }, modal: true, dismiss: *toggle }, style.defaults(), popup[0usize..1usize])
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = accessibility.ROLE_COMBOBOX
    sem.label = label
    sem.value = shown
    if open { sem.states = accessibility.STATE_EXPANDED }
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A menu's option row (D956, docs/ux/components/Select): `body-medium` in
// `on-surface`, 36 tall with a pointer and 48 on touch, 12 each side under the
// state layer of its label colour; the chosen one `secondary-container`, its
// label in `on-secondary-container` after a 24 check (18 dense), the others
// indented by the check and its 12 so the labels align.
fn menu_row(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, chosen: bool, action: *const widget.Submit) -> (widget.Node, err) {
    let state = control_state(t, key, true, false)
    var fill = paint.rgba(0.0, 0.0, 0.0, 0.0)
    var words = style.color(t.tokens, .OnSurface)
    if chosen {
        fill = style.color(t.tokens, .SecondaryContainer)
        words = style.color(t.tokens, .OnSecondaryContainer)
    }
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = style.layer(fill, words, state_opacity(t, state))
    look.foreground = words
    look.radius = 0.0
    var h: f32 = 36.0
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { h = t.tokens.sizes.control_lg }
    var mark: f32 = 24.0
    if t.tokens.metrics.control_height < t.tokens.sizes.control_sm {
        h = t.tokens.sizes.control_sm
        mark = t.tokens.sizes.icon_sm
    }
    look.custom_padding = true
    look.padding = 12.0
    look.padding_start = 24.0 + mark
    look.padding_y = max_zero((h - style.text_style(t.tokens, .BodyMedium).line_height) * 0.5)
    look.min_height = h
    var caption = text_options()
    caption.role = .BodyMedium
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, words)
    if label_error != ok { ret (zero, label_error) }
    var content = label_node
    if chosen {
        let (check, check_error) = mark_glyph(a, words, .Check, mark)
        if check_error != ok { ret (zero, check_error) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
        if parts_error != ok { ret (zero, TooLarge) }
        parts[0usize] = check
        parts[1usize] = label_node
        look.padding_start = 12.0
        look.padding_y = max_zero((h - mark) * 0.5)
        content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, style.defaults(), parts[0usize..2usize])
    }
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, true, false, action, content)
    ret (node, node_error)
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
    let (made, made_error) = listed(a, key, t, label, options, chosen, picks, rows, width, false, true)
    ret (made, made_error)
}

// The rows of a list box or a multi-select list: `chosen` says which are selected.
// v2 (D956, docs/ux/components/ListBox, MultiSelectList): the viewport is
// `surface-container-lowest` in a 1px `outline-variant` edge with 8 corners (12
// for a multi-select list), 4 above and below its rows; a row is 40 tall with a
// pointer (48 on touch, a multi-select row 56; 32 dense), 16 each side (12
// dense), its `body-large` label (`body-medium` dense) in `on-surface` under the
// state layer of its label colour; a selected row is `secondary-container` with
// its label in `on-secondary-container`, a list box's with a trailing check (18,
// 24 on touch), a multi-select list's rows leading with a checkbox in its 40
// circle, 4 from the edge.
// Unframed (D958), it is the rows alone on the container, for a frame around more.
fn listed(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, chosen: []const bool, picks: []const widget.Submit, rows: u32, width: f32, multi: bool, framed: bool) -> (widget.Node, err) {
    if picks.len != options.len || chosen.len != options.len { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[widget.Node](a, options.len)
    if items_error != ok { ret (zero, TooLarge) }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    let dense = t.tokens.metrics.control_height < t.tokens.sizes.control_sm
    var row_height = t.tokens.sizes.control_md
    var check_size = t.tokens.sizes.icon_sm
    if touch {
        row_height = t.tokens.sizes.control_lg
        if multi { row_height = t.tokens.sizes.control_xl }
        check_size = t.tokens.sizes.icon_md
    }
    var pad_x: f32 = 16.0
    var role: style.TextRole = .BodyLarge
    if dense {
        row_height = t.tokens.sizes.control_sm
        pad_x = 12.0
        role = .BodyMedium
    }
    let row_width = max_zero(width - 2.0)
    var i = 0usize
    while i < options.len {
        let row_key = key + 1u64 + u64(i)
        let state = control_state(t, row_key, true, false)
        var fill = paint.rgba(0.0, 0.0, 0.0, 0.0)
        var words = style.color(t.tokens, .OnSurface)
        if chosen[i] {
            fill = style.color(t.tokens, .SecondaryContainer)
            words = style.color(t.tokens, .OnSecondaryContainer)
        }
        var row_style = style.defaults()
        row_style.width = style.Length { Px: row_width }
        row_style.height = style.Length { Px: row_height }
        row_style.background = paint.Brush { Solid: style.layer(fill, words, state_opacity(t, state)) }
        var caption = text_options()
        caption.role = role
        caption.wrap = .None
        let (text_item, text_error) = colored_text(a, 0u64, options[i], t, caption, words)
        if text_error != ok { ret (zero, text_error) }
        let (bits, bits_error) = mem.alloc[widget.Node](a, 3usize)
        if bits_error != ok { ret (zero, TooLarge) }
        var used = 1usize
        var lead = pad_x
        var gap: f32 = 0.0
        bits[0usize] = text_item
        if multi {
            let (mark_node, mark_error) = choice_mark(a, t, state, chosen[i], false, false, true)
            if mark_error != ok { ret (zero, mark_error) }
            bits[0usize] = mark_node
            bits[1usize] = text_item
            used = 2usize
            lead = 4.0
            gap = 8.0
        } else {
            if chosen[i] {
                let (check, check_error) = mark_glyph(a, words, .Check, check_size)
                if check_error != ok { ret (zero, check_error) }
                bits[1usize] = widget.spacer(0u64, 1.0)
                bits[2usize] = check
                used = 3usize
            }
        }
        var line_style = style.defaults()
        line_style.width = style.Length { Px: row_width }
        line_style.height = style.Length { Px: row_height }
        line_style.padding = style.EdgeLengths { left: style.Length { Px: lead }, top: style.Length { Px: 0.0 }, right: style.Length { Px: pad_x }, bottom: style.Length { Px: 0.0 } }
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: gap }, line_style, bits[0usize..used])
        let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
        if region_error != ok { ret (zero, TooLarge) }
        region[0usize] = widget.region(row_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[i]), invoke: press_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, row_style, body[0usize..1usize])
        var entry: widget.Semantics = zero
        entry.role = accessibility.ROLE_OPTION
        entry.label = options[i]
        entry.row = u32(i + 1usize)
        entry.row_count = u32(options.len)
        if chosen[i] { entry.states = accessibility.STATE_SELECTED }
        items[i] = widget.semantics(0u64, entry, style.defaults(), region[0usize..1usize])
        i += 1usize
    }
    var view_style = style.defaults()
    view_style.width = style.Length { Px: width }
    view_style.height = style.Length { Px: f32(rows) * row_height + 8.0 }
    view_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLowest) }
    view_style.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .OutlineVariant) }
    view_style.radius = t.tokens.radii.sm
    if multi { view_style.radius = t.tokens.radii.md }
    let one = style.Length { Px: 1.0 }
    let four = style.Length { Px: 4.0 }
    view_style.padding = style.EdgeLengths { left: one, top: four, right: one, bottom: four }
    if !framed {
        view_style.width = style.Length { Px: row_width }
        view_style.border = style.Border { width: 0.0, color: paint.rgba(0.0, 0.0, 0.0, 0.0) }
        view_style.radius = 0.0
        view_style.padding = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: four, right: style.Length { Px: 0.0 }, bottom: four }
        // An unframed single-choice list (D961, the font panel's) stands on its caller's surface.
        if !multi { view_style.background = paint.Brush { Solid: paint.rgba(0.0, 0.0, 0.0, 0.0) } }
    }
    view_style.overflow = .Clip
    let (view, view_error) = widget.scroll_view(a, key, .Vertical, view_style, items[0usize..options.len])
    if view_error != ok { ret (zero, TooLarge) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = view
    // The viewport is the list in the tree; the group above it carries the label.
    var sem: widget.Semantics = zero
    sem.role = accessibility.ROLE_LISTBOX
    sem.label = label
    sem.row_count = u32(options.len)
    ret (widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize]), ok)
}

// ---------------------------------------------------------------- forms (D825, P1-12)

// Validation is data: how a field stands and what to tell the person.
type Validity = enum u8 { Valid, Warning, Invalid }
type Message = struct { validity: Validity, text: str }

// A field's label: v2 (D951, docs/ux/components/FieldLabel) `title-small` in
// `on-surface`, a required one's `*` in `error` 4 after it; controlling the field it
// is for (by key).
fn field_label(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, for_key: widget.Key, required: bool) -> (widget.Node, err) {
    var caption = text_options()
    caption.role = .TitleSmall
    caption.color = .OnSurface
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
// v2 (D951, docs/ux/components/FieldMessage): `body-small`; help and warnings in
// `on-surface-variant`, an error in `error`.
fn field_message(a: *mem.Arena, key: widget.Key, t: *const Theme, message: Message, for_key: widget.Key) -> (widget.Node, err) {
    var caption = text_options()
    caption.role = .BodySmall
    caption.color = .OnSurfaceVariant
    if message.validity == .Invalid { caption.color = .Error }
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
    // v2 (D951, docs/ux/components/FormField): 6 from the label to the control, 4
    // from the control to its message.
    var placed = control_node
    placed.style.margin.top = style.Length { Px: 6.0 }
    placed.style.margin.bottom = style.Length { Px: 4.0 }
    parts[1usize] = placed
    var shown = message
    if shown.text.len == 0usize { shown = Message { validity: .Valid, text: help } }
    let (message_node, message_error) = field_message(a, key + 2u64, t, shown, control_key)
    if message_error != ok { ret (zero, message_error) }
    parts[2usize] = message_node
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..3usize])
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
    // v2 (D951, docs/ux/components/Form): 20 between fields with a pointer, 16 on
    // touch; two columns from the expanded width with a 24 gutter.
    var between: f32 = 20.0
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { between = 16.0 }
    if style.size_class(width) == .Expanded {
        body[0usize] = widget.wrap(0u64, ui_layout.Wrap { axis: .Horizontal, main_gap: 24.0, cross_gap: between }, layout_style, fields)
    } else {
        body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: between }, layout_style, fields)
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

// An entry of a validation summary: its text in `on-error-container`, underlined,
// a tap region with the link role firing `action`.
fn summary_link(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, action: *const widget.Submit) -> (widget.Node, err) {
    var caption = text_options()
    caption.role = .BodyMedium
    caption.color = .OnErrorContainer
    caption.wrap = .None
    let (label_node, label_error) = text_node(a, 0u64, label, t, caption)
    if label_error != ok { ret (zero, label_error) }
    let (lines, lines_error) = mem.alloc[widget.Node](a, 2usize)
    if lines_error != ok { ret (zero, TooLarge) }
    lines[0usize] = label_node
    var under = style.defaults()
    under.width = style.Length { Percent: 100.0 }
    under.height = style.Length { Px: t.tokens.sizes.divider }
    under.background = paint.Brush { Solid: style.color(t.tokens, .OnErrorContainer) }
    under.margin.top = style.Length { Px: 2.0 }
    lines[1usize] = widget.box(0u64, under, zero)
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), lines[0usize..2usize])
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    var target_style = style.defaults()
    target_style.radius = t.tokens.radii.xs
    inner[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](action), invoke: press_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, target_style, body[0usize..1usize])
    focus_look(t)
    var sem: widget.Semantics = zero
    sem.role = ROLE_LINK
    sem.label = label
    sem.actions = accessibility.ACTION_PRESS
    ret (widget.semantics(0u64, sem, style.defaults(), inner[0usize..1usize]), ok)
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
            let (item, item_error) = summary_link(a, key + 1u64 + u64(i), t, messages[i].text, &jumps[i])
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
    // v2 (D951, docs/ux/components/ValidationSummary): the error container, 12
    // corners, 16 in, entries 4 apart.
    var options = surface_options(t)
    options.background = .ErrorContainer
    options.radius = t.tokens.radii.md
    options.padding = t.tokens.spacing.lg
    var sheet = surface_style(t, options)
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

// A disclosure: the header button firing `toggle` (the caller keeps `expanded`)
// over the content only while expanded; the header says expanded or not in the
// tree, offers the other, and controls the content, a group keyed `key + 1`.
fn disclosure(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, expanded: bool, toggle: *const widget.Submit, content: widget.Node) -> (widget.Node, err) {
    let (made, made_error) = disclosure_of(a, key, t, label, expanded, toggle, disclosure_options(), content)
    ret (made, made_error)
}

// A disclosure's or an expander's extras (D965): the meta after a disclosure's
// label (a count or summary), the supporting line under an expander's title,
// whether it is enabled, and an expander's width (0: its header's).
// (D1221) `has_icon` puts `icon` at the start of an expander's header.
type DisclosureOptions = struct { meta: str, supporting: str, enabled: bool, width: f32, has_icon: bool, icon: GlyphKind }

fn disclosure_options() -> DisclosureOptions {
    var out: DisclosureOptions = zero
    out.enabled = true
    ret out
}

// The reading-direction forward arrow opens a shut header and the back arrow
// shuts an open one, around `header` (D1160).
fn toggle_keys(a: *mem.Arena, expanded: bool, rtl: bool, toggle: *const widget.Submit, header: widget.Node) -> (widget.Node, err) {
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 1usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    var arrow = 39u32
    if expanded { arrow = 37u32 }
    if rtl {
        arrow = 37u32
        if expanded { arrow = 39u32 }
    }
    shortcuts[0usize] = widget.Shortcut { key: arrow, modifiers: zero, action: *toggle }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    inner[0usize] = header
    ret (widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..1usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), inner[0usize..1usize]), ok)
}

// v2 (D965, docs/ux/components/Disclosure): the header is a `radius-sm` button
// 40 tall (32 dense), 8 at the start and 12 at the end, under the `on-surface`
// state layer: a `chevron-right` `icon-md` 24 in `on-surface-variant`
// (`chevron-down` while open), 8 to the label in `title-small` `on-surface` and
// the meta after it in `body-medium` `on-surface-variant`. The content stands
// 4 below, indented 40, 8 above what follows. Right opens and Left closes a
// focused header. Disabled, the header's content is `on-surface` 38%, no layer,
// not focusable.
// ponytail: the chevron swaps rather than turning and the content does not
// animate; add the motion with the animation module's tweens.
fn disclosure_of(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, expanded: bool, toggle: *const widget.Submit, options: DisclosureOptions, content: widget.Node) -> (widget.Node, err) {
    let state = control_state(t, key, options.enabled, false)
    var h: f32 = t.tokens.sizes.control_md
    if t.tokens.metrics.control_height < t.tokens.sizes.control_sm { h = t.tokens.sizes.control_sm }
    var fade: f32 = 1.0
    if !options.enabled { fade = t.tokens.states.disabled_content }
    let on = with_alpha(style.color(t.tokens, .OnSurface), fade)
    var muted = style.color(t.tokens, .OnSurfaceVariant)
    if !options.enabled { muted = on }
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), style.color(t.tokens, .OnSurface), state_opacity(t, state))
    look.foreground = on
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = t.tokens.radii.sm
    look.custom_padding = true
    look.padding = 12.0
    look.padding_start = 8.0
    look.padding_y = max_zero((h - t.tokens.sizes.icon_md) * 0.5)
    look.min_height = h
    look.min_width = h
    var kind: GlyphKind = .ChevronRight
    if t.tokens.direction == .RightToLeft { kind = .ChevronLeft }
    if expanded { kind = .ChevronDown }
    let (head, head_error) = mem.alloc[widget.Node](a, 3usize)
    if head_error != ok { ret (zero, TooLarge) }
    let (chevron, chevron_error) = icon_square(a, muted, kind, t.tokens.sizes.icon_md)
    if chevron_error != ok { ret (zero, chevron_error) }
    head[0usize] = chevron
    var caption = text_options()
    caption.role = .TitleSmall
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, on)
    if label_error != ok { ret (zero, label_error) }
    head[1usize] = label_node
    var head_count = 2usize
    if options.meta.len != 0usize {
        var said = text_options()
        said.role = .BodyMedium
        said.wrap = .None
        let (meta_node, meta_error) = colored_text(a, 0u64, options.meta, t, said, muted)
        if meta_error != ok { ret (zero, meta_error) }
        head[2usize] = meta_node
        head_count = 3usize
    }
    let header = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.sm }, style.defaults(), head[0usize..head_count])
    var states = 0u32
    var actions = accessibility.ACTION_EXPAND
    if expanded {
        states = accessibility.STATE_EXPANDED
        actions = accessibility.ACTION_COLLAPSE
    }
    let (button_node, button_error) = pressable_states(a, key, t, 3u8, label, look, options.enabled, false, states, actions, key + 1u64, toggle, header)
    if button_error != ok { ret (zero, button_error) }
    let (keyed, keyed_error) = toggle_keys(a, expanded, t.tokens.direction == .RightToLeft, toggle, button_node)
    if keyed_error != ok { ret (zero, keyed_error) }
    var count = 1usize
    if expanded { count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = keyed
    if expanded {
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = content
        var sem: widget.Semantics = zero
        sem.role = 2u8
        sem.labelled_by = key
        var padded = style.defaults()
        padded.padding = style.EdgeLengths { left: style.Length { Px: 40.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 8.0 } }
        parts[1usize] = widget.semantics(key + 1u64, sem, padded, body[0usize..1usize])
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..count]), ok)
}

// An expander: the outlined section of D965 below.
fn expander(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, expanded: bool, toggle: *const widget.Submit, content: widget.Node) -> (widget.Node, err) {
    let (made, made_error) = expander_of(a, key, t, label, expanded, toggle, disclosure_options(), content)
    ret (made, made_error)
}

// A section's header row (D965), an expander's or an accordion's: a square
// button `width` wide (0: its content's), `h` tall (plus 16 with a supporting
// line), 16 each side and 8 above and below, under the `on-surface` state layer:
// the title in `title` role `on-surface`, the supporting line under it in
// `line` role `on-surface-variant`, and a trailing `chevron-down` 24 in
// `on-surface-variant` (`chevron-up` open) 16 after them; it controls `key + 1`.
fn section_header(a: *mem.Arena, key: widget.Key, t: *const Theme, title: str, supporting: str, expanded: bool, enabled: bool, toggle: *const widget.Submit, width: f32, h: f32, title_role: style.TextRole, line_role: style.TextRole) -> (widget.Node, err) {
    let (made, made_error) = section_header_icon(a, key, t, title, supporting, expanded, enabled, toggle, width, h, title_role, line_role, false, .ChevronDown)
    ret (made, made_error)
}

// (D1221) The same header with, when `has_icon`, a 24 `leading` glyph in
// `on-surface-variant` 16 before the title.
fn section_header_icon(a: *mem.Arena, key: widget.Key, t: *const Theme, title: str, supporting: str, expanded: bool, enabled: bool, toggle: *const widget.Submit, width: f32, h: f32, title_role: style.TextRole, line_role: style.TextRole, has_icon: bool, leading: GlyphKind) -> (widget.Node, err) {
    let state = control_state(t, key, enabled, false)
    var fade: f32 = 1.0
    if !enabled { fade = t.tokens.states.disabled_content }
    let on = with_alpha(style.color(t.tokens, .OnSurface), fade)
    var muted = style.color(t.tokens, .OnSurfaceVariant)
    if !enabled { muted = on }
    var tall = h
    if supporting.len != 0usize { tall = h + 16.0 }
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), style.color(t.tokens, .OnSurface), state_opacity(t, state))
    look.foreground = on
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = 0.0
    look.custom_padding = true
    look.padding = 16.0
    look.padding_y = 8.0
    look.min_height = tall
    look.min_width = max_of(width, 1.0)
    let (words, words_error) = mem.alloc[widget.Node](a, 2usize)
    if words_error != ok { ret (zero, TooLarge) }
    var caption = text_options()
    caption.role = title_role
    caption.wrap = .None
    let (title_node, title_error) = colored_text(a, 0u64, title, t, caption, on)
    if title_error != ok { ret (zero, title_error) }
    words[0usize] = title_node
    var word_count = 1usize
    if supporting.len != 0usize {
        var said = text_options()
        said.role = line_role
        said.wrap = .None
        let (line_node, line_error) = colored_text(a, 0u64, supporting, t, said, muted)
        if line_error != ok { ret (zero, line_error) }
        words[1usize] = line_node
        word_count = 2usize
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 3usize)
    if row_error != ok { ret (zero, TooLarge) }
    var cells = 0usize
    if has_icon {
        let (lead, lead_error) = icon_square(a, muted, leading, t.tokens.sizes.icon_md)
        if lead_error != ok { ret (zero, lead_error) }
        row[cells] = lead
        cells += 1usize
    }
    var words_style = style.defaults()
    words_style.width = style.Length { Flex: 1.0 }
    row[cells] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Start, gap: 0.0 }, words_style, words[0usize..word_count])
    cells += 1usize
    var kind: GlyphKind = .ChevronDown
    if expanded { kind = .ChevronUp }
    let (chevron, chevron_error) = icon_square(a, muted, kind, t.tokens.sizes.icon_md)
    if chevron_error != ok { ret (zero, chevron_error) }
    row[cells] = chevron
    cells += 1usize
    var row_style = style.defaults()
    if width > 0.0 { row_style.width = style.Length { Px: width - 32.0 } }
    row_style.min_height = style.Length { Px: tall - 16.0 }
    let header = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 16.0 }, row_style, row[0usize..cells])
    var states = 0u32
    var actions = accessibility.ACTION_EXPAND
    if expanded {
        states = accessibility.STATE_EXPANDED
        actions = accessibility.ACTION_COLLAPSE
    }
    let (button_node, button_error) = pressable_states(a, key, t, 3u8, title, look, enabled, false, states, actions, key + 1u64, toggle, header)
    ret (button_node, button_error)
}

// A section's content (D965): 16 at the sides and below, a group keyed `key`
// labelled by its header.
fn section_body(a: *mem.Arena, key: widget.Key, header: widget.Key, content: widget.Node) -> (widget.Node, err) {
    let (made, made_error) = section_body_from(a, key, header, content, 16.0, 16.0)
    ret (made, made_error)
}

// (D1221) The same content `left` and `right` in from the sides.
fn section_body_from(a: *mem.Arena, key: widget.Key, header: widget.Key, content: widget.Node, left: f32, right: f32) -> (widget.Node, err) {
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.labelled_by = header
    var padded = style.defaults()
    let side = style.Length { Px: 16.0 }
    padded.padding = style.EdgeLengths { left: style.Length { Px: left }, top: style.Length { Px: 0.0 }, right: style.Length { Px: right }, bottom: side }
    ret (widget.semantics(key, sem, padded, body[0usize..1usize]), ok)
}

// v2 (D965, docs/ux/components/Disclosure, the expander): a `surface` container
// in a 1px `outline-variant` edge with `radius-md` 12, clipping (so the focus
// ring stands inside it), holding the section header 56 tall (72 with a
// supporting line) with the title in `body-large` and the supporting line in
// `body-medium`, and the content 16 in at the sides and below while open. Right
// opens and Left closes a focused header. (D1221) With `has_icon` the header
// leads with a 24 `on-surface-variant` icon and the open content is 56 in.
// ponytail: no motion.
fn expander_of(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, expanded: bool, toggle: *const widget.Submit, options: DisclosureOptions, content: widget.Node) -> (widget.Node, err) {
    let (header, header_error) = section_header_icon(a, key, t, label, options.supporting, expanded, options.enabled, toggle, options.width, t.tokens.sizes.control_xl, .BodyLarge, .BodyMedium, options.has_icon, options.icon)
    if header_error != ok { ret (zero, header_error) }
    let (keyed, keyed_error) = toggle_keys(a, expanded, t.tokens.direction == .RightToLeft, toggle, header)
    if keyed_error != ok { ret (zero, keyed_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = keyed
    var count = 1usize
    if expanded {
        var left: f32 = 16.0
        var right: f32 = 16.0
        if options.has_icon && t.tokens.direction == .RightToLeft { right = 56.0 } else if options.has_icon { left = 56.0 }
        let (inner, inner_error) = section_body_from(a, key + 1u64, key, content, left, right)
        if inner_error != ok { ret (zero, inner_error) }
        parts[1usize] = inner
        count = 2usize
    }
    var sheet = style.defaults()
    sheet.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    sheet.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .OutlineVariant) }
    sheet.radius = t.tokens.radii.md
    sheet.overflow = .Clip
    if options.width > 0.0 { sheet.width = style.Length { Px: options.width } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, sheet, parts[0usize..count]), ok)
}

// A tab list: a row of tabs keyed `key + 1 + index`, the selected one selected in
// the tree, each firing its own pick; Left and Right on a focused tab pick its
// neighbours, Home and End the ends. The primary scrollable bar below.
fn tabs(a: *mem.Arena, key: widget.Key, t: *const Theme, labels: []const str, selected: usize, picks: []const widget.Submit) -> (widget.Node, err) {
    let (made, made_error) = tabs_of(a, key, t, labels, selected, picks, tabs_options())
    ret (made, made_error)
}

// A tab bar's form (D972): secondary (a 2px line across the tab, the active
// label `on-surface`) rather than primary, and fixed (the tabs share `width`)
// rather than scrollable (each as wide as its label, from the start inset).
// (D1213) `disabled` marks tabs by index (shorter than the tabs: the rest are
// enabled). (D1226) `icons` puts a glyph above each label; `badges` holds a count
// per tab ("" for none) and `badge_names` what each means in the tab's name
// (the count itself when shorter).
type TabsOptions = struct { secondary: bool, fixed: bool, width: f32, disabled: []const bool, icons: []const GlyphKind, badges: []const str, badge_names: []const str }

fn tab_badge(options: *const TabsOptions, i: usize) -> str {
    if i >= options.badges.len { ret "" }
    ret options.badges[i]
}

// (D1226) A tab's face: its label, under a 24 icon 2 above it when the bar has
// icons, with the tab's count badge on the icon's top end corner -- or, with no
// icon, 4 after the label.
fn tab_face(a: *mem.Arena, t: *const Theme, options: *const TabsOptions, i: usize, label_node: widget.Node, ink: paint.Color) -> (widget.Node, err) {
    let value = tab_badge(options, i)
    let has_icon = i < options.icons.len
    if !has_icon && value.len == 0usize { ret (label_node, ok) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    if has_icon {
        let side = t.tokens.sizes.icon_md
        let (glyph, glyph_error) = icon_square(a, ink, options.icons[i], side)
        if glyph_error != ok { ret (zero, glyph_error) }
        parts[0usize] = glyph
        if value.len != 0usize {
            let (mark, mark_error) = badge_of(a, 0u64, t, value, .Urgent)
            if mark_error != ok { ret (zero, mark_error) }
            let (anchored, anchored_error) = badge_anchor(a, 0u64, glyph, side, mark, false)
            if anchored_error != ok { ret (zero, anchored_error) }
            parts[0usize] = anchored
        }
        parts[1usize] = label_node
        ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Center, gap: 2.0 }, style.defaults(), parts[0usize..2usize]), ok)
    }
    let (mark, mark_error) = badge_of(a, 0u64, t, value, .Urgent)
    if mark_error != ok { ret (zero, mark_error) }
    parts[0usize] = label_node
    parts[1usize] = mark
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 4.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

fn tab_enabled(options: *const TabsOptions, i: usize) -> bool {
    ret i >= options.disabled.len || !options.disabled[i]
}

fn tabs_options() -> TabsOptions {
    var out: TabsOptions = zero
    ret out
}

// v2 (D972, docs/ux/components/Tabs): a bar on `surface` over a 1px
// `outline-variant` line. A tab is 40 tall at pointer density (48 touch), 16 at
// its sides, at least 48 wide (90 fixed), its `title-small` label in
// `on-surface-variant` -- the active one `primary` (`on-surface` when secondary)
// -- under the `state-hover`/`state-pressed` layer of the label colour. The
// active indicator is 3px `primary` as wide as the label (at least 24) with 3
// rounded top corners, or 2px across the whole tab when secondary. A scrollable
// bar starts 8 in (16 touch). (D1213) A disabled tab's label is `on-surface` at
// 38%, it is neither pressable nor focusable, and Left, Right, Home and End
// skip it. (D1226) With `icons` a tab is 16 taller (56 pointer, 64 touch) and
// shows its icon 2 above the label; a count badge sits on the icon's top end
// corner, or 4 after the label on a text-only tab, and joins the tab's name.
// ponytail: no overflow button or horizontal scrolling; no dot badge; the
// indicator does not slide between tabs.
fn tabs_of(a: *mem.Arena, key: widget.Key, t: *const Theme, labels: []const str, selected: usize, picks: []const widget.Submit, options: TabsOptions) -> (widget.Node, err) {
    if picks.len != labels.len { ret (zero, TooLarge) }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var h = t.tokens.sizes.control_md
    if touch { h = t.tokens.sizes.control_lg }
    if options.icons.len > 0usize { h += 16.0 }
    let sharing = options.fixed && options.width > 0.0
    var least: f32 = 48.0
    if sharing && labels.len > 0usize { least = max_of(90.0, options.width / f32(labels.len)) }
    let (items, items_error) = mem.alloc[widget.Node](a, labels.len)
    if items_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < labels.len {
        let chosen = i == selected
        let tab_key = key + 1u64 + u64(i)
        let enabled = tab_enabled(&options, i)
        let state = control_state(t, tab_key, enabled, chosen)
        var ink = style.color(t.tokens, .OnSurfaceVariant)
        if chosen && options.secondary { ink = style.color(t.tokens, .OnSurface) }
        if chosen && !options.secondary { ink = style.color(t.tokens, .Primary) }
        if !enabled { ink = with_alpha(style.color(t.tokens, .OnSurface), t.tokens.states.disabled_content) }
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = with_alpha(ink, state_opacity(t, state))
        look.foreground = ink
        look.border_width = 0.0
        look.radius = 0.0
        look.opacity = 1.0
        look.custom_padding = true
        look.padding = 0.0
        look.padding_y = 0.0
        look.min_height = h
        look.min_width = least
        var caption = text_options()
        caption.role = .TitleSmall
        caption.wrap = .None
        caption.align = .Center
        let (label_text, label_error) = colored_text(a, 0u64, labels[i], t, caption, ink)
        if label_error != ok { ret (zero, label_error) }
        let (label_node, face_error) = tab_face(a, t, &options, i, label_text, ink)
        if face_error != ok { ret (zero, face_error) }
        var named = labels[i]
        if tab_badge(&options, i).len != 0usize {
            var meaning = tab_badge(&options, i)
            if i < options.badge_names.len && options.badge_names[i].len != 0usize { meaning = options.badge_names[i] }
            let (with_badge, with_badge_error) = badge_name(a, labels[i], meaning)
            if with_badge_error != ok { ret (zero, with_badge_error) }
            named = with_badge
        }
        var mark = style.defaults()
        if chosen { mark.background = paint.Brush { Solid: style.color(t.tokens, .Primary) } }
        let sides = style.Length { Px: 16.0 }
        let flat = style.Length { Px: 0.0 }
        var content = label_node
        if options.secondary {
            mark.height = style.Length { Px: 2.0 }
            let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
            if inner_error != ok { ret (zero, TooLarge) }
            inner[0usize] = label_node
            var inner_style = style.defaults()
            inner_style.height = style.Length { Flex: 1.0 }
            inner_style.padding = style.EdgeLengths { left: sides, top: flat, right: sides, bottom: flat }
            let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
            if parts_error != ok { ret (zero, TooLarge) }
            parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Center, gap: 0.0 }, inner_style, inner[0usize..1usize])
            parts[1usize] = widget.box(0u64, mark, zero)
            var column_style = style.defaults()
            column_style.height = style.Length { Px: h }
            column_style.min_width = style.Length { Px: least }
            content = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, column_style, parts[0usize..2usize])
        } else {
            mark.height = style.Length { Px: 3.0 }
            mark.min_width = style.Length { Px: 24.0 }
            mark.corners = style.Corners { top_left: 3.0, top_right: 3.0, bottom_right: 0.0, bottom_left: 0.0 }
            let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
            if parts_error != ok { ret (zero, TooLarge) }
            parts[0usize] = widget.spacer(0u64, 1.0)
            parts[1usize] = label_node
            parts[2usize] = widget.spacer(0u64, 1.0)
            parts[3usize] = widget.box(0u64, mark, zero)
            var column_style = style.defaults()
            column_style.height = style.Length { Px: h }
            column_style.padding = style.EdgeLengths { left: sides, top: flat, right: sides, bottom: flat }
            content = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, column_style, parts[0usize..4usize])
        }
        if !enabled { look.background = with_alpha(ink, 0.0) }
        let (tab, tab_error) = pressable_states(a, tab_key, t, 19u8, named, look, enabled, chosen, 0u32, 0u32, 0u64, &picks[i], content)
        if tab_error != ok { ret (zero, tab_error) }
        items[i] = tab
        i += 1usize
    }
    var strip = style.defaults()
    if !sharing {
        var inset: f32 = 8.0
        if touch { inset = 16.0 }
        let none = style.Length { Px: 0.0 }
        strip.padding = style.EdgeLengths { left: style.Length { Px: inset }, top: none, right: none, bottom: none }
    }
    if sharing { strip.width = style.Length { Px: options.width } }
    let (bar_parts, bar_parts_error) = mem.alloc[widget.Node](a, 2usize)
    if bar_parts_error != ok { ret (zero, TooLarge) }
    bar_parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .End, gap: 0.0 }, strip, items[0usize..labels.len])
    var line = style.defaults()
    line.height = style.Length { Px: t.tokens.sizes.divider }
    line.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
    bar_parts[1usize] = widget.box(0u64, line, zero)
    var bar = style.defaults()
    bar.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    if options.width > 0.0 { bar.width = style.Length { Px: options.width } }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, bar, bar_parts[0usize..2usize])
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 4usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    var back = 37u32
    var forward = 39u32
    if t.tokens.direction == .RightToLeft {
        back = 39u32
        forward = 37u32
    }
    // The enabled neighbours and ends of the selected tab (D1213).
    var before = labels.len
    var first = labels.len
    var after = labels.len
    var last = labels.len
    var k = 0usize
    while k < labels.len {
        if tab_enabled(&options, k) {
            if k < selected {
                before = k
                if first == labels.len { first = k }
            }
            if k > selected {
                if after == labels.len { after = k }
                last = k
            }
        }
        k += 1usize
    }
    var bound = 0usize
    if before < labels.len && selected < labels.len {
        shortcuts[bound] = widget.Shortcut { key: back, modifiers: zero, action: picks[before] }
        shortcuts[bound + 1usize] = widget.Shortcut { key: 36u32, modifiers: zero, action: picks[first] }
        bound += 2usize
    }
    if after < labels.len {
        shortcuts[bound] = widget.Shortcut { key: forward, modifiers: zero, action: picks[after] }
        shortcuts[bound + 1usize] = widget.Shortcut { key: 35u32, modifiers: zero, action: picks[last] }
        bound += 2usize
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
    // v2 (D972): the page stands directly below the bar.
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

// A pane handle's state for the frame: where the pane is, its limits, and whom to
// tell. A drag reports the pointer's distance from the pane's origin, the pointer
// taken as the handle's middle; a nudge
// reports the size moved by a step; both are clamped to `low..high`, and with no
// `high` to the extent of the element `bound` names less `reserve` (no bound: no
// upper limit).
// (D1212) The sash keeps, across frames, the size it was first built at (what a
// double-click restores) and the size a drag began at, whether a drag is under
// way, and whether Escape cancelled it (its later moves are ignored).
type Handle = struct { runtime: *widget.Runtime, pane: widget.Key, bound: widget.Key, vertical: bool, size: f32, thick: f32, low: f32, high: f32, reserve: f32, change: widget.Change[f32], cell: *SashCell, has_cell: bool }
type Nudge = struct { handle: *Handle, amount: f32 }
type SashCell = struct { initial: f32, start: f32, dragging: bool, cancelled: bool }

fn sash_cell(runtime: *widget.Runtime, key: widget.Key, size: f32) -> (*SashCell, bool) {
    var none: *SashCell = zero
    if mem.address_of(runtime) == 0usize { ret (none, false) }
    let (s, state_error) = widget.state_of(runtime)
    if state_error != ok { ret (none, false) }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret (none, false) }
    var build = widget.BuildContext { runtime: runtime, element: id, frame: 0u64 }
    let (kept, _, kept_error) = widget.state[SashCell](&build, key, SashCell { initial: size, start: size, dragging: false, cancelled: false })
    if kept_error != ok { ret (none, false) }
    ret (kept, true)
}

// (D1212) Escape during a drag: back to the size the drag began at.
fn handle_cancel(ctx: *void) -> err {
    let h = mem.cast[*Handle](ctx)
    if !h.has_cell || !h.cell.dragging { ret ok }
    h.cell.cancelled = true
    ret handle_report(h, h.cell.start)
}

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
    case .DragStart as p:
        if h.has_cell {
            h.cell.start = h.size
            h.cell.dragging = true
            h.cell.cancelled = false
        }
        ret ok
    case .DragEnd as p:
        if h.has_cell {
            h.cell.dragging = false
            h.cell.cancelled = false
        }
        ret ok
    case .DoubleTap as p:
        if h.has_cell { ret handle_report(h, h.cell.initial) }
        ret ok
    case .DragMove as d:
        if h.has_cell && h.cell.cancelled { ret ok }
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
// size and hears each change), the sash of D966 after it, between `low` and
// `high` (0: no limit). The pane is keyed `key + 1`, the sash `key + 2`, a
// separator in the tree named "Resize " and `label`, its value the size in px.
fn resizable_pane(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, axis: ui_layout.Axis, size: f32, low: f32, high: f32, change: widget.Change[f32], content: widget.Node) -> (widget.Node, err) {
    let (named, named_error) = mem.alloc[u8](a, label.len + 7usize)
    if named_error != ok { ret (zero, TooLarge) }
    var n = copy_text(named, "Resize ")
    n += copy_text(named[n..named.len], label)
    let (made, made_error) = pane_with_reserve(a, key, t, named[0usize..n], axis, size, low, high, 0u64, 0.0, change, content, false)
    ret (made, made_error)
}

// A sash's paint (D966): the line across the sash's middle (on whole pixels),
// `line_width` thick, and a 4 x 48 fully rounded grip on it (none while `grip`
// is clear), or, as a dock layout's, a 4px bar in place of the line.
type Sash = struct { line: paint.Color, line_width: f32, grip: paint.Color, across: bool, arena: *mem.Arena }

fn sash_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let s = mem.cast[*Sash](ctx)
    // `across`: the sash lies along x (a bottom panel's), else along y.
    if s.across {
        try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(area.x, area.y + f32(i64((area.height - s.line_width) * 0.5)), area.width, s.line_width), brush: paint.Brush { Solid: s.line } } })
    } else {
        try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(area.x + f32(i64((area.width - s.line_width) * 0.5)), area.y, s.line_width, area.height), brush: paint.Brush { Solid: s.line } } })
    }
    if !(s.grip.alpha > 0.0) { ret ok }
    let cx = area.x + area.width * 0.5
    let cy = area.y + area.height * 0.5
    let (pb, pb_error) = geometry.path_builder(s.arena, 32usize, 64usize)
    if pb_error != ok { ret TooLarge }
    var builder = pb
    if s.across {
        try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(cx - 22.0, cy - 2.0, 44.0, 4.0), brush: paint.Brush { Solid: s.grip } } })
        try oval(&builder, cx - 22.0, cy, 2.0, 2.0)
        try oval(&builder, cx + 22.0, cy, 2.0, 2.0)
    } else {
        try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(cx - 2.0, cy - 22.0, 4.0, 44.0), brush: paint.Brush { Solid: s.grip } } })
        try oval(&builder, cx, cy - 22.0, 2.0, 2.0)
        try oval(&builder, cx, cy + 22.0, 2.0, 2.0)
    }
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&builder), brush: paint.Brush { Solid: s.grip } } })
}

// v2 (D966, docs/ux/components/ResizablePane): the sash is an 8 hit strip (24 on
// touch) on the pane's inner edge, transparent, with a centred 1px
// `outline-variant` line; a 4 x 48 fully rounded grip on it shows `outline` on
// hover and keyboard focus (always, `on-surface-variant`, on touch) and, dragged,
// the line is 2px `primary` and the grip `primary`. As a dock layout's (`bar`),
// hover and drag draw a 4px `primary` bar and no grip. Arrows move it 8, 48 with
// Shift; Home and End go to the limits. A separator in the tree named `label`, its
// value the size ("240 px"), controlling the pane. (D1212) A double-click restores
// the size the pane was first built at, and Escape during a drag restores the
// size the drag began at and ignores the rest of that drag.
// ponytail: no snap-to-close, size readout or resize cursor; the default size is
// the first built one, not a separate caller value.
fn pane_with_reserve(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, axis: ui_layout.Axis, size: f32, low: f32, high: f32, bound: widget.Key, reserve: f32, change: widget.Change[f32], content: widget.Node, bar: bool) -> (widget.Node, err) {
    let vertical = axis == .Vertical
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var hit: f32 = 8.0
    if touch { hit = 24.0 }
    let (handles, handles_error) = mem.alloc[Handle](a, 1usize)
    if handles_error != ok { ret (zero, TooLarge) }
    let (kept, has_kept) = sash_cell(t.runtime, key + 2u64, size)
    handles[0usize] = Handle { runtime: t.runtime, pane: key, bound: bound, vertical: vertical, size: size, thick: hit, low: low, high: high, reserve: reserve, change: change, cell: kept, has_cell: has_kept }
    let (nudges, nudges_error) = mem.alloc[Nudge](a, 6usize)
    if nudges_error != ok { ret (zero, TooLarge) }
    nudges[0usize] = Nudge { handle: &handles[0usize], amount: -8.0 }
    nudges[1usize] = Nudge { handle: &handles[0usize], amount: 8.0 }
    nudges[2usize] = Nudge { handle: &handles[0usize], amount: -48.0 }
    nudges[3usize] = Nudge { handle: &handles[0usize], amount: 48.0 }
    nudges[4usize] = Nudge { handle: &handles[0usize], amount: -1.0e9 }
    nudges[5usize] = Nudge { handle: &handles[0usize], amount: 1.0e9 }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var pane_style = style.defaults()
    pane_style.overflow = .Clip
    var grip = style.defaults()
    let full = style.Length { Percent: 100.0 }
    if vertical {
        pane_style.height = style.Length { Px: size }
        pane_style.width = full
        grip.height = style.Length { Px: hit }
        grip.width = full
    } else {
        pane_style.width = style.Length { Px: size }
        pane_style.height = full
        grip.width = style.Length { Px: hit }
        grip.height = full
    }
    parts[0usize] = widget.box(key + 1u64, pane_style, body[0usize..1usize])
    // The sash's look in its state.
    let state = control_state(t, key + 2u64, true, false)
    var sashes_line = style.color(t.tokens, .OutlineVariant)
    var line_width: f32 = 1.0
    var grip_color = paint.rgba(0.0, 0.0, 0.0, 0.0)
    if touch { grip_color = style.color(t.tokens, .OnSurfaceVariant) }
    if state.hovered || state.focus_visible { grip_color = style.color(t.tokens, .Outline) }
    if state.pressed {
        sashes_line = style.color(t.tokens, .Primary)
        line_width = 2.0
        grip_color = sashes_line
    }
    if bar {
        grip_color = paint.rgba(0.0, 0.0, 0.0, 0.0)
        if state.hovered || state.pressed {
            sashes_line = style.color(t.tokens, .Primary)
            line_width = 4.0
        }
    }
    let (sashes, sashes_error) = mem.alloc[Sash](a, 1usize)
    if sashes_error != ok { ret (zero, TooLarge) }
    sashes[0usize] = Sash { line: sashes_line, line_width: line_width, grip: grip_color, across: vertical, arena: a }
    var paint_style = style.defaults()
    paint_style.width = full
    paint_style.height = full
    var none: []const widget.Node = zero
    let (drawn, drawn_error) = mem.alloc[widget.Node](a, 1usize)
    if drawn_error != ok { ret (zero, TooLarge) }
    drawn[0usize] = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&sashes[0usize]), measure: mark_measure, paint: sash_paint, state: widget.bytes_of[Sash](&sashes[0usize]) } }, style: paint_style, children: none }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 7usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    var less = 37u32
    var more = 39u32
    if vertical {
        less = 38u32
        more = 40u32
    }
    var shifted: input.Modifiers = zero
    shifted.shift = true
    shortcuts[0usize] = widget.Shortcut { key: less, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&nudges[0usize]), invoke: handle_nudge } }
    shortcuts[1usize] = widget.Shortcut { key: more, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&nudges[1usize]), invoke: handle_nudge } }
    shortcuts[2usize] = widget.Shortcut { key: less, modifiers: shifted, action: widget.Submit { ctx: mem.cast[*void](&nudges[2usize]), invoke: handle_nudge } }
    shortcuts[3usize] = widget.Shortcut { key: more, modifiers: shifted, action: widget.Submit { ctx: mem.cast[*void](&nudges[3usize]), invoke: handle_nudge } }
    shortcuts[4usize] = widget.Shortcut { key: 36u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&nudges[4usize]), invoke: handle_nudge } }
    var bound_keys = 5usize
    // End only where the pane has an upper limit.
    if high > 0.0 || bound != 0u64 {
        shortcuts[5usize] = widget.Shortcut { key: 35u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&nudges[5usize]), invoke: handle_nudge } }
        bound_keys = 6usize
    }
    if has_kept && kept.dragging && !kept.cancelled {
        shortcuts[bound_keys] = widget.Shortcut { key: 27u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&handles[0usize]), invoke: handle_cancel } }
        bound_keys += 1usize
    }
    let (grip_node, grip_error) = mem.alloc[widget.Node](a, 1usize)
    if grip_error != ok { ret (zero, TooLarge) }
    grip_node[0usize] = widget.region(key + 2u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&handles[0usize]), invoke: handle_drag }, gestures: 1u8 | 2u8 | 4u8, enabled: true, focusable: true }, grip, drawn[0usize..1usize])
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..bound_keys], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), grip_node[0usize..1usize])
    let (said, said_error) = mem.alloc[u8](a, 24usize)
    if said_error != ok { ret (zero, TooLarge) }
    var said_len = write_i64(said, i64(size))
    said_len += copy_text(said[said_len..24usize], " px")
    var sem: widget.Semantics = zero
    sem.role = accessibility.ROLE_SEPARATOR
    sem.label = label
    sem.value = said[0usize..said_len]
    sem.actions = accessibility.ACTION_INCREMENT | accessibility.ACTION_DECREMENT
    sem.controls = key + 1u64
    parts[1usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    ret (widget.flex(key, ui_layout.Flex { axis: axis, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

// A split view: the named split of D966 below with its sash named "Divider".
fn split_view(a: *mem.Arena, key: widget.Key, t: *const Theme, axis: ui_layout.Axis, first: widget.Node, second: widget.Node, position: f32, min_first: f32, min_second: f32, change: widget.Change[f32], width: f32, height: f32) -> (widget.Node, err) {
    let (made, made_error) = split_view_named(a, key, t, "Divider", axis, first, second, position, min_first, min_second, change, width, height)
    ret (made, made_error)
}

// v2 (D966, docs/ux/components/SplitView): `first` in a resizable pane sized
// `position` along `axis`, D966's sash after it (8 hit, the 1px `outline-variant`
// line, the 4 x 48 grip on hover, focus and drag, 2px `primary` dragged), and
// `second` filling the rest on `surface`; the sash keeps `min_first` and
// `min_second` of each and is a separator named `label` with the first pane's size
// as its value. The pane is keyed `key + 1` (its content `key + 2`, its sash
// `key + 3`); a group in the tree.
// Its sash resets on double-click and cancels a drag on Escape (D1212).
// ponytail: no stacking below the breakpoint, snap points, ratio across window
// resizes, F6 cycling or empty-detail slot; add them with a window-size input.
fn split_view_named(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, axis: ui_layout.Axis, first: widget.Node, second: widget.Node, position: f32, min_first: f32, min_second: f32, change: widget.Change[f32], width: f32, height: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (pane, pane_error) = pane_with_reserve(a, key + 1u64, t, label, axis, position, min_first, 0.0, key, min_second, change, first, false)
    if pane_error != ok { ret (zero, pane_error) }
    parts[0usize] = pane
    let (rest, rest_error) = mem.alloc[widget.Node](a, 1usize)
    if rest_error != ok { ret (zero, TooLarge) }
    rest[0usize] = second
    var rest_style = style.defaults()
    rest_style.overflow = .Clip
    rest_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
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

// A round icon button (D966, docs/ux/components/DockPanel's header actions):
// `side` across (32), the drawn glyph `glyph_size` (18) in `on-surface-variant` under
// its state layer, named `label`.
fn glyph_button(a: *mem.Arena, key: widget.Key, t: *const Theme, kind: GlyphKind, label: str, action: *const widget.Submit, side: f32, glyph_size: f32) -> (widget.Node, err) {
    let (node, node_error) = glyph_toggle(a, key, t, kind, label, action, side, glyph_size, false)
    ret (node, node_error)
}

// The same as a toggle (D968, a dock layout's activity strip): selected, it is
// tonal, `secondary-container` with the glyph in `on-secondary-container`, and
// Selected in the tree.
fn glyph_toggle(a: *mem.Arena, key: widget.Key, t: *const Theme, kind: GlyphKind, label: str, action: *const widget.Submit, side: f32, glyph_size: f32, selected: bool) -> (widget.Node, err) {
    let state = control_state(t, key, true, selected)
    var muted = style.color(t.tokens, .OnSurfaceVariant)
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = with_alpha(muted, state_opacity(t, state))
    if selected {
        muted = style.color(t.tokens, .OnSecondaryContainer)
        look.background = style.layer(style.color(t.tokens, .SecondaryContainer), muted, state_opacity(t, state))
    }
    look.foreground = muted
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = side * 0.5
    look.custom_padding = true
    look.padding = (side - glyph_size) * 0.5
    look.padding_y = (side - glyph_size) * 0.5
    look.min_width = side
    look.min_height = side
    let (mark, mark_error) = icon_square(a, muted, kind, glyph_size)
    if mark_error != ok { ret (zero, mark_error) }
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, true, selected, action, mark)
    ret (node, node_error)
}

// ------------------------------------------------- advanced actions (D829, P2-01)

// A split button: the primary action as a filled button keyed `key`, joined to a
// narrower filled button keyed `key + 1` firing `toggle` for the menu the caller
// places (D827's `overlay.menu`, anchored to `key + 1` and keyed `key + 2`); the
// second says expanded while `open`, offers the menu and controls it.
// v2 (D945, docs/ux/components/SplitButton): two filled halves 2 apart, each round
// at its outer end and `radius-xs` at the inner one; the trailing half is 36 wide at
// pointer density (44 at touch) round an 18px chevron.
fn split_button(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, action: *const widget.Submit, open: bool, toggle: *const widget.Submit) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let h = t.tokens.metrics.control_height
    let outer = h * 0.5
    let inner = t.tokens.radii.xs
    var head_look = button_look(t, style.resolve(t.tokens, .Filled, control_state(t, key, true, false)), true)
    head_look.corners = style.Corners { top_left: outer, top_right: inner, bottom_right: inner, bottom_left: outer }
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, head_look.foreground)
    if label_error != ok { ret (zero, label_error) }
    let (head, head_error) = pressable(a, key, t, 3u8, label, head_look, true, false, action, label_node)
    if head_error != ok { ret (zero, head_error) }
    parts[0usize] = head
    var look = button_look(t, style.resolve(t.tokens, .Filled, control_state(t, key + 1u64, true, false)), true)
    look.corners = style.Corners { top_left: inner, top_right: outer, bottom_right: outer, bottom_left: inner }
    let size = t.tokens.sizes.icon_sm
    var width: f32 = 36.0
    if h > t.tokens.sizes.control_sm { width = 44.0 }
    look.custom_padding = true
    look.padding = (width - size) * 0.5
    look.padding_y = max_zero((h - size) * 0.5)
    look.min_width = width
    var states = 0u32
    if open { states = accessibility.STATE_EXPANDED }
    let (marks, marks_error) = mem.alloc[Mark](a, 1usize)
    if marks_error != ok { ret (zero, TooLarge) }
    marks[0usize] = Mark { color: look.foreground, expanded: true, arena: a }
    var none: []const widget.Node = zero
    let chevron = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&marks[0usize]), measure: mark_measure, paint: mark_paint, state: widget.bytes_of[Mark](&marks[0usize]) } }, style: sized_style(size, size), children: none }
    let (tail, tail_error) = pressable_states(a, key + 1u64, t, 3u8, "More", look, true, false, states, accessibility.ACTION_SHOW_MENU, key + 2u64, toggle, chevron)
    if tail_error != ok { ret (zero, tail_error) }
    parts[1usize] = tail
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 2.0 }, style.defaults(), parts[0usize..2usize])
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

// v2 (D955, docs/ux/components/Chip): 32 tall with `radius-sm` corners in a 1px
// `outline` edge, the `label-large` label in `on-surface` 16 from each side under
// its state layer; a selected filter chip is `secondary-container` without the
// edge, an 18 check leading its `on-secondary-container` label, 8 before the check;
// an input chip ends 8 after a 24 remove circle round an 18 cross in
// `on-surface-variant`, which takes its own state layer.
fn chip(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, kind: ChipKind, selected: bool, action: *const widget.Submit, remove: *const widget.Submit) -> (widget.Node, err) {
    let chosen = kind == .Filter && selected
    let state = control_state(t, key, true, chosen)
    var fill = paint.rgba(0.0, 0.0, 0.0, 0.0)
    var words = style.color(t.tokens, .OnSurface)
    var look = style.resolve(t.tokens, .Outlined, state)
    look.border = style.color(t.tokens, .Outline)
    look.border_width = 1.0
    if chosen {
        fill = style.color(t.tokens, .SecondaryContainer)
        words = style.color(t.tokens, .OnSecondaryContainer)
        look.border_width = 0.0
    }
    look.background = style.layer(fill, words, state_opacity(t, state))
    look.foreground = words
    look.radius = t.tokens.radii.sm
    let height = t.tokens.sizes.control_sm
    look.custom_padding = true
    look.padding = 16.0
    look.padding_y = max_zero((height - look.border_width * 2.0 - style.text_style(t.tokens, .Label).line_height) * 0.5)
    look.min_height = height
    var caption = text_options()
    caption.role = .Label
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, words)
    if label_error != ok { ret (zero, label_error) }
    var states = 0u32
    if chosen { states = accessibility.STATE_CHECKED }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var content = label_node
    if chosen {
        let (check, check_error) = mark_glyph(a, words, .Check, t.tokens.sizes.icon_sm)
        if check_error != ok { ret (zero, check_error) }
        parts[0usize] = check
        parts[1usize] = label_node
        look.padding_start = 8.0
        content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, style.defaults(), parts[0usize..2usize])
    }
    if kind == .Input {
        parts[0usize] = label_node
        let muted = style.color(t.tokens, .OnSurfaceVariant)
        let (cross, cross_error) = mark_glyph(a, muted, .Cross, t.tokens.sizes.icon_sm)
        if cross_error != ok { ret (zero, cross_error) }
        let (removed, removed_error) = mem.alloc[widget.Node](a, 1usize)
        if removed_error != ok { ret (zero, TooLarge) }
        removed[0usize] = cross
        var circle = sized_style(24.0, 24.0)
        circle.radius = 12.0
        circle.background = paint.Brush { Solid: with_alpha(muted, state_opacity(t, control_state(t, key + 1u64, true, false))) }
        let (hit, hit_error) = mem.alloc[widget.Node](a, 1usize)
        if hit_error != ok { ret (zero, TooLarge) }
        hit[0usize] = widget.aligned(0u64, .Center, .Center, circle, removed[0usize..1usize])
        let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
        if region_error != ok { ret (zero, TooLarge) }
        region[0usize] = widget.region(key + 1u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](remove), invoke: press_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, style.defaults(), hit[0usize..1usize])
        var remove_sem: widget.Semantics = zero
        remove_sem.role = 3u8
        remove_sem.label = "Remove"
        remove_sem.actions = accessibility.ACTION_PRESS
        parts[1usize] = widget.semantics(0u64, remove_sem, style.defaults(), region[0usize..1usize])
        look.padding = 8.0
        look.padding_start = 16.0
        look.padding_y = max_zero((height - 2.0 - 24.0) * 0.5)
        content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, style.defaults(), parts[0usize..2usize])
    }
    var role = 3u8
    if kind == .Filter { role = 4u8 }
    let (node, node_error) = pressable_states(a, key, t, role, label, look, true, chosen, states, 0u32, 0u64, action, content)
    ret (node, node_error)
}

// A rating's star, painted: five points about the middle, filled or outlined in
// the primary colour.
// v2 (D953): an empty star is a 1.75 stroke.
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
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: path, brush: paint.Brush { Solid: star.color }, stroke: paint.Stroke { width: 1.75, cap: .Round, join: .Round, miter_limit: 4.0 } } })
}

// A rating's keyboard move within `0..max` (D1162).
type RateMove = enum u8 { Less, More, First, Last }
type Rate = struct { value: u32, max: u32, move: RateMove, change: widget.Change[u32] }

fn rate_step(ctx: *void) -> err {
    let r = mem.cast[*Rate](ctx)
    var next = r.value
    if r.move == .More {
        if next < r.max { next += 1u32 }
    }
    if r.move == .Less {
        if next > 0u32 { next = next - 1u32 }
    }
    if r.move == .First { next = 0u32 }
    if r.move == .Last { next = r.max }
    ret widget.fire_change[u32](r.change, next)
}

// A tap on star `index` sets it, or clears an already-current value (D1167).
// Tap identity plus the row geometry used by drag scrubbing (D1173).
type Rated = struct { value: u32, current: u32, max: u32, key: widget.Key, cell: f32, rtl: bool, runtime: *widget.Runtime, change: widget.Change[u32] }

fn rate_at(r: *Rated, x: f32) -> err {
    let (area, has_area) = keyed_bounds(r.runtime, r.key)
    if !has_area { ret ok }
    var offset = x - area.x
    if r.rtl { offset = area.width - offset }
    var index = i64(offset / r.cell)
    if index < 0i64 { index = 0i64 }
    if index >= i64(r.max) { index = i64(r.max) - 1i64 }
    ret widget.fire_change[u32](r.change, u32(index) + 1u32)
}

fn rate_tap(ctx: *void, g: widget.Gesture) -> err {
    let r = mem.cast[*Rated](ctx)
    switch g {
    case .Tap as at:
        var next = r.value
        if r.current == next { next = 0u32 }
        ret widget.fire_change[u32](r.change, next)
    case .DragMove as moved:
        ret rate_at(r, moved.position.x)
    default:
        ret ok
    }
}

// A bound digit sets its exact in-range Rating value (D1169).
fn rate_exact(ctx: *void) -> err {
    let r = mem.cast[*Rated](ctx)
    ret widget.fire_change[u32](r.change, r.value)
}

// A rating: `max` stars in a row, the first `value` filled, each a tap region
// keyed `key + 1 + index` setting the value to its number; the row a focus
// target whose arrows step the value and whose Home/End reach its bounds; a
// slider in the tree named `label` with the value as digits.
fn rating(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: u32, max: u32, change: widget.Change[u32]) -> (widget.Node, err) {
    if max == 0u32 || max > 32u32 { ret (zero, TooLarge) }
    let count = usize(max)
    let (stars, stars_error) = mem.alloc[Star](a, count)
    if stars_error != ok { ret (zero, TooLarge) }
    var digit_count = count + 1usize
    if digit_count > 10usize { digit_count = 10usize }
    let (rated, rated_error) = mem.alloc[Rated](a, count + digit_count)
    if rated_error != ok { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[widget.Node](a, count)
    if items_error != ok { ret (zero, TooLarge) }
    // v2 (D953, docs/ux/components/Rating): each star centred in a round cell the
    // control height across (32 with a pointer, 40 on touch) that carries the hover
    // layer; the star 20 (24 on touch), filled `primary`, empty `on-surface-variant`;
    // while the pointer is over a star, the stars up to it preview in `primary` at 60%.
    // (D1166) RTL reverses only the physical cells; logical values and keys stay fixed.
    // (D1171) Keyboard focus rings the row and layers its current star.
    // (D1172) A pressed cell takes the pressed layer over hover and focus.
    let cell = t.tokens.metrics.control_height
    var size: f32 = 20.0
    if cell > t.tokens.sizes.control_sm { size = t.tokens.sizes.icon_md }
    let primary = style.color(t.tokens, .Primary)
    let group_state = control_state(t, key, true, false)
    var hovered = count
    var pressed = count
    var h = 0usize
    while h < count {
        let state = control_state(t, key + 1u64 + u64(h), true, false)
        if state.hovered { hovered = h }
        if state.pressed { pressed = h }
        h += 1usize
    }
    var none: []const widget.Node = zero
    var i = 0usize
    while i < count {
        var ink = style.color(t.tokens, .OnSurfaceVariant)
        var filled = u32(i) < value
        if filled { ink = primary }
        if hovered < count && i <= hovered && !filled {
            ink = with_alpha(primary, 0.6)
            filled = true
        }
        stars[i] = Star { color: ink, filled: filled, arena: a }
        rated[i] = Rated { value: u32(i) + 1u32, current: value, max: max, key: key, cell: cell, rtl: t.tokens.direction == .RightToLeft, runtime: t.runtime, change: change }
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&stars[i]), measure: mark_measure, paint: star_paint, state: widget.bytes_of[Star](&stars[i]) } }, style: sized_style(size, size), children: none }
        var cell_style = sized_style(cell, cell)
        cell_style.radius = cell * 0.5
        let inset = style.Length { Px: (cell - size) * 0.5 }
        cell_style.padding = style.EdgeLengths { left: inset, top: inset, right: inset, bottom: inset }
        if group_state.focus_visible && u32(i) + 1u32 == value { cell_style.background = paint.Brush { Solid: style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), style.color(t.tokens, .OnSurface), t.tokens.states.focus) } }
        if i == hovered { cell_style.background = paint.Brush { Solid: style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), style.color(t.tokens, .OnSurface), t.tokens.states.hover) } }
        if i == pressed { cell_style.background = paint.Brush { Solid: style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), style.color(t.tokens, .OnSurface), t.tokens.states.pressed) } }
        var slot = i
        if t.tokens.direction == .RightToLeft { slot = count - 1usize - i }
        items[slot] = widget.region(key + 1u64 + u64(i), widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&rated[i]), invoke: rate_tap }, gestures: 1u8 | 2u8 | 4u8, enabled: true, focusable: false }, cell_style, body[0usize..1usize])
        i += 1usize
    }
    let (steps, steps_error) = mem.alloc[Rate](a, 4usize)
    if steps_error != ok { ret (zero, TooLarge) }
    steps[0usize] = Rate { value: value, max: max, move: .Less, change: change }
    steps[1usize] = Rate { value: value, max: max, move: .More, change: change }
    steps[2usize] = Rate { value: value, max: max, move: .First, change: change }
    steps[3usize] = Rate { value: value, max: max, move: .Last, change: change }
    let less = widget.Submit { ctx: mem.cast[*void](&steps[0usize]), invoke: rate_step }
    let more = widget.Submit { ctx: mem.cast[*void](&steps[1usize]), invoke: rate_step }
    let shortcut_count = 6usize + digit_count
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, shortcut_count)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 37u32, modifiers: zero, action: less }
    shortcuts[1usize] = widget.Shortcut { key: 39u32, modifiers: zero, action: more }
    if t.tokens.direction == .RightToLeft {
        shortcuts[0usize].action = more
        shortcuts[1usize].action = less
    }
    shortcuts[2usize] = widget.Shortcut { key: 40u32, modifiers: zero, action: less }
    shortcuts[3usize] = widget.Shortcut { key: 38u32, modifiers: zero, action: more }
    shortcuts[4usize] = widget.Shortcut { key: 36u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&steps[2usize]), invoke: rate_step } }
    shortcuts[5usize] = widget.Shortcut { key: 35u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&steps[3usize]), invoke: rate_step } }
    var d = 0usize
    while d < digit_count {
        rated[count + d] = Rated { value: u32(d), current: value, max: max, key: key, cell: cell, rtl: t.tokens.direction == .RightToLeft, runtime: t.runtime, change: change }
        shortcuts[6usize + d] = widget.Shortcut { key: 48u32 + u32(d), modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&rated[count + d]), invoke: rate_exact } }
        d += 1usize
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), items[0usize..count])
    // The row is one focus target so the keyboard reaches it; a press on a star
    // lands on the star, whose region is under it.
    var none_gesture: widget.GestureAction = zero
    let (focus, focus_error) = mem.alloc[widget.Node](a, 1usize)
    if focus_error != ok { ret (zero, TooLarge) }
    var focus_style = style.defaults()
    focus_style.radius = cell * 0.5
    focus[0usize] = widget.region(key, widget.Region { gesture: none_gesture, gestures: 0u8, enabled: true, focusable: true }, focus_style, row[0usize..1usize])
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..shortcut_count], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), focus[0usize..1usize])
    // D1168: expose the scale, and give zero its specified spoken value.
    let (said, said_error) = mem.alloc[u8](a, 32usize)
    if said_error != ok { ret (zero, TooLarge) }
    var said_len = 0usize
    if value == 0u32 {
        said_len = copy_text(said, "Not rated")
    } else {
        said_len = write_i64(said, i64(value))
        said_len += copy_text(said[said_len..], " of ")
        said_len += write_i64(said[said_len..], i64(max))
        said_len += copy_text(said[said_len..], " stars")
    }
    var sem: widget.Semantics = zero
    sem.role = 15u8
    sem.label = label
    sem.value = said[0usize..said_len]
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
// The inner padding of a stepper's pill: 2 with a pointer, 4 on touch.
fn step_inset(t: *const Theme) -> f32 {
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { ret 4.0 }
    ret 2.0
}

// A stepper's button: a circle the control height less twice the inset across,
// its glyph centred in `on-surface`, the v2 disabled colours at its bound.
fn step_button(a: *mem.Arena, key: widget.Key, t: *const Theme, glyph: str, action: *const widget.Submit, enabled: bool) -> (widget.Node, err) {
    var look = style.resolve(t.tokens, .Plain, control_state(t, key, enabled, false))
    look.foreground = style.color(t.tokens, .OnSurface)
    if !enabled { look = style.disabled_look(t.tokens, look) }
    let side = t.tokens.metrics.control_height - 2.0 * step_inset(t)
    let line = style.text_style(t.tokens, .LabelLarge).line_height
    look.radius = side * 0.5
    look.custom_padding = true
    look.padding = 0.0
    look.padding_y = max_zero((side - line) * 0.5)
    look.min_width = side
    look.min_height = side
    var caption = text_options()
    caption.role = .LabelLarge
    caption.wrap = .None
    caption.align = .Center
    let (glyph_node, glyph_error) = colored_text(a, 0u64, glyph, t, caption, look.foreground)
    if glyph_error != ok { ret (zero, glyph_error) }
    var centred = glyph_node
    centred.style.width = style.Length { Px: side }
    let (node, node_error) = pressable(a, key, t, 3u8, glyph, look, enabled, false, action, centred)
    ret (node, node_error)
}

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
    // v2 (D952, docs/ux/components/Stepper): round buttons in `on-surface`, the
    // control height less the pill's inner padding across.
    let (minus, minus_error) = step_button(a, less, t, "-", &actions[0usize], value > low)
    if minus_error != ok { ret (zero, zero, minus_error) }
    buttons[0usize] = minus
    let (plus, plus_error) = step_button(a, more, t, "+", &actions[1usize], value < high)
    if plus_error != ok { ret (zero, zero, plus_error) }
    buttons[1usize] = plus
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if shortcuts_error != ok { ret (zero, zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 40u32, modifiers: zero, action: actions[0usize] }
    shortcuts[1usize] = widget.Shortcut { key: 38u32, modifiers: zero, action: actions[1usize] }
    ret (buttons, shortcuts, ok)
}

// The row of a stepper or a spin box under its scope and its slider semantics.
// With no buttons (D956) the middle stands alone: a spin box's arrows are inside it.
fn stepped(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: i64, middle: widget.Node, buttons: []widget.Node, shortcuts: []widget.Shortcut, role: u8) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var used = 1usize
    parts[0usize] = middle
    if buttons.len == 2usize {
        parts[0usize] = buttons[0usize]
        parts[1usize] = middle
        parts[2usize] = buttons[1usize]
        used = 3usize
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    // v2 (D952): a pill the control height tall, 1px `outline`, the buttons 4 from
    // the value and `step_inset` from the edge.
    var pill = style.defaults()
    pill.min_height = style.Length { Px: t.tokens.metrics.control_height }
    pill.radius = t.tokens.metrics.control_height * 0.5
    pill.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .Outline) }
    let inset = style.Length { Px: step_inset(t) }
    pill.padding = style.EdgeLengths { left: inset, top: inset, right: inset, bottom: inset }
    if role == 2u8 { pill = style.defaults() }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, pill, parts[0usize..used])
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
    caption.role = .LabelLarge
    caption.color = .OnSurface
    caption.wrap = .None
    caption.align = .Center
    let (shown, shown_error) = text_node(a, 0u64, digits[0usize..digit_count], t, caption)
    if shown_error != ok { ret (zero, shown_error) }
    var fixed = shown
    fixed.style.min_width = style.Length { Px: 40.0 }
    let (made, made_error) = stepped(a, key, t, label, value, fixed, buttons, shortcuts, 15u8)
    ret (made, made_error)
}

// A spin box: a text field (keyed `key`) over the caller's `buffer` showing
// `value` as digits, between the stepper's buttons (`key + 1`, `key + 2`); typed
// text reaches `typed` for the caller to parse, the buttons and Up/Down move
// `value` through `change`. A group in the tree named `label`, the field inside
// it labelled the same.
// v2 (D956, docs/ux/components/SpinBox): with a pointer, the buttons are a stacked
// pair of 24 x 18 arrows (`key + 2` up, `key + 1` down) inside the field's end, 8
// from it, their 16 chevrons in `on-surface-variant` under their own state layers,
// the v2 disabled colours at a bound; on touch they flank the field as D952's.
fn spin_box(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, value: i64, low: i64, high: i64, step: i64, change: widget.Change[i64], typed: widget.Change[str]) -> (widget.Node, err) {
    let (made, made_error) = spin_box_sized(a, key, t, label, buffer, value, low, high, step, change, typed, 4.0 * t.tokens.spacing.lg)
    ret (made, made_error)
}

// The same spin box `width` wide (D961: the font picker's 104).
fn spin_box_sized(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, value: i64, low: i64, high: i64, step: i64, change: widget.Change[i64], typed: widget.Change[str], width: f32) -> (widget.Node, err) {
    let (buttons, shortcuts, pair_error) = step_pair(a, t, key + 1u64, key + 2u64, value, low, high, step, change)
    if pair_error != ok { ret (zero, pair_error) }
    let len = write_i64(buffer, value)
    var options = field_options()
    options.width = width
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    if !touch { options.end_space = 24.0 - 8.0 }
    let (editor, editor_error) = text_field(a, key, t, label, buffer, len, typed, zero, options)
    if editor_error != ok { ret (zero, editor_error) }
    if touch {
        let (made, made_error) = stepped(a, key + 3u64, t, label, value, editor, buttons, shortcuts, 2u8)
        ret (made, made_error)
    }
    let (arrows, arrows_error) = mem.alloc[widget.Node](a, 4usize)
    if arrows_error != ok { ret (zero, TooLarge) }
    let (up, up_error) = arrow_button(a, key + 2u64, t, .ChevronUp, "Increase", &shortcuts[1usize].action, value < high)
    if up_error != ok { ret (zero, up_error) }
    let (down, down_error) = arrow_button(a, key + 1u64, t, .ChevronDown, "Decrease", &shortcuts[0usize].action, value > low)
    if down_error != ok { ret (zero, down_error) }
    arrows[0usize] = up
    arrows[1usize] = down
    arrows[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), arrows[0usize..2usize])
    let h = t.tokens.metrics.control_height + 16.0
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[0usize] = editor
    layers[1usize] = widget.positioned(0u64, options.width - 8.0 - 24.0, max_zero((h - 36.0) * 0.5), style.defaults(), arrows[2usize..3usize])
    let boxed = widget.stack(0u64, style.defaults(), layers[0usize..2usize])
    var none: []widget.Node = zero
    let (made, made_error) = stepped(a, key + 3u64, t, label, value, boxed, none, shortcuts, 2u8)
    ret (made, made_error)
}

// A spin box's arrow: 24 x 18 with `radius-xs` corners, a 16 chevron in
// `on-surface-variant` under the state layer of that colour.
fn arrow_button(a: *mem.Arena, key: widget.Key, t: *const Theme, kind: GlyphKind, label: str, action: *const widget.Submit, enabled: bool) -> (widget.Node, err) {
    let state = control_state(t, key, enabled, false)
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = with_alpha(muted, state_opacity(t, state))
    look.foreground = muted
    if !enabled { look = style.disabled_look(t.tokens, look) }
    look.radius = t.tokens.radii.xs
    look.custom_padding = true
    look.padding = 4.0
    look.padding_y = 1.0
    look.min_width = 24.0
    look.min_height = 18.0
    let (chevron, chevron_error) = mark_glyph(a, look.foreground, kind, 16.0)
    if chevron_error != ok { ret (zero, chevron_error) }
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, enabled, false, action, chevron)
    ret (node, node_error)
}

// A dial's paint and pointer: the value's share of the turn, where it is, whom to
// tell. The knob is a stroked circle with a line from the middle at the share's
// angle, which runs three quarters of a turn from the lower left clockwise.
type Knob = struct { runtime: *widget.Runtime, key: widget.Key, track: paint.Color, fill: paint.Color, share: f32, low: f32, high: f32, change: widget.Change[f32], arena: *mem.Arena }

// v2 (D953, docs/ux/components/Dial): a 270-degree track from the lower left,
// radius 40% of the face and 6% wide in `secondary-container` with round caps, the
// active arc over it in `primary` up to the value, and a round `primary` handle
// 14% of the face across at its end.
fn knob_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let k = mem.cast[*Knob](ctx)
    let cx = area.x + area.width * 0.5
    let cy = area.y + area.height * 0.5
    var face = area.width
    if area.height < face { face = area.height }
    let radius = face * 0.4
    if radius <= 0.0 { ret ok }
    let stroke = paint.Stroke { width: face * 0.06, cap: .Round, join: .Round, miter_limit: 4.0 }
    let start: f32 = 0.0 - 2.3561945
    let (track, track_error) = sweep_path(k.arena, cx, cy, radius, start, 4.712389)
    if track_error != ok { ret track_error }
    try scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: track, brush: paint.Brush { Solid: k.track }, stroke: stroke } })
    let sweep = k.share * 4.712389
    if sweep > 0.001 {
        let (active, active_error) = sweep_path(k.arena, cx, cy, radius, start, sweep)
        if active_error != ok { ret active_error }
        try scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: active, brush: paint.Brush { Solid: k.fill }, stroke: stroke } })
    }
    let end = start + sweep
    let (handle, handle_error) = arc_path(k.arena, cx + math.sin[f32](end) * radius, cy - math.cos[f32](end) * radius, face * 0.07, 1.0)
    if handle_error != ok { ret handle_error }
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: handle, brush: paint.Brush { Solid: k.fill } } })
}

// An open arc as chords: from `start` (radians clockwise from the top) through
// `sweep`, a chord every sixteenth of a turn or less.
fn sweep_path(a: *mem.Arena, cx: f32, cy: f32, radius: f32, start: f32, sweep: f32) -> (geometry.Path, err) {
    var steps = usize(sweep / 0.19634955) + 2usize
    if steps > 40usize { steps = 40usize }
    let (pb, pb_error) = geometry.path_builder(a, steps + 2usize, steps + 2usize)
    if pb_error != ok { ret (zero, TooLarge) }
    var builder = pb
    if geometry.move_to(&builder, geometry.Point { x: cx + math.sin[f32](start) * radius, y: cy - math.cos[f32](start) * radius }) != ok { ret (zero, TooLarge) }
    var i = 1usize
    while i <= steps {
        let angle = start + sweep * f32(i) / f32(steps)
        if geometry.line_to(&builder, geometry.Point { x: cx + math.sin[f32](angle) * radius, y: cy - math.cos[f32](angle) * radius }) != ok { ret (zero, TooLarge) }
        i += 1usize
    }
    ret (geometry.finish(&builder), ok)
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
    knobs[0usize] = Knob { runtime: t.runtime, key: key, track: style.color(t.tokens, .SecondaryContainer), fill: style.color(t.tokens, .Primary), share: share, low: low, high: high, change: change, arena: a }
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
    // The readout in the middle: `title-large` (`label-large` on a small face) in
    // `on-surface`, over the face.
    let (readout_digits, readout_error) = mem.alloc[u8](a, 21usize)
    if readout_error != ok { ret (zero, TooLarge) }
    var readout_value = value + 0.5
    if value < 0.0 { readout_value = value - 0.5 }
    let readout_len = write_i64(readout_digits, i64(readout_value))
    var readout = text_options()
    readout.role = .TitleLarge
    if size < 100.0 { readout.role = .LabelLarge }
    readout.color = .OnSurface
    readout.wrap = .None
    let (readout_node, readout_node_error) = text_node(a, 0u64, readout_digits[0usize..readout_len], t, readout)
    if readout_node_error != ok { ret (zero, readout_node_error) }
    let (faces, faces_error) = mem.alloc[widget.Node](a, 3usize)
    if faces_error != ok { ret (zero, TooLarge) }
    faces[0usize] = readout_node
    faces[1usize] = body[0usize]
    faces[2usize] = widget.aligned(0u64, .Center, .Center, sized_style(size, size), faces[0usize..1usize])
    let face = widget.stack(0u64, sized_style(size, size), faces[1usize..3usize])
    let (faced, faced_error) = mem.alloc[widget.Node](a, 1usize)
    if faced_error != ok { ret (zero, TooLarge) }
    faced[0usize] = face
    var hit_style = sized_style(size, size)
    hit_style.radius = size * 0.5
    hit[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&knobs[0usize]), invoke: knob_gesture }, gestures: 1u8 | 2u8 | 4u8, enabled: true, focusable: true }, hit_style, faced[0usize..1usize])
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
    // v2 (D953, docs/ux/components/ShortcutRecorder): a field-shaped box 40 tall
    // (32 dense) and 220 wide, 12 before its content and 4 after, 1px `outline`
    // (`on-surface` hovered); recording, a 2px `primary` outline over `primary` at
    // 8% and the hint in `on-surface`; the chord as key caps 24 tall, 4 apart.
    let state = control_state(t, key, true, false)
    var look = style.resolve(t.tokens, .Outlined, state)
    look.border = style.color(t.tokens, .Outline)
    if state.hovered { look.border = style.color(t.tokens, .OnSurface) }
    look.border_width = t.tokens.sizes.divider
    look.background = paint.rgba(0.0, 0.0, 0.0, 0.0)
    if recording {
        look.border = style.color(t.tokens, .Primary)
        look.border_width = t.tokens.sizes.outline_focused
        look.background = style.layer(look.background, look.border, 0.08)
    }
    look.radius = t.tokens.radii.xs
    var box_h = t.tokens.sizes.control_md
    if t.tokens.metrics.control_height < t.tokens.sizes.control_sm { box_h = t.tokens.sizes.control_sm }
    look.custom_padding = true
    look.padding_start = 12.0
    look.padding = 4.0
    look.padding_y = max_zero((box_h - 24.0) * 0.5)
    look.min_height = box_h
    look.min_width = 220.0
    var content: widget.Node = zero
    if recording || chord.key == 0u32 {
        var hint = text_options()
        hint.role = .BodyMedium
        hint.color = .OnSurfaceVariant
        if recording { hint.color = .OnSurface }
        hint.wrap = .None
        var words = shown
        if !recording { words = label }
        let (hint_node, hint_error) = text_node(a, 0u64, words, t, hint)
        if hint_error != ok { ret (zero, hint_error) }
        content = hint_node
    } else {
        let (caps, caps_error) = key_caps(a, t, shown)
        if caps_error != ok { ret (zero, caps_error) }
        content = caps
    }
    let (field_node, field_error) = pressable_states(a, key, t, 3u8, label, look, true, recording, 0u32, 0u32, 0u64, start, content)
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

// A chord's key caps (D953): each `+`-separated part a cap 24 tall with 6px sides,
// `radius-xs`, a 1px `outline-variant` edge on `surface-container-lowest`, its
// name in `code` and `on-surface-variant`; 4 apart.
fn key_caps_of(a: *mem.Arena, t: *const Theme, chord_text: str, height: f32, min_width: f32, side: f32, vertical: f32, role: style.TextRole) -> (widget.Node, err) {
    var parts_count = 1usize
    var i = 0usize
    while i < chord_text.len {
        if chord_text[i] == 43u8 && i + 1usize < chord_text.len { parts_count += 1usize }
        i += 1usize
    }
    let (caps, caps_error) = mem.alloc[widget.Node](a, parts_count)
    if caps_error != ok { ret (zero, TooLarge) }
    var cap_text = text_options()
    cap_text.role = role
    cap_text.color = .OnSurfaceVariant
    cap_text.wrap = .None
    var from = 0usize
    var at = 0usize
    i = 0usize
    while i <= chord_text.len {
        let boundary = i == chord_text.len || (chord_text[i] == 43u8 && i + 1usize < chord_text.len && i > from)
        if boundary {
            let (name, name_error) = text_node(a, 0u64, chord_text[from..i], t, cap_text)
            if name_error != ok { ret (zero, name_error) }
            let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
            if inner_error != ok { ret (zero, TooLarge) }
            inner[0usize] = name
            var cap = style.defaults()
            cap.min_height = style.Length { Px: height }
            cap.min_width = style.Length { Px: min_width }
            cap.radius = t.tokens.radii.xs
            cap.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLowest) }
            cap.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .OutlineVariant) }
            let sides = style.Length { Px: side }
            let tb = style.Length { Px: vertical }
            cap.padding = style.EdgeLengths { left: sides, top: tb, right: sides, bottom: tb }
            if at < parts_count {
                caps[at] = widget.box(0u64, cap, inner[0usize..1usize])
                at += 1usize
            }
            from = i + 1usize
        }
        i += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), caps[0usize..at]), ok)
}

fn key_caps(a: *mem.Arena, t: *const Theme, chord_text: str) -> (widget.Node, err) {
    let (made, made_error) = key_caps_of(a, t, chord_text, 24.0, 24.0, 6.0, 2.0, .Code)
    ret (made, made_error)
}

fn compact_key_caps(a: *mem.Arena, t: *const Theme, chord_text: str) -> (widget.Node, err) {
    let (made, made_error) = key_caps_of(a, t, chord_text, 20.0, 20.0, 4.0, 0.0, .LabelSmall)
    ret (made, made_error)
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
    // An untouched, empty field is not wrong yet (D952).
    shown.invalid = options.invalid || (len != 0usize && !adapter.accept(adapter.ctx, buffer[0usize..len]))
    let (made, made_error) = text_field(a, key, t, label, buffer, len, typed, widget.Submit { ctx: mem.cast[*void](&formats[0usize]), invoke: format_submit }, shown)
    ret (made, made_error)
}

// A move of the active suggestion, for Up and Down.
type Move = struct { index: usize, activate: widget.Change[usize] }

fn move_fire(ctx: *void) -> err {
    let m = mem.cast[*Move](ctx)
    ret widget.fire_change[usize](m.activate, m.index)
}

// A row of a list of suggestions or choices (D952): `body-medium` in `on-surface`,
// 12 each side, 36 tall with a pointer and 48 on touch, transparent; the active
// row carries the `state-focus` layer of `on-surface`, a hovered one the hover layer.
fn list_row(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, active: bool, action: *const widget.Submit) -> (widget.Node, err) {
    let state = control_state(t, key, true, false)
    let ink = style.color(t.tokens, .OnSurface)
    var look = style.resolve(t.tokens, .Plain, state)
    look.foreground = ink
    look.background = paint.rgba(0.0, 0.0, 0.0, 0.0)
    if active { look.background = style.layer(look.background, ink, t.tokens.states.focus) }
    if state.hovered && !active { look.background = style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), ink, t.tokens.states.hover) }
    look.radius = 0.0
    var h: f32 = 36.0
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { h = t.tokens.sizes.control_lg }
    let line = style.text_style(t.tokens, .BodyMedium).line_height
    look.custom_padding = true
    look.padding = 12.0
    look.padding_y = max_zero((h - line) * 0.5)
    look.min_height = h
    var caption = text_options()
    caption.role = .BodyMedium
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, ink)
    if label_error != ok { ret (zero, label_error) }
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, true, false, action, label_node)
    ret (node, node_error)
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
            let (item, item_error) = list_row(a, first + u64(i), t, suggestions[i], i == active, &picks[i])
            if item_error != ok { ret (zero, item_error) }
            var entry: widget.Semantics = zero
            entry.role = accessibility.ROLE_OPTION
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
        // v2 (D952, docs/ux/components/Autocomplete): `surface-container`, 8
        // corners, elevation 2, 8 above and below the rows, 4 below the field.
        var sheet = surface_options(t)
        sheet.background = .SurfaceContainer
        sheet.elevation = 2u8
        sheet.radius = t.tokens.radii.sm
        sheet.padding = 0.0
        var sheet_style = surface_style(t, sheet)
        sheet_style.padding.top = style.Length { Px: 8.0 }
        sheet_style.padding.bottom = style.Length { Px: 8.0 }
        let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
        if column_error != ok { ret (zero, TooLarge) }
        column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, sheet_style, items[0usize..suggestions.len])
        var list_sem: widget.Semantics = zero
        list_sem.role = accessibility.ROLE_LISTBOX
        list_sem.label = label
        list_sem.row_count = u32(suggestions.len)
        let (popup, popup_error) = mem.alloc[widget.Node](a, 1usize)
        if popup_error != ok { ret (zero, TooLarge) }
        popup[0usize] = widget.semantics(0u64, list_sem, style.defaults(), column[0usize..1usize])
        parts[count - 1usize] = widget.overlay(list_key, widget.Overlay { anchor: key, placement: .BelowMatch, offset: geometry.Point { x: 0.0, y: 4.0 }, modal: false, dismiss: zero }, style.defaults(), popup[0usize..1usize])
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
    sem.role = accessibility.ROLE_COMBOBOX
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
// `toggle`; the list is `key + 2`, its items `key + 3 + index`.
// v2 (D956, docs/ux/components/ComboBox): the chevron is a round icon button inside
// the field's end, 4 from it -- 32 across with an 18 chevron with a pointer, 40
// with a 24 on touch -- in `on-surface-variant`, pointing up while open.
fn combo_box(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], choices: []const str, active: usize, open: bool, picks: []const widget.Submit, activate: widget.Change[usize], toggle: *const widget.Submit, options: FieldOptions) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var side = t.tokens.sizes.control_sm
    var size = t.tokens.sizes.icon_sm
    if touch {
        side = t.tokens.sizes.control_md
        size = t.tokens.sizes.icon_md
    }
    // The value stops before the chevron: its 4 in plus its width, less the side.
    var kept = options
    kept.end_space = max_zero(side + 4.0 - 16.0)
    let (field_node, field_error) = text_field(a, key, t, label, buffer, len, typed, zero, kept)
    if field_error != ok { ret (zero, field_error) }
    let state = control_state(t, key + 1u64, true, false)
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = with_alpha(muted, state_opacity(t, state))
    look.foreground = muted
    look.radius = side * 0.5
    look.custom_padding = true
    look.padding = (side - size) * 0.5
    look.padding_y = look.padding
    look.min_width = side
    look.min_height = side
    var kind: GlyphKind = .ChevronDown
    if open { kind = .ChevronUp }
    let (chevron, chevron_error) = mark_glyph(a, muted, kind, size)
    if chevron_error != ok { ret (zero, chevron_error) }
    var states = 0u32
    if open { states = accessibility.STATE_EXPANDED }
    let (opener, opener_error) = pressable_states(a, key + 1u64, t, 3u8, "Choices", look, true, false, states, accessibility.ACTION_SHOW_MENU, key + 2u64, toggle, chevron)
    if opener_error != ok { ret (zero, opener_error) }
    let h = t.tokens.metrics.control_height + 16.0
    let (layers, layers_error) = mem.alloc[widget.Node](a, 3usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[2usize] = opener
    layers[0usize] = field_node
    layers[1usize] = widget.positioned(0u64, options.width - 4.0 - side, max_zero((h - side) * 0.5), style.defaults(), layers[2usize..3usize])
    let boxed = widget.stack(0u64, style.defaults(), layers[0usize..2usize])
    var none: []const widget.Node = zero
    let (made, made_error) = suggesting(a, key, t, label, boxed, none, key + 2u64, key + 3u64, choices, active, open, picks, activate, toggle)
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
    // v2 (D952, docs/ux/components/TokenField): the chips and the input flow inside
    // one outlined box -- 1px `outline`, 2px `primary` while the input is focused --
    // at least 56 tall on touch and 40 with a pointer, 12 in (4 above and below
    // with a pointer), 8 between (4 with a pointer); the input at least 96 wide.
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    let state = control_state(t, key, true, false)
    var role: style.TextRole = .BodyMedium
    if touch { role = .BodyLarge }
    let (text_look, style_error) = text_style(a, t, role)
    if style_error != ok { ret (zero, style_error) }
    let line = style.text_style(t.tokens, role).line_height
    var editor_style = style.defaults()
    editor_style.min_width = style.Length { Px: 96.0 }
    editor_style.min_height = style.Length { Px: line }
    let bare = widget.edit(key, widget.Edit { buffer: buffer, len: len, style: text_look, color: style.color(t.tokens, .OnSurface), selection: style.color(t.tokens, .TextSelection), change: typed, submit: add, enabled: true, read_only: false, multiline: false, secret: false, marked: zero, caret: zero, untabbed: false, ringed: false }, editor_style)
    var input_count = 1usize
    if len == 0usize && tokens.len == 0usize && label.len != 0usize { input_count = 2usize }
    let (input_parts, input_parts_error) = mem.alloc[widget.Node](a, input_count)
    if input_parts_error != ok { ret (zero, TooLarge) }
    input_parts[input_count - 1usize] = bare
    if input_count == 2usize {
        var hint = text_options()
        hint.role = role
        hint.color = .OnSurfaceVariant
        hint.wrap = .None
        let (hint_node, hint_error) = text_node(a, 0u64, label, t, hint)
        if hint_error != ok { ret (zero, hint_error) }
        input_parts[0usize] = hint_node
    }
    items[tokens.len] = widget.stack(0u64, style.defaults(), input_parts[0usize..input_count])
    var gap: f32 = 4.0
    var box_h: f32 = 40.0
    var pad_y: f32 = 4.0
    if touch {
        gap = 8.0
        box_h = t.tokens.sizes.control_xl
        pad_y = 12.0
    }
    var wrapped = style.defaults()
    wrapped.width = style.Length { Px: width }
    wrapped.min_height = style.Length { Px: box_h }
    wrapped.radius = t.tokens.radii.xs
    var edge = style.color(t.tokens, .Outline)
    var edge_width = t.tokens.sizes.divider
    if state.hovered { edge = style.color(t.tokens, .OnSurface) }
    if state.focused {
        edge = style.color(t.tokens, .Primary)
        edge_width = t.tokens.sizes.outline_focused
    }
    wrapped.border = style.Border { width: edge_width, color: edge }
    wrapped.padding = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: pad_y }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: pad_y } }
    let flow = widget.wrap(0u64, ui_layout.Wrap { axis: .Horizontal, main_gap: gap, cross_gap: gap }, wrapped, items[0usize..tokens.len + 1usize])
    var none: []const widget.Node = zero
    let (made, made_error) = suggesting(a, key, t, label, flow, none, key + 62u64, key + 63u64, suggestions, active, open, picks, activate, dismiss)
    ret (made, made_error)
}

// How a picker presents its choice: D824's popup select, or a sheet -- a modal
// overlay listing the options under a title, for a touch host.
type PickerForm = enum u8 { Popup, Sheet }

// A picker: `.Popup` is the select (D956: the docked menu with the chosen row
// checked); `.Sheet` keeps the select's field (keyed `key`, firing `toggle`) and,
// open, raises a bottom sheet (keyed `key + 1`) of radio rows keyed `key + 2 + index`.
// v2 (D959, docs/ux/components/Picker): the sheet is `surface-container-low` with
// 28 top corners and elevation 1, the window's width up to 640 and centred, over a
// `scrim` at the scrim opacity across the window; a 32 x 4 handle in
// `on-surface-variant` at 40% stands 16 from its top, the title in `title-large`
// 24 in from the sides, then rows 56 tall, 16 in, a radio in its 40 circle before
// the option in `body-large`; a press on the scrim, or Escape, fires `toggle`.
// ponytail: the sheet opens at its full height; the 60% cap, the drag to expand and the slide wait on motion and a scrolled body.
fn picker(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, selected: usize, open: bool, toggle: *const widget.Submit, picks: []const widget.Submit, presentation: PickerForm) -> (widget.Node, err) {
    if presentation == .Popup {
        let (popup, popup_error) = select(a, key, t, label, options, selected, open, toggle, picks)
        ret (popup, popup_error)
    }
    if picks.len != options.len { ret (zero, TooLarge) }
    let chosen = selected < options.len
    var shown = label
    if chosen { shown = options[selected] }
    let dense = t.tokens.metrics.control_height < t.tokens.sizes.control_sm
    let (head, head_error) = field_head(a, key, t, label, shown, chosen, open, toggle, t.tokens.metrics.control_height + 16.0, .ChevronDown, .ChevronUp, !dense)
    if head_error != ok { ret (zero, head_error) }
    var count = 1usize
    if open { count = 3usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    if open {
        let (rows, rows_error) = mem.alloc[widget.Node](a, options.len + 2usize)
        if rows_error != ok { ret (zero, TooLarge) }
        var grip = sized_style(32.0, 4.0)
        grip.radius = 2.0
        grip.background = paint.Brush { Solid: with_alpha(style.color(t.tokens, .OnSurfaceVariant), 0.4) }
        let (grips, grips_error) = mem.alloc[widget.Node](a, 1usize)
        if grips_error != ok { ret (zero, TooLarge) }
        grips[0usize] = widget.box(0u64, grip, zero)
        rows[0usize] = widget.aligned(0u64, .Center, .Start, style.defaults(), grips[0usize..1usize])
        var heading = text_options()
        heading.role = .TitleLarge
        heading.wrap = .None
        let (title_node, title_error) = colored_text(a, 0u64, label, t, heading, style.color(t.tokens, .OnSurface))
        if title_error != ok { ret (zero, title_error) }
        let (titles, titles_error) = mem.alloc[widget.Node](a, 1usize)
        if titles_error != ok { ret (zero, TooLarge) }
        titles[0usize] = title_node
        var title_box = style.defaults()
        let side = style.Length { Px: 24.0 }
        title_box.padding = style.EdgeLengths { left: side, top: style.Length { Px: 16.0 }, right: side, bottom: style.Length { Px: 8.0 } }
        rows[1usize] = widget.box(0u64, title_box, titles[0usize..1usize])
        var full = style.defaults()
        full.width = style.Length { Percent: 100.0 }
        var i = 0usize
        while i < options.len {
            let row_key = key + 2u64 + u64(i)
            let row_state = control_state(t, row_key, true, false)
            let (bits, bits_error) = mem.alloc[widget.Node](a, 2usize)
            if bits_error != ok { ret (zero, TooLarge) }
            let (ring, ring_error) = choice_mark(a, t, row_state, i == selected, false, true, true)
            if ring_error != ok { ret (zero, ring_error) }
            bits[0usize] = ring
            var words = text_options()
            words.role = .BodyLarge
            words.wrap = .None
            let (word, word_error) = colored_text(a, 0u64, options[i], t, words, style.color(t.tokens, .OnSurface))
            if word_error != ok { ret (zero, word_error) }
            bits[1usize] = word
            let (lines, lines_error) = mem.alloc[widget.Node](a, 1usize)
            if lines_error != ok { ret (zero, TooLarge) }
            var line_style = style.defaults()
            line_style.min_height = style.Length { Px: 56.0 }
            line_style.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 0.0 } }
            lines[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, line_style, bits[0usize..2usize])
            let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
            if inner_error != ok { ret (zero, TooLarge) }
            inner[0usize] = widget.region(row_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&picks[i]), invoke: press_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, full, lines[0usize..1usize])
            var entry: widget.Semantics = zero
            entry.role = 5u8
            entry.label = options[i]
            entry.actions = accessibility.ACTION_PRESS
            if i == selected { entry.states = accessibility.STATE_CHECKED }
            rows[2usize + i] = widget.semantics(0u64, entry, full, inner[0usize..1usize])
            i += 1usize
        }
        var sheet_style = style.defaults()
        sheet_style.width = style.Length { Percent: 100.0 }
        sheet_style.max_width = style.Length { Px: 640.0 }
        sheet_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
        sheet_style.corners = style.Corners { top_left: t.tokens.radii.xl, top_right: t.tokens.radii.xl, bottom_right: 0.0, bottom_left: 0.0 }
        sheet_style.shadow = style.Shadow { offset: geometry.Point { x: 0.0, y: 2.0 }, color: paint.rgba(0.0, 0.0, 0.0, t.tokens.elevation[1usize]) }
        sheet_style.overflow = .Clip
        sheet_style.padding = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 16.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 8.0 } }
        let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
        if column_error != ok { ret (zero, TooLarge) }
        column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, sheet_style, rows[0usize..options.len + 2usize])
        var group: widget.Semantics = zero
        group.role = 2u8
        group.label = label
        let (grouped, grouped_error) = mem.alloc[widget.Node](a, 1usize)
        if grouped_error != ok { ret (zero, TooLarge) }
        var group_style = style.defaults()
        group_style.width = style.Length { Percent: 100.0 }
        group_style.max_width = style.Length { Px: 640.0 }
        grouped[0usize] = widget.semantics(0u64, group, group_style, column[0usize..1usize])
        var centre = style.defaults()
        centre.width = style.Length { Percent: 100.0 }
        let (centred, centred_error) = mem.alloc[widget.Node](a, 1usize)
        if centred_error != ok { ret (zero, TooLarge) }
        centred[0usize] = widget.aligned(0u64, .Center, .End, centre, grouped[0usize..1usize])
        var none: []const widget.Shortcut = zero
        let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
        if scoped_error != ok { ret (zero, TooLarge) }
        scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: zero, cancel_action: *toggle, keys: zero }, style.defaults(), centred[0usize..1usize])
        var list_sem: widget.Semantics = zero
        list_sem.role = 23u8
        list_sem.label = label
        list_sem.states = accessibility.STATE_MODAL
        let (dialog, dialog_error) = mem.alloc[widget.Node](a, 1usize)
        if dialog_error != ok { ret (zero, TooLarge) }
        dialog[0usize] = widget.semantics(0u64, list_sem, style.defaults(), scoped[0usize..1usize])
        // The scrim is an overlay of its own under the sheet: a press on it misses
        // the modal sheet, which dismisses it.
        var dim = style.defaults()
        dim.width = style.Length { Percent: 100.0 }
        dim.height = style.Length { Percent: 100.0 }
        dim.background = paint.Brush { Solid: with_alpha(style.color(t.tokens, .Scrim), t.tokens.states.scrim) }
        let (dims, dims_error) = mem.alloc[widget.Node](a, 1usize)
        if dims_error != ok { ret (zero, TooLarge) }
        dims[0usize] = widget.box(0u64, dim, zero)
        parts[1usize] = widget.overlay(0u64, widget.Overlay { anchor: 0u64, placement: .Center, offset: zero, modal: false, dismiss: zero }, style.defaults(), dims[0usize..1usize])
        parts[2usize] = widget.overlay(key + 1u64, widget.Overlay { anchor: 0u64, placement: .Below, offset: zero, modal: true, dismiss: *toggle }, style.defaults(), dialog[0usize..1usize])
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
    let (made, made_error) = listed(a, key, t, label, options, selected, toggles, rows, width, true, true)
    ret (made, made_error)
}

// A multi-select list under its count bar (D958, docs/ux/components/MultiSelectList):
// one 1px `outline-variant` box with 12 corners, clipped, holding a bar 40 tall (48
// on touch) on `surface-container-low` that says "3 of 6 selected" in `title-small`
// `on-surface`, 16 each side, with a text button (keyed `key + 1 + options.len`)
// firing `all` -- "Select all" -- or, once every row is selected, `none` -- "Clear";
// a 1px `outline-variant` rule under it, then the rows.
fn multi_select_list_counted(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, options: []const str, selected: []const bool, toggles: []const widget.Submit, rows: u32, width: f32, all: *const widget.Submit, none: *const widget.Submit) -> (widget.Node, err) {
    let (list, list_error) = listed(a, key, t, label, options, selected, toggles, rows, width, true, false)
    if list_error != ok { ret (zero, list_error) }
    var picked = 0usize
    var i = 0usize
    while i < selected.len {
        if selected[i] { picked += 1usize }
        i += 1usize
    }
    let (said, said_error) = mem.alloc[u8](a, 64usize)
    if said_error != ok { ret (zero, TooLarge) }
    var at = write_i64(said, i64(picked))
    at += copy_text(said[at..], " of ")
    at += write_i64(said[at..], i64(options.len))
    at += copy_text(said[at..], " selected")
    var caption = text_options()
    caption.role = .TitleSmall
    caption.wrap = .None
    let (count_node, count_error) = colored_text(a, 0u64, said[0usize..at], t, caption, style.color(t.tokens, .OnSurface))
    if count_error != ok { ret (zero, count_error) }
    var plain = button_options()
    plain.variant = .Plain
    var word = "Select all"
    var action = all
    if options.len != 0usize && picked == options.len {
        word = "Clear"
        action = none
    }
    let (toggle_all, toggle_error) = button(a, key + 1u64 + u64(options.len), t, word, action, plain)
    if toggle_error != ok { ret (zero, toggle_error) }
    let (bits, bits_error) = mem.alloc[widget.Node](a, 2usize)
    if bits_error != ok { ret (zero, TooLarge) }
    bits[0usize] = count_node
    bits[1usize] = toggle_all
    var bar_height = t.tokens.sizes.control_md
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { bar_height = t.tokens.sizes.control_lg }
    var bar = style.defaults()
    bar.width = style.Length { Px: max_zero(width - 2.0) }
    bar.height = style.Length { Px: bar_height }
    bar.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    let side = style.Length { Px: 16.0 }
    let flat = style.Length { Px: 0.0 }
    bar.padding = style.EdgeLengths { left: side, top: flat, right: style.Length { Px: 4.0 }, bottom: flat }
    let (stack, stack_error) = mem.alloc[widget.Node](a, 3usize)
    if stack_error != ok { ret (zero, TooLarge) }
    stack[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 8.0 }, bar, bits[0usize..2usize])
    var rule = sized_style(max_zero(width - 2.0), t.tokens.sizes.divider)
    rule.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
    stack[1usize] = widget.box(0u64, rule, zero)
    stack[2usize] = list
    var frame = style.defaults()
    frame.width = style.Length { Px: width }
    frame.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .OutlineVariant) }
    frame.radius = t.tokens.radii.md
    frame.overflow = .Clip
    let one = style.Length { Px: 1.0 }
    frame.padding = style.EdgeLengths { left: one, top: one, right: one, bottom: one }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, frame, stack[0usize..3usize]), ok)
}

// `words` copied into the front of `out`, as much as fits; how much that was.
fn copy_text(out: []u8, words: str) -> usize {
    var i = 0usize
    while i < words.len && i < out.len {
        out[i] = words[i]
        i += 1usize
    }
    ret i
}

// ------------------------------------------ feedback and disclosure (D832, P2-04)

// A value rounded to whole digits, in the arena.
fn rounded_digits(a: *mem.Arena, value: f32) -> (str, err) {
    let (digits, digits_error) = mem.alloc[u8](a, 21usize)
    if digits_error != ok { ret (zero, TooLarge) }
    var rounded = value + 0.5
    if value < 0.0 { rounded = value - 0.5 }
    let count = write_i64(digits, i64(rounded))
    ret (digits[0usize..count], ok)
}

// A meter's state words (D970): a 16 `alert` mark in `tone` (none when `marked`
// is false) before `words` in `body-small` `on-surface-variant`.
fn status_line(a: *mem.Arena, t: *const Theme, words: str, marked: bool, tone: style.ColorRole) -> (widget.Node, err) {
    let (bits, bits_error) = mem.alloc[widget.Node](a, 2usize)
    if bits_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    if marked {
        let (mark, mark_error) = stroked_glyph(a, style.color(t.tokens, tone), .Alert, 16.0, 1.5)
        if mark_error != ok { ret (zero, mark_error) }
        bits[n] = mark
        n += 1usize
    }
    var small = text_options()
    small.role = .BodySmall
    small.wrap = .None
    let (said, said_error) = colored_text(a, 0u64, words, t, small, style.color(t.tokens, .OnSurfaceVariant))
    if said_error != ok { ret (zero, said_error) }
    bits[n] = said
    n += 1usize
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), bits[0usize..n]), ok)
}

// A gauge's thresholds and words (D970): the warning and critical shares of the
// range (1 or more: none), the unit or context under the readout, the status word
// (empty: Normal, High or Critical once there are thresholds), and the no-data and
// stale states.
type GaugeOptions = struct { warn: f32, critical: f32, unit: str, status: str, no_data: bool, stale: bool }

fn gauge_options() -> GaugeOptions {
    var out: GaugeOptions = zero
    out.warn = 2.0
    out.critical = 2.0
    ret out
}

// A gauge: the v2 look with no thresholds.
fn gauge(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, size: f32) -> (widget.Node, err) {
    let (node, node_error) = gauge_of(a, key, t, label, value, low, high, size, gauge_options())
    ret (node, node_error)
}

// v2 (D970, docs/ux/components/Gauge): a 270-degree arc open at the bottom (keyed
// `key + 1`), from lower left clockwise, its radius 40% of `size` and its stroke
// 10% with round caps: the `surface-container-highest` track, the
// `warning-container` band from the warning threshold to the maximum, and the
// value arc in `primary` -- `warning` past the warning threshold, `error` past the
// critical one; the readout inside, rounded digits in `display-small` (from 128;
// `title-large` smaller) `on-surface` over the unit in `body-small`
// `on-surface-variant`; the name in `title-small` 4 below, then the status line
// (the word, and a 16 alert mark in the status colour when not normal). No data
// draws the track alone with "-" and "No data"; stale draws the arc and readout
// in `on-surface-variant`. One progress node named `label` with the digits as its
// value and the status word as its hint; the ring is not in the tree.
// ponytail: value changes jump (no easing) and the loading skeleton is the
// caller's; the no-data readout is an ASCII hyphen.
fn gauge_of(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, size: f32, options: GaugeOptions) -> (widget.Node, err) {
    if high <= low { ret (zero, TooLarge) }
    let share = clamp_share((value - low) / (high - low))
    var tone: style.ColorRole = .Primary
    var word = "Normal"
    if share >= options.warn {
        tone = .Warning
        word = "High"
    }
    if share >= options.critical {
        tone = .Error
        word = "Critical"
    }
    let thresholds = options.warn < 1.0 || options.critical < 1.0
    var fill = style.color(t.tokens, tone)
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var ink = style.color(t.tokens, .OnSurface)
    if options.stale {
        fill = muted
        ink = muted
    }
    var ring = Ring { track: style.color(t.tokens, .SurfaceContainerHighest), fill: fill, share: share, thickness: size * 0.1, arena: a, start: 0.0 - 2.3561945, sweep: 4.712389, gap: 0.0, band: style.color(t.tokens, .WarningContainer), band_from: options.warn }
    if options.no_data { ring.share = 0.0 }
    // The stroke's centre line at 40% of the size: the ring square 90% of it.
    let (painted, painted_error) = ring_node(a, key + 1u64, ring, size * 0.9)
    if painted_error != ok { ret (zero, painted_error) }
    var shown = "-"
    if !options.no_data {
        let (digits, digits_error) = rounded_digits(a, value)
        if digits_error != ok { ret (zero, digits_error) }
        shown = digits
    }
    var big = text_options()
    big.role = .DisplaySmall
    if size < 128.0 { big.role = .TitleLarge }
    big.wrap = .None
    let (readout, readout_error) = colored_text(a, 0u64, shown, t, big, ink)
    if readout_error != ok { ret (zero, readout_error) }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 2usize)
    if inner_error != ok { ret (zero, TooLarge) }
    inner[0usize] = readout
    var inner_count = 1usize
    if options.unit.len != 0usize {
        var small = text_options()
        small.role = .BodySmall
        small.wrap = .None
        let (unit_node, unit_error) = colored_text(a, 0u64, options.unit, t, small, muted)
        if unit_error != ok { ret (zero, unit_error) }
        inner[1usize] = unit_node
        inner_count = 2usize
    }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 3usize)
    if layers_error != ok { ret (zero, TooLarge) }
    let pad = size * 0.05
    layers[2usize] = painted
    layers[0usize] = widget.padded(0u64, pad, pad, pad, pad, sized_style(size, size), layers[2usize..3usize])
    layers[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Center, gap: 0.0 }, sized_style(size, size), inner[0usize..inner_count])
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.stack(0u64, sized_style(size, size), layers[0usize..2usize])
    var count = 1usize
    if label.len != 0usize {
        var name_look = text_options()
        name_look.role = .TitleSmall
        name_look.wrap = .None
        let (name_node, name_error) = colored_text(a, 0u64, label, t, name_look, style.color(t.tokens, .OnSurface))
        if name_error != ok { ret (zero, name_error) }
        parts[count] = name_node
        count += 1usize
    }
    var status = options.status
    if status.len == 0usize && thresholds { status = word }
    if options.no_data { status = "No data" }
    if status.len != 0usize {
        let (line, line_error) = status_line(a, t, status, tone != .Primary && !options.no_data, tone)
        if line_error != ok { ret (zero, line_error) }
        parts[count] = line
        count += 1usize
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 16u8
    sem.label = label
    sem.value = shown
    sem.hint = status
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A level's words and form (D970): the value with its scale ("27 of 64 GB";
// empty: the rounded digits), the status line, the small form (4 tall, no
// header), the limit mark at the warning share, and the segmented form (2 to 5
// segments) or the bars form (rising bars) in place of the continuous bar.
type LevelOptions = struct { value_text: str, status: str, small: bool, limit: bool, segments: u32, bars: bool }

fn level_options() -> LevelOptions {
    var out: LevelOptions = zero
    ret out
}

// A level: the v2 continuous look.
fn level(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, warn: f32, danger: f32, width: f32) -> (widget.Node, err) {
    let (node, node_error) = level_of(a, key, t, label, value, low, high, warn, danger, width, level_options())
    ret (node, node_error)
}

// v2 (D970, docs/ux/components/Level): a header (the name in `label-large`, the
// value in `body-medium` `on-surface-variant` at the end) 6 above an 8 tall bar
// (4 small, no header) split into the fill (keyed `key + 1`, as long as `value`'s
// share of `low..high` and at least 4 above zero) and the
// `surface-container-highest` rest, 4 apart, both fully rounded; the fill
// `primary`, `warning` from `warn` and `error` from `danger` (shares of the
// range; 1 or more for never); the 2x16 `on-surface-variant` limit mark at
// `warn`; the status line under it, with a 16 alert mark in the status colour
// when not normal. Segmented, 32x6 segments 4 apart fill in `error`, `warning`
// or `success` as the share rises; bars, four 6 wide bars 6/10/14/18 tall. A
// progress node named `label` with the value text, the status as its hint, and
// invalid from `danger`.
// ponytail: value changes jump (no easing); segmented scales always take the
// strength colours (no neutral `primary` scale).
fn level_of(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, value: f32, low: f32, high: f32, warn: f32, danger: f32, width: f32, options: LevelOptions) -> (widget.Node, err) {
    if high <= low { ret (zero, TooLarge) }
    let share = clamp_share((value - low) / (high - low))
    var tone: style.ColorRole = .Primary
    if share >= warn { tone = .Warning }
    if share >= danger { tone = .Error }
    let rest_color = style.color(t.tokens, .SurfaceContainerHighest)
    var shown = options.value_text
    if shown.len == 0usize {
        let (digits, digits_error) = rounded_digits(a, value)
        if digits_error != ok { ret (zero, digits_error) }
        shown = digits
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var count = 0usize
    let discrete = options.segments > 0u32 || options.bars
    if !options.small && label.len != 0usize {
        let (heads, heads_error) = mem.alloc[widget.Node](a, 2usize)
        if heads_error != ok { ret (zero, TooLarge) }
        var name_look = text_options()
        name_look.role = .LabelLarge
        name_look.wrap = .None
        let (name_node, name_error) = colored_text(a, 0u64, label, t, name_look, style.color(t.tokens, .OnSurface))
        if name_error != ok { ret (zero, name_error) }
        heads[0usize] = name_node
        var head_count = 1usize
        if !discrete {
            var value_look = text_options()
            value_look.role = .BodyMedium
            value_look.wrap = .None
            let (value_node, value_error) = colored_text(a, 0u64, shown, t, value_look, style.color(t.tokens, .OnSurfaceVariant))
            if value_error != ok { ret (zero, value_error) }
            heads[1usize] = value_node
            head_count = 2usize
        }
        var head_style = style.defaults()
        head_style.width = style.Length { Px: width }
        parts[count] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 8.0 }, head_style, heads[0usize..head_count])
        count += 1usize
    }
    if discrete {
        // Segments or rising bars, lit up to the share.
        var steps = options.segments
        if options.bars { steps = 4u32 }
        if steps > 8u32 { steps = 8u32 }
        let lit = u32(share * f32(steps) + 0.5)
        var lit_tone: style.ColorRole = .Success
        if lit * 3u32 <= 2u32 * steps { lit_tone = .Warning }
        if lit * 3u32 <= steps { lit_tone = .Error }
        let (cells, cells_error) = mem.alloc[widget.Node](a, usize(steps))
        if cells_error != ok { ret (zero, TooLarge) }
        var i = 0u32
        while i < steps {
            var c = rest_color
            if i < lit { c = style.color(t.tokens, lit_tone) }
            if options.bars {
                cells[usize(i)] = bar_piece(0u64, 6.0, 6.0 + 4.0 * f32(i), c, 1.0)
            } else {
                cells[usize(i)] = bar_piece(0u64, 32.0, 6.0, c, 3.0)
            }
            i += 1u32
        }
        parts[count] = widget.flex(key + 1u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .End, gap: 4.0 }, style.defaults(), cells[0usize..usize(steps)])
        count += 1usize
    } else {
        let h: f32 = if_else(options.small, 4.0, 8.0)
        var done = share * width
        if share > 0.0 && done < 4.0 { done = 4.0 }
        let (pieces, pieces_error) = mem.alloc[widget.Node](a, 2usize)
        if pieces_error != ok { ret (zero, TooLarge) }
        var n = 0usize
        var rest = width
        if share > 0.0 {
            pieces[n] = bar_piece(key + 1u64, done, h, style.color(t.tokens, tone), h * 0.5)
            n += 1usize
            rest = width - done - 4.0
        }
        if rest > 0.0 {
            pieces[n] = bar_piece(0u64, rest, h, rest_color, h * 0.5)
            n += 1usize
        }
        let bar = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, sized_style(width, h), pieces[0usize..n])
        if options.limit && warn < 1.0 && !options.small {
            // The limit mark stands 16 tall across the bar at the warning share.
            let (marks, marks_error) = mem.alloc[widget.Node](a, 4usize)
            if marks_error != ok { ret (zero, TooLarge) }
            marks[2usize] = bar
            marks[3usize] = bar_piece(0u64, 2.0, 16.0, style.color(t.tokens, .OnSurfaceVariant), 1.0)
            marks[0usize] = widget.positioned(0u64, 0.0, 4.0, style.defaults(), marks[2usize..3usize])
            marks[1usize] = widget.positioned(0u64, warn * width - 1.0, 0.0, style.defaults(), marks[3usize..4usize])
            parts[count] = widget.stack(0u64, sized_style(width, 16.0), marks[0usize..2usize])
        } else {
            parts[count] = bar
        }
        count += 1usize
    }
    if options.status.len != 0usize && !options.small {
        let (line, line_error) = status_line(a, t, options.status, tone != .Primary, tone)
        if line_error != ok { ret (zero, line_error) }
        parts[count] = line
        count += 1usize
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 6.0 }, style.defaults(), parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 16u8
    sem.label = label
    sem.value = shown
    sem.hint = options.status
    if share >= danger { sem.states = accessibility.STATE_INVALID }
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A transient notice: its text, an optional action (an empty label for none) and
// what dismisses it. The caller keeps the queue; a snackbar or a toast shows its
// head.
type Notice = struct { text: str, action_label: str, action: widget.Submit, dismiss: widget.Submit }

// A text button in a colour of its own (D971): the label and its state layer in
// `color`, for a ground the theme's text buttons do not stand on.
fn tinted_button(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, action: *const widget.Submit, color: paint.Color) -> (widget.Node, err) {
    let state = control_state(t, key, true, false)
    var look = button_look(t, style.resolve(t.tokens, .Plain, state), true)
    look.foreground = color
    look.background = with_alpha(color, state_opacity(t, state))
    look.border_width = 0.0
    var caption = text_options()
    caption.role = .LabelLarge
    caption.wrap = .None
    let (label_node, label_error) = colored_text(a, 0u64, label, t, caption, color)
    if label_error != ok { ret (zero, label_error) }
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, true, false, action, label_node)
    ret (node, node_error)
}

// A round glyph button in a colour of its own (D971): `side` across, the glyph
// `glyph_size` and its state layer in `color`, named `label`.
fn tinted_glyph_button(a: *mem.Arena, key: widget.Key, t: *const Theme, kind: GlyphKind, label: str, action: *const widget.Submit, side: f32, glyph_size: f32, color: paint.Color) -> (widget.Node, err) {
    let state = control_state(t, key, true, false)
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = with_alpha(color, state_opacity(t, state))
    look.foreground = color
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = side * 0.5
    look.custom_padding = true
    look.padding = (side - glyph_size) * 0.5
    look.padding_y = (side - glyph_size) * 0.5
    look.min_width = side
    look.min_height = side
    let (mark, mark_error) = icon_square(a, color, kind, glyph_size)
    if mark_error != ok { ret (zero, mark_error) }
    let (node, node_error) = pressable(a, key, t, 3u8, label, look, true, false, action, mark)
    ret (node, node_error)
}

// The same with more for the tree (D972, the navigation bars' icon actions):
// disabled, the glyph in `on-surface` at 38% under no layer; further state bits,
// further actions and a controlled element as `pressable_states` takes them.
fn glyph_action(a: *mem.Arena, key: widget.Key, t: *const Theme, kind: GlyphKind, label: str, action: *const widget.Submit, side: f32, glyph_size: f32, color: paint.Color, enabled: bool, states: u32, actions: u32, controls: widget.Key) -> (widget.Node, err) {
    let state = control_state(t, key, enabled, false)
    var ink = color
    if !enabled { ink = with_alpha(style.color(t.tokens, .OnSurface), t.tokens.states.disabled_content) }
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = with_alpha(ink, state_opacity(t, state))
    if !enabled { look.background = with_alpha(ink, 0.0) }
    look.foreground = ink
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = side * 0.5
    look.custom_padding = true
    look.padding = (side - glyph_size) * 0.5
    look.padding_y = (side - glyph_size) * 0.5
    look.min_width = side
    look.min_height = side
    let (mark, mark_error) = icon_square(a, ink, kind, glyph_size)
    if mark_error != ok { ret (zero, mark_error) }
    let (node, node_error) = pressable_states(a, key, t, 3u8, label, look, enabled, false, states, actions, controls, action, mark)
    ret (node, node_error)
}

// v2 (D971, docs/ux/components/Snackbar): the head of a queue of notices as a
// non-modal overlay against the window, kept clear of its edges by transparent
// padding (the window clamp would eat an offset). The snackbar: `inverse-surface`,
// `radius-xs`, elevation 3, at least 48 tall and `width` (288 to 560) wide, 16 in
// at the start, 8 at the end and 4 vertically, the `body-medium` message in
// `inverse-on-surface`, the action a text button in `inverse-primary` (keyed
// `key + 1`) and a `close` icon button in `inverse-on-surface` named "Dismiss"
// (`key + 2`), 24 from the bottom start of the window. The toast: 340 wide (300
// at least), `surface-container-high`, `radius-md`, elevation 3, 12 vertically,
// 16 at the start and 8 at the end, a 32 info well, the message in `body-medium`
// `on-surface-variant`, its action a text button, the same close; 12 in from the
// top end. A polite status in the tree named by the text. Nothing while the queue
// is empty.
// ponytail: the compact (bottom-centre) placement, timeouts, motion, the
// two-line layout and the toast's title and severity well wait on a richer
// Notice; the toast's stack of three shows the head alone.
fn noticed(a: *mem.Arena, key: widget.Key, t: *const Theme, notices: []const Notice, width: f32, bottom: bool) -> (widget.Node, err) {
    if notices.len == 0usize { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let head = &notices[0usize]
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var at = 0usize
    var ink = style.color(t.tokens, .InverseOnSurface)
    var accent = style.color(t.tokens, .InversePrimary)
    if !bottom {
        ink = style.color(t.tokens, .OnSurfaceVariant)
        accent = style.color(t.tokens, .Primary)
        let (well, well_error) = severity_well(a, t, .Info, 32.0)
        if well_error != ok { ret (zero, well_error) }
        parts[at] = well
        at += 1usize
    }
    var caption = text_options()
    caption.role = .BodyMedium
    let (text_item, text_error) = colored_text(a, 0u64, head.text, t, caption, ink)
    if text_error != ok { ret (zero, text_error) }
    var grown = text_item
    grown.style.width = style.Length { Flex: 1.0 }
    parts[at] = grown
    at += 1usize
    if head.action_label.len != 0usize {
        let (act, act_error) = tinted_button(a, key + 1u64, t, head.action_label, &head.action, accent)
        if act_error != ok { ret (zero, act_error) }
        parts[at] = act
        at += 1usize
    }
    let (close, close_error) = tinted_glyph_button(a, key + 2u64, t, .Cross, "Dismiss", &head.dismiss, t.tokens.sizes.control_md, t.tokens.sizes.icon_md, ink)
    if close_error != ok { ret (zero, close_error) }
    parts[at] = close
    at += 1usize
    var options = surface_options(t)
    options.background = .InverseSurface
    options.radius = t.tokens.radii.xs
    options.elevation = 3u8
    var wide = width
    if wide < 288.0 { wide = 288.0 }
    if wide > 560.0 { wide = 560.0 }
    let start = style.Length { Px: 16.0 }
    let end = style.Length { Px: 8.0 }
    var pad_y = style.Length { Px: 4.0 }
    if !bottom {
        options.background = .SurfaceContainerHigh
        options.radius = t.tokens.radii.md
        wide = 340.0
        pad_y = style.Length { Px: 12.0 }
    }
    var sheet = surface_style(t, options)
    sheet.overflow = .Visible
    sheet.width = style.Length { Px: wide }
    sheet.min_height = style.Length { Px: 48.0 }
    sheet.padding = style.EdgeLengths { left: start, top: pad_y, right: end, bottom: pad_y }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, sheet, parts[0usize..at])
    var sem: widget.Semantics = zero
    sem.role = 26u8
    sem.label = head.text
    sem.live = 1u8
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.semantics(0u64, sem, style.defaults(), row[0usize..1usize])
    // The margin rides inside the overlay as padding, which the clamp keeps.
    var margin: f32 = 24.0
    if !bottom { margin = 12.0 }
    let (kept, kept_error) = mem.alloc[widget.Node](a, 1usize)
    if kept_error != ok { ret (zero, TooLarge) }
    if bottom {
        kept[0usize] = widget.padded(0u64, margin, 0.0, 0.0, margin, style.defaults(), body[0usize..1usize])
    } else {
        kept[0usize] = widget.padded(0u64, 0.0, margin, margin, 0.0, style.defaults(), body[0usize..1usize])
    }
    var placement: widget.Placement = .Right
    if bottom { placement = .Below }
    ret (widget.overlay(key, widget.Overlay { anchor: 0u64, placement: placement, offset: geometry.Point { x: 0.0, y: 0.0 }, modal: false, dismiss: zero }, style.defaults(), kept[0usize..1usize]), ok)
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

// How serious a banner is: the well it takes and how the tree announces it.
type Severity = enum u8 { Info, Success, Warning, Error }

fn severity_name(severity: Severity) -> str {
    if severity == .Success { ret "success" }
    if severity == .Warning { ret "warning" }
    if severity == .Error { ret "error" }
    ret "info"
}

// A banner's layout (D971): the optional title, the standard form (message
// block, actions in a row below) rather than the inline one-line form, and
// full-bleed (square, under a bar).
type BannerOptions = struct { title: str, standard: bool, full_bleed: bool }

fn banner_options() -> BannerOptions {
    var out: BannerOptions = zero
    ret out
}

// A banner: the v2 inline banner, its actions as text buttons keyed
// `key + 2 + index`.
fn banner(a: *mem.Arena, key: widget.Key, t: *const Theme, severity: Severity, message: str, labels: []const str, actions: []const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = noted(a, key, t, severity, message, labels, actions, width, zero, banner_options())
    ret (made, made_error)
}

// An info bar: a banner with a close button (keyed `key + 1`) firing `dismiss`.
fn info_bar(a: *mem.Arena, key: widget.Key, t: *const Theme, severity: Severity, message: str, labels: []const str, actions: []const widget.Submit, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = noted(a, key, t, severity, message, labels, actions, width, *dismiss, banner_options())
    ret (made, made_error)
}

// A banner in any layout; `dismiss` null for none.
fn banner_of(a: *mem.Arena, key: widget.Key, t: *const Theme, severity: Severity, message: str, labels: []const str, actions: []const widget.Submit, dismiss: *const widget.Submit, width: f32, options: BannerOptions) -> (widget.Node, err) {
    var closer: widget.Submit = zero
    if mem.address_of(dismiss) != 0usize { closer = *dismiss }
    let (made, made_error) = noted(a, key, t, severity, message, labels, actions, width, closer, options)
    ret (made, made_error)
}

// A 40 status well (D971): a circle in a severity's container pair with its 24
// icon -- info, check-circle, warning, error.
fn severity_well(a: *mem.Arena, t: *const Theme, severity: Severity, side: f32) -> (widget.Node, err) {
    var ground: style.ColorRole = .PrimaryContainer
    var ink: style.ColorRole = .OnPrimaryContainer
    var kind: GlyphKind = .Info
    if severity == .Success {
        ground = .SuccessContainer
        ink = .OnSuccessContainer
        kind = .CheckCircle
    }
    if severity == .Warning {
        ground = .WarningContainer
        ink = .OnWarningContainer
        kind = .Warning
    }
    if severity == .Error {
        ground = .ErrorContainer
        ink = .OnErrorContainer
        kind = .Alert
    }
    let (marks, marks_error) = mem.alloc[widget.Node](a, 1usize)
    if marks_error != ok { ret (zero, TooLarge) }
    let (mark, mark_error) = icon_square(a, style.color(t.tokens, ink), kind, side * 0.6)
    if mark_error != ok { ret (zero, mark_error) }
    marks[0usize] = mark
    var disc = sized_style(side, side)
    disc.background = paint.Brush { Solid: style.color(t.tokens, ground) }
    disc.radius = side * 0.5
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, disc, marks[0usize..1usize]), ok)
}

// v2 (D971, docs/ux/components/Banner): on `surface-container-low` for every
// severity, `radius-md` (square full-bleed), the severity carried by a 40 well in
// its status container pair with its icon, 16 before the text. Inline: one line,
// 12 top and bottom and 16 at the sides, the `body-medium` `on-surface` message
// centred on the well, then the text-button actions (keyed `key + 2 + index`) and
// the close. Standard: 16 top and sides and 8 at the foot, the `title-small`
// title over the message, the actions in a row below at the end, 8 apart. The
// close is a 40 `close` icon button in `on-surface-variant` named "Dismiss"
// (keyed `key + 1`). A polite status for info, success and warning, an assertive
// alert for an error, named by the title or the message.
// ponytail: no height animation on enter and leave.
fn noted(a: *mem.Arena, key: widget.Key, t: *const Theme, severity: Severity, message: str, labels: []const str, actions: []const widget.Submit, width: f32, dismiss: widget.Submit, options: BannerOptions) -> (widget.Node, err) {
    if labels.len != actions.len { ret (zero, TooLarge) }
    let closable = widget.submit_set(dismiss.invoke)
    let (well, well_error) = severity_well(a, t, severity, 40.0)
    if well_error != ok { ret (zero, well_error) }
    let ink = style.color(t.tokens, .OnSurface)
    var body_text = text_options()
    body_text.role = .BodyMedium
    let (text_item, text_error) = colored_text(a, 0u64, message, t, body_text, ink)
    if text_error != ok { ret (zero, text_error) }
    let (texts, texts_error) = mem.alloc[widget.Node](a, 2usize)
    if texts_error != ok { ret (zero, TooLarge) }
    var text_count = 0usize
    if options.standard && options.title.len != 0usize {
        var head = text_options()
        head.role = .TitleSmall
        let (title_node, title_error) = colored_text(a, 0u64, options.title, t, head, ink)
        if title_error != ok { ret (zero, title_error) }
        texts[0usize] = title_node
        text_count = 1usize
    }
    texts[text_count] = text_item
    text_count += 1usize
    var grow = style.defaults()
    grow.width = style.Length { Flex: 1.0 }
    if options.standard {
        let flat = style.Length { Px: 0.0 }
        grow.padding = style.EdgeLengths { left: flat, top: style.Length { Px: 10.0 }, right: flat, bottom: flat }
    }
    let words = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, grow, texts[0usize..text_count])
    let (acts, acts_error) = mem.alloc[widget.Node](a, labels.len + 1usize)
    if acts_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < labels.len {
        var plain = button_options()
        plain.variant = .Plain
        let (act, act_error) = button(a, key + 2u64 + u64(i), t, labels[i], &actions[i], plain)
        if act_error != ok { ret (zero, act_error) }
        acts[i] = act
        i += 1usize
    }
    var close: widget.Node = widget.box(0u64, style.defaults(), zero)
    if closable {
        let (closes, closes_error) = mem.alloc[widget.Submit](a, 1usize)
        if closes_error != ok { ret (zero, TooLarge) }
        closes[0usize] = dismiss
        let (made, made_error) = glyph_button(a, key + 1u64, t, .Cross, "Dismiss", &closes[0usize], t.tokens.sizes.control_md, t.tokens.sizes.icon_md)
        if made_error != ok { ret (zero, made_error) }
        close = made
    }
    let (line, line_error) = mem.alloc[widget.Node](a, labels.len + 3usize)
    if line_error != ok { ret (zero, TooLarge) }
    line[0usize] = well
    line[1usize] = words
    var n = 2usize
    var sheet = style.defaults()
    sheet.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    sheet.radius = t.tokens.radii.md
    if options.full_bleed { sheet.radius = 0.0 }
    sheet.width = style.Length { Px: width }
    let side = style.Length { Px: 16.0 }
    var row_cross: ui_layout.CrossAlign = .Center
    if options.standard { row_cross = .Start }
    if !options.standard {
        i = 0usize
        while i < labels.len {
            line[n] = acts[i]
            n += 1usize
            i += 1usize
        }
    }
    if closable {
        line[n] = close
        n += 1usize
    }
    let (rows, rows_error) = mem.alloc[widget.Node](a, 2usize)
    if rows_error != ok { ret (zero, TooLarge) }
    var full = style.defaults()
    full.width = style.Length { Percent: 100.0 }
    rows[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: row_cross, gap: 16.0 }, full, line[0usize..n])
    var row_count = 1usize
    if options.standard {
        sheet.padding = style.EdgeLengths { left: side, top: side, right: side, bottom: style.Length { Px: 8.0 } }
        if labels.len != 0usize {
            rows[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: 8.0 }, full, acts[0usize..labels.len])
            row_count = 2usize
        }
    } else {
        let tall = style.Length { Px: 12.0 }
        sheet.padding = style.EdgeLengths { left: side, top: tall, right: side, bottom: tall }
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, sheet, rows[0usize..row_count])
    var sem: widget.Semantics = zero
    sem.role = 26u8
    sem.live = 1u8
    if severity == .Error {
        sem.role = 24u8
        sem.live = 2u8
    }
    sem.label = message
    if options.title.len != 0usize { sem.label = options.title }
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A skeleton block's shape (D970): a text line, a circle, a rectangle with the
// media's radius, or a pill; `on_highest` for a block standing on
// `surface-container-highest`.
type SkeletonShape = enum u8 { Line, Circle, Rect, Pill }
type SkeletonOptions = struct { shape: SkeletonShape, radius: f32, sweep: *Sweep, on_highest: bool }

fn skeleton_options() -> SkeletonOptions {
    var out: SkeletonOptions = zero
    out.shape = .Rect
    ret out
}

// v2 (D970, docs/ux/components/Skeleton): a block in `surface-container-highest`
// (`surface-container-lowest` on a `surface-container-highest` ground): a text
// line with `radius-xs`, a circle `width` across, a rectangle with
// `options.radius`, or a pill fully rounded; carrying its region's shimmer, a
// `surface-container-high` band 40% of the region wide; not in the tree.
// ponytail: the 300 ms show delay and 500 ms minimum are the caller's timing.
fn skeleton_of(a: *mem.Arena, key: widget.Key, t: *const Theme, width: f32, height: f32, options: SkeletonOptions) -> (widget.Node, err) {
    var h = height
    var radius = options.radius
    if options.shape == .Line { radius = t.tokens.radii.xs }
    if options.shape == .Pill { radius = h * 0.5 }
    if options.shape == .Circle {
        h = width
        radius = width * 0.5
    }
    var fill = style.color(t.tokens, .SurfaceContainerHighest)
    if options.on_highest { fill = style.color(t.tokens, .SurfaceContainerLowest) }
    if mem.address_of(options.sweep) != 0usize { options.sweep.angled = true }
    let (node, node_error) = loading_shape(a, key, width, h, radius, fill, options.sweep)
    ret (node, node_error)
}

// A list row's skeleton (D970): a 72 tall row `width` wide, 16 in, with a 40
// avatar circle and two lines 16 after it -- 14 tall at 60% and 12 tall at 40% of
// the text's width, 8 apart.
fn skeleton_row(a: *mem.Arena, key: widget.Key, t: *const Theme, width: f32, sweep: *Sweep) -> (widget.Node, err) {
    var circle = skeleton_options()
    circle.shape = .Circle
    circle.sweep = sweep
    var lined = skeleton_options()
    lined.shape = .Line
    lined.sweep = sweep
    let text_width = max_zero(width - 32.0 - 56.0)
    let (avatar_node, e1) = skeleton_of(a, 0u64, t, 40.0, 40.0, circle)
    let (first, e2) = skeleton_of(a, 0u64, t, text_width * 0.6, 14.0, lined)
    let (second, e3) = skeleton_of(a, 0u64, t, text_width * 0.4, 12.0, lined)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, TooLarge) }
    let (lines, lines_error) = mem.alloc[widget.Node](a, 4usize)
    if lines_error != ok { ret (zero, TooLarge) }
    lines[2usize] = first
    lines[3usize] = second
    lines[0usize] = avatar_node
    lines[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, style.defaults(), lines[2usize..4usize])
    var row_style = sized_style(width, 72.0)
    let side = style.Length { Px: 16.0 }
    let flat = style.Length { Px: 0.0 }
    row_style.padding = style.EdgeLengths { left: side, top: flat, right: side, bottom: flat }
    ret (widget.flex(key, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 16.0 }, row_style, lines[0usize..2usize]), ok)
}

// A skeleton standing alone: a `radius-xs` rectangle `width` by `height` that is
// its own region, busy and unnamed, its shimmer at `phase` (the caller's clock, in
// radians) and still under reduced motion.
fn skeleton(a: *mem.Arena, key: widget.Key, t: *const Theme, width: f32, height: f32, phase: f32) -> (widget.Node, err) {
    let (sweep, sweep_error) = placeholder_sweep(a, t, phase / 6.2831855, width, 0.4)
    if sweep_error != ok { ret (zero, sweep_error) }
    var options = skeleton_options()
    options.radius = t.tokens.radii.xs
    options.sweep = sweep
    let (block, block_error) = skeleton_of(a, 0u64, t, width, height, options)
    if block_error != ok { ret (zero, block_error) }
    let (region, region_error) = placeholder_region(a, key, t, "", sweep, block)
    ret (region, region_error)
}

// An empty state's art and actions (D971): the glyph in the circle (`art` false
// for none), the compact form, the filled next step and the text alternative
// (empty labels for none; compact draws the first as one outlined button), and
// the view's width.
type EmptyOptions = struct { art: bool, glyph: GlyphKind, compact: bool, action_label: str, action: *const widget.Submit, other_label: str, other: *const widget.Submit, width: f32 }

fn empty_options() -> EmptyOptions {
    var out: EmptyOptions = zero
    out.art = true
    out.glyph = .Search
    out.width = 360.0
    ret out
}

// An empty state: the v2 page form with the caller's texture (a zero texture for
// none) as its art and one filled action keyed `key + 1`.
fn empty_state(a: *mem.Arena, key: widget.Key, t: *const Theme, icon_texture: scene.TextureId, title: str, message: str, action_label: str, action: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let pictured = icon_texture.slot != 0u32 || icon_texture.generation != 0u32
    var options = empty_options()
    options.art = false
    options.action_label = action_label
    options.action = action
    options.width = width
    var art: widget.Node = widget.box(0u64, style.defaults(), zero)
    if pictured { art = widget.image(0u64, widget.Image { texture: icon_texture, fit: .Contain }, sized_style(36.0, 36.0)) }
    let (node, node_error) = empty_with_art(a, key, t, title, message, options, pictured, art)
    ret (node, node_error)
}

// v2 (D971, docs/ux/components/EmptyState): a column centred in the view, at most
// 360 wide (320 compact), padded 40 top and bottom and 24 at the sides (24 and 16
// compact): the art -- a glyph `icon-lg` 36 in a 72 `secondary-container` circle,
// `on-secondary-container` (24 in 48 compact), hidden from the tree -- then 16
// below (8 compact) the title in `headline-small` (`title-medium` compact)
// `on-surface`, 8 below (4) the message in `body-medium` `on-surface-variant`, both
// centred, and 24 below (16) the filled next step (keyed `key + 1`) and the text
// alternative (`key + 2`) 8 apart -- compact, one outlined button. A group in the
// tree named by the title with the message as its hint.
// ponytail: no cross-fade on a filter change and no 10% optical raise.
fn empty_state_of(a: *mem.Arena, key: widget.Key, t: *const Theme, title: str, message: str, options: EmptyOptions) -> (widget.Node, err) {
    let side: f32 = if_else(options.compact, 24.0, 36.0)
    var tint = style.color(t.tokens, .OnSecondaryContainer)
    let (art, art_error) = icon_square(a, tint, options.glyph, side)
    if art_error != ok { ret (zero, art_error) }
    let (node, node_error) = empty_with_art(a, key, t, title, message, options, options.art, art)
    ret (node, node_error)
}

fn gap_box(height: f32) -> widget.Node {
    ret widget.box(0u64, sized_style(0.0, height), zero)
}

fn empty_with_art(a: *mem.Arena, key: widget.Key, t: *const Theme, title: str, message: str, options: EmptyOptions, pictured: bool, art: widget.Node) -> (widget.Node, err) {
    let compact = options.compact
    let (parts, parts_error) = mem.alloc[widget.Node](a, 9usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var at = 0usize
    if pictured {
        let (wells, wells_error) = mem.alloc[widget.Node](a, 1usize)
        if wells_error != ok { ret (zero, TooLarge) }
        wells[0usize] = art
        let circle = if_else(compact, 48.0, 72.0)
        var disc = sized_style(circle, circle)
        disc.background = paint.Brush { Solid: style.color(t.tokens, .SecondaryContainer) }
        disc.radius = circle * 0.5
        parts[at] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, disc, wells[0usize..1usize])
        parts[at + 1usize] = gap_box(if_else(compact, 8.0, 16.0))
        at += 2usize
    }
    var heading = text_options()
    heading.role = .HeadlineSmall
    if compact { heading.role = .TitleMedium }
    heading.align = .Center
    let (title_node, title_error) = colored_text(a, 0u64, title, t, heading, style.color(t.tokens, .OnSurface))
    if title_error != ok { ret (zero, title_error) }
    parts[at] = title_node
    parts[at + 1usize] = gap_box(if_else(compact, 4.0, 8.0))
    at += 2usize
    var body_text = text_options()
    body_text.role = .BodyMedium
    body_text.align = .Center
    body_text.max_lines = 2u32
    let (message_node, message_error) = colored_text(a, 0u64, message, t, body_text, style.color(t.tokens, .OnSurfaceVariant))
    if message_error != ok { ret (zero, message_error) }
    parts[at] = message_node
    at += 1usize
    let acts = options.action_label.len != 0usize || options.other_label.len != 0usize
    if acts {
        parts[at] = gap_box(if_else(compact, 16.0, 24.0))
        at += 1usize
        let (buttons, buttons_error) = mem.alloc[widget.Node](a, 2usize)
        if buttons_error != ok { ret (zero, TooLarge) }
        var n = 0usize
        if options.action_label.len != 0usize {
            var filled = button_options()
            if compact { filled.variant = .Outlined }
            let (act, act_error) = button(a, key + 1u64, t, options.action_label, options.action, filled)
            if act_error != ok { ret (zero, act_error) }
            buttons[n] = act
            n += 1usize
        }
        if options.other_label.len != 0usize && !compact {
            var plain = button_options()
            plain.variant = .Plain
            let (alt, alt_error) = button(a, key + 2u64, t, options.other_label, options.other, plain)
            if alt_error != ok { ret (zero, alt_error) }
            buttons[n] = alt
            n += 1usize
        }
        parts[at] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 8.0 }, style.defaults(), buttons[0usize..n])
        at += 1usize
    }
    var most: f32 = if_else(compact, 320.0, 360.0)
    if options.width < most { most = options.width }
    var column_style = style.defaults()
    column_style.width = style.Length { Px: most }
    let pad_y = style.Length { Px: if_else(compact, 24.0, 40.0) }
    let pad_x = style.Length { Px: if_else(compact, 16.0, 24.0) }
    column_style.padding = style.EdgeLengths { left: pad_x, top: pad_y, right: pad_x, bottom: pad_y }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 0.0 }, column_style, parts[0usize..at])
    let (view, view_error) = mem.alloc[widget.Node](a, 1usize)
    if view_error != ok { ret (zero, TooLarge) }
    var view_style = style.defaults()
    view_style.width = style.Length { Px: options.width }
    view[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 0.0 }, view_style, column[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = title
    sem.hint = message
    ret (widget.semantics(key, sem, style.defaults(), view[0usize..1usize]), ok)
}

// An accordion: the filled accordion of D965 below with the section at
// `expanded` open alone (an index past the end for none).
fn accordion(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, labels: []const str, contents: []const widget.Node, expanded: usize, toggles: []const widget.Submit) -> (widget.Node, err) {
    let (open, open_error) = mem.alloc[bool](a, labels.len)
    if open_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < labels.len {
        open[i] = i == expanded
        i += 1usize
    }
    let (made, made_error) = accordion_of(a, key, t, label, labels, contents, open[0usize..labels.len], toggles, accordion_options())
    ret (made, made_error)
}

// An accordion's options (D965): outlined rather than filled, the supporting
// line under each title (empty, or one per section), which sections are enabled
// (empty: all), and its width (0: its widest header's).
type AccordionOptions = struct { outlined: bool, supporting: []const str, enabled: []const bool, width: f32 }

fn accordion_options() -> AccordionOptions {
    var out: AccordionOptions = zero
    ret out
}

// Keyboard focus moved to the element keyed `key`.
type FocusTo = struct { runtime: *widget.Runtime, key: widget.Key }

fn focus_to_fire(ctx: *void) -> err {
    let f = mem.cast[*FocusTo](ctx)
    let (s, state_error) = widget.state_of(f.runtime)
    if state_error != ok { ret ok }
    let (id, count) = widget.find_by_key(s, f.key)
    if count == 0usize { ret ok }
    ret widget.focus(f.runtime, id)
}

// v2 (D965, docs/ux/components/Accordion): the sections in one container,
// `surface-container-low` (filled) or `surface` in a 1px `outline-variant` edge
// (outlined), `radius-md` 12, clipping (so a header's focus ring stands inside);
// each header the full-width section header (keyed `key + 1 + 2 * index`) 48 tall
// with a pointer and 56 on touch (16 more with a supporting line), the title in
// `body-medium` (`body-large` on touch) and the supporting line in `body-small`
// (`body-medium`), the open content below it (`key + 2 + 2 * index`) 16 in at the
// sides and below, and 1px `outline-variant` dividers between sections. `open`
// says which are open, so one index or a set; each header fires its own toggle.
// Up and Down move focus between headers, Home and End to the first and last.
// A Group named `label`.
// ponytail: no motion, no leading icons and no error summary in a shut header.
fn accordion_of(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, labels: []const str, contents: []const widget.Node, open: []const bool, toggles: []const widget.Submit, options: AccordionOptions) -> (widget.Node, err) {
    let n = labels.len
    if contents.len != n || toggles.len != n || open.len != n { ret (zero, TooLarge) }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var h = t.tokens.sizes.control_lg
    var title_role: style.TextRole = .BodyMedium
    var line_role: style.TextRole = .BodySmall
    if touch {
        h = t.tokens.sizes.control_xl
        title_role = .BodyLarge
        line_role = .BodyMedium
    }
    let (targets, targets_error) = mem.alloc[FocusTo](a, n + 2usize)
    if targets_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < n {
        targets[i] = FocusTo { runtime: t.runtime, key: key + 1u64 + 2u64 * u64(i) }
        i += 1usize
    }
    let (items, items_error) = mem.alloc[widget.Node](a, 3usize * n)
    if items_error != ok { ret (zero, TooLarge) }
    var count = 0usize
    i = 0usize
    while i < n {
        let header_key = key + 1u64 + 2u64 * u64(i)
        var supporting: str = ""
        if options.supporting.len == n { supporting = options.supporting[i] }
        var enabled = true
        if options.enabled.len == n { enabled = options.enabled[i] }
        if i > 0usize {
            var line = style.defaults()
            line.height = style.Length { Px: t.tokens.sizes.divider }
            if options.width > 0.0 { line.width = style.Length { Px: options.width } }
            line.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
            items[count] = widget.box(0u64, line, zero)
            count += 1usize
        }
        let (header, header_error) = section_header(a, header_key, t, labels[i], supporting, open[i], enabled, &toggles[i], options.width, h, title_role, line_role)
        if header_error != ok { ret (zero, header_error) }
        // Up, Down, Home and End from this header.
        let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 4usize)
        if shortcuts_error != ok { ret (zero, TooLarge) }
        var previous = i
        if i > 0usize { previous = i - 1usize }
        var next = i
        if i + 1usize < n { next = i + 1usize }
        shortcuts[0usize] = widget.Shortcut { key: 38u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&targets[previous]), invoke: focus_to_fire } }
        shortcuts[1usize] = widget.Shortcut { key: 40u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&targets[next]), invoke: focus_to_fire } }
        shortcuts[2usize] = widget.Shortcut { key: 36u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&targets[0usize]), invoke: focus_to_fire } }
        shortcuts[3usize] = widget.Shortcut { key: 35u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&targets[n - 1usize]), invoke: focus_to_fire } }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = header
        items[count] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..4usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), held[0usize..1usize])
        count += 1usize
        if open[i] {
            let (inner, inner_error) = section_body(a, header_key + 1u64, header_key, contents[i])
            if inner_error != ok { ret (zero, inner_error) }
            items[count] = inner
            count += 1usize
        }
        i += 1usize
    }
    var sheet = style.defaults()
    sheet.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    if options.outlined {
        sheet.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
        sheet.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .OutlineVariant) }
    }
    sheet.radius = t.tokens.radii.md
    sheet.overflow = .Clip
    if options.width > 0.0 { sheet.width = style.Length { Px: options.width } }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, sheet, items[0usize..count])
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

// A font panel (D961) over the caller's catalogue: the families as a list (keyed
// `key + 1`, its rows `key + 2 + index`, `rows` tall), the family's styles as a
// picker (`key + 64`, open while `styles_open`, its menu `key + 65` and its rows
// after) firing `toggle_styles`, the size as a spin box (`key + 80`, its arrows
// `key + 81` and `key + 82`) over the caller's `size_buffer`, 1 to 288, and a
// preview of `sample` (keyed `key + 84`), and a search field (`key + 85`) over the
// caller's `search` text reaching `searched` -- the caller filters `families`;
// the panel box is `key`. A `family` past
// the end reads as the first. A group in the tree named `label` whose value is
// the picked family.
// v2 (D961, docs/ux/components/FontPicker, inline panel): `surface-container-low`,
// `radius-md` 12, 16 padding, two columns 16 apart; the family list column 260 on
// `surface` with `radius-sm` corners, its rows the list box's 40 rows, the chosen
// one `secondary-container` with its trailing check; "Family", "Style" and "Size"
// drawn in `label-medium` `on-surface-variant` 4 above their parts; style and size
// at pointer density -1 (the dense 40 Picker, and the dense Spin box 104 wide);
// the preview on `surface` in a 1px `outline-variant` edge with `radius-sm`
// corners, 12 above and below and 16 at the sides, at least 88 tall, the sample in
// `body-large` over the caption "Preview, <size> pt" in `label-small`
// `on-surface-variant`.
// The search is the outlined field 40 tall with an 18 `search` mark 12 in, 16
// above the family label.
// ponytail: no subheaders, recent families, feature chips, trigger or sheet; the picker is its least 112 wide, not 160; rows are in the theme's face -- a field per family's face waits on the caller's fonts.
fn font_panel(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, families: []const str, family: usize, styles: []const str, style_index: usize, styles_open: bool, toggle_styles: *const widget.Submit, size: i64, size_buffer: []u8, sample: str, pick_family: widget.Change[usize], pick_style: widget.Change[usize], change_size: widget.Change[i64], typed_size: widget.Change[str], search: []u8, search_len: usize, searched: widget.Change[str], rows: u32, width: f32) -> (widget.Node, err) {
    if families.len == 0usize || styles.len == 0usize { ret (zero, TooLarge) }
    var picked = family
    if picked >= families.len { picked = 0usize }
    let (family_actions, family_error) = chosen_actions(a, families.len, pick_family)
    if family_error != ok { ret (zero, family_error) }
    let (style_actions, style_error) = chosen_actions(a, styles.len, pick_style)
    if style_error != ok { ret (zero, style_error) }
    // Style and size at density -1: a copy of the theme whose controls are 24 + 16.
    let (dense_tokens, dense_error) = mem.alloc[style.ThemeTokens](a, 1usize)
    if dense_error != ok { ret (zero, TooLarge) }
    dense_tokens[0usize] = *t.tokens
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    if !touch { dense_tokens[0usize].metrics.control_height = t.tokens.sizes.control_xs }
    let (themes, themes_error) = mem.alloc[Theme](a, 1usize)
    if themes_error != ok { ret (zero, TooLarge) }
    themes[0usize] = *t
    themes[0usize].tokens = &dense_tokens[0usize]
    let dense = &themes[0usize]
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var heading = text_options()
    heading.role = .LabelMedium
    heading.wrap = .None
    let (parts, parts_error) = mem.alloc[widget.Node](a, 12usize)
    if parts_error != ok { ret (zero, TooLarge) }
    // The family column: its label over the list on `surface`.
    let (family_label, family_label_error) = colored_text(a, 0u64, "Family", t, heading, muted)
    if family_label_error != ok { ret (zero, family_label_error) }
    let (chosen_rows, chosen_error) = mem.alloc[bool](a, families.len)
    if chosen_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < families.len {
        chosen_rows[i] = i == picked
        i += 1usize
    }
    let (list, list_error) = listed(a, key + 1u64, t, "Family", families, chosen_rows, family_actions, rows, 262.0, false, false)
    if list_error != ok { ret (zero, list_error) }
    parts[0usize] = list
    var list_frame = style.defaults()
    list_frame.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    list_frame.radius = t.tokens.radii.sm
    list_frame.overflow = .Clip
    // The search: the outlined field 40 tall and 260 wide, its 18 `search` mark 12
    // in, in `on-surface-variant`, and the query 12 after it.
    var query = field_options()
    query.width = 260.0
    query.height = t.tokens.sizes.control_md
    query.placeholder = "Search fonts"
    query.start_space = 12.0 + t.tokens.sizes.icon_sm + 12.0 - 16.0
    if t.tokens.metrics.control_height < t.tokens.sizes.control_sm { query.start_space = 12.0 + t.tokens.sizes.icon_sm }
    let (query_field, query_error) = text_field(a, key + 85u64, t, "", search, search_len, searched, zero, query)
    if query_error != ok { ret (zero, query_error) }
    let (lens, lens_error) = mark_glyph(a, muted, .Search, t.tokens.sizes.icon_sm)
    if lens_error != ok { ret (zero, lens_error) }
    let (searching, searching_error) = mem.alloc[widget.Node](a, 3usize)
    if searching_error != ok { ret (zero, TooLarge) }
    searching[0usize] = query_field
    searching[2usize] = lens
    searching[1usize] = widget.positioned(0u64, 12.0, max_zero((query.height - t.tokens.sizes.icon_sm) * 0.5), style.defaults(), searching[2usize..3usize])
    var search_sem: widget.Semantics = zero
    search_sem.role = 2u8
    search_sem.label = "Search fonts"
    let (searched_parts, searched_error) = mem.alloc[widget.Node](a, 1usize)
    if searched_error != ok { ret (zero, TooLarge) }
    searched_parts[0usize] = widget.stack(0u64, style.defaults(), searching[0usize..2usize])
    let (column_parts, column_parts_error) = mem.alloc[widget.Node](a, 4usize)
    if column_parts_error != ok { ret (zero, TooLarge) }
    column_parts[2usize] = family_label
    column_parts[3usize] = widget.box(0u64, list_frame, parts[0usize..1usize])
    column_parts[0usize] = widget.semantics(0u64, search_sem, style.defaults(), searched_parts[0usize..1usize])
    // The label 16 under the search, 4 above the list.
    column_parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, style.defaults(), column_parts[2usize..4usize])
    parts[3usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, style.defaults(), column_parts[0usize..2usize])
    // The style and size, each under its label.
    let (style_label, style_label_error) = colored_text(a, 0u64, "Style", t, heading, muted)
    if style_label_error != ok { ret (zero, style_label_error) }
    let (faces, faces_error) = picker(a, key + 64u64, dense, "Style", styles, style_index, styles_open, toggle_styles, style_actions, .Popup)
    if faces_error != ok { ret (zero, faces_error) }
    let (size_label, size_label_error) = colored_text(a, 0u64, "Size", t, heading, muted)
    if size_label_error != ok { ret (zero, size_label_error) }
    let (sized, sized_error) = spin_box_sized(a, key + 80u64, dense, "Size", size_buffer, size, 1i64, 288i64, 1i64, change_size, typed_size, 104.0)
    if sized_error != ok { ret (zero, sized_error) }
    let (labelled_parts, labelled_error) = mem.alloc[widget.Node](a, 4usize)
    if labelled_error != ok { ret (zero, TooLarge) }
    labelled_parts[0usize] = style_label
    labelled_parts[1usize] = faces
    labelled_parts[2usize] = size_label
    labelled_parts[3usize] = sized
    parts[4usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, style.defaults(), labelled_parts[0usize..2usize])
    parts[5usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, style.defaults(), labelled_parts[2usize..4usize])
    // The preview: the sample over its caption.
    var sample_words = text_options()
    sample_words.role = .BodyLarge
    sample_words.wrap = .None
    sample_words.ellipsis = "..."
    sample_words.max_lines = 1u32
    let (sample_node, sample_error) = colored_text(a, 0u64, sample, t, sample_words, style.color(t.tokens, .OnSurface))
    if sample_error != ok { ret (zero, sample_error) }
    let (caption_text, caption_error) = mem.alloc[u8](a, 40usize)
    if caption_error != ok { ret (zero, TooLarge) }
    var caption_len = copy_text(caption_text, "Preview, ")
    caption_len += write_i64(caption_text[caption_len..40usize], size)
    caption_len += copy_text(caption_text[caption_len..40usize], " pt")
    var small = text_options()
    small.role = .LabelSmall
    small.wrap = .None
    let (caption_node, caption_node_error) = colored_text(a, 0u64, caption_text[0usize..caption_len], t, small, muted)
    if caption_node_error != ok { ret (zero, caption_node_error) }
    parts[6usize] = sample_node
    parts[7usize] = caption_node
    let right_width = max_zero(width - 32.0 - 260.0 - 16.0)
    var preview_style = style.defaults()
    preview_style.width = style.Length { Px: right_width }
    preview_style.min_height = style.Length { Px: 88.0 }
    preview_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    preview_style.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .OutlineVariant) }
    preview_style.radius = t.tokens.radii.sm
    let side = style.Length { Px: 16.0 }
    let edge = style.Length { Px: 12.0 }
    preview_style.padding = style.EdgeLengths { left: side, top: edge, right: side, bottom: edge }
    parts[8usize] = widget.flex(key + 84u64, ui_layout.Flex { axis: .Vertical, main: .SpaceBetween, cross: .Start, gap: 4.0 }, preview_style, parts[6usize..8usize])
    parts[9usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, style.defaults(), parts[4usize..6usize])
    let (right, right_error) = mem.alloc[widget.Node](a, 2usize)
    if right_error != ok { ret (zero, TooLarge) }
    right[0usize] = parts[9usize]
    right[1usize] = parts[8usize]
    parts[10usize] = parts[3usize]
    parts[11usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, style.defaults(), right[0usize..2usize])
    var panel_options = surface_options(t)
    panel_options.background = .SurfaceContainerLow
    panel_options.radius = t.tokens.radii.md
    panel_options.padding = 16.0
    var panel_style = surface_style(t, panel_options)
    panel_style.width = style.Length { Px: width }
    panel_style.overflow = .Visible
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(key, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 16.0 }, panel_style, parts[10usize..12usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    sem.value = families[picked]
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A notification in the list (D971): its title, message and time, its severity,
// whether it is unread, the day group it belongs to (a header shows where the
// group changes; empty for none), an optional action (an empty label for none)
// and what dismisses it.
type NotificationItem = struct { title: str, message: str, time: str, severity: Severity, unread: bool, group: str, action_label: str, action: widget.Submit, dismiss: widget.Submit }

// A notification list of D832's notices: each notice a read item titled by its
// text, Mark all read (keyed `key + 1`) firing `clear`.
fn notification_list(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, notices: []const Notice, clear: *const widget.Submit, width: f32, height: f32) -> (widget.Node, err) {
    if notices.len > 64usize { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[NotificationItem](a, notices.len)
    if items_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < notices.len {
        var item: NotificationItem = zero
        item.title = notices[i].text
        item.severity = .Info
        item.action_label = notices[i].action_label
        item.action = notices[i].action
        item.dismiss = notices[i].dismiss
        items[i] = item
        i += 1usize
    }
    let (node, node_error) = notification_list_of(a, key, t, label, items[0usize..notices.len], clear, width, height)
    ret (node, node_error)
}

// Whether two texts hold the same bytes.
fn same_text(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// "<head>, <tail>" in the arena, or `tail` alone when `head` is empty.
fn joined(a: *mem.Arena, head: str, tail: str) -> (str, err) {
    if head.len == 0usize { ret (tail, ok) }
    let (made, made_error) = badge_name(a, head, tail)
    ret (made, made_error)
}

// v2 (D971, docs/ux/components/NotificationList): a panel `width` wide on
// `surface-container-low`, `radius-md`, clipping: a 56 header (16 in at the start,
// 8 at the end) with `label` in `title-medium` and a Mark all read text button
// (keyed `key + 1`) firing `mark_read`, a 1px `outline-variant` line under it,
// then the rows in a viewport (keyed `key`) filling the rest of `height`. A day
// group's header in `label-medium` `on-surface-variant` (8 over, 16 at the sides,
// 4 under) stands where the group changes. A row (keyed `key + 2 + 3 * index`) is
// at least 72 tall, 12 over and under, 16 in at the start and 8 at the end, 12
// between: a 40 severity well, the title (`title-small` unread, `body-medium`
// read) in `on-surface`, the message in `body-medium` and the time in
// `body-small`, both `on-surface-variant`, a small text-button action (`key + 3 +
// 3 * index`) under them, an 8 `primary` dot when unread, and a 32 `close` icon
// button named "Dismiss" (`key + 4 + 3 * index`). Empty, the compact empty state
// "You're all caught up". A polite group in the tree named `label` with the
// unread count ("Notifications, 2 unread"); each row a list item named by its
// title, "Unread, " first when unread.
// Up, Down, Home and End move focus between rows, skipping day headings; Delete
// fires that row's existing dismiss action. (D1220) With a pointer the Dismiss
// button is built only while its row or the button is hovered or focused (a 32
// space holds its place otherwise); on touch it always shows.
// ponytail: no settings button, grouping of repeats, loading rows or insert
// motion.
fn notification_list_of(a: *mem.Arena, key: widget.Key, t: *const Theme, label: str, items: []const NotificationItem, mark_read: *const widget.Submit, width: f32, height: f32) -> (widget.Node, err) {
    if items.len > 64usize { ret (zero, TooLarge) }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let ink = style.color(t.tokens, .OnSurface)
    let inner = max_zero(width - 2.0)
    let (rows, rows_error) = mem.alloc[widget.Node](a, 2usize * items.len + 1usize)
    if rows_error != ok { ret (zero, TooLarge) }
    let (targets, targets_error) = mem.alloc[FocusTo](a, items.len)
    if targets_error != ok { ret (zero, TooLarge) }
    let (row_shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 5usize * items.len)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    var target_index = 0usize
    while target_index < items.len {
        targets[target_index] = FocusTo { runtime: t.runtime, key: key + 2u64 + 3u64 * u64(target_index) }
        target_index += 1usize
    }
    var n = 0usize
    var unread = 0usize
    var i = 0usize
    while i < items.len {
        let item = &items[i]
        if item.unread { unread += 1usize }
        let starts = item.group.len != 0usize && (i == 0usize || !same_text(item.group, items[i - 1usize].group))
        if starts {
            var head = text_options()
            head.role = .LabelMedium
            head.wrap = .None
            let (group_node, group_error) = colored_text(a, 0u64, item.group, t, head, muted)
            if group_error != ok { ret (zero, group_error) }
            let (heads, heads_error) = mem.alloc[widget.Node](a, 1usize)
            if heads_error != ok { ret (zero, TooLarge) }
            heads[0usize] = group_node
            rows[n] = widget.padded(0u64, 16.0, 8.0, 16.0, 4.0, style.defaults(), heads[0usize..1usize])
            n += 1usize
        }
        let (well, well_error) = severity_well(a, t, item.severity, 40.0)
        if well_error != ok { ret (zero, well_error) }
        let (lines, lines_error) = mem.alloc[widget.Node](a, 4usize)
        if lines_error != ok { ret (zero, TooLarge) }
        var line_count = 0usize
        var title_look = text_options()
        title_look.role = .BodyMedium
        if item.unread { title_look.role = .TitleSmall }
        let (title_node, title_error) = colored_text(a, 0u64, item.title, t, title_look, ink)
        if title_error != ok { ret (zero, title_error) }
        lines[line_count] = title_node
        line_count += 1usize
        if item.message.len != 0usize {
            var said = text_options()
            said.role = .BodyMedium
            said.max_lines = 2u32
            let (said_node, said_error) = colored_text(a, 0u64, item.message, t, said, muted)
            if said_error != ok { ret (zero, said_error) }
            lines[line_count] = said_node
            line_count += 1usize
        }
        if item.time.len != 0usize {
            var stamp = text_options()
            stamp.role = .BodySmall
            stamp.wrap = .None
            let (when_node, when_error) = colored_text(a, 0u64, item.time, t, stamp, muted)
            if when_error != ok { ret (zero, when_error) }
            lines[line_count] = when_node
            line_count += 1usize
        }
        if item.action_label.len != 0usize {
            var plain = button_options()
            plain.variant = .Plain
            let (act, act_error) = button(a, key + 3u64 + 3u64 * u64(i), t, item.action_label, &item.action, plain)
            if act_error != ok { ret (zero, act_error) }
            lines[line_count] = act
            line_count += 1usize
        }
        let (cells, cells_error) = mem.alloc[widget.Node](a, 4usize)
        if cells_error != ok { ret (zero, TooLarge) }
        cells[0usize] = well
        var grow = style.defaults()
        grow.width = style.Length { Flex: 1.0 }
        cells[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, grow, lines[0usize..line_count])
        var cell_count = 2usize
        if item.unread {
            var dot = sized_style(8.0, 8.0)
            dot.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
            dot.radius = 4.0
            cells[cell_count] = widget.box(0u64, dot, zero)
            cell_count += 1usize
        }
        let close_key = key + 4u64 + 3u64 * u64(i)
        let row_state = control_state(t, targets[i].key, true, false)
        let close_state = control_state(t, close_key, true, false)
        let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
        if touch || row_state.hovered || row_state.focused || close_state.hovered || close_state.focused {
            let (close, close_error) = glyph_button(a, close_key, t, .Cross, "Dismiss", &item.dismiss, 32.0, 18.0)
            if close_error != ok { ret (zero, close_error) }
            cells[cell_count] = close
        } else {
            cells[cell_count] = widget.box(0u64, sized_style(32.0, 32.0), zero)
        }
        cell_count += 1usize
        var row_style = style.defaults()
        row_style.width = style.Length { Px: inner }
        row_style.min_height = style.Length { Px: 72.0 }
        let edge = style.Length { Px: 12.0 }
        row_style.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: edge, right: style.Length { Px: 8.0 }, bottom: edge }
        let (lined, lined_error) = mem.alloc[widget.Node](a, 1usize)
        if lined_error != ok { ret (zero, TooLarge) }
        lined[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 12.0 }, row_style, cells[0usize..cell_count])
        var entry: widget.Semantics = zero
        entry.role = 11u8
        let (described, described_error) = joined(a, severity_name(item.severity), item.title)
        if described_error != ok { ret (zero, described_error) }
        entry.label = described
        if item.unread {
            let (named, named_error) = joined(a, "Unread", described)
            if named_error != ok { ret (zero, named_error) }
            entry.label = named
        }
        entry.hint = item.message
        entry.row = u32(i + 1usize)
        entry.row_count = u32(items.len)
        let (named, named_error) = mem.alloc[widget.Node](a, 1usize)
        if named_error != ok { ret (zero, TooLarge) }
        named[0usize] = widget.semantics(0u64, entry, style.defaults(), lined[0usize..1usize])
        var previous = i
        if i > 0usize { previous = i - 1usize }
        var next = i
        if i + 1usize < items.len { next = i + 1usize }
        let base = 5usize * i
        row_shortcuts[base] = widget.Shortcut { key: 38u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&targets[previous]), invoke: focus_to_fire } }
        row_shortcuts[base + 1usize] = widget.Shortcut { key: 40u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&targets[next]), invoke: focus_to_fire } }
        row_shortcuts[base + 2usize] = widget.Shortcut { key: 36u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&targets[0usize]), invoke: focus_to_fire } }
        row_shortcuts[base + 3usize] = widget.Shortcut { key: 35u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&targets[items.len - 1usize]), invoke: focus_to_fire } }
        row_shortcuts[base + 4usize] = widget.Shortcut { key: 46u32, modifiers: zero, action: item.dismiss }
        let (focused, focused_error) = mem.alloc[widget.Node](a, 1usize)
        if focused_error != ok { ret (zero, TooLarge) }
        var none_gesture: widget.GestureAction = zero
        var focus_style = style.defaults()
        focus_style.radius = t.tokens.radii.sm
        focus_look(t)
        focused[0usize] = widget.region(targets[i].key, widget.Region { gesture: none_gesture, gestures: 4u8, enabled: true, focusable: true }, focus_style, named[0usize..1usize])
        rows[n] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: row_shortcuts[base..base + 5usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), focused[0usize..1usize])
        n += 1usize
        i += 1usize
    }
    if items.len == 0usize {
        var calm = empty_options()
        calm.compact = true
        calm.glyph = .CheckCircle
        calm.width = inner
        let (empty_node, empty_error) = empty_state_of(a, 0u64, t, "You're all caught up", "New notifications appear here.", calm)
        if empty_error != ok { ret (zero, empty_error) }
        rows[n] = empty_node
        n += 1usize
    }
    var view_style = style.defaults()
    view_style.width = style.Length { Px: inner }
    view_style.height = style.Length { Px: max_zero(height - 2.0 - 56.0 - t.tokens.sizes.divider) }
    view_style.overflow = .Clip
    let (view, view_error) = widget.scroll_view(a, key, .Vertical, view_style, rows[0usize..n])
    if view_error != ok { ret (zero, TooLarge) }
    // The header bar.
    var title_look = text_options()
    title_look.role = .TitleMedium
    title_look.wrap = .None
    let (title_node, title_error) = colored_text(a, 0u64, label, t, title_look, ink)
    if title_error != ok { ret (zero, title_error) }
    var plain = button_options()
    plain.variant = .Plain
    plain.enabled = unread > 0usize || items.len > 0usize
    let (marked, marked_error) = button(a, key + 1u64, t, "Mark all read", mark_read, plain)
    if marked_error != ok { ret (zero, marked_error) }
    let (bits, bits_error) = mem.alloc[widget.Node](a, 2usize)
    if bits_error != ok { ret (zero, TooLarge) }
    bits[0usize] = title_node
    bits[1usize] = marked
    var bar = sized_style(inner, 56.0)
    let flat = style.Length { Px: 0.0 }
    bar.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: flat, right: style.Length { Px: 8.0 }, bottom: flat }
    let (stack, stack_error) = mem.alloc[widget.Node](a, 3usize)
    if stack_error != ok { ret (zero, TooLarge) }
    stack[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 8.0 }, bar, bits[0usize..2usize])
    var rule = sized_style(inner, t.tokens.sizes.divider)
    rule.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
    stack[1usize] = widget.box(0u64, rule, zero)
    stack[2usize] = view
    var frame_style = style.defaults()
    frame_style.width = style.Length { Px: width }
    frame_style.height = style.Length { Px: height }
    frame_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    frame_style.radius = t.tokens.radii.md
    frame_style.overflow = .Clip
    let one = style.Length { Px: 1.0 }
    frame_style.padding = style.EdgeLengths { left: one, top: one, right: one, bottom: one }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, frame_style, stack[0usize..3usize])
    var sem: widget.Semantics = zero
    sem.role = accessibility.ROLE_REGION
    sem.label = label
    if unread > 0usize {
        let (counted, counted_error) = mem.alloc[u8](a, 24usize)
        if counted_error != ok { ret (zero, TooLarge) }
        let digits = write_i64(counted, i64(unread))
        let tail = copy_text(counted[digits..counted.len], " unread")
        let (named, named_error) = joined(a, label, counted[0usize..digits + tail])
        if named_error != ok { ret (zero, named_error) }
        sem.label = named
    }
    sem.live = 1u8
    sem.row_count = u32(items.len)
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}
