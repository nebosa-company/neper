// Application structure over the controls (D828, widget plan P1-15): the bars a
// window or a page is framed by, a stack of destinations pushed and popped, and
// the top-level destinations in the form the width calls for. Navigation state is
// the caller's data -- the titles, the pages, which destination is current -- and
// every control here only places what it is given and fires the caller's actions
// (§3.7 of the proposal).

use e.mem
use e.str as string
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.unicode
use e.ui.accessibility
use e.ui.animation
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.overlay
use e.ui.style
use e.ui.widget

error TooLarge

// An action in a bar: its label (the tree's name, and the face when there is no
// icon), what it does, its icon (a zero id for none), and whether it may be taken.
type Action = struct { label: str, action: widget.Submit, icon: scene.TextureId, enabled: bool }

// One action as a button of `variant`: the icon when there is one, the label
// otherwise; the action outlives the frame.
fn action_button(a: *mem.Arena, key: widget.Key, t: *const control.Theme, item: *const Action, variant: style.ControlVariant) -> (widget.Node, err) {
    var options = control.button_options()
    options.variant = variant
    options.enabled = item.enabled
    if item.icon.slot != 0u32 || item.icon.generation != 0u32 {
        let (pictured, pictured_error) = control.icon_button(a, key, t, item.icon, item.label, &item.action, options)
        ret (pictured, pictured_error)
    }
    let (worded, worded_error) = control.button(a, key, t, item.label, &item.action, options)
    ret (worded, worded_error)
}

// The actions as plain buttons in a row, keyed `key + index`, `space-2` apart;
// right-to-left layouts mirror their physical order (D944, D1158,
// docs/ux/components/ActionRow).
fn action_row(a: *mem.Arena, key: widget.Key, t: *const control.Theme, items: []const Action, variant: style.ControlVariant) -> (widget.Node, err) {
    let (row, row_error) = spaced_row(a, key, t, items, variant, 8.0, t.tokens.direction == .RightToLeft)
    ret (row, row_error)
}

fn spaced_row(a: *mem.Arena, key: widget.Key, t: *const control.Theme, items: []const Action, variant: style.ControlVariant, gap: f32, reverse: bool) -> (widget.Node, err) {
    let (buttons, buttons_error) = mem.alloc[widget.Node](a, items.len)
    if buttons_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < items.len {
        let (made, made_error) = action_button(a, key + u64(i), t, &items[i], variant)
        if made_error != ok { ret (zero, made_error) }
        var slot = i
        if reverse { slot = items.len - 1usize - i }
        buttons[slot] = made
        i += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: gap }, style.defaults(), buttons[0usize..items.len]), ok)
}

// An app bar: the leading actions (keyed `key + 1 + index`, at most 8), the title
// as a heading of level 1, then the trailing actions (keyed `key + 9 + index`) at
// the end, `width` wide; a group named by the title. The small bar of D972 below.
fn app_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, leading: []const Action, trailing: []const Action, width: f32) -> (widget.Node, err) {
    let (made, made_error) = app_bar_of(a, key, t, title, leading, trailing, app_bar_options(), width)
    ret (made, made_error)
}

// The four top app bar sizes (D972, docs/ux/components/AppBar).
type AppBarSize = enum u8 { Small, Center, Medium, Large }

// An app bar's state (D972): its size; whether content has scrolled under it; the
// contextual title ("3 selected"; set, the bar leads with Clear selection firing
// `clear`); past three trailing actions, whether the More menu is open and what
// toggles it; Back's name (set, an `arrow-back` action firing `back` leads;
// `closing`, a `close` one, D974); and
// a node standing in place of the title (`headed`), the bar still named by it.
type AppBarOptions = struct { size: AppBarSize, scrolled: bool, contextual: str, clear: widget.Submit, more_open: bool, more: widget.Submit, back_label: str, back: widget.Submit, back_disabled: bool, closing: bool, heading: widget.Node, headed: bool }

fn app_bar_options() -> AppBarOptions {
    var out: AppBarOptions = zero
    ret out
}

// One bar action (D972): an icon action keyed `key` (the icon button at the
// density's size), or a worded one as a text button in `color`.
fn bar_action(a: *mem.Arena, key: widget.Key, t: *const control.Theme, item: *const Action, color: paint.Color) -> (widget.Node, err) {
    var options = control.button_options()
    options.variant = .Plain
    options.enabled = item.enabled
    if item.icon.slot != 0u32 || item.icon.generation != 0u32 {
        let (pictured, pictured_error) = control.icon_button(a, key, t, item.icon, item.label, &item.action, options)
        ret (pictured, pictured_error)
    }
    if !item.enabled {
        let (dim, dim_error) = control.button(a, key, t, item.label, &item.action, options)
        ret (dim, dim_error)
    }
    let (worded, worded_error) = control.tinted_button(a, key, t, item.label, &item.action, color)
    ret (worded, worded_error)
}

fn bar_group(items: []const widget.Node) -> widget.Node {
    ret widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), items)
}

// v2 (D972, docs/ux/components/AppBar): full-bleed and square on `surface`
// (`surface-container` once scrolled, `secondary-container` contextual), with no
// divider or shadow, 4 in at the sides. At pointer density the row is 48 with 32
// icon actions and a `title-medium` title; at touch density it is 64 with 40
// actions and `title-large`. The title is one line cut with an ellipsis, 8 after
// the leading action (16 in with none), centred in the center-aligned bar;
// medium (112) and large (152) set it on its own line in `headline-small` and
// `headline-medium`, 16 in and 16 (28) above the bottom edge. Leading content is
// `on-surface`, trailing `on-surface-variant` (`on-secondary-container`
// contextual); actions stand 4 apart, at most three, the rest in a More menu:
// `more-vert` (keyed `key + 12`), its menu `key + 20`, items `key + 21 + index`.
// The contextual bar leads with Clear selection (`key + 1`) and says its title
// politely; Back, when named, leads as `arrow-back` (`key + 1`).
// ponytail: no collapse or hiding on scroll and no motion; worded actions stay
// text buttons; a disabled action is dimmed rather than hidden.
fn app_bar_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, leading: []const Action, trailing: []const Action, options: AppBarOptions, width: f32) -> (widget.Node, err) {
    if leading.len > 8usize || trailing.len > 8usize { ret (zero, TooLarge) }
    // The options' actions outlive the frame in the arena.
    let (held, held_error) = mem.alloc[widget.Submit](a, 3usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = options.clear
    held[1usize] = options.more
    held[2usize] = options.back
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var side = t.tokens.sizes.control_sm
    var glyph = t.tokens.sizes.icon_sm
    var row_height: f32 = 48.0
    var role: style.TextRole = .TitleMedium
    if touch {
        side = t.tokens.sizes.control_md
        glyph = t.tokens.sizes.icon_md
        row_height = 64.0
        role = .TitleLarge
    }
    let tall = options.size == .Medium || options.size == .Large
    var height = row_height
    var above: f32 = 16.0
    if options.size == .Medium {
        height = 112.0
        role = .HeadlineSmall
    }
    if options.size == .Large {
        height = 152.0
        role = .HeadlineMedium
        above = 28.0
    }
    let contextual = options.contextual.len > 0usize
    var ground: style.ColorRole = .Background
    if options.scrolled { ground = .SurfaceContainer }
    var ink = style.color(t.tokens, .OnSurface)
    var muted = style.color(t.tokens, .OnSurfaceVariant)
    var named = title
    if contextual {
        ground = .SecondaryContainer
        ink = style.color(t.tokens, .OnSecondaryContainer)
        muted = ink
        named = options.contextual
    }
    // The leading group.
    var lead_count = leading.len
    let backed = options.back_label.len > 0usize
    if contextual || backed { lead_count = 1usize }
    let (fronts, fronts_error) = mem.alloc[widget.Node](a, lead_count)
    if fronts_error != ok { ret (zero, TooLarge) }
    if contextual {
        let (clearing, clearing_error) = control.glyph_action(a, key + 1u64, t, .Cross, "Clear selection", &held[0usize], side, glyph, ink, true, 0u32, 0u32, 0u64)
        if clearing_error != ok { ret (zero, clearing_error) }
        fronts[0usize] = clearing
    } else {
        if backed {
            var kind: control.GlyphKind = .ArrowBack
            if options.closing { kind = .Cross }
            let (going, going_error) = control.glyph_action(a, key + 1u64, t, kind, options.back_label, &held[2usize], side, glyph, ink, !options.back_disabled, 0u32, 0u32, 0u64)
            if going_error != ok { ret (zero, going_error) }
            fronts[0usize] = going
        } else {
            var i = 0usize
            while i < leading.len {
                let (made, made_error) = bar_action(a, key + 1u64 + u64(i), t, &leading[i], ink)
                if made_error != ok { ret (zero, made_error) }
                fronts[i] = made
                i += 1usize
            }
        }
    }
    // The trailing group: three, then More over the rest.
    var shown = trailing.len
    let overflow = trailing.len > 3usize
    if overflow { shown = 3usize }
    var back_count = shown
    if overflow { back_count = shown + 1usize }
    if overflow && options.more_open { back_count = shown + 2usize }
    let (backs, backs_error) = mem.alloc[widget.Node](a, back_count)
    if backs_error != ok { ret (zero, TooLarge) }
    var j = 0usize
    while j < shown {
        let (made, made_error) = bar_action(a, key + 9u64 + u64(j), t, &trailing[j], muted)
        if made_error != ok { ret (zero, made_error) }
        backs[j] = made
        j += 1usize
    }
    if overflow {
        let (rest, rest_error) = mem.alloc[overlay.MenuItem](a, trailing.len - shown)
        if rest_error != ok { ret (zero, TooLarge) }
        var k = 0usize
        while k < trailing.len - shown {
            let item = &trailing[shown + k]
            rest[k] = overlay.MenuItem { label: item.label, action: item.action, enabled: item.enabled }
            k += 1usize
        }
        var states = 0u32
        if options.more_open { states = accessibility.STATE_EXPANDED }
        let (more_node, more_error) = control.glyph_action(a, key + 12u64, t, .MoreVert, "More options", &held[1usize], side, glyph, muted, true, states, accessibility.ACTION_SHOW_MENU, key + 20u64)
        if more_error != ok { ret (zero, more_error) }
        backs[shown] = more_node
        let (menu_node, menu_error) = overlay.menu(a, key + 20u64, t, key + 12u64, "More options", rest[0usize..trailing.len - shown], options.more_open, &held[1usize])
        if menu_error != ok { ret (zero, menu_error) }
        if options.more_open { backs[shown + 1usize] = menu_node }
    }
    // The title, a heading of level 1 (said politely when contextual).
    var heading = control.text_options()
    heading.role = role
    heading.wrap = .None
    heading.ellipsis = "..."
    heading.max_lines = 1u32
    if options.size == .Center { heading.align = .Center }
    let (title_node, title_error) = control.colored_text(a, 0u64, named, t, heading, ink)
    if title_error != ok { ret (zero, title_error) }
    let (titled, titled_error) = mem.alloc[widget.Node](a, 1usize)
    if titled_error != ok { ret (zero, TooLarge) }
    titled[0usize] = title_node
    if options.headed { titled[0usize] = options.heading }
    var title_sem: widget.Semantics = zero
    title_sem.role = 25u8
    title_sem.label = named
    title_sem.level = 1u8
    if contextual { title_sem.live = 1u8 }
    var inset: f32 = 12.0
    if lead_count > 0usize { inset = 8.0 }
    if tall { inset = 12.0 }
    var end_inset: f32 = 8.0
    if options.size == .Center { end_inset = inset }
    var title_style = style.defaults()
    title_style.width = style.Length { Flex: 1.0 }
    let flat = style.Length { Px: 0.0 }
    var bottom = flat
    if tall { bottom = style.Length { Px: above } }
    title_style.padding = style.EdgeLengths { left: style.Length { Px: inset }, top: flat, right: style.Length { Px: end_inset }, bottom: bottom }
    let title_box = widget.semantics(0u64, title_sem, title_style, titled[0usize..1usize])
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = bar_group(fronts[0usize..lead_count])
    parts[2usize] = bar_group(backs[0usize..back_count])
    var bar = control.sized_style(width, height)
    bar.background = paint.Brush { Solid: style.color(t.tokens, ground) }
    let ends = style.Length { Px: 4.0 }
    bar.padding = style.EdgeLengths { left: ends, top: flat, right: ends, bottom: flat }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    if tall {
        parts[1usize] = widget.spacer(0u64, 1.0)
        var top_style = style.defaults()
        top_style.height = style.Length { Px: row_height }
        let (lines, lines_error) = mem.alloc[widget.Node](a, 3usize)
        if lines_error != ok { ret (zero, TooLarge) }
        lines[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, top_style, parts[0usize..3usize])
        lines[1usize] = widget.spacer(0u64, 1.0)
        lines[2usize] = title_box
        row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, bar, lines[0usize..3usize])
    } else {
        parts[1usize] = title_box
        row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, bar, parts[0usize..3usize])
    }
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = named
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// v2 (D972, docs/ux/components/AppBar, bottom): 80 tall and full-bleed on
// `surface-container`, 4 in at the start and 16 at the end; up to four actions
// (keyed `key + 1 + index`) in `on-surface-variant`, 4 apart, then the FAB (keyed
// `key + 9`; an empty label for none) at the end: 56 on `primary-container` with
// `radius-lg` and a 24 icon, casting no shadow. A group named `label`.
fn bottom_app_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, actions: []const Action, fab: *const Action, width: f32) -> (widget.Node, err) {
    if actions.len > 4usize { ret (zero, TooLarge) }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let (items, items_error) = mem.alloc[widget.Node](a, actions.len)
    if items_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < actions.len {
        let (made, made_error) = bar_action(a, key + 1u64 + u64(i), t, &actions[i], muted)
        if made_error != ok { ret (zero, made_error) }
        items[i] = made
        i += 1usize
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = bar_group(items[0usize..actions.len])
    parts[1usize] = widget.spacer(0u64, 1.0)
    var count = 2usize
    if fab.label.len > 0usize {
        var look = style.resolve(t.tokens, .Container, control.control_state(t, key + 9u64, true, false))
        look.elevation = 0u8
        look.radius = t.tokens.radii.lg
        look.custom_padding = true
        look.padding = 16.0
        look.padding_y = 16.0
        look.min_width = 56.0
        look.min_height = 56.0
        let icon_size = t.tokens.sizes.icon_md
        var picture = widget.box(0u64, control.sized_style(icon_size, icon_size), zero)
        if fab.icon.slot != 0u32 || fab.icon.generation != 0u32 { picture = widget.image(0u64, widget.Image { texture: fab.icon, fit: .Contain }, control.sized_style(icon_size, icon_size)) }
        let (button, button_error) = control.pressable(a, key + 9u64, t, 3u8, fab.label, look, true, false, &fab.action, picture)
        if button_error != ok { ret (zero, button_error) }
        parts[2usize] = button
        count = 3usize
    }
    var bar = control.sized_style(width, 80.0)
    bar.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainer) }
    let flat = style.Length { Px: 0.0 }
    bar.padding = style.EdgeLengths { left: style.Length { Px: 4.0 }, top: flat, right: style.Length { Px: 16.0 }, bottom: flat }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, bar, parts[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// Two words as one, in the arena (D972).
fn joined(a: *mem.Arena, first: str, second: str) -> (str, err) {
    let (bytes, bytes_error) = mem.alloc[u8](a, first.len + second.len)
    if bytes_error != ok { ret ("", TooLarge) }
    let n = control.copy_text(bytes, first)
    let m = control.copy_text(bytes[n..first.len + second.len], second)
    ret (bytes[0usize..n + m], ok)
}

// A toolbar: the actions as plain buttons in a row keyed `key + 1 + index`; a
// group named `label`. v2 (D944, docs/ux/components/Toolbar, docked): square on
// `surface-container`, 4 apart and 4 in at pointer density, 8 at touch density.
fn toolbar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const Action) -> (widget.Node, err) {
    var gap: f32 = 4.0
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { gap = 8.0 }
    let (row, row_error) = spaced_row(a, key + 1u64, t, items, .Plain, gap, false)
    if row_error != ok { ret (zero, row_error) }
    var options = control.surface_options(t)
    options.background = .SurfaceContainer
    options.padding = gap
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = row
    let (sheet, sheet_error) = mem.alloc[widget.Node](a, 1usize)
    if sheet_error != ok { ret (zero, TooLarge) }
    sheet[0usize] = widget.box(0u64, control.surface_style(t, options), body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), sheet[0usize..1usize]), ok)
}

// A status bar item (D971): its text, an optional 16 glyph, its tone (Error and
// Warning colour the glyph; anything else is `on-surface-variant`), whether it
// sits in the end group, an optional press (unset: a plain item), and a progress
// share for the meter item (below zero: none), and optional action tooltip.
type StatusItem = struct { text: str, glyph: control.GlyphKind, marked: bool, tone: control.StatusTone, end: bool, action: widget.Submit, progress: f32, tooltip: str }

// A plain text item at the start.
fn status_item(text: str) -> StatusItem {
    var out: StatusItem = zero
    out.text = text
    out.tone = .Neutral
    out.progress = 0.0 - 1.0
    ret out
}

// A status bar: the sections as items, the first (the message) at the start and
// the rest in the end group.
fn status_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, sections: []const str, width: f32) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[StatusItem](a, sections.len)
    if items_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < sections.len {
        items[i] = status_item(sections[i])
        items[i].end = i > 0usize
        i += 1usize
    }
    let (node, node_error) = status_bar_of(a, key, t, items[0usize..sections.len], false, width)
    ret (node, node_error)
}

// v2 (D971, docs/ux/components/StatusBar): full-bleed and square, 24 tall on
// `surface-container` (`primary-container` in a mode), 4 in at the ends; the start
// group, a spacer, then the end group. An item is 24 tall with 8 at its sides, an
// optional 16 glyph (in `error` or `warning` for those tones) 4 before its
// `body-small` text in `on-surface-variant` (`on-primary-container` in a mode), or
// a 48x4 fully rounded meter, `primary` on `secondary-container`, before its
// words; a pressable item (keyed `key + 1 + index`) is a button named by its text
// under the `state-hover` layer. Only the first item, the message, is a polite
// status named by its text. Pressable items share one roving Tab stop, with
// Left/Right and Home/End moving in visual order.
// ponytail: no narrowing rules.
type StatusMove = struct { runtime: *widget.Runtime, keys: []const widget.Key, backward: bool, edge: bool }

fn status_move_fire(ctx: *void) -> err {
    let m = mem.cast[*StatusMove](ctx)
    var current = 0usize
    while current < m.keys.len {
        if widget.focus_within(m.runtime, m.keys[current]) { break }
        current += 1usize
    }
    if current == m.keys.len { ret ok }
    var next = current
    if m.edge {
        if m.backward { next = 0usize } else { next = m.keys.len - 1usize }
    } else if m.backward {
        if next > 0usize { next -= 1usize }
    } else if next + 1usize < m.keys.len {
        next += 1usize
    }
    ret widget.focus_key(m.runtime, m.keys[next])
}

fn status_bar_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, items: []const StatusItem, mode: bool, width: f32) -> (widget.Node, err) {
    var ground: style.ColorRole = .SurfaceContainer
    var ink = style.color(t.tokens, .OnSurfaceVariant)
    if mode {
        ground = .PrimaryContainer
        ink = style.color(t.tokens, .OnPrimaryContainer)
    }
    let (starts, starts_error) = mem.alloc[widget.Node](a, items.len)
    if starts_error != ok { ret (zero, TooLarge) }
    let (ends, ends_error) = mem.alloc[widget.Node](a, items.len)
    if ends_error != ok { ret (zero, TooLarge) }
    let (action_keys, action_keys_error) = mem.alloc[widget.Key](a, items.len)
    if action_keys_error != ok { ret (zero, TooLarge) }
    var action_count = 0usize
    var pass = 0usize
    while pass < 2usize {
        var at = 0usize
        while at < items.len {
            if items[at].end == (pass == 1usize) && widget.submit_set(items[at].action.invoke) {
                action_keys[action_count] = key + 1u64 + u64(at)
                action_count += 1usize
            }
            at += 1usize
        }
        pass += 1usize
    }
    var tab_key = 0u64
    if action_count > 0usize { tab_key = action_keys[0usize] }
    var active = 0usize
    while active < action_count {
        if widget.focus_within(t.runtime, action_keys[active]) { tab_key = action_keys[active] }
        active += 1usize
    }
    var s = 0usize
    var e = 0usize
    var i = 0usize
    while i < items.len {
        let item = &items[i]
        let (bits, bits_error) = mem.alloc[widget.Node](a, 2usize)
        if bits_error != ok { ret (zero, TooLarge) }
        var n = 0usize
        if item.progress >= 0.0 {
            let (meters, meters_error) = mem.alloc[widget.Node](a, 1usize)
            if meters_error != ok { ret (zero, TooLarge) }
            var share = item.progress
            if share > 1.0 { share = 1.0 }
            var filled = control.sized_style(48.0 * share, 4.0)
            filled.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
            filled.radius = 2.0
            meters[0usize] = widget.box(0u64, filled, zero)
            var track = control.sized_style(48.0, 4.0)
            track.background = paint.Brush { Solid: style.color(t.tokens, .SecondaryContainer) }
            track.radius = 2.0
            track.overflow = .Clip
            bits[n] = widget.box(0u64, track, meters[0usize..1usize])
            n += 1usize
        }
        if item.progress < 0.0 && item.marked {
            var tint = ink
            if item.tone == .Error { tint = style.color(t.tokens, .Error) }
            if item.tone == .Warning { tint = style.color(t.tokens, .Warning) }
            let (mark, mark_error) = control.stroked_glyph(a, tint, item.glyph, 16.0, 1.5)
            if mark_error != ok { ret (zero, mark_error) }
            bits[n] = mark
            n += 1usize
        }
        var small = control.text_options()
        small.role = .BodySmall
        small.wrap = .None
        let (said, said_error) = control.colored_text(a, 0u64, item.text, t, small, ink)
        if said_error != ok { ret (zero, said_error) }
        bits[n] = said
        n += 1usize
        var line_style = style.defaults()
        line_style.height = style.Length { Px: 16.0 }
        let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, line_style, bits[0usize..n])
        var made = content
        if widget.submit_set(item.action.invoke) {
            let state = control.control_state(t, key + 1u64 + u64(i), true, false)
            var look = style.resolve(t.tokens, .Plain, state)
            look.background = control.with_alpha(ink, control.state_opacity(t, state))
            look.foreground = ink
            look.border_width = 0.0
            look.radius = 0.0
            look.custom_padding = true
            look.padding = 8.0
            look.padding_y = 4.0
            look.min_height = 24.0
            look.min_width = 16.0
            let (built, pressed_error) = control.pressable(a, key + 1u64 + u64(i), t, 3u8, item.text, look, true, false, &item.action, content)
            if pressed_error != ok { ret (zero, pressed_error) }
            var pressed = built
            switch pressed.kind {
            case .Semantics as pressed_sem:
                var inset_sem = pressed_sem
                inset_sem.focus_inset = 3.0
                pressed.kind = widget.Kind { Semantics: inset_sem }
            default:
                pressed = built
            }
            made = pressed
            if key + 1u64 + u64(i) != tab_key {
                let (untabbed, untabbed_error) = untab_pressable(a, made)
                if untabbed_error != ok { ret (zero, untabbed_error) }
                made = untabbed
            }
            if item.tooltip.len > 0usize {
                let item_key = key + 1u64 + u64(i)
                let (tip, tip_error) = overlay.tooltip(a, key + 1000000u64 + u64(i), t, item_key, item.tooltip, overlay.tooltip_wanted(t, item_key))
                if tip_error != ok { ret (zero, tip_error) }
                let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
                if layers_error != ok { ret (zero, TooLarge) }
                layers[0usize] = made
                layers[1usize] = tip
                made = widget.stack(0u64, style.defaults(), layers[0usize..2usize])
            }
        } else {
            let (wraps, wraps_error) = mem.alloc[widget.Node](a, 1usize)
            if wraps_error != ok { ret (zero, TooLarge) }
            wraps[0usize] = content
            var item_style = style.defaults()
            item_style.height = style.Length { Px: 24.0 }
            made = widget.padded(0u64, 8.0, 4.0, 8.0, 4.0, item_style, wraps[0usize..1usize])
            if i == 0usize {
                let (lives, lives_error) = mem.alloc[widget.Node](a, 1usize)
                if lives_error != ok { ret (zero, TooLarge) }
                lives[0usize] = made
                var live: widget.Semantics = zero
                live.role = 26u8
                live.label = item.text
                live.live = 1u8
                made = widget.semantics(0u64, live, style.defaults(), lives[0usize..1usize])
            }
        }
        if item.end {
            ends[e] = made
            e += 1usize
        } else {
            starts[s] = made
            s += 1usize
        }
        i += 1usize
    }
    let (groups, groups_error) = mem.alloc[widget.Node](a, 3usize)
    if groups_error != ok { ret (zero, TooLarge) }
    groups[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), starts[0usize..s])
    groups[1usize] = widget.spacer(0u64, 1.0)
    groups[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), ends[0usize..e])
    var bar = control.sized_style(width, 24.0)
    bar.background = paint.Brush { Solid: style.color(t.tokens, ground) }
    let ends_pad = style.Length { Px: 4.0 }
    let flat = style.Length { Px: 0.0 }
    bar.padding = style.EdgeLengths { left: ends_pad, top: flat, right: ends_pad, bottom: flat }
    let (boxed, boxed_error) = mem.alloc[widget.Node](a, 2usize)
    if boxed_error != ok { ret (zero, TooLarge) }
    boxed[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, bar, groups[0usize..3usize])
    var layer = 0usize
    if action_count > 0usize {
        let (moves, moves_error) = mem.alloc[StatusMove](a, 4usize)
        if moves_error != ok { ret (zero, TooLarge) }
        let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 4usize)
        if shortcuts_error != ok { ret (zero, TooLarge) }
        var move = 0usize
        while move < 4usize {
            moves[move] = StatusMove { runtime: t.runtime, keys: action_keys[0usize..action_count], backward: move == 0usize || move == 2usize, edge: move >= 2usize }
            move += 1usize
        }
        shortcuts[0usize] = widget.Shortcut { key: 37u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[0usize]), invoke: status_move_fire } }
        shortcuts[1usize] = widget.Shortcut { key: 39u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[1usize]), invoke: status_move_fire } }
        shortcuts[2usize] = widget.Shortcut { key: 36u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[2usize]), invoke: status_move_fire } }
        shortcuts[3usize] = widget.Shortcut { key: 35u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[3usize]), invoke: status_move_fire } }
        boxed[1usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..4usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), boxed[0usize..1usize])
        layer = 1usize
    }
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = "Status bar"
    ret (widget.semantics(key, sem, style.defaults(), boxed[layer..layer + 1usize]), ok)
}

// A navigation stack: the top of `titles` and `pages` (the same length, the last
// the top) under an app bar (keyed `key + 1`) with a back button (keyed `key + 2`)
// while there is somewhere to go back to, firing `pop`; Escape -- and so the
// host's back gesture -- pops the same way. The page is a group (keyed `key + 3`)
// named by its title.
fn navigation_stack(a: *mem.Arena, key: widget.Key, t: *const control.Theme, titles: []const str, pages: []const widget.Node, pop: *const widget.Submit, width: f32) -> (widget.Node, err) {
    var none: []const widget.Submit = zero
    let (made, made_error) = navigation_stack_of(a, key, t, titles, pages, pop, none, width)
    ret (made, made_error)
}

// A backable scope: Escape, Alt+Left and Command+[ share the caller-owned action.
fn back_scope(a: *mem.Arena, key: widget.Key, content: widget.Node, back: widget.Submit) -> (widget.Node, err) {
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = content
    let (keys, keys_error) = mem.alloc[widget.Shortcut](a, 3usize)
    if keys_error != ok { ret (zero, TooLarge) }
    var alt: input.Modifiers = zero
    alt.alt = true
    keys[0usize] = widget.Shortcut { key: 37u32, modifiers: alt, action: back }
    var command: input.Modifiers = zero
    command.meta = true
    keys[1usize] = widget.Shortcut { key: 219u32, modifiers: command, action: back }
    keys[2usize] = widget.Shortcut { key: 91u32, modifiers: command, action: back }
    ret (widget.scope(key, widget.Scope { traps_focus: false, shortcuts: keys[0usize..3usize], default_action: zero, cancel_action: back, keys: zero }, style.defaults(), held[0usize..1usize]), ok)
}

