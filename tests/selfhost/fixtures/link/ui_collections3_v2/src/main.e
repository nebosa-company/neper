// The v2 tree, outline and tree table (D981, widget plan P5-12,
// docs/ux/components/Tree, Outline, TreeTable) under the light theme at pointer
// density: a tree on `surface` with 4 above, its rows 32 tall inset 8 with
// `radius-sm`, 4 before a 24 twisty drawing its chevron in
// `on-surface-variant`, 20 a level, the selected row `secondary-container`,
// Down moving the focus and Right expanding; an outline whose 1px
// `outline-variant` guides run through each ancestor's twisty from row to row
// and whose current heading carries a 3px `primary` bar, under its 40 header
// with Collapse all; a tree table under the
// v2 header with 40 tall full-width rows over dividers.

use e.algo.hash as hash
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
use e.ui.collection
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

const W: usize = 320usize

type Log = struct { toggles: usize, toggled: widget.Key, picks: usize, collapses: usize, large: bool }

fn on_toggle(ctx: *void, value: widget.Key) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    log.toggled = value
    ret ok
}

// (D1342) A rename ask, kept as the node's key; and a count bumped.
fn on_rename(ctx: *void, value: widget.Key) -> err {
    let seen = mem.cast[*usize](ctx)
    *seen = usize(value)
    ret ok
}

fn on_bump(ctx: *void) -> err {
    let seen = mem.cast[*usize](ctx)
    *seen += 1usize
    ret ok
}

fn on_pick(ctx: *void, value: widget.Key) -> err {
    let log = mem.cast[*Log](ctx)
    log.picks += 1usize
    ret ok
}

fn on_collapse(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.collapses += 1usize
    ret ok
}

fn on_sort(ctx: *void, value: usize) -> err {
    ret ok
}

fn on_reorder(ctx: *void, value: collection.Reorder) -> err {
    ret ok
}

fn on_resize(ctx: *void, value: collection.ColumnResize) -> err {
    ret ok
}

// A (1) holds A1 (11), which holds A1a (111), and A2 (12); B (2) holds B1 (21).
fn tree_count(ctx: *void, parent: widget.Key) -> usize {
    let log = mem.cast[*Log](ctx)
    if log.large {
        if parent == 0u64 { ret 513usize }
        ret 0usize
    }
    if parent == 0u64 || parent == 1u64 { ret 2usize }
    if parent == 11u64 || parent == 2u64 { ret 1usize }
    ret 0usize
}

fn tree_key(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    let log = mem.cast[*Log](ctx)
    if log.large { ret 10000u64 + u64(index) }
    if parent == 0u64 { ret 1u64 + u64(index) }
    if parent == 1u64 { ret 11u64 + u64(index) }
    if parent == 11u64 { ret 111u64 }
    ret 21u64
}

// (D1372) A tree move, kept.
type TreeMoveLog = struct { node: widget.Key, into: widget.Key }

fn on_tree_move(ctx: *void, value: collection.TreeMove) -> err {
    let kept = mem.cast[*TreeMoveLog](ctx)
    kept.node = value.node
    kept.into = value.into
    ret ok
}

fn tree_has_children(ctx: *void, key: widget.Key) -> bool {
    let log = mem.cast[*Log](ctx)
    if log.large { ret false }
    ret key == 1u64 || key == 11u64 || key == 2u64
}

fn tree_build(ctx: *void, a: *mem.Arena, key: widget.Key, out: *widget.Node) -> err {
    let log = mem.cast[*Log](ctx)
    var label = "A"
    if log.large { label = "Item" }
    if key == 11u64 { label = "A1" }
    if key == 111u64 { label = "A1a" }
    if key == 12u64 { label = "A2" }
    if key == 2u64 { label = "B" }
    if key == 21u64 { label = "B1" }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret held_error }
    held[0usize] = widget.box(0u64, control.sized_style(40.0, 10.0), zero)
    var sem: widget.Semantics = zero
    sem.label = label
    *out = widget.semantics(0u64, sem, style.defaults(), held[0usize..1usize])
    ret ok
}

