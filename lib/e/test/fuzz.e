// In-process fuzzing: `run` feeds a target the corpus as given, then mutations of
// it until one fails, the run budget is spent or the deadline passes; `minimize`
// shrinks a failing input while it keeps failing. Everything is deterministic:
// mutation `i` of the run draws from a PCG seeded by the base entry's `seed` and
// `i`, so a failing input's `seed` and the corpus reproduce it. Corpus
// persistence, subprocess isolation and reproduction commands are the harness's
// (`neper test --fuzz`), as the fence says; nothing here touches a file.
//
// `Options`: `max_input` bounds every candidate (0 means 4096); `max_runs` bounds
// the target calls, corpus included (0 means no bound); `deadline` is a monotonic
// instant (`nanos` 0 means none). A run with neither bound is refused with
// `Limit`, since it could not end. An empty corpus, or an entry over `max_input`,
// is `InvalidCorpus`. `minimize` answers the smallest input it reached; when the
// deadline passes first it answers the best so far with `Limit`.
//
// Mutations: flip a bit, set a byte to a random or an interesting value, insert,
// delete, duplicate a range, splice in another corpus entry -- one to four per
// candidate. Minimization is delta debugging: drop halves, then quarters, down
// to single bytes, then simplify bytes toward zero, repeating until a pass
// changes nothing. ponytail: no coverage feedback (the compiler's instrumentation
// is not here yet); a candidate that reaches new regions would join the corpus.

use e.algo.rand
use e.mem
use e.test
use e.time

type Input = struct { bytes: []const u8, seed: u64 }
type Options = struct { max_input: usize, max_runs: u64, deadline: time.Instant }
type Result = struct { runs: u64, failing: Input, failed: bool }
type Target = fn(input: Input) -> err
error InvalidCorpus
error Limit

const DEFAULT_MAX_INPUT: usize = 4096usize

fn interesting(r: *rand.Pcg64) -> u8 {
    let values: [8]u8 = [8]u8{ 0, 1, 127, 128, 255, 254, 32, 10 }
    ret values[usize(rand.pcg64_bounded(r, 8u64))]
}

// One candidate from `base` into `buffer`; answers its length.
fn mutate(r: *rand.Pcg64, base: []const u8, corpus: []const Input, buffer: []u8, max_input: usize) -> usize {
    var len = base.len
    if len > max_input { len = max_input }
    mem.copy[u8](buffer[..len], base[..len])
    let rounds = 1usize + usize(rand.pcg64_bounded(r, 4u64))
    var round = 0usize
    while round < rounds {
        let op = rand.pcg64_bounded(r, 7u64)
        if op == 0u64 && len > 0usize {
            let at = usize(rand.pcg64_bounded(r, u64(len)))
            buffer[at] = buffer[at] ^ u8(1u64 << rand.pcg64_bounded(r, 8u64))
        } else if op == 1u64 && len > 0usize {
            let at = usize(rand.pcg64_bounded(r, u64(len)))
            buffer[at] = u8(rand.pcg64_bounded(r, 256u64))
        } else if op == 2u64 && len > 0usize {
            let at = usize(rand.pcg64_bounded(r, u64(len)))
            buffer[at] = interesting(r)
        } else if op == 3u64 && len < max_input {
            let at = usize(rand.pcg64_bounded(r, u64(len) + 1u64))
            var i = len
            while i > at {
                buffer[i] = buffer[i - 1usize]
                i -= 1usize
            }
            var value = u8(rand.pcg64_bounded(r, 256u64))
            if rand.pcg64_bounded(r, 2u64) == 0u64 { value = interesting(r) }
            buffer[at] = value
            len += 1usize
        } else if op == 4u64 && len > 0usize {
            let at = usize(rand.pcg64_bounded(r, u64(len)))
            var i = at
            while i + 1usize < len {
                buffer[i] = buffer[i + 1usize]
                i += 1usize
            }
            len -= 1usize
        } else if op == 5u64 && len > 0usize && len < max_input {
            // Duplicate a range after itself, as far as the bound allows.
            let from = usize(rand.pcg64_bounded(r, u64(len)))
            var count = 1usize + usize(rand.pcg64_bounded(r, u64(len - from)))
            if len + count > max_input { count = max_input - len }
            var i = len
            while i > from + count {
                buffer[i + count - 1usize] = buffer[i - 1usize]
                i -= 1usize
            }
            i = 0usize
            while i < count {
                buffer[from + count + i] = buffer[from + i]
                i += 1usize
            }
            len += count
        } else if op == 6u64 && corpus.len > 0usize {
            // Splice: the tail of another entry replaces this one's tail.
            let other = corpus[usize(rand.pcg64_bounded(r, u64(corpus.len)))].bytes
            if other.len > 0usize {
                let cut = usize(rand.pcg64_bounded(r, u64(len) + 1u64))
                let from = usize(rand.pcg64_bounded(r, u64(other.len)))
                var count = other.len - from
                if cut + count > max_input { count = max_input - cut }
                mem.copy[u8](buffer[cut..cut + count], other[from..from + count])
                len = cut + count
            }
        }
        round += 1usize
    }
    ret len
}

fn past(deadline: time.Instant) -> (bool, err) {
    if deadline.nanos == 0i64 { ret (false, ok) }
    let (now, now_error) = time.monotonic()
    if now_error != ok { ret (false, now_error) }
    ret (time.instant_cmp(now, deadline) >= 0i32, ok)
}

