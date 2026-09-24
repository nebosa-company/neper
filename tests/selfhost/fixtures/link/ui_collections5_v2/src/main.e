// The v2 property grid and key-value editor (D983, widget plan P5-12,
// docs/ux/components/PropertyGrid, KeyValueEditor) under the light theme at
// pointer density: a grid under its kind and name with a 32 filter field, 32
// tall group headings with their twisty and, while shut, "2 properties", 40
// tall rows exactly as wide as the grid with the editors in one column, a
// modified property's Reset in its last 32 and its message; the filter
// narrowing the rows and leaving out a group with none; a key-value editor with
// its column labels once, 2:3 fields beside a 40 remove button named by its
// pair, a repeated name marked "Duplicate name", and Add.

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

const W: usize = 420usize

type Log = struct { toggles: usize, adds: usize, removes: usize, removed: usize, resets: usize, reset: usize }

fn on_toggle(ctx: *void, value: widget.Key) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    ret ok
}

fn on_edit(ctx: *void, value: collection.PairEdit) -> err {
    ret ok
}

fn on_remove(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.removes += 1usize
    log.removed = value
    ret ok
}

fn on_add(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.adds += 1usize
    ret ok
}

fn on_reset(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.resets += 1usize
    log.reset = value
    ret ok
}

// Age differs from its default and is wrong.
fn property_status(ctx: *void, index: usize) -> collection.PropertyStatus {
    if index == 1usize { ret collection.PropertyStatus { modified: true, message: "Must be a number" } }
    ret collection.PropertyStatus { modified: false, message: "" }
}

fn on_filter(ctx: *void, value: str) -> err {
    ret ok
}

fn property_count(ctx: *void) -> usize {
    ret 4usize
}

fn property_at(ctx: *void, index: usize) -> collection.Property {
    if index == 0usize { ret collection.Property { key: 101u64, name: "Name", group: "Person" } }
    if index == 1usize { ret collection.Property { key: 102u64, name: "Age", group: "Person" } }
    if index == 2usize { ret collection.Property { key: 103u64, name: "Dark", group: "Look" } }
    ret collection.Property { key: 104u64, name: "Note", group: "Look" }
}

