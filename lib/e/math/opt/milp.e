// Mixed-integer linear programming in caller storage: minimise `c·x`
// subject to `row_lower <= A x <= row_upper` (a row with equal bounds is an
// equality, an infinite bound is absent), `lower <= x <= upper` and
// integrality of the flagged variables, by branch and cut.
//
// The linear relaxations are solved by a dense bounded-variable simplex over
// the tableau `B⁻¹ [A | -I]`, one logical column per row: a node starts
// from the last basis, re-inverted, with every nonbasic variable placed at
// the bound its reduced cost asks for; when that basis is dual feasible (a
// changed branching bound, an added cut) the dual simplex repairs it,
// otherwise the primal simplex (sum-of-infeasibilities phase one, then
// Dantzig pricing that falls back to Bland's rule on degeneracy) solves it.
// At the root, `cut_rounds` rounds of Gomory mixed-integer cuts are read off
// the optimal tableau and appended as rows; then branch and bound picks the
// open node with the best bound, branches on the most fractional variable,
// and prunes by bound (and by the relative `gap`). An integral relaxation is
// polished (integers fixed at their rounded values, the continuous part
// re-solved) before it becomes the incumbent. `Result.bound` is the least
// bound over the incumbent and the open nodes; `nodes` counts relaxations
// solved, the root included.
//
// A bound whose magnitude is at least 1e30 (or `infinity()`) is infinite.
// Scratch is `scratch_len(n, m, max_cuts, nodes)` floats and
// `slot_len(n, m, max_cuts)` indices, where `nodes` open nodes fit the pool;
// a full pool stops the search as `NodeLimit`.
//
// ponytail: no presolve, dense tableau instead of a sparse LU, no bound-flipping
// ratio test, only GMI cuts at the root (no MIR, knapsack cover or clique
// cuts, no cut pool management), no primal heuristics, one thread; add them
// when problems grow past a few hundred rows.

use e.math

type Problem = struct { n: usize, m: usize, c: []const f64, a: []const f64, row_lower: []const f64, row_upper: []const f64, lower: []const f64, upper: []const f64, integer: []const bool }
type Options = struct { node_limit: u32, cut_rounds: u32, max_cuts: usize, gap: f64, integrality: f64 }
type Status = enum u8 { Optimal, Infeasible, Unbounded, NodeLimit }
type Result = struct { status: Status, objective: f64, bound: f64, nodes: u32, cuts: u32 }
error TooSmall
error Invalid
error Stalled

type Lp = struct { n: usize, m: usize, rows: usize, width: usize, a: []const f64, cost: []const f64, cut: []f64, t: []f64, lo: []f64, hi: []f64, val: []f64, d: []f64, w: []f64, basis: []usize, state: []usize, integral: []usize, pivots: usize }

const BASIC: usize = 0usize
const AT_LOWER: usize = 1usize
const AT_UPPER: usize = 2usize
const FREE: usize = 3usize
const LP_OPTIMAL: usize = 0usize
const LP_INFEASIBLE: usize = 1usize
const LP_UNBOUNDED: usize = 2usize
const LP_STALLED: usize = 3usize

fn feasibility() -> f64 { ret 0.000000001f64 }
fn optimality() -> f64 { ret 0.000000001f64 }
fn pivot_tolerance() -> f64 { ret 0.000000001f64 }

// The infinite bound.
fn infinity() -> f64 { ret math.inf64() }

fn finite(v: f64) -> bool { ret v < 1.0e30f64 && v > 0.0f64 - 1.0e30f64 }

// Options that solve to optimality: 100000 nodes, three rounds of up to 64
// cuts, integrality tolerance 1e-6.
fn defaults() -> Options { ret Options { node_limit: 100000u32, cut_rounds: 3u32, max_cuts: 64usize, gap: 0.0f64, integrality: 0.000001f64 } }

fn scratch_len(n: usize, m: usize, max_cuts: usize, nodes: usize) -> usize {
    let cap = m + max_cuts
    let wd = n + cap
    ret cap * wd + 4usize * wd + cap + max_cuts * n + 4usize * n + nodes * (2usize * n + 1usize)
}

fn slot_len(n: usize, m: usize, max_cuts: usize) -> usize {
    let cap = m + max_cuts
    ret cap + 2usize * (n + cap)
}

