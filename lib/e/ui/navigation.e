// Application structure over the controls (D828, widget plan P1-15): the bars a
// window or a page is framed by, a stack of destinations pushed and popped, and
// the top-level destinations in the form the width calls for. Navigation state is
// the caller's data -- the titles, the pages, which destination is current -- and
// every control here only places what it is given and fires the caller's actions
// (§3.7 of the proposal).

use e.mem
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.ui.accessibility
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

// The actions as plain buttons in a row, keyed `key + index`.
fn action_row(a: *mem.Arena, key: widget.Key, t: *const control.Theme, items: []const Action, variant: style.ControlVariant) -> (widget.Node, err) {
    let (buttons, buttons_error) = mem.alloc[widget.Node](a, items.len)
    if buttons_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < items.len {
        let (made, made_error) = action_button(a, key + u64(i), t, &items[i], variant)
        if made_error != ok { ret (zero, made_error) }
        buttons[i] = made
        i += 1usize
    }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), buttons[0usize..items.len]), ok)
}

// An app bar: the leading actions (keyed `key + 1 + index`, at most 8), the title
// as a heading of level 1, then the trailing actions (keyed `key + 9 + index`) at
// the end, on the primary colour and `width` wide; a group named by the title.
fn app_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, leading: []const Action, trailing: []const Action, width: f32) -> (widget.Node, err) {
    if leading.len > 8usize { ret (zero, TooLarge) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    let (front, front_error) = action_row(a, key + 1u64, t, leading, .Plain)
    if front_error != ok { ret (zero, front_error) }
    parts[0usize] = front
    var heading = control.text_options()
    heading.role = .Title
    heading.color = .OnPrimary
    heading.wrap = .None
    heading.ellipsis = "..."
    heading.max_lines = 1u32
    let (title_node, title_error) = control.text(a, 0u64, title, t, heading)
    if title_error != ok { ret (zero, title_error) }
    let (titled, titled_error) = mem.alloc[widget.Node](a, 1usize)
    if titled_error != ok { ret (zero, TooLarge) }
    titled[0usize] = title_node
    var title_sem: widget.Semantics = zero
    title_sem.role = 25u8
    title_sem.label = title
    title_sem.level = 1u8
    var grow = style.defaults()
    grow.width = style.Length { Flex: 1.0 }
    parts[1usize] = widget.semantics(0u64, title_sem, grow, titled[0usize..1usize])
    let (back, back_error) = action_row(a, key + 9u64, t, trailing, .Plain)
    if back_error != ok { ret (zero, back_error) }
    parts[2usize] = back
    var bar = style.defaults()
    bar.background = paint.Brush { Solid: style.color(t.tokens, .Primary) }
    bar.width = style.Length { Px: width }
    bar.min_height = style.Length { Px: t.tokens.metrics.control_height + 2.0 * t.tokens.spacing.sm }
    let pad = style.Length { Px: t.tokens.spacing.sm }
    bar.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.sm }, bar, parts[0usize..3usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = title
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// A toolbar: the actions as plain buttons in a row keyed `key + 1 + index` on the
// surface variant; a group named `label`.
fn toolbar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, items: []const Action) -> (widget.Node, err) {
    let (row, row_error) = action_row(a, key + 1u64, t, items, .Plain)
    if row_error != ok { ret (zero, row_error) }
    var options = control.surface_options(t)
    options.background = .SurfaceVariant
    options.padding = t.tokens.spacing.xs
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

// A status bar: the sections as captions spread across `width` on the surface
// variant, the first the message; a polite status in the tree named by it.
fn status_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, sections: []const str, width: f32) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, sections.len)
    if items_error != ok { ret (zero, TooLarge) }
    var caption = control.text_options()
    caption.role = .Caption
    caption.wrap = .None
    var i = 0usize
    while i < sections.len {
        let (piece, piece_error) = control.text(a, 0u64, sections[i], t, caption)
        if piece_error != ok { ret (zero, piece_error) }
        items[i] = piece
        i += 1usize
    }
    var options = control.surface_options(t)
    options.background = .SurfaceVariant
    options.padding = t.tokens.spacing.xs
    var bar = control.surface_style(t, options)
    bar.width = style.Length { Px: width }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: t.tokens.spacing.md }, bar, items[0usize..sections.len])
    var sem: widget.Semantics = zero
    sem.role = 26u8
    if sections.len > 0usize { sem.label = sections[0usize] }
    sem.live = 1u8
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// A navigation stack: the top of `titles` and `pages` (the same length, the last
// the top) under an app bar (keyed `key + 1`) with a back button (keyed `key + 2`)
// while there is somewhere to go back to, firing `pop`; Escape -- and so the
// host's back gesture -- pops the same way. The page is a group (keyed `key + 3`)
// named by its title.
fn navigation_stack(a: *mem.Arena, key: widget.Key, t: *const control.Theme, titles: []const str, pages: []const widget.Node, pop: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if titles.len != pages.len || titles.len == 0usize { ret (zero, TooLarge) }
    let top = titles.len - 1usize
    var leading_count = 0usize
    if top > 0usize { leading_count = 1usize }
    let (leading, leading_error) = mem.alloc[Action](a, leading_count)
    if leading_error != ok { ret (zero, TooLarge) }
    if top > 0usize { leading[0usize] = Action { label: "Back", action: *pop, icon: zero, enabled: true } }
    var none: []const Action = zero
    let (bar, bar_error) = app_bar(a, key + 1u64, t, titles[top], leading[0usize..leading_count], none, width)
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
    parts[1usize] = widget.semantics(key + 3u64, page_sem, grow, body[0usize..1usize])
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize])
    var cancel: widget.Submit = zero
    if top > 0usize { cancel = *pop }
    var shortcuts: []const widget.Shortcut = zero
    ret (widget.scope(key, widget.Scope { traps_focus: false, shortcuts: shortcuts, default_action: zero, cancel_action: cancel, keys: zero }, style.defaults(), column[0usize..1usize]), ok)
}

