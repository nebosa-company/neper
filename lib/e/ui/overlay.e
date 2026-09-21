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
    raised.radius = t.tokens.radii.sm
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
    raised.radius = t.tokens.radii.sm
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
    raised.radius = t.tokens.radii.md
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
    raised.radius = t.tokens.radii.sm
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
    ret (widget.overlay(key, widget.Overlay { anchor: anchor, placement: placement, offset: geometry.Point { x: 0.0, y: t.tokens.spacing.xs }, modal: true, dismiss: *dismiss }, style.defaults(), framed[0usize..1usize]), ok)
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

// A calendar of the month `shown` (its day is ignored): a header of a Previous
// button (keyed `key + 1`), the year and month, and a Next button (`key + 2`),
// each reporting the first of the neighbouring month through `show`; then the
// weeks, Monday first, a plain button a day keyed `key + 3 + day` reporting its
// date through `pick`, the day of `selected` filled and the days from `from` to
// `to` (when `ranged`) tinted. A grid in the tree named `label`, seven columns.
fn calendar(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, shown: time.Date, selected: time.Date, has_selected: bool, ranged: bool, from: time.Date, to: time.Date, show: widget.Change[time.Date], pick: widget.Change[time.Date]) -> (widget.Node, err) {
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
    // The header.
    let (head, head_error) = mem.alloc[widget.Node](a, 3usize)
    if head_error != ok { ret (zero, TooLarge) }
    var plain = control.button_options()
    plain.variant = .Plain
    let (back, back_error) = control.button(a, key + 1u64, t, "<", &actions[0usize], plain)
    if back_error != ok { ret (zero, back_error) }
    head[0usize] = back
    let (title_bytes, title_error) = mem.alloc[u8](a, 16usize)
    if title_error != ok { ret (zero, TooLarge) }
    let year_len = control.write_i64(title_bytes, year)
    title_bytes[year_len] = 45u8
    let title_len = write_two(title_bytes, year_len + 1usize, month)
    var heading = control.text_options()
    heading.role = .Label
    heading.wrap = .None
    heading.align = .Center
    let (title_node, title_node_error) = control.text(a, 0u64, title_bytes[0usize..title_len], t, heading)
    if title_node_error != ok { ret (zero, title_node_error) }
    var spread = title_node
    spread.style.width = style.Length { Flex: 1.0 }
    head[1usize] = spread
    let (forward, forward_error) = control.button(a, key + 2u64, t, ">", &actions[1usize], plain)
    if forward_error != ok { ret (zero, forward_error) }
    head[2usize] = forward
    // The days: blanks before the first, then a button a day, in rows of seven.
    let cell = t.tokens.metrics.hit_target
    let slots = usize(first_weekday) + usize(days)
    let weeks = (slots + 6usize) / 7usize
    let (rows, rows_error) = mem.alloc[widget.Node](a, 1usize + weeks)
    if rows_error != ok { ret (zero, TooLarge) }
    rows[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: t.tokens.spacing.xs }, control.sized_style(7.0 * cell, t.tokens.metrics.control_height), head[0usize..3usize])
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
                let chosen = has_selected && same_date(date, selected)
                var variant: style.ControlVariant = .Plain
                if chosen { variant = .Filled }
                let day_key = key + 3u64 + u64(day)
                var look = style.resolve(t.tokens, variant, control.control_state(t, day_key, true, chosen))
                if !chosen && ranged && within_range(date, from, to) { look.background = style.color(t.tokens, .Selection) }
                let (digits, digits_error) = mem.alloc[u8](a, 4usize)
                if digits_error != ok { ret (zero, TooLarge) }
                let digit_count = control.write_i64(digits, i64(day))
                var caption = control.text_options()
                caption.role = .Label
                caption.wrap = .None
                let (label_node, label_error) = control.colored_text(a, 0u64, digits[0usize..digit_count], t, caption, look.foreground)
                if label_error != ok { ret (zero, label_error) }
                let (pressed, pressed_error) = control.pressable_states(a, day_key, t, 3u8, digits[0usize..digit_count], look, true, chosen, 0u32, 0u32, 0u64, &actions[1usize + day], label_node)
                if pressed_error != ok { ret (zero, pressed_error) }
                var sized = pressed
                sized.style.width = style.Length { Px: cell }
                sized.style.height = style.Length { Px: cell }
                sized.style.min_width = style.Length { Px: cell }
                made = sized
            }
            cells[column] = made
            column += 1usize
        }
        rows[1usize + week] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, style.defaults(), cells[0usize..7usize])
        week += 1usize
    }
    let (column_node, column_error) = mem.alloc[widget.Node](a, 1usize)
    if column_error != ok { ret (zero, TooLarge) }
    column_node[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), rows[0usize..1usize + weeks])
    var sem: widget.Semantics = zero
    sem.role = 30u8
    sem.label = label
    sem.column_count = 7u32
    sem.row_count = u32(weeks)
    ret (widget.semantics(key, sem, style.defaults(), column_node[0usize..1usize]), ok)
}

// A date picker: an outlined button (keyed `key`) showing `value` as
// `YYYY-MM-DD` (or the label while there is none) firing `toggle`, with a
// calendar (keyed `key + 2`, in a flyout keyed `key + 1`) of the month `shown`
// below it while `open`; a pick reaches `pick`, a month turn `show`, and the
// flyout's dismissal is `toggle` again.
fn date_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, value: time.Date, has_value: bool, open: bool, toggle: *const widget.Submit, shown: time.Date, show: widget.Change[time.Date], pick: widget.Change[time.Date]) -> (widget.Node, err) {
    let (made, made_error) = dated(a, key, t, label, value, has_value, false, value, value, open, toggle, shown, show, pick)
    ret (made, made_error)
}

// A date range picker: the same over `from` and `to`, the button showing both,
// the days between tinted; a pick reaches `pick` and the caller decides which
// end it sets.
fn date_range_picker(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, from: time.Date, to: time.Date, has_range: bool, open: bool, toggle: *const widget.Submit, shown: time.Date, show: widget.Change[time.Date], pick: widget.Change[time.Date]) -> (widget.Node, err) {
    let (made, made_error) = dated(a, key, t, label, from, has_range, true, from, to, open, toggle, shown, show, pick)
    ret (made, made_error)
}

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
    var outlined = control.button_options()
    outlined.variant = .Outlined
    let (head, head_error) = control.button(a, key, t, caption, toggle, outlined)
    if head_error != ok { ret (zero, head_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, TooLarge) }
    parts[0usize] = head
    var popup_node = widget.box(0u64, style.defaults(), zero)
    if open {
        let (month, month_error) = calendar(a, key + 2u64, t, label, shown, value, has_value, ranged, from, to, show, pick)
        if month_error != ok { ret (zero, month_error) }
        let (lifted, lifted_error) = light_dismissed(a, key + 1u64, t, key, .Below, label, month, toggle)
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
    swatch.radius = t.tokens.radii.sm
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
