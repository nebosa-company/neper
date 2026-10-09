// A flow (node-graph) editor (D2284, L091). This first half is the model and geometry the visual editor stands on, pure and
// widget-free so a brute-force model can check it: node types with named input and output ports, nodes and links as the
// caller's plain data, where a node and its ports stand on the canvas, which thing a point hits (a port, a node, a link,
// the canvas), the links as cubic curves and their distance to a point, the rules a new link must meet and why one is
// refused, snapping, the layout of the editor's panes (palette, canvas, inspector, lint strip) and which pane a point is in,
// and the lint of a graph: unconnected required inputs, links to nothing, an input fed twice, cycles, nodes nothing reaches,
// isolated nodes, duplicate labels and duplicate ids. Coordinates are logical pixels; the canvas is panned, not zoomed.

use e.mem
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget

type NodeType = struct { name: str, inputs: []const str, outputs: []const str, required: u32 }
type Param = struct { name: str, value: str }
type Node = struct { id: u32, kind: usize, x: f32, y: f32, label: str, params: []const Param }
type Link = struct { from: u32, from_port: usize, to: u32, to_port: usize }
type Graph = struct { types: []const NodeType, nodes: []const Node, links: []const Link }
// The canvas's pan: the world position shown at the canvas's top-left corner.
type View = struct { pan_x: f32, pan_y: f32 }
type HitKind = enum u8 { Canvas, Node, InPort, OutPort, Link }
type Hit = struct { kind: HitKind, node: u32, index: usize, port: usize }
type Connect = enum u8 { Ok, SelfLoop, Duplicate, InputTaken, BadPort, UnknownNode, Cycle }
type Severity = enum u8 { Error, Warning }
type Code = enum u8 { DuplicateId, DanglingLink, InputFed, UnconnectedInput, Cycle, Unreachable, Isolated, DuplicateLabel }
type Issue = struct { severity: Severity, code: Code, node: u32, link: usize }
type Pane = enum u8 { None, Palette, Canvas, Inspector, Lint }
type Panes = struct { palette: geometry.Rect, canvas: geometry.Rect, inspector: geometry.Rect, lint: geometry.Rect }

error Invalid
error TooLarge

// Sizes of a node: 160 wide, a 28 header, 20 for each port row and 8 below; ports 6 in radius on the node's side edges.
fn node_width() -> f32 { ret 160.0 }
fn header_height() -> f32 { ret 28.0 }
fn port_row() -> f32 { ret 20.0 }
fn port_radius() -> f32 { ret 6.0 }
fn grid_step() -> f32 { ret 20.0 }

