// The ribbon (D2280, L087, e.ui.navigation) under the light theme at pointer density: a quick-access bar, a
// strip of tabs with a tinted band over the contextual ones, and for the current tab a 100 tall panel of
// groups -- a split command, toggles, a gallery with a menu of the rest, a dropdown, a launcher -- every
// control firing the caller's action; collapsed it keeps only the strip and floats the panel under the
// chosen tab; Left, Right, Home and End move between tabs and between the panel's controls, Down enters the
// panel, Escape and Up leave it, Ctrl+F1 collapses; and the tree names the region, the tab list, the tabs, the
// groups and the commands with their state.

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
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Counter = struct { count: usize }
type Turned = struct { count: usize, last: usize }

type Store = struct {
    picks: Turned,
    counters: [24]Counter, subs: [24]widget.Submit, tab_picks: [5]widget.Submit, tab_args: [5]TabArg,
    selected: usize, collapsed: bool, popup: bool, show_context: bool, paste_menu: bool, gallery_open: bool,
    bold: bool, style_chosen: usize,
    paste_items: [2]overlay.MenuItem, tab_list: [5]navigation.RibbonTab, groups_home: [3]navigation.RibbonGroup,
    groups_insert: [1]navigation.RibbonGroup, groups_view: [1]navigation.RibbonGroup,
    clipboard: [4]navigation.RibbonCommand, font: [5]navigation.RibbonCommand, editing: [2]navigation.RibbonCommand,
    tables: [2]navigation.RibbonCommand, zoom: [1]navigation.RibbonCommand, gallery_items: [8]navigation.RibbonItem,
    quick: [3]navigation.Action,
}
type TabArg = struct { store: *Store, index: usize }

fn on_count(ctx: *void) -> err {
    let c = mem.cast[*Counter](ctx)
    c.count += 1usize
    ret ok
}

fn on_tab(ctx: *void) -> err {
    let a = mem.cast[*TabArg](ctx)
    a.store.selected = a.index
    a.store.picks.count += 1usize
    a.store.picks.last = a.index
    if a.store.collapsed { a.store.popup = true }
    ret ok
}

fn on_bold(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.bold = !s.bold
    s.counters[4usize].count += 1usize
    ret ok
}

fn on_paste_menu(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.paste_menu = !s.paste_menu
    ret ok
}

fn on_gallery_menu(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.gallery_open = !s.gallery_open
    ret ok
}

fn on_collapse(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.collapsed = !s.collapsed
    s.popup = false
    s.counters[20usize].count += 1usize
    ret ok
}

fn on_dismiss(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.popup = false
    s.counters[21usize].count += 1usize
    ret ok
}

