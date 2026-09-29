// Model checking over caller storage. `explore` is explicit-state checking:
// a state is `width` u64 words, the caller's `successors` writes a state's
// successors and `invariant` judges each state as it is first reached;
// breadth-first search with a visited set (open addressing over `table`)
// and a parent link per state, so the first violation found is at the least
// depth and `trace` answers a shortest counterexample. `bmc` is bounded
// model checking over `e.algo.sat`: a boolean transition system of `n`
// variables per frame, given as clause-building callbacks, is unrolled and
// the solver asked whether a bad state is reachable at step exactly
// j = 0, 1, .., k; `prove` adds k-induction so a safe property is proven,
// not only bounded.
//
// ponytail: safety only; liveness/LTL (Büchi products, nested DFS) is out.
// ponytail: no symmetry or partial-order reduction; every interleaving is a
// state, so the visited set grows with the product of the process states.
// ponytail: the visited set lives in caller memory and refuses when full;
// no disk spill or hash compaction.

use e.algo.sat as sat

error TooSmall
error Invalid
error Full

// Safe: every reachable state (within the bound) satisfies the invariant;
// for `prove` the property is proven. Violated: a bad state is reachable.
// Deadlock: a reachable state has no successor. Bounded: nothing found, but
// the depth bound stopped the search.
type Verdict = enum u8 { Safe, Violated, Deadlock, Bounded }

// `states` stored, `transitions` generated (duplicates included), `depth` of
// the deepest stored state, `last` the violating or deadlocked state's index.
type Result = struct { verdict: Verdict, states: usize, transitions: usize, depth: usize, last: usize }

const ROOT: u32 = 4294967295u32

fn hash_state(s: []const u64) -> u64 {
    var h = 14695981039346656037u64
    var i = 0usize
    while i < s.len {
        h = (h ^ s[i]) *% 11400714819323198485u64
        h = h ^ (h >> 29u32)
        i += 1usize
    }
    ret h
}

