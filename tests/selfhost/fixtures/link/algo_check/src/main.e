// `e.algo.check`: explicit-state BFS finds Peterson's two-process mutex safe
// with the reachable-state and transition counts of the Python reference
// (vectors.py), stops at a depth bound, refuses when the visited set is full,
// finds the broken test-then-set mutex violating with a shortest trace that
// replays (each step a successor), and finds the three dining philosophers'
// deadlock. Bounded model checking over e.algo.sat finds a 4-bit counter
// (x + 1 mod 16, 11 wraps to 0) reaching 11 at step exactly 11 with the
// counting trace, none within 10 steps, never 13 within 15, and k-induction
// proves 13 unreachable at depth 2 while answering 11's counterexample.
// Each check exits with its own code.

use e.algo.check as check
use e.algo.sat as sat
use e.io
use e.mem
use e.os

type Nothing = struct { unused: u8 }

// Copy `s` into successor slot `count` of `out`.
fn emit(s: []const u64, out: []u64, count: usize) -> []u64 {
    let t = out[count * s.len..(count + 1usize) * s.len]
    var i = 0usize
    while i < s.len {
        t[i] = s[i]
        i += 1usize
    }
    ret t
}

// Peterson: s = pc0, pc1, flag0, flag1, turn.
fn peterson(m: *Nothing, s: []const u64, out: []u64) -> usize {
    var count = 0usize
    var i = 0usize
    while i < 2usize {
        let other = 1usize - i
        let pc = s[i]
        if pc != 2u64 || s[2usize + other] == 0u64 || s[4usize] == u64(i) {
            let t = emit(s, out, count)
            if pc == 0u64 {
                t[2usize + i] = 1u64
                t[i] = 1u64
            } else if pc == 1u64 {
                t[4usize] = u64(other)
                t[i] = 2u64
            } else if pc == 2u64 {
                t[i] = 3u64
            } else {
                t[2usize + i] = 0u64
                t[i] = 0u64
            }
            count += 1usize
        }
        i += 1usize
    }
    ret count
}

fn peterson_safe(m: *Nothing, s: []const u64) -> bool { ret !(s[0usize] == 3u64 && s[1usize] == 3u64) }

fn always(m: *Nothing, s: []const u64) -> bool { ret true }

// Test-then-set without atomicity: s = pc0, pc1, lock; pc 0 waits for the
// lock to be free, 1 takes it, 2 is critical and releases it.
fn mutex(m: *Nothing, s: []const u64, out: []u64) -> usize {
    var count = 0usize
    var i = 0usize
    while i < 2usize {
        let pc = s[i]
        if pc != 0u64 || s[2usize] == 0u64 {
            let t = emit(s, out, count)
            if pc == 0u64 {
                t[i] = 1u64
            } else if pc == 1u64 {
                t[2usize] = 1u64
                t[i] = 2u64
            } else {
                t[2usize] = 0u64
                t[i] = 0u64
            }
            count += 1usize
        }
        i += 1usize
    }
    ret count
}

fn mutex_safe(m: *Nothing, s: []const u64) -> bool { ret !(s[0usize] == 2u64 && s[1usize] == 2u64) }

// Fork j is philosopher j's left and philosopher (j + 2) % 3's right.
fn fork_free(s: []const u64, j: usize) -> bool { ret s[j] == 0u64 && s[(j + 2usize) % 3usize] != 2u64 }

// Dining philosophers: s = pc of each; 0 thinks, 1 holds the left fork, 2 eats.
fn dining(m: *Nothing, s: []const u64, out: []u64) -> usize {
    var count = 0usize
    var i = 0usize
    while i < 3usize {
        let pc = s[i]
        if pc == 2u64 || (pc == 0u64 && fork_free(s, i)) || (pc == 1u64 && fork_free(s, (i + 1usize) % 3usize)) {
            let t = emit(s, out, count)
            t[i] = (pc + 1u64) % 3u64
            count += 1usize
        }
        i += 1usize
    }
    ret count
}

