// `e.ui.collection`'s rich tabular data (D845, widget plan P3-01): a table builds
// only the rows in view under a header whose taps sort, whose drags reorder and
// whose handles resize, its rows picking by key; a data grid is the same as a
// grid; a tree shows the expanded nodes' children only, its marks and Left/Right
// toggling, its rows picking; an outline draws guides; a tree table hangs
// columns off a tree.

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

type Log = struct { theme: *const control.Theme, cells: usize, sorts: usize, sorted: usize, reorders: usize, reorder: collection.Reorder, resizes: usize, resized: collection.ColumnResize, picks: usize, picked: widget.Key, toggles: usize, toggled: widget.Key }

fn on_sort(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.sorts += 1usize
    log.sorted = value
    ret ok
}

fn on_reorder(ctx: *void, value: collection.Reorder) -> err {
    let log = mem.cast[*Log](ctx)
    log.reorders += 1usize
    log.reorder = value
    ret ok
}

fn on_resize(ctx: *void, value: collection.ColumnResize) -> err {
    let log = mem.cast[*Log](ctx)
    log.resizes += 1usize
    log.resized = value
    ret ok
}

fn on_pick(ctx: *void, value: widget.Key) -> err {
    let log = mem.cast[*Log](ctx)
    log.picks += 1usize
    log.picked = value
    ret ok
}

fn on_toggle(ctx: *void, value: widget.Key) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    log.toggled = value
    ret ok
}

fn on_scroll(ctx: *void, value: f32) -> err {
    ret ok
}

