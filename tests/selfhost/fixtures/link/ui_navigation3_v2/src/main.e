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

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
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
    if !tap_key(&harness, &runtime, 3002u64) || s.counters[1usize].count != 1usize { os.exit(16i32) }
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
    // The modal drawer open: 300 wide at the start, its end corners rounded, over
    // the scrim; 56 tall rows; Sent picks, Escape dismisses.
    let (root_2, build_2_error) = build(&f, &theme, s, true)
    if build_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(24i32) }
    let (drawer_focus, has_drawer_focus) = testing.focused(&harness)
    if !has_drawer_focus || drawer_focus.slot != testing.by_key(&harness, 3402u64).element.slot { os.exit(32i32) }
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
    if !tap_key(&harness, &runtime, 3403u64) || s.counters[1usize].count != 2usize || testing.press_key(&harness, 27u32, zero) != ok || s.counters[3usize].count != 1usize { os.exit(30i32) }
    let (root_3, build_3_error) = build(&f, &theme, s, false)
    if build_3_error != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1200000000i64 }) != ok { os.exit(33i32) }
    let (returned_focus, has_returned_focus) = testing.focused(&harness)
    if !has_returned_focus || returned_focus.slot != testing.by_key(&harness, 3002u64).element.slot { os.exit(34i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(31i32) }
    try io.print("ui navigation3 v2 ok\n")
    ret ok
}
