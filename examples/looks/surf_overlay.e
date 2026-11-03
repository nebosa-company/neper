// Round 62 (g): the overlay surfaces in all ten looks: alert_dialog, popover, flyout, side_sheet, bottom_sheet, action_sheet.
// `surf_overlay <control> [state]` renders docs/ui/looks/<look>/<control>[_state].png in Neper, Windows, Linux, Cupertino and Material
// (Light and Dark each). An open modal overlay fills the window, so each sheet holds one cell; popover and flyout, which hang
// from an anchor button, hold three. Derived: every look draws the shared widget under its own tokens; Windows, Linux, Cupertino
// and Material have no capture of these surfaces, so nothing here is compared with a real screen.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_g
use e.ui.looks_y85
use e.ui.overlay
use e.ui.style
use e.ui.widget
use e.ui.layout as ui_layout
use e.str as strs

fn noop_submit(ctx: *void) -> err { ret ok }

fn none_action() -> widget.Submit { ret widget.Submit { ctx: zero, invoke: noop_submit } }

fn words(a: *mem.Arena, t: *const control.Theme, value: str) -> (widget.Node, err) {
    var o = control.text_options()
    o.role = .BodyMedium
    let (node, node_error) = control.text(a, 0u64, value, t, o)
    ret (node, node_error)
}

