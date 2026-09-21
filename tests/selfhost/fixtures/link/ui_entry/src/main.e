// `e.ui.control`'s advanced text and choice input (D831, widget plan P2-03) under
// the light theme: a formatted field is invalid while its adapter refuses the text
// and Enter writes the formatted text back; an autocomplete's suggestions are
// moved through with the arrow keys, picked with Enter or a tap and dismissed with
// Escape; a combo box adds a chevron that toggles; a token field's chips remove
// and its Enter adds; a picker's sheet is a modal dialog of rows; a multi-select
// list keeps any number of rows selected.

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

type Log = struct { changed_len: usize, changes: usize, active: usize, activations: usize, picks: usize, last_pick: usize, dismisses: usize, toggles: usize, removes: usize, last_remove: usize, adds: usize, fruit_picks: usize, fruit_toggles: usize, row_toggles: usize, last_row: usize }
type Numbered = struct { log: *Log, index: usize }

fn digits_only(ctx: *void, text: str) -> bool {
    var i = 0usize
    while i < text.len {
        if text[i] < 48u8 || text[i] > 57u8 { ret false }
        i += 1usize
    }
    ret true
}

// Four digits, zero-padded on the left.
fn pad_four(ctx: *void, out: []u8, text: str) -> usize {
    if out.len < 4usize { ret 0usize }
    var i = 0usize
    while i < 4usize {
        out[i] = 48u8
        i += 1usize
    }
    var from = 0usize
    if text.len > 4usize { from = text.len - 4usize }
    var at = 4usize - (text.len - from)
    while from < text.len {
        out[at] = text[from]
        at += 1usize
        from += 1usize
    }
    ret 4usize
}

fn on_change(ctx: *void, value: str) -> err {
    let log = mem.cast[*Log](ctx)
    log.changes += 1usize
    log.changed_len = value.len
    ret ok
}

fn on_typed(ctx: *void, value: str) -> err {
    ret ok
}

fn on_activate(ctx: *void, value: usize) -> err {
    let log = mem.cast[*Log](ctx)
    log.activations += 1usize
    log.active = value
    ret ok
}

fn on_pick(ctx: *void) -> err {
    let n = mem.cast[*Numbered](ctx)
    n.log.picks += 1usize
    n.log.last_pick = n.index
    ret ok
}

fn on_dismiss(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.dismisses += 1usize
    ret ok
}

fn on_toggle(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    ret ok
}

fn on_remove(ctx: *void) -> err {
    let n = mem.cast[*Numbered](ctx)
    n.log.removes += 1usize
    n.log.last_remove = n.index
    ret ok
}

fn on_add(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.adds += 1usize
    ret ok
}

fn on_fruit(ctx: *void) -> err {
    let n = mem.cast[*Numbered](ctx)
    n.log.fruit_picks += 1usize
    n.log.last_pick = n.index
    ret ok
}

fn on_fruit_toggle(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.fruit_toggles += 1usize
    ret ok
}

