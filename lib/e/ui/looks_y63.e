// Round 63, lane y: navigation shapes of the Windows, Linux and Cupertino looks (and their darks): the destination rows of the
// sidebar and the drawer, the compact rail and the bottom bar. Windows follows Fluent NavigationView / CommandBar (a 40 px row,
// 4 px radius, a 3 x 16 accent indicator), Linux libadwaita 1.5 (.navigation-sidebar rows, GtkActionBar), Cupertino the AppKit
// source list (accent selection) and the UIToolbar. Metrics are the platforms' public values, derived, not measured on a screen.
// Neper and Material keep the Material 3 shapes in navigation.e.

use e.gfx.paint
use e.mem
use e.ui.accessibility
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

type Item = struct { label: str, glyph: control.GlyphKind, pictured: bool, badge: str, dot: bool, section: str }
type Act = struct { label: str, action: *const widget.Submit, enabled: bool }

fn owns(t: *const control.Theme) -> bool {
    let p = t.tokens.profile
    ret p == .Windows || p == .Linux || p == .CupertinoLike
}

fn ink(t: *const control.Theme) -> paint.Color { ret style.color(t.tokens, .OnSurface) }

// The ring of a keyboard-focused row: 2 px, the primary (Windows: the text colour, as WinUI's black ring).
fn ring_color(t: *const control.Theme) -> paint.Color {
    if t.tokens.profile == .Windows { ret style.color(t.tokens, .OnSurface) }
    ret style.color(t.tokens, .Primary)
}

// Not-focusable copy of a pressable (a roving tab stop keeps one row focusable).
fn untab(a: *mem.Arena, node: widget.Node) -> (widget.Node, err) {
    if node.children.len != 1usize { ret (node, ok) }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = node.children[0usize]
    switch inner[0usize].kind {
    case .Region as region:
        var untabbed = region
        untabbed.focusable = false
        inner[0usize].kind = widget.Kind { Region: untabbed }
    default:
        ret (node, ok)
    }
    var out = node
    out.children = inner[0usize..1usize]
    ret (out, ok)
}

fn kid(a: *mem.Arena, node: widget.Node) -> []widget.Node {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret zero }
    held[0usize] = node
    ret held
}

fn one(a: *mem.Arena, node: widget.Node) -> ([]widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = node
    ret (held, ok)
}

// A pressable box with its own fill: the row, the bar button.
fn surface(a: *mem.Arena, key: widget.Key, t: *const control.Theme, role: u8, label: str, state: style.ControlState, enabled: bool, selected: bool, states: u32, fill: paint.Color, fg: paint.Color, radius: f32, width: f32, height: f32, action: *const widget.Submit, content: widget.Node) -> (widget.Node, err) {
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = fill
    look.foreground = fg
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = radius
    look.custom_padding = true
    look.padding = 0.0
    look.padding_y = 0.0
    look.min_height = height
    look.min_width = width
    if state.focus_visible && enabled {
        look.border_width = 2.0
        look.border = ring_color(t)
    }
    let (node, node_error) = control.pressable_states(a, key, t, role, label, look, enabled, selected, states, 0u32, 0u64, action, content)
    ret (node, node_error)
}

fn caption_options(role: style.TextRole) -> control.TextOptions {
    var o = control.text_options()
    o.role = role
    o.wrap = .None
    o.ellipsis = "..."
    o.max_lines = 1u32
    ret o
}

// ------------------------------------------------------------------ sidebar and drawer rows

type Shape = struct { height: f32, radius: f32, side: f32, gap: f32, icon: f32, hover: f32, chosen: f32, pressed: f32 }

fn shape(t: *const control.Theme) -> Shape {
    if t.tokens.profile == .Windows { ret Shape { height: 40.0, radius: 4.0, side: 16.0, gap: 2.0, icon: 16.0, hover: 0.06, chosen: 0.04, pressed: 0.04 } }
    if t.tokens.profile == .Linux { ret Shape { height: 36.0, radius: 6.0, side: 12.0, gap: 2.0, icon: 16.0, hover: 0.07, chosen: 0.10, pressed: 0.16 } }
    ret Shape { height: 30.0, radius: 6.0, side: 10.0, gap: 2.0, icon: 16.0, hover: 0.0, chosen: 1.0, pressed: 0.0 }
}

