// Propositional satisfiability over CNF in caller storage. A formula is a
// flat list of literals (`v + 1` for variable `v`, `-(v + 1)` for its
// negation, as `i32`) with clause boundaries in `starts` (clause `c` is
// `literals[starts[c]..starts[c + 1]]`). `solve` is DPLL with unit
// propagation and chronological backtracking that flips the deepest
// unflipped decision, learning a clause per conflict (the negation of the
// decisions on the trail) so it is a small CDCL; `walksat` is the local
// search; `preprocess` removes satisfied clauses and applies units;
// `Cnf` builds formulas: `tseitin_*` gates, `at_most` (sequential
// counter) and `pseudo_boolean` (a totaliser-free BDD-style expansion for
// small coefficients); `equivalent` decides whether two circuits agree.

use e.algo.rand

error TooSmall
error Invalid
error Unsatisfiable

type Cnf = struct { literals: []i32, starts: []usize, clauses: usize, variables: usize }

fn cnf(literals: []i32, starts: []usize, variables: usize) -> (Cnf, err) {
    if starts.len < 1usize { ret (zero, TooSmall) }
    starts[0usize] = 0usize
    ret (Cnf { literals: literals, starts: starts, clauses: 0usize, variables: variables }, ok)
}

fn fresh(f: *Cnf) -> i32 {
    f.variables += 1usize
    ret i32(f.variables)
}

// Append a clause of `lits`.
fn add_clause(f: *Cnf, lits: []const i32) -> err {
    let at = f.starts[f.clauses]
    if f.clauses + 1usize >= f.starts.len || at + lits.len > f.literals.len { ret TooSmall }
    var i = 0usize
    while i < lits.len {
        if lits[i] == 0i32 || usize(abs(lits[i])) > f.variables { ret Invalid }
        f.literals[at + i] = lits[i]
        i += 1usize
    }
    f.clauses += 1usize
    f.starts[f.clauses] = at + lits.len
    ret ok
}

fn abs(x: i32) -> i32 {
    if x < 0i32 { ret 0i32 - x }
    ret x
}

fn clause1(f: *Cnf, a: i32) -> err {
    var c: [1]i32 = zero
    c[0usize] = a
    ret add_clause(f, c[..])
}
fn clause2(f: *Cnf, a: i32, b: i32) -> err {
    var c: [2]i32 = zero
    c[0usize] = a
    c[1usize] = b
    ret add_clause(f, c[..])
}
fn clause3(f: *Cnf, a: i32, b: i32, c3: i32) -> err {
    var c: [3]i32 = zero
    c[0usize] = a
    c[1usize] = b
    c[2usize] = c3
    ret add_clause(f, c[..])
}

// Tseitin gates: each answers a fresh literal equal to the gate's output.
fn tseitin_and(f: *Cnf, a: i32, b: i32) -> (i32, err) {
    let o = fresh(f)
    if clause2(f, 0i32 - o, a) != ok || clause2(f, 0i32 - o, b) != ok || clause3(f, o, 0i32 - a, 0i32 - b) != ok { ret (0i32, TooSmall) }
    ret (o, ok)
}
fn tseitin_or(f: *Cnf, a: i32, b: i32) -> (i32, err) {
    let o = fresh(f)
    if clause2(f, o, 0i32 - a) != ok || clause2(f, o, 0i32 - b) != ok || clause3(f, 0i32 - o, a, b) != ok { ret (0i32, TooSmall) }
    ret (o, ok)
}
fn tseitin_xor(f: *Cnf, a: i32, b: i32) -> (i32, err) {
    let o = fresh(f)
    if clause3(f, 0i32 - o, a, b) != ok || clause3(f, 0i32 - o, 0i32 - a, 0i32 - b) != ok || clause3(f, o, 0i32 - a, b) != ok || clause3(f, o, a, 0i32 - b) != ok { ret (0i32, TooSmall) }
    ret (o, ok)
}
// Negation needs no gate: the negated literal is the output.
fn tseitin_not(a: i32) -> i32 { ret 0i32 - a }

