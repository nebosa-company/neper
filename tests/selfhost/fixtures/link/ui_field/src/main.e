// `e.ui.control`'s text fields (D823, widget plan P1-10) under the light theme: a
// text field takes typed text into the caller's buffer and shows its placeholder
// only while empty; an invalid field says so; a password field keeps the real value
// while showing asterisks; a search field's Enter submits and its clear button
// fires the caller's action while it holds anything; a text area breaks lines on
// Enter and stands its rows tall.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { name_len: usize, search_len: usize, submits: usize, clears: usize, secret_len: usize, note_len: usize }

fn on_name(ctx: *void, value: str) -> err {
    let log = mem.cast[*Log](ctx)
    log.name_len = value.len
    ret ok
}

fn on_search(ctx: *void, value: str) -> err {
    let log = mem.cast[*Log](ctx)
    log.search_len = value.len
    ret ok
}

fn on_secret(ctx: *void, value: str) -> err {
    let log = mem.cast[*Log](ctx)
    log.secret_len = value.len
    ret ok
}

fn on_note(ctx: *void, value: str) -> err {
    let log = mem.cast[*Log](ctx)
    log.note_len = value.len
    ret ok
}

fn on_submit(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.submits += 1usize
    ret ok
}

fn on_clear(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.clears += 1usize
    log.search_len = 0usize
    ret ok
}

