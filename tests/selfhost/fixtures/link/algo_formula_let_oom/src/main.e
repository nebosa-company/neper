// LET and LETS must not continue under an older scope after their binding
// allocation fails.  Each low-arena call has an outer x = 5, so the old bug
// would return that plausible value instead of a formula error.
use e.algo.formula as formula
use e.mem
use e.os
use e.str

fn is_oom(v: formula.Value) -> bool {
    ret v.kind == .Error && v.code == formula.E_ERROR && str.eq(v.s, "Out of memory")
}

fn let_oom() -> bool {
    var storage: [1]u8 = zero
    var arena = mem.arena_from(storage[0usize..0usize])
    var context: formula.Context = zero
    var evaluator = formula.evaluator(&arena, zero, &context)
    var outer = formula.Scope { name: "x", value: formula.number(5.0f64), parent: zero, has_parent: false }
    var nodes: [3]formula.Node = zero
    nodes[0usize].kind = .Name
    nodes[0usize].s = "x"
    nodes[1usize].kind = .Number
    nodes[1usize].n = 7.0f64
    nodes[2usize].kind = .Name
    nodes[2usize].s = "x"
    var no_args: []const formula.Value = zero
    var call = formula.Call { ev: &evaluator, entry: zero, args: no_args, nodes: nodes[0usize..], scope: &outer, has_scope: true, a: &arena }
    ret is_oom(formula.let_handler(&call))
}

fn lets_oom() -> bool {
    var storage: [1]u8 = zero
    var arena = mem.arena_from(storage[0usize..0usize])
    var context: formula.Context = zero
    var evaluator = formula.evaluator(&arena, zero, &context)
    var outer = formula.Scope { name: "x", value: formula.number(5.0f64), parent: zero, has_parent: false }
    var nodes: [3]formula.Node = zero
    nodes[0usize].kind = .Name
    nodes[0usize].s = "x"
    nodes[1usize].kind = .Number
    nodes[1usize].n = 7.0f64
    nodes[2usize].kind = .Name
    nodes[2usize].s = "x"
    var no_args: []const formula.Value = zero
    var call = formula.Call { ev: &evaluator, entry: zero, args: no_args, nodes: nodes[0usize..], scope: &outer, has_scope: true, a: &arena }
    ret is_oom(formula.lets_handler(&call))
}

fn let_normal() -> bool {
    var storage: [256]u8 = zero
    var arena = mem.arena_from(storage[0usize..])
    var context: formula.Context = zero
    var evaluator = formula.evaluator(&arena, zero, &context)
    var nodes: [3]formula.Node = zero
    nodes[0usize].kind = .Name
    nodes[0usize].s = "x"
    nodes[1usize].kind = .Number
    nodes[1usize].n = 7.0f64
    nodes[2usize].kind = .Name
    nodes[2usize].s = "x"
    var no_args: []const formula.Value = zero
    var call = formula.Call { ev: &evaluator, entry: zero, args: no_args, nodes: nodes[0usize..], scope: zero, has_scope: false, a: &arena }
    let result = formula.let_handler(&call)
    ret result.kind == .Number && result.n == 7.0f64
}

fn lets_normal() -> bool {
    var storage: [256]u8 = zero
    var arena = mem.arena_from(storage[0usize..])
    var context: formula.Context = zero
    var evaluator = formula.evaluator(&arena, zero, &context)
    var nodes: [3]formula.Node = zero
    nodes[0usize].kind = .Name
    nodes[0usize].s = "x"
    nodes[1usize].kind = .Number
    nodes[1usize].n = 7.0f64
    nodes[2usize].kind = .Name
    nodes[2usize].s = "x"
    var no_args: []const formula.Value = zero
    var call = formula.Call { ev: &evaluator, entry: zero, args: no_args, nodes: nodes[0usize..], scope: zero, has_scope: false, a: &arena }
    let result = formula.lets_handler(&call)
    ret result.kind == .Number && result.n == 7.0f64
}

fn main() {
    if !let_oom() || !lets_oom() || !let_normal() || !lets_normal() { os.exit(1i32) }
    os.exit(0i32)
}
