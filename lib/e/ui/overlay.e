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
use e.ui.accessibility
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

error TooLarge

// Whether a tooltip for `anchor` is wanted now: the anchor hovered, focused or held.
fn tooltip_wanted(t: *const control.Theme, anchor: widget.Key) -> bool {
    if mem.address_of(t.runtime) == 0usize { ret false }
    let now = widget.interaction(t.runtime, anchor)
    ret now.hovered || now.focused || now.pressed
}

// A tooltip: `text` as a caption on a small raised surface below `anchor`, keyed
// `key`, placed only while `shown` (an empty box otherwise); a tooltip in the tree
// that describes nothing by itself -- the anchor's `described_by` is the caller's.
fn tooltip(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, text: str, shown: bool) -> (widget.Node, err) {
    if !shown { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var caption = control.text_options()
    caption.role = .Caption
    caption.wrap = .None
    let (label_node, label_error) = control.text(a, 0u64, text, t, caption)
    if label_error != ok { ret (zero, label_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = label_node
    var raised = control.surface_options(t)
    raised.background = .SurfaceVariant
    raised.bordered = true
    raised.elevation = 1u8
    raised.radius = t.tokens.radii.xs
    raised.padding = t.tokens.spacing.xs
    let (surface, surface_error) = mem.alloc[widget.Node](a, 1usize)
    if surface_error != ok { ret (zero, TooLarge) }
    surface[0usize] = widget.box(0u64, control.surface_style(t, raised), body[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 27u8
    sem.label = text
    let (tip, tip_error) = mem.alloc[widget.Node](a, 1usize)
    if tip_error != ok { ret (zero, TooLarge) }
    tip[0usize] = widget.semantics(0u64, sem, style.defaults(), surface[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: .Below, offset: geometry.Point { x: 0.0, y: t.tokens.spacing.xs }, modal: false, dismiss: zero }, style.defaults(), tip[0usize..1usize]), ok)
}

// A command in a menu: its label, what it does, and whether it may be chosen.
type MenuItem = struct { label: str, action: widget.Submit, enabled: bool }

// A menu: a modal overlay below `anchor` of the items as plain buttons keyed
// `key + 1 + index` (menu items in the tree), placed only while `open`; a press
// outside it or Escape fires `dismiss`. The items outlive the frame.
fn menu(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, label: str, items: []const MenuItem, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, items.len)
    if rows_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < items.len {
        var plain = control.button_options()
        plain.variant = .Plain
        plain.enabled = items[i].enabled
        let (item, item_error) = control.button(a, key + 1u64 + u64(i), t, items[i].label, &items[i].action, plain)
        if item_error != ok { ret (zero, item_error) }
        var entry: widget.Semantics = zero
        entry.role = 22u8
        entry.label = items[i].label
        if !items[i].enabled { entry.states = accessibility.STATE_DISABLED }
        let (wrapped, wrapped_error) = mem.alloc[widget.Node](a, 1usize)
        if wrapped_error != ok { ret (zero, TooLarge) }
        wrapped[0usize] = item
        rows[i] = widget.semantics(0u64, entry, style.defaults(), wrapped[0usize..1usize])
        i += 1usize
    }
    var raised = control.surface_options(t)
    raised.bordered = true
    raised.elevation = 2u8
    raised.radius = t.tokens.radii.xs
    raised.padding = t.tokens.spacing.xs
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, control.surface_style(t, raised), rows[0usize..items.len])
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
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: .Below, offset: geometry.Point { x: 0.0, y: t.tokens.spacing.xs }, modal: true, dismiss: *dismiss }, style.defaults(), lifted[0usize..1usize]), ok)
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
fn alert_dialog(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, message: str, buttons: []const DialogButton, open: bool) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (message_node, message_error) = control.text(a, key + 2u64, message, t, control.text_options())
    if message_error != ok { ret (zero, message_error) }
    let (made, made_error) = dialog(a, key, t, title, message_node, buttons, open, true)
    ret (made, made_error)
}

