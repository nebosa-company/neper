// `e.ui.terminal_view` (D4500, L136): the scrollback of an `e.ui.terminal` buffer as a virtual list. A terminal with
// a bounded history is fed numbered lines; the list builds only the lines in view; a line keeps its key while the
// output scrolls it into history and while older lines are evicted; the offset follows the newest output when it
// was at the bottom and stays on the same text when it was not; a selection marks the rows it touches; the
// alternate screen is a list of its rows alone, in its own key range; the cell under a point maps to buffer
// coordinates. Checked through the widget runtime's accessibility tree and by-key / by-text queries.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.style
use e.ui.terminal as tm
use e.ui.terminal_view as tv
use e.ui.testing
use e.ui.widget

fn extent_px() -> f32 { ret 16.0 }
fn height_px() -> f32 { ret 80.0 }
fn width_px() -> f32 { ret 200.0 }

type Log = struct { scrolls: usize, offset: f32 }

fn on_scroll(ctx: *void, value: f32) -> err {
    let log = mem.cast[*Log](ctx)
    log.scrolls += 1usize
    log.offset = value
    ret ok
}

// "line NN\r\n" for NN in [from, to).
fn feed_lines(t: *tm.Term, from: usize, to: usize) {
    var n = from
    while n < to {
        var b: [16]u8 = zero
        b[0usize] = 108u8
        b[1usize] = 105u8
        b[2usize] = 110u8
        b[3usize] = 101u8
        b[4usize] = 32u8
        b[5usize] = 48u8 + u8((n / 100usize) % 10usize)
        b[6usize] = 48u8 + u8((n / 10usize) % 10usize)
        b[7usize] = 48u8 + u8(n % 10usize)
        b[8usize] = 13u8
        b[9usize] = 10u8
        tm.feed(t, b[0usize..10usize])
        n += 1usize
    }
}

fn label_of(n: usize, out: []u8) -> usize {
    out[0usize] = 108u8
    out[1usize] = 105u8
    out[2usize] = 110u8
    out[3usize] = 101u8
    out[4usize] = 32u8
    out[5usize] = 48u8 + u8((n / 100usize) % 10usize)
    out[6usize] = 48u8 + u8((n / 10usize) % 10usize)
    out[7usize] = 48u8 + u8(n % 10usize)
    ret 8usize
}