// At most `k` of `lits` true, by Sinz's sequential counter (`(n - 1) k` fresh variables).
fn at_most(f: *Cnf, lits: []const i32, k: usize) -> err {
    let n = lits.len
    if k >= n { ret ok }
    if k == 0usize {
        var i = 0usize
        while i < n {
            if clause1(f, 0i32 - lits[i]) != ok { ret TooSmall }
            i += 1usize
        }
        ret ok
    }
    // s[i][j]: among the first i + 1 literals at least j + 1 are true.
    let base = f.variables
    f.variables += (n - 1usize) * k
    var i = 0usize
    while i + 1usize < n {
        let s0 = i32(base + i * k + 1usize)
        if clause2(f, 0i32 - lits[i], s0) != ok { ret TooSmall }
        var j = 1usize
        while j < k {
            let sij = i32(base + i * k + j + 1usize)
            if i == 0usize {
                if clause1(f, 0i32 - sij) != ok { ret TooSmall }
            } else {
                let previous = i32(base + (i - 1usize) * k + j)
                let previous_same = i32(base + (i - 1usize) * k + j + 1usize)
                if clause3(f, 0i32 - lits[i], 0i32 - previous, sij) != ok || clause2(f, 0i32 - previous_same, sij) != ok { ret TooSmall }
            }
            j += 1usize
        }
        if i > 0usize {
            let previous_first = i32(base + (i - 1usize) * k + 1usize)
            if clause2(f, 0i32 - previous_first, s0) != ok { ret TooSmall }
            let previous_last = i32(base + (i - 1usize) * k + k)
            if clause2(f, 0i32 - lits[i], 0i32 - previous_last) != ok { ret TooSmall }
        }
        i += 1usize
    }
    let last = i32(base + (n - 2usize) * k + k)
    if clause2(f, 0i32 - lits[n - 1usize], 0i32 - last) != ok { ret TooSmall }
    ret ok
}

// `Σ coefficient_i · lit_i <= bound` for non-negative integer coefficients,
// compiled by a decision diagram over the partial sums (memoised on
// (index, sum) in `memo`, `memo.len >= (n + 1) * (bound + 1)`): each node
// is a fresh literal true when the suffix can still stay within budget.
fn pseudo_boolean(f: *Cnf, lits: []const i32, coefficients: []const u32, bound: u32, memo: []i32) -> err {
    let n = lits.len
    if coefficients.len < n || memo.len < (n + 1usize) * (usize(bound) + 1usize) { ret TooSmall }
    var i = 0usize
    while i < memo.len {
        memo[i] = 0i32
        i += 1usize
    }
    let (root, e) = pb_node(f, lits, coefficients, bound, memo, 0usize, 0u32)
    if e != ok { ret e }
    if root == 0i32 { ret Unsatisfiable }
    if root == 1i32 { ret ok }
    ret clause1(f, root)
}

// The literal for "assignments of lits[index..] keep sum + rest <= bound":
// 1 for true, 0 for false (a constant), else a fresh variable.
fn pb_node(f: *Cnf, lits: []const i32, coefficients: []const u32, bound: u32, memo: []i32, index: usize, sum: u32) -> (i32, err) {
    if sum > bound { ret (0i32, ok) }
    if index == lits.len { ret (1i32, ok) }
    let width = usize(bound) + 1usize
    let key = index * width + usize(sum)
    if memo[key] != 0i32 {
        if memo[key] == 0i32 - 1i32 { ret (0i32, ok) }
        if memo[key] == 0i32 - 2i32 { ret (1i32, ok) }
        ret (memo[key], ok)
    }
    let (high, high_error) = pb_node(f, lits, coefficients, bound, memo, index + 1usize, sum + coefficients[index])
    if high_error != ok { ret (0i32, high_error) }
    let (low, low_error) = pb_node(f, lits, coefficients, bound, memo, index + 1usize, sum)
    if low_error != ok { ret (0i32, low_error) }
    var result = 0i32
    if high == low {
        result = high
    } else {
        // node = (lit -> high) and (not lit -> low), with constants folded.
        let node = fresh(f)
        let x = lits[index]
        if high == 0i32 {
            if clause2(f, 0i32 - node, 0i32 - x) != ok { ret (0i32, TooSmall) }
        } else if high != 1i32 {
            if clause3(f, 0i32 - node, 0i32 - x, high) != ok { ret (0i32, TooSmall) }
        }
        if low == 0i32 {
            if clause2(f, 0i32 - node, x) != ok { ret (0i32, TooSmall) }
        } else if low != 1i32 {
            if clause3(f, 0i32 - node, x, low) != ok { ret (0i32, TooSmall) }
        }
        result = node
    }
    if result == 0i32 { memo[key] = 0i32 - 1i32 } else if result == 1i32 { memo[key] = 0i32 - 2i32 } else { memo[key] = result }
    ret (result, ok)
}