fn node_index(g: Graph, id: u32) -> (usize, bool) {
    var i = 0usize
    while i < g.nodes.len {
        if g.nodes[i].id == id { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn ports_of(g: Graph, node: usize) -> usize {
    let t = g.types[g.nodes[node].kind]
    if t.inputs.len > t.outputs.len { ret t.inputs.len }
    ret t.outputs.len
}

fn node_height(g: Graph, node: usize) -> f32 {
    ret header_height() + f32(ports_of(g, node)) * port_row() + 8.0
}

// The node's rectangle in world coordinates.
fn node_rect(g: Graph, node: usize) -> geometry.Rect {
    ret geometry.rect(g.nodes[node].x, g.nodes[node].y, node_width(), node_height(g, node))
}

// A port's centre in world coordinates: on the left edge for an input, the right edge for an output.
fn port_pos(g: Graph, node: usize, output: bool, port: usize) -> geometry.Point {
    let r = node_rect(g, node)
    var x = r.x
    if output { x = r.x + r.width }
    ret geometry.Point { x: x, y: r.y + header_height() + f32(port) * port_row() + port_row() * 0.5 }
}

fn to_screen(v: View, canvas: geometry.Rect, p: geometry.Point) -> geometry.Point {
    ret geometry.Point { x: canvas.x + p.x - v.pan_x, y: canvas.y + p.y - v.pan_y }
}

fn to_world(v: View, canvas: geometry.Rect, p: geometry.Point) -> geometry.Point {
    ret geometry.Point { x: p.x - canvas.x + v.pan_x, y: p.y - canvas.y + v.pan_y }
}

// ---- links as curves -----------------------------------------------------------------------------------------

fn curve_offset(from: geometry.Point, to: geometry.Point) -> f32 {
    var d = to.x - from.x
    if d < 0.0 { d = 0.0 - d }
    var off = d * 0.5
    if off < 40.0 { off = 40.0 }
    ret off
}

// The point at `t` (0 to 1) of the link's cubic: it leaves `from` to the right and enters `to` from the left.
fn curve_point(from: geometry.Point, to: geometry.Point, t: f32) -> geometry.Point {
    let off = curve_offset(from, to)
    let c1x = from.x + off
    let c2x = to.x - off
    let u = 1.0 - t
    let a = u * u * u
    let b = 3.0 * u * u * t
    let c = 3.0 * u * t * t
    let d = t * t * t
    ret geometry.Point { x: a * from.x + b * c1x + c * c2x + d * to.x, y: a * from.y + b * from.y + c * to.y + d * to.y }
}

fn segment_distance(p: geometry.Point, a: geometry.Point, b: geometry.Point) -> f32 {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let len2 = dx * dx + dy * dy
    var t: f32 = 0.0
    if len2 > 0.0 { t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 }
    if t < 0.0 { t = 0.0 }
    if t > 1.0 { t = 1.0 }
    let ex = a.x + t * dx - p.x
    let ey = a.y + t * dy - p.y
    ret sqrt32(ex * ex + ey * ey)
}

fn sqrt32(v: f32) -> f32 {
    if v <= 0.0 { ret 0.0 }
    var x = v
    if x < 1.0 { x = 1.0 }
    var i = 0usize
    while i < 24usize {
        x = 0.5 * (x + v / x)
        i += 1usize
    }
    ret x
}

// The distance from a world point to the link's curve, taken along 24 straight pieces.
fn link_distance(from: geometry.Point, to: geometry.Point, p: geometry.Point) -> f32 {
    var best: f32 = 1000000.0
    var prev = from
    var i = 1usize
    while i <= 24usize {
        let next = curve_point(from, to, f32(i) / 24.0)
        let d = segment_distance(p, prev, next)
        if d < best { best = d }
        prev = next
        i += 1usize
    }
    ret best
}

// The ends of link `link` in world coordinates, and whether it names real nodes and ports.
fn link_ends(g: Graph, link: usize) -> (geometry.Point, geometry.Point, bool) {
    let l = g.links[link]
    let (from_node, has_from) = node_index(g, l.from)
    let (to_node, has_to) = node_index(g, l.to)
    var none = geometry.Point { x: 0.0, y: 0.0 }
    if !has_from || !has_to { ret (none, none, false) }
    if l.from_port >= g.types[g.nodes[from_node].kind].outputs.len || l.to_port >= g.types[g.nodes[to_node].kind].inputs.len { ret (none, none, false) }
    ret (port_pos(g, from_node, true, l.from_port), port_pos(g, to_node, false, l.to_port), true)
}

// ---- hit testing --------------------------------------------------------------------------------------------

// What the screen point (`x`, `y`) is over on a canvas: ports first (a 4 pixel margin past their radius), then nodes
// (the last in the list is on top), then links within 6 pixels of their curve, else the bare canvas.
fn hit_test(g: Graph, v: View, canvas: geometry.Rect, x: f32, y: f32) -> Hit {
    var none = Hit { kind: .Canvas, node: 0u32, index: 0usize, port: 0usize }
    if !geometry.contains(canvas, geometry.Point { x: x, y: y }) { ret none }
    let p = to_world(v, canvas, geometry.Point { x: x, y: y })
    var i = g.nodes.len
    while i > 0usize {
        i -= 1usize
        let t = g.types[g.nodes[i].kind]
        var k = 0usize
        while k < t.outputs.len {
            let c = port_pos(g, i, true, k)
            if (p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y) <= (port_radius() + 4.0) * (port_radius() + 4.0) { ret Hit { kind: .OutPort, node: g.nodes[i].id, index: i, port: k } }
            k += 1usize
        }
        k = 0usize
        while k < t.inputs.len {
            let c = port_pos(g, i, false, k)
            if (p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y) <= (port_radius() + 4.0) * (port_radius() + 4.0) { ret Hit { kind: .InPort, node: g.nodes[i].id, index: i, port: k } }
            k += 1usize
        }
        if geometry.contains(node_rect(g, i), p) { ret Hit { kind: .Node, node: g.nodes[i].id, index: i, port: 0usize } }
    }
    var best = g.links.len
    var best_d: f32 = 6.0
    var l = 0usize
    while l < g.links.len {
        let (from, to, real) = link_ends(g, l)
        if real {
            let d = link_distance(from, to, p)
            if d <= best_d {
                best_d = d
                best = l
            }
        }
        l += 1usize
    }
    if best < g.links.len { ret Hit { kind: .Link, node: 0u32, index: best, port: 0usize } }
    ret none
}

fn snap(v: f32, step: f32) -> f32 {
    if !(step > 0.0) { ret v }
    var n = v / step
    if n >= 0.0 { n = f32(i64(n + 0.5)) } else { n = f32(i64(n - 0.5)) }
    ret n * step
}

// ---- connection rules ---------------------------------------------------------------------------------------

// Whether an output (`from`, `from_port`) may feed an input (`to`, `to_port`): both nodes and ports exist, they are not the
// same node, the link is not already there, the input is free (an input takes one link; an output may feed many), and with
// `forbid_cycles` it does not close a loop.
fn can_connect(g: Graph, from: u32, from_port: usize, to: u32, to_port: usize, forbid_cycles: bool) -> Connect {
    let (a, has_a) = node_index(g, from)
    let (b, has_b) = node_index(g, to)
    if !has_a || !has_b { ret .UnknownNode }
    if from == to { ret .SelfLoop }
    if from_port >= g.types[g.nodes[a].kind].outputs.len || to_port >= g.types[g.nodes[b].kind].inputs.len { ret .BadPort }
    var taken = false
    var i = 0usize
    while i < g.links.len {
        let l = g.links[i]
        if l.from == from && l.from_port == from_port && l.to == to && l.to_port == to_port { ret .Duplicate }
        if l.to == to && l.to_port == to_port { taken = true }
        i += 1usize
    }
    if taken { ret .InputTaken }
    if forbid_cycles && reaches(g, to, from) { ret .Cycle }
    ret .Ok
}

// Whether `target_id` can be reached from `start` by following at least one link (so a node reaches itself only through a
// loop). Graphs of more than 256 nodes are not searched.
fn reaches(g: Graph, start: u32, target_id: u32) -> bool {
    if g.nodes.len > 256usize { ret false }
    var seen: [256]bool = zero
    var stack: [256]u32 = zero
    var top = 1usize
    stack[0] = start
    while top > 0usize {
        top -= 1usize
        let id = stack[top]
        var l = 0usize
        while l < g.links.len {
            let (_, _, real) = link_ends(g, l)
            if real && g.links[l].from == id {
                let to = g.links[l].to
                if to == target_id { ret true }
                let (to_idx, found) = node_index(g, to)
                if found && !seen[to_idx] {
                    seen[to_idx] = true
                    stack[top] = to
                    top += 1usize
                }
            }
            l += 1usize
        }
    }
    ret false
}

// ---- lint ---------------------------------------------------------------------------------------------------

fn same_text(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

type Lint = struct { a: *mem.Arena, issues: []Issue, count: usize }

fn push_issue(l: *Lint, issue: Issue) -> err {
    if l.count >= l.issues.len { ret TooLarge }
    l.issues[l.count] = issue
    l.count += 1usize
    ret ok
}

// The problems of a graph, errors first within each kind of check, in node order: a node id used twice, a link to a missing
// node or port, an input fed by two links, a required input with no link, a node on a cycle, a node with inputs that
// no node without inputs reaches, a node with no links at all, and nodes sharing a non-empty label. At most 256 nodes.
fn lint(a: *mem.Arena, g: Graph) -> ([]const Issue, err) {
    let n = g.nodes.len
    if n > 256usize { ret (zero, TooLarge) }
    let (issues, issues_error) = mem.alloc[Issue](a, n * 8usize + g.links.len * 2usize + 8usize)
    if issues_error != ok { ret (zero, TooLarge) }
    var l = Lint { a: a, issues: issues, count: 0usize }
    var i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            if g.nodes[i].id == g.nodes[j].id { try push_issue(&l, Issue { severity: .Error, code: .DuplicateId, node: g.nodes[j].id, link: 0usize }) }
            j += 1usize
        }
        i += 1usize
    }
    var k = 0usize
    while k < g.links.len {
        let (_, _, real) = link_ends(g, k)
        if !real { try push_issue(&l, Issue { severity: .Error, code: .DanglingLink, node: g.links[k].to, link: k }) }
        k += 1usize
    }
    // an input fed twice
    k = 0usize
    while k < g.links.len {
        var m = k + 1usize
        var fed = false
        while m < g.links.len {
            if g.links[m].to == g.links[k].to && g.links[m].to_port == g.links[k].to_port { fed = true }
            m += 1usize
        }
        var earlier = false
        var e = 0usize
        while e < k {
            if g.links[e].to == g.links[k].to && g.links[e].to_port == g.links[k].to_port { earlier = true }
            e += 1usize
        }
        if fed && !earlier { try push_issue(&l, Issue { severity: .Error, code: .InputFed, node: g.links[k].to, link: k }) }
        k += 1usize
    }
    // required inputs
    i = 0usize
    while i < n {
        let t = g.types[g.nodes[i].kind]
        var p = 0usize
        while p < t.inputs.len && p < 32usize {
            if (t.required >> u32(p)) & 1u32 == 1u32 {
                var linked = false
                var m = 0usize
                while m < g.links.len {
                    if g.links[m].to == g.nodes[i].id && g.links[m].to_port == p { linked = true }
                    m += 1usize
                }
                if !linked { try push_issue(&l, Issue { severity: .Error, code: .UnconnectedInput, node: g.nodes[i].id, link: p }) }
            }
            p += 1usize
        }
        i += 1usize
    }
    // cycles: strongly connected components by Tarjan, over the links that name real nodes
    let cycle = on_cycle(g)
    i = 0usize
    while i < n {
        if cycle[i] { try push_issue(&l, Issue { severity: .Error, code: .Cycle, node: g.nodes[i].id, link: 0usize }) }
        i += 1usize
    }
    // nodes nothing reaches: from every node whose type has no inputs, forward
    var reached: [256]bool = zero
    var frontier: [256]usize = zero
    var fcount = 0usize
    i = 0usize
    while i < n {
        if g.types[g.nodes[i].kind].inputs.len == 0usize {
            reached[i] = true
            frontier[fcount] = i
            fcount += 1usize
        }
        i += 1usize
    }
    while fcount > 0usize {
        fcount -= 1usize
        let at = frontier[fcount]
        var m = 0usize
        while m < g.links.len {
            let (_, _, real) = link_ends(g, m)
            if real && g.links[m].from == g.nodes[at].id {
                let (to_idx, found) = node_index(g, g.links[m].to)
                if found && !reached[to_idx] {
                    reached[to_idx] = true
                    frontier[fcount] = to_idx
                    fcount += 1usize
                }
            }
            m += 1usize
        }
    }
    i = 0usize
    while i < n {
        if g.types[g.nodes[i].kind].inputs.len > 0usize && !reached[i] { try push_issue(&l, Issue { severity: .Warning, code: .Unreachable, node: g.nodes[i].id, link: 0usize }) }
        i += 1usize
    }
    // isolated nodes
    i = 0usize
    while i < n {
        var touched = false
        var m = 0usize
        while m < g.links.len {
            if g.links[m].from == g.nodes[i].id || g.links[m].to == g.nodes[i].id { touched = true }
            m += 1usize
        }
        if !touched { try push_issue(&l, Issue { severity: .Warning, code: .Isolated, node: g.nodes[i].id, link: 0usize }) }
        i += 1usize
    }
    // duplicate labels: reported on every node but the first of each label
    i = 0usize
    while i < n {
        if g.nodes[i].label.len > 0usize {
            var j = 0usize
            while j < i {
                if same_text(g.nodes[j].label, g.nodes[i].label) {
                    try push_issue(&l, Issue { severity: .Warning, code: .DuplicateLabel, node: g.nodes[i].id, link: 0usize })
                    break
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    ret (l.issues[..l.count], ok)
}

// Which nodes lie on a cycle (in a strongly connected component of two or more, or with a link to themselves).
fn on_cycle(g: Graph) -> [256]bool {
    var result: [256]bool = zero
    let n = g.nodes.len
    var index: [256]i32 = zero
    var low: [256]i32 = zero
    var on_stack: [256]bool = zero
    var stack: [256]usize = zero
    var sp = 0usize
    var counter = 1i32
    // iterative DFS: a frame is a node and the next link to try
    var frame_node: [256]usize = zero
    var frame_link: [256]usize = zero
    var root = 0usize
    while root < n {
        if index[root] == 0i32 {
            var fp = 0usize
            frame_node[0] = root
            frame_link[0] = 0usize
            fp = 1usize
            index[root] = counter
            low[root] = counter
            counter += 1i32
            stack[sp] = root
            sp += 1usize
            on_stack[root] = true
            while fp > 0usize {
                let v = frame_node[fp - 1usize]
                var advanced = false
                while frame_link[fp - 1usize] < g.links.len && !advanced {
                    let li = frame_link[fp - 1usize]
                    frame_link[fp - 1usize] = li + 1usize
                    if g.links[li].from != g.nodes[v].id { continue }
                    let (_, _, real) = link_ends(g, li)
                    if !real { continue }
                    let (w, found) = node_index(g, g.links[li].to)
                    if !found { continue }
                    if w == v { result[v] = true }
                    if index[w] == 0i32 {
                        index[w] = counter
                        low[w] = counter
                        counter += 1i32
                        stack[sp] = w
                        sp += 1usize
                        on_stack[w] = true
                        frame_node[fp] = w
                        frame_link[fp] = 0usize
                        fp += 1usize
                        advanced = true
                    } else if on_stack[w] {
                        if index[w] < low[v] { low[v] = index[w] }
                    }
                }
                if advanced { continue }
                // v is done
                if low[v] == index[v] {
                    var members = 0usize
                    var scan = sp
                    while scan > 0usize {
                        scan -= 1usize
                        members += 1usize
                        if stack[scan] == v { break }
                    }
                    var pop = 0usize
                    while pop < members {
                        sp -= 1usize
                        let w = stack[sp]
                        on_stack[w] = false
                        if members > 1usize { result[w] = true }
                        pop += 1usize
                    }
                }
                fp -= 1usize
                if fp > 0usize {
                    let parent = frame_node[fp - 1usize]
                    if low[v] < low[parent] { low[parent] = low[v] }
                }
            }
        }
        root += 1usize
    }
    ret result
}

// ---- the editor's panes -------------------------------------------------------------------------------------

// The panes of an editor `width` by `height`: a 168 wide palette at the start, a 220 wide inspector at the end, the lint strip
// along the bottom (32 tall, or 32 plus 22 for each of up to six issues when open) and the canvas between them.
fn panes(width: f32, height: f32, lint_open: bool, issue_count: usize) -> Panes {
    var strip: f32 = 32.0
    if lint_open {
        var rows = issue_count
        if rows > 6usize { rows = 6usize }
        strip = 32.0 + f32(rows) * 22.0
    }
    var inspector: f32 = 220.0
    var palette: f32 = 168.0
    if width < 640.0 {
        inspector = 0.0
        palette = 0.0
    }
    let canvas_height = height - strip
    ret Panes {
        palette: geometry.rect(0.0, 0.0, palette, canvas_height),
        canvas: geometry.rect(palette, 0.0, width - palette - inspector, canvas_height),
        inspector: geometry.rect(width - inspector, 0.0, inspector, canvas_height),
        lint: geometry.rect(0.0, canvas_height, width, strip),
    }
}

fn pane_at(p: Panes, x: f32, y: f32) -> Pane {
    let at = geometry.Point { x: x, y: y }
    if p.lint.height > 0.0 && geometry.contains(p.lint, at) { ret .Lint }
    if p.palette.width > 0.0 && geometry.contains(p.palette, at) { ret .Palette }
    if p.inspector.width > 0.0 && geometry.contains(p.inspector, at) { ret .Inspector }
    if geometry.contains(p.canvas, at) { ret .Canvas }
    ret .None
}

// The palette's item under a point: items are 36 tall from 32 below the pane's top; the index, or the count for none.
fn palette_item_at(p: Panes, count: usize, x: f32, y: f32) -> usize {
    if !geometry.contains(p.palette, geometry.Point { x: x, y: y }) { ret count }
    let row = (y - p.palette.y - 32.0) / 36.0
    if row < 0.0 { ret count }
    let index = usize(row)
    if index >= count { ret count }
    ret index
}

// A view that shows the whole graph in a canvas `width` by `height` with 24 around it (panned, not scaled): the top-left
// of the nodes' bounding box less the margin, and where the box is larger than the canvas that same corner.
fn fit(g: Graph, width: f32, height: f32) -> View {
    if g.nodes.len == 0usize { ret View { pan_x: 0.0, pan_y: 0.0 } }
    var left = g.nodes[0].x
    var top = g.nodes[0].y
    var right = g.nodes[0].x + node_width()
    var bottom = g.nodes[0].y + node_height(g, 0usize)
    var i = 1usize
    while i < g.nodes.len {
        let r = node_rect(g, i)
        if r.x < left { left = r.x }
        if r.y < top { top = r.y }
        if r.x + r.width > right { right = r.x + r.width }
        if r.y + r.height > bottom { bottom = r.y + r.height }
        i += 1usize
    }
    var x = left - 24.0
    var y = top - 24.0
    let spare_x = width - (right - left + 48.0)
    let spare_y = height - (bottom - top + 48.0)
    if spare_x > 0.0 { x = x - spare_x * 0.5 }
    if spare_y > 0.0 { y = y - spare_y * 0.5 }
    ret View { pan_x: x, pan_y: y }
}

// ---------------------------------------------------------------- the editor (D2284, part 2)

// The visual editor over the model above: a palette of node types at the start, the canvas (dotted ground, links as
// curves, nodes with their ports), an inspector for the selected node at the end, and a lint strip along the bottom that
// opens into a list of problems. The caller owns the graph and the state; the editor builds what it is given and reports
// what the user asked as `FlowEvent`s that carry the state they lead to, applying nothing itself. One pointer region covers
// the editor and decides what a gesture grabbed from where it began: a port starts a link, a node moves, empty canvas pans,
// a palette item is dropped on the canvas to add a node. A drag in progress is `state.drag`; the editor keeps it current
// between events within a frame, and the caller applies each event's state before the next frame, as any frame loop does.

type DragKind = enum u8 { None, Node, Link, Palette, Pan }
type DragState = struct { kind: DragKind, node: u32, port: usize, from_output: bool, type_index: usize, x: f32, y: f32, off_x: f32, off_y: f32, pan_x: f32, pan_y: f32 }
type FlowState = struct {
    view: View, selected: u32, has_selected: bool, selected_link: usize, has_link: bool, drag: DragState,
    field: usize, editing: bool, len: usize, lint_open: bool,
}
type FlowEventKind = enum u8 {
    Select, SelectLink, Move, Pan, DragLink, DragPalette, DragEnd, Connect, Refuse, Add, Delete, Disconnect,
    InspectStart, InspectType, InspectCommit, InspectCancel, ToggleLint,
}
// `state` is where the action leads. Move and Add carry a world position (`x`, `y`), Connect and Refuse the two ends and (for
// Refuse) the `reason`, Delete a node, Disconnect a link, the Inspect events the field (0 the label, then the parameters),
// and Commit and Type the text.
type FlowEvent = struct {
    kind: FlowEventKind, state: FlowState, node: u32, port: usize, to_node: u32, to_port: usize, type_index: usize,
    x: f32, y: f32, field: usize, text: str, reason: Connect, link: usize,
}
type FlowOptions = struct { forbid_cycles: bool, grid: f32, disabled: bool }

fn flow_options() -> FlowOptions {
    ret FlowOptions { forbid_cycles: false, grid: 20.0, disabled: false }
}

fn none_drag() -> DragState {
    ret DragState { kind: .None, node: 0u32, port: 0usize, from_output: false, type_index: 0usize, x: 0.0, y: 0.0, off_x: 0.0, off_y: 0.0, pan_x: 0.0, pan_y: 0.0 }
}

fn base_event(kind: FlowEventKind, state: FlowState) -> FlowEvent {
    ret FlowEvent { kind: kind, state: state, node: 0u32, port: 0usize, to_node: 0u32, to_port: 0usize, type_index: 0usize, x: 0.0, y: 0.0, field: 0usize, text: "", reason: .Ok, link: 0usize }
}

// The inspector's field rows: the type's name 32 below the pane's top (24 tall), then 44 for each field (the label, then the
// node's parameters); the field at a point, or `count` for none.
fn inspector_field_at(p: Panes, count: usize, x: f32, y: f32) -> usize {
    if !geometry.contains(p.inspector, geometry.Point { x: x, y: y }) { ret count }
    let row = (y - p.inspector.y - 56.0) / 44.0
    if row < 0.0 { ret count }
    let index = usize(row)
    if index >= count { ret count }
    ret index
}

// The lint strip's issue row under a point when it is open: rows are 22 tall below the 32 tall bar; `count` for none.
fn lint_row_at(p: Panes, count: usize, x: f32, y: f32) -> usize {
    if !geometry.contains(p.lint, geometry.Point { x: x, y: y }) { ret count }
    let row = (y - p.lint.y - 32.0) / 22.0
    if row < 0.0 { ret count }
    let index = usize(row)
    if index >= count || index >= 6usize { ret count }
    ret index
}

type FlowCtx = struct {
    g: Graph, state: FlowState, panes: Panes, issues: []const Issue, change: widget.Change[FlowEvent], draft: []u8,
    runtime: *widget.Runtime, key: widget.Key, options: FlowOptions,
}

fn fire(c: *FlowCtx, event: FlowEvent) -> err {
    c.state = event.state
    let fired = widget.fire_change[FlowEvent](c.change, event)
    if fired != ok { ret fired }
    if event.kind == .InspectStart { ret widget.focus_key(c.runtime, c.key + 2u64) }
    if event.kind == .InspectCommit || event.kind == .InspectCancel { ret widget.focus_key(c.runtime, c.key + 1u64) }
    ret ok
}

fn select_node(s: FlowState, id: u32) -> FlowState {
    var next = s
    next.selected = id
    next.has_selected = true
    next.has_link = false
    next.editing = false
    next.len = 0usize
    ret next
}

fn flow_press(ctx: *void, gesture: widget.Gesture) -> err {
    let c = mem.cast[*FlowCtx](ctx)
    if c.options.disabled { ret ok }
    switch gesture {
    case .Tap as at:
        ret flow_tap(c, at)
    case .DragMove as drag:
        ret flow_drag(c, drag)
    case .DragEnd as end:
        ret flow_end(c, end)
    default:
        ret ok
    }
}

fn flow_tap(c: *FlowCtx, at: geometry.Point) -> err {
    let zone = pane_at(c.panes, at.x, at.y)
    var base = c.state
    base.drag = none_drag()
    if zone == .Canvas {
        let hit = hit_test(c.g, c.state.view, c.panes.canvas, at.x, at.y)
        try widget.focus_key(c.runtime, c.key + 1u64)
        if hit.kind == .Node { ret fire(c, FlowEvent { kind: .Select, state: select_node(base, hit.node), node: hit.node, port: 0usize, to_node: 0u32, to_port: 0usize, type_index: 0usize, x: 0.0, y: 0.0, field: 0usize, text: "", reason: .Ok, link: 0usize }) }
        if hit.kind == .Link {
            var next = base
            next.has_selected = false
            next.has_link = true
            next.selected_link = hit.index
            next.editing = false
            var e = base_event(.SelectLink, next)
            e.link = hit.index
            ret fire(c, e)
        }
        var cleared = base
        cleared.has_selected = false
        cleared.has_link = false
        cleared.editing = false
        cleared.len = 0usize
        ret fire(c, base_event(.Select, cleared))
    }
    if zone == .Inspector && c.state.has_selected {
        let (idx, found) = node_index(c.g, c.state.selected)
        if !found { ret ok }
        let count = 1usize + c.g.nodes[idx].params.len
        let field = inspector_field_at(c.panes, count, at.x, at.y)
        if field >= count { ret ok }
        var next = base
        next.editing = true
        next.field = field
        next.len = 0usize
        var e = base_event(.InspectStart, next)
        e.node = c.state.selected
        e.field = field
        ret fire(c, e)
    }
    if zone == .Lint {
        let row = lint_row_at(c.panes, c.issues.len, at.x, at.y)
        if c.state.lint_open && row < c.issues.len && c.issues[row].node != 0u32 {
            let (_, found) = node_index(c.g, c.issues[row].node)
            if found { ret fire(c, FlowEvent { kind: .Select, state: select_node(base, c.issues[row].node), node: c.issues[row].node, port: 0usize, to_node: 0u32, to_port: 0usize, type_index: 0usize, x: 0.0, y: 0.0, field: 0usize, text: "", reason: .Ok, link: 0usize }) }
        }
        if at.y < c.panes.lint.y + 32.0 {
            var next = base
            next.lint_open = !base.lint_open
            ret fire(c, base_event(.ToggleLint, next))
        }
    }
    ret ok
}

fn flow_drag(c: *FlowCtx, d: widget.Drag) -> err {
    var s = c.state
    if s.drag.kind == .None {
        let zone = pane_at(c.panes, d.start.x, d.start.y)
        if zone == .Canvas {
            let hit = hit_test(c.g, s.view, c.panes.canvas, d.start.x, d.start.y)
            if hit.kind == .OutPort || hit.kind == .InPort {
                s.drag = DragState { kind: .Link, node: hit.node, port: hit.port, from_output: hit.kind == .OutPort, type_index: 0usize, x: d.position.x, y: d.position.y, off_x: 0.0, off_y: 0.0, pan_x: 0.0, pan_y: 0.0 }
            } else if hit.kind == .Node {
                let world = to_world(s.view, c.panes.canvas, d.start)
                s.drag = DragState { kind: .Node, node: hit.node, port: 0usize, from_output: false, type_index: 0usize, x: d.position.x, y: d.position.y, off_x: world.x - c.g.nodes[hit.index].x, off_y: world.y - c.g.nodes[hit.index].y, pan_x: 0.0, pan_y: 0.0 }
                s = select_node(s, hit.node)
                s.drag = DragState { kind: .Node, node: hit.node, port: 0usize, from_output: false, type_index: 0usize, x: d.position.x, y: d.position.y, off_x: world.x - c.g.nodes[hit.index].x, off_y: world.y - c.g.nodes[hit.index].y, pan_x: 0.0, pan_y: 0.0 }
            } else {
                s.drag = DragState { kind: .Pan, node: 0u32, port: 0usize, from_output: false, type_index: 0usize, x: d.position.x, y: d.position.y, off_x: 0.0, off_y: 0.0, pan_x: s.view.pan_x, pan_y: s.view.pan_y }
            }
        } else if zone == .Palette {
            let item = palette_item_at(c.panes, c.g.types.len, d.start.x, d.start.y)
            if item >= c.g.types.len { ret ok }
            s.drag = DragState { kind: .Palette, node: 0u32, port: 0usize, from_output: false, type_index: item, x: d.position.x, y: d.position.y, off_x: 0.0, off_y: 0.0, pan_x: 0.0, pan_y: 0.0 }
        } else {
            ret ok
        }
    }
    s.drag.x = d.position.x
    s.drag.y = d.position.y
    if s.drag.kind == .Node {
        let world = to_world(s.view, c.panes.canvas, d.position)
        var e = base_event(.Move, s)
        e.node = s.drag.node
        e.x = snap(world.x - s.drag.off_x, c.options.grid)
        e.y = snap(world.y - s.drag.off_y, c.options.grid)
        ret fire(c, e)
    }
    if s.drag.kind == .Pan {
        s.view.pan_x = s.drag.pan_x - (d.position.x - d.start.x)
        s.view.pan_y = s.drag.pan_y - (d.position.y - d.start.y)
        ret fire(c, base_event(.Pan, s))
    }
    if s.drag.kind == .Link { ret fire(c, base_event(.DragLink, s)) }
    ret fire(c, base_event(.DragPalette, s))
}

fn flow_end(c: *FlowCtx, end: geometry.Point) -> err {
    var s = c.state
    let drag = s.drag
    s.drag = none_drag()
    if drag.kind == .None { ret ok }
    if drag.kind == .Link {
        let hit = hit_test(c.g, s.view, c.panes.canvas, end.x, end.y)
        var wanted_kind: HitKind = .InPort
        if !drag.from_output { wanted_kind = .OutPort }
        if hit.kind == wanted_kind {
            var from = drag.node
            var from_port = drag.port
            var to = hit.node
            var to_port = hit.port
            if !drag.from_output {
                from = hit.node
                from_port = hit.port
                to = drag.node
                to_port = drag.port
            }
            let verdict = can_connect(c.g, from, from_port, to, to_port, c.options.forbid_cycles)
            var kind: FlowEventKind = .Connect
            if verdict != .Ok { kind = .Refuse }
            var e = base_event(kind, s)
            e.node = from
            e.port = from_port
            e.to_node = to
            e.to_port = to_port
            e.reason = verdict
            ret fire(c, e)
        }
        ret fire(c, base_event(.DragEnd, s))
    }
    if drag.kind == .Palette {
        if pane_at(c.panes, end.x, end.y) == .Canvas {
            let world = to_world(s.view, c.panes.canvas, end)
            var e = base_event(.Add, s)
            e.type_index = drag.type_index
            e.x = snap(world.x - node_width() * 0.5, c.options.grid)
            e.y = snap(world.y - header_height() * 0.5, c.options.grid)
            ret fire(c, e)
        }
        ret fire(c, base_event(.DragEnd, s))
    }
    ret fire(c, base_event(.DragEnd, s))
}

fn str_of(buf: []u8, len: usize) -> str {
    if len > buf.len { ret buf[..buf.len] }
    ret buf[..len]
}

fn flow_key(ctx: *void, k: input.KeyEvent) -> err {
    let c = mem.cast[*FlowCtx](ctx)
    if c.options.disabled { ret ok }
    let code = widget.key_code(k.key.physical)
    let s = c.state
    if s.editing {
        if code == 27u32 {
            var next = s
            next.editing = false
            next.len = 0usize
            var e = base_event(.InspectCancel, next)
            e.node = s.selected
            e.field = s.field
            ret fire(c, e)
        }
        if code == 13u32 {
            var next = s
            next.editing = false
            next.len = 0usize
            var e = base_event(.InspectCommit, next)
            e.node = s.selected
            e.field = s.field
            e.text = str_of(c.draft, s.len)
            ret fire(c, e)
        }
        ret ok
    }
    if code == 27u32 {
        if s.drag.kind != .None {
            var next = s
            next.drag = none_drag()
            ret fire(c, base_event(.DragEnd, next))
        }
        var cleared = s
        cleared.has_selected = false
        cleared.has_link = false
        ret fire(c, base_event(.Select, cleared))
    }
    if code == 46u32 && s.has_selected {
        var next = s
        next.has_selected = false
        var e = base_event(.Delete, next)
        e.node = s.selected
        ret fire(c, e)
    }
    if code == 46u32 && s.has_link {
        var next = s
        next.has_link = false
        var e = base_event(.Disconnect, next)
        e.link = s.selected_link
        ret fire(c, e)
    }
    if s.has_selected && (code == 37u32 || code == 38u32 || code == 39u32 || code == 40u32) {
        let (idx, found) = node_index(c.g, s.selected)
        if !found { ret ok }
        var dx: f32 = 0.0
        var dy: f32 = 0.0
        if code == 37u32 { dx = 0.0 - c.options.grid }
        if code == 39u32 { dx = c.options.grid }
        if code == 38u32 { dy = 0.0 - c.options.grid }
        if code == 40u32 { dy = c.options.grid }
        var e = base_event(.Move, s)
        e.node = s.selected
        e.x = snap(c.g.nodes[idx].x + dx, c.options.grid)
        e.y = snap(c.g.nodes[idx].y + dy, c.options.grid)
        ret fire(c, e)
    }
    ret ok
}

fn flow_typed(ctx: *void, value: str) -> err {
    let c = mem.cast[*FlowCtx](ctx)
    var next = c.state
    next.len = value.len
    var e = base_event(.InspectType, next)
    e.node = c.state.selected
    e.field = c.state.field
    e.text = value
    ret fire(c, e)
}

fn flow_input(ctx: *void, event: input.Event) -> err { ret ok }

// ---- painting: the dotted ground and the links ---------------------------------------------------------------

type GroundPaint = struct { color: paint.Color, step: f32, pan_x: f32, pan_y: f32 }

fn ground_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

fn ground_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let g = mem.cast[*GroundPaint](ctx)
    var gx = g.step - g.pan_x
    while gx < 0.0 { gx += g.step }
    while gx >= g.step { gx -= g.step }
    var gy = g.step - g.pan_y
    while gy < 0.0 { gy += g.step }
    while gy >= g.step { gy -= g.step }
    var y = gy
    while y < area.height {
        var x = gx
        while x < area.width {
            try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(area.x + x - 1.0, area.y + y - 1.0, 2.0, 2.0), brush: paint.Brush { Solid: g.color } } })
            x += g.step
        }
        y += g.step
    }
    ret ok
}

type LinkPaint = struct {
    arena: *mem.Arena, g: Graph, view: View, canvas: geometry.Rect, ink: paint.Color, chosen: paint.Color, selected: usize, has_selected: bool,
    pending: bool, from: geometry.Point, to: geometry.Point, pending_ink: paint.Color,
}

fn stroke_curve(a: *mem.Arena, b: *scene.Builder, from: geometry.Point, to: geometry.Point, color: paint.Color, width: f32) -> err {
    let (pb, pb_error) = geometry.path_builder(a, 4usize, 8usize)
    if pb_error != ok { ret TooLarge }
    var builder = pb
    let off = curve_offset(from, to)
    try geometry.move_to(&builder, from)
    try geometry.cubic_to(&builder, geometry.Point { x: from.x + off, y: from.y }, geometry.Point { x: to.x - off, y: to.y }, to)
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: geometry.finish(&builder), brush: paint.Brush { Solid: color }, stroke: paint.Stroke { width: width, cap: .Round, join: .Round, miter_limit: 4.0 } } })
}