// The list item index of the line whose text is "line NN", or the total when it is not in the buffer.
fn index_of(v: *const tv.Viewport, n: usize) -> usize {
    var want: [8]u8 = zero
    let wn = label_of(n, want[..])
    var i = 0usize
    while i < tv.line_total(v) {
        var buf: [32]u8 = zero
        let got = tm.line_text(v.t, tv.buffer_line(v, i), buf[..])
        if got == wn {
            var same = true
            var k = 0usize
            while k < wn {
                if buf[k] != want[k] { same = false }
                k += 1usize
            }
            if same { ret i }
        }
        i += 1usize
    }
    ret tv.line_total(v)
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
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(7i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(8i32) }
    let change = widget.Change[f32] { ctx: mem.cast[*void](&logs[0usize]), invoke: on_scroll }

    // A terminal 20 x 5 with room for 40 lines of history.
    let (tt, term_error) = tm.new(a, 20usize, 5usize, 20usize, 5usize, 40usize)
    if term_error != ok { os.exit(9i32) }
    var term = tt
    feed_lines(&term, 0usize, 30usize)
    // 30 lines then a cursor on the 31st row: 26 lines of history and five live rows.
    if term.sb_len != 26usize || tm.line_count(&term) != 31usize || term.sb_dropped != 0usize { os.exit(10i32) }
    var viewport = tv.viewport(&term, &theme)
    if tv.line_total(&viewport) != 31usize { os.exit(11i32) }
    // Keys: line n is key n + 1 until something is evicted.
    if tv.line_key(&viewport, 0usize) != 1u64 || tv.line_key(&viewport, 30usize) != 31u64 { os.exit(12i32) }

    // At the bottom: the newest lines are built, the oldest are not; only the visible ones plus overscan.
    var offset = tv.bottom_offset(&viewport, extent_px(), height_px())
    if offset != 31.0 * 16.0 - 80.0 || !tv.at_bottom(&viewport, offset, extent_px(), height_px()) { os.exit(13i32) }
    if tv.at_bottom(&viewport, offset - 40.0, extent_px(), height_px()) { os.exit(14i32) }
    var none: [1]widget.Key = zero
    let (root, root_error) = tv.list(&frame, 7u64, &viewport, "Output", none[0usize..0usize], extent_px(), offset, change, width_px(), height_px())
    if root_error != ok { os.exit(15i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(16i32) }
    if testing.by_key(&harness, 31u64).count != 1usize || testing.by_key(&harness, 1u64).count != 0usize { os.exit(17i32) }
    if testing.by_text(&harness, "line 027").count != 1usize || testing.by_text(&harness, "line 000").count != 0usize { os.exit(18i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(19i32) }
    var counted = false
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .List && tree.nodes[i].position.row_count == 31u32 { counted = true }
        i += 1usize
    }
    if !counted { os.exit(20i32) }

    // Scrolled to the top, the oldest lines are the ones built.
    let (top_root, top_error) = tv.list(&frame, 7u64, &viewport, "Output", none[0usize..0usize], extent_px(), 0.0, change, width_px(), height_px())
    if top_error != ok { os.exit(21i32) }
    if testing.pump(&harness, top_root, now) != ok { os.exit(22i32) }
    if testing.by_key(&harness, 1u64).count != 1usize || testing.by_key(&harness, 31u64).count != 0usize { os.exit(23i32) }
    if testing.by_text(&harness, "line 000").count != 1usize { os.exit(24i32) }

    // Output while the view is at the bottom: it follows; keys of lines that were there are unchanged.
    let key_20_before = tv.line_key(&viewport, index_of(&viewport, 20usize))
    let dropped_before = term.sb_dropped
    feed_lines(&term, 30usize, 49usize)
    // 49 lines and the cursor row: 45 lines of history against a cap of 40, five evicted.
    if term.sb_len != 40usize || term.sb_dropped != 5usize { os.exit(25i32) }
    let key_20_after = tv.line_key(&viewport, index_of(&viewport, 20usize))
    if key_20_before != key_20_after { os.exit(26i32) }
    let followed = tv.follow(&viewport, offset, extent_px(), height_px(), true, dropped_before)
    if followed != tv.bottom_offset(&viewport, extent_px(), height_px()) || followed <= offset { os.exit(27i32) }

    // Not at the bottom: the offset moves up by the evicted lines so the same text stays in view.
    let held = tv.follow(&viewport, 400.0, extent_px(), height_px(), false, dropped_before)
    if held != 400.0 - 5.0 * 16.0 { os.exit(28i32) }
    if tv.follow(&viewport, 30.0, extent_px(), height_px(), false, dropped_before) != 0.0 { os.exit(29i32) }

    // Evicted lines are gone; the survivors keep their numbering.
    if index_of(&viewport, 3usize) != tv.line_total(&viewport) { os.exit(30i32) }
    let at_20 = index_of(&viewport, 20usize)
    if at_20 != 15usize || tv.line_key(&viewport, at_20) != 21u64 { os.exit(31i32) }

    // A selection over lines 20..22 marks three rows in the range the list builds.
    var sel = tm.selection_start(tm.SEL_CHAR, tv.buffer_line(&viewport, at_20), 0usize)
    tm.selection_extend(&sel, tv.buffer_line(&viewport, at_20 + 2usize), 3usize)
    var picked: [8]widget.Key = zero
    let marked = tv.selected_keys(&viewport, &sel, at_20 - 2usize, 8usize, picked[..])
    if marked != 3usize || picked[0usize] != 21u64 || picked[2usize] != 23u64 { os.exit(32i32) }
    let sel_offset = f32(at_20 - 2usize) * extent_px()
    let (sel_root, sel_error) = tv.list(&frame, 7u64, &viewport, "Output", picked[0usize..marked], extent_px(), sel_offset, change, width_px(), height_px())
    if sel_error != ok { os.exit(33i32) }
    if testing.pump(&harness, sel_root, now) != ok { os.exit(34i32) }
    let (sel_tree, sel_tree_error) = testing.semantics(&harness)
    if sel_tree_error != ok { os.exit(35i32) }
    var selected_rows = 0usize
    i = 0usize
    while i < sel_tree.nodes.len {
        if sel_tree.nodes[i].role == .ListItem && sel_tree.nodes[i].state.selected { selected_rows += 1usize }
        i += 1usize
    }
    if selected_rows != 3usize { os.exit(36i32) }
    var sel_text: [64]u8 = zero
    let sn = tm.selection_text(&term, &sel, sel_text[..])
    if sn != 8usize + 1usize + 8usize + 1usize + 4usize { os.exit(37i32) }

    // The cell under a point: 8-pixel cells, list-local coordinates, scrolled by 3 lines and a half.
    let (cl, cc) = tv.cell_at(&viewport, 3.5 * extent_px(), extent_px(), 8.0, 41.0, 7.0)
    if cl != 3usize || cc != 5usize { os.exit(38i32) }
    let (far_line, far_col) = tv.cell_at(&viewport, 0.0, extent_px(), 8.0, 5000.0, 99999.0)
    if far_line != tm.line_count(&term) - 1usize || far_col != 19usize { os.exit(39i32) }

    // The alternate screen: its rows alone, in a separate key range.
    tm.feed(&term, "\x1b[?1049hALT")
    if tv.line_total(&viewport) != 5usize || tv.buffer_line(&viewport, 0usize) != term.sb_len { os.exit(40i32) }
    let alt_key = tv.line_key(&viewport, 0usize)
    if alt_key == tv.line_key(&viewport, 1usize) || alt_key < tv.ALT_KEY_BIT { os.exit(41i32) }
    let (alt_root, alt_error) = tv.list(&frame, 7u64, &viewport, "Output", none[0usize..0usize], extent_px(), 0.0, change, width_px(), height_px())
    if alt_error != ok { os.exit(42i32) }
    if testing.pump(&harness, alt_root, now) != ok { os.exit(43i32) }
    if testing.by_text(&harness, "ALT").count != 1usize || testing.by_text(&harness, "line 044").count != 0usize { os.exit(44i32) }
    tm.feed(&term, "\x1b[?1049l")
    if tv.line_total(&viewport) != tm.line_count(&term) { os.exit(45i32) }

    // A reflow renumbers: no key of the old numbering is reused.
    let before_reflow = term.sb_dropped + tm.line_count(&term)
    let (scratch_storage, scratch_error) = mem.alloc[u8](a, 65536usize)
    if scratch_error != ok { os.exit(46i32) }
    var scratch = mem.arena_from(scratch_storage)
    if tm.resize_reflow(&scratch, &term, 10usize, 5usize, 100usize) != ok { os.exit(47i32) }
    if term.sb_dropped < before_reflow { os.exit(48i32) }

    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(49i32) }
    try io.print("ui terminal view ok\n")
    ret ok
}