// v2 (D972, docs/ux/components/NavigationStack): the top page fills on `surface`
// under the v2 app bar (48 with `title-medium` at pointer density, 64 with
// `title-large` at touch), led while there is a page beneath by Back: an
// `arrow-back` icon action in `on-surface` named "Back to <the page beneath>".
// With `jumps` (one a level) on a pointer host three or more levels deep,
// breadcrumbs (keyed `key + 4`, the ancestors jumping to their levels) stand in
// the bar in place of the title.
// Alt+Left and Command+[ share Back and Escape's pop action.
// ponytail: no push or pop transitions, predictive back, focus moves or discard
// guard; the page beneath is not kept in the tree.
fn navigation_stack_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, titles: []const str, pages: []const widget.Node, pop: *const widget.Submit, jumps: []const widget.Submit, width: f32) -> (widget.Node, err) {
    if titles.len != pages.len || titles.len == 0usize { ret (zero, TooLarge) }
    let top = titles.len - 1usize
    var bar_options = app_bar_options()
    if top > 0usize {
        let (named, named_error) = joined(a, "Back to ", titles[top - 1usize])
        if named_error != ok { ret (zero, named_error) }
        bar_options.back_label = named
        bar_options.back = *pop
    }
    let pointer = t.tokens.metrics.control_height <= t.tokens.sizes.control_sm
    if pointer && top >= 2usize && jumps.len == titles.len {
        let (trail, trail_error) = breadcrumbs(a, key + 4u64, t, "Location", titles, jumps)
        if trail_error != ok { ret (zero, trail_error) }
        bar_options.heading = trail
        bar_options.headed = true
    }
    var nothing: []const Action = zero
    let (bar, bar_error) = app_bar_of(a, key + 1u64, t, titles[top], nothing, nothing, bar_options, width)
    if bar_error != ok { ret (zero, bar_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = bar
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = pages[top]
    var page_sem: widget.Semantics = zero
    page_sem.role = 2u8
    page_sem.label = titles[top]
    var grow = style.defaults()
    grow.width = style.Length { Px: width }
    grow.height = style.Length { Flex: 1.0 }
    grow.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    parts[1usize] = widget.semantics(key + 3u64, page_sem, grow, body[0usize..1usize])
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
    if top > 0usize {
        let (backed, backed_error) = back_scope(a, key, column[0usize], *pop)
        ret (backed, backed_error)
    }
    var shortcuts: []const widget.Shortcut = zero
    ret (widget.scope(key, widget.Scope { traps_focus: false, shortcuts: shortcuts, default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), column[0usize..1usize]), ok)
}

// The form the top-level destinations take at a width: a bar along the bottom on
// a compact screen, a narrow rail at medium width, a sidebar with room for the
// labels when expanded (§3.7). v2 (D973, docs/ux/components/DestinationBar): the
// bar under 600, the rail from 600 and the sidebar from 1200.
type DestinationForm = enum u8 { Bottom, Rail, Sidebar }

fn destination_form(width: f32) -> DestinationForm {
    if width < 600.0 { ret .Bottom }
    if width < 1200.0 { ret .Rail }
    ret .Sidebar
}

// A destination (D973): its label, an optional drawn icon (`pictured`), a badge
// (a count or a word; `dot` for a dot on the icon), and the section heading it
// starts (a sidebar or a drawer draws a divider and the heading before it).
type Destination = struct { label: str, glyph: control.GlyphKind, pictured: bool, badge: str, dot: bool, section: str }

fn destination(label: str) -> Destination {
    var out: Destination = zero
    out.label = label
    ret out
}

fn destinations_of(a: *mem.Arena, labels: []const str) -> ([]Destination, err) {
    let (items, items_error) = mem.alloc[Destination](a, labels.len)
    if items_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < labels.len {
        items[i] = destination(labels[i])
        i += 1usize
    }
    ret (items[0usize..labels.len], ok)
}

// A destination's name (D973): its label and its badge's meaning ("Builds, 3";
// a dot is "new").
fn destination_name(a: *mem.Arena, item: *const Destination) -> (str, err) {
    if item.dot {
        let (named, named_error) = control.badge_name(a, item.label, "new")
        ret (named, named_error)
    }
    if item.badge.len > 0usize {
        let (counted, counted_error) = control.badge_name(a, item.label, item.badge)
        ret (counted, counted_error)
    }
    ret (item.label, ok)
}

type DestinationPick = struct { action: widget.Submit, runtime: *widget.Runtime, focus: widget.Key }

fn destination_pick_fire(ctx: *void) -> err {
    let p = mem.cast[*DestinationPick](ctx)
    let picked = widget.fire_submit(p.action)
    if picked != ok { ret picked }
    ret widget.focus_key(p.runtime, p.focus)
}

fn destination_actions(a: *mem.Arena, first: widget.Key, t: *const control.Theme, picks: []const widget.Submit, selected: usize) -> ([]widget.Submit, usize, err) {
    let (contexts, contexts_error) = mem.alloc[DestinationPick](a, picks.len)
    if contexts_error != ok { ret (zero, 0usize, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, picks.len)
    if actions_error != ok { ret (zero, 0usize, TooLarge) }
    var tab_stop = selected
    if tab_stop >= picks.len { tab_stop = 0usize }
    var i = 0usize
    while i < picks.len {
        if widget.focus_within(t.runtime, first + u64(i)) { tab_stop = i }
        contexts[i] = DestinationPick { action: picks[i], runtime: t.runtime, focus: first + u64(i) }
        actions[i] = widget.Submit { ctx: mem.cast[*void](&contexts[i]), invoke: destination_pick_fire }
        i += 1usize
    }
    ret (actions[0usize..picks.len], tab_stop, ok)
}

type DestinationMove = struct { runtime: *widget.Runtime, first: widget.Key, count: usize, backward: bool, edge: bool }

fn destination_move_fire(ctx: *void) -> err {
    let m = mem.cast[*DestinationMove](ctx)
    var current = 0usize
    while current < m.count {
        if widget.focus_within(m.runtime, m.first + u64(current)) { break }
        current += 1usize
    }
    if current == m.count { ret ok }
    var next_index = current
    if m.edge {
        if m.backward { next_index = 0usize } else { next_index = m.count - 1usize }
    } else if m.backward {
        if next_index > 0usize { next_index -= 1usize }
    } else if next_index + 1usize < m.count {
        next_index += 1usize
    }
    ret widget.focus_key(m.runtime, m.first + u64(next_index))
}

fn destination_tab_list(a: *mem.Arena, key: widget.Key, t: *const control.Theme, form: DestinationForm, picks: []const widget.Submit, direct_keys: bool, sem: widget.Semantics, body: widget.Node) -> (widget.Node, err) {
    let (moves, moves_error) = mem.alloc[DestinationMove](a, 4usize)
    if moves_error != ok { ret (zero, TooLarge) }
    var direct = 0usize
    if direct_keys && t.tokens.metrics.control_height <= t.tokens.sizes.control_sm {
        direct = picks.len
        if direct > 9usize { direct = 9usize }
    }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 4usize + direct)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    let horizontal = form == .Bottom
    var previous = 38u32
    var next = 40u32
    if horizontal {
        previous = 37u32
        next = 39u32
    }
    moves[0usize] = DestinationMove { runtime: t.runtime, first: key + 1u64, count: picks.len, backward: true, edge: false }
    moves[1usize] = DestinationMove { runtime: t.runtime, first: key + 1u64, count: picks.len, backward: false, edge: false }
    moves[2usize] = DestinationMove { runtime: t.runtime, first: key + 1u64, count: picks.len, backward: true, edge: true }
    moves[3usize] = DestinationMove { runtime: t.runtime, first: key + 1u64, count: picks.len, backward: false, edge: true }
    shortcuts[0usize] = widget.Shortcut { key: previous, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[0usize]), invoke: destination_move_fire } }
    shortcuts[1usize] = widget.Shortcut { key: next, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[1usize]), invoke: destination_move_fire } }
    shortcuts[2usize] = widget.Shortcut { key: 36u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[2usize]), invoke: destination_move_fire } }
    shortcuts[3usize] = widget.Shortcut { key: 35u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[3usize]), invoke: destination_move_fire } }
    var ctrl: input.Modifiers = zero
    ctrl.control = true
    var i = 0usize
    while i < direct {
        shortcuts[4usize + i] = widget.Shortcut { key: 49u32 + u32(i), modifiers: ctrl, action: picks[i] }
        i += 1usize
    }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = body
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..4usize + direct], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), held[0usize..1usize])
    ret (widget.semantics(key, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// The destinations as tabs keyed `key + 1 + index`, the current one selected and
// each firing its own pick: a row when the form is the bottom bar, a column
// otherwise. A tab list in the tree. The caller places it where the form says
// and lays the content out beside or above it; the width or the height it takes
// is `extent`. The v2 forms of D973 below over labels alone.
fn destination_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, form: DestinationForm, extent: f32) -> (widget.Node, err) {
    let (items, items_error) = destinations_of(a, labels)
    if items_error != ok { ret (zero, items_error) }
    let (made, made_error) = destination_bar_of(a, key, t, items, selected, picks, form, extent)
    ret (made, made_error)
}

// Drawer and sidebar rows (D973): each destination a row keyed `first + index`,
// `height` tall and `width` wide, `start` and `end` in, fully rounded; its 24
// icon and `label-large` label 12 apart in `on-surface-variant`, a trailing
// badge word in the same colour, the active row `secondary-container` with
// `on-secondary-container` content, under the content's state layer. A section
// starts with a 1px `outline-variant` divider (16 at the sides, 8 above and
// below; none before the first) and its `label-medium` heading in
// `on-surface-variant`, 16 in, 16 above and 8 below.
fn destination_rows(a: *mem.Arena, first: widget.Key, t: *const control.Theme, items: []const Destination, selected: usize, picks: []const widget.Submit, tab_stop: usize, height: f32, start: f32, end: f32, width: f32) -> ([]widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 3usize * items.len)
    if rows_error != ok { ret (zero, TooLarge) }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var n = 0usize
    var i = 0usize
    while i < items.len {
        let item = &items[i]
        if item.section.len > 0usize {
            if n > 0usize {
                var line = style.defaults()
                line.width = style.Length { Percent: 100.0 }
                line.height = style.Length { Px: t.tokens.sizes.divider }
                line.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
                let (lines, lines_error) = mem.alloc[widget.Node](a, 1usize)
                if lines_error != ok { ret (zero, TooLarge) }
                lines[0usize] = widget.box(0u64, line, zero)
                var ruled = style.defaults()
                ruled.width = style.Length { Px: width }
                rows[n] = widget.padded(0u64, 16.0, 8.0, 16.0, 8.0, ruled, lines[0usize..1usize])
                n += 1usize
            }
            var heading = control.text_options()
            heading.role = .LabelMedium
            heading.wrap = .None
            let (said, said_error) = control.colored_text(a, 0u64, item.section, t, heading, muted)
            if said_error != ok { ret (zero, said_error) }
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (zero, TooLarge) }
            held[0usize] = said
            var head_sem: widget.Semantics = zero
            head_sem.role = 25u8
            head_sem.label = item.section
            head_sem.level = 2u8
            let (heads, heads_error) = mem.alloc[widget.Node](a, 1usize)
            if heads_error != ok { ret (zero, TooLarge) }
            heads[0usize] = widget.padded(0u64, 16.0, 16.0, 16.0, 8.0, style.defaults(), held[0usize..1usize])
            rows[n] = widget.semantics(0u64, head_sem, style.defaults(), heads[0usize..1usize])
            n += 1usize
        }
        let chosen = i == selected
        let row_key = first + u64(i)
        let state = control.control_state(t, row_key, true, chosen)
        var ink = muted
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = control.with_alpha(ink, control.state_opacity(t, state))
        if chosen {
            ink = style.color(t.tokens, .OnSecondaryContainer)
            look.background = style.layer(style.color(t.tokens, .SecondaryContainer), ink, control.state_opacity(t, state))
        }
        look.foreground = ink
        look.border_width = 0.0
        look.opacity = 1.0
        look.radius = height * 0.5
        look.custom_padding = true
        look.padding = end
        look.padding_start = start
        look.padding_y = 0.0
        look.min_height = height
        look.min_width = width
        let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
        if parts_error != ok { ret (zero, TooLarge) }
        var p = 0usize
        if item.pictured {
            let (icon, icon_error) = control.icon_square(a, ink, item.glyph, 24.0)
            if icon_error != ok { ret (zero, icon_error) }
            parts[p] = icon
            p += 1usize
        }
        var caption = control.text_options()
        caption.role = .LabelLarge
        caption.wrap = .None
        caption.ellipsis = "..."
        caption.max_lines = 1u32
        let (label_node, label_error) = control.colored_text(a, 0u64, item.label, t, caption, ink)
        if label_error != ok { ret (zero, label_error) }
        parts[p] = label_node
        p += 1usize
        parts[p] = widget.spacer(0u64, 1.0)
        p += 1usize
        if item.badge.len > 0usize && !item.dot {
            let (count_node, count_error) = control.colored_text(a, 0u64, item.badge, t, caption, ink)
            if count_error != ok { ret (zero, count_error) }
            parts[p] = count_node
            p += 1usize
        }
        var line_style = style.defaults()
        line_style.width = style.Length { Px: control.max_zero(width - start - end) }
        line_style.height = style.Length { Px: height }
        let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, line_style, parts[0usize..p])
        let (named, named_error) = destination_name(a, item)
        if named_error != ok { ret (zero, named_error) }
        var states = 0u32
        if chosen { states = accessibility.STATE_CURRENT }
        let (row, row_error) = control.pressable_states(a, row_key, t, 19u8, named, look, true, chosen, states, 0u32, 0u64, &picks[i], content)
        if row_error != ok { ret (zero, row_error) }
        var placed = row
        if tab_stop < items.len && i != tab_stop {
            let (untabbed, untabbed_error) = untab_pressable(a, row)
            if untabbed_error != ok { ret (zero, untabbed_error) }
            placed = untabbed
        }
        rows[n] = placed
        n += 1usize
        i += 1usize
    }
    ret (rows[0usize..n], ok)
}

// v2 (D973, docs/ux/components/DestinationBar). The bar: 80 tall and `extent`
// wide on `surface-container`, 12 above, 16 below and 8 at the sides, the
// destinations sharing the width. The rail: `extent` (80) wide on `surface`, 16
// above, the destinations 12 apart. A bar or rail destination is its icon in a
// 32 tall fully rounded pill (64 wide in the bar, 56 in the rail) over its
// `label-medium` label, 4 apart and centred; at rest both are
// `on-surface-variant`, active the pill is `secondary-container` with the icon in
// `on-secondary-container` and the label `on-surface`; the state layer rides on
// the pill; a badge is D971's count (or dot) on the icon. With no icon the label
// stands in the pill. The sidebar: `extent` (240-360) wide on
// `surface-container-low`, 12 in, its destinations 40 tall rows (56 touch) of
// `destination_rows`, 16 in and 24 at the end. Every destination is a tab named
// by its label and badge, the active one Selected and Current, in a tab list
// named "Main". The current or focused destination is the bar's one Tab stop;
// Left/Right in the bottom bar or Up/Down in the rail and sidebar move focus,
// Home and End jump, the pressable's Enter and Space activate it, and pointer
// density binds Ctrl+1 through Ctrl+9 directly to the matching destination.
// ponytail: no rail menu button or FAB slot, sidebar header, hiding on scroll or
// pill growth; tabs rather than links in a navigation landmark (the spec allows
// tabs where the content changes without a URL).
fn destination_bar_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, items: []const Destination, selected: usize, picks: []const widget.Submit, form: DestinationForm, extent: f32) -> (widget.Node, err) {
    if picks.len != items.len { ret (zero, TooLarge) }
    let (pick_actions, tab_stop, pick_actions_error) = destination_actions(a, key + 1u64, t, picks, selected)
    if pick_actions_error != ok { ret (zero, pick_actions_error) }
    var sem: widget.Semantics = zero
    sem.role = 20u8
    sem.label = "Main"
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    if form == .Sidebar {
        let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
        var row_height: f32 = 40.0
        if touch { row_height = 56.0 }
        let (rows, rows_error) = destination_rows(a, key + 1u64, t, items, selected, pick_actions[0usize..items.len], tab_stop, row_height, 16.0, 24.0, control.max_zero(extent - 24.0))
        if rows_error != ok { ret (zero, rows_error) }
        var side = style.defaults()
        side.width = style.Length { Px: extent }
        side.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
        let rim = style.Length { Px: 12.0 }
        side.padding = style.EdgeLengths { left: rim, top: rim, right: rim, bottom: rim }
        body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, side, rows)
        sem.row_count = u32(items.len)
        let (made, made_error) = destination_tab_list(a, key, t, form, pick_actions, true, sem, body[0usize])
        ret (made, made_error)
    }
    let bottom = form == .Bottom
    var pill_width: f32 = 56.0
    var cell = extent
    var cell_height: f32 = 56.0
    if bottom {
        pill_width = 64.0
        cell_height = 52.0
        if items.len > 0usize { cell = control.max_zero(extent - 16.0) / f32(items.len) }
    }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let (cells, cells_error) = mem.alloc[widget.Node](a, items.len)
    if cells_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < items.len {
        let item = &items[i]
        let chosen = i == selected
        let tab_key = key + 1u64 + u64(i)
        let state = control.control_state(t, tab_key, true, chosen)
        var icon_ink = muted
        var label_ink = muted
        var pill = control.sized_style(pill_width, 32.0)
        pill.radius = 16.0
        pill.background = paint.Brush { Solid: control.with_alpha(muted, control.state_opacity(t, state)) }
        if chosen {
            icon_ink = style.color(t.tokens, .OnSecondaryContainer)
            label_ink = style.color(t.tokens, .OnSurface)
            pill.background = paint.Brush { Solid: style.layer(style.color(t.tokens, .SecondaryContainer), icon_ink, control.state_opacity(t, state)) }
        }
        var caption = control.text_options()
        caption.role = .LabelMedium
        caption.wrap = .None
        caption.ellipsis = "..."
        caption.max_lines = 1u32
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
        if parts_error != ok { ret (zero, TooLarge) }
        var p = 1usize
        if item.pictured {
            let (icon, icon_error) = control.icon_square(a, icon_ink, item.glyph, 24.0)
            if icon_error != ok { ret (zero, icon_error) }
            held[0usize] = icon
            if item.dot || item.badge.len > 0usize {
                var kind: control.BadgeKind = .Urgent
                if item.dot { kind = .Dot }
                let (mark, mark_error) = control.badge_of(a, 0u64, t, item.badge, kind)
                if mark_error != ok { ret (zero, mark_error) }
                let (marked, marked_error) = control.badge_anchor(a, 0u64, icon, 24.0, mark, item.dot)
                if marked_error != ok { ret (zero, marked_error) }
                held[0usize] = marked
            }
            let (label_node, label_error) = control.colored_text(a, 0u64, item.label, t, caption, label_ink)
            if label_error != ok { ret (zero, label_error) }
            parts[1usize] = label_node
            p = 2usize
        } else {
            let (label_node, label_error) = control.colored_text(a, 0u64, item.label, t, caption, label_ink)
            if label_error != ok { ret (zero, label_error) }
            held[0usize] = label_node
        }
        parts[0usize] = widget.aligned(0u64, .Center, .Center, pill, held[0usize..1usize])
        var column_style = style.defaults()
        column_style.width = style.Length { Px: cell }
        let content = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 4.0 }, column_style, parts[0usize..p])
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = control.with_alpha(muted, 0.0)
        look.foreground = label_ink
        look.border_width = 0.0
        look.opacity = 1.0
        look.radius = 0.0
        look.custom_padding = true
        look.padding = 0.0
        look.padding_y = 0.0
        look.min_width = cell
        look.min_height = cell_height
        let (named, named_error) = destination_name(a, item)
        if named_error != ok { ret (zero, named_error) }
        var states = 0u32
        if chosen { states = accessibility.STATE_CURRENT }
        let (tab, tab_error) = control.pressable_states(a, tab_key, t, 19u8, named, look, true, chosen, states, 0u32, 0u64, &pick_actions[i], content)
        if tab_error != ok { ret (zero, tab_error) }
        var placed = tab
        if i != tab_stop {
            let (untabbed, untabbed_error) = untab_pressable(a, tab)
            if untabbed_error != ok { ret (zero, untabbed_error) }
            placed = untabbed
        }
        cells[i] = placed
        i += 1usize
    }
    var sheet = style.defaults()
    if bottom {
        sheet = control.sized_style(extent, 80.0)
        sheet.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainer) }
        sheet.padding = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 12.0 }, right: style.Length { Px: 8.0 }, bottom: style.Length { Px: 16.0 } }
        body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, sheet, cells[0usize..items.len])
        sem.column_count = u32(items.len)
    } else {
        sheet.width = style.Length { Px: extent }
        sheet.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
        let flat = style.Length { Px: 0.0 }
        sheet.padding = style.EdgeLengths { left: flat, top: style.Length { Px: 16.0 }, right: flat, bottom: flat }
        body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 12.0 }, sheet, cells[0usize..items.len])
        sem.row_count = u32(items.len)
    }
    let (made, made_error) = destination_tab_list(a, key, t, form, pick_actions, true, sem, body[0usize])
    ret (made, made_error)
}

// --------------------------------------------------- adaptive navigation (D840, P2-08)

// A menu of a menu bar: its title and its commands.
type MenuBarItem = struct { label: str, items: []const overlay.MenuItem }

// A command in a menu bar's menu (D972): its label, what it does, whether it may
// be chosen, its shortcut's words ("Ctrl+S"; empty for none), whether it is
// checkable and checked, a radio choice or pictured with a leading glyph,
// whether a separator stands before it, whether it destroys (in `error`), and
// its first-level submenu state and toggle.
type BarCommand = struct { label: str, action: widget.Submit, enabled: bool, shortcut: str, checkable: bool, checked: bool, radio: bool, pictured: bool, glyph: control.GlyphKind, separated: bool, destructive: bool, submenu: []const BarCommand, submenu_open: bool, submenu_toggle: widget.Submit }

// A menu of the v2 menu bar (D972): its title and its commands.
type BarMenu = struct { label: str, commands: []const BarCommand }

fn menu_title_label(a: *mem.Arena, t: *const control.Theme, label: str, caption: control.TextOptions, ink: paint.Color, underlined: bool) -> (widget.Node, err) {
    if !underlined || label.len == 0usize {
        let (plain, plain_error) = control.colored_text(a, 0u64, label, t, caption, ink)
        ret (plain, plain_error)
    }
    let (_, first_bytes) = unicode.read_utf8(label, 0usize)
    let (advance, fit, baseline, metrics_error) = control.run_metrics(a, t, caption.role, label[0usize..first_bytes])
    if metrics_error != ok { ret (zero, metrics_error) }
    let (text_look, style_error) = control.text_style(a, t, caption.role)
    if style_error != ok { ret (zero, style_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (first, first_error) = control.colored_text(a, 0u64, label[0usize..first_bytes], t, caption, ink)
    if first_error != ok { ret (zero, first_error) }
    parts[0usize] = first
    var rule = control.sized_style(fit, t.tokens.sizes.divider)
    rule.background = paint.Brush { Solid: ink }
    parts[1usize] = widget.positioned(0u64, 0.0, baseline + 2.0, rule, zero)
    parts[2usize] = widget.stack(0u64, control.sized_style(advance, text_look.line_height), parts[0usize..2usize])
    let (rest, rest_error) = control.colored_text(a, 0u64, label[first_bytes..label.len], t, caption, ink)
    if rest_error != ok { ret (zero, rest_error) }
    parts[3usize] = rest
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), parts[2usize..4usize]), ok)
}

// A menu bar: the menus' titles in a row, 256 keys apart from `key + 1` (a
// title, its menu, up to fourteen commands and their first-level submenus), the
// one at `open` open (an index past the end for none), each firing its toggle; a
// group in the tree named `label`. The v2 bar of D972 below over plain commands.
fn menu_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, menus: []const MenuBarItem, open: usize, toggles: []const widget.Submit) -> (widget.Node, err) {
    let (bars, bars_error) = mem.alloc[BarMenu](a, menus.len)
    if bars_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < menus.len {
        let items = menus[i].items
        let (commands, commands_error) = mem.alloc[BarCommand](a, items.len)
        if commands_error != ok { ret (zero, TooLarge) }
        var j = 0usize
        while j < items.len {
            var command: BarCommand = zero
            command.label = items[j].label
            command.action = items[j].action
            command.enabled = items[j].enabled
            commands[j] = command
            j += 1usize
        }
        bars[i] = BarMenu { label: menus[i].label, commands: commands[0usize..items.len] }
        i += 1usize
    }
    let (made, made_error) = menu_bar_of(a, key, t, label, bars[0usize..menus.len], open, toggles)
    ret (made, made_error)
}

// v2 (D972, docs/ux/components/MenuBar): full-bleed and square, 32 tall on
// `surface`, 4 in at the ends. A title (keyed `key + 1 + 256 * index`) is 24 tall,
// 8 at its sides, `radius-xs`, its `body-medium` label in `on-surface` under the
// `state-hover` layer, the titles touching; the open one is `secondary-container`
// with `on-secondary-container` and Expanded, its menu (keyed `key + 2 + 256 *
// index`, its commands `key + 3 + 256 * index + j`, at most 14) hanging 2 below
// it: `surface-container`, `radius-sm`, elevation 2, 8 at top and bottom, 200 to
// 320 wide. A command is 32 tall, 12 at its sides, 8 between its parts: the 18
// leading slot (a check; reserved in every command once any is checked), the
// `body-medium` label in `on-surface` (`error` when destructive) and the
// shortcut in `on-surface-variant` at the end, at least 32 after the label. A
// separator is a 1px `outline-variant` line with 8 above and below. A disabled
// command is `on-surface` at 38% under no layer. A MenuBar in the tree named
// by `label`.
// A command can open a submenu to its right, overlapping by 4 and aligned 8
// above the row; cascades repeat that rule, Right opens one level, Left closes
// it, and a leaf closes the full chain.
// ponytail: no collapsed form.
// Command dismissal and focus return are shared by the widget runtime.
fn menu_bar_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, menus: []const BarMenu, open: usize, toggles: []const widget.Submit) -> (widget.Node, err) {
    if toggles.len != menus.len { ret (zero, TooLarge) }
    let (heads, heads_error) = mem.alloc[widget.Node](a, 2usize * menus.len)
    if heads_error != ok { ret (zero, TooLarge) }
    let ink = style.color(t.tokens, .OnSurface)
    var i = 0usize
    while i < menus.len {
        if menus[i].commands.len > 14usize { ret (zero, TooLarge) }
        let title_key = key + 1u64 + 256u64 * u64(i)
        let opened = i == open
        let state = control.control_state(t, title_key, true, false)
        var tint = ink
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = control.with_alpha(ink, control.state_opacity(t, state))
        if opened {
            tint = style.color(t.tokens, .OnSecondaryContainer)
            look.background = style.layer(style.color(t.tokens, .SecondaryContainer), tint, control.state_opacity(t, state))
        }
        look.foreground = tint
        look.border_width = 0.0
        look.opacity = 1.0
        look.radius = t.tokens.radii.xs
        look.custom_padding = true
        look.padding = 8.0
        look.padding_y = 2.0
        look.min_height = 24.0
        look.min_width = 16.0
        var caption = control.text_options()
        caption.role = .BodyMedium
        caption.wrap = .None
        let (label_node, label_error) = menu_title_label(a, t, menus[i].label, caption, tint, widget.menu_access_keys_visible(t.runtime))
        if label_error != ok { ret (zero, label_error) }
        var states = 0u32
        if opened { states = accessibility.STATE_EXPANDED }
        let (head, head_error) = control.pressable_states(a, title_key, t, 3u8, menus[i].label, look, true, false, states, accessibility.ACTION_SHOW_MENU, title_key + 1u64, &toggles[i], label_node)
        if head_error != ok { ret (zero, head_error) }
        heads[2usize * i] = head
        let (hung, hung_error) = bar_menu(a, title_key + 1u64, t, title_key, menus[i].label, menus[i].commands, opened, &toggles[i])
        if hung_error != ok { ret (zero, hung_error) }
        heads[2usize * i + 1usize] = hung
        i += 1usize
    }
    var bar = style.defaults()
    bar.width = style.Length { Percent: 100.0 }
    bar.height = style.Length { Px: 32.0 }
    bar.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let ends = style.Length { Px: 4.0 }
    let flat = style.Length { Px: 0.0 }
    bar.padding = style.EdgeLengths { left: ends, top: flat, right: ends, bottom: flat }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, bar, heads[0usize..2usize * menus.len])
    var sem: widget.Semantics = zero
    sem.role = accessibility.ROLE_MENU_BAR
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// A menu bar's menu (D972): a modal overlay 2 below `anchor` while `open`, the
// commands keyed `key + 1 + index`; a press outside it or Escape fires `dismiss`.
fn bar_menu(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, label: str, commands: []const BarCommand, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let (made, made_error) = bar_menu_at(a, key, t, anchor, label, commands, open, dismiss, .Below, geometry.Point { x: 0.0, y: 2.0 }, 0u8)
    ret (made, made_error)
}

fn bar_menu_at(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, label: str, commands: []const BarCommand, open: bool, dismiss: *const widget.Submit, placement: widget.Placement, offset: geometry.Point, depth: u8) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    if commands.len > 14usize { ret (zero, TooLarge) }
    var slotted = false
    var k = 0usize
    while k < commands.len {
        if commands[k].checkable || commands[k].checked || commands[k].radio || commands[k].pictured { slotted = true }
        k += 1usize
    }
    let (rows, rows_error) = mem.alloc[widget.Node](a, 3usize * commands.len)
    if rows_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    var i = 0usize
    while i < commands.len {
        let c = &commands[i]
        let has_submenu = c.submenu.len != 0usize
        if c.separated && i > 0usize {
            let (lines, lines_error) = mem.alloc[widget.Node](a, 1usize)
            if lines_error != ok { ret (zero, TooLarge) }
            var line = style.defaults()
            line.width = style.Length { Percent: 100.0 }
            line.height = style.Length { Px: t.tokens.sizes.divider }
            line.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
            lines[0usize] = widget.box(0u64, line, zero)
            rows[n] = widget.padded(0u64, 0.0, 8.0, 0.0, 8.0, style.defaults(), lines[0usize..1usize])
            n += 1usize
        }
        let item_key = key + 1u64 + u64(i)
        var state = control.control_state(t, item_key, c.enabled, false)
        if c.submenu_open { state.hovered = true }
        var ink = style.color(t.tokens, .OnSurface)
        if c.destructive { ink = style.color(t.tokens, .Error) }
        var muted = style.color(t.tokens, .OnSurfaceVariant)
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = control.with_alpha(ink, control.state_opacity(t, state))
        if !c.enabled {
            ink = control.with_alpha(style.color(t.tokens, .OnSurface), t.tokens.states.disabled_content)
            muted = ink
            look.background = control.with_alpha(ink, 0.0)
        }
        look.foreground = ink
        look.border_width = 0.0
        look.opacity = 1.0
        look.radius = 0.0
        look.custom_padding = true
        look.padding = 12.0
        look.padding_y = 0.0
        look.min_height = 32.0
        look.min_width = 24.0
        let (parts, parts_error) = mem.alloc[widget.Node](a, 5usize)
        if parts_error != ok { ret (zero, TooLarge) }
        var p = 0usize
        if slotted {
            if c.radio && c.checked {
                let (tick, tick_error) = overlay.menu_radio_dot(a, ink, 18.0)
                if tick_error != ok { ret (zero, tick_error) }
                parts[p] = tick
            } else if c.checked {
                let (tick, tick_error) = control.icon_square(a, ink, .Check, 18.0)
                if tick_error != ok { ret (zero, tick_error) }
                parts[p] = tick
            } else if c.pictured && !c.radio && !c.checkable {
                var icon_ink = muted
                if c.destructive { icon_ink = ink }
                let (tick, tick_error) = control.icon_square(a, icon_ink, c.glyph, 18.0)
                if tick_error != ok { ret (zero, tick_error) }
                parts[p] = tick
            } else {
                parts[p] = widget.box(0u64, control.sized_style(18.0, 18.0), zero)
            }
            p += 1usize
        }
        var caption = control.text_options()
        caption.role = .BodyMedium
        caption.wrap = .None
        let (said, said_error) = control.colored_text(a, 0u64, c.label, t, caption, ink)
        if said_error != ok { ret (zero, said_error) }
        parts[p] = said
        p += 1usize
        parts[p] = widget.spacer(0u64, 1.0)
        p += 1usize
        if c.shortcut.len > 0usize {
            let (keys_node, keys_error) = control.colored_text(a, 0u64, c.shortcut, t, caption, muted)
            if keys_error != ok { ret (zero, keys_error) }
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (zero, TooLarge) }
            held[0usize] = keys_node
            parts[p] = widget.padded(0u64, 24.0, 0.0, 0.0, 0.0, style.defaults(), held[0usize..1usize])
            p += 1usize
        }
        if has_submenu {
            let (arrow, arrow_error) = control.icon_square(a, muted, .ChevronRight, 18.0)
            if arrow_error != ok { ret (zero, arrow_error) }
            parts[p] = arrow
            p += 1usize
        }
        var line_style = style.defaults()
        line_style.width = style.Length { Percent: 100.0 }
        let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, line_style, parts[0usize..p])
        var sem_states = 0u32
        if c.checked { sem_states = accessibility.STATE_CHECKED }
        var semantic_role = 22u8
        if c.checkable || c.checked { semantic_role = accessibility.ROLE_MENU_ITEM_CHECKBOX }
        if c.radio { semantic_role = accessibility.ROLE_MENU_ITEM_RADIO }
        var sem_actions = 0u32
        var controls = 0u64
        var chosen = &c.action
        var submenu_key = key + 15u64 + 16u64 * u64(i)
        if depth > 0u8 { submenu_key = key * 32u64 + 16u64 + u64(i) }
        if has_submenu {
            sem_actions = accessibility.ACTION_SHOW_MENU
            controls = submenu_key
            chosen = &c.submenu_toggle
            if c.submenu_open { sem_states = sem_states | accessibility.STATE_EXPANDED }
        }
        let (made, made_error) = control.pressable_states(a, item_key, t, semantic_role, c.label, look, c.enabled, false, sem_states, sem_actions, controls, chosen, content)
        if made_error != ok { ret (zero, made_error) }
        rows[n] = made
        n += 1usize
        if has_submenu {
            let (nested, nested_error) = bar_menu_at(a, submenu_key, t, item_key, c.label, c.submenu, c.submenu_open, &c.submenu_toggle, .Right, geometry.Point { x: -4.0, y: -8.0 }, depth + 1u8)
            if nested_error != ok { ret (zero, nested_error) }
            rows[n] = nested
            n += 1usize
        }
        i += 1usize
    }
    var sheet = control.surface_options(t)
    sheet.background = .SurfaceContainer
    sheet.elevation = 2u8
    sheet.radius = t.tokens.radii.sm
    sheet.padding = 0.0
    var sheet_style = control.surface_style(t, sheet)
    let flat = style.Length { Px: 0.0 }
    let rim = style.Length { Px: 8.0 }
    sheet_style.padding = style.EdgeLengths { left: flat, top: rim, right: flat, bottom: rim }
    sheet_style.min_width = style.Length { Px: 200.0 }
    sheet_style.max_width = style.Length { Px: 320.0 }
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
    let (lifted, lifted_error) = mem.alloc[widget.Node](a, 1usize)
    if lifted_error != ok { ret (zero, TooLarge) }
    lifted[0usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: placement, offset: offset, modal: true, dismiss: *dismiss }, style.defaults(), lifted[0usize..1usize]), ok)
}

// A context menu: D827's menu (keyed `key`, items `key + 1 + index`) below
// `anchor` while `open`; the caller opens it from the secondary press or the
// keyboard's menu key it handles itself, and `dismiss` closes it. v2 (D975):
// `overlay.context_menu_of` as opened from the keyboard, below `anchor`; touch
// density uses the lifted-target scrim form.
fn context_menu(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, label: str, items: []const overlay.MenuItem, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (commands, commands_error) = mem.alloc[overlay.MenuCommand](a, items.len)
    if commands_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < items.len {
        commands[i] = overlay.menu_command(items[i].label, items[i].action)
        commands[i].enabled = items[i].enabled
        i += 1usize
    }
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm {
        let (made, made_error) = overlay.context_menu_touch_of(a, key, t, anchor, label, commands[0usize..items.len], open, dismiss)
        ret (made, made_error)
    }
    let (made, made_error) = overlay.context_menu_of(a, key, t, anchor, label, commands[0usize..items.len], open, dismiss, zero, false)
    ret (made, made_error)
}

// A navigation split: `primary` and `detail` side by side in D826's split view
// (keyed `key`, the pane `key + 1`) when the width reaches the medium size
// class; compact, one of them alone -- the detail while `showing_detail`, so a
// push shows it and a pop (the caller's) shows the primary again. The v2 split
// of D973 below, side by side from medium width.
fn navigation_split(a: *mem.Arena, key: widget.Key, t: *const control.Theme, primary: widget.Node, detail: widget.Node, showing_detail: bool, position: f32, change: widget.Change[f32], width: f32, height: f32) -> (widget.Node, err) {
    var options = navigation_split_options()
    options.medium = true
    let (made, made_error) = navigation_split_of(a, key, t, primary, detail, showing_detail, position, change, width, height, options)
    ret (made, made_error)
}

// A navigation split's form (D973): side by side from the medium size class
// (600) rather than expanded (840); the panes' names (the list's also names
// Back); the statement the detail shows while nothing is selected (empty: the
// detail itself); and in a single pane, the detail's title under a Back bar
// firing `pop` (no title: no bar).
type NavigationSplitOptions = struct { medium: bool, list_label: str, detail_label: str, empty: str, detail_title: str, pop: widget.Submit }

fn navigation_split_options() -> NavigationSplitOptions {
    var out: NavigationSplitOptions = zero
    out.list_label = "List"
    out.detail_label = "Detail"
    ret out
}

// v2 (D973, docs/ux/components/NavigationSplit): side by side from expanded
// width (840; medium, 600, on request), the list pane on
// `surface-container-low` and the detail on `surface`, flush at pointer density
// across D966's 1px `outline-variant` sash named "Resize list"; the list keeps
// 200 and the detail 320 (280 and 360 at touch density, where the window is 16
// in and both panes take `radius-lg`, the detail on
// `surface-container-lowest`). Each pane is a group named by its label. With
// nothing selected the detail shows the `empty` statement centred in
// `body-medium` `on-surface-variant`. In a single pane the list, or the detail
// under a v2 app bar (keyed `key + 4`) led by Back (`key + 5`) named "Back to
// <the list>"; Escape and Alt+Left share its `pop` action.
// ponytail: the touch divider is D966's sash, not the 24 gutter with its 4 x 48
// handle; no supporting pane, snap points, push motion or focus moves.
fn navigation_split_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, primary: widget.Node, detail: widget.Node, showing_detail: bool, position: f32, change: widget.Change[f32], width: f32, height: f32, options: NavigationSplitOptions) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    let size = style.size_class(width)
    let side_by_side = size == .Expanded || (options.medium && size != .Compact)
    var radius: f32 = 0.0
    if touch && side_by_side { radius = t.tokens.radii.lg }
    // The list pane.
    let (lists, lists_error) = mem.alloc[widget.Node](a, 1usize)
    if lists_error != ok { ret (zero, TooLarge) }
    lists[0usize] = primary
    var list_style = style.defaults()
    list_style.width = style.Length { Percent: 100.0 }
    list_style.height = style.Length { Percent: 100.0 }
    list_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    list_style.radius = radius
    list_style.overflow = .Clip
    let (list_boxes, list_boxes_error) = mem.alloc[widget.Node](a, 1usize)
    if list_boxes_error != ok { ret (zero, TooLarge) }
    list_boxes[0usize] = widget.box(0u64, list_style, lists[0usize..1usize])
    var list_sem: widget.Semantics = zero
    list_sem.role = 2u8
    list_sem.label = options.list_label
    let list_pane = widget.semantics(0u64, list_sem, style.defaults(), list_boxes[0usize..1usize])
    // The detail pane.
    let (details, details_error) = mem.alloc[widget.Node](a, 1usize)
    if details_error != ok { ret (zero, TooLarge) }
    details[0usize] = detail
    if options.empty.len > 0usize {
        var said = control.text_options()
        said.role = .BodyMedium
        said.align = .Center
        let (statement, statement_error) = control.colored_text(a, 0u64, options.empty, t, said, style.color(t.tokens, .OnSurfaceVariant))
        if statement_error != ok { ret (zero, statement_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = statement
        var middle = style.defaults()
        middle.width = style.Length { Percent: 100.0 }
        middle.height = style.Length { Percent: 100.0 }
        details[0usize] = widget.aligned(0u64, .Center, .Center, middle, held[0usize..1usize])
    }
    var detail_style = style.defaults()
    detail_style.width = style.Length { Percent: 100.0 }
    detail_style.height = style.Length { Percent: 100.0 }
    if side_by_side {
        // Beside the pane the detail stands in a flexible slot, where a 100%
        // width would ask for the whole row: it is what the pane and sash leave.
        var hit: f32 = 8.0
        var inset: f32 = 0.0
        if touch {
            hit = 24.0
            inset = 16.0
        }
        detail_style.width = style.Length { Px: control.max_zero(width - 2.0 * inset - position - hit) }
    }
    if !side_by_side && showing_detail && options.detail_title.len > 0usize {
        // Under the Back bar the detail takes what the bar leaves.
        var bar_height: f32 = 48.0
        if touch { bar_height = 64.0 }
        detail_style.height = style.Length { Px: control.max_zero(height - bar_height) }
    }
    detail_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    if touch && side_by_side { detail_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLowest) } }
    detail_style.radius = radius
    detail_style.overflow = .Clip
    let (detail_boxes, detail_boxes_error) = mem.alloc[widget.Node](a, 1usize)
    if detail_boxes_error != ok { ret (zero, TooLarge) }
    detail_boxes[0usize] = widget.box(0u64, detail_style, details[0usize..1usize])
    var detail_sem: widget.Semantics = zero
    detail_sem.role = 2u8
    detail_sem.label = options.detail_label
    let detail_pane = widget.semantics(0u64, detail_sem, style.defaults(), detail_boxes[0usize..1usize])
    if side_by_side {
        var least_list: f32 = 200.0
        var least_detail: f32 = 320.0
        var inset: f32 = 0.0
        if touch {
            least_list = 280.0
            least_detail = 360.0
            inset = 16.0
        }
        let (split, split_error) = control.split_view_named(a, key, t, "Resize list", .Horizontal, list_pane, detail_pane, position, least_list, least_detail, change, control.max_zero(width - 2.0 * inset), control.max_zero(height - 2.0 * inset))
        if split_error != ok { ret (zero, split_error) }
        if !touch { ret (split, ok) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = split
        var window = control.sized_style(width, height)
        window.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
        ret (widget.padded(0u64, inset, inset, inset, inset, window, held[0usize..1usize]), ok)
    }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = list_pane
    if showing_detail {
        body[0usize] = detail_pane
        if options.detail_title.len > 0usize {
            var bar_options = app_bar_options()
            let (named, named_error) = joined(a, "Back to ", options.list_label)
            if named_error != ok { ret (zero, named_error) }
            bar_options.back_label = named
            bar_options.back = options.pop
            var nothing: []const Action = zero
            let (bar, bar_error) = app_bar_of(a, key + 4u64, t, options.detail_title, nothing, nothing, bar_options, width)
            if bar_error != ok { ret (zero, bar_error) }
            let (stacked, stacked_error) = mem.alloc[widget.Node](a, 2usize)
            if stacked_error != ok { ret (zero, TooLarge) }
            stacked[0usize] = bar
            stacked[1usize] = detail_pane
            var column = style.defaults()
            column.width = style.Length { Px: width }
            column.height = style.Length { Px: height }
            body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, column, stacked[0usize..2usize])
        }
    }
    var page = control.sized_style(width, height)
    page.overflow = .Clip
    var sem: widget.Semantics = zero
    sem.role = 2u8
    let (boxed, boxed_error) = mem.alloc[widget.Node](a, 1usize)
    if boxed_error != ok { ret (zero, TooLarge) }
    boxed[0usize] = widget.box(key, page, body[0usize..1usize])
    let made = widget.semantics(0u64, sem, style.defaults(), boxed[0usize..1usize])
    if showing_detail && options.detail_title.len > 0usize {
        let (backed, backed_error) = back_scope(a, key + 6u64, made, options.pop)
        ret (backed, backed_error)
    }
    ret (made, ok)
}

