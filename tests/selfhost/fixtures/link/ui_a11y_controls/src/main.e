// The accessibility of the controls the audit (D1598) found wanting, in one page
// that scrolls: a field names its editor, a field label names the field it
// controls, a spin box is a spin button, page dots are "Page N", a reorderable
// row is named by what it shows; the spin box's arrows, the dots, the column
// resize handles and the pane's sash take input 24 across; and Tab walks the
// whole page -- through a virtual data grid that scrolls under it -- with every
// focus kept across the rebuild and brought into the page's viewport.

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
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Model = struct { name: [16]u8, name_len: usize, nick: [16]u8, nick_len: usize, count: [16]u8, value: i64, pane: f32, grid: f32 }

fn on_name(ctx: *void, value: str) -> err {
    let m = mem.cast[*Model](ctx)
    m.name_len = value.len
    ret ok
}

fn on_nick(ctx: *void, value: str) -> err {
    let m = mem.cast[*Model](ctx)
    m.nick_len = value.len
    ret ok
}

fn on_value(ctx: *void, value: i64) -> err {
    let m = mem.cast[*Model](ctx)
    m.value = value
    ret ok
}

fn on_pane(ctx: *void, value: f32) -> err {
    let m = mem.cast[*Model](ctx)
    m.pane = value
    ret ok
}

fn on_grid(ctx: *void, value: f32) -> err {
    let m = mem.cast[*Model](ctx)
    m.grid = value
    ret ok
}

fn no_text(ctx: *void, value: str) -> err { ret ok }
fn no_page(ctx: *void, value: usize) -> err { ret ok }
fn no_move(ctx: *void, value: collection.Reorder) -> err { ret ok }
fn no_resize(ctx: *void, value: collection.ColumnResize) -> err { ret ok }
fn no_pick(ctx: *void, value: widget.Key) -> err { ret ok }
fn rows(ctx: *void) -> usize { ret 12usize }
fn row_key(ctx: *void, index: usize) -> widget.Key { ret 5000u64 + u64(index) }

fn cell(ctx: *void, a: *mem.Arena, row: usize, column: usize, out: *widget.Node) -> err {
    let t = mem.cast[*const control.Theme](ctx)
    let (node, node_error) = control.text(a, 0u64, "cell", t, control.text_options())
    if node_error != ok { ret node_error }
    *out = node
    ret ok
}

