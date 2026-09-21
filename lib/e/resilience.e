// Fault-tolerance building blocks, all pure over the caller's clock and
// storage: `Breaker` is the Closed/Open/HalfOpen circuit breaker
// (`circuit_breaker`, `breaker_allow`, `breaker_success`, `breaker_failure`),
// `backoff` is exponential delay with full jitter (`backoff_decorrelated`,
// `backoff_exponential` are the other two shapes), `Heartbeat` is a table of
// nodes by last-seen time swept for the dead, `Shedder` admits by priority
// band against an EWMA load estimate, `Bulkhead` is a bounded permit pool
// per partition, `health` folds dependency probes into one `Health`, and
// `rollout_bucket` hashes a user into a stable bucket of ten thousand.
// Times are whatever unit the caller's `now: u64` counts in; no threads.

use e.algo.rand

type BreakerState = enum u8 { Closed, Open, HalfOpen }

// `failure_threshold` consecutive failures open the breaker for
// `open_timeout`; then `half_open_probes` successes in a row close it again
// and one failure re-opens it.
type Breaker = struct { state: BreakerState, failure_threshold: u32, open_timeout: u64, half_open_probes: u32, failures: u32, probes: u32, opened_at: u64 }

type Heartbeat = struct { ids: []u64, last_seen: []u64, count: usize }

// `thresholds[p]` is the load below which priority `p` is admitted (0 is
// the most important); a priority past the table uses its last entry.
type Shedder = struct { load: f64, alpha: f64, thresholds: []const f64 }

type Bulkhead = struct { limits: []const u32, used: []u32 }

// `Live`: every probe up. `Degraded`: only non-critical probes down (still
// ready). `NotReady`: a critical probe down. `Dead`: every probe down.
type Health = enum u8 { Live, Degraded, NotReady, Dead }

error TooSmall
error Invalid

fn circuit_breaker(failure_threshold: u32, open_timeout: u64, half_open_probes: u32) -> Breaker {
    ret Breaker { state: .Closed, failure_threshold: failure_threshold, open_timeout: open_timeout, half_open_probes: half_open_probes, failures: 0u32, probes: 0u32, opened_at: 0u64 }
}

// Whether a call may go out at `now`; an expired Open moves to HalfOpen.
fn breaker_allow(b: *Breaker, now: u64) -> bool {
    if b.state == .Open {
        if now -% b.opened_at >= b.open_timeout {
            b.state = .HalfOpen
            b.probes = 0u32
            ret true
        }
        ret false
    }
    ret true
}

fn breaker_success(b: *Breaker) {
    if b.state == .HalfOpen {
        b.probes += 1u32
        if b.probes >= b.half_open_probes {
            b.state = .Closed
            b.failures = 0u32
        }
    } else {
        b.failures = 0u32
    }
}

fn breaker_failure(b: *Breaker, now: u64) {
    if b.state == .HalfOpen {
        b.state = .Open
        b.opened_at = now
        ret
    }
    b.failures += 1u32
    if b.failures >= b.failure_threshold {
        b.state = .Open
        b.opened_at = now
    }
}

// `min(cap, base * 2^attempt)`, saturating at `cap`.
fn backoff_exponential(attempt: u32, base: u64, cap: u64) -> u64 {
    if attempt >= 64u32 { ret cap }
    let v = base << attempt
    if (v >> attempt) != base || v > cap { ret cap }
    ret v
}

// Full jitter: uniform in `[0, backoff_exponential(attempt, base, cap)]`.
fn backoff(attempt: u32, base: u64, cap: u64, rng: *rand.Pcg64) -> u64 {
    let ceiling = backoff_exponential(attempt, base, cap)
    if ceiling == 18446744073709551615u64 { ret rand.pcg64_next(rng) }
    ret rand.pcg64_bounded(rng, ceiling + 1u64)
}

// Decorrelated jitter: uniform in `[base, 3 * previous]`, clamped to `cap`;
// the answer is the next `previous`. Always within `[base, cap]`.
fn backoff_decorrelated(previous: u64, base: u64, cap: u64, rng: *rand.Pcg64) -> u64 {
    if base >= cap { ret cap }
    var low = previous
    if low < base { low = base }
    var high = low *% 3u64
    if high / 3u64 != low || high > cap { high = cap }
    ret low + rand.pcg64_bounded(rng, high - low + 1u64)
}

fn heartbeat(ids: []u64, last_seen: []u64) -> Heartbeat {
    ret Heartbeat { ids: ids, last_seen: last_seen, count: 0usize }
}

fn heartbeat_find(h: *const Heartbeat, id: u64) -> usize {
    var i = 0usize
    while i < h.count {
        if h.ids[i] == id { ret i }
        i += 1usize
    }
    ret h.count
}

