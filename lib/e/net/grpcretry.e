// gRPC retries and backoff (L164), the decisions of gRFC A6 as pure functions so that any transport can carry them out:
// the `retryPolicy` and `retryThrottling` of a service config read from JSON (`maxAttempts` at least 2 and clamped to 5;
// `initialBackoff`, `maxBackoff` and `backoffMultiplier` strictly positive; `retryableStatusCodes` non-empty, by name
// or number; `maxTokens` in (0, 1000] and a positive `tokenRatio` of at most three decimals), the backoff before the nth
// retry (a number of nanoseconds drawn from `0` to `min(initialBackoff * backoffMultiplier^(n-1), maxBackoff)` by a
// uniform `jitter` in [0, 1) the caller supplies, so a test can pin it), the server's `grpc-retry-pushback-ms` (a
// non-negative integer replaces the backoff, capped at 10^18 nanoseconds, anything else forbids a retry) and `decide`, which answers whether a failed
// attempt is retried and after how long.
//
// `decide` takes the attempts made so far, the status code, whether the response was committed (headers were received),
// the pushback header if any, the clock and the call's deadline (0 for none), and updates the throttle: a success adds
// `tokenRatio` (up to `maxTokens`), a retryable failure -- even one that is then not retried -- takes one token (down to
// zero), a non-retryable failure and a committed one change nothing; no retry is made while the tokens are at most
// half of `maxTokens`. The order of refusals is: committed, not retryable, bad pushback, attempts exhausted, throttled,
// deadline.
//
// Memory: nothing is allocated.

use e.algo.ir as ir
use e.algo.sync as sync
use e.fmt.json as json
use e.str

error Invalid

type Policy = struct { max_attempts: u32, initial_ns: u64, max_ns: u64, multiplier: f64, codes: u32 }
type Throttle = struct { max_tokens: f64, ratio: f64, tokens: f64 }
type Decision = struct { retry: bool, delay_ns: u64, reason: str }

fn attempts_cap() -> u32 { ret 5u32 }

// The status code of a canonical name, or -1.
fn code_from_name(name: str) -> i32 {
    if str.eq(name, "OK") { ret 0i32 }
    if str.eq(name, "CANCELLED") { ret 1i32 }
    if str.eq(name, "UNKNOWN") { ret 2i32 }
    if str.eq(name, "INVALID_ARGUMENT") { ret 3i32 }
    if str.eq(name, "DEADLINE_EXCEEDED") { ret 4i32 }
    if str.eq(name, "NOT_FOUND") { ret 5i32 }
    if str.eq(name, "ALREADY_EXISTS") { ret 6i32 }
    if str.eq(name, "PERMISSION_DENIED") { ret 7i32 }
    if str.eq(name, "RESOURCE_EXHAUSTED") { ret 8i32 }
    if str.eq(name, "FAILED_PRECONDITION") { ret 9i32 }
    if str.eq(name, "ABORTED") { ret 10i32 }
    if str.eq(name, "OUT_OF_RANGE") { ret 11i32 }
    if str.eq(name, "UNIMPLEMENTED") { ret 12i32 }
    if str.eq(name, "INTERNAL") { ret 13i32 }
    if str.eq(name, "UNAVAILABLE") { ret 14i32 }
    if str.eq(name, "DATA_LOSS") { ret 15i32 }
    if str.eq(name, "UNAUTHENTICATED") { ret 16i32 }
    ret -1i32
}