fn build(a: *mem.Arena, t: *const control.Theme, m: *Model) -> (widget.Node, err) {
    let ctx = mem.cast[*void](m)
    let (items, items_error) = mem.alloc[widget.Node](a, 9usize)
    if items_error != ok { ret (zero, items_error) }
    var n = 0usize
    let (name, name_error) = control.text_field(a, 10u64, t, "Name", m.name[..], m.name_len, widget.Change[str] { ctx: ctx, invoke: on_name }, zero, control.field_options())
    if name_error != ok { ret (zero, name_error) }
    items[n] = name
    n += 1usize
    let (nick_label, nick_label_error) = control.field_label(a, 20u64, t, "Nickname", 21u64, false)
    if nick_label_error != ok { ret (zero, nick_label_error) }
    items[n] = nick_label
    n += 1usize
    let (nick, nick_error) = control.text_field(a, 21u64, t, "", m.nick[..], m.nick_len, widget.Change[str] { ctx: ctx, invoke: on_nick }, zero, control.field_options())
    if nick_error != ok { ret (zero, nick_error) }
    items[n] = nick
    n += 1usize
    let (spin, spin_error) = control.spin_box(a, 30u64, t, "Count", m.count[..], m.value, 0i64, 9i64, 1i64, widget.Change[i64] { ctx: ctx, invoke: on_value }, widget.Change[str] { ctx: ctx, invoke: no_text })
    if spin_error != ok { ret (zero, spin_error) }
    items[n] = spin
    n += 1usize
    let (dots, dots_error) = collection.page_indicator(a, 40u64, t, 5usize, 0usize, widget.Change[usize] { ctx: ctx, invoke: no_page })
    if dots_error != ok { ret (zero, dots_error) }
    items[n] = dots
    n += 1usize
    let words: [3]str = [3]str{ "Alpha", "Beta", "Gamma" }
    let (shown, shown_error) = mem.alloc[widget.Node](a, 3usize)
    if shown_error != ok { ret (zero, shown_error) }
    let (keys, keys_error) = mem.alloc[widget.Key](a, 3usize)
    if keys_error != ok { ret (zero, keys_error) }
    var i = 0usize
    while i < 3usize {
        let (word, word_error) = control.text(a, 0u64, words[i], t, control.text_options())
        if word_error != ok { ret (zero, word_error) }
        shown[i] = word
        keys[i] = 60u64 + u64(i)
        i += 1usize
    }
    let (order, order_error) = collection.reorderable_list(a, 50u64, t, "Order", shown[0usize..3usize], keys[0usize..3usize], 28.0, widget.Change[collection.Reorder] { ctx: ctx, invoke: no_move }, 200.0)
    if order_error != ok { ret (zero, order_error) }
    items[n] = order
    n += 1usize
    let (inside, inside_error) = control.text(a, 0u64, "Pane", t, control.text_options())
    if inside_error != ok { ret (zero, inside_error) }
    let (pane, pane_error) = control.resizable_pane(a, 70u64, t, "Pane", .Horizontal, m.pane, 80.0, 240.0, widget.Change[f32] { ctx: ctx, invoke: on_pane }, inside)
    if pane_error != ok { ret (zero, pane_error) }
    var pane_box = style.defaults()
    pane_box.height = style.Length { Px: 40.0 }
    items[n] = widget.box(0u64, pane_box, control_slice(a, pane))
    n += 1usize
    let (columns, columns_error) = mem.alloc[collection.Column](a, 2usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = collection.Column { title: "A", width: 100.0 }
    columns[1usize] = collection.Column { title: "B", width: 100.0 }
    let (header, header_error) = collection.header_row(a, 80u64, t, columns[0usize..2usize], 0usize, false, widget.Change[usize] { ctx: ctx, invoke: no_page }, widget.Change[collection.Reorder] { ctx: ctx, invoke: no_move }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: no_resize })
    if header_error != ok { ret (zero, header_error) }
    items[n] = header
    n += 1usize
    var none: []widget.Key = zero
    let source = collection.TableSource { ctx: mem.cast[*void](t), count: rows, key: row_key, cell: cell }
    let (grid, grid_error) = collection.data_grid(a, 90u64, t, "Grid", columns[0usize..2usize], source, none, 0usize, false, widget.Change[usize] { ctx: ctx, invoke: no_page }, widget.Change[collection.Reorder] { ctx: ctx, invoke: no_move }, widget.Change[collection.ColumnResize] { ctx: ctx, invoke: no_resize }, widget.Change[widget.Key] { ctx: ctx, invoke: no_pick }, 28.0, m.grid, widget.Change[f32] { ctx: ctx, invoke: on_grid }, 160.0)
    if grid_error != ok { ret (zero, grid_error) }
    items[n] = grid
    n += 1usize
    let column = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, style.defaults(), items[0usize..n])
    var page_style = style.defaults()
    page_style.width = style.Length { Px: 400.0 }
    page_style.height = style.Length { Px: 300.0 }
    let (page, page_error) = widget.scroll_view(a, 900u64, .Vertical, page_style, control_slice(a, column))
    ret (page, page_error)
}

fn control_slice(a: *mem.Arena, node: widget.Node) -> []widget.Node {
    let (one, one_error) = mem.alloc[widget.Node](a, 1usize)
    if one_error != ok { ret zero }
    one[0usize] = node
    ret one[0usize..1usize]
}

type World = struct { h: *testing.Harness, runtime: *widget.Runtime, t: *const control.Theme, m: *Model, storage: []u8, tree_storage: []u8, clock: i64 }