fn links_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let p = mem.cast[*LinkPaint](ctx)
    var i = 0usize
    while i < p.g.links.len {
        let (from, to, real) = link_ends(p.g, i)
        if real {
            let a = geometry.Point { x: area.x + from.x - p.view.pan_x, y: area.y + from.y - p.view.pan_y }
            let z = geometry.Point { x: area.x + to.x - p.view.pan_x, y: area.y + to.y - p.view.pan_y }
            if p.has_selected && p.selected == i {
                try stroke_curve(p.arena, b, a, z, p.chosen, 3.0)
            } else {
                try stroke_curve(p.arena, b, a, z, p.ink, 2.0)
            }
        }
        i += 1usize
    }
    if p.pending { ret stroke_curve(p.arena, b, p.from, p.to, p.pending_ink, 2.0) }
    ret ok
}

fn custom_node(a: *mem.Arena, key: widget.Key, ctx: *void, bytes: []const u8, measure: fn(*void, ui_layout.Constraints) -> geometry.Size, painter: fn(*void, *scene.Builder, geometry.Rect) -> err, width: f32, height: f32) -> widget.Node {
    var none: []const widget.Node = zero
    ret widget.Node { key: key, kind: widget.Kind { Custom: widget.Custom { ctx: ctx, measure: measure, paint: painter, state: bytes } }, style: control.sized_style(width, height), children: none }
}

