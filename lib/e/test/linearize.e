// Linearizability checking (Wing-Gong / Knossos style) of a history of
// concurrent operations on one object. An `Event` is one call with its
// `call_time` and `return_time` (an op precedes another when it returned
// before the other was called; otherwise they are concurrent), its `op` and
// arguments, and the `result` the caller observed. `check` searches for a
// sequential order that respects precedence and the model by depth-first
// backtracking: at each point any not-yet-placed op that no other pending op
// precedes may go next if the model accepts its result from the current
// state. Models over one `i64` state: `Register` (`Read` answers the value,
// `Write` sets `arg`, `Cas` swaps `arg` for `arg2` and answers 1 or 0),
// `Counter` (`Write` adds `arg`, `Read` answers the total), `Set` over
// elements `0..63` as bits (`Write` inserts `arg`, `Read` answers 1 when
// `arg` is present). ponytail: no memo of visited (placed-set, state) pairs;
// exponential past a dozen concurrent ops, add a bitset cache then.

type Op = enum u8 { Read, Write, Cas }
type Model = enum u8 { Register, Counter, Set }
type Event = struct { call_time: u64, return_time: u64, op: Op, arg: i64, arg2: i64, result: i64 }
error TooSmall
error Invalid

// The state after `e` and whether the model accepts `e.result` from `state`.
fn step(model: Model, state: i64, e: Event) -> (i64, bool) {
    if e.op == .Cas {
        if state == e.arg { ret (e.arg2, e.result == 1i64) }
        ret (state, e.result == 0i64)
    }
    if model == .Counter {
        if e.op == .Write { ret (state +% e.arg, true) }
        ret (state, e.result == state)
    }
    if model == .Set {
        if e.arg < 0i64 || e.arg > 63i64 { ret (state, false) }
        let bit = 1i64 << u32(e.arg)
        if e.op == .Write { ret (state | bit, true) }
        var present = 0i64
        if state & bit != 0i64 { present = 1i64 }
        ret (state, e.result == present)
    }
    if e.op == .Write { ret (e.arg, true) }
    ret (state, e.result == state)
}

fn search(history: []const Event, model: Model, state: i64, placed: []u8, remaining: usize) -> bool {
    if remaining == 0usize { ret true }
    var earliest = 0u64
    var first = true
    var i = 0usize
    while i < history.len {
        if placed[i] == 0u8 && (first || history[i].return_time < earliest) {
            earliest = history[i].return_time
            first = false
        }
        i += 1usize
    }
    i = 0usize
    while i < history.len {
        if placed[i] == 0u8 && history[i].call_time <= earliest {
            let (next_state, accepted) = step(model, state, history[i])
            if accepted {
                placed[i] = 1u8
                if search(history, model, next_state, placed, remaining - 1usize) { ret true }
                placed[i] = 0u8
            }
        }
        i += 1usize
    }
    ret false
}

// Whether `history` is linearizable under `model` from `initial`; `placed`
// is scratch of at least `history.len` bytes.
fn check(history: []const Event, model: Model, initial: i64, placed: []u8) -> (bool, err) {
    if placed.len < history.len { ret (false, TooSmall) }
    var i = 0usize
    while i < history.len {
        if history[i].call_time > history[i].return_time { ret (false, Invalid) }
        placed[i] = 0u8
        i += 1usize
    }
    ret (search(history, model, initial, placed, history.len), ok)
}