fn on_style(ctx: *void) -> err {
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

fn command(label: str, glyph: control.GlyphKind, action: widget.Submit, large: bool) -> navigation.RibbonCommand {
    var c: navigation.RibbonCommand = zero
    c.label = label
    c.glyph = glyph
    c.action = action
    c.enabled = true
    c.large = large
    ret c
}

fn setup(s: *Store) {
    var i = 0usize
    while i < 24usize {
        s.subs[i] = widget.Submit { ctx: mem.cast[*void](&s.counters[i]), invoke: on_count }
        i += 1usize
    }
    i = 0usize
    while i < 5usize {
        s.tab_args[i] = TabArg { store: s, index: i }
        s.tab_picks[i] = widget.Submit { ctx: mem.cast[*void](&s.tab_args[i]), invoke: on_tab }
        i += 1usize
    }
    s.quick[0usize] = navigation.Action { label: "Save", action: s.subs[10usize], icon: zero, enabled: true }
    s.quick[1usize] = navigation.Action { label: "Undo", action: s.subs[11usize], icon: zero, enabled: true }
    s.quick[2usize] = navigation.Action { label: "Redo", action: s.subs[12usize], icon: zero, enabled: false }
    s.paste_items[0usize] = overlay.MenuItem { label: "Paste special", action: s.subs[13usize], enabled: true }
    s.paste_items[1usize] = overlay.MenuItem { label: "Paste values", action: s.subs[14usize], enabled: true }
    i = 0usize
    while i < 8usize {
        var names: [8]str = [8]str{ "Normal", "Heading 1", "Heading 2", "Title", "Quote", "Code", "Caption", "Emphasis" }
        s.gallery_items[i] = navigation.RibbonItem { label: names[i], action: widget.Submit { ctx: mem.cast[*void](&s.counters[15usize]), invoke: on_style }, selected: i == 1usize, enabled: true }
        i += 1usize
    }
    // Home: Clipboard, Font, Editing
    var paste = command("Paste", .Add, s.subs[0usize], true)
    paste.menu = s.paste_items[0usize..2usize]
    paste.menu_toggle = widget.Submit { ctx: mem.cast[*void](s), invoke: on_paste_menu }
    paste.menu_open = s.paste_menu
    paste.tooltip = "Paste from the clipboard"
    s.clipboard[0usize] = paste
    s.clipboard[1usize] = command("Cut", .Cross, s.subs[1usize], false)
    s.clipboard[2usize] = command("Copy", .Check, s.subs[2usize], false)
    var painter = command("Format painter", .Edit, s.subs[3usize], false)
    painter.toggle = true
    painter.checked = false
    s.clipboard[3usize] = painter
    var bold = command("Bold", .Edit, widget.Submit { ctx: mem.cast[*void](s), invoke: on_bold }, false)
    bold.toggle = true
    bold.checked = s.bold
    s.font[0usize] = bold
    s.font[1usize] = command("Italic", .Edit, s.subs[5usize], false)
    s.font[2usize] = command("Underline", .Edit, s.subs[6usize], false)
    var styles = command("Styles", .Settings, s.subs[7usize], false)
    styles.gallery = s.gallery_items[0usize..8usize]
    styles.columns = 4usize
    styles.rows = 1usize
    styles.gallery_open = s.gallery_open
    styles.gallery_toggle = widget.Submit { ctx: mem.cast[*void](s), invoke: on_gallery_menu }
    s.font[3usize] = styles
    var colour = command("Font colour", .Picture, zero, false)
    colour.menu = s.paste_items[0usize..2usize]
    colour.menu_toggle = s.subs[16usize]
    s.font[4usize] = colour
    s.editing[0usize] = command("Find", .Search, s.subs[8usize], true)
    s.editing[1usize] = command("Replace", .Refresh, s.subs[9usize], false)
    s.groups_home[0usize] = navigation.RibbonGroup { label: "Clipboard", commands: s.clipboard[0usize..4usize], launcher: s.subs[17usize], launcher_label: "Clipboard options" }
    s.groups_home[1usize] = navigation.RibbonGroup { label: "Font", commands: s.font[0usize..5usize], launcher: zero, launcher_label: "" }
    s.groups_home[2usize] = navigation.RibbonGroup { label: "Editing", commands: s.editing[0usize..2usize], launcher: zero, launcher_label: "" }
    s.tables[0usize] = command("Table", .Calendar, s.subs[18usize], true)
    s.tables[1usize] = command("Picture", .Picture, s.subs[19usize], true)
    s.groups_insert[0usize] = navigation.RibbonGroup { label: "Tables", commands: s.tables[0usize..2usize], launcher: zero, launcher_label: "" }
    s.zoom[0usize] = command("Zoom", .Visibility, s.subs[22usize], true)
    s.groups_view[0usize] = navigation.RibbonGroup { label: "Zoom", commands: s.zoom[0usize..1usize], launcher: zero, launcher_label: "" }
    s.tab_list[0usize] = navigation.RibbonTab { label: "Home", groups: s.groups_home[0usize..3usize], context: "", visible: true }
    s.tab_list[1usize] = navigation.RibbonTab { label: "Insert", groups: s.groups_insert[0usize..1usize], context: "", visible: true }
    s.tab_list[2usize] = navigation.RibbonTab { label: "View", groups: s.groups_view[0usize..1usize], context: "", visible: true }
    s.tab_list[3usize] = navigation.RibbonTab { label: "Design", groups: s.groups_insert[0usize..1usize], context: "Table Tools", visible: s.show_context }
    s.tab_list[4usize] = navigation.RibbonTab { label: "Layout", groups: s.groups_view[0usize..1usize], context: "Table Tools", visible: s.show_context }
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    setup(s)
    var options = navigation.ribbon_options()
    options.selected = s.selected
    options.collapsed = s.collapsed
    options.popup = s.popup
    options.picks = s.tab_picks[0usize..5usize]
    options.collapse = widget.Submit { ctx: mem.cast[*void](s), invoke: on_collapse }
    options.dismiss = widget.Submit { ctx: mem.cast[*void](s), invoke: on_dismiss }
    options.quick = s.quick[0usize..3usize]
    options.width = 900.0
    let (made, made_error) = navigation.ribbon(a, 1000u64, t, s.tab_list[0usize..5usize], options)
    if made_error != ok { ret (zero, made_error) }
    var page = style.defaults()
    page.width = style.Length { Px: 1000.0 }
    page.height = style.Length { Px: 600.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let (items, items_error) = mem.alloc[widget.Node](a, 1usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = made
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page, items[0usize..1usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 1200usize, max_states: 128usize, state_bytes: 8192usize, state_classes: 32u16, max_depth: 40u16, max_commands: 4096usize })
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
    s.show_context = true
    let (frame_storage, storage_error) = mem.alloc[u8](a, 4194304usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s)
    if build_error != ok { os.exit(9i32) }
    var clock = 1000000000i64
    if testing.pump(&harness, root, time.Instant { nanos: clock }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    // The tree: the region, the tab list, the tabs (the current one selected), the group and its commands.
    let (region, has_region) = find(tree, .Region, "Ribbon")
    let (tab_list, has_tab_list) = find(tree, .TabList, "Ribbon tabs")
    let (home, has_home) = find(tree, .Tab, "Home")
    let (insert, has_insert) = find(tree, .Tab, "Insert")
    let (design, has_design) = find(tree, .Tab, "Design")
    if !has_region || !has_tab_list || !has_home || !has_insert || !has_design || !home.state.selected || insert.state.selected { os.exit(13i32) }
    let (clipboard, has_clipboard) = find(tree, .Group, "Clipboard")
    let (home_panel, has_home_panel) = find(tree, .Group, "Home")
    let (quick_group, has_quick) = find(tree, .Group, "Quick access")
    let (paste_node, has_paste) = find(tree, .Button, "Paste")
    let (bold_node, has_bold) = find(tree, .Button, "Bold")
    if !has_clipboard || !has_home_panel || !has_quick || !has_paste || !has_bold || bold_node.state.checked { os.exit(14i32) }
    if testing.by_text(&harness, "Table Tools").count != 1usize { os.exit(15i32) }
    // The geometry: quick bar 32, band 20, strip 32, panel 100.
    let (strip_home, has_strip_home) = bounds(&harness, &runtime, 1100u64)
    let (strip_insert, has_strip_insert) = bounds(&harness, &runtime, 1101u64)
    let (strip_design, has_strip_design) = bounds(&harness, &runtime, 1103u64)
    let (strip_layout, has_strip_layout) = bounds(&harness, &runtime, 1104u64)
    let (band, has_band) = bounds(&harness, &runtime, 1300u64 + 3u64)
    if !has_strip_home || !has_strip_insert || !has_strip_design || !has_strip_layout || !has_band { os.exit(16i32) }
    if !near(strip_home.height, 32.0) || !near(strip_home.y, 52.0) || !near(band.height, 20.0) || !near(band.y, 32.0) || !near(band.x, strip_design.x) || !near(band.width, strip_layout.x + strip_layout.width - strip_design.x) { os.exit(17i32) }
    let (panel, has_panel) = bounds(&harness, &runtime, 1500u64)
    if !has_panel || !near(panel.y, 84.0) || !near(panel.height, 100.0) || !near(panel.width, 900.0) { os.exit(18i32) }
    let raised = style.color(&tokens, .SurfaceContainer)
    if !is_color(shot, at(strip_home.x + 20.0, strip_home.y + 20.0), raised) || !is_color(shot, at(panel.x + 5.0, panel.y + 90.0), raised) { os.exit(19i32) }
    if !is_color(shot, at(strip_insert.x + 20.0, strip_insert.y + 20.0), style.color(&tokens, .SurfaceContainerLow)) { os.exit(20i32) }
    if !is_color(shot, at(band.x + 4.0, band.y + 10.0), style.color(&tokens, .TertiaryContainer)) { os.exit(21i32) }
    // Every shown tab takes focus; the panel has one Tab stop.
    if !focusable(&harness, &runtime, 1100u64) || !focusable(&harness, &runtime, 1101u64) || !focusable(&harness, &runtime, 1102u64) { os.exit(22i32) }
    let paste_key = 1000u64 + 4096u64
    if !focusable(&harness, &runtime, paste_key) || focusable(&harness, &runtime, paste_key + 1u64 * 64u64) { os.exit(23i32) }
    // Presses: a plain command, a toggle (reports checked afterwards), a quick-access button, the launcher.
    if !tap_key(&harness, &runtime, paste_key + 64u64 * 1u64) || s.counters[1usize].count != 1usize { os.exit(24i32) }
    let cut_key = 1000u64 + 4096u64 + 1u64 * 64u64
    if !tap_key(&harness, &runtime, cut_key) || s.counters[1usize].count != 2usize { os.exit(25i32) }
    if !tap_key(&harness, &runtime, 1001u64 + 1u64) || s.counters[11usize].count != 1usize { os.exit(26i32) }
    if testing.by_key(&harness, 1001u64 + 2u64).count != 1usize { os.exit(27i32) }
    if !tap_key(&harness, &runtime, 1900u64) || s.counters[17usize].count != 1usize { os.exit(28i32) }
    let bold_key = 1000u64 + 4096u64 + (1u64 * 32u64 + 0u64) * 64u64
    if !tap_key(&harness, &runtime, bold_key) || !s.bold { os.exit(29i32) }
    clock += 100000000i64
    let (after_bold, after_bold_error) = build(&f, &theme, s)
    if after_bold_error != ok || testing.pump(&harness, after_bold, time.Instant { nanos: clock }) != ok { os.exit(30i32) }
    let (bold_tree, bold_tree_error) = testing.semantics(&harness)
    let (bold_on, has_bold_on) = find(bold_tree, .Button, "Bold")
    if bold_tree_error != ok || !has_bold_on || !bold_on.state.checked { os.exit(31i32) }
    // The split command: its arrow opens the menu; the menu's items appear.
    let arrow_key = paste_key + 1u64
    if !tap_key(&harness, &runtime, arrow_key) || !s.paste_menu { os.exit(32i32) }
    clock += 100000000i64
    let (menu_frame, menu_frame_error) = build(&f, &theme, s)
    if menu_frame_error != ok || testing.pump(&harness, menu_frame, time.Instant { nanos: clock }) != ok { os.exit(33i32) }
    let (menu_tree, menu_tree_error) = testing.semantics(&harness)
    let (special, has_special) = find(menu_tree, .MenuItem, "Paste special")
    let (menu_node, has_menu_node) = find(menu_tree, .Menu, "Paste")
    if menu_tree_error != ok || !has_special || !has_menu_node || testing.by_text(&harness, "Paste values").count == 0usize { os.exit(34i32) }
    let (paste_open, has_paste_open) = find(menu_tree, .Button, "Paste")
    if !has_paste_open { os.exit(56i32) }
    s.paste_menu = false
    // The gallery: four tiles show, the rest are behind its button; the current one is marked in the tree.
    clock += 100000000i64
    let (closed_menu, closed_menu_error) = build(&f, &theme, s)
    if closed_menu_error != ok || testing.pump(&harness, closed_menu, time.Instant { nanos: clock }) != ok { os.exit(35i32) }
    let styles_key = 1000u64 + 4096u64 + (1u64 * 32u64 + 3u64) * 64u64
    if testing.by_key(&harness, styles_key + 24u64 + 3u64).count != 1usize || testing.by_key(&harness, styles_key + 24u64 + 4u64).count != 0usize { os.exit(36i32) }
    if !tap_key(&harness, &runtime, styles_key + 24u64 + 2u64) || s.counters[15usize].count != 1usize { os.exit(37i32) }
    if !tap_key(&harness, &runtime, styles_key + 1u64) || !s.gallery_open { os.exit(38i32) }
    clock += 100000000i64
    let (gallery_frame, gallery_frame_error) = build(&f, &theme, s)
    if gallery_frame_error != ok || testing.pump(&harness, gallery_frame, time.Instant { nanos: clock }) != ok { os.exit(39i32) }
    if testing.by_key(&harness, styles_key + 24u64 + 7u64).count != 1usize { os.exit(40i32) }
    s.gallery_open = false
    // Tabs: a press picks, the new tab's panel replaces the old.
    clock += 100000000i64
    let (gallery_shut, gallery_shut_error) = build(&f, &theme, s)
    if gallery_shut_error != ok || testing.pump(&harness, gallery_shut, time.Instant { nanos: clock }) != ok { os.exit(41i32) }
    if !tap_key(&harness, &runtime, 1101u64) || s.picks.last != 1usize { os.exit(42i32) }
    clock += 100000000i64
    let (insert_frame, insert_frame_error) = build(&f, &theme, s)
    if insert_frame_error != ok || testing.pump(&harness, insert_frame, time.Instant { nanos: clock }) != ok { os.exit(43i32) }
    let (insert_tree, insert_tree_error) = testing.semantics(&harness)
    let (tables, has_tables) = find(insert_tree, .Group, "Tables")
    let (insert_now, has_insert_now) = find(insert_tree, .Tab, "Insert")
    let (no_clipboard, has_no_clipboard) = find(insert_tree, .Group, "Clipboard")
    if insert_tree_error != ok || !has_tables || !has_insert_now || !insert_now.state.selected || has_no_clipboard { os.exit(44i32) }
    // Keys: Right on the focused tab picks the next visible tab (View) and moves the focus; Home and End go to the ends.
    if !widget.focus_within(&runtime, 1101u64) { os.exit(45i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || s.picks.last != 2usize || !widget.focus_within(&runtime, 1102u64) { os.exit(46i32) }
    clock += 100000000i64
    let (view_frame, view_frame_error) = build(&f, &theme, s)
    if view_frame_error != ok || testing.pump(&harness, view_frame, time.Instant { nanos: clock }) != ok { os.exit(47i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || s.picks.last != 3usize || !widget.focus_within(&runtime, 1103u64) { os.exit(48i32) }
    clock += 100000000i64
    let (design_frame, design_frame_error) = build(&f, &theme, s)
    if design_frame_error != ok || testing.pump(&harness, design_frame, time.Instant { nanos: clock }) != ok { os.exit(49i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || s.picks.last != 4usize || !widget.focus_within(&runtime, 1104u64) { os.exit(50i32) }
    clock += 100000000i64
    let (layout_frame, layout_frame_error) = build(&f, &theme, s)
    if layout_frame_error != ok || testing.pump(&harness, layout_frame, time.Instant { nanos: clock }) != ok { os.exit(51i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || s.picks.last != 4usize { os.exit(52i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || s.picks.last != 0usize || !widget.focus_within(&runtime, 1100u64) { os.exit(53i32) }
    clock += 100000000i64
    let (home_frame, home_frame_error) = build(&f, &theme, s)
    if home_frame_error != ok || testing.pump(&harness, home_frame, time.Instant { nanos: clock }) != ok { os.exit(54i32) }
    // Down enters the panel at its first control; Right moves along, End goes to the last (the launcher); Escape
    // and Up return to the current tab.
    if testing.press_key(&harness, 40u32, zero) != ok || !widget.focus_within(&runtime, paste_key) { os.exit(55i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || !widget.focus_within(&runtime, paste_key + 1u64) { os.exit(57i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || !widget.focus_within(&runtime, cut_key) { os.exit(58i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !widget.focus_within(&runtime, 1000u64 + 900u64 + 2u64) && !widget.focus_within(&runtime, 1000u64 + 4096u64 + (2u64 * 32u64 + 1u64) * 64u64) { os.exit(59i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !widget.focus_within(&runtime, paste_key) { os.exit(60i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || !widget.focus_within(&runtime, 1100u64) { os.exit(61i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || testing.press_key(&harness, 38u32, zero) != ok || !widget.focus_within(&runtime, 1100u64) { os.exit(62i32) }
    // Contextual tabs come and go; the band goes with them; the quick-access Redo is disabled.
    s.show_context = false
    clock += 100000000i64
    let (plain_frame, plain_frame_error) = build(&f, &theme, s)
    if plain_frame_error != ok || testing.pump(&harness, plain_frame, time.Instant { nanos: clock }) != ok { os.exit(63i32) }
    if testing.by_key(&harness, 1103u64).count != 0usize || testing.by_key(&harness, 1104u64).count != 0usize || testing.by_text(&harness, "Table Tools").count != 0usize { os.exit(64i32) }
    let (plain_tree, plain_tree_error) = testing.semantics(&harness)
    let (redo, has_redo) = find(plain_tree, .Button, "Redo")
    if plain_tree_error != ok || !has_redo || !redo.state.disabled { os.exit(65i32) }
    // Collapsed: the strip and the quick bar only; a tab press floats the panel under it; Escape puts it away.
    if !tap_key(&harness, &runtime, 1090u64) || !s.collapsed || s.counters[20usize].count != 1usize { os.exit(66i32) }
    clock += 100000000i64
    let (collapsed_frame, collapsed_frame_error) = build(&f, &theme, s)
    if collapsed_frame_error != ok || testing.pump(&harness, collapsed_frame, time.Instant { nanos: clock }) != ok { os.exit(67i32) }
    if testing.by_key(&harness, 1500u64).count != 0usize || testing.by_key(&harness, paste_key).count != 0usize { os.exit(68i32) }
    let (collapsed_tree, collapsed_tree_error) = testing.semantics(&harness)
    let (expand, has_expand) = find(collapsed_tree, .Button, "Expand the ribbon")
    if collapsed_tree_error != ok || !has_expand { os.exit(69i32) }
    if !tap_key(&harness, &runtime, 1101u64) || !s.popup || s.picks.last != 1usize { os.exit(70i32) }
    clock += 100000000i64
    let (popup_frame, popup_frame_error) = build(&f, &theme, s)
    if popup_frame_error != ok || testing.pump(&harness, popup_frame, time.Instant { nanos: clock }) != ok { os.exit(71i32) }
    let tables_key = 1000u64 + 4096u64
    let (floating, has_floating) = bounds(&harness, &runtime, tables_key)
    let (anchor, has_anchor) = bounds(&harness, &runtime, 1101u64)
    if testing.by_key(&harness, 1500u64).count != 1usize || !has_floating || !has_anchor || floating.y < anchor.y + anchor.height - 1.0 { os.exit(72i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || s.popup || s.counters[21usize].count == 0usize { os.exit(73i32) }
    // Ctrl+F1 expands again.
    var ctrl: input.Modifiers = zero
    ctrl.control = true
    if testing.press_key(&harness, 112u32, ctrl) != ok || s.collapsed || s.counters[20usize].count != 2usize { os.exit(74i32) }
    try io.print("ui ribbon ok\n")
    ret ok
}
