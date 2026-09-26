// The v2 destination bar and navigation drawers (D973, widget plan P5-10,
// docs/ux/components/DestinationBar, NavigationDrawer) under the light theme at
// pointer density: the bar 80 tall on `surface-container` sharing its width, the
// active icon in a 64 x 32 `secondary-container` pill, badges in the names and
// Current on the active tab; the rail on `surface` with 56 x 32 pills 12 apart;
// the sidebar on `surface-container-low` with 40 tall fully rounded rows, a
// divider and a section heading; the standard drawer's header and rows; the
// modal drawer 300 wide at the window's start on `surface-container-low` with
// rounded end corners over a 32% scrim, 56 tall rows picking and Escape
// dismissing.

use e.gpu
use e.ui.input
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
use e.ui.layout as ui_layout
use e.ui.navigation
use e.ui.style
use e.ui.testing
use e.ui.widget

type Counter = struct { count: usize }

// The counters: 0-2 picks by index, 3 dismiss.
type Store = struct { counters: [4]Counter, picks: [3]widget.Submit, dismiss: widget.Submit, places: [3]navigation.Destination, rows: [3]navigation.Destination }

fn on_count(ctx: *void) -> err {
    let c = mem.cast[*Counter](ctx)
    c.count += 1usize
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

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store, open: bool) -> (widget.Node, err) {
    let (bar, e1) = navigation.destination_bar_of(a, 3000u64, t, s.places[0usize..3usize], 0usize, s.picks[0usize..3usize], .Bottom, 400.0)
    let (rail, e2) = navigation.destination_bar_of(a, 3100u64, t, s.places[0usize..3usize], 1usize, s.picks[0usize..3usize], .Rail, 80.0)
    let (side, e3) = navigation.destination_bar_of(a, 3200u64, t, s.rows[0usize..3usize], 0usize, s.picks[0usize..3usize], .Sidebar, 260.0)
    let (standard, e4) = navigation.navigation_drawer_standard(a, 3300u64, t, "Workspace", s.rows[0usize..2usize], 1usize, s.picks[0usize..2usize], 240.0, 200.0)
    let (modal, e5) = navigation.navigation_drawer_of(a, 3400u64, t, "neper", s.rows[0usize..3usize], 0usize, s.picks[0usize..3usize], open, &s.dismiss, 300.0)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (zero, e1) }
    let (lower, lower_error) = mem.alloc[widget.Node](a, 3usize)
    if lower_error != ok { ret (zero, lower_error) }
    lower[0usize] = rail
    lower[1usize] = side
    lower[2usize] = standard
    let (items, items_error) = mem.alloc[widget.Node](a, 3usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = bar
    items[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 12.0 }, style.defaults(), lower[0usize..3usize])
    items[2usize] = modal
    var page_style = style.defaults()
    page_style.width = style.Length { Px: 640.0 }
    page_style.height = style.Length { Px: 520.0 }
    page_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
    let pad = style.Length { Px: 10.0 }
    page_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page_style, items[0usize..3usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 640usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

// (D1269) The width a sash reported last.
fn on_width(ctx: *void, value: f32) -> err {
    let width = mem.cast[*f32](ctx)
    *width = value
    ret ok
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 600usize, max_states: 64usize, state_bytes: 4096usize, state_classes: 32u16, max_depth: 32u16, max_commands: 2048usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 520u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    var i = 0usize
    while i < 3usize {
        s.picks[i] = widget.Submit { ctx: mem.cast[*void](&s.counters[i]), invoke: on_count }
        i += 1usize
    }
    s.dismiss = widget.Submit { ctx: mem.cast[*void](&s.counters[3usize]), invoke: on_count }
    s.places[0usize] = navigation.destination("Search")
    s.places[0usize].glyph = .Search
    s.places[0usize].pictured = true
    s.places[1usize] = navigation.destination("People")
    s.places[1usize].glyph = .Person
    s.places[1usize].pictured = true
    s.places[1usize].badge = "3"
    s.places[2usize] = navigation.destination("Calendar")
    s.places[2usize].glyph = .Calendar
    s.places[2usize].pictured = true
    s.places[2usize].dot = true
    s.rows[0usize] = navigation.destination("Inbox")
    s.rows[0usize].badge = "12"
    s.rows[1usize] = navigation.destination("Sent")
    s.rows[2usize] = navigation.destination("Design")
    s.rows[2usize].section = "Teams"
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s, false)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    // The bar: 80 on `surface-container`, three cells sharing 384 from 8 in, the
    // active pill `secondary-container`, the others clear.
    let (bar, has_bar) = bounds(&harness, &runtime, 3000u64)
    let (search, has_search) = bounds(&harness, &runtime, 3001u64)
    let (people, has_people) = bounds(&harness, &runtime, 3002u64)
    if !has_bar || !has_search || !has_people || !near(bar.height, 80.0) || !near(search.x, bar.x + 8.0) || !near(search.y, bar.y + 12.0) || !near(search.width, 128.0) || !near(people.x, search.x + 128.0) { os.exit(13i32) }
    if !is_color(shot, at(bar.x + 3.0, bar.y + 40.0), style.color(&tokens, .SurfaceContainer)) || !is_color(shot, at(search.x + 38.0, search.y + 16.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(people.x + 38.0, people.y + 16.0), style.color(&tokens, .SurfaceContainer)) { os.exit(14i32) }
    // Names carry the badges; the active tab is Selected and Current.
    let (search_node, has_search_node) = find(tree, .Tab, "Search")
    let (people_node, has_people_node) = find(tree, .Tab, "People, 3")
    let (calendar_node, has_calendar_node) = find(tree, .Tab, "Calendar, new")
    let (main_list, has_main) = find(tree, .TabList, "Main")
    if !has_search_node || !search_node.state.selected || !search_node.state.current || !has_people_node || people_node.state.current || !has_calendar_node || !has_main { os.exit(15i32) }
    if !focusable(&harness, &runtime, 3001u64) || focusable(&harness, &runtime, 3002u64) || focusable(&harness, &runtime, 3003u64) { os.exit(35i32) }
    if !focusable(&harness, &runtime, 3102u64) || focusable(&harness, &runtime, 3101u64) || focusable(&harness, &runtime, 3103u64) { os.exit(36i32) }
    if !focusable(&harness, &runtime, 3201u64) || focusable(&harness, &runtime, 3202u64) || focusable(&harness, &runtime, 3203u64) { os.exit(37i32) }
    if !tap_key(&harness, &runtime, 3002u64) || s.counters[1usize].count != 1usize || !widget.focus_within(&runtime, 3002u64) { os.exit(16i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || !widget.focus_within(&runtime, 3003u64) { os.exit(38i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !widget.focus_within(&runtime, 3001u64) { os.exit(39i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || testing.press_key(&harness, 32u32, zero) != ok || s.counters[0usize].count != 2usize { os.exit(45i32) }
    var ctrl: input.Modifiers = zero
    ctrl.control = true
    if testing.press_key(&harness, 51u32, ctrl) != ok || s.counters[2usize].count != 1usize || !widget.focus_within(&runtime, 3003u64) { os.exit(46i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 3102u64).element) != ok || testing.press_key(&harness, 38u32, zero) != ok || !widget.focus_within(&runtime, 3101u64) { os.exit(40i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !widget.focus_within(&runtime, 3103u64) { os.exit(41i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 3201u64).element) != ok || testing.press_key(&harness, 40u32, zero) != ok || !widget.focus_within(&runtime, 3202u64) { os.exit(42i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !widget.focus_within(&runtime, 3203u64) { os.exit(43i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 3002u64).element) != ok { os.exit(44i32) }
    // The rail: 80 wide on `surface`, 56 tall cells 12 apart from 16 down, the
    // active (second) pill `secondary-container`.
    let (rail, has_rail) = bounds(&harness, &runtime, 3100u64)
    let (first_cell, has_first_cell) = bounds(&harness, &runtime, 3101u64)
    let (second_cell, has_second_cell) = bounds(&harness, &runtime, 3102u64)
    if !has_rail || !has_first_cell || !has_second_cell || !near(rail.width, 80.0) || !near(first_cell.y, rail.y + 16.0) || !near(first_cell.height, 56.0) || !near(second_cell.y, first_cell.y + 68.0) { os.exit(17i32) }
    if !is_color(shot, at(rail.x + 40.0, rail.y + 8.0), style.color(&tokens, .Background)) || !is_color(shot, at(rail.x + 14.0, second_cell.y + 16.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(rail.x + 14.0, first_cell.y + 16.0), style.color(&tokens, .Background)) { os.exit(18i32) }
    // The sidebar: `surface-container-low`, 12 in; 40 tall full-width rows, the
    // active one `secondary-container`; a divider and the Teams heading before
    // Design.
    let (side, has_side) = bounds(&harness, &runtime, 3200u64)
    let (inbox, has_inbox) = bounds(&harness, &runtime, 3201u64)
    let (sent, has_sent) = bounds(&harness, &runtime, 3202u64)
    let (design, has_design) = bounds(&harness, &runtime, 3203u64)
    if !has_side || !has_inbox || !has_sent || !has_design || !near(inbox.x, side.x + 12.0) || !near(inbox.y, side.y + 12.0) || !near(inbox.height, 40.0) || !near(inbox.width, 236.0) { os.exit(19i32) }
    if !is_color(shot, at(side.x + 4.0, side.y + 4.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(inbox.x + 118.0, inbox.y + 20.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(sent.x + 118.0, sent.y + 20.0), style.color(&tokens, .SurfaceContainerLow)) { os.exit(20i32) }
    let (teams, has_teams) = find(tree, .Heading, "Teams")
    let (inbox_node, has_inbox_node) = find(tree, .Tab, "Inbox, 12")
    if !has_teams || !has_inbox_node || !near(design.y, sent.y + 81.0) || !is_color(shot, at(sent.x + 40.0, sent.y + 48.5), style.color(&tokens, .OutlineVariant)) { os.exit(21i32) }
    // The standard drawer: `surface-container-low` 8 in, its header over 40 tall
    // rows 12 in, Sent active; a group named Main.
    let (standard, has_standard) = bounds(&harness, &runtime, 3300u64)
    let (row, has_row) = bounds(&harness, &runtime, 3303u64)
    if !has_standard || !has_row || !near(standard.width, 240.0) || !near(row.x, standard.x + 8.0) || !near(row.y, standard.y + 60.0) || !near(row.height, 40.0) || testing.by_text(&harness, "Workspace").count != 1usize { os.exit(22i32) }
    if !is_color(shot, at(row.x + 100.0, row.y + 20.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(standard.x + 4.0, standard.y + 150.0), style.color(&tokens, .SurfaceContainerLow)) { os.exit(23i32) }
    if !focusable(&harness, &runtime, 3303u64) || focusable(&harness, &runtime, 3302u64) { os.exit(47i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 3303u64).element) != ok || testing.press_key(&harness, 38u32, zero) != ok || !widget.focus_within(&runtime, 3302u64) { os.exit(48i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !widget.focus_within(&runtime, 3303u64) || testing.press_key(&harness, 36u32, zero) != ok || !widget.focus_within(&runtime, 3302u64) { os.exit(49i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 3002u64).element) != ok { os.exit(50i32) }
    // The modal drawer open: 300 wide at the start, its end corners rounded, over
    // the scrim; 56 tall rows; Sent picks, Escape dismisses.
    let (root_2, build_2_error) = build(&f, &theme, s, true)
    if build_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(24i32) }
    let (drawer_focus, has_drawer_focus) = testing.focused(&harness)
    if !has_drawer_focus || drawer_focus.slot != testing.by_key(&harness, 3402u64).element.slot { os.exit(32i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !widget.focus_within(&runtime, 3403u64) || testing.press_key(&harness, 35u32, zero) != ok || !widget.focus_within(&runtime, 3404u64) { os.exit(51i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || s.counters[2usize].count != 2usize || s.counters[3usize].count != 1usize || testing.press_key(&harness, 36u32, zero) != ok || !widget.focus_within(&runtime, 3402u64) { os.exit(52i32) }
    if testing.press_key(&harness, 83u32, zero) != ok || !widget.focus_within(&runtime, 3403u64) || testing.press_key(&harness, 68u32, zero) != ok || !widget.focus_within(&runtime, 3404u64) { os.exit(53i32) }
    if testing.press_key(&harness, 73u32, zero) != ok || !widget.focus_within(&runtime, 3402u64) { os.exit(54i32) }
    let (shot_2, shot_2_error) = testing.snapshot(&harness, a)
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if shot_2_error != ok || tree_2_error != ok { os.exit(25i32) }
    let (drawer_node, has_drawer_node) = find(tree_2, .Dialog, "Navigation")
    let (drawer, has_drawer) = testing.overlay_of(&harness, testing.by_key(&harness, 3400u64).element)
    if !has_drawer_node || !drawer_node.state.modal || !has_drawer || !near(drawer.x, 0.0) || !near(drawer.width, 300.0) { os.exit(26i32) }
    let low = style.color(&tokens, .SurfaceContainerLow)
    if !is_color(shot_2, at(drawer.x + 4.0, drawer.y + 300.0), low) || is_color(shot_2, at(drawer.x + drawer.width - 1.5, drawer.y + 1.5), low) { os.exit(27i32) }
    let under = style.color(&tokens, .SurfaceContainerHighest)
    let dim = style.color(&tokens, .Scrim)
    let k = tokens.states.scrim
    let dimmed = paint.Color { red: under.red * (1.0 - k) + dim.red * k, green: under.green * (1.0 - k) + dim.green * k, blue: under.blue * (1.0 - k) + dim.blue * k, alpha: 1.0 }
    if !is_color(shot_2, at(630.0, 510.0), dimmed) { os.exit(28i32) }
    let (sent_row, has_sent_row) = bounds(&harness, &runtime, 3403u64)
    if !has_sent_row || !near(sent_row.height, 56.0) || !near(sent_row.width, 276.0) || testing.by_text(&harness, "neper").count != 1usize { os.exit(29i32) }
    if !tap_key(&harness, &runtime, 3403u64) || s.counters[1usize].count != 2usize || s.counters[3usize].count != 2usize || testing.press_key(&harness, 27u32, zero) != ok || s.counters[3usize].count != 3usize { os.exit(30i32) }
    let (root_3, build_3_error) = build(&f, &theme, s, false)
    if build_3_error != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1200000000i64 }) != ok { os.exit(33i32) }
    let (returned_focus, has_returned_focus) = testing.focused(&harness)
    if !has_returned_focus || returned_focus.slot != testing.by_key(&harness, 3002u64).element.slot { os.exit(34i32) }
    // In a right-to-left theme the modal drawer moves to the physical right and
    // rounds only its open, left corners.
    var rtl_tokens = style.reference(.Light)
    rtl_tokens.direction = .RightToLeft
    let rtl_theme = control.Theme { tokens: &rtl_tokens, fonts: fonts, language: "", runtime: &runtime }
    let (root_4, build_4_error) = build(&f, &rtl_theme, s, true)
    if build_4_error != ok || testing.pump(&harness, root_4, time.Instant { nanos: 1300000000i64 }) != ok { os.exit(55i32) }
    let (shot_4, shot_4_error) = testing.snapshot(&harness, a)
    let (rtl_drawer, has_rtl_drawer) = testing.overlay_of(&harness, testing.by_key(&harness, 3400u64).element)
    if shot_4_error != ok || !has_rtl_drawer || !near(rtl_drawer.x, 340.0) || !near(rtl_drawer.width, 300.0) { os.exit(56i32) }
    if !is_color(shot_4, at(rtl_drawer.x + rtl_drawer.width - 4.0, rtl_drawer.y + 300.0), low) || is_color(shot_4, at(rtl_drawer.x + 1.5, rtl_drawer.y + 1.5), low) { os.exit(57i32) }
    // (D1266) The rail's menu button and FAB stand above its destinations and the
    // menu opens the drawer; the sidebar leads with its header.
    var rail_extras: navigation.DestinationExtras = zero
    rail_extras.menu = &s.dismiss
    rail_extras.fab = widget.box(3590u64, control.sized_style(56.0, 56.0), zero)
    rail_extras.has_fab = true
    var side_extras: navigation.DestinationExtras = zero
    side_extras.header = "neper workspace"
    f = mem.arena_from(frame_storage)
    let (extra_rail, extra_rail_error) = navigation.destination_bar_with(&f, 3500u64, &theme, s.places[0usize..3usize], 0usize, s.picks[0usize..3usize], .Rail, 80.0, rail_extras)
    let (extra_side, extra_side_error) = navigation.destination_bar_with(&f, 3600u64, &theme, s.rows[0usize..3usize], 0usize, s.picks[0usize..3usize], .Sidebar, 260.0, side_extras)
    let (extra_parts, extra_parts_error) = mem.alloc[widget.Node](&f, 2usize)
    if extra_rail_error != ok || extra_side_error != ok || extra_parts_error != ok { os.exit(58i32) }
    extra_parts[0usize] = extra_rail
    extra_parts[1usize] = extra_side
    var extra_page = control.sized_style(600.0, 600.0)
    extra_page.background = paint.Brush { Solid: style.color(&tokens, .Background) }
    if testing.pump(&harness, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 0.0 }, extra_page, extra_parts[0usize..2usize]), time.Instant { nanos: 5000000000i64 }) != ok { os.exit(59i32) }
    let (menu_box, has_menu_box) = bounds(&harness, &runtime, 7596u64)
    let (fab_box, has_fab_box) = bounds(&harness, &runtime, 3590u64)
    let (first_place, has_first_place) = bounds(&harness, &runtime, 3501u64)
    if !has_menu_box || !has_fab_box || !has_first_place || !(menu_box.y < fab_box.y) || !(fab_box.y + fab_box.height <= first_place.y) { os.exit(60i32) }
    let dismissals = s.counters[3usize].count
    if testing.tap(&harness, menu_box.x + menu_box.width * 0.5, menu_box.y + menu_box.height * 0.5) != ok || s.counters[3usize].count != dismissals + 1usize { os.exit(61i32) }
    if testing.by_text(&harness, "neper workspace").count == 0usize { os.exit(62i32) }
    let (extra_tree, extra_tree_error) = testing.semantics(&harness)
    let (_, has_open_nav) = find(extra_tree, .Button, "Open navigation")
    if extra_tree_error != ok || !has_open_nav { os.exit(63i32) }
    // (D1269) The standard drawer hidden is nothing wide, as a rail 80, and shown
    // with its sash: Right on the focused sash widens it 8.
    var drawer_width: f32 = 0.0
    let drawer_resize = widget.Change[f32] { ctx: mem.cast[*void](&drawer_width), invoke: on_width }
    var drawer_step = 0usize
    while drawer_step < 3usize {
        var drawer_state: navigation.DrawerState = .Hidden
        if drawer_step == 1usize { drawer_state = .Rail }
        if drawer_step == 2usize { drawer_state = .Shown }
        f = mem.arena_from(frame_storage)
        let (standard_drawer, standard_error) = navigation.navigation_drawer_standard_with(&f, 3700u64, &theme, "Workspace", s.rows[0usize..2usize], 0usize, s.picks[0usize..2usize], 240.0, 300.0, drawer_state, drawer_resize)
        let (standard_page, standard_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if standard_error != ok || standard_page_error != ok { os.exit(64i32) }
        standard_page[0usize] = standard_drawer
        if testing.pump(&harness, widget.box(0u64, control.sized_style(600.0, 600.0), standard_page[0usize..1usize]), time.Instant { nanos: 5100000000i64 + i64(drawer_step) }) != ok { os.exit(65i32) }
        let (standard_box, has_standard_box) = bounds(&harness, &runtime, 3700u64)
        if drawer_step == 0usize && (!has_standard_box || !near(standard_box.width, 0.0)) { os.exit(66i32) }
        if drawer_step == 1usize && (!has_standard_box || !near(standard_box.width, 80.0)) { os.exit(67i32) }
        if drawer_step == 2usize {
            let (_, has_sash) = bounds(&harness, &runtime, 3700u64 + 4096u64 + 2u64)
            if !has_sash || widget.focus(&runtime, testing.by_key(&harness, 3700u64 + 4096u64 + 2u64).element) != ok || testing.press_key(&harness, 39u32, zero) != ok || !near(drawer_width, 248.0) { os.exit(68i32) }
        }
        drawer_step += 1usize
    }
    // (D1270) A drag from the start edge opens the drawer; a short one does not.
    f = mem.arena_from(frame_storage)
    let (edged, edged_error) = navigation.drawer_edge_swipe(&f, 3800u64, &theme, widget.box(0u64, control.sized_style(400.0, 300.0), zero), s.dismiss, 400.0, 300.0)
    if edged_error != ok || testing.pump(&harness, edged, time.Instant { nanos: 5200000000i64 }) != ok { os.exit(69i32) }
    let swipes_before = s.counters[3usize].count
    if testing.drag(&harness, geometry.Point { x: 5.0, y: 100.0 }, geometry.Point { x: 40.0, y: 100.0 }, 4usize) != ok || s.counters[3usize].count != swipes_before { os.exit(70i32) }
    if testing.drag(&harness, geometry.Point { x: 5.0, y: 100.0 }, geometry.Point { x: 120.0, y: 100.0 }, 6usize) != ok || s.counters[3usize].count == swipes_before { os.exit(71i32) }
    // (D1286) Opening slides the drawer in: part way, 280 in from the edge is
    // still the page; settled, it is the drawer's surface. (D1447) It enters on
    // `ease-emphasized-decelerate`: a quarter of the way through its
    // `duration-medium-2`, 100 in is already the drawer (the standard curve had
    // it well short).
    let slide_surface = style.color(&tokens, .SurfaceContainerLow)
    var slide_step = 0usize
    while slide_step < 4usize {
        var slide_at = 9000000000i64
        var slide_open = false
        if slide_step == 1usize { slide_at = 9016000000i64 }
        if slide_step == 2usize {
            slide_at = 9100000000i64
            slide_open = true
        }
        if slide_step == 3usize {
            slide_at = 9175000000i64
            slide_open = true
        }
        if testing.begin(&harness, time.Instant { nanos: slide_at }) != ok { os.exit(72i32) }
        f = mem.arena_from(frame_storage)
        let (slid_drawer, slid_error) = navigation.navigation_drawer_of(&f, 3900u64, &theme, "neper", s.rows[0usize..3usize], 0usize, s.picks[0usize..3usize], slide_open, &s.dismiss, 300.0)
        let (slide_parts, slide_parts_error) = mem.alloc[widget.Node](&f, 1usize)
        if slid_error != ok || slide_parts_error != ok { os.exit(73i32) }
        slide_parts[0usize] = slid_drawer
        var slide_page = control.sized_style(640.0, 520.0)
        slide_page.background = paint.Brush { Solid: style.color(&tokens, .Background) }
        if testing.pump(&harness, widget.box(0u64, slide_page, slide_parts[0usize..1usize]), time.Instant { nanos: slide_at }) != ok { os.exit(74i32) }
        slide_step += 1usize
    }
    let (half_shot, half_shot_error) = testing.snapshot(&harness, a)
    if half_shot_error != ok || is_color(half_shot, at(280.0, 300.0), slide_surface) || !is_color(half_shot, at(100.0, 300.0), slide_surface) { os.exit(75i32) }
    if testing.begin(&harness, time.Instant { nanos: 9600000000i64 }) != ok { os.exit(76i32) }
    f = mem.arena_from(frame_storage)
    let (settled_drawer, settled_error) = navigation.navigation_drawer_of(&f, 3900u64, &theme, "neper", s.rows[0usize..3usize], 0usize, s.picks[0usize..3usize], true, &s.dismiss, 300.0)
    let (settled_parts, settled_parts_error) = mem.alloc[widget.Node](&f, 1usize)
    if settled_error != ok || settled_parts_error != ok { os.exit(77i32) }
    settled_parts[0usize] = settled_drawer
    var settled_page = control.sized_style(640.0, 520.0)
    settled_page.background = paint.Brush { Solid: style.color(&tokens, .Background) }
    if testing.pump(&harness, widget.box(0u64, settled_page, settled_parts[0usize..1usize]), time.Instant { nanos: 9600000000i64 }) != ok { os.exit(78i32) }
    let (settled_shot, settled_shot_error) = testing.snapshot(&harness, a)
    if settled_shot_error != ok || !is_color(settled_shot, at(200.0, 300.0), slide_surface) { os.exit(79i32) }
    // (D1317) Choosing People fills its pill from the centre: part way through
    // `duration-medium-1` the fill is narrower than the 64 pill; done, no fill
    // stands apart from the pill.
    var pill_step = 0usize
    while pill_step < 5usize {
        var pill_at = 11000000000i64
        var pill_pick = 0usize
        if pill_step == 1usize { pill_at = 11016000000i64 }
        if pill_step == 2usize {
            pill_at = 11100000000i64
            pill_pick = 1usize
        }
        if pill_step == 3usize {
            pill_at = 11200000000i64
            pill_pick = 1usize
        }
        if pill_step == 4usize {
            pill_at = 11500000000i64
            pill_pick = 1usize
        }
        if testing.begin(&harness, time.Instant { nanos: pill_at }) != ok { os.exit(80i32) }
        f = mem.arena_from(frame_storage)
        let (pill_bar, pill_bar_error) = navigation.destination_bar_of(&f, 3000u64, &theme, s.places[0usize..3usize], pill_pick, s.picks[0usize..3usize], .Bottom, 400.0)
        let (pill_parts, pill_parts_error) = mem.alloc[widget.Node](&f, 1usize)
        if pill_bar_error != ok || pill_parts_error != ok { os.exit(81i32) }
        pill_parts[0usize] = pill_bar
        if testing.pump(&harness, widget.box(0u64, control.sized_style(640.0, 520.0), pill_parts[0usize..1usize]), time.Instant { nanos: pill_at }) != ok { os.exit(82i32) }
        let fill_key = 3002u64 + 1048576u64
        if pill_step == 3usize {
            let (fill_box, has_fill_box) = bounds(&harness, &runtime, fill_key)
            if !has_fill_box || !(fill_box.width > 1.0) || !(fill_box.width < 63.0) { os.exit(83i32) }
        }
        if pill_step == 4usize && testing.by_key(&harness, fill_key).count != 0usize { os.exit(84i32) }
        pill_step += 1usize
    }
    // (D1448) Moved to another destination, its page fades in over
    // `duration-medium-1`: on the move's frame the page's block is not yet
    // `primary`, a second on it is.
    var page_block = control.sized_style(200.0, 100.0)
    page_block.background = paint.Brush { Solid: style.color(&tokens, .Primary) }
    var page_step = 0usize
    while page_step < 4usize {
        var page_at = 20000000000i64
        var page_chosen = 0usize
        if page_step == 1usize { page_at = 20000000001i64 }
        if page_step == 2usize {
            page_at = 20100000000i64
            page_chosen = 1usize
        }
        if page_step == 3usize {
            page_at = 21100000000i64
            page_chosen = 1usize
        }
        if testing.begin(&harness, time.Instant { nanos: page_at }) != ok { os.exit(82i32) }
        f = mem.arena_from(frame_storage)
        let (destination, destination_error) = navigation.destination_page(&f, 3950u64, &theme, page_chosen, widget.box(3951u64, page_block, zero))
        let (destination_parts, destination_parts_error) = mem.alloc[widget.Node](&f, 1usize)
        if destination_error != ok || destination_parts_error != ok { os.exit(82i32) }
        destination_parts[0usize] = destination
        if testing.pump(&harness, widget.box(0u64, control.sized_style(640.0, 520.0), destination_parts[0usize..1usize]), time.Instant { nanos: page_at }) != ok { os.exit(82i32) }
        if page_step >= 2usize {
            let (page_box, has_page_box) = bounds(&harness, &runtime, 3951u64)
            let (page_shot, page_shot_error) = testing.snapshot(&harness, a)
            if !has_page_box || page_shot_error != ok { os.exit(83i32) }
            let shown_page = is_color(page_shot, at(page_box.x + 100.0, page_box.y + 50.0), style.color(&tokens, .Primary))
            if page_step == 2usize && shown_page { os.exit(84i32) }
            if page_step == 3usize && !shown_page { os.exit(85i32) }
        }
        page_step += 1usize
    }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(31i32) }
    try io.print("ui navigation3 v2 ok\n")
    ret ok
}