fn same_state(a: []const u64, b: []const u64) -> bool {
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// Finds `s` in the set or inserts it at index `count` (copied into `store`);
// answers the index and whether it was new. `Full` when no room is left.
fn visit(s: []const u64, width: usize, store: []u64, table: []u32, count: usize, capacity: usize) -> (usize, bool, err) {
    var slot = usize(hash_state(s) % u64(table.len))
    while table[slot] != 0u32 {
        let i = usize(table[slot]) - 1usize
        if same_state(store[i * width..(i + 1usize) * width], s) { ret (i, false, ok) }
        slot += 1usize
        if slot == table.len { slot = 0usize }
    }
    if count >= capacity || count + 1usize >= table.len { ret (0usize, false, Full) }
    var w = 0usize
    while w < width {
        store[count * width + w] = s[w]
        w += 1usize
    }
    table[slot] = u32(count + 1usize)
    ret (count, true, ok)
}

// Breadth-first explicit-state search from the states in `initial` (a
// multiple of `width` words). `successors(ctx, state, out)` writes a state's
// successors one after another into `out` (`scratch`) and answers how many;
// `invariant` is checked on every state when first reached. With `deadlock`
// a state without successors is reported. `max_depth` stops expanding at
// that depth (zero means no limit). Storage: `store` holds `width` words per
// state, `parent` one entry per state, `table` the hash slots (more than the
// state capacity); the capacity is `min(store.len / width, parent.len)` and
// running out answers `Full`.
fn explore[Ctx: type](ctx: *Ctx, width: usize, initial: []const u64, successors: fn(*Ctx, []const u64, []u64) -> usize, invariant: fn(*Ctx, []const u64) -> bool, deadlock: bool, max_depth: usize, store: []u64, parent: []u32, table: []u32, scratch: []u64) -> (Result, err) {
    var r = Result { verdict: .Safe, states: 0usize, transitions: 0usize, depth: 0usize, last: 0usize }
    if width == 0usize || initial.len % width != 0usize || table.len < 2usize { ret (r, Invalid) }
    var capacity = store.len / width
    if parent.len < capacity { capacity = parent.len }
    if capacity > usize(ROOT) { capacity = usize(ROOT) }
    var i = 0usize
    while i < table.len {
        table[i] = 0u32
        i += 1usize
    }
    var count = 0usize
    i = 0usize
    while i < initial.len {
        let s = initial[i..i + width]
        let (at, fresh, e) = visit(s, width, store, table, count, capacity)
        if e != ok { ret (r, e) }
        if fresh {
            parent[at] = ROOT
            count += 1usize
            if !invariant(ctx, s) {
                r.verdict = .Violated
                r.states = count
                r.last = at
                ret (r, ok)
            }
        }
        i += width
    }
    var head = 0usize
    var depth = 0usize
    var level_end = count
    while head < count {
        if head == level_end {
            depth += 1usize
            level_end = count
        }
        if max_depth != 0usize && depth >= max_depth {
            r.verdict = .Bounded
            r.states = count
            ret (r, ok)
        }
        let produced = successors(ctx, store[head * width..(head + 1usize) * width], scratch)
        if produced > scratch.len / width { ret (r, Invalid) }
        r.transitions += produced
        if produced == 0usize && deadlock {
            r.verdict = .Deadlock
            r.states = count
            r.last = head
            ret (r, ok)
        }
        var k = 0usize
        while k < produced {
            let s = scratch[k * width..(k + 1usize) * width]
            let (at, fresh, e) = visit(s, width, store, table, count, capacity)
            if e != ok {
                r.states = count
                ret (r, e)
            }
            if fresh {
                parent[at] = u32(head)
                count += 1usize
                r.depth = depth + 1usize
                if !invariant(ctx, s) {
                    r.verdict = .Violated
                    r.states = count
                    r.last = at
                    ret (r, ok)
                }
            }
            k += 1usize
        }
        head += 1usize
    }
    r.states = count
    ret (r, ok)
}

// The path of state indices from an initial state to `last` through the
// parent links `explore` left, written to `out`; answers its length.
fn trace(parent: []const u32, last: usize, out: []u32) -> (usize, err) {
    if last >= parent.len { ret (0usize, Invalid) }
    var n = 1usize
    var i = last
    while parent[i] != ROOT {
        i = usize(parent[i])
        n += 1usize
    }
    if out.len < n { ret (0usize, TooSmall) }
    i = last
    var k = n
    while k > 0usize {
        k = k - 1usize
        out[k] = u32(i)
        if parent[i] != ROOT { i = usize(parent[i]) }
    }
    ret (n, ok)
}

// Solver storage for `bmc` and `prove` (see `sat.solve`); every buffer must
// cover the formula's variables.
type Solver = struct { assignment: []i8, trail: []u32, level: []u32, flipped: []u8, learned: []i32, learned_starts: []usize }

fn solver(assignment: []i8, trail: []u32, level: []u32, flipped: []u8, learned: []i32, learned_starts: []usize) -> Solver {
    ret Solver { assignment: assignment, trail: trail, level: level, flipped: flipped, learned: learned, learned_starts: learned_starts }
}

// Is `f` satisfiable with `lit` true? The unit is withdrawn afterwards.
fn satisfiable_with(f: *sat.Cnf, lit: i32, s: *Solver) -> (bool, err) {
    let before = f.clauses
    if sat.clause1(f, lit) != ok { ret (false, TooSmall) }
    let verdict = sat.solve(f, s.assignment, s.trail, s.level, s.flipped, s.learned, s.learned_starts, 1000000usize)
    f.clauses = before
    if verdict == ok { ret (true, ok) }
    if verdict == sat.Unsatisfiable { ret (false, ok) }
    ret (false, verdict)
}

fn fresh_frame(f: *sat.Cnf, frame: []i32) {
    var i = 0usize
    while i < frame.len {
        frame[i] = sat.fresh(f)
        i += 1usize
    }
}

// Bounded model checking. The system has `n` state variables per frame;
// frame literals live in `frames` (`(k + 1) * n`). `init(ctx, f, frame0)`
// adds the initial-state clauses; `trans(ctx, f, now, after)` constrains the
// next frame, whose literals arrive fresh and may be replaced (by gate
// outputs, say); `bad(ctx, f, frame)` answers a literal true exactly when the
// frame is a bad state. `f` starts empty (`sat.cnf(.., 0)`). Answers
// `Violated` and the least step j with a bad state reachable -- `values`
// (`(k + 1) * n`, one 0/1 per variable per frame) then holds the trace for
// frames 0..j -- or `Bounded` and `k` when none is reachable within k steps.
fn bmc[Ctx: type](ctx: *Ctx, n: usize, init: fn(*Ctx, *sat.Cnf, []const i32) -> err, trans: fn(*Ctx, *sat.Cnf, []const i32, []i32) -> err, bad: fn(*Ctx, *sat.Cnf, []const i32) -> (i32, err), k: usize, f: *sat.Cnf, frames: []i32, s: *Solver, values: []u8) -> (Verdict, usize, err) {
    if n == 0usize { ret (.Bounded, 0usize, Invalid) }
    if frames.len < (k + 1usize) * n || values.len < (k + 1usize) * n { ret (.Bounded, 0usize, TooSmall) }
    fresh_frame(f, frames[..n])
    let init_error = init(ctx, f, frames[..n])
    if init_error != ok { ret (.Bounded, 0usize, init_error) }
    var j = 0usize
    while j <= k {
        let now = frames[j * n..(j + 1usize) * n]
        if j > 0usize {
            fresh_frame(f, now)
            let trans_error = trans(ctx, f, frames[(j - 1usize) * n..j * n], now)
            if trans_error != ok { ret (.Bounded, 0usize, trans_error) }
        }
        let (b, bad_error) = bad(ctx, f, now)
        if bad_error != ok { ret (.Bounded, 0usize, bad_error) }
        let (hit, solve_error) = satisfiable_with(f, b, s)
        if solve_error != ok { ret (.Bounded, 0usize, solve_error) }
        if hit {
            var i = 0usize
            while i < (j + 1usize) * n {
                values[i] = 0u8
                if sat.value_of(s.assignment, frames[i]) > 0i8 { values[i] = 1u8 }
                i += 1usize
            }
            ret (.Violated, j, ok)
        }
        j += 1usize
    }
    ret (.Bounded, k, ok)
}

// k-induction: for m = 1, 2, .., k + 1 asks (in `step`, no initial state)
// whether m consecutive good states can be followed by a bad one; when not,
// the property holds once `bmc` finds no bad state within m - 1 steps, and
// the answer is `Safe` and m. Otherwise as `bmc` up to `k` (with `base` and
// `frames`). `step` starts empty; `step_frames.len >= (k + 2) * n`.
// ponytail: no simple-path constraint, so a property whose unreachable states
// loop among themselves is never proven; add pairwise frame disequality
// clauses when one is needed.
fn prove[Ctx: type](ctx: *Ctx, n: usize, init: fn(*Ctx, *sat.Cnf, []const i32) -> err, trans: fn(*Ctx, *sat.Cnf, []const i32, []i32) -> err, bad: fn(*Ctx, *sat.Cnf, []const i32) -> (i32, err), k: usize, base: *sat.Cnf, frames: []i32, step: *sat.Cnf, step_frames: []i32, s: *Solver, values: []u8) -> (Verdict, usize, err) {
    if n == 0usize { ret (.Bounded, 0usize, Invalid) }
    if step_frames.len < (k + 2usize) * n { ret (.Bounded, 0usize, TooSmall) }
    fresh_frame(step, step_frames[..n])
    let (first_bad, first_error) = bad(ctx, step, step_frames[..n])
    if first_error != ok { ret (.Bounded, 0usize, first_error) }
    var current = first_bad
    var j = 0usize
    var proven = false
    while j <= k && !proven {
        if sat.clause1(step, 0i32 - current) != ok { ret (.Bounded, 0usize, TooSmall) }
        let after = step_frames[(j + 1usize) * n..(j + 2usize) * n]
        fresh_frame(step, after)
        let trans_error = trans(ctx, step, step_frames[j * n..(j + 1usize) * n], after)
        if trans_error != ok { ret (.Bounded, 0usize, trans_error) }
        let (b, bad_error) = bad(ctx, step, after)
        if bad_error != ok { ret (.Bounded, 0usize, bad_error) }
        let (hit, solve_error) = satisfiable_with(step, b, s)
        if solve_error != ok { ret (.Bounded, 0usize, solve_error) }
        current = b
        j += 1usize
        if !hit { proven = true }
    }
    if !proven {
        let (verdict, depth, e) = bmc[Ctx](ctx, n, init, trans, bad, k, base, frames, s, values)
        ret (verdict, depth, e)
    }
    let (verdict, depth, e) = bmc[Ctx](ctx, n, init, trans, bad, j - 1usize, base, frames, s, values)
    if e != ok || verdict == .Violated { ret (verdict, depth, e) }
    ret (.Safe, j, ok)
}
