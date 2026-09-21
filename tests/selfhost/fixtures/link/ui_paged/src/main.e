// `e.ui.collection`'s paged collections (D835, widget plan P2-06) under the light
// theme: a page view shows one page, turns once per swipe past a quarter of its
// width and on the arrow keys from the focused view; a page indicator's dots turn
// to their page; pagination's numbers, Previous and Next turn and disable at the
// ends; a carousel is all three sharing one turn.

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

type Log = struct { turns: usize, page: usize, jumps: usize, jump: usize, leafs: usize, leaf: usize }

fn on_turn(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.turns += 1usize
    log.page = value
    ret ok
}

fn on_jump(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.jumps += 1usize
    log.jump = value
    ret ok
}

fn on_leaf(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.leafs += 1usize
    log.leaf = value
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

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, current: usize, leaf: usize) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 3usize)
    if parts_error != ok { ret (zero, parts_error) }
    var pages: [3]widget.Node = zero
    let (one, one_error) = control.text(a, 0u64, "Page one", t, control.text_options())
    if one_error != ok { ret (zero, one_error) }
    let (two, two_error) = control.text(a, 0u64, "Page two", t, control.text_options())
    if two_error != ok { ret (zero, two_error) }
    let (three, three_error) = control.text(a, 0u64, "Page three", t, control.text_options())
    if three_error != ok { ret (zero, three_error) }
    pages[0usize] = one
    pages[1usize] = two
    pages[2usize] = three
    let (spread, spread_error) = collection.carousel(a, 1u64, t, pages[..], current, widget.Change[usize] { ctx: ctx, invoke: on_turn }, 200.0, 60.0)
    if spread_error != ok { ret (zero, spread_error) }
    parts[0usize] = spread
    let (dots, dots_error) = collection.page_indicator(a, 20u64, t, 4usize, 1usize, widget.Change[usize] { ctx: ctx, invoke: on_jump })
    if dots_error != ok { ret (zero, dots_error) }
    parts[1usize] = dots
    let (pages_bar, pages_error) = collection.pagination(a, 30u64, t, "Pages", 20usize, leaf, 5usize, widget.Change[usize] { ctx: ctx, invoke: on_leaf })
    if pages_error != ok { ret (zero, pages_error) }
    parts[2usize] = pages_bar
    var column = style.defaults()
    column.width = style.Length { Px: 400.0 }
    column.height = style.Length { Px: 300.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, column, parts[0usize..3usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 160usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 14u16, max_commands: 400usize })
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
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(8i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, ctx, 0usize, 0usize)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(10i32) }
    // The carousel on page one: the page alone, Previous disabled; a swipe on the
    // first frame turns nothing (no cell yet); built and pumped again, a swipe
    // left past a quarter of the width turns to page two once, however far it
    // goes on.
    if testing.by_text(&harness, "Page one").count != 1usize || testing.by_text(&harness, "Page two").count != 0usize { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    let (back, has_back) = find(tree, .Button, "<")
    if !has_back || !back.state.disabled { os.exit(13i32) }
    let (view_at, has_view) = centre_of(&harness, &runtime, 1u64)
    if !has_view { os.exit(14i32) }
    if testing.drag(&harness, view_at, geometry.Point { x: view_at.x - 80.0, y: view_at.y }, 4usize) != ok || logs[0usize].turns != 0usize { os.exit(15i32) }
    let (root_b, build_b_error) = build(&frame, &theme, ctx, 0usize, 0usize)
    if build_b_error != ok || testing.pump(&harness, root_b, now) != ok { os.exit(16i32) }
    if testing.drag(&harness, view_at, geometry.Point { x: view_at.x - 80.0, y: view_at.y }, 8usize) != ok { os.exit(17i32) }
    if logs[0usize].turns != 1usize || logs[0usize].page != 1usize { os.exit(18i32) }
    // A short swipe turns nothing; Right from the focused view turns to two; Left
    // on page one turns to one again (the caller's page is still one).
    if testing.drag(&harness, view_at, geometry.Point { x: view_at.x - 20.0, y: view_at.y }, 2usize) != ok || logs[0usize].turns != 1usize { os.exit(19i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || logs[0usize].turns != 2usize || logs[0usize].page != 1usize { os.exit(20i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || logs[0usize].turns != 3usize || logs[0usize].page != 0usize { os.exit(21i32) }
    // Next turns to two; the third dot (keyed after the view and the buttons)
    // turns to three.
    let (next_at, has_next) = centre_of(&harness, &runtime, 3u64)
    if !has_next || testing.tap(&harness, next_at.x, next_at.y) != ok || logs[0usize].page != 1usize { os.exit(22i32) }
    let (third_dot, has_third) = centre_of(&harness, &runtime, 7u64)
    if !has_third || testing.tap(&harness, third_dot.x, third_dot.y) != ok || logs[0usize].page != 2usize { os.exit(23i32) }
    // On page three: Next is disabled, the page shows, the third dot is selected.
    let (root_2, build_2_error) = build(&frame, &theme, ctx, 2usize, 7usize)
    if build_2_error != ok { os.exit(24i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(25i32) }
    if testing.by_text(&harness, "Page three").count != 1usize || testing.by_text(&harness, "Page one").count != 0usize { os.exit(26i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(27i32) }
    let (forward, has_forward) = find(tree_2, .Button, ">")
    if !has_forward || !forward.state.disabled { os.exit(28i32) }
    var selected_tabs = 0usize
    var i = 0usize
    while i < tree_2.nodes.len {
        if tree_2.nodes[i].role == .Tab && tree_2.nodes[i].state.selected && tree_2.nodes[i].position.column == 3u32 && tree_2.nodes[i].position.column_count == 3u32 { selected_tabs += 1usize }
        i += 1usize
    }
    if selected_tabs != 1usize { os.exit(29i32) }
    // The standalone indicator of four with the second current: a tap on the
    // fourth dot jumps to it.
    let (fourth_dot, has_fourth) = centre_of(&harness, &runtime, 24u64)
    if !has_fourth || testing.tap(&harness, fourth_dot.x, fourth_dot.y) != ok || logs[0usize].jumps != 1usize || logs[0usize].jump != 3usize { os.exit(30i32) }
    // Pagination of twenty at page eight with a window of five: pages six to ten
    // shown, eight selected; ten (keyed by its index) turns to it; Previous turns
    // to seven; the group says eight of twenty.
    let (pages_node, has_pages) = find(tree_2, .Group, "Pages")
    if !has_pages || pages_node.position.row != 8u32 || pages_node.position.row_count != 20u32 { os.exit(31i32) }
    if testing.by_text(&harness, "6").count == 0usize || testing.by_text(&harness, "10").count == 0usize || testing.by_text(&harness, "11").count != 0usize { os.exit(32i32) }
    let (eight, has_eight) = find(tree_2, .Button, "8")
    if !has_eight || !eight.state.selected { os.exit(33i32) }
    let (ten_at, has_ten) = centre_of(&harness, &runtime, 30u64 + 3u64 + 9u64)
    if !has_ten || testing.tap(&harness, ten_at.x, ten_at.y) != ok || logs[0usize].leafs != 1usize || logs[0usize].leaf != 9usize { os.exit(34i32) }
    let (previous_at, has_previous) = centre_of(&harness, &runtime, 31u64)
    if !has_previous || testing.tap(&harness, previous_at.x, previous_at.y) != ok || logs[0usize].leaf != 6usize { os.exit(35i32) }
    // At the last page Next is disabled and the window ends at twenty.
    let (root_3, build_3_error) = build(&frame, &theme, ctx, 2usize, 19usize)
    if build_3_error != ok { os.exit(36i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(37i32) }
    let (tree_3, tree_3_error) = testing.semantics(&harness)
    if tree_3_error != ok { os.exit(38i32) }
    let (last_next, has_last_next) = find(tree_3, .Button, "Next")
    if !has_last_next || !last_next.state.disabled || testing.by_text(&harness, "16").count == 0usize || testing.by_text(&harness, "20").count == 0usize { os.exit(39i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(40i32) }
    try io.print("ui paged ok\n")
    ret ok
}
