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
use e.algo.hash as hash
use e.ui.collection
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

const W: usize = 420usize

type Log = struct { toggles: usize, adds: usize, removes: usize, removed: usize, resets: usize, reset: usize, reordered: bool }

fn on_toggle(ctx: *void, value: widget.Key) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    ret ok
}

fn on_edit(ctx: *void, value: collection.PairEdit) -> err {
    ret ok
}

// (D1259) The last pair edit and how many.
type Edits = struct { count: usize, index: usize, value: bool }

fn on_pair_edit(ctx: *void, value: collection.PairEdit) -> err {
    let edits = mem.cast[*Edits](ctx)
    edits.count += 1usize
    edits.index = value.index
    edits.value = value.value
    ret ok
}

// (D1544) A property grid's divider reports: how many, and the last width.
type DivideLog = struct { count: usize, width: f32 }

fn on_divide(ctx: *void, value: f32) -> err {
    let log = mem.cast[*DivideLog](ctx)
    log.count += 1usize
    log.width = value
    ret ok
}

// (D1260) A tap on the middle of the element keyed `key`.
fn tap_bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let (b, found) = bounds(h, runtime, key)
    if !found { ret false }
    ret testing.tap(h, b.x + b.width * 0.5, b.y + b.height * 0.5) == ok
}

// (D1260) The pair whose Show value was pressed.
fn on_reveal(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Edits](ctx)
    log.count += 1usize
    log.index = value
    ret ok
}

fn on_remove(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.removes += 1usize
    log.removed = value
    ret ok
}

