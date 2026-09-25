// The v2 header row, table rows, table and data grid (D980, widget plan P5-12,
// docs/ux/components/HeaderRow, TableRow, Table, DataGrid) under the light theme
// at pointer density: a 48 `surface-container` header over a 1px
// `outline-variant` line, the sorted column's `arrow-up` in `on-surface`, 1px
// resize lines that turn into the 3px `primary` bar under the pointer; 40 tall
// rows (39 over a 1px divider) on `surface`, the selected one
// `secondary-container`, Down moving the focus; a data grid at dense metrics: a
// 40 header, 32 rows, the 40 wide row-number column on
// `surface-container-low` and grid lines between the cells.

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

const W: usize = 400usize

type Log = struct { theme: *const control.Theme, sorts: usize, picks: usize, resizes: usize, reorders: usize, from: usize, to: usize, width: f32, offset: f32 }

fn on_sort(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.sorts += 1usize
    ret ok
}

fn on_reorder(ctx: *void, value: collection.Reorder) -> err {
    let log = mem.cast[*Log](ctx)
    log.reorders += 1usize
    log.from = value.from
    log.to = value.to
    ret ok
}

fn on_resize(ctx: *void, value: collection.ColumnResize) -> err {
    let log = mem.cast[*Log](ctx)
    log.resizes += 1usize
    log.width = value.width
    ret ok
}

fn on_pick(ctx: *void, value: widget.Key) -> err {
    let log = mem.cast[*Log](ctx)
    log.picks += 1usize
    ret ok
}

fn on_scroll(ctx: *void, value: f32) -> err {
    let log = mem.cast[*Log](ctx)
    log.offset = value
    ret ok
}

fn row_count(ctx: *void) -> usize {
    ret 50usize
}

fn row_key(ctx: *void, index: usize) -> widget.Key {
    ret 1000u64 + u64(index)
}

fn grid_key(ctx: *void, index: usize) -> widget.Key {
    ret 2000u64 + u64(index)
}

