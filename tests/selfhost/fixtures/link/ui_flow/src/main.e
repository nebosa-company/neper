// The flow editor (D2284, L091; e.ui.flow.flow_editor) under the light theme at pointer density, 900 by 460: the palette,
// canvas, inspector and lint strip in their places; nodes with their headers, ports and lint marks; node moves snapped to
// the grid; links made by dragging from a port to a port, refused with the reason when the rules say no; nodes added by
// dropping a palette item on the canvas; the inspector bound to the selected node (select, edit the label, commit); links
// selected and deleted, nodes deleted, the canvas panned; the lint strip counting problems and opening into a list whose
// rows select their node; and the tree naming the editor, canvas, nodes, palette items and problems.

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
use e.ui.flow as fl
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Store = struct {
    types: [4]fl.NodeType, nodes: [16]fl.Node, node_count: usize, links: [16]fl.Link, link_count: usize, params: [2]fl.Param,
    state: fl.FlowState, draft: [64]u8, events: usize, last: fl.FlowEvent, next_id: u32, kinds: [32]fl.FlowEventKind, kind_count: usize,
}

fn on_event(ctx: *void, e: fl.FlowEvent) -> err {
    let s = mem.cast[*Store](ctx)
    s.state = e.state
    s.events += 1usize
    s.last = e
    if s.kind_count < 32usize {
        s.kinds[s.kind_count] = e.kind
        s.kind_count += 1usize
    }
    if e.kind == .Move {
        let (i, found) = fl.node_index(graph_of(s), e.node)
        if found {
            s.nodes[i].x = e.x
            s.nodes[i].y = e.y
        }
    }
    if e.kind == .Connect && s.link_count < 16usize {
        s.links[s.link_count] = fl.Link { from: e.node, from_port: e.port, to: e.to_node, to_port: e.to_port }
        s.link_count += 1usize
    }
    if e.kind == .Add && s.node_count < 16usize {
        s.nodes[s.node_count] = fl.Node { id: s.next_id, kind: e.type_index, x: e.x, y: e.y, label: "", params: zero }
        s.next_id += 1u32
        s.node_count += 1usize
    }
    if e.kind == .Disconnect {
        var k = e.link
        while k + 1usize < s.link_count {
            s.links[k] = s.links[k + 1usize]
            k += 1usize
        }
        s.link_count -= 1usize
    }
    if e.kind == .Delete {
        let (i, found) = fl.node_index(graph_of(s), e.node)
        if found {
            var k = i
            while k + 1usize < s.node_count {
                s.nodes[k] = s.nodes[k + 1usize]
                k += 1usize
            }
            s.node_count -= 1usize
            var w = 0usize
            var r = 0usize
            while r < s.link_count {
                if s.links[r].from != e.node && s.links[r].to != e.node {
                    s.links[w] = s.links[r]
                    w += 1usize
                }
                r += 1usize
            }
            s.link_count = w
        }
    }
    if e.kind == .InspectStart {
        let (i, found) = fl.node_index(graph_of(s), e.node)
        if found {
            var value = s.nodes[i].label
            if e.field > 0usize { value = s.nodes[i].params[e.field - 1usize].value }
            mem.copy[u8](s.draft[0..], value)
            s.state.len = value.len
        }
    }
    if e.kind == .InspectCommit {
        let (i, found) = fl.node_index(graph_of(s), e.node)
        if found && e.field == 0usize { s.nodes[i].label = copy_label(s, e.text) }
    }
    ret ok
}

fn copy_label(s: *Store, text: str) -> str {
    // keep the committed text in the store's own buffer
    mem.copy[u8](s.draft[32..], text)
    ret s.draft[32..32usize + text.len]
}