// Record that `id` was seen at `now`; a new node joins the table.
fn heartbeat_observe(h: *Heartbeat, id: u64, now: u64) -> err {
    let i = heartbeat_find(h, id)
    if i == h.count {
        if i >= h.ids.len || i >= h.last_seen.len { ret TooSmall }
        h.ids[i] = id
        h.count += 1usize
    }
    h.last_seen[i] = now
    ret ok
}

fn heartbeat_alive(h: *const Heartbeat, id: u64, now: u64, timeout: u64) -> bool {
    let i = heartbeat_find(h, id)
    ret i < h.count && now -% h.last_seen[i] <= timeout
}

// Drop every node unseen for longer than `timeout` and answer them in
// `out_dead` (table order); answers the dead count.
// ponytail: linear table, a map when the cluster outgrows a few thousand nodes.
fn heartbeat_sweep(h: *Heartbeat, now: u64, timeout: u64, out_dead: []u64) -> (usize, err) {
    var dead = 0usize
    var keep = 0usize
    var i = 0usize
    while i < h.count {
        if now -% h.last_seen[i] > timeout {
            if dead >= out_dead.len { ret (dead, TooSmall) }
            out_dead[dead] = h.ids[i]
            dead += 1usize
        } else {
            h.ids[keep] = h.ids[i]
            h.last_seen[keep] = h.last_seen[i]
            keep += 1usize
        }
        i += 1usize
    }
    h.count = keep
    ret (dead, ok)
}

fn load_shed(alpha: f64, thresholds: []const f64) -> Shedder {
    ret Shedder { load: 0.0f64, alpha: alpha, thresholds: thresholds }
}

// Fold one load sample (0..1 or whatever the thresholds are in) into the EWMA.
fn load_shed_observe(s: *Shedder, sample: f64) {
    s.load = s.alpha * sample + (1.0f64 - s.alpha) * s.load
}

fn load_shed_admit(s: *const Shedder, priority: usize) -> bool {
    if s.thresholds.len == 0usize { ret true }
    var p = priority
    if p >= s.thresholds.len { p = s.thresholds.len - 1usize }
    ret s.load < s.thresholds[p]
}

// `used[p]` counts the permits out of `limits[p]`; `used` starts at zero.
fn bulkhead(limits: []const u32, used: []u32) -> Bulkhead {
    ret Bulkhead { limits: limits, used: used }
}

fn bulkhead_acquire(b: *Bulkhead, partition: usize) -> bool {
    if partition >= b.limits.len || partition >= b.used.len { ret false }
    if b.used[partition] >= b.limits[partition] { ret false }
    b.used[partition] += 1u32
    ret true
}

fn bulkhead_release(b: *Bulkhead, partition: usize) {
    if partition < b.used.len && b.used[partition] > 0u32 { b.used[partition] -= 1u32 }
}

fn bulkhead_available(b: *const Bulkhead, partition: usize) -> u32 {
    if partition >= b.limits.len || partition >= b.used.len { ret 0u32 }
    ret b.limits[partition] - b.used[partition]
}

// Fold probes (`up[i]`, `critical[i]`) into one state; no probes is `Live`.
fn health(up: []const bool, critical: []const bool) -> Health {
    var down = 0usize
    var critical_down = false
    var i = 0usize
    while i < up.len {
        if !up[i] {
            down += 1usize
            if i < critical.len && critical[i] { critical_down = true }
        }
        i += 1usize
    }
    if up.len > 0usize && down == up.len { ret .Dead }
    if critical_down { ret .NotReady }
    if down > 0usize { ret .Degraded }
    ret .Live
}

fn health_live(h: Health) -> bool { ret h != .Dead }
fn health_ready(h: Health) -> bool { ret h == .Live || h == .Degraded }

fn fnv_feed(h: u32, s: str) -> u32 {
    var hash = h
    var i = 0usize
    while i < s.len {
        hash = (hash ^ u32(s[i])) *% 16777619u32
        i += 1usize
    }
    ret hash
}

// FNV-1a over `salt`, `:`, `user_id`, reduced to a bucket in `0..9999`.
fn rollout_bucket(user_id: str, salt: str) -> u32 {
    let h = fnv_feed(fnv_feed(fnv_feed(2166136261u32, salt), ":"), user_id)
    ret h % 10000u32
}

// Whether `user_id` is inside the first `basis_points` (of 10000) of `salt`'s rollout.
fn rollout_enabled(user_id: str, salt: str, basis_points: u32) -> bool {
    ret rollout_bucket(user_id, salt) < basis_points
}
