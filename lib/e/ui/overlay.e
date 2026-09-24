// Transient UI over the widget tree (D827, widget plan P1-14): a tooltip beside
// what it explains, a menu of commands under its anchor, an alert dialog in the
// middle of the window. Every one is D810's overlay placed by a control function
// under `control.Theme`, present in the tree only while the caller says so -- the
// caller keeps `shown` and `open` the way it keeps every other value (D807) -- and
// keyed so the harness and the tree can find it.

use e.mem
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.ui.accessibility
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

error TooLarge

// Whether a tooltip for `anchor` is wanted now: the anchor hovered and not held,
// or focused from the keyboard.
// v2 (D975, docs/ux/components/Tooltip): hover waits 500 ms, the next anchor in
// a 1500 ms toolbar sweep shows at once, a press hides it, and keyboard focus
// shows it at once; touch uses a 500 ms long press and remains 1500 ms after release.
fn tooltip_wanted(t: *const control.Theme, anchor: widget.Key) -> bool {
    if mem.address_of(t.runtime) == 0usize { ret false }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    ret widget.tooltip_wanted(t.runtime, anchor, touch)
}

// Whether a rich tooltip is wanted after its initial hover delay and while the
// pointer or focus crosses between its anchor and interactive surface.
fn rich_tooltip_wanted(t: *const control.Theme, anchor: widget.Key, tooltip_key: widget.Key) -> bool {
    if mem.address_of(t.runtime) == 0usize { ret false }
    ret widget.rich_tooltip_wanted(t.runtime, anchor, tooltip_key)
}

// A tooltip: `text` beside `anchor`, keyed `key`, placed only while `shown` (an
// empty box otherwise); the overlay sets the anchor's `described_by`. The plain
// tooltip of D975 below.
fn tooltip(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, text: str, shown: bool) -> (widget.Node, err) {
    let (made, made_error) = tooltip_of(a, key, t, anchor, text, "", shown)
    ret (made, made_error)
}

// v2 (D975, docs/ux/components/Tooltip, plain): `inverse-surface`, `radius-xs`, no
// border or shadow, at least 24 tall and at most 200 wide, 4 above and below and
// 8 at the sides; the text in `body-small` `inverse-on-surface`, wrapping to two
// lines, then the `shortcut` (empty for none) in the same 8 after it. Centred
// above the anchor, 4 from it, flipping below when there is no room above; a
// non-modal overlay that presses pass through.
fn tooltip_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, text: str, shortcut: str, shown: bool) -> (widget.Node, err) {
    if !shown { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let ink = style.color(t.tokens, .InverseOnSurface)
    var caption = control.text_options()
    caption.role = .BodySmall
    caption.wrap = .Word
    caption.max_lines = 2u32
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (label_node, label_error) = control.colored_text(a, 0u64, text, t, caption, ink)
    if label_error != ok { ret (zero, label_error) }
    parts[0usize] = label_node
    var n = 1usize
    if shortcut.len > 0usize {
        caption.wrap = .None
        let (keys_node, keys_error) = control.colored_text(a, 0u64, shortcut, t, caption, ink)
        if keys_error != ok { ret (zero, keys_error) }
        parts[1usize] = keys_node
        n = 2usize
    }
    var plate = style.defaults()
    plate.background = paint.Brush { Solid: style.color(t.tokens, .InverseSurface) }
    plate.radius = t.tokens.radii.xs
    plate.min_height = style.Length { Px: 24.0 }
    plate.max_width = style.Length { Px: 200.0 }
    let sides = style.Length { Px: 8.0 }
    let ends = style.Length { Px: 4.0 }
    plate.padding = style.EdgeLengths { left: sides, top: ends, right: sides, bottom: ends }
    let (surface, surface_error) = mem.alloc[widget.Node](a, 1usize)
    if surface_error != ok { ret (zero, TooLarge) }
    surface[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, plate, parts[0usize..n])
    var sem: widget.Semantics = zero
    sem.role = 27u8
    sem.label = text
    let (tip, tip_error) = mem.alloc[widget.Node](a, 1usize)
    if tip_error != ok { ret (zero, TooLarge) }
    tip[0usize] = widget.semantics(0u64, sem, style.defaults(), surface[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: .AboveCenter, offset: geometry.Point { x: 0.0, y: -4.0 }, modal: false, dismiss: zero }, style.defaults(), tip[0usize..1usize]), ok)
}

// v2 (D975, docs/ux/components/Tooltip, rich): `surface-container`, `radius-md`,
// elevation 2, at least 48 tall and at most 312 wide, 12 above, 16 at the sides
// and 8 below; the `subhead` (empty for none) in `title-small` `on-surface` 4
// above the `body-medium` `on-surface-variant` text (up to four lines), then up to
// two text buttons (keyed `key + 1 + index`) 8 below it and 8 apart. Below the
// anchor, its end aligned with the anchor's, 4 from it, flipping above; a
// non-modal overlay, a tooltip in the tree named by the subhead (or the text).
fn rich_tooltip(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, subhead: str, text: str, actions: []const MenuItem, shown: bool) -> (widget.Node, err) {
    if !shown { ret (widget.box(0u64, style.defaults(), zero), ok) }
    if actions.len > 2usize { ret (zero, TooLarge) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    var words = control.text_options()
    if subhead.len > 0usize {
        words.role = .TitleSmall
        words.wrap = .Word
        let (head, head_error) = control.colored_text(a, 0u64, subhead, t, words, style.color(t.tokens, .OnSurface))
        if head_error != ok { ret (zero, head_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = head
        parts[n] = widget.padded(0u64, 0.0, 0.0, 0.0, 4.0, style.defaults(), held[0usize..1usize])
        n += 1usize
    }
    words.role = .BodyMedium
    words.wrap = .Word
    words.max_lines = 4u32
    let (body, body_error) = control.colored_text(a, 0u64, text, t, words, style.color(t.tokens, .OnSurfaceVariant))
    if body_error != ok { ret (zero, body_error) }
    parts[n] = body
    n += 1usize
    if actions.len > 0usize {
        let (buttons, buttons_error) = mem.alloc[widget.Node](a, actions.len)
        if buttons_error != ok { ret (zero, TooLarge) }
        var i = 0usize
        while i < actions.len {
            let action_key = key + 1u64 + u64(i)
            let state = control.control_state(t, action_key, actions[i].enabled, false)
            var look = style.resolve(t.tokens, .Plain, state)
            look.radius = 20.0
            look.custom_padding = true
            look.padding = 12.0
            look.padding_y = control.max_zero((40.0 - style.text_style(t.tokens, .Label).line_height) * 0.5)
            look.min_height = 40.0
            look.min_width = 24.0
            var caption = control.text_options()
            caption.role = .Label
            caption.wrap = .None
            let (said, said_error) = control.colored_text(a, 0u64, actions[i].label, t, caption, look.foreground)
            if said_error != ok { ret (zero, said_error) }
            let (pressed, pressed_error) = control.pressable(a, action_key, t, 3u8, actions[i].label, look, actions[i].enabled, false, &actions[i].action, said)
            if pressed_error != ok { ret (zero, pressed_error) }
            buttons[i] = pressed
            i += 1usize
        }
        let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
        if row_error != ok { ret (zero, TooLarge) }
        row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, style.defaults(), buttons[0usize..actions.len])
        parts[n] = widget.padded(0u64, 0.0, 8.0, 0.0, 0.0, style.defaults(), row[0usize..1usize])
        n += 1usize
    }
    var raised = control.surface_options(t)
    raised.background = .SurfaceContainer
    raised.elevation = 2u8
    raised.radius = t.tokens.radii.md
    raised.padding = 16.0
    var plate = control.surface_style(t, raised)
    plate.padding.top = style.Length { Px: 12.0 }
    plate.padding.bottom = style.Length { Px: 8.0 }
    plate.min_height = style.Length { Px: 48.0 }
    plate.max_width = style.Length { Px: 312.0 }
    let (surface, surface_error) = mem.alloc[widget.Node](a, 1usize)
    if surface_error != ok { ret (zero, TooLarge) }
    surface[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, plate, parts[0usize..n])
    var sem: widget.Semantics = zero
    sem.role = 27u8
    sem.label = subhead
    if subhead.len == 0usize { sem.label = text }
    let (tip, tip_error) = mem.alloc[widget.Node](a, 1usize)
    if tip_error != ok { ret (zero, TooLarge) }
    tip[0usize] = widget.semantics(0u64, sem, style.defaults(), surface[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: .BelowEnd, offset: geometry.Point { x: 0.0, y: 4.0 }, modal: false, dismiss: zero }, style.defaults(), tip[0usize..1usize]), ok)
}

// A command in a menu: its label, what it does, and whether it may be chosen.
type MenuItem = struct { label: str, action: widget.Submit, enabled: bool }

// A command in a v2 menu (D975): its label, what it does, whether it may be
// chosen, its shortcut's words ("Ctrl+S"; empty for none, never shown on touch),
// whether it is checkable and checked (a check in the leading slot), a radio
// choice (a 6px dot), or has a leading glyph; its optional supporting line;
// whether a separator stands before it, whether it destroys (in `error`), the
// head of the group it starts, and its optional first-level submenu.
type MenuCommand = struct { label: str, supporting: str, action: widget.Submit, enabled: bool, shortcut: str, checkable: bool, checked: bool, radio: bool, pictured: bool, glyph: control.GlyphKind, separated: bool, destructive: bool, head: str, submenu: []const MenuCommand, submenu_open: bool, submenu_toggle: widget.Submit }

// A plain enabled command.
fn menu_command(label: str, action: widget.Submit) -> MenuCommand {
    var c: MenuCommand = zero
    c.label = label
    c.action = action
    c.enabled = true
    ret c
}

fn menu_radio_dot(a: *mem.Arena, color: paint.Color, slot: f32) -> (widget.Node, err) {
    let (marks, marks_error) = mem.alloc[widget.Node](a, 1usize)
    if marks_error != ok { ret (zero, TooLarge) }
    var dot = control.sized_style(6.0, 6.0)
    dot.background = paint.Brush { Solid: color }
    dot.radius = 3.0
    marks[0usize] = widget.box(0u64, dot, zero)
    let inset = (slot - 6.0) * 0.5
    ret (widget.padded(0u64, inset, inset, inset, inset, style.defaults(), marks[0usize..1usize]), ok)
}

// A menu: a modal overlay below `anchor` of the items keyed `key + 1 + index`,
// placed only while `open`; a press outside it or Escape fires `dismiss`. The
// items outlive the frame. The v2 menu of D975 below over plain commands.
fn menu(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, label: str, items: []const MenuItem, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (commands, commands_error) = mem.alloc[MenuCommand](a, items.len)
    if commands_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < items.len {
        commands[i] = menu_command(items[i].label, items[i].action)
        commands[i].enabled = items[i].enabled
        i += 1usize
    }
    let (made, made_error) = menu_of(a, key, t, anchor, label, commands[0usize..items.len], open, dismiss)
    ret (made, made_error)
}

// v2 (D975, docs/ux/components/Menu): the menu 4 below its anchor (flipping
// above), its commands keyed `key + 1 + index`; submenu overlays use `key +
// 1024 + 16 * index` and their commands continue from that key.
fn menu_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, label: str, commands: []const MenuCommand, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    let rim = control.if_else(touch, 8.0, 4.0)
    let (made, made_error) = menu_at(a, key, t, anchor, label, commands, open, dismiss, .Below, geometry.Point { x: 0.0, y: 4.0 }, rim, true)
    ret (made, made_error)
}

fn menu_at(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, label: str, commands: []const MenuCommand, open: bool, dismiss: *const widget.Submit, placement: widget.Placement, offset: geometry.Point, rim: f32, allow_submenus: bool) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (panel, panel_error) = menu_panel(a, key, t, label, commands, dismiss, rim, allow_submenus, "", 0u64, dismiss)
    if panel_error != ok { ret (zero, panel_error) }
    let (lifted, lifted_error) = mem.alloc[widget.Node](a, 1usize)
    if lifted_error != ok { ret (zero, TooLarge) }
    lifted[0usize] = panel
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: placement, offset: offset, modal: true, dismiss: *dismiss }, style.defaults(), lifted[0usize..1usize]), ok)
}

// v2 (D975, docs/ux/components/ContextMenu): the menu for `owner` with its
// top-start corner at the pointer `at` (+2, +2 in the window), flipping to the
// pointer's start or above it where it would overflow; or, opened from the
// keyboard (`pointed` false), below `owner` at its start edge. 8 above and below
// its commands at either density; the commands keyed `key + 1 + index` and
// submenu overlays following `menu_of`'s key scheme. Touch uses
// `context_target` and `context_menu_touch_of` below.
fn context_menu_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, owner: widget.Key, label: str, commands: []const MenuCommand, open: bool, dismiss: *const widget.Submit, at: geometry.Point, pointed: bool) -> (widget.Node, err) {
    var anchor = owner
    var placement: widget.Placement = .Below
    var offset: geometry.Point = zero
    if pointed {
        anchor = 0u64
        placement = .At
        offset = geometry.Point { x: at.x + 2.0, y: at.y + 2.0 }
    }
    let (made, made_error) = menu_at(a, key, t, anchor, label, commands, open, dismiss, placement, offset, 8.0, true)
    ret (made, made_error)
}

fn context_show(ctx: *void, action: u32) -> err {
    if action != accessibility.ACTION_SHOW_MENU { ret ok }
    let show = mem.cast[*const widget.Submit](ctx)
    ret widget.fire_submit(*show)
}

fn context_hold(ctx: *void, gesture: widget.Gesture) -> err {
    ret ok
}

// A target that owns a context menu. It exposes Show menu and Controls, reports
// its open state, and on touch asks the shared runtime for the 500 ms long press.
// `content` supplies the target itself and `show` outlives the element.
fn context_target(a: *mem.Arena, key: widget.Key, t: *const control.Theme, role: accessibility.Role, label: str, menu_key: widget.Key, open: bool, show: *const widget.Submit, content: widget.Node) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    if touch && mem.address_of(t.runtime) != 0usize {
        let press_error = widget.long_press(t.runtime, key, show)
        if press_error != ok { ret (zero, press_error) }
    }
    var plate = style.defaults()
    if open {
        plate.background = paint.Brush { Solid: style.color(t.tokens, .SecondaryContainer) }
        if touch {
            plate.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLowest) }
            plate.radius = t.tokens.radii.md
            plate.shadow = style.Shadow { offset: geometry.Point { x: 0.0, y: 3.0 }, color: paint.rgba(0.0, 0.0, 0.0, t.tokens.elevation[3usize]) }
        }
    }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    inner[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: zero, invoke: context_hold }, gestures: 1u8 | 4u8, enabled: true, focusable: false }, plate, body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = accessibility.role_code(role)
    sem.label = label
    sem.actions = accessibility.ACTION_SHOW_MENU
    sem.controls = menu_key
    sem.on_action = widget.Change[u32] { ctx: mem.cast[*void](show), invoke: context_show }
    if open { sem.states = accessibility.STATE_SELECTED | accessibility.STATE_EXPANDED }
    ret (widget.semantics(0u64, sem, style.defaults(), inner[0usize..1usize]), ok)
}

fn context_scrim_piece(t: *const control.Theme, width: f32, height: f32) -> widget.Node {
    var dim = style.defaults()
    dim.width = style.Length { Px: width }
    dim.height = style.Length { Px: height }
    dim.background = paint.Brush { Solid: control.with_alpha(style.color(t.tokens, .Scrim), t.tokens.states.scrim) }
    ret widget.box(0u64, dim, zero)
}

// Four scrim rectangles leave the target and its 4px shadow exposed, so the
// in-layout target itself is the lifted preview without duplicating keyed nodes.
fn context_scrim_around(a: *mem.Arena, t: *const control.Theme, owner: widget.Key, top: widget.Node) -> (widget.Node, err) {
    if mem.address_of(t.runtime) == 0usize {
        let (made, made_error) = with_scrim(a, t, top)
        ret (made, made_error)
    }
    let (owner_bounds, has_target) = widget.bounds_for_key(t.runtime, owner)
    let surface = widget.surface_size(t.runtime)
    if !has_target || surface.width <= 0.0 || surface.height <= 0.0 {
        let (made, made_error) = with_scrim(a, t, top)
        ret (made, made_error)
    }
    var left = owner_bounds.x - 4.0
    var top_at = owner_bounds.y - 4.0
    var right = owner_bounds.x + owner_bounds.width + 4.0
    var bottom = owner_bounds.y + owner_bounds.height + 4.0
    if left < 0.0 { left = 0.0 }
    if top_at < 0.0 { top_at = 0.0 }
    if right > surface.width { right = surface.width }
    if bottom > surface.height { bottom = surface.height }
    let (pieces, pieces_error) = mem.alloc[widget.Node](a, 4usize)
    if pieces_error != ok { ret (zero, TooLarge) }
    pieces[0usize] = context_scrim_piece(t, surface.width, top_at)
    pieces[1usize] = context_scrim_piece(t, left, bottom - top_at)
    pieces[2usize] = context_scrim_piece(t, surface.width - right, bottom - top_at)
    pieces[3usize] = context_scrim_piece(t, surface.width, surface.height - bottom)
    let (layers, layers_error) = mem.alloc[widget.Node](a, 5usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[0usize] = widget.overlay(0u64, widget.Overlay { anchor: 0u64, placement: .At, offset: zero, modal: false, dismiss: zero }, style.defaults(), pieces[0usize..1usize])
    layers[1usize] = widget.overlay(0u64, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: 0.0, y: top_at }, modal: false, dismiss: zero }, style.defaults(), pieces[1usize..2usize])
    layers[2usize] = widget.overlay(0u64, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: right, y: top_at }, modal: false, dismiss: zero }, style.defaults(), pieces[2usize..3usize])
    layers[3usize] = widget.overlay(0u64, widget.Overlay { anchor: 0u64, placement: .At, offset: geometry.Point { x: 0.0, y: bottom }, modal: false, dismiss: zero }, style.defaults(), pieces[3usize..4usize])
    layers[4usize] = top
    ret (widget.box(0u64, style.defaults(), layers[0usize..5usize]), ok)
}

// Touch context menu: 8 below its lifted target, under the target-preserving
// scrim. The target's `show` action normally toggles `open` on long press.
// Hosts may install `widget.set_long_press_feedback` for the boundary tick.
fn context_menu_touch_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, owner: widget.Key, label: str, commands: []const MenuCommand, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (floating, menu_error) = menu_at(a, key, t, owner, label, commands, true, dismiss, .Below, geometry.Point { x: 0.0, y: 8.0 }, 8.0, true)
    if menu_error != ok { ret (zero, menu_error) }
    let (made, made_error) = context_scrim_around(a, t, owner, floating)
    ret (made, made_error)
}

// One command of a v2 menu (D975), keyed `item_key`, as `menu_panel` draws it.
fn menu_row_of(a: *mem.Arena, item_key: widget.Key, submenu_key: widget.Key, t: *const control.Theme, c: *const MenuCommand, slotted: bool) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var row_height = control.if_else(touch, 48.0, 32.0)
    if c.supporting.len > 0usize { row_height = control.if_else(touch, 56.0, 48.0) }
    let slot = control.if_else(touch, 24.0, 18.0)
    let gap = control.if_else(touch, 12.0, 8.0)
    var role: style.TextRole = .BodyMedium
    if touch { role = .BodyLarge }
    let line = style.text_style(t.tokens, role).line_height
    let surface_ink = style.color(t.tokens, .OnSurface)
    var state = control.control_state(t, item_key, c.enabled, false)
    if c.submenu_open { state.hovered = true }
    var ink = surface_ink
    if c.destructive { ink = style.color(t.tokens, .Error) }
    var muted = style.color(t.tokens, .OnSurfaceVariant)
    var mark_ink = surface_ink
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = control.with_alpha(surface_ink, control.state_opacity(t, state))
    if !c.enabled {
        ink = control.with_alpha(surface_ink, t.tokens.states.disabled_content)
        muted = ink
        mark_ink = ink
        look.background = control.with_alpha(ink, 0.0)
    }
    look.foreground = ink
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = 0.0
    look.custom_padding = true
    look.padding = 12.0
    var tallest = line
    if c.supporting.len > 0usize { tallest += style.text_style(t.tokens, .BodySmall).line_height }
    if slotted && slot > tallest { tallest = slot }
    look.padding_y = control.max_zero((row_height - tallest) * 0.5)
    look.min_height = row_height
    look.min_width = 24.0
    let (parts, parts_error) = mem.alloc[widget.Node](a, 5usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var p = 0usize
    if slotted {
        if c.radio && c.checked {
            let (mark, mark_error) = menu_radio_dot(a, mark_ink, slot)
            if mark_error != ok { ret (zero, mark_error) }
            parts[p] = mark
        } else if c.checked {
            let (mark, mark_error) = control.icon_square(a, mark_ink, .Check, slot)
            if mark_error != ok { ret (zero, mark_error) }
            parts[p] = mark
        } else if c.pictured && !c.radio && !c.checkable {
            var icon_ink = muted
            if c.destructive { icon_ink = ink }
            let (mark, mark_error) = control.icon_square(a, icon_ink, c.glyph, slot)
            if mark_error != ok { ret (zero, mark_error) }
            parts[p] = mark
        } else {
            parts[p] = widget.box(0u64, control.sized_style(slot, slot), zero)
        }
        p += 1usize
    }
    var caption = control.text_options()
    caption.role = role
    caption.wrap = .None
    let (said, said_error) = control.colored_text(a, 0u64, c.label, t, caption, ink)
    if said_error != ok { ret (zero, said_error) }
    var words = said
    if c.supporting.len > 0usize {
        let (lines, lines_error) = mem.alloc[widget.Node](a, 2usize)
        if lines_error != ok { ret (zero, TooLarge) }
        lines[0usize] = said
        caption.role = .BodySmall
        let (note, note_error) = control.colored_text(a, 0u64, c.supporting, t, caption, muted)
        if note_error != ok { ret (zero, note_error) }
        lines[1usize] = note
        words = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), lines[0usize..2usize])
    }
    parts[p] = words
    p += 1usize
    parts[p] = widget.spacer(0u64, 1.0)
    p += 1usize
    let has_submenu = c.submenu.len != 0usize
    if c.shortcut.len > 0usize && !touch && !has_submenu {
        caption.role = .BodyMedium
        let (keys_node, keys_error) = control.colored_text(a, 0u64, c.shortcut, t, caption, muted)
        if keys_error != ok { ret (zero, keys_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = keys_node
        parts[p] = widget.padded(0u64, 24.0 - gap, 0.0, 0.0, 0.0, style.defaults(), held[0usize..1usize])
        p += 1usize
    }
    if has_submenu {
        let (arrow, arrow_error) = control.icon_square(a, muted, .ChevronRight, slot)
        if arrow_error != ok { ret (zero, arrow_error) }
        parts[p] = arrow
        p += 1usize
    }
    var line_style = style.defaults()
    line_style.width = style.Length { Percent: 100.0 }
    let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: gap }, line_style, parts[0usize..p])
    var sem_states = 0u32
    if c.checked { sem_states = accessibility.STATE_CHECKED }
    var semantic_role = 22u8
    if c.checkable || c.checked { semantic_role = accessibility.ROLE_MENU_ITEM_CHECKBOX }
    if c.radio { semantic_role = accessibility.ROLE_MENU_ITEM_RADIO }
    var sem_actions = 0u32
    var controls = 0u64
    var chosen = &c.action
    if has_submenu {
        sem_actions = accessibility.ACTION_SHOW_MENU
        controls = submenu_key
        chosen = &c.submenu_toggle
        if c.submenu_open { sem_states = sem_states | accessibility.STATE_EXPANDED }
    }
    let (made, made_error) = control.pressable_states(a, item_key, t, semantic_role, c.label, look, c.enabled, false, sem_states, sem_actions, controls, chosen, content)
    ret (made, made_error)
}

