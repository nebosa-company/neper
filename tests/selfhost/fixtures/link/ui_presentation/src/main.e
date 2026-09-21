// `e.ui.overlay`'s transient presentation (D841, widget plan P2-09) under the
// light theme: a popup is non-modal and lets presses through; a flyout and a
// popover are modal against their anchor, dismissed by Escape and a press
// outside, the popover with a title and a close; a dialog takes any content; a
// sheet stands along the right edge and a bottom sheet along the bottom; an
// action sheet lists its actions with Cancel last.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { presses: usize, dismisses: usize, confirms: usize, shares: usize }

fn on_press(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.presses += 1usize
    ret ok
}

fn on_dismiss(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.dismisses += 1usize
    ret ok
}

fn on_confirm(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.confirms += 1usize
    ret ok
}

fn on_share(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.shares += 1usize
    ret ok
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

type Which = enum u8 { None, Popup, Flyout, Popover, Dialog, Sheet, Bottom, Actions }

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, press: *const widget.Submit, dismiss: *const widget.Submit, dialog_buttons: []const overlay.DialogButton, sheet_buttons: []const overlay.DialogButton, which: Which) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, parts_error) }
    let (anchor, anchor_error) = control.button(a, 1u64, t, "Anchor", press, control.button_options())
    if anchor_error != ok { ret (zero, anchor_error) }
    parts[0usize] = anchor
    let (inside, inside_error) = control.text(a, 0u64, "Inside", t, control.text_options())
    if inside_error != ok { ret (zero, inside_error) }
    var shown: widget.Node = widget.box(0u64, style.defaults(), zero)
    if which == .Popup {
        let (made, made_error) = overlay.popup(a, 10u64, t, 1u64, .Below, inside, true)
        if made_error != ok { ret (zero, made_error) }
        shown = made
    }
    if which == .Flyout {
        let (made, made_error) = overlay.flyout(a, 20u64, t, 1u64, .Below, "Options", inside, true, dismiss)
        if made_error != ok { ret (zero, made_error) }
        shown = made
    }
    if which == .Popover {
        let (made, made_error) = overlay.popover(a, 30u64, t, 1u64, .Right, "Details", inside, true, dismiss)
        if made_error != ok { ret (zero, made_error) }
        shown = made
    }
    if which == .Dialog {
        let (made, made_error) = overlay.dialog(a, 40u64, t, "Confirm", inside, dialog_buttons, true, false)
        if made_error != ok { ret (zero, made_error) }
        shown = made
    }
    if which == .Sheet {
        let (made, made_error) = overlay.sheet(a, 50u64, t, "Filters", inside, true, dismiss, 120.0)
        if made_error != ok { ret (zero, made_error) }
        shown = made
    }
    if which == .Bottom {
        let (made, made_error) = overlay.bottom_sheet(a, 60u64, t, "Share", inside, true, dismiss, 100.0)
        if made_error != ok { ret (zero, made_error) }
        shown = made
    }
    if which == .Actions {
        let (made, made_error) = overlay.action_sheet(a, 70u64, t, "Photo", sheet_buttons, true, dismiss)
        if made_error != ok { ret (zero, made_error) }
        shown = made
    }
    parts[1usize] = shown
    let (other, other_error) = control.button(a, 2u64, t, "Other", press, control.button_options())
    if other_error != ok { ret (zero, other_error) }
    parts[2usize] = other
    var column = style.defaults()
    column.width = style.Length { Px: 480.0 }
    column.height = style.Length { Px: 320.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 120.0 }, column, parts[0usize..3usize]), ok)
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn centre_of(h: *testing.Harness, runtime: *const widget.Runtime, key: widget.Key) -> (geometry.Point, bool) {
    let found = testing.by_key(h, key)
    if found.count != 1usize { ret (zero, false) }
    let (area, has_area) = widget.bounds_of(runtime, found.element)
    if !has_area { ret (zero, false) }
    ret (geometry.Point { x: area.x + area.width * 0.5, y: area.y + area.height * 0.5 }, true)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 128usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 14u16, max_commands: 400usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 480u32, 320u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (subs, subs_error) = mem.alloc[widget.Submit](a, 2usize)
    if subs_error != ok { os.exit(8i32) }
    subs[0usize] = widget.Submit { ctx: ctx, invoke: on_press }
    subs[1usize] = widget.Submit { ctx: ctx, invoke: on_dismiss }
    let (dialog_buttons, dialog_buttons_error) = mem.alloc[overlay.DialogButton](a, 2usize)
    if dialog_buttons_error != ok { os.exit(9i32) }
    dialog_buttons[0usize] = overlay.DialogButton { label: "Cancel", action: widget.Submit { ctx: ctx, invoke: on_dismiss }, kind: .Cancel }
    dialog_buttons[1usize] = overlay.DialogButton { label: "OK", action: widget.Submit { ctx: ctx, invoke: on_confirm }, kind: .Default }
    let (sheet_buttons, sheet_buttons_error) = mem.alloc[overlay.DialogButton](a, 2usize)
    if sheet_buttons_error != ok { os.exit(10i32) }
    sheet_buttons[0usize] = overlay.DialogButton { label: "Share", action: widget.Submit { ctx: ctx, invoke: on_share }, kind: .Plain }
    sheet_buttons[1usize] = overlay.DialogButton { label: "Delete", action: widget.Submit { ctx: ctx, invoke: on_confirm }, kind: .Destructive }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(11i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    // The popup: below the anchor, non-modal -- a tap on Other still presses it.
    let (root, build_error) = build(&frame, &theme, ctx, &subs[0usize], &subs[1usize], dialog_buttons[0usize..2usize], sheet_buttons[0usize..2usize], .Popup)
    if build_error != ok || testing.pump(&harness, root, now) != ok { os.exit(12i32) }
    let (anchor_bounds, has_anchor) = widget.bounds_of(&runtime, testing.by_key(&harness, 1u64).element)
    let (popup_bounds, has_popup) = testing.overlay_of(&harness, testing.by_key(&harness, 10u64).element)
    if !has_anchor || !has_popup || popup_bounds.y < anchor_bounds.y + anchor_bounds.height || testing.by_text(&harness, "Inside").count != 1usize { os.exit(13i32) }
    let (other_at, has_other) = centre_of(&harness, &runtime, 2u64)
    if !has_other || testing.tap(&harness, other_at.x, other_at.y) != ok || logs[0usize].presses != 1usize { os.exit(14i32) }
    // The flyout: a modal dialog named Options; a tap on Other dismisses instead of
    // pressing; Escape dismisses.
    let (root_2, build_2_error) = build(&frame, &theme, ctx, &subs[0usize], &subs[1usize], dialog_buttons[0usize..2usize], sheet_buttons[0usize..2usize], .Flyout)
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(15i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(16i32) }
    let (options_node, has_options) = find(tree_2, .Dialog, "Options")
    if !has_options || !options_node.state.modal { os.exit(17i32) }
    if testing.tap(&harness, other_at.x, other_at.y) != ok || logs[0usize].dismisses != 1usize || logs[0usize].presses != 1usize { os.exit(18i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].dismisses != 2usize { os.exit(19i32) }
    // The popover: to the right of the anchor, a heading Details and a close
    // button (keyed after it) that dismisses.
    let (root_3, build_3_error) = build(&frame, &theme, ctx, &subs[0usize], &subs[1usize], dialog_buttons[0usize..2usize], sheet_buttons[0usize..2usize], .Popover)
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(20i32) }
    let (tree_3, tree_3_error) = testing.semantics(&harness)
    if tree_3_error != ok { os.exit(21i32) }
    let (details, has_details) = find(tree_3, .Heading, "Details")
    let (popover_bounds, has_popover) = testing.overlay_of(&harness, testing.by_key(&harness, 30u64).element)
    if !has_details || !has_popover || popover_bounds.x < anchor_bounds.x + anchor_bounds.width { os.exit(22i32) }
    let (close_at, has_close) = centre_of(&harness, &runtime, 32u64)
    if !has_close || testing.tap(&harness, close_at.x, close_at.y) != ok || logs[0usize].dismisses != 3usize { os.exit(23i32) }
    // The dialog over any content: the focus lands on Cancel, so Enter presses it
    // (a focused button wins over the default, D818); Tab to OK and Enter confirms.
    let (root_4, build_4_error) = build(&frame, &theme, ctx, &subs[0usize], &subs[1usize], dialog_buttons[0usize..2usize], sheet_buttons[0usize..2usize], .Dialog)
    if build_4_error != ok || testing.pump(&harness, root_4, now) != ok { os.exit(24i32) }
    let (tree_4, tree_4_error) = testing.semantics(&harness)
    if tree_4_error != ok { os.exit(25i32) }
    let (confirm, has_confirm) = find(tree_4, .Dialog, "Confirm")
    if !has_confirm || testing.by_text(&harness, "Inside").count != 1usize { os.exit(26i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].dismisses != 4usize { os.exit(27i32) }
    if testing.tab(&harness, false) != ok || testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].confirms != 1usize { os.exit(27i32) }
    // The sheet: along the right edge, the window's height, named by its title.
    let (root_5, build_5_error) = build(&frame, &theme, ctx, &subs[0usize], &subs[1usize], dialog_buttons[0usize..2usize], sheet_buttons[0usize..2usize], .Sheet)
    if build_5_error != ok || testing.pump(&harness, root_5, now) != ok { os.exit(28i32) }
    let (sheet_bounds, has_sheet) = testing.overlay_of(&harness, testing.by_key(&harness, 50u64).element)
    if !has_sheet || sheet_bounds.x + sheet_bounds.width != 480.0 || sheet_bounds.width != 120.0 || sheet_bounds.height < 300.0 { os.exit(29i32) }
    let (tree_5, tree_5_error) = testing.semantics(&harness)
    if tree_5_error != ok { os.exit(30i32) }
    let (filters, has_filters) = find(tree_5, .Dialog, "Filters")
    if !has_filters || !filters.state.modal { os.exit(31i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].dismisses != 5usize { os.exit(32i32) }
    // The bottom sheet: along the bottom, the window's width, a hundred tall.
    let (root_6, build_6_error) = build(&frame, &theme, ctx, &subs[0usize], &subs[1usize], dialog_buttons[0usize..2usize], sheet_buttons[0usize..2usize], .Bottom)
    if build_6_error != ok || testing.pump(&harness, root_6, now) != ok { os.exit(33i32) }
    let (bottom_bounds, has_bottom) = testing.overlay_of(&harness, testing.by_key(&harness, 60u64).element)
    if !has_bottom || bottom_bounds.y + bottom_bounds.height != 320.0 || bottom_bounds.width != 480.0 || bottom_bounds.height != 100.0 { os.exit(34i32) }
    // The action sheet: Share and Delete then Cancel; Share fires; Cancel dismisses.
    let (root_7, build_7_error) = build(&frame, &theme, ctx, &subs[0usize], &subs[1usize], dialog_buttons[0usize..2usize], sheet_buttons[0usize..2usize], .Actions)
    if build_7_error != ok || testing.pump(&harness, root_7, now) != ok { os.exit(35i32) }
    let (share_at, has_share) = centre_of(&harness, &runtime, 73u64)
    if !has_share || testing.tap(&harness, share_at.x, share_at.y) != ok || logs[0usize].shares != 1usize { os.exit(36i32) }
    let (cancel_at, has_cancel) = centre_of(&harness, &runtime, 75u64)
    if !has_cancel || testing.tap(&harness, cancel_at.x, cancel_at.y) != ok || logs[0usize].dismisses != 6usize { os.exit(37i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(38i32) }
    try io.print("ui presentation ok\n")
    ret ok
}