type Buffers = struct { name: [32]u8, search: [32]u8, secret: [32]u8, note: [64]u8 }

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn build(a: *mem.Arena, t: *const control.Theme, buffers: *Buffers, log: *const Log, ctx: *void, clear: *const widget.Submit, invalid: bool) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 4usize)
    if items_error != ok { ret (zero, items_error) }
    var name_options = control.field_options()
    name_options.placeholder = "Your name"
    name_options.invalid = invalid
    let (name, name_error) = control.text_field(a, 1u64, t, "Name", buffers.name[..], log.name_len, widget.Change[str] { ctx: ctx, invoke: on_name }, widget.Submit { ctx: ctx, invoke: on_submit }, name_options)
    if name_error != ok { ret (zero, name_error) }
    items[0usize] = name
    let (secret, secret_error) = control.password_field(a, 2u64, t, "Password", buffers.secret[..], log.secret_len, widget.Change[str] { ctx: ctx, invoke: on_secret }, zero, control.field_options())
    if secret_error != ok { ret (zero, secret_error) }
    items[1usize] = secret
    let (search, search_error) = control.search_field(a, 3u64, t, buffers.search[..], log.search_len, widget.Change[str] { ctx: ctx, invoke: on_search }, widget.Submit { ctx: ctx, invoke: on_submit }, clear, control.field_options())
    if search_error != ok { ret (zero, search_error) }
    items[2usize] = search
    var note_options = control.field_options()
    note_options.rows = 3u32
    let (note, note_error) = control.text_area(a, 5u64, t, "Note", buffers.note[..], log.note_len, widget.Change[str] { ctx: ctx, invoke: on_note }, note_options)
    if note_error != ok { ret (zero, note_error) }
    items[3usize] = note
    var column = style.defaults()
    column.width = style.Length { Px: 240.0 }
    column.height = style.Length { Px: 320.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, items[0usize..4usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 64usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 10u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 240u32, 320u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (buffers, buffers_error) = mem.alloc[Buffers](a, 1usize)
    if buffers_error != ok { os.exit(8i32) }
    var empty: Buffers = zero
    buffers[0usize] = empty
    let (clears, clears_error) = mem.alloc[widget.Submit](a, 1usize)
    if clears_error != ok { os.exit(9i32) }
    clears[0usize] = widget.Submit { ctx: ctx, invoke: on_clear }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 524288usize)
    if storage_error != ok { os.exit(10i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, &buffers[0usize], &logs[0usize], ctx, &clears[0usize], false)
    if build_error != ok { os.exit(11i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(12i32) }
    // Four text fields, labelled; the placeholders show while the fields are empty.
    if testing.by_role(&harness, .TextField).count != 4usize { os.exit(13i32) }
    if testing.by_label(&harness, "Name").count == 0usize || testing.by_label(&harness, "Password").count == 0usize || testing.by_label(&harness, "Note").count == 0usize { os.exit(14i32) }
    if testing.by_text(&harness, "Your name").count != 1usize || testing.by_text(&harness, "Search").count != 1usize { os.exit(15i32) }
    // Typed into the name field: the buffer takes it, the change reports it, and the
    // placeholder goes on the next frame.
    let name = testing.by_key(&harness, 1u64).element
    let (name_bounds, has_name) = widget.bounds_of(&runtime, name)
    if !has_name || testing.tap(&harness, name_bounds.x + 2.0, name_bounds.y + 2.0) != ok { os.exit(16i32) }
    if testing.type_text(&harness, "Ann") != ok || logs[0usize].name_len != 3usize { os.exit(17i32) }
    let (typed, has_typed) = widget.edit_value(&runtime, name)
    if !has_typed || !same(typed, "Ann") || !same(buffers[0usize].name[0usize..3usize], "Ann") { os.exit(18i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].submits != 1usize { os.exit(19i32) }
    let (root_2, build_2_error) = build(&frame, &theme, &buffers[0usize], &logs[0usize], ctx, &clears[0usize], true)
    if build_2_error != ok { os.exit(20i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(21i32) }
    if testing.by_text(&harness, "Your name").count != 0usize { os.exit(22i32) }
    // Invalid now: the field's group says so.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(23i32) }
    var invalid_seen = false
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].state.invalid { invalid_seen = true }
        i += 1usize
    }
    if !invalid_seen { os.exit(24i32) }
    // The password: typed, the real value is kept; the field is a text field too.
    let secret = testing.by_key(&harness, 2u64).element
    let (secret_bounds, has_secret) = widget.bounds_of(&runtime, secret)
    if !has_secret || testing.tap(&harness, secret_bounds.x + 2.0, secret_bounds.y + 2.0) != ok { os.exit(25i32) }
    if testing.type_text(&harness, "hunter2") != ok || logs[0usize].secret_len != 7usize { os.exit(26i32) }
    let (kept, has_kept) = widget.edit_value(&runtime, secret)
    if !has_kept || !same(kept, "hunter2") { os.exit(27i32) }
    // The search field: no clear button while empty; typed, the next frame shows
    // one, and a tap on it fires the caller's clear.
    if testing.by_key(&harness, 4u64).count != 0usize { os.exit(28i32) }
    let search = testing.by_key(&harness, 3u64).element
    let (search_bounds, has_search) = widget.bounds_of(&runtime, search)
    if !has_search || testing.tap(&harness, search_bounds.x + 2.0, search_bounds.y + 2.0) != ok { os.exit(29i32) }
    if testing.type_text(&harness, "cat") != ok || logs[0usize].search_len != 3usize { os.exit(30i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].submits != 2usize { os.exit(31i32) }
    let (root_3, build_3_error) = build(&frame, &theme, &buffers[0usize], &logs[0usize], ctx, &clears[0usize], true)
    if build_3_error != ok { os.exit(32i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(33i32) }
    let clear_button = testing.by_key(&harness, 4u64)
    let (clear_bounds, has_clear) = widget.bounds_of(&runtime, clear_button.element)
    if clear_button.count != 1usize || !has_clear { os.exit(34i32) }
    if testing.tap(&harness, clear_bounds.x + clear_bounds.width * 0.5, clear_bounds.y + clear_bounds.height * 0.5) != ok || logs[0usize].clears != 1usize || logs[0usize].search_len != 0usize { os.exit(35i32) }
    // The text area: three rows tall, Enter breaks a line.
    let note = testing.by_key(&harness, 5u64).element
    let (note_bounds, has_note) = widget.bounds_of(&runtime, note)
    if !has_note || testing.tap(&harness, note_bounds.x + 2.0, note_bounds.y + 2.0) != ok { os.exit(36i32) }
    if testing.type_text(&harness, "a") != ok || testing.press_key(&harness, 13u32, zero) != ok || testing.type_text(&harness, "b") != ok { os.exit(37i32) }
    let (lines, has_lines) = widget.edit_value(&runtime, note)
    if !has_lines || lines.len != 3usize || lines[1usize] != 10u8 || logs[0usize].note_len != 3usize { os.exit(38i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(39i32) }
    var note_frame_tall = false
    i = 0usize
    while i < tree_2.nodes.len {
        if tree_2.nodes[i].role == .Group && tree_2.nodes[i].bounds.height >= 3.0 * tokens.text[0usize].line_height { note_frame_tall = true }
        i += 1usize
    }
    if !note_frame_tall { os.exit(40i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(41i32) }
    try io.print("ui field ok\n")
    ret ok
}
