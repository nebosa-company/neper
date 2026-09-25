// `e.ui.collection`'s collection interaction (D839, widget plan P2-07) under the
// light theme: a reorderable list reports a move from the dragged row's index to
// the row under the drop and by one on Alt+Up and Alt+Down from the focused row; a
// pull past a third of the height refreshes once per pull and the Refresh button
// is the same action; a swipe left reveals a row's actions once per swipe, a swipe
// right hides them, and the More button reveals for a keyboard.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.collection
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { moves: usize, from: usize, to: usize, refreshes: usize, reveals: usize, revealed: bool, deletes: usize }

fn on_move(ctx: *void, value: collection.Reorder) -> err {
    let log = mem.cast[*Log](ctx)
    log.moves += 1usize
    log.from = value.from
    log.to = value.to
    ret ok
}

fn on_refresh(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.refreshes += 1usize
    ret ok
}

fn on_reveal(ctx: *void, value: bool) -> err {
    let log = mem.cast[*Log](ctx)
    log.reveals += 1usize
    log.revealed = value
    ret ok
}

fn on_delete(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.deletes += 1usize
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

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, refresh: *const widget.Submit, deletes: []const widget.Submit, refreshing: bool, revealed: bool) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, parts_error) }
    var items: [3]widget.Node = zero
    var keys: [3]widget.Key = zero
    let (one, one_error) = control.text(a, 0u64, "Alpha", t, control.text_options())
    if one_error != ok { ret (zero, one_error) }
    let (two, two_error) = control.text(a, 0u64, "Beta", t, control.text_options())
    if two_error != ok { ret (zero, two_error) }
    let (three, three_error) = control.text(a, 0u64, "Gamma", t, control.text_options())
    if three_error != ok { ret (zero, three_error) }
    items[0usize] = one
    items[1usize] = two
    items[2usize] = three
    keys[0usize] = 101u64
    keys[1usize] = 102u64
    keys[2usize] = 103u64
    let (ordered, ordered_error) = collection.reorderable_list(a, 1u64, t, "Greek", items[..], keys[..], 30.0, widget.Change[collection.Reorder] { ctx: ctx, invoke: on_move }, 200.0)
    if ordered_error != ok { ret (zero, ordered_error) }
    parts[0usize] = ordered
    let (inbox, inbox_error) = control.text(a, 0u64, "Inbox", t, control.text_options())
    if inbox_error != ok { ret (zero, inbox_error) }
    let (pulled, pulled_error) = collection.pull_to_refresh(a, 10u64, t, inbox, refreshing, refresh, 200.0, 90.0)
    if pulled_error != ok { ret (zero, pulled_error) }
    parts[1usize] = pulled
    let (mail, mail_error) = control.text(a, 0u64, "A letter", t, control.text_options())
    if mail_error != ok { ret (zero, mail_error) }
    var labels: [1]str = zero
    labels[0usize] = "Delete"
    let (swiped, swiped_error) = collection.swipe_actions(a, 20u64, t, mail, labels[..], deletes, revealed, widget.Change[bool] { ctx: ctx, invoke: on_reveal }, 200.0, 40.0)
    if swiped_error != ok { ret (zero, swiped_error) }
    parts[2usize] = swiped
    var column = style.defaults()
    column.width = style.Length { Px: 240.0 }
    column.height = style.Length { Px: 300.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, parts[0usize..3usize]), ok)
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
    let (h, harness_error) = testing.harness(a, &runtime, 240u32, 300u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { os.exit(8i32) }
    actions[0usize] = widget.Submit { ctx: ctx, invoke: on_refresh }
    actions[1usize] = widget.Submit { ctx: ctx, invoke: on_delete }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(9i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, ctx, &actions[0usize], actions[1usize..2usize], false, false)
    if build_error != ok { os.exit(10i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(11i32) }
    // Built and pumped once more so the swipe cells exist.
    let (root_2, build_2_error) = build(&frame, &theme, ctx, &actions[0usize], actions[1usize..2usize], false, false)
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(12i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(13i32) }
    // The list: three list items under a list named Greek; dragging Alpha down two
    // rows reports a move from 0 to 2; a drop on its own row reports nothing.
    let (greek, has_greek) = find(tree, .List, "Greek")
    if !has_greek || greek.position.row_count != 3u32 { os.exit(14i32) }
    let (alpha_at, has_alpha) = centre_of(&harness, &runtime, 101u64)
    if !has_alpha || testing.drag(&harness, alpha_at, geometry.Point { x: alpha_at.x, y: alpha_at.y + 60.0 }, 6usize) != ok { os.exit(15i32) }
    if logs[0usize].moves != 1usize || logs[0usize].from != 0usize || logs[0usize].to != 2usize { os.exit(16i32) }
    if testing.drag(&harness, alpha_at, geometry.Point { x: alpha_at.x + 5.0, y: alpha_at.y + 12.0 }, 2usize) != ok || logs[0usize].moves != 1usize { os.exit(17i32) }
    // Alt+Down from the focused Alpha reports 0 to 1; Alt+Up at the top reports
    // nothing; Down without Alt is not a move.
    var alt: input.Modifiers = zero
    alt.alt = true
    if testing.press_key(&harness, 40u32, alt) != ok || logs[0usize].moves != 2usize || logs[0usize].from != 0usize || logs[0usize].to != 1usize { os.exit(18i32) }
    if testing.press_key(&harness, 38u32, alt) != ok || logs[0usize].moves != 2usize { os.exit(19i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || logs[0usize].moves != 2usize { os.exit(20i32) }
    // Pull to refresh: a pull of a third of the height refreshes once, a short one
    // not at all; the Refresh button refreshes; refreshing, a ring stands and the
    // group is busy.
    let (inbox_at, has_inbox) = centre_of(&harness, &runtime, 10u64)
    if !has_inbox || testing.drag(&harness, geometry.Point { x: inbox_at.x, y: inbox_at.y - 30.0 }, geometry.Point { x: inbox_at.x, y: inbox_at.y + 30.0 }, 6usize) != ok { os.exit(21i32) }
    if logs[0usize].refreshes != 1usize { os.exit(22i32) }
    if testing.drag(&harness, geometry.Point { x: inbox_at.x, y: inbox_at.y - 10.0 }, geometry.Point { x: inbox_at.x, y: inbox_at.y + 5.0 }, 2usize) != ok || logs[0usize].refreshes != 1usize { os.exit(23i32) }
    let (again_at, has_again) = centre_of(&harness, &runtime, 11u64)
    if !has_again || testing.tap(&harness, again_at.x, again_at.y) != ok || logs[0usize].refreshes != 2usize { os.exit(24i32) }
    let (root_3, build_3_error) = build(&frame, &theme, ctx, &actions[0usize], actions[1usize..2usize], true, false)
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(25i32) }
    let (tree_3, tree_3_error) = testing.semantics(&harness)
    if tree_3_error != ok { os.exit(26i32) }
    let (ring, has_ring) = find(tree_3, .Progress, "Refreshing")
    if !has_ring || !ring.state.busy { os.exit(27i32) }
    // Swipe actions: hidden, a More button and no Delete; a swipe left reveals
    // once; revealed, Delete stands and fires, and a swipe right hides.
    if testing.by_label(&harness, "Delete").count != 0usize || testing.by_label(&harness, "More").count == 0usize { os.exit(28i32) }
    let (mail_at, has_mail) = centre_of(&harness, &runtime, 20u64)
    if !has_mail || testing.drag(&harness, mail_at, geometry.Point { x: mail_at.x - 70.0, y: mail_at.y }, 7usize) != ok { os.exit(29i32) }
    if logs[0usize].reveals != 1usize || !logs[0usize].revealed { os.exit(30i32) }
    let (root_4, build_4_error) = build(&frame, &theme, ctx, &actions[0usize], actions[1usize..2usize], false, true)
    if build_4_error != ok || testing.pump(&harness, root_4, now) != ok { os.exit(31i32) }
    if testing.by_label(&harness, "More").count != 0usize { os.exit(32i32) }
    let (delete_at, has_delete) = centre_of(&harness, &runtime, 22u64)
    if !has_delete || testing.tap(&harness, delete_at.x, delete_at.y) != ok || logs[0usize].deletes != 1usize || logs[0usize].reveals != 2usize || logs[0usize].revealed { os.exit(33i32) }
    // Reveal once more, then a swipe right closes without running an action.
    let (root_action_closed, root_action_closed_error) = build(&frame, &theme, ctx, &actions[0usize], actions[1usize..2usize], false, false)
    if root_action_closed_error != ok || testing.pump(&harness, root_action_closed, now) != ok { os.exit(39i32) }
    let (more_again, has_more_again) = centre_of(&harness, &runtime, 21u64)
    if !has_more_again || testing.tap(&harness, more_again.x, more_again.y) != ok || logs[0usize].reveals != 3usize || !logs[0usize].revealed { os.exit(40i32) }
    let (root_again, root_again_error) = build(&frame, &theme, ctx, &actions[0usize], actions[1usize..2usize], false, true)
    if root_again_error != ok || testing.pump(&harness, root_again, now) != ok { os.exit(41i32) }
    let (mail_2_at, has_mail_2) = centre_of(&harness, &runtime, 20u64)
    if !has_mail_2 || testing.drag(&harness, mail_2_at, geometry.Point { x: mail_2_at.x + 70.0, y: mail_2_at.y }, 7usize) != ok { os.exit(34i32) }
    if logs[0usize].reveals != 4usize || logs[0usize].revealed { os.exit(35i32) }
    // Hidden again, More reveals for a keyboard.
    let (root_5, build_5_error) = build(&frame, &theme, ctx, &actions[0usize], actions[1usize..2usize], false, false)
    if build_5_error != ok || testing.pump(&harness, root_5, now) != ok { os.exit(36i32) }
    let (more_at, has_more) = centre_of(&harness, &runtime, 21u64)
    if !has_more || testing.tap(&harness, more_at.x, more_at.y) != ok || logs[0usize].reveals != 5usize || !logs[0usize].revealed { os.exit(37i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(38i32) }
    try io.print("ui interaction ok\n")
    ret ok
}