fn mem_one(a: *mem.Arena, node: widget.Node) -> []const widget.Node {
    let (one, one_error) = mem.alloc[widget.Node](a, 1usize)
    if one_error != ok { ret zero }
    one[0usize] = node
    ret one[0usize..1usize]
}

fn text_node(a: *mem.Arena, t: *const control.Theme, text: str, role: style.TextRole, ink: paint.Color) -> (widget.Node, err) {
    var words = control.text_options()
    words.role = role
    words.wrap = .None
    let (node, node_error) = control.colored_text(a, 0u64, text, t, words, ink)
    ret (node, node_error)
}

fn joined(a: *mem.Arena, first: str, second: str, third: str) -> (str, err) {
    let (buf, buf_error) = mem.alloc[u8](a, first.len + second.len + third.len + 1usize)
    if buf_error != ok { ret ("", TooLarge) }
    mem.copy[u8](buf, first)
    mem.copy[u8](buf[first.len..], second)
    mem.copy[u8](buf[first.len + second.len..], third)
    ret (buf[..first.len + second.len + third.len], ok)
}

fn count_text(a: *mem.Arena, value: usize) -> (str, err) {
    let (buf, buf_error) = mem.alloc[u8](a, 24usize)
    if buf_error != ok { ret ("", TooLarge) }
    var digits: [24]u8 = zero
    var n = 0usize
    var rest = value
    if rest == 0usize {
        digits[0] = 48u8
        n = 1usize
    }
    while rest > 0usize {
        digits[n] = u8(48usize + rest % 10usize)
        n += 1usize
        rest = rest / 10usize
    }
    var i = 0usize
    while i < n {
        buf[i] = digits[n - 1usize - i]
        i += 1usize
    }
    ret (buf[..n], ok)
}