// A navigation drawer: the destinations (their rows keyed `key + 2 + index`) in
// a modal overlay (keyed `key`) along the left edge of the window while `open`;
// a press outside or Escape fires `dismiss`; nothing while shut. The v2 modal
// drawer of D973 below over labels alone.
fn navigation_drawer(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, open: bool, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let (items, items_error) = destinations_of(a, labels)
    if items_error != ok { ret (zero, items_error) }
    let (made, made_error) = navigation_drawer_of(a, key, t, "", items, selected, picks, open, dismiss, width)
    ret (made, made_error)
}

// A drawer's sheet (D973): the optional header, then the rows, in a column
// `width` wide, `pad` in; a list named "Main" (keyed `key`). The selected or
// focused row is its one Tab stop; Up/Down move focus, Home/End jump, and the
// pressable's Enter and Space activate it. The runtime's buffered TabList
// typeahead moves focus by label.
fn drawer_sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, header: str, items: []const Destination, selected: usize, picks: []const widget.Submit, row_height: f32, start: f32, end: f32, pad: f32, head_top: f32, head_bottom: f32, width: f32) -> (widget.Node, err) {
    if picks.len != items.len { ret (zero, TooLarge) }
    let (pick_actions, tab_stop, pick_actions_error) = destination_actions(a, key + 1u64, t, picks, selected)
    if pick_actions_error != ok { ret (zero, pick_actions_error) }
    let (rows, rows_error) = destination_rows(a, key + 1u64, t, items, selected, pick_actions, tab_stop, row_height, start, end, control.max_zero(width - 2.0 * pad))
    if rows_error != ok { ret (zero, rows_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, rows.len + 1usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    if header.len > 0usize {
        var heading = control.text_options()
        heading.role = .TitleSmall
        heading.wrap = .None
        let (said, said_error) = control.colored_text(a, 0u64, header, t, heading, style.color(t.tokens, .OnSurfaceVariant))
        if said_error != ok { ret (zero, said_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = said
        let sides = control.max_zero(16.0 - pad)
        parts[0usize] = widget.padded(0u64, sides, control.max_zero(head_top - pad), sides, head_bottom, style.defaults(), held[0usize..1usize])
        n = 1usize
    }
    var k = 0usize
    while k < rows.len {
        parts[n] = rows[k]
        n += 1usize
        k += 1usize
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..n])
    var sem: widget.Semantics = zero
    sem.role = 20u8
    sem.label = "Main"
    sem.row_count = u32(items.len)
    let (made, made_error) = destination_tab_list(a, key, t, .Sidebar, pick_actions, false, sem, column[0usize])
    ret (made, made_error)
}

type DrawerPick = struct { pick: widget.Submit, dismiss: widget.Submit }

fn drawer_pick_fire(ctx: *void) -> err {
    let p = mem.cast[*DrawerPick](ctx)
    let picked = widget.fire_submit(p.pick)
    if picked != ok { ret picked }
    ret widget.fire_submit(p.dismiss)
}

// v2 (D973, docs/ux/components/NavigationDrawer, modal): 256 to 360 wide and the
// window's height on `surface-container-low`, its end corners `radius-lg`,
// elevation 1, 12 in, over a `scrim` at 32% across the window; the header in
// `title-small` `on-surface-variant` 16 in, 16 above and 12 below; the rows of
// `destination_rows` 56 tall, 16 in and 24 at the end, sections with their
// headings and dividers. A modal dialog named "Navigation" round the list; a
// successful destination pick, press on the scrim or Escape fires `dismiss`.
// ponytail: no edge swipe or open/close motion.
fn navigation_drawer_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, header: str, items: []const Destination, selected: usize, picks: []const widget.Submit, open: bool, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    if picks.len != items.len { ret (zero, TooLarge) }
    let (pick_contexts, pick_contexts_error) = mem.alloc[DrawerPick](a, picks.len)
    if pick_contexts_error != ok { ret (zero, TooLarge) }
    let (closing_picks, closing_picks_error) = mem.alloc[widget.Submit](a, picks.len)
    if closing_picks_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < picks.len {
        pick_contexts[i] = DrawerPick { pick: picks[i], dismiss: *dismiss }
        closing_picks[i] = widget.Submit { ctx: mem.cast[*void](&pick_contexts[i]), invoke: drawer_pick_fire }
        i += 1usize
    }
    var wide = width
    if wide < 256.0 { wide = 256.0 }
    if wide > 360.0 { wide = 360.0 }
    let (sheet_node, sheet_error) = drawer_sheet(a, key + 1u64, t, header, items, selected, closing_picks[0usize..picks.len], 56.0, 16.0, 24.0, 12.0, 16.0, 12.0, wide)
    if sheet_error != ok { ret (zero, sheet_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = sheet_node
    var sheet = control.surface_options(t)
    sheet.background = .SurfaceContainerLow
    sheet.elevation = 1u8
    sheet.radius = 0.0
    sheet.padding = 12.0
    var sheet_style = control.surface_style(t, sheet)
    sheet_style.width = style.Length { Px: wide }
    sheet_style.height = style.Length { Percent: 100.0 }
    let lg = t.tokens.radii.lg
    sheet_style.corners = style.Corners { top_left: 0.0, top_right: lg, bottom_right: lg, bottom_left: 0.0 }
    let rtl = t.tokens.direction == .RightToLeft
    if rtl { sheet_style.corners = style.Corners { top_left: lg, top_right: 0.0, bottom_right: 0.0, bottom_left: lg } }
    let (panel, panel_error) = mem.alloc[widget.Node](a, 1usize)
    if panel_error != ok { ret (zero, TooLarge) }
    panel[0usize] = widget.box(0u64, sheet_style, body[0usize..1usize])
    var none: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: zero, cancel_action: *dismiss, keys: zero }, style.defaults(), panel[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 23u8
    sem.label = "Navigation"
    sem.states = accessibility.STATE_MODAL
    let (drawer, drawer_error) = mem.alloc[widget.Node](a, 1usize)
    if drawer_error != ok { ret (zero, TooLarge) }
    drawer[0usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    // The scrim is an overlay of its own under the drawer: a press on it misses
    // the modal drawer, which dismisses it.
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
    var placement: widget.Placement = .Left
    if rtl { placement = .Right }
    layers[1usize] = widget.overlay(key, widget.Overlay { anchor: 0u64, placement: placement, offset: zero, modal: true, dismiss: *dismiss }, style.defaults(), drawer[0usize..1usize])
    ret (widget.box(0u64, style.defaults(), layers[0usize..2usize]), ok)
}

// v2 (D973, docs/ux/components/NavigationDrawer, standard): in the layout,
// `width` wide (200-280 at pointer density) and `height` tall, square with no
// shadow on `surface-container-low`, 8 in (12 touch); the header 12 above and 8
// below (16 and 12 touch); rows 40 tall 12 in at both ends (56, 16 and 24
// touch); the list (keyed `key + 1`, rows `key + 2 + index`) in a group named
// "Main" keyed `key`.
// ponytail: no hiding, collapsing to the rail or resizing sash.
fn navigation_drawer_standard(a: *mem.Arena, key: widget.Key, t: *const control.Theme, header: str, items: []const Destination, selected: usize, picks: []const widget.Submit, width: f32, height: f32) -> (widget.Node, err) {
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var row_height: f32 = 40.0
    var start: f32 = 12.0
    var end: f32 = 12.0
    var pad: f32 = 8.0
    var head_top: f32 = 12.0
    var head_bottom: f32 = 8.0
    if touch {
        row_height = 56.0
        start = 16.0
        end = 24.0
        pad = 12.0
        head_top = 16.0
        head_bottom = 12.0
    }
    let (sheet_node, sheet_error) = drawer_sheet(a, key + 1u64, t, header, items, selected, picks, row_height, start, end, pad, head_top, head_bottom, width)
    if sheet_error != ok { ret (zero, sheet_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = sheet_node
    var sheet_style = control.sized_style(width, height)
    sheet_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    let rim = style.Length { Px: pad }
    sheet_style.padding = style.EdgeLengths { left: rim, top: rim, right: rim, bottom: rim }
    let (panel, panel_error) = mem.alloc[widget.Node](a, 1usize)
    if panel_error != ok { ret (zero, TooLarge) }
    panel[0usize] = widget.box(0u64, sheet_style, body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = "Main"
    ret (widget.semantics(key, sem, style.defaults(), panel[0usize..1usize]), ok)
}

// The three explicit forms of the destination bar, for a caller that chooses.
fn navigation_rail(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = destination_bar(a, key, t, labels, selected, picks, .Rail, width)
    ret (made, made_error)
}

fn bottom_navigation(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = destination_bar(a, key, t, labels, selected, picks, .Bottom, width)
    ret (made, made_error)
}

fn sidebar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = destination_bar(a, key, t, labels, selected, picks, .Sidebar, width)
    ret (made, made_error)
}

// Breadcrumbs: the path's names in a row, every one but the last a link keyed
// `key + 1 + index` firing its pick, the last the current place; a group in the
// tree named `label`. The full trail of D972 below.
fn breadcrumbs(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, names: []const str, picks: []const widget.Submit) -> (widget.Node, err) {
    let (made, made_error) = breadcrumbs_of(a, key, t, label, names, picks, breadcrumbs_options())
    ret (made, made_error)
}

// A trail's form (D972): `hidden` middle levels collapsed into one overflow crumb
// (keyed `key + 40`; its menu `key + 41`, the levels `key + 42 + index`) that
// `toggle` opens while `open`; or `compact`, the parent link alone.
type BreadcrumbsOptions = struct { hidden: usize, open: bool, toggle: widget.Submit, compact: bool }

fn breadcrumbs_options() -> BreadcrumbsOptions {
    var out: BreadcrumbsOptions = zero
    ret out
}

// A crumb's look (D972): `height` tall, 8 at the sides, `radius-sm`, the ink
// `on-surface-variant` (`on-surface` hovered) and its `state-hover` layer.
fn crumb_look(t: *const control.Theme, key: widget.Key, height: f32) -> (style.ResolvedControl, paint.Color) {
    let state = control.control_state(t, key, true, false)
    var ink = style.color(t.tokens, .OnSurfaceVariant)
    if state.hovered { ink = style.color(t.tokens, .OnSurface) }
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = control.with_alpha(ink, control.state_opacity(t, state))
    look.foreground = ink
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = t.tokens.radii.sm
    look.custom_padding = true
    look.padding = 8.0
    look.padding_y = 0.0
    look.min_height = height
    look.min_width = 16.0
    ret (look, ink)
}

// One crumb (D972): a link keyed `key` named `label`, its `body-medium` words (or
// `glyph` when `drawn`) under the crumb look, at most `widest` across.
fn trail_crumb(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, action: *const widget.Submit, height: f32, widest: f32) -> (widget.Node, err) {
    let (look, ink) = crumb_look(t, key, height)
    var caption = control.text_options()
    caption.role = .BodyMedium
    caption.wrap = .None
    caption.ellipsis = "..."
    caption.max_lines = 1u32
    let (said, said_error) = control.colored_text(a, 0u64, label, t, caption, ink)
    if said_error != ok { ret (zero, said_error) }
    let (made, made_error) = control.pressable_states(a, key, t, 9u8, label, look, true, false, 0u32, 0u32, 0u64, action, said)
    if made_error != ok { ret (zero, made_error) }
    var capped = made
    capped.style.max_width = style.Length { Px: widest }
    ret (capped, ok)
}

// v2 (D972, docs/ux/components/Breadcrumbs): one row that never wraps. A crumb is
// a link 32 tall at pointer density (48 touch), 8 at its sides, `radius-sm`, its
// `body-medium` label in `on-surface-variant` (`on-surface` hovered) under the
// `state-hover` layer, at most 200 wide (160 touch) and cut with an ellipsis.
// Between crumbs stands a 16 direction-mirrored chevron in
// `on-surface-variant`, out of the tree. The current place is `body-medium` at 600 (`title-small`) in
// `on-surface`, at most 320 wide: text marked Current, no Tab stop. With `hidden`
// levels the root and the last two stay and the rest collapse into a `more-horiz`
// crumb, a button named "Show 3 hidden levels" with a menu of them in order.
// Compact, the trail is the parent alone as a 48 tall link led by
// a start-facing chevron. The trail is a group named `label` round a list.
// ponytail: the caller says how many levels collapse (the width is not measured);
// the ellipsis ends a name rather than cutting its middle; no root icon, drop
// targets, sibling menus or editable path.
fn breadcrumbs_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, names: []const str, picks: []const widget.Submit, options: BreadcrumbsOptions) -> (widget.Node, err) {
    if picks.len != names.len || names.len == 0usize { ret (zero, TooLarge) }
    if options.hidden > 0usize && options.hidden + 3usize > names.len { ret (zero, TooLarge) }
    let (held, held_error) = mem.alloc[widget.Submit](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = options.toggle
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var h: f32 = 32.0
    var widest: f32 = 200.0
    if touch {
        h = 48.0
        widest = 160.0
    }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let rtl = t.tokens.direction == .RightToLeft
    let last = names.len - 1usize
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize * names.len + 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    if options.compact && names.len > 1usize {
        let parent = last - 1usize
        let parent_key = key + 1u64 + u64(parent)
        let (look, ink) = crumb_look(t, parent_key, 48.0)
        let (bits, bits_error) = mem.alloc[widget.Node](a, 2usize)
        if bits_error != ok { ret (zero, TooLarge) }
        var parent_glyph: control.GlyphKind = .ChevronLeft
        if rtl { parent_glyph = .ChevronRight }
        let (chevron, chevron_error) = control.icon_square(a, ink, parent_glyph, 18.0)
        if chevron_error != ok { ret (zero, chevron_error) }
        bits[0usize] = chevron
        var caption = control.text_options()
        caption.role = .BodyMedium
        caption.wrap = .None
        let (said, said_error) = control.colored_text(a, 0u64, names[parent], t, caption, ink)
        if said_error != ok { ret (zero, said_error) }
        bits[1usize] = said
        // The row stands the target's full 48, so the chevron and name centre in it.
        var row_style = style.defaults()
        row_style.height = style.Length { Px: 48.0 }
        let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, row_style, bits[0usize..2usize])
        let (made, made_error) = control.pressable_states(a, parent_key, t, 9u8, names[parent], look, true, false, 0u32, 0u32, 0u64, &picks[parent], content)
        if made_error != ok { ret (zero, made_error) }
        parts[0usize] = made
        n = 1usize
    } else {
        var i = 0usize
        while i < names.len {
            if i > 0usize {
                var separator_glyph: control.GlyphKind = .ChevronRight
                if rtl { separator_glyph = .ChevronLeft }
                let (chevron, chevron_error) = control.icon_square(a, muted, separator_glyph, 16.0)
                if chevron_error != ok { ret (zero, chevron_error) }
                parts[n] = chevron
                n += 1usize
            }
            if options.hidden > 0usize && i == 1usize {
                // The overflow crumb over the collapsed levels.
                let (items, items_error) = mem.alloc[overlay.MenuItem](a, options.hidden)
                if items_error != ok { ret (zero, TooLarge) }
                var k = 0usize
                while k < options.hidden {
                    items[k] = overlay.MenuItem { label: names[1usize + k], action: picks[1usize + k], enabled: true }
                    k += 1usize
                }
                let (digits, digits_error) = mem.alloc[u8](a, 21usize)
                if digits_error != ok { ret (zero, TooLarge) }
                let count = control.write_i64(digits, i64(options.hidden))
                var tail = " hidden levels"
                if options.hidden == 1usize { tail = " hidden level" }
                let (front, front_error) = joined(a, "Show ", digits[0usize..count])
                if front_error != ok { ret (zero, front_error) }
                let (named, named_error) = joined(a, front, tail)
                if named_error != ok { ret (zero, named_error) }
                let (look, ink) = crumb_look(t, key + 40u64, h)
                let (dots, dots_error) = control.icon_square(a, ink, .MoreHoriz, 18.0)
                if dots_error != ok { ret (zero, dots_error) }
                var states = 0u32
                if options.open { states = accessibility.STATE_EXPANDED }
                let (more, more_error) = control.pressable_states(a, key + 40u64, t, 3u8, named, look, true, false, states, accessibility.ACTION_SHOW_MENU, key + 41u64, &held[0usize], dots)
                if more_error != ok { ret (zero, more_error) }
                parts[n] = more
                n += 1usize
                let (menu_node, menu_error) = overlay.menu(a, key + 41u64, t, key + 40u64, "Hidden levels", items[0usize..options.hidden], options.open, &held[0usize])
                if menu_error != ok { ret (zero, menu_error) }
                parts[n] = menu_node
                n += 1usize
                i += options.hidden
                continue
            }
            if i < last {
                let (made, made_error) = trail_crumb(a, key + 1u64 + u64(i), t, names[i], &picks[i], h, widest)
                if made_error != ok { ret (zero, made_error) }
                parts[n] = made
                n += 1usize
            } else {
                var here = control.text_options()
                here.role = .TitleSmall
                here.wrap = .None
                here.ellipsis = "..."
                here.max_lines = 1u32
                let (current, current_error) = control.colored_text(a, 0u64, names[i], t, here, style.color(t.tokens, .OnSurface))
                if current_error != ok { ret (zero, current_error) }
                let (held_text, held_text_error) = mem.alloc[widget.Node](a, 1usize)
                if held_text_error != ok { ret (zero, TooLarge) }
                held_text[0usize] = current
                var place = style.defaults()
                place.height = style.Length { Px: h }
                place.max_width = style.Length { Px: 320.0 }
                let sides = style.Length { Px: 8.0 }
                let flat = style.Length { Px: 0.0 }
                place.padding = style.EdgeLengths { left: sides, top: flat, right: sides, bottom: flat }
                let (placed, placed_error) = mem.alloc[widget.Node](a, 1usize)
                if placed_error != ok { ret (zero, TooLarge) }
                placed[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, place, held_text[0usize..1usize])
                var here_sem: widget.Semantics = zero
                here_sem.role = 6u8
                here_sem.states = accessibility.STATE_CURRENT
                parts[n] = widget.semantics(0u64, here_sem, style.defaults(), placed[0usize..1usize])
                n += 1usize
            }
            i += 1usize
        }
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), parts[0usize..n])
    var list_sem: widget.Semantics = zero
    list_sem.role = 10u8
    list_sem.row_count = u32(names.len)
    let (listed, listed_error) = mem.alloc[widget.Node](a, 1usize)
    if listed_error != ok { ret (zero, TooLarge) }
    listed[0usize] = widget.semantics(0u64, list_sem, style.defaults(), row[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), listed[0usize..1usize]), ok)
}

// ------------------------------------------------------ document workspace (D852, P3-03)

// An open document: its stable key, its title, whether it has unsaved changes,
// whether it is pinned (its tab keeps no close button and stays where it is).
type Document = struct { key: widget.Key, title: str, dirty: bool, pinned: bool }

// A document tab moved from one index to another.
type DocumentMove = struct { from: usize, to: usize }

// A tab's gestures: a tap picks it, a drag begins a move carrying the index
// (D844), a drop of another's tab on it ends one.
type TabGesture = struct { runtime: *widget.Runtime, focus: widget.Key, index: usize, pinned: bool, pick: widget.Change[usize], move: widget.Change[DocumentMove] }

fn tab_gesture(ctx: *void, g: widget.Gesture) -> err {
    let h = mem.cast[*TabGesture](ctx)
    switch g {
    case .Tap as at:
        let picked = widget.fire_change[usize](h.pick, h.index)
        if picked != ok { ret picked }
        ret widget.focus_key(h.runtime, h.focus)
    case .DragStart as at:
        if h.pinned { ret ok }
        ret widget.begin_drag(h.runtime, u64(h.index) + 1u64)
    case .Drop as d:
        if d.payload == 0u64 || h.pinned { ret ok }
        let from = usize(d.payload - 1u64)
        if from == h.index { ret ok }
        ret widget.fire_change[DocumentMove](h.move, DocumentMove { from: from, to: h.index })
    default:
        ret ok
    }
}

type TabClose = struct { index: usize, close: widget.Change[usize] }

fn tab_close_fire(ctx: *void) -> err {
    let c = mem.cast[*TabClose](ctx)
    ret widget.fire_change[usize](c.close, c.index)
}

type TabPick = struct { index: usize, pick: widget.Change[usize], runtime: *widget.Runtime, focus: widget.Key }

fn tab_pick_fire(ctx: *void) -> err {
    let p = mem.cast[*TabPick](ctx)
    let picked = widget.fire_change[usize](p.pick, p.index)
    if picked != ok { ret picked }
    ret widget.focus_key(p.runtime, p.focus)
}

type TabMove = struct { move: widget.Change[DocumentMove], from: usize, to: usize, runtime: *widget.Runtime, focus: widget.Key }

fn tab_move_fire(ctx: *void) -> err {
    let m = mem.cast[*TabMove](ctx)
    let moved = widget.fire_change[DocumentMove](m.move, DocumentMove { from: m.from, to: m.to })
    if moved != ok { ret moved }
    ret widget.focus_key(m.runtime, m.focus)
}

// A shared pressable remains pointer-accessible while excluded from a roving
// Tab order.
fn untab_pressable(a: *mem.Arena, node: widget.Node) -> (widget.Node, err) {
    if node.children.len != 1usize { ret (node, ok) }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, TooLarge) }
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

// Document tabs: a tab a document keyed `key + 1 + 2 * index`, the current one
// selected, with a close button (keyed `key + 2 + 2 * index`) after the title
// unless pinned; a tap picks, a close reports the index through `close`, a tab
// dragged onto another reports a `DocumentMove` (pinned tabs neither move nor
// take a drop), and Left and Right from a focused tab pick the neighbours. A tab
// list in the tree named `label`. The v2 strip of D974 below, no group active.
fn document_tabs(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, documents: []const Document, current: usize, pick: widget.Change[usize], close: widget.Change[usize], move: widget.Change[DocumentMove]) -> (widget.Node, err) {
    let (made, made_error) = document_tabs_marked(a, key, t, label, documents, current, pick, close, move, false, false)
    ret (made, made_error)
}

// The same in an editor group (D969): `active` when the group has the keyboard
// focus, which marks its current tab. (`marked` is kept for the callers of
// D969; every v2 tab keeps room for the line.)
//
// v2 (D974, docs/ux/components/DocumentTabs): a strip 40 tall (56 touch) on
// `surface-container`, 4 in at the sides, its tabs 2 apart along the bottom. A
// tab is 36 tall (48 touch), 96 to 220 wide (120 to 240), `radius-sm` at its top
// corners: 12 in at the start (16 touch), 4 at the end, 8 between its parts. Its
// `body-medium` title is one line with an ellipsis, `on-surface-variant` at rest
// under the `state-hover` layer; the current tab is `surface` with an
// `on-surface` title, and in the active group a 2px `primary` line runs along its
// top edge. The close slot is a 24 round button (40 touch) with a 16 (24)
// `close` glyph named "Close <title>"; while the document is dirty and the tab
// neither hovered nor focused it holds an 8 dot in the title colour instead. A
// pinned tab has no close. A tab is named with its state ("lower.e, unsaved
// changes", "neper.json, pinned"), its position and Selected; Home and End pick
// the ends and Delete closes the current tab, beside Left and Right. Ctrl+PageUp
// and Ctrl+PageDown select the previous or next tab in strip order, wrapping;
// adding Shift moves the current tab one place without wrapping.
// The current or focused tab is the strip's one tab stop; close buttons remain
// pointer-only.
// (D1233) Each tab offers Show menu: Close, Close others, Close to the right and
// Close saved over its unpinned tabs.
// ponytail: no file-type icons (a pinned tab keeps its title), preview tabs,
// dragged lift or drop line, overflow scrolling, Show all open files, Pin, Copy
// path, Reveal or Split in the menu, or read-only mark.
// (D1233) A document strip's tab menu, kept across frames on the strip: whether
// it is open and for which tab.
type TabMenu = struct { open: bool, index: usize }
type TabMenuAsk = struct { runtime: *widget.Runtime, cell: *TabMenu, index: usize }

fn tab_menu_cell(t: *const control.Theme, key: widget.Key) -> (*TabMenu, bool) {
    var none: *TabMenu = zero
    if mem.address_of(t.runtime) == 0usize { ret (none, false) }
    let (s, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret (none, false) }
    let (id, found) = widget.find_by_key(s, key)
    if found != 1usize { ret (none, false) }
    var build = widget.BuildContext { runtime: t.runtime, element: id, frame: 0u64 }
    let (kept, _, kept_error) = widget.state[TabMenu](&build, key, TabMenu { open: false, index: 0usize })
    if kept_error != ok { ret (none, false) }
    ret (kept, true)
}

fn tab_menu_ask(ctx: *void, action: u32) -> err {
    let ask = mem.cast[*TabMenuAsk](ctx)
    if action != accessibility.ACTION_SHOW_MENU { ret ok }
    ask.cell.open = true
    ask.cell.index = ask.index
    widget.request_animation_frame(ask.runtime)
    ret ok
}

// (D1233) A tab menu command: `close` for each index listed, highest first so
// the caller's lower indices still name the same documents; then the menu shuts.
type TabCloseMany = struct { runtime: *widget.Runtime, cell: *TabMenu, close: widget.Change[usize], indices: []const usize }

fn tab_close_many(ctx: *void) -> err {
    let c = mem.cast[*TabCloseMany](ctx)
    c.cell.open = false
    widget.request_animation_frame(c.runtime)
    var at = c.indices.len
    while at > 0usize {
        at -= 1usize
        try widget.fire_change[usize](c.close, c.indices[at])
    }
    ret ok
}

// (D1233, docs/ux/components/DocumentTabs) The menu of the tab `menu_for`: Close,
// Close others, Close to the right and Close saved, each over the unpinned tabs
// it names and disabled when it names none.
fn tab_menu(a: *mem.Arena, key: widget.Key, t: *const control.Theme, documents: []const Document, menu_for: usize, cell: *TabMenu, close: widget.Change[usize]) -> (widget.Node, err) {
    let n = documents.len
    let (lists, lists_error) = mem.alloc[usize](a, 4usize * n)
    if lists_error != ok { ret (zero, TooLarge) }
    var counts: [4]usize = zero
    var i = 0usize
    while i < n {
        if !documents[i].pinned {
            if i == menu_for {
                lists[counts[0usize]] = i
                counts[0usize] += 1usize
            } else {
                lists[n + counts[1usize]] = i
                counts[1usize] += 1usize
            }
            if i > menu_for {
                lists[2usize * n + counts[2usize]] = i
                counts[2usize] += 1usize
            }
            if !documents[i].dirty {
                lists[3usize * n + counts[3usize]] = i
                counts[3usize] += 1usize
            }
        }
        i += 1usize
    }
    let (runs, runs_error) = mem.alloc[TabCloseMany](a, 5usize)
    if runs_error != ok { ret (zero, TooLarge) }
    let (commands, commands_error) = mem.alloc[overlay.MenuCommand](a, 4usize)
    if commands_error != ok { ret (zero, TooLarge) }
    var names: [4]str = zero
    names[0usize] = "Close"
    names[1usize] = "Close others"
    names[2usize] = "Close to the right"
    names[3usize] = "Close saved"
    var none: []const usize = zero
    i = 0usize
    while i < 4usize {
        runs[i] = TabCloseMany { runtime: t.runtime, cell: cell, close: close, indices: lists[i * n..i * n + counts[i]] }
        commands[i] = overlay.menu_command(names[i], widget.Submit { ctx: mem.cast[*void](&runs[i]), invoke: tab_close_many })
        commands[i].enabled = counts[i] > 0usize
        i += 1usize
    }
    runs[4usize] = TabCloseMany { runtime: t.runtime, cell: cell, close: close, indices: none }
    let (closer, closer_error) = mem.alloc[widget.Submit](a, 1usize)
    if closer_error != ok { ret (zero, TooLarge) }
    closer[0usize] = widget.Submit { ctx: mem.cast[*void](&runs[4usize]), invoke: tab_close_many }
    let (at, pointed) = widget.context_point(t.runtime)
    let (made, made_error) = overlay.context_menu_of(a, key, t, key - 129u64 + 2u64 * u64(menu_for), documents[menu_for].title, commands[0usize..4usize], true, &closer[0usize], at, pointed)
    ret (made, made_error)
}

fn document_tabs_marked(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, documents: []const Document, current: usize, pick: widget.Change[usize], close: widget.Change[usize], move: widget.Change[DocumentMove], marked: bool, active: bool) -> (widget.Node, err) {
    if documents.len > 64usize { ret (zero, TooLarge) }
    let touch = t.tokens.metrics.control_height > t.tokens.sizes.control_sm
    var strip_height: f32 = 40.0
    var tab_height: f32 = 36.0
    var least: f32 = 96.0
    var most: f32 = 220.0
    var start: f32 = 12.0
    var closer: f32 = 24.0
    var cross: f32 = 16.0
    if touch {
        strip_height = 56.0
        tab_height = 48.0
        least = 120.0
        most = 240.0
        start = 16.0
        closer = 40.0
        cross = 24.0
    }
    let (tabs, tabs_error) = mem.alloc[widget.Node](a, documents.len)
    if tabs_error != ok { ret (zero, TooLarge) }
    let (gestures, gestures_error) = mem.alloc[TabGesture](a, documents.len)
    if gestures_error != ok { ret (zero, TooLarge) }
    let (closes, closes_error) = mem.alloc[TabClose](a, documents.len)
    if closes_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, documents.len)
    if actions_error != ok { ret (zero, TooLarge) }
    let (picks, picks_error) = mem.alloc[TabPick](a, 6usize)
    if picks_error != ok { ret (zero, TooLarge) }
    let (moves, moves_error) = mem.alloc[TabMove](a, 2usize)
    if moves_error != ok { ret (zero, TooLarge) }
    let (menu_cell, has_menu_cell) = tab_menu_cell(t, key)
    let (asks, asks_error) = mem.alloc[TabMenuAsk](a, documents.len)
    if asks_error != ok { ret (zero, TooLarge) }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var tab_stop = current
    if tab_stop >= documents.len { tab_stop = 0usize }
    var focused = 0usize
    while focused < documents.len {
        if widget.focus_within(t.runtime, key + 1u64 + 2u64 * u64(focused)) {
            tab_stop = focused
            break
        }
        focused += 1usize
    }
    var i = 0usize
    while i < documents.len {
        let d = documents[i]
        let chosen = i == current
        let tab_key = key + 1u64 + 2u64 * u64(i)
        let close_key = key + 2u64 + 2u64 * u64(i)
        gestures[i] = TabGesture { runtime: t.runtime, focus: tab_key, index: i, pinned: d.pinned, pick: pick, move: move }
        closes[i] = TabClose { index: i, close: close }
        actions[i] = widget.Submit { ctx: mem.cast[*void](&closes[i]), invoke: tab_close_fire }
        let state = control.control_state(t, tab_key, true, chosen)
        var ink = muted
        var ground = control.with_alpha(muted, control.state_opacity(t, state))
        if chosen {
            ink = style.color(t.tokens, .OnSurface)
            ground = style.layer(style.color(t.tokens, .Background), ink, control.state_opacity(t, state))
        }
        var caption = control.text_options()
        caption.role = .BodyMedium
        caption.wrap = .None
        caption.ellipsis = "..."
        caption.max_lines = 1u32
        let (title_node, title_node_error) = control.colored_text(a, 0u64, d.title, t, caption, ink)
        if title_node_error != ok { ret (zero, title_node_error) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
        if parts_error != ok { ret (zero, TooLarge) }
        parts[0usize] = title_node
        var part_count = 1usize
        if !d.pinned {
            // The close slot: the close glyph, or the unsaved dot at rest.
            let close_state = control.control_state(t, close_key, true, false)
            let showing = !d.dirty || state.hovered || state.focus_visible || close_state.hovered || close_state.focus_visible
            var slot_look = style.resolve(t.tokens, .Plain, close_state)
            slot_look.background = control.with_alpha(muted, control.state_opacity(t, close_state))
            slot_look.foreground = muted
            slot_look.border_width = 0.0
            slot_look.opacity = 1.0
            slot_look.radius = closer * 0.5
            slot_look.custom_padding = true
            slot_look.padding = (closer - cross) * 0.5
            slot_look.padding_y = (closer - cross) * 0.5
            slot_look.min_width = closer
            slot_look.min_height = closer
            var mark = widget.box(0u64, control.sized_style(cross, cross), zero)
            if showing {
                let (glyph, glyph_error) = control.icon_square(a, muted, .Cross, cross)
                if glyph_error != ok { ret (zero, glyph_error) }
                mark = glyph
            } else {
                let (dots, dots_error) = mem.alloc[widget.Node](a, 1usize)
                if dots_error != ok { ret (zero, TooLarge) }
                var dot = control.sized_style(8.0, 8.0)
                dot.radius = 4.0
                dot.background = paint.Brush { Solid: ink }
                dots[0usize] = widget.box(0u64, dot, zero)
                mark = widget.aligned(0u64, .Center, .Center, control.sized_style(cross, cross), dots[0usize..1usize])
            }
            let (close_name, close_name_error) = joined(a, "Close ", d.title)
            if close_name_error != ok { ret (zero, close_name_error) }
            let (closing, closing_error) = control.pressable(a, close_key, t, 3u8, close_name, slot_look, true, false, &actions[i], mark)
            if closing_error != ok { ret (zero, closing_error) }
            let (untabbed, untabbed_error) = untab_pressable(a, closing)
            if untabbed_error != ok { ret (zero, untabbed_error) }
            parts[1usize] = untabbed
            part_count = 2usize
        }
        var line_style = style.defaults()
        line_style.height = style.Length { Px: tab_height - 2.0 }
        line_style.min_width = style.Length { Px: least }
        let flat = style.Length { Px: 0.0 }
        line_style.padding = style.EdgeLengths { left: style.Length { Px: start }, top: flat, right: style.Length { Px: 4.0 }, bottom: flat }
        let (lined, lined_error) = mem.alloc[widget.Node](a, 2usize)
        if lined_error != ok { ret (zero, TooLarge) }
        var line = style.defaults()
        line.height = style.Length { Px: 2.0 }
        if chosen && active { line.background = paint.Brush { Solid: style.color(t.tokens, .Primary) } }
        lined[0usize] = widget.box(0u64, line, zero)
        lined[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 8.0 }, line_style, parts[0usize..part_count])
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), lined[0usize..2usize])
        var tab_style = style.defaults()
        tab_style.background = paint.Brush { Solid: ground }
        tab_style.height = style.Length { Px: tab_height }
        tab_style.min_width = style.Length { Px: least }
        tab_style.max_width = style.Length { Px: most }
        let sm = t.tokens.radii.sm
        tab_style.corners = style.Corners { top_left: sm, top_right: sm, bottom_right: 0.0, bottom_left: 0.0 }
        tab_style.overflow = .Clip
        let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
        if region_error != ok { ret (zero, TooLarge) }
        control.focus_look(t)
        region[0usize] = widget.region(tab_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&gestures[i]), invoke: tab_gesture }, gestures: 1u8 | 2u8 | 4u8 | 8u8, enabled: true, focusable: i == tab_stop }, tab_style, body[0usize..1usize])
        var named = d.title
        if d.dirty {
            let (dirty_name, dirty_error) = joined(a, d.title, ", unsaved changes")
            if dirty_error != ok { ret (zero, dirty_error) }
            named = dirty_name
        }
        if d.pinned {
            let (pinned_name, pinned_error) = joined(a, named, ", pinned")
            if pinned_error != ok { ret (zero, pinned_error) }
            named = pinned_name
        }
        var sem: widget.Semantics = zero
        sem.role = 19u8
        sem.label = named
        sem.column = u32(i + 1usize)
        sem.column_count = u32(documents.len)
        sem.actions = accessibility.ACTION_PRESS
        if has_menu_cell {
            asks[i] = TabMenuAsk { runtime: t.runtime, cell: menu_cell, index: i }
            sem.actions = accessibility.ACTION_PRESS | accessibility.ACTION_SHOW_MENU
            sem.on_action = widget.Change[u32] { ctx: mem.cast[*void](&asks[i]), invoke: tab_menu_ask }
        }
        if chosen { sem.states = accessibility.STATE_SELECTED }
        if d.dirty { sem.hint = "unsaved" }
        tabs[i] = widget.semantics(0u64, sem, style.defaults(), region[0usize..1usize])
        i += 1usize
    }
    // Left and Right pick the neighbours of the current tab, Home and End the
    // ends; Delete closes it.
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 7usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    let (move_shortcuts, move_shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if move_shortcuts_error != ok { ret (zero, TooLarge) }
    var bound = 0usize
    var move_bound = 0usize
    if current > 0usize && current < documents.len {
        picks[0usize] = TabPick { index: current - 1usize, pick: pick, runtime: t.runtime, focus: key + 1u64 + 2u64 * u64(current - 1usize) }
        shortcuts[bound] = widget.Shortcut { key: 37u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&picks[0usize]), invoke: tab_pick_fire } }
        picks[2usize] = TabPick { index: 0usize, pick: pick, runtime: t.runtime, focus: key + 1u64 }
        shortcuts[bound + 1usize] = widget.Shortcut { key: 36u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&picks[2usize]), invoke: tab_pick_fire } }
        bound += 2usize
    }
    if current + 1usize < documents.len {
        picks[1usize] = TabPick { index: current + 1usize, pick: pick, runtime: t.runtime, focus: key + 1u64 + 2u64 * u64(current + 1usize) }
        shortcuts[bound] = widget.Shortcut { key: 39u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&picks[1usize]), invoke: tab_pick_fire } }
        picks[3usize] = TabPick { index: documents.len - 1usize, pick: pick, runtime: t.runtime, focus: key + 1u64 + 2u64 * u64(documents.len - 1usize) }
        shortcuts[bound + 1usize] = widget.Shortcut { key: 35u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&picks[3usize]), invoke: tab_pick_fire } }
        bound += 2usize
    }
    if current < documents.len && !documents[current].pinned {
        shortcuts[bound] = widget.Shortcut { key: 46u32, modifiers: zero, action: actions[current] }
        bound += 1usize
    }
    if documents.len > 1usize && current < documents.len {
        var previous = documents.len - 1usize
        if current > 0usize { previous = current - 1usize }
        var next = 0usize
        if current + 1usize < documents.len { next = current + 1usize }
        picks[4usize] = TabPick { index: previous, pick: pick, runtime: t.runtime, focus: key + 1u64 + 2u64 * u64(previous) }
        picks[5usize] = TabPick { index: next, pick: pick, runtime: t.runtime, focus: key + 1u64 + 2u64 * u64(next) }
        var ctrl: input.Modifiers = zero
        ctrl.control = true
        shortcuts[bound] = widget.Shortcut { key: 33u32, modifiers: ctrl, action: widget.Submit { ctx: mem.cast[*void](&picks[4usize]), invoke: tab_pick_fire } }
        shortcuts[bound + 1usize] = widget.Shortcut { key: 34u32, modifiers: ctrl, action: widget.Submit { ctx: mem.cast[*void](&picks[5usize]), invoke: tab_pick_fire } }
        bound += 2usize
        ctrl.shift = true
        if current > 0usize {
            moves[0usize] = TabMove { move: move, from: current, to: current - 1usize, runtime: t.runtime, focus: key + 1u64 + 2u64 * u64(current - 1usize) }
            move_shortcuts[move_bound] = widget.Shortcut { key: 33u32, modifiers: ctrl, action: widget.Submit { ctx: mem.cast[*void](&moves[0usize]), invoke: tab_move_fire } }
            move_bound += 1usize
        }
        if current + 1usize < documents.len {
            moves[1usize] = TabMove { move: move, from: current, to: current + 1usize, runtime: t.runtime, focus: key + 1u64 + 2u64 * u64(current + 1usize) }
            move_shortcuts[move_bound] = widget.Shortcut { key: 34u32, modifiers: ctrl, action: widget.Submit { ctx: mem.cast[*void](&moves[1usize]), invoke: tab_move_fire } }
            move_bound += 1usize
        }
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    var strip = style.defaults()
    strip.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainer) }
    strip.height = style.Length { Px: strip_height }
    let sides = style.Length { Px: 4.0 }
    let flat = style.Length { Px: 0.0 }
    strip.padding = style.EdgeLengths { left: sides, top: flat, right: sides, bottom: flat }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .End, gap: 2.0 }, strip, tabs[0usize..documents.len])
    let (moving, moving_error) = mem.alloc[widget.Node](a, 1usize)
    if moving_error != ok { ret (zero, TooLarge) }
    moving[0usize] = row[0usize]
    if move_bound > 0usize {
        moving[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: move_shortcuts[0usize..move_bound], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), row[0usize..1usize])
    }
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..bound], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), moving[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 20u8
    sem.label = label
    sem.column_count = u32(documents.len)
    let strip_node = widget.semantics(key, sem, style.defaults(), scoped[0usize..1usize])
    // (D1233) The open tab menu stands beside the strip.
    if has_menu_cell && menu_cell.open && menu_cell.index < documents.len {
        let (menu, menu_error) = tab_menu(a, key + 130u64, t, documents, menu_cell.index, menu_cell, close)
        if menu_error != ok { ret (zero, menu_error) }
        let (both, both_error) = mem.alloc[widget.Node](a, 2usize)
        if both_error != ok { ret (zero, TooLarge) }
        both[0usize] = strip_node
        both[1usize] = menu
        ret (widget.box(0u64, style.defaults(), both[0usize..2usize]), ok)
    }
    ret (strip_node, ok)
}