fn buttons_of(a: *mem.Arena, count: usize) -> ([]overlay.DialogButton, err) {
    let (list, list_error) = mem.alloc[overlay.DialogButton](a, 3usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = overlay.DialogButton { label: "Cancel", action: none_action(), kind: .Cancel }
    list[1usize] = overlay.DialogButton { label: "Delete", action: none_action(), kind: .Destructive }
    list[2usize] = overlay.DialogButton { label: "Keep", action: none_action(), kind: .Default }
    if count == 2usize { list[1usize] = overlay.DialogButton { label: "OK", action: none_action(), kind: .Default } }
    ret (list[0usize..count], ok)
}

fn dismiss_of(a: *mem.Arena) -> (*const widget.Submit, err) {
    let (one, one_error) = mem.alloc[widget.Submit](a, 1usize)
    if one_error != ok { ret (zero, one_error) }
    one[0usize] = none_action()
    ret (&one[0usize], ok)
}

// The anchor button of a popover or flyout, keyed 10 + cell, and the overlay hung from it.
fn anchored(a: *mem.Arena, t: *const control.Theme, anchor_key: widget.Key, overlay_node: widget.Node, label: str) -> (widget.Node, err) {
    let act = none_action()
    let (hold, hold_error) = mem.alloc[widget.Submit](a, 1usize)
    if hold_error != ok { ret (zero, hold_error) }
    hold[0usize] = act
    let (anchor, anchor_error) = control.button(a, anchor_key, t, label, &hold[0usize], control.button_options())
    if anchor_error != ok { ret (zero, anchor_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = anchor
    parts[1usize] = overlay_node
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

// A sheet's content: a line of text over one button (keyed 50), the part of a sheet that can be hovered, pressed or focused.
fn with_button(a: *mem.Arena, t: *const control.Theme, line: str, label: str) -> (widget.Node, err) {
    let (text_node, text_error) = words(a, t, line)
    if text_error != ok { ret (zero, text_error) }
    let (hold, hold_error) = mem.alloc[widget.Submit](a, 1usize)
    if hold_error != ok { ret (zero, hold_error) }
    hold[0usize] = none_action()
    let (button, button_error) = control.button(a, 50u64, t, label, &hold[0usize], control.button_options())
    if button_error != ok { ret (zero, button_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = text_node
    parts[1usize] = button
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, style.defaults(), parts[0usize..2usize]), ok)
}

fn build_alert(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (buttons, buttons_error) = buttons_of(a, 3usize)
    if buttons_error != ok { ret (0usize, buttons_error) }
    let (node, node_error) = overlay.alert_dialog(a, 100u64, t, "Delete this deck?", "The deck and its notes are removed from your library.", buttons, true)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "alert dialog, three buttons", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_popover(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (dismiss, dismiss_error) = dismiss_of(a)
    if dismiss_error != ok { ret (0usize, dismiss_error) }
    let names = [3]str{ "below", "above", "with actions" }
    var i = 0usize
    while i < 3usize {
        let (body, body_error) = words(a, t, "Prices come from the daily bulk file.")
        if body_error != ok { ret (0usize, body_error) }
        var placement: widget.Placement = .Below
        if i == 1usize { placement = .Above }
        var node: widget.Node = zero
        var made_error: err = ok
        if i < 2usize {
            let (made, e1) = overlay.popover(a, u64(100 + i * 100), t, 10u64 + u64(i), placement, "Price source", body, true, dismiss)
            node = made
            made_error = e1
        } else {
            let (items, items_error) = mem.alloc[overlay.MenuItem](a, 2usize)
            if items_error != ok { ret (0usize, items_error) }
            items[0usize] = overlay.MenuItem { label: "Update", action: none_action(), enabled: true }
            items[1usize] = overlay.MenuItem { label: "Later", action: none_action(), enabled: true }
            let (made, e2) = overlay.popover_of(a, u64(100 + i * 100), t, 10u64 + u64(i), placement, "Price source", body, items[0usize..2usize], true, dismiss)
            node = made
            made_error = e2
        }
        if made_error != ok { ret (0usize, made_error) }
        let (host, host_error) = anchored(a, t, 10u64 + u64(i), node, "Prices")
        if host_error != ok { ret (0usize, host_error) }
        cells[i] = looks.Cell { caption: names[i], node: host, drive: .None }
        i += 1usize
    }
    ret (3usize, ok)
}

fn build_flyout(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (dismiss, dismiss_error) = dismiss_of(a)
    if dismiss_error != ok { ret (0usize, dismiss_error) }
    let names = [3]str{ "below", "above", "right" }
    var i = 0usize
    while i < 3usize {
        let (body, body_error) = words(a, t, "Set the card size for this view.")
        if body_error != ok { ret (0usize, body_error) }
        var placement: widget.Placement = .Below
        if i == 1usize { placement = .Above }
        if i == 2usize { placement = .Right }
        let (node, node_error) = overlay.flyout(a, u64(100 + i * 100), t, 10u64 + u64(i), placement, "View options", body, true, dismiss)
        if node_error != ok { ret (0usize, node_error) }
        let (host, host_error) = anchored(a, t, 10u64 + u64(i), node, "View")
        if host_error != ok { ret (0usize, host_error) }
        cells[i] = looks.Cell { caption: names[i], node: host, drive: .None }
        i += 1usize
    }
    ret (3usize, ok)
}

fn build_side(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (dismiss, dismiss_error) = dismiss_of(a)
    if dismiss_error != ok { ret (0usize, dismiss_error) }
    let (body, body_error) = with_button(a, t, "Filters apply to the whole collection.", "Apply")
    if body_error != ok { ret (0usize, body_error) }
    let (node, node_error) = overlay.sheet(a, 100u64, t, "Filters", body, true, dismiss, 300.0)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "side sheet", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_bottom(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: the Save fill is the blue white text holds 4.5:1 on (0A60FF, 0B57D0); other looks get their own tokens back.
    let (tokens, tokens_error) = looks_y85.tinted_ring(a, base.tokens, 0x0A60FFu32, 0x0B57D0u32)
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *base
    themed.tokens = tokens
    let t = &themed
    let (dismiss, dismiss_error) = dismiss_of(a)
    if dismiss_error != ok { ret (0usize, dismiss_error) }
    let (body, body_error) = with_button(a, t, "Choose where the copy is saved.", "Save")
    if body_error != ok { ret (0usize, body_error) }
    let (node, node_error) = overlay.bottom_sheet(a, 100u64, t, "Save a copy", body, true, dismiss, 170.0)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "bottom sheet", node: node, drive: .None }
    ret (1usize, ok)
}

fn build_action(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (dismiss, dismiss_error) = dismiss_of(a)
    if dismiss_error != ok { ret (0usize, dismiss_error) }
    let (buttons, buttons_error) = buttons_of(a, 3usize)
    if buttons_error != ok { ret (0usize, buttons_error) }
    var node: widget.Node = zero
    var node_error: err = ok
    if t.tokens.profile == .CupertinoLike {
        (node, node_error) = overlay.action_sheet_ios(a, 100u64, t, "Deck actions", buttons, "Cancel", true, dismiss)
    } else {
        (node, node_error) = overlay.action_sheet(a, 100u64, t, "Deck actions", buttons, true, dismiss)
    }
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "action sheet", node: node, drive: .None }
    ret (1usize, ok)
}

fn action_buttons(a: *mem.Arena) -> ([]overlay.DialogButton, err) {
    let (list, list_error) = mem.alloc[overlay.DialogButton](a, 3usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = overlay.DialogButton { label: "Duplicate", action: none_action(), kind: .Plain }
    list[1usize] = overlay.DialogButton { label: "Rename", action: none_action(), kind: .Plain }
    list[2usize] = overlay.DialogButton { label: "Delete", action: none_action(), kind: .Destructive }
    ret (list[0usize..3usize], ok)
}

// A window of the spec's control: the popover and flyout hang from anchors laid out in a row.
fn row_of(a: *mem.Arena, nodes: []const widget.Node, width: f32, height: f32) -> widget.Node {
    var box = style.defaults()
    box.width = style.Length { Px: width }
    box.height = style.Length { Px: height }
    ret widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, box, nodes)
}

fn at_start(a: *mem.Arena, inner: widget.Node, width: f32, height: f32) -> widget.Node {
    var slot = style.defaults()
    slot.width = style.Length { Px: width }
    slot.height = style.Length { Px: height }
    slot.padding.left = style.Length { Px: 24.0 }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret inner }
    held[0usize] = inner
    ret widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Center, cross: .Start, gap: 0.0 }, slot, held[0usize..1usize])
}

// The popover and flyout sheets are a row of three anchored cells (build_popover, build_flyout): the cells' nodes in one row.
fn joined(a: *mem.Arena, cells: []looks.Cell, count: usize, width: f32, height: f32) -> (widget.Node, err) {
    let (nodes, nodes_error) = mem.alloc[widget.Node](a, count)
    if nodes_error != ok { ret (zero, nodes_error) }
    var i = 0usize
    while i < count {
        nodes[i] = at_start(a, cells[i].node, width, height)
        i += 1usize
    }
    ret (row_of(a, nodes[0usize..count], width * f32(count), height), ok)
}

fn build_popover_row(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (three, three_error) = mem.alloc[looks.Cell](a, 3usize)
    if three_error != ok { ret (0usize, three_error) }
    let (count, build_error) = build_popover(ctx, a, t, three)
    if build_error != ok { ret (0usize, build_error) }
    let (row, row_error) = joined(a, three, count, 372.0, 380.0)
    if row_error != ok { ret (0usize, row_error) }
    cells[0usize] = looks.Cell { caption: "", node: row, drive: .None }
    ret (1usize, ok)
}

fn build_flyout_row(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (three, three_error) = mem.alloc[looks.Cell](a, 3usize)
    if three_error != ok { ret (0usize, three_error) }
    let (count, build_error) = build_flyout(ctx, a, t, three)
    if build_error != ok { ret (0usize, build_error) }
    let (row, row_error) = joined(a, three, count, 340.0, 240.0)
    if row_error != ok { ret (0usize, row_error) }
    cells[0usize] = looks.Cell { caption: "", node: row, drive: .None }
    ret (1usize, ok)
}

fn build_action_window(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (dismiss, dismiss_error) = dismiss_of(a)
    if dismiss_error != ok { ret (0usize, dismiss_error) }
    let (buttons, buttons_error) = action_buttons(a)
    if buttons_error != ok { ret (0usize, buttons_error) }
    var node: widget.Node = zero
    var node_error: err = ok
    if t.tokens.profile == .CupertinoLike {
        (node, node_error) = overlay.action_sheet_ios(a, 100u64, t, "Deck actions", buttons, "Cancel", true, dismiss)
    } else {
        (node, node_error) = overlay.action_sheet(a, 100u64, t, "Deck actions", buttons, true, dismiss)
    }
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "", node: node, drive: .None }
    ret (1usize, ok)
}