// The destinations as source-list / sidebar rows `width` wide, `first + index` keyed; a section starts with its heading (and, on
// Windows and Linux, a divider). The tab stop keeps the roving focus of navigation.destination_rows.
fn rows(a: *mem.Arena, first: widget.Key, t: *const control.Theme, items: []const Item, selected: usize, picks: []const widget.Submit, tab_stop: usize, width: f32) -> ([]widget.Node, err) {
    let sh = shape(t)
    let (out, out_error) = mem.alloc[widget.Node](a, 3usize * items.len)
    if out_error != ok { ret (zero, out_error) }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let mac = t.tokens.profile == .CupertinoLike
    var n = 0usize
    var i = 0usize
    while i < items.len {
        let item = &items[i]
        if item.section.len > 0usize {
            if n > 0usize && !mac {
                var line = style.defaults()
                line.width = style.Length { Percent: 100.0 }
                line.height = style.Length { Px: t.tokens.sizes.divider }
                line.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
                let (lines, lines_error) = one(a, widget.box(0u64, line, zero))
                if lines_error != ok { ret (zero, lines_error) }
                var ruled = style.defaults()
                ruled.width = style.Length { Px: width }
                out[n] = widget.padded(0u64, 0.0, 6.0, 0.0, 4.0, ruled, lines)
                n += 1usize
            }
            var role: style.TextRole = .BodySmall
            if mac { role = .Caption }
            let (said, said_error) = control.colored_text(a, 0u64, item.section, t, caption_options(role), muted)
            if said_error != ok { ret (zero, said_error) }
            let (held, held_error) = one(a, said)
            if held_error != ok { ret (zero, held_error) }
            var head_sem: widget.Semantics = zero
            head_sem.role = 25u8
            head_sem.label = item.section
            head_sem.level = 2u8
            let (heads, heads_error) = one(a, widget.padded(0u64, sh.side, 12.0, sh.side, 4.0, style.defaults(), held))
            if heads_error != ok { ret (zero, heads_error) }
            out[n] = widget.semantics(0u64, head_sem, style.defaults(), heads)
            n += 1usize
        }
        let chosen = i == selected
        let row_key = first + u64(i)
        let state = control.control_state(t, row_key, true, chosen)
        var text_ink = ink(t)
        var icon_ink = text_ink
        var fill = control.with_alpha(ink(t), 0.0)
        if mac {
            icon_ink = style.color(t.tokens, .Primary)
            if chosen {
                text_ink = style.color(t.tokens, .OnPrimary)
                icon_ink = text_ink
                fill = style.color(t.tokens, .Primary)
                if state.pressed { fill = style.layer(fill, style.color(t.tokens, .Scrim), 0.18) }
            }
        } else {
            var alpha: f32 = 0.0
            if chosen { alpha = sh.chosen }
            if state.hovered { alpha = sh.hover }
            if chosen && state.hovered { alpha = sh.hover + 0.03 }
            if state.pressed { alpha = sh.pressed }
            if state.pressed && t.tokens.profile == .Linux { alpha = sh.pressed }
            fill = control.with_alpha(ink(t), alpha)
        }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
        if parts_error != ok { ret (zero, parts_error) }
        var p = 0usize
        if item.pictured {
            let (icon, icon_error) = control.icon_square(a, icon_ink, item.glyph, sh.icon)
            if icon_error != ok { ret (zero, icon_error) }
            parts[p] = icon
            p += 1usize
        }
        let (label_node, label_error) = control.colored_text(a, 0u64, item.label, t, caption_options(.BodyMedium), text_ink)
        if label_error != ok { ret (zero, label_error) }
        parts[p] = label_node
        p += 1usize
        parts[p] = widget.spacer(0u64, 1.0)
        p += 1usize
        if item.badge.len > 0usize && !item.dot {
            let (count_node, count_error) = control.colored_text(a, 0u64, item.badge, t, caption_options(.BodyMedium), text_ink)
            if count_error != ok { ret (zero, count_error) }
            parts[p] = count_node
            p += 1usize
        }
        var line_style = style.defaults()
        line_style.width = style.Length { Px: control.max_zero(width - 2.0 * sh.side) }
        line_style.height = style.Length { Px: sh.height }
        let flow = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, line_style, parts[0usize..p])
        var content = flow
        if t.tokens.profile == .Windows {
            // The NavigationView indicator: 3 x 16, primary, 0 from the row's edge, on the selected row only.
            let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
            if layers_error != ok { ret (zero, layers_error) }
            layers[0usize] = widget.padded(0u64, sh.side, 0.0, sh.side, 0.0, style.defaults(), kid(a, flow))
            var bar = control.sized_style(3.0, 16.0)
            bar.radius = 1.5
            bar.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
            var count = 1usize
            if chosen {
                layers[1usize] = widget.positioned(0u64, 0.0, (sh.height - 16.0) * 0.5, style.defaults(), kid(a, widget.box(0u64, bar, zero)))
                count = 2usize
            }
            content = widget.stack(0u64, control.sized_style(width, sh.height), layers[0usize..count])
        } else {
            content = widget.padded(0u64, sh.side, 0.0, sh.side, 0.0, style.defaults(), kid(a, flow))
        }
        var states = 0u32
        if chosen { states = accessibility.STATE_CURRENT }
        let (row, row_error) = surface(a, row_key, t, 19u8, item.label, state, true, chosen, states, fill, text_ink, sh.radius, width, sh.height, &picks[i], content)
        if row_error != ok { ret (zero, row_error) }
        var placed = row
        if tab_stop < items.len && i != tab_stop {
            let (untabbed, untabbed_error) = untab(a, row)
            if untabbed_error != ok { ret (zero, untabbed_error) }
            placed = untabbed
        }
        let (spaced, spaced_error) = one(a, placed)
        if spaced_error != ok { ret (zero, spaced_error) }
        out[n] = widget.padded(0u64, 0.0, sh.gap * 0.5, 0.0, sh.gap * 0.5, style.defaults(), spaced)
        n += 1usize
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// ------------------------------------------------------------------ rail

fn rail_glyph(i: usize) -> control.GlyphKind {
    if i == 0usize { ret .Calendar }
    if i == 1usize { ret .Search }
    if i == 2usize { ret .Clock }
    if i == 3usize { ret .Person }
    ret .Settings
}

// The compact rail. Windows: the NavigationView compact pane, 48 wide, icon-only 40 x 40 items with the indicator. Linux and
// Cupertino: a narrow sidebar, a 16 (20) icon over a 11 px label in a rounded item; Linux selects with the 10 % wash, Cupertino
// tints the icon, label and a 12 % wash with the accent. Destinations without a picture get a generic glyph.
fn rail(a: *mem.Arena, first: widget.Key, t: *const control.Theme, items: []const Item, selected: usize, picks: []const widget.Submit, tab_stop: usize, extent: f32) -> (widget.Node, err) {
    let win = t.tokens.profile == .Windows
    let mac = t.tokens.profile == .CupertinoLike
    var width = extent
    if win { width = 48.0 }
    var item_w = width - 12.0
    var item_h: f32 = 56.0
    if win {
        item_w = 40.0
        item_h = 40.0
    }
    let (cells, cells_error) = mem.alloc[widget.Node](a, items.len)
    if cells_error != ok { ret (zero, cells_error) }
    var i = 0usize
    while i < items.len {
        let item = &items[i]
        let chosen = i == selected
        let key = first + u64(i)
        let state = control.control_state(t, key, true, chosen)
        var text_ink = ink(t)
        if !win { text_ink = style.color(t.tokens, .OnSurfaceVariant) }
        var fill = control.with_alpha(ink(t), 0.0)
        var alpha: f32 = 0.0
        if win {
            if chosen { alpha = 0.04 }
            if state.hovered { alpha = 0.06 }
            if state.pressed { alpha = 0.04 }
            fill = control.with_alpha(ink(t), alpha)
        } else if mac {
            if chosen {
                text_ink = style.color(t.tokens, .Primary)
                alpha = 0.12
            }
            if state.pressed { alpha = 0.2 }
            fill = control.with_alpha(style.color(t.tokens, .Primary), alpha)
        } else {
            if chosen { text_ink = ink(t) }
            if chosen { alpha = 0.10 }
            if state.hovered { alpha = 0.07 }
            if chosen && state.hovered { alpha = 0.13 }
            if state.pressed { alpha = 0.16 }
            fill = control.with_alpha(ink(t), alpha)
        }
        var glyph = item.glyph
        if !item.pictured { glyph = rail_glyph(i) }
        var icon_size: f32 = 16.0
        if mac { icon_size = 20.0 }
        let (icon, icon_error) = control.icon_square(a, text_ink, glyph, icon_size)
        if icon_error != ok { ret (zero, icon_error) }
        var content = icon
        var radius: f32 = 4.0
        if !win {
            let (said, said_error) = control.colored_text(a, 0u64, item.label, t, caption_options(.LabelSmall), text_ink)
            if said_error != ok { ret (zero, said_error) }
            let (stack, stack_error) = mem.alloc[widget.Node](a, 2usize)
            if stack_error != ok { ret (zero, stack_error) }
            stack[0usize] = icon
            stack[1usize] = said
            content = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Center, gap: 4.0 }, control.sized_style(item_w, item_h), stack[0usize..2usize])
            radius = 6.0
            if mac { radius = 8.0 }
        } else {
            content = widget.aligned(0u64, .Center, .Center, control.sized_style(item_w, item_h), kid(a, icon))
            if chosen {
                let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
                if layers_error != ok { ret (zero, layers_error) }
                var bar = control.sized_style(3.0, 16.0)
                bar.radius = 1.5
                bar.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
                layers[0usize] = content
                layers[1usize] = widget.positioned(0u64, 0.0, (item_h - 16.0) * 0.5, style.defaults(), kid(a, widget.box(0u64, bar, zero)))
                content = widget.stack(0u64, control.sized_style(item_w, item_h), layers[0usize..2usize])
            }
        }
        var states = 0u32
        if chosen { states = accessibility.STATE_CURRENT }
        let (cell, cell_error) = surface(a, key, t, 19u8, item.label, state, true, chosen, states, fill, text_ink, radius, item_w, item_h, &picks[i], content)
        if cell_error != ok { ret (zero, cell_error) }
        var placed = cell
        if i != tab_stop {
            let (untabbed, untabbed_error) = untab(a, cell)
            if untabbed_error != ok { ret (zero, untabbed_error) }
            placed = untabbed
        }
        cells[i] = placed
        i += 1usize
    }
    var column = style.defaults()
    column.width = style.Length { Px: width }
    column.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    let flat = style.Length { Px: 0.0 }
    column.padding = style.EdgeLengths { left: flat, top: style.Length { Px: 8.0 }, right: flat, bottom: flat }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 2.0 }, column, cells[0usize..items.len]), ok)
}