fn explicit_checks() -> i32 {
    var nothing = Nothing { unused: 0u8 }
    var store: [512]u64 = zero
    var parent: [128]u32 = zero
    var table: [256]u32 = zero
    var scratch: [16]u64 = zero
    var path: [32]u32 = zero
    var start: [5]u64 = zero

    // 1: Peterson is safe, 20 states, 34 transitions, deepest state at 6; no deadlock.
    let (p, p_error) = check.explore[Nothing](&nothing, 5usize, start[..], peterson, peterson_safe, true, 0usize, store[..], parent[..], table[..], scratch[..])
    if p_error != ok || p.verdict != .Safe || p.states != 20usize || p.transitions != 34usize || p.depth != 6usize { ret 1i32 }

    // 2: bounded at depth 3: 10 states, 12 transitions; capacity 10 refuses.
    let (b, b_error) = check.explore[Nothing](&nothing, 5usize, start[..], peterson, peterson_safe, false, 3usize, store[..], parent[..], table[..], scratch[..])
    if b_error != ok || b.verdict != .Bounded || b.states != 10usize || b.transitions != 12usize || b.depth != 3usize { ret 2i32 }
    let (_, full_error) = check.explore[Nothing](&nothing, 5usize, start[..], peterson, always, false, 0usize, store[..], parent[..10usize], table[..], scratch[..])
    if full_error != check.Full { ret 2i32 }
    let (_, width_error) = check.explore[Nothing](&nothing, 0usize, start[..], peterson, always, false, 0usize, store[..], parent[..], table[..], scratch[..])
    if width_error != check.Invalid { ret 2i32 }

    // 3: the broken mutex violates after 9 states, 12 transitions, at state 8;
    // the shortest trace has 5 states and replays.
    let (v, v_error) = check.explore[Nothing](&nothing, 3usize, start[..3usize], mutex, mutex_safe, false, 0usize, store[..], parent[..], table[..], scratch[..])
    if v_error != ok || v.verdict != .Violated || v.states != 9usize || v.transitions != 12usize || v.last != 8usize { ret 3i32 }
    let (n, trace_error) = check.trace(parent[..], v.last, path[..])
    if trace_error != ok || n != 5usize || path[0usize] != 0u32 || usize(path[4usize]) != v.last { ret 3i32 }
    var step = 0usize
    while step + 1usize < n {
        let from = usize(path[step])
        let to = usize(path[step + 1usize])
        let count = mutex(&nothing, store[from * 3usize..from * 3usize + 3usize], scratch[..])
        var found = false
        var k = 0usize
        while k < count {
            if scratch[k * 3usize] == store[to * 3usize] && scratch[k * 3usize + 1usize] == store[to * 3usize + 1usize] && scratch[k * 3usize + 2usize] == store[to * 3usize + 2usize] { found = true }
            k += 1usize
        }
        if !found { ret 3i32 }
        step += 1usize
    }
    // The last state has both processes critical; the trace ends (2, 2, 1).
    if store[v.last * 3usize] != 2u64 || store[v.last * 3usize + 1usize] != 2u64 || store[v.last * 3usize + 2usize] != 1u64 { ret 3i32 }
    let (_, short_error) = check.trace(parent[..], v.last, path[..4usize])
    if short_error != check.TooSmall { ret 3i32 }

    // 4: three dining philosophers deadlock at state 12 (all hold the left fork)
    // after 14 states and 26 transitions; the trace has 4 states.
    let (d, d_error) = check.explore[Nothing](&nothing, 3usize, start[..3usize], dining, always, true, 0usize, store[..], parent[..], table[..], scratch[..])
    if d_error != ok || d.verdict != .Deadlock || d.states != 14usize || d.transitions != 26usize || d.last != 12usize { ret 4i32 }
    if store[36usize] != 1u64 || store[37usize] != 1u64 || store[38usize] != 1u64 { ret 4i32 }
    let (dn, dn_error) = check.trace(parent[..], d.last, path[..])
    if dn_error != ok || dn != 4usize { ret 4i32 }
    ret 0i32
}

// The 4-bit counter: x -> x + 1 mod 16, except 11 -> 0; bits LSB first.
type Counter = struct { bad_value: u64 }

fn counter_init(c: *Counter, f: *sat.Cnf, x: []const i32) -> err {
    var i = 0usize
    while i < 4usize {
        if sat.clause1(f, 0i32 - x[i]) != ok { ret sat.TooSmall }
        i += 1usize
    }
    ret ok
}

fn counter_trans(c: *Counter, f: *sat.Cnf, x: []const i32, y: []i32) -> err {
    // wrap = x == 1011b.
    let (w1, e1) = sat.tseitin_and(f, x[0usize], x[1usize])
    let (w2, e2) = sat.tseitin_and(f, w1, 0i32 - x[2usize])
    let (wrap, e3) = sat.tseitin_and(f, w2, x[3usize])
    // inc = x + 1 by a half-adder chain.
    let (inc1, e4) = sat.tseitin_xor(f, x[1usize], x[0usize])
    let (c2, e5) = sat.tseitin_and(f, x[1usize], x[0usize])
    let (inc2, e6) = sat.tseitin_xor(f, x[2usize], c2)
    let (c3, e7) = sat.tseitin_and(f, x[2usize], c2)
    let (inc3, e8) = sat.tseitin_xor(f, x[3usize], c3)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret sat.TooSmall }
    let (y0, f0) = sat.tseitin_and(f, 0i32 - x[0usize], 0i32 - wrap)
    let (y1, f1) = sat.tseitin_and(f, inc1, 0i32 - wrap)
    let (y2, f2) = sat.tseitin_and(f, inc2, 0i32 - wrap)
    let (y3, f3) = sat.tseitin_and(f, inc3, 0i32 - wrap)
    if f0 != ok || f1 != ok || f2 != ok || f3 != ok { ret sat.TooSmall }
    y[0usize] = y0
    y[1usize] = y1
    y[2usize] = y2
    y[3usize] = y3
    ret ok
}