fn keep(a: *mem.Arena, bytes: []const u8, seed: u64) -> (Input, err) {
    let (copy, copy_error) = mem.alloc[u8](a, bytes.len)
    if copy_error != ok { ret (zero, copy_error) }
    mem.copy[u8](copy, bytes)
    ret (Input { bytes: copy, seed: seed }, ok)
}

fn run(a: *mem.Arena, target_fn: Target, corpus: []const Input, options: Options) -> (Result, err) {
    var max_input = options.max_input
    if max_input == 0usize { max_input = DEFAULT_MAX_INPUT }
    if corpus.len == 0usize { ret (zero, InvalidCorpus) }
    var i = 0usize
    while i < corpus.len {
        if corpus[i].bytes.len > max_input { ret (zero, InvalidCorpus) }
        i += 1usize
    }
    if options.max_runs == 0u64 && options.deadline.nanos == 0i64 { ret (zero, Limit) }
    var runs = 0u64
    // The corpus first, as given.
    i = 0usize
    while i < corpus.len {
        if options.max_runs > 0u64 && runs >= options.max_runs { break }
        runs += 1u64
        if target_fn(corpus[i]) != ok {
            let (failing, keep_error) = keep(a, corpus[i].bytes, corpus[i].seed)
            if keep_error != ok { ret (zero, keep_error) }
            ret (Result { runs: runs, failing: failing, failed: true }, ok)
        }
        i += 1usize
    }
    let (buffer, buffer_error) = mem.alloc[u8](a, max_input)
    if buffer_error != ok { ret (zero, buffer_error) }
    var index = 0u64
    while options.max_runs == 0u64 || runs < options.max_runs {
        let (over, past_error) = past(options.deadline)
        if past_error != ok { ret (zero, past_error) }
        if over { break }
        let base = corpus[usize(index % u64(corpus.len))]
        var r = rand.pcg64(base.seed, index)
        let len = mutate(&r, base.bytes, corpus, buffer, max_input)
        let candidate = Input { bytes: buffer[..len], seed: base.seed ^ (index *% 6364136223846793005u64) }
        runs += 1u64
        if target_fn(candidate) != ok {
            let (failing, keep_error) = keep(a, candidate.bytes, candidate.seed)
            if keep_error != ok { ret (zero, keep_error) }
            ret (Result { runs: runs, failing: failing, failed: true }, ok)
        }
        index += 1u64
    }
    ret (Result { runs: runs, failing: zero, failed: false }, ok)
}

// Whether `candidate` still fails; a passing candidate is not kept.
fn still_fails(target_fn: Target, candidate: []const u8, seed: u64) -> bool {
    ret target_fn(Input { bytes: candidate, seed: seed }) != ok
}

fn minimize(a: *mem.Arena, target_fn: Target, failing: Input, deadline: time.Instant) -> (Input, err) {
    let (best, best_error) = mem.alloc[u8](a, failing.bytes.len)
    if best_error != ok { ret (zero, best_error) }
    let (scratch, scratch_error) = mem.alloc[u8](a, failing.bytes.len)
    if scratch_error != ok { ret (zero, scratch_error) }
    mem.copy[u8](best, failing.bytes)
    var len = failing.bytes.len
    if !still_fails(target_fn, best[..len], failing.seed) { ret (Input { bytes: best[..len], seed: failing.seed }, ok) }
    var changed = true
    while changed && len > 0usize {
        changed = false
        // Drop a chunk: halves, then quarters, down to single bytes.
        var chunk = len / 2usize
        if chunk == 0usize { chunk = 1usize }
        while chunk >= 1usize {
            var at = 0usize
            while at < len {
                let (over, past_error) = past(deadline)
                if past_error != ok { ret (zero, past_error) }
                if over { ret (Input { bytes: best[..len], seed: failing.seed }, Limit) }
                var take = chunk
                if at + take > len { take = len - at }
                mem.copy[u8](scratch[..at], best[..at])
                mem.copy[u8](scratch[at..len - take], best[at + take..len])
                if still_fails(target_fn, scratch[..len - take], failing.seed) {
                    mem.copy[u8](best[..len - take], scratch[..len - take])
                    len -= take
                    changed = true
                } else {
                    at += take
                }
            }
            if chunk == 1usize { break }
            chunk = chunk / 2usize
        }
        // Simplify bytes: toward zero, then toward a printable.
        var at = 0usize
        while at < len {
            if best[at] != 0u8 {
                let (over, past_error) = past(deadline)
                if past_error != ok { ret (zero, past_error) }
                if over { ret (Input { bytes: best[..len], seed: failing.seed }, Limit) }
                mem.copy[u8](scratch[..len], best[..len])
                scratch[at] = 0u8
                if still_fails(target_fn, scratch[..len], failing.seed) {
                    best[at] = 0u8
                    changed = true
                } else if best[at] != 97u8 {
                    scratch[at] = 97u8
                    if still_fails(target_fn, scratch[..len], failing.seed) {
                        best[at] = 97u8
                        changed = true
                    }
                }
            }
            at += 1usize
        }
    }
    ret (Input { bytes: best[..len], seed: failing.seed }, ok)
}