// A JSON duration (`"0.1s"`, `"2s"`, up to nine fractional digits) as nanoseconds.
fn parse_duration(text: str) -> (u64, err) {
    if text.len < 2usize || text[text.len - 1usize] != 115u8 { ret (0u64, Invalid) }
    let body = text[0usize..text.len - 1usize]
    var whole = 0u64
    var fraction = 0u64
    var fraction_digits = 0usize
    var seen_dot = false
    var whole_digits = 0usize
    var at = 0usize
    while at < body.len {
        let c = body[at]
        at += 1usize
        if c == 46u8 {
            if seen_dot { ret (0u64, Invalid) }
            seen_dot = true
            continue
        }
        if c < 48u8 || c > 57u8 { ret (0u64, Invalid) }
        if !seen_dot { whole_digits += 1usize }
        if seen_dot {
            if fraction_digits >= 9usize { ret (0u64, Invalid) }
            fraction = fraction * 10u64 + u64(c - 48u8)
            fraction_digits += 1usize
        } else {
            if whole > 922337203u64 { ret (0u64, Invalid) }
            whole = whole * 10u64 + u64(c - 48u8)
        }
    }
    if whole_digits == 0usize || (seen_dot && fraction_digits == 0usize) || whole > 9223372036u64 { ret (0u64, Invalid) }
    var scale = 1u64
    var k = fraction_digits
    while k < 9usize {
        scale = scale * 10u64
        k += 1usize
    }
    ret (whole * 1000000000u64 + fraction * scale, ok)
}

fn number_member(v: json.Value, key: str) -> (f64, bool) {
    let (x, found) = sync.get(v, key)
    if !found { ret (0.0f64, false) }
    switch x {
    case .Number as n:
        let (value, e) = json.number_f64(n)
        if e != ok { ret (0.0f64, false) }
        ret (value, true)
    default:
        ret (0.0f64, false)
    }
}

// The retry policy of a method config `{maxAttempts, initialBackoff, maxBackoff, backoffMultiplier,
// retryableStatusCodes}`; `Invalid` when a member is missing or out of range.
fn policy_parse(config: json.Value) -> (Policy, err) {
    var p: Policy = zero
    let (attempts, have_attempts) = number_member(config, "maxAttempts")
    if !have_attempts || attempts < 2.0f64 || attempts != f64(i64(attempts)) { ret (p, Invalid) }
    p.max_attempts = u32(attempts)
    if attempts > f64(attempts_cap()) { p.max_attempts = attempts_cap() }
    let (initial, have_initial) = sync.member_text(config, "initialBackoff")
    if !have_initial { ret (p, Invalid) }
    let (initial_ns, initial_error) = parse_duration(initial)
    if initial_error != ok || initial_ns == 0u64 { ret (p, Invalid) }
    p.initial_ns = initial_ns
    let (maximum, have_maximum) = sync.member_text(config, "maxBackoff")
    if !have_maximum { ret (p, Invalid) }
    let (maximum_ns, maximum_error) = parse_duration(maximum)
    if maximum_error != ok || maximum_ns == 0u64 { ret (p, Invalid) }
    p.max_ns = maximum_ns
    let (multiplier, have_multiplier) = number_member(config, "backoffMultiplier")
    if !have_multiplier || !(multiplier > 0.0f64) { ret (p, Invalid) }
    p.multiplier = multiplier
    let codes = sync.items(ir.value_of(config, "retryableStatusCodes"))
    if codes.len == 0usize { ret (p, Invalid) }
    var mask = 0u32
    var at = 0usize
    while at < codes.len {
        var code = -1i32
        let (name, is_name) = ir.string_of(codes[at])
        if is_name {
            code = code_from_name(name)
        } else {
            switch codes[at] {
            case .Number as n:
                let (value, e) = json.number_i64(n)
                if e == ok && value >= 0i64 && value <= 16i64 { code = i32(value) }
            default:
                code = -1i32
            }
        }
        if code < 0i32 { ret (p, Invalid) }
        mask = mask | (1u32 << u32(code))
        at += 1usize
    }
    p.codes = mask
    ret (p, ok)
}

// A token bucket from `{maxTokens, tokenRatio}`; it starts full. `Invalid` outside the ranges of the gRFC.
fn throttle_parse(config: json.Value) -> (Throttle, err) {
    var t: Throttle = zero
    let (maximum, have_maximum) = number_member(config, "maxTokens")
    if !have_maximum || !(maximum > 0.0f64) || maximum > 1000.0f64 || maximum != f64(i64(maximum)) { ret (t, Invalid) }
    let (ratio, have_ratio) = number_member(config, "tokenRatio")
    if !have_ratio || !(ratio > 0.0f64) { ret (t, Invalid) }
    // at most three decimals are kept
    let kept = f64(i64(ratio * 1000.0f64)) / 1000.0f64
    if !(kept > 0.0f64) { ret (t, Invalid) }
    t.max_tokens = maximum
    t.ratio = kept
    t.tokens = maximum
    ret (t, ok)
}