// A compact touch submenu's first row: back to its parent page, with the
// submenu title in `title-small` after a 24px back arrow.
fn menu_back_row(a: *mem.Arena, key: widget.Key, return_key: widget.Key, t: *const control.Theme, label: str, action: *const widget.Submit) -> (widget.Node, err) {
    let ink = style.color(t.tokens, .OnSurface)
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let state = control.control_state(t, key, true, false)
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = control.with_alpha(ink, control.state_opacity(t, state))
    look.foreground = ink
    look.border_width = 0.0
    look.radius = 0.0
    look.custom_padding = true
    look.padding = 12.0
    look.padding_y = 12.0
    look.min_height = 48.0
    look.min_width = 24.0
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (arrow, arrow_error) = control.icon_square(a, muted, .ChevronLeft, 24.0)
    if arrow_error != ok { ret (zero, arrow_error) }
    parts[0usize] = arrow
    var caption = control.text_options()
    caption.role = .TitleSmall
    caption.wrap = .None
    let (said, said_error) = control.colored_text(a, 0u64, label, t, caption, ink)
    if said_error != ok { ret (zero, said_error) }
    parts[1usize] = said
    var line_style = style.defaults()
    line_style.width = style.Length { Percent: 100.0 }
    let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, line_style, parts[..])
    let (made, made_error) = control.pressable_states(a, key, t, 22u8, "Back", look, true, false, 0u32, accessibility.ACTION_COLLAPSE, return_key, action, content)
    ret (made, made_error)
}

// v2 (D975, docs/ux/components/Menu): `surface-container`, `radius-sm`, elevation
// 2, no border, `rim` above and below its commands; 200 to 320 wide with a pointer
// (112 to 280 on touch). A command is a full-width row 32 tall (48 touch), or
// 48 (56 touch) with a `body-small` supporting line, 12 at
// its sides, 8 between its parts (12 touch): the 18 leading slot (24 touch; a
// check in `on-surface`, reserved in every command once any is checked), the
// `body-medium` label (`body-large` touch) in `on-surface` (`error` when
// destructive) and, with a pointer, the shortcut in `body-medium`
// `on-surface-variant` at the end, at least 24 after the label; the `state-hover`
// layer of `on-surface` on every row. A disabled command is `on-surface` at 38%
// under no layer, and skipped by the arrows. A separator is a 1px
// `outline-variant` line with 4 above and below (8 touch); a group head is
// `label-medium` `on-surface-variant`, 12 in, 8 above and 4 below. A menu in the
// tree named `label`, its commands MenuItems (Checked when checked); the runtime
// moves the focus through them with Down and Up, wrapping, and Home and End. A
// command may open one submenu to its right, overlapping by 4 with its first row
// aligned to the parent row; Right opens, Left closes, and hover uses D1004's
// delay and safe triangle. At touch density the child replaces the parent page,
// led by a Back row and separator.
fn menu_panel(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, commands: []const MenuCommand, dismiss: *const widget.Submit, rim: f32, allow_submenus: bool, back_label: str, back_target: widget.Key, back: *const widget.Submit) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    let around = control.if_else(touch, 8.0, 4.0)
    if touch && allow_submenus {
        var opened = commands.len
        var o = 0usize
        while o < commands.len {
            if commands[o].submenu_open {
                if opened != commands.len { ret (zero, TooLarge) }
                opened = o
            }
            o += 1usize
        }
        if opened != commands.len {
            let c = &commands[opened]
            if c.submenu.len == 0usize || c.submenu.len > 8usize { ret (zero, TooLarge) }
            let item_key = key + 1u64 + u64(opened)
            let submenu_key = key + 1024u64 + 16u64 * u64(opened)
            let (page, page_error) = menu_panel(a, submenu_key, t, c.label, c.submenu, &c.submenu_toggle, rim, false, c.label, item_key, &c.submenu_toggle)
            ret (page, page_error)
        }
    }
    var slotted = false
    var k = 0usize
    while k < commands.len {
        if commands[k].checkable || commands[k].checked || commands[k].radio || commands[k].pictured { slotted = true }
        k += 1usize
    }
    let (rows, rows_error) = mem.alloc[widget.Node](a, 4usize * commands.len + 2usize)
    if rows_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    if back_label.len > 0usize {
        let (back_row, back_error) = menu_back_row(a, key, back_target, t, back_label, back)
        if back_error != ok { ret (zero, back_error) }
        rows[n] = back_row
        n += 1usize
        let (lines, lines_error) = mem.alloc[widget.Node](a, 1usize)
        if lines_error != ok { ret (zero, TooLarge) }
        var rule = style.defaults()
        rule.width = style.Length { Percent: 100.0 }
        rule.height = style.Length { Px: t.tokens.sizes.divider }
        rule.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
        lines[0usize] = widget.box(0u64, rule, zero)
        let (rule_body, rule_body_error) = mem.alloc[widget.Node](a, 1usize)
        if rule_body_error != ok { ret (zero, TooLarge) }
        rule_body[0usize] = widget.padded(0u64, 0.0, 0.0, 0.0, around, style.defaults(), lines[..])
        var rule_sem: widget.Semantics = zero
        rule_sem.role = accessibility.ROLE_SEPARATOR
        rows[n] = widget.semantics(0u64, rule_sem, style.defaults(), rule_body[..])
        n += 1usize
    }
    var i = 0usize
    while i < commands.len {
        let c = &commands[i]
        let has_submenu = c.submenu.len != 0usize
        if has_submenu && (!allow_submenus || c.submenu.len > 8usize) { ret (zero, TooLarge) }
        if c.separated && i > 0usize {
            let (lines, lines_error) = mem.alloc[widget.Node](a, 1usize)
            if lines_error != ok { ret (zero, TooLarge) }
            var rule = style.defaults()
            rule.width = style.Length { Percent: 100.0 }
            rule.height = style.Length { Px: t.tokens.sizes.divider }
            rule.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
            lines[0usize] = widget.box(0u64, rule, zero)
            let (rule_body, rule_body_error) = mem.alloc[widget.Node](a, 1usize)
            if rule_body_error != ok { ret (zero, TooLarge) }
            rule_body[0usize] = widget.padded(0u64, 0.0, around, 0.0, around, style.defaults(), lines[0usize..1usize])
            var rule_sem: widget.Semantics = zero
            rule_sem.role = accessibility.ROLE_SEPARATOR
            rows[n] = widget.semantics(0u64, rule_sem, style.defaults(), rule_body[0usize..1usize])
            n += 1usize
        }
        if c.head.len > 0usize {
            var heading = control.text_options()
            heading.role = .LabelMedium
            heading.wrap = .None
            let (head_node, head_error) = control.colored_text(a, 0u64, c.head, t, heading, style.color(t.tokens, .OnSurfaceVariant))
            if head_error != ok { ret (zero, head_error) }
            let (heads, heads_error) = mem.alloc[widget.Node](a, 1usize)
            if heads_error != ok { ret (zero, TooLarge) }
            heads[0usize] = head_node
            rows[n] = widget.padded(0u64, 12.0, 8.0, 12.0, 4.0, style.defaults(), heads[0usize..1usize])
            n += 1usize
        }
        let item_key = key + 1u64 + u64(i)
        let submenu_key = key + 1024u64 + 16u64 * u64(i)
        let (made, made_error) = menu_row_of(a, item_key, submenu_key, t, c, slotted)
        if made_error != ok { ret (zero, made_error) }
        rows[n] = made
        n += 1usize
        if has_submenu {
            let (nested, nested_error) = menu_at(a, submenu_key, t, item_key, c.label, c.submenu, c.submenu_open, &c.submenu_toggle, .Right, geometry.Point { x: -4.0, y: -rim }, rim, false)
            if nested_error != ok { ret (zero, nested_error) }
            rows[n] = nested
            n += 1usize
        }
        i += 1usize
    }
    var raised = control.surface_options(t)
    raised.background = .SurfaceContainer
    raised.elevation = 2u8
    raised.radius = t.tokens.radii.sm
    raised.padding = 0.0
    var sheet_style = control.surface_style(t, raised)
    sheet_style.padding.top = style.Length { Px: rim }
    sheet_style.padding.bottom = style.Length { Px: rim }
    sheet_style.min_width = style.Length { Px: control.if_else(touch, 112.0, 200.0) }
    sheet_style.max_width = style.Length { Px: control.if_else(touch, 280.0, 320.0) }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, sheet_style, rows[0usize..n])
    var none: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: zero, cancel_action: *dismiss, keys: zero }, style.defaults(), column[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 21u8
    sem.label = label
    ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// A menu button: an outlined button keyed `key` firing `toggle`, with the menu
// (keyed `key + 1`, its items `key + 2 + index`) below it while `open`; the button
// says expanded and offers the menu in the tree.
fn menu_button(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const MenuItem, open: bool, toggle: *const widget.Submit) -> (widget.Node, err) {
    let look = style.resolve(t.tokens, .Outlined, control.control_state(t, key, true, false))
    var caption = control.text_options()
    caption.role = .Label
    caption.wrap = .None
    let (label_node, label_error) = control.colored_text(a, 0u64, label, t, caption, look.foreground)
    if label_error != ok { ret (zero, label_error) }
    var states = 0u32
    if open { states = accessibility.STATE_EXPANDED }
    let (head, head_error) = control.pressable_states(a, key, t, 3u8, label, look, true, false, states, accessibility.ACTION_SHOW_MENU, key + 1u64, toggle, label_node)
    if head_error != ok { ret (zero, head_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    let (opened, opened_error) = menu(a, key + 1u64, t, key, label, items, open, toggle)
    if opened_error != ok { ret (zero, opened_error) }
    parts[1usize] = opened
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

// What a dialog button means: the default one is filled and Enter, the cancel one
// is Escape and the dismiss, a destructive one is in the error colour, a plain one
// is just a button.
type DialogAction = enum u8 { Plain, Default, Cancel, Destructive }
type DialogButton = struct { label: str, action: widget.Submit, kind: DialogAction }

// An alert dialog: a dialog whose content is a message (keyed `key + 2`), the
// dialog described by it.
// v2 (D977, docs/ux/components/Dialog): the message in `body-medium`
// `on-surface-variant`.
fn alert_dialog(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, message: str, buttons: []const DialogButton, open: bool) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var words = control.text_options()
    words.role = .BodyMedium
    let (message_node, message_error) = control.colored_text(a, key + 2u64, message, t, words, style.color(t.tokens, .OnSurfaceVariant))
    if message_error != ok { ret (zero, message_error) }
    let (made, made_error) = dialog_as(a, key, t, title, message_node, buttons, open, true, accessibility.ROLE_ALERT_DIALOG)
    ret (made, made_error)
}

// The scrim under a modal overlay (D977): `scrim` at the scrim opacity across the
// window, an overlay of its own under `top`; a press on it misses the modal
// overlay, which dismisses it.
fn with_scrim(a: *mem.Arena, t: *const control.Theme, top: widget.Node) -> (widget.Node, err) {
    var dim = style.defaults()
    dim.width = style.Length { Percent: 100.0 }
    dim.height = style.Length { Percent: 100.0 }
    dim.background = paint.Brush { Solid: control.with_alpha(style.color(t.tokens, .Scrim), t.tokens.states.scrim) }
    let (dims, dims_error) = mem.alloc[widget.Node](a, 1usize)
    if dims_error != ok { ret (zero, TooLarge) }
    dims[0usize] = widget.box(0u64, dim, zero)
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[0usize] = widget.overlay(0u64, widget.Overlay { anchor: 0u64, placement: .Center, offset: zero, modal: false, dismiss: zero }, style.defaults(), dims[0usize..1usize])
    layers[1usize] = top
    ret (widget.box(0u64, style.defaults(), layers[0usize..2usize]), ok)
}

// A dialog: a modal overlay in the middle of the window, a card of the title (a
// heading keyed `key + 1`), the caller's content and the buttons in a row keyed
// `key + 3 + index`, placed only while `open`; a modal dialog in the tree labelled
// by the title and, when `described`, described by the content's key `key + 2`.
// The buttons outlive the frame.
// v2 (D977, docs/ux/components/Dialog): over a `scrim` at 32% across the window,
// the card is `surface-container-high`, `radius-xl`, elevation 3, no border, 24
// all round, 280 to 560 wide; the `headline-small` `on-surface` title (a level-2
// heading), 16 above the content, 8 above the actions at the end 8 apart -- the
// default a filled button, a destructive one filled in `error`, the others text
// buttons, all at the control height.
// ponytail: no scroll dividers or host button order.
fn dialog(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, buttons: []const DialogButton, open: bool, described: bool) -> (widget.Node, err) {
    let (made, made_error) = dialog_as(a, key, t, title, content, buttons, open, described, 23u8)
    ret (made, made_error)
}

fn dialog_host_order(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, buttons: []const DialogButton, default_first: bool, open: bool, described: bool) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (ordered, ordered_error) = mem.alloc[DialogButton](a, buttons.len)
    if ordered_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    var group = 0usize
    while group < 3usize {
        var i = 0usize
        while i < buttons.len {
            let primary = buttons[i].kind == .Default
            let cancel = buttons[i].kind == .Cancel
            var wanted = (!primary && !cancel && group == 0usize) || (cancel && group == 1usize) || (primary && group == 2usize)
            if default_first { wanted = (primary && group == 0usize) || (!primary && !cancel && group == 1usize) || (cancel && group == 2usize) }
            if wanted {
                ordered[n] = buttons[i]
                n += 1usize
            }
            i += 1usize
        }
        group += 1usize
    }
    let (made, made_error) = dialog(a, key, t, title, content, ordered[0usize..n], true, described)
    ret (made, made_error)
}

fn dialog_scrolled(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, buttons: []const DialogButton, scrolled_above: bool, scrolled_below: bool, open: bool, described: bool) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    if scrolled_above {
        let (rule, rule_error) = control.divider(a, 0u64, t, .Horizontal, 0.0)
        if rule_error != ok { ret (zero, rule_error) }
        parts[n] = rule
        n += 1usize
    }
    parts[n] = content
    n += 1usize
    if scrolled_below {
        let (rule, rule_error) = control.divider(a, 0u64, t, .Horizontal, 0.0)
        if rule_error != ok { ret (zero, rule_error) }
        parts[n] = rule
        n += 1usize
    }
    var full = style.defaults()
    full.width = style.Length { Percent: 100.0 }
    let divided = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, full, parts[0usize..n])
    let (made, made_error) = dialog(a, key, t, title, divided, buttons, true, described)
    ret (made, made_error)
}

fn dialog_state(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, buttons: []const DialogButton, open: bool, described: bool, busy: bool) -> (widget.Node, err) {
    let (made, made_error) = dialog_as_state(a, key, t, title, content, buttons, open, described, 23u8, busy, zero, false, .Info, false)
    ret (made, made_error)
}

fn dialog_with_icon(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, buttons: []const DialogButton, icon: control.GlyphKind, destructive: bool, open: bool, described: bool) -> (widget.Node, err) {
    let (made, made_error) = dialog_as_state(a, key, t, title, content, buttons, open, described, 23u8, false, zero, true, icon, destructive)
    ret (made, made_error)
}

// A basic dialog with an explicit fallback used by Escape and its scrim when
// the button list has no Cancel action.
fn dialog_dismissable(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, buttons: []const DialogButton, open: bool, described: bool, busy: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let (made, made_error) = dialog_as_state(a, key, t, title, content, buttons, open, described, 23u8, busy, *dismiss, false, .Info, false)
    ret (made, made_error)
}

fn dialog_as(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, buttons: []const DialogButton, open: bool, described: bool, semantic_role: u8) -> (widget.Node, err) {
    let (made, made_error) = dialog_as_state(a, key, t, title, content, buttons, open, described, semantic_role, false, zero, false, .Info, false)
    ret (made, made_error)
}

fn dialog_as_state(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, buttons: []const DialogButton, open: bool, described: bool, semantic_role: u8, busy: bool, fallback: widget.Submit, has_icon: bool, icon: control.GlyphKind, destructive_icon: bool) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var submit: widget.Submit = zero
    var cancel: widget.Submit = zero
    let (row, row_error) = mem.alloc[widget.Node](a, buttons.len)
    if row_error != ok { ret (zero, TooLarge) }
    var idle: []widget.Submit = zero
    if busy {
        let (made_idle, idle_error) = mem.alloc[widget.Submit](a, 1usize)
        if idle_error != ok { ret (zero, TooLarge) }
        made_idle[0usize] = widget.Submit { ctx: zero, invoke: zero }
        idle = made_idle
    }
    var i = 0usize
    while i < buttons.len {
        let button_key = key + 3u64 + u64(i)
        var options = control.button_options()
        options.variant = .Plain
        if buttons[i].kind == .Default {
            options.variant = .Filled
            options.loading = busy
            if !busy { submit = buttons[i].action }
        }
        if buttons[i].kind == .Destructive { options.variant = .Danger }
        if buttons[i].kind == .Cancel && !busy { cancel = buttons[i].action }
        if busy && buttons[i].kind != .Default { options.enabled = false }
        var action = &buttons[i].action
        if busy { action = &idle[0usize] }
        let (pressed, pressed_error) = control.button(a, button_key, t, buttons[i].label, action, options)
        if pressed_error != ok { ret (zero, pressed_error) }
        row[i] = pressed
        i += 1usize
    }
    if !busy && !widget.submit_set(cancel.invoke) && widget.submit_set(fallback.invoke) { cancel = fallback }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var heading = control.text_options()
    heading.role = .HeadlineSmall
    if has_icon { heading.align = .Center }
    let (title_node, title_error) = control.colored_text(a, key + 1u64, title, t, heading, style.color(t.tokens, .OnSurface))
    if title_error != ok { ret (zero, title_error) }
    let (titled, titled_error) = mem.alloc[widget.Node](a, 1usize)
    if titled_error != ok { ret (zero, TooLarge) }
    titled[0usize] = title_node
    var title_sem: widget.Semantics = zero
    title_sem.role = 25u8
    title_sem.label = title
    title_sem.level = 2u8
    parts[0usize] = widget.semantics(0u64, title_sem, style.defaults(), titled[0usize..1usize])
    if has_icon {
        var well_fill: style.ColorRole = .SecondaryContainer
        var well_ink: style.ColorRole = .OnSecondaryContainer
        if destructive_icon {
            well_fill = .ErrorContainer
            well_ink = .OnErrorContainer
        }
        let (mark, mark_error) = control.icon_square(a, style.color(t.tokens, well_ink), icon, 24.0)
        if mark_error != ok { ret (zero, mark_error) }
        let (mark_body, mark_body_error) = mem.alloc[widget.Node](a, 1usize)
        if mark_body_error != ok { ret (zero, TooLarge) }
        mark_body[0usize] = mark
        var well = control.sized_style(40.0, 40.0)
        well.radius = 20.0
        well.background = paint.Brush { Solid: style.color(t.tokens, well_fill) }
        let icon_well = widget.aligned(0u64, .Center, .Center, well, mark_body[0usize..1usize])
        let (header, header_error) = mem.alloc[widget.Node](a, 2usize)
        if header_error != ok { ret (zero, TooLarge) }
        header[0usize] = icon_well
        header[1usize] = parts[0usize]
        var header_style = style.defaults()
        header_style.width = style.Length { Percent: 100.0 }
        parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 16.0 }, header_style, header[0usize..2usize])
    }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = content
    parts[1usize] = widget.padded(0u64, 0.0, 16.0, 0.0, 0.0, style.defaults(), held[0usize..1usize])
    var actions_style = style.defaults()
    actions_style.padding.top = style.Length { Px: 8.0 }
    parts[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: 8.0 }, actions_style, row[0usize..buttons.len])
    var raised = control.surface_options(t)
    raised.background = .SurfaceContainerHigh
    raised.elevation = 3u8
    raised.radius = t.tokens.radii.xl
    raised.padding = 24.0
    var card_style = control.surface_style(t, raised)
    card_style.min_width = style.Length { Px: 280.0 }
    card_style.max_width = style.Length { Px: 560.0 }
    let (card, card_error) = mem.alloc[widget.Node](a, 1usize)
    if card_error != ok { ret (zero, TooLarge) }
    card[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, card_style, parts[0usize..3usize])
    var none: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: submit, cancel_action: cancel, keys: zero }, style.defaults(), card[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = semantic_role
    sem.label = title
    sem.states = accessibility.STATE_MODAL
    if busy { sem.states = sem.states | accessibility.STATE_BUSY }
    sem.labelled_by = key + 1u64
    if described { sem.described_by = key + 2u64 }
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    var outside = cancel
    if semantic_role == accessibility.ROLE_ALERT_DIALOG { outside = widget.Submit { ctx: zero, invoke: zero } }
    let (made, made_error) = with_scrim(a, t, widget.overlay(key, widget.Overlay { anchor: 0u64, placement: .Center, offset: zero, modal: true, dismiss: outside }, style.defaults(), framed[0usize..1usize]))
    ret (made, made_error)
}