// The form the top-level destinations take at a width: a bar along the bottom on
// a compact screen, a narrow rail at medium width, a sidebar with room for the
// labels when expanded (§3.7).
type DestinationForm = enum u8 { Bottom, Rail, Sidebar }

fn destination_form(width: f32) -> DestinationForm {
    let size = style.size_class(width)
    if size == .Compact { ret .Bottom }
    if size == .Medium { ret .Rail }
    ret .Sidebar
}

// The destinations as tabs keyed `key + 1 + index`, the current one selected and
// each firing its own pick: a row when the form is the bottom bar, a column
// otherwise -- a hit target wide as a rail, wider as a sidebar. A tab list in the
// tree. The caller places it where the form says and lays the content out beside
// or above it; the width or the height it takes is `extent`.
fn destination_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, form: DestinationForm, extent: f32) -> (widget.Node, err) {
    if picks.len != labels.len { ret (zero, TooLarge) }
    let (items, items_error) = mem.alloc[widget.Node](a, labels.len)
    if items_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < labels.len {
        let chosen = i == selected
        let tab_key = key + 1u64 + u64(i)
        var variant: style.ControlVariant = .Plain
        if chosen { variant = .Filled }
        let look = style.resolve(t.tokens, variant, control.control_state(t, tab_key, true, chosen))
        var caption = control.text_options()
        caption.role = .Label
        caption.wrap = .None
        caption.ellipsis = "..."
        caption.max_lines = 1u32
        let (label_node, label_error) = control.colored_text(a, 0u64, labels[i], t, caption, look.foreground)
        if label_error != ok { ret (zero, label_error) }
        let (tab, tab_error) = control.pressable_states(a, tab_key, t, 19u8, labels[i], look, true, chosen, 0u32, 0u32, 0u64, &picks[i], label_node)
        if tab_error != ok { ret (zero, tab_error) }
        var sized = tab
        if form == .Bottom {
            sized.style.width = style.Length { Flex: 1.0 }
        } else {
            sized.style.width = style.Length { Percent: 100.0 }
        }
        items[i] = sized
        i += 1usize
    }
    var options = control.surface_options(t)
    options.background = .SurfaceVariant
    options.padding = t.tokens.spacing.xs
    var bar = control.surface_style(t, options)
    var axis: ui_layout.Axis = .Vertical
    if form == .Bottom { axis = .Horizontal }
    bar.width = style.Length { Px: extent }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: axis, main: .Start, cross: .Stretch, gap: t.tokens.spacing.xs }, bar, items[0usize..labels.len])
    var sem: widget.Semantics = zero
    sem.role = 20u8
    sem.label = "Navigation"
    if form == .Bottom {
        sem.column_count = u32(labels.len)
    } else {
        sem.row_count = u32(labels.len)
    }
    ret (widget.semantics(key, sem, style.defaults(), body[0usize..1usize]), ok)
}