fn status_retryable(p: *const Policy, code: u32) -> bool {
    if code > 16u32 { ret false }
    ret (p.codes & (1u32 << code)) != 0u32
}

// The upper bound in nanoseconds of the wait before retry number `n` (1 for the first retry):
// `min(initialBackoff * backoffMultiplier^(n-1), maxBackoff)`.
fn backoff_cap_ns(p: *const Policy, n: u32) -> u64 {
    var cap = f64(p.initial_ns)
    let ceiling = f64(p.max_ns)
    var i = 1u32
    while i < n {
        if cap >= ceiling { break }
        cap = cap * p.multiplier
        i += 1u32
    }
    if cap > ceiling { cap = ceiling }
    ret u64(cap)
}

// The wait before retry `n` for a uniform `jitter` in [0, 1).
fn backoff_ns(p: *const Policy, n: u32, jitter: f64) -> u64 {
    var j = jitter
    if !(j >= 0.0f64) { j = 0.0f64 }
    if j >= 1.0f64 { j = 0.999999999f64 }
    ret u64(f64(backoff_cap_ns(p, n)) * j)
}

// `grpc-retry-pushback-ms` as nanoseconds: a non-negative decimal integer, else `Invalid` (no retry).
fn pushback_parse(text: str) -> (u64, err) {
    if text.len == 0usize || text.len > 15usize { ret (0u64, Invalid) }
    var v = 0u64
    var at = 0usize
    while at < text.len {
        if text[at] < 48u8 || text[at] > 57u8 { ret (0u64, Invalid) }
        v = v * 10u64 + u64(text[at] - 48u8)
        at += 1usize
    }
    if v > 1000000000000u64 { ret (1000000000000000000u64, ok) }
    ret (v * 1000000u64, ok)
}

fn throttle_allows(t: *const Throttle) -> bool { ret t.tokens > t.max_tokens / 2.0f64 }

fn throttle_success(t: *Throttle) {
    t.tokens = t.tokens + t.ratio
    if t.tokens > t.max_tokens { t.tokens = t.max_tokens }
}

fn throttle_failure(t: *Throttle) {
    t.tokens = t.tokens - 1.0f64
    if t.tokens < 0.0f64 { t.tokens = 0.0f64 }
}

fn refuse(reason: str) -> Decision { ret Decision { retry: false, delay_ns: 0u64, reason: reason } }

// Whether the attempt that just ended with `code` (after `attempts` attempts in all) is retried, and the wait before the
// next. `deadline_ns` is the absolute deadline on the clock `now_ns` reads, or 0.
fn decide(p: *const Policy, t: *Throttle, attempts: u32, code: u32, committed: bool, pushback: str, has_pushback: bool, jitter: f64, now_ns: u64, deadline_ns: u64) -> Decision {
    if code == 0u32 {
        throttle_success(t)
        ret refuse("ok")
    }
    if committed { ret refuse("committed") }
    if !status_retryable(p, code) { ret refuse("not-retryable") }
    throttle_failure(t)
    var delay = 0u64
    if has_pushback {
        let (pushed, push_error) = pushback_parse(pushback)
        if push_error != ok { ret refuse("pushback-refused") }
        delay = pushed
    }
    if attempts >= p.max_attempts { ret refuse("attempts-exhausted") }
    if !throttle_allows(t) { ret refuse("throttled") }
    if !has_pushback { delay = backoff_ns(p, attempts, jitter) }
    if deadline_ns > 0u64 && now_ns + delay >= deadline_ns { ret refuse("deadline") }
    ret Decision { retry: true, delay_ns: delay, reason: "retry" }
}