// A dock panel: the docked panel of D966 below, unfocused.
fn dock_panel(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, close: *const widget.Submit) -> (widget.Node, err) {
    let (made, made_error) = dock_panel_of(a, key, t, title, content, close, dock_panel_options())
    ret (made, made_error)
}

// A dock panel's state (D967): focus inside it, floating rather than docked,
// maximised, busy, the empty-state sentence (set: shown in place of the
// content), the tab group sharing its slot (the panels' names, their count badges
// -- empty or one each --, the current one and a pick each), and the Maximise and
// Dock actions (none: no button).
type DockPanelOptions = struct { focused: bool, floating: bool, maximised: bool, busy: bool, empty: str, tabs: []const str, counts: []const str, current: usize, picks: []const widget.Submit, maximise: *const widget.Submit, dock: *const widget.Submit }

fn dock_panel_options() -> DockPanelOptions {
    var out: DockPanelOptions = zero
    ret out
}

fn dock_header_gesture(ctx: *void, g: widget.Gesture) -> err {
    switch g {
    case .DoubleTap as at:
        ret widget.fire_submit(*mem.cast[*const widget.Submit](ctx))
    default:
        ret ok
    }
}

// A panel tab (D967): `label-medium`, 12 each side, 32 tall under the
// `on-surface` state layer; the current one `on-surface` over a 2px `primary`
// line as wide as its label, the others `on-surface-variant`; a count badge on
// `secondary-container` after the label.
fn panel_tab(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, count: str, chosen: bool, pick: *const widget.Submit) -> (widget.Node, err) {
    let state = control.control_state(t, key, true, chosen)
    var ink = style.color(t.tokens, .OnSurfaceVariant)
    if chosen { ink = style.color(t.tokens, .OnSurface) }
    var look = style.resolve(t.tokens, .Plain, state)
    look.background = style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), style.color(t.tokens, .OnSurface), control.state_opacity(t, state))
    look.foreground = ink
    look.border_width = 0.0
    look.opacity = 1.0
    look.radius = 0.0
    look.custom_padding = true
    look.padding = 12.0
    look.padding_y = 0.0
    look.min_height = t.tokens.sizes.control_sm
    look.min_width = 24.0
    var caption = control.text_options()
    caption.role = .LabelMedium
    caption.wrap = .None
    let (words, words_error) = control.colored_text(a, 0u64, label, t, caption, ink)
    if words_error != ok { ret (zero, words_error) }
    let (bits, bits_error) = mem.alloc[widget.Node](a, 4usize)
    if bits_error != ok { ret (zero, TooLarge) }
    bits[0usize] = words
    var used = 1usize
    if count.len != 0usize {
        var small = control.text_options()
        small.role = .LabelSmall
        small.wrap = .None
        let (said, said_error) = control.colored_text(a, 0u64, count, t, small, style.color(t.tokens, .OnSecondaryContainer))
        if said_error != ok { ret (zero, said_error) }
        bits[3usize] = said
        var pill = style.defaults()
        pill.background = paint.Brush { Solid: style.color(t.tokens, .SecondaryContainer) }
        pill.radius = 8.0
        pill.min_width = style.Length { Px: 16.0 }
        pill.min_height = style.Length { Px: 16.0 }
        pill.padding = style.EdgeLengths { left: style.Length { Px: 4.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 4.0 }, bottom: style.Length { Px: 0.0 } }
        bits[1usize] = widget.box(0u64, pill, bits[3usize..4usize])
        used = 2usize
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 3usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), bits[0usize..used])
    var line = style.defaults()
    line.height = style.Length { Px: 2.0 }
    if chosen { line.background = paint.Brush { Solid: style.color(t.tokens, .Primary) } }
    column[1usize] = widget.box(0u64, line, zero)
    var stacked = style.defaults()
    stacked.height = style.Length { Px: t.tokens.sizes.control_sm }
    let content = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .End, cross: .Stretch, gap: 7.0 }, stacked, column[0usize..2usize])
    let (made, made_error) = control.pressable_states(a, key, t, 19u8, label, look, true, chosen, 0u32, 0u32, 0u64, pick, content)
    ret (made, made_error)
}

// v2 (D966, D967, docs/ux/components/DockPanel): docked, `surface-container-low`,
// square, no border and no padding (sashes separate panels), at least 160 wide,
// under a 32 header, 12 at the start and 4 at the end: the title in
// `label-medium` `on-surface-variant` (`on-surface` while `focused`, with a 2px
// `primary` line inside the header's top edge) -- or, as a tab group, the panel
// tabs (keyed `key + 4 + index`, Left and Right picking the neighbours) -- then
// the header actions, 32 round buttons with 18 drawn icons and no gap: Maximise
// (keyed `key + 2`; "Restore panel" with `chevron-down` while maximised), Ctrl+M,
// and Close (keyed `key + 1`), named "Close <title> panel". Floating, the panel is
// `surface-container`, `radius-md`, `elevation-3`, at least 240 x 160, its
// header 40 with a drag handle leading and a Dock button (`key + 3`, `dock-left`)
// before Maximise, the title `on-surface` and no focus line. Double-clicking the
// header fires that same Maximise action. Busy, a 2px
// `primary` bar sweeps under the header (centred and pulsing with reduced motion);
// with an empty sentence the body is that sentence in `body-small`
// `on-surface-variant`, 12 in and 8 down. A region in the tree named by the title,
// busy while busy.
// ponytail: moving a floating panel is the caller's (its header is no drag region yet).
fn dock_panel_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, close: *const widget.Submit, options: DockPanelOptions) -> (widget.Node, err) {
    let floating = options.floating
    let focused = options.focused || widget.focus_within(t.runtime, key)
    var h = t.tokens.sizes.control_sm
    if floating { h = t.tokens.sizes.control_md }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var ink = muted
    if focused || floating { ink = style.color(t.tokens, .OnSurface) }
    let (head, head_error) = mem.alloc[widget.Node](a, 6usize)
    if head_error != ok { ret (zero, TooLarge) }
    var used = 0usize
    if floating {
        let (handle, handle_error) = control.icon_square(a, muted, .DragHandle, t.tokens.sizes.icon_sm)
        if handle_error != ok { ret (zero, handle_error) }
        head[used] = handle
        used += 1usize
    }
    if options.tabs.len != 0usize {
        if options.picks.len != options.tabs.len { ret (zero, TooLarge) }
        let (tabbed, tabbed_error) = mem.alloc[widget.Node](a, options.tabs.len)
        if tabbed_error != ok { ret (zero, TooLarge) }
        var i = 0usize
        while i < options.tabs.len {
            var count: str = ""
            if options.counts.len == options.tabs.len { count = options.counts[i] }
            let (tab, tab_error) = panel_tab(a, key + 4u64 + u64(i), t, options.tabs[i], count, i == options.current, &options.picks[i])
            if tab_error != ok { ret (zero, tab_error) }
            tabbed[i] = tab
            i += 1usize
        }
        let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
        if shortcuts_error != ok { ret (zero, TooLarge) }
        var bound = 0usize
        if options.current > 0usize && options.current < options.tabs.len {
            shortcuts[bound] = widget.Shortcut { key: 37u32, modifiers: zero, action: options.picks[options.current - 1usize] }
            bound += 1usize
        }
        if options.current + 1usize < options.tabs.len {
            shortcuts[bound] = widget.Shortcut { key: 39u32, modifiers: zero, action: options.picks[options.current + 1usize] }
            bound += 1usize
        }
        let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
        if row_error != ok { ret (zero, TooLarge) }
        row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), tabbed[0usize..options.tabs.len])
        var strip: widget.Semantics = zero
        strip.role = 20u8
        strip.label = title
        strip.column_count = u32(options.tabs.len)
        let (listed, listed_error) = mem.alloc[widget.Node](a, 1usize)
        if listed_error != ok { ret (zero, TooLarge) }
        listed[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..bound], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), row[0usize..1usize])
        head[used] = widget.semantics(0u64, strip, style.defaults(), listed[0usize..1usize])
    } else {
        var caption = control.text_options()
        caption.role = .LabelMedium
        caption.wrap = .None
        let (title_node, title_error) = control.colored_text(a, 0u64, title, t, caption, ink)
        if title_error != ok { ret (zero, title_error) }
        head[used] = title_node
    }
    used += 1usize
    head[used] = widget.spacer(0u64, 1.0)
    used += 1usize
    if floating && mem.address_of(options.dock) != 0usize {
        let (docker, docker_error) = control.glyph_button(a, key + 3u64, t, .DockLeft, "Dock panel", options.dock, 32.0, t.tokens.sizes.icon_sm)
        if docker_error != ok { ret (zero, docker_error) }
        head[used] = docker
        used += 1usize
    }
    if mem.address_of(options.maximise) != 0usize {
        var kind: control.GlyphKind = .Maximize
        var said: str = "Maximise panel"
        if options.maximised {
            kind = .ChevronDown
            said = "Restore panel"
        }
        let (bigger, bigger_error) = control.glyph_button(a, key + 2u64, t, kind, said, options.maximise, 32.0, t.tokens.sizes.icon_sm)
        if bigger_error != ok { ret (zero, bigger_error) }
        head[used] = bigger
        used += 1usize
    }
    let (named, named_error) = mem.alloc[u8](a, title.len + 12usize)
    if named_error != ok { ret (zero, TooLarge) }
    var n = control.copy_text(named, "Close ")
    n += control.copy_text(named[n..named.len], title)
    n += control.copy_text(named[n..named.len], " panel")
    let (closer, closer_error) = control.glyph_button(a, key + 1u64, t, .Cross, named[0usize..n], close, 32.0, t.tokens.sizes.icon_sm)
    if closer_error != ok { ret (zero, closer_error) }
    head[used] = closer
    used += 1usize
    var bar = style.defaults()
    bar.width = style.Length { Percent: 100.0 }
    bar.height = style.Length { Px: h }
    bar.padding = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 4.0 }, bottom: style.Length { Px: 0.0 } }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 6usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[3usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, bar, head[0usize..used])
    parts[0usize] = parts[3usize]
    if !floating {
        // Keep the line layer in the tree at rest so gaining focus does not
        // replace the header subtree (and retire the focused child).
        var line = style.defaults()
        line.width = style.Length { Percent: 100.0 }
        line.height = style.Length { Px: 2.0 }
        if focused { line.background = paint.Brush { Solid: style.color(t.tokens, .Primary) } }
        parts[4usize] = widget.positioned(0u64, 0.0, 0.0, line, zero)
        var header = style.defaults()
        header.width = style.Length { Percent: 100.0 }
        header.height = style.Length { Px: h }
        parts[0usize] = widget.stack(0u64, header, parts[3usize..5usize])
    }
    if mem.address_of(options.maximise) != 0usize {
        let (header_child, header_child_error) = mem.alloc[widget.Node](a, 1usize)
        if header_child_error != ok { ret (zero, TooLarge) }
        header_child[0usize] = parts[0usize]
        let gesture = widget.GestureAction { ctx: mem.cast[*void](options.maximise), invoke: dock_header_gesture }
        parts[0usize] = widget.region(0u64, widget.Region { gesture: gesture, gestures: 1u8, enabled: true, focusable: false }, style.defaults(), header_child[0usize..1usize])
    }
    var count = 1usize
    if options.busy {
        // A 40% `primary` segment sweeps across the clear track; reduced motion
        // keeps it centred and pulses its opacity.
        let (segments, segments_error) = mem.alloc[widget.Node](a, 3usize)
        if segments_error != ok { ret (zero, TooLarge) }
        let turn = animation.cycle(t.runtime, time.seconds(2i64))
        var before = 3.0 * turn
        var after = 3.0 * (1.0 - turn)
        var alpha: f32 = 1.0
        if t.tokens.motion.reduced {
            before = 1.5
            after = 1.5
            alpha = 0.38 + 0.62 * animation.triangle(turn)
        }
        var busy_bar = style.defaults()
        busy_bar.width = style.Length { Flex: 2.0 }
        busy_bar.height = style.Length { Px: 2.0 }
        busy_bar.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
        busy_bar.opacity = alpha
        segments[0usize] = widget.spacer(0u64, before)
        segments[1usize] = widget.box(key + 64u64, busy_bar, zero)
        segments[2usize] = widget.spacer(0u64, after)
        var track = style.defaults()
        track.height = style.Length { Px: 2.0 }
        parts[count] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, track, segments[0usize..3usize])
        count += 1usize
    }
    parts[count] = content
    if options.empty.len != 0usize {
        var said = control.text_options()
        said.role = .BodySmall
        let (sentence, sentence_error) = control.colored_text(a, 0u64, options.empty, t, said, muted)
        if sentence_error != ok { ret (zero, sentence_error) }
        parts[5usize] = sentence
        parts[count] = widget.padded(0u64, 12.0, 8.0, 12.0, 0.0, style.defaults(), parts[5usize..6usize])
    }
    count += 1usize
    var panel = style.defaults()
    panel.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    panel.width = style.Length { Percent: 100.0 }
    panel.height = style.Length { Percent: 100.0 }
    panel.min_width = style.Length { Px: 160.0 }
    panel.overflow = .Clip
    if floating {
        panel.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainer) }
        panel.radius = t.tokens.radii.md
        panel.min_width = style.Length { Px: 240.0 }
        panel.min_height = style.Length { Px: 160.0 }
        panel.shadow = style.Shadow { offset: geometry.Point { x: 0.0, y: 6.0 }, color: paint.rgba(0.0, 0.0, 0.0, t.tokens.elevation[3usize]) }
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, panel, parts[0usize..count])
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 1usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    var shortcut_count = 0usize
    if mem.address_of(options.maximise) != 0usize {
        var held: input.Modifiers = zero
        held.control = true
        shortcuts[0usize] = widget.Shortcut { key: 77u32, modifiers: held, action: *options.maximise }
        shortcut_count = 1usize
    }
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..shortcut_count], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), column[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = accessibility.ROLE_REGION
    sem.label = title
    if options.busy { sem.states = accessibility.STATE_BUSY }
    ret (widget.semantics(key, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// v2 (D967, docs/ux/components/DockPanel, stacked): several tools in one side
// slot on `surface-container-low`, each under a 32 header (keyed
// `key + 1 + 2 * index`, 12 at the start) of a `chevron-down` (`chevron-right`
// collapsed) 18 in `on-surface-variant` and the title in `label-medium`
// `on-surface-variant`, under the `on-surface` state layer, firing its toggle
// and controlling its body (`key + 2 + 2 * index`); the open bodies share the
// height left, 1px `outline-variant` lines between sections. A group in the tree
// named `label`; each open body is a region labelled by its header.
fn dock_stack(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, titles: []const str, contents: []const widget.Node, open: []const bool, toggles: []const widget.Submit) -> (widget.Node, err) {
    let n = titles.len
    if contents.len != n || open.len != n || toggles.len != n { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[widget.Node](a, 3usize * n)
    if items_error != ok { ret (zero, TooLarge) }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var count = 0usize
    var i = 0usize
    while i < n {
        let header_key = key + 1u64 + 2u64 * u64(i)
        if i > 0usize {
            var line = style.defaults()
            line.height = style.Length { Px: t.tokens.sizes.divider }
            line.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
            items[count] = widget.box(0u64, line, zero)
            count += 1usize
        }
        let state = control.control_state(t, header_key, true, false)
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), style.color(t.tokens, .OnSurface), control.state_opacity(t, state))
        look.foreground = muted
        look.border_width = 0.0
        look.opacity = 1.0
        look.radius = 0.0
        look.custom_padding = true
        look.padding = 4.0
        look.padding_start = 12.0
        look.padding_y = (t.tokens.sizes.control_sm - t.tokens.sizes.icon_sm) * 0.5
        look.min_height = t.tokens.sizes.control_sm
        look.min_width = 1.0
        var kind: control.GlyphKind = .ChevronRight
        if open[i] { kind = .ChevronDown }
        let (bits, bits_error) = mem.alloc[widget.Node](a, 2usize)
        if bits_error != ok { ret (zero, TooLarge) }
        let (chevron, chevron_error) = control.icon_square(a, muted, kind, t.tokens.sizes.icon_sm)
        if chevron_error != ok { ret (zero, chevron_error) }
        bits[0usize] = chevron
        var caption = control.text_options()
        caption.role = .LabelMedium
        caption.wrap = .None
        let (words, words_error) = control.colored_text(a, 0u64, titles[i], t, caption, muted)
        if words_error != ok { ret (zero, words_error) }
        bits[1usize] = words
        let row = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), bits[0usize..2usize])
        var states = 0u32
        var actions = accessibility.ACTION_EXPAND
        if open[i] {
            states = accessibility.STATE_EXPANDED
            actions = accessibility.ACTION_COLLAPSE
        }
        let (header, header_error) = control.pressable_states_fill(a, header_key, t, 3u8, titles[i], look, true, false, states, actions, header_key + 1u64, &toggles[i], true, row)
        if header_error != ok { ret (zero, header_error) }
        items[count] = header
        count += 1usize
        if open[i] {
            let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
            if body_error != ok { ret (zero, TooLarge) }
            body[0usize] = contents[i]
            var sem: widget.Semantics = zero
            sem.role = accessibility.ROLE_REGION
            sem.labelled_by = header_key
            var share = style.defaults()
            share.height = style.Length { Flex: 1.0 }
            share.overflow = .Clip
            items[count] = widget.semantics(header_key + 1u64, sem, share, body[0usize..1usize])
            count += 1usize
        }
        i += 1usize
    }
    var panel = style.defaults()
    panel.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    panel.width = style.Length { Percent: 100.0 }
    panel.height = style.Length { Percent: 100.0 }
    panel.overflow = .Clip
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, panel, items[0usize..count])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), column[0usize..1usize]), ok)
}

// The sizes of a dock layout's side panels, the caller's value.
type DockSizes = struct { left: f32, right: f32, bottom: f32 }

// One sash's move turned into the whole sizes value: the left sash sizes the
// left panel, the middle's sizes the middle (the right is what remains of
// `extent`, the width), the bottom's sizes the centre (the bottom is what remains
// of `extent`, the height).
type DockMove = struct { side: u8, sizes: DockSizes, extent: f32, handle: f32, change: widget.Change[DockSizes] }

fn dock_move_fire(ctx: *void, moved: f32) -> err {
    let m = mem.cast[*DockMove](ctx)
    var next = m.sizes
    if m.side == 0u8 { next.left = moved }
    if m.side == 1u8 {
        next.right = m.extent - m.sizes.left - moved - 2.0 * m.handle
        if next.right < 0.0 { next.right = 0.0 }
    }
    if m.side == 2u8 {
        next.bottom = m.extent - moved - m.handle
        if next.bottom < 0.0 { next.bottom = 0.0 }
    }
    // (D968) The middle's sash with no left slot's width in `extent`.
    if m.side == 3u8 {
        next.right = m.extent - moved - m.handle
        if next.right < 0.0 { next.right = 0.0 }
    }
    ret widget.fire_change[DockSizes](m.change, next)
}

