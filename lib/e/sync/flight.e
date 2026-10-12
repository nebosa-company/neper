// Call de-duplication, Go's `singleflight`: concurrent callers that ask for the same key share
// one execution of the work. The first caller for a key (the leader) runs `f`; callers that
// arrive while it runs wait and receive the leader's result, value and error alike. A caller
// that arrives after it finished starts a new execution.
//
// The group is a fixed table of in-flight slots the caller provides, so the bound on distinct
// concurrent keys is explicit (`Full` when every slot is busy). Keys and the returned value are
// borrowed: the key must outlive the call, and the value is whatever `f` returned, so it must
// stay valid for the waiters (a static, or memory the caller's code owns). A `Group` must not be
// moved or copied once in use.

use e.sync

type Call = struct { key: str, used: bool, done: bool, forgotten: bool, waiters: u32, value: str, failure: err }
type Group = struct { lock: sync.Mutex, finished: sync.Condition, calls: []Call }
error Full

fn group(calls: []Call) -> Group {
    var i = 0usize
    while i < calls.len {
        var c: Call = zero
        calls[i] = c
        i += 1usize
    }
    ret Group { lock: sync.mutex(), finished: sync.condition(), calls: calls }
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// The in-flight slot for `key`, or calls.len when there is none (forgotten slots do not match).
fn find(g: *Group, key: str) -> usize {
    var i = 0usize
    while i < g.calls.len {
        if g.calls[i].used && !g.calls[i].forgotten && same(g.calls[i].key, key) { ret i }
        i += 1usize
    }
    ret g.calls.len
}

fn free_slot(g: *Group) -> usize {
    var i = 0usize
    while i < g.calls.len {
        if !g.calls[i].used { ret i }
        i += 1usize
    }
    ret g.calls.len
}

// Runs `f(ctx)` once for `key` however many callers ask at the same time. Returns the value,
// whether the result was shared with another caller, and the error (`Full` when no slot is free).
fn do(g: *Group, key: str, ctx: *void, f: fn(*void) -> (str, err)) -> (str, bool, err) {
    sync.mutex_lock(&g.lock)
    let found = find(g, key)
    if found < g.calls.len {
        g.calls[found].waiters += 1u32
        while !g.calls[found].done { sync.condition_wait(&g.finished, &g.lock) }
        let value = g.calls[found].value
        let failure = g.calls[found].failure
        g.calls[found].waiters -= 1u32
        if g.calls[found].waiters == 0u32 && g.calls[found].done { g.calls[found].used = false }
        sync.mutex_unlock(&g.lock)
        ret (value, true, failure)
    }
    let slot = free_slot(g)
    if slot >= g.calls.len {
        sync.mutex_unlock(&g.lock)
        ret ("", false, Full)
    }
    g.calls[slot].used = true
    g.calls[slot].done = false
    g.calls[slot].forgotten = false
    g.calls[slot].waiters = 0u32
    g.calls[slot].key = key
    sync.mutex_unlock(&g.lock)
    let (value, failure) = f(ctx)
    sync.mutex_lock(&g.lock)
    g.calls[slot].value = value
    g.calls[slot].failure = failure
    g.calls[slot].done = true
    let joint = g.calls[slot].waiters > 0u32
    sync.condition_broadcast(&g.finished)
    if g.calls[slot].waiters == 0u32 { g.calls[slot].used = false }
    sync.mutex_unlock(&g.lock)
    ret (value, joint, failure)
}

// Stops new callers from joining the in-flight execution of `key`; the next `do` for it runs
// `f` again, while current waiters still receive the first execution's result.
fn forget(g: *Group, key: str) {
    sync.mutex_lock(&g.lock)
    let found = find(g, key)
    if found < g.calls.len { g.calls[found].forgotten = true }
    sync.mutex_unlock(&g.lock)
}

// How many callers are waiting on the in-flight execution of `key` (0 when none).
fn waiting(g: *Group, key: str) -> u32 {
    sync.mutex_lock(&g.lock)
    let found = find(g, key)
    var n = 0u32
    if found < g.calls.len { n = g.calls[found].waiters }
    sync.mutex_unlock(&g.lock)
    ret n
}