// (D1327) A move: counted in `adds`, its destination kept in `removed`.
fn on_order(ctx: *void, value: collection.Reorder) -> err {
    let log = mem.cast[*Log](ctx)
    log.adds += 1usize
    log.removed = value.to
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
    let log = mem.cast[*Log](ctx)
    if log.reordered {
        if index == 0usize { ret collection.Property { key: 103u64, name: "Dark", group: "Look" } }
        if index == 1usize { ret collection.Property { key: 104u64, name: "Note", group: "Look" } }
        if index == 2usize { ret collection.Property { key: 101u64, name: "Name", group: "Person" } }
        ret collection.Property { key: 102u64, name: "Age", group: "Person" }
    }
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
    let person_key = collection.property_group_key("Person")
    let look_key = collection.property_group_key("Look")
    let person_heading = collection.property_group_heading_key(1u64, "Person")
    let look_heading = collection.property_group_heading_key(1u64, "Look")
    let (person, has_person) = bounds(&harness, &runtime, person_heading)
    let (look, has_look) = bounds(&harness, &runtime, look_heading)
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
    let (value_node, has_value_node) = find(tree, .TextField, "Value of API")
    let (headers, has_headers) = find(tree, .Table, "Headers")
    if !has_remove_node || !has_value_node || !has_headers || headers.position.column_count != 3u32 || headers.position.row_count != 2u32 { os.exit(25i32) }
    if testing.tap(&harness, first_remove.x + 20.0, first_remove.y + 20.0) != ok || logs[0usize].removes != 1usize || logs[0usize].removed != 0usize { os.exit(26i32) }
    let (more, has_more) = bounds(&harness, &runtime, 510u64)
    if !has_more || testing.tap(&harness, more.x + more.width * 0.5, more.y + more.height * 0.5) != ok || logs[0usize].adds != 1usize { os.exit(27i32) }
    // Look shut: its rows gone, "2 properties" at the heading's end.
    var shut: [1]widget.Key = zero
    shut[0usize] = look_key
    let (root_2, build_2_error) = build(&f, &theme, ctx, shut[..], filter, 0usize, pairs[0usize..2usize], &adds[0usize])
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(28i32) }
    if testing.by_key(&harness, 103u64).count != 0usize || testing.by_text(&harness, "2 properties").count != 1usize { os.exit(29i32) }
    // The filter "ag": Age alone, under Person; Look, with nothing matching, gone.
    let (root_3, build_3_error) = build(&f, &theme, ctx, none[0usize..0usize], filter, 2usize, pairs[0usize..2usize], &adds[0usize])
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(30i32) }
    if testing.by_key(&harness, 102u64).count != 1usize || testing.by_key(&harness, 101u64).count != 0usize || testing.by_key(&harness, person_heading).count != 1usize || testing.by_key(&harness, look_heading).count != 0usize { os.exit(31i32) }
    // Reordering whole groups preserves both heading identities and collapse keys.
    logs[0usize].reordered = true
    let (root_4, build_4_error) = build(&f, &theme, ctx, shut[..], filter, 0usize, pairs[0usize..2usize], &adds[0usize])
    if build_4_error != ok || testing.pump(&harness, root_4, now) != ok || testing.by_key(&harness, look_heading).count != 1usize || testing.by_key(&harness, person_heading).count != 1usize || testing.by_key(&harness, 103u64).count != 0usize || testing.by_key(&harness, 101u64).count != 1usize { os.exit(32i32) }
    // (D1259) The second value is secret, a masked field; the empty row after the
    // pairs takes typing as an edit at index 2 and has no Remove.
    var edits: Edits = zero
    var kv_secret: [2]bool = zero
    kv_secret[1usize] = true
    var kv = collection.key_value_options()
    kv.secret = kv_secret[..]
    kv.empty_row = true
    kv.spare = collection.Pair { name: buffers[160usize..192usize], name_len: 0usize, value: buffers[192usize..224usize], value_len: 0usize }
    f = mem.arena_from(storage)
    let (kv_editor, kv_error) = collection.key_value_editor_of(&f, 700u64, &theme, "Secrets", pairs[0usize..2usize], widget.Change[collection.PairEdit] { ctx: mem.cast[*void](&edits), invoke: on_pair_edit }, zero, &adds[0usize], 400.0, kv)
    let (kv_page, kv_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if kv_error != ok || kv_page_error != ok { os.exit(36i32) }
    kv_page[0usize] = kv_editor
    if testing.pump(&harness, widget.box(0u64, control.sized_style(420.0, 700.0), kv_page[0usize..1usize]), time.Instant { nanos: 4000000000i64 }) != ok { os.exit(37i32) }
    let (plain_value, has_plain_value) = widget.summary_at(&runtime, usize(testing.by_key(&harness, 702u64).element.slot))
    let (secret_value, has_secret_value) = widget.summary_at(&runtime, usize(testing.by_key(&harness, 705u64).element.slot))
    if !has_plain_value || !has_secret_value || plain_value.secret || !secret_value.secret { os.exit(38i32) }
    if testing.by_key(&harness, 707u64).count != 1usize || testing.by_key(&harness, 709u64).count != 0usize || testing.by_label(&harness, "Add a name").count == 0usize { os.exit(39i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 707u64).element) != ok || testing.type_text(&harness, "X") != ok || edits.count == 0usize || edits.index != 2usize || edits.value { os.exit(40i32) }
    // (D1260) With a reveal listener the secret value has its Show value toggle;
    // pressed, it reports the pair, and once shown the value is plain and the
    // toggle Checked.
    var reveal_log: Edits = zero
    var kv_shown: [2]bool = zero
    var reveal_step = 0usize
    while reveal_step < 2usize {
        kv_shown[1usize] = reveal_step == 1usize
        kv.shown = kv_shown[..]
        kv.reveal = widget.Change[usize] { ctx: mem.cast[*void](&reveal_log), invoke: on_reveal }
        f = mem.arena_from(storage)
        let (shown_editor, shown_error) = collection.key_value_editor_of(&f, 700u64, &theme, "Secrets", pairs[0usize..2usize], widget.Change[collection.PairEdit] { ctx: mem.cast[*void](&edits), invoke: on_pair_edit }, zero, &adds[0usize], 400.0, kv)
        let (shown_page, shown_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if shown_error != ok || shown_page_error != ok { os.exit(41i32) }
        shown_page[0usize] = shown_editor
        if testing.pump(&harness, widget.box(0u64, control.sized_style(420.0, 700.0), shown_page[0usize..1usize]), time.Instant { nanos: 4100000000i64 + i64(reveal_step) }) != ok { os.exit(42i32) }
        let (value_now, has_value_now) = widget.summary_at(&runtime, usize(testing.by_key(&harness, 705u64).element.slot))
        let (eye_tree, eye_tree_error) = testing.semantics(&harness)
        if eye_tree_error != ok || !has_value_now { os.exit(43i32) }
        let (eye, has_eye) = find(eye_tree, .Button, "Show value")
        if !has_eye || testing.by_key(&harness, 1049276u64).count != 0usize { os.exit(44i32) }
        if reveal_step == 0usize && (!value_now.secret || eye.state.checked || !tap_bounds(&harness, &runtime, 1049277u64) || reveal_log.count != 1usize || reveal_log.index != 1usize) { os.exit(45i32) }
        if reveal_step == 1usize && (value_now.secret || !eye.state.checked) { os.exit(46i32) }
        reveal_step += 1usize
    }
    // (D1536) Shown with its value field unfocused, the secret keeps for 20 s and
    // past 30 s (seen on the next build) its reveal fires with the pair, once.
    var limit_step = 0usize
    while limit_step < 5usize {
        f = mem.arena_from(storage)
        let (limit_editor, limit_error) = collection.key_value_editor_of(&f, 700u64, &theme, "Secrets", pairs[0usize..2usize], widget.Change[collection.PairEdit] { ctx: mem.cast[*void](&edits), invoke: on_pair_edit }, zero, &adds[0usize], 400.0, kv)
        let (limit_page, limit_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if limit_error != ok || limit_page_error != ok { os.exit(71i32) }
        limit_page[0usize] = limit_editor
        var limit_at = 4200000000i64
        if limit_step == 1usize { limit_at += 20000000000i64 }
        if limit_step >= 2usize { limit_at += 31000000000i64 + i64(limit_step) }
        if testing.pump(&harness, widget.box(0u64, control.sized_style(420.0, 700.0), limit_page[0usize..1usize]), time.Instant { nanos: limit_at }) != ok { os.exit(71i32) }
        if limit_step < 3usize && reveal_log.count != 1usize { os.exit(72i32) }
        if limit_step >= 3usize && (reveal_log.count != 2usize || reveal_log.index != 1usize) { os.exit(72i32) }
        limit_step += 1usize
    }
    // (D1541) Down to one pair, the removed row's place stands a row tall on the
    // first frame and has closed half a second later: the Add button (keyed
    // `key + 3 * 1 + 4`) rises by a row.
    var gone_step = 0usize
    var add_before: f32 = 0.0
    var add_after: f32 = 0.0
    while gone_step < 4usize {
        var kept = pairs[0usize..2usize]
        if gone_step > 0usize { kept = pairs[1usize..2usize] }
        var gone_at = 36000000000i64 + i64(gone_step)
        if gone_step >= 2usize { gone_at = 36500000000i64 + i64(gone_step) }
        f = mem.arena_from(storage)
        let (gone_editor, gone_error) = collection.key_value_editor_of(&f, 700u64, &theme, "Secrets", kept, widget.Change[collection.PairEdit] { ctx: mem.cast[*void](&edits), invoke: on_pair_edit }, zero, &adds[0usize], 400.0, kv)
        let (gone_page, gone_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if gone_error != ok || gone_page_error != ok { os.exit(73i32) }
        gone_page[0usize] = gone_editor
        if testing.pump(&harness, widget.box(0u64, control.sized_style(420.0, 700.0), gone_page[0usize..1usize]), time.Instant { nanos: gone_at }) != ok { os.exit(73i32) }
        let (add_box, has_add_box) = bounds(&harness, &runtime, 707u64)
        if gone_step == 1usize && has_add_box { add_before = add_box.y }
        if gone_step == 3usize && has_add_box { add_after = add_box.y }
        gone_step += 1usize
    }
    if !(add_before - add_after > 40.0) { os.exit(74i32) }
    if testing.by_label(&harness, "Add variable").count == 0usize { os.exit(47i32) }
    // (D1544) A property grid with Age selected: its row on
    // `secondary-container`, Name's not; dragging the first row's picked_seam 60 on
    // reports a name column 188 wide.
    var grid_log: Log = zero
    var divide_log = DivideLog { count: 0usize, width: 0.0 }
    var picked = collection.property_grid_options()
    picked.selected = 102u64
    picked.divide = widget.Change[f32] { ctx: mem.cast[*void](&divide_log), invoke: on_divide }
    f = mem.arena_from(storage)
    var no_collapsed: []const widget.Key = zero
    let (picked_grid, picked_error) = collection.property_grid_of(&f, 1200u64, &theme, "Properties", collection.PropertySource { ctx: mem.cast[*void](&grid_log), count: property_count, property: property_at, editor: property_editor }, no_collapsed, widget.Change[widget.Key] { ctx: mem.cast[*void](&grid_log), invoke: on_toggle }, 128.0, 320.0, picked)
    let (picked_page, picked_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if picked_error != ok || picked_page_error != ok { os.exit(75i32) }
    picked_page[0usize] = picked_grid
    if testing.pump(&harness, widget.box(0u64, control.sized_style(420.0, 700.0), picked_page[0usize..1usize]), time.Instant { nanos: 37000000000i64 }) != ok { os.exit(75i32) }
    let (picked_age, has_picked_age) = bounds(&harness, &runtime, 102u64)
    let (picked_name, has_picked_name) = bounds(&harness, &runtime, 101u64)
    let (picked_shot, picked_shot_error) = testing.snapshot(&harness, a)
    if !has_picked_age || !has_picked_name || picked_shot_error != ok { os.exit(76i32) }
    let chosen_ground = style.color(&tokens, .SecondaryContainer)
    if !is_color(picked_shot, at(picked_age.x + 4.0, picked_age.y + 2.0), chosen_ground) || is_color(picked_shot, at(picked_name.x + 4.0, picked_name.y + 2.0), chosen_ground) { os.exit(77i32) }
    let (picked_seam, has_picked_seam) = bounds(&harness, &runtime, 1800u64)
    if !has_picked_seam { os.exit(78i32) }
    let seam_from = geometry.Point { x: picked_seam.x + picked_seam.width * 0.5, y: picked_seam.y + picked_seam.height * 0.5 }
    if testing.drag(&harness, seam_from, geometry.Point { x: seam_from.x + 60.0, y: seam_from.y }, 4usize) != ok || divide_log.count == 0usize || !(divide_log.width > 180.0) || !(divide_log.width < 196.0) { os.exit(79i32) }
    // (D1314) Text mode: the pairs written one a line; parsed back, blank lines
    // and comments pass and a line with no `=` is named; the Text segment fires
    // the switch, and in text mode the area stands with its hint.
    let (as_text, as_text_error) = mem.alloc[u8](a, 128usize)
    if as_text_error != ok { os.exit(48i32) }
    let written = collection.pairs_text(as_text, pairs[0usize..2usize])
    if !same(as_text[0usize..written], "API=\nAPI=") { os.exit(49i32) }
    let (parsed_count, parsed_bad) = collection.pairs_parse("# env\nHOME = /root\n\nPATH=/bin\n", pairs[0usize..2usize])
    if parsed_count != 2usize || parsed_bad != 0usize || !same(pairs[0usize].name[0usize..pairs[0usize].name_len], "HOME") || !same(pairs[0usize].value[0usize..pairs[0usize].value_len], " /root") || !same(pairs[1usize].name[0usize..pairs[1usize].name_len], "PATH") { os.exit(50i32) }
    // (D1371) Parsed with notes, the comment and the blank line come back where
    // they stood.
    let (note_bytes, note_bytes_error) = mem.alloc[u8](a, 64usize)
    if note_bytes_error != ok { os.exit(67i32) }
    var notes: [2]collection.PairNote = zero
    notes[0usize].text = note_bytes[0usize..32usize]
    notes[1usize].text = note_bytes[32usize..64usize]
    let (noted_count, _) = collection.pairs_parse_noted("# env\nHOME = /root\n\nPATH=/bin\n", pairs[0usize..2usize], notes[..])
    let rewritten = collection.pairs_text_noted(as_text, pairs[0usize..2usize], notes[..])
    if noted_count != 2usize || !same(as_text[0usize..rewritten], "# env\nHOME= /root\n\nPATH=/bin") { os.exit(68i32) }
    // (D1460) Identifier names take the `code` face; others do not.
    if !collection.identifier_name("API_KEY") || !collection.identifier_name("_x9") || collection.identifier_name("9x") || collection.identifier_name("My name") || collection.identifier_name("") { os.exit(70i32) }
    // (D1459) Lines after the last pair come back after it.
    let (tail_bytes, tail_bytes_error) = mem.alloc[u8](a, 96usize)
    if tail_bytes_error != ok { os.exit(67i32) }
    var tail_notes: [3]collection.PairNote = zero
    tail_notes[0usize].text = tail_bytes[0usize..32usize]
    tail_notes[1usize].text = tail_bytes[32usize..64usize]
    tail_notes[2usize].text = tail_bytes[64usize..96usize]
    let (tail_count, _) = collection.pairs_parse_noted("A=1\n# end\n\n# really\n", pairs[0usize..2usize], tail_notes[..])
    let tail_written = collection.pairs_text_noted(as_text, pairs[0usize..tail_count], tail_notes[..])
    if tail_count != 1usize || !same(as_text[0usize..tail_written], "A=1\n# end\n\n# really") { os.exit(69i32) }
    let (_, broken_line) = collection.pairs_parse("A=1\noops", pairs[0usize..2usize])
    if broken_line != 2usize { os.exit(51i32) }
    var mode_log: Log = zero
    kv.toggle_mode = widget.Submit { ctx: mem.cast[*void](&mode_log), invoke: on_add }
    f = mem.arena_from(storage)
    let (moded_editor, moded_error) = collection.key_value_editor_of(&f, 700u64, &theme, "Secrets", pairs[0usize..2usize], widget.Change[collection.PairEdit] { ctx: mem.cast[*void](&edits), invoke: on_pair_edit }, zero, &adds[0usize], 400.0, kv)
    let (moded_page, moded_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if moded_error != ok || moded_page_error != ok { os.exit(52i32) }
    moded_page[0usize] = moded_editor
    if testing.pump(&harness, widget.box(0u64, control.sized_style(420.0, 700.0), moded_page[0usize..1usize]), time.Instant { nanos: 4200000000i64 }) != ok { os.exit(53i32) }
    let mode_key = 700u64 ^ hash.fnv1a64("kv-mode")
    if !tap_bounds(&harness, &runtime, mode_key + 1u64) || mode_log.adds != 0usize || !tap_bounds(&harness, &runtime, mode_key + 2u64) || mode_log.adds != 1usize { os.exit(54i32) }
    let (typed_bytes, typed_bytes_error) = mem.alloc[u8](a, 128usize)
    if typed_bytes_error != ok { os.exit(55i32) }
    kv.text_mode = true
    kv.text = typed_bytes
    kv.text_len = collection.pairs_text(typed_bytes, pairs[0usize..2usize])
    kv.text_error = "Line 2 has no ="
    f = mem.arena_from(storage)
    let (texted, texted_error) = collection.key_value_editor_of(&f, 700u64, &theme, "Secrets", pairs[0usize..2usize], widget.Change[collection.PairEdit] { ctx: mem.cast[*void](&edits), invoke: on_pair_edit }, zero, &adds[0usize], 400.0, kv)
    let (texted_page, texted_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if texted_error != ok || texted_page_error != ok { os.exit(56i32) }
    texted_page[0usize] = texted
    if testing.pump(&harness, widget.box(0u64, control.sized_style(420.0, 700.0), texted_page[0usize..1usize]), time.Instant { nanos: 4300000000i64 }) != ok { os.exit(57i32) }
    if testing.by_key(&harness, 700u64 ^ hash.fnv1a64("kv-text")).count != 1usize || testing.by_key(&harness, 702u64).count != 0usize || testing.by_text(&harness, "Line 2 has no =").count == 0usize { os.exit(58i32) }
    // (D1327) Ordered: each row has its handle; Alt+Down on the first row's name
    // moves it to 1, and a handle dragged a row and a half down lands it at 1.
    var order_log: Log = zero
    var ordered_kv = collection.key_value_options()
    ordered_kv.ordered = true
    ordered_kv.reorder = widget.Change[collection.Reorder] { ctx: mem.cast[*void](&order_log), invoke: on_order }
    f = mem.arena_from(storage)
    let (ordered_editor, ordered_error) = collection.key_value_editor_of(&f, 1700u64, &theme, "Headers", pairs[0usize..2usize], widget.Change[collection.PairEdit] { ctx: mem.cast[*void](&edits), invoke: on_pair_edit }, zero, &adds[0usize], 400.0, ordered_kv)
    let (ordered_page, ordered_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if ordered_error != ok || ordered_page_error != ok { os.exit(59i32) }
    ordered_page[0usize] = ordered_editor
    if testing.pump(&harness, widget.box(0u64, control.sized_style(420.0, 700.0), ordered_page[0usize..1usize]), time.Instant { nanos: 4400000000i64 }) != ok { os.exit(60i32) }
    if testing.by_key(&harness, 1700u64 + 3145728u64).count != 1usize || testing.by_key(&harness, 1700u64 + 3145729u64).count != 1usize { os.exit(61i32) }
    var held_alt: input.Modifiers = zero
    held_alt.alt = true
    if widget.focus(&runtime, testing.by_key(&harness, 1701u64).element) != ok || testing.press_key(&harness, 40u32, held_alt) != ok || order_log.adds != 1usize || order_log.removed != 1usize { os.exit(62i32) }
    let (first_grip, has_first_grip) = widget.bounds_of(&runtime, testing.by_key(&harness, 1700u64 + 3145728u64).element)
    let (first_pair, has_first_pair) = widget.bounds_of(&runtime, testing.by_key(&harness, 1700u64 + 2097152u64).element)
    if !has_first_grip || !has_first_pair { os.exit(63i32) }
    let grip_at = geometry.Point { x: first_grip.x + 12.0, y: first_grip.y + first_grip.height * 0.5 }
    if testing.drag(&harness, grip_at, geometry.Point { x: grip_at.x, y: first_pair.y + first_pair.height * 1.5 + 8.0 }, 4usize) != ok || order_log.adds != 2usize || order_log.removed != 1usize { os.exit(64i32) }
    // (D1353) A removal's notice names the pair and offers Undo.
    let (removed_notice, removed_notice_error) = collection.pair_removed_notice(&f, "API_URL", zero, zero)
    if removed_notice_error != ok || !control.same_text(removed_notice.text, "API_URL removed") || !control.same_text(removed_notice.action_label, "Undo") { os.exit(65i32) }
    let (nameless_notice, _) = collection.pair_removed_notice(&f, "", zero, zero)
    if !control.same_text(nameless_notice.text, "Variable removed") { os.exit(66i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(35i32) }
    try io.print("ui collections5 v2 ok\n")
    ret ok
}
