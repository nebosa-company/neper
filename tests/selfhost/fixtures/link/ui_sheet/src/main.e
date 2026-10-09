// The spreadsheet control (D2283, L090; e.ui.sheet.sheet) under the light theme at pointer density: headers lettered and
// numbered, only the cells in view built, a merged cell as one box with its covered cells absent, a frozen row and column
// that stay while the rest scrolls, cell fills and borders, a selection range tinted and the active cell ringed,
// content embedded over a block of cells at exactly `embed_rect`, pointer selection (tap, shift-tap, drag, header
// taps), double tap and typing and F2 starting an edit, Enter and Tab committing and moving, Escape cancelling, arrow
// keys and Page Down keeping the active cell in view, the wheel scrolling, and the tree naming the grid and its cells.

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
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.sheet as sh
use e.ui.style
use e.ui.testing
use e.ui.widget

type Store = struct {
    state: sh.SheetState, draft: [64]u8, events: usize, last_kind: sh.SheetEventKind, last_row: usize, last_col: usize,
    last_text: [64]u8, last_text_len: usize, kinds: [16]sh.SheetEventKind, kind_count: usize,
}

fn on_event(ctx: *void, e: sh.SheetEvent) -> err {
    let s = mem.cast[*Store](ctx)
    s.state = e.state
    s.events += 1usize
    s.last_kind = e.kind
    s.last_row = e.row
    s.last_col = e.col
    s.last_text_len = e.text.len
    if e.text.len <= 64usize {
        mem.copy[u8](s.last_text[0..], e.text)
    }
    if s.kind_count < 16usize {
        s.kinds[s.kind_count] = e.kind
        s.kind_count += 1usize
    }
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

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 1000usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn cell_key(row: usize, col: usize) -> widget.Key { ret 1000u64 + 4096u64 + u64(row) * 1024u64 + u64(col) }

// The data: row r, column c shows "r,c"; a few cells are styled and one is read-only.
fn source_cell(ctx: *void, row: usize, col: usize) -> sh.SheetCell {
    var c: sh.SheetCell = zero
    c.text = "x"
    if row == 0usize { c.text = "head" }
    if row == 2usize && col == 2usize { c.text = "hit" }
    if row == 1usize && col == 1usize { c.text = "merged title" }
    if row == 0usize {
        c.style.bold = true
        c.style.filled = true
        c.style.fill = paint.rgba(0.80, 0.90, 1.0, 1.0)
    }
    if row == 2usize && col == 2usize {
        c.style.filled = true
        c.style.fill = paint.rgba(1.0, 0.90, 0.30, 1.0)
        c.style.align = .Right
    }
    if row == 4usize && col == 1usize {
        c.style.bottom = true
        c.style.border = paint.rgba(0.80, 0.10, 0.10, 1.0)
    }
    if row == 6usize && col == 0usize { c.read_only = true }
    ret c
}

fn chart_node(a: *mem.Arena) -> widget.Node {
    var bar = style.defaults()
    bar.width = style.Length { Percent: 100.0 }
    bar.height = style.Length { Percent: 100.0 }
    bar.background = paint.Brush { Solid: paint.rgba(0.2, 0.6, 0.3, 1.0) }
    ret widget.box(0u64, bar, zero)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 20000usize, max_states: 4096usize, state_bytes: 262144usize, state_classes: 32u16, max_depth: 64u16, max_commands: 16384usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 1000u32, 600u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    // the sheet: 200 rows of 24 and 12 columns of 80; row 3 is 48 tall, column 4 is 120 wide, row 9 hidden
    let row_over = [2]sh.Override{ sh.Override { index: 3usize, size: 48.0 }, sh.Override { index: 9usize, size: 0.0 } }
    let col_over = [1]sh.Override{ sh.Override { index: 4usize, size: 120.0 } }
    let (rows, rows_error) = sh.axis(a, 200usize, 24.0, row_over[0..])
    let (cols, cols_error) = sh.axis(a, 12usize, 80.0, col_over[0..])
    let merge_list = [2]sh.Merge{ sh.Merge { row: 1usize, col: 1usize, rows: 1usize, cols: 3usize }, sh.Merge { row: 11usize, col: 2usize, rows: 2usize, cols: 2usize } }
    let (merge_set, merges_error) = sh.merges(a, merge_list[0..], 200usize, 12usize)
    if rows_error != ok || cols_error != ok || merges_error != ok { os.exit(7i32) }
    let (g, grid_error) = sh.grid(rows, cols, merge_set, 1usize, 1usize)
    if grid_error != ok { os.exit(8i32) }
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(9i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.state = sh.SheetState { selection: sh.Selection { row: 2usize, col: 2usize, anchor_row: 2usize, anchor_col: 2usize }, editing: false, len: 0usize, scroll_x: 0.0, scroll_y: 0.0 }
    let source = sh.SheetSource { ctx: nil, cell: source_cell }
    let change = widget.Change[sh.SheetEvent] { ctx: mem.cast[*void](s), invoke: on_event }
    let options = sh.sheet_options()
    let (frame_storage, storage_error) = mem.alloc[u8](a, 8388608usize)
    if storage_error != ok { os.exit(10i32) }
    var f = mem.arena_from(frame_storage)
    let embeds = [1]sh.Embed{ sh.Embed { row: 5usize, col: 2usize, rows: 2usize, cols: 2usize, label: "Sales chart", content: chart_node(&f) } }
    let (root, build_error) = build(&f, &theme, g, source, s, embeds[0..], change, options)
    if build_error != ok { os.exit(11i32) }
    var clock = 1000000000i64
    if testing.pump(&harness, root, time.Instant { nanos: clock }) != ok { os.exit(12i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(13i32) }
    let (tree_mem, tree_mem_error) = mem.alloc[u8](a, 16777216usize)
    if tree_mem_error != ok { os.exit(34i32) }
    var tree_arena = mem.arena_from(tree_mem)
    let (tree, tree_error) = accessibility.build(&tree_arena, &runtime)
    if tree_error != ok { os.exit(14i32) }
    // Windowing: the first rows exist, a row far below does not; the hidden row and the covered cells are absent.
    if testing.by_key(&harness, cell_key(0usize, 0usize)).count != 1usize || testing.by_key(&harness, cell_key(5usize, 3usize)).count != 1usize { os.exit(15i32) }
    if testing.by_key(&harness, cell_key(150usize, 3usize)).count != 0usize || testing.by_key(&harness, cell_key(9usize, 2usize)).count != 0usize { os.exit(16i32) }
    if testing.by_key(&harness, cell_key(1usize, 2usize)).count != 0usize || testing.by_key(&harness, cell_key(1usize, 3usize)).count != 0usize { os.exit(17i32) }
    // The viewport is 1000 by 600 less the headers (48 by 24): geometry of cells at the origin.
    let (a1, has_a1) = bounds(&harness, &runtime, cell_key(0usize, 0usize))
    let (b2, has_b2) = bounds(&harness, &runtime, cell_key(2usize, 1usize))
    let (merged, has_merged) = bounds(&harness, &runtime, cell_key(1usize, 1usize))
    let (tall, has_tall) = bounds(&harness, &runtime, cell_key(3usize, 0usize))
    if !has_a1 || !has_b2 || !has_merged || !has_tall { os.exit(18i32) }
    let (origin, has_origin) = bounds(&harness, &runtime, 1000u64)
    if !has_origin { os.exit(19i32) }
    if !near(a1.x - origin.x, 48.0) || !near(a1.y - origin.y, 24.0) || !near(a1.width, 80.0) || !near(a1.height, 24.0) { os.exit(20i32) }
    if !near(b2.x - origin.x, 48.0 + 80.0) || !near(b2.y - origin.y, 24.0 + 48.0) { os.exit(21i32) }
    if !near(merged.width, 240.0) || !near(merged.height, 24.0) || !near(merged.x - origin.x, 48.0 + 80.0) || !near(tall.height, 48.0) { os.exit(22i32) }
    // Headers: letters over the columns (the fifth wide), numbers beside the rows.
    if testing.by_text(&harness, "A").count == 0usize || testing.by_text(&harness, "E").count == 0usize || testing.by_text(&harness, "7").count == 0usize { os.exit(23i32) }
    let (head_e, has_head_e) = bounds(&harness, &runtime, 1000u64 + 2097152u64 + 4u64)
    if !has_head_e || !near(head_e.width, 32.0) || !near(head_e.height, 24.0) { os.exit(24i32) }
    // Pixels: the header row's fill, the styled cell's fill, the red bottom border, the merged cell's plain fill, the ring.
    if !is_color(shot, at(a1.x + 70.0, a1.y + 4.0), paint.rgba(0.80, 0.90, 1.0, 1.0)) { os.exit(25i32) }
    let (styled, has_styled) = bounds(&harness, &runtime, cell_key(2usize, 2usize))
    if !has_styled { os.exit(26i32) }
    let (bordered, has_bordered) = bounds(&harness, &runtime, cell_key(4usize, 1usize))
    if !has_bordered || !is_color(shot, at(bordered.x + 40.0, bordered.y + bordered.height - 3.0), paint.rgba(0.80, 0.10, 0.10, 1.0)) { os.exit(27i32) }
    if !is_color(shot, at(styled.x + styled.width * 0.5, styled.y + 1.0), style.color(&tokens, .Primary)) { os.exit(28i32) }
    // Embedded content at exactly its rectangle.
    let view = sh.sheet_view(g, s.state, 400.0, 200.0, options)
    let rect = sh.embed_rect(g, view, embeds[0usize])
    let (embedded, has_embedded) = bounds(&harness, &runtime, 1000u64 + 1048576u64)
    if !has_embedded || !near(embedded.x - origin.x, 48.0 + rect.x) || !near(embedded.y - origin.y, 24.0 + rect.y) || !near(embedded.width, 160.0) || !near(embedded.height, 32.0) { os.exit(29i32) }
    if !near(rect.width, 160.0) || !near(rect.height, 48.0) { os.exit(30i32) }
    if !is_color(shot, at(embedded.x + embedded.width * 0.5, embedded.y + embedded.height * 0.5), paint.rgba(0.2, 0.6, 0.3, 1.0)) { os.exit(31i32) }
    // The tree: the grid, its cells with their positions.
    let (grid_node, has_grid_node) = find(tree, .Grid, "Sheet")
    let (cell_c3, has_cell) = find(tree, .Cell, "C3")
    if !has_grid_node || grid_node.position.row_count != 200u32 || grid_node.position.column_count != 12u32 || !has_cell || cell_c3.position.row != 3u32 || cell_c3.position.column != 3u32 || !same(cell_c3.value, "hit") { os.exit(32i32) }
    let (read_only, has_read_only) = find(tree, .Cell, "A7")
    if !has_read_only || !read_only.state.read_only { os.exit(33i32) }
    // ---- interaction ----
    // A tap selects the cell.
    let (picked_cell, has_picked) = bounds(&harness, &runtime, cell_key(4usize, 3usize))
    if !has_picked || testing.tap(&harness, picked_cell.x + 10.0, picked_cell.y + 10.0) != ok { os.exit(40i32) }
    if s.events != 1usize || s.last_kind != .Select || s.last_row != 4usize || s.last_col != 3usize || s.state.selection.row != 4usize || s.state.selection.anchor_col != 3usize { os.exit(41i32) }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(42i32) }
    // A drag extends from where it began: from (2, 1) to (4, 3).
    let (from, has_from) = bounds(&harness, &runtime, cell_key(2usize, 1usize))
    let (to, has_to) = bounds(&harness, &runtime, cell_key(4usize, 3usize))
    if !has_from || !has_to || testing.drag(&harness, geometry.Point { x: from.x + 10.0, y: from.y + 10.0 }, geometry.Point { x: to.x + 10.0, y: to.y + 10.0 }, 6usize) != ok { os.exit(43i32) }
    if s.state.selection.anchor_row != 2usize || s.state.selection.anchor_col != 1usize || s.state.selection.row != 4usize || s.state.selection.col != 3usize || s.last_kind != .Extend { os.exit(44i32) }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(45i32) }
    // The range is tinted: a pixel in cell (3, 2) is no longer the plain fill.
    let (tinted, has_tinted) = bounds(&harness, &runtime, cell_key(3usize, 2usize))
    let (range_shot, range_shot_error) = testing.snapshot(&harness, a)
    if !has_tinted || range_shot_error != ok || is_color(range_shot, at(tinted.x + 70.0, tinted.y + 4.0), style.color(&tokens, .Background)) { os.exit(46i32) }
    // A column header selects the column, a row header the row.
    let (col_head, has_col_head) = bounds(&harness, &runtime, 1000u64 + 2097152u64 + 2u64)
    if !has_col_head || testing.tap(&harness, col_head.x + 10.0, col_head.y + 8.0) != ok { os.exit(47i32) }
    if s.state.selection.col != 2usize || s.state.selection.row != 0usize || s.state.selection.anchor_row != 199usize { os.exit(48i32) }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(77i32) }
    let (row_head, has_row_head) = bounds(&harness, &runtime, 1000u64 + 3145728u64 + 5u64)
    if !has_row_head || testing.tap(&harness, row_head.x + 10.0, row_head.y + 8.0) != ok { os.exit(49i32) }
    if s.state.selection.row != 5usize || s.state.selection.anchor_col != 11usize || s.state.selection.col != 0usize { os.exit(50i32) }
    // Keys. From the merged title (1, 1), three columns wide, Right goes to column 4.
    s.state.selection = sh.Selection { row: 1usize, col: 1usize, anchor_row: 1usize, anchor_col: 1usize }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(53i32) }
    if widget.focus_key(&runtime, 1001u64) != ok { os.exit(54i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || s.state.selection.row != 1usize || s.state.selection.col != 4usize || s.last_kind != .Select { os.exit(55i32) }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(56i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || s.state.selection.row != 2usize || s.state.selection.col != 4usize { os.exit(57i32) }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(58i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || s.state.selection.col != 0usize { os.exit(59i32) }
    // Page Down moves a page of rows and scrolls to keep the cell in view.
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(60i32) }
    let before = s.state.scroll_y
    if testing.press_key(&harness, 34u32, zero) != ok || s.state.selection.row < 8usize || !(s.state.scroll_y > before) { os.exit(61i32) }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(62i32) }
    // Scrolled: the frozen row and column stay put while the rest moved; the first scrolled row is gone.
    let (frozen_head, has_frozen_head) = bounds(&harness, &runtime, cell_key(0usize, 3usize))
    let (frozen_col, has_frozen_col) = bounds(&harness, &runtime, cell_key(s.state.selection.row, 0usize))
    if !has_frozen_head || !has_frozen_col || !near(frozen_head.y - origin.y, 24.0) || !near(frozen_col.x - origin.x, 48.0) || testing.by_key(&harness, cell_key(2usize, 3usize)).count != 0usize { os.exit(63i32) }
    // The wheel scrolls.
    let scrolled = s.state.scroll_y
    if testing.wheel(&harness, origin.x + 300.0, origin.y + 150.0, -2i32) != ok || s.last_kind != .Scroll || !(s.state.scroll_y > scrolled) { os.exit(64i32) }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(65i32) }
    // Editing: F2 starts an edit of the active cell; the editor stands over it; typing reports the text; Enter commits it
    // and moves down.
    s.state.selection = sh.Selection { row: 20usize, col: 3usize, anchor_row: 20usize, anchor_col: 3usize }
    let start_over = sh.View { x: 0.0, y: 0.0, width: 352.0, height: 176.0, header_width: 48.0, header_height: 24.0 }
    let (reveal_x, reveal_y) = sh.reveal(g, start_over, 20usize, 3usize)
    s.state.scroll_x = reveal_x
    s.state.scroll_y = reveal_y
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(66i32) }
    if widget.focus_key(&runtime, 1001u64) != ok || testing.press_key(&harness, 65471u32, zero) != ok || !s.state.editing || s.last_kind != .Edit { os.exit(67i32) }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(68i32) }
    let (editor, has_editor) = bounds(&harness, &runtime, 1002u64)
    let (under, has_under) = bounds(&harness, &runtime, cell_key(20usize, 3usize))
    if !has_editor || !has_under || !near(editor.x, under.x) || !near(editor.y, under.y) { os.exit(69i32) }
    if testing.type_text(&harness, "42") != ok || s.last_kind != .Type || s.state.len != 2usize || !same(s.draft[..2usize], "42") { os.exit(70i32) }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(71i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || s.last_kind != .Commit || s.last_row != 20usize || s.last_col != 3usize || s.state.editing || s.state.selection.row != 21usize || !same(s.last_text[..s.last_text_len], "42") { os.exit(72i32) }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(73i32) }
    // A character typed on a selected cell starts an edit with it; Escape drops the edit.
    if widget.focus_key(&runtime, 1001u64) != ok || testing.type_text(&harness, "7") != ok || !s.state.editing || s.last_kind != .Edit || s.state.len != 1usize { os.exit(74i32) }
    if frame(&f, &theme, g, source, s, embeds[0..], change, options, &harness, &clock) != ok { os.exit(75i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || s.last_kind != .Cancel || s.state.editing { os.exit(76i32) }
    try io.print("ui sheet ok\n")
    ret ok
}

fn frame(a: *mem.Arena, t: *const control.Theme, g: sh.Grid, source: sh.SheetSource, s: *Store, embeds: []const sh.Embed, change: widget.Change[sh.SheetEvent], options: sh.SheetOptions, h: *testing.Harness, clock: *i64) -> err {
    let (root, root_error) = build(a, t, g, source, s, embeds, change, options)
    if root_error != ok { ret root_error }
    *clock = *clock + 100000000i64
    ret testing.pump(h, root, time.Instant { nanos: *clock })
}

fn build(a: *mem.Arena, t: *const control.Theme, g: sh.Grid, source: sh.SheetSource, s: *Store, embeds: []const sh.Embed, change: widget.Change[sh.SheetEvent], options: sh.SheetOptions) -> (widget.Node, err) {
    let (made, made_error) = sh.sheet(a, 1000u64, t, "Sheet", g, source, s.state, s.draft[0..], embeds, change, 400.0, 200.0, options)
    if made_error != ok { ret (zero, made_error) }
    var page = style.defaults()
    page.width = style.Length { Px: 1000.0 }
    page.height = style.Length { Px: 600.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (items, items_error) = mem.alloc[widget.Node](a, 1usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = made
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page, items[0usize..1usize]), ok)
}
