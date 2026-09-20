// `e.test.fuzz`: a target that fails on the bytes `BA` in a row is found from a
// corpus that never contains them, twice with the same result (determinism);
// the failing input minimizes to exactly `BA`; a target that never fails spends
// the run budget; a deadline already past stops after the corpus; an empty
// corpus, an entry past `max_input` and a run with no bound are refused; a
// corpus entry that fails is reported as is; minimizing a passing input answers
// it unchanged.

use e.io
use e.mem
use e.os
use e.test.fuzz
use e.time

error Crash

fn has_ba(input: fuzz.Input) -> err {
    var i = 1usize
    while i < input.bytes.len {
        if input.bytes[i - 1usize] == 66u8 && input.bytes[i] == 65u8 { ret Crash }
        i += 1usize
    }
    ret ok
}

fn never(input: fuzz.Input) -> err {
    ret ok
}

fn long_fails(input: fuzz.Input) -> err {
    if input.bytes.len > 3usize { ret Crash }
    ret ok
}

fn options(max_input: usize, max_runs: u64, deadline: i64) -> fuzz.Options {
    ret fuzz.Options { max_input: max_input, max_runs: max_runs, deadline: time.Instant { nanos: deadline } }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let corpus: [3]fuzz.Input = [3]fuzz.Input{ fuzz.Input { bytes: "AB", seed: 1u64 }, fuzz.Input { bytes: "B", seed: 2u64 }, fuzz.Input { bytes: "hello", seed: 3u64 } }
    let (found, found_error) = fuzz.run(a, has_ba, corpus[0..], options(16usize, 200000u64, 0i64))
    if found_error != ok || !found.failed || found.runs == 0u64 || found.failing.bytes.len > 16usize { os.exit(1i32) }
    if has_ba(found.failing) != Crash { os.exit(2i32) }
    let (again, again_error) = fuzz.run(a, has_ba, corpus[0..], options(16usize, 200000u64, 0i64))
    if again_error != ok || again.runs != found.runs || again.failing.bytes.len != found.failing.bytes.len || again.failing.seed != found.failing.seed { os.exit(3i32) }
    var i = 0usize
    while i < found.failing.bytes.len {
        if again.failing.bytes[i] != found.failing.bytes[i] { os.exit(4i32) }
        i += 1usize
    }

    // Minimization lands on the two bytes and nothing else.
    let (small, small_error) = fuzz.minimize(a, has_ba, found.failing, time.Instant { nanos: 0i64 })
    if small_error != ok || small.bytes.len != 2usize || small.bytes[0] != 66u8 || small.bytes[1] != 65u8 || small.seed != found.failing.seed { os.exit(5i32) }
    // A length-triggered failure minimizes to the shortest failing length with zero bytes.
    let (short, short_error) = fuzz.minimize(a, long_fails, fuzz.Input { bytes: "abcdefgh", seed: 9u64 }, time.Instant { nanos: 0i64 })
    if short_error != ok || short.bytes.len != 4usize || short.bytes[0] != 0u8 || short.bytes[3] != 0u8 { os.exit(6i32) }
    // A passing input is answered unchanged.
    let (same, same_error) = fuzz.minimize(a, has_ba, fuzz.Input { bytes: "abc", seed: 4u64 }, time.Instant { nanos: 0i64 })
    if same_error != ok || same.bytes.len != 3usize || same.bytes[1] != 98u8 { os.exit(7i32) }

    // Budgets: a target that never fails spends exactly the run budget; a deadline
    // already past stops after the corpus pass.
    let (spent, spent_error) = fuzz.run(a, never, corpus[0..], options(16usize, 50u64, 0i64))
    if spent_error != ok || spent.failed || spent.runs != 50u64 { os.exit(8i32) }
    let (now, now_error) = time.monotonic()
    if now_error != ok { os.exit(9i32) }
    let (timed, timed_error) = fuzz.run(a, never, corpus[0..], options(16usize, 0u64, now.nanos - 1i64))
    if timed_error != ok || timed.failed || timed.runs != 3u64 { os.exit(10i32) }
    // A corpus entry that fails is reported as given, on the first run.
    let bad: [2]fuzz.Input = [2]fuzz.Input{ fuzz.Input { bytes: "x", seed: 1u64 }, fuzz.Input { bytes: "xBAx", seed: 7u64 } }
    let (direct, direct_error) = fuzz.run(a, has_ba, bad[0..], options(16usize, 10u64, 0i64))
    if direct_error != ok || !direct.failed || direct.runs != 2u64 || direct.failing.bytes.len != 4usize || direct.failing.seed != 7u64 { os.exit(11i32) }

    // Refusals.
    let (_, empty_error) = fuzz.run(a, has_ba, corpus[0usize..0usize], options(16usize, 10u64, 0i64))
    if empty_error != fuzz.InvalidCorpus { os.exit(12i32) }
    let (_, oversized_error) = fuzz.run(a, has_ba, corpus[0..], options(3usize, 10u64, 0i64))
    if oversized_error != fuzz.InvalidCorpus { os.exit(13i32) }
    let (_, unbounded_error) = fuzz.run(a, has_ba, corpus[0..], options(16usize, 0u64, 0i64))
    if unbounded_error != fuzz.Limit { os.exit(14i32) }
    // Every candidate honours max_input.
    let (bounded, bounded_error) = fuzz.run(a, long_fails, corpus[0usize..2usize], options(3usize, 500u64, 0i64))
    if bounded_error != ok || bounded.failed { os.exit(15i32) }

    try io.print("test fuzz ok\n")
    ret ok
}
