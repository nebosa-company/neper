// Formula collection helpers must surface arena exhaustion as an error rather
// than treating it as an empty list or writing through a zero-length slice.
use e.algo.formula as formula
use e.algo.formula.misc as misc
use e.mem
use e.os
use e.str

fn is_oom(v: formula.Value) -> bool {
    ret v.kind == .Error && v.code == formula.E_ERROR && str.eq(v.s, "Out of memory")
}

fn main() {
    var storage: [1]u8 = zero
    var arena = mem.arena_from(storage[0usize..0usize])
    var values: [1]formula.Value = zero
    values[0usize] = formula.number(7.0f64)
    var fields: [1]formula.Field = zero
    fields[0usize] = formula.Field { name: "items", value: formula.number(7.0f64) }
    var context: formula.Context = zero
    context.fields = fields[0usize..]
    var evaluator = formula.evaluator(&arena, zero, &context)
    var nodes: [2]formula.Node = zero
    nodes[0usize].kind = .Field
    nodes[0usize].s = "items"
    nodes[1usize].kind = .Number
    nodes[1usize].n = 1.0f64
    var no_args: []const formula.Value = zero
    var call = formula.Call { ev: &evaluator, entry: zero, args: no_args, nodes: nodes[0usize..], scope: zero, has_scope: false, a: &arena }

    // A scalar must allocate its one-element view, and a zero-capacity arena
    // must report the failure instead of changing MAP's input into [] .
    if !is_oom(misc.h_map(&call)) { os.exit(1) }

    // An existing array needs no items_of allocation; this isolates the output
    // allocation that MAP, FILTER and SORT write through.
    fields[0usize].value = formula.array(values[0usize..])
    if !is_oom(misc.h_map(&call)) { os.exit(2) }
    os.exit(0)
}
