// The v2 dividers, cards, group boxes, disclosure, expander and accordion
// (D965, widget plan P5-08, docs/ux/components) under the light theme at
// pointer density: a divider is a 1px `outline-variant` line, inset by its start;
// a card is `radius-md` with 16 padding, elevated `surface-container-low`, filled
// `surface-container-highest`, selected in a 2px `primary` outline with a 24
// `primary` check disc 8 in from the top end, and a pressable card is a Button
// firing its action; a group box sets its rows 48 tall on `surface` in a 1px
// `outline-variant` edge with a divider between them, 8 under the title, and an
// invalid one wears a 2px `error` edge and asserts its Alert; a collapsible box has an inset-ring title
// Button, summary, trailing chevron and caller-owned body; a disclosure's header
// is 40 tall with the content 40 in and 4 below, Left shutting it; an expander is a 56 header in a
// 1px `outline-variant` edge; an accordion is `surface-container-low` with 48
// headers (64 with a supporting line), several open at once, 1px dividers between
// sections, and Down and End moving focus between headers.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Hit = struct { store: *Store, index: usize }
type Store = struct { hits: [9]u32, targets: [9]Hit, actions: [9]widget.Submit, words: [3]str, lines: [3]str, open: [3]bool, disclosed: bool, group_open: bool }