// A dock layout: `left` and `right` panels beside a middle of `centre` over
// `bottom`, `width` by `height`, the panels sized by `sizes` (the caller's) and
// resized by sashes -- the left panel's (keyed `key + 1`, its content `key + 2`,
// its sash `key + 3`), the middle's (`key + 4`, whose move sizes the right panel
// by what remains) and the bottom's inside the middle (`key + 7`); every move
// reaches `change` with the whole sizes. A group in the tree.
// v2 (D966, docs/ux/components/DockLayout): the sashes are 8 hit strips around a
// 1px `outline-variant` line that turns a 4px `primary` bar on hover and drag,
// each a slider named "Resize left panel", "Resize right panel" or "Resize
// bottom panel"; the sides keep at least 160, the bottom 96 (a 32 header and
// 64), and the centre 320 x 160; the centre stands on `surface`.
// ponytail: fixed left/centre/right/bottom slots; the activity strip, panel
// moving (ghost, dock guide, drop preview, tear-off), collapse, maximise, reset
// and persistence need a panel-to-slot model.
fn dock_layout(a: *mem.Arena, key: widget.Key, t: *const control.Theme, left: widget.Node, centre: widget.Node, right: widget.Node, bottom: widget.Node, sizes: DockSizes, change: widget.Change[DockSizes], width: f32, height: f32) -> (widget.Node, err) {
    var handle: f32 = 8.0
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { handle = 24.0 }
    let side_min: f32 = 160.0
    let bottom_min = t.tokens.sizes.control_sm + 64.0
    let (moves, moves_error) = mem.alloc[DockMove](a, 3usize)
    if moves_error != ok { ret (zero, TooLarge) }
    moves[0usize] = DockMove { side: 0u8, sizes: sizes, extent: width, handle: handle, change: change }
    moves[1usize] = DockMove { side: 1u8, sizes: sizes, extent: width, handle: handle, change: change }
    moves[2usize] = DockMove { side: 2u8, sizes: sizes, extent: height, handle: handle, change: change }
    // The middle: the centre over the bottom panel, the centre's height the rest.
    var middle_height = height - sizes.bottom - handle
    if middle_height < 0.0 { middle_height = 0.0 }
    let (centred, centred_error) = mem.alloc[widget.Node](a, 1usize)
    if centred_error != ok { ret (zero, TooLarge) }
    centred[0usize] = centre
    var centre_style = style.defaults()
    centre_style.width = style.Length { Percent: 100.0 }
    centre_style.height = style.Length { Px: middle_height }
    centre_style.overflow = .Clip
    centre_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (stack, stack_error) = mem.alloc[widget.Node](a, 2usize)
    if stack_error != ok { ret (zero, TooLarge) }
    stack[0usize] = widget.box(0u64, centre_style, centred[0usize..1usize])
    // The bottom panel's sash sits above it: the centre is the resizable pane,
    // its size the centre's height, so a drag reports the bottom by what remains.
    let (bottom_boxed, bottom_boxed_error) = mem.alloc[widget.Node](a, 1usize)
    if bottom_boxed_error != ok { ret (zero, TooLarge) }
    bottom_boxed[0usize] = bottom
    var bottom_style = style.defaults()
    bottom_style.width = style.Length { Percent: 100.0 }
    bottom_style.height = style.Length { Px: sizes.bottom }
    bottom_style.overflow = .Clip
    stack[1usize] = widget.box(0u64, bottom_style, bottom_boxed[0usize..1usize])
    let (middle_pane, middle_pane_error) = control.pane_with_reserve(a, key + 7u64, t, "Resize bottom panel", .Vertical, middle_height, 160.0, height - bottom_min - handle, 0u64, 0.0, widget.Change[f32] { ctx: mem.cast[*void](&moves[2usize]), invoke: dock_move_fire }, stack[0usize], true)
    if middle_pane_error != ok { ret (zero, middle_pane_error) }
    let (middle_parts, middle_parts_error) = mem.alloc[widget.Node](a, 2usize)
    if middle_parts_error != ok { ret (zero, TooLarge) }
    middle_parts[0usize] = middle_pane
    middle_parts[1usize] = stack[1usize]
    var middle_style = style.defaults()
    middle_style.width = style.Length { Percent: 100.0 }
    middle_style.height = style.Length { Px: height }
    let middle = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, middle_style, middle_parts[0usize..2usize])
    // The row: the left panel, the middle (whose sash sizes the right), the right.
    var middle_width = width - sizes.left - sizes.right - 2.0 * handle
    if middle_width < 0.0 { middle_width = 0.0 }
    let (left_pane, left_error) = control.pane_with_reserve(a, key + 1u64, t, "Resize left panel", .Horizontal, sizes.left, side_min, width - sizes.right - 320.0 - 2.0 * handle, 0u64, 0.0, widget.Change[f32] { ctx: mem.cast[*void](&moves[0usize]), invoke: dock_move_fire }, left, true)
    if left_error != ok { ret (zero, left_error) }
    let (middle_sized, middle_sized_error) = control.pane_with_reserve(a, key + 4u64, t, "Resize right panel", .Horizontal, middle_width, 320.0, width - sizes.left - side_min - 2.0 * handle, 0u64, 0.0, widget.Change[f32] { ctx: mem.cast[*void](&moves[1usize]), invoke: dock_move_fire }, middle, true)
    if middle_sized_error != ok { ret (zero, middle_sized_error) }
    let (righted, righted_error) = mem.alloc[widget.Node](a, 1usize)
    if righted_error != ok { ret (zero, TooLarge) }
    righted[0usize] = right
    // Sized, not a flex share: a panel's 100% would ask for the whole row (D968).
    var right_style = style.defaults()
    right_style.width = style.Length { Px: max_f(width - sizes.left - middle_width - 2.0 * handle, 0.0) }
    right_style.height = style.Length { Percent: 100.0 }
    right_style.overflow = .Clip
    let (row, row_error) = mem.alloc[widget.Node](a, 3usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = left_pane
    row[1usize] = middle_sized
    row[2usize] = widget.box(0u64, right_style, righted[0usize..1usize])
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, control.sized_style(width, height), row[0usize..3usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// ------------------------------------------------- the dock layout's slot model (D968)

// Where a panel stands: a side slot, the bottom slot, floating over the layout,
// or closed.
type DockSlot = enum u8 { Left, Right, Bottom, Floating, Hidden }

// A panel's place in a dock layout, the caller's: its name and activity-strip
// mark, the slot it is in and the slot it docks back to, and, floating, its
// rectangle over the layout.
type DockPlacement = struct { name: str, icon: control.GlyphKind, slot: DockSlot, home: DockSlot, x: f32, y: f32, width: f32, height: f32 }

// The layout's own state, the caller's: the slot sizes, the panel each side slot
// shows (`current[0]` left, `[1]` right, `[2]` bottom), which slots are
// collapsed, and what is maximised (0 nothing, 1 left, 2 right, 3 bottom, 4 the
// centre). A plain value, so the caller can save and restore it.
type DockModel = struct { sizes: DockSizes, current: [3]usize, collapsed: [3]bool, maximised: u8 }

// What a press or a drag in the layout asks of the model.
type DockEventKind = enum u8 { Resize, Pick, Toggle, Close, Maximise, Dock, Move }
type DockEvent = struct { kind: DockEventKind, panel: usize, slot: DockSlot, sizes: DockSizes }

type DockFire = struct { event: DockEvent, change: widget.Change[DockEvent] }

fn dock_fire(ctx: *void) -> err {
    let f = mem.cast[*DockFire](ctx)
    ret widget.fire_change[DockEvent](f.change, f.event)
}

type DockFocus = struct { runtime: *widget.Runtime, backward: bool, centre: bool }

fn dock_focus_fire(ctx: *void) -> err {
    let f = mem.cast[*DockFocus](ctx)
    var roles: [3]u8 = zero
    roles[0usize] = accessibility.ROLE_MAIN
    if !f.centre {
        roles[1usize] = accessibility.ROLE_REGION
        roles[2usize] = accessibility.ROLE_SEPARATOR
    }
    ret widget.focus_semantics(f.runtime, roles[..], f.backward)
}

type DockResize = struct { change: widget.Change[DockEvent] }

fn dock_resize_fire(ctx: *void, sizes: DockSizes) -> err {
    let r = mem.cast[*DockResize](ctx)
    ret widget.fire_change[DockEvent](r.change, DockEvent { kind: .Resize, panel: 0usize, slot: .Left, sizes: sizes })
}

fn slot_index(slot: DockSlot) -> usize {
    if slot == .Right { ret 1usize }
    if slot == .Bottom { ret 2usize }
    ret 0usize
}

fn side_slot(slot: DockSlot) -> bool {
    ret slot == .Left || slot == .Right || slot == .Bottom
}

// The panel a slot shows: its current one while it stands there, else the first
// that does (`placements.len` for none).
fn slot_panel(model: DockModel, placements: []const DockPlacement, slot: DockSlot) -> usize {
    let wanted = model.current[slot_index(slot)]
    if wanted < placements.len && placements[wanted].slot == slot { ret wanted }
    var i = 0usize
    while i < placements.len {
        if placements[i].slot == slot { ret i }
        i += 1usize
    }
    ret placements.len
}

// An event applied to the caller's model and placements: a resize takes the new
// sizes; a pick shows a panel in its slot; a toggle (an activity-strip button)
// collapses the slot showing that panel, or shows it (reopening a closed one in
// its home slot); a close hides a panel; a maximise maximises its slot or
// restores it (panel `placements.len`: the centre); a dock returns a floating
// panel to its home slot; a move puts a panel in `slot` (a side slot becomes its
// home) -- the caller drives moves and tear-offs through this, and sets a
// floating panel's rectangle itself.
fn dock_apply(model: *DockModel, placements: []DockPlacement, e: DockEvent) {
    if e.kind == .Resize {
        model.sizes = e.sizes
        ret
    }
    if e.kind == .Maximise {
        var wanted_slot = 4u8
        if e.panel < placements.len { wanted_slot = u8(slot_index(placements[e.panel].slot)) + 1u8 }
        if model.maximised == wanted_slot {
            model.maximised = 0u8
        } else {
            model.maximised = wanted_slot
        }
        ret
    }
    if e.panel >= placements.len { ret }
    let p = &placements[e.panel]
    if e.kind == .Pick && side_slot(p.slot) { model.current[slot_index(p.slot)] = e.panel }
    if e.kind == .Toggle {
        if side_slot(p.slot) {
            let s = slot_index(p.slot)
            if slot_panel(*model, placements, p.slot) == e.panel && !model.collapsed[s] {
                model.collapsed[s] = true
                ret
            }
        }
        if p.slot == .Hidden { p.slot = p.home }
        if side_slot(p.slot) {
            model.current[slot_index(p.slot)] = e.panel
            model.collapsed[slot_index(p.slot)] = false
        }
    }
    if e.kind == .Close { p.slot = .Hidden }
    if e.kind == .Dock {
        p.slot = p.home
        if side_slot(p.slot) { model.current[slot_index(p.slot)] = e.panel }
    }
    if e.kind == .Move {
        p.slot = e.slot
        if side_slot(e.slot) {
            p.home = e.slot
            model.current[slot_index(e.slot)] = e.panel
            model.collapsed[slot_index(e.slot)] = false
        }
    }
}

// The fire for an event about `panel`.
fn dock_action(a: *mem.Arena, kind: DockEventKind, panel: usize, change: widget.Change[DockEvent]) -> (*widget.Submit, err) {
    let (fires, fires_error) = mem.alloc[DockFire](a, 1usize)
    if fires_error != ok { ret (zero, TooLarge) }
    fires[0usize] = DockFire { event: DockEvent { kind: kind, panel: panel, slot: .Left, sizes: zero }, change: change }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (zero, TooLarge) }
    actions[0usize] = widget.Submit { ctx: mem.cast[*void](&fires[0usize]), invoke: dock_fire }
    ret (&actions[0usize], ok)
}

// The panel a slot shows, as a dock panel keyed `key` (its tabs the slot's
// panels when it holds more than one), or a floating panel.
fn slot_node(a: *mem.Arena, key: widget.Key, t: *const control.Theme, model: DockModel, placements: []const DockPlacement, contents: []const widget.Node, shown: usize, change: widget.Change[DockEvent]) -> (widget.Node, err) {
    let slot = placements[shown].slot
    var options = dock_panel_options()
    let (maximise, maximise_error) = dock_action(a, .Maximise, shown, change)
    if maximise_error != ok { ret (zero, maximise_error) }
    let s = slot_index(slot)
    options.maximised = side_slot(slot) && model.maximised == u8(s) + 1u8
    if slot == .Floating {
        options.floating = true
        let (docking, docking_error) = dock_action(a, .Dock, shown, change)
        if docking_error != ok { ret (zero, docking_error) }
        options.dock = docking
    } else {
        options.maximise = maximise
        var n = 0usize
        var i = 0usize
        while i < placements.len {
            if placements[i].slot == slot { n += 1usize }
            i += 1usize
        }
        if n > 1usize {
            let (names, names_error) = mem.alloc[str](a, n)
            if names_error != ok { ret (zero, TooLarge) }
            let (picks, picks_error) = mem.alloc[widget.Submit](a, n)
            if picks_error != ok { ret (zero, TooLarge) }
            var k = 0usize
            i = 0usize
            while i < placements.len {
                if placements[i].slot == slot {
                    names[k] = placements[i].name
                    let (pick, pick_error) = dock_action(a, .Pick, i, change)
                    if pick_error != ok { ret (zero, pick_error) }
                    picks[k] = *pick
                    if i == shown { options.current = k }
                    k += 1usize
                }
                i += 1usize
            }
            options.tabs = names[0usize..n]
            options.picks = picks[0usize..n]
        }
    }
    let (closing, closing_error) = dock_action(a, .Close, shown, change)
    if closing_error != ok { ret (zero, closing_error) }
    let (made, made_error) = dock_panel_of(a, key, t, placements[shown].name, contents[shown], closing, options)
    ret (made, made_error)
}

// v2 (D968, docs/ux/components/DockLayout): the dock layout over a slot model.
// The activity strip leads, 40 wide on `surface-container`, with a 32 round
// button (keyed `key + 20 + index`, 4 apart and 4 in) for each panel whose home
// is a side slot, the open ones tonal (`secondary-container`); a press toggles
// the panel (collapse its slot, or show it). The left, right and bottom slots
// show their current panel (a dock panel keyed `key + 40`, `key + 56` and
// `key + 72`, tabbed when the slot holds several, its Maximise and Close raising
// events), sized by D966's sashes (160 sides, 96 bottom, 320 x 160 centre); a
// collapsed or empty slot takes no room and no sash. Maximised, the slot's panel
// or the centre fills the area beside the strip. Floating panels (keyed
// `key + 100 + 16 * index`) stand over the layout at their rectangles with a Dock
// button. Every press and drag reaches `change` as a `DockEvent`, which
// `dock_apply` turns into the caller's next model and placements. A group in the
// tree.
// ponytail: moving and tearing off are the caller's (a Move event through
// dock_apply); no drag ghost, dock guide, drop preview or sash double-click reset.
fn dock_layout_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, model: DockModel, placements: []const DockPlacement, contents: []const widget.Node, centre: widget.Node, change: widget.Change[DockEvent], width: f32, height: f32) -> (widget.Node, err) {
    if contents.len != placements.len { ret (zero, TooLarge) }
    let (main_child, main_child_error) = mem.alloc[widget.Node](a, 1usize)
    if main_child_error != ok { ret (zero, TooLarge) }
    main_child[0usize] = centre
    var main_sem: widget.Semantics = zero
    main_sem.role = accessibility.ROLE_MAIN
    let main = widget.semantics(key + 8u64, main_sem, style.defaults(), main_child[0usize..1usize])
    var handle: f32 = 8.0
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { handle = 24.0 }
    // The activity strip.
    let (buttons, buttons_error) = mem.alloc[widget.Node](a, placements.len + 1usize)
    if buttons_error != ok { ret (zero, TooLarge) }
    var strip_count = 0usize
    var i = 0usize
    while i < placements.len {
        let home = placements[i].home
        if home == .Left || home == .Right {
            let s = slot_index(placements[i].slot)
            let open = (placements[i].slot == .Left || placements[i].slot == .Right) && !model.collapsed[s] && slot_panel(model, placements, placements[i].slot) == i
            let (toggle, toggle_error) = dock_action(a, .Toggle, i, change)
            if toggle_error != ok { ret (zero, toggle_error) }
            let (button, button_error) = control.glyph_toggle(a, key + 20u64 + u64(i), t, placements[i].icon, placements[i].name, toggle, t.tokens.sizes.control_sm, t.tokens.sizes.icon_sm, open)
            if button_error != ok { ret (zero, button_error) }
            buttons[strip_count] = button
            strip_count += 1usize
        }
        i += 1usize
    }
    var strip_w: f32 = 0.0
    if strip_count > 0usize { strip_w = t.tokens.sizes.control_md }
    let area_w = width - strip_w
    // The side slots.
    let shown_left = slot_panel(model, placements, .Left)
    let shown_right = slot_panel(model, placements, .Right)
    let shown_bottom = slot_panel(model, placements, .Bottom)
    let has_left = shown_left < placements.len && !model.collapsed[0usize]
    let has_right = shown_right < placements.len && !model.collapsed[1usize]
    let has_bottom = shown_bottom < placements.len && !model.collapsed[2usize]
    let (resizes, resizes_error) = mem.alloc[DockResize](a, 1usize)
    if resizes_error != ok { ret (zero, TooLarge) }
    resizes[0usize] = DockResize { change: change }
    let sized = widget.Change[DockSizes] { ctx: mem.cast[*void](&resizes[0usize]), invoke: dock_resize_fire }
    var body: widget.Node = zero
    var full = style.defaults()
    full.width = style.Length { Px: area_w }
    full.height = style.Length { Px: height }
    full.overflow = .Clip
    let (single, single_error) = mem.alloc[widget.Node](a, 1usize)
    if single_error != ok { ret (zero, TooLarge) }
    if model.maximised != 0u8 {
        // The maximised slot's panel, or the centre, alone.
        single[0usize] = main
        full.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
        var chosen = placements.len
        if model.maximised == 1u8 { chosen = shown_left }
        if model.maximised == 2u8 { chosen = shown_right }
        if model.maximised == 3u8 { chosen = shown_bottom }
        if chosen < placements.len {
            let (panel_node, panel_error) = slot_node(a, key + 40u64 + 16u64 * u64(model.maximised - 1u8), t, model, placements, contents, chosen, change)
            if panel_error != ok { ret (zero, panel_error) }
            single[0usize] = panel_node
        }
        body = widget.box(0u64, full, single[0usize..1usize])
    } else {
        var left_w: f32 = 0.0
        if has_left { left_w = model.sizes.left + handle }
        var right_w: f32 = 0.0
        if has_right { right_w = model.sizes.right + handle }
        let middle_w = max_f(area_w - left_w - right_w, 0.0)
        // The middle: the centre over the bottom slot.
        var middle_height = height
        if has_bottom { middle_height = max_f(height - model.sizes.bottom - handle, 0.0) }
        let (centred, centred_error) = mem.alloc[widget.Node](a, 1usize)
        if centred_error != ok { ret (zero, TooLarge) }
        centred[0usize] = main
        var centre_style = style.defaults()
        centre_style.width = style.Length { Percent: 100.0 }
        centre_style.height = style.Length { Px: middle_height }
        centre_style.overflow = .Clip
        centre_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
        let centre_box = widget.box(0u64, centre_style, centred[0usize..1usize])
        var middle = centre_box
        if has_bottom {
            let (bottom_node, bottom_error) = slot_node(a, key + 72u64, t, model, placements, contents, shown_bottom, change)
            if bottom_error != ok { ret (zero, bottom_error) }
            let (lower, lower_error) = mem.alloc[widget.Node](a, 2usize)
            if lower_error != ok { ret (zero, TooLarge) }
            lower[0usize] = bottom_node
            var bottom_style = style.defaults()
            bottom_style.width = style.Length { Percent: 100.0 }
            bottom_style.height = style.Length { Px: model.sizes.bottom }
            bottom_style.overflow = .Clip
            lower[1usize] = widget.box(0u64, bottom_style, lower[0usize..1usize])
            let (moves, moves_error) = mem.alloc[DockMove](a, 1usize)
            if moves_error != ok { ret (zero, TooLarge) }
            moves[0usize] = DockMove { side: 2u8, sizes: model.sizes, extent: height, handle: handle, change: sized }
            let (pane, pane_error) = control.pane_with_reserve(a, key + 7u64, t, "Resize bottom panel", .Vertical, middle_height, 160.0, height - t.tokens.sizes.control_sm - 64.0 - handle, 0u64, 0.0, widget.Change[f32] { ctx: mem.cast[*void](&moves[0usize]), invoke: dock_move_fire }, centre_box, true)
            if pane_error != ok { ret (zero, pane_error) }
            let (stacked, stacked_error) = mem.alloc[widget.Node](a, 2usize)
            if stacked_error != ok { ret (zero, TooLarge) }
            stacked[0usize] = pane
            stacked[1usize] = lower[1usize]
            var middle_style = style.defaults()
            middle_style.width = style.Length { Percent: 100.0 }
            middle_style.height = style.Length { Px: height }
            middle = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, middle_style, stacked[0usize..2usize])
        }
        let (row, row_error) = mem.alloc[widget.Node](a, 3usize)
        if row_error != ok { ret (zero, TooLarge) }
        var row_count = 0usize
        if has_left {
            let (left_node, left_node_error) = slot_node(a, key + 40u64, t, model, placements, contents, shown_left, change)
            if left_node_error != ok { ret (zero, left_node_error) }
            let (moves, moves_error) = mem.alloc[DockMove](a, 1usize)
            if moves_error != ok { ret (zero, TooLarge) }
            moves[0usize] = DockMove { side: 0u8, sizes: model.sizes, extent: area_w, handle: handle, change: sized }
            let (pane, pane_error) = control.pane_with_reserve(a, key + 1u64, t, "Resize left panel", .Horizontal, model.sizes.left, 160.0, area_w - right_w - 320.0 - handle, 0u64, 0.0, widget.Change[f32] { ctx: mem.cast[*void](&moves[0usize]), invoke: dock_move_fire }, left_node, true)
            if pane_error != ok { ret (zero, pane_error) }
            row[row_count] = pane
            row_count += 1usize
        }
        if has_right {
            // The middle's sash sizes the middle; the right is what remains.
            let (moves, moves_error) = mem.alloc[DockMove](a, 1usize)
            if moves_error != ok { ret (zero, TooLarge) }
            moves[0usize] = DockMove { side: 3u8, sizes: model.sizes, extent: area_w - left_w, handle: handle, change: sized }
            let (pane, pane_error) = control.pane_with_reserve(a, key + 4u64, t, "Resize right panel", .Horizontal, middle_w, 320.0, area_w - left_w - 160.0 - handle, 0u64, 0.0, widget.Change[f32] { ctx: mem.cast[*void](&moves[0usize]), invoke: dock_move_fire }, middle, true)
            if pane_error != ok { ret (zero, pane_error) }
            row[row_count] = pane
            row_count += 1usize
            let (right_node, right_node_error) = slot_node(a, key + 56u64, t, model, placements, contents, shown_right, change)
            if right_node_error != ok { ret (zero, right_node_error) }
            let (righted, righted_error) = mem.alloc[widget.Node](a, 1usize)
            if righted_error != ok { ret (zero, TooLarge) }
            righted[0usize] = right_node
            // Sized, not a flex share: a panel's 100% would ask for the whole row.
            var right_style = style.defaults()
            right_style.width = style.Length { Px: max_f(area_w - left_w - middle_w - handle, 0.0) }
            right_style.height = style.Length { Percent: 100.0 }
            right_style.overflow = .Clip
            row[row_count] = widget.box(0u64, right_style, righted[0usize..1usize])
            row_count += 1usize
        } else {
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (zero, TooLarge) }
            held[0usize] = middle
            var rest = style.defaults()
            rest.width = style.Length { Px: max_f(area_w - left_w, 0.0) }
            rest.height = style.Length { Percent: 100.0 }
            row[row_count] = widget.box(0u64, rest, held[0usize..1usize])
            row_count += 1usize
        }
        body = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, full, row[0usize..row_count])
    }
    // The strip beside the body, and the floating panels over both.
    let (outer, outer_error) = mem.alloc[widget.Node](a, 2usize)
    if outer_error != ok { ret (zero, TooLarge) }
    var outer_count = 0usize
    if strip_count > 0usize {
        var strip = style.defaults()
        strip.width = style.Length { Px: strip_w }
        strip.height = style.Length { Px: height }
        strip.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainer) }
        let edge = style.Length { Px: 4.0 }
        strip.padding = style.EdgeLengths { left: edge, top: edge, right: edge, bottom: edge }
        outer[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, strip, buttons[0usize..strip_count])
        outer_count = 1usize
    }
    outer[outer_count] = body
    outer_count += 1usize
    let (layers, layers_error) = mem.alloc[widget.Node](a, placements.len + 1usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, control.sized_style(width, height), outer[0usize..outer_count])
    var layer_count = 1usize
    i = 0usize
    while i < placements.len {
        let p = placements[i]
        if p.slot == .Floating {
            let (floated, floated_error) = slot_node(a, key + 100u64 + 16u64 * u64(i), t, model, placements, contents, i, change)
            if floated_error != ok { ret (zero, floated_error) }
            let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
            if held_error != ok { ret (zero, TooLarge) }
            held[0usize] = floated
            layers[layer_count] = widget.positioned(0u64, p.x, p.y, control.sized_style(p.width, p.height), held[0usize..1usize])
            layer_count += 1usize
        }
        i += 1usize
    }
    let (stacked, stacked_error) = mem.alloc[widget.Node](a, 1usize)
    if stacked_error != ok { ret (zero, TooLarge) }
    stacked[0usize] = layers[0usize]
    if layer_count > 1usize { stacked[0usize] = widget.stack(0u64, control.sized_style(width, height), layers[0usize..layer_count]) }
    let (focuses, focuses_error) = mem.alloc[DockFocus](a, 3usize)
    if focuses_error != ok { ret (zero, TooLarge) }
    focuses[0usize] = DockFocus { runtime: t.runtime, backward: false, centre: false }
    focuses[1usize] = DockFocus { runtime: t.runtime, backward: true, centre: false }
    focuses[2usize] = DockFocus { runtime: t.runtime, backward: false, centre: true }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 65475u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&focuses[0usize]), invoke: dock_focus_fire } }
    var shifted: input.Modifiers = zero
    shifted.shift = true
    shortcuts[1usize] = widget.Shortcut { key: 65475u32, modifiers: shifted, action: widget.Submit { ctx: mem.cast[*void](&focuses[1usize]), invoke: dock_focus_fire } }
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..2usize], default_action: zero, cancel_action: widget.Submit { ctx: mem.cast[*void](&focuses[2usize]), invoke: dock_focus_fire }, keys: zero }, style.defaults(), stacked[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    ret (widget.semantics(key, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

fn max_f(a: f32, b: f32) -> f32 {
    if a > b { ret a }
    ret b
}

// A multi-document workspace: the document tabs (keyed `key + 1`) over the
// current document's view, `width` by `height`, under a scope whose Ctrl+W
// closes the current document and whose Ctrl+PageDown and Ctrl+PageUp pick the
// next and the previous; a group in the tree named `label`.
// v2 (D966, docs/ux/components/MultiDocumentWorkspace): the view stands on
// `surface`; Ctrl+PageDown and Ctrl+PageUp wrap at the ends; with no documents
// the strip gives way to the empty state centred in the view: "No open files" in
// `title-medium` over `body-medium` `on-surface-variant` rows 240 wide, 8 apart,
// naming the shortcuts that open and switch documents, 12 between the blocks.
// ponytail: one editor group; split groups, the location bar, the compact count
// button, most-recently-used Ctrl+Tab, Alt+1..9, Ctrl+Shift+T, the Open recent
// button and restore hooks need a group model the caller does not pass yet.
fn multi_document_workspace(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, documents: []const Document, current: usize, view: widget.Node, pick: widget.Change[usize], close: widget.Change[usize], move: widget.Change[DocumentMove], width: f32, height: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var view_style = style.defaults()
    view_style.width = style.Length { Px: width }
    view_style.height = style.Length { Flex: 1.0 }
    view_style.overflow = .Clip
    view_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (viewed, viewed_error) = mem.alloc[widget.Node](a, 1usize)
    if viewed_error != ok { ret (zero, TooLarge) }
    viewed[0usize] = view
    if documents.len == 0usize {
        let (empty, empty_error) = workspace_empty(a, t, 0u64, zero)
        if empty_error != ok { ret (zero, empty_error) }
        viewed[0usize] = empty
        view_style.height = style.Length { Px: height }
        let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
        if column_error != ok { ret (zero, TooLarge) }
        column[0usize] = widget.aligned(0u64, .Center, .Center, view_style, viewed[0usize..1usize])
        var bare: widget.Semantics = zero
        bare.role = 2u8
        bare.label = label
        ret (widget.semantics(key, bare, style.defaults(), column[0usize..1usize]), ok)
    }
    let (strip, strip_error) = document_tabs(a, key + 1u64, t, label, documents, current, pick, close, move)
    if strip_error != ok { ret (zero, strip_error) }
    parts[0usize] = strip
    parts[1usize] = widget.box(0u64, view_style, viewed[0usize..1usize])
    let (keys, keys_error) = mem.alloc[TabClose](a, 3usize)
    if keys_error != ok { ret (zero, TooLarge) }
    var next = 0usize
    if current + 1usize < documents.len { next = current + 1usize }
    var previous = documents.len - 1usize
    if current > 0usize { previous = current - 1usize }
    keys[0usize] = TabClose { index: current, close: close }
    keys[1usize] = TabClose { index: next, close: pick }
    keys[2usize] = TabClose { index: previous, close: pick }
    var held: input.Modifiers = zero
    held.control = true
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 3usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 87u32, modifiers: held, action: widget.Submit { ctx: mem.cast[*void](&keys[0usize]), invoke: tab_close_fire } }
    shortcuts[1usize] = widget.Shortcut { key: 34u32, modifiers: held, action: widget.Submit { ctx: mem.cast[*void](&keys[1usize]), invoke: tab_close_fire } }
    shortcuts[2usize] = widget.Shortcut { key: 33u32, modifiers: held, action: widget.Submit { ctx: mem.cast[*void](&keys[2usize]), invoke: tab_close_fire } }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(width, height), parts[0usize..2usize])
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(key, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..3usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), column[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// The workspace's empty state (D966): the heading over the shortcut rows; and
// (D969) with `recent`, a small tonal Open recent button (keyed `key`) under them.
fn workspace_empty(a: *mem.Arena, t: *const control.Theme, key: widget.Key, recent: *const widget.Submit) -> (widget.Node, err) {
    let (rows, rows_error) = mem.alloc[widget.Node](a, 3usize)
    if rows_error != ok { ret (zero, TooLarge) }
    var said = control.text_options()
    said.role = .BodyMedium
    said.wrap = .None
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let (one, one_error) = control.colored_text(a, 0u64, "Open a file  Ctrl+O", t, said, muted)
    let (two, two_error) = control.colored_text(a, 0u64, "New file  Ctrl+N", t, said, muted)
    let (three, three_error) = control.colored_text(a, 0u64, "Switch files  Ctrl+Tab", t, said, muted)
    if one_error != ok || two_error != ok || three_error != ok { ret (zero, TooLarge) }
    rows[0usize] = one
    rows[1usize] = two
    rows[2usize] = three
    var caption = control.text_options()
    caption.role = .TitleMedium
    caption.wrap = .None
    let (heading, heading_error) = control.colored_text(a, 0u64, "No open files", t, caption, style.color(t.tokens, .OnSurface))
    if heading_error != ok { ret (zero, heading_error) }
    let (blocks, blocks_error) = mem.alloc[widget.Node](a, 3usize)
    if blocks_error != ok { ret (zero, TooLarge) }
    blocks[0usize] = heading
    var list = style.defaults()
    list.width = style.Length { Px: 240.0 }
    blocks[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, list, rows[0usize..3usize])
    var count = 2usize
    if mem.address_of(recent) != 0usize {
        var tonal = control.button_options()
        tonal.variant = .Tonal
        let (button, button_error) = control.button(a, key, t, "Open recent", recent, tonal)
        if button_error != ok { ret (zero, button_error) }
        blocks[2usize] = button
        count = 3usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 12.0 }, style.defaults(), blocks[0usize..count]), ok)
}

// ------------------------------------------------- editor groups (D969)

// An editor group, the caller's: its documents and current one, its documents
// most recently used first (for Ctrl+Tab), and the location bar's crumbs (none:
// no bar).
type EditorGroup = struct { documents: []const Document, current: usize, recent: []const usize, crumbs: []const str }

// What a press or a key in the workspace asks: pick, close or move a document of
// `group`, split the active group, reopen the last closed document, open a
// recent one, follow crumb `index`, open the document switcher, or open the
// group's actions menu.
type WorkspaceEventKind = enum u8 { Pick, Close, Move, Split, Reopen, OpenRecent, Crumb, Switcher, GroupMenu }
type WorkspaceEvent = struct { kind: WorkspaceEventKind, group: usize, index: usize, move: DocumentMove }

// The workspace's layout: the active group, the axis the groups divide
// (Horizontal: side by side), and the compact form.
type WorkspaceOptions = struct { active: usize, axis: ui_layout.Axis, compact: bool }

fn workspace_options() -> WorkspaceOptions {
    var out: WorkspaceOptions = zero
    out.axis = .Horizontal
    ret out
}

type GroupRelay = struct { kind: WorkspaceEventKind, group: usize, index: usize, change: widget.Change[WorkspaceEvent] }

fn relay_index_fire(ctx: *void, index: usize) -> err {
    let r = mem.cast[*GroupRelay](ctx)
    ret widget.fire_change[WorkspaceEvent](r.change, WorkspaceEvent { kind: r.kind, group: r.group, index: index, move: zero })
}

fn relay_move_fire(ctx: *void, moved: DocumentMove) -> err {
    let r = mem.cast[*GroupRelay](ctx)
    ret widget.fire_change[WorkspaceEvent](r.change, WorkspaceEvent { kind: .Move, group: r.group, index: moved.from, move: moved })
}

fn relay_fire(ctx: *void) -> err {
    let r = mem.cast[*GroupRelay](ctx)
    ret widget.fire_change[WorkspaceEvent](r.change, WorkspaceEvent { kind: r.kind, group: r.group, index: r.index, move: zero })
}

fn relay(a: *mem.Arena, kind: WorkspaceEventKind, group: usize, index: usize, change: widget.Change[WorkspaceEvent]) -> (*GroupRelay, err) {
    let (relays, relays_error) = mem.alloc[GroupRelay](a, 1usize)
    if relays_error != ok { ret (zero, TooLarge) }
    relays[0usize] = GroupRelay { kind: kind, group: group, index: index, change: change }
    ret (&relays[0usize], ok)
}

fn relay_submit(a: *mem.Arena, kind: WorkspaceEventKind, group: usize, index: usize, change: widget.Change[WorkspaceEvent]) -> (*widget.Submit, err) {
    let (r, r_error) = relay(a, kind, group, index, change)
    if r_error != ok { ret (zero, r_error) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (zero, TooLarge) }
    actions[0usize] = widget.Submit { ctx: mem.cast[*void](r), invoke: relay_fire }
    ret (&actions[0usize], ok)
}

// A location bar (D969): 24 tall, the crumbs 24 tall with 4 at each side in
// `body-small` `on-surface-variant`, the last `label-medium` `on-surface`,
// `chevron-right` 12 marks between; a crumb press is a Crumb event. Keyed
// `key + index`.
fn location_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, crumbs: []const str, group: usize, change: widget.Change[WorkspaceEvent]) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 2usize * crumbs.len)
    if items_error != ok { ret (zero, TooLarge) }
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    var count = 0usize
    var i = 0usize
    while i < crumbs.len {
        if i > 0usize {
            let (mark, mark_error) = control.icon_square(a, muted, .ChevronRight, 12.0)
            if mark_error != ok { ret (zero, mark_error) }
            items[count] = mark
            count += 1usize
        }
        let last = i + 1usize == crumbs.len
        var ink = muted
        var caption = control.text_options()
        caption.role = .BodySmall
        caption.wrap = .None
        if last {
            ink = style.color(t.tokens, .OnSurface)
            caption.role = .LabelMedium
        }
        let (words, words_error) = control.colored_text(a, 0u64, crumbs[i], t, caption, ink)
        if words_error != ok { ret (zero, words_error) }
        let (go, go_error) = relay_submit(a, .Crumb, group, i, change)
        if go_error != ok { ret (zero, go_error) }
        let state = control.control_state(t, key + u64(i), true, false)
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), style.color(t.tokens, .OnSurface), control.state_opacity(t, state))
        look.foreground = ink
        look.border_width = 0.0
        look.opacity = 1.0
        look.radius = t.tokens.radii.xs
        look.custom_padding = true
        look.padding = 4.0
        look.padding_y = 4.0
        look.min_height = 24.0
        look.min_width = 8.0
        let (crumb, crumb_error) = control.pressable(a, key + u64(i), t, 9u8, crumbs[i], look, true, false, go, words)
        if crumb_error != ok { ret (zero, crumb_error) }
        items[count] = crumb
        count += 1usize
        i += 1usize
    }
    var bar = style.defaults()
    bar.height = style.Length { Px: 24.0 }
    bar.padding = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 8.0 }, bottom: style.Length { Px: 0.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, bar, items[0usize..count]), ok)
}