fn tree_cell(ctx: *void, a: *mem.Arena, key: widget.Key, column: usize, out: *widget.Node) -> err {
    *out = widget.box(0u64, control.sized_style(20.0, 10.0), zero)
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

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, which: usize) -> (widget.Node, err) {
    let source = collection.TreeSource { ctx: ctx, count: tree_count, key: tree_key, has_children: tree_has_children, build: tree_build }
    var open: [2]widget.Key = zero
    open[0usize] = 1u64
    open[1usize] = 11u64
    var chosen: [1]widget.Key = zero
    chosen[0usize] = 2u64
    let toggle = widget.Change[widget.Key] { ctx: ctx, invoke: on_toggle }
    let pick = widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }
    let (collapses, collapses_error) = mem.alloc[widget.Submit](a, 1usize)
    if collapses_error != ok { ret (zero, collapses_error) }
    collapses[0usize] = widget.Submit { ctx: ctx, invoke: on_collapse }
    let collapse_all = &collapses[0usize]
    let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
    if parts_error != ok { ret (zero, parts_error) }
    if which == 0usize {
        let (made, made_error) = collection.tree(a, 100u64, t, "Files", source, open[..], chosen[..], toggle, pick, 0.0, 240.0)
        if made_error != ok { ret (zero, made_error) }
        parts[0usize] = made
    }
    if which == 1usize {
        let (made, made_error) = collection.outline_of(a, 300u64, t, "Outline", source, open[..], chosen[..], toggle, pick, 12u64, collapse_all, 0.0, 240.0)
        if made_error != ok { ret (zero, made_error) }
        parts[0usize] = made
    }
    if which == 2usize {
        let (columns, columns_error) = mem.alloc[collection.Column](a, 2usize)
        if columns_error != ok { ret (zero, columns_error) }
        columns[0usize] = collection.Column { title: "Name", width: 200.0 }
        columns[1usize] = collection.Column { title: "Size", width: 80.0 }
        let cells = collection.CellSource { ctx: ctx, cell: tree_cell }
        let (made, made_error) = collection.tree_table(a, 500u64, t, "Sizes", columns[0usize..2usize], source, cells, open[..], chosen[..], toggle, pick, 0usize, false, widget.Change[usize] { ctx: ctx, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: ctx, invoke: on_reorder }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: on_resize }, 0.0)
        if made_error != ok { ret (zero, made_error) }
        parts[0usize] = made
    }
    var page = style.defaults()
    page.width = style.Length { Px: 320.0 }
    page.height = style.Length { Px: 300.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page, parts[0usize..1usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * W + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn any_color(shot: image.Image, x: f32, y: f32, w: f32, h: f32, c: paint.Color) -> bool {
    var j: f32 = 0.0
    while j < h {
        var i: f32 = 0.0
        while i < w {
            if is_color(shot, at(x + i, y + j), c) { ret true }
            i += 1.0
        }
        j += 1.0
    }
    ret false
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn focused_is(h: *testing.Harness, key: widget.Key) -> bool {
    let (id, has) = testing.focused(h)
    ret has && id.slot == testing.by_key(h, key).element.slot
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 600usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 32u16, max_commands: 4096usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 300u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (frame_storage, storage_error) = mem.alloc[u8](a, 16777216usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let background = style.color(&tokens, .Background)
    let muted = style.color(&tokens, .OnSurfaceVariant)
    let rule = style.color(&tokens, .OutlineVariant)
    // The tree: on `surface` with 4 above; rows 32 tall inset 8, twisties 4 in,
    // 20 a level; B `secondary-container` with rounded corners.
    let (root, build_error) = build(&f, &theme, ctx, 0usize)
    if build_error != ok || testing.pump(&harness, root, now) != ok { os.exit(9i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(10i32) }
    let (files, has_files) = bounds(&harness, &runtime, 100u64)
    let (row_a, has_a) = bounds(&harness, &runtime, 1u64)
    let (row_a1, has_a1) = bounds(&harness, &runtime, 11u64)
    let (row_b, has_b) = bounds(&harness, &runtime, 2u64)
    if !has_files || !has_a || !has_a1 || !has_b { os.exit(11i32) }
    if !near(row_a.x, files.x + 8.0) || !near(row_a.y, files.y + 4.0) || !near(row_a.width, 224.0) || !near(row_a.height, 32.0) || !near(row_a1.y, row_a.y + 32.0) { os.exit(12i32) }
    if !is_color(shot, at(files.x + 3.0, files.y + 2.0), background) || !is_color(shot, at(row_a.x + 200.0, row_a.y + 16.0), background) { os.exit(13i32) }
    let (twisty_a, has_twisty_a) = bounds(&harness, &runtime, 101u64)
    let (twisty_a1, has_twisty_a1) = bounds(&harness, &runtime, 103u64)
    if !has_twisty_a || !has_twisty_a1 || !near(twisty_a.x, row_a.x + 4.0) || !near(twisty_a.width, 24.0) || !near(twisty_a1.x, twisty_a.x + 20.0) { os.exit(14i32) }
    if !any_color(shot, twisty_a.x, twisty_a.y, 24.0, 24.0, muted) || !is_color(shot, at(twisty_a.x + 9.0, twisty_a.y + 10.0), muted) || any_color(shot, row_a.x + 70.0, row_a.y, 100.0, 32.0, muted) { os.exit(15i32) }
    if !is_color(shot, at(row_b.x + 200.0, row_b.y + 16.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(row_b.x + 0.5, row_b.y + 0.5), background) { os.exit(16i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(17i32) }
    var items = 0usize
    var has_tree_b = false
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .TreeItem {
            items += 1usize
            if tree.nodes[i].label.len == 1usize && tree.nodes[i].label[0usize] == 66u8 { has_tree_b = true }
        }
        i += 1usize
    }
    if items != 5usize { os.exit(18i32) }
    if !has_tree_b || widget.focus(&runtime, testing.by_key(&harness, 1u64).element) != ok || testing.press_key(&harness, 66u32, zero) != ok || !focused_is(&harness, 2u64) { os.exit(50i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 1u64).element) != ok { os.exit(51i32) }
    // A tap on the twisty toggles. The row key scope moves linearly and through
    // the hierarchy: Right enters open children, leaves stay put, and Left
    // returns to a parent or collapses it.
    if testing.tap(&harness, twisty_a.x + 12.0, twisty_a.y + 12.0) != ok || logs[0usize].toggles != 1usize || logs[0usize].toggled != 1u64 { os.exit(19i32) }
    var tabs = 0usize
    while !focused_is(&harness, 1u64) && tabs < 30usize {
        if testing.tab(&harness, false) != ok { os.exit(20i32) }
        tabs += 1usize
    }
    if !focused_is(&harness, 1u64) || testing.press_key(&harness, 40u32, zero) != ok || !focused_is(&harness, 11u64) || testing.press_key(&harness, 36u32, zero) != ok || !focused_is(&harness, 1u64) { os.exit(21i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || !focused_is(&harness, 11u64) || logs[0usize].toggles != 1usize { os.exit(22i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || !focused_is(&harness, 111u64) || testing.press_key(&harness, 39u32, zero) != ok || !focused_is(&harness, 111u64) || logs[0usize].toggles != 1usize { os.exit(40i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || !focused_is(&harness, 11u64) || testing.press_key(&harness, 37u32, zero) != ok || logs[0usize].toggles != 2usize || logs[0usize].toggled != 11u64 { os.exit(41i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !focused_is(&harness, 2u64) || testing.press_key(&harness, 39u32, zero) != ok || logs[0usize].toggles != 3usize || logs[0usize].toggled != 2u64 { os.exit(42i32) }
    // Branch semantics offer only the action matching their current state.
    var open_id: accessibility.Id = zero
    var shut_id: accessibility.Id = zero
    var has_open_id = false
    var has_shut_id = false
    i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .TreeItem && tree.nodes[i].level == 1u8 && tree.nodes[i].position.row == 1u32 && tree.nodes[i].actions.len == 3usize && tree.nodes[i].actions[1usize] == .Press && tree.nodes[i].actions[2usize] == .Collapse {
            open_id = tree.nodes[i].id
            has_open_id = true
        }
        if tree.nodes[i].role == .TreeItem && tree.nodes[i].level == 1u8 && tree.nodes[i].position.row == 2u32 && tree.nodes[i].actions.len == 3usize && tree.nodes[i].actions[1usize] == .Press && tree.nodes[i].actions[2usize] == .Expand {
            shut_id = tree.nodes[i].id
            has_shut_id = true
        }
        i += 1usize
    }
    if !has_open_id || !has_shut_id { os.exit(43i32) }
    if widget.semantic_action(&runtime, open_id, accessibility.ACTION_PRESS) != ok || logs[0usize].picks != 1usize { os.exit(52i32) }
    if widget.semantic_action(&runtime, open_id, accessibility.ACTION_COLLAPSE) != ok || logs[0usize].toggles != 4usize || logs[0usize].toggled != 1u64 { os.exit(44i32) }
    if widget.semantic_action(&runtime, shut_id, accessibility.ACTION_EXPAND) != ok || logs[0usize].toggles != 5usize || logs[0usize].toggled != 2u64 { os.exit(45i32) }
    // The ordinary second row tap still selects, then DoubleTap toggles a branch.
    if testing.tap(&harness, row_a.x + 150.0, row_a.y + 16.0) != ok || testing.tap(&harness, row_a.x + 150.0, row_a.y + 16.0) != ok || logs[0usize].picks != 3usize || logs[0usize].toggles != 6usize || logs[0usize].toggled != 1u64 { os.exit(46i32) }
    // `*` expands collapsed branch siblings through the Windows Shift+8 and X
    // asterisk physical paths.
    var star_held: input.Modifiers = zero
    star_held.shift = true
    if !focused_is(&harness, 1u64) || testing.press_key(&harness, 56u32, star_held) != ok || logs[0usize].toggles != 7usize || logs[0usize].toggled != 2u64 { os.exit(48i32) }
    if testing.press_key(&harness, 42u32, star_held) != ok || logs[0usize].toggles != 8usize || logs[0usize].toggled != 2u64 { os.exit(49i32) }
    // The outline: guides through each ancestor's twisty, 16 and 36 in, from row
    // to row; A2, the current heading, with its 3px `primary` bar.
    let (root_2, build_2_error) = build(&f, &theme, ctx, 1usize)
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(23i32) }
    let (shot_2, shot_2_error) = testing.snapshot(&harness, a)
    if shot_2_error != ok { os.exit(24i32) }
    let (deep, has_deep) = bounds(&harness, &runtime, 111u64)
    let (middle, has_middle) = bounds(&harness, &runtime, 11u64)
    let (current, has_current) = bounds(&harness, &runtime, 12u64)
    if !has_deep || !has_middle || !has_current { os.exit(25i32) }
    if !is_color(shot_2, at(deep.x + 16.5, deep.y + 16.0), rule) || !is_color(shot_2, at(deep.x + 36.5, deep.y + 16.0), rule) || !is_color(shot_2, at(deep.x + 26.5, deep.y + 16.0), background) { os.exit(26i32) }
    if !is_color(shot_2, at(middle.x + 16.5, middle.y + 0.5), rule) || !is_color(shot_2, at(middle.x + 16.5, middle.y + 31.5), rule) || !is_color(shot_2, at(deep.x + 16.5, deep.y + 0.5), rule) { os.exit(27i32) }
    if !is_color(shot_2, at(current.x + 1.5, current.y + 16.0), style.color(&tokens, .Primary)) || !is_color(shot_2, at(current.x + 1.5, current.y + 4.0), background) { os.exit(28i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(29i32) }
    var currents = 0usize
    i = 0usize
    while i < tree_2.nodes.len {
        if tree_2.nodes[i].role == .TreeItem && tree_2.nodes[i].state.current { currents += 1usize }
        i += 1usize
    }
    if currents != 1usize { os.exit(30i32) }
    // The header: 40 tall on `surface` over the rows; Collapse all fires.
    let (fold, has_fold) = bounds(&harness, &runtime, 302u64)
    let (outline, has_outline) = bounds(&harness, &runtime, 300u64)
    if !has_fold || !has_outline || !near(outline.y - fold.y, 40.0 - (40.0 - fold.height) * 0.5) || testing.by_text(&harness, "Outline").count == 0usize { os.exit(38i32) }
    if testing.tap(&harness, fold.x + fold.width * 0.5, fold.y + fold.height * 0.5) != ok || logs[0usize].collapses != 1usize { os.exit(39i32) }
    // The tree table: the 48 header, rows of 40 (39 over a full-width divider),
    // the twisty 16 into the first cell and 20 a level.
    let (root_3, build_3_error) = build(&f, &theme, ctx, 2usize)
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(31i32) }
    let (shot_3, shot_3_error) = testing.snapshot(&harness, a)
    if shot_3_error != ok { os.exit(32i32) }
    let (head, has_head) = bounds(&harness, &runtime, 501u64)
    let (table_a, has_table_a) = bounds(&harness, &runtime, 1u64)
    let (table_b, has_table_b) = bounds(&harness, &runtime, 2u64)
    let (table_twisty, has_table_twisty) = bounds(&harness, &runtime, 629u64)
    let (table_twisty_a1, has_table_twisty_a1) = bounds(&harness, &runtime, 631u64)
    if !has_head || !has_table_a || !has_table_b || !has_table_twisty || !has_table_twisty_a1 { os.exit(33i32) }
    if !near(head.height, 47.0) || !near(table_a.y, head.y + 48.0) || !near(table_a.height, 39.0) || !near(table_a.width, 280.0) || !near(table_b.height, 40.0) { os.exit(34i32) }
    if !is_color(shot_3, at(table_a.x + 2.0, table_a.y + 39.5), rule) || !is_color(shot_3, at(table_a.x + 150.0, table_a.y + 20.0), background) || !is_color(shot_3, at(table_b.x + 150.0, table_b.y + 20.0), style.color(&tokens, .SecondaryContainer)) { os.exit(35i32) }
    if !near(table_twisty.x, table_a.x + 16.0) || !near(table_twisty_a1.x, table_twisty.x + 20.0) { os.exit(36i32) }
    let (tree_3, tree_3_error) = testing.semantics(&harness)
    if tree_3_error != ok { os.exit(54i32) }
    var tree_grids = 0usize
    var tree_grid_rows = 0usize
    var named_tree_grid_rows = 0usize
    var named_tree_grid_cells = 0usize
    i = 0usize
    while i < tree_3.nodes.len {
        if tree_3.nodes[i].role == .TreeGrid && tree_3.nodes[i].position.row_count == 5u32 && tree_3.nodes[i].position.column_count == 2u32 { tree_grids += 1usize }
        if tree_3.nodes[i].role == .Row && tree_3.nodes[i].level > 0u8 {
            tree_grid_rows += 1usize
            if tree_3.nodes[i].label.len == 1usize && tree_3.nodes[i].label[0usize] == 66u8 { named_tree_grid_rows += 1usize }
        }
        if tree_3.nodes[i].role == .Cell && tree_3.nodes[i].label.len == 4usize && tree_3.nodes[i].label[0usize] == 78u8 && tree_3.nodes[i].value.len == 1usize && tree_3.nodes[i].value[0usize] == 66u8 { named_tree_grid_cells += 1usize }
        i += 1usize
    }
    if tree_grids != 1usize || tree_grid_rows != 5usize || named_tree_grid_rows != 1usize { os.exit(54i32) }
    if named_tree_grid_cells != 1usize { os.exit(55i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 1u64).element) != ok || testing.press_key(&harness, 66u32, zero) != ok || !focused_is(&harness, 2u64) { os.exit(56i32) }
    if testing.tap(&harness, table_a.x + 150.0, table_a.y + 20.0) != ok || testing.tap(&harness, table_a.x + 150.0, table_a.y + 20.0) != ok || logs[0usize].picks != 5usize || logs[0usize].toggles != 9usize || logs[0usize].toggled != 1u64 { os.exit(47i32) }
    // (D1330) A2 disabled and B loading: A2 takes no pick, B's children wait
    // under a Loading row, and the tree says A2 disabled and B busy.
    var with_open: [2]widget.Key = zero
    with_open[0usize] = 1u64
    with_open[1usize] = 2u64
    var no_chosen: [1]widget.Key = zero
    var off_keys: [1]widget.Key = zero
    off_keys[0usize] = 12u64
    var loading_keys: [1]widget.Key = zero
    loading_keys[0usize] = 2u64
    var states: collection.TreeOptions = zero
    states.disabled = off_keys[..]
    states.loading = loading_keys[..]
    f = mem.arena_from(frame_storage)
    let states_source = collection.TreeSource { ctx: ctx, count: tree_count, key: tree_key, has_children: tree_has_children, build: tree_build }
    let (stated_tree, stated_tree_error) = collection.tree_with(&f, 500u64, &theme, "States", states_source, with_open[..], no_chosen[0usize..0usize], widget.Change[widget.Key] { ctx: ctx, invoke: on_toggle }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 0.0, 240.0, states)
    let (stated_page, stated_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if stated_tree_error != ok || stated_page_error != ok { os.exit(57i32) }
    stated_page[0usize] = stated_tree
    if testing.pump(&harness, widget.box(0u64, control.sized_style(320.0, 360.0), stated_page[0usize..1usize]), time.Instant { nanos: 1400000000i64 }) != ok { os.exit(58i32) }
    if testing.by_key(&harness, 2u64 ^ hash.fnv1a64("tree-loading")).count != 1usize { os.exit(59i32) }
    let (off_row, has_off_row) = bounds(&harness, &runtime, 12u64)
    let picks_before_off = logs[0usize].picks
    if !has_off_row || testing.tap(&harness, off_row.x + off_row.width * 0.5, off_row.y + off_row.height * 0.5) != ok || logs[0usize].picks != picks_before_off { os.exit(60i32) }
    let (stated_semantics, stated_semantics_error) = testing.semantics(&harness)
    if stated_semantics_error != ok { os.exit(61i32) }
    var disabled_items = 0usize
    var busy_items = 0usize
    var sn = 0usize
    while sn < stated_semantics.nodes.len {
        if stated_semantics.nodes[sn].state.disabled { disabled_items += 1usize }
        if stated_semantics.nodes[sn].state.busy { busy_items += 1usize }
        sn += 1usize
    }
    if disabled_items != 1usize || busy_items == 0usize { os.exit(62i32) }
    // (D1342) F2 on A2 asks to rename it; renaming, its content is the field,
    // Enter commits and Escape cancels.
    let (rename_bytes, rename_bytes_error) = mem.alloc[u8](a, 16usize)
    if rename_bytes_error != ok { os.exit(63i32) }
    rename_bytes[0usize] = 65u8
    rename_bytes[1usize] = 50u8
    var rename_log: [3]usize = zero
    let (rename_submits, rename_submits_error) = mem.alloc[widget.Submit](a, 2usize)
    if rename_submits_error != ok { os.exit(64i32) }
    rename_submits[0usize] = widget.Submit { ctx: mem.cast[*void](&rename_log[1usize]), invoke: on_bump }
    rename_submits[1usize] = widget.Submit { ctx: mem.cast[*void](&rename_log[2usize]), invoke: on_bump }
    var rename_step = 0usize
    while rename_step < 3usize {
        var renamed: collection.TreeOptions = zero
        renamed.rename = widget.Change[widget.Key] { ctx: mem.cast[*void](&rename_log[0usize]), invoke: on_rename }
        renamed.name = rename_bytes
        renamed.name_len = 2usize
        renamed.commit = rename_submits[0usize]
        renamed.cancel = rename_submits[1usize]
        if rename_step >= 1usize { renamed.renaming = 12u64 }
        f = mem.arena_from(frame_storage)
        let rename_source = collection.TreeSource { ctx: ctx, count: tree_count, key: tree_key, has_children: tree_has_children, build: tree_build }
        let (renaming_tree, renaming_tree_error) = collection.tree_with(&f, 600u64, &theme, "Rename", rename_source, with_open[0usize..1usize], no_chosen[0usize..0usize], widget.Change[widget.Key] { ctx: ctx, invoke: on_toggle }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 0.0, 240.0, renamed)
        let (rename_page, rename_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if renaming_tree_error != ok || rename_page_error != ok { os.exit(65i32) }
        rename_page[0usize] = renaming_tree
        if testing.pump(&harness, widget.box(0u64, control.sized_style(320.0, 360.0), rename_page[0usize..1usize]), time.Instant { nanos: 1500000000i64 + i64(rename_step) }) != ok { os.exit(66i32) }
        let field_key = 12u64 ^ hash.fnv1a64("tree-rename")
        if rename_step == 0usize {
            if testing.by_key(&harness, field_key).count != 0usize { os.exit(70i32) }
            if widget.focus(&runtime, testing.by_key(&harness, 12u64).element) != ok { os.exit(71i32) }
            if testing.press_key(&harness, 65471u32, zero) != ok { os.exit(72i32) }
            if rename_log[0usize] != 12usize { os.exit(67i32) }
        }
        if rename_step == 1usize {
            if testing.by_key(&harness, field_key).count != 1usize || widget.focus(&runtime, testing.by_key(&harness, field_key).element) != ok || testing.press_key(&harness, 13u32, zero) != ok || rename_log[1usize] != 1usize { os.exit(68i32) }
        }
        if rename_step == 2usize {
            if widget.focus(&runtime, testing.by_key(&harness, field_key).element) != ok || testing.press_key(&harness, 27u32, zero) != ok || rename_log[2usize] != 1usize { os.exit(69i32) }
        }
        rename_step += 1usize
    }
    // (D1372) A2 dragged onto B: B takes the drop look (its top edge `primary`)
    // and the drop reports A2 into B.
    var moved_log = TreeMoveLog { node: 0u64, into: 0u64 }
    var move_step = 0usize
    let toggles_at_hold = logs[0usize].toggles
    while move_step < 3usize {
        var moving: collection.TreeOptions = zero
        moving.move = widget.Change[collection.TreeMove] { ctx: mem.cast[*void](&moved_log), invoke: on_tree_move }
        f = mem.arena_from(frame_storage)
        let move_source = collection.TreeSource { ctx: ctx, count: tree_count, key: tree_key, has_children: tree_has_children, build: tree_build }
        let (moving_tree, moving_tree_error) = collection.tree_with(&f, 700u64, &theme, "Move", move_source, with_open[0usize..1usize], no_chosen[0usize..0usize], widget.Change[widget.Key] { ctx: ctx, invoke: on_toggle }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 0.0, 240.0, moving)
        let (move_page, move_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if moving_tree_error != ok || move_page_error != ok { os.exit(73i32) }
        var move_ground = control.sized_style(320.0, 360.0)
        move_ground.background = paint.Brush { Solid: style.color(&tokens, .Surface) }
        move_page[0usize] = moving_tree
        if testing.pump(&harness, widget.box(0u64, move_ground, move_page[0usize..1usize]), time.Instant { nanos: 1600000000i64 + i64(move_step) * 1000000000i64 }) != ok { os.exit(74i32) }
        let (a2_row, has_a2_row) = bounds(&harness, &runtime, 12u64)
        let (b_row, has_b_row) = bounds(&harness, &runtime, 2u64)
        if !has_a2_row || !has_b_row { os.exit(75i32) }
        if move_step == 0usize {
            if testing.send(&harness, input.Event { PointerDown: testing.pointer_at(a2_row.x + 60.0, a2_row.y + a2_row.height * 0.5) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(a2_row.x + 60.0, a2_row.y + a2_row.height * 0.5 + 10.0) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(b_row.x + 60.0, b_row.y + b_row.height * 0.5) }) != ok { os.exit(76i32) }
        }
        // (D1373) Held over B a second, B is asked to open.
        if move_step == 2usize && (logs[0usize].toggled != 2u64 || logs[0usize].toggles == toggles_at_hold) { os.exit(79i32) }
        if move_step == 2usize {
            let (move_shot, move_shot_error) = testing.snapshot(&harness, a)
            if move_shot_error != ok || !is_color(move_shot, at(b_row.x + b_row.width * 0.5, b_row.y + 0.5), style.color(&tokens, .Primary)) { os.exit(77i32) }
            if testing.send(&harness, input.Event { PointerUp: testing.pointer_at(b_row.x + 60.0, b_row.y + b_row.height * 0.5) }) != ok || moved_log.node != 12u64 || moved_log.into != 2u64 { os.exit(78i32) }
        }
        move_step += 1usize
    }
    // (D1437) Opened, the first twisty turns a quarter over `duration-short-3`:
    // on the open's first frame its box differs from how it settles a second on.
    var twist_sums: [2]u32 = zero
    var twist_step = 0usize
    while twist_step < 4usize {
        var twist_at = 1800000000i64
        if twist_step == 1usize { twist_at = 1800000001i64 }
        if twist_step == 2usize { twist_at = 1900000000i64 }
        if twist_step == 3usize { twist_at = 2900000000i64 }
        if testing.begin(&harness, time.Instant { nanos: twist_at }) != ok { os.exit(80i32) }
        f = mem.arena_from(frame_storage)
        var twist_options: collection.TreeOptions = zero
        var twist_open = with_open[0usize..0usize]
        if twist_step >= 2usize { twist_open = with_open[0usize..1usize] }
        let twist_source = collection.TreeSource { ctx: ctx, count: tree_count, key: tree_key, has_children: tree_has_children, build: tree_build }
        let (twisting_tree, twisting_tree_error) = collection.tree_with(&f, 800u64, &theme, "Twist", twist_source, twist_open, no_chosen[0usize..0usize], widget.Change[widget.Key] { ctx: ctx, invoke: on_toggle }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 0.0, 240.0, twist_options)
        let (twist_page, twist_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if twisting_tree_error != ok || twist_page_error != ok { os.exit(80i32) }
        twist_page[0usize] = twisting_tree
        if testing.pump(&harness, widget.box(0u64, control.sized_style(320.0, 360.0), twist_page[0usize..1usize]), time.Instant { nanos: twist_at }) != ok { os.exit(80i32) }
        if twist_step >= 2usize {
            let (twisty_box, has_twisty_box) = bounds(&harness, &runtime, 801u64)
            let (twist_shot, twist_shot_error) = testing.snapshot(&harness, a)
            if !has_twisty_box || twist_shot_error != ok { os.exit(81i32) }
            var sum = 0u32
            var y = 0usize
            while y < 12usize {
                var x = 0usize
                while x < 24usize {
                    sum += u32(twist_shot.pixels[at(twisty_box.x + f32(x), twisty_box.y + f32(y)) + 1usize])
                    x += 1usize
                }
                y += 1usize
            }
            twist_sums[twist_step - 2usize] = sum
        }
        twist_step += 1usize
    }
    if twist_sums[0usize] == twist_sums[1usize] { os.exit(82i32) }
    // (D1452) The outline's current marker slides from the first heading to the
    // second over `duration-medium-2`: on the change's frame the rows' leading
    // edge looks other than it settles a second on.
    var marker_sums: [2]u32 = zero
    var marker_step = 0usize
    while marker_step < 4usize {
        var marker_at = 3000000000i64
        var marker_current = 1u64
        if marker_step == 1usize { marker_at = 3000000001i64 }
        if marker_step == 2usize {
            marker_at = 3100000000i64
            marker_current = 2u64
        }
        if marker_step == 3usize {
            marker_at = 4100000000i64
            marker_current = 2u64
        }
        if testing.begin(&harness, time.Instant { nanos: marker_at }) != ok { os.exit(83i32) }
        f = mem.arena_from(frame_storage)
        let marker_source = collection.TreeSource { ctx: ctx, count: tree_count, key: tree_key, has_children: tree_has_children, build: tree_build }
        var no_folds: widget.Submit = zero
        let (marked_outline, marked_outline_error) = collection.outline_of(&f, 850u64, &theme, "Marked", marker_source, with_open[0usize..0usize], no_chosen[0usize..0usize], widget.Change[widget.Key] { ctx: ctx, invoke: on_toggle }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, marker_current, &no_folds, 0.0, 240.0)
        let (marker_page, marker_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if marked_outline_error != ok || marker_page_error != ok { os.exit(83i32) }
        marker_page[0usize] = marked_outline
        if testing.pump(&harness, widget.box(0u64, control.sized_style(320.0, 360.0), marker_page[0usize..1usize]), time.Instant { nanos: marker_at }) != ok { os.exit(83i32) }
        if marker_step >= 2usize {
            let (first_row, has_first_row) = bounds(&harness, &runtime, 1u64)
            let (marker_shot, marker_shot_error) = testing.snapshot(&harness, a)
            if !has_first_row || marker_shot_error != ok { os.exit(84i32) }
            var sum = 0u32
            var y = 0usize
            while y < usize(first_row.height * 2.0) {
                var x = 0usize
                while x < 16usize {
                    sum += u32(marker_shot.pixels[at(first_row.x + f32(x), first_row.y + f32(y)) + 1usize])
                    x += 1usize
                }
                y += 1usize
            }
            marker_sums[marker_step - 2usize] = sum
        }
        marker_step += 1usize
    }
    if marker_sums[0usize] == marker_sums[1usize] { os.exit(85i32) }
    logs[0usize].large = true
    let (large_rt, large_runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 6000usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 32u16, max_commands: 16384usize })
    if large_runtime_error != ok { os.exit(53i32) }
    var large_runtime = large_rt
    let large_theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &large_runtime }
    let (large_h, large_harness_error) = testing.harness(a, &large_runtime, 320u32, 360u32, 1.0)
    if large_harness_error != ok { os.exit(53i32) }
    var large_harness = large_h
    f = mem.arena_from(frame_storage)
    let (root_4, build_4_error) = build(&f, &large_theme, ctx, 0usize)
    if build_4_error != ok || testing.pump(&large_harness, root_4, time.Instant { nanos: 1300000000i64 }) != ok || testing.by_key(&large_harness, 10512u64).count != 1usize { os.exit(53i32) }
    if testing.close(&large_harness) != ok || widget.close(&large_runtime) != ok || testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(37i32) }
    try io.print("ui collections3 v2 ok\n")
    ret ok
}
