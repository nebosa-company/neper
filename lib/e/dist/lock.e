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

fn instance(skew: i64, latency: u64) -> Instance { ret Instance { up: true, skew: skew, latency: latency, holder: 0u64, expires: 0u64 } }

// `now` on the instance's own clock.
fn local_time(inst: *const Instance, now: u64) -> u64 {
    if inst.skew < 0i64 {
        let back = u64(0i64 - inst.skew)
        if back > now { ret 0u64 }
        ret now - back
    }
    ret now + u64(inst.skew)
}

fn instance_free(inst: *const Instance, now: u64) -> bool { ret inst.holder == 0u64 || inst.expires <= local_time(inst, now) }

// Answers (held, validity); `token` must be non-zero.
fn redlock_acquire(instances: []Instance, token: u64, now: u64, ttl: u64, drift: u64) -> (bool, u64) {
    var granted = 0usize
    var elapsed = 0u64
    var i = 0usize
    while i < instances.len {
        let at = now + elapsed
        if instances[i].up && instance_free(&instances[i], at) {
            instances[i].holder = token
            instances[i].expires = local_time(&instances[i], at) + ttl
            granted += 1usize
        }
        elapsed += instances[i].latency
        i += 1usize
    }
    let majority = instances.len / 2usize + 1usize
    if granted >= majority && ttl > elapsed + drift { ret (true, ttl - elapsed - drift) }
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
    l.holder = holder
    l.granted = now
    l.expires = now + ttl
    ret true
}

// Extend the lease by `ttl` from `now`; only the holder can, and only before expiry.
fn lease_renew(l: *Lease, holder: u64, now: u64, ttl: u64) -> bool {
    if l.holder != holder || lease_expired(l, now) { ret false }
    l.granted = now
    l.expires = now + ttl
    ret true
}

// Should the holder send its heartbeat: has `num / den` of the lease run?
fn lease_due(l: *const Lease, now: u64, num: u64, den: u64) -> bool {
    if now < l.granted { ret false }
    ret (now - l.granted) * den >= (l.expires - l.granted) * num
}

// Redlock in one call: `redlock_acquire` under its planned name; answers (held, validity).
fn redlock(instances: []Instance, token: u64, now: u64, ttl: u64, drift: u64) -> (bool, u64) {
    let (held, validity) = redlock_acquire(instances, token, now, ttl, drift)
    ret (held, validity)
}
