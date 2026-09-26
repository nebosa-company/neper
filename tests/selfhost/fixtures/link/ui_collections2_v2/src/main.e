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
use e.ui.overlay
use e.algo.hash as hash
use e.ui.style
use e.ui.testing
use e.ui.widget

const W: usize = 400usize

type Log = struct { theme: *const control.Theme, sorts: usize, picks: usize, resizes: usize, reorders: usize, from: usize, to: usize, width: f32, offset: f32 }

// (D1312) A row action's report: counted, the last ask kept.
type ActLog = struct { count: usize, ask: collection.TableActionAsk }

fn on_row_action(ctx: *void, value: collection.TableActionAsk) -> err {
    let log = mem.cast[*ActLog](ctx)
    log.count += 1usize
    log.ask = value
    ret ok
}

// (D1313) A disclosure's press, kept as a row ask; and a detail row's content.
fn on_expand(ctx: *void, value: widget.Key) -> err {
    let log = mem.cast[*ActLog](ctx)
    log.count += 1usize
    log.ask.row = value
    ret ok
}

fn detail_of(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    *out = widget.box(0u64, control.sized_style(40.0, 20.0), zero)
    ret ok
}

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

// (D1246) What a selectable table said last, and how often.
type Chosen = struct { count: usize, kind: collection.ListSelectKind, index: usize }

