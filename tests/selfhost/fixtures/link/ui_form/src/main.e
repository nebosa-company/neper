// `e.ui.control`'s forms (D825, widget plan P1-12) under the light theme: a form
// field stands its label above the control and its help below, required and
// invalid as states and relationships in the tree; Enter in a field with no submit
// of its own is the form's default action and Escape its cancel; an invalid form
// shows each message in the error colour and a validation summary whose links jump
// to their fields; wide enough, the fields wrap into a row.

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

type Log = struct { submits: usize, cancels: usize, jumps: usize, last_jump: usize }
type Jump = struct { log: *Log, index: usize }

fn on_submit(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.submits += 1usize
    ret ok
}

fn on_cancel(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.cancels += 1usize
    ret ok
}

fn on_jump(ctx: *void) -> err {
    let jump = mem.cast[*Jump](ctx)
    jump.log.jumps += 1usize
    jump.log.last_jump = jump.index
    ret ok
}

fn on_text(ctx: *void, value: str) -> err {
    ret ok
}

type Buffers = struct { name: [32]u8, email: [32]u8 }

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn build(a: *mem.Arena, t: *const control.Theme, buffers: *Buffers, ctx: *void, jumps: []const widget.Submit, invalid: bool, width: f32) -> (widget.Node, err) {
    let (fields, fields_error) = mem.alloc[widget.Node](a, 3usize)
    if fields_error != ok { ret (zero, fields_error) }
    var messages: [2]control.Message = zero
    messages[0usize] = control.Message { validity: .Valid, text: "" }
    messages[1usize] = control.Message { validity: .Valid, text: "" }
    if invalid { messages[1usize] = control.Message { validity: .Invalid, text: "Email is required" } }
    var field_keys: [2]widget.Key = zero
    field_keys[0usize] = 1u64
    field_keys[1usize] = 2u64
    let (summary, summary_error) = control.validation_summary(a, 100u64, t, messages[..], field_keys[..], jumps)
    if summary_error != ok { ret (zero, summary_error) }
    fields[0usize] = summary
    let (name, name_error) = control.text_field(a, 1u64, t, "Name", buffers.name[..], 0usize, widget.Change[str] { ctx: ctx, invoke: on_text }, zero, control.field_options())
    if name_error != ok { ret (zero, name_error) }
    let (name_field, name_field_error) = control.form_field(a, 10u64, t, "Name", 1u64, name, "As on your card", messages[0usize], true)
    if name_field_error != ok { ret (zero, name_field_error) }
    fields[1usize] = name_field
    var email_options = control.field_options()
    email_options.invalid = invalid
    let (email, email_error) = control.text_field(a, 2u64, t, "Email", buffers.email[..], 0usize, widget.Change[str] { ctx: ctx, invoke: on_text }, zero, email_options)
    if email_error != ok { ret (zero, email_error) }
    let (email_field, email_field_error) = control.form_field(a, 20u64, t, "Email", 2u64, email, "", messages[1usize], false)
    if email_field_error != ok { ret (zero, email_field_error) }
    fields[2usize] = email_field
    let (whole, whole_error) = control.form(a, 30u64, t, "Sign up", width, fields[0usize..3usize], widget.Submit { ctx: ctx, invoke: on_submit }, widget.Submit { ctx: ctx, invoke: on_cancel })
    if whole_error != ok { ret (zero, whole_error) }
    ret (whole, ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 96usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 12u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 900u32, 320u32, 1.0)
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
    let (jump_targets, jump_targets_error) = mem.alloc[Jump](a, 2usize)
    if jump_targets_error != ok { os.exit(9i32) }
    jump_targets[0usize] = Jump { log: &logs[0usize], index: 0usize }
    jump_targets[1usize] = Jump { log: &logs[0usize], index: 1usize }
    let (jumps, jumps_error) = mem.alloc[widget.Submit](a, 2usize)
    if jumps_error != ok { os.exit(10i32) }
    jumps[0usize] = widget.Submit { ctx: mem.cast[*void](&jump_targets[0usize]), invoke: on_jump }
    jumps[1usize] = widget.Submit { ctx: mem.cast[*void](&jump_targets[1usize]), invoke: on_jump }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 524288usize)
    if storage_error != ok { os.exit(11i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, &buffers[0usize], ctx, jumps[0usize..2usize], false, 240.0)
    if build_error != ok { os.exit(12i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(13i32) }
    // Two labelled fields; the required one carries an asterisk; the help shows (its
    // text, and the status labelled by it) and no message or summary does.
    if testing.by_role(&harness, .TextField).count != 2usize { os.exit(14i32) }
    if testing.by_text(&harness, "*").count != 1usize || testing.by_text(&harness, "As on your card").count != 2usize { os.exit(15i32) }
    if testing.by_text(&harness, "Email is required").count != 0usize || testing.by_role(&harness, .Link).count != 0usize { os.exit(16i32) }
    // The tree: the form is a group named by its label; the name field's group is
    // required, labelled by its label and described by its help; the email field's
    // group is neither.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(17i32) }
    let (form_node, has_form) = find(tree, .Group, "Sign up")
    if !has_form { os.exit(18i32) }
    let (name_group, has_name_group) = find(tree, .Group, "Name")
    if !has_name_group || !name_group.state.required || name_group.state.invalid { os.exit(19i32) }
    if name_group.relations.labelled_by.slot == 0u32 && name_group.relations.labelled_by.generation == 0u32 { os.exit(20i32) }
    if name_group.relations.described_by.slot == 0u32 && name_group.relations.described_by.generation == 0u32 { os.exit(21i32) }
    let (help_node, has_help) = find(tree, .Status, "As on your card")
    if !has_help || help_node.live != .Polite { os.exit(22i32) }
    let (email_group, has_email_group) = find(tree, .Group, "Email")
    if !has_email_group || email_group.state.required || email_group.state.invalid { os.exit(23i32) }
    // Compact: the email field stands below the name field.
    if email_group.bounds.y <= name_group.bounds.y { os.exit(24i32) }
    // Enter in the name field (no submit of its own) is the form's default action;
    // Escape is its cancel.
    let name = testing.by_key(&harness, 1u64).element
    let (name_bounds, has_name) = widget.bounds_of(&runtime, name)
    if !has_name || testing.tap(&harness, name_bounds.x + 2.0, name_bounds.y + 2.0) != ok { os.exit(25i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].submits != 1usize { os.exit(26i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].cancels != 1usize { os.exit(27i32) }
    // Invalid: the message shows, the email group says invalid with its error
    // relationship, the message is assertive, and the summary is an alert with one
    // link whose tap jumps to the email field.
    let (root_2, build_2_error) = build(&frame, &theme, &buffers[0usize], ctx, jumps[0usize..2usize], true, 240.0)
    if build_2_error != ok { os.exit(28i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(29i32) }
    // The message and its status, the link and its label.
    if testing.by_text(&harness, "Email is required").count != 4usize || testing.by_role(&harness, .Link).count != 1usize { os.exit(30i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(31i32) }
    let (email_group_2, has_email_group_2) = find(tree_2, .Group, "Email")
    if !has_email_group_2 || !email_group_2.state.invalid { os.exit(32i32) }
    if email_group_2.relations.error_by.slot == 0u32 && email_group_2.relations.error_by.generation == 0u32 { os.exit(33i32) }
    let (message_node, has_message) = find(tree_2, .Status, "Email is required")
    if !has_message || message_node.live != .Assertive || !message_node.state.invalid { os.exit(34i32) }
    var alert_seen = false
    var i = 0usize
    while i < tree_2.nodes.len {
        if tree_2.nodes[i].role == .Alert && tree_2.nodes[i].live == .Assertive && !tree_2.nodes[i].state.hidden { alert_seen = true }
        i += 1usize
    }
    if !alert_seen { os.exit(35i32) }
    let jump_link = testing.by_key(&harness, 102u64)
    let (link_bounds, has_link) = widget.bounds_of(&runtime, jump_link.element)
    if jump_link.count != 1usize || !has_link { os.exit(36i32) }
    if testing.tap(&harness, link_bounds.x + link_bounds.width * 0.5, link_bounds.y + link_bounds.height * 0.5) != ok { os.exit(37i32) }
    if logs[0usize].jumps != 1usize || logs[0usize].last_jump != 1usize { os.exit(38i32) }
    // Expanded: the fields wrap into a row.
    let (root_3, build_3_error) = build(&frame, &theme, &buffers[0usize], ctx, jumps[0usize..2usize], false, 900.0)
    if build_3_error != ok { os.exit(39i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(40i32) }
    let (tree_3, tree_3_error) = testing.semantics(&harness)
    if tree_3_error != ok { os.exit(41i32) }
    let (name_group_3, has_name_group_3) = find(tree_3, .Group, "Name")
    let (email_group_3, has_email_group_3) = find(tree_3, .Group, "Email")
    if !has_name_group_3 || !has_email_group_3 { os.exit(42i32) }
    if email_group_3.bounds.y != name_group_3.bounds.y || email_group_3.bounds.x <= name_group_3.bounds.x { os.exit(43i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(44i32) }
    try io.print("ui form ok\n")
    ret ok
}