// `surf_overlay <control> [rest|hover|pressed|focus]`. Windows are logical px: a dialog and the sheets are phone or dialog sized.
fn main(a: *mem.Arena, args: []str) -> err {
    var which = "alert_dialog"
    if args.len > 1usize { which = args[1usize] }
    var state = "rest"
    if args.len > 2usize { state = args[2usize] }
    var drive: looks.Drive = .None
    if strs.eq(state, "hover") { drive = .Hover }
    if strs.eq(state, "pressed") { drive = .Press }
    if strs.eq(state, "focus") { drive = .Focus }
    var name = which
    if drive != .None {
        let (head, head_error) = strs.concat(a, which, "_")
        if head_error != ok { ret head_error }
        let (joined_name, joined_error) = strs.concat(a, head, state)
        if joined_error != ok { ret joined_error }
        name = joined_name
    }
    var spec = looks_g.Spec { name: name, width: 440.0, height: 280.0, ctx: zero, build: build_alert, drive: drive, target: 105u64 }
    if strs.eq(which, "popover") { spec = looks_g.Spec { name: name, width: 1116.0, height: 380.0, ctx: zero, build: build_popover_row, drive: drive, target: 102u64 } }
    if strs.eq(which, "flyout") { spec = looks_g.Spec { name: name, width: 1020.0, height: 240.0, ctx: zero, build: build_flyout_row, drive: drive, target: 10u64 } }
    if strs.eq(which, "side_sheet") { spec = looks_g.Spec { name: name, width: 560.0, height: 340.0, ctx: zero, build: build_side, drive: drive, target: 50u64 } }
    if strs.eq(which, "bottom_sheet") { spec = looks_g.Spec { name: name, width: 480.0, height: 360.0, ctx: zero, build: build_bottom, drive: drive, target: 50u64 } }
    if strs.eq(which, "action_sheet") { spec = looks_g.Spec { name: name, width: 360.0, height: 420.0, ctx: zero, build: build_action_window, drive: drive, target: 104u64 } }
    ret looks_g.run(a, &spec)
}
