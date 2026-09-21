// `e.ui.control`'s basic choice (D824, widget plan P1-11) under the light theme: a
// select shows its chosen option, a tap asks the caller to open it, the open menu
// lists the options as menu items, a tap on one fires its action and a press
// outside asks to close; a list box shows its rows in a viewport, a tap picks a
// row, the tree marks the selected one, and the wheel brings the hidden rows up.

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
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { open: bool, toggles: usize, colour: usize, picks: usize, fruit: usize, fruit_picks: usize }

fn on_toggle(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.open = !log.open
    log.toggles += 1usize
    ret ok
}

fn on_red(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.colour = 0usize
    log.picks += 1usize
    log.open = false
    ret ok
}

fn on_green(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.colour = 1usize
    log.picks += 1usize
    log.open = false
    ret ok
}

fn on_blue(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.colour = 2usize
    log.picks += 1usize
    log.open = false
    ret ok
}

fn on_fruit_0(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.fruit = 0usize
    log.fruit_picks += 1usize
    ret ok
}

fn on_fruit_1(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.fruit = 1usize
    log.fruit_picks += 1usize
    ret ok
}

fn on_fruit_2(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.fruit = 2usize
    log.fruit_picks += 1usize
    ret ok
}

fn on_fruit_3(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.fruit = 3usize
    log.fruit_picks += 1usize
    ret ok
}

type Actions = struct { toggle: widget.Submit, colours: [3]widget.Submit, fruits: [4]widget.Submit }

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn build(a: *mem.Arena, t: *const control.Theme, actions: *const Actions, log: *const Log) -> (widget.Node, err) {
    let (colours, colours_error) = mem.alloc[str](a, 3usize)
    if colours_error != ok { ret (zero, colours_error) }
    colours[0usize] = "Red"
    colours[1usize] = "Green"
    colours[2usize] = "Blue"
    let (fruits, fruits_error) = mem.alloc[str](a, 4usize)
    if fruits_error != ok { ret (zero, fruits_error) }
    fruits[0usize] = "Apple"
    fruits[1usize] = "Pear"
    fruits[2usize] = "Plum"
    fruits[3usize] = "Fig"
    let (items, items_error) = mem.alloc[widget.Node](a, 2usize)
    if items_error != ok { ret (zero, items_error) }
    let (colour, colour_error) = control.select(a, 1u64, t, "Colour", colours[0usize..3usize], log.colour, log.open, &actions.toggle, actions.colours[..])
    if colour_error != ok { ret (zero, colour_error) }
    items[0usize] = colour
    let (fruit, fruit_error) = control.list_box(a, 10u64, t, "Fruit", fruits[0usize..4usize], log.fruit, actions.fruits[..], 2u32, 120.0)
    if fruit_error != ok { ret (zero, fruit_error) }
    items[1usize] = fruit
    var column = style.defaults()
    column.width = style.Length { Px: 200.0 }
    column.height = style.Length { Px: 240.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, items[0usize..2usize]), ok)
}