fn counter_bad(c: *Counter, f: *sat.Cnf, x: []const i32) -> (i32, err) {
    var lits: [4]i32 = zero
    var i = 0usize
    while i < 4usize {
        lits[i] = x[i]
        if ((c.bad_value >> u32(i)) & 1u64) == 0u64 { lits[i] = 0i32 - x[i] }
        i += 1usize
    }
    let (a, e1) = sat.tseitin_and(f, lits[0usize], lits[1usize])
    let (b, e2) = sat.tseitin_and(f, a, lits[2usize])
    let (o, e3) = sat.tseitin_and(f, b, lits[3usize])
    if e1 != ok || e2 != ok || e3 != ok { ret (0i32, sat.TooSmall) }
    ret (o, ok)
}

fn bmc_checks() -> i32 {
    var literals: [8192]i32 = zero
    var starts: [2048]usize = zero
    var step_literals: [8192]i32 = zero
    var step_starts: [2048]usize = zero
    var assignment: [1024]i8 = zero
    var trail: [1024]u32 = zero
    var level: [1024]u32 = zero
    var flipped: [1025]u8 = zero
    var learned: [8192]i32 = zero
    var learned_starts: [1024]usize = zero
    var frames: [80]i32 = zero
    var step_frames: [80]i32 = zero
    var values: [80]u8 = zero
    var s = check.solver(assignment[..], trail[..], level[..], flipped[..], learned[..], learned_starts[..])
    var c = Counter { bad_value: 11u64 }

    // 5: 11 is first reachable at step 11, the trace counts 0..11; not within 10.
    let (f0, f0_error) = sat.cnf(literals[..], starts[..], 0usize)
    if f0_error != ok { ret 5i32 }
    var f = f0
    let (v, depth, e) = check.bmc[Counter](&c, 4usize, counter_init, counter_trans, counter_bad, 15usize, &f, frames[..], &s, values[..])
    if e != ok || v != .Violated || depth != 11usize { ret 5i32 }
    var j = 0usize
    while j <= 11usize {
        let x = u64(values[j * 4usize]) | (u64(values[j * 4usize + 1usize]) << 1u32) | (u64(values[j * 4usize + 2usize]) << 2u32) | (u64(values[j * 4usize + 3usize]) << 3u32)
        if x != u64(j) { ret 5i32 }
        j += 1usize
    }
    let (f1, f1_error) = sat.cnf(literals[..], starts[..], 0usize)
    if f1_error != ok { ret 5i32 }
    f = f1
    let (v10, depth10, e10) = check.bmc[Counter](&c, 4usize, counter_init, counter_trans, counter_bad, 10usize, &f, frames[..], &s, values[..])
    if e10 != ok || v10 != .Bounded || depth10 != 10usize { ret 5i32 }

    // 6: 13 is never reached within 15 steps.
    c.bad_value = 13u64
    let (f2, f2_error) = sat.cnf(literals[..], starts[..], 0usize)
    if f2_error != ok { ret 6i32 }
    f = f2
    let (v13, depth13, e13) = check.bmc[Counter](&c, 4usize, counter_init, counter_trans, counter_bad, 15usize, &f, frames[..], &s, values[..])
    if e13 != ok || v13 != .Bounded || depth13 != 15usize { ret 6i32 }

    // 7: k-induction proves 13 unreachable at depth 2 (12 has no predecessor).
    let (f3, f3_error) = sat.cnf(literals[..], starts[..], 0usize)
    let (g3, g3_error) = sat.cnf(step_literals[..], step_starts[..], 0usize)
    if f3_error != ok || g3_error != ok { ret 7i32 }
    f = f3
    var g = g3
    let (p, pd, pe) = check.prove[Counter](&c, 4usize, counter_init, counter_trans, counter_bad, 5usize, &f, frames[..], &g, step_frames[..], &s, values[..])
    if pe != ok || p != .Safe || pd != 2usize { ret 7i32 }

    // 8: 11 is not inductive within 12; prove answers its counterexample at 11.
    c.bad_value = 11u64
    let (f4, f4_error) = sat.cnf(literals[..], starts[..], 0usize)
    let (g4, g4_error) = sat.cnf(step_literals[..], step_starts[..], 0usize)
    if f4_error != ok || g4_error != ok { ret 8i32 }
    f = f4
    g = g4
    let (q, qd, qe) = check.prove[Counter](&c, 4usize, counter_init, counter_trans, counter_bad, 12usize, &f, frames[..], &g, step_frames[..], &s, values[..])
    if qe != ok || q != .Violated || qd != 11usize { ret 8i32 }
    // Frames too small for k.
    let (f5, f5_error) = sat.cnf(literals[..], starts[..], 0usize)
    if f5_error != ok { ret 8i32 }
    f = f5
    let (_, _, small) = check.bmc[Counter](&c, 4usize, counter_init, counter_trans, counter_bad, 20usize, &f, frames[..], &s, values[..])
    if small != check.TooSmall { ret 8i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let first = explicit_checks()
    if first != 0i32 { os.exit(first) }
    let second = bmc_checks()
    if second != 0i32 { os.exit(second) }
    try io.print("algo check ok\n")
    ret ok
}
