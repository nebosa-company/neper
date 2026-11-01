// The flow (node-graph) editor (e.ui.flow.flow_editor), docs/ui/looks/<look>/flow_editor.png in all ten looks. The palette of
// node types, the dotted canvas with its nodes, ports and cubic links, the inspector and the lint strip, all drawn through the
// shared tokens (surface containers, outline variant, primary selection). Cells: rest, a node selected (inspector fields),
// a link selected, the lint strip open, keyboard focus, hover over a node, disabled. A graph with an unconnected required input
// and an unreachable node, so the lint has warnings and errors to show. Derived; no platform has a native node editor to compare.

use e.mem
use e.ui.control
use e.ui.flow as fl
use e.ui.looks
use e.ui.widget

var in0: [0]str = zero
var in1: [1]str = zero
var in2: [2]str = zero
var out1: [1]str = zero
var out2: [2]str = zero
var types: [4]fl.NodeType = zero
var nodes: [5]fl.Node = zero
var links: [3]fl.Link = zero
var params: [1]fl.Param = zero
var draft: [64]u8 = zero

fn graph() -> fl.Graph {
    in1[0usize] = "in"
    in2[0usize] = "a"
    in2[1usize] = "b"
    out1[0usize] = "out"
    out2[0usize] = "yes"
    out2[1usize] = "no"
    types[0usize] = fl.NodeType { name: "Source", inputs: in0[0..], outputs: out1[0..], required: 0u32 }
    types[1usize] = fl.NodeType { name: "Filter", inputs: in1[0..], outputs: out2[0..], required: 1u32 }
    types[2usize] = fl.NodeType { name: "Join", inputs: in2[0..], outputs: out1[0..], required: 3u32 }
    types[3usize] = fl.NodeType { name: "Sink", inputs: in1[0..], outputs: in0[0..], required: 1u32 }
    params[0usize] = fl.Param { name: "threshold", value: "100" }
    nodes[0usize] = fl.Node { id: 1u32, kind: 0usize, x: 16.0, y: 16.0, label: "Orders", params: zero }
    nodes[1usize] = fl.Node { id: 2u32, kind: 1usize, x: 196.0, y: 16.0, label: "Big", params: params[0..1] }
    nodes[2usize] = fl.Node { id: 3u32, kind: 3usize, x: 16.0, y: 190.0, label: "Archive", params: zero }
    nodes[3usize] = fl.Node { id: 4u32, kind: 2usize, x: 196.0, y: 170.0, label: "Merge", params: zero }
    nodes[4usize] = fl.Node { id: 5u32, kind: 0usize, x: 16.0, y: 100.0, label: "Spare", params: zero }
    links[0usize] = fl.Link { from: 1u32, from_port: 0usize, to: 2u32, to_port: 0usize }
    links[1usize] = fl.Link { from: 2u32, from_port: 0usize, to: 4u32, to_port: 0usize }
    links[2usize] = fl.Link { from: 1u32, from_port: 0usize, to: 3u32, to_port: 0usize }
    ret fl.Graph { types: types[0..], nodes: nodes[0..5], links: links[0..3] }
}

fn on_event(ctx: *void, e: fl.FlowEvent) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [7]str{ "rest", "node selected", "link selected", "lint strip open", "focus", "hover over a node", "disabled" }
    let g = graph()
    var i = 0usize
    while i < 7usize {
        var state = fl.FlowState { view: fl.View { pan_x: 0.0, pan_y: 0.0 }, selected: 0u32, has_selected: false, selected_link: 0usize, has_link: false, drag: fl.none_drag(), field: 0usize, editing: false, len: 0usize, lint_open: false }
        var options = fl.flow_options()
        var drive: looks.Drive = .None
        if i == 1usize {
            state.selected = 2u32
            state.has_selected = true
        }
        if i == 2usize {
            state.selected_link = 1usize
            state.has_link = true
        }
        if i == 3usize { state.lint_open = true }
        if i == 4usize { drive = .Focus }
        if i == 5usize { drive = .Hover }
        if i == 6usize { options.disabled = true }
        let change = widget.Change[fl.FlowEvent] { ctx: nil, invoke: on_event }
        let (node, node_error) = fl.flow_editor(a, u64(i + 1usize) * 100000u64, t, "Flow editor", g, state, draft[0..], change, 760.0, 380.0, options)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: drive }
        if i == 5usize { looks.aim(i, -380.0 + 168.0 + 196.0 + 80.0, -190.0 + 16.0 + 14.0) }
        i += 1usize
    }
    ret (7usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "flow_editor", cells: 7usize, columns: 2usize, cell_w: 780.0, cell_h: 400.0, ctx: zero, build: build }
    try looks.run_all(a, &sheet)
    try looks.run_linux(a, &sheet)
    try looks.run_cupertino(a, &sheet)
    ret looks.run_material(a, &sheet)
}