fn row_cell(ctx: *void, a: *mem.Arena, index: usize, column: usize, out: *widget.Node) -> err {
    let log = mem.cast[*Log](ctx)
    var caption = control.text_options()
    caption.wrap = .None
    let (made, made_error) = control.text(a, 0u64, "x", log.theme, caption)
    if made_error != ok { ret made_error }
    *out = made
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

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, columns: []const collection.Column) -> (widget.Node, err) {
    let log = mem.cast[*Log](ctx)
    var chosen: [1]widget.Key = zero
    chosen[0usize] = 1001u64
    let source = collection.TableSource { ctx: ctx, count: row_count, key: row_key, cell: row_cell }
    let (files, e1) = collection.table(a, 1u64, t, "Files", columns, source, chosen[..], 0usize, false, widget.Change[usize] { ctx: ctx, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: ctx, invoke: on_reorder }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: on_resize }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 0.0, log.offset, widget.Change[f32] { ctx: ctx, invoke: on_scroll }, 168.0)
    let sheet_source = collection.TableSource { ctx: ctx, count: row_count, key: grid_key, cell: row_cell }
    var none: [1]widget.Key = zero
    let (sheet, e2) = collection.data_grid(a, 300u64, t, "Sheet", columns, sheet_source, none[0usize..0usize], 1usize, true, widget.Change[usize] { ctx: ctx, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: ctx, invoke: on_reorder }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: on_resize }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 0.0, 0.0, widget.Change[f32] { ctx: ctx, invoke: on_scroll }, 136.0)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = files
    parts[1usize] = sheet
    var page = style.defaults()
    page.width = style.Length { Px: 400.0 }
    page.height = style.Length { Px: 360.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, page, parts[0usize..2usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * W + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

// Whether any pixel of the box is `c`.
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 800usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 40u16, max_commands: 4096usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 400u32, 360u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    log.theme = &theme
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (columns, columns_error) = mem.alloc[collection.Column](a, 3usize)
    if columns_error != ok { os.exit(8i32) }
    columns[0usize] = collection.Column { title: "Name", width: 120.0 }
    columns[1usize] = collection.Column { title: "Size", width: 80.0 }
    columns[2usize] = collection.Column { title: "Kind", width: 100.0 }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 4194304usize)
    if storage_error != ok { os.exit(9i32) }
    var f = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&f, &theme, ctx, columns[0usize..3usize])
    if build_error != ok || testing.pump(&harness, root, now) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    let background = style.color(&tokens, .Background)
    let rule = style.color(&tokens, .OutlineVariant)
    // The header: 47 of `surface-container` over the 1px line; the sorted Name's
    // arrow in `on-surface` 16 in; the resize line 12 in from top and bottom.
    let (name, has_name) = bounds(&harness, &runtime, 2u64)
    let (grip, has_grip) = bounds(&harness, &runtime, 3u64)
    if !has_name || !has_grip || !near(name.height, 47.0) || !near(name.width, 112.0) || !near(grip.x, name.x + 112.0) { os.exit(13i32) }
    if !is_color(shot, at(name.x + 80.0, name.y + 24.0), style.color(&tokens, .SurfaceContainer)) || !is_color(shot, at(name.x + 80.0, name.y + 47.5), rule) { os.exit(14i32) }
    if !any_color(shot, name.x + 16.0, name.y + 14.0, 18.0, 20.0, style.color(&tokens, .OnSurface)) || any_color(shot, name.x + 40.0, name.y + 4.0, 60.0, 40.0, style.color(&tokens, .OnSurface)) { os.exit(15i32) }
    if !is_color(shot, at(grip.x + 3.5, grip.y + 24.0), rule) || !is_color(shot, at(grip.x + 3.5, grip.y + 6.0), style.color(&tokens, .SurfaceContainer)) { os.exit(16i32) }
    let (files, has_files) = find(tree, .Table, "Files")
    let (name_header, has_name_header) = find(tree, .ColumnHeader, "Name")
    let (name_grip, has_name_grip) = find(tree, .Separator, "Resize Name")
    let (name_cell, has_name_cell) = find(tree, .Cell, "Name")
    var descending_headers = 0usize
    var header_at = 0usize
    while header_at < tree.nodes.len {
        if tree.nodes[header_at].role == .ColumnHeader && tree.nodes[header_at].sort == .Descending { descending_headers += 1usize }
        header_at += 1usize
    }
    if !has_files || files.position.row_count != 50u32 || files.position.column_count != 3u32 || !has_name_header || !name_header.state.selected || name_header.sort != .Ascending || descending_headers != 1usize || !has_name_grip || !same(name_grip.value, "120 px") || !has_name_cell || !same(name_cell.value, "x") { os.exit(17i32) }
    if widget.semantic_action(&runtime, name_header.id, accessibility.ACTION_PRESS) != ok || logs[0usize].sorts != 1usize { os.exit(53i32) }
    if widget.semantic_action(&runtime, name_grip.id, accessibility.ACTION_INCREMENT) != ok || logs[0usize].resizes != 1usize || !near(logs[0usize].width, 136.0) { os.exit(54i32) }
    if widget.semantic_action(&runtime, name_grip.id, accessibility.ACTION_DECREMENT) != ok || logs[0usize].resizes != 2usize || !near(logs[0usize].width, 104.0) { os.exit(55i32) }
    var first_row_node: accessibility.Node = zero
    var has_first_row_node = false
    var row_at = 0usize
    while row_at < tree.nodes.len {
        if tree.nodes[row_at].role == .Row && tree.nodes[row_at].position.row == 1u32 && tree.nodes[row_at].position.row_count == 50u32 {
            first_row_node = tree.nodes[row_at]
            has_first_row_node = true
            row_at = tree.nodes.len
        }
        row_at += 1usize
    }
    if !has_first_row_node || !same(first_row_node.label, "x") || widget.semantic_action(&runtime, first_row_node.id, accessibility.ACTION_PRESS) != ok || logs[0usize].picks != 1usize { os.exit(56i32) }
    // The rows: 40 each (39 over the divider) on `surface`, 48 under the
    // header's top; Beta (1001) `secondary-container`.
    let (first, has_first) = bounds(&harness, &runtime, 1000u64)
    let (second, has_second) = bounds(&harness, &runtime, 1001u64)
    if !has_first || !has_second || !near(first.y, name.y + 48.0) || !near(first.height, 39.0) || !near(second.y, first.y + 40.0) { os.exit(18i32) }
    if testing.by_key(&harness, 1005u64).count != 1usize || testing.by_key(&harness, 1006u64).count != 0usize { os.exit(40i32) }
    if !is_color(shot, at(first.x + 150.0, first.y + 20.0), background) || !is_color(shot, at(first.x + 150.0, first.y + 39.5), rule) || !is_color(shot, at(second.x + 150.0, second.y + 20.0), style.color(&tokens, .SecondaryContainer)) { os.exit(19i32) }
    // The pointer over the resize handle turns it into the 3px `primary` bar.
    if testing.hover(&harness, grip.x + 4.0, grip.y + 24.0) != ok { os.exit(20i32) }
    let (hovered, hovered_error) = build(&f, &theme, ctx, columns[0usize..3usize])
    if hovered_error != ok || testing.pump(&harness, hovered, now) != ok { os.exit(21i32) }
    let (shot_2, shot_2_error) = testing.snapshot(&harness, a)
    if shot_2_error != ok || !is_color(shot_2, at(grip.x + 3.5, grip.y + 4.0), style.color(&tokens, .Primary)) { os.exit(22i32) }
    // A tap on a row picks it; Tab reaches the rows and Down moves on.
    if testing.tap(&harness, first.x + 150.0, first.y + 20.0) != ok || logs[0usize].picks != 2usize { os.exit(23i32) }
    var tabs = 0usize
    while !focused_is(&harness, 1000u64) && tabs < 60usize {
        if testing.tab(&harness, false) != ok { os.exit(24i32) }
        tabs += 1usize
    }
    if !focused_is(&harness, 1000u64) || testing.press_key(&harness, 40u32, zero) != ok || !focused_is(&harness, 1001u64) { os.exit(25i32) }
    // Page keys move by the three-row body viewport; targets outside the built
    // window request their minimum offset and receive focus after rebuilding.
    if testing.press_key(&harness, 34u32, zero) != ok || !focused_is(&harness, 1004u64) || !near(logs[0usize].offset, 80.0) { os.exit(32i32) }
    if testing.press_key(&harness, 34u32, zero) != ok || !near(logs[0usize].offset, 200.0) || focused_is(&harness, 1007u64) { os.exit(33i32) }
    f = mem.arena_from(frame_storage)
    let (root_2, root_2_error) = build(&f, &theme, ctx, columns[0usize..3usize])
    if root_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok || !focused_is(&harness, 1007u64) { os.exit(34i32) }
    if testing.by_key(&harness, 1002u64).count != 1usize || testing.by_key(&harness, 1010u64).count != 1usize || testing.by_key(&harness, 1011u64).count != 0usize { os.exit(41i32) }
    if testing.press_key(&harness, 33u32, zero) != ok || !focused_is(&harness, 1004u64) || !near(logs[0usize].offset, 160.0) { os.exit(35i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !near(logs[0usize].offset, 1880.0) || focused_is(&harness, 1049u64) { os.exit(36i32) }
    f = mem.arena_from(frame_storage)
    let (root_3, root_3_error) = build(&f, &theme, ctx, columns[0usize..3usize])
    if root_3_error != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1200000000i64 }) != ok || !focused_is(&harness, 1049u64) { os.exit(37i32) }
    if testing.by_key(&harness, 1044u64).count != 1usize || testing.by_key(&harness, 1043u64).count != 0usize { os.exit(42i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !near(logs[0usize].offset, 0.0) || focused_is(&harness, 1000u64) { os.exit(38i32) }
    f = mem.arena_from(frame_storage)
    let (root_4, root_4_error) = build(&f, &theme, ctx, columns[0usize..3usize])
    if root_4_error != ok || testing.pump(&harness, root_4, time.Instant { nanos: 1300000000i64 }) != ok || !focused_is(&harness, 1000u64) { os.exit(39i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || !focused_is(&harness, 2u64) { os.exit(43i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || !focused_is(&harness, 4u64) { os.exit(46i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || !focused_is(&harness, 2u64) { os.exit(47i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].sorts != 2usize { os.exit(44i32) }
    if testing.press_key(&harness, 32u32, zero) != ok || logs[0usize].sorts != 3usize { os.exit(45i32) }
    var alt: input.Modifiers = zero
    alt.alt = true
    if testing.press_key(&harness, 39u32, alt) != ok || logs[0usize].resizes != 3usize || !near(logs[0usize].width, 136.0) { os.exit(49i32) }
    if testing.press_key(&harness, 37u32, alt) != ok || logs[0usize].resizes != 4usize || !near(logs[0usize].width, 104.0) { os.exit(50i32) }
    var move_modifiers: input.Modifiers = zero
    move_modifiers.control = true
    move_modifiers.shift = true
    if testing.press_key(&harness, 39u32, move_modifiers) != ok || logs[0usize].reorders != 1usize || logs[0usize].from != 0usize || logs[0usize].to != 1usize { os.exit(51i32) }
    if testing.press_key(&harness, 37u32, move_modifiers) != ok || logs[0usize].reorders != 1usize { os.exit(52i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focused_is(&harness, 1000u64) { os.exit(48i32) }
    // The data grid: a 40 header, 32 rows, the row numbers on
    // `surface-container-low` and a grid line after each cell.
    let (sheet_head, has_sheet_head) = bounds(&harness, &runtime, 301u64)
    let (sheet_row, has_sheet_row) = bounds(&harness, &runtime, 2000u64)
    if !has_sheet_head || !has_sheet_row || !near(sheet_head.height, 39.0) || !near(sheet_row.height, 31.0) || !near(sheet_row.y, sheet_head.y + 40.0) || !near(sheet_head.x, sheet_row.x + 40.0) { os.exit(26i32) }
    if !is_color(shot, at(sheet_row.x + 20.0, sheet_row.y + 16.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(sheet_row.x + 20.0, sheet_head.y + 20.0), style.color(&tokens, .SurfaceContainerLow)) { os.exit(27i32) }
    if !is_color(shot, at(sheet_row.x + 159.5, sheet_row.y + 16.0), rule) || !is_color(shot, at(sheet_row.x + 150.0, sheet_row.y + 16.0), background) { os.exit(28i32) }
    let (sheet, has_sheet) = find(tree, .Grid, "Sheet")
    var sorted_sizes = 0usize
    var k = 0usize
    while k < tree.nodes.len {
        if tree.nodes[k].role == .ColumnHeader && same(tree.nodes[k].label, "Size") && tree.nodes[k].state.selected { sorted_sizes += 1usize }
        k += 1usize
    }
    if !has_sheet || sheet.position.row_count != 50u32 || sorted_sizes != 1usize { os.exit(29i32) }
    if testing.by_text(&harness, "1").count == 0usize { os.exit(30i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(31i32) }
    try io.print("ui collections2 v2 ok\n")
    ret ok
}