fn value_of(assignment: []const i8, lit: i32) -> i8 {
    let v = assignment[usize(abs(lit)) - 1usize]
    if v == 0i8 { ret 0i8 }
    if lit > 0i32 { ret v }
    ret 0i8 - v
}

// DPLL with unit propagation, chronological backtracking with flipping,
// and a learned clause per conflict (the negation of the decisions on the
// trail, sound and kept while room lasts) -- a small CDCL.
// `assignment` (one `i8` per variable: 1, -1 or 0) receives the model;
// `trail.len >= variables`, `level.len >= variables`, `flipped.len >= variables + 1`,
// `learned` and `learned_starts` hold the learned clauses (`learned_starts.len >= 1`).
// Answers `Unsatisfiable` when no model exists, `Invalid` past `max_conflicts`.
fn solve(f: *const Cnf, assignment: []i8, trail: []u32, level: []u32, flipped: []u8, learned: []i32, learned_starts: []usize, max_conflicts: usize) -> err {
    let n = f.variables
    if assignment.len < n || trail.len < n || level.len < n || flipped.len < n + 1usize || learned_starts.len < 1usize { ret TooSmall }
    var i = 0usize
    while i < n {
        assignment[i] = 0i8
        i += 1usize
    }
    learned_starts[0usize] = 0usize
    var learned_count = 0usize
    var trail_len = 0usize
    var decisions = 0usize
    var conflicts = 0usize
    while true {
        if propagate(f, assignment, trail, level, &trail_len, decisions, learned, learned_starts, learned_count) {
            conflicts += 1usize
            if conflicts > max_conflicts { ret Invalid }
            // Learn the negation of the decisions.
            let start = learned_starts[learned_count]
            if learned_count + 1usize < learned_starts.len && start + decisions <= learned.len {
                var lits = 0usize
                i = 0usize
                while i < trail_len {
                    if level[i] > 0u32 && (i == 0usize || level[i] != level[i - 1usize]) {
                        var lit = i32(trail[i])
                        if assignment[usize(trail[i]) - 1usize] > 0i8 { lit = 0i32 - lit }
                        learned[start + lits] = lit
                        lits += 1usize
                    }
                    i += 1usize
                }
                learned_starts[learned_count + 1usize] = start + lits
                learned_count += 1usize
            }
            // Back to the deepest level whose decision has not been flipped.
            while decisions > 0usize && flipped[decisions] != 0u8 {
                while trail_len > 0usize && level[trail_len - 1usize] == u32(decisions) {
                    trail_len -= 1usize
                    assignment[usize(trail[trail_len]) - 1usize] = 0i8
                }
                decisions -= 1usize
            }
            if decisions == 0usize { ret Unsatisfiable }
            // The level's decision is its first trail entry: undo the level, flip it.
            var first = trail_len
            while first > 0usize && level[first - 1usize] == u32(decisions) { first -= 1usize }
            let d = trail[first]
            let was = assignment[usize(d) - 1usize]
            while trail_len > first {
                trail_len -= 1usize
                assignment[usize(trail[trail_len]) - 1usize] = 0i8
            }
            flipped[decisions] = 1u8
            assignment[usize(d) - 1usize] = 0i8 - was
            trail[trail_len] = d
            level[trail_len] = u32(decisions)
            trail_len += 1usize
        } else {
            var v = 0usize
            while v < n && assignment[v] != 0i8 { v += 1usize }
            if v == n { ret ok }
            decisions += 1usize
            flipped[decisions] = 0u8
            assignment[v] = 1i8
            trail[trail_len] = u32(v + 1usize)
            level[trail_len] = u32(decisions)
            trail_len += 1usize
        }
    }
    ret ok
}