// v2 (D969, docs/ux/components/MultiDocumentWorkspace): the workspace over the
// caller's editor groups, `width` by `height`, divided along the options' axis by
// 1px `outline-variant` lines. A group (its parts keyed from `key + 1 + 200 *
// group`; its tabs from `+ 2`) is its document tabs (marked: the active group's current tab over the
// 2px `primary` line), a `more-horiz` 32 button at the strip's end for its
// actions menu, the location bar under them while it has crumbs, and its view on
// `surface`. The active group's scope holds the keys: Ctrl+W closes, Ctrl+PageDown
// and Ctrl+PageUp pick the next and previous (wrapping), Ctrl+Tab the most
// recently used before the current and Ctrl+Shift+Tab the least, Alt+1..9 the
// document at that place, Ctrl+Shift+T reopens and Ctrl+\ splits. With no
// documents in any group, the empty state stands centred with the tonal Open
// recent button (`key + 900`). Compact, the active group's current document
// stands alone under a 56 app bar of its title in `title-large` and a 32
// outlined `radius-sm` count button (`key + 901`, 48 target) opening the
// switcher. Every press and key is a `WorkspaceEvent` for the caller to apply.
// A group in the tree named `label`, each group a group named by its current
// document.
// ponytail: groups share the axis equally (no group sashes, no 2 x 2 grid, no
// drag between groups); the switcher itself is the caller's (window_switcher);
// no restore hooks beyond the caller's own model; macOS/Web key maps not done.
fn multi_document_workspace_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, groups: []const EditorGroup, views: []const widget.Node, options: WorkspaceOptions, change: widget.Change[WorkspaceEvent], width: f32, height: f32) -> (widget.Node, err) {
    if views.len != groups.len { ret (zero, TooLarge) }
    var total = 0usize
    var g = 0usize
    while g < groups.len {
        total += groups[g].documents.len
        g += 1usize
    }
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    let (single, single_error) = mem.alloc[widget.Node](a, 2usize)
    if single_error != ok { ret (zero, TooLarge) }
    var ground = control.sized_style(width, height)
    ground.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    ground.overflow = .Clip
    if total == 0usize {
        let (recent, recent_error) = relay_submit(a, .OpenRecent, 0usize, 0usize, change)
        if recent_error != ok { ret (zero, recent_error) }
        let (empty, empty_error) = workspace_empty(a, t, key + 900u64, recent)
        if empty_error != ok { ret (zero, empty_error) }
        single[0usize] = empty
        single[1usize] = widget.aligned(0u64, .Center, .Center, ground, single[0usize..1usize])
        ret (widget.semantics(key, sem, style.defaults(), single[1usize..2usize]), ok)
    }
    var active = options.active
    if active >= groups.len { active = 0usize }
    if options.compact {
        let group = groups[active]
        var title: str = ""
        if group.current < group.documents.len { title = group.documents[group.current].title }
        let (bar_parts, bar_parts_error) = mem.alloc[widget.Node](a, 4usize)
        if bar_parts_error != ok { ret (zero, TooLarge) }
        var caption = control.text_options()
        caption.role = .TitleLarge
        caption.wrap = .None
        let (heading, heading_error) = control.colored_text(a, 0u64, title, t, caption, style.color(t.tokens, .OnSurface))
        if heading_error != ok { ret (zero, heading_error) }
        bar_parts[0usize] = heading
        bar_parts[1usize] = widget.spacer(0u64, 1.0)
        let (counted, counted_error) = mem.alloc[u8](a, 24usize)
        if counted_error != ok { ret (zero, TooLarge) }
        let n = control.write_i64(counted, i64(total))
        var small = control.text_options()
        small.role = .LabelMedium
        small.wrap = .None
        let (number, number_error) = control.colored_text(a, 0u64, counted[0usize..n], t, small, style.color(t.tokens, .OnSurface))
        if number_error != ok { ret (zero, number_error) }
        let (switcher, switcher_error) = relay_submit(a, .Switcher, active, 0usize, change)
        if switcher_error != ok { ret (zero, switcher_error) }
        let state = control.control_state(t, key + 901u64, true, false)
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = style.layer(paint.rgba(0.0, 0.0, 0.0, 0.0), style.color(t.tokens, .OnSurface), control.state_opacity(t, state))
        look.foreground = style.color(t.tokens, .OnSurface)
        look.border = style.color(t.tokens, .Outline)
        look.border_width = 1.0
        look.opacity = 1.0
        look.radius = t.tokens.radii.sm
        look.custom_padding = true
        look.padding = 8.0
        look.padding_y = 8.0
        look.min_width = 32.0
        look.min_height = 32.0
        let (counter, counter_error) = control.pressable(a, key + 901u64, t, 3u8, "Documents", look, true, false, switcher, number)
        if counter_error != ok { ret (zero, counter_error) }
        bar_parts[3usize] = counter
        // The count button's 48 target around its 32 box.
        bar_parts[2usize] = widget.padded(0u64, 8.0, 8.0, 8.0, 8.0, style.defaults(), bar_parts[3usize..4usize])
        var bar = style.defaults()
        bar.width = style.Length { Px: width }
        bar.height = style.Length { Px: 56.0 }
        bar.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 4.0 }, bottom: style.Length { Px: 0.0 } }
        let (column, column_error) = mem.alloc[widget.Node](a, 3usize)
        if column_error != ok { ret (zero, TooLarge) }
        column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, bar, bar_parts[0usize..3usize])
        column[2usize] = views[active]
        var view_style = style.defaults()
        view_style.width = style.Length { Px: width }
        view_style.height = style.Length { Px: max_f(height - 56.0, 0.0) }
        view_style.overflow = .Clip
        column[1usize] = widget.box(0u64, view_style, column[2usize..3usize])
        single[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, ground, column[0usize..2usize])
        ret (widget.semantics(key, sem, style.defaults(), single[0usize..1usize]), ok)
    }
    // The groups along the axis, equal shares between 1px lines.
    let n_groups = groups.len
    let across = options.axis == .Horizontal
    var share_w = width
    var share_h = height
    if across {
        share_w = (width - f32(n_groups - 1usize)) / f32(n_groups)
    } else {
        share_h = (height - f32(n_groups - 1usize)) / f32(n_groups)
    }
    let (cells, cells_error) = mem.alloc[widget.Node](a, 2usize * n_groups)
    if cells_error != ok { ret (zero, TooLarge) }
    var count = 0usize
    g = 0usize
    while g < n_groups {
        let group = groups[g]
        let base = key + 1u64 + 200u64 * u64(g)
        if g > 0usize {
            var line = style.defaults()
            line.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
            if across {
                line.width = style.Length { Px: 1.0 }
                line.height = style.Length { Px: height }
            } else {
                line.height = style.Length { Px: 1.0 }
                line.width = style.Length { Px: width }
            }
            cells[count] = widget.box(0u64, line, zero)
            count += 1usize
        }
        let (picked, picked_error) = relay(a, .Pick, g, 0usize, change)
        let (closed, closed_error) = relay(a, .Close, g, 0usize, change)
        let (moved, moved_error) = relay(a, .Move, g, 0usize, change)
        if picked_error != ok || closed_error != ok || moved_error != ok { ret (zero, TooLarge) }
        let pick = widget.Change[usize] { ctx: mem.cast[*void](picked), invoke: relay_index_fire }
        let close = widget.Change[usize] { ctx: mem.cast[*void](closed), invoke: relay_index_fire }
        let move = widget.Change[DocumentMove] { ctx: mem.cast[*void](moved), invoke: relay_move_fire }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
        if parts_error != ok { ret (zero, TooLarge) }
        let (strip_parts, strip_parts_error) = mem.alloc[widget.Node](a, 3usize)
        if strip_parts_error != ok { ret (zero, TooLarge) }
        let (strip, strip_error) = document_tabs_marked(a, base + 1u64, t, label, group.documents, group.current, pick, close, move, true, g == active)
        if strip_error != ok { ret (zero, strip_error) }
        strip_parts[0usize] = strip
        strip_parts[1usize] = widget.spacer(0u64, 1.0)
        let (menu, menu_error) = relay_submit(a, .GroupMenu, g, 0usize, change)
        if menu_error != ok { ret (zero, menu_error) }
        let (more, more_error) = control.glyph_button(a, base + 190u64, t, .MoreHoriz, "Group actions", menu, 32.0, t.tokens.sizes.icon_sm)
        if more_error != ok { ret (zero, more_error) }
        strip_parts[2usize] = more
        var head = style.defaults()
        head.width = style.Length { Px: share_w }
        head.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceVariant) }
        parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, head, strip_parts[0usize..3usize])
        var used = 1usize
        if group.crumbs.len != 0usize {
            let (located, located_error) = location_bar(a, base + 150u64, t, group.crumbs, g, change)
            if located_error != ok { ret (zero, located_error) }
            parts[used] = located
            used += 1usize
        }
        parts[3usize] = views[g]
        var view_style = style.defaults()
        view_style.width = style.Length { Px: share_w }
        view_style.height = style.Length { Flex: 1.0 }
        view_style.overflow = .Clip
        view_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
        parts[used] = widget.box(0u64, view_style, parts[3usize..4usize])
        used += 1usize
        let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
        if framed_error != ok { ret (zero, TooLarge) }
        framed[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, control.sized_style(share_w, share_h), parts[0usize..used])
        // The active group's keys.
        var held = framed[0usize]
        if g == active && group.documents.len > 0usize {
            let docs = group.documents.len
            let (keys, keys_error) = mem.alloc[widget.Shortcut](a, 16usize)
            if keys_error != ok { ret (zero, TooLarge) }
            var bound = 0usize
            var ctrl: input.Modifiers = zero
            ctrl.control = true
            var ctrl_shift = ctrl
            ctrl_shift.shift = true
            var alt: input.Modifiers = zero
            alt.alt = true
            var next = 0usize
            if group.current + 1usize < docs { next = group.current + 1usize }
            var previous = docs - 1usize
            if group.current > 0usize && group.current < docs { previous = group.current - 1usize }
            let (closing, closing_error) = relay_submit(a, .Close, g, group.current, change)
            let (forward, forward_error) = relay_submit(a, .Pick, g, next, change)
            let (backward, backward_error) = relay_submit(a, .Pick, g, previous, change)
            let (reopen, reopen_error) = relay_submit(a, .Reopen, g, 0usize, change)
            let (split, split_error) = relay_submit(a, .Split, g, 0usize, change)
            if closing_error != ok || forward_error != ok || backward_error != ok || reopen_error != ok || split_error != ok { ret (zero, TooLarge) }
            keys[0usize] = widget.Shortcut { key: 87u32, modifiers: ctrl, action: *closing }
            keys[1usize] = widget.Shortcut { key: 34u32, modifiers: ctrl, action: *forward }
            keys[2usize] = widget.Shortcut { key: 33u32, modifiers: ctrl, action: *backward }
            keys[3usize] = widget.Shortcut { key: 84u32, modifiers: ctrl_shift, action: *reopen }
            keys[4usize] = widget.Shortcut { key: 220u32, modifiers: ctrl, action: *split }
            bound = 5usize
            if group.recent.len > 1usize {
                let (mru, mru_error) = relay_submit(a, .Pick, g, group.recent[1usize], change)
                let (lru, lru_error) = relay_submit(a, .Pick, g, group.recent[group.recent.len - 1usize], change)
                if mru_error != ok || lru_error != ok { ret (zero, TooLarge) }
                keys[bound] = widget.Shortcut { key: 9u32, modifiers: ctrl, action: *mru }
                keys[bound + 1usize] = widget.Shortcut { key: 9u32, modifiers: ctrl_shift, action: *lru }
                bound += 2usize
            }
            var place = 0usize
            while place < docs && place < 9usize {
                let (jump, jump_error) = relay_submit(a, .Pick, g, place, change)
                if jump_error != ok { ret (zero, jump_error) }
                keys[bound] = widget.Shortcut { key: 49u32 + u32(place), modifiers: alt, action: *jump }
                bound += 1usize
                place += 1usize
            }
            // A scope holds at most 8 shortcuts: nest one per 8.
            let (wraps, wraps_error) = mem.alloc[widget.Node](a, 3usize)
            if wraps_error != ok { ret (zero, TooLarge) }
            wraps[0usize] = framed[0usize]
            var from = 0usize
            var level = 0usize
            while from < bound {
                var upto = from + 8usize
                if upto > bound { upto = bound }
                wraps[level + 1usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: keys[from..upto], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), wraps[level..level + 1usize])
                level += 1usize
                from = upto
            }
            held = wraps[level]
        }
        let (named, named_error) = mem.alloc[widget.Node](a, 1usize)
        if named_error != ok { ret (zero, TooLarge) }
        named[0usize] = held
        var group_sem: widget.Semantics = zero
        group_sem.role = 2u8
        if group.current < group.documents.len { group_sem.label = group.documents[group.current].title }
        cells[count] = widget.semantics(base, group_sem, style.defaults(), named[0usize..1usize])
        count += 1usize
        g += 1usize
    }
    single[0usize] = widget.flex(0u64, ui_layout.Flex { axis: options.axis, main: .Start, cross: .Start, gap: 0.0 }, ground, cells[0usize..count])
    ret (widget.semantics(key, sem, style.defaults(), single[0usize..1usize]), ok)
}

// ------------------------------------------------- productivity navigation (D853, P3-04)

// A wizard step (D974): its label, a second line ("Optional", or what needs
// fixing) and whether it needs attention.
type WizardStep = struct { label: str, note: str, attention: bool }

// The three wizard forms (D974, docs/ux/components/Wizard).
type WizardForm = enum u8 { Horizontal, Vertical, Compact }

// A wizard's options (D974): its form, whether it stands in a dialog, the last
// step's action ("Create project"; empty: "Finish"), and an optional step-pick
// path. With `pressable_steps`, completed and current steps can be revisited;
// `nonlinear` also makes upcoming steps reachable; `finishing` replaces the
// last action's label with its progress ring and disables competing actions.
// A dirty wizard routes Cancel through `request_discard`; `discard_open` shows
// the standard alert, whose Keep editing and Discard actions stay caller-owned.
type WizardOptions = struct { form: WizardForm, dialog: bool, finish_label: str, pressable_steps: bool, nonlinear: bool, step: widget.Change[usize], finishing: bool, dirty: bool, discard_open: bool, request_discard: widget.Submit, keep_editing: widget.Submit }

fn wizard_options() -> WizardOptions {
    var out: WizardOptions = zero
    ret out
}

// A wizard: the steps' names in a stepper, the current `content`, and a footer
// of Cancel (keyed `key + 1`), Back (`key + 2`, disabled on the first step) and
// Next (`key + 3`) or, on the last step, Finish (`key + 4`), the two disabled
// while `can_advance` is false; Enter is Next or Finish, Escape is Cancel. The
// page (keyed `key + 5`) is a group named by the step, the wizard a group named
// by its title at the current step of the count. Drawn as the v2 horizontal
// wizard of D974 below.
fn wizard(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, steps: []const str, current: usize, content: widget.Node, can_advance: bool, back: *const widget.Submit, next: *const widget.Submit, finish: *const widget.Submit, cancel: *const widget.Submit, width: f32, height: f32) -> (widget.Node, err) {
    let (named, named_error) = mem.alloc[WizardStep](a, steps.len)
    if named_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < steps.len {
        var step: WizardStep = zero
        step.label = steps[i]
        named[i] = step
        i += 1usize
    }
    let (made, made_error) = wizard_drawn(a, key, t, title, named[0usize..steps.len], current, content, can_advance, true, back, next, finish, cancel, wizard_options(), width, height)
    ret (made, made_error)
}

// v2 (D974, docs/ux/components/Wizard): the wizard of its specification, Next
// always enabled (the caller reports an invalid step through its `attention` and
// `note`) and Back hidden on the first step.
fn wizard_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, steps: []const WizardStep, current: usize, content: widget.Node, back: *const widget.Submit, next: *const widget.Submit, finish: *const widget.Submit, cancel: *const widget.Submit, options: WizardOptions, width: f32, height: f32) -> (widget.Node, err) {
    let (made, made_error) = wizard_drawn(a, key, t, title, steps, current, content, true, false, back, next, finish, cancel, options, width, height)
    ret (made, made_error)
}

type WizardMove = struct { action: widget.Submit, runtime: *widget.Runtime, focus: widget.Key }

fn wizard_move_fire(ctx: *void) -> err {
    let m = mem.cast[*WizardMove](ctx)
    let moved = widget.fire_submit(m.action)
    if moved != ok { ret moved }
    ret widget.focus_key(m.runtime, m.focus)
}

type WizardStepPick = struct { index: usize, pick: widget.Change[usize], runtime: *widget.Runtime, focus: widget.Key }

fn wizard_step_pick(ctx: *void, gesture: widget.Gesture) -> err {
    if gesture.tag != .Tap { ret ok }
    let p = mem.cast[*WizardStepPick](ctx)
    let picked = widget.fire_change[usize](p.pick, p.index)
    if picked != ok { ret picked }
    ret widget.focus_key(p.runtime, p.focus)
}

// One step of the stepper (D974): the 24 marker, then 8 on, the label over its
// note; a list item named with its state. When reachable it is a 32 (48 touch)
// pressable target keyed by the caller, with one roving stepper Tab stop.
fn wizard_step(a: *mem.Arena, key: widget.Key, t: *const control.Theme, step: *const WizardStep, index: usize, count: usize, current: usize, pressable: bool, focusable: bool, pick: *WizardStepPick) -> (widget.Node, err) {
    let done = index < current
    let now = index == current
    let primary = style.color(t.tokens, .Primary)
    let on_primary = style.color(t.tokens, .OnPrimary)
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let ink = style.color(t.tokens, .OnSurface)
    let (digits, digits_error) = mem.alloc[u8](a, 21usize)
    if digits_error != ok { ret (zero, TooLarge) }
    let digit_count = control.write_i64(digits, i64(index + 1usize))
    var number = control.text_options()
    number.role = .LabelMedium
    number.wrap = .None
    var marker = widget.box(0u64, control.sized_style(24.0, 24.0), zero)
    if step.attention {
        let (alert, alert_error) = control.icon_square(a, style.color(t.tokens, .Error), .Alert, 24.0)
        if alert_error != ok { ret (zero, alert_error) }
        marker = alert
    } else {
        let (inside, inside_error) = mem.alloc[widget.Node](a, 1usize)
        if inside_error != ok { ret (zero, TooLarge) }
        var disc = control.sized_style(24.0, 24.0)
        disc.radius = 12.0
        if done || now {
            disc.background = paint.Brush { Solid: primary }
            if done {
                let (tick, tick_error) = control.icon_square(a, on_primary, .Check, 18.0)
                if tick_error != ok { ret (zero, tick_error) }
                inside[0usize] = tick
            } else {
                let (said, said_error) = control.colored_text(a, 0u64, digits[0usize..digit_count], t, number, on_primary)
                if said_error != ok { ret (zero, said_error) }
                inside[0usize] = said
            }
        } else {
            disc.border = style.Border { width: 1.0, color: style.color(t.tokens, .Outline) }
            let (said, said_error) = control.colored_text(a, 0u64, digits[0usize..digit_count], t, number, muted)
            if said_error != ok { ret (zero, said_error) }
            inside[0usize] = said
        }
        marker = widget.aligned(0u64, .Center, .Center, disc, inside[0usize..1usize])
    }
    var caption = control.text_options()
    caption.role = .BodyMedium
    caption.wrap = .None
    var label_ink = ink
    if now { caption.role = .TitleSmall }
    if !done && !now && !step.attention { label_ink = muted }
    let (lines, lines_error) = mem.alloc[widget.Node](a, 2usize)
    if lines_error != ok { ret (zero, TooLarge) }
    let (label_node, label_error) = control.colored_text(a, 0u64, step.label, t, caption, label_ink)
    if label_error != ok { ret (zero, label_error) }
    lines[0usize] = label_node
    var line_count = 1usize
    if step.note.len > 0usize {
        var small = control.text_options()
        small.role = .BodySmall
        small.wrap = .None
        var note_ink = muted
        if step.attention { note_ink = style.color(t.tokens, .Error) }
        let (note_node, note_error) = control.colored_text(a, 0u64, step.note, t, small, note_ink)
        if note_error != ok { ret (zero, note_error) }
        lines[1usize] = note_node
        line_count = 2usize
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = marker
    parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), lines[0usize..line_count])
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, style.defaults(), parts[0usize..2usize])
    var named = step.label
    if done {
        let (finished, finished_error) = joined(a, step.label, ", completed")
        if finished_error != ok { ret (zero, finished_error) }
        named = finished
    }
    if step.attention {
        let (flagged, flagged_error) = joined(a, step.label, ", needs attention")
        if flagged_error != ok { ret (zero, flagged_error) }
        named = flagged
        if step.note.len > 0usize {
            let (said, said_error) = joined(a, flagged, ": ")
            if said_error != ok { ret (zero, said_error) }
            let (full, full_error) = joined(a, said, step.note)
            if full_error != ok { ret (zero, full_error) }
            named = full
        }
    }
    var sem: widget.Semantics = zero
    sem.role = 11u8
    sem.label = named
    sem.row = u32(index + 1usize)
    sem.row_count = u32(count)
    if now { sem.states = accessibility.STATE_CURRENT }
    if !pressable { ret (widget.semantics(0u64, sem, style.defaults(), held[0usize..1usize]), ok) }
    sem.actions = accessibility.ACTION_PRESS
    var hit = style.defaults()
    hit.min_height = style.Length { Px: 32.0 }
    if t.tokens.metrics.control_height > t.tokens.sizes.control_sm { hit.min_height = style.Length { Px: 48.0 } }
    let state = control.control_state(t, key, true, now)
    hit.background = paint.Brush { Solid: control.with_alpha(ink, control.state_opacity(t, state)) }
    hit.radius = t.tokens.radii.sm
    control.focus_look(t)
    let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
    if region_error != ok { ret (zero, TooLarge) }
    region[0usize] = widget.region(key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](pick), invoke: wizard_step_pick }, gestures: 1u8 | 4u8, enabled: true, focusable: focusable }, hit, held[0usize..1usize])
    ret (widget.semantics(0u64, sem, style.defaults(), region[0usize..1usize]), ok)
}

// v2 (D974, docs/ux/components/Wizard). Expanded, the wizard is `width` by
// `height` on `surface` (a dialog: `surface-container-high`, `radius-xl`): the
// `headline-small` title 24 in and 20 from the top, a level-1 heading; the
// stepper 24 in and 16 above and below; the content 24 in and 8 below it; the
// footer 24 in and 16 above and below, Cancel a text button at the start, Back
// outlined and Next (Finish, or the task's verb, on the last step) filled at the
// end, 8 apart. A step is its 24 marker -- upcoming a 1px `outline` ring round
// its `label-medium` number in `on-surface-variant`, current a `primary` disc
// with the number in `on-primary`, done the disc with a check, needing attention
// the 24 `error` alert -- then, 8 on, its `body-medium` label (`on-surface-variant`
// upcoming, `title-small` current, `on-surface` done) over an optional
// `body-small` note (`error` when the step needs attention). Horizontal steps
// stand in a row joined by connectors at least 16 long, 8 clear of each step, 1px
// `outline-variant` or 2px `primary` after a done step; vertical steps stand in
// a 240 column at the start, joined by 16 tall connectors under their markers.
// Compact, the wizard is full screen on `surface` under a v2 app bar (keyed
// `key + 6`) led by Back (`arrow-back`) or on the first step Close, "Step 2 of 4:
// Build" in `label-medium` `on-surface-variant` over a 4 tall `primary` bar
// (keyed `key + 8`) on `secondary-container`, the content 16 in, and Next
// full-width at the foot, 16 in. The stepper is a list of its steps, each named
// with its state ("Account, completed", "Build, needs attention: fix 1 field")
// and the current one Current. The content exposes its step name as a level-2
// heading keyed `key + 5`; successful Back and Next request it across rebuilds.
// At pointer density Alt+B and Alt+N invoke those same backward and forward
// paths. On the last step `finishing` keeps the primary button's width while an
// indeterminate 18 ring replaces its label and disables Back, Cancel, access
// keys, step picks and repeated Finish activation. Cancel, Escape and compact
// Close ask before discarding a dirty wizard.
// `legacy` keeps D853's contract: Back stays (disabled) on the first step and
// Next and Finish follow `can_advance`.
fn wizard_drawn(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, steps: []const WizardStep, current: usize, content: widget.Node, can_advance: bool, legacy: bool, back: *const widget.Submit, next: *const widget.Submit, finish: *const widget.Submit, cancel: *const widget.Submit, options: WizardOptions, width: f32, height: f32) -> (widget.Node, err) {
    if steps.len == 0usize || current >= steps.len { ret (zero, TooLarge) }
    let last = current + 1usize == steps.len
    let compact = options.form == .Compact
    let vertical = options.form == .Vertical
    let advancing = !legacy || can_advance
    let finishing = options.finishing && last
    let (moves, moves_error) = mem.alloc[WizardMove](a, 2usize)
    if moves_error != ok { ret (zero, TooLarge) }
    let (move_actions, move_actions_error) = mem.alloc[widget.Submit](a, 4usize)
    if move_actions_error != ok { ret (zero, TooLarge) }
    moves[0usize] = WizardMove { action: *back, runtime: t.runtime, focus: key + 5u64 }
    moves[1usize] = WizardMove { action: *next, runtime: t.runtime, focus: key + 5u64 }
    move_actions[0usize] = widget.Submit { ctx: mem.cast[*void](&moves[0usize]), invoke: wizard_move_fire }
    move_actions[1usize] = widget.Submit { ctx: mem.cast[*void](&moves[1usize]), invoke: wizard_move_fire }
    move_actions[2usize] = widget.Submit { ctx: zero, invoke: zero }
    move_actions[3usize] = *cancel
    if options.dirty { move_actions[3usize] = options.request_discard }
    if finishing { move_actions[3usize] = move_actions[2usize] }
    var pressable_count = 0usize
    if options.pressable_steps {
        pressable_count = current + 1usize
        if options.nonlinear { pressable_count = steps.len }
    }
    if finishing { pressable_count = 0usize }
    var step_tab_stop = current
    var focused_step = 0usize
    while focused_step < pressable_count {
        if widget.focus_within(t.runtime, key + 16u64 + u64(focused_step)) { step_tab_stop = focused_step }
        focused_step += 1usize
    }
    let (step_picks, step_picks_error) = mem.alloc[WizardStepPick](a, steps.len)
    if step_picks_error != ok { ret (zero, TooLarge) }
    let flat = style.Length { Px: 0.0 }
    var finish_label = options.finish_label
    if finish_label.len == 0usize { finish_label = "Finish" }
    // The stepper.
    let (items, items_error) = mem.alloc[widget.Node](a, 2usize * steps.len)
    if items_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    var i = 0usize
    while i < steps.len {
        let step_key = key + 16u64 + u64(i)
        step_picks[i] = WizardStepPick { index: i, pick: options.step, runtime: t.runtime, focus: step_key }
        let (made, made_error) = wizard_step(a, step_key, t, &steps[i], i, steps.len, current, i < pressable_count, i == step_tab_stop, &step_picks[i])
        if made_error != ok { ret (zero, made_error) }
        items[n] = made
        n += 1usize
        if i + 1usize < steps.len {
            var joint = style.defaults()
            var thick: f32 = 1.0
            joint.background = paint.Brush { Solid: style.color(t.tokens, .OutlineVariant) }
            if i < current {
                thick = 2.0
                joint.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
            }
            if vertical {
                joint.width = style.Length { Px: thick }
                joint.height = style.Length { Px: 16.0 }
                let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
                if held_error != ok { ret (zero, TooLarge) }
                held[0usize] = widget.box(0u64, joint, zero)
                items[n] = widget.aligned(0u64, .Center, .Center, control.sized_style(24.0, 16.0), held[0usize..1usize])
            } else {
                joint.height = style.Length { Px: thick }
                joint.width = style.Length { Flex: 1.0 }
                joint.min_width = style.Length { Px: 16.0 }
                items[n] = widget.box(0u64, joint, zero)
            }
            n += 1usize
        }
        i += 1usize
    }
    var list_sem: widget.Semantics = zero
    list_sem.role = 10u8
    list_sem.row_count = u32(steps.len)
    let (listed, listed_error) = mem.alloc[widget.Node](a, 1usize)
    if listed_error != ok { ret (zero, TooLarge) }
    var stepper_style = style.defaults()
    if vertical {
        stepper_style.width = style.Length { Px: 240.0 }
        stepper_style.padding = style.EdgeLengths { left: style.Length { Px: 24.0 }, top: style.Length { Px: 16.0 }, right: style.Length { Px: 24.0 }, bottom: style.Length { Px: 16.0 } }
        listed[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, stepper_style, items[0usize..n])
    } else {
        stepper_style.width = style.Length { Px: width }
        stepper_style.padding = style.EdgeLengths { left: style.Length { Px: 24.0 }, top: style.Length { Px: 16.0 }, right: style.Length { Px: 24.0 }, bottom: style.Length { Px: 16.0 } }
        listed[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, stepper_style, items[0usize..n])
    }
    var stepper = widget.semantics(0u64, list_sem, style.defaults(), listed[0usize..1usize])
    if pressable_count > 0usize {
        let (step_moves, step_moves_error) = mem.alloc[DestinationMove](a, 4usize)
        if step_moves_error != ok { ret (zero, TooLarge) }
        let (step_shortcuts, step_shortcuts_error) = mem.alloc[widget.Shortcut](a, 4usize)
        if step_shortcuts_error != ok { ret (zero, TooLarge) }
        var previous = 37u32
        var next_key = 39u32
        if vertical {
            previous = 38u32
            next_key = 40u32
        }
        step_moves[0usize] = DestinationMove { runtime: t.runtime, first: key + 16u64, count: pressable_count, backward: true, edge: false }
        step_moves[1usize] = DestinationMove { runtime: t.runtime, first: key + 16u64, count: pressable_count, backward: false, edge: false }
        step_moves[2usize] = DestinationMove { runtime: t.runtime, first: key + 16u64, count: pressable_count, backward: true, edge: true }
        step_moves[3usize] = DestinationMove { runtime: t.runtime, first: key + 16u64, count: pressable_count, backward: false, edge: true }
        step_shortcuts[0usize] = widget.Shortcut { key: previous, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&step_moves[0usize]), invoke: destination_move_fire } }
        step_shortcuts[1usize] = widget.Shortcut { key: next_key, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&step_moves[1usize]), invoke: destination_move_fire } }
        step_shortcuts[2usize] = widget.Shortcut { key: 36u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&step_moves[2usize]), invoke: destination_move_fire } }
        step_shortcuts[3usize] = widget.Shortcut { key: 35u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&step_moves[3usize]), invoke: destination_move_fire } }
        let (step_held, step_held_error) = mem.alloc[widget.Node](a, 1usize)
        if step_held_error != ok { ret (zero, TooLarge) }
        step_held[0usize] = stepper
        stepper = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: step_shortcuts[0usize..4usize], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), step_held[0usize..1usize])
    }
    // The page, growing.
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var page = style.defaults()
    page.width = style.Length { Flex: 1.0 }
    if !vertical {
        page.width = style.Length { Px: width }
        page.height = style.Length { Flex: 1.0 }
    }
    page.overflow = .Clip
    var sides: f32 = 24.0
    if compact { sides = 16.0 }
    var page_top: f32 = 8.0
    if vertical { page_top = 16.0 }
    page.padding = style.EdgeLengths { left: style.Length { Px: sides }, top: style.Length { Px: page_top }, right: style.Length { Px: sides }, bottom: flat }
    var page_sem: widget.Semantics = zero
    page_sem.role = 25u8
    page_sem.label = steps[current].label
    page_sem.level = 2u8
    let page_node = widget.semantics(key + 5u64, page_sem, page, body[0usize..1usize])
    // The footer.
    var default_action: widget.Submit = zero
    var forward: *const widget.Submit = &move_actions[1usize]
    var forward_key = key + 3u64
    var forward_label = "Next"
    if last {
        forward = finish
        forward_key = key + 4u64
        forward_label = finish_label
    }
    if advancing && !finishing { default_action = *forward }
    let (foot, foot_error) = mem.alloc[widget.Node](a, 4usize)
    if foot_error != ok { ret (zero, TooLarge) }
    var f = 0usize
    var footer = style.defaults()
    footer.width = style.Length { Px: width }
    if compact {
        // Next full-width at the foot.
        let state = control.control_state(t, forward_key, advancing, false)
        var look = control.button_look(t, style.resolve(t.tokens, .Filled, state), advancing)
        look.min_width = control.max_zero(width - 32.0)
        look.min_height = t.tokens.sizes.control_md
        var caption = control.text_options()
        caption.role = .LabelLarge
        caption.wrap = .None
        var label_ink = look.foreground
        if finishing { label_ink.alpha = 0.0 }
        let (said, said_error) = control.colored_text(a, 0u64, forward_label, t, caption, label_ink)
        if said_error != ok { ret (zero, said_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = said
        var centre = style.defaults()
        centre.min_width = style.Length { Px: control.max_zero(width - 32.0 - 2.0 * look.padding) }
        var label_node = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, centre, held[0usize..1usize])
        if finishing {
            var inked = control.progress_options()
            inked.content = look.foreground
            let (ring, ring_error) = control.progress_ring_of(a, 0u64, t, forward_label, 0.0, true, t.tokens.sizes.icon_sm, inked)
            if ring_error != ok { ret (zero, ring_error) }
            let (loading, loading_error) = mem.alloc[widget.Node](a, 3usize)
            if loading_error != ok { ret (zero, TooLarge) }
            loading[0usize] = ring
            loading[1usize] = label_node
            loading[2usize] = widget.aligned(0u64, .Center, .Center, style.defaults(), loading[0usize..1usize])
            label_node = widget.stack(0u64, style.defaults(), loading[1usize..3usize])
        }
        var forward_action = forward
        if finishing { forward_action = &move_actions[2usize] }
        var forward_states = 0u32
        if finishing { forward_states = accessibility.STATE_BUSY }
        let (going, going_error) = control.pressable_states(a, forward_key, t, 3u8, forward_label, look, advancing, false, forward_states, 0u32, 0u64, forward_action, label_node)
        if going_error != ok { ret (zero, going_error) }
        foot[0usize] = going
        f = 1usize
        footer.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: flat, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 16.0 } }
    } else {
        var plain = control.button_options()
        plain.variant = .Plain
        plain.enabled = !finishing
        let (cancel_button, cancel_error) = control.button(a, key + 1u64, t, "Cancel", &move_actions[3usize], plain)
        if cancel_error != ok { ret (zero, cancel_error) }
        foot[0usize] = cancel_button
        foot[1usize] = widget.spacer(0u64, 1.0)
        f = 2usize
        if legacy || current > 0usize {
            var outlined = control.button_options()
            outlined.variant = .Outlined
            outlined.enabled = current > 0usize && !finishing
            let (back_button, back_error) = control.button(a, key + 2u64, t, "Back", &move_actions[0usize], outlined)
            if back_error != ok { ret (zero, back_error) }
            foot[f] = back_button
            f += 1usize
        }
        var filled = control.button_options()
        filled.enabled = advancing
        filled.loading = finishing
        var forward_action = forward
        if finishing { forward_action = &move_actions[2usize] }
        let (next_button, next_error) = control.button(a, forward_key, t, forward_label, forward_action, filled)
        if next_error != ok { ret (zero, next_error) }
        foot[f] = next_button
        f += 1usize
        let edge = style.Length { Px: 24.0 }
        let rim = style.Length { Px: 16.0 }
        footer.padding = style.EdgeLengths { left: edge, top: rim, right: edge, bottom: rim }
    }
    let footer_node = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, footer, foot[0usize..f])
    // The head, then the steps, the page and the footer.
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var p = 0usize
    if compact {
        var bar_options = app_bar_options()
        bar_options.back_label = "Close"
        bar_options.back = move_actions[3usize]
        bar_options.closing = true
        if current > 0usize {
            bar_options.back_label = "Back"
            bar_options.back = move_actions[0usize]
            bar_options.closing = false
        }
        if finishing {
            bar_options.back = move_actions[2usize]
            bar_options.back_disabled = true
        }
        var nothing: []const Action = zero
        let (bar, bar_error) = app_bar_of(a, key + 6u64, t, title, nothing, nothing, bar_options, width)
        if bar_error != ok { ret (zero, bar_error) }
        parts[p] = bar
        p += 1usize
        // "Step 2 of 4: Build" over the progress bar.
        let cap = steps[current].label.len + 48usize
        let (said, said_error) = mem.alloc[u8](a, cap)
        if said_error != ok { ret (zero, TooLarge) }
        var m = control.copy_text(said, "Step ")
        m += control.write_i64(said[m..cap], i64(current + 1usize))
        m += control.copy_text(said[m..cap], " of ")
        m += control.write_i64(said[m..cap], i64(steps.len))
        m += control.copy_text(said[m..cap], ": ")
        m += control.copy_text(said[m..cap], steps[current].label)
        var small = control.text_options()
        small.role = .LabelMedium
        small.wrap = .None
        let (step_words, step_words_error) = control.colored_text(a, 0u64, said[0usize..m], t, small, muted)
        if step_words_error != ok { ret (zero, step_words_error) }
        let span = control.max_zero(width - 32.0)
        let share = f32(current + 1usize) / f32(steps.len)
        var filled = control.sized_style(span * share, 4.0)
        filled.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
        filled.radius = 2.0
        let (fills, fills_error) = mem.alloc[widget.Node](a, 1usize)
        if fills_error != ok { ret (zero, TooLarge) }
        fills[0usize] = widget.box(0u64, filled, zero)
        var track = control.sized_style(span, 4.0)
        track.background = paint.Brush { Solid: style.color(t.tokens, .SecondaryContainer) }
        track.radius = 2.0
        track.overflow = .Clip
        let (progress, progress_error) = mem.alloc[widget.Node](a, 2usize)
        if progress_error != ok { ret (zero, TooLarge) }
        progress[0usize] = step_words
        progress[1usize] = widget.box(key + 8u64, track, fills[0usize..1usize])
        var told = style.defaults()
        told.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 8.0 }, right: style.Length { Px: 16.0 }, bottom: flat }
        parts[p] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, told, progress[0usize..2usize])
        p += 1usize
        parts[p] = page_node
        p += 1usize
    } else {
        var heading = control.text_options()
        heading.role = .HeadlineSmall
        heading.wrap = .None
        heading.ellipsis = "..."
        heading.max_lines = 1u32
        let (title_node, title_error) = control.colored_text(a, 0u64, title, t, heading, style.color(t.tokens, .OnSurface))
        if title_error != ok { ret (zero, title_error) }
        let (titled, titled_error) = mem.alloc[widget.Node](a, 1usize)
        if titled_error != ok { ret (zero, TooLarge) }
        titled[0usize] = title_node
        var title_sem: widget.Semantics = zero
        title_sem.role = 25u8
        title_sem.label = title
        title_sem.level = 1u8
        var title_style = style.defaults()
        title_style.padding = style.EdgeLengths { left: style.Length { Px: 24.0 }, top: style.Length { Px: 20.0 }, right: style.Length { Px: 24.0 }, bottom: flat }
        parts[p] = widget.semantics(0u64, title_sem, title_style, titled[0usize..1usize])
        p += 1usize
        if vertical {
            let (middle, middle_error) = mem.alloc[widget.Node](a, 2usize)
            if middle_error != ok { ret (zero, TooLarge) }
            middle[0usize] = stepper
            middle[1usize] = page_node
            var middle_style = style.defaults()
            middle_style.width = style.Length { Px: width }
            middle_style.height = style.Length { Flex: 1.0 }
            parts[p] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Stretch, gap: 0.0 }, middle_style, middle[0usize..2usize])
            p += 1usize
        } else {
            parts[p] = stepper
            p += 1usize
            parts[p] = page_node
            p += 1usize
        }
    }
    parts[p] = footer_node
    p += 1usize
    var outer = control.sized_style(width, height)
    outer.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    if options.dialog && !compact {
        outer.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) }
        outer.radius = t.tokens.radii.xl
        outer.overflow = .Clip
    }
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, outer, parts[0usize..p])
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    var shortcut_count = 0usize
    if t.tokens.metrics.control_height <= t.tokens.sizes.control_sm {
        var alt: input.Modifiers = zero
        alt.alt = true
        if current > 0usize && !finishing {
            shortcuts[shortcut_count] = widget.Shortcut { key: 66u32, modifiers: alt, action: move_actions[0usize] }
            shortcut_count += 1usize
        }
        if advancing && !finishing {
            shortcuts[shortcut_count] = widget.Shortcut { key: 78u32, modifiers: alt, action: *forward }
            shortcut_count += 1usize
        }
    }
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(key, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..shortcut_count], default_action: default_action, cancel_action: move_actions[3usize], keys: zero }, style.defaults(), column[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = title
    sem.row = u32(current + 1usize)
    sem.row_count = u32(steps.len)
    let wizard_node = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    if !options.dirty || !options.discard_open || finishing { ret (wizard_node, ok) }
    let (question, question_error) = joined(a, "Discard ", title)
    if question_error != ok { ret (zero, question_error) }
    let (prompt, prompt_error) = joined(a, question, "?")
    if prompt_error != ok { ret (zero, prompt_error) }
    let (buttons, buttons_error) = mem.alloc[overlay.DialogButton](a, 2usize)
    if buttons_error != ok { ret (zero, TooLarge) }
    buttons[0usize] = overlay.DialogButton { label: "Keep editing", action: options.keep_editing, kind: .Cancel }
    buttons[1usize] = overlay.DialogButton { label: "Discard", action: *cancel, kind: .Destructive }
    let (alert, alert_error) = overlay.alert_dialog(a, key + 10u64, t, prompt, "Your changes will be lost.", buttons[0usize..2usize], true)
    if alert_error != ok { ret (zero, alert_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, TooLarge) }
    layers[0usize] = wizard_node
    layers[1usize] = alert
    ret (widget.box(0u64, style.defaults(), layers[0usize..2usize]), ok)
}