fn on_row(ctx: *void) -> err {
    let n = mem.cast[*Numbered](ctx)
    n.log.row_toggles += 1usize
    n.log.last_row = n.index
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

type Buffers = struct { code: [16]u8, fruit: [16]u8, combo: [16]u8, token: [16]u8 }
type Actions = struct { picks: []widget.Submit, removes: []widget.Submit, fruit_picks: []widget.Submit, rows: []widget.Submit, dismiss: widget.Submit, toggle: widget.Submit, fruit_toggle: widget.Submit }

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, b: *Buffers, code_len: usize, acts: *const Actions, open: bool, active: usize, combo_open: bool, fruit_open: bool) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 6usize)
    if parts_error != ok { ret (zero, parts_error) }
    let adapter = control.Format { ctx: ctx, accept: digits_only, format: pad_four }
    let (code, code_error) = control.formatted_field(a, 1u64, t, "Code", b.code[..], code_len, adapter, widget.Change[str] { ctx: ctx, invoke: on_typed }, widget.Change[str] { ctx: ctx, invoke: on_change }, control.field_options())
    if code_error != ok { ret (zero, code_error) }
    parts[0usize] = code
    var fruits: [2]str = zero
    fruits[0usize] = "apple"
    fruits[1usize] = "apricot"
    let (complete, complete_error) = control.autocomplete(a, 10u64, t, "Fruit", b.fruit[..], 0usize, widget.Change[str] { ctx: ctx, invoke: on_typed }, fruits[..], active, open, acts.picks, widget.Change[usize] { ctx: ctx, invoke: on_activate }, &acts.dismiss, control.field_options())
    if complete_error != ok { ret (zero, complete_error) }
    parts[1usize] = complete
    let (combo, combo_error) = control.combo_box(a, 20u64, t, "Colour", b.combo[..], 0usize, widget.Change[str] { ctx: ctx, invoke: on_typed }, fruits[..], active, combo_open, acts.picks, widget.Change[usize] { ctx: ctx, invoke: on_activate }, &acts.toggle, control.field_options())
    if combo_error != ok { ret (zero, combo_error) }
    parts[2usize] = combo
    var tokens: [2]str = zero
    tokens[0usize] = "a@x"
    tokens[1usize] = "b@y"
    var none: []const str = zero
    var no_picks: []const widget.Submit = zero
    let (field, field_error) = control.token_field(a, 30u64, t, "To", tokens[..], acts.removes, b.token[..], 0usize, widget.Change[str] { ctx: ctx, invoke: on_typed }, widget.Submit { ctx: ctx, invoke: on_add }, none, 0usize, false, no_picks, widget.Change[usize] { ctx: ctx, invoke: on_activate }, &acts.dismiss, 300.0)
    if field_error != ok { ret (zero, field_error) }
    parts[3usize] = field
    var kinds: [3]str = zero
    kinds[0usize] = "Pear"
    kinds[1usize] = "Plum"
    kinds[2usize] = "Fig"
    let (sheet, sheet_error) = control.picker(a, 40u64, t, "Kind", kinds[..], 0usize, fruit_open, &acts.fruit_toggle, acts.fruit_picks, .Sheet)
    if sheet_error != ok { ret (zero, sheet_error) }
    parts[4usize] = sheet
    var chosen: [3]bool = zero
    chosen[0usize] = true
    chosen[2usize] = true
    let (rows, rows_error) = control.multi_select_list(a, 50u64, t, "Kinds", kinds[..], chosen[..], acts.rows, 3u32, 160.0)
    if rows_error != ok { ret (zero, rows_error) }
    parts[5usize] = rows
    var column = style.defaults()
    column.width = style.Length { Px: 320.0 }
    column.height = style.Length { Px: 480.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, column, parts[0usize..6usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 160usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 18u16, max_commands: 400usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 480u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (numbers, numbers_error) = mem.alloc[Numbered](a, 8usize)
    if numbers_error != ok { os.exit(8i32) }
    var i = 0usize
    while i < 8usize {
        numbers[i] = Numbered { log: &logs[0usize], index: i % 3usize }
        i += 1usize
    }
    let (subs, subs_error) = mem.alloc[widget.Submit](a, 8usize)
    if subs_error != ok { os.exit(9i32) }
    subs[0usize] = widget.Submit { ctx: mem.cast[*void](&numbers[0usize]), invoke: on_pick }
    subs[1usize] = widget.Submit { ctx: mem.cast[*void](&numbers[1usize]), invoke: on_pick }
    subs[2usize] = widget.Submit { ctx: mem.cast[*void](&numbers[0usize]), invoke: on_remove }
    subs[3usize] = widget.Submit { ctx: mem.cast[*void](&numbers[1usize]), invoke: on_remove }
    subs[4usize] = widget.Submit { ctx: mem.cast[*void](&numbers[3usize]), invoke: on_fruit }
    subs[5usize] = widget.Submit { ctx: mem.cast[*void](&numbers[4usize]), invoke: on_fruit }
    subs[6usize] = widget.Submit { ctx: mem.cast[*void](&numbers[5usize]), invoke: on_fruit }
    subs[7usize] = widget.Submit { ctx: mem.cast[*void](&numbers[6usize]), invoke: on_row }
    let (rows, rows_error) = mem.alloc[widget.Submit](a, 3usize)
    if rows_error != ok { os.exit(10i32) }
    rows[0usize] = widget.Submit { ctx: mem.cast[*void](&numbers[3usize]), invoke: on_row }
    rows[1usize] = widget.Submit { ctx: mem.cast[*void](&numbers[4usize]), invoke: on_row }
    rows[2usize] = widget.Submit { ctx: mem.cast[*void](&numbers[5usize]), invoke: on_row }
    let (acts, acts_error) = mem.alloc[Actions](a, 1usize)
    if acts_error != ok { os.exit(11i32) }
    acts[0usize] = Actions { picks: subs[0usize..2usize], removes: subs[2usize..4usize], fruit_picks: subs[4usize..7usize], rows: rows[0usize..3usize], dismiss: widget.Submit { ctx: ctx, invoke: on_dismiss }, toggle: widget.Submit { ctx: ctx, invoke: on_toggle }, fruit_toggle: widget.Submit { ctx: ctx, invoke: on_fruit_toggle } }
    let (buffers, buffers_error) = mem.alloc[Buffers](a, 1usize)
    if buffers_error != ok { os.exit(12i32) }
    var empty: Buffers = zero
    buffers[0usize] = empty
    buffers[0usize].code[0usize] = 52u8
    buffers[0usize].code[1usize] = 120u8
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(13i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, ctx, &buffers[0usize], 2usize, &acts[0usize], true, 0usize, false, false)
    if build_error != ok { os.exit(14i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(15i32) }
    // The formatted field over "4x": invalid. Over "42" it is not, and Enter in it
    // writes "0042" back and reports the four.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(16i32) }
    let (code_group, has_code) = find(tree, .Group, "Code")
    if !has_code || !code_group.state.invalid { os.exit(17i32) }
    buffers[0usize].code[0usize] = 52u8
    buffers[0usize].code[1usize] = 50u8
    let (root_2, build_2_error) = build(&frame, &theme, ctx, &buffers[0usize], 2usize, &acts[0usize], true, 0usize, false, false)
    if build_2_error != ok { os.exit(18i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(19i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(20i32) }
    let (code_group_2, has_code_2) = find(tree_2, .Group, "Code")
    if !has_code_2 || code_group_2.state.invalid { os.exit(21i32) }
    let (code_at, has_code_at) = centre_of(&harness, &runtime, 1u64)
    if !has_code_at || testing.tap(&harness, code_at.x, code_at.y) != ok || testing.press_key(&harness, 13u32, zero) != ok { os.exit(22i32) }
    if logs[0usize].changes != 1usize || logs[0usize].changed_len != 4usize || !same(buffers[0usize].code[0usize..4usize], "0042") { os.exit(23i32) }
    // The autocomplete, open with two suggestions and the first active: the group
    // is expanded, the list holds two items; Down from the field activates the
    // second; Enter picks the (still) first; a tap on the second picks it; Escape
    // dismisses.
    let (fruit_group, has_fruit) = find(tree_2, .Group, "Fruit")
    if !has_fruit || !fruit_group.state.expanded || testing.by_role(&harness, .ListItem).count < 2usize { os.exit(24i32) }
    let (fruit_at, has_fruit_at) = centre_of(&harness, &runtime, 10u64)
    if !has_fruit_at || testing.tap(&harness, fruit_at.x, fruit_at.y) != ok { os.exit(25i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || logs[0usize].activations != 1usize || logs[0usize].active != 1usize { os.exit(26i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].picks != 1usize || logs[0usize].last_pick != 0usize { os.exit(27i32) }
    let (second_at, has_second) = centre_of(&harness, &runtime, 13u64)
    if !has_second || testing.tap(&harness, second_at.x, second_at.y) != ok || logs[0usize].picks != 2usize || logs[0usize].last_pick != 1usize { os.exit(28i32) }
    if testing.tap(&harness, fruit_at.x, fruit_at.y) != ok || testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].dismisses != 1usize { os.exit(29i32) }
    // The combo box (once the autocomplete's list, which lay over it, is gone):
    // closed, a chevron toggles; open, its list lies under the field and Enter
    // picks the active.
    let (root_closed, closed_error) = build(&frame, &theme, ctx, &buffers[0usize], 4usize, &acts[0usize], false, 1usize, false, false)
    if closed_error != ok { os.exit(30i32) }
    if testing.pump(&harness, root_closed, now) != ok || testing.by_key(&harness, 22u64).count != 0usize { os.exit(30i32) }
    let (chevron_at, has_chevron) = centre_of(&harness, &runtime, 21u64)
    if !has_chevron || testing.tap(&harness, chevron_at.x, chevron_at.y) != ok || logs[0usize].toggles != 1usize { os.exit(31i32) }
    let (root_3, build_3_error) = build(&frame, &theme, ctx, &buffers[0usize], 4usize, &acts[0usize], false, 1usize, true, false)
    if build_3_error != ok { os.exit(32i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(33i32) }
    if testing.by_key(&harness, 22u64).count != 1usize || testing.by_key(&harness, 24u64).count != 1usize { os.exit(34i32) }
    let (colour_at, has_colour) = centre_of(&harness, &runtime, 20u64)
    if !has_colour || testing.tap(&harness, colour_at.x, colour_at.y) != ok || testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].picks != 3usize || logs[0usize].last_pick != 1usize { os.exit(35i32) }
    // The token field (the combo's list closed again): two chips; the second's
    // remove fires; typed then Enter adds.
    let (root_closed_2, closed_2_error) = build(&frame, &theme, ctx, &buffers[0usize], 4usize, &acts[0usize], false, 1usize, false, false)
    if closed_2_error != ok || testing.pump(&harness, root_closed_2, now) != ok { os.exit(36i32) }
    if testing.by_text(&harness, "a@x").count == 0usize || testing.by_text(&harness, "b@y").count == 0usize { os.exit(36i32) }
    let (remove_at, has_remove) = centre_of(&harness, &runtime, 34u64)
    if !has_remove || testing.tap(&harness, remove_at.x, remove_at.y) != ok || logs[0usize].removes != 1usize || logs[0usize].last_remove != 1usize { os.exit(37i32) }
    let (to_at, has_to) = centre_of(&harness, &runtime, 30u64)
    if !has_to || testing.tap(&harness, to_at.x, to_at.y) != ok || testing.type_text(&harness, "c") != ok || testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].adds != 1usize { os.exit(38i32) }
    // The picker's sheet: closed, a button; a tap toggles; open, a modal dialog of
    // rows in the middle; a row picks; Escape toggles.
    if testing.by_role(&harness, .Dialog).count != 0usize { os.exit(39i32) }
    let (kind_at, has_kind) = centre_of(&harness, &runtime, 40u64)
    if !has_kind || testing.tap(&harness, kind_at.x, kind_at.y) != ok || logs[0usize].fruit_toggles != 1usize { os.exit(40i32) }
    let (root_4, build_4_error) = build(&frame, &theme, ctx, &buffers[0usize], 4usize, &acts[0usize], false, 1usize, false, true)
    if build_4_error != ok { os.exit(41i32) }
    if testing.pump(&harness, root_4, now) != ok { os.exit(42i32) }
    let (tree_4, tree_4_error) = testing.semantics(&harness)
    if tree_4_error != ok { os.exit(43i32) }
    let (sheet_node, has_sheet) = find(tree_4, .Dialog, "Kind")
    if !has_sheet || !sheet_node.state.modal { os.exit(44i32) }
    let (plum_at, has_plum) = centre_of(&harness, &runtime, 43u64)
    if !has_plum || testing.tap(&harness, plum_at.x, plum_at.y) != ok || logs[0usize].fruit_picks != 1usize || logs[0usize].last_pick != 1usize { os.exit(45i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].fruit_toggles != 2usize { os.exit(46i32) }
    // The multi-select list: three rows, two selected; a tap on the middle fires its
    // toggle.
    let (root_5, build_5_error) = build(&frame, &theme, ctx, &buffers[0usize], 4usize, &acts[0usize], false, 1usize, false, false)
    if build_5_error != ok { os.exit(47i32) }
    if testing.pump(&harness, root_5, now) != ok { os.exit(48i32) }
    let (tree_5, tree_5_error) = testing.semantics(&harness)
    if tree_5_error != ok { os.exit(49i32) }
    var selected_rows = 0usize
    i = 0usize
    while i < tree_5.nodes.len {
        if tree_5.nodes[i].role == .ListItem && tree_5.nodes[i].state.selected { selected_rows += 1usize }
        i += 1usize
    }
    if selected_rows != 2usize { os.exit(50i32) }
    let (middle_at, has_middle) = centre_of(&harness, &runtime, 52u64)
    if !has_middle || testing.tap(&harness, middle_at.x, middle_at.y) != ok || logs[0usize].row_toggles != 1usize || logs[0usize].last_row != 1usize { os.exit(51i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(52i32) }
    try io.print("ui entry ok\n")
    ret ok
}