fn rebuild(w: *World) -> err {
    w.clock += 16000000i64
    let now = time.Instant { nanos: w.clock }
    try testing.begin(w.h, now)
    var frame = mem.arena_from(w.storage)
    let (root, build_error) = build(&frame, w.t, w.m)
    if build_error != ok { ret build_error }
    ret testing.pump(w.h, root, now)
}

fn same(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// The first node of `role` named `label`.
fn node_of(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn wide(n: accessibility.Node) -> bool {
    ret n.bounds.width >= 24.0 && n.bounds.height >= 24.0
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 2048usize, max_states: 128usize, state_bytes: 8192usize, state_classes: 8u16, max_depth: 48u16, max_commands: 8192usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 400u32, 300u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (models, models_error) = mem.alloc[Model](a, 1usize)
    if models_error != ok { os.exit(7i32) }
    var model: Model = zero
    model.pane = 120.0
    models[0usize] = model
    let (storage, storage_error) = mem.alloc[u8](a, 8388608usize)
    if storage_error != ok { os.exit(8i32) }
    let (tree_storage, tree_storage_error) = mem.alloc[u8](a, 8388608usize)
    if tree_storage_error != ok { os.exit(9i32) }
    var w = World { h: &harness, runtime: &runtime, t: &theme, m: &models[0usize], storage: storage, tree_storage: tree_storage, clock: 1000000000i64 }
    if rebuild(&w) != ok || rebuild(&w) != ok { os.exit(10i32) }
    var tree_arena = mem.arena_from(tree_storage)
    let (tree, tree_error) = accessibility.build(&tree_arena, &runtime)
    if tree_error != ok { os.exit(11i32) }
    // Names: the editor its field's, a field its label's, rows their words.
    let (_, has_name) = node_of(tree, .TextField, "Name")
    if !has_name { os.exit(12i32) }
    let (nick, has_nick) = node_of(tree, .TextField, "Nickname")
    if !has_nick || nick.relations.labelled_by.generation == 0u32 { os.exit(13i32) }
    let (_, has_spin) = node_of(tree, .SpinButton, "Count")
    if !has_spin { os.exit(14i32) }
    let (page_three, has_page_three) = node_of(tree, .Tab, "Page 3")
    if !has_page_three || !wide(page_three) { os.exit(15i32) }
    let (_, has_beta) = node_of(tree, .ListItem, "Beta")
    if !has_beta { os.exit(16i32) }
    // Targets: 24 across where the pointer takes them.
    let (up, has_up) = node_of(tree, .Button, "Increase")
    let (down, has_down) = node_of(tree, .Button, "Decrease")
    if !has_up || !has_down || !wide(up) || !wide(down) { os.exit(17i32) }
    let (sash, has_sash) = node_of(tree, .Separator, "Resize Pane")
    if !has_sash || !(sash.bounds.width >= 24.0) { os.exit(18i32) }
    let (handle, has_handle) = node_of(tree, .Separator, "Resize A")
    if !has_handle || !(handle.bounds.width >= 24.0) { os.exit(19i32) }
    // Tab through it all: the focus survives every rebuild and stands in view.
    let viewport = testing.by_key(&harness, 900u64).element
    let (view, has_view) = widget.bounds_of(&runtime, viewport)
    if !has_view { os.exit(20i32) }
    var stops = 0usize
    var grid_moved = false
    while stops < 40usize {
        if testing.tab(&harness, false) != ok || rebuild(&w) != ok || rebuild(&w) != ok { os.exit(21i32) }
        let (focus, has_focus) = testing.focused(&harness)
        if !has_focus { os.exit(22i32) }
        let (b, has_b) = widget.bounds_of(&runtime, focus)
        if !has_b || b.y < view.y - 0.5 || b.y + b.height > view.y + view.height + 0.5 { os.exit(23i32) }
        if models[0usize].grid > 0.0 { grid_moved = true }
        stops += 1usize
    }
    // The walk went down the grid far enough to scroll it.
    if !grid_moved { os.exit(24i32) }
    try io.print("ui a11y controls ok\n")
    ret ok
}