// ------------------------------------------------------------------ bottom bar

// A bar button: the label alone. `solid` fills with the accent (Windows accent button, GNOME suggested-action); `plain` is the
// flat button (a wash on hover and press) or, on Cupertino, accent text that dims while pressed.
fn bar_button(a: *mem.Arena, key: widget.Key, t: *const control.Theme, act: *const Act, solid: bool, radius: f32, height: f32, side: f32, hover: f32, press: f32) -> (widget.Node, err) {
    let state = control.control_state(t, key, act.enabled, false)
    let mac = t.tokens.profile == .CupertinoLike
    var text_ink = ink(t)
    var fill = control.with_alpha(ink(t), 0.0)
    if mac { text_ink = style.color(t.tokens, .Primary) }
    if solid {
        text_ink = style.color(t.tokens, .OnPrimary)
        fill = style.color(t.tokens, .Primary)
        if state.hovered { fill = style.layer(fill, text_ink, 0.08) }
        if state.pressed { fill = style.layer(fill, style.color(t.tokens, .Scrim), 0.18) }
    } else {
        var alpha: f32 = 0.0
        if state.hovered { alpha = hover }
        if state.pressed { alpha = press }
        if !mac { fill = control.with_alpha(ink(t), alpha) }
        if mac && state.pressed { text_ink = control.with_alpha(text_ink, 0.35) }
    }
    if !act.enabled { text_ink = control.with_alpha(ink(t), 0.38) }
    let (said, said_error) = control.colored_text(a, 0u64, act.label, t, caption_options(.BodyMedium), text_ink)
    if said_error != ok { ret (zero, said_error) }
    let (held, held_error) = one(a, said)
    if held_error != ok { ret (zero, held_error) }
    var look_h = height
    if mac { look_h = 44.0 }
    var line = style.defaults()
    line.height = style.Length { Px: look_h }
    let middle = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, line, held)
    let centred = widget.padded(0u64, side, 0.0, side, 0.0, style.defaults(), kid(a, middle))
    let (node, node_error) = surface(a, key, t, 3u8, act.label, state, act.enabled, false, 0u32, fill, text_ink, radius, 0.0, look_h, act.action, centred)
    ret (node, node_error)
}