// Unit propagation to a fixpoint; answers whether a clause became empty.
fn propagate(f: *const Cnf, assignment: []i8, trail: []u32, level: []u32, trail_len: *usize, decisions: usize, learned: []const i32, learned_starts: []const usize, learned_count: usize) -> bool {
    var progress = true
    while progress {
        progress = false
        var c = 0usize
        let total = f.clauses + learned_count
        while c < total {
            var from = 0usize
            var to = 0usize
            if c < f.clauses {
                from = f.starts[c]
                to = f.starts[c + 1usize]
            } else {
                from = learned_starts[c - f.clauses]
                to = learned_starts[c - f.clauses + 1usize]
            }
            var satisfied_clause = false
            var unassigned = 0usize
            var last = 0i32
            var k = from
            while k < to && !satisfied_clause {
                var lit = 0i32
                if c < f.clauses { lit = f.literals[k] } else { lit = learned[k] }
                let v = value_of(assignment, lit)
                if v > 0i8 {
                    satisfied_clause = true
                } else if v == 0i8 {
                    unassigned += 1usize
                    last = lit
                }
                k += 1usize
            }
            if !satisfied_clause {
                if unassigned == 0usize { ret true }
                if unassigned == 1usize {
                    var value = 1i8
                    if last < 0i32 { value = 0i8 - 1i8 }
                    assignment[usize(abs(last)) - 1usize] = value
                    trail[*trail_len] = u32(abs(last))
                    level[*trail_len] = u32(decisions)
                    *trail_len += 1usize
                    progress = true
                }
            }
            c += 1usize
        }
    }
    ret false
}

// Is the formula satisfied by `assignment`?
fn satisfied(f: *const Cnf, assignment: []const i8) -> bool {
    var c = 0usize
    while c < f.clauses {
        var any = false
        var k = f.starts[c]
        while k < f.starts[c + 1usize] && !any {
            if value_of(assignment, f.literals[k]) > 0i8 { any = true }
            k += 1usize
        }
        if !any { ret false }
        c += 1usize
    }
    ret true
}

// WalkSAT with noise `p` (in [0, 1]) for `flips` flips from a random
// assignment through the caller's PCG; answers whether a model was found.
fn walksat(f: *const Cnf, assignment: []i8, p: f64, flips: usize, r: *rand.Pcg64) -> (bool, err) {
    if assignment.len < f.variables { ret (false, TooSmall) }
    var i = 0usize
    while i < f.variables {
        assignment[i] = 1i8
        if rand.pcg64_bounded(r, 2u64) == 0u64 { assignment[i] = 0i8 - 1i8 }
        i += 1usize
    }
    var flip = 0usize
    while flip < flips {
        // An unsatisfied clause, chosen uniformly among them by reservoir sampling.
        var chosen = f.clauses
        var seen = 0usize
        var c = 0usize
        while c < f.clauses {
            var any = false
            var k = f.starts[c]
            while k < f.starts[c + 1usize] && !any {
                if value_of(assignment, f.literals[k]) > 0i8 { any = true }
                k += 1usize
            }
            if !any {
                seen += 1usize
                if rand.pcg64_bounded(r, u64(seen)) == 0u64 { chosen = c }
            }
            c += 1usize
        }
        if chosen == f.clauses { ret (true, ok) }
        let from = f.starts[chosen]
        let to = f.starts[chosen + 1usize]
        var pick = 0usize
        if rand.pcg64_f64(r) < p {
            pick = from + usize(rand.pcg64_bounded(r, u64(to - from)))
        } else {
            // The literal whose flip breaks the fewest satisfied clauses.
            var best_break = f.clauses + 1usize
            var k = from
            while k < to {
                let v = usize(abs(f.literals[k])) - 1usize
                assignment[v] = 0i8 - assignment[v]
                var broken = 0usize
                var c2 = 0usize
                while c2 < f.clauses {
                    var any = false
                    var k2 = f.starts[c2]
                    while k2 < f.starts[c2 + 1usize] && !any {
                        if value_of(assignment, f.literals[k2]) > 0i8 { any = true }
                        k2 += 1usize
                    }
                    if !any { broken += 1usize }
                    c2 += 1usize
                }
                assignment[v] = 0i8 - assignment[v]
                if broken < best_break {
                    best_break = broken
                    pick = k
                }
                k += 1usize
            }
        }
        let v = usize(abs(f.literals[pick])) - 1usize
        assignment[v] = 0i8 - assignment[v]
        flip += 1usize
    }
    ret (satisfied(f, assignment), ok)
}