// A text of one letter for a row and column: 'a' + column, so a cell reads.
fn letter(a: *mem.Arena, t: *const control.Theme, code: u8, out: *widget.Node) -> err {
    let (bytes, bytes_error) = mem.alloc[u8](a, 1usize)
    if bytes_error != ok { ret bytes_error }
    bytes[0usize] = code
    var caption = control.text_options()
    caption.wrap = .None
    let (made, made_error) = control.text(a, 0u64, bytes[0usize..1usize], t, caption)
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

// The table's source: two hundred rows keyed 1000 up, a cell's letter by column.
fn table_count(ctx: *void) -> usize {
    ret 200usize
}

fn table_key(ctx: *void, index: usize) -> widget.Key {
    ret 1000u64 + u64(index)
}

fn table_cell(ctx: *void, a: *mem.Arena, row: usize, column: usize, out: *widget.Node) -> err {
    let log = mem.cast[*Log](ctx)
    log.cells += 1usize
    ret letter(a, log.theme, 97u8 + u8(column), out)
}

// The tree's source: A (5001) with A1 and A2 (5011, 5012), B (5002) with B1 (5021),
// C (5003); a row shows its letter.
fn tree_count(ctx: *void, parent: widget.Key) -> usize {
    if parent == 0u64 { ret 3usize }
    if parent == 5001u64 { ret 2usize }
    if parent == 5002u64 { ret 1usize }
    ret 0usize
}

fn tree_key(ctx: *void, parent: widget.Key, index: usize) -> widget.Key {
    if parent == 0u64 { ret 5001u64 + u64(index) }
    ret parent * 10u64 + 1u64 + u64(index) - 50000u64
}

fn tree_has_children(ctx: *void, key: widget.Key) -> bool {
    ret key == 5001u64 || key == 5002u64
}

fn tree_build(ctx: *void, a: *mem.Arena, key: widget.Key, out: *widget.Node) -> err {
    let log = mem.cast[*Log](ctx)
    var code = 65u8
    if key == 5002u64 || key == 21u64 { code = 66u8 }
    if key == 5003u64 { code = 67u8 }
    if key == 11u64 || key == 12u64 { code = 120u8 }
    ret letter(a, log.theme, code, out)
}

fn tree_cell(ctx: *void, a: *mem.Arena, key: widget.Key, column: usize, out: *widget.Node) -> err {
    let log = mem.cast[*Log](ctx)
    ret letter(a, log.theme, 107u8, out)
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

type Sources = struct { table: collection.TableSource, tree: collection.TreeSource, cells: collection.CellSource }

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, sources: *const Sources, columns: []const collection.Column, expanded: []const widget.Key, which: usize) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
    if parts_error != ok { ret (zero, parts_error) }
    var chosen: [1]widget.Key = zero
    chosen[0usize] = 1002u64
    var picked_node: [1]widget.Key = zero
    picked_node[0usize] = 5003u64
    if which == 0usize {
        let (made, made_error) = collection.table(a, 1u64, t, "Files", columns, sources.table, chosen[..], 0usize, false, widget.Change[usize] { ctx: ctx, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: ctx, invoke: on_reorder }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: on_resize }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 24.0, 0.0, widget.Change[f32] { ctx: ctx, invoke: on_scroll }, 120.0)
        if made_error != ok { ret (zero, made_error) }
        parts[0usize] = made
    }
    if which == 1usize {
        let (made, made_error) = collection.data_grid(a, 1u64, t, "Sheet", columns, sources.table, chosen[..], 0usize, true, widget.Change[usize] { ctx: ctx, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: ctx, invoke: on_reorder }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: on_resize }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 24.0, 0.0, widget.Change[f32] { ctx: ctx, invoke: on_scroll }, 72.0)
        if made_error != ok { ret (zero, made_error) }
        parts[0usize] = made
    }
    if which == 2usize {
        let (made, made_error) = collection.tree(a, 100u64, t, "Nodes", sources.tree, expanded, picked_node[..], widget.Change[widget.Key] { ctx: ctx, invoke: on_toggle }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 24.0, 200.0)
        if made_error != ok { ret (zero, made_error) }
        parts[0usize] = made
    }
    if which == 3usize {
        let (made, made_error) = collection.outline(a, 100u64, t, "Outline", sources.tree, expanded, picked_node[..], widget.Change[widget.Key] { ctx: ctx, invoke: on_toggle }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 24.0, 200.0)
        if made_error != ok { ret (zero, made_error) }
        parts[0usize] = made
    }
    if which == 4usize {
        let (made, made_error) = collection.tree_table(a, 200u64, t, "Sizes", columns[0usize..2usize], sources.tree, sources.cells, expanded, picked_node[..], widget.Change[widget.Key] { ctx: ctx, invoke: on_toggle }, widget.Change[widget.Key] { ctx: ctx, invoke: on_pick }, 1usize, false, widget.Change[usize] { ctx: ctx, invoke: on_sort }, widget.Change[collection.Reorder] { ctx: ctx, invoke: on_reorder }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: on_resize }, 24.0)
        if made_error != ok { ret (zero, made_error) }
        parts[0usize] = made
    }
    var column = style.defaults()
    column.width = style.Length { Px: 320.0 }
    column.height = style.Length { Px: 300.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, parts[0usize..1usize]), ok)
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn count_role(tree: accessibility.Tree, role: accessibility.Role) -> usize {
    var n = 0usize
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role { n += 1usize }
        i += 1usize
    }
    ret n
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 400usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 300u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    log.theme = &theme
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (sources, sources_error) = mem.alloc[Sources](a, 1usize)
    if sources_error != ok { os.exit(8i32) }
    sources[0usize] = Sources { table: collection.TableSource { ctx: ctx, count: table_count, key: table_key, cell: table_cell }, tree: collection.TreeSource { ctx: ctx, count: tree_count, key: tree_key, has_children: tree_has_children, build: tree_build }, cells: collection.CellSource { ctx: ctx, cell: tree_cell } }
    let (columns, columns_error) = mem.alloc[collection.Column](a, 3usize)
    if columns_error != ok { os.exit(9i32) }
    columns[0usize] = collection.Column { title: "Name", width: 100.0 }
    columns[1usize] = collection.Column { title: "Size", width: 60.0 }
    columns[2usize] = collection.Column { title: "Kind", width: 80.0 }
    let (expanded, expanded_error) = mem.alloc[widget.Key](a, 1usize)
    if expanded_error != ok { os.exit(10i32) }
    expanded[0usize] = 5001u64
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(11i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    // The table: a table of two hundred rows and three columns, three column
    // headers with the sorted one marked, only the rows in view and the overscan
    // built, the row keyed 1002 selected.
    let (root, build_error) = build(&frame, &theme, ctx, &sources[0usize], columns[0usize..3usize], expanded[0usize..1usize], 0usize)
    if build_error != ok || testing.pump(&harness, root, now) != ok { os.exit(12i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(13i32) }
    let (files, has_files) = find(tree, .Table, "Files")
    if !has_files || files.position.row_count != 200u32 || files.position.column_count != 3u32 { os.exit(14i32) }
    if count_role(tree, .ColumnHeader) != 3usize || testing.by_text(&harness, "Name").count == 0usize { os.exit(15i32) }
    // The header is a row too; every built row cost three cells; not every row was.
    let built_rows = count_role(tree, .Row) - 1usize
    if built_rows < 4usize || built_rows > 8usize || logs[0usize].cells != 3usize * built_rows { os.exit(16i32) }
    var selected_rows = 0usize
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .Row && tree.nodes[i].state.selected && tree.nodes[i].position.row == 3u32 { selected_rows += 1usize }
        i += 1usize
    }
    if selected_rows != 1usize { os.exit(17i32) }
    // A tap on the Size header asks to sort by 1; dragging Kind's header onto
    // Name's reorders 2 to 0; dragging Name's handle 40 right resizes Name to
    // 140; a tap on a row picks its key.
    let (size_at, has_size) = centre_of(&harness, &runtime, 4u64)
    if !has_size || testing.tap(&harness, size_at.x, size_at.y) != ok || logs[0usize].sorts != 1usize || logs[0usize].sorted != 1usize { os.exit(18i32) }
    let (kind_at, has_kind) = centre_of(&harness, &runtime, 6u64)
    let (name_at, has_name) = centre_of(&harness, &runtime, 2u64)
    if !has_kind || !has_name || testing.drag(&harness, kind_at, name_at, 5usize) != ok { os.exit(19i32) }
    if logs[0usize].reorders != 1usize || logs[0usize].reorder.from != 2usize || logs[0usize].reorder.to != 0usize { os.exit(20i32) }
    let (grip_at, has_grip) = centre_of(&harness, &runtime, 3u64)
    if !has_grip || testing.drag(&harness, grip_at, geometry.Point { x: grip_at.x + 40.0, y: grip_at.y }, 4usize) != ok { os.exit(21i32) }
    if logs[0usize].resizes == 0usize || logs[0usize].resized.column != 0usize || logs[0usize].resized.width < 135.0 || logs[0usize].resized.width > 145.0 { os.exit(22i32) }
    let (row_at, has_row) = centre_of(&harness, &runtime, 1001u64)
    if !has_row || testing.tap(&harness, row_at.x, row_at.y) != ok || logs[0usize].picks != 1usize || logs[0usize].picked != 1001u64 { os.exit(23i32) }
    // The data grid: a grid in the tree, sorted descending.
    let (root_2, build_2_error) = build(&frame, &theme, ctx, &sources[0usize], columns[0usize..3usize], expanded[0usize..1usize], 1usize)
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(24i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(25i32) }
    let (sheet, has_sheet) = find(tree_2, .Grid, "Sheet")
    if !has_sheet || testing.by_text(&harness, "Name").count == 0usize { os.exit(26i32) }
    // The tree with A expanded: five tree items (A, its two, B, C), A at level 1
    // expanded, its children at level 2, C selected; B's children are never
    // asked for. A tap on A's mark toggles A; a tap on A1's row picks it; Right
    // on the focused B toggles B; Left on the focused A1 (a leaf) does nothing.
    let (root_3, build_3_error) = build(&frame, &theme, ctx, &sources[0usize], columns[0usize..3usize], expanded[0usize..1usize], 2usize)
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(27i32) }
    let (tree_3, tree_3_error) = testing.semantics(&harness)
    if tree_3_error != ok { os.exit(28i32) }
    let (nodes, has_nodes) = find(tree_3, .Tree, "Nodes")
    if !has_nodes || count_role(tree_3, .TreeItem) != 5usize { os.exit(29i32) }
    var levels_ok = true
    var expanded_seen = 0usize
    var selected_seen = 0usize
    i = 0usize
    while i < tree_3.nodes.len {
        if tree_3.nodes[i].role == .TreeItem {
            if tree_3.nodes[i].state.expanded {
                expanded_seen += 1usize
                if tree_3.nodes[i].level != 1u8 { levels_ok = false }
            }
            if tree_3.nodes[i].level == 2u8 && tree_3.nodes[i].position.row_count != 2u32 { levels_ok = false }
            if tree_3.nodes[i].state.selected { selected_seen += 1usize }
        }
        i += 1usize
    }
    if !levels_ok || expanded_seen != 1usize || selected_seen != 1usize { os.exit(30i32) }
    let (mark_at, has_mark) = centre_of(&harness, &runtime, 101u64)
    if !has_mark || testing.tap(&harness, mark_at.x, mark_at.y) != ok || logs[0usize].toggles != 1usize || logs[0usize].toggled != 5001u64 { os.exit(31i32) }
    let (a1_at, has_a1) = centre_of(&harness, &runtime, 11u64)
    if !has_a1 || testing.tap(&harness, a1_at.x, a1_at.y) != ok || logs[0usize].picks != 2usize || logs[0usize].picked != 11u64 { os.exit(32i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || logs[0usize].toggles != 1usize { os.exit(33i32) }
    let (b_at, has_b) = centre_of(&harness, &runtime, 5002u64)
    if !has_b || testing.tap(&harness, b_at.x, b_at.y) != ok || testing.press_key(&harness, 39u32, zero) != ok || logs[0usize].toggles != 2usize || logs[0usize].toggled != 5002u64 { os.exit(34i32) }
    // The outline: the same five items.
    let (root_4, build_4_error) = build(&frame, &theme, ctx, &sources[0usize], columns[0usize..3usize], expanded[0usize..1usize], 3usize)
    if build_4_error != ok || testing.pump(&harness, root_4, now) != ok { os.exit(35i32) }
    let (tree_4, tree_4_error) = testing.semantics(&harness)
    if tree_4_error != ok || count_role(tree_4, .TreeItem) != 5usize { os.exit(36i32) }
    // The tree table: two column headers over the five items, each a row of two
    // cells; Size sorted; a tap on Name's header sorts by 0.
    let (root_5, build_5_error) = build(&frame, &theme, ctx, &sources[0usize], columns[0usize..3usize], expanded[0usize..1usize], 4usize)
    if build_5_error != ok || testing.pump(&harness, root_5, now) != ok { os.exit(37i32) }
    let (tree_5, tree_5_error) = testing.semantics(&harness)
    if tree_5_error != ok { os.exit(38i32) }
    // A treegrid (D1106): its header row and five item rows are Rows.
    let (sizes, has_sizes) = find(tree_5, .TreeGrid, "Sizes")
    if !has_sizes || count_role(tree_5, .ColumnHeader) != 2usize || count_role(tree_5, .Row) != 6usize || count_role(tree_5, .Cell) != 10usize { os.exit(39i32) }
    if testing.by_text(&harness, "Size").count == 0usize || testing.by_text(&harness, "k").count != 5usize { os.exit(40i32) }
    let (head_at, has_head) = centre_of(&harness, &runtime, 201u64)
    if !has_head || testing.tap(&harness, head_at.x, head_at.y) != ok || logs[0usize].sorts != 2usize || logs[0usize].sorted != 0usize { os.exit(41i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(42i32) }
    try io.print("ui tabular ok\n")
    ret ok
}