fn row_coefficient(lp: *const Lp, k: usize, j: usize) -> f64 {
    if k < lp.m { ret lp.a[k * lp.n + j] }
    ret lp.cut[(k - lp.m) * lp.n + j]
}

fn column_cost(lp: *const Lp, j: usize) -> f64 {
    if j < lp.n { ret lp.cost[j] }
    ret 0.0f64
}

fn lp_objective(lp: *const Lp) -> f64 {
    var sum = 0.0f64
    var j = 0usize
    while j < lp.n {
        sum += lp.cost[j] * lp.val[j]
        j += 1usize
    }
    ret sum
}

fn lp_pivot(lp: *Lp, r: usize, q: usize) {
    let wd = lp.width
    let active = lp.n + lp.rows
    let s = lp.t[r * wd + q]
    var j = 0usize
    while j < active {
        lp.t[r * wd + j] = lp.t[r * wd + j] / s
        j += 1usize
    }
    lp.t[r * wd + q] = 1.0f64
    var i = 0usize
    while i < lp.rows {
        if i != r {
            let f = lp.t[i * wd + q]
            if f != 0.0f64 {
                j = 0usize
                while j < active {
                    lp.t[i * wd + j] -= f * lp.t[r * wd + j]
                    j += 1usize
                }
                lp.t[i * wd + q] = 0.0f64
            }
        }
        i += 1usize
    }
    lp.basis[r] = q
    lp.pivots += 1usize
}

// Lower if that bound is finite and wanted (or the only one), else upper, else free.
fn place_nonbasic(lp: *Lp, j: usize, prefer_upper: bool) {
    let lo_ok = finite(lp.lo[j])
    let hi_ok = finite(lp.hi[j])
    if lo_ok && (!hi_ok || !prefer_upper) {
        lp.state[j] = AT_LOWER
    } else if hi_ok {
        lp.state[j] = AT_UPPER
    } else {
        lp.state[j] = FREE
    }
}