// Below the medium window threshold a form dialog becomes a full-window surface
// with a 56px Close/title/Save bar; larger sizes keep the ordinary dialog.
fn dialog_adaptive(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, buttons: []const DialogButton, open: bool, described: bool, size: style.SizeClass) -> (widget.Node, err) {
    if size != .Compact {
        let (made, made_error) = dialog(a, key, t, title, content, buttons, open, described)
        ret (made, made_error)
    }
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var submit: widget.Submit = zero
    var cancel: widget.Submit = zero
    var submit_index = 0usize
    var cancel_index = 0usize
    var i = 0usize
    while i < buttons.len {
        if buttons[i].kind == .Default {
            submit = buttons[i].action
            submit_index = i
        }
        if buttons[i].kind == .Cancel {
            cancel = buttons[i].action
            cancel_index = i
        }
        i += 1usize
    }
    if !widget.submit_set(submit.invoke) || !widget.submit_set(cancel.invoke) { ret (zero, TooLarge) }
    let (bar, bar_error) = mem.alloc[widget.Node](a, 4usize)
    if bar_error != ok { ret (zero, TooLarge) }
    let (close, close_error) = control.glyph_button(a, key + 2u64, t, .Cross, "Close", &buttons[cancel_index].action, 48.0, 24.0)
    if close_error != ok { ret (zero, close_error) }
    bar[0usize] = close
    var heading = control.text_options()
    heading.role = .TitleLarge
    heading.wrap = .None
    let (title_node, title_error) = control.colored_text(a, key + 1u64, title, t, heading, style.color(t.tokens, .OnSurface))
    if title_error != ok { ret (zero, title_error) }
    let (titled, titled_error) = mem.alloc[widget.Node](a, 1usize)
    if titled_error != ok { ret (zero, TooLarge) }
    titled[0usize] = title_node
    var title_sem: widget.Semantics = zero
    title_sem.role = 25u8
    title_sem.label = title
    title_sem.level = 2u8
    bar[1usize] = widget.semantics(0u64, title_sem, style.defaults(), titled[0usize..1usize])
    bar[2usize] = widget.spacer(0u64, 1.0)
    var save_options = control.button_options()
    save_options.variant = .Plain
    let (save, save_error) = control.button(a, key + 3u64 + u64(submit_index), t, buttons[submit_index].label, &buttons[submit_index].action, save_options)
    if save_error != ok { ret (zero, save_error) }
    bar[3usize] = save
    var bar_style = style.defaults()
    bar_style.width = style.Length { Percent: 100.0 }
    bar_style.height = style.Length { Px: 56.0 }
    bar_style.padding.left = style.Length { Px: 4.0 }
    bar_style.padding.right = style.Length { Px: 8.0 }
    let (page, page_error) = mem.alloc[widget.Node](a, 2usize)
    if page_error != ok { ret (zero, TooLarge) }
    page[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, bar_style, bar[0usize..4usize])
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = content
    page[1usize] = widget.padded(0u64, 16.0, 8.0, 16.0, 16.0, style.defaults(), held[0usize..1usize])
    var surface = style.defaults()
    surface.width = style.Length { Percent: 100.0 }
    surface.height = style.Length { Percent: 100.0 }
    surface.background = paint.Brush { Solid: style.color(t.tokens, .Surface) }
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, surface, page[0usize..2usize])
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = column
    var none: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: submit, cancel_action: cancel, keys: zero }, style.defaults(), body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 23u8
    sem.label = title
    sem.states = accessibility.STATE_MODAL
    sem.labelled_by = key + 1u64
    if described { sem.described_by = key + 2u64 }
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: 0u64, placement: .Center, offset: zero, modal: true, dismiss: cancel }, style.defaults(), framed[0usize..1usize]), ok)
}

// -------------------------------------------- transient presentation (D841, P2-09)

// The surface a popup stands on.
// v2 (D976, docs/ux/components/Popup): `surface-container`, `radius-sm`, elevation
// 2, no border, 4 above and below the content and none at the sides (its rows
// run edge to edge), 200 to 480 wide.
fn popup_surface(a: *mem.Arena, t: *const control.Theme, content: widget.Node) -> (widget.Node, err) {
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var raised = control.surface_options(t)
    raised.background = .SurfaceContainer
    raised.elevation = 2u8
    raised.radius = t.tokens.radii.sm
    raised.padding = 0.0
    var plate = control.surface_style(t, raised)
    plate.padding.top = style.Length { Px: 4.0 }
    plate.padding.bottom = style.Length { Px: 4.0 }
    plate.min_width = style.Length { Px: 200.0 }
    plate.max_width = style.Length { Px: 480.0 }
    ret (widget.box(0u64, plate, body[0usize..1usize]), ok)
}

// The offset that stands an overlay `gap` off its anchor on the side `placement`
// names (D976).
fn gap_offset(placement: widget.Placement, gap: f32) -> geometry.Point {
    if placement == .Above || placement == .AboveCenter || placement == .AboveMatch { ret geometry.Point { x: 0.0, y: 0.0 - gap } }
    if placement == .Right { ret geometry.Point { x: gap, y: 0.0 } }
    if placement == .Left { ret geometry.Point { x: 0.0 - gap, y: 0.0 } }
    if placement == .Center || placement == .At { ret geometry.Point { x: 0.0, y: 0.0 } }
    ret geometry.Point { x: 0.0, y: gap }
}

// A popup: the content on a raised surface placed against `anchor` (keyed
// `key`), non-modal -- presses elsewhere pass through and nothing closes it but
// the caller -- placed only while `open`. A group in the tree. The v2 popup of
// D976 below, unnamed.
fn popup(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, content: widget.Node, open: bool) -> (widget.Node, err) {
    let (made, made_error) = popup_of(a, key, t, anchor, placement, "", content, open)
    ret (made, made_error)
}

// A suggestion popup's owner: the caller's field remains the focusable child,
// while this combobox reports the open popup and its virtual active row.
fn popup_combobox(a: *mem.Arena, label: str, popup_key: widget.Key, active_key: widget.Key, open: bool, field: widget.Node) -> (widget.Node, err) {
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = field
    var sem: widget.Semantics = zero
    sem.role = accessibility.ROLE_COMBOBOX
    sem.label = label
    sem.controls = popup_key
    if open {
        sem.states = accessibility.STATE_EXPANDED
        if active_key != 0u64 { sem.active = active_key }
    }
    ret (widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize]), ok)
}

// An open popup with no results: one polite body-medium status row, padded 12
// vertically and 16 at the sides instead of an empty surface.
fn popup_empty(a: *mem.Arena, key: widget.Key, t: *const control.Theme, message: str) -> (widget.Node, err) {
    var words = control.text_options()
    words.role = .BodyMedium
    words.wrap = .Word
    let (text_node, text_error) = control.colored_text(a, 0u64, message, t, words, style.color(t.tokens, .OnSurfaceVariant))
    if text_error != ok { ret (zero, text_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = text_node
    var row = style.defaults()
    row.width = style.Length { Percent: 100.0 }
    row.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 12.0 }, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 12.0 } }
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.box(0u64, row, body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 26u8
    sem.label = message
    sem.live = 1u8
    ret (widget.semantics(key, sem, style.defaults(), framed[0usize..1usize]), ok)
}

// A popup error: alert icon and message followed by one quiet Retry action.
fn popup_error(a: *mem.Arena, key: widget.Key, t: *const control.Theme, message: str, retry: *const widget.Submit) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 4usize)
    if items_error != ok { ret (zero, TooLarge) }
    let alarm = style.color(t.tokens, .Error)
    let (mark, mark_error) = control.icon_square(a, alarm, .Alert, 18.0)
    if mark_error != ok { ret (zero, mark_error) }
    items[0usize] = mark
    var words = control.text_options()
    words.role = .BodyMedium
    words.wrap = .Word
    let (message_node, message_error) = control.colored_text(a, 0u64, message, t, words, alarm)
    if message_error != ok { ret (zero, message_error) }
    items[1usize] = message_node
    items[2usize] = widget.spacer(0u64, 1.0)
    var plain = control.button_options()
    plain.variant = .Plain
    let (again, again_error) = control.button(a, key + 1u64, t, "Retry", retry, plain)
    if again_error != ok { ret (zero, again_error) }
    items[3usize] = again
    var row = style.defaults()
    row.width = style.Length { Percent: 100.0 }
    row.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 12.0 }, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 12.0 } }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, row, items[0usize..4usize])
    var sem: widget.Semantics = zero
    sem.role = 24u8
    sem.label = message
    sem.states = accessibility.STATE_INVALID
    sem.live = 2u8
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// A popup footer: a divider followed by one full-width 40px primary action row.
fn popup_footer(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, action: *const widget.Submit) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (rule, rule_error) = control.divider(a, 0u64, t, .Horizontal, 0.0)
    if rule_error != ok { ret (zero, rule_error) }
    parts[0usize] = rule
    let ink = style.color(t.tokens, .Primary)
    let state = control.control_state(t, key, true, false)
    var look = style.resolve(t.tokens, .Plain, state)
    look.foreground = ink
    look.radius = 0.0
    look.custom_padding = true
    look.padding_start = 16.0
    look.padding = 16.0
    look.padding_y = (40.0 - style.text_style(t.tokens, .BodyMedium).line_height) * 0.5
    look.min_height = 40.0
    var words = control.text_options()
    words.role = .BodyMedium
    words.wrap = .None
    let (label_node, label_error) = control.colored_text(a, 0u64, label, t, words, ink)
    if label_error != ok { ret (zero, label_error) }
    let (pressed, pressed_error) = control.pressable_states_fill(a, key, t, 3u8, label, look, true, false, 0u32, 0u32, 0u64, action, true, label_node)
    if pressed_error != ok { ret (zero, pressed_error) }
    parts[1usize] = pressed
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

type PopupLoad = struct { fill: paint.Color, phase: f32 }

fn popup_load_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let load = mem.cast[*PopupLoad](ctx)
    let width = area.width * 0.3
    let x = area.x - width + load.phase * (area.width + width)
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(x, area.y, width, area.height), brush: paint.Brush { Solid: load.fill } } })
}

// A loading popup: an indeterminate 4px bar flush with the surface's top edge,
// then one polite muted status line at the final popup width.
fn popup_loading(a: *mem.Arena, key: widget.Key, t: *const control.Theme, message: str) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (loads, loads_error) = mem.alloc[PopupLoad](a, 1usize)
    if loads_error != ok { ret (zero, TooLarge) }
    loads[0usize] = PopupLoad { fill: style.color(t.tokens, .Primary), phase: control.progress_turn(t, 0.0 - 1.0, time.seconds(2i64)) }
    var bar = control.sized_style(0.0, 4.0)
    bar.width = style.Length { Percent: 100.0 }
    bar.background = paint.Brush { Solid: style.color(t.tokens, .SecondaryContainer) }
    bar.radius = 2.0
    bar.overflow = .Clip
    bar.margin.top = style.Length { Px: 0.0 - 4.0 }
    var none: []const widget.Node = zero
    parts[0usize] = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&loads[0usize]), measure: control.mark_measure, paint: popup_load_paint, state: widget.bytes_of[PopupLoad](&loads[0usize]) } }, style: bar, children: none }
    var words = control.text_options()
    words.role = .BodyMedium
    words.wrap = .Word
    let (message_node, message_error) = control.colored_text(a, 0u64, message, t, words, style.color(t.tokens, .OnSurfaceVariant))
    if message_error != ok { ret (zero, message_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = message_node
    var row = style.defaults()
    row.width = style.Length { Percent: 100.0 }
    row.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 12.0 }, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 8.0 } }
    parts[1usize] = widget.box(0u64, row, held[0usize..1usize])
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 26u8
    sem.label = message
    sem.states = accessibility.STATE_BUSY
    sem.live = 1u8
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// v2 (D976/D987, docs/ux/components/Popup): the popup surface matches its anchor
// within 200..480 and sits 4 off it on the `placement` side (flipping when that
// side overflows), a group in the tree named `label`.
// ponytail: no match highlighting; the anchor keeps the focus
// because the popup takes none.
fn popup_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, label: str, content: widget.Node, open: bool) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (surface, surface_error) = popup_surface(a, t, content)
    if surface_error != ok { ret (zero, surface_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = surface
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize])
    var placed = placement
    if placement == .Below { placed = .BelowMatch }
    if placement == .Above { placed = .AboveMatch }
    var overlay_style = style.defaults()
    overlay_style.min_width = style.Length { Px: 200.0 }
    overlay_style.max_width = style.Length { Px: 480.0 }
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: placed, offset: gap_offset(placed, 4.0), modal: false, dismiss: zero }, overlay_style, framed[0usize..1usize]), ok)
}

// v2 (D976, docs/ux/components/Popup): a suggestion row, full width, 40 tall (48
// on touch), 16 at the sides, the `body-medium` label (`body-large` on touch) in
// `on-surface` and the `meta` (empty for none) in `label-small`
// `on-surface-variant` at the end, under the `on-surface` state layer; a list item
// in the tree firing `action`.
fn popup_row_with_label(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, meta: str, action: *const widget.Submit, label_node: widget.Node) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    let row_height = control.if_else(touch, 48.0, 40.0)
    var role: style.TextRole = .BodyMedium
    if touch { role = .BodyLarge }
    let ink = style.color(t.tokens, .OnSurface)
    let state = control.control_state(t, key, true, false)
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = control.with_alpha(ink, control.state_opacity(t, state))
    look.foreground = ink
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = 0.0
    look.custom_padding = true
    look.padding = 16.0
    look.padding_y = control.max_zero((row_height - style.text_style(t.tokens, role).line_height) * 0.5)
    look.min_height = row_height
    look.min_width = 24.0
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = label_node
    parts[1usize] = widget.spacer(0u64, 1.0)
    var caption = control.text_options()
    caption.wrap = .None
    var n = 2usize
    if meta.len > 0usize {
        caption.role = .LabelSmall
        let (noted, noted_error) = control.colored_text(a, 0u64, meta, t, caption, style.color(t.tokens, .OnSurfaceVariant))
        if noted_error != ok { ret (zero, noted_error) }
        parts[2usize] = noted
        n = 3usize
    }
    var line_style = style.defaults()
    line_style.width = style.Length { Percent: 100.0 }
    let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, line_style, parts[0usize..n])
    let (made, made_error) = control.pressable(a, key, t, 11u8, label, look, true, false, action, content)
    ret (made, made_error)
}

fn popup_row(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, meta: str, action: *const widget.Submit) -> (widget.Node, err) {
    var caption = control.text_options()
    caption.role = .BodyMedium
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { caption.role = .BodyLarge }
    caption.wrap = .None
    let (said, said_error) = control.colored_text(a, 0u64, label, t, caption, style.color(t.tokens, .OnSurface))
    if said_error != ok { ret (zero, said_error) }
    let (made, made_error) = popup_row_with_label(a, key, t, label, meta, action, said)
    ret (made, made_error)
}

// A suggestion row with one byte range of its label emphasized at weight 600.
// Invalid or empty ranges safely fall back to the ordinary row.
fn popup_row_match(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, match_start: usize, match_end: usize, meta: str, action: *const widget.Submit) -> (widget.Node, err) {
    if match_start >= match_end || match_end > label.len {
        let (plain, plain_error) = popup_row(a, key, t, label, meta, action)
        ret (plain, plain_error)
    }
    let (runs, runs_error) = mem.alloc[widget.Node](a, 3usize)
    if runs_error != ok { ret (zero, TooLarge) }
    var normal = control.text_options()
    normal.role = .BodyMedium
    var strong = control.text_options()
    strong.role = .TitleSmall
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm {
        normal.role = .BodyLarge
        strong.role = .TitleMedium
    }
    normal.wrap = .None
    strong.wrap = .None
    let ink = style.color(t.tokens, .OnSurface)
    let (before, before_error) = control.colored_text(a, 0u64, label[0usize..match_start], t, normal, ink)
    let (matched, matched_error) = control.colored_text(a, 0u64, label[match_start..match_end], t, strong, ink)
    let (after, after_error) = control.colored_text(a, 0u64, label[match_end..label.len], t, normal, ink)
    if before_error != ok { ret (zero, before_error) }
    if matched_error != ok { ret (zero, matched_error) }
    if after_error != ok { ret (zero, after_error) }
    runs[0usize] = before
    runs[1usize] = matched
    runs[2usize] = after
    let label_node = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), runs[0usize..3usize])
    let (made, made_error) = popup_row_with_label(a, key, t, label, meta, action, label_node)
    ret (made, made_error)
}

// A modal popup against an anchor: the content on the surface, taking the focus,
// Escape and a press outside firing `dismiss` (which also gives the focus back,
// D810); a dialog in the tree named `label`. The v2 flyout surface of D976.
fn light_dismissed(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, label: str, content: widget.Node, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var raised = control.surface_options(t)
    raised.background = .SurfaceContainer
    raised.elevation = 2u8
    raised.radius = t.tokens.radii.md
    raised.padding = control.if_else(touch, 16.0, 12.0)
    var plate = control.surface_style(t, raised)
    if !touch { plate.padding.bottom = style.Length { Px: 8.0 } }
    plate.min_width = style.Length { Px: control.if_else(touch, 240.0, 200.0) }
    plate.max_width = style.Length { Px: control.if_else(touch, 360.0, 320.0) }
    let (made, made_error) = dismissable(a, key, anchor, placement, label, widget.box(0u64, plate, body[0usize..1usize]), dismiss, 4.0)
    ret (made, made_error)
}

// The same over a surface the caller drew, `gap` from the anchor (D959) on the
// `placement` side (D976).
fn dismissable(a: *mem.Arena, key: widget.Key, anchor: widget.Key, placement: widget.Placement, label: str, surface: widget.Node, dismiss: *const widget.Submit, gap: f32) -> (widget.Node, err) {
    let (made, made_error) = dismissable_by(a, key, anchor, placement, label, surface, dismiss, gap, 0u64)
    ret (made, made_error)
}

// The same labelled by the element keyed `by` (0 for none, D976).
fn dismissable_by(a: *mem.Arena, key: widget.Key, anchor: widget.Key, placement: widget.Placement, label: str, surface: widget.Node, dismiss: *const widget.Submit, gap: f32, by: widget.Key) -> (widget.Node, err) {
    let (made, made_error) = dismissable_by_offset(a, key, anchor, placement, label, surface, dismiss, gap_offset(placement, gap), by)
    ret (made, made_error)
}

fn dismissable_by_offset(a: *mem.Arena, key: widget.Key, anchor: widget.Key, placement: widget.Placement, label: str, surface: widget.Node, dismiss: *const widget.Submit, offset: geometry.Point, by: widget.Key) -> (widget.Node, err) {
    let (made, made_error) = dismissable_by_offset_outside(a, key, anchor, placement, label, surface, dismiss, *dismiss, offset, by)
    ret (made, made_error)
}

fn dismissable_by_offset_outside(a: *mem.Arena, key: widget.Key, anchor: widget.Key, placement: widget.Placement, label: str, surface: widget.Node, dismiss: *const widget.Submit, outside: widget.Submit, offset: geometry.Point, by: widget.Key) -> (widget.Node, err) {
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = surface
    var none: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: zero, cancel_action: *dismiss, keys: zero }, style.defaults(), body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 23u8
    sem.label = label
    sem.states = accessibility.STATE_MODAL
    sem.labelled_by = by
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: placement, offset: offset, modal: true, dismiss: outside }, style.defaults(), framed[0usize..1usize]), ok)
}

// A standard flyout anchor: filled while closed, selected tonal while open, and
// reporting Show menu / Expanded / Controls to the accessibility tree.
fn flyout_button(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, flyout_key: widget.Key, open: bool, toggle: *const widget.Submit) -> (widget.Node, err) {
    var variant: style.ControlVariant = .Filled
    if open { variant = .Tonal }
    let look = control.button_look(t, style.resolve(t.tokens, variant, control.control_state(t, key, true, false)), true)
    var caption = control.text_options()
    caption.role = .Label
    caption.wrap = .None
    let (label_node, label_error) = control.colored_text(a, 0u64, label, t, caption, look.foreground)
    if label_error != ok { ret (zero, label_error) }
    var states = 0u32
    if open { states = accessibility.STATE_EXPANDED }
    let (made, made_error) = control.pressable_states(a, key, t, 3u8, label, look, true, open, states, accessibility.ACTION_SHOW_MENU, flyout_key, toggle, label_node)
    ret (made, made_error)
}

// A flyout: a light-dismissed popup against its anchor, placed while `open`.
// v2 (D976, docs/ux/components/Flyout): `surface-container`, `radius-md`,
// elevation 2, no border; 16 all round on touch, 12 at the sides and top and 8
// below with a pointer; 240 to 360 wide on touch, 200 to 320 with a pointer; 4
// off its anchor, flipping when that side overflows.
fn flyout(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, label: str, content: widget.Node, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (made, made_error) = light_dismissed(a, key, t, anchor, placement, label, content, dismiss)
    ret (made, made_error)
}

// The same flyout adapted to the caller's size class: compact touch screens use
// the existing modal bottom sheet at its medium (half-window) detent.
fn flyout_adaptive(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, label: str, content: widget.Node, open: bool, dismiss: *const widget.Submit, size: style.SizeClass) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    if size != .Compact || !touch {
        let (floating, floating_error) = flyout(a, key, t, anchor, placement, label, content, open, dismiss)
        ret (floating, floating_error)
    }
    var height: f32 = 320.0
    if mem.address_of(t.runtime) != 0usize { height = widget.surface_size(t.runtime).height * 0.5 }
    let (sheet_node, sheet_error) = bottom_sheet(a, key, t, label, content, open, dismiss, height)
    ret (sheet_node, sheet_error)
}

// A popover: a flyout with a title (a heading keyed `key + 1`) and a close
// button (keyed `key + 2`) above the content. The v2 popover of D976 below,
// without actions.
fn popover(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    var none: []const MenuItem = zero
    let (made, made_error) = popover_of(a, key, t, anchor, placement, title, content, none, open, dismiss)
    ret (made, made_error)
}

// v2 (D976, docs/ux/components/Popover): `surface-container-high`, `radius-md`,
// elevation 3, no border, 320 wide, 16 at the sides and top and 12 below, 12
// between its blocks: the header -- the `title-medium` `on-surface` title (a
// level-2 heading keyed `key + 1` that names the dialog) and a round Close button
// at the end (keyed `key + 2`, 40 across with a 24 `close`, 32 and 18 with a
// pointer, in `on-surface-variant`) -- then the content, then up to two actions
// at the end 8 apart (keyed `key + 3 + index`): the first, the main one, tonal
// and last, the other a text button before it. A 12 wide, 6 deep beak in the
// container's colour stands on the near edge, centred on the anchor but at least
// 16 in from a corner, its tip 4 from the anchor (the container 10); a modal
// dialog in the tree.
fn popover_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, title: str, content: widget.Node, actions: []const MenuItem, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let (made, made_error) = popover_state(a, key, t, anchor, placement, title, content, actions, open, false, false, dismiss)
    ret (made, made_error)
}

fn popover_action_row(a: *mem.Arena, key: widget.Key, t: *const control.Theme, actions: []const MenuItem, busy: bool) -> (widget.Node, err) {
    let (row, row_error) = mem.alloc[widget.Node](a, actions.len)
    if row_error != ok { ret (zero, TooLarge) }
    var idle: []widget.Submit = zero
    if busy {
        let (made_idle, idle_error) = mem.alloc[widget.Submit](a, 1usize)
        if idle_error != ok { ret (zero, TooLarge) }
        made_idle[0usize] = widget.Submit { ctx: zero, invoke: zero }
        idle = made_idle
    }
    var i = 0usize
    while i < actions.len {
        var options = control.button_options()
        options.variant = .Plain
        if i == 0usize { options.variant = .Tonal }
        options.enabled = actions[i].enabled
        var action = &actions[i].action
        if busy {
            if i == 0usize {
                options.loading = true
                action = &idle[0usize]
            } else {
                options.enabled = false
            }
        }
        let (pressed, pressed_error) = control.button(a, key + 3u64 + u64(i), t, actions[i].label, action, options)
        if pressed_error != ok { ret (zero, pressed_error) }
        row[actions.len - 1usize - i] = pressed
        i += 1usize
    }
    var full = style.defaults()
    full.width = style.Length { Percent: 100.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: 8.0 }, full, row[0usize..actions.len]), ok)
}

