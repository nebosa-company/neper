// `e.test.arch`: an 11-module graph built with intentional violations of every rule
// kind, and the exact violation list and text they must produce (8 violations: two
// layering, one forbid, one only-depend, two cycle members, one layer range, one
// naming). Also component-aware prefix matching (`e.fs` is not `e.fsx`), reading `use`
// lines from source, a clean graph, the TooSmall cuts and `assert_holds` leaving the
// text in `e.test.current`. Hand-derived from the edge list below. Every check has its
// own exit code.
use e.os
use e.mem
use e.str
use e.test
use e.test.arch as arch

fn build(g: *arch.Graph) -> i32 {
    let (_, m0) = arch.add_module(g, "e.mem", 0u8)
    let (_, m1) = arch.add_module(g, "e.str", 1u8)
    let (_, m2) = arch.add_module(g, "e.os", 3u8)
    let (_, m3) = arch.add_module(g, "e.fs", 4u8)
    let (_, m4) = arch.add_module(g, "e.fs.watch", 4u8)
    let (_, m5) = arch.add_module(g, "e.ui.core", 6u8)
    let (_, m6) = arch.add_module(g, "e.algo.sort", 2u8)
    let (_, m7) = arch.add_module(g, "x.a", 3u8)
    let (_, m8) = arch.add_module(g, "x.b", 3u8)
    let (_, m9) = arch.add_module(g, "app.main", 6u8)
    let (_, m10) = arch.add_module(g, "e.bad", 2u8)
    if m0 != ok || m1 != ok || m2 != ok || m3 != ok || m4 != ok || m5 != ok || m6 != ok || m7 != ok || m8 != ok || m9 != ok || m10 != ok { ret 1i32 }
    if arch.add_dep(g, "e.str", "e.mem") != ok { ret 2i32 }
    if arch.add_dep(g, "e.os", "e.mem") != ok { ret 2i32 }
    if arch.add_dep(g, "e.fs", "e.os") != ok { ret 2i32 }
    if arch.add_dep(g, "e.fs", "e.str") != ok { ret 2i32 }
    if arch.add_dep(g, "e.fs.watch", "e.fs") != ok { ret 2i32 }
    if arch.add_dep(g, "e.ui.core", "e.fs") != ok { ret 2i32 }
    if arch.add_dep(g, "e.algo.sort", "e.mem") != ok { ret 2i32 }
    if arch.add_dep(g, "e.algo.sort", "e.os") != ok { ret 2i32 }
    if arch.add_dep(g, "e.bad", "e.ui.core") != ok { ret 2i32 }
    if arch.add_dep(g, "x.a", "x.b") != ok { ret 2i32 }
    if arch.add_dep(g, "x.b", "x.a") != ok { ret 2i32 }
    if arch.add_dep(g, "x.a", "e.mem") != ok { ret 2i32 }
    if arch.add_dep(g, "app.main", "e.ui.core") != ok { ret 2i32 }
    if arch.add_dep(g, "app.main", "e.bad") != ok { ret 2i32 }
    ret 0i32
}

fn rules(out: []arch.Rule) {
    out[0] = arch.Rule { kind: .Layering, from: "", to: "", lo: 0u8, hi: 0u8 }
    out[1] = arch.Rule { kind: .Forbid, from: "e.fs", to: "e.str", lo: 0u8, hi: 0u8 }
    out[2] = arch.Rule { kind: .OnlyDepend, from: "e.algo", to: "e.mem,e.str", lo: 0u8, hi: 0u8 }
    out[3] = arch.Rule { kind: .NoCycles, from: "", to: "", lo: 0u8, hi: 0u8 }
    out[4] = arch.Rule { kind: .LayerRange, from: "e.algo", to: "", lo: 3u8, hi: 4u8 }
    out[5] = arch.Rule { kind: .Naming, from: "app", to: "", lo: 6u8, hi: 6u8 }
}

