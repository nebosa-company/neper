// The v2 document tabs and wizards (D974, widget plan P5-10,
// docs/ux/components/DocumentTabs, Wizard) under the light theme at pointer
// density: a 40 tall strip on `surface-container` with 36 tall tabs 2 apart along
// its bottom, their top corners rounded, the current tab `surface` with the
// active group's 2px `primary` top line, the dirty tab's close slot holding the
// unsaved dot, names carrying the state, and Home, End and Delete; a horizontal
// wizard with its level-1 title, done, current and attention steps named so,
// the connector after a done step 2px `primary`, Cancel at the start and Back
// and Next at the end; a vertical wizard in a dialog on
// `surface-container-high` with Back hidden on the first step; a compact wizard
// under a Back bar with "Step 3 of 3: Deploy", a full progress bar and a
// full-width "Create project".

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
use e.ui.navigation
use e.ui.style
use e.ui.testing
use e.ui.widget

type Counter = struct { count: usize }
type Turned = struct { count: usize, last: usize }
type Moved = struct { count: usize, from: usize, to: usize }

// The counters: 0 back, 1 next, 2 finish, 3 cancel.
type Store = struct { counters: [4]Counter, subs: [4]widget.Submit, picks: Turned, closes: Turned, step_picks: Turned, moves: Moved, documents: [3]navigation.Document, steps: [3]navigation.WizardStep, finishing: bool, dirty: bool, discard_open: bool }

fn on_count(ctx: *void) -> err {
    let c = mem.cast[*Counter](ctx)
    c.count += 1usize
    ret ok
}

fn on_discard(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.discard_open = !s.discard_open
    ret ok
}

fn on_turn(ctx: *void, value: usize) -> err {
    let c = mem.cast[*Turned](ctx)
    c.count += 1usize
    c.last = value
    ret ok
}

