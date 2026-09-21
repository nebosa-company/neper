// `e.ui.navigation`'s adaptive navigation (D840, widget plan P2-08) under the
// light theme: a menu bar's titles open their menus; a context menu is a menu at
// its anchor; a navigation split is a split view at medium width and one page at
// compact width; a navigation drawer is a modal sidebar along the left edge that
// Escape dismisses; the rail, the bottom bar and the sidebar are the explicit
// forms; breadcrumbs link every name but the last.

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
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.navigation
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { toggles: usize, last_toggle: usize, commands: usize, dismisses: usize, picks: usize, last_pick: usize, sizes: usize, crumbs: usize, last_crumb: usize }
type Numbered = struct { log: *Log, index: usize }

fn on_toggle(ctx: *void) -> err {
    let n = mem.cast[*Numbered](ctx)
    n.log.toggles += 1usize
    n.log.last_toggle = n.index
    ret ok
}

fn on_command(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.commands += 1usize
    ret ok
}

fn on_dismiss(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.dismisses += 1usize
    ret ok
}

fn on_pick(ctx: *void) -> err {
    let n = mem.cast[*Numbered](ctx)
    n.log.picks += 1usize
    n.log.last_pick = n.index
    ret ok
}

fn on_size(ctx: *void, value: f32) -> err {
    let log = mem.cast[*Log](ctx)
    log.sizes += 1usize
    ret ok
}