fn graph_of(s: *Store) -> fl.Graph {
    ret fl.Graph { types: s.types[0..], nodes: s.nodes[0..s.node_count], links: s.links[0..s.link_count] }
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

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn pointer(x: f32, y: f32, down: bool) -> input.Pointer {
    var buttons = 0u32
    if down { buttons = 1u32 }
    ret input.Pointer { window: testing.no_window(), device: 0u32, pointer: 0u32, kind: .Mouse, position: geometry.Point { x: x, y: y }, buttons: buttons, changed: .Primary }
}

type Rig = struct {
    harness: *testing.Harness, theme: *control.Theme, store: *Store, f: *mem.Arena, clock: i64, change: widget.Change[fl.FlowEvent], options: fl.FlowOptions,
}

fn frame(r: *Rig) -> err {
    let (made, made_error) = fl.flow_editor(r.f, 1000u64, r.theme, "Flow editor", graph_of(r.store), r.store.state, r.store.draft[0..32usize], r.change, 900.0, 460.0, r.options)
    if made_error != ok { ret made_error }
    var page = style.defaults()
    page.width = style.Length { Px: 1000.0 }
    page.height = style.Length { Px: 600.0 }
    page.background = paint.Brush { Solid: style.color(r.theme.tokens, .Background) }
    let (items, items_error) = mem.alloc[widget.Node](r.f, 1usize)
    if items_error != ok { ret items_error }
    items[0usize] = made
    let root = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, page, items[0usize..1usize])
    r.clock += 50000000i64
    ret testing.pump(r.harness, root, time.Instant { nanos: r.clock })
}

