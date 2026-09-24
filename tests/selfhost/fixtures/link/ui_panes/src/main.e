// `e.ui.control`'s disclosure and panes (D826, widget plan P1-13) under the light
// theme: a disclosure hides its content until expanded and its header says which;
// an expander is the same on a surface; a tab list's tabs pick, the selected one is
// selected in the tree and the arrow keys pick the neighbours; a tab view shows the
// selected page alone; a split view's handle is dragged and nudged by the keyboard
// within its limits, reporting the first pane's size.

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
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { toggles: usize, picks: usize, last_pick: usize, sizes: usize, last_size: f32 }
type Pick = struct { log: *Log, index: usize }

fn on_toggle(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    ret ok
}

fn on_pick(ctx: *void) -> err {
    let pick = mem.cast[*Pick](ctx)
    pick.log.picks += 1usize
    pick.log.last_pick = pick.index
    ret ok
}

fn on_size(ctx: *void, value: f32) -> err {
    let log = mem.cast[*Log](ctx)
    log.sizes += 1usize
    log.last_size = value
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

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.5 && d > -0.5
}

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, toggle: *const widget.Submit, picks: []const widget.Submit, expanded: bool, selected: usize, position: f32) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 4usize)
    if items_error != ok { ret (zero, items_error) }
    var caption = control.text_options()
    let (hidden, hidden_error) = control.text(a, 0u64, "Hidden text", t, caption)
    if hidden_error != ok { ret (zero, hidden_error) }
    let (opened, opened_error) = control.disclosure(a, 1u64, t, "Details", expanded, toggle, hidden)
    if opened_error != ok { ret (zero, opened_error) }
    items[0usize] = opened
    let (more, more_error) = control.text(a, 0u64, "More text", t, caption)
    if more_error != ok { ret (zero, more_error) }
    let (boxed, boxed_error) = control.expander(a, 5u64, t, "More", expanded, toggle, more)
    if boxed_error != ok { ret (zero, boxed_error) }
    items[1usize] = boxed
    var labels: [3]str = zero
    labels[0usize] = "One"
    labels[1usize] = "Two"
    labels[2usize] = "Three"
    var pages: [3]widget.Node = zero
    let (page_one, page_one_error) = control.text(a, 0u64, "Page one", t, caption)
    if page_one_error != ok { ret (zero, page_one_error) }
    let (page_two, page_two_error) = control.text(a, 0u64, "Page two", t, caption)
    if page_two_error != ok { ret (zero, page_two_error) }
    let (page_three, page_three_error) = control.text(a, 0u64, "Page three", t, caption)
    if page_three_error != ok { ret (zero, page_three_error) }
    pages[0usize] = page_one
    pages[1usize] = page_two
    pages[2usize] = page_three
    let (view, view_error) = control.tab_view(a, 10u64, t, labels[..], selected, picks, pages[..])
    if view_error != ok { ret (zero, view_error) }
    items[2usize] = view
    let (left, left_error) = control.text(a, 0u64, "Left", t, caption)
    if left_error != ok { ret (zero, left_error) }
    let (right, right_error) = control.text(a, 0u64, "Right", t, caption)
    if right_error != ok { ret (zero, right_error) }
    let (split, split_error) = control.split_view(a, 20u64, t, .Horizontal, left, right, position, 40.0, 40.0, widget.Change[f32] { ctx: ctx, invoke: on_size }, 300.0, 60.0)
    if split_error != ok { ret (zero, split_error) }
    items[3usize] = split
    var column = style.defaults()
    column.width = style.Length { Px: 320.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, items[0usize..4usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 96usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 12u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 400u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (toggles, toggles_error) = mem.alloc[widget.Submit](a, 1usize)
    if toggles_error != ok { os.exit(8i32) }
    toggles[0usize] = widget.Submit { ctx: ctx, invoke: on_toggle }
    let (pick_targets, pick_targets_error) = mem.alloc[Pick](a, 3usize)
    if pick_targets_error != ok { os.exit(9i32) }
    let (picks, picks_error) = mem.alloc[widget.Submit](a, 3usize)
    if picks_error != ok { os.exit(10i32) }
    var i = 0usize
    while i < 3usize {
        pick_targets[i] = Pick { log: &logs[0usize], index: i }
        picks[i] = widget.Submit { ctx: mem.cast[*void](&pick_targets[i]), invoke: on_pick }
        i += 1usize
    }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 524288usize)
    if storage_error != ok { os.exit(11i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, ctx, &toggles[0usize], picks[0usize..3usize], false, 0usize, 100.0)
    if build_error != ok { os.exit(12i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(13i32) }
    // Collapsed: the headers stand, the content does not; the header is a button that
    // offers to expand and controls its content.
    if testing.by_text(&harness, "Hidden text").count != 0usize || testing.by_text(&harness, "More text").count != 0usize { os.exit(14i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(15i32) }
    let (header, has_header) = find(tree, .Button, "Details")
    if !has_header || header.state.expanded { os.exit(16i32) }
    var offers_expand = false
    i = 0usize
    while i < header.actions.len {
        if header.actions[i] == .Expand { offers_expand = true }
        i += 1usize
    }
    if !offers_expand { os.exit(17i32) }
    // A tap on the header fires the toggle; expanded, the content shows in a group
    // labelled by the header, which says expanded.
    let (header_at, has_header_at) = centre_of(&harness, &runtime, 1u64)
    if !has_header_at || testing.tap(&harness, header_at.x, header_at.y) != ok || logs[0usize].toggles != 1usize { os.exit(18i32) }
    let (root_2, build_2_error) = build(&frame, &theme, ctx, &toggles[0usize], picks[0usize..3usize], true, 0usize, 100.0)
    if build_2_error != ok { os.exit(19i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(20i32) }
    if testing.by_text(&harness, "Hidden text").count != 1usize || testing.by_text(&harness, "More text").count != 1usize { os.exit(21i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(22i32) }
    let (header_2, has_header_2) = find(tree_2, .Button, "Details")
    if !has_header_2 || !header_2.state.expanded { os.exit(23i32) }
    if testing.by_key(&harness, 2u64).count != 1usize { os.exit(24i32) }
    // Enter on the focused header toggles again.
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].toggles != 2usize { os.exit(25i32) }
    // Tabs: three, in a tab list, the first selected; the first page alone shows.
    if testing.by_role(&harness, .Tab).count != 3usize || testing.by_role(&harness, .TabList).count != 1usize { os.exit(26i32) }
    let (first_tab, has_first) = find(tree_2, .Tab, "One")
    let (second_tab, has_second) = find(tree_2, .Tab, "Two")
    if !has_first || !has_second || !first_tab.state.selected || second_tab.state.selected { os.exit(27i32) }
    if testing.by_text(&harness, "Page one").count != 1usize || testing.by_text(&harness, "Page two").count != 0usize { os.exit(28i32) }
    // A tap on the second tab picks it; Right from the (still) selected first picks
    // the second again; Left from the first picks nothing.
    let (second_at, has_second_at) = centre_of(&harness, &runtime, 13u64)
    if !has_second_at || testing.tap(&harness, second_at.x, second_at.y) != ok { os.exit(29i32) }
    if logs[0usize].picks != 1usize || logs[0usize].last_pick != 1usize { os.exit(30i32) }
    let (first_at, has_first_at) = centre_of(&harness, &runtime, 12u64)
    if !has_first_at || testing.tap(&harness, first_at.x, first_at.y) != ok || logs[0usize].picks != 2usize { os.exit(31i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || logs[0usize].picks != 3usize || logs[0usize].last_pick != 1usize { os.exit(32i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || logs[0usize].picks != 3usize { os.exit(33i32) }
    let (root_3, build_3_error) = build(&frame, &theme, ctx, &toggles[0usize], picks[0usize..3usize], true, 1usize, 100.0)
    if build_3_error != ok { os.exit(34i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(35i32) }
    if testing.by_text(&harness, "Page one").count != 0usize || testing.by_text(&harness, "Page two").count != 1usize { os.exit(36i32) }
    // The split: the first pane is 100 wide; a drag of the handle 50 to the right
    // reports 150; Right on the focused handle reports 8 more (v2, D966); a drag
    // far left stops at the minimum, far right at the extent less the second's.
    let pane = testing.by_key(&harness, 22u64)
    let (pane_bounds, has_pane) = widget.bounds_of(&runtime, pane.element)
    if pane.count != 1usize || !has_pane || !near(pane_bounds.width, 100.0) { os.exit(37i32) }
    let (grip_at, has_grip) = centre_of(&harness, &runtime, 23u64)
    if !has_grip { os.exit(38i32) }
    if testing.drag(&harness, grip_at, geometry.Point { x: grip_at.x + 50.0, y: grip_at.y }, 5usize) != ok { os.exit(39i32) }
    if logs[0usize].sizes == 0usize || !near(logs[0usize].last_size, 150.0) { os.exit(40i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || !near(logs[0usize].last_size, 108.0) { os.exit(41i32) }
    if testing.drag(&harness, grip_at, geometry.Point { x: grip_at.x - 200.0, y: grip_at.y }, 2usize) != ok || !near(logs[0usize].last_size, 40.0) { os.exit(42i32) }
    if testing.drag(&harness, grip_at, geometry.Point { x: grip_at.x + 400.0, y: grip_at.y }, 2usize) != ok || !near(logs[0usize].last_size, 260.0) { os.exit(43i32) }
    let (root_4, build_4_error) = build(&frame, &theme, ctx, &toggles[0usize], picks[0usize..3usize], true, 1usize, 150.0)
    if build_4_error != ok { os.exit(44i32) }
    if testing.pump(&harness, root_4, now) != ok { os.exit(45i32) }
    let pane_2 = testing.by_key(&harness, 22u64)
    let (pane_2_bounds, has_pane_2) = widget.bounds_of(&runtime, pane_2.element)
    if pane_2.count != 1usize || !has_pane_2 || !near(pane_2_bounds.width, 150.0) { os.exit(46i32) }
    let (tree_4, tree_4_error) = testing.semantics(&harness)
    if tree_4_error != ok { os.exit(47i32) }
    let (divider, has_divider) = find(tree_4, .Slider, "Divider")
    if !has_divider { os.exit(48i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(49i32) }
    try io.print("ui panes ok\n")
    ret ok
}