fn on_choose(ctx: *void, value: collection.ListSelect) -> err {
    let chose = mem.cast[*Chosen](ctx)
    chose.count += 1usize
    chose.kind = value.kind
    chose.index = value.index
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

fn no_row_count(ctx: *void) -> usize {
    ret 0usize
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

// (D1328) A cell source whose cells are 30 wide boxes, keyed by row in the third column.
fn numeric_cell_key(index: usize) -> widget.Key {
    ret 9000u64 + u64(index)
}

fn numeric_row_cell(ctx: *void, a: *mem.Arena, index: usize, column: usize, out: *widget.Node) -> err {
    var key: widget.Key = 0u64
    if column == 2usize { key = numeric_cell_key(index) }
    *out = widget.box(key, control.sized_style(30.0, 10.0), zero)
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
    // (D1246) A selectable table: with nothing selected the select-all checkbox is
    // clear, a row's checkbox toggles it, a plain row click still picks, a
    // Ctrl-click toggles, Space toggles and Ctrl+A selects all; with Beta selected
    // the bar says "1 selected", select-all is mixed and a plain click toggles.
    var chose: Chosen = zero
    var table_choice: collection.TableOptions = zero
    table_choice.select = widget.Change[collection.ListSelect] { ctx: mem.cast[*void](&chose), invoke: on_choose }
    // (D1304) Bulk actions stand in the bar as text buttons.
    var bulk_commands: [2]overlay.MenuCommand = zero
    bulk_commands[0usize].label = "Archive"
    bulk_commands[0usize].enabled = true
    bulk_commands[1usize].label = "Delete"
    bulk_commands[1usize].enabled = true
    bulk_commands[1usize].destructive = true
    table_choice.bulk = bulk_commands[..]
    var held_control: input.Modifiers = zero
    held_control.control = true
    var picked_keys: [1]widget.Key = zero
    picked_keys[0usize] = 1001u64
    var sel_step = 0usize
    while sel_step < 2usize {
        f = mem.arena_from(frame_storage)
        var shown_keys = picked_keys[0usize..0usize]
        if sel_step == 1usize { shown_keys = picked_keys[0usize..1usize] }
        let pick_source = collection.TableSource { ctx: ctx, count: row_count, key: row_key, cell: row_cell }
        let (pickable, pickable_error) = collection.table_with(&f, 1u64, &theme, "Files", columns[0usize..3usize], pick_source, shown_keys, 0usize, false, zero, zero, zero, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 0.0, 0.0, zero, 300.0, table_choice)
        let (pickable_page, pickable_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if pickable_error != ok || pickable_page_error != ok { os.exit(57i32) }
        pickable_page[0usize] = pickable
        var pickable_ground = style.defaults()
        pickable_ground.width = style.Length { Px: 400.0 }
        pickable_ground.height = style.Length { Px: 360.0 }
        pickable_ground.background = paint.Brush { Solid: background }
        if testing.pump(&harness, widget.box(0u64, pickable_ground, pickable_page[0usize..1usize]), time.Instant { nanos: 5000000000i64 + i64(sel_step) }) != ok { os.exit(58i32) }
        let (pick_tree, pick_tree_error) = testing.semantics(&harness)
        if pick_tree_error != ok { os.exit(59i32) }
        let (select_all, has_select_all) = find(pick_tree, .Checkbox, "Select all Files")
        let (first_check, has_first_check) = find(pick_tree, .Checkbox, "Select")
        if !has_select_all || !has_first_check { os.exit(60i32) }
        let (beta_row, has_beta_row) = bounds(&harness, &runtime, 1001u64)
        let (gamma_row, has_gamma_row) = bounds(&harness, &runtime, 1002u64)
        if !has_beta_row || !has_gamma_row { os.exit(61i32) }
        if sel_step == 0usize {
            if select_all.state.checked || select_all.state.mixed || testing.by_text(&harness, "1 selected").count != 0usize { os.exit(62i32) }
            if testing.tap(&harness, first_check.bounds.x + first_check.bounds.width * 0.5, first_check.bounds.y + first_check.bounds.height * 0.5) != ok || chose.kind != .Toggle || chose.index != 0usize { os.exit(63i32) }
            let picks_before = logs[0usize].picks
            let chose_before = chose.count
            if testing.tap(&harness, beta_row.x + beta_row.width * 0.6, beta_row.y + beta_row.height * 0.5) != ok || logs[0usize].picks != picks_before + 1usize || chose.count != chose_before { os.exit(64i32) }
            if widget.dispatch(&runtime, input.Event { KeyDown: input.KeyEvent { window: testing.no_window(), key: input.Key { physical: 17u32, logical: 17u32 }, modifiers: held_control, repeat: false } }) != ok { os.exit(65i32) }
            if testing.tap(&harness, gamma_row.x + gamma_row.width * 0.6, gamma_row.y + gamma_row.height * 0.5) != ok || chose.kind != .Toggle || chose.index != 2usize { os.exit(66i32) }
            if widget.dispatch(&runtime, input.Event { KeyUp: input.KeyEvent { window: testing.no_window(), key: input.Key { physical: 17u32, logical: 17u32 }, modifiers: zero, repeat: false } }) != ok { os.exit(67i32) }
            if widget.focus(&runtime, testing.by_key(&harness, 1001u64).element) != ok || testing.press_key(&harness, 32u32, zero) != ok || chose.kind != .Toggle || chose.index != 1usize { os.exit(68i32) }
            if testing.press_key(&harness, 65u32, held_control) != ok || chose.kind != .All { os.exit(69i32) }
        }
        if sel_step == 1usize {
            if select_all.state.checked || !select_all.state.mixed || testing.by_text(&harness, "1 selected").count == 0usize { os.exit(70i32) }
            let (_, has_delete) = find(pick_tree, .Button, "Delete")
            if !has_delete || testing.by_text(&harness, "Delete").count == 0usize || testing.by_text(&harness, "Archive").count == 0usize { os.exit(83i32) }
            let picks_before = logs[0usize].picks
            if testing.tap(&harness, gamma_row.x + gamma_row.width * 0.6, gamma_row.y + gamma_row.height * 0.5) != ok || logs[0usize].picks != picks_before || chose.kind != .Toggle || chose.index != 2usize { os.exit(71i32) }
            if testing.tap(&harness, select_all.bounds.x + select_all.bounds.width * 0.5, select_all.bounds.y + select_all.bounds.height * 0.5) != ok || chose.kind != .All { os.exit(72i32) }
        }
        sel_step += 1usize
    }
    // (D1312) Row actions: none on a resting row; hovered, Rerun and Download stand
    // in its last cell, and a press on Download reports the row and the action.
    var act_log: ActLog = zero
    var action_specs: [2]collection.TableAction = zero
    action_specs[0usize] = collection.TableAction { label: "Rerun", glyph: .Refresh }
    action_specs[1usize] = collection.TableAction { label: "Download", glyph: .ArrowDown }
    var act_options: collection.TableOptions = zero
    act_options.row_actions = action_specs[..]
    act_options.act = widget.Change[collection.TableActionAsk] { ctx: mem.cast[*void](&act_log), invoke: on_row_action }
    if testing.hover(&harness, 395.0, 355.0) != ok { os.exit(89i32) }
    var act_step = 0usize
    while act_step < 2usize {
        f = mem.arena_from(frame_storage)
        let act_source = collection.TableSource { ctx: ctx, count: row_count, key: row_key, cell: row_cell }
        let (acting, acting_error) = collection.table_with(&f, 7u64, &theme, "Files", columns[0usize..3usize], act_source, picked_keys[0usize..0usize], 0usize, false, zero, zero, zero, zero, 0.0, 0.0, zero, 300.0, act_options)
        let (acting_page, acting_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if acting_error != ok || acting_page_error != ok { os.exit(84i32) }
        acting_page[0usize] = acting
        var acting_ground = control.sized_style(400.0, 360.0)
        acting_ground.background = paint.Brush { Solid: background }
        if testing.pump(&harness, widget.box(0u64, acting_ground, acting_page[0usize..1usize]), time.Instant { nanos: 5100000000i64 + i64(act_step) }) != ok { os.exit(85i32) }
        let actions_shown = testing.by_key(&harness, (1003u64 ^ hash.fnv1a64("row-action")) + 1u64).count
        if act_step == 0usize {
            let (act_row, has_act_row) = bounds(&harness, &runtime, 1003u64)
            if !has_act_row { os.exit(90i32) }
            if actions_shown != 0usize { os.exit(91i32) }
            if testing.hover(&harness, act_row.x + 20.0, act_row.y + act_row.height * 0.5) != ok { os.exit(86i32) }
        }
        if act_step == 1usize {
            if actions_shown != 1usize { os.exit(87i32) }
            let download_key = 1003u64 ^ hash.fnv1a64("row-action")
            let (download, has_download) = bounds(&harness, &runtime, download_key + 1u64)
            if !has_download || testing.tap(&harness, download.x + 16.0, download.y + 16.0) != ok || act_log.count != 1usize || act_log.ask.row != 1003u64 || act_log.ask.action != 1usize { os.exit(88i32) }
        }
        act_step += 1usize
    }
    // (D1313) Expandable rows: each first cell leads with its disclosure; a press
    // reports the row; the open row is followed by its detail on
    // `surface-container-low`, and its disclosure says expanded.
    var opened_row: [1]widget.Key = zero
    opened_row[0usize] = 1002u64
    var expand_log: ActLog = zero
    var open_options: collection.TableOptions = zero
    open_options.expandable = true
    open_options.expanded = opened_row[..]
    open_options.expand = widget.Change[widget.Key] { ctx: mem.cast[*void](&expand_log), invoke: on_expand }
    open_options.detail = collection.TableDetail { ctx: mem.cast[*void](&expand_log), build: detail_of }
    f = mem.arena_from(frame_storage)
    let open_source = collection.TableSource { ctx: ctx, count: row_count, key: row_key, cell: row_cell }
    let (opening, opening_error) = collection.table_with(&f, 8u64, &theme, "Files", columns[0usize..3usize], open_source, picked_keys[0usize..0usize], 0usize, false, zero, zero, zero, zero, 0.0, 0.0, zero, 300.0, open_options)
    let (opening_page, opening_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if opening_error != ok || opening_page_error != ok { os.exit(92i32) }
    opening_page[0usize] = opening
    if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 360.0), opening_page[0usize..1usize]), time.Instant { nanos: 5200000000i64 }) != ok { os.exit(93i32) }
    let (detail_box, has_detail_box) = bounds(&harness, &runtime, 1002u64 ^ hash.fnv1a64("row-detail"))
    let (open_row, has_open_row) = bounds(&harness, &runtime, 1002u64)
    if !has_detail_box || !has_open_row || !(detail_box.y >= open_row.y + open_row.height - 0.5) || testing.by_key(&harness, 1001u64 ^ hash.fnv1a64("row-detail")).count != 0usize { os.exit(94i32) }
    let (open_tree, open_tree_error) = testing.semantics(&harness)
    if open_tree_error != ok { os.exit(95i32) }
    var expanded_twisties = 0usize
    var twisty_count = 0usize
    var tn = 0usize
    while tn < open_tree.nodes.len {
        if same(open_tree.nodes[tn].label, "Details") {
            twisty_count += 1usize
            if open_tree.nodes[tn].state.expanded { expanded_twisties += 1usize }
        }
        tn += 1usize
    }
    if twisty_count < 3usize || expanded_twisties != 1usize { os.exit(96i32) }
    let (gamma_twisty, has_gamma_twisty) = bounds(&harness, &runtime, 1003u64 ^ hash.fnv1a64("row-disclose"))
    if !has_gamma_twisty || testing.tap(&harness, gamma_twisty.x + 12.0, gamma_twisty.y + 12.0) != ok || expand_log.count != 1usize || expand_log.ask.row != 1003u64 { os.exit(97i32) }
    // (D1328) A numeric third column: its cells end at the column's end, 16 in.
    var numbers_only: [3]bool = zero
    numbers_only[2usize] = true
    var numeric_options: collection.TableOptions = zero
    numeric_options.numeric = numbers_only[..]
    // (D1340) ...and the second column filtered: its header says so.
    var filtered_only: [3]bool = zero
    filtered_only[1usize] = true
    numeric_options.filtered = filtered_only[..]
    // (D1341) ...and Size and Kind grouped under "Detail".
    var detail_group: [1]collection.HeaderGroup = zero
    detail_group[0usize] = collection.HeaderGroup { title: "Detail", first: 1usize, span: 2usize }
    numeric_options.groups = detail_group[..]
    f = mem.arena_from(frame_storage)
    let numeric_source = collection.TableSource { ctx: ctx, count: row_count, key: row_key, cell: numeric_row_cell }
    let (numeric_table, numeric_table_error) = collection.table_with(&f, 9u64, &theme, "Files", columns[0usize..3usize], numeric_source, picked_keys[0usize..0usize], 0usize, false, zero, zero, zero, zero, 0.0, 0.0, zero, 300.0, numeric_options)
    let (numeric_page, numeric_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if numeric_table_error != ok || numeric_page_error != ok { os.exit(98i32) }
    numeric_page[0usize] = numeric_table
    if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 360.0), numeric_page[0usize..1usize]), time.Instant { nanos: 5300000000i64 }) != ok { os.exit(99i32) }
    let (numeric_row, has_numeric_row) = bounds(&harness, &runtime, 1001u64)
    let (numeric_cell, has_numeric_cell) = bounds(&harness, &runtime, numeric_cell_key(1usize))
    if !has_numeric_row || !has_numeric_cell || !near(numeric_cell.x + numeric_cell.width, numeric_row.x + numeric_row.width - 16.0) { os.exit(100i32) }
    let (filter_tree, filter_tree_error) = testing.semantics(&harness)
    let (size_head, has_size_head) = find(filter_tree, .ColumnHeader, "Size")
    let (name_head, has_name_head) = find(filter_tree, .ColumnHeader, "Name")
    if filter_tree_error != ok || !has_size_head || !has_name_head || !same(size_head.hint, "filtered") || name_head.hint.len != 0usize { os.exit(101i32) }
    let (detail_head, has_detail_head) = find(filter_tree, .ColumnHeader, "Detail")
    if !has_detail_head || !near(detail_head.bounds.width, 180.0) || !near(detail_head.bounds.x, size_head.bounds.x) || !(detail_head.bounds.y + detail_head.bounds.height <= size_head.bounds.y + 0.5) { os.exit(102i32) }
    // (D1345) A header held mid-drag lifts onto `surface-container-highest`;
    // released, it rests.
    var lift_step = 0usize
    while lift_step < 3usize {
        f = mem.arena_from(frame_storage)
        let lift_source = collection.TableSource { ctx: ctx, count: row_count, key: row_key, cell: row_cell }
        var lift_options: collection.TableOptions = zero
        let (lifting, lifting_error) = collection.table_with(&f, 11u64, &theme, "Files", columns[0usize..3usize], lift_source, picked_keys[0usize..0usize], 0usize, false, zero, zero, zero, zero, 0.0, 0.0, zero, 300.0, lift_options)
        let (lift_page, lift_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if lifting_error != ok || lift_page_error != ok { os.exit(103i32) }
        lift_page[0usize] = lifting
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 360.0), lift_page[0usize..1usize]), time.Instant { nanos: 5400000000i64 + i64(lift_step) }) != ok { os.exit(104i32) }
        let (kind_head, has_kind_head) = bounds(&harness, &runtime, 16u64)
        let (lift_shot, lift_shot_error) = testing.snapshot(&harness, a)
        if !has_kind_head || lift_shot_error != ok { os.exit(105i32) }
        let risen = is_color(lift_shot, at(kind_head.x + kind_head.width - 12.0, kind_head.y + 4.0), style.color(&tokens, .SurfaceContainerHighest))
        if lift_step == 0usize {
            if risen || testing.send(&harness, input.Event { PointerDown: testing.pointer_at(kind_head.x + 20.0, kind_head.y + 20.0) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(kind_head.x + 40.0, kind_head.y + 20.0) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(kind_head.x + 60.0, kind_head.y + 20.0) }) != ok { os.exit(106i32) }
        }
        if lift_step == 1usize {
            if !risen || testing.send(&harness, input.Event { PointerUp: testing.pointer_at(kind_head.x + 60.0, kind_head.y + 20.0) }) != ok { os.exit(107i32) }
        }
        if lift_step == 2usize && risen { os.exit(108i32) }
        lift_step += 1usize
    }
    // (D1357) Name dragged over Kind: the handle after Kind turns `primary`;
    // released, it goes back.
    var land_step = 0usize
    while land_step < 3usize {
        f = mem.arena_from(frame_storage)
        let land_source = collection.TableSource { ctx: ctx, count: row_count, key: row_key, cell: row_cell }
        var land_options: collection.TableOptions = zero
        let (landing_table, landing_table_error) = collection.table_with(&f, 11u64, &theme, "Files", columns[0usize..3usize], land_source, picked_keys[0usize..0usize], 0usize, false, zero, zero, zero, zero, 0.0, 0.0, zero, 300.0, land_options)
        let (land_page, land_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if landing_table_error != ok || land_page_error != ok { os.exit(109i32) }
        land_page[0usize] = landing_table
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 360.0), land_page[0usize..1usize]), time.Instant { nanos: 5500000000i64 + i64(land_step) }) != ok { os.exit(110i32) }
        let (kind_at, has_kind_at) = bounds(&harness, &runtime, 16u64)
        let (name_at, has_name_at) = bounds(&harness, &runtime, 12u64)
        let (after_kind, has_after_kind) = bounds(&harness, &runtime, 17u64)
        let (land_shot, land_shot_error) = testing.snapshot(&harness, a)
        if !has_kind_at || !has_name_at || !has_after_kind || land_shot_error != ok { os.exit(111i32) }
        let lit = is_color(land_shot, at(after_kind.x + 4.0, after_kind.y + 2.0), style.color(&tokens, .Primary))
        if land_step == 0usize {
            if lit || testing.send(&harness, input.Event { PointerDown: testing.pointer_at(name_at.x + 20.0, name_at.y + 20.0) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(name_at.x + 30.0, name_at.y + 20.0) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(kind_at.x + 30.0, kind_at.y + 20.0) }) != ok { os.exit(112i32) }
        }
        if land_step == 1usize {
            if !lit { os.exit(113i32) }
            if testing.send(&harness, input.Event { PointerUp: testing.pointer_at(kind_at.x + 30.0, kind_at.y + 20.0) }) != ok { os.exit(114i32) }
        }
        if land_step == 2usize && lit { os.exit(115i32) }
        land_step += 1usize
    }
    // (D1383) A touch held 600 ms on the first row of a selectable table with
    // nothing selected toggles it into the selection; the release picks nothing.
    var held_chose: Chosen = zero
    var hold_choice: collection.TableOptions = zero
    hold_choice.select = widget.Change[collection.ListSelect] { ctx: mem.cast[*void](&held_chose), invoke: on_choose }
    var hold_step = 0usize
    var hold_touch = testing.pointer_at(0.0, 0.0)
    while hold_step < 3usize {
        var hold_at = 5600000000i64
        if hold_step == 1usize { hold_at = 5700000000i64 }
        if hold_step == 2usize { hold_at = 6300000000i64 }
        if testing.begin(&harness, time.Instant { nanos: hold_at }) != ok { os.exit(120i32) }
        f = mem.arena_from(frame_storage)
        let hold_source = collection.TableSource { ctx: ctx, count: row_count, key: row_key, cell: row_cell }
        let (holding, holding_error) = collection.table_with(&f, 31u64, &theme, "Files", columns[0usize..3usize], hold_source, picked_keys[0usize..0usize], 0usize, false, zero, zero, zero, zero, 0.0, 0.0, zero, 300.0, hold_choice)
        let (hold_page, hold_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if holding_error != ok || hold_page_error != ok { os.exit(121i32) }
        hold_page[0usize] = holding
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 360.0), hold_page[0usize..1usize]), time.Instant { nanos: hold_at }) != ok { os.exit(122i32) }
        if hold_step == 0usize {
            let (first_row, has_first_row) = bounds(&harness, &runtime, 1000u64)
            if !has_first_row { os.exit(123i32) }
            hold_touch = testing.pointer_at(first_row.x + first_row.width * 0.5, first_row.y + first_row.height * 0.5)
            hold_touch.kind = .Touch
            if testing.send(&harness, input.Event { PointerDown: hold_touch }) != ok { os.exit(124i32) }
        }
        hold_step += 1usize
    }
    if held_chose.count != 1usize || held_chose.kind != .Toggle || held_chose.index != 0usize { os.exit(125i32) }
    if testing.send(&harness, input.Event { PointerUp: hold_touch }) != ok || held_chose.count != 1usize { os.exit(126i32) }
    // (D1248) With no rows the header stays over the loading state (a busy
    // "Loading" group under an indeterminate progress bar) or the empty state.
    var state_step = 0usize
    while state_step < 2usize {
        var state_options: collection.TableOptions = zero
        state_options.loading = state_step == 0usize
        state_options.empty_title = "No builds yet"
        state_options.empty_message = "Builds you start appear here"
        f = mem.arena_from(frame_storage)
        let empty_source = collection.TableSource { ctx: ctx, count: no_row_count, key: row_key, cell: row_cell }
        let (stated, stated_error) = collection.table_with(&f, 1u64, &theme, "Builds", columns[0usize..3usize], empty_source, picked_keys[0usize..0usize], 0usize, false, zero, zero, zero, zero, 0.0, 0.0, zero, 300.0, state_options)
        let (stated_page, stated_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if stated_error != ok || stated_page_error != ok { os.exit(73i32) }
        stated_page[0usize] = stated
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 360.0), stated_page[0usize..1usize]), time.Instant { nanos: 5100000000i64 + i64(state_step) }) != ok { os.exit(74i32) }
        let (state_tree, state_tree_error) = testing.semantics(&harness)
        if state_tree_error != ok { os.exit(75i32) }
        let (loading_group, has_loading_group) = find(state_tree, .Group, "Loading")
        let (_, has_state_header) = find(state_tree, .ColumnHeader, "Name")
        if !has_state_header { os.exit(76i32) }
        if state_step == 0usize && (!has_loading_group || !loading_group.state.busy || testing.by_role(&harness, .Progress).count == 0usize) { os.exit(77i32) }
        if state_step == 1usize && (has_loading_group || testing.by_text(&harness, "No builds yet").count == 0usize) { os.exit(78i32) }
        state_step += 1usize
    }
    // (D1283) The 300 wide columns in a 200 view scroll sideways: the viewport is
    // 200 over 300 of content.
    var narrow_options: collection.TableOptions = zero
    narrow_options.view_width = 200.0
    f = mem.arena_from(frame_storage)
    let narrow_source = collection.TableSource { ctx: ctx, count: row_count, key: row_key, cell: row_cell }
    let (narrow_table, narrow_error) = collection.table_with(&f, 1u64, &theme, "Files", columns[0usize..3usize], narrow_source, picked_keys[0usize..0usize], 0usize, false, zero, zero, zero, zero, 0.0, 0.0, zero, 300.0, narrow_options)
    let (narrow_page, narrow_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if narrow_error != ok || narrow_page_error != ok { os.exit(79i32) }
    narrow_page[0usize] = narrow_table
    if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 360.0), narrow_page[0usize..1usize]), time.Instant { nanos: 5200000000i64 }) != ok { os.exit(80i32) }
    let (side_view, has_side_view) = bounds(&harness, &runtime, 1u64 + 2097152u64)
    if !has_side_view || !near(side_view.width, 200.0) { os.exit(81i32) }
    let (_, has_side_extents) = widget.scroll_offset_of(&runtime, testing.by_key(&harness, 1u64 + 2097152u64).element)
    let (side_content, side_shown, has_side) = widget.scroll_extents(&runtime, testing.by_key(&harness, 1u64 + 2097152u64).element)
    if !has_side_extents || !has_side || !near(side_content, 300.0) || !near(side_shown, 200.0) { os.exit(82i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(31i32) }
    try io.print("ui collections2 v2 ok\n")
    ret ok
}