// The same with the main action's loading ring shown and repeat actions ignored;
// secondary actions are disabled until the caller clears `busy`. A dirty short
// task consumes outside presses while Close and Escape still dismiss it.
fn popover_state(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, title: str, content: widget.Node, actions: []const MenuItem, open: bool, busy: bool, dirty: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    if actions.len > 2usize { ret (zero, TooLarge) }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var heading = control.text_options()
    heading.role = .TitleMedium
    heading.wrap = .Word
    heading.max_lines = 2u32
    let (title_node, title_error) = control.colored_text(a, key + 1u64, title, t, heading, style.color(t.tokens, .OnSurface))
    if title_error != ok { ret (zero, title_error) }
    let (titled, titled_error) = mem.alloc[widget.Node](a, 1usize)
    if titled_error != ok { ret (zero, TooLarge) }
    titled[0usize] = title_node
    var title_sem: widget.Semantics = zero
    title_sem.role = 25u8
    title_sem.label = title
    title_sem.level = 2u8
    let (head, head_error) = mem.alloc[widget.Node](a, 3usize)
    if head_error != ok { ret (zero, TooLarge) }
    head[0usize] = widget.semantics(0u64, title_sem, style.defaults(), titled[0usize..1usize])
    head[1usize] = widget.spacer(0u64, 1.0)
    let (close, close_error) = control.glyph_button(a, key + 2u64, t, .Cross, "Close", dismiss, control.if_else(touch, 40.0, 32.0), control.if_else(touch, 24.0, 18.0))
    if close_error != ok { ret (zero, close_error) }
    head[2usize] = close
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var full = style.defaults()
    full.width = style.Length { Percent: 100.0 }
    parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, full, head[0usize..3usize])
    parts[1usize] = content
    var n = 2usize
    if actions.len > 0usize {
        let (action_row, action_row_error) = popover_action_row(a, key, t, actions, busy)
        if action_row_error != ok { ret (zero, action_row_error) }
        parts[2usize] = action_row
        n = 3usize
    }
    var raised = control.surface_options(t)
    raised.background = .SurfaceContainerHigh
    raised.elevation = 3u8
    raised.radius = t.tokens.radii.md
    raised.padding = 16.0
    var plate = control.surface_style(t, raised)
    plate.padding.bottom = style.Length { Px: 12.0 }
    plate.width = style.Length { Px: 320.0 }
    let (card, card_error) = mem.alloc[widget.Node](a, 2usize)
    if card_error != ok { ret (zero, TooLarge) }
    let fill = style.color(t.tokens, .SurfaceContainerHigh)
    let across = placement == .Right || placement == .Left
    var pointing: control.GlyphKind = .ChevronUp
    if placement == .Right { pointing = .ChevronLeft }
    if placement == .Left { pointing = .ChevronRight }
    if placement == .Above || placement == .AboveCenter { pointing = .ChevronDown }
    let (tip, tip_error) = control.beak(a, fill, pointing, control.if_else(across, 6.0, 12.0), control.if_else(across, 12.0, 6.0))
    if tip_error != ok { ret (zero, tip_error) }
    var inset: f32 = 16.0
    var offset = gap_offset(placement, 4.0)
    if mem.address_of(t.runtime) != 0usize {
        let (anchor_bounds, has_anchor) = widget.bounds_for_key(t.runtime, anchor)
        if has_anchor {
            if across {
                offset.y = anchor_bounds.height * 0.5 - 22.0
            } else {
                let surface = widget.surface_size(t.runtime)
                let first_placed = widget.overlay_rect(anchor_bounds, geometry.Size { width: 320.0, height: 0.0 }, widget.Overlay { anchor: anchor, placement: placement, offset: offset, modal: true, dismiss: *dismiss }, surface)
                let wanted = anchor_bounds.x + anchor_bounds.width * 0.5 - first_placed.x - 6.0
                if wanted < 16.0 { offset.x += wanted - 16.0 }
                if wanted > 292.0 { offset.x += wanted - 292.0 }
                let placed = widget.overlay_rect(anchor_bounds, geometry.Size { width: 320.0, height: 0.0 }, widget.Overlay { anchor: anchor, placement: placement, offset: offset, modal: true, dismiss: *dismiss }, surface)
                inset = anchor_bounds.x + anchor_bounds.width * 0.5 - placed.x - 6.0
                if inset < 16.0 { inset = 16.0 }
                if inset > 292.0 { inset = 292.0 }
            }
        }
    }
    let (tips, tips_error) = mem.alloc[widget.Node](a, 1usize)
    if tips_error != ok { ret (zero, TooLarge) }
    tips[0usize] = tip
    var tip_node = widget.padded(0u64, inset, 0.0, 0.0, 0.0, style.defaults(), tips[0usize..1usize])
    if across { tip_node = widget.padded(0u64, 0.0, inset, 0.0, 0.0, style.defaults(), tips[0usize..1usize]) }
    let box_node = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 12.0 }, plate, parts[0usize..n])
    // The beak comes first on the anchor's side: before the card below or to the
    // right of the anchor, after it above or to the left.
    var axis: ui_layout.Axis = .Vertical
    if across { axis = .Horizontal }
    card[0usize] = tip_node
    card[1usize] = box_node
    if pointing == .ChevronDown || pointing == .ChevronRight {
        card[0usize] = box_node
        card[1usize] = tip_node
    }
    let joined = widget.flex(0u64, ui_layout.Flex { axis: axis, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), card[0usize..2usize])
    var outside = *dismiss
    if dirty { outside = widget.Submit { ctx: zero, invoke: zero } }
    let (made, made_error) = dismissable_by_offset_outside(a, key, anchor, placement, title, joined, dismiss, outside, offset, key + 1u64)
    ret (made, made_error)
}

// The popover stays anchored except at compact touch size, where the same body
// and actions use the existing half-height modal bottom sheet without a beak.
fn popover_adaptive(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, title: str, content: widget.Node, actions: []const MenuItem, open: bool, busy: bool, dirty: bool, dismiss: *const widget.Submit, size: style.SizeClass) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    if size != .Compact || !touch {
        let (floating, floating_error) = popover_state(a, key, t, anchor, placement, title, content, actions, open, busy, dirty, dismiss)
        ret (floating, floating_error)
    }
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    if actions.len > 2usize { ret (zero, TooLarge) }
    var sheet_content = content
    if actions.len > 0usize {
        let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
        if parts_error != ok { ret (zero, TooLarge) }
        parts[0usize] = content
        let (action_row, action_row_error) = popover_action_row(a, key, t, actions, busy)
        if action_row_error != ok { ret (zero, action_row_error) }
        parts[1usize] = action_row
        sheet_content = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 12.0 }, style.defaults(), parts[0usize..2usize])
    }
    var height: f32 = 320.0
    if mem.address_of(t.runtime) != 0usize { height = widget.surface_size(t.runtime).height * 0.5 }
    var outside = *dismiss
    if dirty { outside = widget.Submit { ctx: zero, invoke: zero } }
    let (sheet_node, sheet_error) = edged(a, key, t, title, sheet_content, dismiss, outside, .Below, 0.0, height)
    ret (sheet_node, sheet_error)
}

// A sheet: a modal panel `width` wide along the right edge of the window, the
// window's height, with a title and a close button (keyed `key + 1`, `key + 2`)
// above the content, placed while `open`; Escape and a press outside fire
// `dismiss`. A modal dialog in the tree named by the title.
fn sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var clamped = width
    if clamped < 256.0 { clamped = 256.0 }
    if clamped > 400.0 { clamped = 400.0 }
    let (made, made_error) = edged(a, key, t, title, content, dismiss, *dismiss, .Right, clamped, 0.0)
    ret (made, made_error)
}

fn sheet_state(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, dirty: bool, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var clamped = width
    if clamped < 256.0 { clamped = 256.0 }
    if clamped > 400.0 { clamped = 400.0 }
    var outside = *dismiss
    if dirty { outside = widget.Submit { ctx: zero, invoke: zero } }
    let (made, made_error) = edged(a, key, t, title, content, dismiss, outside, .Right, clamped, 0.0)
    ret (made, made_error)
}

fn sheet_with_actions(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, actions: []const DialogButton, open: bool, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var clamped = width
    if clamped < 256.0 { clamped = 256.0 }
    if clamped > 400.0 { clamped = 400.0 }
    let (made, made_error) = edged_with_actions(a, key, t, title, content, dismiss, *dismiss, .Right, clamped, 0.0, actions)
    ret (made, made_error)
}

fn standard_sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, close: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var clamped = width
    if clamped < 256.0 { clamped = 256.0 }
    if clamped > 400.0 { clamped = 400.0 }
    let (made, made_error) = edged_standard(a, key, t, title, content, close, .Right, clamped, 0.0)
    ret (made, made_error)
}

// A bottom sheet: the same along the bottom edge, the window's width and
// `height` tall; v2 (D977), a drag handle rather than the close button.
fn bottom_sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit, height: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (made, made_error) = edged(a, key, t, title, content, dismiss, *dismiss, .Below, 0.0, height)
    ret (made, made_error)
}

fn bottom_sheet_state(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, dirty: bool, dismiss: *const widget.Submit, height: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var outside = *dismiss
    if dirty { outside = widget.Submit { ctx: zero, invoke: zero } }
    let (made, made_error) = edged(a, key, t, title, content, dismiss, outside, .Below, 0.0, height)
    ret (made, made_error)
}

fn bottom_sheet_with_actions(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, actions: []const DialogButton, open: bool, dismiss: *const widget.Submit, height: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (made, made_error) = edged_with_actions(a, key, t, title, content, dismiss, *dismiss, .Below, 0.0, height, actions)
    ret (made, made_error)
}

fn standard_bottom_sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, close: *const widget.Submit, height: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var clamped = height
    if clamped < 64.0 { clamped = 64.0 }
    let (made, made_error) = edged_standard(a, key, t, title, content, close, .Below, 0.0, clamped)
    ret (made, made_error)
}

type SheetDetent = enum u8 { Peek, Half, Full }

fn sheet_detent_height(t: *const control.Theme, detent: SheetDetent, peek_height: f32) -> f32 {
    var peek = peek_height
    if peek < 64.0 { peek = 64.0 }
    var available: f32 = 640.0
    if mem.address_of(t.runtime) != 0usize {
        let surface = widget.surface_size(t.runtime)
        available = surface.height
    }
    var full: f32 = available - 72.0
    if full < 64.0 { full = 64.0 }
    if peek > full { peek = full }
    if detent == .Half { ret available * 0.5 }
    if detent == .Full { ret full }
    ret peek
}

fn sheet_detent_label(detent: SheetDetent) -> str {
    if detent == .Half { ret "half height" }
    if detent == .Full { ret "full height" }
    ret "peek height"
}

type SheetDrag = struct { moved: f32 }
type SheetDragging = struct { cell: *SheetDrag, has_cell: bool, tap: widget.Submit, settle: widget.Submit, threshold: f32 }

fn sheet_drag_cell(t: *const control.Theme, key: widget.Key) -> (*SheetDrag, bool) {
    var none: *SheetDrag = zero
    if mem.address_of(t.runtime) == 0usize { ret (none, false) }
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret (none, false) }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret (none, false) }
    var build = widget.BuildContext { runtime: t.runtime, element: id, frame: 0u64 }
    let (kept, _, kept_error) = widget.state[SheetDrag](&build, key, SheetDrag { moved: 0.0 })
    if kept_error != ok { ret (none, false) }
    ret (kept, true)
}

fn sheet_drag(ctx: *void, g: widget.Gesture) -> err {
    let d = mem.cast[*SheetDragging](ctx)
    switch g {
    case .Tap as at:
        ret widget.fire_submit(d.tap)
    case .DragStart as at:
        if d.has_cell { d.cell.moved = 0.0 }
        ret ok
    case .DragMove as moved:
        if d.has_cell {
            d.cell.moved = moved.position.y - moved.start.y
            if d.cell.moved < 0.0 { d.cell.moved = 0.0 }
        }
        ret ok
    case .DragEnd as at:
        if !d.has_cell { ret ok }
        let moved = d.cell.moved
        d.cell.moved = 0.0
        if moved >= d.threshold { ret widget.fire_submit(d.settle) }
        ret ok
    default:
        ret ok
    }
}

fn bottom_sheet_detent(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit, cycle: *const widget.Submit, detent: SheetDetent, peek_height: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var settle = cycle
    if detent == .Peek { settle = dismiss }
    let (made, made_error) = edged_detent(a, key, t, title, content, dismiss, *dismiss, .Below, 0.0, sheet_detent_height(t, detent, peek_height), cycle, settle, sheet_detent_label(detent), false, true)
    ret (made, made_error)
}

fn standard_bottom_sheet_detent(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, close: *const widget.Submit, cycle: *const widget.Submit, detent: SheetDetent, peek_height: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (made, made_error) = edged_detent(a, key, t, title, content, close, *close, .Below, 0.0, sheet_detent_height(t, detent, peek_height), cycle, cycle, sheet_detent_label(detent), true, false)
    ret (made, made_error)
}

fn sheet_with_back(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit, back: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var clamped = width
    if clamped < 256.0 { clamped = 256.0 }
    if clamped > 400.0 { clamped = 400.0 }
    let (made, made_error) = edged_with_back(a, key, t, title, content, dismiss, *dismiss, .Right, clamped, 0.0, back)
    ret (made, made_error)
}

fn bottom_sheet_with_back(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit, back: *const widget.Submit, height: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (made, made_error) = edged_with_back(a, key, t, title, content, dismiss, *dismiss, .Below, 0.0, height, back)
    ret (made, made_error)
}

// A bottom sheet's drag handle (D977): 32 by 4, `radius-full`, `on-surface-variant`
// at 40%, centred 16 from the sheet's top.
fn sheet_handle(t: *const control.Theme, grips: []widget.Node) -> widget.Node {
    var grip = control.sized_style(32.0, 4.0)
    grip.radius = 2.0
    grip.background = paint.Brush { Solid: control.with_alpha(style.color(t.tokens, .OnSurfaceVariant), 0.4) }
    grips[0usize] = widget.box(0u64, grip, zero)
    var row = style.defaults()
    row.width = style.Length { Percent: 100.0 }
    row.padding.top = style.Length { Px: 16.0 }
    ret widget.aligned(0u64, .Center, .Start, row, grips[0usize..1usize])
}

fn sheet_resize_handle(a: *mem.Arena, key: widget.Key, t: *const control.Theme, grips: []widget.Node, cycle: *const widget.Submit, settle: *const widget.Submit, cell: *SheetDrag, has_cell: bool, value: str) -> (widget.Node, err) {
    var grip = control.sized_style(32.0, 4.0)
    grip.radius = 2.0
    grip.background = paint.Brush { Solid: control.with_alpha(style.color(t.tokens, .OnSurfaceVariant), 0.4) }
    grips[0usize] = widget.box(0u64, grip, zero)
    var holder = style.defaults()
    holder.width = style.Length { Percent: 100.0 }
    holder.height = style.Length { Px: 48.0 }
    holder.padding.top = style.Length { Px: 16.0 }
    grips[1usize] = widget.aligned(0u64, .Center, .Start, holder, grips[0usize..1usize])
    let state = control.control_state(t, key, true, false)
    var target_style = style.defaults()
    target_style.width = style.Length { Percent: 100.0 }
    target_style.height = style.Length { Px: 48.0 }
    target_style.background = paint.Brush { Solid: control.with_alpha(style.color(t.tokens, .OnSurface), control.state_opacity(t, state)) }
    let (region_body, region_body_error) = mem.alloc[widget.Node](a, 1usize)
    if region_body_error != ok { ret (zero, TooLarge) }
    let (dragging, dragging_error) = mem.alloc[SheetDragging](a, 1usize)
    if dragging_error != ok { ret (zero, TooLarge) }
    dragging[0usize] = SheetDragging { cell: cell, has_cell: has_cell, tap: *cycle, settle: *settle, threshold: 64.0 }
    var gestures = 1u8 | 4u8
    if has_cell { gestures |= 2u8 }
    region_body[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&dragging[0usize]), invoke: sheet_drag }, gestures: gestures, enabled: true, focusable: true }, target_style, grips[1usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 3u8
    sem.label = "Resize sheet"
    sem.value = value
    sem.actions = accessibility.ACTION_PRESS
    ret (widget.semantics(0u64, sem, style.defaults(), region_body[0usize..1usize]), ok)
}

// v2 (D977, docs/ux/components/Sheet): the header -- the `title-large` `on-surface`
// title (a heading keyed `key + 1`), 16 in, 56 tall (48 for a side sheet with a
// pointer), and on a side sheet a round Close button at the end (keyed `key + 2`,
// 40 across with a 24 `close`, 32 and 18 with a pointer, named "Close") -- over
// the content 16 in at the sides; a bottom sheet's drag handle above the header.
fn edged(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, dismiss: *const widget.Submit, outside: widget.Submit, placement: widget.Placement, width: f32, height: f32) -> (widget.Node, err) {
    var no_actions: []const DialogButton = zero
    let (made, made_error) = edged_full(a, key, t, title, content, dismiss, outside, placement, width, height, zero, no_actions, false, zero, zero, "", false)
    ret (made, made_error)
}

fn edged_with_back(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, dismiss: *const widget.Submit, outside: widget.Submit, placement: widget.Placement, width: f32, height: f32, back: *const widget.Submit) -> (widget.Node, err) {
    var no_actions: []const DialogButton = zero
    let (made, made_error) = edged_full(a, key, t, title, content, dismiss, outside, placement, width, height, back, no_actions, false, zero, zero, "", false)
    ret (made, made_error)
}

fn edged_with_actions(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, dismiss: *const widget.Submit, outside: widget.Submit, placement: widget.Placement, width: f32, height: f32, actions: []const DialogButton) -> (widget.Node, err) {
    let (made, made_error) = edged_full(a, key, t, title, content, dismiss, outside, placement, width, height, zero, actions, false, zero, zero, "", false)
    ret (made, made_error)
}

fn edged_standard(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, close: *const widget.Submit, placement: widget.Placement, width: f32, height: f32) -> (widget.Node, err) {
    var no_actions: []const DialogButton = zero
    let (made, made_error) = edged_full(a, key, t, title, content, close, *close, placement, width, height, zero, no_actions, true, zero, zero, "", false)
    ret (made, made_error)
}

fn edged_detent(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, dismiss: *const widget.Submit, outside: widget.Submit, placement: widget.Placement, width: f32, height: f32, cycle: *const widget.Submit, settle: *const widget.Submit, value: str, standard: bool, draggable: bool) -> (widget.Node, err) {
    var no_actions: []const DialogButton = zero
    let (made, made_error) = edged_full(a, key, t, title, content, dismiss, outside, placement, width, height, zero, no_actions, standard, cycle, settle, value, draggable)
    ret (made, made_error)
}

fn edged_full(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, dismiss: *const widget.Submit, outside: widget.Submit, placement: widget.Placement, width: f32, height: f32, back: *const widget.Submit, actions: []const DialogButton, standard: bool, resize: *const widget.Submit, settle: *const widget.Submit, resize_value: str, draggable: bool) -> (widget.Node, err) {
    if actions.len > 2usize { ret (zero, TooLarge) }
    let bottom = placement == .Below
    let (drag_cell, has_drag_cell) = sheet_drag_cell(t, key + 2u64)
    var drag_offset: f32 = 0.0
    if draggable && has_drag_cell { drag_offset = drag_cell.moved }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var heading = control.text_options()
    heading.role = .TitleLarge
    heading.wrap = .None
    let (title_node, title_error) = control.colored_text(a, key + 1u64, title, t, heading, style.color(t.tokens, .OnSurface))
    if title_error != ok { ret (zero, title_error) }
    let (bits, bits_error) = mem.alloc[widget.Node](a, 7usize)
    if bits_error != ok { ret (zero, TooLarge) }
    bits[0usize] = title_node
    var title_sem: widget.Semantics = zero
    title_sem.role = 25u8
    title_sem.label = title
    title_sem.level = 1u8
    bits[1usize] = widget.semantics(0u64, title_sem, style.defaults(), bits[0usize..1usize])
    let (header, header_error) = mem.alloc[widget.Node](a, 4usize)
    if header_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    let has_back = mem.address_of(back) != 0usize
    if has_back {
        let (back_button, back_error) = control.glyph_button(a, key + 3u64, t, .ArrowBack, "Back", back, control.if_else(touch, 40.0, 32.0), control.if_else(touch, 24.0, 18.0))
        if back_error != ok { ret (zero, back_error) }
        header[n] = back_button
        n += 1usize
    }
    header[n] = bits[1usize]
    n += 1usize
    header[n] = widget.spacer(0u64, 1.0)
    n += 1usize
    if !bottom {
        let (close, close_error) = control.glyph_button(a, key + 2u64, t, .Cross, "Close", dismiss, control.if_else(touch, 40.0, 32.0), control.if_else(touch, 24.0, 18.0))
        if close_error != ok { ret (zero, close_error) }
        header[n] = close
        n += 1usize
    }
    var bar = style.defaults()
    bar.width = style.Length { Percent: 100.0 }
    bar.height = style.Length { Px: control.if_else(!bottom && !touch, 48.0, 56.0) }
    bar.padding.left = style.Length { Px: control.if_else(has_back, 8.0, 16.0) }
    bar.padding.right = style.Length { Px: control.if_else(bottom, 16.0, 8.0) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 5usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var p = 0usize
    if bottom {
        if mem.address_of(resize) != 0usize {
            let (handle, handle_error) = sheet_resize_handle(a, key + 2u64, t, bits[3usize..5usize], resize, settle, drag_cell, draggable && has_drag_cell, resize_value)
            if handle_error != ok { ret (zero, handle_error) }
            parts[0usize] = handle
        } else {
            parts[0usize] = sheet_handle(t, bits[4usize..5usize])
        }
        p = 1usize
    }
    parts[p] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, bar, header[0usize..n])
    bits[5usize] = content
    parts[p + 1usize] = widget.padded(0u64, 16.0, 0.0, 16.0, 0.0, style.defaults(), bits[5usize..6usize])
    var part_count = p + 2usize
    if actions.len > 0usize {
        let (footer, footer_error) = mem.alloc[widget.Node](a, 2usize)
        if footer_error != ok { ret (zero, TooLarge) }
        let (rule, rule_error) = control.divider(a, 0u64, t, .Horizontal, 0.0)
        if rule_error != ok { ret (zero, rule_error) }
        footer[0usize] = rule
        let (buttons, buttons_error) = mem.alloc[widget.Node](a, actions.len)
        if buttons_error != ok { ret (zero, TooLarge) }
        var i = 0usize
        while i < actions.len {
            var options = control.button_options()
            options.variant = .Plain
            if actions[i].kind == .Default { options.variant = .Filled }
            if actions[i].kind == .Cancel { options.variant = .Outlined }
            if actions[i].kind == .Destructive { options.variant = .Danger }
            let (button, button_error) = control.button(a, key + 4u64 + u64(i), t, actions[i].label, &actions[i].action, options)
            if button_error != ok { ret (zero, button_error) }
            buttons[i] = button
            i += 1usize
        }
        var footer_style = style.defaults()
        footer_style.width = style.Length { Percent: 100.0 }
        footer_style.padding.top = style.Length { Px: 16.0 }
        footer_style.padding.right = style.Length { Px: 16.0 }
        footer_style.padding.bottom = style.Length { Px: 16.0 }
        footer_style.padding.left = style.Length { Px: 16.0 }
        footer[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, footer_style, buttons[0usize..actions.len])
        parts[part_count] = widget.spacer(0u64, 1.0)
        parts[part_count + 1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), footer[0usize..2usize])
        part_count += 2usize
    }
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), parts[0usize..part_count])
    if standard {
        let (made, made_error) = standard_sheet_frame(a, key, t, title, column, placement, width, height)
        ret (made, made_error)
    }
    let (made, made_error) = sheet_frame(a, key, t, title, column, dismiss, outside, placement, width, height, drag_offset)
    ret (made, made_error)
}

