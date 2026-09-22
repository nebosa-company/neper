// Sliding-window aggregates in caller storage. `MonotonicQueue` answers
// the minimum (or maximum) of the last `width` pushed values in amortised
// constant time; `TwoStack[T]` aggregates any associative `combine` over a
// FIFO window by the two-stack trick (amortised constant time);
// `ExponentialHistogram` counts the ones among the last `width` bits to
// within a relative error of `1 / k` (Datar, Gionis, Indyk, Motwani).

type MonotonicQueue = struct { values: []i64, positions: []u64, head: usize, tail: usize, width: usize, pushed: u64, minimum: bool }
type TwoStack[T: type] = struct { front: []T, front_folds: []T, back: []T, front_count: usize, back_count: usize, identity: T }
type ExponentialHistogram = struct { sizes: []u64, stamps: []u64, count: usize, width: u64, k: usize, now: u64 }
error TooSmall
error Invalid

// A queue over `values`/`positions` (ring buffers of at least `width`).
fn monotonic_queue(values: []i64, positions: []u64, width: usize, minimum: bool) -> (MonotonicQueue, err) {
    if width == 0usize { ret (zero, Invalid) }
    if values.len < width || positions.len < width { ret (zero, TooSmall) }
    ret (MonotonicQueue { values: values, positions: positions, head: 0usize, tail: 0usize, width: width, pushed: 0u64, minimum: minimum }, ok)
}

fn dominated(q: *const MonotonicQueue, kept: i64, incoming: i64) -> bool {
    if q.minimum { ret kept >= incoming }
    ret kept <= incoming
}

// Push the next value of the stream.
fn monotonic_push(q: *MonotonicQueue, value: i64) {
    let cap = q.values.len
    // Drop kept values the newcomer makes irrelevant, from the back.
    while q.tail != q.head && dominated(q, q.values[(q.tail + cap - 1usize) % cap], value) { q.tail = (q.tail + cap - 1usize) % cap }
    q.values[q.tail] = value
    q.positions[q.tail] = q.pushed
    q.tail = (q.tail + 1usize) % cap
    q.pushed += 1u64
    // Expire the front when it has left the window.
    if q.positions[q.head] + u64(q.width) < q.pushed { q.head = (q.head + 1usize) % cap }
}

// The extreme of the current window (`Invalid` before the first push).
fn monotonic_extreme(q: *const MonotonicQueue) -> (i64, err) {
    if q.head == q.tail { ret (0i64, Invalid) }
    ret (q.values[q.head], ok)
}

// A window over caller stacks of one capacity each.
fn two_stack[T: type](front: []T, front_folds: []T, back: []T, identity: T) -> TwoStack[T] {
    ret TwoStack[T] { front: front, front_folds: front_folds, back: back, front_count: 0usize, back_count: 0usize, identity: identity }
}

fn two_stack_push[T: type](w: *TwoStack[T], value: T) -> err {
    if w.back_count >= w.back.len { ret TooSmall }
    w.back[w.back_count] = value
    w.back_count += 1usize
    ret ok
}

