// `e.ui.collection` (D833, widget plan P2-05) under the light theme: a static list
// is a list of list items with separators and the selected keys marked; a virtual
// list over a thousand-item source builds only the rows in view, recycles them by
// key as the wheel moves the offset, and reports every move; a grid view wraps as
// many cells as fit across; a virtual grid builds only the visible rows of cells.

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

type Log = struct { scrolls: usize, offset: f32, grid_scrolls: usize, grid_offset: f32, builds: usize }
type Model = struct { theme: *const control.Theme, log: *Log, total: usize, base: u64 }

fn model_count(ctx: *void) -> usize {
    let m = mem.cast[*Model](ctx)
    ret m.total
}

fn model_key(ctx: *void, index: usize) -> widget.Key {
    let m = mem.cast[*Model](ctx)
    ret m.base + u64(index)
}

// Each item is a box `extent` wide named by its index in a single digit run.
fn model_build(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let m = mem.cast[*Model](ctx)
    m.log.builds += 1usize
    let (digits, digits_error) = mem.alloc[u8](a, 8usize)
    if digits_error != ok { ret digits_error }
    var n = index
    var count = 0usize
    var scratch: [8]u8 = zero
    if n == 0usize {
        scratch[0usize] = 48u8
        count = 1usize
    }
    while n > 0usize {
        scratch[count] = u8(48usize + n % 10usize)
        n = n / 10usize
        count += 1usize
    }
    var i = 0usize
    while i < count {
        digits[i] = scratch[count - 1usize - i]
        i += 1usize
    }
    var caption = control.text_options()
    caption.wrap = .None
    let (made, made_error) = control.text(a, 0u64, digits[0usize..count], m.theme, caption)
    if made_error != ok { ret made_error }
    *out = made
    ret ok
}

fn on_scroll(ctx: *void, value: f32) -> err {
    let log = mem.cast[*Log](ctx)
    log.scrolls += 1usize
    log.offset = value
    ret ok
}