fn selected_label(h: *const testing.Harness, role: accessibility.Role) -> (str, bool) {
    let (tree, tree_error) = testing.semantics(h)
    if tree_error != ok { ret ("", false) }
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && tree.nodes[i].state.selected { ret (tree.nodes[i].label, true) }
        i += 1usize
    }
    ret ("", false)
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
    let (h, harness_error) = testing.harness(a, &runtime, 200u32, 240u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (actions, actions_error) = mem.alloc[Actions](a, 1usize)
    if actions_error != ok { os.exit(8i32) }
    var acts: Actions = zero
    acts.toggle = widget.Submit { ctx: ctx, invoke: on_toggle }
    acts.colours[0usize] = widget.Submit { ctx: ctx, invoke: on_red }
    acts.colours[1usize] = widget.Submit { ctx: ctx, invoke: on_green }
    acts.colours[2usize] = widget.Submit { ctx: ctx, invoke: on_blue }
    acts.fruits[0usize] = widget.Submit { ctx: ctx, invoke: on_fruit_0 }
    acts.fruits[1usize] = widget.Submit { ctx: ctx, invoke: on_fruit_1 }
    acts.fruits[2usize] = widget.Submit { ctx: ctx, invoke: on_fruit_2 }
    acts.fruits[3usize] = widget.Submit { ctx: ctx, invoke: on_fruit_3 }
    actions[0usize] = acts
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(9i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_error != ok { os.exit(10i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(11i32) }
    // Closed: the select shows Red and no menu items exist.
    if testing.by_label(&harness, "Red").count == 0usize || testing.by_role(&harness, .MenuItem).count != 0usize { os.exit(12i32) }
    // A tap on the select asks to open; open, three menu items, Red selected.
    let head = testing.by_key(&harness, 1u64).element
    let (head_bounds, has_head) = widget.bounds_of(&runtime, head)
    if !has_head || testing.tap(&harness, head_bounds.x + 4.0, head_bounds.y + 4.0) != ok || logs[0usize].toggles != 1usize || !logs[0usize].open { os.exit(13i32) }
    let (root_2, build_2_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_2_error != ok { os.exit(14i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(15i32) }
    if testing.by_role(&harness, .MenuItem).count != 3usize || testing.by_role(&harness, .Menu).count != 1usize { os.exit(16i32) }
    let (chosen, has_chosen) = selected_label(&harness, .MenuItem)
    if !has_chosen || !same(chosen, "Red") { os.exit(17i32) }
    let (popup_bounds, has_popup) = testing.overlay_of(&harness, testing.by_key(&harness, 2u64).element)
    if !has_popup || !(popup_bounds.y >= head_bounds.y + head_bounds.height) { os.exit(18i32) }
    // A tap on Green picks it and closes; the next frame shows Green.
    let green = testing.by_key(&harness, 4u64).element
    let (green_bounds, has_green) = widget.bounds_of(&runtime, green)
    if !has_green || testing.tap(&harness, green_bounds.x + 4.0, green_bounds.y + 4.0) != ok { os.exit(19i32) }
    if logs[0usize].picks != 1usize || logs[0usize].colour != 1usize || logs[0usize].open { os.exit(20i32) }
    let (root_3, build_3_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_3_error != ok { os.exit(21i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(22i32) }
    if testing.by_label(&harness, "Green").count == 0usize || testing.by_role(&harness, .MenuItem).count != 0usize { os.exit(23i32) }
    // Open again, a press far outside asks to close through the modal's dismiss.
    if testing.tap(&harness, head_bounds.x + 4.0, head_bounds.y + 4.0) != ok || !logs[0usize].open { os.exit(24i32) }
    let (root_4, build_4_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_4_error != ok { os.exit(25i32) }
    if testing.pump(&harness, root_4, now) != ok { os.exit(26i32) }
    if testing.tap(&harness, 190.0, 230.0) != ok || logs[0usize].open || logs[0usize].toggles != 3usize { os.exit(27i32) }
    let (root_5, build_5_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_5_error != ok { os.exit(28i32) }
    if testing.pump(&harness, root_5, now) != ok { os.exit(29i32) }
    // The list box: four items in a two-row viewport, Apple selected; a tap on
    // Pear picks it; the wheel brings Plum and Fig into view.
    if testing.by_role(&harness, .List).count != 1usize || testing.by_role(&harness, .ListItem).count != 4usize { os.exit(30i32) }
    let (first_choice, has_first) = selected_label(&harness, .ListItem)
    if !has_first || !same(first_choice, "Apple") { os.exit(31i32) }
    let pear = testing.by_key(&harness, 12u64).element
    let (pear_bounds, has_pear) = widget.bounds_of(&runtime, pear)
    if !has_pear || !testing.visible(&harness, pear) || testing.visible(&harness, testing.by_key(&harness, 14u64).element) { os.exit(32i32) }
    if testing.tap(&harness, pear_bounds.x + 4.0, pear_bounds.y + 4.0) != ok || logs[0usize].fruit_picks != 1usize || logs[0usize].fruit != 1usize { os.exit(33i32) }
    let (root_6, build_6_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_6_error != ok { os.exit(34i32) }
    if testing.pump(&harness, root_6, now) != ok { os.exit(35i32) }
    let (second_choice, has_second) = selected_label(&harness, .ListItem)
    if !has_second || !same(second_choice, "Pear") { os.exit(36i32) }
    let (view_bounds, has_view) = widget.bounds_of(&runtime, testing.by_key(&harness, 10u64).element)
    if !has_view || testing.wheel(&harness, view_bounds.x + 10.0, view_bounds.y + 10.0, -2i32) != ok { os.exit(37i32) }
    let (root_7, build_7_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_7_error != ok { os.exit(38i32) }
    if testing.pump(&harness, root_7, now) != ok { os.exit(39i32) }
    if !testing.visible(&harness, testing.by_key(&harness, 14u64).element) || testing.visible(&harness, testing.by_key(&harness, 11u64).element) { os.exit(40i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(41i32) }
    try io.print("ui choice ok\n")
    ret ok
}