// v2 (D977, docs/ux/components/Sheet, modal): over a `scrim` at 32% across the
// window, `surface-container-low` with elevation 3; along the bottom the window's
// width up to 640, centred, `height` tall (0: as tall as its content), its top
// corners `radius-xl`; along a side `width` wide and the window's height, its
// open edge's corners `radius-lg`. A modal dialog in the tree named `label`,
// labelled by the element keyed `key + 1`; Escape fires `dismiss` and a press
// outside fires `outside` (normally the same action).
fn sheet_frame(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, column: widget.Node, dismiss: *const widget.Submit, outside: widget.Submit, placement: widget.Placement, width: f32, height: f32, drag_offset: f32) -> (widget.Node, err) {
    let bottom = placement == .Below
    let (body, body_error) = mem.alloc[widget.Node](a, 5usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = column
    var raised = control.surface_options(t)
    raised.background = .SurfaceContainerLow
    raised.elevation = 3u8
    raised.padding = 0.0
    var panel = control.surface_style(t, raised)
    panel.overflow = .Clip
    panel.width = style.Length { Percent: 100.0 }
    panel.height = style.Length { Percent: 100.0 }
    if width > 0.0 { panel.width = style.Length { Px: width } }
    if bottom {
        let content_high: style.Length = .Auto
        panel.height = content_high
        if height > 0.0 { panel.height = style.Length { Px: height } }
        panel.max_width = style.Length { Px: 640.0 }
        let xl = t.tokens.radii.xl
        panel.corners = style.Corners { top_left: xl, top_right: xl, bottom_right: 0.0, bottom_left: 0.0 }
    } else {
        let lg = t.tokens.radii.lg
        panel.corners = style.Corners { top_left: lg, top_right: 0.0, bottom_right: 0.0, bottom_left: lg }
        if placement == .Left { panel.corners = style.Corners { top_left: 0.0, top_right: lg, bottom_right: lg, bottom_left: 0.0 } }
    }
    body[1usize] = widget.box(0u64, panel, body[0usize..1usize])
    var placed = body[1usize]
    if bottom {
        if drag_offset > 0.0 && height > 0.0 {
            var slot = style.defaults()
            slot.width = style.Length { Percent: 100.0 }
            slot.max_width = style.Length { Px: 640.0 }
            slot.height = style.Length { Px: height }
            body[2usize] = widget.positioned(0u64, 0.0, drag_offset, slot, body[1usize..2usize])
            body[3usize] = widget.stack(0u64, slot, body[2usize..3usize])
            placed = body[3usize]
        }
        var centre = style.defaults()
        centre.width = style.Length { Percent: 100.0 }
        body[4usize] = placed
        placed = widget.aligned(0u64, .Center, .End, centre, body[4usize..5usize])
    }
    body[4usize] = placed
    var none: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: zero, cancel_action: *dismiss, keys: zero }, style.defaults(), body[4usize..5usize])
    var sem: widget.Semantics = zero
    sem.role = 23u8
    sem.label = label
    sem.states = accessibility.STATE_MODAL
    sem.labelled_by = key + 1u64
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    let (made, made_error) = with_scrim(a, t, widget.overlay(key, widget.Overlay { anchor: 0u64, placement: placement, offset: zero, modal: true, dismiss: outside }, style.defaults(), framed[0usize..1usize]))
    ret (made, made_error)
}

fn standard_sheet_frame(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, column: widget.Node, placement: widget.Placement, width: f32, height: f32) -> (widget.Node, err) {
    let bottom = placement == .Below
    let (panel_body, panel_body_error) = mem.alloc[widget.Node](a, 1usize)
    if panel_body_error != ok { ret (zero, TooLarge) }
    panel_body[0usize] = column
    var surface = control.surface_options(t)
    surface.background = .SurfaceContainerLow
    surface.elevation = 0u8
    if bottom { surface.elevation = 1u8 }
    surface.radius = 0.0
    surface.padding = 0.0
    var panel = control.surface_style(t, surface)
    panel.width = style.Length { Flex: 1.0 }
    panel.height = style.Length { Percent: 100.0 }
    panel.overflow = .Clip
    let panel_node = widget.box(0u64, panel, panel_body[0usize..1usize])
    var edge_axis: ui_layout.Axis = .Vertical
    if bottom { edge_axis = .Horizontal }
    let (edge, edge_error) = control.divider(a, 0u64, t, edge_axis, 0.0)
    if edge_error != ok { ret (zero, edge_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = edge
    parts[1usize] = panel_node
    if placement == .Left {
        parts[0usize] = panel_node
        parts[1usize] = edge
    }
    var frame = style.defaults()
    frame.width = style.Length { Px: width }
    frame.height = style.Length { Percent: 100.0 }
    var axis: ui_layout.Axis = .Horizontal
    if bottom {
        axis = .Vertical
        frame.width = style.Length { Percent: 100.0 }
        frame.max_width = style.Length { Px: 640.0 }
    }
    if height > 0.0 { frame.height = style.Length { Px: height } }
    let sheet_node = widget.flex(0u64, ui_layout.Flex { axis: axis, main: .Start, cross: .Stretch, gap: 0.0 }, frame, parts[0usize..2usize])
    let (semantic_body, semantic_body_error) = mem.alloc[widget.Node](a, 1usize)
    if semantic_body_error != ok { ret (zero, TooLarge) }
    semantic_body[0usize] = sheet_node
    var sem: widget.Semantics = zero
    sem.role = accessibility.ROLE_REGION
    sem.label = label
    sem.labelled_by = key + 1u64
    ret (widget.semantics(key, sem, style.defaults(), semantic_body[0usize..1usize]), ok)
}

// v2 (D977): an action sheet's row, full width, 48 tall, 16 at the sides, the
// `body-large` label in `ink` under the `on-surface` state layer; a button in the
// tree.
fn sheet_row(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, ink: paint.Color, action: *const widget.Submit) -> (widget.Node, err) {
    let (made, made_error) = sheet_row_with_icon(a, key, t, label, ink, .Info, false, false, action)
    ret (made, made_error)
}

fn sheet_row_with_icon(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, ink: paint.Color, icon: control.GlyphKind, has_icon: bool, destructive: bool, action: *const widget.Submit) -> (widget.Node, err) {
    let state = control.control_state(t, key, true, false)
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = control.with_alpha(style.color(t.tokens, .OnSurface), control.state_opacity(t, state))
    look.foreground = ink
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = 0.0
    look.custom_padding = true
    look.padding = 16.0
    look.padding_y = control.max_zero((48.0 - style.text_style(t.tokens, .BodyLarge).line_height) * 0.5)
    look.min_height = 48.0
    look.min_width = 24.0
    var caption = control.text_options()
    caption.role = .BodyLarge
    caption.wrap = .None
    let (said, said_error) = control.colored_text(a, 0u64, label, t, caption, ink)
    if said_error != ok { ret (zero, said_error) }
    var content = said
    if has_icon {
        var icon_ink = style.color(t.tokens, .OnSurfaceVariant)
        if destructive { icon_ink = ink }
        let (mark, mark_error) = control.icon_square(a, icon_ink, icon, 24.0)
        if mark_error != ok { ret (zero, mark_error) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
        if parts_error != ok { ret (zero, TooLarge) }
        parts[0usize] = mark
        parts[1usize] = said
        content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 16.0 }, style.defaults(), parts[0usize..2usize])
    }
    let (made, made_error) = control.pressable_states_fill(a, key, t, 3u8, label, look, true, false, 0u32, 0u32, 0u64, action, true, content)
    ret (made, made_error)
}

// An action sheet: a bottom sheet of the actions keyed `key + 3 + index` (the
// destructive ones in the error colour) with a Cancel (keyed `key + 3 + count`)
// last that fires `dismiss`.
// v2 (D977, docs/ux/components/ActionSheet, sheet of rows): the modal bottom
// sheet (`surface-container-low`, `radius-xl` top corners, elevation 3, the drag
// handle, over the scrim), as tall as its content; the `title` (empty for none)
// a header in `body-small` `on-surface-variant` keyed `key + 1`, 16 in, 4 above
// and 8 below; the actions `sheet_row`s in `on-surface`, a destructive one in
// `error` after a 1px `outline-variant` divider with 8 around; Cancel last after
// another divider. Escape, the scrim and Cancel fire `dismiss`.
// ponytail: no leading icons, grouped iOS cards or pointer-host menu form, and
// no host locale service -- callers provide translated copy when needed.
fn action_sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, buttons: []const DialogButton, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let (made, made_error) = action_sheet_localized(a, key, t, title, buttons, "Cancel", open, dismiss)
    ret (made, made_error)
}

fn action_sheet_localized(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, buttons: []const DialogButton, cancel_label: str, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    var no_icons: []const control.GlyphKind = zero
    let (made, made_error) = action_sheet_form(a, key, t, title, buttons, no_icons, cancel_label, true, open, dismiss)
    ret (made, made_error)
}

fn action_sheet_android(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, buttons: []const DialogButton, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    var no_icons: []const control.GlyphKind = zero
    let (made, made_error) = action_sheet_form(a, key, t, title, buttons, no_icons, "", false, open, dismiss)
    ret (made, made_error)
}

fn action_sheet_android_with_icons(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, buttons: []const DialogButton, icons: []const control.GlyphKind, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let (made, made_error) = action_sheet_form(a, key, t, title, buttons, icons, "", false, open, dismiss)
    ret (made, made_error)
}

fn action_sheet_menu(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, title: str, buttons: []const DialogButton, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let (commands, commands_error) = mem.alloc[MenuCommand](a, buttons.len)
    if commands_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < buttons.len {
        commands[i] = menu_command(buttons[i].label, buttons[i].action)
        commands[i].destructive = buttons[i].kind == .Destructive
        commands[i].separated = commands[i].destructive
        i += 1usize
    }
    let (made, made_error) = menu_of(a, key, t, anchor, title, commands[0usize..buttons.len], open, dismiss)
    ret (made, made_error)
}

fn ios_action_row(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, ink: paint.Color, strong: bool, action: *const widget.Submit) -> (widget.Node, err) {
    let state = control.control_state(t, key, true, false)
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = control.with_alpha(style.color(t.tokens, .OnSurface), control.state_opacity(t, state))
    look.foreground = ink
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = 0.0
    look.custom_padding = true
    look.padding = 16.0
    look.padding_y = 16.0
    look.min_height = 56.0
    look.min_width = 24.0
    var caption = control.text_options()
    caption.role = .BodyLarge
    if strong { caption.role = .TitleMedium }
    caption.align = .Center
    caption.wrap = .None
    let (said, said_error) = control.colored_text(a, 0u64, label, t, caption, ink)
    if said_error != ok { ret (zero, said_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = said
    var centred = style.defaults()
    centred.width = style.Length { Percent: 100.0 }
    let content = widget.aligned(0u64, .Center, .Center, centred, held[0usize..1usize])
    let (made, made_error) = control.pressable_states_fill(a, key, t, 3u8, label, look, true, false, 0u32, 0u32, 0u64, action, true, content)
    ret (made, made_error)
}

fn action_sheet_ios(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, buttons: []const DialogButton, cancel_label: str, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    if buttons.len > 6usize { ret (zero, TooLarge) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, 2usize * buttons.len + 1usize)
    if rows_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    if title.len > 0usize {
        var heading = control.text_options()
        heading.role = .BodySmall
        let (said, said_error) = control.colored_text(a, key + 1u64, title, t, heading, style.color(t.tokens, .OnSurfaceVariant))
        if said_error != ok { ret (zero, said_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 2usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = said
        var centred = style.defaults()
        centred.width = style.Length { Percent: 100.0 }
        held[1usize] = widget.aligned(0u64, .Center, .Center, centred, held[0usize..1usize])
        rows[n] = widget.padded(0u64, 16.0, 12.0, 16.0, 12.0, style.defaults(), held[1usize..2usize])
        n += 1usize
    }
    var i = 0usize
    while i < buttons.len {
        if i > 0usize {
            let (rule, rule_error) = control.divider(a, 0u64, t, .Horizontal, 0.0)
            if rule_error != ok { ret (zero, rule_error) }
            rows[n] = rule
            n += 1usize
        }
        var ink = style.color(t.tokens, .Primary)
        if buttons[i].kind == .Destructive { ink = style.color(t.tokens, .Error) }
        let (row, row_error) = ios_action_row(a, key + 3u64 + u64(i), t, buttons[i].label, ink, false, &buttons[i].action)
        if row_error != ok { ret (zero, row_error) }
        rows[n] = row
        n += 1usize
        i += 1usize
    }
    var card_options = control.surface_options(t)
    card_options.background = .SurfaceContainerHigh
    card_options.elevation = 3u8
    card_options.radius = t.tokens.radii.md
    card_options.padding = 0.0
    var card_style = control.surface_style(t, card_options)
    card_style.width = style.Length { Percent: 100.0 }
    card_style.overflow = .Clip
    let action_column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), rows[0usize..n])
    let (groups, groups_error) = mem.alloc[widget.Node](a, 2usize)
    if groups_error != ok { ret (zero, TooLarge) }
    let (action_body, action_body_error) = mem.alloc[widget.Node](a, 1usize)
    if action_body_error != ok { ret (zero, TooLarge) }
    action_body[0usize] = action_column
    groups[0usize] = widget.box(0u64, card_style, action_body[0usize..1usize])
    let (cancel, cancel_error) = ios_action_row(a, key + 3u64 + u64(buttons.len), t, cancel_label, style.color(t.tokens, .Primary), true, dismiss)
    if cancel_error != ok { ret (zero, cancel_error) }
    let (cancel_body, cancel_body_error) = mem.alloc[widget.Node](a, 1usize)
    if cancel_body_error != ok { ret (zero, TooLarge) }
    cancel_body[0usize] = cancel
    groups[1usize] = widget.box(0u64, card_style, cancel_body[0usize..1usize])
    var group_style = style.defaults()
    group_style.width = style.Length { Percent: 100.0 }
    let grouped = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 8.0 }, group_style, groups[0usize..2usize])
    let (inset_body, inset_body_error) = mem.alloc[widget.Node](a, 1usize)
    if inset_body_error != ok { ret (zero, TooLarge) }
    inset_body[0usize] = grouped
    let inset = widget.padded(0u64, 8.0, 0.0, 8.0, 8.0, group_style, inset_body[0usize..1usize])
    let (placed_body, placed_body_error) = mem.alloc[widget.Node](a, 1usize)
    if placed_body_error != ok { ret (zero, TooLarge) }
    placed_body[0usize] = inset
    let placed = widget.aligned(0u64, .Center, .End, group_style, placed_body[0usize..1usize])
    let (scoped_body, scoped_body_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_body_error != ok { ret (zero, TooLarge) }
    scoped_body[0usize] = placed
    var none: []const widget.Shortcut = zero
    let scoped = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: zero, cancel_action: *dismiss, keys: zero }, style.defaults(), scoped_body[0usize..1usize])
    let (semantic_body, semantic_body_error) = mem.alloc[widget.Node](a, 1usize)
    if semantic_body_error != ok { ret (zero, TooLarge) }
    semantic_body[0usize] = scoped
    var sem: widget.Semantics = zero
    sem.role = 23u8
    sem.label = title
    sem.states = accessibility.STATE_MODAL
    if title.len > 0usize { sem.labelled_by = key + 1u64 }
    let framed = widget.semantics(0u64, sem, style.defaults(), semantic_body[0usize..1usize])
    let (framed_body, framed_body_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_body_error != ok { ret (zero, TooLarge) }
    framed_body[0usize] = framed
    let top = widget.overlay(key, widget.Overlay { anchor: 0u64, placement: .Below, offset: zero, modal: true, dismiss: *dismiss }, style.defaults(), framed_body[0usize..1usize])
    let (made, made_error) = with_scrim(a, t, top)
    ret (made, made_error)
}

fn action_sheet_form(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, buttons: []const DialogButton, icons: []const control.GlyphKind, cancel_label: str, has_cancel: bool, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    if icons.len != 0usize && icons.len != buttons.len { ret (zero, TooLarge) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, 2usize * buttons.len + 5usize)
    if rows_error != ok { ret (zero, TooLarge) }
    let (grips, grips_error) = mem.alloc[widget.Node](a, 2usize)
    if grips_error != ok { ret (zero, TooLarge) }
    rows[0usize] = sheet_handle(t, grips[0usize..1usize])
    var n = 1usize
    if title.len > 0usize {
        var small = control.text_options()
        small.role = .BodySmall
        let (said, said_error) = control.colored_text(a, key + 1u64, title, t, small, style.color(t.tokens, .OnSurfaceVariant))
        if said_error != ok { ret (zero, said_error) }
        grips[1usize] = said
        rows[n] = widget.padded(0u64, 16.0, 20.0, 16.0, 8.0, style.defaults(), grips[1usize..2usize])
        n += 1usize
    } else {
        rows[n] = widget.box(0u64, control.sized_style(1.0, 16.0), zero)
        n += 1usize
    }
    var i = 0usize
    var count = buttons.len
    if has_cancel { count += 1usize }
    while i < count {
        let cancelling = i == buttons.len
        var ink = style.color(t.tokens, .OnSurface)
        if !cancelling && buttons[i].kind == .Destructive { ink = style.color(t.tokens, .Error) }
        if cancelling || buttons[i].kind == .Destructive {
            let (rule, rule_error) = control.divider(a, 0u64, t, .Horizontal, 0.0)
            if rule_error != ok { ret (zero, rule_error) }
            let (lines, lines_error) = mem.alloc[widget.Node](a, 1usize)
            if lines_error != ok { ret (zero, TooLarge) }
            lines[0usize] = rule
            rows[n] = widget.padded(0u64, 0.0, 8.0, 0.0, 8.0, style.defaults(), lines[0usize..1usize])
            n += 1usize
        }
        var made: widget.Node = zero
        if cancelling {
            let (row, row_error) = sheet_row(a, key + 3u64 + u64(i), t, cancel_label, ink, dismiss)
            if row_error != ok { ret (zero, row_error) }
            made = row
        } else {
            var row: widget.Node = zero
            var row_error: err = ok
            if icons.len == buttons.len {
                let (icon_row, icon_row_error) = sheet_row_with_icon(a, key + 3u64 + u64(i), t, buttons[i].label, ink, icons[i], true, buttons[i].kind == .Destructive, &buttons[i].action)
                row = icon_row
                row_error = icon_row_error
            } else {
                let (plain_row, plain_row_error) = sheet_row(a, key + 3u64 + u64(i), t, buttons[i].label, ink, &buttons[i].action)
                row = plain_row
                row_error = plain_row_error
            }
            if row_error != ok { ret (zero, row_error) }
            made = row
        }
        rows[n] = made
        n += 1usize
        i += 1usize
    }
    rows[n] = widget.box(0u64, control.sized_style(1.0, 8.0), zero)
    n += 1usize
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), rows[0usize..n])
    let (made, made_error) = sheet_frame(a, key, t, title, column, dismiss, *dismiss, .Below, 0.0, 0.0, 0.0)
    ret (made, made_error)
}

// ------------------------------------------------------------- pickers (D842, P2-10)

// Two decimal digits of `value` (0..99) into `out` at `at`; the new position.
fn write_two(out: []u8, at: usize, value: i64) -> usize {
    if at + 2usize > out.len { ret at }
    out[at] = u8(48i64 + value / 10i64 % 10i64)
    out[at + 1usize] = u8(48i64 + value % 10i64)
    ret at + 2usize
}

// A date as `YYYY-MM-DD` into `out`; the length.
fn write_date(out: []u8, d: time.Date) -> usize {
    let year_len = control.write_i64(out, i64(d.year))
    if year_len == 0usize || year_len + 6usize > out.len { ret 0usize }
    out[year_len] = 45u8
    var at = write_two(out, year_len + 1usize, i64(d.month))
    out[at] = 45u8
    ret write_two(out, at + 1usize, i64(d.day))
}

// The weekday of a date, Monday 0 to Sunday 6.
fn weekday_of(year: i64, month: i64, day: i64) -> i64 {
    // 1970-01-01 was a Thursday, day 3 from Monday.
    let days = time.days_from_civil(year, month, day) + 3i64
    let w = days % 7i64
    if w < 0i64 { ret w + 7i64 }
    ret w
}

// A calendar's pick of one day, and a turn to another month.
type DayPick = struct { day: time.Date, pick: widget.Change[time.Date] }

fn day_fire(ctx: *void) -> err {
    let p = mem.cast[*DayPick](ctx)
    ret widget.fire_change[time.Date](p.pick, p.day)
}

// Whether `d` lies in `from..to` inclusive (both given), for a range's tint.
fn within_range(d: time.Date, from: time.Date, to: time.Date) -> bool {
    let n = time.days_from_civil(i64(d.year), i64(d.month), i64(d.day))
    let lo = time.days_from_civil(i64(from.year), i64(from.month), i64(from.day))
    let hi = time.days_from_civil(i64(to.year), i64(to.month), i64(to.day))
    ret n >= lo && n <= hi
}

fn same_date(a: time.Date, b: time.Date) -> bool {
    ret a.year == b.year && a.month == b.month && a.day == b.day
}