// A pick of an index through a change, for a row.
type IndexPick = struct { index: usize, pick: widget.Change[usize] }

fn index_pick_fire(ctx: *void) -> err {
    let p = mem.cast[*IndexPick](ctx)
    ret widget.fire_change[usize](p.pick, p.index)
}

// The rows of a switcher or a palette: plain buttons keyed `first + index`, the
// active one filled and selected, each reporting its index through `pick`.
// v2 (D978, docs/ux/components/CommandPalette, WindowSwitcher): a row is 40 tall,
// 12 at its sides, `radius-sm`, its `body-medium` label in `on-surface`, centred
// in its height, under the `on-surface` state layer; the active one
// `secondary-container` with its label in `on-secondary-container`. A list item
// in the tree with its position, Selected when active.
fn choice_rows(a: *mem.Arena, first: widget.Key, t: *const control.Theme, names: []const str, categories: []const str, match_starts: []const usize, match_ends: []const usize, shortcuts: []const str, unavailable: []const str, active: usize, compact: bool, pick: widget.Change[usize]) -> ([]widget.Node, err) {
    var none: []widget.Node = zero
    let (rows, rows_error) = mem.alloc[widget.Node](a, names.len)
    if rows_error != ok { ret (none, TooLarge) }
    let (picks, picks_error) = mem.alloc[IndexPick](a, names.len)
    if picks_error != ok { ret (none, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, names.len)
    if actions_error != ok { ret (none, TooLarge) }
    let line = style.text_style(t.tokens, .BodyMedium).line_height
    var i = 0usize
    while i < names.len {
        picks[i] = IndexPick { index: i, pick: pick }
        actions[i] = widget.Submit { ctx: mem.cast[*void](&picks[i]), invoke: index_pick_fire }
        let row_key = first + u64(i)
        let enabled = unavailable.len != names.len || unavailable[i].len == 0usize
        let state = control.control_state(t, row_key, enabled, false)
        var fill = paint.rgba(0.0, 0.0, 0.0, 0.0)
        var ink = style.color(t.tokens, .OnSurface)
        if i == active && enabled && !compact {
            fill = style.color(t.tokens, .SecondaryContainer)
            ink = style.color(t.tokens, .OnSecondaryContainer)
        }
        var look = style.resolve(t.tokens, .Plain, state)
        look.background = style.layer(fill, ink, control.state_opacity(t, state))
        look.foreground = ink
        look.border_width = 0.0
        look.opacity = 1.0
        look.radius = t.tokens.radii.sm
        look.custom_padding = true
        look.padding = 12.0
        var row_height: f32 = 40.0
        if compact { row_height = 48.0 }
        look.padding_y = control.max_zero((row_height - line) * 0.5)
        look.min_height = row_height
        look.min_width = 24.0
        if !enabled { look.opacity = t.tokens.states.disabled_content }
        var caption = control.text_options()
        caption.role = .BodyMedium
        caption.wrap = .None
        var name_node: widget.Node = zero
        let matched = match_starts.len == names.len && match_ends.len == names.len && match_starts[i] < match_ends[i] && match_ends[i] <= names[i].len
        if matched {
            let (runs, runs_error) = mem.alloc[widget.Node](a, 5usize)
            if runs_error != ok { ret (none, TooLarge) }
            var strong = caption
            strong.role = .TitleSmall
            var match_ink = style.color(t.tokens, .Primary)
            if i == active { match_ink = ink }
            var before_text = names[i][0usize..match_starts[i]]
            var before_gap: f32 = 0.0
            if before_text.len > 0usize && before_text[before_text.len - 1usize] == 32u8 {
                before_text = before_text[0usize..before_text.len - 1usize]
                before_gap = 4.0
            }
            var after_text = names[i][match_ends[i]..names[i].len]
            var after_gap: f32 = 0.0
            if after_text.len > 0usize && after_text[0usize] == 32u8 {
                after_text = after_text[1usize..after_text.len]
                after_gap = 4.0
            }
            let (before, before_error) = control.colored_text(a, 0u64, before_text, t, caption, ink)
            let (hit, hit_error) = control.colored_text(a, 0u64, names[i][match_starts[i]..match_ends[i]], t, strong, match_ink)
            let (after, after_error) = control.colored_text(a, 0u64, after_text, t, caption, ink)
            if before_error != ok { ret (none, before_error) }
            if hit_error != ok { ret (none, hit_error) }
            if after_error != ok { ret (none, after_error) }
            var empty_children: []const widget.Node = zero
            runs[0usize] = before
            runs[1usize] = widget.box(0u64, control.sized_style(before_gap, 0.0), empty_children)
            runs[2usize] = hit
            runs[3usize] = widget.box(0u64, control.sized_style(after_gap, 0.0), empty_children)
            runs[4usize] = after
            name_node = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), runs[0usize..5usize])
        } else {
            let (plain_name, name_error) = control.colored_text(a, 0u64, names[i], t, caption, ink)
            if name_error != ok { ret (none, name_error) }
            name_node = plain_name
        }
        var said = name_node
        var semantic_label = names[i]
        if categories.len == names.len && categories[i].len > 0usize {
            let (category_label, category_error) = string.concat(a, categories[i], ":")
            if category_error != ok { ret (none, TooLarge) }
            let (category_space, category_space_error) = string.concat(a, category_label, " ")
            if category_space_error != ok { ret (none, TooLarge) }
            let (full_label, full_label_error) = string.concat(a, category_space, names[i])
            if full_label_error != ok { ret (none, TooLarge) }
            semantic_label = full_label
            var category_ink = style.color(t.tokens, .OnSurfaceVariant)
            if i == active { category_ink = ink }
            let (category_node, category_node_error) = control.colored_text(a, 0u64, category_label, t, caption, category_ink)
            if category_node_error != ok { ret (none, category_node_error) }
            let (caption_parts, caption_parts_error) = mem.alloc[widget.Node](a, 2usize)
            if caption_parts_error != ok { ret (none, TooLarge) }
            caption_parts[0usize] = category_node
            caption_parts[1usize] = name_node
            said = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 4.0 }, style.defaults(), caption_parts[0usize..2usize])
        }
        var trailing: widget.Node = zero
        var has_trailing = false
        if !enabled {
            var reason_options = caption
            reason_options.role = .BodySmall
            let (reason, reason_error) = control.colored_text(a, 0u64, unavailable[i], t, reason_options, style.color(t.tokens, .OnSurfaceVariant))
            if reason_error != ok { ret (none, reason_error) }
            trailing = reason
            has_trailing = true
        } else if !compact && shortcuts.len == names.len && shortcuts[i].len > 0usize {
            let (caps, caps_error) = control.compact_key_caps(a, t, shortcuts[i])
            if caps_error != ok { ret (none, caps_error) }
            trailing = caps
            has_trailing = true
            let (spoken_prefix, spoken_prefix_error) = string.concat(a, semantic_label, ", ")
            if spoken_prefix_error != ok { ret (none, TooLarge) }
            let (spoken, spoken_error) = string.concat(a, spoken_prefix, shortcuts[i])
            if spoken_error != ok { ret (none, TooLarge) }
            semantic_label = spoken
        }
        if has_trailing {
            let (row_parts, row_parts_error) = mem.alloc[widget.Node](a, 2usize)
            if row_parts_error != ok { ret (none, TooLarge) }
            row_parts[0usize] = said
            row_parts[1usize] = trailing
            var spread = style.defaults()
            spread.width = style.Length { Percent: 100.0 }
            said = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 12.0 }, spread, row_parts[0usize..2usize])
        }
        let (made, made_error) = control.pressable(a, row_key, t, 3u8, semantic_label, look, enabled, false, &actions[i], said)
        if made_error != ok { ret (none, made_error) }
        var stretched = made
        stretched.style.width = style.Length { Percent: 100.0 }
        var entry: widget.Semantics = zero
        entry.role = accessibility.ROLE_OPTION
        entry.label = semantic_label
        entry.row = u32(i + 1usize)
        entry.row_count = u32(names.len)
        if i == active { entry.states = accessibility.STATE_SELECTED }
        if !enabled {
            entry.states = entry.states | accessibility.STATE_DISABLED
            entry.hint = unavailable[i]
        }
        let (wrapped, wrapped_error) = mem.alloc[widget.Node](a, 1usize)
        if wrapped_error != ok { ret (none, TooLarge) }
        wrapped[0usize] = stretched
        var full = style.defaults()
        full.width = style.Length { Percent: 100.0 }
        rows[i] = widget.semantics(0u64, entry, full, wrapped[0usize..1usize])
        i += 1usize
    }
    ret (rows[0usize..names.len], ok)
}

// The Up and Down shortcuts moving `active` through `activate`, Enter picking
// it and, when `close` is set, Delete closing it; v2 (D978), wrapping at the
// ends.
fn choice_scope(a: *mem.Arena, key: widget.Key, count: usize, active: usize, runnable: bool, activate: widget.Change[usize], pick: widget.Change[usize], close: widget.Change[usize], dismiss: *const widget.Submit, content: widget.Node) -> (widget.Node, err) {
    let (moves, moves_error) = mem.alloc[IndexPick](a, 4usize)
    if moves_error != ok { ret (zero, TooLarge) }
    var previous = active
    if active > 0usize { previous = active - 1usize }
    if active == 0usize && count > 0usize { previous = count - 1usize }
    var next = 0usize
    if active + 1usize < count { next = active + 1usize }
    moves[0usize] = IndexPick { index: previous, pick: activate }
    moves[1usize] = IndexPick { index: next, pick: activate }
    moves[2usize] = IndexPick { index: active, pick: pick }
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 3usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    shortcuts[0usize] = widget.Shortcut { key: 38u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[0usize]), invoke: index_pick_fire } }
    shortcuts[1usize] = widget.Shortcut { key: 40u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[1usize]), invoke: index_pick_fire } }
    var shortcut_count = 2usize
    if active < count && widget.change_set[usize](close.invoke) {
        moves[3usize] = IndexPick { index: active, pick: close }
        shortcuts[2usize] = widget.Shortcut { key: 46u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&moves[3usize]), invoke: index_pick_fire } }
        shortcut_count = 3usize
    }
    var default_action: widget.Submit = zero
    if count > 0usize && runnable { default_action = widget.Submit { ctx: mem.cast[*void](&moves[2usize]), invoke: index_pick_fire } }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    ret (widget.scope(key, widget.Scope { traps_focus: true, shortcuts: shortcuts[0usize..shortcut_count], default_action: default_action, cancel_action: *dismiss, keys: zero }, style.defaults(), body[0usize..1usize]), ok)
}

// A modal panel holding `content` (keyed `key`), Escape and a press outside
// firing `dismiss`; a modal dialog in the tree named `label`.
// v2 (D978): `surface-container-high`, `radius-xl`, elevation 3, no border, no
// padding, `width` wide, top-centred 64 below the window's top; over a `scrim`
// at 32% across the window when `dimmed`.
fn centred_modal(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, content: widget.Node, dismiss: *const widget.Submit, width: f32, dimmed: bool) -> (widget.Node, err) {
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var options = control.surface_options(t)
    options.background = .SurfaceContainerHigh
    options.elevation = 3u8
    options.radius = t.tokens.radii.xl
    options.padding = 0.0
    var panel = control.surface_style(t, options)
    panel.width = style.Length { Px: width }
    let (boxed, boxed_error) = mem.alloc[widget.Node](a, 1usize)
    if boxed_error != ok { ret (zero, TooLarge) }
    boxed[0usize] = widget.box(0u64, panel, body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 23u8
    sem.label = label
    sem.states = accessibility.STATE_MODAL
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.semantics(0u64, sem, style.defaults(), boxed[0usize..1usize])
    let top = widget.overlay(key, widget.Overlay { anchor: 0u64, placement: .TopCenter, offset: geometry.Point { x: 0.0, y: 64.0 }, modal: true, dismiss: *dismiss }, style.defaults(), framed[0usize..1usize])
    if !dimmed { ret (top, ok) }
    let (made, made_error) = overlay.with_scrim(a, t, top)
    ret (made, made_error)
}

fn compact_modal(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, content: widget.Node, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var full = style.defaults()
    full.width = style.Length { Percent: 100.0 }
    full.height = style.Length { Percent: 100.0 }
    full.background = paint.Brush { Solid: style.color(t.tokens, .Surface) }
    let (boxed, boxed_error) = mem.alloc[widget.Node](a, 1usize)
    if boxed_error != ok { ret (zero, TooLarge) }
    boxed[0usize] = widget.box(0u64, full, body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 23u8
    sem.label = label
    sem.states = accessibility.STATE_MODAL
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.semantics(0u64, sem, style.defaults(), boxed[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: 0u64, placement: .Center, offset: zero, modal: true, dismiss: *dismiss }, style.defaults(), framed[0usize..1usize]), ok)
}

// A window switcher: the application's windows or documents by name in a modal
// panel in the middle of the window while `open`, the active one filled; Up and
// Down move the active one through `activate` (the caller keeps it), Enter and a
// tap pick through `pick`, Escape and a press outside fire `dismiss`. The rows
// are keyed `key + 2 + index`, the scope `key + 1`. The caller opens it from
// whatever chord its host lets it hear.
// v2 (D978, docs/ux/components/WindowSwitcher, list form): the panel of
// `centred_modal`, no scrim, the rows 4 above and below and 8 at the sides.
fn window_switcher(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, names: []const str, active: usize, open: bool, activate: widget.Change[usize], pick: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = window_switcher_closable(a, key, t, label, names, active, open, activate, pick, zero, dismiss, width)
    ret (made, made_error)
}

fn window_switcher_closable(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, names: []const str, active: usize, open: bool, activate: widget.Change[usize], pick: widget.Change[usize], close: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var no_categories: []const str = zero
    var no_shortcuts: []const str = zero
    var no_matches: []const usize = zero
    let (rows, rows_error) = choice_rows(a, key + 2u64, t, names, no_categories, no_matches, no_matches, no_shortcuts, no_shortcuts, active, false, pick)
    if rows_error != ok { ret (zero, rows_error) }
    var inset = style.defaults()
    inset.padding = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 8.0 }, bottom: style.Length { Px: 4.0 } }
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, inset, rows)
    let (list_body, list_body_error) = mem.alloc[widget.Node](a, 1usize)
    if list_body_error != ok { ret (zero, TooLarge) }
    list_body[0usize] = column
    var list_sem: widget.Semantics = zero
    list_sem.role = accessibility.ROLE_LISTBOX
    list_sem.label = label
    list_sem.row_count = u32(names.len)
    if active < names.len { list_sem.active = key + 2u64 + u64(active) }
    let list = widget.semantics(0u64, list_sem, style.defaults(), list_body[0usize..1usize])
    let (scoped, scoped_error) = choice_scope(a, key + 1u64, names.len, active, true, activate, pick, close, dismiss, list)
    if scoped_error != ok { ret (zero, scoped_error) }
    let (made, made_error) = centred_modal(a, key, t, label, scoped, dismiss, width, false)
    ret (made, made_error)
}

type SwitcherItem = struct { name: str, context: str, state: str, thumbnail: scene.TextureId }

// The caller-owned Ctrl+Tab hold lifecycle. Feed host events through
// `switcher_hold_event`, then build `window_switcher_grid_held`: the first chord
// selects the previous MRU item without drawing, another Tab steps (Shift goes
// back), the panel appears after 200ms, modifier release picks, and Escape or
// window blur cancels.
type SwitcherHold = struct { started: time.Instant, holding: bool }

fn switcher_hold_event(hold: *SwitcherHold, runtime: *widget.Runtime, event: input.Event, count: usize, current: usize, activate: widget.Change[usize], pick: widget.Change[usize], dismiss: *const widget.Submit) -> (bool, err) {
    switch event {
    case .KeyDown as k:
        let code = widget.key_code(k.key.physical)
        if code == 27u32 && hold.holding {
            hold.holding = false
            ret (true, widget.fire_submit(*dismiss))
        }
        if code != 9u32 || !k.modifiers.control || count <= 1usize { ret (false, ok) }
        var next = current
        if !hold.holding {
            hold.holding = true
            hold.started = widget.frame_time(runtime)
            next = 1usize
            if k.modifiers.shift { next = count - 1usize }
        } else if k.modifiers.shift {
            if next == 0usize { next = count - 1usize } else { next -= 1usize }
        } else {
            next += 1usize
            if next >= count { next = 0usize }
        }
        widget.request_animation_frame(runtime)
        ret (true, widget.fire_change[usize](activate, next))
    case .KeyUp as k:
        if !hold.holding || k.modifiers.control { ret (false, ok) }
        hold.holding = false
        ret (true, widget.fire_change[usize](pick, current))
    case .Blur as w:
        if !hold.holding { ret (false, ok) }
        hold.holding = false
        ret (true, widget.fire_submit(*dismiss))
    default:
        ret (false, ok)
    }
}

fn switcher_hold_open(hold: *const SwitcherHold, runtime: *widget.Runtime) -> bool {
    if !hold.holding { ret false }
    let elapsed = widget.frame_time(runtime).nanos - hold.started.nanos
    if elapsed < 200000000i64 {
        widget.request_animation_frame(runtime)
        ret false
    }
    ret true
}

fn switcher_item_label(a: *mem.Arena, item: SwitcherItem) -> (str, err) {
    var label = item.name
    if item.context.len > 0usize {
        let (prefix, prefix_error) = string.concat(a, label, ", ")
        if prefix_error != ok { ret ("", TooLarge) }
        let (full_label, full_label_error) = string.concat(a, prefix, item.context)
        if full_label_error != ok { ret ("", TooLarge) }
        label = full_label
    }
    if item.state.len > 0usize {
        let (prefix, prefix_error) = string.concat(a, label, ", ")
        if prefix_error != ok { ret ("", TooLarge) }
        let (full_label, full_label_error) = string.concat(a, prefix, item.state)
        if full_label_error != ok { ret ("", TooLarge) }
        label = full_label
    }
    ret (label, ok)
}

fn switcher_item_detail(a: *mem.Arena, item: SwitcherItem) -> (str, err) {
    if item.context.len == 0usize { ret (item.state, ok) }
    if item.state.len == 0usize { ret (item.context, ok) }
    let (prefix, prefix_error) = string.concat(a, item.context, ", ")
    if prefix_error != ok { ret ("", TooLarge) }
    let (detail, detail_error) = string.concat(a, prefix, item.state)
    if detail_error != ok { ret ("", TooLarge) }
    ret (detail, ok)
}

fn switcher_grid_rows(a: *mem.Arena, first: widget.Key, t: *const control.Theme, items: []const SwitcherItem, active: usize, pick: widget.Change[usize], close: widget.Change[usize]) -> ([]widget.Node, err) {
    var none: []widget.Node = zero
    let (tiles, tiles_error) = mem.alloc[widget.Node](a, items.len)
    if tiles_error != ok { ret (none, TooLarge) }
    let (picks, picks_error) = mem.alloc[IndexPick](a, items.len)
    if picks_error != ok { ret (none, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, items.len)
    if actions_error != ok { ret (none, TooLarge) }
    let (closes, closes_error) = mem.alloc[TabClose](a, items.len)
    if closes_error != ok { ret (none, TooLarge) }
    let (close_actions, close_actions_error) = mem.alloc[widget.Submit](a, items.len)
    if close_actions_error != ok { ret (none, TooLarge) }
    let closable = widget.change_set[usize](close.invoke)
    var i = 0usize
    while i < items.len {
        picks[i] = IndexPick { index: i, pick: pick }
        actions[i] = widget.Submit { ctx: mem.cast[*void](&picks[i]), invoke: index_pick_fire }
        let row_key = first + u64(i)
        let close_key = first + 1024u64 + u64(i)
        var ink = style.color(t.tokens, .OnSurface)
        var fill = paint.rgba(0.0, 0.0, 0.0, 0.0)
        if i == active {
            ink = style.color(t.tokens, .OnSecondaryContainer)
            fill = style.color(t.tokens, .SecondaryContainer)
        }
        let (content, content_error) = mem.alloc[widget.Node](a, 2usize)
        if content_error != ok { ret (none, TooLarge) }
        let has_thumbnail = items[i].thumbnail.slot != 0u32 || items[i].thumbnail.generation != 0u32
        var picture: widget.Node = zero
        if has_thumbnail {
            let (image_node, image_error) = control.image(a, 0u64, items[i].thumbnail, 120.0, 84.0, .Cover, "")
            if image_error != ok { ret (none, image_error) }
            picture = image_node
        } else {
            picture = widget.box(0u64, control.sized_style(120.0, 84.0), zero)
        }
        let (picture_body, picture_body_error) = mem.alloc[widget.Node](a, 1usize)
        if picture_body_error != ok { ret (none, TooLarge) }
        picture_body[0usize] = picture
        var frame = control.sized_style(120.0, 84.0)
        frame.background = paint.Brush { Solid: style.color(t.tokens, .Surface) }
        frame.border = style.Border { width: t.tokens.sizes.divider, color: style.color(t.tokens, .OutlineVariant) }
        frame.radius = t.tokens.radii.sm
        frame.overflow = .Clip
        content[0usize] = widget.box(0u64, frame, picture_body[0usize..1usize])
        let (caption, caption_error) = mem.alloc[widget.Node](a, 2usize)
        if caption_error != ok { ret (none, TooLarge) }
        let (icon, icon_error) = control.icon_square(a, ink, .Picture, 16.0)
        if icon_error != ok { ret (none, icon_error) }
        caption[0usize] = icon
        var words = control.text_options()
        words.role = .BodySmall
        words.wrap = .None
        words.ellipsis = "…"
        let (name, name_error) = control.colored_text(a, 0u64, items[i].name, t, words, ink)
        if name_error != ok { ret (none, name_error) }
        caption[1usize] = name
        content[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, style.defaults(), caption[0usize..2usize])
        let face = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 8.0 }, style.defaults(), content[0usize..2usize])
        var look = style.resolve(t.tokens, .Plain, control.control_state(t, row_key, true, false))
        look.background = style.layer(fill, ink, control.state_opacity(t, control.control_state(t, row_key, true, false)))
        look.foreground = ink
        look.border_width = 0.0
        if i == active {
            look.border_width = 3.0
            look.border = style.color(t.tokens, .FocusRing)
        }
        look.radius = t.tokens.radii.md
        look.custom_padding = true
        look.padding = 8.0
        look.padding_y = 8.0
        look.min_width = 136.0
        look.min_height = 120.0
        let (semantic_label, semantic_label_error) = switcher_item_label(a, items[i])
        if semantic_label_error != ok { ret (none, semantic_label_error) }
        let (pressed, pressed_error) = control.pressable(a, row_key, t, 3u8, semantic_label, look, true, false, &actions[i], face)
        if pressed_error != ok { ret (none, pressed_error) }
        var tile = pressed
        if closable {
            let state = control.control_state(t, row_key, true, false)
            let close_state = control.control_state(t, close_key, true, false)
            if state.hovered || close_state.hovered || close_state.focus_visible {
                closes[i] = TabClose { index: i, close: close }
                close_actions[i] = widget.Submit { ctx: mem.cast[*void](&closes[i]), invoke: tab_close_fire }
                let (close_name, close_name_error) = joined(a, "Close ", items[i].name)
                if close_name_error != ok { ret (none, close_name_error) }
                let close_ink = style.color(t.tokens, .OnSurface)
                let (close_icon, close_icon_error) = control.icon_square(a, close_ink, .Cross, 14.0)
                if close_icon_error != ok { ret (none, close_icon_error) }
                var close_look = style.resolve(t.tokens, .Plain, close_state)
                close_look.background = style.layer(style.color(t.tokens, .SurfaceContainerHighest), close_ink, control.state_opacity(t, close_state))
                close_look.foreground = close_ink
                close_look.border_width = 0.0
                close_look.radius = 12.0
                close_look.custom_padding = true
                close_look.padding = 5.0
                close_look.padding_y = 5.0
                close_look.min_width = 24.0
                close_look.min_height = 24.0
                let (button, button_error) = control.pressable(a, close_key, t, 3u8, close_name, close_look, true, false, &close_actions[i], close_icon)
                if button_error != ok { ret (none, button_error) }
                let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
                if layers_error != ok { ret (none, TooLarge) }
                layers[0usize] = pressed
                let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
                if held_error != ok { ret (none, TooLarge) }
                held[0usize] = button
                layers[1usize] = widget.positioned(0u64, 108.0, 4.0, style.defaults(), held[0usize..1usize])
                tile = widget.stack(0u64, control.sized_style(136.0, 120.0), layers[0usize..2usize])
            }
        }
        let (wrapped, wrapped_error) = mem.alloc[widget.Node](a, 1usize)
        if wrapped_error != ok { ret (none, TooLarge) }
        wrapped[0usize] = tile
        var sem: widget.Semantics = zero
        sem.role = accessibility.ROLE_OPTION
        sem.label = semantic_label
        sem.row = u32(i + 1usize)
        sem.row_count = u32(items.len)
        if i == active { sem.states = accessibility.STATE_SELECTED }
        tiles[i] = widget.semantics(0u64, sem, style.defaults(), wrapped[0usize..1usize])
        i += 1usize
    }
    ret (tiles, ok)
}

fn window_switcher_grid(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const SwitcherItem, active: usize, open: bool, activate: widget.Change[usize], pick: widget.Change[usize], dismiss: *const widget.Submit) -> (widget.Node, err) {
    let (made, made_error) = window_switcher_grid_closable(a, key, t, label, items, active, open, activate, pick, zero, dismiss)
    ret (made, made_error)
}

fn window_switcher_grid_closable(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const SwitcherItem, active: usize, open: bool, activate: widget.Change[usize], pick: widget.Change[usize], close: widget.Change[usize], dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open || items.len <= 1usize { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (tiles, tiles_error) = switcher_grid_rows(a, key + 2u64, t, items, active, pick, close)
    if tiles_error != ok { ret (zero, tiles_error) }
    var columns = items.len
    if columns > 6usize { columns = 6usize }
    let inner_width = f32(columns) * 136.0 + f32(columns - 1usize) * 8.0
    var grid_style = style.defaults()
    grid_style.width = style.Length { Px: inner_width }
    let grid = widget.wrap(0u64, ui_layout.Wrap { axis: .Horizontal, main_gap: 8.0, cross_gap: 8.0 }, grid_style, tiles)
    let (list_body, list_body_error) = mem.alloc[widget.Node](a, 1usize)
    if list_body_error != ok { ret (zero, TooLarge) }
    list_body[0usize] = grid
    var list_sem: widget.Semantics = zero
    list_sem.role = accessibility.ROLE_LISTBOX
    list_sem.label = label
    list_sem.row_count = u32(items.len)
    if active < items.len { list_sem.active = key + 2u64 + u64(active) }
    let list = widget.semantics(0u64, list_sem, style.defaults(), list_body[0usize..1usize])
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = list
    var part_count = 1usize
    if active < items.len {
        var title = control.text_options()
        title.role = .TitleSmall
        title.wrap = .None
        let (name, name_error) = control.colored_text(a, 0u64, items[active].name, t, title, style.color(t.tokens, .OnSurface))
        if name_error != ok { ret (zero, name_error) }
        let (detail_parts, detail_parts_error) = mem.alloc[widget.Node](a, 2usize)
        if detail_parts_error != ok { ret (zero, TooLarge) }
        detail_parts[0usize] = name
        let (detail, detail_error) = switcher_item_detail(a, items[active])
        if detail_error != ok { ret (zero, detail_error) }
        var small = control.text_options()
        small.role = .BodySmall
        small.wrap = .None
        let (context, context_error) = control.colored_text(a, 0u64, detail, t, small, style.color(t.tokens, .OnSurfaceVariant))
        if context_error != ok { ret (zero, context_error) }
        detail_parts[1usize] = context
        var detail_style = style.defaults()
        detail_style.width = style.Length { Percent: 100.0 }
        parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: 12.0 }, detail_style, detail_parts[0usize..2usize])
        part_count = 2usize
    }
    var panel = control.surface_style(t, control.surface_options(t))
    panel.width = style.Length { Px: inner_width + 32.0 }
    panel.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 16.0 }, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 16.0 } }
    panel.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) }
    panel.border.width = 0.0
    panel.radius = t.tokens.radii.xl
    panel.shadow = style.Shadow { offset: geometry.Point { x: 0.0, y: 3.0 }, color: paint.rgba(0.0, 0.0, 0.0, t.tokens.elevation[3usize]) }
    let content = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 12.0 }, panel, parts[0usize..part_count])
    let (scoped, scoped_error) = choice_scope(a, key + 1u64, items.len, active, true, activate, pick, close, dismiss, content)
    if scoped_error != ok { ret (zero, scoped_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = scoped
    var sem: widget.Semantics = zero
    sem.role = 23u8
    sem.label = label
    sem.states = accessibility.STATE_MODAL
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize])
    let lifted = widget.overlay(key, widget.Overlay { anchor: 0u64, placement: .Center, offset: zero, modal: true, dismiss: *dismiss }, style.defaults(), framed[0usize..1usize])
    let (made, made_error) = overlay.with_scrim(a, t, lifted)
    ret (made, made_error)
}

fn window_switcher_grid_held(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const SwitcherItem, active: usize, hold: *const SwitcherHold, activate: widget.Change[usize], pick: widget.Change[usize], close: widget.Change[usize], dismiss: *const widget.Submit) -> (widget.Node, err) {
    let open = items.len > 1usize && switcher_hold_open(hold, t.runtime)
    let (made, made_error) = window_switcher_grid_closable(a, key, t, label, items, active, open, activate, pick, close, dismiss)
    ret (made, made_error)
}

type PaletteMode = enum u8 { Commands, Files, Symbols, Line }
type PaletteCommand = struct { name: str, group: str, category: str, match_start: usize, match_end: usize, shortcut: str, unavailable: str, recency: u32 }

type PaletteRanked = struct { command: PaletteCommand, source: usize, score: u64 }
type PaletteIndexMap = struct { indices: []const usize, change: widget.Change[usize] }

fn palette_mapped_change(ctx: *void, index: usize) -> err {
    let mapped = mem.cast[*PaletteIndexMap](ctx)
    if index >= mapped.indices.len { ret ok }
    ret widget.fire_change[usize](mapped.change, mapped.indices[index])
}

fn palette_prefix(haystack: str, needle: str) -> bool {
    ret needle.len > 0usize && needle.len <= haystack.len && string.compare(haystack[0usize..needle.len], needle) == 0i32
}

