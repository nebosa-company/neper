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
// More than 63 variables has no representable count (2^64 does not fit u64).
fn bdd(variable: []u32, low: []u32, high: []u32, variables: usize) -> (Bdd, err) {
    if variables > 63usize { ret (zero, Invalid) }
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

// The number of satisfying assignments over all `variables` variables. `memo`
// (`memo.len >= b.used`) holds each node's count over its own variable and up, so a
// shared diagram is summed once per node instead of once per assignment prefix.
fn count(b: *const Bdd, f: u32, memo: []u64) -> (u64, err) {
    let top = u32(b.variables)
    if f == 0u32 { ret (0u64, ok) }
    if f == 1u32 { ret (1u64 << top, ok) }
    if memo.len < b.used { ret (0u64, TooSmall) }
    // Children are made before their parent, so increasing node order is bottom-up.
    var n = 2usize
    while n < b.used {
        let v = u32(b.variable[n])
        if v >= top { ret (0u64, Invalid) }
        var below = 0u64
        let lo = b.low[n]
        if lo == 1u32 {
            below += 1u64 << (top - v - 1u32)
        } else if lo >= 2u32 {
            let lv = u32(b.variable[usize(lo)])
            if lv <= v || lv >= top { ret (0u64, Invalid) }
            below += memo[usize(lo)] << (lv - v - 1u32)
        }
        let hi = b.high[n]
        if hi == 1u32 {
            below += 1u64 << (top - v - 1u32)
        } else if hi >= 2u32 {
            let hv = u32(b.variable[usize(hi)])
            if hv <= v || hv >= top { ret (0u64, Invalid) }
            below += memo[usize(hi)] << (hv - v - 1u32)
        }
        memo[n] = below
        n += 1usize
    }
    let v = u32(b.variable[usize(f)])
    if v >= top { ret (0u64, Invalid) }
    // `memo` covers this variable and up; every variable below it is free.
    ret (memo[usize(f)] << v, ok)
}

// An expression tree in caller arrays: node `i` is `kind[i]` with operands
// `left[i]`, `right[i]` (`Not` uses `left`; `Var` reads the variable from
// `left`; `Const` reads 0 or 1 from `left`).
type Expr = enum u8 { And, Or, Xor, Not, Var, Const }

// The diagram of the expression rooted at `root`, built bottom-up by `apply`
// over the memo (cleared before every combination).
fn build(b: *Bdd, kind: []const Expr, left: []const u32, right: []const u32, root: u32, memo_keys: []u64, memo_values: []u32) -> (u32, err) {
    let i = usize(root)
    if i >= kind.len || i >= left.len || i >= right.len { ret (0u32, Invalid) }
    let k = kind[i]
    if k == .Const { ret (constant(left[i] != 0u32), ok) }
    if k == .Var {
        let (node, var_error) = var_node(b, usize(left[i]))
        ret (node, var_error)
    }
    // Operands must be earlier nodes: that is what makes the tree acyclic and bounds
    // the recursion to the node count (#277).
    if usize(left[i]) >= i { ret (0u32, Invalid) }
    if k != .Not && usize(right[i]) >= i { ret (0u32, Invalid) }
    let (f, left_error) = build(b, kind, left, right, left[i], memo_keys, memo_values)
    if left_error != ok { ret (0u32, left_error) }
    var memo_count = 0usize
    if k == .Not {
        let (negated, not_error) = negate(b, f, memo_keys, memo_values, &memo_count)
        ret (negated, not_error)
    }
    let (g, right_error) = build(b, kind, left, right, right[i], memo_keys, memo_values)
    if right_error != ok { ret (0u32, right_error) }
    var op: Op = .And
    if k == .Or { op = .Or }
    if k == .Xor { op = .Xor }
    let (node, apply_error) = apply(b, op, f, g, memo_keys, memo_values, &memo_count)
    ret (node, apply_error)
}