// Rebuilds the tableau from `[-A | I]` and pivots the current basic columns
// back in with partial pivoting; a singular basis falls back to the logicals.
fn lp_refactor(lp: *Lp) -> bool {
    let wd = lp.width
    let active = lp.n + lp.rows
    var k = 0usize
    while k < lp.rows {
        var j = 0usize
        while j < active {
            lp.t[k * wd + j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < lp.n {
            lp.t[k * wd + j] = 0.0f64 - row_coefficient(lp, k, j)
            j += 1usize
        }
        lp.t[k * wd + lp.n + k] = 1.0f64
        lp.basis[k] = wd
        k += 1usize
    }
    var singular = false
    var j = 0usize
    while j < active && !singular {
        if lp.state[j] == BASIC {
            var r = lp.rows
            var best = pivot_tolerance()
            k = 0usize
            while k < lp.rows {
                let v = math.abs[f64](lp.t[k * wd + j])
                if lp.basis[k] == wd && v > best {
                    best = v
                    r = k
                }
                k += 1usize
            }
            if r == lp.rows {
                singular = true
            } else {
                lp_pivot(lp, r, j)
            }
        }
        j += 1usize
    }
    lp.pivots = 0usize
    if !singular { ret true }
    // Back to the all-logical basis.
    k = 0usize
    while k < lp.rows {
        j = 0usize
        while j < active {
            lp.t[k * wd + j] = 0.0f64
            j += 1usize
        }
        j = 0usize
        while j < lp.n {
            lp.t[k * wd + j] = 0.0f64 - row_coefficient(lp, k, j)
            j += 1usize
        }
        lp.t[k * wd + lp.n + k] = 1.0f64
        lp.basis[k] = lp.n + k
        k += 1usize
    }
    j = 0usize
    while j < active {
        if j < lp.n {
            place_nonbasic(lp, j, lp.cost[j] < 0.0f64)
        } else {
            lp.state[j] = BASIC
        }
        j += 1usize
    }
    ret false
}

// Nonbasic variables at their bounds, basic ones from the tableau rows.
fn lp_values(lp: *Lp) {
    let wd = lp.width
    let active = lp.n + lp.rows
    var j = 0usize
    while j < active {
        let s = lp.state[j]
        if s == AT_LOWER {
            lp.val[j] = lp.lo[j]
        } else if s == AT_UPPER {
            lp.val[j] = lp.hi[j]
        } else if s == FREE {
            lp.val[j] = 0.0f64
        }
        j += 1usize
    }
    var i = 0usize
    while i < lp.rows {
        var v = 0.0f64
        j = 0usize
        while j < active {
            if lp.state[j] != BASIC && lp.val[j] != 0.0f64 { v -= lp.t[i * wd + j] * lp.val[j] }
            j += 1usize
        }
        lp.val[lp.basis[i]] = v
        i += 1usize
    }
}

// Row weights for phase one (-1 below, +1 above a violated bound); when no
// basic variable is infeasible, the basic costs. Answers whether any was.
fn lp_weights(lp: *Lp) -> bool {
    var any = false
    var i = 0usize
    while i < lp.rows {
        let b = lp.basis[i]
        lp.w[i] = 0.0f64
        if lp.val[b] < lp.lo[b] - feasibility() {
            lp.w[i] = 0.0f64 - 1.0f64
            any = true
        } else if lp.val[b] > lp.hi[b] + feasibility() {
            lp.w[i] = 1.0f64
            any = true
        }
        i += 1usize
    }
    if !any {
        i = 0usize
        while i < lp.rows {
            lp.w[i] = column_cost(lp, lp.basis[i])
            i += 1usize
        }
    }
    ret any
}

// Reduced costs `d_j = cost_j - Σ w_i T_ij` of the nonbasic columns.
fn lp_duals(lp: *Lp, phase_one: bool) {
    let wd = lp.width
    let active = lp.n + lp.rows
    var j = 0usize
    while j < active {
        var s = 0.0f64
        if lp.state[j] != BASIC {
            if !phase_one { s = column_cost(lp, j) }
            var i = 0usize
            while i < lp.rows {
                s -= lp.w[i] * lp.t[i * wd + j]
                i += 1usize
            }
        }
        lp.d[j] = s
        j += 1usize
    }
}

fn lp_primal(lp: *Lp) -> usize {
    let wd = lp.width
    let active = lp.n + lp.rows
    let limit = 50usize * active + 1000usize
    var bland = false
    var degenerate = 0usize
    var iteration = 0usize
    var outcome = LP_STALLED
    var running = true
    while running && iteration < limit {
        if lp.pivots >= 100usize { let _ = lp_refactor(lp) }
        lp_values(lp)
        let phase_one = lp_weights(lp)
        lp_duals(lp, phase_one)
        var q = active
        var dir = 0.0f64
        var best = 0.0f64
        var j = 0usize
        while j < active {
            let s = lp.state[j]
            if s != BASIC && lp.lo[j] < lp.hi[j] {
                let dj = lp.d[j]
                var sign = 0.0f64
                if (s == AT_LOWER || s == FREE) && dj < 0.0f64 - optimality() { sign = 1.0f64 }
                if (s == AT_UPPER || s == FREE) && dj > optimality() { sign = 0.0f64 - 1.0f64 }
                if sign != 0.0f64 && (q == active || (!bland && math.abs[f64](dj) > best)) {
                    q = j
                    dir = sign
                    best = math.abs[f64](dj)
                }
            }
            j += 1usize
        }
        if q == active {
            if phase_one { outcome = LP_INFEASIBLE } else { outcome = LP_OPTIMAL }
            running = false
        } else {
            var flip = infinity()
            if finite(lp.lo[q]) && finite(lp.hi[q]) { flip = lp.hi[q] - lp.lo[q] }
            var r = lp.rows
            var room_r = infinity()
            var goes_r = BASIC
            var alpha_r = 0.0f64
            var i = 0usize
            while i < lp.rows {
                let alpha = lp.t[i * wd + q]
                if math.abs[f64](alpha) > pivot_tolerance() {
                    let rate = 0.0f64 - alpha * dir
                    let b = lp.basis[i]
                    let v = lp.val[b]
                    var room = 0.0f64
                    var goes = BASIC
                    if rate > 0.0f64 {
                        if v < lp.lo[b] - feasibility() {
                            room = (lp.lo[b] - v) / rate
                            goes = AT_LOWER
                        } else if v <= lp.hi[b] + feasibility() && finite(lp.hi[b]) {
                            room = (lp.hi[b] - v) / rate
                            goes = AT_UPPER
                        }
                    } else {
                        if v > lp.hi[b] + feasibility() {
                            room = (v - lp.hi[b]) / (0.0f64 - rate)
                            goes = AT_UPPER
                        } else if v >= lp.lo[b] - feasibility() && finite(lp.lo[b]) {
                            room = (v - lp.lo[b]) / (0.0f64 - rate)
                            goes = AT_LOWER
                        }
                    }
                    if goes != BASIC {
                        if room < 0.0f64 { room = 0.0f64 }
                        var take = r == lp.rows || room < room_r - 0.000000000001f64
                        if !take && room <= room_r + 0.000000000001f64 {
                            if bland {
                                take = b < lp.basis[r]
                            } else {
                                take = math.abs[f64](alpha) > math.abs[f64](alpha_r)
                            }
                        }
                        if take {
                            r = i
                            room_r = room
                            goes_r = goes
                            alpha_r = alpha
                        }
                    }
                }
                i += 1usize
            }
            if r == lp.rows && !finite(flip) {
                outcome = LP_UNBOUNDED
                running = false
            } else if r == lp.rows || flip <= room_r {
                if dir > 0.0f64 { lp.state[q] = AT_UPPER } else { lp.state[q] = AT_LOWER }
                degenerate = 0usize
            } else {
                let leaving = lp.basis[r]
                lp_pivot(lp, r, q)
                lp.state[leaving] = goes_r
                lp.state[q] = BASIC
                if room_r <= 0.000000000001f64 {
                    degenerate += 1usize
                    if degenerate > active { bland = true }
                } else {
                    degenerate = 0usize
                }
            }
        }
        iteration += 1usize
    }
    ret outcome
}

fn lp_dual(lp: *Lp) -> usize {
    let wd = lp.width
    let active = lp.n + lp.rows
    let limit = 20usize * active + 500usize
    var iteration = 0usize
    var outcome = LP_STALLED
    var running = true
    while running && iteration < limit {
        if lp.pivots >= 100usize { let _ = lp_refactor(lp) }
        lp_values(lp)
        var i = 0usize
        while i < lp.rows {
            lp.w[i] = column_cost(lp, lp.basis[i])
            i += 1usize
        }
        lp_duals(lp, false)
        var r = lp.rows
        var worst = feasibility()
        i = 0usize
        while i < lp.rows {
            let b = lp.basis[i]
            var amount = 0.0f64
            if lp.val[b] < lp.lo[b] - feasibility() {
                amount = lp.lo[b] - lp.val[b]
            } else if lp.val[b] > lp.hi[b] + feasibility() {
                amount = lp.val[b] - lp.hi[b]
            }
            if amount > worst {
                worst = amount
                r = i
            }
            i += 1usize
        }
        if r == lp.rows {
            outcome = LP_OPTIMAL
            running = false
        } else {
            let leaving = lp.basis[r]
            let below = lp.val[leaving] < lp.lo[leaving]
            var q = active
            var ratio_q = infinity()
            var alpha_q = 0.0f64
            var j = 0usize
            while j < active {
                let s = lp.state[j]
                let alpha = lp.t[r * wd + j]
                if s != BASIC && lp.lo[j] < lp.hi[j] && math.abs[f64](alpha) > pivot_tolerance() {
                    // x_leaving moves by -alpha per unit of x_j.
                    var eligible = false
                    if below {
                        eligible = ((s == AT_LOWER || s == FREE) && alpha < 0.0f64) || ((s == AT_UPPER || s == FREE) && alpha > 0.0f64)
                    } else {
                        eligible = ((s == AT_LOWER || s == FREE) && alpha > 0.0f64) || ((s == AT_UPPER || s == FREE) && alpha < 0.0f64)
                    }
                    if eligible {
                        let ratio = math.abs[f64](lp.d[j]) / math.abs[f64](alpha)
                        if q == active || ratio < ratio_q - 0.000000000001f64 || (ratio <= ratio_q + 0.000000000001f64 && math.abs[f64](alpha) > math.abs[f64](alpha_q)) {
                            q = j
                            ratio_q = ratio
                            alpha_q = alpha
                        }
                    }
                }
                j += 1usize
            }
            if q == active {
                outcome = LP_INFEASIBLE
                running = false
            } else {
                lp_pivot(lp, r, q)
                if below { lp.state[leaving] = AT_LOWER } else { lp.state[leaving] = AT_UPPER }
                lp.state[q] = BASIC
            }
        }
        iteration += 1usize
    }
    ret outcome
}

// Re-inverts the current basis, places the nonbasic variables by the sign
// of their reduced costs, then the dual simplex when that is dual feasible
// and the primal simplex otherwise (or when the dual one stalls).
fn lp_solve(lp: *Lp) -> usize {
    let _ = lp_refactor(lp)
    var i = 0usize
    while i < lp.rows {
        lp.w[i] = column_cost(lp, lp.basis[i])
        i += 1usize
    }
    lp_duals(lp, false)
    let active = lp.n + lp.rows
    var dual_feasible = true
    var j = 0usize
    while j < active {
        if lp.state[j] != BASIC {
            let dj = lp.d[j]
            place_nonbasic(lp, j, dj < 0.0f64)
            let s = lp.state[j]
            if lp.lo[j] < lp.hi[j] {
                if s == AT_LOWER && dj < 0.0f64 - optimality() { dual_feasible = false }
                if s == AT_UPPER && dj > optimality() { dual_feasible = false }
                if s == FREE && math.abs[f64](dj) > optimality() { dual_feasible = false }
            }
        }
        j += 1usize
    }
    if dual_feasible {
        let outcome = lp_dual(lp)
        if outcome != LP_STALLED { ret outcome }
    }
    ret lp_primal(lp)
}

fn fraction(v: f64) -> f64 {
    let f = v - math.floor[f64](v)
    if f > 0.5f64 { ret 1.0f64 - f }
    ret f
}

// The most fractional integer variable, or `n` when the solution is integral.
fn branching_variable(lp: *const Lp, tolerance: f64) -> usize {
    var pick = lp.n
    var best = tolerance
    var j = 0usize
    while j < lp.n {
        if lp.integral[j] == 1usize {
            let f = fraction(lp.val[j])
            if f > best {
                best = f
                pick = j
            }
        }
        j += 1usize
    }
    ret pick
}

// One Gomory mixed-integer cut per fractional basic integer variable, read
// off its tableau row with the nonbasic variables shifted to their bounds,
// expressed back over the structural variables and appended as a row
// `g·x >= rhs`. `g` is scratch of `n`. Answers the number appended.
fn gmi_round(lp: *Lp, max_rows: usize, g: []f64) -> usize {
    let wd = lp.width
    let n = lp.n
    let rows0 = lp.rows
    let active0 = n + rows0
    var added = 0usize
    var i = 0usize
    while i < rows0 && lp.rows < max_rows {
        let b = lp.basis[i]
        let beta = lp.val[b]
        let f0 = beta - math.floor[f64](beta)
        if b < n && lp.integral[b] == 1usize && f0 >= 0.01f64 && f0 <= 0.99f64 {
            var usable = true
            var rhs = 1.0f64
            var k = 0usize
            while k < n {
                g[k] = 0.0f64
                k += 1usize
            }
            var j = 0usize
            while j < active0 && usable {
                let s = lp.state[j]
                let a = lp.t[i * wd + j]
                if s != BASIC && lp.lo[j] < lp.hi[j] && math.abs[f64](a) > 0.000000000001f64 {
                    if s == FREE {
                        usable = false
                    } else {
                        var sign = 1.0f64
                        var bound = lp.lo[j]
                        if s == AT_UPPER {
                            sign = 0.0f64 - 1.0f64
                            bound = lp.hi[j]
                        }
                        let abar = sign * a
                        var coef = 0.0f64
                        if lp.integral[j] == 1usize {
                            let fj = abar - math.floor[f64](abar)
                            if fj <= f0 { coef = fj / f0 } else { coef = (1.0f64 - fj) / (1.0f64 - f0) }
                        } else if abar >= 0.0f64 {
                            coef = abar / f0
                        } else {
                            coef = (0.0f64 - abar) / (1.0f64 - f0)
                        }
                        // coef * y_j with y_j = sign (x_j - bound).
                        rhs += coef * sign * bound
                        if j < n {
                            g[j] += coef * sign
                        } else {
                            k = 0usize
                            while k < n {
                                g[k] += coef * sign * row_coefficient(lp, j - n, k)
                                k += 1usize
                            }
                        }
                    }
                }
                j += 1usize
            }
            // Drop tiny coefficients by relaxing the right-hand side over the
            // variable's box; refuse a cut that needs an infinite box or has a
            // wide dynamic range, and one the current point already satisfies.
            var largest = 0.0f64
            var smallest = infinity()
            var activity = 0.0f64
            k = 0usize
            while k < n && usable {
                let gk = g[k]
                let size = math.abs[f64](gk)
                if size > 0.0f64 && size < 0.000000001f64 {
                    var reach = math.abs[f64](lp.lo[k])
                    if math.abs[f64](lp.hi[k]) > reach { reach = math.abs[f64](lp.hi[k]) }
                    if !finite(lp.lo[k]) || !finite(lp.hi[k]) {
                        usable = false
                    } else {
                        rhs -= size * reach
                        g[k] = 0.0f64
                    }
                } else if size > 0.0f64 {
                    if size > largest { largest = size }
                    if size < smallest { smallest = size }
                    activity += gk * lp.val[k]
                }
                k += 1usize
            }
            rhs -= 0.000000001f64 * (1.0f64 + math.abs[f64](rhs))
            if usable && largest > 0.0f64 && largest <= 1000000.0f64 * smallest && activity < rhs - 0.000001f64 * (1.0f64 + math.abs[f64](rhs)) {
                let row = lp.rows
                let column = n + row
                k = 0usize
                while k < n {
                    lp.cut[(row - lp.m) * n + k] = g[k]
                    k += 1usize
                }
                lp.rows += 1usize
                let active = n + lp.rows
                j = 0usize
                while j < active {
                    lp.t[row * wd + j] = 0.0f64
                    j += 1usize
                }
                k = 0usize
                while k < n {
                    lp.t[row * wd + k] = 0.0f64 - g[k]
                    k += 1usize
                }
                lp.t[row * wd + column] = 1.0f64
                var e = 0usize
                while e < row {
                    lp.t[e * wd + column] = 0.0f64
                    e += 1usize
                }
                // Eliminate the basic columns so the new logical is basic in it.
                e = 0usize
                while e < row {
                    let f = lp.t[row * wd + lp.basis[e]]
                    if f != 0.0f64 {
                        j = 0usize
                        while j < active {
                            lp.t[row * wd + j] -= f * lp.t[e * wd + j]
                            j += 1usize
                        }
                        lp.t[row * wd + lp.basis[e]] = 0.0f64
                    }
                    e += 1usize
                }
                lp.basis[row] = column
                lp.state[column] = BASIC
                lp.lo[column] = rhs
                lp.hi[column] = infinity()
                lp.integral[column] = 0usize
                added += 1usize
            }
        }
        i += 1usize
    }
    ret added
}

fn is_whole(v: f64) -> bool { ret v == math.floor[f64](v) }

// Minimise `p.c·x` over the mixed-integer set of `p`; `x` receives the best
// solution found. Errors are for bad arguments and a stalled simplex; an
// infeasible or unbounded programme is a status.
fn solve(p: *const Problem, o: Options, x: []f64, scratch: []f64, slots: []usize) -> (Result, err) {
    let n = p.n
    let m = p.m
    if n == 0usize || o.integrality <= 0.0f64 || o.gap < 0.0f64 { ret (zero, Invalid) }
    if p.c.len < n || p.a.len < m * n || p.row_lower.len < m || p.row_upper.len < m || p.lower.len < n || p.upper.len < n || p.integer.len < n || x.len < n { ret (zero, TooSmall) }
    let cap = m + o.max_cuts
    let wd = n + cap
    let stride = 2usize * n + 1usize
    let fixed = scratch_len(n, m, o.max_cuts, 0usize)
    if scratch.len < fixed + 2usize * stride || slots.len < slot_len(n, m, o.max_cuts) { ret (zero, TooSmall) }
    var at = 0usize
    let t = scratch[at..at + cap * wd]
    at += cap * wd
    let lo = scratch[at..at + wd]
    at += wd
    let hi = scratch[at..at + wd]
    at += wd
    let val = scratch[at..at + wd]
    at += wd
    let d = scratch[at..at + wd]
    at += wd
    let w = scratch[at..at + cap]
    at += cap
    let cut = scratch[at..at + o.max_cuts * n]
    at += o.max_cuts * n
    let g = scratch[at..at + n]
    at += n
    let base_lo = scratch[at..at + n]
    at += n
    let base_hi = scratch[at..at + n]
    at += n
    let best = scratch[at..at + n]
    at += n
    let pool = scratch[at..scratch.len]
    let pool_cap = pool.len / stride
    let basis = slots[..cap]
    let state = slots[cap..cap + wd]
    let integral = slots[cap + wd..cap + 2usize * wd]
    var lp = Lp { n: n, m: m, rows: m, width: wd, a: p.a, cost: p.c, cut: cut, t: t, lo: lo, hi: hi, val: val, d: d, w: w, basis: basis, state: state, integral: integral, pivots: 0usize }

    // Bounds: integer boxes rounded inward, a row over integer variables with
    // integer coefficients has an integer logical and rounded bounds too.
    var box_empty = false
    var j = 0usize
    while j < n {
        var l = p.lower[j]
        var u = p.upper[j]
        if !finite(l) { l = 0.0f64 - infinity() }
        if !finite(u) { u = infinity() }
        integral[j] = 0usize
        if p.integer[j] {
            integral[j] = 1usize
            if finite(l) { l = math.ceil[f64](l - 0.000000001f64) }
            if finite(u) { u = math.floor[f64](u + 0.000000001f64) }
        }
        if l > u { box_empty = true }
        lo[j] = l
        hi[j] = u
        base_lo[j] = l
        base_hi[j] = u
        state[j] = AT_LOWER
        j += 1usize
    }
    var i = 0usize
    while i < m {
        var l = p.row_lower[i]
        var u = p.row_upper[i]
        if !finite(l) { l = 0.0f64 - infinity() }
        if !finite(u) { u = infinity() }
        var whole = true
        j = 0usize
        while j < n {
            let aij = p.a[i * n + j]
            if aij != 0.0f64 && (integral[j] == 0usize || !is_whole(aij)) { whole = false }
            j += 1usize
        }
        integral[n + i] = 0usize
        if whole {
            integral[n + i] = 1usize
            if finite(l) { l = math.ceil[f64](l - 0.000000001f64) }
            if finite(u) { u = math.floor[f64](u + 0.000000001f64) }
        }
        if l > u { box_empty = true }
        lo[n + i] = l
        hi[n + i] = u
        state[n + i] = BASIC
        basis[i] = n + i
        i += 1usize
    }
    var result = Result { status: .Infeasible, objective: infinity(), bound: infinity(), nodes: 0u32, cuts: 0u32 }
    if box_empty { ret (result, ok) }

    // Root, then rounds of cuts while they move the bound.
    var outcome = lp_solve(&lp)
    result.nodes = 1u32
    if outcome == LP_STALLED { ret (result, Stalled) }
    if outcome == LP_INFEASIBLE { ret (result, ok) }
    if outcome == LP_UNBOUNDED {
        result.status = .Unbounded
        result.objective = 0.0f64 - infinity()
        result.bound = 0.0f64 - infinity()
        ret (result, ok)
    }
    var root = lp_objective(&lp)
    var round = 0u32
    var cutting = o.cut_rounds > 0u32
    while cutting && round < o.cut_rounds && branching_variable(&lp, o.integrality) < n {
        let added = gmi_round(&lp, cap, g)
        result.cuts += u32(added)
        round += 1u32
        if added == 0usize {
            cutting = false
        } else {
            outcome = lp_solve(&lp)
            if outcome == LP_STALLED { ret (result, Stalled) }
            if outcome != LP_OPTIMAL { ret (result, ok) }
            let moved = lp_objective(&lp)
            if moved <= root + 0.000000001f64 * (1.0f64 + math.abs[f64](root)) { cutting = false }
            root = moved
        }
    }

    // Best-bound branch and bound; the open pool holds [bound, lower, upper].
    var incumbent = infinity()
    var have = false
    var open = 0usize
    var limited = false
    var leftover = infinity()
    var node_ready = true
    var node_value = root
    var searching = true
    while searching {
        if node_ready {
            let pick = branching_variable(&lp, o.integrality)
            var margin = 0.000000001f64 * (1.0f64 + math.abs[f64](incumbent))
            if have && o.gap * math.abs[f64](incumbent) > margin { margin = o.gap * math.abs[f64](incumbent) }
            if have && node_value >= incumbent - margin {
                // Pruned by bound.
            } else if pick == n {
                // Polish: fix the integers at their rounded values and re-solve
                // for the continuous ones, so rounding leaves no row violated.
                j = 0usize
                while j < n {
                    best[j] = lp.val[j]
                    if integral[j] == 1usize {
                        lo[j] = math.round[f64](lp.val[j])
                        hi[j] = lo[j]
                    }
                    j += 1usize
                }
                incumbent = node_value
                outcome = lp_solve(&lp)
                if outcome == LP_STALLED { ret (result, Stalled) }
                if outcome == LP_OPTIMAL {
                    incumbent = lp_objective(&lp)
                    j = 0usize
                    while j < n {
                        best[j] = lp.val[j]
                        j += 1usize
                    }
                }
                j = 0usize
                while j < n {
                    if integral[j] == 1usize { best[j] = math.round[f64](best[j]) }
                    j += 1usize
                }
                have = true
            } else if open + 2usize > pool_cap {
                limited = true
                leftover = node_value
                searching = false
            } else {
                let v = lp.val[pick]
                var child = 0usize
                while child < 2usize {
                    let base = (open + child) * stride
                    pool[base] = node_value
                    j = 0usize
                    while j < n {
                        pool[base + 1usize + j] = lo[j]
                        pool[base + 1usize + n + j] = hi[j]
                        j += 1usize
                    }
                    if child == 0usize {
                        pool[base + 1usize + n + pick] = math.floor[f64](v)
                    } else {
                        pool[base + 1usize + pick] = math.ceil[f64](v)
                    }
                    child += 1usize
                }
                open += 2usize
            }
            node_ready = false
        }
        if searching {
            // The open node with the least bound, the latest on a tie.
            var chosen = open
            var k = 0usize
            while k < open {
                if chosen == open || pool[k * stride] <= pool[chosen * stride] { chosen = k }
                k += 1usize
            }
            if chosen == open {
                searching = false
            } else {
                let bound = pool[chosen * stride]
                var margin = 0.000000001f64 * (1.0f64 + math.abs[f64](incumbent))
                if have && o.gap * math.abs[f64](incumbent) > margin { margin = o.gap * math.abs[f64](incumbent) }
                if have && bound >= incumbent - margin {
                    // Every open node is at least this bound: done.
                    open = 0usize
                    searching = false
                } else if result.nodes >= o.node_limit {
                    limited = true
                    searching = false
                } else {
                    let base = chosen * stride
                    j = 0usize
                    while j < n {
                        lo[j] = pool[base + 1usize + j]
                        hi[j] = pool[base + 1usize + n + j]
                        j += 1usize
                    }
                    // Remove by moving the last node into its slot.
                    open -= 1usize
                    if chosen != open {
                        k = 0usize
                        while k < stride {
                            pool[base + k] = pool[open * stride + k]
                            k += 1usize
                        }
                    }
                    outcome = lp_solve(&lp)
                    result.nodes += 1u32
                    if outcome == LP_STALLED { ret (result, Stalled) }
                    if outcome == LP_OPTIMAL {
                        node_value = lp_objective(&lp)
                        node_ready = true
                    }
                }
            }
        }
    }

    // Best bound: the incumbent or the least open node.
    var lowest = leftover
    var k = 0usize
    while k < open {
        if pool[k * stride] < lowest { lowest = pool[k * stride] }
        k += 1usize
    }
    if have {
        result.objective = 0.0f64
        j = 0usize
        while j < n {
            x[j] = best[j]
            result.objective += p.c[j] * best[j]
            j += 1usize
        }
        result.bound = incumbent
        if lowest < incumbent { result.bound = lowest }
    } else {
        result.bound = lowest
    }
    if limited {
        result.status = .NodeLimit
    } else if have {
        result.status = .Optimal
    }
    ret (result, ok)
}
