// `e.ui.control`'s discrete selection (D819, widget plan P1-07) under the light
// theme: a checkbox toggles on a tap and says checked, and mixed, in the tree; a
// radio group marks its selected radio and a tap on another fires that one's
// action; a switch is checked when on, its knob painted at the right; a segmented
// control fills its selected segment and a tap on another fires its action; every
// one is at least the hit target tall.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { checks: usize, checked: bool, picked: usize, picks: usize, on: bool, switches: usize, segment: usize, segments: usize }

fn on_check(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.checks += 1usize
    log.checked = !log.checked
    ret ok
}

fn on_pick_0(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.picked = 0usize
    log.picks += 1usize
    ret ok
}

fn on_pick_1(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.picked = 1usize
    log.picks += 1usize
    ret ok
}

fn on_pick_2(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.picked = 2usize
    log.picks += 1usize
    ret ok
}

fn on_switch(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.on = !log.on
    log.switches += 1usize
    ret ok
}

fn on_segment_0(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.segment = 0usize
    log.segments += 1usize
    ret ok
}

fn on_segment_1(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.segment = 1usize
    log.segments += 1usize
    ret ok
}

type Actions = struct { check: widget.Submit, picks: [3]widget.Submit, switch_it: widget.Submit, segments: [2]widget.Submit }

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn build(a: *mem.Arena, t: *const control.Theme, actions: *const Actions, log: *const Log) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 5usize)
    if items_error != ok { ret (zero, items_error) }
    let (agree, agree_error) = control.checkbox(a, 1u64, t, "Agree", log.checked, false, &actions.check, true)
    if agree_error != ok { ret (zero, agree_error) }
    items[0usize] = agree
    let (some, some_error) = control.checkbox(a, 2u64, t, "Some", false, true, &actions.check, false)
    if some_error != ok { ret (zero, some_error) }
    items[1usize] = some
    let (labels, labels_error) = mem.alloc[str](a, 3usize)
    if labels_error != ok { ret (zero, labels_error) }
    labels[0usize] = "Red"
    labels[1usize] = "Green"
    labels[2usize] = "Blue"
    let (colours, colours_error) = control.radio_group(a, 10u64, t, "Colour", labels[0usize..3usize], log.picked, actions.picks[..], true)
    if colours_error != ok { ret (zero, colours_error) }
    items[2usize] = colours
    let (dark, dark_error) = control.switch_control(a, 20u64, t, "Dark", log.on, &actions.switch_it, true)
    if dark_error != ok { ret (zero, dark_error) }
    items[3usize] = dark
    let (views, views_error) = mem.alloc[str](a, 2usize)
    if views_error != ok { ret (zero, views_error) }
    views[0usize] = "List"
    views[1usize] = "Grid"
    let (view, view_error) = control.segmented_control(a, 30u64, t, "View", views[0usize..2usize], log.segment, actions.segments[..], true)
    if view_error != ok { ret (zero, view_error) }
    items[4usize] = view
    var column = style.defaults()
    column.width = style.Length { Px: 140.0 }
    column.height = style.Length { Px: 300.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, column, items[0usize..5usize]), ok)
}

fn state_of(h: *const testing.Harness, role: accessibility.Role, label: str) -> (accessibility.State, bool) {
    let (tree, tree_error) = testing.semantics(h)
    if tree_error != ok { ret (zero, false) }
    var i = 0usize
    while i < tree.nodes.len {
        let n = tree.nodes[i]
        if n.role == role && n.label.len == label.len {
            var same = true
            var k = 0usize
            while k < label.len {
                if n.label[k] != label[k] { same = false }
                k += 1usize
            }
            if same { ret (n.state, true) }
        }
        i += 1usize
    }
    ret (zero, false)
}

