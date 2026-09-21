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
use e.ui.layout as ui_layout
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
    ret (widget.scope(key, widget.Scope { traps_focus: false, shortcuts: shortcuts, default_action: zero, cancel_action: cancel }, style.defaults(), column[0usize..1usize]), ok)
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