// The words of one lint issue, led by the node it is about.
fn issue_words(a: *mem.Arena, g: Graph, issue: Issue) -> (str, err) {
    var who = "A link"
    var idx = 0usize
    var has = false
    if issue.node != 0u32 {
        let (i, found) = node_index(g, issue.node)
        idx = i
        has = found
    }
    if has {
        who = g.nodes[idx].label
        if who.len == 0usize { who = g.types[g.nodes[idx].kind].name }
    }
    var what = "has a problem"
    if issue.code == .DuplicateId { what = "shares its id with another node" }
    if issue.code == .DanglingLink { what = "has a link that goes nowhere" }
    if issue.code == .InputFed { what = "has an input with more than one link" }
    if issue.code == .UnconnectedInput {
        what = "has a required input with no link"
        if has && issue.link < g.types[g.nodes[idx].kind].inputs.len {
            let (named, named_error) = joined(a, "input ", g.types[g.nodes[idx].kind].inputs[issue.link], " is not connected")
            if named_error != ok { ret ("", named_error) }
            what = named
        }
    }
    if issue.code == .Cycle { what = "is part of a cycle" }
    if issue.code == .Unreachable { what = "gets nothing from a source" }
    if issue.code == .Isolated { what = "is not connected to anything" }
    if issue.code == .DuplicateLabel { what = "uses a label another node has" }
    let (words, words_error) = joined(a, who, ": ", what)
    ret (words, words_error)
}

