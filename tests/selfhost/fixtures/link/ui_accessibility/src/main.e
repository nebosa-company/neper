// `e.ui.accessibility` (D802): the semantic tree of a widget runtime -- a group
// holding a button labelled by its text and a plain box -- with roles, labels,
// children, focus and actions; a press performed through the tree reaches the
// button's action; a stale window refuses publication.

use e.gpu
use e.io
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.text.shape
use e.ui.accessibility
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.window

type Counter = struct { presses: usize }

fn on_press(ctx: *void, event: input.Event) -> err {
    let counter = mem.cast[*Counter](ctx)
    if event.tag == .PointerDown { counter.presses += 1usize }
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

fn sized(width: f32, height: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    s.background = paint.Brush { Solid: paint.rgba(0.5, 0.5, 0.5, 1.0) }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 2u32, 2u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let limits = widget.Limits { max_elements: 16usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 32usize }
    let (rt, runtime_error) = widget.runtime(a, &renderer, limits)
    if runtime_error != ok { os.exit(4i32) }
    var runtime = rt
    var counter = Counter { presses: 0usize }
    // The text child needs a font choice to lay out; an empty font list makes the
    // text node measure as nothing, so the label is carried by a text without fonts
    // only through its value -- a synthetic font is not needed for the tree.
    let (fonts, fonts_error) = mem.alloc[layout.FontChoice](a, 0usize)
    if fonts_error != ok { os.exit(5i32) }
    let (label, label_error) = mem.alloc[widget.Node](a, 1usize)
    if label_error != ok { os.exit(6i32) }
    label[0usize] = widget.text(0u64, widget.Text { value: "Go", style: layout.Style { fonts: fonts, language: "", line_height: 16.0 }, color: paint.rgba(1.0, 1.0, 1.0, 1.0), wrap: .Word, align: .Start, max_lines: 0u32, ellipsis: "" }, style.defaults())
    let (children, children_error) = mem.alloc[widget.Node](a, 2usize)
    if children_error != ok { os.exit(7i32) }
    children[0usize] = widget.button(2u64, widget.Button { action: widget.Action { ctx: mem.cast[*void](&counter), invoke: on_press }, enabled: true }, sized(40.0, 20.0), label[0usize..1usize])
    children[1usize] = widget.box(3u64, sized(20.0, 10.0), zero)
    var column = style.defaults()
    column.width = style.Length { Px: 64.0 }
    column.height = style.Length { Px: 64.0 }
    let root = widget.flex(1u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, children[0usize..2usize])
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(8i32) }
    var frame = mem.arena_from(frame_storage)
    let (compiled, reconcile_error) = widget.reconcile(&runtime, &frame, root, ui_layout.Constraints { min_width: 0.0, max_width: 64.0, min_height: 0.0, max_height: 64.0 })
    if reconcile_error != ok {
        // A text with no fonts is refused by the layout; the tree needs no text
        // painted, so the label is dropped and the button stays unlabelled.
        os.exit(9i32)
    }
    let (tree, build_error) = accessibility.build(a, &runtime)
    if build_error != ok || tree.nodes.len != 4usize { os.exit(10i32) }
    // The root is a group with two children; the button is labelled by its text.
    var root_index = 0usize
    var button_index = 0usize
    var box_index = 0usize
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].id.slot == tree.root.slot { root_index = i }
        if tree.nodes[i].role == .Button { button_index = i }
        if tree.nodes[i].role == .Group && tree.nodes[i].id.slot != tree.root.slot { box_index = i }
        i += 1usize
    }
    if tree.nodes[root_index].role != .Group || tree.nodes[root_index].children.len != 2usize { os.exit(11i32) }
    if !same(tree.nodes[button_index].label, "Go") || tree.nodes[button_index].children.len != 1usize { os.exit(12i32) }
    if tree.nodes[button_index].bounds.height != 20.0 || tree.nodes[button_index].actions.len != 2usize || tree.nodes[button_index].actions[1] != .Press { os.exit(13i32) }
    if tree.nodes[box_index].actions.len != 1usize || tree.nodes[box_index].state.focused { os.exit(14i32) }
    // Focus through the tree, then a press: the action fires and the tree says focused.
    if accessibility.perform(&runtime, tree.nodes[button_index].id, .Focus, "") != ok { os.exit(15i32) }
    if accessibility.perform(&runtime, tree.nodes[button_index].id, .Press, "") != ok || counter.presses != 1usize { os.exit(16i32) }
    if accessibility.perform(&runtime, tree.nodes[button_index].id, .SetValue, "x") != accessibility.Unsupported { os.exit(17i32) }
    let (again, again_error) = accessibility.build(a, &runtime)
    if again_error != ok || !again.nodes[button_index].state.focused { os.exit(18i32) }
    // A window nobody opened cannot publish.
    if accessibility.publish(window.Id { slot: 3u32, generation: 9u32 }, &tree) != accessibility.Invalid { os.exit(19i32) }
    let stale = widget.ElementId { slot: 99u32, generation: 1u32 }
    if accessibility.perform(&runtime, stale, .Focus, "") != accessibility.Invalid { os.exit(20i32) }
    let all_flags = accessibility.flags_of(accessibility.State { disabled: true, focused: true, selected: true, checked: true, expanded: true, hidden: true, mixed: true, busy: true, invalid: true, required: true, read_only: true, modal: true, current: true })
    if all_flags != 8191u16 { os.exit(22i32) }
    var sample: accessibility.Node = zero
    sample.role = .TextField
    sample.live = .Assertive
    sample.position = accessibility.Position { row: 2u32, column: 3u32, row_count: 20u32, column_count: 4u32 }
    sample.level = 5u8
    sample.selection_start = 7usize
    sample.selection_end = 11usize
    let flat = accessibility.flat_node(&sample)
    if flat.role != 7u8 || flat.live != 2u8 || flat.row != 2u32 || flat.column != 3u32 || flat.row_count != 20u32 || flat.column_count != 4u32 || flat.level != 5u8 || flat.selection_start != 7usize || flat.selection_end != 11usize { os.exit(23i32) }
    if widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(21i32) }
    try io.print("ui accessibility ok\n")
    ret ok
}
