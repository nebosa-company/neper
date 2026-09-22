// `e.algo.egraph`: the hashcons folds a repeated node, merging two leaves and
// rebuilding unites their parents (upward congruence), the egg README rules
// saturate (a*2)/2 to a in the replica's iteration, class and node counts and
// extract with unit costs reads the leaf a, commutativity and associativity
// hit a node cap yet a+(b+c) ≡ (a+b)+c, and exhausted storage is reported.
// Each check exits with its own code. Expected values: scratch egraph_ref.py.

use e.algo.egraph as eg
use e.io
use e.mem
use e.os

fn mul() -> u32 { ret 1u32 }
fn dv() -> u32 { ret 2u32 }
fn shl() -> u32 { ret 3u32 }
fn add_op() -> u32 { ret 4u32 }
fn constant(v: u32) -> u32 { ret 100u32 + v }
fn sym(k: u32) -> u32 { ret 200u32 + k }

fn main(a: *mem.Arena, args: []str) -> err {
    let none = eg.none()
    let v0 = eg.variable(0u32)
    let v1 = eg.variable(1u32)
    let v2 = eg.variable(2u32)
    var op: [64]u32 = zero
    var ca: [64]u32 = zero
    var cb: [64]u32 = zero
    var parent: [64]u32 = zero
    var rank: [64]u8 = zero
    var table: [129]u32 = zero
    var matches: [400]u32 = zero

    // 1: hashcons.
    let (g1, e1) = eg.egraph(op[..], ca[..], cb[..], parent[..], rank[..], table[..])
    if e1 != ok { os.exit(1i32) }
    var g = g1
    let (x1, xe1) = eg.add_leaf(&g, sym(0u32))
    let (x2, xe2) = eg.add_leaf(&g, sym(0u32))
    if xe1 != ok || xe2 != ok || x1 != x2 || eg.node_count(&g) != 1usize || eg.class_count(&g) != 1usize { os.exit(1i32) }

    // 2: merge + rebuild gives upward congruence.
    let (g2, e2) = eg.egraph(op[..], ca[..], cb[..], parent[..], rank[..], table[..])
    if e2 != ok { os.exit(2i32) }
    g = g2
    let (la, _) = eg.add_leaf(&g, sym(0u32))
    let (lb, _) = eg.add_leaf(&g, sym(1u32))
    let (fa, _) = eg.add(&g, add_op(), la, none)
    let (fb, fe) = eg.add(&g, add_op(), lb, none)
    if fe != ok || fa == fb { os.exit(2i32) }
    let _ = eg.merge(&g, la, lb)
    eg.rebuild(&g)
    if eg.find(&g, fa) != eg.find(&g, fb) || eg.node_count(&g) != 3usize || eg.class_count(&g) != 2usize { os.exit(2i32) }

    // 3: the egg README example.
    var rules: [4]eg.Rule = zero
    // x*2 -> x<<1
    let p1o = [3]u32{ mul(), v0, constant(2u32) }
    let p1a = [3]u32{ 1u32, none, none }
    let p1b = [3]u32{ 2u32, none, none }
    let q1o = [3]u32{ shl(), v0, constant(1u32) }
    rules[0usize] = eg.Rule { lhs: eg.Pattern { op: p1o[..], a: p1a[..], b: p1b[..], root: 0u32 }, rhs: eg.Pattern { op: q1o[..], a: p1a[..], b: p1b[..], root: 0u32 } }
    // (x*y)/z -> x*(y/z)
    let p2o = [5]u32{ dv(), mul(), v0, v1, v2 }
    let p2a = [5]u32{ 1u32, 2u32, none, none, none }
    let p2b = [5]u32{ 4u32, 3u32, none, none, none }
    let q2o = [5]u32{ mul(), v0, dv(), v1, v2 }
    let q2a = [5]u32{ 1u32, none, 3u32, none, none }
    let q2b = [5]u32{ 2u32, none, 4u32, none, none }
    rules[1usize] = eg.Rule { lhs: eg.Pattern { op: p2o[..], a: p2a[..], b: p2b[..], root: 0u32 }, rhs: eg.Pattern { op: q2o[..], a: q2a[..], b: q2b[..], root: 0u32 } }
    // x/x -> 1
    let p3o = [3]u32{ dv(), v0, v0 }
    let q3o = [1]u32{ constant(1u32) }
    let q3n = [1]u32{ none }
    rules[2usize] = eg.Rule { lhs: eg.Pattern { op: p3o[..], a: p1a[..], b: p1b[..], root: 0u32 }, rhs: eg.Pattern { op: q3o[..], a: q3n[..], b: q3n[..], root: 0u32 } }
    // x*1 -> x
    let p4o = [3]u32{ mul(), v0, constant(1u32) }
    let q4o = [1]u32{ v0 }
    rules[3usize] = eg.Rule { lhs: eg.Pattern { op: p4o[..], a: p1a[..], b: p1b[..], root: 0u32 }, rhs: eg.Pattern { op: q4o[..], a: q3n[..], b: q3n[..], root: 0u32 } }

    let (g3, e3) = eg.egraph(op[..], ca[..], cb[..], parent[..], rank[..], table[..])
    if e3 != ok { os.exit(3i32) }
    g = g3
    let (sa, _) = eg.add_leaf(&g, sym(0u32))
    let (two, _) = eg.add_leaf(&g, constant(2u32))
    let (m, _) = eg.add(&g, mul(), sa, two)
    let (root, re) = eg.add(&g, dv(), m, two)
    if re != ok { os.exit(3i32) }
    let (iterations, se) = eg.saturate(&g, rules[..], 20usize, matches[..])
    if se != ok || iterations != 4usize { os.exit(3i32) }
    if eg.find(&g, root) != eg.find(&g, sa) { os.exit(3i32) }
    if eg.node_count(&g) != 8usize || eg.class_count(&g) != 4usize { os.exit(3i32) }
    var best_cost: [64]u32 = zero
    var best_node: [64]u32 = zero
    var costs: [0]u32 = zero
    let (cost, xe) = eg.extract(&g, root, costs[..], best_cost[..], best_node[..])
    if xe != ok || cost != 1u32 { os.exit(3i32) }
    var out_op: [8]u32 = zero
    var out_a: [8]u32 = zero
    var out_b: [8]u32 = zero
    let (written, we) = eg.extract_write(&g, root, best_node[..], out_op[..], out_a[..], out_b[..])
    if we != ok || written != 1usize || out_op[0usize] != sym(0u32) || out_a[0usize] != none || out_b[0usize] != none { os.exit(3i32) }

    // 4: commutativity + associativity under a cap of 12 nodes.
    var rules2: [2]eg.Rule = zero
    let c1o = [3]u32{ add_op(), v0, v1 }
    let d1o = [3]u32{ add_op(), v1, v0 }
    rules2[0usize] = eg.Rule { lhs: eg.Pattern { op: c1o[..], a: p1a[..], b: p1b[..], root: 0u32 }, rhs: eg.Pattern { op: d1o[..], a: p1a[..], b: p1b[..], root: 0u32 } }
    let c2o = [5]u32{ add_op(), add_op(), v0, v1, v2 }
    let d2o = [5]u32{ add_op(), v0, add_op(), v1, v2 }
    rules2[1usize] = eg.Rule { lhs: eg.Pattern { op: c2o[..], a: p2a[..], b: p2b[..], root: 0u32 }, rhs: eg.Pattern { op: d2o[..], a: q2a[..], b: q2b[..], root: 0u32 } }
    let (g4, e4) = eg.egraph(op[..12usize], ca[..], cb[..], parent[..], rank[..], table[..])
    if e4 != ok { os.exit(4i32) }
    g = g4
    let (ya, _) = eg.add_leaf(&g, sym(0u32))
    let (yb, _) = eg.add_leaf(&g, sym(1u32))
    let (yc, _) = eg.add_leaf(&g, sym(2u32))
    let (ab, _) = eg.add(&g, add_op(), ya, yb)
    let (abc, _) = eg.add(&g, add_op(), ab, yc)
    let (bc, _) = eg.add(&g, add_op(), yb, yc)
    let (a_bc, ae) = eg.add(&g, add_op(), ya, bc)
    if ae != ok || eg.find(&g, abc) == eg.find(&g, a_bc) { os.exit(4i32) }
    let (iterations2, se2) = eg.saturate(&g, rules2[..], 20usize, matches[..])
    if se2 != eg.TooSmall || iterations2 != 2usize { os.exit(4i32) }
    if eg.find(&g, abc) != eg.find(&g, a_bc) { os.exit(4i32) }
    if eg.node_count(&g) != 12usize || eg.class_count(&g) != 7usize { os.exit(4i32) }

    // 5: exhausted storage.
    let (g5, e5) = eg.egraph(op[..2usize], ca[..], cb[..], parent[..], rank[..], table[..])
    if e5 != ok { os.exit(5i32) }
    g = g5
    let (_, z0) = eg.add_leaf(&g, sym(0u32))
    let (_, z1) = eg.add_leaf(&g, sym(1u32))
    let (_, z2) = eg.add_leaf(&g, sym(2u32))
    if z0 != ok || z1 != ok || z2 != eg.TooSmall { os.exit(5i32) }
    let (_, te) = eg.egraph(op[..], ca[..], cb[..], parent[..], rank[..], table[..100usize])
    if te != eg.TooSmall { os.exit(5i32) }
    let (_, ve) = eg.add_leaf(&g, v0)
    if ve != eg.Invalid { os.exit(5i32) }

    try io.print("algo egraph ok\n")
    ret ok
}
