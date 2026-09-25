// `e.ui.control`'s desktop selection and history (D854, widget plan P3-05): a
// font picker's family rows, style segments and size stepper each report their
// choice and the preview stands; a notification list shows the caller's notices
// with their actions and closes, Mark all read fires, and Up, Down, Home and End
// move focus between rows and Delete dismisses the focused row (v2, D971,
// D1174–D1175).

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

type Log = struct { families: usize, family: usize, styles: usize, style_index: usize, sizes: usize, size: i64, undos: usize, dismisses: usize, clears: usize }

fn on_family(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.families += 1usize
    log.family = value
    ret ok
}

fn on_style(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.styles += 1usize
    log.style_index = value
    ret ok
}

fn on_size(ctx: *void, value: i64) -> err {
    let log = mem.cast[*Log](ctx)
    log.sizes += 1usize
    log.size = value
    ret ok
}

fn on_undo(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.undos += 1usize
    ret ok
}

fn on_dismiss(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.dismisses += 1usize
    ret ok
}

fn on_clear(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.clears += 1usize
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

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, notices: []const control.Notice, clear: *const widget.Submit, family: usize) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    var families: [3]str = zero
    families[0usize] = "Serif"
    families[1usize] = "Sans"
    families[2usize] = "Mono"
    var styles: [2]str = zero
    styles[0usize] = "Regular"
    styles[1usize] = "Bold"
    let (picker, picker_error) = control.font_picker(a, 1u64, t, "Font", families[..], family, styles[..], 0usize, 12i64, "The quick brown fox", widget.Change[usize] { ctx: ctx, invoke: on_family }, widget.Change[usize] { ctx: ctx, invoke: on_style }, widget.Change[i64] { ctx: ctx, invoke: on_size }, 3u32, 200.0)
    if picker_error != ok { ret (zero, picker_error) }
    parts[0usize] = picker
    let (list, list_error) = control.notification_list(a, 100u64, t, "Notifications", notices, clear, 280.0, 220.0)
    if list_error != ok { ret (zero, list_error) }
    parts[1usize] = list
    var column = style.defaults()
    column.width = style.Length { Px: 320.0 }
    column.height = style.Length { Px: 600.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, column, parts[0usize..2usize]), ok)
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn centre_of(h: *testing.Harness, runtime: *const widget.Runtime, key: widget.Key) -> (geometry.Point, bool) {
    let found = testing.by_key(h, key)
    if found.count != 1usize { ret (zero, false) }
    let (area, has_area) = widget.bounds_of(runtime, found.element)
    if !has_area { ret (zero, false) }
    ret (geometry.Point { x: area.x + area.width * 0.5, y: area.y + area.height * 0.5 }, true)
}

fn focused_is(h: *testing.Harness, key: widget.Key) -> bool {
    let (focused, has_focus) = testing.focused(h)
    let found = testing.by_key(h, key)
    ret has_focus && found.count == 1usize && focused.slot == found.element.slot
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 200usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 512usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 600u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (notices, notices_error) = mem.alloc[control.Notice](a, 2usize)
    if notices_error != ok { os.exit(8i32) }
    notices[0usize] = control.Notice { text: "Deleted 3 files", action_label: "Undo", action: widget.Submit { ctx: ctx, invoke: on_undo }, dismiss: widget.Submit { ctx: ctx, invoke: on_dismiss } }
    notices[1usize] = control.Notice { text: "Backup done", action_label: "", action: zero, dismiss: widget.Submit { ctx: ctx, invoke: on_dismiss } }
    let (clears, clears_error) = mem.alloc[widget.Submit](a, 1usize)
    if clears_error != ok { os.exit(9i32) }
    clears[0usize] = widget.Submit { ctx: ctx, invoke: on_clear }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(10i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, ctx, notices[0usize..2usize], &clears[0usize], 1usize)
    if build_error != ok || testing.pump(&harness, root, now) != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    // The font picker: a group named Font valued Sans; the preview shows; the
    // third family's row picks 2; the Bold segment picks 1; the size's plus
    // reports 13.
    let (font, has_font) = find(tree, .Group, "Font")
    if !has_font || !same(font.value, "Sans") || testing.by_text(&harness, "The quick brown fox").count != 1usize { os.exit(13i32) }
    let (mono_at, has_mono) = centre_of(&harness, &runtime, 1u64 + 1u64 + 1u64 + 2u64)
    if !has_mono || testing.tap(&harness, mono_at.x, mono_at.y) != ok || logs[0usize].families != 1usize || logs[0usize].family != 2usize { os.exit(14i32) }
    let (bold_at, has_bold) = centre_of(&harness, &runtime, 1u64 + 64u64 + 1u64 + 1u64)
    if !has_bold || testing.tap(&harness, bold_at.x, bold_at.y) != ok || logs[0usize].styles != 1usize || logs[0usize].style_index != 1usize { os.exit(15i32) }
    let (plus_at, has_plus) = centre_of(&harness, &runtime, 1u64 + 80u64 + 2u64)
    if !has_plus || testing.tap(&harness, plus_at.x, plus_at.y) != ok || logs[0usize].sizes != 1usize || logs[0usize].size != 13i64 { os.exit(16i32) }
    // The notification list: two list items in a polite group; Undo fires the
    // first's action; the second's close fires its dismiss; Mark all read fires.
    let (notifications, has_notifications) = find(tree, .Group, "Notifications")
    if !has_notifications || notifications.live != .Polite || notifications.position.row_count != 2u32 { os.exit(17i32) }
    let (deleted, has_deleted) = find(tree, .ListItem, "Deleted 3 files")
    let (backup, has_backup) = find(tree, .ListItem, "Backup done")
    if !has_deleted || !has_backup { os.exit(18i32) }
    let (undo_at, has_undo) = centre_of(&harness, &runtime, 103u64)
    if !has_undo || testing.tap(&harness, undo_at.x, undo_at.y) != ok || logs[0usize].undos != 1usize { os.exit(19i32) }
    if testing.by_key(&harness, 106u64).count != 0usize { os.exit(20i32) }
    let (close_at, has_close) = centre_of(&harness, &runtime, 107u64)
    if !has_close || testing.tap(&harness, close_at.x, close_at.y) != ok || logs[0usize].dismisses != 1usize { os.exit(21i32) }
    let (clear_at, has_clear) = centre_of(&harness, &runtime, 101u64)
    if !has_clear || testing.tap(&harness, clear_at.x, clear_at.y) != ok || logs[0usize].clears != 1usize { os.exit(22i32) }
    let first_row = testing.by_key(&harness, 102u64)
    let (first_summary, has_first_summary) = widget.summary_at(&runtime, usize(first_row.element.slot))
    if first_row.count != 1usize || !has_first_summary || !first_summary.focusable || widget.focus(&runtime, first_row.element) != ok { os.exit(23i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focused_is(&harness, 105u64) { os.exit(24i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !focused_is(&harness, 102u64) { os.exit(25i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !focused_is(&harness, 105u64) { os.exit(26i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || !focused_is(&harness, 102u64) { os.exit(27i32) }
    if testing.press_key(&harness, 46u32, zero) != ok || logs[0usize].dismisses != 2usize { os.exit(28i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(29i32) }
    try io.print("ui desktop ok\n")
    ret ok
}
