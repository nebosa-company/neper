// `e.ui.collection`'s property editing (D851, widget plan P3-02): a property grid
// lays a source's properties out as name and editor rows under group headings
// that collapse and expand through the caller; a key-value editor's fields report
// every keystroke with the pair and the side, its removes report the index, and
// its Add button fires.

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

type Log = struct { theme: *const control.Theme, editors: usize, toggles: usize, toggled: widget.Key, edits: usize, edit: collection.PairEdit, edit_len: usize, removes: usize, removed: usize, adds: usize, checks: usize }

fn on_toggle(ctx: *void, value: widget.Key) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    log.toggled = value
    ret ok
}

fn on_edit(ctx: *void, value: collection.PairEdit) -> err {
    let log = mem.cast[*Log](ctx)
    log.edits += 1usize
    log.edit = value
    log.edit_len = value.text.len
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

fn on_check(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.checks += 1usize
    ret ok
}

fn on_text(ctx: *void, value: str) -> err {
    ret ok
}

// Four properties in two groups: Name and Age under Person, Dark under Look, and
// an ungrouped Note.
fn property_count(ctx: *void) -> usize {
    ret 4usize
}

fn property_at(ctx: *void, index: usize) -> collection.Property {
    if index == 0usize { ret collection.Property { key: 101u64, name: "Name", group: "Person" } }
    if index == 1usize { ret collection.Property { key: 102u64, name: "Age", group: "Person" } }
    if index == 2usize { ret collection.Property { key: 103u64, name: "Dark", group: "Look" } }
    ret collection.Property { key: 104u64, name: "Note", group: "" }
}

type Editors = struct { log: *Log, check: widget.Submit, buffer: []u8 }

fn property_editor(ctx: *void, a: *mem.Arena, index: usize, out: *widget.Node) -> err {
    let e = mem.cast[*Editors](ctx)
    e.log.editors += 1usize
    if index == 2usize {
        let (box, box_error) = control.checkbox(a, 300u64, e.log.theme, "Dark", true, false, &e.check, true)
        if box_error != ok { ret box_error }
        *out = box
        ret ok
    }
    let (field, field_error) = control.text_field(a, 200u64 + u64(index), e.log.theme, "", e.buffer, 0usize, widget.Change[str] { ctx: ctx, invoke: on_text }, zero, control.field_options())
    if field_error != ok { ret field_error }
    *out = field
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

type Handlers = struct { add: widget.Submit }

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, source: collection.PropertySource, collapsed: []const widget.Key, pairs: []const collection.Pair, h: *const Handlers) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    let (grid, grid_error) = collection.property_grid(a, 1u64, t, "Settings", source, collapsed, widget.Change[widget.Key] { ctx: ctx, invoke: on_toggle }, 80.0, 280.0)
    if grid_error != ok { ret (zero, grid_error) }
    parts[0usize] = grid
    let (editor, editor_error) = collection.key_value_editor(a, 500u64, t, "Headers", pairs, widget.Change[collection.PairEdit] { ctx: ctx, invoke: on_edit }, widget.Change[usize] { ctx: ctx, invoke: on_remove }, &h.add, 280.0)
    if editor_error != ok { ret (zero, editor_error) }
    parts[1usize] = editor
    var column = style.defaults()
    column.width = style.Length { Px: 320.0 }
    column.height = style.Length { Px: 500.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, column, parts[0usize..2usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 256usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 512usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 500u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    log.theme = &theme
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (scratch, scratch_error) = mem.alloc[u8](a, 32usize)
    if scratch_error != ok { os.exit(8i32) }
    let (editors, editors_error) = mem.alloc[Editors](a, 1usize)
    if editors_error != ok { os.exit(9i32) }
    editors[0usize] = Editors { log: &logs[0usize], check: widget.Submit { ctx: ctx, invoke: on_check }, buffer: scratch }
    let source = collection.PropertySource { ctx: mem.cast[*void](&editors[0usize]), count: property_count, property: property_at, editor: property_editor }
    let (buffers, buffers_error) = mem.alloc[u8](a, 128usize)
    if buffers_error != ok { os.exit(10i32) }
    let (pairs, pairs_error) = mem.alloc[collection.Pair](a, 2usize)
    if pairs_error != ok { os.exit(11i32) }
    buffers[0usize] = 72u8
    pairs[0usize] = collection.Pair { name: buffers[0usize..32usize], name_len: 1usize, value: buffers[32usize..64usize], value_len: 0usize }
    pairs[1usize] = collection.Pair { name: buffers[64usize..96usize], name_len: 0usize, value: buffers[96usize..128usize], value_len: 0usize }
    let (handlers, handlers_error) = mem.alloc[Handlers](a, 1usize)
    if handlers_error != ok { os.exit(12i32) }
    handlers[0usize] = Handlers { add: widget.Submit { ctx: ctx, invoke: on_add } }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(13i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    var none: []const widget.Key = zero
    let (root, build_error) = build(&frame, &theme, ctx, source, none, pairs[0usize..2usize], &handlers[0usize])
    if build_error != ok || testing.pump(&harness, root, now) != ok { os.exit(14i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(15i32) }
    // The grid: a table of four rows and two columns named Settings, four row
    // headers, two group headings (Person, Look) as expanded buttons, every editor
    // built; the checkbox stands in the Look group and checks.
    let (settings, has_settings) = find(tree, .Table, "Settings")
    if !has_settings || settings.position.row_count != 4u32 || settings.position.column_count != 2u32 { os.exit(16i32) }
    if count_role(tree, .RowHeader) != 4usize || logs[0usize].editors != 4usize { os.exit(17i32) }
    let (person, has_person) = find(tree, .Button, "Person")
    let (look, has_look) = find(tree, .Button, "Look")
    if !has_person || !has_look || !person.state.expanded || !look.state.expanded { os.exit(18i32) }
    let (dark_at, has_dark) = centre_of(&harness, &runtime, 300u64)
    if !has_dark || testing.tap(&harness, dark_at.x, dark_at.y) != ok || logs[0usize].checks != 1usize { os.exit(19i32) }
    // A tap on Person's header reports the stable group-name key; collapsed,
    // its two rows are gone and the header says shut.
    let person_key = collection.property_group_key("Person")
    let (person_at, has_person_at) = centre_of(&harness, &runtime, collection.property_group_heading_key(1u64, "Person"))
    if !has_person_at || testing.tap(&harness, person_at.x, person_at.y) != ok || logs[0usize].toggles != 1usize || logs[0usize].toggled != person_key { os.exit(20i32) }
    let (collapsed, collapsed_error) = mem.alloc[widget.Key](a, 1usize)
    if collapsed_error != ok { os.exit(21i32) }
    collapsed[0usize] = person_key
    let (root_2, build_2_error) = build(&frame, &theme, ctx, source, collapsed[0usize..1usize], pairs[0usize..2usize], &handlers[0usize])
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(22i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(23i32) }
    let (person_2, has_person_2) = find(tree_2, .Button, "Person")
    if !has_person_2 || person_2.state.expanded || count_role(tree_2, .RowHeader) != 2usize || testing.by_text(&harness, "Age").count != 0usize { os.exit(24i32) }
    // The key-value editor: a table of two rows named Headers; typing in the
    // second pair's value reports pair 1, the value side and the text; its remove
    // reports 1; Add fires.
    let (headers, has_headers) = find(tree_2, .Table, "Headers")
    if !has_headers || headers.position.row_count != 2u32 { os.exit(25i32) }
    let (value_at, has_value) = centre_of(&harness, &runtime, 500u64 + 2u64 + 3u64)
    if !has_value || testing.tap(&harness, value_at.x, value_at.y) != ok || testing.type_text(&harness, "ab") != ok { os.exit(26i32) }
    if logs[0usize].edits != 2usize || logs[0usize].edit.index != 1usize || !logs[0usize].edit.value || logs[0usize].edit_len != 2usize { os.exit(27i32) }
    let (name_at, has_name) = centre_of(&harness, &runtime, 500u64 + 1u64)
    if !has_name || testing.tap(&harness, name_at.x, name_at.y) != ok || testing.type_text(&harness, "z") != ok || logs[0usize].edit.index != 0usize || logs[0usize].edit.value || logs[0usize].edit_len != 2usize { os.exit(28i32) }
    let (remove_at, has_remove) = centre_of(&harness, &runtime, 500u64 + 3u64 + 3u64)
    if !has_remove || testing.tap(&harness, remove_at.x, remove_at.y) != ok || logs[0usize].removes != 1usize || logs[0usize].removed != 1usize { os.exit(29i32) }
    let (add_at, has_add) = centre_of(&harness, &runtime, 500u64 + 6u64 + 4u64)
    if !has_add || testing.tap(&harness, add_at.x, add_at.y) != ok || logs[0usize].adds != 1usize { os.exit(30i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(31i32) }
    try io.print("ui property ok\n")
    ret ok
}
