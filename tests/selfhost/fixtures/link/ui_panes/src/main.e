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
    let (divider, has_divider) = find(tree_4, .Separator, "Divider")
    if !has_divider { os.exit(48i32) }
    // (D1310) A collapsible pane 120 wide with a minimum of 80: dragged to 20 it
    // snaps shut (0); dragged to 60 it stops at the minimum.
    frame = mem.arena_from(frame_storage)
    let (folding_body, folding_body_error) = control.text(&frame, 0u64, "Side", &theme, control.text_options())
    if folding_body_error != ok { os.exit(50i32) }
    let (folding, folding_error) = control.resizable_pane_with(&frame, 900u64, &theme, "Side", .Horizontal, 120.0, 80.0, 300.0, widget.Change[f32] { ctx: ctx, invoke: on_size }, folding_body, true)
    let (folding_page, folding_page_error) = mem.alloc[widget.Node](&frame, 1usize)
    if folding_error != ok || folding_page_error != ok { os.exit(51i32) }
    folding_page[0usize] = folding
    if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 200.0), folding_page[0usize..1usize]), now) != ok { os.exit(52i32) }
    let (fold_grip, has_fold_grip) = centre_of(&harness, &runtime, 902u64)
    if !has_fold_grip { os.exit(53i32) }
    if testing.drag(&harness, fold_grip, geometry.Point { x: fold_grip.x - 100.0, y: fold_grip.y }, 2usize) != ok || !near(logs[0usize].last_size, 0.0) { os.exit(54i32) }
    if testing.drag(&harness, fold_grip, geometry.Point { x: fold_grip.x - 60.0, y: fold_grip.y }, 2usize) != ok || !near(logs[0usize].last_size, 80.0) { os.exit(55i32) }
    // (D1333) Held mid-drag, the pane shows its size in a tooltip; released, not.
    var held_step = 0usize
    var held_size: f32 = 120.0
    while held_step < 4usize {
        frame = mem.arena_from(frame_storage)
        let (held_body, held_body_error) = control.text(&frame, 0u64, "Side", &theme, control.text_options())
        if held_body_error != ok { os.exit(56i32) }
        let (held_pane, held_pane_error) = control.resizable_pane_with(&frame, 950u64, &theme, "Side", .Horizontal, held_size, 80.0, 300.0, widget.Change[f32] { ctx: ctx, invoke: on_size }, held_body, false)
        let (held_page, held_page_error) = mem.alloc[widget.Node](&frame, 1usize)
        if held_pane_error != ok || held_page_error != ok { os.exit(57i32) }
        held_page[0usize] = held_pane
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 200.0), held_page[0usize..1usize]), now) != ok { os.exit(58i32) }
        let tipped = testing.by_key(&harness, 950u64 + 1048577u64).count
        let (held_grip, has_held_grip) = centre_of(&harness, &runtime, 952u64)
        if !has_held_grip { os.exit(59i32) }
        if held_step == 1usize {
            if tipped != 0usize || testing.send(&harness, input.Event { PointerDown: testing.pointer_at(held_grip.x, held_grip.y) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(held_grip.x + 15.0, held_grip.y) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(held_grip.x + 30.0, held_grip.y) }) != ok { os.exit(60i32) }
            held_size = logs[0usize].last_size
        }
        if held_step == 2usize {
            if tipped != 1usize || testing.by_text(&harness, "150 px").count == 0usize { os.exit(61i32) }
            if testing.send(&harness, input.Event { PointerUp: testing.pointer_at(held_grip.x, held_grip.y) }) != ok { os.exit(61i32) }
        }
        if held_step == 3usize && tipped != 0usize { os.exit(62i32) }
        held_step += 1usize
    }
    // (D1334) Over the sash the frame asks for the resize-across cursor; away, the arrow.
    var cursor_step = 0usize
    while cursor_step < 3usize {
        frame = mem.arena_from(frame_storage)
        let (cursor_body, cursor_body_error) = control.text(&frame, 0u64, "Side", &theme, control.text_options())
        if cursor_body_error != ok { os.exit(63i32) }
        let (cursor_pane, cursor_pane_error) = control.resizable_pane_with(&frame, 980u64, &theme, "Side", .Horizontal, 120.0, 80.0, 300.0, widget.Change[f32] { ctx: ctx, invoke: on_size }, cursor_body, false)
        let (cursor_page, cursor_page_error) = mem.alloc[widget.Node](&frame, 1usize)
        if cursor_pane_error != ok || cursor_page_error != ok { os.exit(64i32) }
        cursor_page[0usize] = cursor_pane
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 200.0), cursor_page[0usize..1usize]), now) != ok { os.exit(65i32) }
        let (cursor_grip, has_cursor_grip) = centre_of(&harness, &runtime, 982u64)
        if !has_cursor_grip { os.exit(66i32) }
        if cursor_step == 0usize && (widget.cursor_of(&runtime) != 0u8 || testing.hover(&harness, cursor_grip.x, cursor_grip.y) != ok) { os.exit(67i32) }
        if cursor_step == 1usize && (widget.cursor_of(&runtime) != 4u8 || testing.hover(&harness, 390.0, 190.0) != ok) { os.exit(68i32) }
        if cursor_step == 2usize && widget.cursor_of(&runtime) != 0u8 { os.exit(69i32) }
        cursor_step += 1usize
    }
    // (D1335) Over a text field the frame asks for the text cursor, over a link
    // the hand.
    let (typed_bytes, typed_bytes_error) = mem.alloc[u8](a, 16usize)
    if typed_bytes_error != ok { os.exit(70i32) }
    var point_step = 0usize
    while point_step < 3usize {
        frame = mem.arena_from(frame_storage)
        var wide_field = control.field_options()
        wide_field.width = 200.0
        let (typing, typing_error) = control.text_field(&frame, 990u64, &theme, "Name", typed_bytes, 0usize, zero, zero, wide_field)
        let (linking, linking_error) = control.link(&frame, 995u64, &theme, "Learn more", &toggles[0usize])
        let (pointed, pointed_error) = mem.alloc[widget.Node](&frame, 2usize)
        if typing_error != ok || linking_error != ok || pointed_error != ok { os.exit(71i32) }
        pointed[0usize] = typing
        pointed[1usize] = linking
        if testing.pump(&harness, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 20.0 }, control.sized_style(400.0, 200.0), pointed[0usize..2usize]), now) != ok { os.exit(72i32) }
        let (field_at, has_field_at) = centre_of(&harness, &runtime, 990u64)
        let (link_at, has_link_at) = centre_of(&harness, &runtime, 995u64)
        if !has_field_at || !has_link_at { os.exit(73i32) }
        if point_step == 0usize && testing.hover(&harness, field_at.x, field_at.y) != ok { os.exit(74i32) }
        if point_step == 1usize && (widget.cursor_of(&runtime) != 1u8 || testing.hover(&harness, link_at.x, link_at.y) != ok) { os.exit(75i32) }
        if point_step == 2usize && widget.cursor_of(&runtime) != 2u8 { os.exit(76i32) }
        point_step += 1usize
    }
    // (D1356) A collapsible pane at 120 set to 0 eases shut: part way after 100 ms,
    // gone after a second (the cell is there from the second frame, and a build
    // sees the last pump's time).
    var fold_step = 0usize
    while fold_step < 6usize {
        var fold_size: f32 = 0.0
        if fold_step < 2usize { fold_size = 120.0 }
        var fold_at = 20000000000i64
        if fold_step == 3usize { fold_at = 20100000000i64 }
        if fold_step == 4usize { fold_at = 21000000000i64 }
        if fold_step == 5usize { fold_at = 22000000000i64 }
        frame = mem.arena_from(frame_storage)
        let (fold_body, fold_body_error) = control.text(&frame, 0u64, "Side", &theme, control.text_options())
        let (fold_pane, fold_pane_error) = control.resizable_pane_with(&frame, 960u64, &theme, "Side", .Horizontal, fold_size, 80.0, 300.0, widget.Change[f32] { ctx: ctx, invoke: on_size }, fold_body, true)
        let (fold_page, fold_page_error) = mem.alloc[widget.Node](&frame, 1usize)
        if fold_body_error != ok || fold_pane_error != ok || fold_page_error != ok { os.exit(77i32) }
        fold_page[0usize] = fold_pane
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 200.0), fold_page[0usize..1usize]), time.Instant { nanos: fold_at }) != ok { os.exit(78i32) }
        let fold_box = testing.by_key(&harness, 961u64)
        let (fold_area, has_fold_area) = widget.bounds_of(&runtime, fold_box.element)
        if !has_fold_area { os.exit(79i32) }
        if fold_step == 4usize && (fold_area.width < 1.0 || fold_area.width > 119.0) { os.exit(80i32) }
        if fold_step == 5usize && fold_area.width > 0.5 { os.exit(81i32) }
        fold_step += 1usize
    }
    // (D1406) A snapping split 300 wide: its divider dragged from 100 to 142
    // lands on the half, 150; F6 moves the focus between the panes.
    var split_step = 0usize
    while split_step < 2usize {
        frame = mem.arena_from(frame_storage)
        let (left_parts, left_parts_error) = mem.alloc[widget.Node](&frame, 2usize)
        if left_parts_error != ok { os.exit(82i32) }
        left_parts[0usize] = widget.region(991u64, widget.Region { gesture: zero, gestures: 0u8, enabled: true, focusable: true }, control.sized_style(40.0, 20.0), zero)
        left_parts[1usize] = widget.region(992u64, widget.Region { gesture: zero, gestures: 0u8, enabled: true, focusable: true }, control.sized_style(40.0, 20.0), zero)
        var snapping: control.SplitOptions = zero
        snapping.snaps = true
        snapping.first_focus = 991u64
        snapping.second_focus = 992u64
        let (snap_split, snap_split_error) = control.split_view_with(&frame, 980u64, &theme, "Divider", .Horizontal, left_parts[0usize], left_parts[1usize], 100.0, 40.0, 40.0, widget.Change[f32] { ctx: ctx, invoke: on_size }, 300.0, 60.0, snapping)
        let (split_page, split_page_error) = mem.alloc[widget.Node](&frame, 1usize)
        if snap_split_error != ok || split_page_error != ok { os.exit(83i32) }
        split_page[0usize] = snap_split
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 200.0), split_page[0usize..1usize]), time.Instant { nanos: 30000000000i64 + i64(split_step) }) != ok { os.exit(84i32) }
        split_step += 1usize
    }
    let (snap_grip, has_snap_grip) = centre_of(&harness, &runtime, 983u64)
    if !has_snap_grip || testing.drag(&harness, snap_grip, geometry.Point { x: snap_grip.x + 42.0, y: snap_grip.y }, 3usize) != ok || !near(logs[0usize].last_size, 150.0) { os.exit(85i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 991u64).element) != ok || testing.press_key(&harness, 65475u32, zero) != ok { os.exit(86i32) }
    let (cycled_to, _) = widget.focused_key(&runtime)
    if cycled_to != 992u64 || testing.press_key(&harness, 65475u32, zero) != ok { os.exit(87i32) }
    let (cycled_back, _) = widget.focused_key(&runtime)
    if cycled_back != 991u64 { os.exit(88i32) }
    // (D1472) A ratio split: a quarter of 400 is 100 (108 with its sash); dragged 100 on it reports a
    // half, and a half of a 200 wide window is 100 again.
    var ratio_step = 0usize
    var ratio_at: f32 = 0.25
    var ratio_width: f32 = 400.0
    while ratio_step < 5usize {
        if ratio_step == 3usize {
            ratio_at = logs[0usize].last_size
            ratio_width = 200.0
        }
        frame = mem.arena_from(frame_storage)
        let (ratio_parts, ratio_parts_error) = mem.alloc[widget.Node](&frame, 2usize)
        if ratio_parts_error != ok { os.exit(94i32) }
        ratio_parts[0usize] = widget.box(0u64, control.sized_style(20.0, 20.0), zero)
        ratio_parts[1usize] = widget.box(0u64, control.sized_style(20.0, 20.0), zero)
        var sharing: control.SplitOptions = zero
        sharing.ratio = true
        let (ratio_split, ratio_split_error) = control.split_view_with(&frame, 2980u64, &theme, "Share", .Horizontal, ratio_parts[0usize], ratio_parts[1usize], ratio_at, 40.0, 40.0, widget.Change[f32] { ctx: ctx, invoke: on_size }, ratio_width, 60.0, sharing)
        let (ratio_page, ratio_page_error) = mem.alloc[widget.Node](&frame, 1usize)
        if ratio_split_error != ok || ratio_page_error != ok { os.exit(95i32) }
        ratio_page[0usize] = ratio_split
        if testing.pump(&harness, widget.box(0u64, control.sized_style(ratio_width, 60.0), ratio_page[0usize..1usize]), time.Instant { nanos: 31000000000i64 + i64(ratio_step) }) != ok { os.exit(96i32) }
        if ratio_step == 1usize {
            let (quarter, has_quarter) = widget.bounds_of(&runtime, testing.by_key(&harness, 2981u64).element)
            if !has_quarter || !near(quarter.width, 108.0) { os.exit(97i32) }
            let (ratio_grip, has_ratio_grip) = centre_of(&harness, &runtime, 2983u64)
            if !has_ratio_grip || testing.drag(&harness, ratio_grip, geometry.Point { x: ratio_grip.x + 100.0, y: ratio_grip.y }, 3usize) != ok || !near(logs[0usize].last_size, 0.5) { os.exit(98i32) }
        }
        ratio_step += 1usize
    }
    let (half, has_half) = widget.bounds_of(&runtime, testing.by_key(&harness, 2981u64).element)
    if !has_half || !near(half.width, 108.0) { os.exit(99i32) }
    // (D1464) 300 wide for minimums of 240 and 320, the split stacks: the first
    // pane alone; showing the second, it stands under a Back that fires.
    var stack_step = 0usize
    while stack_step < 3usize {
        frame = mem.arena_from(frame_storage)
        let (stack_parts, stack_parts_error) = mem.alloc[widget.Node](&frame, 2usize)
        if stack_parts_error != ok { os.exit(89i32) }
        stack_parts[0usize] = widget.box(1991u64, control.sized_style(40.0, 20.0), zero)
        stack_parts[1usize] = widget.box(1992u64, control.sized_style(40.0, 20.0), zero)
        var stacking: control.SplitOptions = zero
        stacking.stack = true
        stacking.showing_second = stack_step >= 1usize
        stacking.back = widget.Submit { ctx: ctx, invoke: on_toggle }
        stacking.second_title = "Build 4127"
        let (stacked_split, stacked_split_error) = control.split_view_with(&frame, 1980u64, &theme, "Builds", .Horizontal, stack_parts[0usize], stack_parts[1usize], 200.0, 240.0, 320.0, widget.Change[f32] { ctx: ctx, invoke: on_size }, 300.0, 400.0, stacking)
        let (stack_page, stack_page_error) = mem.alloc[widget.Node](&frame, 1usize)
        if stacked_split_error != ok || stack_page_error != ok { os.exit(89i32) }
        stack_page[0usize] = stacked_split
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 420.0), stack_page[0usize..1usize]), time.Instant { nanos: 31000000000i64 + i64(stack_step) }) != ok { os.exit(90i32) }
        let firsts = testing.by_key(&harness, 1991u64).count
        let seconds = testing.by_key(&harness, 1992u64).count
        if stack_step == 0usize && (firsts == 0usize || seconds != 0usize || testing.by_key(&harness, 1983u64).count != 0usize) { os.exit(91i32) }
        if stack_step == 2usize {
            if firsts != 0usize || seconds == 0usize { os.exit(92i32) }
            let backs_before = logs[0usize].toggles
            let (back_at, has_back_at) = centre_of(&harness, &runtime, 1984u64)
            if !has_back_at || testing.tap(&harness, back_at.x, back_at.y) != ok || logs[0usize].toggles != backs_before + 1usize { os.exit(93i32) }
        }
        stack_step += 1usize
    }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(49i32) }
    try io.print("ui panes ok\n")
    ret ok
}
