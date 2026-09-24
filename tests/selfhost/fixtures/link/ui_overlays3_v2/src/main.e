// The v2 dialogs, sheets and action sheets (D977, widget plan P5-11,
// docs/ux/components/Dialog, Sheet, ActionSheet) under the light theme at
// pointer density: an alert dialog over a 32% scrim, its card
// `surface-container-high` 280 wide at least, 24 in, its level-2 title labelling
// it, the destructive action filled in `error`, the default filled in `primary`
// at the end, Escape and the scrim cancelling; a side sheet on
// `surface-container-low` along the right edge, its open edge rounded, a 48
// header with a 32 Close; a bottom sheet with its top corners rounded and the
// drag handle 16 down; an action sheet as tall as its rows, 48 each, the
// destructive one after a divider, Cancel last.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Counter = struct { count: usize }

// The counters: 0 cancel, 1 delete, 2 keep, 3 dismiss, 4 share.
type Store = struct { counters: [8]Counter, subs: [8]widget.Submit, buttons: [3]overlay.DialogButton, actions: [3]overlay.DialogButton }

type Which = enum u8 { Dialog, Side, Bottom, Actions }

fn on_count(ctx: *void) -> err {
    let c = mem.cast[*Counter](ctx)
    c.count += 1usize
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
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

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store, which: Which) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 4usize)
    if items_error != ok { ret (zero, items_error) }
    let (inside, e1) = control.text(a, 0u64, "Inside", t, control.text_options())
    let (alert, e2) = overlay.alert_dialog(a, 100u64, t, "Delete build?", "The artifacts go too.", s.buttons[0usize..3usize], which == .Dialog)
    let (side, e3) = overlay.sheet(a, 200u64, t, "Details", inside, which == .Side, &s.subs[3usize], 300.0)
    let (bottom, e4) = overlay.bottom_sheet(a, 300u64, t, "Share", inside, which == .Bottom, &s.subs[3usize], 200.0)
    let (actions, e5) = overlay.action_sheet(a, 400u64, t, "build-4128.zip", s.actions[0usize..3usize], which == .Actions, &s.subs[3usize])
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (zero, e1) }
    items[0usize] = alert
    items[1usize] = side
    items[2usize] = bottom
    items[3usize] = actions
    var page_style = style.defaults()
    page_style.width = style.Length { Px: 640.0 }
    page_style.height = style.Length { Px: 480.0 }
    page_style.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page_style, items[0usize..4usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 640usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn lifted(h: *testing.Harness, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = testing.overlay_of(h, testing.by_key(h, key).element)
    ret (b, found)
}

fn tap_key(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let (b, found) = bounds(h, runtime, key)
    if !found { ret false }
    ret testing.tap(h, b.x + b.width * 0.5, b.y + b.height * 0.5) == ok
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 800usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 40u16, max_commands: 8192usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 480u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    var i = 0usize
    while i < 8usize {
        s.subs[i] = widget.Submit { ctx: mem.cast[*void](&s.counters[i]), invoke: on_count }
        i += 1usize
    }
    s.buttons[0usize] = overlay.DialogButton { label: "Cancel", action: s.subs[0usize], kind: .Cancel }
    s.buttons[1usize] = overlay.DialogButton { label: "Delete", action: s.subs[1usize], kind: .Destructive }
    s.buttons[2usize] = overlay.DialogButton { label: "Keep", action: s.subs[2usize], kind: .Default }
    s.actions[0usize] = overlay.DialogButton { label: "Share", action: s.subs[4usize], kind: .Plain }
    s.actions[1usize] = overlay.DialogButton { label: "Download", action: s.subs[4usize], kind: .Plain }
    s.actions[2usize] = overlay.DialogButton { label: "Delete", action: s.subs[1usize], kind: .Destructive }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let page = style.color(&tokens, .Background)
    let dimmed = style.layer(page, style.color(&tokens, .Scrim), tokens.states.scrim)
    // The alert dialog: the scrim across the window; the card centred, 280 wide
    // at least, `surface-container-high`, 24 in all round (104 tall over empty
    // text: 24, the title, 16, the message, 8, a 32 row, 24).
    let (root, build_error) = build(&f, &theme, s, .Dialog)
    if build_error != ok || testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(9i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(10i32) }
    let (card, has_card) = lifted(&harness, 100u64)
    if !has_card || card.width < 280.0 || !near(card.x + card.width * 0.5, 320.0) || !near(card.height, 104.0) { os.exit(11i32) }
    if !is_color(shot, at(5.0, 5.0), dimmed) || !is_color(shot, at(card.x + card.width * 0.5, card.y + 10.0), style.color(&tokens, .SurfaceContainerHigh)) { os.exit(12i32) }
    // The buttons at the end, 8 apart: Delete filled in `error`, Keep in
    // `primary` last, 24 from the card's end; Cancel a text button.
    let (cancel, has_cancel) = bounds(&harness, &runtime, 103u64)
    let (delete, has_delete) = bounds(&harness, &runtime, 104u64)
    let (keep, has_keep) = bounds(&harness, &runtime, 105u64)
    if !has_cancel || !has_delete || !has_keep || !near(keep.x + keep.width, card.x + card.width - 24.0) || !near(keep.x, delete.x + delete.width + 8.0) || !near(keep.y + keep.height, card.y + card.height - 24.0) { os.exit(13i32) }
    if !is_color(shot, at(delete.x + delete.width * 0.5, delete.y + delete.height * 0.5), style.color(&tokens, .Error)) || !is_color(shot, at(keep.x + keep.width * 0.5, keep.y + keep.height * 0.5), style.color(&tokens, .Primary)) { os.exit(14i32) }
    if !is_color(shot, at(cancel.x + cancel.width * 0.5, cancel.y + cancel.height * 0.5), style.color(&tokens, .SurfaceContainerHigh)) { os.exit(15i32) }
    // The tree: a modal dialog labelled by its level-2 title.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(16i32) }
    let (dialog, has_dialog) = find(tree, .Dialog, "Delete build?")
    let (heading, has_heading) = find(tree, .Heading, "Delete build?")
    if !has_dialog || !dialog.state.modal || dialog.relations.labelled_by.generation == 0u32 || !has_heading || heading.level != 2u8 { os.exit(17i32) }
    // Escape cancels, a press on the scrim cancels, Delete deletes.
    if testing.press_key(&harness, 27u32, zero) != ok || s.counters[0usize].count != 1usize { os.exit(18i32) }
    if testing.tap(&harness, 5.0, 5.0) != ok || s.counters[0usize].count != 2usize { os.exit(19i32) }
    if !tap_key(&harness, &runtime, 104u64) || s.counters[1usize].count != 1usize { os.exit(20i32) }
    // The side sheet: 300 wide along the right edge, the window's height,
    // `surface-container-low`, its open edge's corners rounded; a 48 header
    // with a 32 Close 8 from the end that dismisses.
    let (root_2, build_2_error) = build(&f, &theme, s, .Side)
    if build_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(21i32) }
    let (shot_2, shot_2_error) = testing.snapshot(&harness, a)
    if shot_2_error != ok { os.exit(22i32) }
    let (side, has_side) = lifted(&harness, 200u64)
    if !has_side || !near(side.x + side.width, 640.0) || !near(side.width, 300.0) || !near(side.height, 480.0) { os.exit(23i32) }
    if !is_color(shot_2, at(side.x + 150.0, side.y + 100.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot_2, at(side.x + 1.0, side.y + 1.0), dimmed) || !is_color(shot_2, at(side.x + side.width - 1.0, side.y + 1.0), style.color(&tokens, .SurfaceContainerLow)) { os.exit(24i32) }
    let (closer, has_closer) = bounds(&harness, &runtime, 202u64)
    if !has_closer || !near(closer.width, 32.0) || !near(closer.x + closer.width, 632.0) || !near(closer.y + 16.0, side.y + 24.0) { os.exit(25i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(26i32) }
    let (details, has_details) = find(tree_2, .Dialog, "Details")
    let (close_node, has_close_node) = find(tree_2, .Button, "Close")
    if !has_details || details.relations.labelled_by.generation == 0u32 || !has_close_node { os.exit(27i32) }
    if !tap_key(&harness, &runtime, 202u64) || s.counters[3usize].count != 1usize { os.exit(28i32) }
    // The bottom sheet: 200 tall along the bottom, its top corners rounded, the
    // handle 16 down in `on-surface-variant` at 40%; no Close.
    let (root_3, build_3_error) = build(&f, &theme, s, .Bottom)
    if build_3_error != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1200000000i64 }) != ok { os.exit(29i32) }
    let (shot_3, shot_3_error) = testing.snapshot(&harness, a)
    if shot_3_error != ok { os.exit(30i32) }
    let (bottom, has_bottom) = lifted(&harness, 300u64)
    if !has_bottom || !near(bottom.y + bottom.height, 480.0) || !near(bottom.height, 200.0) || !near(bottom.width, 640.0) { os.exit(31i32) }
    let low = style.color(&tokens, .SurfaceContainerLow)
    if !is_color(shot_3, at(320.0, bottom.y + 100.0), low) || !is_color(shot_3, at(2.0, bottom.y + 2.0), dimmed) { os.exit(32i32) }
    if !is_color(shot_3, at(320.0, bottom.y + 17.5), style.layer(low, style.color(&tokens, .OnSurfaceVariant), 0.4)) || !is_color(shot_3, at(320.0, bottom.y + 22.0), low) { os.exit(33i32) }
    if testing.by_key(&harness, 302u64).count != 0usize { os.exit(34i32) }
    // The action sheet: as tall as its content (the handle 20, the header 28,
    // rows of 48, dividers of 17, 8 below); a divider before Delete; Share runs,
    // Cancel dismisses.
    let (root_4, build_4_error) = build(&f, &theme, s, .Actions)
    if build_4_error != ok || testing.pump(&harness, root_4, time.Instant { nanos: 1300000000i64 }) != ok { os.exit(35i32) }
    let (shot_4, shot_4_error) = testing.snapshot(&harness, a)
    if shot_4_error != ok { os.exit(36i32) }
    let (acts, has_acts) = lifted(&harness, 400u64)
    if !has_acts || !near(acts.y + acts.height, 480.0) || !near(acts.height, 282.0) { os.exit(37i32) }
    let (share, has_share) = bounds(&harness, &runtime, 403u64)
    let (download, has_download) = bounds(&harness, &runtime, 404u64)
    if !has_share || !has_download || !near(share.height, 48.0) || !near(share.y, acts.y + 48.0) || !near(download.y, share.y + 48.0) { os.exit(38i32) }
    if !is_color(shot_4, at(320.0, download.y + 56.5), style.color(&tokens, .OutlineVariant)) || !is_color(shot_4, at(320.0, download.y + 52.0), low) { os.exit(39i32) }
    if !tap_key(&harness, &runtime, 403u64) || s.counters[4usize].count != 1usize { os.exit(40i32) }
    if !tap_key(&harness, &runtime, 406u64) || s.counters[3usize].count != 2usize { os.exit(41i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(42i32) }
    try io.print("ui overlays3 v2 ok\n")
    ret ok
}