// --------------------------------------------------- adaptive navigation (D840, P2-08)

// A menu of a menu bar: its title and its commands.
type MenuBarItem = struct { label: str, items: []const overlay.MenuItem }

// A menu bar: the menus' titles as D827's menu buttons in a row, sixteen keys
// apart from `key + 1` (a title, its menu and up to fourteen items each), the one
// at `open` open (an index past the end for none), each firing its toggle; on the
// surface variant, a group in the tree named `label`.
fn menu_bar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, menus: []const MenuBarItem, open: usize, toggles: []const widget.Submit) -> (widget.Node, err) {
    if toggles.len != menus.len { ret (zero, TooLarge) }
    let (heads, heads_error) = mem.alloc[widget.Node](a, menus.len)
    if heads_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < menus.len {
        let (head, head_error) = overlay.menu_button(a, key + 1u64 + 16u64 * u64(i), t, menus[i].label, menus[i].items, i == open, &toggles[i])
        if head_error != ok { ret (zero, head_error) }
        heads[i] = head
        i += 1usize
    }
    var options = control.surface_options(t)
    options.background = .SurfaceVariant
    options.padding = t.tokens.spacing.xs
    var bar = control.surface_style(t, options)
    bar.width = style.Length { Percent: 100.0 }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, bar, heads[0usize..menus.len])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// A context menu: D827's menu (keyed `key`, items `key + 1 + index`) below
// `anchor` while `open`; the caller opens it from the secondary press or the
// keyboard's menu key it handles itself, and `dismiss` closes it.
fn context_menu(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, label: str, items: []const overlay.MenuItem, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let (made, made_error) = overlay.menu(a, key, t, anchor, label, items, open, dismiss)
    ret (made, made_error)
}

// A navigation split: `primary` and `detail` side by side in D826's split view
// (keyed `key`, the pane `key + 1`) when the width reaches the medium size
// class; compact, one of them alone -- the detail while `showing_detail`, so a
// push shows it and a pop (the caller's) shows the primary again.
fn navigation_split(a: *mem.Arena, key: widget.Key, t: *const control.Theme, primary: widget.Node, detail: widget.Node, showing_detail: bool, position: f32, change: widget.Change[f32], width: f32, height: f32) -> (widget.Node, err) {
    if style.size_class(width) != .Compact {
        let (split, split_error) = control.split_view(a, key, t, .Horizontal, primary, detail, position, 4.0 * t.tokens.spacing.lg, 4.0 * t.tokens.spacing.lg, change, width, height)
        ret (split, split_error)
    }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = primary
    if showing_detail { body[0usize] = detail }
    var page = control.sized_style(width, height)
    page.overflow = .Clip
    var sem: widget.Semantics = zero
    sem.role = 2u8
    let (boxed, boxed_error) = mem.alloc[widget.Node](a, 1usize)
    if boxed_error != ok { ret (zero, TooLarge) }
    boxed[0usize] = widget.box(key, page, body[0usize..1usize])
    ret (widget.semantics(0u64, sem, style.defaults(), boxed[0usize..1usize]), ok)
}

