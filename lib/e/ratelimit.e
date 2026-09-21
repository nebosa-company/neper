// Rate limiters as pure state machines over the caller's clock: every
// `*_allow` takes `now` in the caller's ticks (nanoseconds, milliseconds,
// whatever `interval`/`width` are expressed in) and answers whether the
// request is admitted, updating the limiter. Nothing here reads a clock.
//
// `TokenBucket` refills `refill` tokens per `interval` ticks continuously up
// to `capacity` and admits a request of `cost` tokens when enough are held
// (bursts up to `capacity`). `LeakyBucket` is the meter form: `cost` units of
// water are poured in when they fit under `capacity`, and `leak` units drain
// per `interval` ticks (smooth output rate). `FixedWindow` counts requests
// in windows of `width` ticks aligned at `now / width` (2x bursts at a
// boundary are possible). `SlidingLog` keeps every admitted timestamp in a
// caller ring and admits when fewer than `limit` fall in the last `width`
// ticks. `SlidingWindow` weighs the previous window's count by the part of
// it still inside the last `width` ticks and adds the current count.
// Levels are held scaled by `interval` so all arithmetic is exact integers.

type TokenBucket = struct { capacity: u64, refill: u64, interval: u64, level: u64, last: u64 }
type LeakyBucket = struct { capacity: u64, leak: u64, interval: u64, water: u64, last: u64 }
type FixedWindow = struct { limit: u64, width: u64, window: u64, count: u64 }
type SlidingLog = struct { limit: u64, width: u64, stamps: []u64, head: usize, len: usize }
type SlidingWindow = struct { limit: u64, width: u64, window: u64, count: u64, previous: u64 }
error Invalid

// A bucket that starts full at `now`; `refill` tokens per `interval` ticks.
fn token_bucket(capacity: u64, refill: u64, interval: u64, now: u64) -> (TokenBucket, err) {
    if interval == 0u64 { ret (TokenBucket { capacity: 0u64, refill: 0u64, interval: 1u64, level: 0u64, last: 0u64 }, Invalid) }
    ret (TokenBucket { capacity: capacity, refill: refill, interval: interval, level: capacity *% interval, last: now }, ok)
}

// ponytail: `elapsed * rate` wraps past 2^64 (an idle limiter for ages at a huge
// rate) and then under-refills; clamp elapsed first if that clock is possible.
fn token_bucket_refill(b: *TokenBucket, now: u64) {
    if now > b.last {
        let gained = (now - b.last) *% b.refill
        let full = b.capacity *% b.interval
        if b.level +% gained < b.level || b.level +% gained > full { b.level = full } else { b.level += gained }
        b.last = now
    }
}

// Take `cost` tokens at `now` if held; a denied request takes nothing.
fn token_bucket_allow(b: *TokenBucket, now: u64, cost: u64) -> bool {
    token_bucket_refill(b, now)
    let need = cost *% b.interval
    if need > b.level { ret false }
    b.level -= need
    ret true
}

// Whole tokens available at `now` (after refilling).
fn token_bucket_tokens(b: *TokenBucket, now: u64) -> u64 {
    token_bucket_refill(b, now)
    ret b.level / b.interval
}

// An empty bucket at `now` holding `capacity` units and leaking `leak` per `interval` ticks.
fn leaky_bucket(capacity: u64, leak: u64, interval: u64, now: u64) -> (LeakyBucket, err) {
    if interval == 0u64 { ret (LeakyBucket { capacity: 0u64, leak: 0u64, interval: 1u64, water: 0u64, last: 0u64 }, Invalid) }
    ret (LeakyBucket { capacity: capacity, leak: leak, interval: interval, water: 0u64, last: now }, ok)
}

fn leaky_bucket_drain(b: *LeakyBucket, now: u64) {
    if now > b.last {
        let gone = (now - b.last) *% b.leak
        if gone >= b.water { b.water = 0u64 } else { b.water -= gone }
        b.last = now
    }
}

