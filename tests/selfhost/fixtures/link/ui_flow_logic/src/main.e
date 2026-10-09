// e.ui.flow model and geometry (D2284, L091) against brute force on seeded random graphs: link rules against a transitive
// closure, the lint against closure-based definitions (cycles are nodes that reach themselves; unreachable nodes are those
// no source reaches), hit testing against the shapes the nodes and ports are known to occupy, the curve distance against
// a dense sampling, and hand cases for the panes, snapping, fit and the refusal reasons.
use e.io
use e.mem
use e.os
use e.gfx.geometry
use e.ui.flow as fl

type Rng = struct { state: u64 }

fn next(r: *Rng) -> u64 {
    r.state = (r.state * 1664525u64 + 1013904223u64) % 4294967296u64
    ret r.state / 256u64
}

fn below(r: *Rng, n: usize) -> usize {
    ret usize(next(r) % u64(n))
}

fn fail(code: i32) -> err {
    let _ = io.print("ui flow logic failed at ")
    var digits: [6]u8 = zero
    digits[0] = u8(48i32 + code / 10000i32)
    digits[1] = u8(48i32 + (code / 1000i32) % 10i32)
    digits[2] = u8(48i32 + (code / 100i32) % 10i32)
    digits[3] = u8(48i32 + (code / 10i32) % 10i32)
    digits[4] = u8(48i32 + code % 10i32)
    let _ = io.print(digits[..5])
    let _ = io.print("\n")
    os.exit(code)
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn count_issues(issues: []const fl.Issue, code: fl.Code, node: u32) -> usize {
    var n = 0usize
    var i = 0usize
    while i < issues.len {
        if issues[i].code == code && issues[i].node == node { n += 1usize }
        i += 1usize
    }
    ret n
}

fn main(a: *mem.Arena) -> err {
    let in0: [0]str = zero
    let in1 = [1]str{ "in" }
    let in2 = [2]str{ "a", "b" }
    let in3 = [3]str{ "a", "b", "c" }
    let out0: [0]str = zero
    let out1 = [1]str{ "out" }
    let out2 = [2]str{ "yes", "no" }
    let types = [4]fl.NodeType{
        fl.NodeType { name: "Source", inputs: in0[0..], outputs: out1[0..], required: 0u32 },
        fl.NodeType { name: "Filter", inputs: in1[0..], outputs: out2[0..], required: 1u32 },
        fl.NodeType { name: "Join", inputs: in3[0..], outputs: out1[0..], required: 3u32 },
        fl.NodeType { name: "Sink", inputs: in2[0..], outputs: out0[0..], required: 1u32 },
    }
    var rng = Rng { state: 20261029u64 }
    var round = 0usize
    while round < 150usize {
        let mark = mem.mark(a)
        let n = 2usize + below(&rng, 14usize)
        let (nodes, nodes_error) = mem.alloc[fl.Node](a, n)
        if nodes_error != ok { ret fail(1i32) }
        var i = 0usize
        let labels = [5]str{ "a", "b", "c", "load", "save" }
        while i < n {
            // nodes on a coarse grid so none overlap: 5 columns of 240 by rows of 200, with a little jitter
            let col = i % 5usize
            let row = i / 5usize
            nodes[i] = fl.Node { id: u32(10usize + i * 3usize), kind: below(&rng, 4usize), x: f32(col * 240usize + below(&rng, 4usize) * 10usize), y: f32(row * 200usize + below(&rng, 4usize) * 10usize), label: labels[below(&rng, 5usize)], params: zero }
            i += 1usize
        }
        // a duplicate id now and then
        var dup_id = false
        if below(&rng, 6usize) == 0usize && n > 2usize {
            nodes[n - 1usize].id = nodes[0usize].id
            dup_id = true
        }
        let (links, links_error) = mem.alloc[fl.Link](a, 40usize)
        if links_error != ok { ret fail(2i32) }
        var lc = 0usize
        var attempts = 0usize
        while attempts < 60usize && lc < 30usize {
            attempts += 1usize
            let from = below(&rng, n)
            let to = below(&rng, n)
            let fp = below(&rng, 3usize)
            let tp = below(&rng, 4usize)
            links[lc] = fl.Link { from: nodes[from].id, from_port: fp, to: nodes[to].id, to_port: tp }
            lc += 1usize
        }
        // and one link to a node that is not there
        if below(&rng, 5usize) == 0usize {
            links[lc] = fl.Link { from: 9999u32, from_port: 0usize, to: nodes[0usize].id, to_port: 0usize }
            lc += 1usize
        }
        let g = fl.Graph { types: types[0..], nodes: nodes[0..n], links: links[0..lc] }
        // ---- rectangles and ports ----
        i = 0usize
        while i < n {
            let t = types[nodes[i].kind]
            var ports = t.inputs.len
            if t.outputs.len > ports { ports = t.outputs.len }
            let r = fl.node_rect(g, i)
            if !near(r.width, 160.0) || !near(r.height, 28.0 + f32(ports) * 20.0 + 8.0) || !near(r.x, nodes[i].x) || !near(r.y, nodes[i].y) { ret fail(100i32 + i32(round)) }
            if t.inputs.len > 0usize {
                let p = fl.port_pos(g, i, false, t.inputs.len - 1usize)
                if !near(p.x, nodes[i].x) || !near(p.y, nodes[i].y + 28.0 + f32(t.inputs.len - 1usize) * 20.0 + 10.0) { ret fail(300i32 + i32(round)) }
            }
            if t.outputs.len > 0usize {
                let p = fl.port_pos(g, i, true, 0usize)
                if !near(p.x, nodes[i].x + 160.0) || !near(p.y, nodes[i].y + 38.0) { ret fail(500i32 + i32(round)) }
            }
            i += 1usize
        }
        // ---- the closure: reach[x][y] when a path of one or more valid links runs from node x to node y ----
        var reach: [256]bool = zero
        var valid: [256]bool = zero
        var k = 0usize
        while k < lc {
            let (from_idx, has_from) = fl.node_index(g, links[k].from)
            let (to_idx, has_to) = fl.node_index(g, links[k].to)
            if has_from && has_to && links[k].from_port < types[nodes[from_idx].kind].outputs.len && links[k].to_port < types[nodes[to_idx].kind].inputs.len {
                reach[from_idx * 16usize + to_idx] = true
            }
            k += 1usize
        }
        var via = 0usize
        while via < n {
            var x = 0usize
            while x < n {
                var y = 0usize
                while y < n {
                    if reach[x * 16usize + via] && reach[via * 16usize + y] { reach[x * 16usize + y] = true }
                    y += 1usize
                }
                x += 1usize
            }
            via += 1usize
        }
        // ---- the lint ----
        let (issues, lint_error) = fl.lint(a, g)
        if lint_error != ok { ret fail(700i32 + i32(round)) }
        i = 0usize
        while i < n {
            let id = nodes[i].id
            // the first node with this id decides: a repeated id is the issue itself
            var first_with_id = true
            var j = 0usize
            while j < i {
                if nodes[j].id == id { first_with_id = false }
                j += 1usize
            }
            if first_with_id {
                var expect_cycle = 0usize
                if reach[i * 16usize + i] { expect_cycle = 1usize }
                // a duplicate id shares the first node's index in lookups, so only count nodes whose id is unique
                var unique = !dup_id
                j = 0usize
                while j < n {
                    if j != i && nodes[j].id == id { unique = false }
                    j += 1usize
                }
                if unique {
                    if count_issues(issues, .Cycle, id) != expect_cycle { ret fail(1000i32 + i32(round)) }
                    // unreachable: has inputs and no source reaches it
                    var from_source = false
                    var s = 0usize
                    while s < n {
                        if types[nodes[s].kind].inputs.len == 0usize && (s == i || reach[s * 16usize + i]) { from_source = true }
                        s += 1usize
                    }
                    var expect_unreachable = 0usize
                    if types[nodes[i].kind].inputs.len > 0usize && !from_source { expect_unreachable = 1usize }
                    if count_issues(issues, .Unreachable, id) != expect_unreachable { ret fail(1300i32 + i32(round)) }
                    // isolated: no link names this node
                    var touched = false
                    k = 0usize
                    while k < lc {
                        if links[k].from == id || links[k].to == id { touched = true }
                        k += 1usize
                    }
                    var expect_isolated = 0usize
                    if !touched { expect_isolated = 1usize }
                    if count_issues(issues, .Isolated, id) != expect_isolated { ret fail(1600i32 + i32(round)) }
                }
            }
            i += 1usize
        }
        // dangling links: those whose ends do not exist
        var dangling = 0usize
        k = 0usize
        while k < lc {
            let (_, _, real) = fl.link_ends(g, k)
            if !real { dangling += 1usize }
            k += 1usize
        }
        var found_dangling = 0usize
        i = 0usize
        while i < issues.len {
            if issues[i].code == .DanglingLink { found_dangling += 1usize }
            i += 1usize
        }
        if found_dangling != dangling { ret fail(1900i32 + i32(round)) }
        // ---- connection rules against the closure ----
        var probes = 0usize
        while probes < 20usize {
            let from = below(&rng, n)
            let to = below(&rng, n)
            let fp = below(&rng, 3usize)
            let tp = below(&rng, 4usize)
            let verdict = fl.can_connect(g, nodes[from].id, fp, nodes[to].id, tp, true)
            let (from_first, _) = fl.node_index(g, nodes[from].id)
            let (to_first, _) = fl.node_index(g, nodes[to].id)
            let unique_from = from_first == from
            let unique_to = to_first == to
            if unique_from && unique_to {
                var expect: fl.Connect = .Ok
                if from == to {
                    expect = .SelfLoop
                } else if fp >= types[nodes[from].kind].outputs.len || tp >= types[nodes[to].kind].inputs.len {
                    expect = .BadPort
                } else {
                    var dup = false
                    var taken = false
                    k = 0usize
                    while k < lc {
                        if links[k].to == nodes[to].id && links[k].to_port == tp {
                            taken = true
                            if links[k].from == nodes[from].id && links[k].from_port == fp { dup = true }
                        }
                        k += 1usize
                    }
                    if dup { expect = .Duplicate } else if taken { expect = .InputTaken } else if reach[to * 16usize + from] { expect = .Cycle }
                }
                if verdict != expect { ret fail(2200i32 + i32(round)) }
            }
            probes += 1usize
        }
        // ---- hit testing on a canvas at the origin with a pan ----
        let canvas = geometry.rect(0.0, 0.0, 1400.0, 900.0)
        let view = fl.View { pan_x: 0.0 - f32(1usize + below(&rng, 5usize)) * 10.0, pan_y: 0.0 - f32(1usize + below(&rng, 5usize)) * 10.0 }
        i = 0usize
        while i < n {
            let (first_idx, _) = fl.node_index(g, nodes[i].id)
            if first_idx != i {
                i += 1usize
                continue
            }
            let t = types[nodes[i].kind]
            let body = fl.to_screen(view, canvas, geometry.Point { x: nodes[i].x + 80.0, y: nodes[i].y + 14.0 })
            let hit = fl.hit_test(g, view, canvas, body.x, body.y)
            if hit.kind != .Node || hit.node != nodes[i].id { ret fail(2500i32 + i32(round)) }
            if t.outputs.len > 0usize {
                let p = fl.to_screen(view, canvas, fl.port_pos(g, i, true, t.outputs.len - 1usize))
                let h2 = fl.hit_test(g, view, canvas, p.x, p.y)
                if h2.kind != .OutPort || h2.node != nodes[i].id || h2.port != t.outputs.len - 1usize { ret fail(2800i32 + i32(round)) }
            }
            if t.inputs.len > 0usize {
                let p = fl.to_screen(view, canvas, fl.port_pos(g, i, false, 0usize))
                let h3 = fl.hit_test(g, view, canvas, p.x, p.y)
                if h3.kind != .InPort || h3.node != nodes[i].id || h3.port != 0usize { ret fail(3100i32 + i32(round)) }
            }
            i += 1usize
        }
        if fl.hit_test(g, view, canvas, 1395.0, 895.0).kind != .Canvas || fl.hit_test(g, view, canvas, -5.0, 10.0).kind != .Canvas { ret fail(3400i32 + i32(round)) }
        // ---- curve distance against dense sampling ----
        k = 0usize
        while k < lc && k < 4usize {
            let (from, to, real) = fl.link_ends(g, k)
            if real {
                let probe = geometry.Point { x: from.x + f32(below(&rng, 200usize)) - 50.0, y: from.y + f32(below(&rng, 200usize)) - 100.0 }
                var best: f32 = 1000000.0
                var s = 0usize
                while s <= 2000usize {
                    let p = fl.curve_point(from, to, f32(s) / 2000.0)
                    let dx = p.x - probe.x
                    let dy = p.y - probe.y
                    let d2 = dx * dx + dy * dy
                    if d2 < best { best = d2 }
                    s += 1usize
                }
                let exact = fl.sqrt32(best)
                let coarse = fl.link_distance(from, to, probe)
                // 24 straight pieces stand within the curve's sagitta (under a pixel and a half) of the dense measure
                if coarse > exact + 1.5 || coarse < exact - 1.5 { ret fail(3700i32 + i32(round)) }
            }
            k += 1usize
        }
        mem.reset(a, mark)
        round += 1usize
    }
    // ---- hand cases ----
    let ends = fl.curve_point(geometry.Point { x: 0.0, y: 0.0 }, geometry.Point { x: 200.0, y: 100.0 }, 0.0)
    let finish = fl.curve_point(geometry.Point { x: 0.0, y: 0.0 }, geometry.Point { x: 200.0, y: 100.0 }, 1.0)
    let middle = fl.curve_point(geometry.Point { x: 0.0, y: 0.0 }, geometry.Point { x: 200.0, y: 100.0 }, 0.5)
    if !near(ends.x, 0.0) || !near(ends.y, 0.0) || !near(finish.x, 200.0) || !near(finish.y, 100.0) || !near(middle.x, 100.0) || !near(middle.y, 50.0) { ret fail(5000i32) }
    if !near(fl.snap(13.0, 20.0), 20.0) || !near(fl.snap(9.0, 20.0), 0.0) || !near(fl.snap(-11.0, 20.0), -20.0) || !near(fl.snap(30.0, 20.0), 40.0) || !near(fl.snap(7.5, 0.0), 7.5) { ret fail(5001i32) }
    let p = fl.panes(1000.0, 600.0, false, 3usize)
    if !near(p.palette.width, 168.0) || !near(p.inspector.width, 220.0) || !near(p.inspector.x, 780.0) || !near(p.canvas.x, 168.0) || !near(p.canvas.width, 612.0) || !near(p.lint.y, 568.0) || !near(p.lint.height, 32.0) || !near(p.canvas.height, 568.0) { ret fail(5002i32) }
    let open = fl.panes(1000.0, 600.0, true, 9usize)
    if !near(open.lint.height, 32.0 + 6.0 * 22.0) || !near(open.canvas.height, 600.0 - 164.0) { ret fail(5003i32) }
    let narrow = fl.panes(500.0, 400.0, false, 0usize)
    if !near(narrow.palette.width, 0.0) || !near(narrow.inspector.width, 0.0) || !near(narrow.canvas.width, 500.0) { ret fail(5004i32) }
    if fl.pane_at(p, 50.0, 50.0) != .Palette || fl.pane_at(p, 400.0, 50.0) != .Canvas || fl.pane_at(p, 900.0, 50.0) != .Inspector || fl.pane_at(p, 400.0, 580.0) != .Lint || fl.pane_at(p, 1200.0, 50.0) != .None { ret fail(5005i32) }
    if fl.palette_item_at(p, 4usize, 20.0, 33.0) != 0usize || fl.palette_item_at(p, 4usize, 20.0, 32.0 + 36.0 * 2.0 + 1.0) != 2usize || fl.palette_item_at(p, 4usize, 20.0, 32.0 + 36.0 * 4.0 + 1.0) != 4usize || fl.palette_item_at(p, 4usize, 20.0, 10.0) != 4usize || fl.palette_item_at(p, 4usize, 400.0, 40.0) != 4usize { ret fail(5006i32) }
    // fit: two nodes; the view puts the bounding box 24 from the corner, centred when it is smaller than the canvas
    let two_types = [2]fl.NodeType{ fl.NodeType { name: "Source", inputs: in0[0..], outputs: out1[0..], required: 0u32 }, fl.NodeType { name: "Sink", inputs: in1[0..], outputs: out0[0..], required: 1u32 } }
    let two_nodes = [2]fl.Node{ fl.Node { id: 1u32, kind: 0usize, x: 100.0, y: 50.0, label: "s", params: zero }, fl.Node { id: 2u32, kind: 1usize, x: 400.0, y: 250.0, label: "t", params: zero } }
    let one_link = [1]fl.Link{ fl.Link { from: 1u32, from_port: 0usize, to: 2u32, to_port: 0usize } }
    let two = fl.Graph { types: two_types[0..], nodes: two_nodes[0..], links: one_link[0..] }
    let tight = fl.fit(two, 300.0, 200.0)
    if !near(tight.pan_x, 76.0) || !near(tight.pan_y, 26.0) { ret fail(5007i32) }
    let roomy = fl.fit(two, 1000.0, 600.0)
    // box 100..560 by 50..306: 460 by 256 plus 48 each; spare 1000-508 and 600-304
    if !near(roomy.pan_x, 76.0 - (1000.0 - 508.0) * 0.5) || !near(roomy.pan_y, 26.0 - (600.0 - 304.0) * 0.5) { ret fail(5008i32) }
    // refusal reasons
    if fl.can_connect(two, 1u32, 0usize, 2u32, 0usize, true) != .Duplicate || fl.can_connect(two, 1u32, 0usize, 1u32, 0usize, true) != .SelfLoop || fl.can_connect(two, 1u32, 0usize, 9u32, 0usize, true) != .UnknownNode || fl.can_connect(two, 1u32, 3usize, 2u32, 0usize, true) != .BadPort { ret fail(5009i32) }
    // lint of the two-node graph: nothing wrong; with the link gone the sink is unconnected, unreachable, and both are isolated
    let (clean, clean_error) = fl.lint(a, two)
    if clean_error != ok || clean.len != 0usize { ret fail(5010i32) }
    let no_links: [0]fl.Link = zero
    let bare = fl.Graph { types: two_types[0..], nodes: two_nodes[0..], links: no_links[0..] }
    let (bare_issues, bare_error) = fl.lint(a, bare)
    if bare_error != ok || count_issues(bare_issues, .UnconnectedInput, 2u32) != 1usize || count_issues(bare_issues, .Unreachable, 2u32) != 1usize || count_issues(bare_issues, .Isolated, 1u32) != 1usize || count_issues(bare_issues, .Isolated, 2u32) != 1usize { ret fail(5011i32) }
    // a loop: filter feeds itself through a join
    let loop_types = [2]fl.NodeType{ fl.NodeType { name: "Source", inputs: in0[0..], outputs: out1[0..], required: 0u32 }, fl.NodeType { name: "Join", inputs: in2[0..], outputs: out1[0..], required: 0u32 } }
    let loop_nodes = [2]fl.Node{ fl.Node { id: 1u32, kind: 0usize, x: 0.0, y: 0.0, label: "", params: zero }, fl.Node { id: 2u32, kind: 1usize, x: 300.0, y: 0.0, label: "", params: zero } }
    let loop_links = [3]fl.Link{ fl.Link { from: 1u32, from_port: 0usize, to: 2u32, to_port: 0usize }, fl.Link { from: 2u32, from_port: 0usize, to: 2u32, to_port: 1usize }, fl.Link { from: 2u32, from_port: 0usize, to: 2u32, to_port: 0usize } }
    let loop_graph = fl.Graph { types: loop_types[0..], nodes: loop_nodes[0..], links: loop_links[0..] }
    let (loop_issues, loop_error) = fl.lint(a, loop_graph)
    if loop_error != ok || count_issues(loop_issues, .Cycle, 2u32) != 1usize || count_issues(loop_issues, .InputFed, 2u32) != 1usize || count_issues(loop_issues, .Cycle, 1u32) != 0usize { ret fail(5012i32) }
    try io.print("ui flow logic ok\n")
    ret ok
}