// A dialog: a modal overlay in the middle of the window, a card of the title (a
// heading keyed `key + 1`), the caller's content and the buttons in a row keyed
// `key + 3 + index`, placed only while `open`; a modal dialog in the tree labelled
// by the title and, when `described`, described by the content's key `key + 2`.
// The buttons outlive the frame.
fn dialog(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, buttons: []const DialogButton, open: bool, described: bool) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    var submit: widget.Submit = zero
    var cancel: widget.Submit = zero
    let (row, row_error) = mem.alloc[widget.Node](a, buttons.len)
    if row_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < buttons.len {
        let button_key = key + 3u64 + u64(i)
        var variant: style.ControlVariant = .Outlined
        if buttons[i].kind == .Default {
            variant = .Filled
            submit = buttons[i].action
        }
        if buttons[i].kind == .Cancel { cancel = buttons[i].action }
        var look = style.resolve(t.tokens, variant, control.control_state(t, button_key, true, false))
        if buttons[i].kind == .Destructive {
            look.background = style.color(t.tokens, .Error)
            look.foreground = style.color(t.tokens, .OnError)
            look.border = look.background
        }
        var caption = control.text_options()
        caption.role = .Label
        caption.wrap = .None
        let (label_node, label_error) = control.colored_text(a, 0u64, buttons[i].label, t, caption, look.foreground)
        if label_error != ok { ret (zero, label_error) }
        let (pressed, pressed_error) = control.pressable_states(a, button_key, t, 3u8, buttons[i].label, look, true, false, 0u32, 0u32, 0u64, &buttons[i].action, label_node)
        if pressed_error != ok { ret (zero, pressed_error) }
        row[i] = pressed
        i += 1usize
    }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var heading = control.text_options()
    heading.role = .Title
    let (title_node, title_error) = control.text(a, key + 1u64, title, t, heading)
    if title_error != ok { ret (zero, title_error) }
    let (titled, titled_error) = mem.alloc[widget.Node](a, 1usize)
    if titled_error != ok { ret (zero, TooLarge) }
    titled[0usize] = title_node
    var title_sem: widget.Semantics = zero
    title_sem.role = 25u8
    title_sem.label = title
    title_sem.level = 1u8
    parts[0usize] = widget.semantics(0u64, title_sem, style.defaults(), titled[0usize..1usize])
    parts[1usize] = content
    parts[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: t.tokens.spacing.sm }, style.defaults(), row[0usize..buttons.len])
    var raised = control.surface_options(t)
    raised.bordered = true
    raised.elevation = 3u8
    raised.radius = t.tokens.radii.sm
    raised.padding = t.tokens.spacing.lg
    var card_style = control.surface_style(t, raised)
    card_style.min_width = style.Length { Px: 8.0 * t.tokens.spacing.lg }
    let (card, card_error) = mem.alloc[widget.Node](a, 1usize)
    if card_error != ok { ret (zero, TooLarge) }
    card[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: t.tokens.spacing.md }, card_style, parts[0usize..3usize])
    var none: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: submit, cancel_action: cancel, keys: zero }, style.defaults(), card[0usize..1usize])
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

// The raised surface every popup stands on.
fn popup_surface(a: *mem.Arena, t: *const control.Theme, content: widget.Node) -> (widget.Node, err) {
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = content
    var raised = control.surface_options(t)
    raised.bordered = true
    raised.elevation = 2u8
    raised.radius = t.tokens.radii.xs
    raised.padding = t.tokens.spacing.sm
    ret (widget.box(0u64, control.surface_style(t, raised), body[0usize..1usize]), ok)
}

// A popup: the content on a raised surface placed against `anchor` (keyed
// `key`), non-modal -- presses elsewhere pass through and nothing closes it but
// the caller -- placed only while `open`. A group in the tree.
fn popup(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, content: widget.Node, open: bool) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (surface, surface_error) = popup_surface(a, t, content)
    if surface_error != ok { ret (zero, surface_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = surface
    var sem: widget.Semantics = zero
    sem.role = 2u8
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.semantics(0u64, sem, style.defaults(), body[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: placement, offset: geometry.Point { x: 0.0, y: t.tokens.spacing.xs }, modal: false, dismiss: zero }, style.defaults(), framed[0usize..1usize]), ok)
}