// A drag in steps, the editor rebuilt after each pointer event the way a frame loop would.
fn drag_steps(r: *Rig, from: geometry.Point, to: geometry.Point) -> err {
    try testing.send(r.harness, input.Event { PointerDown: pointer(from.x, from.y, true) })
    try frame(r)
    var k = 1usize
    while k <= 4usize {
        let t = f32(k) / 4.0
        try testing.send(r.harness, input.Event { PointerMove: pointer(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t, true) })
        try frame(r)
        k += 1usize
    }
    try testing.send(r.harness, input.Event { PointerUp: pointer(to.x, to.y, false) })
    ret frame(r)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (rr, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = rr
    let tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 6000usize, max_states: 512usize, state_bytes: 16384usize, state_classes: 32u16, max_depth: 64u16, max_commands: 16384usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    var theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 1000u32, 600u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    let in0: [0]str = zero
    let in1 = [1]str{ "in" }
    let in2 = [2]str{ "a", "b" }
    let out0: [0]str = zero
    let out1 = [1]str{ "out" }
    let out2 = [2]str{ "yes", "no" }
    s.types[0usize] = fl.NodeType { name: "Source", inputs: in0[0..], outputs: out1[0..], required: 0u32 }
    s.types[1usize] = fl.NodeType { name: "Filter", inputs: in1[0..], outputs: out2[0..], required: 1u32 }
    s.types[2usize] = fl.NodeType { name: "Join", inputs: in2[0..], outputs: out1[0..], required: 3u32 }
    s.types[3usize] = fl.NodeType { name: "Sink", inputs: in1[0..], outputs: out0[0..], required: 1u32 }
    s.params[0usize] = fl.Param { name: "threshold", value: "100" }
    s.nodes[0usize] = fl.Node { id: 1u32, kind: 0usize, x: 40.0, y: 40.0, label: "Orders", params: zero }
    s.nodes[1usize] = fl.Node { id: 2u32, kind: 1usize, x: 280.0, y: 40.0, label: "Big", params: s.params[0usize..1usize] }
    s.nodes[2usize] = fl.Node { id: 3u32, kind: 3usize, x: 40.0, y: 220.0, label: "Archive", params: zero }
    s.nodes[3usize] = fl.Node { id: 4u32, kind: 2usize, x: 280.0, y: 200.0, label: "Merge", params: zero }
    s.node_count = 4usize
    s.links[0usize] = fl.Link { from: 1u32, from_port: 0usize, to: 2u32, to_port: 0usize }
    s.links[1usize] = fl.Link { from: 2u32, from_port: 0usize, to: 3u32, to_port: 0usize }
    s.link_count = 2usize
    s.next_id = 10u32
    s.state = fl.FlowState { view: fl.View { pan_x: 0.0, pan_y: 0.0 }, selected: 0u32, has_selected: false, selected_link: 0usize, has_link: false, drag: fl.none_drag(), field: 0usize, editing: false, len: 0usize, lint_open: false }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 8388608usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    var rig = Rig { harness: &harness, theme: &theme, store: s, f: &f, clock: 1000000000i64, change: widget.Change[fl.FlowEvent] { ctx: mem.cast[*void](s), invoke: on_event }, options: fl.flow_options() }
    if frame(&rig) != ok { os.exit(9i32) }
    if frame(&rig) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let (tree_mem, tree_mem_error) = mem.alloc[u8](a, 16777216usize)
    if tree_mem_error != ok { os.exit(12i32) }
    var tree_arena = mem.arena_from(tree_mem)
    let (tree, tree_error) = accessibility.build(&tree_arena, &runtime)
    if tree_error != ok { os.exit(13i32) }
    // The tree.
    let (root_node, has_root) = find(tree, .Group, "Flow editor")
    let (canvas_node, has_canvas) = find(tree, .Region, "Canvas")
    let (orders, has_orders) = find(tree, .Group, "Orders (Source)")
    let (add_filter, has_add) = find(tree, .ListItem, "Add Filter")
    let (status, has_status) = find(tree, .Status, "2 errors, 2 warnings")
    if !has_root || !has_canvas || !has_orders || !has_add { os.exit(14i32) }
    if !has_status { os.exit(15i32) }
    // The panes: the palette 168 wide, the canvas after it, the inspector 220 at the end, the strip 32 along the bottom.
    let (o, has_o) = bounds(&harness, &runtime, 1000u64)
    let (orders_box, has_orders_box) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 1u64)
    if !has_o || !has_orders_box || !near(orders_box.x - o.x, 168.0 + 40.0) || !near(orders_box.y - o.y, 40.0) || !near(orders_box.width, 160.0) || !near(orders_box.height, 28.0 + 20.0 + 8.0) { os.exit(16i32) }
    let (filter_box, has_filter_box) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 2u64)
    if !has_filter_box || !near(filter_box.height, 28.0 + 40.0 + 8.0) { os.exit(17i32) }
    // Pixels: the canvas ground, the header of a node, its selected border later, and the lint marks (errors on Merge and the
    // sink's neighbours; a warning dot is amber).
    if !is_color(shot, at(o.x + 168.0 + 407.0, o.y + 307.0), style.color(&tokens, .SurfaceContainerLowest)) { os.exit(18i32) }
    if !is_color(shot, at(orders_box.x + 40.0, orders_box.y + 4.0), style.color(&tokens, .SecondaryContainer)) { os.exit(19i32) }
    let (merge_box, has_merge_box) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 4u64)
    if !has_merge_box || !is_color(shot, at(merge_box.x + merge_box.width - 11.0, merge_box.y + 14.0), style.color(&tokens, .Error)) { os.exit(20i32) }
    if !is_color(shot, at(o.x + 10.0, o.y + 436.0), style.color(&tokens, .SurfaceContainer)) { os.exit(21i32) }
    // A tap selects a node; the inspector shows it.
    if testing.tap(&harness, orders_box.x + 40.0, orders_box.y + 10.0) != ok || s.last.kind != .Select || s.last.node != 1u32 || !s.state.has_selected || s.state.selected != 1u32 { os.exit(22i32) }
    if frame(&rig) != ok { os.exit(23i32) }
    let (selected_shot, selected_shot_error) = testing.snapshot(&harness, a)
    if selected_shot_error != ok || !is_color(selected_shot, at(orders_box.x + 40.0, orders_box.y), style.color(&tokens, .Primary)) { os.exit(24i32) }
    // Moving a node: drag Orders' header 60 right and 33 down; it lands snapped to the grid (100, 80).
    if drag_steps(&rig, geometry.Point { x: orders_box.x + 40.0, y: orders_box.y + 10.0 }, geometry.Point { x: orders_box.x + 100.0, y: orders_box.y + 43.0 }) != ok { os.exit(25i32) }
    if s.nodes[0usize].x != 100.0 || s.nodes[0usize].y != 80.0 || s.state.drag.kind != .None { os.exit(26i32) }
    let (moved, has_moved) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 1u64)
    if !has_moved || !near(moved.x - o.x, 168.0 + 100.0) || !near(moved.y - o.y, 80.0) { os.exit(27i32) }
    // Panning: drag empty canvas left and up by 30 and 20: the content follows the pointer, the pan grows by that.
    if drag_steps(&rig, geometry.Point { x: o.x + 168.0 + 440.0, y: o.y + 330.0 }, geometry.Point { x: o.x + 168.0 + 410.0, y: o.y + 310.0 }) != ok { os.exit(28i32) }
    if !near(s.state.view.pan_x, 30.0) || !near(s.state.view.pan_y, 20.0) { os.exit(29i32) }
    // Pan back so the following coordinates hold.
    s.state.view = fl.View { pan_x: 0.0, pan_y: 0.0 }
    if frame(&rig) != ok { os.exit(30i32) }
    // Connecting: Filter's `no` output (port 1) dragged to Merge's `a` input (port 0).
    let (filter_now, has_filter_now) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 2u64)
    let (merge_now, has_merge_now) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 4u64)
    if !has_filter_now || !has_merge_now { os.exit(31i32) }
    let no_port = geometry.Point { x: filter_now.x + 160.0, y: filter_now.y + 28.0 + 20.0 + 10.0 }
    let a_port = geometry.Point { x: merge_now.x, y: merge_now.y + 28.0 + 10.0 }
    let links_before = s.link_count
    if drag_steps(&rig, no_port, a_port) != ok { os.exit(32i32) }
    if s.last.kind != .Connect || s.link_count != links_before + 1usize || s.last.node != 2u32 || s.last.port != 1usize || s.last.to_node != 4u32 || s.last.to_port != 0usize { os.exit(33i32) }
    // Refused: Orders' output onto the Archive's input that Big's `yes` already feeds.
    let (orders_now, has_orders_now) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 1u64)
    let (archive_now, has_archive_now) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 3u64)
    if !has_orders_now || !has_archive_now { os.exit(34i32) }
    let out_port = geometry.Point { x: orders_now.x + 160.0, y: orders_now.y + 38.0 }
    let in_port = geometry.Point { x: archive_now.x, y: archive_now.y + 38.0 }
    if drag_steps(&rig, out_port, in_port) != ok { os.exit(35i32) }
    if s.last.kind != .Refuse || s.last.reason != .InputTaken || s.link_count != links_before + 1usize { os.exit(36i32) }
    // Refused: Big's `yes` output dropped on Big's own input.
    let (own, has_own) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 2u64)
    if !has_own { os.exit(37i32) }
    if drag_steps(&rig, geometry.Point { x: own.x + 160.0, y: own.y + 38.0 }, geometry.Point { x: own.x, y: own.y + 38.0 }) != ok { os.exit(70i32) }
    if s.last.kind != .Refuse || s.last.reason != .SelfLoop || s.link_count != links_before + 1usize { os.exit(71i32) }
    // Dropped on bare canvas, a link drag ends without a link.
    if drag_steps(&rig, out_port, geometry.Point { x: o.x + 168.0 + 440.0, y: o.y + 330.0 }) != ok { os.exit(38i32) }
    if s.last.kind != .DragEnd || s.link_count != links_before + 1usize || s.state.drag.kind != .None { os.exit(39i32) }
    // Adding: drag the Join item (the third, 32 + 2 * 36 below the palette's top) onto the canvas at (420, 330 in the canvas).
    let node_count_before = s.node_count
    if drag_steps(&rig, geometry.Point { x: o.x + 40.0, y: o.y + 32.0 + 72.0 + 10.0 }, geometry.Point { x: o.x + 168.0 + 420.0, y: o.y + 330.0 }) != ok { os.exit(40i32) }
    if s.last.kind != .Add || s.last.type_index != 2usize || s.node_count != node_count_before + 1usize { os.exit(41i32) }
    if s.nodes[s.node_count - 1usize].x != 340.0 || s.nodes[s.node_count - 1usize].y != 320.0 || s.nodes[s.node_count - 1usize].id != 10u32 { os.exit(42i32) }
    // A drop in the inspector adds nothing.
    let adds = s.node_count
    if drag_steps(&rig, geometry.Point { x: o.x + 40.0, y: o.y + 32.0 + 10.0 }, geometry.Point { x: o.x + 700.0, y: o.y + 200.0 }) != ok { os.exit(43i32) }
    if s.node_count != adds || s.last.kind != .DragEnd { os.exit(44i32) }
    // The inspector: select Big, tap its label row, edit, commit.
    let (big, has_big) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 2u64)
    if !has_big || testing.tap(&harness, big.x + 40.0, big.y + 10.0) != ok || s.state.selected != 2u32 { os.exit(45i32) }
    if frame(&rig) != ok { os.exit(46i32) }
    let (label_row, has_label_row) = bounds(&harness, &runtime, 1000u64 + 2048u64)
    let (param_row, has_param_row) = bounds(&harness, &runtime, 1000u64 + 2048u64 + 1u64)
    if !has_label_row || !has_param_row || !near(label_row.x - o.x, 680.0 + 12.0) || !near(param_row.y - label_row.y, 44.0) { os.exit(47i32) }
    if testing.tap(&harness, label_row.x + 40.0, label_row.y + 30.0) != ok || s.last.kind != .InspectStart || s.last.field != 0usize || !s.state.editing || s.state.len != 3usize || !same(s.draft[..3usize], "Big") { os.exit(48i32) }
    if frame(&rig) != ok { os.exit(49i32) }
    if frame(&rig) != ok { os.exit(50i32) }
    if testing.type_text(&harness, "!") != ok || s.last.kind != .InspectType { os.exit(51i32) }
    if frame(&rig) != ok { os.exit(52i32) }
    if testing.press_key(&harness, 13u32, zero) != ok || s.last.kind != .InspectCommit || !same(s.last.text, "!Big") || s.state.editing { os.exit(53i32) }
    if frame(&rig) != ok { os.exit(54i32) }
    if !same(s.nodes[1usize].label, "!Big") { os.exit(55i32) }
    // Deleting: a selected node goes with its links (Delete key); a selected link goes alone.
    let links_now = s.link_count
    let (archive_sel, has_archive_sel) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 3u64)
    if !has_archive_sel || testing.tap(&harness, archive_sel.x + 40.0, archive_sel.y + 10.0) != ok || s.state.selected != 3u32 { os.exit(56i32) }
    if frame(&rig) != ok { os.exit(57i32) }
    if testing.press_key(&harness, 46u32, zero) != ok || s.last.kind != .Delete || s.last.node != 3u32 || s.node_count != adds - 1usize || s.link_count != links_now - 1usize { os.exit(58i32) }
    if frame(&rig) != ok { os.exit(59i32) }
    // The Orders to Big link: tap its middle (the curve's midpoint).
    let (a_box, has_a_box) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 1u64)
    let (b_box, has_b_box) = bounds(&harness, &runtime, 1000u64 + 4096u64 + 2u64)
    if !has_a_box || !has_b_box { os.exit(60i32) }
    let from_pt = geometry.Point { x: a_box.x + 160.0, y: a_box.y + 38.0 }
    let to_pt = geometry.Point { x: b_box.x, y: b_box.y + 38.0 }
    let mid = fl.curve_point(from_pt, to_pt, 0.5)
    if testing.tap(&harness, mid.x, mid.y) != ok || s.last.kind != .SelectLink || !s.state.has_link { os.exit(61i32) }
    if frame(&rig) != ok { os.exit(62i32) }
    let links_then = s.link_count
    if testing.press_key(&harness, 46u32, zero) != ok || s.last.kind != .Disconnect || s.link_count != links_then - 1usize { os.exit(63i32) }
    if frame(&rig) != ok { os.exit(64i32) }
    // The lint strip: a tap on the bar opens the list; a row selects its node.
    let (strip_before, has_strip_before) = bounds(&harness, &runtime, 1000u64 + 3072u64)
    if !has_strip_before { os.exit(65i32) }
    if testing.tap(&harness, o.x + 450.0, o.y + 444.0) != ok || s.last.kind != .ToggleLint || !s.state.lint_open { os.exit(66i32) }
    if frame(&rig) != ok { os.exit(67i32) }
    let (row0, has_row0) = bounds(&harness, &runtime, 1000u64 + 3073u64)
    if !has_row0 { os.exit(68i32) }
    if testing.tap(&harness, row0.x + 60.0, row0.y + 8.0) != ok || s.last.kind != .Select || !s.state.has_selected { os.exit(69i32) }
    try io.print("ui flow ok\n")
    ret ok
}