fn on_crumb(ctx: *void) -> err {
    let n = mem.cast[*Numbered](ctx)
    n.log.crumbs += 1usize
    n.log.last_crumb = n.index
    ret ok
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

type Actions = struct { toggles: []widget.Submit, picks: []widget.Submit, crumbs: []widget.Submit, dismiss: widget.Submit, menus: []navigation.MenuBarItem, items: []overlay.MenuItem }

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, acts: *const Actions, open_menu: usize, context_open: bool, drawer_open: bool, width: f32, showing_detail: bool) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 7usize)
    if parts_error != ok { ret (zero, parts_error) }
    let (bar, bar_error) = navigation.menu_bar(a, 1u64, t, "Menu bar", acts.menus, open_menu, acts.toggles[0usize..2usize])
    if bar_error != ok { ret (zero, bar_error) }
    parts[0usize] = bar
    let (item_button, item_error) = control.button(a, 10u64, t, "Item", &acts.toggles[2usize], control.button_options())
    if item_error != ok { ret (zero, item_error) }
    parts[1usize] = item_button
    let (popup, popup_error) = navigation.context_menu(a, 11u64, t, 10u64, "Item actions", acts.items, context_open, &acts.dismiss)
    if popup_error != ok { ret (zero, popup_error) }
    parts[2usize] = popup
    let (primary, primary_error) = control.text(a, 0u64, "Folders", t, control.text_options())
    if primary_error != ok { ret (zero, primary_error) }
    let (detail, detail_error) = control.text(a, 0u64, "Messages", t, control.text_options())
    if detail_error != ok { ret (zero, detail_error) }
    let (split, split_error) = navigation.navigation_split(a, 20u64, t, primary, detail, showing_detail, 150.0, widget.Change[f32] { ctx: ctx, invoke: on_size }, width, 80.0)
    if split_error != ok { ret (zero, split_error) }
    parts[3usize] = split
    var labels: [3]str = zero
    labels[0usize] = "Mail"
    labels[1usize] = "Calendar"
    labels[2usize] = "Contacts"
    let (drawer, drawer_error) = navigation.navigation_drawer(a, 30u64, t, labels[..], 0usize, acts.picks, drawer_open, &acts.dismiss, 160.0)
    if drawer_error != ok { ret (zero, drawer_error) }
    parts[4usize] = drawer
    let (rail, rail_error) = navigation.navigation_rail(a, 40u64, t, labels[..], 1usize, acts.picks, 72.0)
    if rail_error != ok { ret (zero, rail_error) }
    parts[5usize] = rail
    var names: [3]str = zero
    names[0usize] = "Home"
    names[1usize] = "Docs"
    names[2usize] = "Widgets"
    let (trail, trail_error) = navigation.breadcrumbs(a, 50u64, t, "Path", names[..], acts.crumbs)
    if trail_error != ok { ret (zero, trail_error) }
    parts[6usize] = trail
    var column = style.defaults()
    column.width = style.Length { Px: width }
    column.height = style.Length { Px: 500.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, parts[0usize..7usize]), ok)
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn centre_of(h: *testing.Harness, runtime: *const widget.Runtime, key: widget.Key) -> (geometry.Point, bool) {
    let found = testing.by_key(h, key)
    if found.count != 1usize { ret (zero, false) }
    let (area, has_area) = widget.bounds_of(runtime, found.element)
    if !has_area { ret (zero, false) }
    ret (geometry.Point { x: area.x + area.width * 0.5, y: area.y + area.height * 0.5 }, true)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 200usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 512usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 700u32, 500u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (numbers, numbers_error) = mem.alloc[Numbered](a, 9usize)
    if numbers_error != ok { os.exit(8i32) }
    let (subs, subs_error) = mem.alloc[widget.Submit](a, 9usize)
    if subs_error != ok { os.exit(9i32) }
    var i = 0usize
    while i < 9usize {
        numbers[i] = Numbered { log: &logs[0usize], index: i % 3usize }
        subs[i] = widget.Submit { ctx: mem.cast[*void](&numbers[i]), invoke: on_pick }
        if i < 3usize { subs[i] = widget.Submit { ctx: mem.cast[*void](&numbers[i]), invoke: on_toggle } }
        if i >= 6usize { subs[i] = widget.Submit { ctx: mem.cast[*void](&numbers[i]), invoke: on_crumb } }
        i += 1usize
    }
    let (items, items_error) = mem.alloc[overlay.MenuItem](a, 2usize)
    if items_error != ok { os.exit(10i32) }
    items[0usize] = overlay.MenuItem { label: "Open", action: widget.Submit { ctx: ctx, invoke: on_command }, enabled: true }
    items[1usize] = overlay.MenuItem { label: "Rename", action: widget.Submit { ctx: ctx, invoke: on_command }, enabled: true }
    let (menus, menus_error) = mem.alloc[navigation.MenuBarItem](a, 2usize)
    if menus_error != ok { os.exit(11i32) }
    menus[0usize] = navigation.MenuBarItem { label: "File", items: items[0usize..2usize] }
    menus[1usize] = navigation.MenuBarItem { label: "Edit", items: items[0usize..1usize] }
    let (acts, acts_error) = mem.alloc[Actions](a, 1usize)
    if acts_error != ok { os.exit(12i32) }
    acts[0usize] = Actions { toggles: subs[0usize..3usize], picks: subs[3usize..6usize], crumbs: subs[6usize..9usize], dismiss: widget.Submit { ctx: ctx, invoke: on_dismiss }, menus: menus[0usize..2usize], items: items[0usize..2usize] }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(13i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, ctx, &acts[0usize], 9usize, false, false, 700.0, false)
    if build_error != ok { os.exit(14i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(15i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(16i32) }
    // The menu bar: a group of two menu buttons, none open; a tap on File fires
    // its toggle; open, File's menu holds two items under the button.
    let (bar, has_bar) = find(tree, .Group, "Menu bar")
    if !has_bar || testing.by_role(&harness, .MenuItem).count != 0usize { os.exit(17i32) }
    let (file_at, has_file) = centre_of(&harness, &runtime, 2u64)
    if !has_file || testing.tap(&harness, file_at.x, file_at.y) != ok || logs[0usize].toggles != 1usize || logs[0usize].last_toggle != 0usize { os.exit(18i32) }
    let (root_2, build_2_error) = build(&frame, &theme, ctx, &acts[0usize], 0usize, false, false, 700.0, false)
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(19i32) }
    if testing.by_role(&harness, .MenuItem).count != 2usize || testing.by_key(&harness, 3u64).count != 1usize { os.exit(20i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || logs[0usize].commands != 1usize { os.exit(21i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].toggles != 2usize { os.exit(22i32) }
    // The context menu: open, it lies under Item with its two items; Escape
    // dismisses.
    let (root_3, build_3_error) = build(&frame, &theme, ctx, &acts[0usize], 9usize, true, false, 700.0, false)
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(23i32) }
    let (item_bounds, has_item) = widget.bounds_of(&runtime, testing.by_key(&harness, 10u64).element)
    let (menu_bounds, has_menu) = testing.overlay_of(&harness, testing.by_key(&harness, 11u64).element)
    if !has_item || !has_menu || menu_bounds.y < item_bounds.y + item_bounds.height || testing.by_role(&harness, .MenuItem).count != 2usize { os.exit(24i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].dismisses != 1usize { os.exit(25i32) }
    // The split at 700 wide (medium): both pages side by side; the handle nudges.
    let (root_4, build_4_error) = build(&frame, &theme, ctx, &acts[0usize], 9usize, false, false, 700.0, false)
    if build_4_error != ok || testing.pump(&harness, root_4, now) != ok { os.exit(26i32) }
    if testing.by_text(&harness, "Folders").count != 1usize || testing.by_text(&harness, "Messages").count != 1usize { os.exit(27i32) }
    let (grip_at, has_grip) = centre_of(&harness, &runtime, 23u64)
    if !has_grip || testing.tap(&harness, grip_at.x, grip_at.y) != ok || testing.press_key(&harness, 39u32, zero) != ok || logs[0usize].sizes == 0usize { os.exit(28i32) }
    // The drawer: open, a modal dialog named Navigation along the left edge with
    // three tabs, the first selected; Calendar picks; Escape dismisses.
    let (root_5, build_5_error) = build(&frame, &theme, ctx, &acts[0usize], 9usize, false, true, 700.0, false)
    if build_5_error != ok || testing.pump(&harness, root_5, now) != ok { os.exit(29i32) }
    let (tree_5, tree_5_error) = testing.semantics(&harness)
    if tree_5_error != ok { os.exit(30i32) }
    let (drawer_node, has_drawer) = find(tree_5, .Dialog, "Navigation")
    if !has_drawer || !drawer_node.state.modal { os.exit(31i32) }
    let (drawer_bounds, has_drawer_bounds) = testing.overlay_of(&harness, testing.by_key(&harness, 30u64).element)
    if !has_drawer_bounds || drawer_bounds.x != 0.0 { os.exit(32i32) }
    let (calendar_at, has_calendar) = centre_of(&harness, &runtime, 33u64)
    if !has_calendar || testing.tap(&harness, calendar_at.x, calendar_at.y) != ok || logs[0usize].picks != 1usize || logs[0usize].last_pick != 1usize { os.exit(33i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].dismisses != 2usize { os.exit(34i32) }
    // The rail: a column of three tabs, Calendar selected; the breadcrumbs: two
    // links and the current name; Docs fires its pick.
    let (root_6, build_6_error) = build(&frame, &theme, ctx, &acts[0usize], 9usize, false, false, 700.0, false)
    if build_6_error != ok || testing.pump(&harness, root_6, now) != ok { os.exit(35i32) }
    let (mail_bounds, has_mail) = widget.bounds_of(&runtime, testing.by_key(&harness, 41u64).element)
    let (contacts_bounds, has_contacts) = widget.bounds_of(&runtime, testing.by_key(&harness, 43u64).element)
    if !has_mail || !has_contacts || contacts_bounds.y <= mail_bounds.y || contacts_bounds.x != mail_bounds.x { os.exit(36i32) }
    if testing.by_role(&harness, .Link).count != 2usize || testing.by_text(&harness, "Widgets").count != 1usize { os.exit(37i32) }
    let (docs_at, has_docs) = centre_of(&harness, &runtime, 52u64)
    if !has_docs || testing.tap(&harness, docs_at.x, docs_at.y) != ok || logs[0usize].crumbs != 1usize || logs[0usize].last_crumb != 1usize { os.exit(38i32) }
    // The split at 400 wide (compact): the primary alone, then the detail alone.
    let (root_7, build_7_error) = build(&frame, &theme, ctx, &acts[0usize], 9usize, false, false, 400.0, false)
    if build_7_error != ok || testing.pump(&harness, root_7, now) != ok { os.exit(39i32) }
    if testing.by_text(&harness, "Folders").count != 1usize || testing.by_text(&harness, "Messages").count != 0usize { os.exit(40i32) }
    let (root_8, build_8_error) = build(&frame, &theme, ctx, &acts[0usize], 9usize, false, false, 400.0, true)
    if build_8_error != ok || testing.pump(&harness, root_8, now) != ok { os.exit(41i32) }
    if testing.by_text(&harness, "Folders").count != 0usize || testing.by_text(&harness, "Messages").count != 1usize { os.exit(42i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(43i32) }
    try io.print("ui adaptive ok\n")
    ret ok
}
