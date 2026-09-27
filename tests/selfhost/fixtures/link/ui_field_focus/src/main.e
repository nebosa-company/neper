// A labelled text field keeps the focus across the rebuild its focus causes
// (D1595). Focused, a field floats its label: into a notch over an outlined box, to
// the top of a filled one, and a prefix appears beside the value. Each of those
// changed the shape of the unkeyed nodes around the editor, so the reconciler made
// the editor afresh and dropped the focus a tap or a Tab had just given it: a
// labelled field took no typing in a running app. Here each field is focused -- by
// a tap, by Tab, by Shift+Tab -- then the tree is rebuilt and pumped, and the
// field must still hold the focus and take what is typed.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.scene
use e.text.shape
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { lens: [3]usize, picked: usize }
type Buffers = struct { outlined: [32]u8, filled: [32]u8, priced: [32]u8 }
type Change = struct { log: *Log, index: usize }

fn on_change(ctx: *void, value: str) -> err {
    let c = mem.cast[*Change](ctx)
    c.log.lens[c.index] = value.len
    ret ok
}

fn build(a: *mem.Arena, t: *const control.Theme, buffers: *Buffers, log: *Log, changes: []Change) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 4usize)
    if items_error != ok { ret (zero, items_error) }
    let (outlined, outlined_error) = control.text_field(a, 1u64, t, "Name", buffers.outlined[..], log.lens[0usize], widget.Change[str] { ctx: mem.cast[*void](&changes[0usize]), invoke: on_change }, zero, control.field_options())
    if outlined_error != ok { ret (zero, outlined_error) }
    items[0usize] = outlined
    var filled_options = control.field_options()
    filled_options.filled = true
    let (filled, filled_error) = control.text_field(a, 2u64, t, "City", buffers.filled[..], log.lens[1usize], widget.Change[str] { ctx: mem.cast[*void](&changes[1usize]), invoke: on_change }, zero, filled_options)
    if filled_error != ok { ret (zero, filled_error) }
    items[1usize] = filled
    var priced_options = control.field_options()
    priced_options.prefix = "$"
    let (priced, priced_error) = control.text_field(a, 3u64, t, "Price", buffers.priced[..], log.lens[2usize], widget.Change[str] { ctx: mem.cast[*void](&changes[2usize]), invoke: on_change }, zero, priced_options)
    if priced_error != ok { ret (zero, priced_error) }
    items[2usize] = priced
    // A select whose label moves into the notch once something is chosen.
    let (submits, submits_error) = mem.alloc[widget.Submit](a, 3usize)
    if submits_error != ok { ret (zero, submits_error) }
    var i = 0usize
    while i < 3usize {
        submits[i] = widget.Submit { ctx: mem.cast[*void](log), invoke: none }
        i += 1usize
    }
    let fruits: [2]str = [2]str{ "Apple", "Pear" }
    let (chooser, chooser_error) = control.select(a, 4u64, t, "Fruit", fruits[..], log.picked, false, &submits[0usize], submits[1usize..3usize])
    if chooser_error != ok { ret (zero, chooser_error) }
    items[3usize] = chooser
    var column = style.defaults()
    column.width = style.Length { Px: 240.0 }
    column.height = style.Length { Px: 400.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, items[0usize..4usize]), ok)
}

fn none(ctx: *void) -> err {
    ret ok
}

// The element keyed `key` holds the focus.
fn focused_on(w: *World, key: widget.Key) -> bool {
    let (focus, has_focus) = testing.focused(w.h)
    let element = testing.by_key(w.h, key).element
    ret has_focus && focus.slot == element.slot && focus.generation == element.generation
}

type World = struct { h: *testing.Harness, t: *const control.Theme, buffers: *Buffers, log: *Log, changes: []Change, frame_storage: []u8, clock: i64 }

// The tree built afresh and pumped: the rebuild a focus change causes.
fn rebuild(w: *World) -> err {
    w.clock += 16000000i64
    let now = time.Instant { nanos: w.clock }
    try testing.begin(w.h, now)
    var frame = mem.arena_from(w.frame_storage)
    let (root, build_error) = build(&frame, w.t, w.buffers, w.log, w.changes)
    if build_error != ok { ret build_error }
    ret testing.pump(w.h, root, now)
}

// The field keyed `key` holds the focus after a rebuild, and takes typing: its
// text is then `total` bytes long.
fn holds(w: *World, key: widget.Key, index: usize, typed: str, total: usize) -> bool {
    if rebuild(w) != ok || rebuild(w) != ok || !focused_on(w, key) { ret false }
    if testing.type_text(w.h, typed) != ok { ret false }
    ret w.log.lens[index] == total
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 96usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 12u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 240u32, 400u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var empty_log: Log = zero
    empty_log.picked = 2usize
    logs[0usize] = empty_log
    let (buffers, buffers_error) = mem.alloc[Buffers](a, 1usize)
    if buffers_error != ok { os.exit(8i32) }
    var empty: Buffers = zero
    buffers[0usize] = empty
    let (changes, changes_error) = mem.alloc[Change](a, 3usize)
    if changes_error != ok { os.exit(9i32) }
    var i = 0usize
    while i < 3usize {
        changes[i] = Change { log: &logs[0usize], index: i }
        i += 1usize
    }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 524288usize)
    if storage_error != ok { os.exit(10i32) }
    var w = World { h: &harness, t: &theme, buffers: &buffers[0usize], log: &logs[0usize], changes: changes, frame_storage: frame_storage, clock: 1000000000i64 }
    if rebuild(&w) != ok { os.exit(11i32) }
    // A tap on the outlined field: its label floats into the notch.
    let (bounds, has_bounds) = widget.bounds_of(&runtime, testing.by_key(&harness, 1u64).element)
    if !has_bounds || testing.tap(&harness, bounds.x + 2.0, bounds.y + 2.0) != ok { os.exit(12i32) }
    if !holds(&w, 1u64, 0usize, "Ann", 3usize) { os.exit(13i32) }
    // Tab to the filled field: its label moves to the top of the box.
    if testing.tab(&harness, false) != ok || !holds(&w, 2u64, 1usize, "Oslo", 4usize) { os.exit(14i32) }
    // Tab to the field with a prefix: the prefix appears beside the value.
    if testing.tab(&harness, false) != ok || !holds(&w, 3u64, 2usize, "12", 2usize) { os.exit(15i32) }
    // Shift+Tab back to the filled field, which holds text and stays floated.
    if testing.tab(&harness, true) != ok || !holds(&w, 2u64, 1usize, "!", 5usize) { os.exit(16i32) }
    // Two Tabs on, the select's head; a choice floats its label into the notch,
    // and the head keeps the focus.
    if testing.tab(&harness, false) != ok || testing.tab(&harness, false) != ok || rebuild(&w) != ok || !focused_on(&w, 4u64) { os.exit(17i32) }
    logs[0usize].picked = 0usize
    if rebuild(&w) != ok || rebuild(&w) != ok || !focused_on(&w, 4u64) { os.exit(18i32) }
    try io.print("ui field focus ok\n")
    ret ok
}