// A calendar of the month `shown` (its day is ignored): a header of the month
// and year, a Previous button (keyed `key + 1`) and a Next button (`key + 2`),
// each reporting the first of the neighbouring month through `show`; then the
// weekday row and the weeks, Monday first, a day button keyed `key + 3 + day`
// reporting its date through `pick`, the day of `selected` marked and the days
// from `from` to `to` (when `ranged`) banded. A grid in the tree named `label`,
// seven columns.
fn calendar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, shown: time.Date, selected: time.Date, has_selected: bool, ranged: bool, from: time.Date, to: time.Date, show: widget.Change[time.Date], pick: widget.Change[time.Date]) -> (widget.Node, err) {
    let (made, made_error) = calendar_marked(a, key, t, label, shown, selected, has_selected, ranged, from, to, shown, false, show, pick)
    ret (made, made_error)
}

// The same with `today` marked when `has_today`.
// v2 (D959, docs/ux/components/Calendar): cells 32 with a pointer (224 wide), 40
// on touch (280) with 4 between the weeks; the header 32 tall and 8 above the
// weekdays (48 on touch) holds the month's name and year in `title-small`
// `on-surface` (`label-large` `on-surface-variant` on touch), then Previous and
// Next as round icon buttons the cell's size with `chevron-left` / `chevron-right`
// 18 (24 on touch) in `on-surface-variant`; the weekday row says Mo Tu We (M T W on
// touch) in `label-medium` `on-surface-variant`. A day is a disc the cell's size,
// its digits centred in `body-medium` `on-surface` under the `on-surface` state
// layer; today is a 1px `primary` ring with `primary` digits; the selected day --
// and in range mode both ends -- a `primary` disc with `on-primary` digits (winning
// over today); between the ends a `primary-container` band, reaching half a cell
// under each end's disc, with `on-primary-container` digits. Days of the
// neighbouring months stay empty cells.
// ponytail: Monday first and English names; the locale's first day and month names, the year view, week numbers, event dots and unavailable days are still to come.
fn calendar_marked(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, shown: time.Date, selected: time.Date, has_selected: bool, ranged: bool, from: time.Date, to: time.Date, today: time.Date, has_today: bool, show: widget.Change[time.Date], pick: widget.Change[time.Date]) -> (widget.Node, err) {
    let year = i64(shown.year)
    let month = i64(shown.month)
    if month < 1i64 || month > 12i64 { ret (zero, TooLarge) }
    let days = time.days_in_month(year, month)
    let first_weekday = weekday_of(year, month, 1i64)
    let (turns, turns_error) = mem.alloc[DayPick](a, 2usize + usize(days))
    if turns_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize + usize(days))
    if actions_error != ok { ret (zero, TooLarge) }
    var previous = time.Date { year: shown.year, month: shown.month - 1u8, day: 1u8 }
    if shown.month == 1u8 { previous = time.Date { year: shown.year - 1i32, month: 12u8, day: 1u8 } }
    var next = time.Date { year: shown.year, month: shown.month + 1u8, day: 1u8 }
    if shown.month == 12u8 { next = time.Date { year: shown.year + 1i32, month: 1u8, day: 1u8 } }
    turns[0usize] = DayPick { day: previous, pick: show }
    turns[1usize] = DayPick { day: next, pick: show }
    actions[0usize] = widget.Submit { ctx: mem.cast[*void](&turns[0usize]), invoke: day_fire }
    actions[1usize] = widget.Submit { ctx: mem.cast[*void](&turns[1usize]), invoke: day_fire }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var cell = t.tokens.sizes.control_sm
    var week_gap: f32 = 0.0
    var icon = t.tokens.sizes.icon_sm
    var head_height = t.tokens.sizes.control_sm
    var head_below: f32 = 8.0
    if touch {
        cell = t.tokens.sizes.control_md
        week_gap = 4.0
        icon = t.tokens.sizes.icon_md
        head_height = t.tokens.sizes.control_lg
        head_below = 0.0
    }
    let ink = style.color(t.tokens, .OnSurface)
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let primary = style.color(t.tokens, .Primary)
    let clear = paint.rgba(0.0, 0.0, 0.0, 0.0)
    // The header: the month and year, then Previous and Next at the end.
    let (head, head_error) = mem.alloc[widget.Node](a, 3usize)
    if head_error != ok { ret (zero, TooLarge) }
    let (title_bytes, title_error) = mem.alloc[u8](a, 24usize)
    if title_error != ok { ret (zero, TooLarge) }
    var title_len = control.copy_text(title_bytes, month_name(month))
    title_bytes[title_len] = 32u8
    title_len += 1usize
    title_len += control.write_i64(title_bytes[title_len..], year)
    var heading = control.text_options()
    heading.role = .TitleSmall
    heading.wrap = .None
    var heading_color = ink
    if touch {
        heading.role = .LabelLarge
        heading_color = muted
    }
    let (title_node, title_node_error) = control.colored_text(a, 0u64, title_bytes[0usize..title_len], t, heading, heading_color)
    if title_node_error != ok { ret (zero, title_node_error) }
    var spread = title_node
    spread.style.width = style.Length { Flex: 1.0 }
    head[0usize] = spread
    let (back, back_error) = month_turn(a, key + 1u64, t, .ChevronLeft, "Previous month", &actions[0usize], cell, icon)
    if back_error != ok { ret (zero, back_error) }
    head[1usize] = back
    let (forward, forward_error) = month_turn(a, key + 2u64, t, .ChevronRight, "Next month", &actions[1usize], cell, icon)
    if forward_error != ok { ret (zero, forward_error) }
    head[2usize] = forward
    // The weekdays.
    let (names, names_error) = mem.alloc[widget.Node](a, 7usize)
    if names_error != ok { ret (zero, TooLarge) }
    var weekday = 0usize
    while weekday < 7usize {
        var caption = control.text_options()
        caption.role = .LabelMedium
        caption.wrap = .None
        let (name_node, name_error) = control.colored_text(a, 0u64, weekday_name(weekday, touch), t, caption, muted)
        if name_error != ok { ret (zero, name_error) }
        let (named, named_error) = mem.alloc[widget.Node](a, 1usize)
        if named_error != ok { ret (zero, TooLarge) }
        named[0usize] = name_node
        names[weekday] = widget.aligned(0u64, .Center, .Center, control.sized_style(cell, cell), named[0usize..1usize])
        weekday += 1usize
    }
    // The days: blanks before the first, then a disc a day, in rows of seven.
    let slots = usize(first_weekday) + usize(days)
    let weeks = (slots + 6usize) / 7usize
    let (rows, rows_error) = mem.alloc[widget.Node](a, weeks)
    if rows_error != ok { ret (zero, TooLarge) }
    var week = 0usize
    while week < weeks {
        let (cells, cells_error) = mem.alloc[widget.Node](a, 7usize)
        if cells_error != ok { ret (zero, TooLarge) }
        var column = 0usize
        while column < 7usize {
            let slot = week * 7usize + column
            var made = widget.box(0u64, control.sized_style(cell, cell), zero)
            if slot >= usize(first_weekday) && slot < slots {
                let day = slot - usize(first_weekday) + 1usize
                let date = time.Date { year: shown.year, month: shown.month, day: u8(day) }
                turns[1usize + day] = DayPick { day: date, pick: pick }
                actions[1usize + day] = widget.Submit { ctx: mem.cast[*void](&turns[1usize + day]), invoke: day_fire }
                var end = has_selected && same_date(date, selected)
                if ranged { end = has_selected && (same_date(date, from) || same_date(date, to)) }
                let spans = ranged && !same_date(from, to)
                let inside = spans && within_range(date, from, to)
                let marked = has_today && same_date(date, today) && !end
                var fill = clear
                var digit_color = ink
                var layer_color = ink
                if inside { digit_color = style.color(t.tokens, .OnPrimaryContainer) }
                if marked { digit_color = primary }
                if end {
                    fill = primary
                    digit_color = style.color(t.tokens, .OnPrimary)
                    layer_color = digit_color
                }
                let day_key = key + 3u64 + u64(day)
                let state = control.control_state(t, day_key, true, end)
                var look = style.resolve(t.tokens, .Plain, state)
                look.background = style.layer(fill, layer_color, control.state_opacity(t, state))
                look.foreground = digit_color
                look.border = primary
                look.border_width = 0.0
                if marked { look.border_width = 1.0 }
                look.radius = cell * 0.5
                look.custom_padding = true
                look.padding = 0.0
                look.padding_start = 0.0
                look.padding_y = 0.0
                look.min_width = cell
                look.min_height = cell
                let (digits, digits_error) = mem.alloc[u8](a, 4usize)
                if digits_error != ok { ret (zero, TooLarge) }
                let digit_count = control.write_i64(digits, i64(day))
                var caption = control.text_options()
                caption.role = .BodyMedium
                caption.wrap = .None
                let (label_node, label_error) = control.colored_text(a, 0u64, digits[0usize..digit_count], t, caption, digit_color)
                if label_error != ok { ret (zero, label_error) }
                let (centred, centred_error) = mem.alloc[widget.Node](a, 1usize)
                if centred_error != ok { ret (zero, TooLarge) }
                centred[0usize] = label_node
                let content = widget.aligned(0u64, .Center, .Center, control.sized_style(cell, cell), centred[0usize..1usize])
                let (pressed, pressed_error) = control.pressable_states(a, day_key, t, 3u8, digits[0usize..digit_count], look, true, end, 0u32, 0u32, 0u64, &actions[1usize + day], content)
                if pressed_error != ok { ret (zero, pressed_error) }
                var sized = pressed
                sized.style.width = style.Length { Px: cell }
                sized.style.height = style.Length { Px: cell }
                made = sized
                if inside {
                    // The band: the whole cell between the ends, the inner half at an end.
                    var band_x: f32 = 0.0
                    var band_width = cell
                    if same_date(date, from) {
                        band_x = cell * 0.5
                        band_width = cell * 0.5
                    }
                    if same_date(date, to) { band_width = cell * 0.5 }
                    var band = control.sized_style(band_width, cell)
                    band.background = paint.Brush { Solid: style.color(t.tokens, .PrimaryContainer) }
                    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
                    if layers_error != ok { ret (zero, TooLarge) }
                    var none: []const widget.Node = zero
                    layers[0usize] = widget.positioned(0u64, band_x, 0.0, band, none)
                    layers[1usize] = sized
                    made = widget.stack(0u64, control.sized_style(cell, cell), layers[0usize..2usize])
                }
            }
            cells[column] = made
            column += 1usize
        }
        rows[week] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..7usize])
        week += 1usize
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var head_style = control.sized_style(7.0 * cell, head_height)
    head_style.margin.bottom = style.Length { Px: head_below }
    parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, head_style, head[0usize..3usize])
    parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), names[0usize..7usize])
    parts[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: week_gap }, style.defaults(), rows[0usize..weeks])
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..3usize])
    var sem: widget.Semantics = zero
    sem.role = 30u8
    sem.label = label
    sem.column_count = 7u32
    sem.row_count = u32(weeks)
    ret (widget.semantics(key, sem, style.defaults(), column_node[0usize..1usize]), ok)
}

// A calendar's Previous or Next: a round icon button `size` across, its chevron
// `icon` in `on-surface-variant` under that colour's state layer.
fn month_turn(a: *mem.Arena, key: widget.Key, t: *const control.Theme, kind: control.GlyphKind, label: str, action: *const widget.Submit, size: f32, icon: f32) -> (widget.Node, err) {
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let state = control.control_state(t, key, true, false)
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), muted, control.state_opacity(t, state))
    look.foreground = muted
    look.border_width = 0.0
    look.radius = size * 0.5
    look.custom_padding = true
    look.padding = 0.0
    look.padding_start = 0.0
    look.padding_y = 0.0
    look.min_width = size
    look.min_height = size
    let (chevron, chevron_error) = control.mark_glyph(a, muted, kind, icon)
    if chevron_error != ok { ret (zero, chevron_error) }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
    inner[0usize] = chevron
    let content = widget.aligned(0u64, .Center, .Center, control.sized_style(size, size), inner[0usize..1usize])
    let (made, made_error) = control.pressable(a, key, t, 3u8, label, look, true, false, action, content)
    ret (made, made_error)
}

fn month_name(month: i64) -> str {
    if month == 1i64 { ret "January" }
    if month == 2i64 { ret "February" }
    if month == 3i64 { ret "March" }
    if month == 4i64 { ret "April" }
    if month == 5i64 { ret "May" }
    if month == 6i64 { ret "June" }
    if month == 7i64 { ret "July" }
    if month == 8i64 { ret "August" }
    if month == 9i64 { ret "September" }
    if month == 10i64 { ret "October" }
    if month == 11i64 { ret "November" }
    ret "December"
}

// Monday 0 to Sunday 6: short names with a pointer, narrow ones on touch.
fn weekday_name(day: usize, narrow: bool) -> str {
    if narrow {
        if day == 0usize { ret "M" }
        if day == 1usize || day == 3usize { ret "T" }
        if day == 2usize { ret "W" }
        if day == 4usize { ret "F" }
        ret "S"
    }
    if day == 0usize { ret "Mo" }
    if day == 1usize { ret "Tu" }
    if day == 2usize { ret "We" }
    if day == 3usize { ret "Th" }
    if day == 4usize { ret "Fr" }
    if day == 5usize { ret "Sa" }
    ret "Su"
}

// A date picker: a field (keyed `key`) showing `value` as `YYYY-MM-DD` (or the
// label while there is none) firing `toggle`, with a calendar (keyed `key + 2`,
// in a flyout keyed `key + 1`) of the month `shown` below it while `open`; a pick
// reaches `pick`, a month turn `show`, and the flyout's dismissal is `toggle` again.
fn date_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, value: time.Date, has_value: bool, open: bool, toggle: *const widget.Submit, shown: time.Date, show: widget.Change[time.Date], pick: widget.Change[time.Date]) -> (widget.Node, err) {
    let (made, made_error) = dated(a, key, t, label, value, has_value, false, value, value, open, toggle, shown, show, pick)
    ret (made, made_error)
}

// A date range picker: the same over `from` and `to`, the field showing both,
// both ends marked and the days between banded; a pick reaches `pick` and the
// caller decides which end it sets.
fn date_range_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, from: time.Date, to: time.Date, has_range: bool, open: bool, toggle: *const widget.Submit, shown: time.Date, show: widget.Change[time.Date], pick: widget.Change[time.Date]) -> (widget.Node, err) {
    let (made, made_error) = dated(a, key, t, label, from, has_range, true, from, to, open, toggle, shown, show, pick)
    ret (made, made_error)
}

// v2 (D959, docs/ux/components/DatePicker, docked): the field is the outlined
// read-only field (control.field_head) 40 tall with a pointer and 56 on touch, the
// label in its notch once a date is set, a trailing calendar mark 18 (24 on touch)
// in `on-surface-variant`, `primary` in the 2px `primary` outline while open, the
// field saying Expanded. The calendar stands 4 below it on `surface-container-high`
// with 12 corners and elevation 2, 8 above it and 12 at the sides and below, as
// wide as seven cells and 32 (256 with a pointer).
// ponytail: the value is typed by nobody and written YYYY-MM-DD; typing, the locale's format, Today and Clear, the modal form for touch and inline errors wait on a date field that owns its text.
fn dated(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, value: time.Date, has_value: bool, ranged: bool, from: time.Date, to: time.Date, open: bool, toggle: *const widget.Submit, shown: time.Date, show: widget.Change[time.Date], pick: widget.Change[time.Date]) -> (widget.Node, err) {
    let (text_bytes, text_error) = mem.alloc[u8](a, 32usize)
    if text_error != ok { ret (zero, TooLarge) }
    var caption: str = label
    if has_value {
        var n = write_date(text_bytes, value)
        if ranged && n > 0usize && n + 13usize <= text_bytes.len {
            text_bytes[n] = 32u8
            text_bytes[n + 1usize] = 45u8
            text_bytes[n + 2usize] = 32u8
            n = n + 3usize + write_date(text_bytes[n + 3usize..text_bytes.len], to)
        }
        caption = text_bytes[0usize..n]
    }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var field_height = t.tokens.sizes.control_md
    var cell = t.tokens.sizes.control_sm
    if touch {
        field_height = t.tokens.sizes.control_xl
        cell = t.tokens.sizes.control_md
    }
    let (head, head_error) = control.field_head(a, key, t, label, caption, has_value, open, toggle, field_height, .Calendar, .Calendar, true)
    if head_error != ok { ret (zero, head_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    var popup_node = widget.box(0u64, style.defaults(), zero)
    if open {
        let (month, month_error) = calendar(a, key + 2u64, t, label, shown, value, has_value, ranged, from, to, show, pick)
        if month_error != ok { ret (zero, month_error) }
        let (inside, inside_error) = mem.alloc[widget.Node](a, 1usize)
        if inside_error != ok { ret (zero, TooLarge) }
        inside[0usize] = month
        var raised = control.surface_options(t)
        raised.background = .SurfaceContainerHigh
        raised.radius = t.tokens.radii.md
        raised.elevation = 2u8
        raised.padding = 12.0
        var raised_style = control.surface_style(t, raised)
        raised_style.padding.top = style.Length { Px: 8.0 }
        raised_style.width = style.Length { Px: 7.0 * cell + 32.0 }
        let (lifted, lifted_error) = dismissable(a, key + 1u64, key, .Below, label, widget.box(0u64, raised_style, inside[0usize..1usize]), toggle, 4.0)
        if lifted_error != ok { ret (zero, lifted_error) }
        popup_node = lifted
    }
    parts[1usize] = popup_node
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    if open { sem.states = accessibility.STATE_EXPANDED }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A part of a time of day stepped: which part, the whole value, whom to tell.
type TimePart = struct { part: u8, value: time.Time, change: widget.Change[time.Time] }

fn time_part_fire(ctx: *void, moved: i64) -> err {
    let p = mem.cast[*TimePart](ctx)
    var next = p.value
    if p.part == 0u8 { next.hour = u8(moved) }
    if p.part == 1u8 { next.minute = u8(moved) }
    if p.part == 2u8 { next.second = u8(moved) }
    ret widget.fire_change[time.Time](p.change, next)
}

// A time picker: D830's steppers for the hour (keyed `key + 1`), the minute
// (`key + 4`) and, when `seconds`, the second (`key + 7`), colons between; each
// step reaches `change` with the whole time. A group in the tree named `label`.
fn time_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, value: time.Time, seconds: bool, change: widget.Change[time.Time]) -> (widget.Node, err) {
    var count = 3usize
    if seconds { count = 5usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    let (ticks, ticks_error) = mem.alloc[TimePart](a, 3usize)
    if ticks_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < 3usize {
        ticks[i] = TimePart { part: u8(i), value: value, change: change }
        i += 1usize
    }
    let (hours, hours_error) = control.stepper(a, key + 1u64, t, "Hour", i64(value.hour), 0i64, 23i64, 1i64, widget.Change[i64] { ctx: mem.cast[*void](&ticks[0usize]), invoke: time_part_fire })
    if hours_error != ok { ret (zero, hours_error) }
    parts[0usize] = hours
    let (colon, colon_error) = control.text(a, 0u64, ":", t, control.text_options())
    if colon_error != ok { ret (zero, colon_error) }
    parts[1usize] = colon
    let (minutes, minutes_error) = control.stepper(a, key + 4u64, t, "Minute", i64(value.minute), 0i64, 59i64, 1i64, widget.Change[i64] { ctx: mem.cast[*void](&ticks[1usize]), invoke: time_part_fire })
    if minutes_error != ok { ret (zero, minutes_error) }
    parts[2usize] = minutes
    if seconds {
        parts[3usize] = colon
        let (secs, secs_error) = control.stepper(a, key + 7u64, t, "Second", i64(value.second), 0i64, 59i64, 1i64, widget.Change[i64] { ctx: mem.cast[*void](&ticks[2usize]), invoke: time_part_fire })
        if secs_error != ok { ret (zero, secs_error) }
        parts[4usize] = secs
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// A part of a duration stepped: hours, minutes or seconds of the whole.
type DurationPart = struct { part: u8, value: time.Duration, change: widget.Change[time.Duration] }

fn duration_part_fire(ctx: *void, moved: i64) -> err {
    let p = mem.cast[*DurationPart](ctx)
    let second = 1000000000i64
    let total = p.value.nanos / second
    var hours = total / 3600i64
    var minutes = total / 60i64 % 60i64
    var secs = total % 60i64
    if p.part == 0u8 { hours = moved }
    if p.part == 1u8 { minutes = moved }
    if p.part == 2u8 { secs = moved }
    ret widget.fire_change[time.Duration](p.change, time.Duration { nanos: (hours * 3600i64 + minutes * 60i64 + secs) * second })
}

// A duration picker: steppers for the hours (keyed `key + 1`, up to 999), the
// minutes (`key + 4`) and the seconds (`key + 7`) of `value`, each step reaching
// `change` with the whole duration; a group in the tree named `label`.
fn duration_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, value: time.Duration, change: widget.Change[time.Duration]) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 5usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (ticks, ticks_error) = mem.alloc[DurationPart](a, 3usize)
    if ticks_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < 3usize {
        ticks[i] = DurationPart { part: u8(i), value: value, change: change }
        i += 1usize
    }
    let total = value.nanos / 1000000000i64
    let (hours, hours_error) = control.stepper(a, key + 1u64, t, "Hours", total / 3600i64, 0i64, 999i64, 1i64, widget.Change[i64] { ctx: mem.cast[*void](&ticks[0usize]), invoke: duration_part_fire })
    if hours_error != ok { ret (zero, hours_error) }
    parts[0usize] = hours
    let (colon, colon_error) = control.text(a, 0u64, ":", t, control.text_options())
    if colon_error != ok { ret (zero, colon_error) }
    parts[1usize] = colon
    let (minutes, minutes_error) = control.stepper(a, key + 4u64, t, "Minutes", total / 60i64 % 60i64, 0i64, 59i64, 1i64, widget.Change[i64] { ctx: mem.cast[*void](&ticks[1usize]), invoke: duration_part_fire })
    if minutes_error != ok { ret (zero, minutes_error) }
    parts[2usize] = minutes
    parts[3usize] = colon
    let (secs, secs_error) = control.stepper(a, key + 7u64, t, "Seconds", total % 60i64, 0i64, 59i64, 1i64, widget.Change[i64] { ctx: mem.cast[*void](&ticks[2usize]), invoke: duration_part_fire })
    if secs_error != ok { ret (zero, secs_error) }
    parts[4usize] = secs
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..5usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// v2 (D960, docs/ux/components/TimePicker, DurationPicker): the field both are on
// pointer hosts -- the outlined text field over the caller's buffer, 40 tall with
// a pointer and 56 on touch (`body-medium` at 40), a trailing `clock` 18 (24 on
// touch) in `on-surface-variant` (`primary` while open) centred in a 32 circle (40
// on touch) 4 in from the end -- over its supporting text `note` in `body-small`,
// 4 below and 16 in, `on-surface-variant` or `error` while invalid. The frame is
// keyed `key + 2`; the clock `key + 1` fires `toggle` when `opener`, and is a
// plain mark otherwise.
fn clocked_field(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], note: str, opener: bool, open: bool, toggle: *const widget.Submit, options: control.FieldOptions) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var h = t.tokens.sizes.control_md
    var side = t.tokens.sizes.control_sm
    var size = t.tokens.sizes.icon_sm
    if touch {
        h = t.tokens.sizes.control_xl
        side = t.tokens.sizes.control_md
        size = t.tokens.sizes.icon_md
    }
    var kept = options
    kept.height = h
    kept.end_space = control.max_zero(side + 4.0 - 16.0)
    let (edit_node, edit_error) = control.text_field(a, key, t, label, buffer, len, typed, zero, kept)
    if edit_error != ok { ret (zero, edit_error) }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var face_color = muted
    if open { face_color = style.color(t.tokens, .Primary) }
    let (face, face_error) = control.mark_glyph(a, face_color, .Clock, size)
    if face_error != ok { ret (zero, face_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 4usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[3usize] = face
    var end_mark = widget.aligned(key + 1u64, .Center, .Center, control.sized_style(side, side), layers[3usize..4usize])
    if opener {
        let state = control.control_state(t, key + 1u64, true, false)
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = control.with_alpha(muted, control.state_opacity(t, state))
        look.foreground = muted
        look.radius = side * 0.5
        look.custom_padding = true
        look.padding = (side - size) * 0.5
        look.padding_start = look.padding
        look.padding_y = look.padding
        look.min_width = side
        look.min_height = side
        var states = 0u32
        if open { states = accessibility.STATE_EXPANDED }
        let (pressed, pressed_error) = control.pressable_states(a, key + 1u64, t, 3u8, "Times", look, true, false, states, accessibility.ACTION_SHOW_MENU, key + 3u64, toggle, face)
        if pressed_error != ok { ret (zero, pressed_error) }
        end_mark = pressed
    }
    layers[2usize] = end_mark
    layers[0usize] = edit_node
    layers[1usize] = widget.positioned(0u64, options.width - 4.0 - side, control.max_zero((h - side) * 0.5), style.defaults(), layers[2usize..3usize])
    let framed = widget.stack(key + 2u64, style.defaults(), layers[0usize..2usize])
    if note.len == 0usize { ret (framed, ok) }
    var small = control.text_options()
    small.role = .BodySmall
    small.wrap = .None
    var note_color = muted
    if options.invalid { note_color = style.color(t.tokens, .Error) }
    let (note_node, note_error) = control.colored_text(a, 0u64, note, t, small, note_color)
    if note_error != ok { ret (zero, note_error) }
    let (lines, lines_error) = mem.alloc[widget.Node](a, 3usize)
    if lines_error != ok { ret (zero, TooLarge) }
    lines[2usize] = note_node
    var note_style = style.defaults()
    note_style.padding.left = style.Length { Px: 16.0 }
    note_style.padding.top = style.Length { Px: 4.0 }
    note_style.min_height = style.Length { Px: 4.0 + style.text_style(t.tokens, .BodySmall).line_height }
    lines[0usize] = framed
    lines[1usize] = widget.box(0u64, note_style, lines[2usize..3usize])
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), lines[0usize..2usize]), ok)
}

// A time list's row (D960): 32 tall, 12 each side, the time in `body-medium`
// `on-surface` and its offset at the end in `on-surface-variant` under the state
// layer; the selected row `secondary-container`, its time `on-secondary-container`.
fn time_row(a: *mem.Arena, key: widget.Key, t: *const control.Theme, clock_text: str, offset: str, chosen: bool, action: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let state = control.control_state(t, key, true, chosen)
    var fill = paint.rgba(0.0, 0.0, 0.0, 0.0)
    var words = style.color(t.tokens, .OnSurface)
    if chosen {
        fill = style.color(t.tokens, .SecondaryContainer)
        words = style.color(t.tokens, .OnSecondaryContainer)
    }
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = style.layer(fill, words, control.state_opacity(t, state))
    look.foreground = words
    look.border_width = 0.0
    look.radius = 0.0
    look.custom_padding = true
    look.padding = 12.0
    look.padding_start = 12.0
    look.padding_y = control.max_zero((t.tokens.sizes.control_sm - style.text_style(t.tokens, .BodyMedium).line_height) * 0.5)
    look.min_height = t.tokens.sizes.control_sm
    look.min_width = width
    var caption = control.text_options()
    caption.role = .BodyMedium
    caption.wrap = .None
    let (bits, bits_error) = mem.alloc[widget.Node](a, 2usize)
    if bits_error != ok { ret (zero, TooLarge) }
    let (time_node, time_error) = control.colored_text(a, 0u64, clock_text, t, caption, words)
    if time_error != ok { ret (zero, time_error) }
    let (offset_node, offset_error) = control.colored_text(a, 0u64, offset, t, caption, style.color(t.tokens, .OnSurfaceVariant))
    if offset_error != ok { ret (zero, offset_error) }
    bits[0usize] = time_node
    bits[1usize] = offset_node
    var spread = style.defaults()
    spread.min_width = style.Length { Px: control.max_zero(width - 24.0) }
    let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 12.0 }, spread, bits[0usize..2usize])
    let (made, made_error) = control.pressable(a, key, t, 3u8, clock_text, look, true, chosen, action, content)
    ret (made, made_error)
}

