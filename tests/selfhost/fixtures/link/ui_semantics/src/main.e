// `e.ui.accessibility`'s semantics node (D809, widget plan P0-06): an element that
// says its role, label, states, relationships, live politeness, collection place
// and level through `widget.Semantics`; an editor reporting its value and selection
// as a text field; a hidden subtree left out of the tree; a platform action reaching
// the semantics' callback when offered and refused when not; a value and a
// selection set on the editor by the platform.

use e.gpu
use e.io
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.ui.accessibility
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.window

type Log = struct { bits: u32, performed: usize, changes: usize }

fn on_action(ctx: *void, bit: u32) -> err {
    let log = mem.cast[*Log](ctx)
    log.bits = log.bits | bit
    log.performed += 1usize
    ret ok
}

fn on_change(ctx: *void, value: str) -> err {
    let log = mem.cast[*Log](ctx)
    log.changes += 1usize
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
    ret s
}

fn node_of(tree: *const accessibility.Tree, id: accessibility.Id) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].id.slot == id.slot && tree.nodes[i].id.generation == id.generation { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn has_action(node: *const accessibility.Node, action: accessibility.Action) -> bool {
    var i = 0usize
    while i < node.actions.len {
        if node.actions[i] == action { ret true }
        i += 1usize
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 2u32, 2u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 16usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 32usize })
    if runtime_error != ok { os.exit(4i32) }
    var runtime = rt
    var log: Log = zero
    let ctx = mem.cast[*void](&log)
    let (fonts, fonts_error) = mem.alloc[layout.FontChoice](a, 0usize)
    if fonts_error != ok { os.exit(5i32) }
    let text_style = layout.Style { fonts: fonts, language: "", line_height: 16.0 }
    let (buffer, buffer_error) = mem.alloc[u8](a, 16usize)
    if buffer_error != ok { os.exit(6i32) }
    buffer[0usize] = 104u8
    buffer[1usize] = 101u8
    buffer[2usize] = 108u8
    buffer[3usize] = 108u8
    buffer[4usize] = 111u8
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { os.exit(7i32) }
    inner[0usize] = widget.box(3u64, sized(20.0, 10.0), zero)
    let (hidden_inner, hidden_inner_error) = mem.alloc[widget.Node](a, 1usize)
    if hidden_inner_error != ok { os.exit(8i32) }
    hidden_inner[0usize] = widget.box(7u64, sized(20.0, 10.0), zero)
    let (children, children_error) = mem.alloc[widget.Node](a, 5usize)
    if children_error != ok { os.exit(9i32) }
    var described: widget.Semantics = zero
    described.role = 18u8
    described.label = "Dark"
    described.states = accessibility.STATE_CHECKED | accessibility.STATE_REQUIRED
    described.actions = accessibility.ACTION_SELECT
    described.on_action = widget.Change[u32] { ctx: ctx, invoke: on_action }
    described.labelled_by = 5u64
    described.controls = 4u64
    described.live = 1u8
    described.row = 2u32
    described.column = 3u32
    described.row_count = 4u32
    described.column_count = 5u32
    described.level = 2u8
    children[0usize] = widget.semantics(2u64, described, sized(40.0, 10.0), inner[0usize..1usize])
    children[1usize] = widget.edit(4u64, widget.Edit { buffer: buffer, len: 5usize, style: text_style, color: paint.rgba(1.0, 1.0, 1.0, 1.0), selection: paint.rgba(0.0, 0.0, 1.0, 1.0), change: widget.Change[str] { ctx: ctx, invoke: on_change }, submit: zero, enabled: true, read_only: false, multiline: false, secret: false }, sized(40.0, 16.0))
    children[2usize] = widget.text(5u64, widget.Text { value: "Theme", style: text_style, color: paint.rgba(1.0, 1.0, 1.0, 1.0), wrap: .Word, align: .Start, max_lines: 0u32, ellipsis: "" }, style.defaults())
    var hidden: widget.Semantics = zero
    hidden.hidden = true
    children[3usize] = widget.semantics(6u64, hidden, sized(20.0, 10.0), hidden_inner[0usize..1usize])
    var flagged: widget.Semantics = zero
    flagged.states = accessibility.STATE_INVALID
    flagged.hint = "bad"
    flagged.value = "v"
    children[4usize] = widget.semantics(8u64, flagged, sized(20.0, 10.0), zero)
    var column = style.defaults()
    column.width = style.Length { Px: 64.0 }
    column.height = style.Length { Px: 100.0 }
    let root = widget.flex(1u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, children[0usize..5usize])
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(10i32) }
    var frame = mem.arena_from(frame_storage)
    let limits = ui_layout.Constraints { min_width: 0.0, max_width: 64.0, min_height: 0.0, max_height: 100.0 }
    let (compiled, reconcile_error) = widget.reconcile(&runtime, &frame, root, limits)
    if reconcile_error != ok { os.exit(11i32) }
    let state = mem.cast[*widget.State](runtime.state)
    let (switch_id, _) = widget.find_by_key(state, 2u64)
    let (edit_id, _) = widget.find_by_key(state, 4u64)
    let (text_id, _) = widget.find_by_key(state, 5u64)
    let (hidden_id, _) = widget.find_by_key(state, 6u64)
    let (inner_hidden_id, _) = widget.find_by_key(state, 7u64)
    let (flagged_id, _) = widget.find_by_key(state, 8u64)
    let (tree, tree_error) = accessibility.build(a, &runtime)
    if tree_error != ok { os.exit(12i32) }
    // Six nodes: the hidden subtree is not among them, nor among the root's children.
    if tree.nodes.len != 6usize { os.exit(13i32) }
    let (_, hidden_present) = node_of(&tree, hidden_id)
    let (_, inner_hidden_present) = node_of(&tree, inner_hidden_id)
    if hidden_present || inner_hidden_present { os.exit(14i32) }
    let (root_node, has_root_node) = node_of(&tree, tree.root)
    if !has_root_node || root_node.children.len != 4usize { os.exit(15i32) }
    // The switch says everything the semantics carried.
    let (switch_node, has_switch) = node_of(&tree, switch_id)
    if !has_switch || switch_node.role != .Switch || !same(switch_node.label, "Dark") { os.exit(16i32) }
    if !switch_node.state.checked || !switch_node.state.required || switch_node.state.invalid || switch_node.state.disabled { os.exit(17i32) }
    if switch_node.live != .Polite || switch_node.level != 2u8 { os.exit(18i32) }
    if switch_node.position.row != 2u32 || switch_node.position.column != 3u32 || switch_node.position.row_count != 4u32 || switch_node.position.column_count != 5u32 { os.exit(19i32) }
    if switch_node.relations.labelled_by.slot != text_id.slot || switch_node.relations.labelled_by.generation != text_id.generation { os.exit(20i32) }
    if switch_node.relations.controls.slot != edit_id.slot || switch_node.relations.described_by.generation != 0u32 { os.exit(21i32) }
    if !has_action(&switch_node, .Select) || !has_action(&switch_node, .Focus) || has_action(&switch_node, .Expand) { os.exit(22i32) }
    // The editor is a text field with its value, selection and the two operations.
    let (edit_node, has_edit) = node_of(&tree, edit_id)
    if !has_edit || edit_node.role != .TextField || !same(edit_node.value, "hello") { os.exit(23i32) }
    if edit_node.selection_start != 0usize || edit_node.selection_end != 0usize || edit_node.state.read_only { os.exit(24i32) }
    if !has_action(&edit_node, .SetValue) || !has_action(&edit_node, .SetSelection) { os.exit(25i32) }
    // A group with only states, a hint and a value keeps its kind's role.
    let (flagged_node, has_flagged) = node_of(&tree, flagged_id)
    if !has_flagged || flagged_node.role != .Group || !flagged_node.state.invalid || !same(flagged_node.hint, "bad") || !same(flagged_node.value, "v") { os.exit(26i32) }
    // Platform actions: the offered one reaches the callback, the other is refused.
    if accessibility.perform(&runtime, switch_id, .Select, "") != ok { os.exit(27i32) }
    if log.performed != 1usize || log.bits != accessibility.ACTION_SELECT { os.exit(28i32) }
    if accessibility.perform(&runtime, switch_id, .Expand, "") != accessibility.Unsupported { os.exit(29i32) }
    if log.performed != 1usize { os.exit(30i32) }
    // The editor's value and selection set by the platform, and seen by the next tree.
    if accessibility.perform(&runtime, edit_id, .SetValue, "bye") != ok || log.changes != 1usize { os.exit(31i32) }
    if accessibility.perform(&runtime, edit_id, .SetSelection, "1:3") != ok { os.exit(32i32) }
    if accessibility.perform(&runtime, edit_id, .SetSelection, "x") != accessibility.Invalid { os.exit(33i32) }
    if accessibility.perform(&runtime, edit_id, .SetSelection, "2:9") != accessibility.Unsupported { os.exit(34i32) }
    let (again, again_error) = accessibility.build(a, &runtime)
    if again_error != ok { os.exit(35i32) }
    let (edit_again, has_edit_again) = node_of(&again, edit_id)
    if !has_edit_again || !same(edit_again.value, "bye") || edit_again.selection_start != 1usize || edit_again.selection_end != 3usize { os.exit(36i32) }
    if widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(37i32) }
    try io.print("ui semantics ok\n")
    ret ok
}
