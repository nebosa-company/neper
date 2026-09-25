// Tabs mirror horizontal navigation in RTL while Home and End stay logical;
// (D1213) a disabled tab is skipped by the keys and does not take a press.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.style
use e.ui.testing
use e.ui.widget

type Counter = struct { count: usize }
type Store = struct { counters: [3]Counter, actions: [3]widget.Submit }

fn on_count(ctx: *void) -> err {
    let counter = mem.cast[*Counter](ctx)
    counter.count += 1usize
    ret ok
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *const Store) -> (widget.Node, err) {
    var labels: [3]str = zero
    labels[0usize] = "Overview"
    labels[1usize] = "Builds"
    labels[2usize] = "Settings"
    let (tabs, tabs_error) = control.tabs(a, 100u64, t, labels[..], 1usize, s.actions[..])
    if tabs_error != ok { ret (zero, tabs_error) }
    let (children, children_error) = mem.alloc[widget.Node](a, 1usize)
    if children_error != ok { ret (zero, children_error) }
    children[0usize] = tabs
    var page = style.defaults()
    page.width = style.Length { Px: 320.0 }
    page.height = style.Length { Px: 80.0 }
    ret (widget.box(0u64, page, children[0usize..1usize]), ok)
}

// The same tabs with the middle one disabled and the first selected.
fn build_disabled(a: *mem.Arena, t: *const control.Theme, s: *const Store) -> (widget.Node, err) {
    var labels: [3]str = zero
    labels[0usize] = "Overview"
    labels[1usize] = "Builds"
    labels[2usize] = "Settings"
    var off: [3]bool = zero
    off[1usize] = true
    var options = control.tabs_options()
    options.disabled = off[..]
    let (tabs, tabs_error) = control.tabs_of(a, 100u64, t, labels[..], 0usize, s.actions[..], options)
    if tabs_error != ok { ret (zero, tabs_error) }
    let (children, children_error) = mem.alloc[widget.Node](a, 1usize)
    if children_error != ok { ret (zero, children_error) }
    children[0usize] = tabs
    var page = style.defaults()
    page.width = style.Length { Px: 320.0 }
    page.height = style.Length { Px: 80.0 }
    ret (widget.box(0u64, page, children[0usize..1usize]), ok)
}

// (D1226) The same tabs with icons over their labels and a count on Builds' icon;
// or, `iconic` false, text tabs with a count after Overview's label.
fn build_badged(a: *mem.Arena, t: *const control.Theme, s: *const Store, iconic: bool) -> (widget.Node, err) {
    var labels: [3]str = zero
    labels[0usize] = "Overview"
    labels[1usize] = "Builds"
    labels[2usize] = "Settings"
    var glyphs: [3]control.GlyphKind = zero
    glyphs[0usize] = .Picture
    glyphs[1usize] = .Refresh
    glyphs[2usize] = .Search
    var counts: [3]str = zero
    var meanings: [3]str = zero
    var dots: [3]bool = zero
    var options = control.tabs_options()
    // (D1242) Settings has a dot; with icons it means "update ready".
    dots[2usize] = true
    options.dots = dots[..]
    if iconic {
        meanings[2usize] = "update ready"
        counts[1usize] = "3"
        meanings[1usize] = "3 failed"
        options.icons = glyphs[..]
        options.badge_names = meanings[..]
    } else {
        counts[0usize] = "2"
    }
    options.badges = counts[..]
    let (tabs, tabs_error) = control.tabs_of(a, 100u64, t, labels[..], 0usize, s.actions[..], options)
    if tabs_error != ok { ret (zero, tabs_error) }
    let (children, children_error) = mem.alloc[widget.Node](a, 1usize)
    if children_error != ok { ret (zero, children_error) }
    children[0usize] = tabs
    var page = style.defaults()
    page.width = style.Length { Px: 320.0 }
    page.height = style.Length { Px: 80.0 }
    ret (widget.box(0u64, page, children[0usize..1usize]), ok)
}