// A time field (D960): the clocked field (editor `key`, clock `key + 1`, frame
// `key + 2`) whose clock fires `toggle`; while `open`, the time list below it (the
// overlay keyed `key + 3`, its viewport `key + 4`, rows `key + 5 + index`), each
// row a time the caller wrote (`write_clock`) with its offset ("30 min", or empty),
// firing its own pick. Escape is `toggle`, Enter the selected pick. The caller
// keeps the text, parses it and reformats it on blur.
// v2 (D960, docs/ux/components/TimePicker, field with time list): the list is a
// menu at pointer density on `surface-container`, 8 corners, elevation 2, 8 above
// and below the rows, 4 below the field and as wide; 6 rows show and it scrolls
// to put the selected one first.
// ponytail: no dial, input mode or wheels for touch, no 12-hour clock, no Up/Down through the list or typing to filter it, no error icon; the caller's text and picks carry the value.
fn time_field(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], open: bool, toggle: *const widget.Submit, times: []const str, offsets: []const str, selected: usize, picks: []const widget.Submit, note: str, options: control.FieldOptions) -> (widget.Node, err) {
    if picks.len != times.len || offsets.len != times.len { ret (zero, TooLarge) }
    let (boxed, boxed_error) = clocked_field(a, key, t, label, buffer, len, typed, note, true, open, toggle, options)
    if boxed_error != ok { ret (zero, boxed_error) }
    let listing = open && times.len > 0usize
    var count = 1usize
    if listing { count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = boxed
    var default_action: widget.Submit = zero
    if listing {
        let row_height = t.tokens.sizes.control_sm
        let (items, items_error) = mem.alloc[widget.Node](a, times.len)
        if items_error != ok { ret (zero, TooLarge) }
        var i = 0usize
        while i < times.len {
            let (row, row_error) = time_row(a, key + 5u64 + u64(i), t, times[i], offsets[i], i == selected, &picks[i], options.width)
            if row_error != ok { ret (zero, row_error) }
            var entry: widget.Semantics = zero
            entry.role = 11u8
            entry.label = times[i]
            if i == selected { entry.states = accessibility.STATE_SELECTED }
            let (wrapped, wrapped_error) = mem.alloc[widget.Node](a, 1usize)
            if wrapped_error != ok { ret (zero, TooLarge) }
            wrapped[0usize] = row
            items[i] = widget.semantics(0u64, entry, style.defaults(), wrapped[0usize..1usize])
            i += 1usize
        }
        var shown = times.len
        if shown > 6usize { shown = 6usize }
        var first = 0usize
        if selected < times.len { first = selected }
        if first + shown > times.len { first = times.len - shown }
        let (column, column_error) = mem.alloc[widget.Node](a, 2usize)
        if column_error != ok { ret (zero, TooLarge) }
        column[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), items[0usize..times.len])
        let view_style = control.sized_style(options.width, f32(shown) * row_height)
        column[0usize] = widget.scroll(key + 4u64, widget.Scroll { axis: .Vertical, offset: f32(first) * row_height, overscroll: .Clamp, momentum: true, scrollbar: true, thumb: style.color(t.tokens, .Outline), change: zero, virtual_first: 0usize, virtual_count: 0usize, virtual_extent: 0.0 }, view_style, column[1usize..2usize])
        var raised = control.surface_options(t)
        raised.background = .SurfaceContainer
        raised.elevation = 2u8
        raised.radius = t.tokens.radii.sm
        raised.padding = 0.0
        var raised_style = control.surface_style(t, raised)
        raised_style.padding.top = style.Length { Px: 8.0 }
        raised_style.padding.bottom = style.Length { Px: 8.0 }
        let (lifted, lifted_error) = mem.alloc[widget.Node](a, 2usize)
        if lifted_error != ok { ret (zero, TooLarge) }
        lifted[1usize] = widget.box(0u64, raised_style, column[0usize..1usize])
        var list_sem: widget.Semantics = zero
        list_sem.role = 10u8
        list_sem.label = label
        list_sem.row_count = u32(times.len)
        lifted[0usize] = widget.semantics(0u64, list_sem, style.defaults(), lifted[1usize..2usize])
        parts[1usize] = widget.overlay(key + 3u64, widget.Overlay { anchor: key + 2u64, placement: .Below, offset: geometry.Point { x: 0.0, y: 4.0 }, modal: false, dismiss: zero }, style.defaults(), lifted[0usize..1usize])
        if selected < picks.len { default_action = picks[selected] }
    }
    var none_keys: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 2usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..count])
    var cancel: widget.Submit = zero
    if listing { cancel = *toggle }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: none_keys, default_action: default_action, cancel_action: cancel, keys: zero }, style.defaults(), scoped[1usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    if listing {
        sem.states = accessibility.STATE_EXPANDED
        if selected < times.len { sem.active = key + 5u64 + u64(selected) }
    }
    ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// A duration field (D960): the clocked field (editor `key`, clock mark `key + 1`,
// frame `key + 2`) whose `note` the caller keeps as the hint, the live reading
// ("Reads as 45 min", from `read_duration` and `write_duration`) or the error;
// with `presets`, a row of filter chips (keyed `key + 3 + index`) under it, the
// one at `chosen` selected, each firing its own pick.
// v2 (D960, docs/ux/components/DurationPicker, typed field with presets): the
// chips are 32 tall, 8 apart, 12 below the field's supporting text, the selected
// one `secondary-container` with its check; the row is a group named "Presets".
// ponytail: no unit boxes for touch or wheels for iOS, and the chips do not wrap; the caller's text carries the value.
fn duration_field(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], note: str, presets: []const str, chosen: usize, picks: []const widget.Submit, options: control.FieldOptions) -> (widget.Node, err) {
    if picks.len != presets.len { ret (zero, TooLarge) }
    var no_toggle: widget.Submit = zero
    let (boxed, boxed_error) = clocked_field(a, key, t, label, buffer, len, typed, note, false, false, &no_toggle, options)
    if boxed_error != ok { ret (zero, boxed_error) }
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = boxed
    if presets.len == 0usize { ret (widget.semantics(0u64, sem, style.defaults(), parts[0usize..1usize]), ok) }
    let (chips, chips_error) = mem.alloc[widget.Node](a, presets.len)
    if chips_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < presets.len {
        let (made, made_error) = control.chip(a, key + 3u64 + u64(i), t, presets[i], .Filter, i == chosen, &picks[i], &picks[i])
        if made_error != ok { ret (zero, made_error) }
        chips[i] = made
        i += 1usize
    }
    var row_style = style.defaults()
    row_style.margin.top = style.Length { Px: 12.0 }
    parts[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, row_style, chips[0usize..presets.len])
    var group: widget.Semantics = zero
    group.role = 2u8
    group.label = "Presets"
    parts[1usize] = widget.semantics(0u64, group, style.defaults(), parts[2usize..3usize])
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// A time of day as zero-padded `HH:MM` into `out`; the length (0 when it does not fit).
fn write_clock(out: []u8, value: time.Time) -> usize {
    if out.len < 5usize { ret 0usize }
    let at = write_two(out, 0usize, i64(value.hour))
    out[at] = 58u8
    ret write_two(out, at + 1usize, i64(value.minute))
}

// A duration written with its units, largest first and zero parts dropped
// ("1 h 30 min", "45 s", "0 min"), whole seconds rounded; the length (0 when
// `out` is shorter than 32).
fn write_duration(out: []u8, d: time.Duration) -> usize {
    if out.len < 32usize || d.nanos < 0i64 { ret 0usize }
    let total = (d.nanos + 500000000i64) / 1000000000i64
    let hours = total / 3600i64
    let minutes = total / 60i64 % 60i64
    let secs = total % 60i64
    var at = 0usize
    if hours != 0i64 {
        at = at + control.write_i64(out[at..out.len], hours)
        at = at + control.copy_text(out[at..out.len], " h")
    }
    if minutes != 0i64 || total == 0i64 {
        if at != 0usize { at = at + control.copy_text(out[at..out.len], " ") }
        at = at + control.write_i64(out[at..out.len], minutes)
        at = at + control.copy_text(out[at..out.len], " min")
    }
    if secs != 0i64 {
        if at != 0usize { at = at + control.copy_text(out[at..out.len], " ") }
        at = at + control.write_i64(out[at..out.len], secs)
        at = at + control.copy_text(out[at..out.len], " s")
    }
    ret at
}

fn is_digit(c: u8) -> bool {
    ret c >= 48u8 && c <= 57u8
}

// A typed duration read (D960, docs/ux/components/DurationPicker): "90m", "90 min",
// "2 hours", "1h30", "1.5h", "45 s", "1:30" (h:mm) and "1:30:00"; a number
// without a unit is the unit below the one before it, minutes at first. False for
// anything else.
fn read_duration(text: str) -> (time.Duration, bool) {
    let second = 1000000000i64
    var i = 0usize
    var colons = 0usize
    while i < text.len {
        if text[i] == 58u8 { colons += 1usize }
        i += 1usize
    }
    if colons > 2usize { ret (zero, false) }
    if colons != 0usize {
        var acc = 0i64
        var part = 0i64
        var digits = 0usize
        i = 0usize
        while i <= text.len {
            var c = 58u8
            if i < text.len { c = text[i] }
            if c == 58u8 {
                if digits == 0usize || digits > 6usize { ret (zero, false) }
                acc = acc * 60i64 + part
                part = 0i64
                digits = 0usize
            } else {
                if is_digit(c) {
                    part = part * 10i64 + i64(c - 48u8)
                    digits += 1usize
                } else {
                    if c != 32u8 { ret (zero, false) }
                }
            }
            i += 1usize
        }
        if colons == 1usize { acc = acc * 60i64 }
        ret (time.Duration { nanos: acc * second }, true)
    }
    var total = 0i64
    var last = 0i64
    var any = false
    i = 0usize
    while i < text.len {
        if text[i] == 32u8 {
            i += 1usize
            continue
        }
        var whole = 0i64
        var frac = 0i64
        var den = 1i64
        var seen = false
        while i < text.len && is_digit(text[i]) {
            whole = whole * 10i64 + i64(text[i] - 48u8)
            if whole > 1000000i64 { ret (zero, false) }
            seen = true
            i += 1usize
        }
        if i < text.len && text[i] == 46u8 {
            i += 1usize
            while i < text.len && is_digit(text[i]) {
                if den < 1000i64 {
                    frac = frac * 10i64 + i64(text[i] - 48u8)
                    den = den * 10i64
                }
                seen = true
                i += 1usize
            }
        }
        if !seen { ret (zero, false) }
        while i < text.len && text[i] == 32u8 { i += 1usize }
        var unit = 0i64
        if i < text.len {
            let u = text[i] | 32u8
            if u == 104u8 { unit = 3600i64 }
            if u == 109u8 { unit = 60i64 }
            if u == 115u8 { unit = 1i64 }
            if unit != 0i64 {
                while i < text.len && (text[i] | 32u8) >= 97u8 && (text[i] | 32u8) <= 122u8 { i += 1usize }
            }
        }
        if unit == 0i64 {
            if last == 0i64 { unit = 60i64 }
            if last == 3600i64 { unit = 60i64 }
            if last == 60i64 { unit = 1i64 }
            if unit == 0i64 { ret (zero, false) }
        }
        total = total + whole * unit * second + frac * unit * second / den
        last = unit
        any = true
    }
    ret (time.Duration { nanos: total }, any)
}

// A channel of a colour moved by its slider.
type Channel = struct { channel: u8, value: paint.Color, change: widget.Change[paint.Color] }

fn channel_fire(ctx: *void, moved: f32) -> err {
    let c = mem.cast[*Channel](ctx)
    var next = c.value
    if c.channel == 0u8 { next.red = moved }
    if c.channel == 1u8 { next.green = moved }
    if c.channel == 2u8 { next.blue = moved }
    if c.channel == 3u8 { next.alpha = moved }
    ret widget.fire_change[paint.Color](c.change, next)
}

// A colour picker: a swatch of `value` beside D820's sliders for red (keyed
// `key + 1`), green (`key + 2`), blue (`key + 3`) and, when `with_alpha`, alpha
// (`key + 4`), each move reaching `change` with the whole colour; the colour
// model is the runtime's own (straight RGBA in 0..1), a host's native picker
// being the caller's to offer. A group in the tree named `label`.
fn color_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, value: paint.Color, with_alpha: bool, change: widget.Change[paint.Color], width: f32) -> (widget.Node, err) {
    var count = 3usize
    if with_alpha { count = 4usize }
    let (channels, channels_error) = mem.alloc[Channel](a, 4usize)
    if channels_error != ok { ret (zero, TooLarge) }
    let (bars, bars_error) = mem.alloc[widget.Node](a, count)
    if bars_error != ok { ret (zero, TooLarge) }
    var names: [4]str = zero
    names[0usize] = "Red"
    names[1usize] = "Green"
    names[2usize] = "Blue"
    names[3usize] = "Alpha"
    var levels: [4]f32 = zero
    levels[0usize] = value.red
    levels[1usize] = value.green
    levels[2usize] = value.blue
    levels[3usize] = value.alpha
    var i = 0usize
    while i < count {
        channels[i] = Channel { channel: u8(i), value: value, change: change }
        let (bar, bar_error) = control.slider(a, key + 1u64 + u64(i), t, names[i], levels[i], 0.0, 1.0, 0.01, widget.Change[f32] { ctx: mem.cast[*void](&channels[i]), invoke: channel_fire }, true)
        if bar_error != ok { ret (zero, bar_error) }
        var sized = bar
        sized.style.width = style.Length { Px: width - t.tokens.metrics.hit_target - t.tokens.spacing.sm }
        bars[i] = sized
        i += 1usize
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var swatch = control.sized_style(t.tokens.metrics.hit_target, t.tokens.metrics.hit_target)
    swatch.background = paint.Brush { Solid: value }
    swatch.radius = t.tokens.radii.xs
    swatch.border = style.Border { width: t.tokens.borders.regular, color: style.color(t.tokens, .Border) }
    parts[0usize] = widget.box(key + 5u64, swatch, zero)
    parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: t.tokens.spacing.xs }, style.defaults(), bars[0usize..count])
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: t.tokens.spacing.sm }, style.defaults(), parts[0usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// ------------------------------------------------ colour picker v2 (D961, P5-06)

// A colour's hue in degrees (0..360), saturation and brightness (0..1).
fn hsv_of(c: paint.Color) -> (f32, f32, f32) {
    var high = c.red
    if c.green > high { high = c.green }
    if c.blue > high { high = c.blue }
    var low = c.red
    if c.green < low { low = c.green }
    if c.blue < low { low = c.blue }
    let span = high - low
    var hue: f32 = 0.0
    if span > 0.0 {
        if high == c.red {
            hue = 60.0 * (c.green - c.blue) / span
            if hue < 0.0 { hue += 360.0 }
        } else if high == c.green {
            hue = 60.0 * ((c.blue - c.red) / span + 2.0)
        } else {
            hue = 60.0 * ((c.red - c.green) / span + 4.0)
        }
    }
    var saturation: f32 = 0.0
    if high > 0.0 { saturation = span / high }
    ret (hue, saturation, high)
}

// The colour at a hue, saturation, brightness and alpha.
fn hsv_color(hue: f32, saturation: f32, bright: f32, alpha: f32) -> paint.Color {
    var h = hue / 60.0
    if h < 0.0 { h = 0.0 }
    while h >= 6.0 { h = h - 6.0 }
    let sector = i64(h)
    let f = h - f32(sector)
    let p = bright * (1.0 - saturation)
    let q = bright * (1.0 - saturation * f)
    let u = bright * (1.0 - saturation * (1.0 - f))
    if sector == 0i64 { ret paint.rgba(bright, u, p, alpha) }
    if sector == 1i64 { ret paint.rgba(q, bright, p, alpha) }
    if sector == 2i64 { ret paint.rgba(p, bright, u, alpha) }
    if sector == 3i64 { ret paint.rgba(p, q, bright, alpha) }
    if sector == 4i64 { ret paint.rgba(u, p, bright, alpha) }
    ret paint.rgba(bright, p, q, alpha)
}

fn hex_digit(v: u32) -> u8 {
    if v < 10u32 { ret u8(48u32 + v) }
    ret u8(55u32 + v)
}

fn channel_byte(v: f32) -> u32 {
    var c = v
    if c < 0.0 { c = 0.0 }
    if c > 1.0 { c = 1.0 }
    ret u32(c * 255.0 + 0.5)
}

// The colour as "#RRGGBB" (upper case) into `out`, "#RRGGBBAA" when it is not
// opaque; the length written.
fn write_hex(out: []u8, c: paint.Color) -> usize {
    if out.len < 9usize { ret 0usize }
    var bytes: [4]u32 = zero
    bytes[0usize] = channel_byte(c.red)
    bytes[1usize] = channel_byte(c.green)
    bytes[2usize] = channel_byte(c.blue)
    bytes[3usize] = channel_byte(c.alpha)
    var count = 3usize
    if bytes[3usize] != 255u32 { count = 4usize }
    out[0usize] = 35u8
    var i = 0usize
    while i < count {
        out[1usize + 2usize * i] = hex_digit(bytes[i] / 16u32)
        out[2usize + 2usize * i] = hex_digit(bytes[i] % 16u32)
        i += 1usize
    }
    ret 1usize + 2usize * count
}

fn hex_value(c: u8) -> u32 {
    if c >= 48u8 && c <= 57u8 { ret u32(c) - 48u32 }
    if c >= 65u8 && c <= 70u8 { ret u32(c) - 55u32 }
    if c >= 97u8 && c <= 102u8 { ret u32(c) - 87u32 }
    ret 16u32
}

// Typed hex: 3, 6 or 8 digits, with or without "#"; false for anything else.
fn read_hex(text: str) -> (paint.Color, bool) {
    var start = 0usize
    if text.len > 0usize && text[0usize] == 35u8 { start = 1usize }
    let n = text.len - start
    if n != 3usize && n != 6usize && n != 8usize { ret (zero, false) }
    var digits: [8]u32 = zero
    var i = 0usize
    while i < n {
        let d = hex_value(text[start + i])
        if d > 15u32 { ret (zero, false) }
        digits[i] = d
        i += 1usize
    }
    if n == 3usize { ret (paint.rgba(f32(digits[0usize] * 17u32) / 255.0, f32(digits[1usize] * 17u32) / 255.0, f32(digits[2usize] * 17u32) / 255.0, 1.0), true) }
    var alpha: f32 = 1.0
    if n == 8usize { alpha = f32(digits[6usize] * 16u32 + digits[7usize]) / 255.0 }
    ret (paint.rgba(f32(digits[0usize] * 16u32 + digits[1usize]) / 255.0, f32(digits[2usize] * 16u32 + digits[3usize]) / 255.0, f32(digits[4usize] * 16u32 + digits[5usize]) / 255.0, alpha), true)
}

// A spectrum, a strip or a swatch: what it paints (`kind` 0 the saturation and
// brightness area, 1 the hue strip, 2 the opacity strip, 3 a swatch), the colour
// as hue, saturation, brightness and alpha, the checkerboard's and the thumb's
// colours, and, for a pointer, where it is and whom to tell.
type Tint = struct { runtime: *widget.Runtime, key: widget.Key, kind: u8, hue: f32, saturation: f32, bright: f32, alpha: f32, color: paint.Color, light: paint.Color, dark: paint.Color, outer: paint.Color, inner: paint.Color, ink: paint.Color, hairline: paint.Color, chosen: bool, layer: f32, change: widget.Change[paint.Color], arena: *mem.Arena }

fn fill_rect(b: *scene.Builder, r: geometry.Rect, brush: paint.Brush) -> err {
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: r, brush: brush } })
}