// One node: a rounded box with its header (the label, the type's name under it), a port circle and name for each input
// and output, and a mark at the corner for its worst lint issue.
fn node_view(a: *mem.Arena, t: *const control.Theme, key: widget.Key, g: Graph, index: usize, selected: bool, linked_in: []const bool, linked_out: []const bool, mark: u8) -> (widget.Node, err) {
    let ty = g.types[g.nodes[index].kind]
    let r = node_rect(g, index)
    var ink = style.color(t.tokens, .OnSurface)
    var quiet = style.color(t.tokens, .OnSurfaceVariant)
    var box = control.sized_style(r.width, r.height)
    box.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) }
    box.radius = 8.0
    box.border = style.Border { width: 1.0, color: style.color(t.tokens, .Outline) }
    if selected { box.border = style.Border { width: 2.0, color: style.color(t.tokens, .Primary) } }
    let (parts, parts_error) = mem.alloc[widget.Node](a, (ty.inputs.len + ty.outputs.len) * 2usize + 6usize)
    if parts_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    // the header
    var head = control.sized_style(r.width - 2.0, header_height())
    head.background = paint.Brush { Solid: style.color(t.tokens, .SecondaryContainer) }
    head.corners = style.Corners { top_left: 7.0, top_right: 7.0, bottom_right: 0.0, bottom_left: 0.0 }
    var title = g.nodes[index].label
    if title.len == 0usize { title = ty.name }
    let (title_node, title_error) = text_node(a, t, title, .LabelLarge, style.color(t.tokens, .OnSecondaryContainer))
    if title_error != ok { ret (zero, title_error) }
    let head_box = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, head, mem_one(a, widget.padded(0u64, 10.0, 0.0, 0.0, 0.0, style.defaults(), mem_one(a, title_node))))
    parts[n] = widget.positioned(0u64, 1.0, 1.0, style.defaults(), mem_one(a, head_box))
    n += 1usize
    var side = 0usize
    while side < 2usize {
        let outputs = side == 1usize
        var count = ty.inputs.len
        if outputs { count = ty.outputs.len }
        var p = 0usize
        while p < count {
            var name = ty.inputs
            if outputs { name = ty.outputs }
            let cy = header_height() + f32(p) * port_row() + port_row() * 0.5
            var linked = false
            if outputs { linked = p < linked_out.len && linked_out[p] } else { linked = p < linked_in.len && linked_in[p] }
            var dot = control.sized_style(port_radius() * 2.0, port_radius() * 2.0)
            dot.radius = port_radius()
            dot.border = style.Border { width: 2.0, color: style.color(t.tokens, .Primary) }
            dot.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerHigh) }
            if linked { dot.background = paint.Brush { Solid: style.color(t.tokens, .Primary) } }
            var dot_x: f32 = 0.0 - port_radius()
            if outputs { dot_x = r.width - port_radius() }
            parts[n] = widget.positioned(0u64, dot_x, cy - port_radius(), style.defaults(), mem_one(a, widget.box(0u64, dot, zero)))
            n += 1usize
            let (label_node, label_error) = text_node(a, t, name[p], .BodySmall, quiet)
            if label_error != ok { ret (zero, label_error) }
            var label_x: f32 = 12.0
            var label_cell = control.sized_style(r.width * 0.5 - 16.0, port_row())
            var place: ui_layout.MainAlign = .Start
            if outputs {
                label_x = r.width * 0.5 + 4.0
                place = .End
            }
            parts[n] = widget.positioned(0u64, label_x, header_height() + f32(p) * port_row(), style.defaults(), mem_one(a, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: place, cross: .Center, gap: 0.0 }, label_cell, mem_one(a, label_node))))
            n += 1usize
            p += 1usize
        }
        side += 1usize
    }
    if mark > 0u8 {
        var dot = control.sized_style(10.0, 10.0)
        dot.radius = 5.0
        dot.background = paint.Brush { Solid: style.color(t.tokens, .Error) }
        if mark == 2u8 { dot.background = paint.Brush { Solid: style.color(t.tokens, .Warning) } }
        parts[n] = widget.positioned(0u64, r.width - 16.0, 9.0, style.defaults(), mem_one(a, widget.box(0u64, dot, zero)))
        n += 1usize
    }
    var sem: widget.Semantics = zero
    sem.role = 2u8
    var named = ty.name
    if g.nodes[index].label.len > 0usize {
        let (both, both_error) = joined(a, g.nodes[index].label, " (", ty.name)
        if both_error != ok { ret (zero, both_error) }
        let (closed, closed_error) = joined(a, both, ")", "")
        if closed_error != ok { ret (zero, closed_error) }
        named = closed
    }
    sem.label = named
    if selected { sem.states = accessibility.STATE_SELECTED }
    ret (widget.semantics(key, sem, control.sized_style(r.width, r.height), mem_one(a, widget.stack(0u64, box, parts[0usize..n]))), ok)
}