fn tab_named(h: *const testing.Harness, label: str) -> bool {
    let (tree, tree_error) = testing.semantics(h)
    if tree_error != ok { ret false }
    var n = 0usize
    while n < tree.nodes.len {
        if tree.nodes[n].role == .Tab && mem.eq[u8](tree.nodes[n].label, label) { ret true }
        n += 1usize
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (queue, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (made_renderer, renderer_error) = scene.renderer(a, device, queue, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = made_renderer
    var tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (made_runtime, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 256usize, max_states: 4usize, state_bytes: 128usize, state_classes: 1u16, max_depth: 24u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = made_runtime
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (made_harness, harness_error) = testing.harness(a, &runtime, 320u32, 80u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = made_harness
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var empty: Store = zero
    stores[0usize] = empty
    var i = 0usize
    while i < 3usize {
        stores[0usize].actions[i] = widget.Submit { ctx: mem.cast[*void](&stores[0usize].counters[i]), invoke: on_count }
        i += 1usize
    }
    let (frame_bytes, frame_error) = mem.alloc[u8](a, 262144usize)
    if frame_error != ok { os.exit(8i32) }
    var frame = mem.arena_from(frame_bytes)
    let (ltr, ltr_error) = build(&frame, &theme, &stores[0usize])
    if ltr_error != ok || testing.pump(&harness, ltr, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(9i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 102u64).element) != ok { os.exit(10i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || stores[0usize].counters[0usize].count != 1usize { os.exit(11i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || stores[0usize].counters[2usize].count != 1usize { os.exit(12i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || stores[0usize].counters[0usize].count != 2usize { os.exit(13i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || stores[0usize].counters[2usize].count != 2usize { os.exit(14i32) }
    tokens.direction = .RightToLeft
    let (rtl, rtl_error) = build(&frame, &theme, &stores[0usize])
    if rtl_error != ok || testing.pump(&harness, rtl, time.Instant { nanos: 2000000000i64 }) != ok { os.exit(15i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 102u64).element) != ok { os.exit(16i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || stores[0usize].counters[2usize].count != 3usize { os.exit(17i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || stores[0usize].counters[0usize].count != 3usize { os.exit(18i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || stores[0usize].counters[0usize].count != 4usize { os.exit(19i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || stores[0usize].counters[2usize].count != 4usize { os.exit(20i32) }
    // A disabled tab: Right and End from the first reach the third, a press on
    // the second does nothing, and the tree says it is disabled.
    tokens.direction = .LeftToRight
    let (off, off_error) = build_disabled(&frame, &theme, &stores[0usize])
    if off_error != ok || testing.pump(&harness, off, time.Instant { nanos: 3000000000i64 }) != ok { os.exit(22i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 101u64).element) != ok { os.exit(23i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || stores[0usize].counters[2usize].count != 5usize || stores[0usize].counters[1usize].count != 0usize { os.exit(24i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || stores[0usize].counters[2usize].count != 6usize { os.exit(25i32) }
    let (builds_tab, has_builds_tab) = widget.bounds_of(&runtime, testing.by_key(&harness, 102u64).element)
    if !has_builds_tab || testing.tap(&harness, builds_tab.x + builds_tab.width * 0.5, builds_tab.y + builds_tab.height * 0.5) != ok || stores[0usize].counters[1usize].count != 0usize { os.exit(26i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(27i32) }
    var disabled_tabs = 0usize
    var n = 0usize
    while n < tree.nodes.len {
        if tree.nodes[n].role == .Tab && tree.nodes[n].state.disabled { disabled_tabs += 1usize }
        n += 1usize
    }
    if disabled_tabs != 1usize { os.exit(28i32) }
    // (D1226) Icon tabs are 56 tall with the count on Builds' icon, named
    // "Builds, 3 failed"; a text tab's count follows its label and joins its name.
    let (iconic, iconic_error) = build_badged(&frame, &theme, &stores[0usize], true)
    if iconic_error != ok || testing.pump(&harness, iconic, time.Instant { nanos: 4000000000i64 }) != ok { os.exit(29i32) }
    let (icon_tab, has_icon_tab) = widget.bounds_of(&runtime, testing.by_key(&harness, 102u64).element)
    if !has_icon_tab || icon_tab.height < 55.5 || icon_tab.height > 56.5 { os.exit(30i32) }
    if !tab_named(&harness, "Builds, 3 failed") || !tab_named(&harness, "Overview") || testing.by_text(&harness, "3").count == 0usize { os.exit(31i32) }
    let (texty, texty_error) = build_badged(&frame, &theme, &stores[0usize], false)
    if texty_error != ok || testing.pump(&harness, texty, time.Instant { nanos: 4100000000i64 }) != ok { os.exit(32i32) }
    let (text_tab, has_text_tab) = widget.bounds_of(&runtime, testing.by_key(&harness, 101u64).element)
    if !has_text_tab || text_tab.height > 40.5 || !tab_named(&harness, "Overview, 2") || testing.by_text(&harness, "2").count == 0usize { os.exit(33i32) }
    // (D1242) A text tab's dot follows its label 4 after it and names it "new".
    if !tab_named(&harness, "Settings, new") { os.exit(34i32) }
    let (iconic_node, iconic_node_error) = build_badged(&frame, &theme, &stores[0usize], true)
    if iconic_node_error != ok || testing.pump(&harness, iconic_node, time.Instant { nanos: 4200000000i64 }) != ok || !tab_named(&harness, "Settings, update ready") || !tab_named(&harness, "Builds, 3 failed") { os.exit(35i32) }
    // (D1254) Eight scrollable tabs in 200 overflow; once the last (selected) tab
    // has the focus the strip scrolls just far enough to show all of it.
    var many_labels: [8]str = zero
    var many_picks: [8]widget.Submit = zero
    var m = 0usize
    while m < 8usize {
        many_labels[m] = "Tab"
        many_picks[m] = stores[0usize].actions[0usize]
        m += 1usize
    }
    var scroller = control.tabs_options()
    scroller.width = 200.0
    var scroll_step = 0usize
    while scroll_step < 3usize {
        frame = mem.arena_from(frame_bytes)
        let (many, many_error) = control.tabs_of(&frame, 300u64, &theme, many_labels[..], 7usize, many_picks[..], scroller)
        let (many_page, many_page_error) = mem.alloc[widget.Node](&frame, 1usize)
        if many_error != ok || many_page_error != ok { os.exit(36i32) }
        many_page[0usize] = many
        if testing.pump(&harness, widget.box(0u64, control.sized_style(320.0, 80.0), many_page[0usize..1usize]), time.Instant { nanos: 5000000000i64 + i64(scroll_step) }) != ok { os.exit(37i32) }
        if scroll_step == 0usize && widget.focus(&runtime, testing.by_key(&harness, 308u64).element) != ok { os.exit(38i32) }
        scroll_step += 1usize
    }
    let (strip_view, has_strip_view) = widget.bounds_of(&runtime, testing.by_key(&harness, 1048876u64).element)
    let (last_tab, has_last_tab) = widget.bounds_of(&runtime, testing.by_key(&harness, 308u64).element)
    let (first_tab, has_first_tab) = widget.bounds_of(&runtime, testing.by_key(&harness, 301u64).element)
    let (strip_offset, has_strip_offset) = widget.scroll_offset_of(&runtime, testing.by_key(&harness, 1048876u64).element)
    if !has_strip_view || !has_last_tab || !has_first_tab || !has_strip_offset || !(strip_offset > 0.0) { os.exit(39i32) }
    if last_tab.x + last_tab.width > strip_view.x + strip_view.width + 0.5 || !(first_tab.x < strip_view.x) { os.exit(40i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(21i32) }
    try io.print("ui tabs rtl ok\n")
    ret ok
}