// A modal popup against an anchor: the content on the surface, taking the focus,
// Escape and a press outside firing `dismiss` (which also gives the focus back,
// D810); a dialog in the tree named `label`.
fn light_dismissed(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, label: str, content: widget.Node, dismiss: *const widget.Submit) -> (widget.Node, err) {
    let (surface, surface_error) = popup_surface(a, t, content)
    if surface_error != ok { ret (zero, surface_error) }
    let (made, made_error) = dismissable(a, key, anchor, placement, label, surface, dismiss, t.tokens.spacing.xs)
    ret (made, made_error)
}

// The same over a surface the caller drew, `gap` from the anchor (D959).
fn dismissable(a: *mem.Arena, key: widget.Key, anchor: widget.Key, placement: widget.Placement, label: str, surface: widget.Node, dismiss: *const widget.Submit, gap: f32) -> (widget.Node, err) {
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
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: placement, offset: geometry.Point { x: 0.0, y: gap }, modal: true, dismiss: *dismiss }, style.defaults(), framed[0usize..1usize]), ok)
}

// A flyout: a light-dismissed popup against its anchor, placed while `open`.
fn flyout(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, label: str, content: widget.Node, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (made, made_error) = light_dismissed(a, key, t, anchor, placement, label, content, dismiss)
    ret (made, made_error)
}

// A popover: a flyout with a title (a heading keyed `key + 1`) and a close
// button (keyed `key + 2`) above the content.
fn popover(a: *mem.Arena, key: widget.Key, t: *const control.Theme, anchor: widget.Key, placement: widget.Placement, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (titled, titled_error) = titled_content(a, key, t, title, content, dismiss)
    if titled_error != ok { ret (zero, titled_error) }
    let (made, made_error) = light_dismissed(a, key, t, anchor, placement, title, titled, dismiss)
    ret (made, made_error)
}

// A title row -- the heading (keyed `key + 1`) and a close button (`key + 2`)
// firing `dismiss` -- above the content.
fn titled_content(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, dismiss: *const widget.Submit) -> (widget.Node, err) {
    var heading = control.text_options()
    heading.role = .Title
    heading.wrap = .None
    let (title_node, title_error) = control.text(a, key + 1u64, title, t, heading)
    if title_error != ok { ret (zero, title_error) }
    let (titled, titled_error) = mem.alloc[widget.Node](a, 1usize)
    if titled_error != ok { ret (zero, TooLarge) }
    titled[0usize] = title_node
    var title_sem: widget.Semantics = zero
    title_sem.role = 25u8
    title_sem.label = title
    title_sem.level = 1u8
    let (head, head_error) = mem.alloc[widget.Node](a, 2usize)
    if head_error != ok { ret (zero, TooLarge) }
    head[0usize] = widget.semantics(0u64, title_sem, style.defaults(), titled[0usize..1usize])
    var plain = control.button_options()
    plain.variant = .Plain
    let (close, close_error) = control.button(a, key + 2u64, t, "x", dismiss, plain)
    if close_error != ok { ret (zero, close_error) }
    head[1usize] = close
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    // The row spreads the title and the close apart without a flex share, which
    // an overlay's loose measure would grow to the window.
    parts[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .SpaceBetween, cross: .Center, gap: t.tokens.spacing.sm }, style.defaults(), head[0usize..2usize])
    parts[1usize] = content
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: t.tokens.spacing.sm }, style.defaults(), parts[0usize..2usize]), ok)
}

// A sheet: a modal panel `width` wide along the right edge of the window, the
// window's height, with a title and a close button (keyed `key + 1`, `key + 2`)
// above the content, placed while `open`; Escape and a press outside fire
// `dismiss`. A modal dialog in the tree named by the title.
fn sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit, width: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (made, made_error) = edged(a, key, t, title, content, dismiss, .Right, width, 0.0)
    ret (made, made_error)
}

// A bottom sheet: the same along the bottom edge, the window's width and
// `height` tall.
fn bottom_sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, open: bool, dismiss: *const widget.Submit, height: f32) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (made, made_error) = edged(a, key, t, title, content, dismiss, .Below, 0.0, height)
    ret (made, made_error)
}

