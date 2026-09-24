// The v2 app bars and navigation stack (D972, widget plan P5-10,
// docs/ux/components/AppBar, NavigationStack) under the light theme at pointer
// density: a small bar 48 tall on `surface` named by its level-1 heading, three
// trailing actions then More over the fourth, its menu opening; the contextual
// bar on `secondary-container` saying "3 selected" politely, Clear selection
// clearing; medium (112) and large (152) bars, the medium one scrolled onto
// `surface-container`; the bottom bar 80 tall on `surface-container` with a 56
// FAB 16 from its end; a stack three deep whose Back is named for the page
// beneath and pops, with breadcrumbs in the bar jumping up.

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

// The counters: 0 trailing actions, 1 More, 2 clear, 3 pop, 4 jumps, 5 FAB.
type Store = struct { counters: [8]Counter, subs: [8]widget.Submit, actions: [4]navigation.Action, bottoms: [2]navigation.Action, fab: navigation.Action, jumps: [3]widget.Submit }

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

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store, more_open: bool) -> (widget.Node, err) {
    var none: []const navigation.Action = zero
    var small = navigation.app_bar_options()
    small.more = s.subs[1usize]
    small.more_open = more_open
    let (bar, e1) = navigation.app_bar_of(a, 1000u64, t, "Inbox", none, s.actions[0usize..4usize], small, 600.0)
    var picked = navigation.app_bar_options()
    picked.contextual = "3 selected"
    picked.clear = s.subs[2usize]
    let (chosen, e2) = navigation.app_bar_of(a, 1100u64, t, "Inbox", none, s.actions[0usize..1usize], picked, 600.0)
    var medium = navigation.app_bar_options()
    medium.size = .Medium
    medium.scrolled = true
    let (tall, e3) = navigation.app_bar_of(a, 1200u64, t, "Projects", none, none, medium, 600.0)
    var large = navigation.app_bar_options()
    large.size = .Large
    let (taller, e4) = navigation.app_bar_of(a, 1300u64, t, "Projects", none, none, large, 600.0)
    let (bottom, e5) = navigation.bottom_app_bar(a, 1400u64, t, "Actions", s.bottoms[0usize..2usize], &s.fab, 600.0)
    var titles: [3]str = zero
    titles[0usize] = "Projects"
    titles[1usize] = "neper"
    titles[2usize] = "Build 4128"
    var pages: [3]widget.Node = zero
    let (page, e6) = control.text(a, 0u64, "Build page", t, control.text_options())
    pages[0usize] = page
    pages[1usize] = page
    pages[2usize] = page
    let (stack, e7) = navigation.navigation_stack_of(a, 1500u64, t, titles[..], pages[..], &s.subs[3usize], s.jumps[0usize..3usize], 600.0)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (zero, e1) }
    let (items, items_error) = mem.alloc[widget.Node](a, 6usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = bar
    items[1usize] = chosen
    items[2usize] = tall
    items[3usize] = taller
    items[4usize] = bottom
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = stack
    items[5usize] = widget.box(0u64, control.sized_style(600.0, 120.0), held[0usize..1usize])
    var page_style = style.defaults()
    page_style.width = style.Length { Px: 640.0 }
    page_style.height = style.Length { Px: 760.0 }
    page_style.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHighest) }
    let pad = style.Length { Px: 10.0 }
    page_style.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page_style, items[0usize..6usize]), ok)
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
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 760u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    var i = 0usize
    while i < 8usize {
        s.subs[i] = widget.Submit { ctx: mem.cast[*void](&s.counters[i]), invoke: on_count }
        i += 1usize
    }
    s.actions[0usize] = navigation.Action { label: "Search", action: s.subs[0usize], icon: zero, enabled: true }
    s.actions[1usize] = navigation.Action { label: "Filter", action: s.subs[0usize], icon: zero, enabled: true }
    s.actions[2usize] = navigation.Action { label: "Share", action: s.subs[0usize], icon: zero, enabled: true }
    s.actions[3usize] = navigation.Action { label: "Archive", action: s.subs[0usize], icon: zero, enabled: true }
    s.bottoms[0usize] = navigation.Action { label: "Search", action: s.subs[0usize], icon: zero, enabled: true }
    s.bottoms[1usize] = navigation.Action { label: "Filter", action: s.subs[0usize], icon: zero, enabled: true }
    s.fab = navigation.Action { label: "Compose", action: s.subs[5usize], icon: zero, enabled: true }
    s.jumps[0usize] = s.subs[4usize]
    s.jumps[1usize] = s.subs[4usize]
    s.jumps[2usize] = s.subs[4usize]
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
    // The small bar: 48 tall on `surface`, named by its level-1 heading.
    let (bar, has_bar) = bounds(&harness, &runtime, 1000u64)
    if !has_bar || !near(bar.height, 48.0) || !near(bar.width, 600.0) || !is_color(shot, at(bar.x + 300.0, bar.y + 24.0), style.color(&tokens, .Background)) { os.exit(13i32) }
    let (group, has_group) = find(tree, .Group, "Inbox")
    let (heading, has_heading) = find(tree, .Heading, "Inbox")
    if !has_group || !has_heading || heading.level != 1u8 { os.exit(14i32) }
    // Three trailing actions, then More over the fourth; More opens its menu.
    if testing.by_key(&harness, 1011u64).count != 1usize || testing.by_label(&harness, "Archive").count != 0usize { os.exit(15i32) }
    let (more, has_more) = find(tree, .Button, "More options")
    let (more_at, has_more_at) = bounds(&harness, &runtime, 1012u64)
    if !has_more || !has_more_at || !near(more_at.x + more_at.width, bar.x + 596.0) || !near(more_at.height, 32.0) { os.exit(16i32) }
    if !tap_key(&harness, &runtime, 1012u64) || s.counters[1usize].count != 1usize { os.exit(17i32) }
    // The contextual bar: `secondary-container`, its title said politely, Clear
    // selection clearing.
    let (picked, has_picked) = bounds(&harness, &runtime, 1100u64)
    if !has_picked || !is_color(shot, at(picked.x + 300.0, picked.y + 24.0), style.color(&tokens, .SecondaryContainer)) { os.exit(18i32) }
    let (said, has_said) = find(tree, .Heading, "3 selected")
    let (clear, has_clear) = find(tree, .Button, "Clear selection")
    if !has_said || said.live != .Polite || !has_clear || !tap_key(&harness, &runtime, 1101u64) || s.counters[2usize].count != 1usize { os.exit(19i32) }
    // Medium 112 scrolled onto `surface-container`; large 152 on `surface`.
    let (tall, has_tall) = bounds(&harness, &runtime, 1200u64)
    let (taller, has_taller) = bounds(&harness, &runtime, 1300u64)
    if !has_tall || !has_taller || !near(tall.height, 112.0) || !near(taller.height, 152.0) { os.exit(20i32) }
    if !is_color(shot, at(tall.x + 300.0, tall.y + 60.0), style.color(&tokens, .SurfaceContainer)) || !is_color(shot, at(taller.x + 300.0, taller.y + 60.0), style.color(&tokens, .Background)) { os.exit(21i32) }
    // The bottom bar: 80 on `surface-container`, the 56 FAB on
    // `primary-container` 16 from the end, pressing.
    let (bottom, has_bottom) = bounds(&harness, &runtime, 1400u64)
    let (fab, has_fab) = bounds(&harness, &runtime, 1409u64)
    if !has_bottom || !has_fab || !near(bottom.height, 80.0) || !is_color(shot, at(bottom.x + 200.0, bottom.y + 40.0), style.color(&tokens, .SurfaceContainer)) { os.exit(22i32) }
    if !near(fab.width, 56.0) || !near(fab.height, 56.0) || !near(fab.x + fab.width, bottom.x + 584.0) || !is_color(shot, at(fab.x + 8.0, fab.y + 28.0), style.color(&tokens, .PrimaryContainer)) { os.exit(23i32) }
    if !tap_key(&harness, &runtime, 1409u64) || s.counters[5usize].count != 1usize { os.exit(24i32) }
    // The stack three deep: Back named for the page beneath, popping; the
    // breadcrumbs in the bar, Projects jumping; the page on `surface`.
    let (back, has_back) = find(tree, .Button, "Back to neper")
    if !has_back || !tap_key(&harness, &runtime, 1502u64) || s.counters[3usize].count != 1usize { os.exit(25i32) }
    let (trail, has_trail) = find(tree, .Group, "Location")
    if !has_trail || testing.by_role(&harness, .Link).count != 2usize || !tap_key(&harness, &runtime, 1505u64) || s.counters[4usize].count != 1usize { os.exit(26i32) }
    let (stack_bar, has_stack_bar) = bounds(&harness, &runtime, 1501u64)
    let (stack_page, has_stack_page) = bounds(&harness, &runtime, 1503u64)
    if !has_stack_bar || !has_stack_page || !near(stack_bar.height, 48.0) || !near(stack_page.y, stack_bar.y + 48.0) { os.exit(27i32) }
    // More open: its menu holds the fourth action.
    let (root_2, build_2_error) = build(&f, &theme, s, true)
    if build_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(28i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(29i32) }
    let (archive, has_archive) = find(tree_2, .MenuItem, "Archive")
    let (more_2, has_more_2) = find(tree_2, .Button, "More options")
    if !has_archive || !has_more_2 || !more_2.state.expanded { os.exit(30i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(31i32) }
    try io.print("ui navigation v2 ok\n")
    ret ok
}
