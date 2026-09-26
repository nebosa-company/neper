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

// (D1271) No breadcrumb jumps.
fn no_jumps() -> []const widget.Submit {
    var none: []const widget.Submit = zero
    ret none
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
    // (D1267) A medium bar (112 at pointer density, its row 48) loses the page's
    // scroll: 32 scrolled leaves 80, and past 64 it is the 48 small bar.
    var no_actions: [1]navigation.Action = zero
    var collapse_step = 0usize
    var projects_at_rest = 0usize
    while collapse_step < 3usize {
        var collapsing = navigation.app_bar_options()
        collapsing.size = .Medium
        if collapse_step == 1usize { collapsing.offset = 32.0 }
        if collapse_step == 2usize { collapsing.offset = 100.0 }
        f = mem.arena_from(frame_storage)
        let (collapsed_bar, collapsed_error) = navigation.app_bar_of(&f, 1900u64, &theme, "Projects", no_actions[0usize..0usize], no_actions[0usize..0usize], collapsing, 600.0)
        let (collapsed_page, collapsed_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if collapsed_error != ok || collapsed_page_error != ok { os.exit(32i32) }
        collapsed_page[0usize] = collapsed_bar
        if testing.pump(&harness, widget.box(0u64, control.sized_style(600.0, 400.0), collapsed_page[0usize..1usize]), time.Instant { nanos: 7000000000i64 + i64(collapse_step) }) != ok { os.exit(33i32) }
        let (collapsed_box, has_collapsed_box) = bounds(&harness, &runtime, 1900u64)
        var expected: f32 = 112.0
        if collapse_step == 1usize { expected = 80.0 }
        if collapse_step == 2usize { expected = 48.0 }
        if !has_collapsed_box || !near(collapsed_box.height, expected) { os.exit(34i32) }
        // (D1318) Mid-collapse the row's title stands beside the headline: one more
        // "Projects" than at rest.
        let projects_now = testing.by_text(&harness, "Projects").count
        if collapse_step == 0usize { projects_at_rest = projects_now }
        if collapse_step == 1usize && projects_now != projects_at_rest + 1usize { os.exit(49i32) }
        collapse_step += 1usize
    }
    // (D1268) A hiding bar stands its shown share: half of 48 is 24; hidden, 0.
    var hide_step = 0usize
    while hide_step < 2usize {
        var hiding = navigation.app_bar_options()
        hiding.hides = true
        hiding.shown = 0.5
        if hide_step == 1usize { hiding.shown = 0.0 }
        f = mem.arena_from(frame_storage)
        let (hiding_bar, hiding_error) = navigation.app_bar_of(&f, 1950u64, &theme, "Inbox", no_actions[0usize..0usize], no_actions[0usize..0usize], hiding, 600.0)
        let (hiding_page, hiding_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if hiding_error != ok || hiding_page_error != ok { os.exit(35i32) }
        hiding_page[0usize] = hiding_bar
        if testing.pump(&harness, widget.box(0u64, control.sized_style(600.0, 400.0), hiding_page[0usize..1usize]), time.Instant { nanos: 7100000000i64 + i64(hide_step) }) != ok { os.exit(36i32) }
        let (hiding_box, has_hiding_box) = bounds(&harness, &runtime, 1950u64)
        var hiding_expected: f32 = 24.0
        if hide_step == 1usize { hiding_expected = 0.0 }
        if !has_hiding_box || !near(hiding_box.height, hiding_expected) { os.exit(37i32) }
        hide_step += 1usize
    }
    // (D1271) Pushing from a focused row moves the focus to the new page's Back;
    // popping returns it to the row.
    var stack_titles: [2]str = zero
    stack_titles[0usize] = "Projects"
    stack_titles[1usize] = "neper"
    var stack_step = 0usize
    while stack_step < 4usize {
        var depth = 1usize
        if stack_step == 2usize { depth = 2usize }
        f = mem.arena_from(frame_storage)
        var plain = control.button_options()
        plain.variant = .Plain
        let (row_button, row_button_error) = control.button(&f, 2600u64, &theme, "Open neper", &s.subs[0usize], plain)
        if row_button_error != ok { os.exit(38i32) }
        var stack_pages: [2]widget.Node = zero
        stack_pages[0usize] = row_button
        stack_pages[1usize] = widget.box(0u64, control.sized_style(100.0, 100.0), zero)
        let (stacked, stacked_error) = navigation.navigation_stack_of(&f, 2500u64, &theme, stack_titles[0usize..depth], stack_pages[0usize..depth], &s.subs[3usize], no_jumps(), 600.0)
        if stacked_error != ok || testing.pump(&harness, stacked, time.Instant { nanos: 7200000000i64 + i64(stack_step) }) != ok { os.exit(39i32) }
        let (focus_now, has_focus_now) = testing.focused(&harness)
        if stack_step == 0usize && widget.focus(&runtime, testing.by_key(&harness, 2600u64).element) != ok { os.exit(40i32) }
        if stack_step == 2usize && (!has_focus_now || focus_now.slot != testing.by_key(&harness, 2502u64).element.slot) { os.exit(41i32) }
        if stack_step == 3usize && (!has_focus_now || focus_now.slot != testing.by_key(&harness, 2600u64).element.slot) { os.exit(42i32) }
        stack_step += 1usize
    }
    // (D1319) A push slides the new page in from the end: part way its
    // `primary` block is not yet at its place; settled, it is.
    var slide_titles: [2]str = zero
    slide_titles[0usize] = "Projects"
    slide_titles[1usize] = "neper"
    var slide_block = control.sized_style(100.0, 100.0)
    slide_block.background = paint.Brush { Solid: style.color(&tokens, .Primary) }
    var slide_step = 0usize
    while slide_step < 4usize {
        var slide_at = 12000000000i64
        var slide_depth = 1usize
        if slide_step == 1usize { slide_at = 12016000000i64 }
        if slide_step == 2usize {
            slide_at = 12150000000i64
            slide_depth = 2usize
        }
        if slide_step == 3usize {
            slide_at = 12600000000i64
            slide_depth = 2usize
        }
        if testing.begin(&harness, time.Instant { nanos: slide_at }) != ok { os.exit(50i32) }
        f = mem.arena_from(frame_storage)
        var slide_pages: [2]widget.Node = zero
        slide_pages[0usize] = widget.box(0u64, control.sized_style(100.0, 100.0), zero)
        slide_pages[1usize] = widget.box(0u64, slide_block, zero)
        let (sliding, sliding_error) = navigation.navigation_stack_of(&f, 2800u64, &theme, slide_titles[0usize..slide_depth], slide_pages[0usize..slide_depth], &s.subs[3usize], no_jumps(), 600.0)
        if sliding_error != ok || testing.pump(&harness, sliding, time.Instant { nanos: slide_at }) != ok { os.exit(51i32) }
        if slide_step >= 2usize {
            let (slide_page, has_slide_page) = bounds(&harness, &runtime, 2803u64)
            let (slide_shot, slide_shot_error) = testing.snapshot(&harness, a)
            if !has_slide_page || slide_shot_error != ok { os.exit(52i32) }
            let placed = is_color(slide_shot, at(slide_page.x + 50.0, slide_page.y + 50.0), style.color(&tokens, .Primary))
            if slide_step == 2usize && placed { os.exit(53i32) }
            if slide_step == 3usize && !placed { os.exit(54i32) }
        }
        slide_step += 1usize
    }
    // (D1445) A pop eases on `ease-emphasized-accelerate` over `duration-medium-1`:
    // 200 ms after it the page beneath (a full-width block) is still well short
    // of its place returning from 30% towards the start, so 530 in is not yet
    // reached (the old standard curve had it there); a second on it is.
    var wide_block = control.sized_style(600.0, 100.0)
    wide_block.background = paint.Brush { Solid: style.color(&tokens, .Primary) }
    var pop_step = 0usize
    while pop_step < 6usize {
        var pop_at = 13000000000i64
        var pop_depth = 2usize
        if pop_step == 1usize { pop_at = 13000000001i64 }
        if pop_step == 2usize { pop_at = 13500000000i64 }
        if pop_step == 3usize {
            pop_at = 14000000000i64
            pop_depth = 1usize
        }
        if pop_step == 4usize {
            pop_at = 14200000000i64
            pop_depth = 1usize
        }
        if pop_step == 5usize {
            pop_at = 15000000000i64
            pop_depth = 1usize
        }
        if testing.begin(&harness, time.Instant { nanos: pop_at }) != ok { os.exit(65i32) }
        f = mem.arena_from(frame_storage)
        var pop_pages: [2]widget.Node = zero
        pop_pages[0usize] = widget.box(0u64, wide_block, zero)
        pop_pages[1usize] = widget.box(0u64, control.sized_style(100.0, 100.0), zero)
        let (popping_stack, popping_stack_error) = navigation.navigation_stack_of(&f, 2850u64, &theme, slide_titles[0usize..pop_depth], pop_pages[0usize..pop_depth], &s.subs[3usize], no_jumps(), 600.0)
        if popping_stack_error != ok || testing.pump(&harness, popping_stack, time.Instant { nanos: pop_at }) != ok { os.exit(65i32) }
        if pop_step >= 4usize {
            let (pop_page, has_pop_page) = bounds(&harness, &runtime, 2853u64)
            let (pop_shot, pop_shot_error) = testing.snapshot(&harness, a)
            if !has_pop_page || pop_shot_error != ok { os.exit(66i32) }
            let reached = is_color(pop_shot, at(pop_page.x + 530.0, pop_page.y + 50.0), style.color(&tokens, .Primary))
            if pop_step == 4usize && reached { os.exit(67i32) }
            if pop_step == 5usize && !reached { os.exit(68i32) }
        }
        pop_step += 1usize
    }
    // (D1272) A dirty page's Back asks instead of popping; the open question's
    // Discard pops.
    var guarded: navigation.StackGuard = zero
    guarded.dirty = true
    guarded.request_discard = s.subs[6usize]
    guarded.keep_editing = s.subs[7usize]
    var guard_pages: [2]widget.Node = zero
    guard_pages[0usize] = widget.box(0u64, control.sized_style(100.0, 100.0), zero)
    guard_pages[1usize] = widget.box(0u64, control.sized_style(100.0, 100.0), zero)
    var guard_step = 0usize
    while guard_step < 2usize {
        guarded.discard_open = guard_step == 1usize
        f = mem.arena_from(frame_storage)
        let (guarded_stack, guarded_error) = navigation.navigation_stack_with(&f, 2700u64, &theme, stack_titles[0usize..2usize], guard_pages[0usize..2usize], &s.subs[3usize], no_jumps(), 600.0, guarded)
        if guarded_error != ok || testing.pump(&harness, guarded_stack, time.Instant { nanos: 7300000000i64 + i64(guard_step) }) != ok { os.exit(43i32) }
        if guard_step == 0usize {
            let asks_before = s.counters[6usize].count
            let pops_before = s.counters[3usize].count
            if !tap_key(&harness, &runtime, 2702u64) || s.counters[6usize].count != asks_before + 1usize || s.counters[3usize].count != pops_before { os.exit(44i32) }
        }
        if guard_step == 1usize {
            let (guard_tree, guard_tree_error) = testing.semantics(&harness)
            let (_, has_question) = find(guard_tree, .AlertDialog, "Discard changes to neper?")
            let (discard_button, has_discard_button) = find(guard_tree, .Button, "Discard")
            let pops_before = s.counters[3usize].count
            if guard_tree_error != ok || !has_question || !has_discard_button { os.exit(45i32) }
            if testing.tap(&harness, discard_button.bounds.x + 10.0, discard_button.bounds.y + discard_button.bounds.height * 0.5) != ok || s.counters[3usize].count != pops_before + 1usize { os.exit(46i32) }
        }
        guard_step += 1usize
    }
    // (D1391) A selection turns a bar contextual: 50 ms in its fill is still
    // coming in; a second later it is the full `secondary-container`.
    var none_actions: []const navigation.Action = zero
    var context_step = 0usize
    var context_mid: u32 = 0u32
    var context_end: u32 = 0u32
    while context_step < 5usize {
        var context_at = 90000000000i64 + i64(context_step) * 16000000i64
        if context_step == 3usize { context_at = 90082000000i64 }
        if context_step == 4usize { context_at = 91000000000i64 }
        if testing.begin(&harness, time.Instant { nanos: context_at }) != ok { os.exit(60i32) }
        var context_look = navigation.app_bar_options()
        if context_step >= 2usize {
            context_look.contextual = "1 selected"
            context_look.clear = s.subs[2usize]
        }
        f = mem.arena_from(frame_storage)
        let (context_bar, context_bar_error) = navigation.app_bar_of(&f, 1500u64, &theme, "Inbox", none_actions, none_actions, context_look, 600.0)
        let (context_page, context_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if context_bar_error != ok || context_page_error != ok { os.exit(61i32) }
        context_page[0usize] = context_bar
        var context_ground = control.sized_style(640.0, 200.0)
        context_ground.background = paint.Brush { Solid: style.color(&tokens, .Surface) }
        if testing.pump(&harness, widget.box(0u64, context_ground, context_page[0usize..1usize]), time.Instant { nanos: context_at }) != ok { os.exit(62i32) }
        if context_step >= 3usize {
            let (context_box, has_context_box) = widget.bounds_of(&runtime, testing.by_key(&harness, 1500u64).element)
            let (context_shot, context_shot_error) = testing.snapshot(&harness, a)
            if !has_context_box || context_shot_error != ok { os.exit(63i32) }
            let context_spot = at(context_box.x + 500.0, context_box.y + 6.0)
            let context_rgb = u32(context_shot.pixels[context_spot]) * 65536u32 + u32(context_shot.pixels[context_spot + 1usize]) * 256u32 + u32(context_shot.pixels[context_spot + 2usize])
            if context_step == 3usize { context_mid = context_rgb }
            if context_step == 4usize { context_end = context_rgb }
        }
        context_step += 1usize
    }
    if context_mid == context_end { os.exit(64i32) }
    // (D1462) A disabled action at its group's outer end is hidden; one between
    // others is dimmed in place.
    var gated: [3]navigation.Action = zero
    gated[0usize] = navigation.Action { label: "Undo", action: s.subs[0usize], icon: zero, enabled: false }
    gated[1usize] = navigation.Action { label: "Share", action: s.subs[0usize], icon: zero, enabled: false }
    gated[2usize] = navigation.Action { label: "Search", action: s.subs[0usize], icon: zero, enabled: true }
    var inner_gated: [3]navigation.Action = zero
    inner_gated[0usize] = navigation.Action { label: "Search", action: s.subs[0usize], icon: zero, enabled: true }
    inner_gated[1usize] = navigation.Action { label: "Share", action: s.subs[0usize], icon: zero, enabled: false }
    inner_gated[2usize] = navigation.Action { label: "Edit", action: s.subs[0usize], icon: zero, enabled: true }
    var gate_step = 0usize
    while gate_step < 2usize {
        f = mem.arena_from(frame_storage)
        let (gated_bar, gated_error) = navigation.app_bar_of(&f, 4000u64, &theme, "Gated", inner_gated[0usize..3usize], gated[0usize..3usize], navigation.app_bar_options(), 600.0)
        let (gated_page, gated_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if gated_error != ok || gated_page_error != ok { os.exit(70i32) }
        gated_page[0usize] = gated_bar
        if testing.pump(&harness, widget.box(0u64, control.sized_style(640.0, 200.0), gated_page[0usize..1usize]), time.Instant { nanos: 30000000000i64 + i64(gate_step) }) != ok { os.exit(71i32) }
        gate_step += 1usize
    }
    // Trailing: the two disabled at the start are hidden, Search stands.
    if testing.by_key(&harness, 4009u64).count != 0usize || testing.by_key(&harness, 4010u64).count != 0usize || testing.by_key(&harness, 4011u64).count == 0usize { os.exit(72i32) }
    // Leading: the disabled Share between Search and Edit stays, dimmed.
    if testing.by_key(&harness, 4001u64).count == 0usize || testing.by_key(&harness, 4002u64).count == 0usize || testing.by_key(&harness, 4003u64).count == 0usize { os.exit(73i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(31i32) }
    try io.print("ui navigation v2 ok\n")
    ret ok
}