fn on_hit(ctx: *void) -> err {
    let h = mem.cast[*Hit](ctx)
    h.store.hits[h.index] += 1u32
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
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

fn has_action(node: accessibility.Node, action: accessibility.Action) -> bool {
    var i = 0usize
    while i < node.actions.len {
        if node.actions[i] == action { ret true }
        i += 1usize
    }
    ret false
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
}

fn blank(w: f32, h: f32) -> widget.Node {
    ret widget.box(0u64, control.sized_style(w, h), zero)
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 14usize)
    if items_error != ok { ret (zero, items_error) }
    let (fillers, fillers_error) = mem.alloc[widget.Node](a, 8usize)
    if fillers_error != ok { ret (zero, fillers_error) }
    var i = 0usize
    while i < 8usize {
        fillers[i] = blank(20.0, 10.0)
        i += 1usize
    }
    fillers[3usize] = blank(20.0, 20.0)
    // Dividers: full and inset by 56.
    var full = control.divider_options()
    full.length = 200.0
    let (one, e1) = control.divider_of(a, 10u64, t, full)
    var inset = full
    inset.start = 56.0
    let (two, e2) = control.divider_of(a, 11u64, t, inset)
    // Cards.
    var lifted = control.card_options()
    lifted.width = 120.0
    let (three, e3) = control.card_of(a, 20u64, t, lifted, fillers[0usize..1usize])
    var filled = lifted
    filled.variant = .Filled
    filled.title = "Open"
    filled.description = "Build details"
    filled.action = &s.actions[0usize]
    let (four, e4) = control.card_of(a, 21u64, t, filled, fillers[1usize..2usize])
    var chosen = lifted
    chosen.variant = .Outlined
    chosen.selected = true
    chosen.title = "Selected project"
    chosen.action = &s.actions[0usize]
    chosen.select = &s.actions[7usize]
    chosen.range_select = &s.actions[8usize]
    let (five, e5) = control.card_of(a, 22u64, t, chosen, fillers[3usize..4usize])
    var dragged_options = lifted
    dragged_options.dragged = true
    dragged_options.title = "Dragging"
    dragged_options.action = &s.actions[7usize]
    let (dragged_card, dragged_error) = control.card_of(a, 23u64, t, dragged_options, fillers[2usize..3usize])
    var loading_options = lifted
    loading_options.width = 200.0
    loading_options.loading = true
    loading_options.phase = 0.0 - 1.0
    loading_options.media_height = 48.0
    loading_options.title = "Loading project"
    loading_options.action = &s.actions[7usize]
    let (loading_card, loading_error) = control.card_of(a, 24u64, t, loading_options, fillers[2usize..3usize])
    let (slot_content, slot_content_error) = mem.alloc[widget.Node](a, 1usize)
    let (slot_actions, slot_actions_error) = mem.alloc[widget.Node](a, 1usize)
    if slot_content_error != ok { ret (zero, slot_content_error) }
    if slot_actions_error != ok { ret (zero, slot_actions_error) }
    var media_style = control.sized_style(200.0, 48.0)
    media_style.background = paint.Brush { Solid: style.color(t.tokens, .PrimaryContainer) }
    var slot_button_options = control.button_options()
    slot_button_options.variant = .Plain
    let (slot_action_button, slot_action_error) = control.button(a, 253u64, t, "More", &s.actions[8usize], slot_button_options)
    if slot_action_error != ok { ret (zero, slot_action_error) }
    var slots = control.card_slots()
    slots.media = widget.box(250u64, media_style, zero)
    slots.has_media = true
    slots.header = widget.box(251u64, control.sized_style(20.0, 24.0), zero)
    slots.has_header = true
    slot_content[0usize] = widget.box(252u64, control.sized_style(20.0, 20.0), zero)
    slot_actions[0usize] = slot_action_button
    slots.content = slot_content
    slots.actions = slot_actions
    var slotted_options = lifted
    slotted_options.width = 200.0
    slotted_options.variant = .Outlined
    slotted_options.title = "Release"
    slotted_options.action = &s.actions[0usize]
    let (slotted_card, slotted_error) = control.card_with_slots(a, 25u64, t, slotted_options, slots)
    // Group boxes.
    var boxed = control.group_options()
    boxed.width = 200.0
    let (six, e6) = control.group_box_of(a, 30u64, t, "Build", boxed, fillers[4usize..6usize])
    var wrong = boxed
    wrong.message = "Choose one"
    let (seven, e7) = control.group_box_of(a, 31u64, t, "Targets", wrong, fillers[6usize..7usize])
    let (collapsed_children, collapsed_children_error) = mem.alloc[widget.Node](a, 1usize)
    if collapsed_children_error != ok { ret (zero, collapsed_children_error) }
    collapsed_children[0usize] = widget.box(320u64, control.sized_style(20.0, 10.0), zero)
    var collapsed = boxed
    collapsed.description = "Rare settings"
    collapsed.summary = "4 settings, 1 changed"
    collapsed.expanded = s.group_open
    collapsed.toggle = &s.actions[6usize]
    let (collapsed_group, collapsed_error) = control.group_box_of(a, 32u64, t, "Advanced", collapsed, collapsed_children[0usize..1usize])
    // A disclosure, open; an expander, shut; an accordion with two open.
    let (eight, e8) = control.disclosure(a, 40u64, t, "Details", s.disclosed, &s.actions[1usize], widget.box(45u64, control.sized_style(20.0, 10.0), zero))
    var wide = control.disclosure_options()
    wide.width = 200.0
    let (nine, e9) = control.expander_of(a, 50u64, t, "More", false, &s.actions[2usize], wide, fillers[7usize])
    var folded = control.accordion_options()
    folded.width = 200.0
    folded.supporting = s.lines[0usize..3usize]
    let (contents, contents_error) = mem.alloc[widget.Node](a, 3usize)
    if contents_error != ok { ret (zero, contents_error) }
    contents[0usize] = blank(20.0, 10.0)
    contents[1usize] = blank(20.0, 10.0)
    contents[2usize] = blank(20.0, 10.0)
    let (ten, e10) = control.accordion_of(a, 60u64, t, "Sections", s.words[0usize..3usize], contents[0usize..3usize], s.open[0usize..3usize], s.actions[3usize..6usize], folded)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || dragged_error != ok || loading_error != ok || slotted_error != ok || e6 != ok || e7 != ok || collapsed_error != ok || e8 != ok || e9 != ok || e10 != ok { ret (zero, e1) }
    items[0usize] = one
    items[1usize] = two
    items[2usize] = three
    items[3usize] = four
    items[4usize] = five
    items[5usize] = dragged_card
    items[6usize] = loading_card
    items[7usize] = slotted_card
    items[8usize] = six
    items[9usize] = seven
    items[10usize] = collapsed_group
    items[11usize] = eight
    items[12usize] = nine
    items[13usize] = ten
    var page = style.defaults()
    page.width = style.Length { Px: 300.0 }
    page.height = style.Length { Px: 1250.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..14usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 300usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn focused_is(h: *testing.Harness, key: widget.Key) -> bool {
    let (id, has) = testing.focused(h)
    ret has && id.slot == testing.by_key(h, key).element.slot
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    var tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 240usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 20u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 300u32, 1250u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    var i = 0usize
    while i < 9usize {
        stores[0usize].targets[i] = Hit { store: &stores[0usize], index: i }
        stores[0usize].actions[i] = widget.Submit { ctx: mem.cast[*void](&stores[0usize].targets[i]), invoke: on_hit }
        i += 1usize
    }
    stores[0usize].words[0usize] = "Build"
    stores[0usize].words[1usize] = "Members"
    stores[0usize].words[2usize] = "Access"
    stores[0usize].lines[0usize] = ""
    stores[0usize].lines[1usize] = "4 people"
    stores[0usize].lines[2usize] = ""
    stores[0usize].open[0usize] = true
    stores[0usize].open[2usize] = true
    stores[0usize].disclosed = true
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, &stores[0usize])
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let page = style.color(&tokens, .Background)
    let edge = style.color(&tokens, .OutlineVariant)
    let primary = style.color(&tokens, .Primary)
    // Dividers: 1px of outline-variant; the inset one starts 56 in.
    let (full, has_full) = bounds(&harness, &runtime, 10u64)
    let (inset, has_inset) = bounds(&harness, &runtime, 11u64)
    if !has_full || !has_inset || !near(full.height, 1.0) || !near(full.width, 200.0) { os.exit(12i32) }
    if !is_color(shot, at(full.x + 100.0, full.y + 0.5), edge) || !is_color(shot, at(inset.x + 30.0, inset.y + 0.5), page) || !is_color(shot, at(inset.x + 100.0, inset.y + 0.5), edge) { os.exit(13i32) }
    // Cards: 16 padding, the elevated one surface-container-low, the filled one
    // surface-container-highest, the selected one in the 2px primary outline with
    // its primary check disc 8 in from the top end.
    let (lifted, has_lifted) = bounds(&harness, &runtime, 20u64)
    let (filled, has_filled) = bounds(&harness, &runtime, 21u64)
    let (chosen, has_chosen) = bounds(&harness, &runtime, 22u64)
    let (dragged, has_dragged) = bounds(&harness, &runtime, 23u64)
    if !has_lifted || !has_filled || !has_chosen || !has_dragged || !near(lifted.width, 120.0) || !near(lifted.height, 42.0) || !near(chosen.height, 52.0) { os.exit(14i32) }
    if !is_color(shot, at(lifted.x + 60.0, lifted.y + 21.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(filled.x + 60.0, filled.y + 21.0), style.color(&tokens, .SurfaceContainerHighest)) { os.exit(15i32) }
    if !is_color(shot, at(chosen.x + 1.0, chosen.y + 26.0), primary) || !is_color(shot, at(chosen.x + 60.0, chosen.y + 26.0), page) || !is_color(shot, at(chosen.x + 120.0 - 8.0 - 21.0, chosen.y + 8.0 + 12.0), primary) { os.exit(16i32) }
    if testing.tap(&harness, chosen.x + 20.0, chosen.y + 26.0) != ok || stores[0usize].hits[0usize] != 1u32 || stores[0usize].hits[7usize] != 0u32 || testing.press_key(&harness, 32u32, zero) != ok || stores[0usize].hits[7usize] != 1u32 { os.exit(54i32) }
    let dragged_ground = style.layer(style.color(&tokens, .SurfaceContainerLow), style.color(&tokens, .OnSurface), tokens.states.dragged)
    if !is_color(shot, at(dragged.x + 60.0, dragged.y + 21.0), dragged_ground) || is_color(shot, at(dragged.x + 60.0, dragged.y + dragged.height + 4.0), page) { os.exit(50i32) }
    let (loading, has_loading) = bounds(&harness, &runtime, 24u64)
    if !has_loading || !near(loading.width, 200.0) || !is_color(shot, at(loading.x + 100.0, loading.y + 16.0 + 24.0), style.color(&tokens, .SurfaceContainerHighest)) { os.exit(51i32) }
    let (slotted, has_slotted) = bounds(&harness, &runtime, 25u64)
    let (slot_header, has_slot_header) = bounds(&harness, &runtime, 251u64)
    let (slot_action, has_slot_action) = bounds(&harness, &runtime, 253u64)
    if !has_slotted || !has_slot_header || !has_slot_action || !near(slotted.width, 200.0) || !near(slot_header.x - slotted.x, 16.0) || !near(slot_header.y - slotted.y, 64.0) || !near(slot_action.x + slot_action.width, slotted.x + slotted.width - 16.0) { os.exit(52i32) }
    if !is_color(shot, at(slotted.x + 100.0, slotted.y + 24.0), style.color(&tokens, .PrimaryContainer)) { os.exit(53i32) }
    if testing.hover(&harness, slotted.x + 100.0, slot_header.y + 12.0) != ok { os.exit(61i32) }
    f = mem.arena_from(frame_storage)
    let (parent_hover_root, parent_hover_error) = build(&f, &theme, &stores[0usize])
    if parent_hover_error != ok || testing.pump(&harness, parent_hover_root, time.Instant { nanos: 1010000000i64 }) != ok { os.exit(62i32) }
    let (parent_hover_shot, parent_hover_shot_error) = testing.snapshot(&harness, a)
    if parent_hover_shot_error != ok || !is_color(parent_hover_shot, at(slotted.x + 100.0, slot_header.y + 12.0), style.layer(page, style.color(&tokens, .OnSurface), tokens.states.hover)) { os.exit(63i32) }
    if testing.hover(&harness, slot_action.x + slot_action.width * 0.5, slot_action.y + slot_action.height * 0.5) != ok { os.exit(64i32) }
    f = mem.arena_from(frame_storage)
    let (child_hover_root, child_hover_error) = build(&f, &theme, &stores[0usize])
    if child_hover_error != ok || testing.pump(&harness, child_hover_root, time.Instant { nanos: 1020000000i64 }) != ok { os.exit(65i32) }
    let (child_hover_shot, child_hover_shot_error) = testing.snapshot(&harness, a)
    if child_hover_shot_error != ok || !is_color(child_hover_shot, at(slotted.x + 100.0, slot_header.y + 12.0), page) { os.exit(66i32) }
    // The pressable card is a Button named by its title, and fires on a tap.
    if testing.by_label(&harness, "Open").count != 1usize || testing.by_role(&harness, .Button).count == 0usize { os.exit(17i32) }
    if testing.tap(&harness, filled.x + 60.0, filled.y + 21.0) != ok || stores[0usize].hits[0usize] != 2u32 { os.exit(18i32) }
    // Group boxes: the box 8 under the title, two 48 rows and a 1px divider in a
    // 1px outline-variant edge on surface; the invalid one's edge 2px error.
    let (group, has_group) = bounds(&harness, &runtime, 30u64)
    let (wrong, has_wrong) = bounds(&harness, &runtime, 31u64)
    if !has_group || !has_wrong || !near(group.height, 8.0 + 97.0) || !near(group.width, 200.0) { os.exit(19i32) }
    if !is_color(shot, at(group.x + 0.5, group.y + 8.0 + 24.0), edge) || !is_color(shot, at(group.x + 100.0, group.y + 8.0 + 24.0), page) || !is_color(shot, at(group.x + 100.0, group.y + 8.0 + 48.5), edge) { os.exit(20i32) }
    if !is_color(shot, at(wrong.x + 1.0, wrong.y + 8.0 + 24.0), style.color(&tokens, .Error)) || !near(wrong.height, 8.0 + 48.0 + 8.0 + 16.0) { os.exit(21i32) }
    // Collapsed groups expose a trailing-chevron Button and summary, but no body.
    let (advanced, has_advanced) = bounds(&harness, &runtime, 33u64)
    if !has_advanced || testing.by_text(&harness, "4 settings, 1 changed").count != 1usize || testing.by_key(&harness, 320u64).count != 0usize { os.exit(43i32) }
    let (group_tree, group_tree_error) = testing.semantics(&harness)
    if group_tree_error != ok { os.exit(44i32) }
    var advanced_sem = false
    var invalid_alert = false
    var described_card = false
    var loading_card_busy = false
    var selectable_card = false
    var sem_at = 0usize
    while sem_at < group_tree.nodes.len {
        let node = group_tree.nodes[sem_at]
        if node.role == .Button && same(node.label, "Advanced") {
            advanced_sem = !node.state.expanded && has_action(node, .Expand)
        }
        if node.role == .Alert && same(node.label, "Choose one") {
            invalid_alert = node.state.invalid && node.live == .Assertive
        }
        if node.role == .Button && same(node.label, "Open") { described_card = same(node.hint, "Build details") }
        if node.role == .Button && same(node.label, "Selected project") { selectable_card = node.state.selected && has_action(node, .Select) }
        if node.role == .Group && same(node.label, "Loading project") { loading_card_busy = node.state.busy }
        sem_at += 1usize
    }
    if widget.semantic_action(&runtime, testing.by_label(&harness, "Selected project").element, accessibility.ACTION_SELECT) != ok || stores[0usize].hits[7usize] != 2u32 { os.exit(55i32) }
    var command: input.Modifiers = zero
    command.control = true
    if testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 17u32, logical: 17u32 }, modifiers: command, repeat: false } }) != ok || testing.tap(&harness, chosen.x + 20.0, chosen.y + 26.0) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 17u32, logical: 17u32 }, modifiers: zero, repeat: false } }) != ok || stores[0usize].hits[7usize] != 3u32 { os.exit(56i32) }
    var shifted: input.Modifiers = zero
    shifted.shift = true
    if testing.send(&harness, input.Event { KeyDown: input.KeyEvent { window: zero, key: input.Key { physical: 16u32, logical: 16u32 }, modifiers: shifted, repeat: false } }) != ok || testing.tap(&harness, chosen.x + 20.0, chosen.y + 26.0) != ok || testing.send(&harness, input.Event { KeyUp: input.KeyEvent { window: zero, key: input.Key { physical: 16u32, logical: 16u32 }, modifiers: zero, repeat: false } }) != ok || stores[0usize].hits[8usize] != 1u32 { os.exit(57i32) }
    var touch = testing.pointer_at(chosen.x + 20.0, chosen.y + 26.0)
    touch.kind = .Touch
    if testing.send(&harness, input.Event { PointerDown: touch }) != ok || testing.begin(&harness, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(58i32) }
    f = mem.arena_from(frame_storage)
    let (hold_start, hold_start_error) = build(&f, &theme, &stores[0usize])
    if hold_start_error != ok || testing.pump(&harness, hold_start, time.Instant { nanos: 1100000000i64 }) != ok || testing.begin(&harness, time.Instant { nanos: 1700000000i64 }) != ok { os.exit(59i32) }
    f = mem.arena_from(frame_storage)
    let (hold_end, hold_end_error) = build(&f, &theme, &stores[0usize])
    if hold_end_error != ok || testing.pump(&harness, hold_end, time.Instant { nanos: 1700000000i64 }) != ok || testing.send(&harness, input.Event { PointerUp: touch }) != ok || stores[0usize].hits[7usize] != 4u32 { os.exit(60i32) }
    if !advanced_sem || !invalid_alert || !described_card || !loading_card_busy || !selectable_card || testing.by_label(&harness, "Loading project").count != 1usize || testing.tap(&harness, advanced.x + 100.0, advanced.y + advanced.height * 0.5) != ok || stores[0usize].hits[6usize] != 1u32 { os.exit(45i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || stores[0usize].hits[6usize] != 2u32 { os.exit(46i32) }
    // The disclosure: a 40 header, the content 40 in and 4 below; open, the
    // header says expanded, and Left on it (focused by the tap) shuts it.
    let (head, has_head) = bounds(&harness, &runtime, 40u64)
    let (shown, has_shown) = bounds(&harness, &runtime, 45u64)
    if !has_head || !has_shown || !near(head.height, 40.0) || !near(shown.x - head.x, 40.0) || !near(shown.y - head.y, 44.0) { os.exit(22i32) }
    if testing.tap(&harness, head.x + 10.0, head.y + 20.0) != ok || stores[0usize].hits[1usize] != 1u32 { os.exit(23i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || stores[0usize].hits[1usize] != 2u32 { os.exit(24i32) }
    // The expander: a 56 header 200 wide inside a 1px outline-variant edge.
    let (more, has_more) = bounds(&harness, &runtime, 50u64)
    if !has_more || !near(more.height, 56.0) || !near(more.width, 200.0) { os.exit(25i32) }
    if !is_color(shot, at(more.x + 0.5, more.y + 28.0), edge) { os.exit(26i32) }
    // The accordion: surface-container-low, a 48 header, the second 64 with its
    // supporting line after the first's open content and a 1px divider.
    let (first, has_first) = bounds(&harness, &runtime, 61u64)
    let (second, has_second) = bounds(&harness, &runtime, 63u64)
    let (third, has_third) = bounds(&harness, &runtime, 65u64)
    let (inside, has_inside) = bounds(&harness, &runtime, 66u64)
    if !has_first || !has_second || !has_third || !has_inside || !near(first.height, 48.0) || !near(second.height, 64.0) || !near(first.width, 200.0) { os.exit(27i32) }
    if !near(second.y - first.y, 48.0 + 26.0 + 1.0) || !near(inside.y - third.y, 48.0) || testing.by_key(&harness, 64u64).count != 0usize { os.exit(28i32) }
    if !is_color(shot, at(first.x + 100.0, first.y + 24.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(first.x + 100.0, second.y - 0.5), edge) { os.exit(29i32) }
    // A tap on the second header fires its toggle; Down moves focus to the third,
    // Home to the first.
    if testing.tap(&harness, second.x + 100.0, second.y + 32.0) != ok || stores[0usize].hits[4usize] != 1u32 { os.exit(30i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focused_is(&harness, 65u64) { os.exit(31i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !focused_is(&harness, 61u64) { os.exit(32i32) }
    // The caller's next frame opens the controlled box and swaps Expand for Collapse.
    stores[0usize].group_open = true
    f = mem.arena_from(frame_storage)
    let (group_open_root, group_open_error) = build(&f, &theme, &stores[0usize])
    if group_open_error != ok || testing.pump(&harness, group_open_root, time.Instant { nanos: 2000000000i64 }) != ok || testing.by_key(&harness, 320u64).count != 1usize { os.exit(47i32) }
    let (open_tree, open_tree_error) = testing.semantics(&harness)
    if open_tree_error != ok { os.exit(48i32) }
    advanced_sem = false
    sem_at = 0usize
    while sem_at < open_tree.nodes.len {
        let node = open_tree.nodes[sem_at]
        if node.role == .Button && same(node.label, "Advanced") {
            advanced_sem = node.state.expanded && has_action(node, .Collapse)
        }
        sem_at += 1usize
    }
    if !advanced_sem { os.exit(49i32) }
    // Horizontal start/end insets follow reading direction: the 56px blank
    // moves from the left edge to the right edge in RTL.
    tokens.direction = .RightToLeft
    stores[0usize].group_open = false
    stores[0usize].disclosed = false
    f = mem.arena_from(frame_storage)
    let (rtl_root, rtl_build_error) = build(&f, &theme, &stores[0usize])
    if rtl_build_error != ok { os.exit(34i32) }
    if testing.pump(&harness, rtl_root, time.Instant { nanos: 2500000000i64 }) != ok { os.exit(35i32) }
    let (rtl_shot, rtl_shot_error) = testing.snapshot(&harness, a)
    if rtl_shot_error != ok { os.exit(36i32) }
    let (rtl_inset, has_rtl_inset) = bounds(&harness, &runtime, 11u64)
    if !has_rtl_inset || !is_color(rtl_shot, at(rtl_inset.x + 30.0, rtl_inset.y + 0.5), edge) || !is_color(rtl_shot, at(rtl_inset.x + 170.0, rtl_inset.y + 0.5), page) { os.exit(37i32) }
    // In RTL Left opens the shut Disclosure and Right does nothing; once open,
    // Right closes it. The caller still owns the state between frames.
    let (rtl_head, has_rtl_head) = bounds(&harness, &runtime, 40u64)
    if !has_rtl_head || testing.tap(&harness, rtl_head.x + 20.0, rtl_head.y + 20.0) != ok || stores[0usize].hits[1usize] != 3u32 { os.exit(38i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || stores[0usize].hits[1usize] != 3u32 { os.exit(39i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || stores[0usize].hits[1usize] != 4u32 { os.exit(40i32) }
    stores[0usize].disclosed = true
    let (rtl_open, rtl_open_error) = build(&f, &theme, &stores[0usize])
    if rtl_open_error != ok || testing.pump(&harness, rtl_open, time.Instant { nanos: 3500000000i64 }) != ok { os.exit(41i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || stores[0usize].hits[1usize] != 5u32 { os.exit(42i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(33i32) }
    try io.print("ui containers v2 ok\n")
    ret ok
}