fn on_grid_scroll(ctx: *void, value: f32) -> err {
    let log = mem.cast[*Log](ctx)
    log.grid_scrolls += 1usize
    log.grid_offset = value
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

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, source: collection.Source, wall_source: collection.Source, offset: f32, grid_offset: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, parts_error) }
    var items: [3]widget.Node = zero
    var keys: [3]widget.Key = zero
    let (one, one_error) = control.text(a, 0u64, "Alpha", t, control.text_options())
    if one_error != ok { ret (zero, one_error) }
    let (two, two_error) = control.text(a, 0u64, "Beta", t, control.text_options())
    if two_error != ok { ret (zero, two_error) }
    let (three, three_error) = control.text(a, 0u64, "Gamma", t, control.text_options())
    if three_error != ok { ret (zero, three_error) }
    items[0usize] = one
    items[1usize] = two
    items[2usize] = three
    keys[0usize] = 101u64
    keys[1usize] = 102u64
    keys[2usize] = 103u64
    var chosen: [1]widget.Key = zero
    chosen[0usize] = 102u64
    let (small, small_error) = collection.list(a, 1u64, t, "Greek", items[..], keys[..], chosen[..], true, 200.0)
    if small_error != ok { ret (zero, small_error) }
    parts[0usize] = small
    var picked: [1]widget.Key = zero
    picked[0usize] = 1003u64
    let (long, long_error) = collection.virtual_list(a, 10u64, t, "Numbers", source, picked[..], 20.0, offset, widget.Change[f32] { ctx: ctx, invoke: on_scroll }, true, 200.0, 100.0)
    if long_error != ok { ret (zero, long_error) }
    parts[1usize] = long
    var tile_keys: [3]widget.Key = zero
    tile_keys[0usize] = 201u64
    tile_keys[1usize] = 202u64
    tile_keys[2usize] = 203u64
    var tile_chosen: [1]widget.Key = zero
    tile_chosen[0usize] = 202u64
    let (tiles, tiles_error) = collection.grid_view(a, 20u64, t, "Tiles", items[..], tile_keys[..], tile_chosen[..], geometry.Size { width: 60.0, height: 40.0 }, 4.0, 200.0)
    if tiles_error != ok { ret (zero, tiles_error) }
    parts[2usize] = tiles
    var wall_picked: [1]widget.Key = zero
    wall_picked[0usize] = 5003u64
    let (wall, wall_error) = collection.virtual_grid(a, 30u64, t, "Wall", wall_source, wall_picked[..], geometry.Size { width: 60.0, height: 40.0 }, 4.0, grid_offset, widget.Change[f32] { ctx: ctx, invoke: on_grid_scroll }, 200.0, 100.0)
    if wall_error != ok { ret (zero, wall_error) }
    parts[3usize] = wall
    var column = style.defaults()
    column.width = style.Length { Px: 240.0 }
    column.height = style.Length { Px: 480.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, parts[0usize..4usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 200usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 14u16, max_commands: 512usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 240u32, 480u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (models, models_error) = mem.alloc[Model](a, 2usize)
    if models_error != ok { os.exit(8i32) }
    models[0usize] = Model { theme: &theme, log: &logs[0usize], total: 1000usize, base: 1000u64 }
    models[1usize] = Model { theme: &theme, log: &logs[0usize], total: 1000usize, base: 5000u64 }
    let source = collection.Source { ctx: mem.cast[*void](&models[0usize]), count: model_count, key: model_key, build: model_build }
    let wall_source = collection.Source { ctx: mem.cast[*void](&models[1usize]), count: model_count, key: model_key, build: model_build }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(9i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, ctx, source, wall_source, 0.0, 0.0)
    if build_error != ok { os.exit(10i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    // The static list: a list of three named Greek, Beta selected, two separators
    // (hidden in the tree).
    let (greek, has_greek) = find(tree, .List, "Greek")
    if !has_greek { os.exit(13i32) }
    var selected_items = 0usize
    var items = 0usize
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .ListItem && tree.nodes[i].position.row_count == 3u32 {
            items += 1usize
            if tree.nodes[i].state.selected && tree.nodes[i].position.row == 2u32 { selected_items += 1usize }
        }
        i += 1usize
    }
    if items != 3usize || selected_items != 1usize { os.exit(14i32) }
    if testing.by_key(&harness, 102u64).count != 1usize { os.exit(15i32) }
    // The virtual list: of a thousand rows twenty tall in a hundred, only the first
    // seven are built (five in view and one beyond each end), keyed by the source;
    // the selected key's row is marked; the group is named. The virtual grid below
    // built its four rows of three at the same time.
    let (numbers, has_numbers) = find(tree, .List, "Numbers")
    if !has_numbers || numbers.position.row_count != 1000u32 { os.exit(16i32) }
    let builds_first = logs[0usize].builds
    if builds_first != 19usize { os.exit(17i32) }
    if testing.by_key(&harness, 1000u64).count != 1usize || testing.by_key(&harness, 1500u64).count != 0usize { os.exit(18i32) }
    if testing.by_text(&harness, "0").count == 0usize || testing.by_text(&harness, "3").count == 0usize { os.exit(19i32) }
    var picked_seen = false
    i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .ListItem && tree.nodes[i].position.row == 4u32 && tree.nodes[i].position.row_count == 1000u32 && tree.nodes[i].state.selected { picked_seen = true }
        i += 1usize
    }
    if !picked_seen { os.exit(20i32) }
    // A wheel over the list moves the offset and reports it; rebuilt at that
    // offset, the rows in view are the ones there and the first is gone.
    let long_view = testing.by_key(&harness, 10u64).element
    let (long_bounds, has_long) = widget.bounds_of(&runtime, long_view)
    if !has_long || testing.wheel(&harness, long_bounds.x + 10.0, long_bounds.y + 10.0, -10i32) != ok { os.exit(21i32) }
    if logs[0usize].scrolls == 0usize || logs[0usize].offset <= 0.0 { os.exit(22i32) }
    let far: f32 = 5000.0
    let (root_2, build_2_error) = build(&frame, &theme, ctx, source, wall_source, far, 0.0)
    if build_2_error != ok { os.exit(23i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(24i32) }
    if testing.by_key(&harness, 1000u64).count != 0usize || testing.by_key(&harness, 1250u64).count != 1usize { os.exit(25i32) }
    // Eight rows there (the range straddles a row boundary) and the grid's twelve.
    let builds_second = logs[0usize].builds - builds_first
    if builds_second != 20usize { os.exit(26i32) }
    // The grid view: three cells of sixty across two hundred wrap as three columns
    // in one row; a grid in the tree with the counts; Beta's cell selected.
    let (tiles, has_tiles) = find(tree, .Grid, "Tiles")
    if !has_tiles || tiles.position.column_count != 3u32 || tiles.position.row_count != 1u32 { os.exit(27i32) }
    let (alpha_bounds, has_alpha) = widget.bounds_of(&runtime, testing.by_key(&harness, 201u64).element)
    let (gamma_bounds, has_gamma) = widget.bounds_of(&runtime, testing.by_key(&harness, 203u64).element)
    if !has_alpha || !has_gamma || gamma_bounds.y != alpha_bounds.y || gamma_bounds.x <= alpha_bounds.x { os.exit(28i32) }
    // The virtual grid: a thousand items in rows of three, forty-four tall in a
    // hundred: only a few rows built; a wheel moves it and reports.
    let (wall, has_wall) = find(tree, .Grid, "Wall")
    if !has_wall || wall.position.column_count != 3u32 || wall.position.row_count != 334u32 { os.exit(29i32) }
    let wall_view = testing.by_key(&harness, 30u64).element
    let (wall_bounds, has_wall_bounds) = widget.bounds_of(&runtime, wall_view)
    if !has_wall_bounds || testing.wheel(&harness, wall_bounds.x + 10.0, wall_bounds.y + 10.0, -5i32) != ok { os.exit(30i32) }
    if logs[0usize].grid_scrolls == 0usize || logs[0usize].grid_offset <= 0.0 { os.exit(31i32) }
    if testing.by_key(&harness, 31u64).count != 1usize || testing.by_key(&harness, 31u64 + 100u64).count != 0usize { os.exit(32i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(33i32) }
    try io.print("ui collection ok\n")
    ret ok
}