// A navigation drawer: the destinations as a sidebar (keyed `key + 1`, its
// tabs `key + 2 + index`) in a modal overlay (keyed `key`) along the left edge of
// the window while `open`; a press outside or Escape fires `dismiss`; nothing
// while shut.
fn navigation_drawer(a: *mem.Arena, key: widget.Key, t: *const control.Theme, labels: []const str, selected: usize, picks: []const widget.Submit, open: bool, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (bar, bar_error) = destination_bar(a, key + 1u64, t, labels, selected, picks, .Sidebar, width)
    if bar_error != ok { ret (zero, bar_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = bar
    var sheet = control.surface_options(t)
    sheet.elevation = 3u8
    var sheet_style = control.surface_style(t, sheet)
    sheet_style.height = style.Length { Percent: 100.0 }
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
    ret (widget.overlay(key, widget.Overlay { anchor: 0u64, placement: .Left, offset: zero, modal: true, dismiss: *dismiss }, style.defaults(), drawer[0usize..1usize]), ok)
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
// `key + 1 + index` firing its pick, the last the current place as plain text,
// slashes between; a group in the tree named `label`.
fn breadcrumbs(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, names: []const str, picks: []const widget.Submit) -> (widget.Node, err) {
    if picks.len != names.len || names.len == 0usize { ret (zero, TooLarge) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize * names.len - 1usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < names.len {
        if i + 1usize < names.len {
            let (crumb, crumb_error) = control.link(a, key + 1u64 + u64(i), t, names[i], &picks[i])
            if crumb_error != ok { ret (zero, crumb_error) }
            parts[2usize * i] = crumb
            var slash = control.text_options()
            slash.color = .TextMuted
            slash.wrap = .None
            let (between, between_error) = control.text(a, 0u64, "/", t, slash)
            if between_error != ok { ret (zero, between_error) }
            parts[2usize * i + 1usize] = between
        } else {
            var here = control.text_options()
            here.role = .Label
            here.wrap = .None
            let (current, current_error) = control.text(a, 0u64, names[i], t, here)
            if current_error != ok { ret (zero, current_error) }
            parts[2usize * i] = current
        }
        i += 1usize
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..2usize * names.len - 1usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    ret (widget.semantics(key, sem, style.defaults(), row[0usize..1usize]), ok)
}

// ------------------------------------------------------ document workspace (D852, P3-03)

// An open document: its stable key, its title, whether it has unsaved changes,
// whether it is pinned (its tab keeps no close button and stays where it is).
type Document = struct { key: widget.Key, title: str, dirty: bool, pinned: bool }

// A document tab moved from one index to another.
type DocumentMove = struct { from: usize, to: usize }

// A tab's gestures: a tap picks it, a drag begins a move carrying the index
// (D844), a drop of another's tab on it ends one.
type TabGesture = struct { runtime: *widget.Runtime, index: usize, pinned: bool, pick: widget.Change[usize], move: widget.Change[DocumentMove] }

fn tab_gesture(ctx: *void, g: widget.Gesture) -> err {
    let h = mem.cast[*TabGesture](ctx)
    switch g {
    case .Tap as at:
        ret widget.fire_change[usize](h.pick, h.index)
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

// Document tabs: a tab a document keyed `key + 1 + 2 * index`, the current one
// filled and selected, a dirty one's title marked, with a close button (keyed
// `key + 2 + 2 * index`) after the title unless pinned; a tap picks, a close
// reports the index through `close`, a tab dragged onto another reports a
// `DocumentMove` (pinned tabs neither move nor take a drop), and Left and Right
// from a focused tab pick the neighbours. A tab list in the tree named `label`.
fn document_tabs(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, documents: []const Document, current: usize, pick: widget.Change[usize], close: widget.Change[usize], move: widget.Change[DocumentMove]) -> (widget.Node, err) {
    if documents.len > 64usize { ret (zero, TooLarge) }
    let (tabs, tabs_error) = mem.alloc[widget.Node](a, documents.len)
    if tabs_error != ok { ret (zero, TooLarge) }
    let (gestures, gestures_error) = mem.alloc[TabGesture](a, documents.len)
    if gestures_error != ok { ret (zero, TooLarge) }
    let (closes, closes_error) = mem.alloc[TabClose](a, documents.len)
    if closes_error != ok { ret (zero, TooLarge) }
    let (actions, actions_error) = mem.alloc[widget.Submit](a, documents.len)
    if actions_error != ok { ret (zero, TooLarge) }
    let (picks, picks_error) = mem.alloc[TabClose](a, 2usize)
    if picks_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < documents.len {
        let d = documents[i]
        let chosen = i == current
        let tab_key = key + 1u64 + 2u64 * u64(i)
        gestures[i] = TabGesture { runtime: t.runtime, index: i, pinned: d.pinned, pick: pick, move: move }
        closes[i] = TabClose { index: i, close: close }
        actions[i] = widget.Submit { ctx: mem.cast[*void](&closes[i]), invoke: tab_close_fire }
        var variant: style.ControlVariant = .Plain
        if chosen { variant = .Filled }
        let look = style.resolve(t.tokens, variant, control.control_state(t, tab_key, true, chosen))
        // The title, a dot before it while dirty.
        let (title_bytes, title_error) = mem.alloc[u8](a, d.title.len + 2usize)
        if title_error != ok { ret (zero, TooLarge) }
        var n = 0usize
        if d.dirty {
            title_bytes[0usize] = 42u8
            title_bytes[1usize] = 32u8
            n = 2usize
        }
        var k = 0usize
        while k < d.title.len {
            title_bytes[n + k] = d.title[k]
            k += 1usize
        }
        n += d.title.len
        var caption = control.text_options()
        caption.role = .Label
        caption.wrap = .None
        let (title_node, title_node_error) = control.colored_text(a, 0u64, title_bytes[0usize..n], t, caption, look.foreground)
        if title_node_error != ok { ret (zero, title_node_error) }
        var part_count = 1usize
        if !d.pinned { part_count = 2usize }
        let (parts, parts_error) = mem.alloc[widget.Node](a, part_count)
        if parts_error != ok { ret (zero, TooLarge) }
        parts[0usize] = title_node
        if !d.pinned {
            var plain = control.button_options()
            plain.variant = .Plain
            let (closer, closer_error) = control.button(a, key + 2u64 + 2u64 * u64(i), t, "x", &actions[i], plain)
            if closer_error != ok { ret (zero, closer_error) }
            parts[1usize] = closer
        }
        let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
        if body_error != ok { ret (zero, TooLarge) }
        body[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, style.defaults(), parts[0usize..part_count])
        var tab_style = style.defaults()
        tab_style.background = paint.Brush { Solid: look.background }
        tab_style.min_height = style.Length { Px: t.tokens.metrics.control_height }
        let pad_x = style.Length { Px: t.tokens.spacing.sm }
        let pad_y = style.Length { Px: t.tokens.spacing.xs }
        tab_style.padding = style.EdgeLengths { left: pad_x, top: pad_y, right: pad_x, bottom: pad_y }
        let (region, region_error) = mem.alloc[widget.Node](a, 1usize)
        if region_error != ok { ret (zero, TooLarge) }
        region[0usize] = widget.region(tab_key, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&gestures[i]), invoke: tab_gesture }, gestures: 1u8 | 2u8 | 4u8 | 8u8, enabled: true, focusable: true }, tab_style, body[0usize..1usize])
        var sem: widget.Semantics = zero
        sem.role = 19u8
        sem.label = d.title
        sem.column = u32(i + 1usize)
        sem.column_count = u32(documents.len)
        sem.actions = accessibility.ACTION_PRESS
        if chosen { sem.states = accessibility.STATE_SELECTED }
        if d.dirty { sem.hint = "unsaved" }
        tabs[i] = widget.semantics(0u64, sem, style.defaults(), region[0usize..1usize])
        i += 1usize
    }
    // Left and Right pick the neighbours of the current tab.
    let (shortcuts, shortcuts_error) = mem.alloc[widget.Shortcut](a, 2usize)
    if shortcuts_error != ok { ret (zero, TooLarge) }
    var bound = 0usize
    if current > 0usize && current < documents.len {
        picks[0usize] = TabClose { index: current - 1usize, close: pick }
        shortcuts[bound] = widget.Shortcut { key: 37u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&picks[0usize]), invoke: tab_close_fire } }
        bound += 1usize
    }
    if current + 1usize < documents.len {
        picks[1usize] = TabClose { index: current + 1usize, close: pick }
        shortcuts[bound] = widget.Shortcut { key: 39u32, modifiers: zero, action: widget.Submit { ctx: mem.cast[*void](&picks[1usize]), invoke: tab_close_fire } }
        bound += 1usize
    }
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, TooLarge) }
    var strip = style.defaults()
    strip.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceVariant) }
    row[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .End, gap: 0.0 }, strip, tabs[0usize..documents.len])
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: shortcuts[0usize..bound], default_action: zero, cancel_action: zero, keys: zero }, style.defaults(), row[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 20u8
    sem.label = label
    sem.column_count = u32(documents.len)
    ret (widget.semantics(key, sem, style.defaults(), scoped[0usize..1usize]), ok)
}