// The bottom bar: Windows 11 CommandBar (48 tall, flat commands, the main command an accent button, all on the right), GNOME
// GtkActionBar (46 tall, flat commands at the start, the main one suggested-action at the end), iOS UIToolbar (44 tall, accent
// text items spaced across the bar). A 1 px divider runs along the top edge; the Windows bar's commands are right aligned.
fn bottom_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, acts: []const Act, fab: Act, width: f32) -> (widget.Node, err) {
    let win = t.tokens.profile == .Windows
    let mac = t.tokens.profile == .CupertinoLike
    var height: f32 = 46.0
    if win { height = 48.0 }
    if mac { height = 44.0 }
    var radius: f32 = 6.0
    if win { radius = 4.0 }
    var button_h: f32 = 34.0
    if win { button_h = 32.0 }
    var hover: f32 = 0.08
    var press: f32 = 0.16
    if win {
        hover = 0.06
        press = 0.04
    }
    // GNOME: a bar too narrow for its buttons would shrink them and leave each label hugging one edge, so the side padding gives
    // way instead (equal on both sides, whole pixels).
    var trim: f32 = 0.0
    if t.tokens.profile == .Linux {
        var natural: f32 = 0.0
        var buttons = acts.len
        var w = 0usize
        while w < acts.len {
            let (said_w, said_w_error) = control.linux_label_width(a, t, caption_options(.BodyMedium), acts[w].label)
            if said_w_error != ok { ret (zero, said_w_error) }
            natural += said_w + 24.0
            w += 1usize
        }
        if fab.label.len > 0usize {
            let (said_f, said_f_error) = control.linux_label_width(a, t, caption_options(.BodyMedium), fab.label)
            if said_f_error != ok { ret (zero, said_f_error) }
            natural += said_f + 32.0
            buttons += 1usize
        }
        let over = natural + 4.0 * f32(buttons - 1usize) - (width - 16.0) + 1.0
        if buttons > 0usize && over > 0.0 {
            trim = f32(u32(over / f32(2usize * buttons))) + 1.0
            if trim > 8.0 { trim = 8.0 }
        }
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize * acts.len + 4usize)
    if parts_error != ok { ret (zero, parts_error) }
    var n = 0usize
    if win {
        parts[n] = widget.spacer(0u64, 1.0)
        n += 1usize
    }
    var i = 0usize
    while i < acts.len {
        if mac && i > 0usize {
            parts[n] = widget.spacer(0u64, 1.0)
            n += 1usize
        }
        let (button, button_error) = bar_button(a, key + 1u64 + u64(i), t, &acts[i], false, radius, button_h, 12.0 - trim, hover, press)
        if button_error != ok { ret (zero, button_error) }
        parts[n] = button
        n += 1usize
        i += 1usize
    }
    if fab.label.len > 0usize {
        if !win {
            parts[n] = widget.spacer(0u64, 1.0)
            n += 1usize
        }
        let (main, main_error) = bar_button(a, key + 9u64, t, &fab, !mac, radius, button_h, 16.0 - trim, hover, press)
        if main_error != ok { ret (zero, main_error) }
        parts[n] = main
        n += 1usize
    }
    var side: f32 = 8.0
    if mac { side = 16.0 }
    var row_style = control.sized_style(width, height - t.tokens.sizes.divider)
    let flat = style.Length { Px: 0.0 }
    row_style.padding = style.EdgeLengths { left: style.Length { Px: side }, top: flat, right: style.Length { Px: side }, bottom: flat }
    var gap: f32 = 4.0
    if mac { gap = 0.0 }
    let row = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: gap }, row_style, parts[0usize..n])
    var line = control.sized_style(width, t.tokens.sizes.divider)
    line.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
    let (stack, stack_error) = mem.alloc[widget.Node](a, 2usize)
    if stack_error != ok { ret (zero, stack_error) }
    stack[0usize] = widget.box(0u64, line, zero)
    stack[1usize] = row
    var bar = control.sized_style(width, height)
    bar.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainer) }
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), kid(a, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, bar, stack[0usize..2usize]))), ok)
}

// Sheet helper: `node` centred in a `w` x `h` frame, so the harness's focus drive (a click at the frame's centre, then Tab and
// Shift+Tab) lands on the middle destination, the only one that holds a roving tab stop.
fn framed_center(a: *mem.Arena, key: widget.Key, w: f32, h: f32, node: widget.Node) -> (widget.Node, err) {
    ret (widget.aligned(key, .Start, .Center, control.sized_style(w, h), kid(a, node)), ok)
}