// Pop the oldest value; when the front stack is empty the back stack is
// flipped into it with running folds.
fn two_stack_pop[T: type, Ctx: type](w: *TwoStack[T], ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> (T, err) {
    if w.front_count == 0usize {
        if w.back_count == 0usize { ret (zero, Invalid) }
        if w.front.len < w.back_count || w.front_folds.len < w.back_count { ret (zero, TooSmall) }
        var fold = w.identity
        var i = w.back_count
        while i > 0usize {
            i -= 1usize
            let index = w.back_count - 1usize - i
            w.front[index] = w.back[i]
            fold = combine(ctx, w.back[i], fold)
            w.front_folds[index] = fold
        }
        w.front_count = w.back_count
        w.back_count = 0usize
    }
    w.front_count -= 1usize
    ret (w.front[w.front_count], ok)
}

// The fold over the whole window: the front's precomputed fold combined
// with a scan of the back.
fn two_stack_query[T: type, Ctx: type](w: *const TwoStack[T], ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> T {
    var result = w.identity
    if w.front_count > 0usize { result = w.front_folds[w.front_count - 1usize] }
    var i = 0usize
    while i < w.back_count {
        result = combine(ctx, result, w.back[i])
        i += 1usize
    }
    ret result
}

// A histogram over `sizes`/`stamps` (at least `(k + 1) * (log2(width) + 2)`
// buckets) for a window of `width` events and error parameter `k`.
fn exponential_histogram(sizes: []u64, stamps: []u64, width: u64, k: usize) -> (ExponentialHistogram, err) {
    if width == 0u64 || k == 0usize { ret (zero, Invalid) }
    var levels = 2usize
    var w = width
    while w > 1u64 {
        w = w >> 1u32
        levels += 1usize
    }
    if sizes.len < (k + 1usize) * levels || stamps.len < sizes.len { ret (zero, TooSmall) }
    ret (ExponentialHistogram { sizes: sizes, stamps: stamps, count: 0usize, width: width, k: k, now: 0u64 }, ok)
}

// Push one bit; buckets are kept newest first, and more than `k + 1`
// buckets of a size merge the two oldest into the next size.
fn histogram_push(h: *ExponentialHistogram, bit: bool) -> err {
    h.now += 1u64
    // Expire the oldest bucket when its timestamp left the window.
    if h.count > 0usize && h.stamps[h.count - 1usize] + h.width <= h.now { h.count -= 1usize }
    if !bit { ret ok }
    if h.count >= h.sizes.len { ret TooSmall }
    var i = h.count
    while i > 0usize {
        h.sizes[i] = h.sizes[i - 1usize]
        h.stamps[i] = h.stamps[i - 1usize]
        i -= 1usize
    }
    h.sizes[0usize] = 1u64
    h.stamps[0usize] = h.now
    h.count += 1usize
    // Cascade merges from the newest size upward.
    var size = 1u64
    var merging = true
    while merging {
        var same = 0usize
        var last = 0usize
        i = 0usize
        while i < h.count {
            if h.sizes[i] == size {
                same += 1usize
                last = i
            }
            i += 1usize
        }
        if same > h.k + 1usize {
            // The two oldest of this size are `last - 1` and `last`: merge into `last - 1`.
            h.sizes[last - 1usize] = 2u64 * size
            i = last
            while i + 1usize < h.count {
                h.sizes[i] = h.sizes[i + 1usize]
                h.stamps[i] = h.stamps[i + 1usize]
                i += 1usize
            }
            h.count -= 1usize
            size = 2u64 * size
        } else {
            merging = false
        }
    }
    ret ok
}

// The estimated count of ones in the window: every bucket's size but half
// of the oldest.
fn histogram_estimate(h: *const ExponentialHistogram) -> u64 {
    if h.count == 0usize { ret 0u64 }
    var total = 0u64
    var i = 0usize
    while i + 1usize < h.count {
        total += h.sizes[i]
        i += 1usize
    }
    ret total + h.sizes[h.count - 1usize] / 2u64
}

// The De-Amortized Banker's Aggregator (Tangwongsan, Hirzel, Schneider):
// a FIFO window over one ring of values and one of partial aggregates,
// any associative `combine`, worst-case constant work per push, pop and
// query. Positions are running counts; the ring holds the window. The
// four cursors bound the regions the paper calls L, R, A and B, whose
// aggregates are suffixes or prefixes of their region so that a query is
// the front's aggregate combined with the back's.
type Daba[T: type] = struct { values: []T, aggs: []T, head: usize, tail: usize, lp: usize, rp: usize, ap: usize, bp: usize, identity: T }

// A window over `values`/`aggs` (rings of one capacity, the largest window).
fn daba[T: type](values: []T, aggs: []T, identity: T) -> (Daba[T], err) {
    if values.len == 0usize || aggs.len < values.len { ret (zero, TooSmall) }
    ret (Daba[T] { values: values, aggs: aggs[..values.len], head: 0usize, tail: 0usize, lp: 0usize, rp: 0usize, ap: 0usize, bp: 0usize, identity: identity }, ok)
}

fn daba_len[T: type](d: *const Daba[T]) -> usize { ret d.tail - d.head }

fn daba_slot[T: type](d: *const Daba[T], position: usize) -> usize { ret position % d.values.len }

// The aggregate of the back region (`B`, prefixes from `bp`).
fn daba_back[T: type](d: *const Daba[T]) -> T {
    if d.bp == d.tail { ret d.identity }
    ret d.aggs[daba_slot[T](d, d.tail - 1usize)]
}

// The aggregate of everything before `bp` (a suffix stored at the front).
fn daba_alpha[T: type](d: *const Daba[T]) -> T {
    if d.bp == d.head { ret d.identity }
    ret d.aggs[daba_slot[T](d, d.head)]
}

fn daba_delta[T: type](d: *const Daba[T]) -> T {
    if d.ap == d.bp { ret d.identity }
    ret d.aggs[daba_slot[T](d, d.ap)]
}

fn daba_gamma[T: type](d: *const Daba[T]) -> T {
    if d.ap == d.rp { ret d.identity }
    ret d.aggs[daba_slot[T](d, d.ap - 1usize)]
}

// One unit of the deferred flip after every push or pop.
fn daba_step[T: type, Ctx: type](d: *Daba[T], ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) {
    if d.lp == d.bp {
        // Flip: the finished front becomes L, the back becomes R.
        d.lp = d.head
        d.rp = d.bp
        d.ap = d.tail
        d.bp = d.tail
    }
    if d.head == d.bp { ret }
    if d.ap != d.rp {
        let previous_delta = daba_delta[T](d)
        d.ap -= 1usize
        let slot = daba_slot[T](d, d.ap)
        d.aggs[slot] = combine(ctx, d.values[slot], previous_delta)
    }
    if d.lp != d.rp {
        let rest = combine(ctx, daba_gamma[T](d), daba_delta[T](d))
        let slot = daba_slot[T](d, d.lp)
        d.aggs[slot] = combine(ctx, d.aggs[slot], rest)
        d.lp += 1usize
    } else {
        d.lp += 1usize
        d.rp += 1usize
        d.ap += 1usize
    }
}

fn daba_push[T: type, Ctx: type](d: *Daba[T], value: T, ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> err {
    if d.tail - d.head >= d.values.len { ret TooSmall }
    let slot = daba_slot[T](d, d.tail)
    d.values[slot] = value
    d.aggs[slot] = combine(ctx, daba_back[T](d), value)
    d.tail += 1usize
    daba_step[T, Ctx](d, ctx, combine)
    ret ok
}

// Evicts the oldest value.
fn daba_pop[T: type, Ctx: type](d: *Daba[T], ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> (T, err) {
    if d.tail == d.head { ret (zero, Invalid) }
    let value = d.values[daba_slot[T](d, d.head)]
    d.head += 1usize
    daba_step[T, Ctx](d, ctx, combine)
    ret (value, ok)
}

// The fold over the window, oldest first; the identity when empty.
fn daba_query[T: type, Ctx: type](d: *const Daba[T], ctx: *Ctx, combine: fn(*Ctx, T, T) -> T) -> T {
    if d.tail == d.head { ret d.identity }
    ret combine(ctx, daba_alpha[T](d), daba_back[T](d))
}