fn tap_key(runtime: *widget.Runtime, h: *testing.Harness, key: widget.Key, code: i32) {
    let (b, has_b) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    if !has_b { os.exit(code) }
    if testing.tap(h, b.x + 4.0, b.y + b.height * 0.5) != ok { os.exit(code) }
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 96usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 10u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 140u32, 300u32, 1.0)
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
    acts.check = widget.Submit { ctx: ctx, invoke: on_check }
    acts.picks[0usize] = widget.Submit { ctx: ctx, invoke: on_pick_0 }
    acts.picks[1usize] = widget.Submit { ctx: ctx, invoke: on_pick_1 }
    acts.picks[2usize] = widget.Submit { ctx: ctx, invoke: on_pick_2 }
    acts.switch_it = widget.Submit { ctx: ctx, invoke: on_switch }
    acts.segments[0usize] = widget.Submit { ctx: ctx, invoke: on_segment_0 }
    acts.segments[1usize] = widget.Submit { ctx: ctx, invoke: on_segment_1 }
    actions[0usize] = acts
    let (frame_storage, storage_error) = mem.alloc[u8](a, 524288usize)
    if storage_error != ok { os.exit(9i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_error != ok { os.exit(10i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(11i32) }
    // The roles: two checkboxes, three radios, a switch, two segment buttons.
    if testing.by_role(&harness, .Checkbox).count != 2usize || testing.by_role(&harness, .Radio).count != 3usize || testing.by_role(&harness, .Switch).count != 1usize || testing.by_role(&harness, .Button).count != 2usize { os.exit(12i32) }
    let (agree_state, has_agree) = state_of(&harness, .Checkbox, "Agree")
    if !has_agree || agree_state.checked { os.exit(13i32) }
    let (some_state, has_some) = state_of(&harness, .Checkbox, "Some")
    if !has_some || !some_state.mixed || !some_state.disabled { os.exit(14i32) }
    // A tap checks the checkbox; the next frame says so.
    tap_key(&runtime, &harness, 1u64, 15i32)
    if logs[0usize].checks != 1usize || !logs[0usize].checked { os.exit(16i32) }
    let (root_2, build_2_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_2_error != ok { os.exit(17i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(18i32) }
    let (agree_2, _) = state_of(&harness, .Checkbox, "Agree")
    if !agree_2.checked { os.exit(19i32) }
    // The radio group: Red is selected; a tap on Green fires its action and the
    // next frame selects it.
    let (red_state, has_red) = state_of(&harness, .Radio, "Red")
    let (green_state, has_green) = state_of(&harness, .Radio, "Green")
    if !has_red || !has_green || !red_state.checked || green_state.checked { os.exit(20i32) }
    tap_key(&runtime, &harness, 12u64, 21i32)
    if logs[0usize].picks != 1usize || logs[0usize].picked != 1usize { os.exit(22i32) }
    let (root_3, build_3_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_3_error != ok { os.exit(23i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(24i32) }
    let (green_2, _) = state_of(&harness, .Radio, "Green")
    let (red_2, _) = state_of(&harness, .Radio, "Red")
    if !green_2.checked || red_2.checked { os.exit(25i32) }
    if testing.by_label(&harness, "Colour").count == 0usize { os.exit(26i32) }
    // The switch: off, then on after a tap, its knob at the right of the track.
    let (dark_state, has_dark) = state_of(&harness, .Switch, "Dark")
    if !has_dark || dark_state.checked { os.exit(27i32) }
    let (switch_bounds, has_switch) = widget.bounds_of(&runtime, testing.by_key(&harness, 20u64).element)
    if !has_switch || !(switch_bounds.height >= tokens.metrics.hit_target) { os.exit(28i32) }
    let (shot_off, shot_off_error) = testing.snapshot(&harness, a)
    if shot_off_error != ok { os.exit(29i32) }
    tap_key(&runtime, &harness, 20u64, 30i32)
    if logs[0usize].switches != 1usize || !logs[0usize].on { os.exit(31i32) }
    let (root_4, build_4_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_4_error != ok { os.exit(32i32) }
    if testing.pump(&harness, root_4, now) != ok { os.exit(33i32) }
    let (dark_2, _) = state_of(&harness, .Switch, "Dark")
    if !dark_2.checked { os.exit(34i32) }
    let (shot_on, shot_on_error) = testing.snapshot(&harness, a)
    if shot_on_error != ok { os.exit(35i32) }
    // The v2 track (D955) is 52 x 32, 4 in from the switch's 60 x 40 box: 12 into
    // it and 4 down, inside the 2px edge and clear of the thumb and its circle, it is
    // the highest container when off and the primary colour when on.
    let track_x = usize(switch_bounds.x + 4.0)
    let track_y = usize(switch_bounds.y + (switch_bounds.height - 40.0) * 0.5 + 4.0)
    let top_px = ((track_y + 4usize) * 140usize + track_x + 12usize) * 4usize
    let primary = style.color(&tokens, .Primary)
    let on_blue = f32(shot_on.pixels[top_px + 2usize])
    let on_red = f32(shot_on.pixels[top_px])
    let off_track = style.color(&tokens, .SurfaceContainerHighest)
    let off_blue = f32(shot_off.pixels[top_px + 2usize])
    if !(off_blue < off_track.blue * 255.0 + 3.0) || !(off_blue > off_track.blue * 255.0 - 3.0) || !(on_blue < primary.blue * 255.0 + 3.0) || !(on_blue > primary.blue * 255.0 - 3.0) || !(on_red < primary.red * 255.0 + 3.0) { os.exit(36i32) }
    // The segmented control: List is selected; a tap on Grid fires its action.
    let (list_state, has_list) = state_of(&harness, .Button, "List")
    let (grid_state, has_grid) = state_of(&harness, .Button, "Grid")
    if !has_list || !has_grid || !list_state.selected || grid_state.selected { os.exit(37i32) }
    tap_key(&runtime, &harness, 32u64, 38i32)
    if logs[0usize].segments != 1usize || logs[0usize].segment != 1usize { os.exit(39i32) }
    let (root_5, build_5_error) = build(&frame, &theme, &actions[0usize], &logs[0usize])
    if build_5_error != ok { os.exit(40i32) }
    if testing.pump(&harness, root_5, now) != ok { os.exit(41i32) }
    let (grid_2, _) = state_of(&harness, .Button, "Grid")
    if !grid_2.selected { os.exit(42i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(43i32) }
    try io.print("ui selection ok\n")
    ret ok
}