fn edged(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, content: widget.Node, dismiss: *const widget.Submit, placement: widget.Placement, width: f32, height: f32) -> (widget.Node, err) {
    let (titled, titled_error) = titled_content(a, key, t, title, content, dismiss)
    if titled_error != ok { ret (zero, titled_error) }
    let (body, body_error) = mem.alloc[widget.Node](a, 1usize)
    if body_error != ok { ret (zero, TooLarge) }
    body[0usize] = titled
    var options = control.surface_options(t)
    options.elevation = 3u8
    options.padding = t.tokens.spacing.md
    var panel = control.surface_style(t, options)
    panel.width = style.Length { Percent: 100.0 }
    panel.height = style.Length { Percent: 100.0 }
    if width > 0.0 { panel.width = style.Length { Px: width } }
    if height > 0.0 { panel.height = style.Length { Px: height } }
    let (boxed, boxed_error) = mem.alloc[widget.Node](a, 1usize)
    if boxed_error != ok { ret (zero, TooLarge) }
    boxed[0usize] = widget.box(0u64, panel, body[0usize..1usize])
    var none: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: zero, cancel_action: *dismiss, keys: zero }, style.defaults(), boxed[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 23u8
    sem.label = title
    sem.states = accessibility.STATE_MODAL
    sem.labelled_by = key + 1u64
    let (framed, framed_error) = mem.alloc[widget.Node](a, 1usize)
    if framed_error != ok { ret (zero, TooLarge) }
    framed[0usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: 0u64, placement: placement, offset: zero, modal: true, dismiss: *dismiss }, style.defaults(), framed[0usize..1usize]), ok)
}

// An action sheet: a bottom sheet of the actions as full-width buttons keyed
// `key + 3 + index` (the destructive ones in the error colour) with a Cancel
// button (keyed `key + 3 + count`) last that fires `dismiss`.
fn action_sheet(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, buttons: []const DialogButton, open: bool, dismiss: *const widget.Submit) -> (widget.Node, err) {
    if !open { ret (widget.box(0u64, style.defaults(), zero), ok) }
    let (rows, rows_error) = mem.alloc[widget.Node](a, buttons.len + 1usize)
    if rows_error != ok { ret (zero, TooLarge) }
    var i = 0usize
    while i < buttons.len {
        let button_key = key + 3u64 + u64(i)
        var look = style.resolve(t.tokens, .Outlined, control.control_state(t, button_key, true, false))
        if buttons[i].kind == .Destructive {
            look.background = style.color(t.tokens, .Error)
            look.foreground = style.color(t.tokens, .OnError)
            look.border = look.background
        }
        var caption = control.text_options()
        caption.role = .Label
        caption.wrap = .None
        let (label_node, label_error) = control.colored_text(a, 0u64, buttons[i].label, t, caption, look.foreground)
        if label_error != ok { ret (zero, label_error) }
        let (pressed, pressed_error) = control.pressable_states(a, button_key, t, 3u8, buttons[i].label, look, true, false, 0u32, 0u32, 0u64, &buttons[i].action, label_node)
        if pressed_error != ok { ret (zero, pressed_error) }
        var stretched = pressed
        stretched.style.width = style.Length { Percent: 100.0 }
        rows[i] = stretched
        i += 1usize
    }
    var outlined = control.button_options()
    outlined.variant = .Outlined
    let (cancel, cancel_error) = control.button(a, key + 3u64 + u64(buttons.len), t, "Cancel", dismiss, outlined)
    if cancel_error != ok { ret (zero, cancel_error) }
    var stretched_cancel = cancel
    stretched_cancel.style.width = style.Length { Percent: 100.0 }
    rows[buttons.len] = stretched_cancel
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: t.tokens.spacing.xs }, style.defaults(), rows[0usize..buttons.len + 1usize])
    let height = f32(buttons.len + 2usize) * (t.tokens.metrics.control_height + t.tokens.spacing.xs) + 3.0 * t.tokens.spacing.md + t.tokens.text[0usize].line_height
    let (made, made_error) = edged(a, key, t, title, column, dismiss, .Below, 0.0, height)
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
        let (lifted, popup_error) = mem.alloc[widget.Node](a, 2usize)
        if popup_error != ok { ret (zero, TooLarge) }
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
