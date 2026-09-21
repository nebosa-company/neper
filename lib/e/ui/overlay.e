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
