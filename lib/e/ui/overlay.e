// Transient UI over the widget tree (D827, widget plan P1-14): a tooltip beside
// what it explains, a menu of commands under its anchor, an alert dialog in the
// middle of the window. Every one is D810's overlay placed by a control function
// under `control.Theme`, present in the tree only while the caller says so -- the
// caller keeps `shown` and `open` the way it keeps every other value (D807) -- and
// keyed so the harness and the tree can find it.

use e.mem
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
    var sheet = control.surface_options(t)
    sheet.background = .SurfaceVariant
    sheet.bordered = true
    sheet.elevation = 1u8
    sheet.radius = t.tokens.radii.sm
    sheet.padding = t.tokens.spacing.xs
    let (surface, surface_error) = mem.alloc[widget.Node](a, 1usize)
    if surface_error != ok { ret (zero, TooLarge) }
    surface[0usize] = widget.box(0u64, control.surface_style(t, sheet), body[0usize..1usize])
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
    var sheet = control.surface_options(t)
    sheet.bordered = true
    sheet.elevation = 2u8
    sheet.radius = t.tokens.radii.sm
    sheet.padding = t.tokens.spacing.xs
    let (column, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Stretch, gap: 0.0 }, control.surface_style(t, sheet), rows[0usize..items.len])
    var none: []const widget.Shortcut = zero
    let (scoped, scoped_error) = mem.alloc[widget.Node](a, 1usize)
    if scoped_error != ok { ret (zero, TooLarge) }
    scoped[0usize] = widget.scope(0u64, widget.Scope { traps_focus: true, shortcuts: none, default_action: zero, cancel_action: *dismiss, keys: zero }, style.defaults(), column[0usize..1usize])
    var sem: widget.Semantics = zero
    sem.role = 21u8
    sem.label = label
    let (popup, popup_error) = mem.alloc[widget.Node](a, 1usize)
    if popup_error != ok { ret (zero, TooLarge) }
    popup[0usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: .Below, offset: geometry.Point { x: 0.0, y: t.tokens.spacing.xs }, modal: true, dismiss: *dismiss }, style.defaults(), popup[0usize..1usize]), ok)
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
    let (popup, popup_error) = menu(a, key + 1u64, t, key, label, items, open, toggle)
    if popup_error != ok { ret (zero, popup_error) }
    parts[1usize] = popup
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

// What a dialog button means: the default one is filled and Enter, the cancel one
// is Escape and the dismiss, a destructive one is in the error colour, a plain one
// is just a button.
type DialogAction = enum u8 { Plain, Default, Cancel, Destructive }
type DialogButton = struct { label: str, action: widget.Submit, kind: DialogAction }

// An alert dialog: a modal overlay in the middle of the window, a card of the title
// (a heading keyed `key + 1`), the message (keyed `key + 2`) and the buttons in a
// row keyed `key + 3 + index`, placed only while `open`; a modal dialog in the tree
// labelled by the title and described by the message. The buttons outlive the frame.
fn alert_dialog(a: *mem.Arena, key: widget.Key, t: *const control.Theme, title: str, message: str, buttons: []const DialogButton, open: bool) -> (widget.Node, err) {
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
    let (message_node, message_error) = control.text(a, key + 2u64, message, t, control.text_options())
    if message_error != ok { ret (zero, message_error) }
    parts[1usize] = message_node
    parts[2usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .End, cross: .Center, gap: t.tokens.spacing.sm }, style.defaults(), row[0usize..buttons.len])
    var sheet = control.surface_options(t)
    sheet.bordered = true
    sheet.elevation = 3u8
    sheet.radius = t.tokens.radii.md
    sheet.padding = t.tokens.spacing.lg
    var card_style = control.surface_style(t, sheet)
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
    sem.described_by = key + 2u64
    let (dialog, dialog_error) = mem.alloc[widget.Node](a, 1usize)
    if dialog_error != ok { ret (zero, TooLarge) }
    dialog[0usize] = widget.semantics(0u64, sem, style.defaults(), scoped[0usize..1usize])
    ret (widget.overlay(key, widget.Overlay { anchor: 0u64, placement: .Center, offset: zero, modal: true, dismiss: cancel }, style.defaults(), dialog[0usize..1usize]), ok)
}
