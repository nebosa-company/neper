// Distributed locks simulated over caller state with caller clocks. Redlock:
// N `Instance` records each with its own clock skew, a call latency and an
// up flag; `redlock_acquire` visits every instance in order (a down one
// still costs its latency, as a timeout), a free or expired instance grants
// the caller's token for `ttl` of its own clock, and the lock is held when a
// majority granted it and `ttl - elapsed - drift` is still positive (the
// validity); otherwise the grants are released again. `redlock_release`
// frees the up instances holding the token. Leases: one `Lease` record,
// `lease_acquire` when free or expired, `lease_renew` by the holder before
// expiry, `lease_expired`, and `lease_due` for heartbeat renewal once a
// fraction `num / den` of the lease has run.

type Instance = struct { up: bool, skew: i64, latency: u64, holder: u64, expires: u64 }
type Lease = struct { holder: u64, granted: u64, expires: u64 }

// An elapsed-time addition. `false` means that the represented clock has no later
// value, so a caller must fail closed rather than wrap a deadline into the past.
fn time_add(start: u64, span: u64) -> (u64, bool) {
    if start > 18446744073709551615u64 - span { ret (0u64, false) }
    ret (start + span, true)
}

fn instance(skew: i64, latency: u64) -> Instance { ret Instance { up: true, skew: skew, latency: latency, holder: 0u64, expires: 0u64 } }

// `now` on the instance's own clock, with a result that tells a deadline writer
// whether a positive skew still fits. The negative branch handles `i64::MIN` too.
fn local_time_checked(inst: *const Instance, now: u64) -> (u64, bool) {
    if inst.skew < 0i64 {
        let back = u64(0i64 - (inst.skew + 1i64)) + 1u64
        if back > now { ret (0u64, true) }
        ret (now - back, true)
    }
    let (at, fits) = time_add(now, u64(inst.skew))
    ret (at, fits)
}

// `now` on the instance's own clock. A read-only clock saturates rather than
// trapping when a positive skew exceeds the representable time domain.
fn local_time(inst: *const Instance, now: u64) -> u64 {
    let (at, fits) = local_time_checked(inst, now)
    if !fits { ret 18446744073709551615u64 }
    ret at
}

fn instance_free(inst: *const Instance, now: u64) -> bool { ret inst.holder == 0u64 || inst.expires <= local_time(inst, now) }

// Answers (held, validity); `token` must be non-zero.
fn redlock_acquire(instances: []Instance, token: u64, now: u64, ttl: u64, drift: u64) -> (bool, u64) {
    var granted = 0usize
    var elapsed = 0u64
    var i = 0usize
    while i < instances.len {
        let (at, at_fits) = time_add(now, elapsed)
        if !at_fits {
            let _ = redlock_release(instances, token)
            ret (false, 0u64)
        }
        if instances[i].up {
            let (local_at, local_fits) = local_time_checked(&instances[i], at)
            if !local_fits {
                let _ = redlock_release(instances, token)
                ret (false, 0u64)
            }
            if instances[i].holder == 0u64 || instances[i].expires <= local_at {
                let (expires, expires_fits) = time_add(local_at, ttl)
                if !expires_fits {
                    let _ = redlock_release(instances, token)
                    ret (false, 0u64)
                }
                instances[i].holder = token
                instances[i].expires = expires
                granted += 1usize
            }
        }
        let (next_elapsed, elapsed_fits) = time_add(elapsed, instances[i].latency)
        if !elapsed_fits {
            let _ = redlock_release(instances, token)
            ret (false, 0u64)
        }
        elapsed = next_elapsed
        i += 1usize
    }
    let majority = instances.len / 2usize + 1usize
    if granted >= majority && elapsed < ttl {
        let remaining = ttl - elapsed
        if drift < remaining { ret (true, remaining - drift) }
    }
    let _ = redlock_release(instances, token)
    ret (false, 0u64)
}

// Free every up instance holding `token`; answers how many.
fn redlock_release(instances: []Instance, token: u64) -> usize {
    var n = 0usize
    var i = 0usize
    while i < instances.len {
        if instances[i].up && instances[i].holder == token {
            instances[i].holder = 0u64
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

// How many up instances hold `token` right now (for the fixture and for monitoring).
fn redlock_held(instances: []const Instance, token: u64, now: u64) -> usize {
    var n = 0usize
    var i = 0usize
    while i < instances.len {
        if instances[i].up && instances[i].holder == token && !instance_free(&instances[i], now) { n += 1usize }
        i += 1usize
    }
    ret n
}

fn lease() -> Lease { ret Lease { holder: 0u64, granted: 0u64, expires: 0u64 } }

fn lease_expired(l: *const Lease, now: u64) -> bool { ret l.holder == 0u64 || l.expires <= now }

// Take the lease when free or expired; answers whether it was granted.
fn lease_acquire(l: *Lease, holder: u64, now: u64, ttl: u64) -> bool {
    if !lease_expired(l, now) && l.holder != holder { ret false }
    let (expires, expires_fits) = time_add(now, ttl)
    if !expires_fits { ret false }
    l.holder = holder
    l.granted = now
    l.expires = expires
    ret true
}

// Extend the lease by `ttl` from `now`; only the holder can, and only before expiry.
fn lease_renew(l: *Lease, holder: u64, now: u64, ttl: u64) -> bool {
    if l.holder != holder || lease_expired(l, now) { ret false }
    let (expires, expires_fits) = time_add(now, ttl)
    if !expires_fits { ret false }
    l.granted = now
    l.expires = expires
    ret true
}

// Exact `left_num / left_den < right_num / right_den` without cross products.
// Continued-fraction comparison keeps every intermediate in `u64`.
fn fraction_less(left_num: u64, left_den: u64, right_num: u64, right_den: u64) -> bool {
    if left_den == 0u64 || right_den == 0u64 { ret false }
    var left_top = left_num
    var left_bottom = left_den
    var right_top = right_num
    var right_bottom = right_den
    var reverse_order = false
    while true {
        let left_whole = left_top / left_bottom
        let right_whole = right_top / right_bottom
        if left_whole != right_whole {
            if reverse_order { ret left_whole > right_whole }
            ret left_whole < right_whole
        }
        let left_rest = left_top % left_bottom
        let right_rest = right_top % right_bottom
        if left_rest == 0u64 || right_rest == 0u64 {
            if left_rest == 0u64 && right_rest == 0u64 { ret false }
            if reverse_order { ret right_rest == 0u64 }
            ret left_rest == 0u64
        }
        left_top = left_bottom
        left_bottom = left_rest
        right_top = right_bottom
        right_bottom = right_rest
        reverse_order = !reverse_order
    }
    ret false
}

// Should the holder send its heartbeat: has `num / den` of the lease run?
fn lease_due(l: *const Lease, now: u64, num: u64, den: u64) -> bool {
    if l.holder == 0u64 || lease_expired(l, now) || now < l.granted || l.expires <= l.granted || den == 0u64 { ret false }
    ret !fraction_less(now - l.granted, l.expires - l.granted, num, den)
}

// Redlock in one call: `redlock_acquire` under its planned name; answers (held, validity).
fn redlock(instances: []Instance, token: u64, now: u64, ttl: u64, drift: u64) -> (bool, u64) {
    let (held, validity) = redlock_acquire(instances, token, now, ttl, drift)
    ret (held, validity)
}
