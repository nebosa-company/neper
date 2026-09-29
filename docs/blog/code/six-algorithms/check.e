use e.io
use e.mem
use e.algo.check as check

type Model = struct { unused: u8 }

// Two threads share a lock taken by "test, then set" -- two steps, not one atomic swap.
// State: pc of thread 0, pc of thread 1, the lock. pc 0 waits until the lock looks free,
// pc 1 sets it, pc 2 is the critical section and frees the lock on the way out.
fn step(m: *Model, s: []const u64, out: []u64) -> usize {
    var count = 0usize
    var t = 0usize
    while t < 2usize {
        if s[t] != 0u64 || s[2usize] == 0u64 {
            let n = out[count * 3usize..count * 3usize + 3usize]
            n[0usize] = s[0usize]
            n[1usize] = s[1usize]
            n[2usize] = s[2usize]
            if s[t] == 0u64 {
                n[t] = 1u64
            } else if s[t] == 1u64 {
                n[2usize] = 1u64
                n[t] = 2u64
            } else {
                n[2usize] = 0u64
                n[t] = 0u64
            }
            count += 1usize
        }
        t += 1usize
    }
    ret count
}

// Mutual exclusion: never both threads in the critical section.
fn exclusive(m: *Model, s: []const u64) -> bool { ret !(s[0usize] == 2u64 && s[1usize] == 2u64) }

fn main(a: *mem.Arena, args: []str) -> err {
    var model = Model { unused: 0u8 }
    var start: [3]u64 = zero
    var store: [300]u64 = zero
    var parent: [100]u32 = zero
    var table: [256]u32 = zero
    var scratch: [6]u64 = zero
    let (r, e) = check.explore[Model](&model, 3usize, start[..], step, exclusive, true, 0usize, store[..], parent[..], table[..], scratch[..])
    if e != ok { ret e }
    try io.printf["{} states, {} transitions\n"](r.states, r.transitions)
    if r.verdict == .Violated {
        var path: [16]u32 = zero
        let (n, trace_error) = check.trace(parent[..], r.last, path[..])
        if trace_error != ok { ret trace_error }
        var i = 0usize
        while i < n {
            let s = usize(path[i]) * 3usize
            try io.printf["  step {}: t0 pc={} t1 pc={} lock={}\n"](i, store[s], store[s + 1usize], store[s + 2usize])
            i += 1usize
        }
    }
    ret ok
}