fn property_editor(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    *out = widget.box(300u64 + u64(index), control.sized_style(20.0, 20.0), zero)
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

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, collapsed: []const widget.Key, filter: []u8, filter_len: usize, pairs: []const collection.Pair, add: *const widget.Submit) -> (widget.Node, err) {
    let source = collection.PropertySource { ctx: ctx, count: property_count, property: property_at, editor: property_editor }
    var options = collection.property_grid_options()
    options.kind = "Button"
    options.name = "save"
    options.filter = filter
    options.filter_len = filter_len
    options.filtering = widget.Change[str] { ctx: ctx, invoke: on_filter }
    options.has_filter = true
    options.status = property_status
    options.has_status = true
    options.reset = widget.Change[usize] { ctx: ctx, invoke: on_reset }
    let (grid, e1) = collection.property_grid_of(a, 1u64, t, "Properties", source, collapsed, widget.Change[widget.Key] { ctx: ctx, invoke: on_toggle }, 128.0, 320.0, options)
    let (editor, e2) = collection.key_value_editor(a, 500u64, t, "Headers", pairs, widget.Change[collection.PairEdit] { ctx: ctx, invoke: on_edit }, widget.Change[usize] { ctx: ctx, invoke: on_remove }, add, 400.0)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = grid
    parts[1usize] = editor
    var page = style.defaults()
    page.width = style.Length { Px: 420.0 }
    page.height = style.Length { Px: 700.0 }
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
    let (h, harness_error) = testing.harness(a, &runtime, 420u32, 700u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (adds, adds_error) = mem.alloc[widget.Submit](a, 1usize)
    if adds_error != ok { os.exit(8i32) }
    adds[0usize] = widget.Submit { ctx: ctx, invoke: on_add }
    let (buffers, buffers_error) = mem.alloc[u8](a, 256usize)
    if buffers_error != ok { os.exit(9i32) }
    buffers[0usize] = 65u8
    buffers[1usize] = 80u8
    buffers[2usize] = 73u8
    buffers[64usize] = 65u8
    buffers[65usize] = 80u8
    buffers[66usize] = 73u8
    buffers[128usize] = 97u8
    buffers[129usize] = 103u8
    let (pairs, pairs_error) = mem.alloc[collection.Pair](a, 2usize)
    if pairs_error != ok { os.exit(10i32) }
    pairs[0usize] = collection.Pair { name: buffers[0usize..32usize], name_len: 3usize, value: buffers[32usize..64usize], value_len: 0usize }
    pairs[1usize] = collection.Pair { name: buffers[64usize..96usize], name_len: 3usize, value: buffers[96usize..128usize], value_len: 0usize }
    let filter = buffers[128usize..160usize]
    let (storage, storage_error) = mem.alloc[u8](a, 4194304usize)
    if storage_error != ok { os.exit(11i32) }
    var f = mem.arena_from(storage)
    let now = time.Instant { nanos: 1000000000i64 }
    var none: [1]widget.Key = zero
    let (root, build_error) = build(&f, &theme, ctx, none[0usize..0usize], filter, 0usize, pairs[0usize..2usize], &adds[0usize])
    if build_error != ok || testing.pump(&harness, root, now) != ok { os.exit(12i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(13i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(14i32) }
    let muted = style.color(&tokens, .OnSurfaceVariant)
    // The header, the 32 filter field, the 32 group headings the grid's width
    // with the twisty drawn 8 in, the 40 rows as wide as the grid, the editors
    // in one column 128 in.
    if testing.by_text(&harness, "Button").count == 0usize || testing.by_text(&harness, "save").count == 0usize { os.exit(15i32) }
    let (filter_box, has_filter_box) = bounds(&harness, &runtime, 301u64)
    let (person, has_person) = bounds(&harness, &runtime, 2u64)
    let (look, has_look) = bounds(&harness, &runtime, 4u64)
    // The header's 8 above and below, the 32 field 4 above and below, 8 over the
    // first group.
    let (grid, has_grid) = bounds(&harness, &runtime, 1u64)
    if !has_grid || !has_filter_box || !has_person || !has_look || !near(person.y, grid.y + 16.0 + 40.0 + 8.0) || !near(person.height, 32.0) || !near(person.width, 320.0) { os.exit(16i32) }
    if !any_color(shot, person.x + 8.0, person.y + 4.0, 24.0, 24.0, muted) { os.exit(17i32) }
    let (name_row, has_name_row) = bounds(&harness, &runtime, 101u64)
    let (name_editor, has_name_editor) = bounds(&harness, &runtime, 300u64)
    let (dark_editor, has_dark_editor) = bounds(&harness, &runtime, 302u64)
    if !has_name_row || !has_name_editor || !has_dark_editor || !near(name_row.height, 40.0) || !near(name_row.width, 320.0) || !near(name_editor.x, name_row.x + 128.0) || !near(dark_editor.x, name_editor.x) { os.exit(18i32) }
    if !near(name_row.y, person.y + 32.0) || !near(look.y, name_row.y + 80.0 + 8.0) { os.exit(19i32) }
    let (person_node, has_person_node) = find(tree, .Button, "Person")
    let (properties, has_properties) = find(tree, .Table, "Properties")
    if !has_person_node || !person_node.state.expanded || !has_properties || properties.position.column_count != 2u32 { os.exit(20i32) }
    // Age, modified: its Reset in the last 32 of the row, reporting its index;
    // its message under the editor.
    let (age_row, has_age_row) = bounds(&harness, &runtime, 102u64)
    let (reset, has_reset) = bounds(&harness, &runtime, 402u64)
    let (reset_node, has_reset_node) = find(tree, .Button, "Reset Age")
    if !has_age_row || !has_reset || !has_reset_node || testing.by_key(&harness, 401u64).count != 0usize || !near(reset.width, 32.0) || !near(reset.x, age_row.x + 280.0) { os.exit(33i32) }
    if testing.by_text(&harness, "Must be a number").count == 0usize || testing.tap(&harness, reset.x + 16.0, reset.y + 16.0) != ok || logs[0usize].resets != 1usize || logs[0usize].reset != 1usize { os.exit(34i32) }
    if testing.tap(&harness, person.x + 100.0, person.y + 16.0) != ok || logs[0usize].toggles != 1usize { os.exit(21i32) }
    // The key-value editor: the labels once; 2:3 fields beside a 40 remove named
    // by its pair; the repeated name marked; Add.
    if testing.by_text(&harness, "Name").count < 2usize || testing.by_text(&harness, "Duplicate name").count == 0usize { os.exit(22i32) }
    let (first_name, has_first_name) = bounds(&harness, &runtime, 501u64)
    let (first_value, has_first_value) = bounds(&harness, &runtime, 502u64)
    let (first_remove, has_first_remove) = bounds(&harness, &runtime, 503u64)
    // Of 400, the remove takes 40 and the gaps 16; the names 2 of the 344 left
    // (137.6), the values 3 (206.4).
    let (headers_box, has_headers_box) = bounds(&harness, &runtime, 500u64)
    if !has_headers_box || !has_first_name || !has_first_value || !has_first_remove || !near(first_remove.width, 40.0) || !near(first_remove.x, headers_box.x + 360.0) { os.exit(23i32) }
    let step = first_value.x - first_name.x
    if step - 145.6 > 0.01 || 145.6 - step > 0.01 { os.exit(24i32) }
    let (remove_node, has_remove_node) = find(tree, .Button, "Remove API")
    let (value_node, has_value_node) = find(tree, .Group, "Value of API")
    let (headers, has_headers) = find(tree, .Table, "Headers")
    if !has_remove_node || !has_value_node || !has_headers || headers.position.column_count != 3u32 || headers.position.row_count != 2u32 { os.exit(25i32) }
    if testing.tap(&harness, first_remove.x + 20.0, first_remove.y + 20.0) != ok || logs[0usize].removes != 1usize || logs[0usize].removed != 0usize { os.exit(26i32) }
    let (more, has_more) = bounds(&harness, &runtime, 510u64)
    if !has_more || testing.tap(&harness, more.x + more.width * 0.5, more.y + more.height * 0.5) != ok || logs[0usize].adds != 1usize { os.exit(27i32) }
    // Look shut: its rows gone, "2 properties" at the heading's end.
    var shut: [1]widget.Key = zero
    shut[0usize] = 3u64
    let (root_2, build_2_error) = build(&f, &theme, ctx, shut[..], filter, 0usize, pairs[0usize..2usize], &adds[0usize])
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(28i32) }
    if testing.by_key(&harness, 103u64).count != 0usize || testing.by_text(&harness, "2 properties").count != 1usize { os.exit(29i32) }
    // The filter "ag": Age alone, under Person; Look, with nothing matching, gone.
    let (root_3, build_3_error) = build(&f, &theme, ctx, none[0usize..0usize], filter, 2usize, pairs[0usize..2usize], &adds[0usize])
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(30i32) }
    if testing.by_key(&harness, 102u64).count != 1usize || testing.by_key(&harness, 101u64).count != 0usize || testing.by_key(&harness, 2u64).count != 1usize || testing.by_key(&harness, 4u64).count != 0usize { os.exit(31i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(32i32) }
    try io.print("ui collections5 v2 ok\n")
    ret ok
}
