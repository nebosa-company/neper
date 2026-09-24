// `e.ui.navigation`'s productivity navigation (D853, widget plan P3-04): a wizard
// names its steps, disables Back on the first and Next while the step cannot be
// left, puts Finish on the last, and takes Enter and Escape; a window switcher
// and a command palette are modal panels in the middle whose Up and Down move
// the active row, whose Enter and taps pick, and whose Escape dismisses.

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
use e.ui.navigation
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { backs: usize, nexts: usize, finishes: usize, cancels: usize, activations: usize, active: usize, picks: usize, picked: usize, runs: usize, ran: usize, dismisses: usize, typed_len: usize }

fn on_back(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.backs += 1usize
    ret ok
}

fn on_next(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.nexts += 1usize
    ret ok
}

fn on_finish(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.finishes += 1usize
    ret ok
}

fn on_cancel(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.cancels += 1usize
    ret ok
}

fn on_activate(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.activations += 1usize
    log.active = value
    ret ok
}

fn on_pick(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.picks += 1usize
    log.picked = value
    ret ok
}

fn on_run(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.runs += 1usize
    log.ran = value
    ret ok
}

fn on_dismiss(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.dismisses += 1usize
    ret ok
}

fn on_typed(ctx: *void, value: str) -> err {
    let log = mem.cast[*Log](ctx)
    log.typed_len = value.len
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

type Handlers = struct { back: widget.Submit, next: widget.Submit, finish: widget.Submit, cancel: widget.Submit, dismiss: widget.Submit }

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, h: *const Handlers, buffer: []u8, current: usize, can_advance: bool, switcher_open: bool, palette_open: bool, active: usize) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, parts_error) }
    var steps: [3]str = zero
    steps[0usize] = "Account"
    steps[1usize] = "Address"
    steps[2usize] = "Review"
    let (page, page_error) = control.text(a, 0u64, "Step content", t, control.text_options())
    if page_error != ok { ret (zero, page_error) }
    let (guide, guide_error) = navigation.wizard(a, 1u64, t, "Setup", steps[..], current, page, can_advance, &h.back, &h.next, &h.finish, &h.cancel, 360.0, 200.0)
    if guide_error != ok { ret (zero, guide_error) }
    parts[0usize] = guide
    var windows: [3]str = zero
    windows[0usize] = "Inbox"
    windows[1usize] = "Draft"
    windows[2usize] = "Settings"
    let (switcher, switcher_error) = navigation.window_switcher(a, 20u64, t, "Windows", windows[..], active, switcher_open, widget.Change[usize] { ctx: ctx, invoke: on_activate }, widget.Change[usize] { ctx: ctx, invoke: on_pick }, &h.dismiss, 200.0)
    if switcher_error != ok { ret (zero, switcher_error) }
    parts[1usize] = switcher
    var commands: [2]str = zero
    commands[0usize] = "Save all"
    commands[1usize] = "Close all"
    let (palette, palette_error) = navigation.command_palette(a, 40u64, t, "Commands", buffer, 0usize, widget.Change[str] { ctx: ctx, invoke: on_typed }, commands[..], active, palette_open, widget.Change[usize] { ctx: ctx, invoke: on_activate }, widget.Change[usize] { ctx: ctx, invoke: on_run }, &h.dismiss, 240.0)
    if palette_error != ok { ret (zero, palette_error) }
    parts[2usize] = palette
    var column = style.defaults()
    column.width = style.Length { Px: 400.0 }
    column.height = style.Length { Px: 300.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, parts[0usize..3usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 200usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 512usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 400u32, 300u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (handlers, handlers_error) = mem.alloc[Handlers](a, 1usize)
    if handlers_error != ok { os.exit(8i32) }
    handlers[0usize] = Handlers { back: widget.Submit { ctx: ctx, invoke: on_back }, next: widget.Submit { ctx: ctx, invoke: on_next }, finish: widget.Submit { ctx: ctx, invoke: on_finish }, cancel: widget.Submit { ctx: ctx, invoke: on_cancel }, dismiss: widget.Submit { ctx: ctx, invoke: on_dismiss } }
    let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
    if buffer_error != ok { os.exit(9i32) }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(10i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    // The wizard on the first step, able to advance: three steps as list items,
    // the first current; Back disabled; Next enabled and fires; Enter is Next;
    // Escape cancels.
    let (root, build_error) = build(&frame, &theme, ctx, &handlers[0usize], buffer, 0usize, true, false, false, 0usize)
    if build_error != ok || testing.pump(&harness, root, now) != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    let (setup, has_setup) = find(tree, .Group, "Setup")
    if !has_setup || setup.position.row != 1u32 || setup.position.row_count != 3u32 { os.exit(13i32) }
    let (account, has_account) = find(tree, .ListItem, "Account")
    let (back_node, has_back) = find(tree, .Button, "Back")
    if !has_account || !account.state.current || !has_back || !back_node.state.disabled || testing.by_label(&harness, "Finish").count != 0usize { os.exit(14i32) }
    let (next_at, has_next) = centre_of(&harness, &runtime, 4u64)
    if !has_next || testing.tap(&harness, next_at.x, next_at.y) != ok || logs[0usize].nexts != 1usize { os.exit(15i32) }
    let (page_at, has_page) = centre_of(&harness, &runtime, 6u64)
    if !has_page || testing.tap(&harness, page_at.x, page_at.y) != ok { os.exit(16i32) }
    let (cancel_at, has_cancel) = centre_of(&harness, &runtime, 2u64)
    if !has_cancel || testing.tap(&harness, cancel_at.x, cancel_at.y) != ok || logs[0usize].cancels != 1usize { os.exit(17i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].cancels != 2usize { os.exit(18i32) }
    // On the last step, unable to advance: Finish stands disabled and Enter does
    // nothing; Back fires; the first step is named done (D974: a check marker).
    let (root_2, build_2_error) = build(&frame, &theme, ctx, &handlers[0usize], buffer, 2usize, false, false, false, 0usize)
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(19i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(20i32) }
    let (finish_node, has_finish) = find(tree_2, .Button, "Finish")
    if !has_finish || !finish_node.state.disabled || testing.by_label(&harness, "Account, completed").count == 0usize || testing.by_label(&harness, "Next").count != 0usize { os.exit(21i32) }
    let (back_at, has_back_at) = centre_of(&harness, &runtime, 3u64)
    if !has_back_at || testing.tap(&harness, back_at.x, back_at.y) != ok || logs[0usize].backs != 1usize { os.exit(22i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].finishes != 0usize { os.exit(23i32) }
    // Able to advance on the last step: Finish fires, and Enter from the page
    // finishes again.
    let (root_3, build_3_error) = build(&frame, &theme, ctx, &handlers[0usize], buffer, 2usize, true, false, false, 0usize)
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(24i32) }
    let (finish_at, has_finish_at) = centre_of(&harness, &runtime, 5u64)
    if !has_finish_at || testing.tap(&harness, finish_at.x, finish_at.y) != ok || logs[0usize].finishes != 1usize { os.exit(25i32) }
    if testing.tap(&harness, page_at.x, page_at.y) != ok || testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].finishes != 2usize { os.exit(26i32) }
    // The switcher: a modal dialog named Windows with three rows, the first
    // active; Down activates 1; Enter picks the (still) first; a tap on the third
    // picks 2; Escape dismisses.
    let (root_4, build_4_error) = build(&frame, &theme, ctx, &handlers[0usize], buffer, 2usize, true, true, false, 0usize)
    if build_4_error != ok || testing.pump(&harness, root_4, now) != ok { os.exit(27i32) }
    let (tree_4, tree_4_error) = testing.semantics(&harness)
    if tree_4_error != ok { os.exit(28i32) }
    let (windows_node, has_windows) = find(tree_4, .Dialog, "Windows")
    // The wizard's three steps are list items too.
    let (inbox_row, has_inbox) = find(tree_4, .ListItem, "Inbox")
    if !has_windows || !windows_node.state.modal || !has_inbox || testing.by_role(&harness, .ListItem).count != 6usize { os.exit(29i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || logs[0usize].activations != 1usize || logs[0usize].active != 1usize { os.exit(30i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].picks != 1usize || logs[0usize].picked != 0usize { os.exit(31i32) }
    let (third_at, has_third) = centre_of(&harness, &runtime, 24u64)
    if !has_third || testing.tap(&harness, third_at.x, third_at.y) != ok || logs[0usize].picks != 2usize || logs[0usize].picked != 2usize { os.exit(32i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].dismisses != 1usize { os.exit(33i32) }
    // The palette: a modal dialog named Commands with a search field the focus
    // lands on; typed text reaches the caller; Down activates 1; Enter runs the
    // (still) first; a press outside dismisses.
    let (root_5, build_5_error) = build(&frame, &theme, ctx, &handlers[0usize], buffer, 2usize, true, false, true, 0usize)
    if build_5_error != ok || testing.pump(&harness, root_5, now) != ok { os.exit(34i32) }
    let (tree_5, tree_5_error) = testing.semantics(&harness)
    if tree_5_error != ok { os.exit(35i32) }
    let (commands_node, has_commands) = find(tree_5, .Dialog, "Commands")
    if !has_commands || testing.by_role(&harness, .TextField).count != 1usize || testing.by_text(&harness, "Type a command").count != 1usize { os.exit(36i32) }
    if testing.type_text(&harness, "sa") != ok || logs[0usize].typed_len != 2usize { os.exit(37i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || logs[0usize].active != 1usize { os.exit(38i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].runs != 1usize || logs[0usize].ran != 0usize { os.exit(39i32) }
    if testing.tap(&harness, 2.0, 298.0) != ok || logs[0usize].dismisses != 2usize { os.exit(40i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(41i32) }
    try io.print("ui productivity ok\n")
    ret ok
}