// Simplify in place: unit clauses are applied (their variables fixed in
// `fixed`, `1`/`-1`/`0`), satisfied clauses dropped and false literals
// removed, until nothing changes; answers `Unsatisfiable` on an empty clause.
fn preprocess(f: *Cnf, fixed: []i8) -> err {
    if fixed.len < f.variables { ret TooSmall }
    var i = 0usize
    while i < f.variables {
        fixed[i] = 0i8
        i += 1usize
    }
    var changed = true
    while changed {
        changed = false
        // Collect units.
        var c = 0usize
        while c < f.clauses {
            if f.starts[c + 1usize] - f.starts[c] == 1usize {
                let lit = f.literals[f.starts[c]]
                let v = usize(abs(lit)) - 1usize
                var want = 1i8
                if lit < 0i32 { want = 0i8 - 1i8 }
                if fixed[v] == 0i8 {
                    fixed[v] = want
                    changed = true
                } else if fixed[v] != want {
                    ret Unsatisfiable
                }
            }
            c += 1usize
        }
        // Rewrite clauses.
        var write = 0usize
        var out = 0usize
        c = 0usize
        while c < f.clauses {
            let from = f.starts[c]
            let to = f.starts[c + 1usize]
            var satisfied_clause = false
            var kept = 0usize
            var k = from
            while k < to {
                let lit = f.literals[k]
                let v = value_of(fixed, lit)
                if v > 0i8 {
                    satisfied_clause = true
                } else if v == 0i8 {
                    f.literals[write + kept] = lit
                    kept += 1usize
                }
                k += 1usize
            }
            if !satisfied_clause {
                if kept == 0usize { ret Unsatisfiable }
                if kept != to - from { changed = true }
                f.starts[out] = write
                write += kept
                out += 1usize
            } else {
                changed = true
            }
            c += 1usize
        }
        f.starts[out] = write
        f.clauses = out
    }
    ret ok
}

// Do two circuits over the same inputs agree everywhere? `left` and `right`
// are output literals of gates already in `f`; a miter clause set is added
// and the formula solved: unsatisfiable means equivalent. The solver's
// storage as for `solve`.
fn equivalent(f: *Cnf, left: i32, right: i32, assignment: []i8, trail: []u32, level: []u32, flipped: []u8, learned: []i32, learned_starts: []usize) -> (bool, err) {
    let (differ, x_error) = tseitin_xor(f, left, right)
    if x_error != ok { ret (false, x_error) }
    if clause1(f, differ) != ok { ret (false, TooSmall) }
    let verdict = solve(f, assignment, trail, level, flipped, learned, learned_starts, 100000usize)
    if verdict == Unsatisfiable { ret (true, ok) }
    if verdict == ok { ret (false, ok) }
    ret (false, verdict)
}