fn checks_graph() -> i32 {
    var names: [16]str = zero
    var layers: [16]u8 = zero
    var from: [32]u32 = zero
    var to: [32]u32 = zero
    var mark: [16]u8 = zero
    var stack: [16]u32 = zero
    var g = arch.graph(names[0..], layers[0..], from[0..], to[0..], mark[0..], stack[0..])
    if build(&g) != 0i32 { ret 10i32 }
    if arch.add_dep(&g, "e.mem", "nope") != arch.Unknown { ret 11i32 }
    var rs: [6]arch.Rule = zero
    rules(rs[0..])
    var found: [16]arch.Violation = zero
    let (n, check_error) = arch.check(&g, rs[0..], found[0..])
    if check_error != ok || n != 8usize { ret 12i32 }
    // Rule index and module per violation, in rule then edge/module order.
    if found[0].rule != 0usize || found[1].rule != 0usize || found[2].rule != 1usize || found[3].rule != 2usize { ret 13i32 }
    if found[4].rule != 3usize || found[5].rule != 3usize || found[6].rule != 4usize || found[7].rule != 5usize { ret 14i32 }
    if found[4].module != 7u32 || found[5].module != 8u32 || found[4].other != arch.NONE { ret 15i32 }
    var out: [1024]u8 = zero
    let want = "layering: e.algo.sort (layer 2) depends on e.os (layer 3)\nlayering: e.bad (layer 2) depends on e.ui.core (layer 6)\nforbidden: e.fs depends on e.str (e.fs must not depend on e.str)\nnot allowed: e.algo.sort depends on e.os (e.algo may depend only on e.mem,e.str)\ncycle: x.a is on a dependency cycle\ncycle: x.b is on a dependency cycle\nlayer range: e.algo.sort is in layer 2, expected 3..4\nnaming: e.ui.core (layer 6) must be under app\n"
    if !str.eq(arch.describe(&g, rs[0..], found[0..n], out[0..]), want) { ret 16i32 }
    // Fewer slots than violations: the first ones stand and the count says so.
    var few: [3]arch.Violation = zero
    let (cut, cut_error) = arch.check(&g, rs[0..], few[0..])
    if cut_error != arch.TooSmall || cut != 3usize { ret 17i32 }
    // The test assertion carries the whole list.
    var scratch: [16]arch.Violation = zero
    var buf: [1024]u8 = zero
    if arch.assert_holds(&g, rs[0..], scratch[0..], buf[0..]) != test.Failed { ret 18i32 }
    if !str.eq(test.current.message, want) { ret 19i32 }
    ret 0i32
}

fn checks_clean() -> i32 {
    var names: [4]str = zero
    var layers: [4]u8 = zero
    var from: [4]u32 = zero
    var to: [4]u32 = zero
    var mark: [4]u8 = zero
    var stack: [4]u32 = zero
    var g = arch.graph(names[0..], layers[0..], from[0..], to[0..], mark[0..], stack[0..])
    let (_, a) = arch.add_module(&g, "core", 0u8)
    let (_, b) = arch.add_module(&g, "app", 1u8)
    if a != ok || b != ok { ret 20i32 }
    if arch.add_dep(&g, "app", "core") != ok { ret 21i32 }
    var rs: [2]arch.Rule = zero
    rs[0] = arch.Rule { kind: .Layering, from: "", to: "", lo: 0u8, hi: 0u8 }
    rs[1] = arch.Rule { kind: .NoCycles, from: "", to: "", lo: 0u8, hi: 0u8 }
    var scratch: [4]arch.Violation = zero
    var buf: [64]u8 = zero
    if arch.assert_holds(&g, rs[0..], scratch[0..], buf[0..]) != ok { ret 22i32 }
    // Storage limits are refused, not overrun.
    if arch.add_dep(&g, "app", "core") != ok || arch.add_dep(&g, "app", "core") != ok || arch.add_dep(&g, "app", "core") != ok { ret 23i32 }
    if arch.add_dep(&g, "app", "core") != arch.TooSmall { ret 24i32 }
    ret 0i32
}

fn checks_text() -> i32 {
    if !arch.under("e.fs", "e.fs") || !arch.under("e.fs.watch", "e.fs") || arch.under("e.fsx", "e.fs") { ret 30i32 }
    if arch.under("e", "e.fs") || !arch.under("anything", "") { ret 31i32 }
    if !arch.under_any("e.str.x", "e.mem, e.str") || arch.under_any("e.os", "e.mem,e.str") { ret 32i32 }
    var found: [8]str = zero
    let source = "// header\nuse e.mem\nuse e.db.migrate as migrate\n  use e.indented\nfn x() {}\nuse x.sqlite.sqlite\n"
    let n = arch.uses(source, found[0..])
    if n != 3usize { ret 33i32 }
    if !str.eq(found[0], "e.mem") || !str.eq(found[1], "e.db.migrate") || !str.eq(found[2], "x.sqlite.sqlite") { ret 34i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    var code = checks_graph()
    if code == 0i32 { code = checks_clean() }
    if code == 0i32 { code = checks_text() }
    if code != 0i32 { os.exit(code) }
    ret ok
}