// The 5px checkerboard in `light` and `dark` over `area`.
fn checker(b: *scene.Builder, area: geometry.Rect, light: paint.Color, dark: paint.Color) -> err {
    try fill_rect(b, area, paint.Brush { Solid: light })
    var row = 0usize
    var y = area.y
    while y < area.y + area.height {
        var col = row % 2usize
        var x = area.x + 5.0 * f32(col)
        while x < area.x + area.width {
            try fill_rect(b, geometry.Rect { x: x, y: y, width: 5.0, height: 5.0 }, paint.Brush { Solid: dark })
            x += 10.0
        }
        y += 5.0
        row += 1usize
    }
    ret ok
}

fn two_stops(a: *mem.Arena, from: paint.Color, to: paint.Color) -> ([]const paint.Stop, err) {
    var none: []const paint.Stop = zero
    let (stops, stops_error) = mem.alloc[paint.Stop](a, 2usize)
    if stops_error != ok { ret (none, TooLarge) }
    stops[0usize] = paint.Stop { offset: 0.0, color: from }
    stops[1usize] = paint.Stop { offset: 1.0, color: to }
    ret (stops[0usize..2usize], ok)
}

fn disc(k: *const Tint, b: *scene.Builder, cx: f32, cy: f32, radius: f32, color: paint.Color) -> err {
    let (path, path_error) = control.arc_path(k.arena, cx, cy, radius, 1.0)
    if path_error != ok { ret path_error }
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: color } } })
}

fn ring(k: *const Tint, b: *scene.Builder, cx: f32, cy: f32, radius: f32, width: f32, color: paint.Color) -> err {
    let (path, path_error) = control.arc_path(k.arena, cx, cy, radius, 1.0)
    if path_error != ok { ret path_error }
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: path, brush: paint.Brush { Solid: color }, stroke: paint.Stroke { width: width, cap: .Butt, join: .Round, miter_limit: 4.0 } } })
}

// v2 (D961, docs/ux/components/ColorPicker): the area is the hue at full
// saturation, white fading out left to right and black fading in top to bottom,
// in `radius-sm` corners, its thumb a 20 disc of the colour in a 2
// `surface-container-lowest` ring and a 1 `outline` ring; the hue strip is the
// hue circle and the opacity strip the colour from transparent to opaque over the
// 5px `outline-variant` and `surface-container-lowest` checkerboard, both pills,
// their thumbs the same rings hollow; a swatch is a disc of its colour (over the
// checkerboard when it is not opaque) with a 1px `on-surface` 16% hairline inside.
fn tint_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let k = mem.cast[*Tint](ctx)
    var save: scene.Command = .Save
    var restore: scene.Command = .Restore
    var corner = area.height * 0.5
    if k.kind == 0u8 { corner = 8.0 }
    if k.kind == 3u8 && area.width * 0.5 < corner { corner = area.width * 0.5 }
    if k.kind == 3u8 && k.layer > 0.0 { try disc(k, b, area.x + area.width * 0.5, area.y + area.height * 0.5, area.width * 0.5 + 4.0, control.with_alpha(k.ink, k.layer)) }
    try scene.push(b, save)
    try scene.push(b, scene.Command { Clip: scene.Clip { Rounded: widget.rounded(area, corner) } })
    let left = geometry.Point { x: area.x, y: area.y }
    let across = geometry.Point { x: area.x + area.width, y: area.y }
    if k.kind == 0u8 {
        try fill_rect(b, area, paint.Brush { Solid: hsv_color(k.hue, 1.0, 1.0, 1.0) })
        let (whites, whites_error) = two_stops(k.arena, paint.rgba(1.0, 1.0, 1.0, 1.0), paint.rgba(1.0, 1.0, 1.0, 0.0))
        if whites_error != ok { ret whites_error }
        try fill_rect(b, area, paint.Brush { Linear: paint.LinearGradient { start: left, end: across, stops: whites } })
        let (blacks, blacks_error) = two_stops(k.arena, paint.rgba(0.0, 0.0, 0.0, 0.0), paint.rgba(0.0, 0.0, 0.0, 1.0))
        if blacks_error != ok { ret blacks_error }
        try fill_rect(b, area, paint.Brush { Linear: paint.LinearGradient { start: left, end: geometry.Point { x: area.x, y: area.y + area.height }, stops: blacks } })
    }
    if k.kind == 1u8 {
        let (stops, stops_error) = mem.alloc[paint.Stop](k.arena, 7usize)
        if stops_error != ok { ret TooLarge }
        var i = 0usize
        while i < 7usize {
            stops[i] = paint.Stop { offset: f32(i) / 6.0, color: hsv_color(60.0 * f32(i % 6usize), 1.0, 1.0, 1.0) }
            i += 1usize
        }
        try fill_rect(b, area, paint.Brush { Linear: paint.LinearGradient { start: left, end: across, stops: stops[0usize..7usize] } })
    }
    if k.kind == 2u8 {
        try checker(b, area, k.light, k.dark)
        let (fade, fade_error) = two_stops(k.arena, control.with_alpha(k.color, 0.0), control.with_alpha(k.color, 1.0))
        if fade_error != ok { ret fade_error }
        try fill_rect(b, area, paint.Brush { Linear: paint.LinearGradient { start: left, end: across, stops: fade } })
    }
    if k.kind == 3u8 {
        if k.color.alpha < 1.0 { try checker(b, area, k.light, k.dark) }
        try fill_rect(b, area, paint.Brush { Solid: k.color })
    }
    try scene.push(b, restore)
    let cy = area.y + area.height * 0.5
    if k.kind == 3u8 {
        let mid = area.x + area.width * 0.5
        if k.chosen { try ring(k, b, mid, cy, area.width * 0.5 + 3.0, 2.0, k.ink) }
        ret ring(k, b, mid, cy, area.width * 0.5 - 0.5, 1.0, k.hairline)
    }
    if k.kind == 0u8 {
        let tx = area.x + k.saturation * area.width
        let ty = area.y + (1.0 - k.bright) * area.height
        try disc(k, b, tx, ty, 10.0, k.outer)
        try disc(k, b, tx, ty, 9.0, k.inner)
        ret disc(k, b, tx, ty, 7.0, control.with_alpha(k.color, 1.0))
    }
    var share = k.hue / 360.0
    if k.kind == 2u8 { share = k.alpha }
    let tx = area.x + share * area.width
    try ring(k, b, tx, cy, 9.5, 1.0, k.outer)
    ret ring(k, b, tx, cy, 8.0, 2.0, k.inner)
}

// A press or a drag on the area sets saturation (across) and brightness (up); on
// a strip, the hue or the opacity (across); each reaches `change` as the colour.
fn tint_at(k: *const Tint, p: geometry.Point) -> err {
    let (area, has_area) = control.keyed_bounds(k.runtime, k.key)
    if !has_area || area.width <= 0.0 || area.height <= 0.0 { ret ok }
    var sx = (p.x - area.x) / area.width
    var sy = (p.y - area.y) / area.height
    if sx < 0.0 { sx = 0.0 }
    if sx > 1.0 { sx = 1.0 }
    if sy < 0.0 { sy = 0.0 }
    if sy > 1.0 { sy = 1.0 }
    var next = hsv_color(k.hue, sx, 1.0 - sy, k.alpha)
    if k.kind == 1u8 { next = hsv_color(sx * 360.0, k.saturation, k.bright, k.alpha) }
    if k.kind == 2u8 { next = control.with_alpha(k.color, sx) }
    ret widget.fire_change[paint.Color](k.change, next)
}

fn tint_gesture(ctx: *void, g: widget.Gesture) -> err {
    let k = mem.cast[*Tint](ctx)
    switch g {
    case .Tap as p:
        ret tint_at(k, p)
    case .DragMove as d:
        ret tint_at(k, d.position)
    default:
        ret ok
    }
}

// A swatch's press: its colour to `change`.
type Swatch = struct { color: paint.Color, change: widget.Change[paint.Color] }

fn swatch_fire(ctx: *void) -> err {
    let s = mem.cast[*Swatch](ctx)
    ret widget.fire_change[paint.Color](s.change, s.color)
}

fn same_color(x: paint.Color, y: paint.Color) -> bool {
    ret channel_byte(x.red) == channel_byte(y.red) && channel_byte(x.green) == channel_byte(y.green) && channel_byte(x.blue) == channel_byte(y.blue) && channel_byte(x.alpha) == channel_byte(y.alpha)
}

// A painted tint `w` x `h`: a Custom node over `tints[at]`, a slider region keyed
// `key` in the tree named `label` with `value` when it takes the pointer.
fn tinted(a: *mem.Arena, key: widget.Key, tint: *Tint, w: f32, h: f32, label: str, value: str) -> (widget.Node, err) {
    var none: []const widget.Node = zero
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](tint), measure: control.mark_measure, paint: tint_paint, state: widget.bytes_of[Tint](tint) } }, style: control.sized_style(w, h), children: none }
    let (hit, hit_error) = mem.alloc[widget.Node](a, 1usize)
    if hit_error != ok { ret (zero, TooLarge) }
    hit[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](tint), invoke: tint_gesture }, gestures: 1u8 | 2u8 | 4u8, enabled: true, focusable: true }, control.sized_style(w, h), body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 15u8
    sem.label = label
    sem.value = value
    sem.actions = accessibility.ACTION_SET_VALUE
    ret (widget.semantics(0u64, sem, style.defaults(), hit[0usize..1usize]), ok)
}

fn percent_text(a: *mem.Arena, share: f32, suffix: str) -> str {
    let (out, out_error) = mem.alloc[u8](a, 32usize)
    if out_error != ok { ret "" }
    var n = control.write_i64(out, i64(share + 0.5))
    n += control.copy_text(out[n..32usize], suffix)
    ret out[0usize..n]
}

// A colour field (D961): the trigger (keyed `key`) showing the colour as a 20
// swatch and its hex, firing `toggle`; open, the panel (the overlay `key + 1`,
// the panel box `key + 7`) holds the saturation and brightness area (`key + 2`),
// the hue strip (`key + 3`), with `with_alpha` the opacity strip (`key + 4`), the
// hex field (`key + 5`) over the caller's `hex` text reaching `typed` (the caller
// parses it with `read_hex`), the opacity readout (`key + 6`) and the caller's
// `swatches` under "Theme" (keyed `key + 8 + index`), a transparent one standing
// for No colour; every move reaches `change` with the whole colour.
// v2 (D961, docs/ux/components/ColorPicker, swatches and spectrum): the trigger
// is the read-only field's box 40 tall (56 on touch) with the 20 swatch leading;
// the panel is a popover 4 below it on `surface-container-high`, `radius-md` 12,
// elevation 3, `width` wide (296 in the spec) with 16 padding and 16 between
// blocks; the area 150 tall (200 on touch) and full width, the strips 12 tall (16
// on touch); the channel fields 32 tall (48 on touch), 8 apart; the section label
// in `label-medium` `on-surface-variant`; the swatches 32 (40 on touch) in 40
// cells, so 8 apart, the chosen one in a 2px `on-surface` ring 2 outside it.
// ponytail: the hue comes from the colour, so it resets to red at a grey; hex only (no RGB/HSL select), the readout is not typed, no recent colours, no keyboard on the area or strips, no sheet or mode switch for touch, no host panel, 20 thumbs on touch.
fn color_field(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, value: paint.Color, with_alpha: bool, change: widget.Change[paint.Color], open: bool, toggle: *const widget.Submit, swatches: []const paint.Color, hex: []u8, hex_len: usize, typed: widget.Change[str], width: f32) -> (widget.Node, err) {
    if swatches.len > 64usize { ret (zero, TooLarge) }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    let (hue, saturation, bright) = hsv_of(value)
    let light = style.color(t.tokens, .SurfaceContainerLowest)
    let dark = style.color(t.tokens, .OutlineVariant)
    let ink = style.color(t.tokens, .OnSurface)
    let (tints, tints_error) = mem.alloc[Tint](a, 4usize + swatches.len)
    if tints_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < 4usize + swatches.len {
        tints[i] = Tint { runtime: t.runtime, key: key + 2u64 + u64(i), kind: u8(i), hue: hue, saturation: saturation, bright: bright, alpha: value.alpha, color: value, light: light, dark: dark, outer: style.color(t.tokens, .Outline), inner: light, ink: ink, hairline: control.with_alpha(ink, 0.16), chosen: false, layer: 0.0, change: change, arena: a }
        if i >= 3usize {
            tints[i].kind = 3u8
            tints[i].key = 0u64
        }
        i += 1usize
    }
    // The trigger: the value's swatch and hex.
    let (shown, shown_error) = mem.alloc[u8](a, 9usize)
    if shown_error != ok { ret (zero, TooLarge) }
    let shown_len = write_hex(shown, value)
    let swatch_size: f32 = 20.0
    var none: []const widget.Node = zero
    let (leads, leads_error) = mem.alloc[widget.Node](a, 1usize)
    if leads_error != ok { ret (zero, TooLarge) }
    leads[0usize] = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&tints[3usize]), measure: control.mark_measure, paint: tint_paint, state: widget.bytes_of[Tint](&tints[3usize]) } }, style: control.sized_style(swatch_size, swatch_size), children: none }
    let field_h: f32 = control.if_else(touch, t.tokens.sizes.control_xl, t.tokens.sizes.control_md)
    let (head, head_error) = control.led_head(a, key, t, label, shown[0usize..shown_len], true, open, toggle, field_h, .ChevronDown, .ChevronUp, true, leads[0usize..1usize])
    if head_error != ok { ret (zero, head_error) }
    var count = 1usize
    if open { count = 2usize }
    let (parts, parts_error) = mem.alloc[widget.Node](a, count)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    if open {
        let inner = control.max_zero(width - 32.0)
        let (blocks, blocks_error) = mem.alloc[widget.Node](a, 8usize)
        if blocks_error != ok { ret (zero, TooLarge) }
        var used = 0usize
        let area_h: f32 = control.if_else(touch, 200.0, 150.0)
        let strip_h: f32 = control.if_else(touch, 16.0, 12.0)
        let (spectrum, spectrum_error) = tinted(a, key + 2u64, &tints[0usize], inner, area_h, "Saturation and brightness", percent_text(a, saturation * 100.0, "%"))
        if spectrum_error != ok { ret (zero, spectrum_error) }
        blocks[used] = spectrum
        used += 1usize
        let (hues, hues_error) = tinted(a, key + 3u64, &tints[1usize], inner, strip_h, "Hue", percent_text(a, hue, " degrees"))
        if hues_error != ok { ret (zero, hues_error) }
        blocks[used] = hues
        used += 1usize
        if with_alpha {
            let (fades, fades_error) = tinted(a, key + 4u64, &tints[2usize], inner, strip_h, "Opacity", percent_text(a, value.alpha * 100.0, "%"))
            if fades_error != ok { ret (zero, fades_error) }
            blocks[used] = fades
            used += 1usize
        }
        // The channel row: the hex field and, with alpha, the opacity readout.
        let channel_h: f32 = control.if_else(touch, t.tokens.sizes.control_lg, t.tokens.sizes.control_sm)
        var readout_w: f32 = 0.0
        if with_alpha { readout_w = 72.0 }
        var field = control.field_options()
        field.width = inner - readout_w - control.if_else(with_alpha, 8.0, 0.0)
        field.height = channel_h
        // Unlabelled, so no notch cuts the 32 field; the group carries the name.
        let (hexed, hexed_error) = control.text_field(a, key + 5u64, t, "", hex, hex_len, typed, zero, field)
        if hexed_error != ok { ret (zero, hexed_error) }
        let (channel_row, channel_error) = mem.alloc[widget.Node](a, 4usize)
        if channel_error != ok { ret (zero, TooLarge) }
        channel_row[3usize] = hexed
        var hex_sem: widget.Semantics = zero
        hex_sem.role = 2u8
        hex_sem.label = "Hex"
        channel_row[0usize] = widget.semantics(0u64, hex_sem, style.defaults(), channel_row[3usize..4usize])
        var channel_count = 1usize
        if with_alpha {
            var words = control.text_options()
            words.role = .BodyMedium
            words.wrap = .None
            let (amount, amount_error) = control.colored_text(a, 0u64, percent_text(a, value.alpha * 100.0, "%"), t, words, ink)
            if amount_error != ok { ret (zero, amount_error) }
            channel_row[2usize] = amount
            var readout = control.sized_style(readout_w, channel_h)
            readout.radius = t.tokens.radii.xs
            readout.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .Outline) }
            channel_row[1usize] = widget.aligned(key + 6u64, .Center, .Center, readout, channel_row[2usize..3usize])
            channel_count = 2usize
        }
        blocks[used] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, style.defaults(), channel_row[0usize..channel_count])
        used += 1usize
        if swatches.len > 0usize {
            let (swatch_picks, swatch_picks_error) = mem.alloc[Swatch](a, swatches.len)
            if swatch_picks_error != ok { ret (zero, TooLarge) }
            let (submits, submits_error) = mem.alloc[widget.Submit](a, swatches.len)
            if submits_error != ok { ret (zero, TooLarge) }
            let (cells, cells_error) = mem.alloc[widget.Node](a, 2usize * swatches.len)
            if cells_error != ok { ret (zero, TooLarge) }
            let dot: f32 = control.if_else(touch, 40.0, 32.0)
            var j = 0usize
            while j < swatches.len {
                let tint = &tints[4usize + j]
                let swatch_key = key + 8u64 + u64(j)
                let chosen = same_color(swatches[j], value)
                tint.color = swatches[j]
                tint.chosen = chosen
                tint.layer = control.state_opacity(t, control.control_state(t, swatch_key, true, chosen))
                swatch_picks[j] = Swatch { color: swatches[j], change: change }
                submits[j] = widget.Submit { ctx: mem.cast[*void](&swatch_picks[j]), invoke: swatch_fire }
                cells[swatches.len + j] = widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](tint), measure: control.mark_measure, paint: tint_paint, state: widget.bytes_of[Tint](tint) } }, style: control.sized_style(dot, dot), children: none }
                var cell_style = control.sized_style(dot, dot)
                cell_style.radius = dot * 0.5
                let (pressed_cell, pressed_error) = mem.alloc[widget.Node](a, 1usize)
                if pressed_error != ok { ret (zero, TooLarge) }
                pressed_cell[0usize] = widget.region(swatch_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&submits[j]), invoke: control.press_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: true }, cell_style, cells[swatches.len + j..swatches.len + j + 1usize])
                var entry: widget.Semantics = zero
                entry.role = 5u8
                let (named, named_error) = mem.alloc[u8](a, 9usize)
                if named_error != ok { ret (zero, TooLarge) }
                entry.label = named[0usize..write_hex(named, swatches[j])]
                if swatches[j].alpha <= 0.0 { entry.label = "No colour" }
                entry.actions = accessibility.ACTION_PRESS
                if chosen { entry.states = accessibility.STATE_CHECKED }
                cells[j] = widget.semantics(0u64, entry, style.defaults(), pressed_cell[0usize..1usize])
                j += 1usize
            }
            var section = control.text_options()
            section.role = .LabelMedium
            section.wrap = .None
            let (theme_label, theme_label_error) = control.colored_text(a, 0u64, "Theme", t, section, style.color(t.tokens, .OnSurfaceVariant))
            if theme_label_error != ok { ret (zero, theme_label_error) }
            let (group, group_error) = mem.alloc[widget.Node](a, 3usize)
            if group_error != ok { ret (zero, TooLarge) }
            var flow = style.defaults()
            flow.width = style.Length { Px: inner }
            group[0usize] = theme_label
            group[2usize] = widget.wrap(0u64, ui_layout.Wrap { axis: .Horizontal, main_gap: 8.0, cross_gap: control.if_else(touch, 16.0, 8.0) }, flow, cells[0usize..swatches.len])
            var radio: widget.Semantics = zero
            radio.role = 2u8
            radio.label = "Theme"
            group[1usize] = widget.semantics(0u64, radio, style.defaults(), group[2usize..3usize])
            blocks[used] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, style.defaults(), group[0usize..2usize])
            used += 1usize
        }
        var raised = control.surface_options(t)
        raised.background = .SurfaceContainerHigh
        raised.radius = t.tokens.radii.md
        raised.elevation = 3u8
        raised.padding = 16.0
        var raised_style = control.surface_style(t, raised)
        raised_style.width = style.Length { Px: width }
        raised_style.overflow = .Visible
        let (panel_body, panel_error) = mem.alloc[widget.Node](a, 1usize)
        if panel_error != ok { ret (zero, TooLarge) }
        panel_body[0usize] = widget.flex(key + 7u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, raised_style, blocks[0usize..used])
        let (made, made_error) = dismissable(a, key + 1u64, key, .Below, label, panel_body[0usize], toggle, 4.0)
        if made_error != ok { ret (zero, made_error) }
        parts[1usize] = made
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    sem.value = shown[0usize..shown_len]
    if open { sem.states = accessibility.STATE_EXPANDED }
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}
