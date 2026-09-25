// `e.ui.navigation` (D828, widget plan P1-15) under the light theme: an app bar
// names its page with a heading between its leading and trailing actions; a
// toolbar and a status bar are what they say in the tree; a navigation stack shows
// its top page under a back button that pops, as Escape and mouse Back do; the destination bar
// is a row at compact width and a column when expanded, its tabs picking.

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
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { fired: usize, last: usize, pops: usize, picks: usize, last_pick: usize }
type Numbered = struct { log: *Log, index: usize }

fn on_action(ctx: *void) -> err {
    let n = mem.cast[*Numbered](ctx)
    n.log.fired += 1usize
    n.log.last = n.index
    ret ok
}

fn on_pop(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.pops += 1usize
    ret ok
}

fn on_pick(ctx: *void) -> err {
    let n = mem.cast[*Numbered](ctx)
    n.log.picks += 1usize
    n.log.last_pick = n.index
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

fn build(a: *mem.Arena, t: *const control.Theme, actions: []const navigation.Action, pop: *const widget.Submit, picks: []const widget.Submit, depth: usize, width: f32) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 5usize)
    if parts_error != ok { ret (zero, parts_error) }
    let (bar, bar_error) = navigation.app_bar(a, 1u64, t, "Inbox", actions[0usize..1usize], actions[1usize..3usize], width)
    if bar_error != ok { ret (zero, bar_error) }
    parts[0usize] = bar
    let (tools, tools_error) = navigation.toolbar(a, 20u64, t, "Formatting", actions[3usize..5usize])
    if tools_error != ok { ret (zero, tools_error) }
    parts[1usize] = tools
    var sections: [2]str = zero
    sections[0usize] = "Ready"
    sections[1usize] = "Ln 1"
    let (status, status_error) = navigation.status_bar(a, 30u64, t, sections[..], width)
    if status_error != ok { ret (zero, status_error) }
    parts[2usize] = status
    var titles: [2]str = zero
    titles[0usize] = "Home"
    titles[1usize] = "Detail"
    var pages: [2]widget.Node = zero
    let (home, home_error) = control.text(a, 0u64, "Home page", t, control.text_options())
    if home_error != ok { ret (zero, home_error) }
    let (detail, detail_error) = control.text(a, 0u64, "Detail page", t, control.text_options())
    if detail_error != ok { ret (zero, detail_error) }
    pages[0usize] = home
    pages[1usize] = detail
    let (stack, stack_error) = navigation.navigation_stack(a, 40u64, t, titles[0usize..depth], pages[0usize..depth], pop, width)
    if stack_error != ok { ret (zero, stack_error) }
    parts[3usize] = stack
    var labels: [3]str = zero
    labels[0usize] = "Mail"
    labels[1usize] = "Calendar"
    labels[2usize] = "Contacts"
    let form = navigation.destination_form(width)
    var extent = width
    if form != .Bottom { extent = 120.0 }
    let (destinations, destinations_error) = navigation.destination_bar(a, 50u64, t, labels[..], 0usize, picks, form, extent)
    if destinations_error != ok { ret (zero, destinations_error) }
    parts[4usize] = destinations
    var column = style.defaults()
    column.width = style.Length { Px: width }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, column, parts[0usize..5usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 128usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 12u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 900u32, 400u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (numbers, numbers_error) = mem.alloc[Numbered](a, 8usize)
    if numbers_error != ok { os.exit(8i32) }
    let (actions, actions_error) = mem.alloc[navigation.Action](a, 5usize)
    if actions_error != ok { os.exit(9i32) }
    let (picks, picks_error) = mem.alloc[widget.Submit](a, 3usize)
    if picks_error != ok { os.exit(10i32) }
    var i = 0usize
    while i < 8usize {
        numbers[i] = Numbered { log: &logs[0usize], index: i }
        if i < 5usize { actions[i] = navigation.Action { label: "Menu", action: widget.Submit { ctx: mem.cast[*void](&numbers[i]), invoke: on_action }, icon: zero, enabled: true } }
        if i >= 5usize { picks[i - 5usize] = widget.Submit { ctx: mem.cast[*void](&numbers[i]), invoke: on_pick } }
        i += 1usize
    }
    actions[1usize].label = "Search"
    actions[2usize].label = "Compose"
    actions[3usize].label = "Bold"
    actions[4usize].label = "Italic"
    actions[4usize].enabled = false
    let (pops, pops_error) = mem.alloc[widget.Submit](a, 1usize)
    if pops_error != ok { os.exit(11i32) }
    pops[0usize] = widget.Submit { ctx: ctx, invoke: on_pop }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 524288usize)
    if storage_error != ok { os.exit(12i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, actions[0usize..5usize], &pops[0usize], picks[0usize..3usize], 1usize, 400.0)
    if build_error != ok { os.exit(13i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(14i32) }
    // The app bar: a group named by the title, the title a heading of level 1, the
    // actions buttons; a tap on Compose fires it.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(15i32) }
    let (bar_node, has_bar) = find(tree, .Group, "Inbox")
    let (title_node, has_title) = find(tree, .Heading, "Inbox")
    if !has_bar || !has_title || title_node.level != 1u8 { os.exit(16i32) }
    if testing.by_label(&harness, "Menu").count == 0usize || testing.by_label(&harness, "Search").count == 0usize { os.exit(17i32) }
    let (compose_at, has_compose) = centre_of(&harness, &runtime, 11u64)
    if !has_compose || testing.tap(&harness, compose_at.x, compose_at.y) != ok || logs[0usize].fired != 1usize || logs[0usize].last != 2usize { os.exit(18i32) }
    // The toolbar: a group named Formatting, Italic disabled; Bold fires.
    let (tools_node, has_tools) = find(tree, .Group, "Formatting")
    let (italic_node, has_italic) = find(tree, .Button, "Italic")
    if !has_tools || !has_italic || !italic_node.state.disabled { os.exit(19i32) }
    let (bold_at, has_bold) = centre_of(&harness, &runtime, 21u64)
    if !has_bold || testing.tap(&harness, bold_at.x, bold_at.y) != ok || logs[0usize].fired != 2usize || logs[0usize].last != 3usize { os.exit(20i32) }
    // The status bar: a polite status named by its message, the other section shown.
    let (status_node, has_status) = find(tree, .Status, "Ready")
    if !has_status || status_node.live != .Polite || testing.by_text(&harness, "Ln 1").count != 1usize { os.exit(21i32) }
    // The stack at depth 1: the home page, no back button, and Escape pops nothing.
    if testing.by_text(&harness, "Home page").count != 1usize || testing.by_label(&harness, "Back").count != 0usize { os.exit(22i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].pops != 0usize { os.exit(23i32) }
    // The destination bar at compact width: a tab list of three in a row; the
    // first selected; a tap on the second picks it.
    if testing.by_role(&harness, .Tab).count != 3usize { os.exit(24i32) }
    let (mail_node, has_mail) = find(tree, .Tab, "Mail")
    let (calendar_node, has_calendar) = find(tree, .Tab, "Calendar")
    if !has_mail || !has_calendar || !mail_node.state.selected || calendar_node.state.selected { os.exit(25i32) }
    if calendar_node.bounds.y != mail_node.bounds.y || calendar_node.bounds.x <= mail_node.bounds.x { os.exit(26i32) }
    let (calendar_at, has_calendar_at) = centre_of(&harness, &runtime, 52u64)
    if !has_calendar_at || testing.tap(&harness, calendar_at.x, calendar_at.y) != ok || logs[0usize].picks != 1usize || logs[0usize].last_pick != 6usize { os.exit(27i32) }
    // Depth 2 at expanded width: the detail page alone under a back button; a tap
    // on it pops, Escape from it pops again; the destinations stand in a column.
    let (root_2, build_2_error) = build(&frame, &theme, actions[0usize..5usize], &pops[0usize], picks[0usize..3usize], 2usize, 900.0)
    if build_2_error != ok { os.exit(28i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(29i32) }
    if testing.by_text(&harness, "Detail page").count != 1usize || testing.by_text(&harness, "Home page").count != 0usize { os.exit(30i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(31i32) }
    let (detail_group, has_detail) = find(tree_2, .Group, "Detail")
    if !has_detail { os.exit(32i32) }
    let (back_at, has_back) = centre_of(&harness, &runtime, 42u64)
    if !has_back || testing.tap(&harness, back_at.x, back_at.y) != ok || logs[0usize].pops != 1usize { os.exit(33i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].pops != 2usize { os.exit(34i32) }
    var alt: input.Modifiers = zero
    alt.alt = true
    if testing.press_key(&harness, 37u32, alt) != ok || logs[0usize].pops != 3usize { os.exit(38i32) }
    var mouse_back: input.Pointer = zero
    mouse_back.kind = .Mouse
    mouse_back.changed = .Back
    if testing.send(&harness, input.Event { PointerDown: mouse_back }) != ok || logs[0usize].pops != 4usize { os.exit(39i32) }
    var command: input.Modifiers = zero
    command.meta = true
    if testing.press_key(&harness, 219u32, command) != ok || logs[0usize].pops != 5usize { os.exit(40i32) }
    if testing.press_key(&harness, 91u32, command) != ok || logs[0usize].pops != 6usize { os.exit(41i32) }
    let (mail_2, has_mail_2) = find(tree_2, .Tab, "Mail")
    let (calendar_2, has_calendar_2) = find(tree_2, .Tab, "Calendar")
    if !has_mail_2 || !has_calendar_2 || calendar_2.bounds.y <= mail_2.bounds.y || calendar_2.bounds.x != mail_2.bounds.x { os.exit(35i32) }
    if navigation.destination_form(400.0) != .Bottom || navigation.destination_form(900.0) != .Rail || navigation.destination_form(1300.0) != .Sidebar { os.exit(36i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(37i32) }
    try io.print("ui navigation ok\n")
    ret ok
}