fn on_move(ctx: *void, value: navigation.DocumentMove) -> err {
    let c = mem.cast[*Moved](ctx)
    c.count += 1usize
    c.from = value.from
    c.to = value.to
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
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

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let pick = widget.Change[usize] { ctx: mem.cast[*void](&s.picks), invoke: on_turn }
    let close = widget.Change[usize] { ctx: mem.cast[*void](&s.closes), invoke: on_turn }
    let move = widget.Change[navigation.DocumentMove] { ctx: mem.cast[*void](&s.moves), invoke: on_move }
    let (strip, e1) = navigation.document_tabs_marked(a, 5000u64, t, "Open files", s.documents[0usize..3usize], 1usize, pick, close, move, true, true)
    let (page, e2) = control.text(a, 0u64, "Step page", t, control.text_options())
    var across_options = navigation.wizard_options()
    across_options.pressable_steps = true
    across_options.nonlinear = true
    across_options.step = widget.Change[usize] { ctx: mem.cast[*void](&s.step_picks), invoke: on_turn }
    let (across, e3) = navigation.wizard_of(a, 6000u64, t, "Setup", s.steps[0usize..3usize], 1usize, page, &s.subs[0usize], &s.subs[1usize], &s.subs[2usize], &s.subs[3usize], across_options, 600.0, 260.0)
    var down = navigation.wizard_options()
    down.form = .Vertical
    down.dialog = true
    let (column, e4) = navigation.wizard_of(a, 6100u64, t, "Install", s.steps[0usize..3usize], 0usize, page, &s.subs[0usize], &s.subs[1usize], &s.subs[2usize], &s.subs[3usize], down, 600.0, 240.0)
    var small = navigation.wizard_options()
    small.form = .Compact
    small.finish_label = "Create project"
    small.finishing = s.finishing
    small.dirty = s.dirty
    small.discard_open = s.discard_open
    small.request_discard = widget.Submit { ctx: mem.cast[*void](s), invoke: on_discard }
    small.keep_editing = small.request_discard
    let (phone, e5) = navigation.wizard_of(a, 6200u64, t, "New project", s.steps[0usize..3usize], 2usize, page, &s.subs[0usize], &s.subs[1usize], &s.subs[2usize], &s.subs[3usize], small, 360.0, 300.0)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (zero, e1) }
    let (lefts, lefts_error) = mem.alloc[widget.Node](a, 3usize)
    if lefts_error != ok { ret (zero, lefts_error) }
    lefts[0usize] = strip
    lefts[1usize] = across
    lefts[2usize] = column
    let (items, items_error) = mem.alloc[widget.Node](a, 2usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, style.defaults(), lefts[0usize..3usize])
    items[1usize] = phone
    var page_style = style.defaults()
    page_style.width = style.Length { Px: 1000.0 }
    page_style.height = style.Length { Px: 600.0 }
    page_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
    let pad = style.Length { Px: 10.0 }
    page_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 12.0 }, page_style, items[0usize..2usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 1000usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn focusable(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let match = testing.by_key(h, key)
    if match.count != 1usize { ret false }
    let (summary, found) = widget.summary_at(runtime, usize(match.element.slot))
    ret found && summary.focusable
}

fn tap_key(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let (b, found) = bounds(h, runtime, key)
    if !found { ret false }
    ret testing.tap(h, b.x + b.width * 0.5, b.y + b.height * 0.5) == ok
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 600usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 32u16, max_commands: 2048usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 1000u32, 600u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    var i = 0usize
    while i < 4usize {
        s.subs[i] = widget.Submit { ctx: mem.cast[*void](&s.counters[i]), invoke: on_count }
        i += 1usize
    }
    s.documents[0usize] = navigation.Document { key: 1u64, title: "main.e", dirty: false, pinned: true }
    s.documents[1usize] = navigation.Document { key: 2u64, title: "lower.e", dirty: true, pinned: false }
    s.documents[2usize] = navigation.Document { key: 3u64, title: "notes", dirty: false, pinned: false }
    s.steps[0usize] = navigation.WizardStep { label: "Account", note: "", attention: false }
    s.steps[1usize] = navigation.WizardStep { label: "Build", note: "Optional", attention: false }
    s.steps[2usize] = navigation.WizardStep { label: "Deploy", note: "Fix 1 field", attention: true }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    // The strip: 40 on `surface-container`; 36 tall tabs 2 apart from 4 in, along
    // the bottom, at least 96 wide.
    let (strip, has_strip) = bounds(&harness, &runtime, 5000u64)
    let (main_tab, has_main_tab) = bounds(&harness, &runtime, 5001u64)
    let (lower, has_lower) = bounds(&harness, &runtime, 5003u64)
    let (notes, has_notes) = bounds(&harness, &runtime, 5005u64)
    if !has_strip || !has_main_tab || !has_lower || !has_notes || !near(strip.height, 40.0) || !near(lower.height, 36.0) || !near(lower.y, strip.y + 4.0) || !near(main_tab.x, strip.x + 4.0) || !near(lower.x, main_tab.x + main_tab.width + 2.0) || lower.width < 96.0 { os.exit(13i32) }
    let container = style.color(&tokens, .SurfaceContainer)
    if !is_color(shot, at(strip.x + 1.0, strip.y + 2.0), container) || !is_color(shot, at(notes.x + 6.0, notes.y + 18.0), container) { os.exit(14i32) }
    // The current tab: `surface`, the top line `primary`, the corners rounded.
    if !is_color(shot, at(lower.x + 6.0, lower.y + 18.0), style.color(&tokens, .Background)) || !is_color(shot, at(lower.x + 12.0, lower.y + 1.0), style.color(&tokens, .Primary)) || !is_color(shot, at(lower.x, lower.y + 3.0), container) { os.exit(15i32) }
    // The dirty tab's close slot: 24 round, the 8 dot in the title colour; names
    // carry the state; the pinned tab has no close.
    let (slot, has_slot) = bounds(&harness, &runtime, 5004u64)
    if !has_slot || !near(slot.width, 24.0) || !near(slot.height, 24.0) || !is_color(shot, at(slot.x + 12.0, slot.y + 12.0), style.color(&tokens, .OnSurface)) { os.exit(16i32) }
    let (lower_node, has_lower_node) = find(tree, .Tab, "lower.e, unsaved changes")
    let (main_node, has_main_node) = find(tree, .Tab, "main.e, pinned")
    let (close_notes, has_close_notes) = find(tree, .Button, "Close notes")
    if !has_lower_node || !lower_node.state.selected || !has_main_node || !has_close_notes || testing.by_key(&harness, 5002u64).count != 0usize || testing.by_label(&harness, "Close lower.e").count != 1usize { os.exit(17i32) }
    if focusable(&harness, &runtime, 5001u64) || !focusable(&harness, &runtime, 5003u64) || focusable(&harness, &runtime, 5004u64) || focusable(&harness, &runtime, 5005u64) || focusable(&harness, &runtime, 5006u64) { os.exit(33i32) }
    // Presses and keys: notes picks 2, its close reports 2; from the focused
    // strip Delete closes the current (1), Home picks 0 and End 2.
    if testing.tap(&harness, notes.x + 6.0, notes.y + 18.0) != ok || s.picks.last != 2usize || !widget.focus_within(&runtime, 5005u64) || !tap_key(&harness, &runtime, 5006u64) || s.closes.last != 2usize { os.exit(18i32) }
    if testing.press_key(&harness, 46u32, zero) != ok || s.closes.count != 2usize || s.closes.last != 1usize { os.exit(19i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || s.picks.last != 0usize || !widget.focus_within(&runtime, 5001u64) { os.exit(20i32) }
    let (moved, moved_error) = build(&f, &theme, s)
    if moved_error != ok || testing.pump(&harness, moved, time.Instant { nanos: 1100000000i64 }) != ok || !focusable(&harness, &runtime, 5001u64) || focusable(&harness, &runtime, 5003u64) { os.exit(34i32) }
    let (focused_shot, focused_shot_error) = testing.snapshot(&harness, a)
    if focused_shot_error != ok || !is_color(focused_shot, at(main_tab.x + 4.0, main_tab.y + main_tab.height * 0.5), style.color(&tokens, .FocusRing)) { os.exit(55i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || s.picks.last != 2usize || !widget.focus_within(&runtime, 5005u64) { os.exit(35i32) }
    var ctrl: input.Modifiers = zero
    ctrl.control = true
    if testing.press_key(&harness, 34u32, ctrl) != ok || s.picks.last != 2usize || !widget.focus_within(&runtime, 5005u64) { os.exit(36i32) }
    if testing.press_key(&harness, 33u32, ctrl) != ok || s.picks.last != 0usize || !widget.focus_within(&runtime, 5001u64) { os.exit(37i32) }
    ctrl.shift = true
    if testing.press_key(&harness, 33u32, ctrl) != ok || s.moves.count != 1usize || s.moves.from != 1usize || s.moves.to != 0usize || !widget.focus_within(&runtime, 5001u64) { os.exit(38i32) }
    if testing.press_key(&harness, 34u32, ctrl) != ok || s.moves.count != 2usize || s.moves.from != 1usize || s.moves.to != 2usize || !widget.focus_within(&runtime, 5005u64) { os.exit(39i32) }
    // The horizontal wizard: its title a level-1 heading; the steps named with
    // their state; the done marker `primary` and the connector after it 2px
    // `primary`.
    let (across, has_across) = bounds(&harness, &runtime, 6000u64)
    let (title, has_title) = find(tree, .Heading, "Setup")
    let (step_title, has_step_title) = find(tree, .Heading, "Build")
    if !has_across || !has_title || title.level != 1u8 || !has_step_title || step_title.level != 2u8 { os.exit(21i32) }
    let (account, has_account) = find(tree, .ListItem, "Account, completed")
    let (building, has_building) = find(tree, .ListItem, "Build")
    let (deploy, has_deploy) = find(tree, .ListItem, "Deploy, needs attention: Fix 1 field")
    if !has_account || !has_building || !building.state.current || account.state.current || !has_deploy || testing.by_text(&harness, "Optional").count != 2usize { os.exit(22i32) }
    let (build_step, has_build_step) = bounds(&harness, &runtime, 6017u64)
    if !has_build_step || !near(build_step.height, 32.0) || !focusable(&harness, &runtime, 6017u64) || focusable(&harness, &runtime, 6016u64) || focusable(&harness, &runtime, 6018u64) { os.exit(42i32) }
    if !tap_key(&harness, &runtime, 6016u64) || s.step_picks.count != 1usize || s.step_picks.last != 0usize || !widget.focus_within(&runtime, 6016u64) { os.exit(43i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || !widget.focus_within(&runtime, 6017u64) || testing.press_key(&harness, 35u32, zero) != ok || !widget.focus_within(&runtime, 6018u64) { os.exit(44i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || s.step_picks.count != 2usize || s.step_picks.last != 2usize || testing.press_key(&harness, 36u32, zero) != ok || testing.press_key(&harness, 32u32, zero) != ok || s.step_picks.count != 3usize || s.step_picks.last != 0usize { os.exit(45i32) }
    let primary = style.color(&tokens, .Primary)
    if !is_color(shot, at(account.bounds.x + 2.0, account.bounds.y + 12.0), primary) || !is_color(shot, at(account.bounds.x + account.bounds.width + 60.0, account.bounds.y + 16.0), primary) { os.exit(23i32) }
    // The footer: Cancel at the start, Back and Next at the end; Next fires.
    let (cancel, has_cancel) = bounds(&harness, &runtime, 6001u64)
    let (next, has_next) = bounds(&harness, &runtime, 6003u64)
    if !has_cancel || !has_next || !near(cancel.x, across.x + 24.0) || !near(next.x + next.width, across.x + 576.0) || testing.by_key(&harness, 6002u64).count != 1usize { os.exit(24i32) }
    if !tap_key(&harness, &runtime, 6003u64) || s.counters[1usize].count != 1usize { os.exit(25i32) }
    let (focused_step, focused_step_error) = build(&f, &theme, s)
    if focused_step_error != ok || testing.pump(&harness, focused_step, time.Instant { nanos: 1200000000i64 }) != ok || !widget.focus_within(&runtime, 6005u64) { os.exit(40i32) }
    var alt: input.Modifiers = zero
    alt.alt = true
    if testing.press_key(&harness, 66u32, alt) != ok || s.counters[0usize].count != 1usize || testing.press_key(&harness, 78u32, alt) != ok || s.counters[1usize].count != 2usize { os.exit(41i32) }
    // The vertical wizard in a dialog: `surface-container-high`; its steps down
    // the start, 48 apart; Back hidden on the first step.
    let (column, has_column) = bounds(&harness, &runtime, 6100u64)
    if !has_column || !is_color(shot, at(column.x + 400.0, column.y + 120.0), style.color(&tokens, .SurfaceContainerHigh)) || testing.by_key(&harness, 6102u64).count != 0usize || testing.by_key(&harness, 6103u64).count != 1usize { os.exit(26i32) }
    var first_y: f32 = 0.0
    var second_y: f32 = 0.0
    var seen = 0usize
    var k = 0usize
    while k < tree.nodes.len {
        let node = tree.nodes[k]
        if node.role == .ListItem && node.bounds.x < column.x + 240.0 && node.bounds.y > column.y && node.bounds.y < column.y + column.height {
            if seen == 0usize { first_y = node.bounds.y }
            if seen == 1usize { second_y = node.bounds.y }
            seen += 1usize
        }
        k += 1usize
    }
    if seen != 3usize || !near(second_y - first_y, 48.0) { os.exit(27i32) }
    // The compact wizard: a 48 bar led by Back, "Step 3 of 3: Deploy", the bar
    // full, and "Create project" full-width, finishing on a press and on Enter.
    let (bar, has_bar) = bounds(&harness, &runtime, 6206u64)
    let (back, has_back) = find(tree, .Button, "Back")
    if !has_bar || !near(bar.height, 48.0) || !has_back || testing.by_text(&harness, "Step 3 of 3: Deploy").count != 1usize { os.exit(28i32) }
    let (track, has_track) = bounds(&harness, &runtime, 6208u64)
    if !has_track || !near(track.width, 328.0) || !near(track.height, 4.0) || !is_color(shot, at(track.x + 300.0, track.y + 2.0), primary) { os.exit(29i32) }
    let (create, has_create) = bounds(&harness, &runtime, 6204u64)
    let (create_node, has_create_node) = find(tree, .Button, "Create project")
    if !has_create || !has_create_node || !near(create.width, 328.0) || !tap_key(&harness, &runtime, 6204u64) || s.counters[2usize].count != 1usize { os.exit(30i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || s.counters[2usize].count != 2usize || !tap_key(&harness, &runtime, 6207u64) || s.counters[0usize].count != 2usize { os.exit(31i32) }
    // A dirty wizard routes Escape through its discard request. The standard
    // alert keeps editing on Escape or performs the original Cancel on Discard.
    s.dirty = true
    let (dirty, dirty_error) = build(&f, &theme, s)
    if dirty_error != ok || testing.pump(&harness, dirty, time.Instant { nanos: 1250000000i64 }) != ok || testing.press_key(&harness, 27u32, zero) != ok || !s.discard_open || s.counters[3usize].count != 0usize { os.exit(50i32) }
    let (asking, asking_error) = build(&f, &theme, s)
    if asking_error != ok || testing.pump(&harness, asking, time.Instant { nanos: 1260000000i64 }) != ok { os.exit(51i32) }
    let (asking_tree, asking_tree_error) = testing.semantics(&harness)
    let (discard_dialog, has_discard_dialog) = find(asking_tree, .AlertDialog, "Discard New project?")
    if asking_tree_error != ok || !has_discard_dialog || !discard_dialog.state.modal || testing.by_text(&harness, "Your changes will be lost.").count != 1usize || testing.press_key(&harness, 27u32, zero) != ok || s.discard_open { os.exit(52i32) }
    let (kept, kept_error) = build(&f, &theme, s)
    if kept_error != ok || testing.pump(&harness, kept, time.Instant { nanos: 1270000000i64 }) != ok || testing.press_key(&harness, 27u32, zero) != ok || !s.discard_open { os.exit(53i32) }
    let (asked_again, asked_again_error) = build(&f, &theme, s)
    if asked_again_error != ok || testing.pump(&harness, asked_again, time.Instant { nanos: 1280000000i64 }) != ok || !tap_key(&harness, &runtime, 6214u64) || s.counters[3usize].count != 1usize { os.exit(54i32) }
    s.discard_open = false
    s.finishing = true
    let (finishing, finishing_error) = build(&f, &theme, s)
    if finishing_error != ok || testing.pump(&harness, finishing, time.Instant { nanos: 1300000000i64 }) != ok { os.exit(46i32) }
    let (finishing_tree, finishing_tree_error) = testing.semantics(&harness)
    if finishing_tree_error != ok { os.exit(47i32) }
    let (busy_finish, has_busy_finish) = find(finishing_tree, .Button, "Create project")
    if !has_busy_finish || !busy_finish.state.busy || focusable(&harness, &runtime, 6207u64) { os.exit(48i32) }
    if !tap_key(&harness, &runtime, 6204u64) || testing.press_key(&harness, 13u32, zero) != ok || testing.press_key(&harness, 66u32, alt) != ok || s.counters[2usize].count != 2usize || s.counters[0usize].count != 2usize { os.exit(49i32) }
    // (D1233) A secondary press on the notes tab opens its menu: Close to the
    // right has nothing to close; Close others closes lower.e alone (main.e is
    // pinned) and shuts the menu.
    f = mem.arena_from(frame_storage)
    let (tabs_rest, tabs_rest_error) = build(&f, &theme, s)
    if tabs_rest_error != ok || testing.pump(&harness, tabs_rest, time.Instant { nanos: 1300000000i64 }) != ok { os.exit(56i32) }
    let (notes_tab, has_notes_tab) = bounds(&harness, &runtime, 5005u64)
    if !has_notes_tab { os.exit(57i32) }
    var tab_press = testing.pointer_at(notes_tab.x + 10.0, notes_tab.y + 10.0)
    tab_press.buttons = 2u32
    tab_press.changed = .Secondary
    if testing.send(&harness, input.Event { PointerDown: tab_press }) != ok { os.exit(58i32) }
    tab_press.buttons = 0u32
    if testing.send(&harness, input.Event { PointerUp: tab_press }) != ok { os.exit(59i32) }
    f = mem.arena_from(frame_storage)
    let (tabs_menu, tabs_menu_error) = build(&f, &theme, s)
    if tabs_menu_error != ok || testing.pump(&harness, tabs_menu, time.Instant { nanos: 1310000000i64 }) != ok { os.exit(60i32) }
    let (tab_tree, tab_tree_error) = testing.semantics(&harness)
    if tab_tree_error != ok { os.exit(61i32) }
    let (others, has_others) = find(tab_tree, .MenuItem, "Close others")
    let (rightward, has_rightward) = find(tab_tree, .MenuItem, "Close to the right")
    let (saved, has_saved) = find(tab_tree, .MenuItem, "Close saved")
    if !has_others || !has_rightward || !has_saved || others.state.disabled || !rightward.state.disabled || saved.state.disabled { os.exit(62i32) }
    let closes_before = s.closes.count
    if testing.tap(&harness, others.bounds.x + 20.0, others.bounds.y + others.bounds.height * 0.5) != ok || s.closes.count != closes_before + 1usize || s.closes.last != 1usize { os.exit(63i32) }
    f = mem.arena_from(frame_storage)
    let (tabs_shut, tabs_shut_error) = build(&f, &theme, s)
    if tabs_shut_error != ok || testing.pump(&harness, tabs_shut, time.Instant { nanos: 1320000000i64 }) != ok || testing.by_role(&harness, .Menu).count != 0usize { os.exit(64i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(32i32) }
    try io.print("ui navigation5 v2 ok\n")
    ret ok
}