// The editor, `width` by `height`. Keys from `key`: the focus holder `+ 1`, the inspector's editor `+ 2`, the pointer region
// `+ 3`, a node `+ 4096 + its id`, the palette items `+ 1024 + index`, the inspector's field rows `+ 2048 + index`, the lint
// strip `+ 3072` and its issue rows `+ 3073 + index`. `draft` holds the text of the field being edited, `state.len` long;
// when an `InspectStart` event is applied the caller copies the field's current text into it and sets `state.len`.
fn flow_editor(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, g: Graph, state: FlowState, draft: []u8, change: widget.Change[FlowEvent], width: f32, height: f32, options: FlowOptions) -> (widget.Node, err) {
    if g.nodes.len > 256usize || g.types.len == 0usize { ret (zero, TooLarge) }
    let (issues, issues_error) = lint(a, g)
    if issues_error != ok { ret (zero, issues_error) }
    let pn = panes(width, height, state.lint_open, issues.len)
    let (ctxs, ctxs_error) = mem.alloc[FlowCtx](a, 1usize)
    if ctxs_error != ok { ret (zero, TooLarge) }
    ctxs[0usize] = FlowCtx { g: g, state: state, panes: pn, issues: issues, change: change, draft: draft, runtime: t.runtime, key: key, options: options }
    let ink = style.color(t.tokens, .OnSurface)
    let quiet = style.color(t.tokens, .OnSurfaceVariant)
    // ---- the canvas ----
    let (flags_in, flags_in_error) = mem.alloc[bool](a, g.nodes.len * 8usize + 8usize)
    if flags_in_error != ok { ret (zero, TooLarge) }
    let (flags_out, flags_out_error) = mem.alloc[bool](a, g.nodes.len * 8usize + 8usize)
    if flags_out_error != ok { ret (zero, TooLarge) }
    var z = 0usize
    while z < g.nodes.len * 8usize + 8usize {
        flags_in[z] = false
        flags_out[z] = false
        z += 1usize
    }
    var li = 0usize
    while li < g.links.len {
        let (_, _, real) = link_ends(g, li)
        if real {
            let (from_idx, _) = node_index(g, g.links[li].from)
            let (to_idx, _) = node_index(g, g.links[li].to)
            if g.links[li].from_port < 8usize { flags_out[from_idx * 8usize + g.links[li].from_port] = true }
            if g.links[li].to_port < 8usize { flags_in[to_idx * 8usize + g.links[li].to_port] = true }
        }
        li += 1usize
    }
    let (marks, marks_error) = mem.alloc[u8](a, g.nodes.len + 1usize)
    if marks_error != ok { ret (zero, TooLarge) }
    var m = 0usize
    while m < g.nodes.len {
        marks[m] = 0u8
        m += 1usize
    }
    var q = 0usize
    while q < issues.len {
        if issues[q].node != 0u32 {
            let (idx, found) = node_index(g, issues[q].node)
            if found {
                var level = 2u8
                if issues[q].severity == .Error { level = 1u8 }
                if marks[idx] == 0u8 || level < marks[idx] { marks[idx] = level }
            }
        }
        q += 1usize
    }
    let (layers, layers_error) = mem.alloc[widget.Node](a, g.nodes.len + 1usize)
    if layers_error != ok { ret (zero, TooLarge) }
    var n = 0usize
    while n < g.nodes.len {
        let chosen = state.has_selected && state.selected == g.nodes[n].id
        let (view, view_error) = node_view(a, t, key + 4096u64 + u64(g.nodes[n].id), g, n, chosen, flags_in[n * 8usize..n * 8usize + 8usize], flags_out[n * 8usize..n * 8usize + 8usize], marks[n])
        if view_error != ok { ret (zero, view_error) }
        let r = node_rect(g, n)
        layers[n] = widget.positioned(0u64, r.x - state.view.pan_x, r.y - state.view.pan_y, style.defaults(), mem_one(a, view))
        n += 1usize
    }
    let (grounds, grounds_error) = mem.alloc[GroundPaint](a, 1usize)
    if grounds_error != ok { ret (zero, TooLarge) }
    grounds[0usize] = GroundPaint { color: control.with_alpha(quiet, 0.35), step: grid_step(), pan_x: state.view.pan_x, pan_y: state.view.pan_y }
    let (paints, paints_error) = mem.alloc[LinkPaint](a, 1usize)
    if paints_error != ok { ret (zero, TooLarge) }
    var pending = false
    var from_pt = geometry.Point { x: 0.0, y: 0.0 }
    var to_pt = geometry.Point { x: 0.0, y: 0.0 }
    if state.drag.kind == .Link {
        let (d_idx, d_found) = node_index(g, state.drag.node)
        if d_found && state.drag.port < 8usize {
            pending = true
            let cursor = geometry.Point { x: state.drag.x - pn.canvas.x, y: state.drag.y - pn.canvas.y }
            let anchor_world = port_pos(g, d_idx, state.drag.from_output, state.drag.port)
            let anchor = geometry.Point { x: anchor_world.x - state.view.pan_x, y: anchor_world.y - state.view.pan_y }
            if state.drag.from_output {
                from_pt = anchor
                to_pt = cursor
            } else {
                from_pt = cursor
                to_pt = anchor
            }
        }
    }
    paints[0usize] = LinkPaint { arena: a, g: g, view: state.view, canvas: pn.canvas, ink: quiet, chosen: style.color(t.tokens, .Primary), selected: state.selected_link, has_selected: state.has_link, pending: pending, from: from_pt, to: to_pt, pending_ink: style.color(t.tokens, .Primary) }
    let (canvas_kids, canvas_kids_error) = mem.alloc[widget.Node](a, 4usize)
    if canvas_kids_error != ok { ret (zero, TooLarge) }
    canvas_kids[0usize] = custom_node(a, 0u64, mem.cast[*void](&grounds[0usize]), widget.bytes_of[GroundPaint](&grounds[0usize]), ground_measure, ground_paint, pn.canvas.width, pn.canvas.height)
    canvas_kids[1usize] = custom_node(a, 0u64, mem.cast[*void](&paints[0usize]), widget.bytes_of[LinkPaint](&paints[0usize]), ground_measure, links_paint, pn.canvas.width, pn.canvas.height)
    canvas_kids[2usize] = widget.stack(0u64, control.sized_style(pn.canvas.width, pn.canvas.height), layers[0usize..g.nodes.len])
    // the focus holder: a 2 by 2 button in the corner
    var fill = style.defaults()
    fill.width = style.Length { Percent: 100.0 }
    fill.height = style.Length { Percent: 100.0 }
    control.focus_look(t)
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, TooLarge) }
    held[0usize] = widget.button(key + 1u64, widget.Button { action: widget.Action { ctx: mem.cast[*void](&ctxs[0usize]), invoke: flow_input }, enabled: !options.disabled }, fill, zero)
    var holder = control.sized_style(2.0, 2.0)
    holder.overflow = .Clip
    canvas_kids[3usize] = widget.box(0u64, holder, held[0usize..1usize])
    var canvas_box = control.sized_style(pn.canvas.width, pn.canvas.height)
    canvas_box.overflow = .Clip
    canvas_box.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLowest) }
    var canvas_sem: widget.Semantics = zero
    canvas_sem.role = 39u8
    canvas_sem.label = "Canvas"
    let canvas = widget.semantics(0u64, canvas_sem, control.sized_style(pn.canvas.width, pn.canvas.height), mem_one(a, widget.stack(0u64, canvas_box, canvas_kids[0usize..4usize])))
    // ---- the palette ----
    var palette_parts: []widget.Node = zero
    let (pal, pal_error) = mem.alloc[widget.Node](a, g.types.len * 2usize + 2usize)
    if pal_error != ok { ret (zero, TooLarge) }
    var pn_count = 0usize
    if pn.palette.width > 0.0 {
        let (heading, heading_error) = text_node(a, t, "Nodes", .TitleSmall, ink)
        if heading_error != ok { ret (zero, heading_error) }
        pal[pn_count] = widget.positioned(0u64, 12.0, 8.0, style.defaults(), mem_one(a, heading))
        pn_count += 1usize
        var item = 0usize
        while item < g.types.len {
            let ty = g.types[item]
            let (name_node, name_error) = text_node(a, t, ty.name, .LabelLarge, ink)
            if name_error != ok { ret (zero, name_error) }
            let (ins, ins_error) = count_text(a, ty.inputs.len)
            if ins_error != ok { ret (zero, ins_error) }
            let (outs, outs_error) = count_text(a, ty.outputs.len)
            if outs_error != ok { ret (zero, outs_error) }
            let (a1, a1_error) = joined(a, ins, " in, ", outs)
            if a1_error != ok { ret (zero, a1_error) }
            let (caption_text, caption_error) = joined(a, a1, " out", "")
            if caption_error != ok { ret (zero, caption_error) }
            let (caption_node, caption_node_error) = text_node(a, t, caption_text, .BodySmall, quiet)
            if caption_node_error != ok { ret (zero, caption_node_error) }
            let (stacked, stacked_error) = mem.alloc[widget.Node](a, 2usize)
            if stacked_error != ok { ret (zero, TooLarge) }
            stacked[0usize] = name_node
            stacked[1usize] = caption_node
            var tile = control.sized_style(pn.palette.width - 16.0, 32.0)
            tile.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainer) }
            tile.radius = 6.0
            tile.padding = style.EdgeLengths { left: style.Length { Px: 10.0 }, top: style.Length { Px: 2.0 }, right: style.Length { Px: 6.0 }, bottom: style.Length { Px: 0.0 } }
            var item_sem: widget.Semantics = zero
            item_sem.role = 11u8
            let (added, added_error) = joined(a, "Add ", ty.name, "")
            if added_error != ok { ret (zero, added_error) }
            item_sem.label = added
            let tile_node = widget.semantics(key + 1024u64 + u64(item), item_sem, control.sized_style(pn.palette.width - 16.0, 32.0), mem_one(a, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, tile, stacked[0usize..2usize])))
            pal[pn_count] = widget.positioned(0u64, 8.0, 32.0 + f32(item) * 36.0, style.defaults(), mem_one(a, tile_node))
            pn_count += 1usize
            item += 1usize
        }
    }
    var palette_box = control.sized_style(pn.palette.width, pn.palette.height)
    palette_box.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    palette_box.overflow = .Clip
    palette_parts = pal[0usize..pn_count]
    // ---- the inspector ----
    let (insp, insp_error) = mem.alloc[widget.Node](a, 4usize * 12usize)
    if insp_error != ok { ret (zero, TooLarge) }
    var in_count = 0usize
    if pn.inspector.width > 0.0 {
        let (heading, heading_error) = text_node(a, t, "Inspector", .TitleSmall, ink)
        if heading_error != ok { ret (zero, heading_error) }
        insp[in_count] = widget.positioned(0u64, 12.0, 8.0, style.defaults(), mem_one(a, heading))
        in_count += 1usize
        var has_node = false
        var node_i = 0usize
        if state.has_selected {
            let (si, sf) = node_index(g, state.selected)
            node_i = si
            has_node = sf
        }
        if has_node {
            let ty = g.types[g.nodes[node_i].kind]
            let (type_node, type_error) = text_node(a, t, ty.name, .BodySmall, quiet)
            if type_error != ok { ret (zero, type_error) }
            insp[in_count] = widget.positioned(0u64, 12.0, 34.0, style.defaults(), mem_one(a, type_node))
            in_count += 1usize
            let fields = 1usize + g.nodes[node_i].params.len
            var f = 0usize
            while f < fields && f < 8usize {
                var name = "Label"
                var value = g.nodes[node_i].label
                if f > 0usize {
                    name = g.nodes[node_i].params[f - 1usize].name
                    value = g.nodes[node_i].params[f - 1usize].value
                }
                let (name_node, name_error) = text_node(a, t, name, .BodySmall, quiet)
                if name_error != ok { ret (zero, name_error) }
                var field = control.sized_style(pn.inspector.width - 24.0, 24.0)
                field.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
                field.border = style.Border { width: 1.0, color: style.color(t.tokens, .OutlineVariant) }
                field.radius = 4.0
                field.padding = style.EdgeLengths { left: style.Length { Px: 6.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 6.0 }, bottom: style.Length { Px: 0.0 } }
                var content: widget.Node = zero
                if state.editing && state.field == f {
                    let (look, look_error) = control.text_style(a, t, .BodyMedium)
                    if look_error != ok { ret (zero, look_error) }
                    field.border = style.Border { width: 2.0, color: style.color(t.tokens, .Primary) }
                    let (edits, edits_error) = mem.alloc[widget.Node](a, 1usize)
                    if edits_error != ok { ret (zero, TooLarge) }
                    edits[0usize] = widget.edit(key + 2u64, widget.Edit { buffer: draft, len: state.len, style: look, color: ink, selection: style.color(t.tokens, .TextSelection), change: widget.Change[str] { ctx: mem.cast[*void](&ctxs[0usize]), invoke: flow_typed }, submit: zero, enabled: true, read_only: false, multiline: false, secret: false, marked: style.color(t.tokens, .Primary), caret: ink, untabbed: false, ringed: false }, field)
                    let (named, named_error) = control.named_editor(a, key + 2u64, name, "", false, field, edits[0usize])
                    if named_error != ok { ret (zero, named_error) }
                    content = named
                } else {
                    var shown = value
                    if shown.len == 0usize { shown = "(none)" }
                    let (value_node, value_error) = text_node(a, t, shown, .BodyMedium, ink)
                    if value_error != ok { ret (zero, value_error) }
                    content = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 0.0 }, field, mem_one(a, value_node))
                }
                var row_sem: widget.Semantics = zero
                row_sem.role = 2u8
                row_sem.label = name
                row_sem.value = value
                let (row_parts, row_parts_error) = mem.alloc[widget.Node](a, 2usize)
                if row_parts_error != ok { ret (zero, TooLarge) }
                row_parts[0usize] = name_node
                row_parts[1usize] = content
                let row = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 2.0 }, control.sized_style(pn.inspector.width - 24.0, 42.0), row_parts[0usize..2usize])
                insp[in_count] = widget.positioned(key + 2048u64 + u64(f), 12.0, 56.0 + f32(f) * 44.0, style.defaults(), mem_one(a, widget.semantics(0u64, row_sem, control.sized_style(pn.inspector.width - 24.0, 42.0), mem_one(a, row))))
                in_count += 1usize
                f += 1usize
            }
        } else {
            let (hint, hint_error) = text_node(a, t, "Select a node", .BodySmall, quiet)
            if hint_error != ok { ret (zero, hint_error) }
            insp[in_count] = widget.positioned(0u64, 12.0, 34.0, style.defaults(), mem_one(a, hint))
            in_count += 1usize
        }
    }
    var inspector_box = control.sized_style(pn.inspector.width, pn.inspector.height)
    inspector_box.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainerLow) }
    inspector_box.overflow = .Clip
    // ---- the lint strip ----
    var errors = 0usize
    var warnings = 0usize
    var s = 0usize
    while s < issues.len {
        if issues[s].severity == .Error { errors += 1usize } else { warnings += 1usize }
        s += 1usize
    }
    let (strip, strip_error) = mem.alloc[widget.Node](a, 16usize)
    if strip_error != ok { ret (zero, TooLarge) }
    var sn = 0usize
    var summary = "No problems"
    if errors + warnings > 0usize {
        let (e_text, e_error) = count_text(a, errors)
        if e_error != ok { ret (zero, e_error) }
        let (w_text, w_error) = count_text(a, warnings)
        if w_error != ok { ret (zero, w_error) }
        let (first, first_error) = joined(a, e_text, " errors, ", w_text)
        if first_error != ok { ret (zero, first_error) }
        let (both, both_error) = joined(a, first, " warnings", "")
        if both_error != ok { ret (zero, both_error) }
        summary = both
    }
    var summary_ink = ink
    if errors > 0usize { summary_ink = style.color(t.tokens, .Error) }
    let (summary_node, summary_error) = text_node(a, t, summary, .LabelLarge, summary_ink)
    if summary_error != ok { ret (zero, summary_error) }
    var strip_sem: widget.Semantics = zero
    strip_sem.role = 26u8
    strip_sem.label = summary
    strip[sn] = widget.positioned(key + 3072u64, 12.0, 8.0, style.defaults(), mem_one(a, widget.semantics(0u64, strip_sem, style.defaults(), mem_one(a, summary_node))))
    sn += 1usize
    if state.lint_open {
        var row = 0usize
        while row < issues.len && row < 6usize {
            let (words, words_error) = issue_words(a, g, issues[row])
            if words_error != ok { ret (zero, words_error) }
            var tone = style.color(t.tokens, .Warning)
            if issues[row].severity == .Error { tone = style.color(t.tokens, .Error) }
            var dot = control.sized_style(8.0, 8.0)
            dot.radius = 4.0
            dot.background = paint.Brush { Solid: tone }
            let (words_node, words_node_error) = text_node(a, t, words, .BodySmall, ink)
            if words_node_error != ok { ret (zero, words_node_error) }
            let (cells, cells_error) = mem.alloc[widget.Node](a, 2usize)
            if cells_error != ok { ret (zero, TooLarge) }
            cells[0usize] = widget.box(0u64, dot, zero)
            cells[1usize] = words_node
            var item_sem: widget.Semantics = zero
            item_sem.role = 11u8
            item_sem.label = words
            let line = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Center, gap: 8.0 }, control.sized_style(pn.lint.width - 24.0, 22.0), cells[0usize..2usize])
            strip[sn] = widget.positioned(key + 3073u64 + u64(row), 12.0, 32.0 + f32(row) * 22.0, style.defaults(), mem_one(a, widget.semantics(0u64, item_sem, control.sized_style(pn.lint.width - 24.0, 22.0), mem_one(a, line))))
            sn += 1usize
            row += 1usize
        }
    }
    var lint_box = control.sized_style(pn.lint.width, pn.lint.height)
    lint_box.background = paint.Brush { Solid: style.color(t.tokens, .SurfaceContainer) }
    lint_box.overflow = .Clip
    // ---- the whole: panes at their places, a ghost for a palette drag, one region over it all ----
    let (everything, everything_error) = mem.alloc[widget.Node](a, 6usize)
    if everything_error != ok { ret (zero, TooLarge) }
    var e = 0usize
    everything[e] = widget.positioned(0u64, pn.palette.x, pn.palette.y, style.defaults(), mem_one(a, widget.stack(0u64, palette_box, palette_parts)))
    e += 1usize
    everything[e] = widget.positioned(0u64, pn.canvas.x, pn.canvas.y, style.defaults(), mem_one(a, canvas))
    e += 1usize
    everything[e] = widget.positioned(0u64, pn.inspector.x, pn.inspector.y, style.defaults(), mem_one(a, widget.stack(0u64, inspector_box, insp[0usize..in_count])))
    e += 1usize
    everything[e] = widget.positioned(0u64, pn.lint.x, pn.lint.y, style.defaults(), mem_one(a, widget.stack(0u64, lint_box, strip[0usize..sn])))
    e += 1usize
    if state.drag.kind == .Palette && state.drag.type_index < g.types.len {
        var ghost = control.sized_style(node_width(), header_height())
        ghost.background = paint.Brush { Solid: control.with_alpha(style.color(t.tokens, .SecondaryContainer), 0.85) }
        ghost.radius = 8.0
        let (ghost_text, ghost_error) = text_node(a, t, g.types[state.drag.type_index].name, .LabelLarge, style.color(t.tokens, .OnSecondaryContainer))
        if ghost_error != ok { ret (zero, ghost_error) }
        everything[e] = widget.positioned(0u64, state.drag.x - node_width() * 0.5, state.drag.y - header_height() * 0.5, style.defaults(), mem_one(a, widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Center, cross: .Center, gap: 0.0 }, ghost, mem_one(a, ghost_text))))
        e += 1usize
    }
    var surface = control.sized_style(width, height)
    surface.overflow = .Clip
    surface.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let region = widget.region(key + 3u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](&ctxs[0usize]), invoke: flow_press }, gestures: widget.GESTURE_TAP | widget.GESTURE_DRAG, enabled: !options.disabled, focusable: false }, control.sized_style(width, height), mem_one(a, widget.stack(0u64, surface, everything[0usize..e])))
    var sem: widget.Semantics = zero
    sem.role = 2u8
    sem.label = label
    let scoped = widget.scope(0u64, widget.Scope { traps_focus: false, shortcuts: zero, default_action: zero, cancel_action: zero, keys: widget.Change[input.KeyEvent] { ctx: mem.cast[*void](&ctxs[0usize]), invoke: flow_key } }, style.defaults(), mem_one(a, region))
    ret (widget.semantics(key, sem, control.sized_style(width, height), mem_one(a, scoped)), ok)
}
