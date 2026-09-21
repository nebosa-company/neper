// Reduced ordered binary decision diagrams over a caller node pool: nodes
// 0 and 1 are the constants, every other node is `(variable, low, high)`
// with the variable order the node index order, and a unique table (a
// linear scan, so this suits small functions) keeps the diagram canonical
// so two equal functions are one node. `apply` combines diagrams by a
// boolean operation with a memo over pairs; `count` answers the number of
// satisfying assignments; `evaluate` reads the function.

error TooSmall
error Invalid

type Bdd = struct { variable: []u32, low: []u32, high: []u32, used: usize, variables: usize }
type Op = enum u8 { And, Or, Xor }

// A diagram over `variables` variables; the pools must hold at least two entries.
fn bdd(variable: []u32, low: []u32, high: []u32, variables: usize) -> (Bdd, err) {
    if variable.len < 2usize || low.len < 2usize || high.len < 2usize { ret (zero, TooSmall) }
    variable[0usize] = u32(variables)
    variable[1usize] = u32(variables)
    low[0usize] = 0u32
    high[0usize] = 0u32
    low[1usize] = 1u32
    high[1usize] = 1u32
    ret (Bdd { variable: variable, low: low, high: high, used: 2usize, variables: variables }, ok)
}

// The node for `(v, lo, hi)`, reduced and shared.
fn make(b: *Bdd, v: u32, lo: u32, hi: u32) -> (u32, err) {
    if lo == hi { ret (lo, ok) }
    var i = 2usize
    while i < b.used {
        if b.variable[i] == v && b.low[i] == lo && b.high[i] == hi { ret (u32(i), ok) }
        i += 1usize
    }
    if b.used >= b.variable.len || b.used >= b.low.len || b.used >= b.high.len { ret (0u32, TooSmall) }
    let id = b.used
    b.used += 1usize
    b.variable[id] = v
    b.low[id] = lo
    b.high[id] = hi
    ret (u32(id), ok)
}

// The diagram of variable `v` alone.
fn var_node(b: *Bdd, v: usize) -> (u32, err) {
    if v >= b.variables { ret (0u32, Invalid) }
    let (node, make_error) = make(b, u32(v), 0u32, 1u32)
    ret (node, make_error)
}

fn constant(value: bool) -> u32 {
    if value { ret 1u32 }
    ret 0u32
}

fn op_apply(op: Op, a: bool, c: bool) -> bool {
    if op == .And { ret a && c }
    if op == .Or { ret a || c }
    ret a != c
}

// `f op g`; `memo` (`memo_keys` pairs and `memo_values`) caches results,
// `memo_len` slots of each. Answers the root.
fn apply(b: *Bdd, op: Op, f: u32, g: u32, memo_keys: []u64, memo_values: []u32, memo_count: *usize) -> (u32, err) {
    if f < 2u32 && g < 2u32 { ret (constant(op_apply(op, f == 1u32, g == 1u32)), ok) }
    // Constants short-circuit for and/or.
    if op == .And && (f == 0u32 || g == 0u32) { ret (0u32, ok) }
    if op == .Or && (f == 1u32 || g == 1u32) { ret (1u32, ok) }
    let key = (u64(f) << 32u32) | u64(g)
    var i = 0usize
    while i < *memo_count {
        if memo_keys[i] == key { ret (memo_values[i], ok) }
        i += 1usize
    }
    let vf = b.variable[usize(f)]
    let vg = b.variable[usize(g)]
    var v = vf
    if vg < v { v = vg }
    var f_low = f
    var f_high = f
    var g_low = g
    var g_high = g
    if vf == v {
        f_low = b.low[usize(f)]
        f_high = b.high[usize(f)]
    }
    if vg == v {
        g_low = b.low[usize(g)]
        g_high = b.high[usize(g)]
    }
    let (lo, lo_error) = apply(b, op, f_low, g_low, memo_keys, memo_values, memo_count)
    if lo_error != ok { ret (0u32, lo_error) }
    let (hi, hi_error) = apply(b, op, f_high, g_high, memo_keys, memo_values, memo_count)
    if hi_error != ok { ret (0u32, hi_error) }
    let (node, make_error) = make(b, v, lo, hi)
    if make_error != ok { ret (0u32, make_error) }
    if *memo_count < memo_keys.len && *memo_count < memo_values.len {
        memo_keys[*memo_count] = key
        memo_values[*memo_count] = node
        *memo_count += 1usize
    }
    ret (node, ok)
}

// `not f` by exchanging the constants (`f xor 1`).
fn negate(b: *Bdd, f: u32, memo_keys: []u64, memo_values: []u32, memo_count: *usize) -> (u32, err) {
    let (node, apply_error) = apply(b, .Xor, f, 1u32, memo_keys, memo_values, memo_count)
    ret (node, apply_error)
}

fn evaluate(b: *const Bdd, f: u32, assignment: []const bool) -> bool {
    var n = f
    while n >= 2u32 {
        if assignment[usize(b.variable[usize(n)])] { n = b.high[usize(n)] } else { n = b.low[usize(n)] }
    }
    ret n == 1u32
}

// The number of satisfying assignments over all `variables` variables.
fn count(b: *const Bdd, f: u32) -> u64 {
    ret count_from(b, f, 0u32)
}

fn count_from(b: *const Bdd, f: u32, from: u32) -> u64 {
    // Variables skipped between `from` and this node's are free.
    if f == 0u32 { ret 0u64 }
    let top = u32(b.variables)
    if f == 1u32 { ret 1u64 << (top - from) }
    let v = b.variable[usize(f)]
    let skipped = v - from
    let below = count_from(b, b.low[usize(f)], v + 1u32) + count_from(b, b.high[usize(f)], v + 1u32)
    ret below << skipped
}