// A dock panel: a title bar (the title as a label, a close button keyed `key + 1`
// firing `close`) over the content on a bordered surface; a group in the tree
// named by the title.
fn dock_panel(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, close: *const widget.Submit) -> (widget.Node, err) {
    var caption = control.text_options()
    caption.role = .Label
    caption.wrap = .None
    let (title_node, title_error) = control.text(a, 0u64, title, t, caption)
    if title_error != ok { ret (zero, title_error) }
    var plain = control.button_options()
    plain.variant = .Plain
    let (closer, closer_error) = control.button(a, key + 1u64, t, "x", close, plain)
    if closer_error != ok { ret (zero, closer_error) }
    let (head, head_error) = mem.alloc[widget.Node](a, 2usize)
    if head_error != ok { ret (zero, TooLarge) }
    head[0usize] = title_node
    head[1usize] = closer
    var bar = style.defaults()
    bar.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceVariant) }
    bar.width = style.Length { Percent: 100.0 }
    let pad = style.Length { Px: t.tokens.spacing.xs }
    bar.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: t.tokens.spacing.xs }, bar, head[0usize..2usize])
    parts[1usize] = content
    var options = control.surface_options(t)
    options.bordered = true
    var panel = control.surface_style(t, options)
    panel.width = style.Length { Percent: 100.0 }
    panel.height = style.Length { Percent: 100.0 }
    panel.overflow = .Clip
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(key, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, panel, parts[0usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = title
    ret (widget.semantics(0u64, sem, style.defaults(), column[0usize..1usize]), ok)
}

// The sizes of a dock layout's side panels, the caller's value.
type DockSizes = struct { left: f32, right: f32, bottom: f32 }

// One handle's move turned into the whole sizes value.
type DockMove = struct { side: u8, sizes: DockSizes, width: f32, handle: f32, change: widget.Change[DockSizes] }

fn dock_move_fire(ctx: *void, moved: f32) -> err {
    let m = mem.cast[*DockMove](ctx)
    var next = m.sizes
    if m.side == 0u8 { next.left = moved }
    if m.side == 2u8 { next.bottom = moved }
    if m.side == 1u8 {
        // The middle's handle sizes the middle; the right panel is what remains.
        next.right = m.width - m.sizes.left - moved - 2.0 * m.handle
        if next.right < 0.0 { next.right = 0.0 }
    }
    ret widget.fire_change[DockSizes](m.change, next)
}

// A dock layout: `left` and `right` panels beside a middle of `centre` over
// `bottom`, `width` by `height`, the panels sized by `sizes` (the caller's) and
// resized by D826's handles -- the left panel's (keyed `key + 1`, its content
// `key + 2`, its handle `key + 3`), the middle's (`key + 4`, whose move sizes the
// right panel by what remains) and the bottom's inside the middle (`key + 7`);
// every move reaches `change` with the whole sizes. A group in the tree.
fn dock_layout(a: *mem.Arena, key: widget.Key, t: *const control.Theme, left: widget.Node, centre: widget.Node, right: widget.Node, bottom: widget.Node, sizes: DockSizes, change: widget.Change[DockSizes], width: f32, height: f32) -> (widget.Node, err) {
    let handle = t.tokens.spacing.xs
    let (moves, moves_error) = mem.alloc[DockMove](a, 3usize)
    if moves_error != ok { ret (zero, TooLarge) }
    moves[0usize] = DockMove { side: 0u8, sizes: sizes, width: width, handle: handle, change: change }
    moves[1usize] = DockMove { side: 1u8, sizes: sizes, width: width, handle: handle, change: change }
    moves[2usize] = DockMove { side: 2u8, sizes: sizes, width: width, handle: handle, change: change }
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
    let (stack, stack_error) = mem.alloc[widget.Node](a, 2usize)
    if stack_error != ok { ret (zero, TooLarge) }
    stack[0usize] = widget.box(0u64, centre_style, centred[0usize..1usize])
    // The bottom panel's handle sits above it: the centre is the resizable pane,
    // its size the centre's height, so a drag reports the bottom by what remains.
    let (bottom_boxed, bottom_boxed_error) = mem.alloc[widget.Node](a, 1usize)
    if bottom_boxed_error != ok { ret (zero, TooLarge) }
    bottom_boxed[0usize] = bottom
    var bottom_style = style.defaults()
    bottom_style.width = style.Length { Percent: 100.0 }
    bottom_style.height = style.Length { Px: sizes.bottom }
    bottom_style.overflow = .Clip
    stack[1usize] = widget.box(0u64, bottom_style, bottom_boxed[0usize..1usize])
    let (lower, lower_error) = mem.alloc[DockMove](a, 1usize)
    if lower_error != ok { ret (zero, TooLarge) }
    lower[0usize] = DockMove { side: 3u8, sizes: sizes, width: height, handle: handle, change: change }
    let (middle_pane, middle_pane_error) = control.resizable_pane(a, key + 7u64, t, "Bottom panel", .Vertical, middle_height, 2.0 * t.tokens.spacing.lg, height - handle, widget.Change[f32] { ctx: mem.cast[*void](&lower[0usize]), invoke: dock_bottom_fire }, stack[0usize])
    if middle_pane_error != ok { ret (zero, middle_pane_error) }
    let (middle_parts, middle_parts_error) = mem.alloc[widget.Node](a, 2usize)
    if middle_parts_error != ok { ret (zero, TooLarge) }
    middle_parts[0usize] = middle_pane
    middle_parts[1usize] = stack[1usize]
    var middle_style = style.defaults()
    middle_style.width = style.Length { Percent: 100.0 }
    middle_style.height = style.Length { Px: height }
    let middle = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, middle_style, middle_parts[0usize..2usize])
    // The row: the left panel, the middle (whose handle sizes the right), the right.
    var middle_width = width - sizes.left - sizes.right - 2.0 * handle
    if middle_width < 0.0 { middle_width = 0.0 }
    let (left_pane, left_error) = control.resizable_pane(a, key + 1u64, t, "Left panel", .Horizontal, sizes.left, 2.0 * t.tokens.spacing.lg, width - handle, widget.Change[f32] { ctx: mem.cast[*void](&moves[0usize]), invoke: dock_move_fire }, left)
    if left_error != ok { ret (zero, left_error) }
    let (middle_sized, middle_sized_error) = control.resizable_pane(a, key + 4u64, t, "Right panel", .Horizontal, middle_width, 2.0 * t.tokens.spacing.lg, width - handle, widget.Change[f32] { ctx: mem.cast[*void](&moves[1usize]), invoke: dock_move_fire }, middle)
    if middle_sized_error != ok { ret (zero, middle_sized_error) }
    let (righted, righted_error) = mem.alloc[widget.Node](a, 1usize)
    if righted_error != ok { ret (zero, TooLarge) }
    righted[0usize] = right
    var right_style = style.defaults()
    right_style.width = style.Length { Flex: 1.0 }
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

// The middle's vertical handle sizes the centre; the bottom is what remains.
fn dock_bottom_fire(ctx: *void, moved: f32) -> err {
    let m = mem.cast[*DockMove](ctx)
    var next = m.sizes
    next.bottom = m.width - moved - m.handle
    if next.bottom < 0.0 { next.bottom = 0.0 }
    ret widget.fire_change[DockSizes](m.change, next)
}

// A multi-document workspace: the document tabs (keyed `key + 1`) over the
// current document's view, `width` by `height`, under a scope whose Ctrl+W
// closes the current document and whose Ctrl+PageDown and Ctrl+PageUp pick the
// next and the previous; a group in the tree named `label`.
fn multi_document_workspace(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, documents: []const Document, current: usize, view: widget.Node, pick: widget.Change[usize], close: widget.Change[usize], move: widget.Change[DocumentMove], width: f32, height: f32) -> (widget.Node, err) {
    let (strip, strip_error) = document_tabs(a, key + 1u64, t, label, documents, current, pick, close, move)
    if strip_error != ok { ret (zero, strip_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = strip
    let (viewed, viewed_error) = mem.alloc[widget.Node](a, 1usize)
    if viewed_error != ok { ret (zero, TooLarge) }
    viewed[0usize] = view
    var view_style = style.defaults()
    view_style.width = style.Length { Px: width }
    view_style.height = style.Length { Flex: 1.0 }
    view_style.overflow = .Clip
    parts[1usize] = widget.box(0u64, view_style, viewed[0usize..1usize])
    let (keys, keys_error) = mem.alloc[TabClose](a, 3usize)
    if keys_error != ok { ret (zero, TooLarge) }
    var next = current
    if current + 1usize < documents.len { next = current + 1usize }
    var previous = current
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