// Pour `cost` units at `now` if they fit under `capacity`.
fn leaky_bucket_allow(b: *LeakyBucket, now: u64, cost: u64) -> bool {
    leaky_bucket_drain(b, now)
    let add = cost *% b.interval
    if b.water +% add > b.capacity *% b.interval { ret false }
    b.water += add
    ret true
}

// Whole units of water at `now` (after draining).
fn leaky_bucket_level(b: *LeakyBucket, now: u64) -> u64 {
    leaky_bucket_drain(b, now)
    ret b.water / b.interval
}

// `limit` units per window of `width` ticks aligned at multiples of `width`.
fn fixed_window(limit: u64, width: u64) -> (FixedWindow, err) {
    if width == 0u64 { ret (FixedWindow { limit: 0u64, width: 1u64, window: 0u64, count: 0u64 }, Invalid) }
    ret (FixedWindow { limit: limit, width: width, window: 0u64, count: 0u64 }, ok)
}

fn fixed_window_allow(w: *FixedWindow, now: u64, cost: u64) -> bool {
    let index = now / w.width
    if index != w.window {
        w.window = index
        w.count = 0u64
    }
    if w.count +% cost > w.limit { ret false }
    w.count += cost
    ret true
}

// `limit` requests per trailing `width` ticks, each admitted one logged in
// `stamps` (a ring the caller sizes; a full ring denies, so size it >= limit).
fn sliding_log(limit: u64, width: u64, stamps: []u64) -> (SlidingLog, err) {
    if width == 0u64 || stamps.len == 0usize { ret (SlidingLog { limit: 0u64, width: 1u64, stamps: stamps, head: 0usize, len: 0usize }, Invalid) }
    ret (SlidingLog { limit: limit, width: width, stamps: stamps, head: 0usize, len: 0usize }, ok)
}

fn sliding_log_evict(l: *SlidingLog, now: u64) {
    while l.len > 0usize && l.stamps[l.head] +% l.width <= now {
        l.head = (l.head + 1usize) % l.stamps.len
        l.len -= 1usize
    }
}

fn sliding_log_allow(l: *SlidingLog, now: u64) -> bool {
    sliding_log_evict(l, now)
    if u64(l.len) >= l.limit || l.len >= l.stamps.len { ret false }
    l.stamps[(l.head + l.len) % l.stamps.len] = now
    l.len += 1usize
    ret true
}

// Requests logged in the last `width` ticks at `now`.
fn sliding_log_count(l: *SlidingLog, now: u64) -> u64 {
    sliding_log_evict(l, now)
    ret u64(l.len)
}

// `limit` units per trailing `width` ticks estimated from the current and
// previous fixed windows: previous * (unelapsed part of the window) / width + current.
fn sliding_window(limit: u64, width: u64) -> (SlidingWindow, err) {
    if width == 0u64 { ret (SlidingWindow { limit: 0u64, width: 1u64, window: 0u64, count: 0u64, previous: 0u64 }, Invalid) }
    ret (SlidingWindow { limit: limit, width: width, window: 0u64, count: 0u64, previous: 0u64 }, ok)
}

fn sliding_window_roll(w: *SlidingWindow, now: u64) {
    let index = now / w.width
    if index == w.window { ret }
    if index == w.window + 1u64 { w.previous = w.count } else { w.previous = 0u64 }
    w.window = index
    w.count = 0u64
}

// The weighted count at `now`.
fn sliding_window_count(w: *SlidingWindow, now: u64) -> u64 {
    sliding_window_roll(w, now)
    ret w.previous *% (w.width - now % w.width) / w.width + w.count
}

fn sliding_window_allow(w: *SlidingWindow, now: u64, cost: u64) -> bool {
    if sliding_window_count(w, now) +% cost > w.limit { ret false }
    w.count += cost
    ret true
}
