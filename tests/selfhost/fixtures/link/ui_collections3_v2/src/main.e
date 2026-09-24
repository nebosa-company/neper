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
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

const W: usize = 320usize

type Log = struct { toggles: usize, toggled: widget.Key, picks: usize, collapses: usize }

fn on_toggle(ctx: *void, value: widget.Key) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    log.toggled = value
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
    if parent == 0u64 || parent == 1u64 { ret 2usize }
    if parent == 11u64 || parent == 2u64 { ret 1usize }
    ret 0usize
}

fn tree_key(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    if parent == 0u64 { ret 1u64 + u64(index) }
    if parent == 1u64 { ret 11u64 + u64(index) }
    if parent == 11u64 { ret 111u64 }
    ret 21u64
}

fn tree_has_children(ctx: *void, key: widget.Key) -> bool {
    ret key == 1u64 || key == 11u64 || key == 2u64
}

fn tree_build(ctx: *void, a: *mem.Arena, key: widget.Key, out: *widget.Node) -> err {
    *out = widget.box(0u64, control.sized_style(40.0, 10.0), zero)
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
    let (frame_storage, storage_error) = mem.alloc[u8](a, 4194304usize)
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
    if !any_color(shot, twisty_a.x, twisty_a.y, 24.0, 24.0, muted) || any_color(shot, row_a.x + 70.0, row_a.y, 100.0, 32.0, muted) { os.exit(15i32) }
    if !is_color(shot, at(row_b.x + 200.0, row_b.y + 16.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(row_b.x + 0.5, row_b.y + 0.5), background) { os.exit(16i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(17i32) }
    var items = 0usize
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .TreeItem { items += 1usize }
        i += 1usize
    }
    if items != 5usize { os.exit(18i32) }
    // A tap on the twisty toggles; Tab reaches A, Down moves to A1, Right on B
    // expands it.
    if testing.tap(&harness, twisty_a.x + 12.0, twisty_a.y + 12.0) != ok || logs[0usize].toggles != 1usize || logs[0usize].toggled != 1u64 { os.exit(19i32) }
    var tabs = 0usize
    while !focused_is(&harness, 1u64) && tabs < 30usize {
        if testing.tab(&harness, false) != ok { os.exit(20i32) }
        tabs += 1usize
    }
    if !focused_is(&harness, 1u64) || testing.press_key(&harness, 40u32, zero) != ok || !focused_is(&harness, 11u64) { os.exit(21i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !focused_is(&harness, 2u64) || testing.press_key(&harness, 39u32, zero) != ok || logs[0usize].toggled != 2u64 { os.exit(22i32) }
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
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(37i32) }
    try io.print("ui collections3 v2 ok\n")
    ret ok
}