fn palette_word_match(haystack: str, needle: str) -> (usize, bool) {
    if needle.len == 0usize || needle.len > haystack.len { ret (0usize, false) }
    var i = 0usize
    while i + needle.len <= haystack.len {
        let boundary = i == 0usize || haystack[i - 1usize] == 32u8 || haystack[i - 1usize] == 45u8 || haystack[i - 1usize] == 95u8 || haystack[i - 1usize] == 47u8 || haystack[i - 1usize] == 58u8
        if boundary && string.compare(haystack[i..i + needle.len], needle) == 0i32 { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn palette_subsequence(haystack: str, needle: str, name_offset: usize) -> (usize, bool) {
    if needle.len == 0usize { ret (0usize, true) }
    var q = 0usize
    var first_name = haystack.len
    var i = 0usize
    while i < haystack.len && q < needle.len {
        if haystack[i] == needle[q] {
            if i >= name_offset && first_name == haystack.len { first_name = i - name_offset }
            q += 1usize
        }
        i += 1usize
    }
    if q != needle.len { ret (0usize, false) }
    if first_name == haystack.len { first_name = 0usize }
    ret (first_name, true)
}

fn palette_before(a: PaletteRanked, b: PaletteRanked) -> bool {
    if a.score != b.score { ret a.score > b.score }
    let names = string.compare(a.command.name, b.command.name)
    if names != 0i32 { ret names < 0i32 }
    ret a.source < b.source
}

// ponytail: insertion sort is enough for command lists; replace it if palettes
// with thousands of commands make ranking measurable.
fn palette_rank(a: *mem.Arena, commands: []const PaletteCommand, query: str) -> ([]PaletteRanked, err) {
    var none: []PaletteRanked = zero
    let (folded_query, query_error) = unicode.casefold(a, query)
    if query_error != ok { ret (none, TooLarge) }
    let (ranked, ranked_error) = mem.alloc[PaletteRanked](a, commands.len)
    if ranked_error != ok { ret (none, TooLarge) }
    var count = 0usize
    var i = 0usize
    while i < commands.len {
        let (folded_name, name_error) = unicode.casefold(a, commands[i].name)
        if name_error != ok { ret (none, TooLarge) }
        let (folded_category, category_error) = unicode.casefold(a, commands[i].category)
        if category_error != ok { ret (none, TooLarge) }
        var tier = 0u64
        var match_start = 0usize
        var match_end = 0usize
        if folded_query.len == 0usize {
            tier = 1u64
        } else if palette_prefix(folded_name, folded_query) || palette_prefix(folded_category, folded_query) {
            tier = 4u64
            if palette_prefix(folded_name, folded_query) { match_end = folded_query.len }
        } else {
            let (name_word, has_name_word) = palette_word_match(folded_name, folded_query)
            let (_, has_category_word) = palette_word_match(folded_category, folded_query)
            if has_name_word || has_category_word {
                tier = 3u64
                if has_name_word {
                    match_start = name_word
                    match_end = name_word + folded_query.len
                }
            } else {
                let (category_gap, category_gap_error) = string.concat(a, folded_category, " ")
                if category_gap_error != ok { ret (none, TooLarge) }
                let (searchable, searchable_error) = string.concat(a, category_gap, folded_name)
                if searchable_error != ok { ret (none, TooLarge) }
                let (name_hit, has_subsequence) = palette_subsequence(searchable, folded_query, category_gap.len)
                if has_subsequence {
                    tier = 2u64
                    if name_hit < folded_name.len {
                        match_start = name_hit
                        match_end = name_hit + 1usize
                    }
                }
            }
        }
        if tier > 0u64 {
            var command = commands[i]
            command.match_start = match_start
            command.match_end = match_end
            ranked[count] = PaletteRanked { command: command, source: i, score: tier * 1000000u64 + u64(commands[i].recency) }
            count += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < count {
        var j = i
        while j > 0usize && palette_before(ranked[j], ranked[j - 1usize]) {
            let swap = ranked[j - 1usize]
            ranked[j - 1usize] = ranked[j]
            ranked[j] = swap
            j -= 1usize
        }
        i += 1usize
    }
    ret (ranked[0usize..count], ok)
}

fn palette_mode_prefix(mode: PaletteMode) -> str {
    if mode == .Commands { ret ">" }
    if mode == .Symbols { ret "@" }
    if mode == .Line { ret ":" }
    ret ""
}

fn palette_mode_placeholder(mode: PaletteMode) -> str {
    if mode == .Files { ret "Search files by name" }
    if mode == .Symbols { ret "Go to symbol" }
    if mode == .Line { ret "Go to line" }
    ret "Type a command"
}

type PaletteTyped = struct { typed: widget.Change[str], activate: widget.Change[usize] }

fn palette_typed_fire(ctx: *void, value: str) -> err {
    let typed_state = mem.cast[*PaletteTyped](ctx)
    let reset_error = widget.fire_change[usize](typed_state.activate, 0usize)
    if reset_error != ok { ret reset_error }
    ret widget.fire_change[str](typed_state.typed, value)
}

fn palette_grouped_rows(a: *mem.Arena, t: *const control.Theme, rows: []widget.Node, groups: []const str) -> ([]widget.Node, err) {
    var none: []widget.Node = zero
    let (grouped, grouped_error) = mem.alloc[widget.Node](a, rows.len * 2usize)
    if grouped_error != ok { ret (none, TooLarge) }
    var n = 0usize
    var i = 0usize
    while i < rows.len {
        let changed = i == 0usize || string.compare(groups[i], groups[i - 1usize]) != 0i32
        if groups[i].len > 0usize && changed {
            var heading = control.text_options()
            heading.role = .LabelMedium
            heading.wrap = .None
            let (said, said_error) = control.colored_text(a, 0u64, groups[i], t, heading, style.color(t.tokens, .OnSurfaceVariant))
            if said_error != ok { ret (none, said_error) }
            let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
            if body_error != ok { ret (none, TooLarge) }
            body[0usize] = said
            var inset = style.defaults()
            inset.width = style.Length { Percent: 100.0 }
            inset.padding = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 8.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 4.0 } }
            let padded = widget.box(0u64, inset, body[0usize..1usize])
            let (semantic_body, semantic_body_error) = mem.alloc[widget.Node](a, 1usize)
            if semantic_body_error != ok { ret (none, TooLarge) }
            semantic_body[0usize] = padded
            var sem: widget.Semantics = zero
            sem.role = 2u8
            sem.label = groups[i]
            grouped[n] = widget.semantics(0u64, sem, style.defaults(), semantic_body[0usize..1usize])
            n += 1usize
        }
        grouped[n] = rows[i]
        n += 1usize
        i += 1usize
    }
    ret (grouped[0usize..n], ok)
}

// v2 (D978, docs/ux/components/CommandPalette): the palette's field, 56 tall and
// the panel's width, 16 at its sides and 12 between its parts: a 24 `search`
// glyph in `on-surface-variant`, the mode prefix in `primary`, the query in
// `body-large` `on-surface` (keyed
// `key`) over the placeholder in `on-surface-variant`, and an "Esc" hint in
// `body-small` `on-surface-variant` at the end.
fn palette_field(a: *mem.Arena, key: widget.Key, t: *const control.Theme, buffer: []u8, len: usize, typed: widget.Change[str], mode: PaletteMode) -> (widget.Node, err) {
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let (query_look, look_error) = control.text_style(a, t, .BodyLarge)
    if look_error != ok { ret (zero, look_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 6usize)
    if layers_error != ok { ret (zero, TooLarge) }
    var at = 0usize
    if len == 0usize {
        var hint = control.text_options()
        hint.role = .BodyLarge
        hint.wrap = .None
        let (hint_node, hint_error) = control.colored_text(a, 0u64, palette_mode_placeholder(mode), t, hint, muted)
        if hint_error != ok { ret (zero, hint_error) }
        layers[at] = hint_node
        at += 1usize
    }
    var editor_style = style.defaults()
    editor_style.width = style.Length { Percent: 100.0 }
    editor_style.min_height = style.Length { Px: style.text_style(t.tokens, .BodyLarge).line_height }
    layers[at] = widget.edit(key, widget.Edit { buffer: buffer, len: len, style: query_look, color: style.color(t.tokens, .OnSurface), selection: style.color(t.tokens, .TextSelection), change: typed, submit: zero, enabled: true, read_only: false, multiline: false, secret: false, marked: zero, caret: zero, untabbed: false, ringed: false }, editor_style)
    at += 1usize
    let (lens, lens_error) = control.icon_square(a, muted, .Search, 24.0)
    if lens_error != ok { ret (zero, lens_error) }
    layers[2usize] = lens
    var field_end = 3usize
    let prefix = palette_mode_prefix(mode)
    if prefix.len > 0usize {
        var prefix_options = control.text_options()
        prefix_options.role = .BodyLarge
        prefix_options.wrap = .None
        let (prefix_node, prefix_error) = control.colored_text(a, 0u64, prefix, t, prefix_options, style.color(t.tokens, .Primary))
        if prefix_error != ok { ret (zero, prefix_error) }
        layers[field_end] = prefix_node
        field_end += 1usize
    }
    var grow = style.defaults()
    grow.width = style.Length { Flex: 1.0 }
    layers[field_end] = widget.stack(0u64, grow, layers[0usize..at])
    field_end += 1usize
    var small = control.text_options()
    small.role = .BodySmall
    small.wrap = .None
    let (esc, esc_error) = control.colored_text(a, 0u64, "Esc", t, small, muted)
    if esc_error != ok { ret (zero, esc_error) }
    layers[field_end] = esc
    field_end += 1usize
    var bar = style.defaults()
    bar.width = style.Length { Percent: 100.0 }
    bar.height = style.Length { Px: 56.0 }
    bar.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 0.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, bar, layers[2usize..field_end]), ok)
}

fn palette_compact_field(a: *mem.Arena, key: widget.Key, t: *const control.Theme, buffer: []u8, len: usize, typed: widget.Change[str], mode: PaletteMode, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let (query_look, look_error) = control.text_style(a, t, .BodyMedium)
    if look_error != ok { ret (zero, look_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (back, back_error) = control.glyph_button(a, key + 200u64, t, .ArrowBack, "Back", dismiss, 32.0, 24.0)
    if back_error != ok { ret (zero, back_error) }
    parts[0usize] = back
    var at = 0usize
    if len == 0usize {
        var hint = control.text_options()
        hint.role = .BodyMedium
        hint.wrap = .None
        let (hint_node, hint_error) = control.colored_text(a, 0u64, palette_mode_placeholder(mode), t, hint, muted)
        if hint_error != ok { ret (zero, hint_error) }
        parts[2usize + at] = hint_node
        at += 1usize
    }
    var editor_style = style.defaults()
    editor_style.width = style.Length { Percent: 100.0 }
    editor_style.min_height = style.Length { Px: style.text_style(t.tokens, .BodyMedium).line_height }
    parts[2usize + at] = widget.edit(key, widget.Edit { buffer: buffer, len: len, style: query_look, color: style.color(t.tokens, .OnSurface), selection: style.color(t.tokens, .TextSelection), change: typed, submit: zero, enabled: true, read_only: false, multiline: false, secret: false, marked: zero, caret: zero, untabbed: false, ringed: false }, editor_style)
    at += 1usize
    var grow = style.defaults()
    grow.width = style.Length { Flex: 1.0 }
    parts[1usize] = widget.stack(0u64, grow, parts[2usize..2usize + at])
    var bar = style.defaults()
    bar.height = style.Length { Px: 48.0 }
    bar.margin = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 8.0 }, right: style.Length { Px: 8.0 }, bottom: style.Length { Px: 8.0 } }
    bar.padding = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    bar.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) }
    bar.radius = t.tokens.radii.full
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, bar, parts[0usize..2usize]), ok)
}

// A command palette: a search field (keyed `key + 2`, over the caller's buffer,
// typed text reaching `typed` for the caller to filter by) over the matching
// commands' names in a modal panel in the middle of the window while `open`, the
// active one filled; Up and Down move it through `activate`, Enter and a tap run
// one through `run`, Escape and a press outside fire `dismiss`. The rows are keyed
// `key + 3 + index`, the scope `key + 1`.
// v2 (D978, docs/ux/components/CommandPalette): over a `scrim` at 32%, the panel
// of `centred_modal` top-centred 64 down; `palette_field`, a 1px `outline-variant`
// divider, the results 4 above, 8 at the sides and 8 below (the field has no
// Clear button now, so no key collides with the rows'); with no match, an empty
// state 24 above and below and 16 at the sides: "No matching commands" in
// `title-small` `on-surface` over "Check the spelling or try fewer words." in
// `body-medium` `on-surface-variant`, centred. The footer is 32 tall, 16 at the
// sides, below a 1px `outline-variant` line: "Up and Down to move, Enter to run"
// in `body-small` `on-surface-variant`.
// command_palette_ranked owns matching while the source-compatible wrappers
// keep caller filtering; its adaptive form uses the compact full-screen layout.
fn command_palette(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], commands: []const str, active: usize, open: bool, activate: widget.Change[usize], run: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = command_palette_mode(a, key, t, label, buffer, len, typed, .Commands, commands, active, open, activate, run, dismiss, width)
    ret (made, made_error)
}

fn command_palette_mode(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], mode: PaletteMode, commands: []const str, active: usize, open: bool, activate: widget.Change[usize], run: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    var no_text: []const str = zero
    var no_matches: []const usize = zero
    let (made, made_error) = command_palette_of(a, key, t, label, buffer, len, typed, mode, commands, no_text, no_text, no_matches, no_matches, no_text, no_text, active, false, false, open, activate, run, dismiss, width)
    ret (made, made_error)
}

fn command_palette_grouped(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], mode: PaletteMode, commands: []const PaletteCommand, active: usize, open: bool, activate: widget.Change[usize], run: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = command_palette_grouped_busy(a, key, t, label, buffer, len, typed, mode, commands, active, false, open, activate, run, dismiss, width)
    ret (made, made_error)
}

fn command_palette_grouped_busy(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], mode: PaletteMode, commands: []const PaletteCommand, active: usize, busy: bool, open: bool, activate: widget.Change[usize], run: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = command_palette_grouped_form(a, key, t, label, buffer, len, typed, mode, commands, active, busy, false, open, activate, run, dismiss, width)
    ret (made, made_error)
}

fn command_palette_grouped_form(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], mode: PaletteMode, commands: []const PaletteCommand, active: usize, busy: bool, compact: bool, open: bool, activate: widget.Change[usize], run: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let (names, names_error) = mem.alloc[str](a, commands.len)
    if names_error != ok { ret (zero, TooLarge) }
    let (groups, groups_error) = mem.alloc[str](a, commands.len)
    if groups_error != ok { ret (zero, TooLarge) }
    let (categories, categories_error) = mem.alloc[str](a, commands.len)
    if categories_error != ok { ret (zero, TooLarge) }
    let (match_starts, match_starts_error) = mem.alloc[usize](a, commands.len)
    if match_starts_error != ok { ret (zero, TooLarge) }
    let (match_ends, match_ends_error) = mem.alloc[usize](a, commands.len)
    if match_ends_error != ok { ret (zero, TooLarge) }
    let (shortcuts, shortcuts_error) = mem.alloc[str](a, commands.len)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    let (unavailable, unavailable_error) = mem.alloc[str](a, commands.len)
    if unavailable_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < commands.len {
        names[i] = commands[i].name
        groups[i] = commands[i].group
        categories[i] = commands[i].category
        match_starts[i] = commands[i].match_start
        match_ends[i] = commands[i].match_end
        shortcuts[i] = commands[i].shortcut
        unavailable[i] = commands[i].unavailable
        i += 1usize
    }
    let (made, made_error) = command_palette_of(a, key, t, label, buffer, len, typed, mode, names, groups, categories, match_starts, match_ends, shortcuts, unavailable, active, busy, compact, open, activate, run, dismiss, width)
    ret (made, made_error)
}

fn command_palette_ranked(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], mode: PaletteMode, commands: []const PaletteCommand, active: usize, busy: bool, open: bool, activate: widget.Change[usize], run: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    let (made, made_error) = command_palette_ranked_form(a, key, t, label, buffer, len, typed, mode, commands, active, busy, false, open, activate, run, dismiss, width)
    ret (made, made_error)
}

fn command_palette_ranked_adaptive(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], mode: PaletteMode, commands: []const PaletteCommand, active: usize, busy: bool, open: bool, activate: widget.Change[usize], run: widget.Change[usize], dismiss: *const widget.Submit, width: f32, size: style.SizeClass) -> (widget.Node, err) {
    let (made, made_error) = command_palette_ranked_form(a, key, t, label, buffer, len, typed, mode, commands, active, busy, size == .Compact, open, activate, run, dismiss, width)
    ret (made, made_error)
}

fn command_palette_ranked_form(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], mode: PaletteMode, commands: []const PaletteCommand, active: usize, busy: bool, compact: bool, open: bool, activate: widget.Change[usize], run: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    var query_len = len
    if query_len > buffer.len { query_len = buffer.len }
    let (ranked, ranked_error) = palette_rank(a, commands, buffer[0usize..query_len])
    if ranked_error != ok { ret (zero, ranked_error) }
    let (shown, shown_error) = mem.alloc[PaletteCommand](a, ranked.len)
    if shown_error != ok { ret (zero, TooLarge) }
    let (indices, indices_error) = mem.alloc[usize](a, ranked.len)
    if indices_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < ranked.len {
        shown[i] = ranked[i].command
        indices[i] = ranked[i].source
        i += 1usize
    }
    let (maps, maps_error) = mem.alloc[PaletteIndexMap](a, 1usize)
    if maps_error != ok { ret (zero, TooLarge) }
    maps[0usize] = PaletteIndexMap { indices: indices, change: run }
    let mapped_run = widget.Change[usize] { ctx: mem.cast[*void](&maps[0usize]), invoke: palette_mapped_change }
    let (made, made_error) = command_palette_grouped_form(a, key, t, label, buffer, query_len, typed, mode, shown, active, busy, compact, open, activate, mapped_run, dismiss, width)
    ret (made, made_error)
}

fn command_palette_of(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], mode: PaletteMode, commands: []const str, groups: []const str, categories: []const str, match_starts: []const usize, match_ends: []const usize, shortcuts: []const str, unavailable: []const str, active: usize, busy: bool, compact: bool, open: bool, activate: widget.Change[usize], run: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (relays, relays_error) = mem.alloc[PaletteTyped](a, 1usize)
    if relays_error != ok { ret (zero, TooLarge) }
    relays[0usize] = PaletteTyped { typed: typed, activate: activate }
    let relayed = widget.Change[str] { ctx: mem.cast[*void](&relays[0usize]), invoke: palette_typed_fire }
    var field: widget.Node = zero
    var field_error: err = ok
    if compact {
        let (made_field, made_field_error) = palette_compact_field(a, key + 2u64, t, buffer, len, relayed, mode, dismiss)
        field = made_field
        field_error = made_field_error
    } else {
        let (made_field, made_field_error) = palette_field(a, key + 2u64, t, buffer, len, relayed, mode)
        field = made_field
        field_error = made_field_error
    }
    if field_error != ok { ret (zero, field_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 8usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (field_body, field_body_error) = mem.alloc[widget.Node](a, 1usize)
    if field_body_error != ok { ret (zero, TooLarge) }
    field_body[0usize] = field
    var combo_sem: widget.Semantics = zero
    combo_sem.role = accessibility.ROLE_COMBOBOX
    combo_sem.label = label
    combo_sem.states = accessibility.STATE_EXPANDED
    if active < commands.len { combo_sem.active = key + 3u64 + u64(active) }
    parts[0usize] = widget.semantics(0u64, combo_sem, style.defaults(), field_body[0usize..1usize])
    if busy {
        var bar_width = width
        if compact {
            bar_width = 360.0
            if mem.address_of(t.runtime) != 0usize { bar_width = widget.surface_size(t.runtime).width }
        }
        var progress_options = control.progress_options()
        progress_options.full_bleed = true
        let (progress, progress_error) = control.progress_bar_of(a, key + 100u64, t, "Loading commands", 0.0, true, bar_width, progress_options)
        if progress_error != ok { ret (zero, progress_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (zero, TooLarge) }
        held[0usize] = progress
        var clipped = control.sized_style(0.0, 2.0)
        clipped.width = style.Length { Percent: 100.0 }
        clipped.overflow = .Clip
        parts[1usize] = widget.box(0u64, clipped, held[0usize..1usize])
    } else {
        let (rule, rule_error) = control.divider(a, 0u64, t, .Horizontal, 0.0)
        if rule_error != ok { ret (zero, rule_error) }
        parts[1usize] = rule
    }
    var results = style.defaults()
    if !compact { results.padding = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 8.0 }, bottom: style.Length { Px: 8.0 } } }
    if commands.len > 0usize {
        let (plain_rows, rows_error) = choice_rows(a, key + 3u64, t, commands, categories, match_starts, match_ends, shortcuts, unavailable, active, compact, run)
        if rows_error != ok { ret (zero, rows_error) }
        var rows = plain_rows
        if groups.len == commands.len {
            let (grouped, grouped_error) = palette_grouped_rows(a, t, rows, groups)
            if grouped_error != ok { ret (zero, grouped_error) }
            rows = grouped
        }
        parts[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, results, rows)
    } else {
        var said = control.text_options()
        said.role = .TitleSmall
        said.align = .Center
        let (statement, statement_error) = control.colored_text(a, 0u64, "No matching commands", t, said, style.color(t.tokens, .OnSurface))
        if statement_error != ok { ret (zero, statement_error) }
        said.role = .BodyMedium
        let (advice, advice_error) = control.colored_text(a, 0u64, "Check the spelling or try fewer words.", t, said, style.color(t.tokens, .OnSurfaceVariant))
        if advice_error != ok { ret (zero, advice_error) }
        parts[5usize] = statement
        parts[6usize] = advice
        var empty = style.defaults()
        empty.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 24.0 }, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 24.0 } }
        parts[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Center, gap: 4.0 }, empty, parts[5usize..7usize])
    }
    let (result_body, result_body_error) = mem.alloc[widget.Node](a, 1usize)
    if result_body_error != ok { ret (zero, TooLarge) }
    result_body[0usize] = parts[2usize]
    var result_sem: widget.Semantics = zero
    result_sem.role = accessibility.ROLE_LISTBOX
    result_sem.label = label
    result_sem.row_count = u32(commands.len)
    if active < commands.len { result_sem.active = key + 3u64 + u64(active) }
    parts[2usize] = widget.semantics(0u64, result_sem, style.defaults(), result_body[0usize..1usize])
    var part_count = 3usize
    if !compact {
        var foot = style.defaults()
        foot.width = style.Length { Percent: 100.0 }
        foot.height = style.Length { Px: 32.0 }
        foot.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 0.0 } }
        var small = control.text_options()
        small.role = .BodySmall
        small.wrap = .None
        let (hints, hints_error) = control.colored_text(a, 0u64, "Up and Down to move, Enter to run", t, small, style.color(t.tokens, .OnSurfaceVariant))
        if hints_error != ok { ret (zero, hints_error) }
        parts[7usize] = hints
        let (edge, edge_error) = control.divider(a, 0u64, t, .Horizontal, 0.0)
        if edge_error != ok { ret (zero, edge_error) }
        parts[3usize] = edge
        parts[4usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, foot, parts[7usize..8usize])
        part_count = 5usize
    }
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), parts[0usize..part_count])
    let runnable = active < commands.len && (unavailable.len != commands.len || unavailable[active].len == 0usize)
    let (scoped, scoped_error) = choice_scope(a, key + 1u64, commands.len, active, runnable, activate, run, zero, dismiss, column)
    if scoped_error != ok { ret (zero, scoped_error) }
    if compact {
        let (made, made_error) = compact_modal(a, key, t, label, scoped, dismiss)
        ret (made, made_error)
    }
    let (made, made_error) = centred_modal(a, key, t, label, scoped, dismiss, width, true)
    ret (made, made_error)
}

type SwitcherRanked = struct { item: SwitcherItem, source: usize, score: u64 }

fn switcher_match_rank(haystack: str, needle: str, base: u64) -> u64 {
    if palette_prefix(haystack, needle) { ret base + 2u64 }
    let (_, word) = palette_word_match(haystack, needle)
    if word { ret base + 1u64 }
    let (_, subsequence) = palette_subsequence(haystack, needle, 0usize)
    if subsequence { ret base }
    ret 0u64
}

fn switcher_rank(a: *mem.Arena, items: []const SwitcherItem, query: str) -> ([]SwitcherRanked, err) {
    var none: []SwitcherRanked = zero
    let (ranked, ranked_error) = mem.alloc[SwitcherRanked](a, items.len)
    if ranked_error != ok { ret (none, TooLarge) }
    let (folded_query, query_error) = unicode.casefold(a, query)
    if query_error != ok { ret (none, TooLarge) }
    var count = 0usize
    var i = 0usize
    while i < items.len {
        var score = 1u64
        if folded_query.len > 0usize {
            let (name, name_error) = unicode.casefold(a, items[i].name)
            if name_error != ok { ret (none, TooLarge) }
            score = switcher_match_rank(name, folded_query, 4u64)
            if score == 0u64 {
                let (context, context_error) = unicode.casefold(a, items[i].context)
                if context_error != ok { ret (none, TooLarge) }
                score = switcher_match_rank(context, folded_query, 1u64)
            }
        }
        if score > 0u64 {
            ranked[count] = SwitcherRanked { item: items[i], source: i, score: score }
            count += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < count {
        var j = i
        while j > 0usize && (ranked[j].score > ranked[j - 1usize].score || (ranked[j].score == ranked[j - 1usize].score && ranked[j].source < ranked[j - 1usize].source)) {
            let swap = ranked[j - 1usize]
            ranked[j - 1usize] = ranked[j]
            ranked[j] = swap
            j -= 1usize
        }
        i += 1usize
    }
    ret (ranked[0usize..count], ok)
}

fn switcher_filter_field(a: *mem.Arena, key: widget.Key, t: *const control.Theme, buffer: []u8, len: usize, typed: widget.Change[str]) -> (widget.Node, err) {
    let muted = style.color(t.tokens, .OnSurfaceVariant)
    let (text_look, text_error) = control.text_style(a, t, .BodyLarge)
    if text_error != ok { ret (zero, text_error) }
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, TooLarge) }
    var at = 0usize
    if len == 0usize {
        var hint = control.text_options()
        hint.role = .BodyLarge
        hint.wrap = .None
        let (placeholder, placeholder_error) = control.colored_text(a, 0u64, "Filter open windows", t, hint, muted)
        if placeholder_error != ok { ret (zero, placeholder_error) }
        layers[at] = placeholder
        at += 1usize
    }
    var editor_style = style.defaults()
    editor_style.width = style.Length { Percent: 100.0 }
    editor_style.min_height = style.Length { Px: style.text_style(t.tokens, .BodyLarge).line_height }
    layers[at] = widget.edit(key, widget.Edit { buffer: buffer, len: len, style: text_look, color: style.color(t.tokens, .OnSurface), selection: style.color(t.tokens, .TextSelection), change: typed, submit: zero, enabled: true, read_only: false, multiline: false, secret: false, marked: zero, caret: zero, untabbed: false, ringed: false }, editor_style)
    at += 1usize
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (search, search_error) = control.icon_square(a, muted, .Search, 24.0)
    if search_error != ok { ret (zero, search_error) }
    parts[0usize] = search
    var grow = style.defaults()
    grow.width = style.Length { Flex: 1.0 }
    parts[1usize] = widget.stack(0u64, grow, layers[0usize..at])
    var bar = style.defaults()
    bar.width = style.Length { Percent: 100.0 }
    bar.height = style.Length { Px: 48.0 }
    bar.padding = style.EdgeLengths { left: style.Length { Px: 12.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 12.0 }, bottom: style.Length { Px: 0.0 } }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 12.0 }, bar, parts[0usize..2usize]), ok)
}

fn switcher_list_rows(a: *mem.Arena, first: widget.Key, t: *const control.Theme, items: []const SwitcherItem, active: usize, pick: widget.Change[usize]) -> ([]widget.Node, err) {
    var none: []widget.Node = zero
    let (rows, rows_error) = mem.alloc[widget.Node](a, items.len)
    if rows_error != ok { ret (none, TooLarge) }
    let (picks, picks_error) = mem.alloc[IndexPick](a, items.len)
    if picks_error != ok { ret (none, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, items.len)
    if actions_error != ok { ret (none, TooLarge) }
    var i = 0usize
    while i < items.len {
        picks[i] = IndexPick { index: i, pick: pick }
        actions[i] = widget.Submit { ctx: mem.cast[*void](&picks[i]), invoke: index_pick_fire }
        let row_key = first + u64(i)
        var ink = style.color(t.tokens, .OnSurface)
        var fill = paint.rgba(0.0, 0.0, 0.0, 0.0)
        if i == active {
            ink = style.color(t.tokens, .OnSecondaryContainer)
            fill = style.color(t.tokens, .SecondaryContainer)
        }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
        if parts_error != ok { ret (none, TooLarge) }
        let (icon, icon_error) = control.icon_square(a, ink, .Picture, 18.0)
        if icon_error != ok { ret (none, icon_error) }
        parts[0usize] = icon
        var words = control.text_options()
        words.role = .BodyMedium
        words.wrap = .None
        words.ellipsis = "…"
        let (name, name_error) = control.colored_text(a, 0u64, items[i].name, t, words, ink)
        if name_error != ok { ret (none, name_error) }
        let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
        if held_error != ok { ret (none, TooLarge) }
        held[0usize] = name
        var grow = style.defaults()
        grow.width = style.Length { Flex: 1.0 }
        parts[1usize] = widget.box(0u64, grow, held[0usize..1usize])
        let (detail, detail_error) = switcher_item_detail(a, items[i])
        if detail_error != ok { ret (none, detail_error) }
        words.role = .BodySmall
        let (context, context_error) = control.colored_text(a, 0u64, detail, t, words, style.color(t.tokens, .OnSurfaceVariant))
        if context_error != ok { ret (none, context_error) }
        parts[2usize] = context
        var row_style = style.defaults()
        row_style.width = style.Length { Percent: 100.0 }
        row_style.height = style.Length { Px: 40.0 }
        let content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, row_style, parts[0usize..3usize])
        var look = style.resolve(t.tokens, .Plain, control.control_state(t, row_key, true, false))
        look.background = style.layer(fill, ink, control.state_opacity(t, control.control_state(t, row_key, true, false)))
        look.foreground = ink
        look.border_width = 0.0
        look.radius = t.tokens.radii.sm
        look.custom_padding = true
        look.padding = 12.0
        look.padding_y = 0.0
        look.min_height = 40.0
        let (semantic_label, semantic_label_error) = switcher_item_label(a, items[i])
        if semantic_label_error != ok { ret (none, semantic_label_error) }
        let (pressed, pressed_error) = control.pressable(a, row_key, t, 3u8, semantic_label, look, true, false, &actions[i], content)
        if pressed_error != ok { ret (none, pressed_error) }
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (none, TooLarge) }
        body[0usize] = pressed
        var sem: widget.Semantics = zero
        sem.role = accessibility.ROLE_OPTION
        sem.label = semantic_label
        sem.row = u32(i + 1usize)
        sem.row_count = u32(items.len)
        if i == active { sem.states = accessibility.STATE_SELECTED }
        rows[i] = widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize])
        i += 1usize
    }
    ret (rows, ok)
}

fn window_switcher_filterable(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, typed: widget.Change[str], items: []const SwitcherItem, active: usize, open: bool, activate: widget.Change[usize], pick: widget.Change[usize], close: widget.Change[usize], dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var query_len = len
    if query_len > buffer.len { query_len = buffer.len }
    let (ranked, ranked_error) = switcher_rank(a, items, buffer[0usize..query_len])
    if ranked_error != ok { ret (zero, ranked_error) }
    let (shown, shown_error) = mem.alloc[SwitcherItem](a, ranked.len)
    if shown_error != ok { ret (zero, TooLarge) }
    let (indices, indices_error) = mem.alloc[usize](a, ranked.len)
    if indices_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < ranked.len {
        shown[i] = ranked[i].item
        indices[i] = ranked[i].source
        i += 1usize
    }
    let (maps, maps_error) = mem.alloc[PaletteIndexMap](a, 2usize)
    if maps_error != ok { ret (zero, TooLarge) }
    maps[0usize] = PaletteIndexMap { indices: indices, change: pick }
    maps[1usize] = PaletteIndexMap { indices: indices, change: close }
    let mapped_pick = widget.Change[usize] { ctx: mem.cast[*void](&maps[0usize]), invoke: palette_mapped_change }
    var mapped_close: widget.Change[usize] = zero
    if widget.change_set[usize](close.invoke) { mapped_close = widget.Change[usize] { ctx: mem.cast[*void](&maps[1usize]), invoke: palette_mapped_change } }
    let (relays, relays_error) = mem.alloc[PaletteTyped](a, 1usize)
    if relays_error != ok { ret (zero, TooLarge) }
    relays[0usize] = PaletteTyped { typed: typed, activate: activate }
    let relayed = widget.Change[str] { ctx: mem.cast[*void](&relays[0usize]), invoke: palette_typed_fire }
    let (field, field_error) = switcher_filter_field(a, key + 2u64, t, buffer, query_len, relayed)
    if field_error != ok { ret (zero, field_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 5usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (field_body, field_body_error) = mem.alloc[widget.Node](a, 1usize)
    if field_body_error != ok { ret (zero, TooLarge) }
    field_body[0usize] = field
    var combo_sem: widget.Semantics = zero
    combo_sem.role = accessibility.ROLE_COMBOBOX
    combo_sem.label = label
    combo_sem.states = accessibility.STATE_EXPANDED
    if active < shown.len { combo_sem.active = key + 3u64 + u64(active) }
    parts[0usize] = widget.semantics(0u64, combo_sem, style.defaults(), field_body[0usize..1usize])
    let (divider, divider_error) = control.divider(a, 0u64, t, .Horizontal, 0.0)
    if divider_error != ok { ret (zero, divider_error) }
    parts[1usize] = divider
    var inset = style.defaults()
    inset.padding = style.EdgeLengths { left: style.Length { Px: 8.0 }, top: style.Length { Px: 4.0 }, right: style.Length { Px: 8.0 }, bottom: style.Length { Px: 8.0 } }
    if shown.len > 0usize {
        let (rows, rows_error) = switcher_list_rows(a, key + 3u64, t, shown, active, mapped_pick)
        if rows_error != ok { ret (zero, rows_error) }
        parts[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, inset, rows)
    } else {
        var message = control.text_options()
        message.role = .BodyMedium
        message.align = .Center
        let (empty, empty_error) = control.colored_text(a, 0u64, "No matching windows", t, message, style.color(t.tokens, .OnSurfaceVariant))
        if empty_error != ok { ret (zero, empty_error) }
        let (empty_body, empty_body_error) = mem.alloc[widget.Node](a, 1usize)
        if empty_body_error != ok { ret (zero, TooLarge) }
        empty_body[0usize] = empty
        inset.padding = style.EdgeLengths { left: style.Length { Px: 16.0 }, top: style.Length { Px: 24.0 }, right: style.Length { Px: 16.0 }, bottom: style.Length { Px: 24.0 } }
        parts[2usize] = widget.box(0u64, inset, empty_body[0usize..1usize])
    }
    let (result_body, result_body_error) = mem.alloc[widget.Node](a, 1usize)
    if result_body_error != ok { ret (zero, TooLarge) }
    result_body[0usize] = parts[2usize]
    var list_sem: widget.Semantics = zero
    list_sem.role = accessibility.ROLE_LISTBOX
    list_sem.label = label
    list_sem.row_count = u32(shown.len)
    if active < shown.len { list_sem.active = key + 3u64 + u64(active) }
    parts[2usize] = widget.semantics(0u64, list_sem, style.defaults(), result_body[0usize..1usize])
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, style.defaults(), parts[0usize..3usize])
    let (scoped, scoped_error) = choice_scope(a, key + 1u64, shown.len, active, true, activate, mapped_pick, mapped_close, dismiss, column)
    if scoped_error != ok { ret (zero, scoped_error) }
    let (made, made_error) = centred_modal(a, key, t, label, scoped, dismiss, width, false)
    ret (made, made_error)
}
