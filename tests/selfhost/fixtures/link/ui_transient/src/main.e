// `e.ui.overlay` (D827, widget plan P1-14) under the light theme: a tooltip is
// wanted while its anchor is hovered and placed below it; a menu button opens a
// modal menu of commands under itself, its items are pressed with Enter, Escape and
// a press outside dismiss it; an alert dialog is a modal dialog in the middle,
// labelled by its title, whose Enter is the default button and Escape the cancel.

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
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { saves: usize, toggles: usize, commands: usize, last_command: usize, deletes: usize, cancels: usize }
type Command = struct { log: *Log, index: usize }

fn on_save(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.saves += 1usize
    ret ok
}

fn on_toggle(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    ret ok
}

fn on_command(ctx: *void) -> err {
    let c = mem.cast[*Command](ctx)
    c.log.commands += 1usize
    c.log.last_command = c.index
    ret ok
}

fn on_delete(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.deletes += 1usize
    ret ok
}

fn on_cancel(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.cancels += 1usize
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

fn build(a: *mem.Arena, t: *const control.Theme, save: *const widget.Submit, toggle: *const widget.Submit, items: []const overlay.MenuItem, buttons: []const overlay.DialogButton, menu_open: bool, dialog_open: bool) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, parts_error) }
    let (save_button, save_error) = control.button(a, 1u64, t, "Save", save, control.button_options())
    if save_error != ok { ret (zero, save_error) }
    parts[0usize] = save_button
    let (tip, tip_error) = overlay.tooltip(a, 2u64, t, 1u64, "Saves the file", overlay.tooltip_wanted(t, 1u64))
    if tip_error != ok { ret (zero, tip_error) }
    parts[1usize] = tip
    let (file_menu, file_error) = overlay.menu_button(a, 10u64, t, "File", items, menu_open, toggle)
    if file_error != ok { ret (zero, file_error) }
    parts[2usize] = file_menu
    let (dialog, dialog_error) = overlay.alert_dialog(a, 20u64, t, "Delete file?", "This cannot be undone.", buttons, dialog_open)
    if dialog_error != ok { ret (zero, dialog_error) }
    parts[3usize] = dialog
    var column = style.defaults()
    column.width = style.Length { Px: 320.0 }
    column.height = style.Length { Px: 320.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, parts[0usize..4usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 96usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 12u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 320u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 2usize)
    if actions_error != ok { os.exit(8i32) }
    actions[0usize] = widget.Submit { ctx: ctx, invoke: on_save }
    actions[1usize] = widget.Submit { ctx: ctx, invoke: on_toggle }
    let (commands, commands_error) = mem.alloc[Command](a, 3usize)
    if commands_error != ok { os.exit(9i32) }
    let (items, items_error) = mem.alloc[overlay.MenuItem](a, 3usize)
    if items_error != ok { os.exit(10i32) }
    var i = 0usize
    while i < 3usize {
        commands[i] = Command { log: &logs[0usize], index: i }
        items[i] = overlay.MenuItem { label: "New", action: widget.Submit { ctx: mem.cast[*void](&commands[i]), invoke: on_command }, enabled: true }
        i += 1usize
    }
    items[1usize].label = "Open"
    items[2usize].label = "Quit"
    items[2usize].enabled = false
    let (buttons, buttons_error) = mem.alloc[overlay.DialogButton](a, 2usize)
    if buttons_error != ok { os.exit(11i32) }
    buttons[0usize] = overlay.DialogButton { label: "Cancel", action: widget.Submit { ctx: ctx, invoke: on_cancel }, kind: .Cancel }
    buttons[1usize] = overlay.DialogButton { label: "Delete", action: widget.Submit { ctx: ctx, invoke: on_delete }, kind: .Destructive }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 524288usize)
    if storage_error != ok { os.exit(12i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, &actions[0usize], &actions[1usize], items[0usize..3usize], buttons[0usize..2usize], false, false)
    if build_error != ok { os.exit(13i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(14i32) }
    // Nothing transient yet: no tooltip, no menu items, no dialog.
    if testing.by_role(&harness, .Tooltip).count != 0usize || testing.by_role(&harness, .MenuItem).count != 0usize || testing.by_role(&harness, .Dialog).count != 0usize { os.exit(15i32) }
    // Hovered, the save button wants its tooltip; the next frame places it below.
    let (save_at, has_save) = centre_of(&harness, &runtime, 1u64)
    if !has_save || testing.hover(&harness, save_at.x, save_at.y) != ok { os.exit(16i32) }
    if !overlay.tooltip_wanted(&theme, 1u64) { os.exit(17i32) }
    let (root_2, build_2_error) = build(&frame, &theme, &actions[0usize], &actions[1usize], items[0usize..3usize], buttons[0usize..2usize], false, false)
    if build_2_error != ok { os.exit(18i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(19i32) }
    if testing.by_role(&harness, .Tooltip).count != 1usize || testing.by_text(&harness, "Saves the file").count != 2usize { os.exit(20i32) }
    let save_button = testing.by_key(&harness, 1u64).element
    let (save_bounds, has_save_bounds) = widget.bounds_of(&runtime, save_button)
    let (tip_bounds, has_tip) = testing.overlay_of(&harness, testing.by_key(&harness, 2u64).element)
    if !has_save_bounds || !has_tip || tip_bounds.y < save_bounds.y + save_bounds.height { os.exit(21i32) }
    // The menu button offers a menu; a tap fires the toggle; open, the menu holds
    // three items (one disabled) under the button and takes the focus.
    let (file_at, has_file) = centre_of(&harness, &runtime, 10u64)
    if !has_file || testing.tap(&harness, file_at.x, file_at.y) != ok || logs[0usize].toggles != 1usize { os.exit(22i32) }
    let (root_3, build_3_error) = build(&frame, &theme, &actions[0usize], &actions[1usize], items[0usize..3usize], buttons[0usize..2usize], true, false)
    if build_3_error != ok { os.exit(23i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(24i32) }
    if testing.by_role(&harness, .MenuItem).count != 3usize || testing.by_role(&harness, .Menu).count != 1usize { os.exit(25i32) }
    let (tree_3, tree_3_error) = testing.semantics(&harness)
    if tree_3_error != ok { os.exit(26i32) }
    let (file_node, has_file_node) = find(tree_3, .Button, "File")
    if !has_file_node || !file_node.state.expanded { os.exit(27i32) }
    let (quit_item, has_quit) = find(tree_3, .MenuItem, "Quit")
    if !has_quit || !quit_item.state.disabled { os.exit(28i32) }
    let file_bounds_found = testing.by_key(&harness, 10u64).element
    let (file_bounds, has_file_bounds) = widget.bounds_of(&runtime, file_bounds_found)
    let (menu_bounds, has_menu_bounds) = testing.overlay_of(&harness, testing.by_key(&harness, 11u64).element)
    if !has_file_bounds || !has_menu_bounds || menu_bounds.y < file_bounds.y + file_bounds.height { os.exit(29i32) }
    // Enter presses the focused first item; Tab then Enter the second; Escape
    // dismisses through the toggle.
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].commands != 1usize || logs[0usize].last_command != 0usize { os.exit(30i32) }
    if testing.tab(&harness, false) != ok || testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].commands != 2usize || logs[0usize].last_command != 1usize { os.exit(31i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].toggles != 2usize { os.exit(32i32) }
    // A press outside dismisses too, and does not reach the save button under it.
    if testing.tap(&harness, save_at.x, save_at.y) != ok || logs[0usize].toggles != 3usize || logs[0usize].saves != 0usize { os.exit(33i32) }
    // The dialog: modal, labelled by its title, described by its message, a heading
    // inside (level 2 since v2, D977); Enter does nothing without a default button,
    // Escape cancels.
    let (root_4, build_4_error) = build(&frame, &theme, &actions[0usize], &actions[1usize], items[0usize..3usize], buttons[0usize..2usize], false, true)
    if build_4_error != ok { os.exit(34i32) }
    if testing.pump(&harness, root_4, now) != ok { os.exit(35i32) }
    let (tree_4, tree_4_error) = testing.semantics(&harness)
    if tree_4_error != ok { os.exit(36i32) }
    let (dialog_node, has_dialog) = find(tree_4, .Dialog, "Delete file?")
    if !has_dialog || !dialog_node.state.modal { os.exit(37i32) }
    if dialog_node.relations.labelled_by.slot == 0u32 && dialog_node.relations.labelled_by.generation == 0u32 { os.exit(38i32) }
    if dialog_node.relations.described_by.slot == 0u32 && dialog_node.relations.described_by.generation == 0u32 { os.exit(39i32) }
    let (heading_node, has_heading) = find(tree_4, .Heading, "Delete file?")
    if !has_heading || heading_node.level != 2u8 { os.exit(40i32) }
    if testing.by_text(&harness, "This cannot be undone.").count != 1usize { os.exit(41i32) }
    // The dialog sits in the middle of the window.
    let (dialog_bounds, has_dialog_bounds) = testing.overlay_of(&harness, testing.by_key(&harness, 20u64).element)
    if !has_dialog_bounds || dialog_bounds.x <= 0.0 || dialog_bounds.x + dialog_bounds.width >= 320.0 { os.exit(42i32) }
    // A tap on the destructive button deletes; Escape cancels; a press outside
    // cancels too.
    let (delete_at, has_delete) = centre_of(&harness, &runtime, 24u64)
    if !has_delete || testing.tap(&harness, delete_at.x, delete_at.y) != ok || logs[0usize].deletes != 1usize { os.exit(43i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].cancels != 1usize { os.exit(44i32) }
    if testing.tap(&harness, 2.0, 318.0) != ok || logs[0usize].cancels != 2usize { os.exit(45i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(46i32) }
    try io.print("ui transient ok\n")
    ret ok
}
