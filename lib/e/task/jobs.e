// Persistent background jobs with retries and cron triggers (L140), in the shape of Hangfire
// and Quartz. A `Queue` holds jobs in fixed capacity over an arena and is plain data: `save`
// writes the whole queue to one blob of an `e.store` (memory, filesystem or HTTP) behind a magic
// and an FNV-1a 64 checksum, `load` reads it back, so a worker that dies loses nothing but the
// time it held a lease.
//
// Delivery is at-least-once. `fetch` hands out the best due job (priority, then due time, then
// id) under a lease: the job is `Processing`, its `attempts` counts deliveries, and a lease that
// runs out before `complete` is a failed attempt ("lease expired") exactly as an explicit `fail`
// is. A failed job with attempts left is `Retry`, due after the policy's backoff; past
// `max_attempts` it is `Dead`: quarantined as a poison message, held with its last error until
// `requeue` puts it back with a fresh count. A `key` makes `enqueue` idempotent while the job it
// names is alive.
//
// Backoff (`Policy`): exponential (`base_ms` doubling, capped at `cap_ms`, plus a deterministic
// jitter below `jitter_ms`) or Hangfire's automatic-retry curve, `(n-1)^4 + 15 + (seed % 30) * n`
// seconds. The jitter is a function of the job id and the attempt, never a clock or a generator,
// so a replayed run retries at the same instants.
//
// Recurring schedules are cron expressions (six fields, seconds first, `e.time.cron`) with a
// fixed UTC offset. `tick(now)` turns every fire time up to `now` into jobs under the schedule's
// misfire policy (Quartz's): a fire within `grace_ms` of `now` is on time and always runs; older
// ones are misfires and are skipped, collapsed into one catch-up job, or all run (bounded by
// `MAX_CATCH_UP`). A fire's job carries the key `<schedule id>@<fire nanos>`, so a tick repeated
// after a restart enqueues nothing twice.
//
// Not here: a dashboard (app-side, D1785), threads (the caller's workers call `fetch`,
// `complete` and `fail`; the queue itself is single-threaded and the caller serializes access),
// reclaiming the arena bytes of purged jobs (a queue grows by its strings until it is rebuilt),
// time zones with daylight saving (a fixed offset only).

use e.algo.hash
use e.mem
use e.store
use e.str
use e.time
use e.time.cron as cron

const STATE_ENQUEUED: u8 = 0u8
const STATE_SCHEDULED: u8 = 1u8
const STATE_PROCESSING: u8 = 2u8
const STATE_RETRY: u8 = 3u8
const STATE_SUCCEEDED: u8 = 4u8
const STATE_DEAD: u8 = 5u8
const MISFIRE_SKIP: u8 = 0u8
const MISFIRE_ONE: u8 = 1u8
const MISFIRE_ALL: u8 = 2u8
const BACKOFF_EXPONENTIAL: u8 = 0u8
const BACKOFF_HANGFIRE: u8 = 1u8
const MS: i64 = 1000000i64
const MAX_CATCH_UP: usize = 1000usize

type Policy = struct { kind: u8, base_ms: i64, cap_ms: i64, jitter_ms: i64 }
type Job = struct { id: u64, name: str, payload: str, key: str, state: u8, attempts: u32, max_attempts: u32, priority: i32, run_at: i64, locked_until: i64, created: i64, last_error: str, recurring: u32 }
type Recurring = struct { id: str, expr: str, offset_minutes: i32, name: str, payload: str, max_attempts: u32, misfire: u8, grace_ms: i64, next_fire: i64, last_fire: i64, active: bool, sched: cron.Schedule }
type Queue = struct { a: *mem.Arena, jobs: []Job, n: usize, recs: []Recurring, nrec: usize, next_id: u64, policy: Policy }

error Full
error NotFound
error NotProcessing
error Invalid
error Corrupt

fn init(a: *mem.Arena, max_jobs: usize, max_recurring: usize, policy: Policy) -> (Queue, err) {
    var q: Queue = zero
    let (jobs, jobs_error) = mem.alloc[Job](a, max_jobs)
    if jobs_error != ok { ret (q, jobs_error) }
    let (recs, recs_error) = mem.alloc[Recurring](a, max_recurring)
    if recs_error != ok { ret (q, recs_error) }
    q.a = a
    q.jobs = jobs
    q.recs = recs
    q.next_id = 1u64
    q.policy = policy
    ret (q, ok)
}

fn keep(a: *mem.Arena, s: str) -> (str, err) {
    if s.len == 0usize { ret ("", ok) }
    let (buf, alloc_error) = mem.alloc[u8](a, s.len)
    if alloc_error != ok { ret ("", alloc_error) }
    var i = 0usize
    while i < s.len {
        buf[i] = s[i]
        i += 1usize
    }
    ret (buf[0..s.len], ok)
}

// The retry delay in milliseconds after delivery number `attempt` (one-based) of job `id`.
fn retry_delay(p: Policy, attempt: u32, id: u64) -> i64 {
    let seed = i64((id * 1000003u64 + u64(attempt) * 7919u64) % 1000000u64)
    var delay = 0i64
    if p.kind == BACKOFF_HANGFIRE {
        let k = i64(attempt) - 1i64
        let seconds = k * k * k * k + 15i64 + (seed % 30i64) * i64(attempt)
        delay = seconds * 1000i64
    } else {
        var steps = attempt
        if steps > 0u32 { steps -= 1u32 }
        if steps > 40u32 { steps = 40u32 }
        delay = p.base_ms * (1i64 << u64(steps))
        if p.jitter_ms > 0i64 { delay += seed % (p.jitter_ms + 1i64) }
    }
    if p.cap_ms > 0i64 && delay > p.cap_ms { delay = p.cap_ms }
    ret delay
}

fn find(q: *Queue, id: u64) -> (usize, bool) {
    var i = 0usize
    while i < q.n {
        if q.jobs[i].id == id { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn alive_with_key(q: *Queue, key: str) -> (u64, bool) {
    var i = 0usize
    while i < q.n {
        let j = q.jobs[i]
        if str.eq(j.key, key) && j.state != STATE_SUCCEEDED && j.state != STATE_DEAD { ret (j.id, true) }
        i += 1usize
    }
    ret (0u64, false)
}

// Adds a job due `delay_ms` after `now`; the id, which is an existing job's when `key` names a
// live one.
fn enqueue(q: *Queue, name: str, payload: str, now: i64, delay_ms: i64, max_attempts: u32, priority: i32, key: str) -> (u64, err) {
    if name.len == 0usize || max_attempts == 0u32 || delay_ms < 0i64 { ret (0u64, Invalid) }
    if key.len != 0usize {
        let (existing, found) = alive_with_key(q, key)
        if found { ret (existing, ok) }
    }
    if q.n >= q.jobs.len { ret (0u64, Full) }
    let (name_copy, e1) = keep(q.a, name)
    if e1 != ok { ret (0u64, e1) }
    let (payload_copy, e2) = keep(q.a, payload)
    if e2 != ok { ret (0u64, e2) }
    let (key_copy, e3) = keep(q.a, key)
    if e3 != ok { ret (0u64, e3) }
    var state = STATE_ENQUEUED
    if delay_ms > 0i64 { state = STATE_SCHEDULED }
    let id = q.next_id
    q.next_id += 1u64
    q.jobs[q.n] = Job { id: id, name: name_copy, payload: payload_copy, key: key_copy, state: state, attempts: 0u32, max_attempts: max_attempts, priority: priority, run_at: now + delay_ms * MS, locked_until: 0i64, created: now, last_error: "", recurring: 0u32 }
    q.n += 1usize
    ret (id, ok)
}

// Records a failed delivery of the job at index `at`: a retry with backoff, or quarantine.
fn fail_at(q: *Queue, at: usize, now: i64, message: str) -> (u8, err) {
    let (msg, keep_error) = keep(q.a, message)
    if keep_error != ok { ret (STATE_DEAD, keep_error) }
    q.jobs[at].last_error = msg
    q.jobs[at].locked_until = 0i64
    if q.jobs[at].attempts >= q.jobs[at].max_attempts {
        q.jobs[at].state = STATE_DEAD
        ret (STATE_DEAD, ok)
    }
    q.jobs[at].state = STATE_RETRY
    q.jobs[at].run_at = now + retry_delay(q.policy, q.jobs[at].attempts, q.jobs[at].id) * MS
    ret (STATE_RETRY, ok)
}

fn better(x: Job, y: Job) -> bool {
    if x.priority != y.priority { ret x.priority > y.priority }
    if x.run_at != y.run_at { ret x.run_at < y.run_at }
    ret x.id < y.id
}

// The next job to run at `now`, leased for `lease_ms`; `found` is false when none is due. Leases
// that ran out are failed attempts first.
fn fetch(q: *Queue, now: i64, lease_ms: i64) -> (Job, bool, err) {
    var i = 0usize
    while i < q.n {
        if q.jobs[i].state == STATE_PROCESSING && q.jobs[i].locked_until <= now {
            let (state, fail_error) = fail_at(q, i, now, "lease expired")
            if fail_error != ok { ret (zero, false, fail_error) }
        }
        i += 1usize
    }
    var best = 0usize
    var found = false
    i = 0usize
    while i < q.n {
        let j = q.jobs[i]
        if (j.state == STATE_ENQUEUED || j.state == STATE_SCHEDULED || j.state == STATE_RETRY) && j.run_at <= now {
            if !found || better(j, q.jobs[best]) {
                best = i
                found = true
            }
        }
        i += 1usize
    }
    if !found { ret (zero, false, ok) }
    q.jobs[best].state = STATE_PROCESSING
    q.jobs[best].attempts += 1u32
    q.jobs[best].locked_until = now + lease_ms * MS
    ret (q.jobs[best], true, ok)
}

fn complete(q: *Queue, id: u64) -> err {
    let (at, found) = find(q, id)
    if !found { ret NotFound }
    if q.jobs[at].state != STATE_PROCESSING { ret NotProcessing }
    q.jobs[at].state = STATE_SUCCEEDED
    q.jobs[at].locked_until = 0i64
    ret ok
}

// Reports a failed delivery; the job's new state.
fn fail(q: *Queue, id: u64, now: i64, message: str) -> (u8, err) {
    let (at, found) = find(q, id)
    if !found { ret (STATE_DEAD, NotFound) }
    if q.jobs[at].state != STATE_PROCESSING { ret (q.jobs[at].state, NotProcessing) }
    let (state, fail_error) = fail_at(q, at, now, message)
    ret (state, fail_error)
}

// Extends a running job's lease from `now`.
fn heartbeat(q: *Queue, id: u64, now: i64, lease_ms: i64) -> err {
    let (at, found) = find(q, id)
    if !found { ret NotFound }
    if q.jobs[at].state != STATE_PROCESSING { ret NotProcessing }
    q.jobs[at].locked_until = now + lease_ms * MS
    ret ok
}

// Puts a quarantined job back with a fresh attempt count, due at `now`.
fn requeue(q: *Queue, id: u64, now: i64) -> err {
    let (at, found) = find(q, id)
    if !found { ret NotFound }
    if q.jobs[at].state != STATE_DEAD { ret Invalid }
    q.jobs[at].state = STATE_ENQUEUED
    q.jobs[at].attempts = 0u32
    q.jobs[at].run_at = now
    ret ok
}

fn get(q: *Queue, id: u64) -> (Job, bool) {
    let (at, found) = find(q, id)
    if !found { ret (zero, false) }
    ret (q.jobs[at], true)
}

fn count(q: *Queue, state: u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < q.n {
        if q.jobs[i].state == state { n += 1usize }
        i += 1usize
    }
    ret n
}

// Drops finished jobs, making room; the number dropped.
fn purge(q: *Queue) -> usize {
    var kept = 0usize
    var i = 0usize
    while i < q.n {
        if q.jobs[i].state != STATE_SUCCEEDED {
            q.jobs[kept] = q.jobs[i]
            kept += 1usize
        }
        i += 1usize
    }
    let dropped = q.n - kept
    q.n = kept
    ret dropped
}

// ---- recurring schedules ---------------------------------------------------------------

fn find_recurring(q: *Queue, id: str) -> (usize, bool) {
    var i = 0usize
    while i < q.nrec {
        if str.eq(q.recs[i].id, id) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// Adds or replaces a recurring schedule; its first fire is the first instant after `now`.
fn recurring_set(q: *Queue, id: str, expr: str, offset_minutes: i32, name: str, payload: str, max_attempts: u32, misfire: u8, grace_ms: i64, now: i64) -> err {
    if id.len == 0usize || name.len == 0usize || max_attempts == 0u32 || misfire > MISFIRE_ALL || grace_ms < 0i64 { ret Invalid }
    let (sched, parse_error) = cron.parse(q.a, expr, offset_minutes)
    if parse_error != ok { ret Invalid }
    let (first, next_error) = cron.next(sched, time.Timestamp { nanos: now })
    if next_error != ok { ret Invalid }
    let (at0, found) = find_recurring(q, id)
    var at = at0
    if !found {
        if q.nrec >= q.recs.len { ret Full }
        at = q.nrec
        q.nrec += 1usize
    }
    let (id_copy, e1) = keep(q.a, id)
    if e1 != ok { ret e1 }
    let (expr_copy, e2) = keep(q.a, expr)
    if e2 != ok { ret e2 }
    let (name_copy, e3) = keep(q.a, name)
    if e3 != ok { ret e3 }
    let (payload_copy, e4) = keep(q.a, payload)
    if e4 != ok { ret e4 }
    q.recs[at] = Recurring { id: id_copy, expr: expr_copy, offset_minutes: offset_minutes, name: name_copy, payload: payload_copy, max_attempts: max_attempts, misfire: misfire, grace_ms: grace_ms, next_fire: first.nanos, last_fire: 0i64, active: true, sched: sched }
    ret ok
}

fn recurring_remove(q: *Queue, id: str) -> err {
    let (at, found) = find_recurring(q, id)
    if !found { ret NotFound }
    q.recs[at].active = false
    ret ok
}

// The fire key of one occurrence, `<schedule id>@<nanos>`.
fn fire_key(a: *mem.Arena, id: str, nanos: i64) -> (str, err) {
    let (b0, builder_error) = str.builder(a, 64usize)
    if builder_error != ok { ret ("", builder_error) }
    var b = b0
    var failure = str.push(&b, id)
    if failure == ok { failure = str.push(&b, "@") }
    if failure == ok { failure = str.push_i64(&b, nanos) }
    if failure != ok { ret ("", failure) }
    ret (str.done(&b), ok)
}

fn enqueue_fire(q: *Queue, r: Recurring, ri: usize, fire: i64, due: i64) -> (bool, err) {
    let (key, key_error) = fire_key(q.a, r.id, fire)
    if key_error != ok { ret (false, key_error) }
    // A key kept by any job, finished or not, names a fire already handled.
    var i = 0usize
    while i < q.n {
        if str.eq(q.jobs[i].key, key) { ret (false, ok) }
        i += 1usize
    }
    let (id, enqueue_error) = enqueue(q, r.name, r.payload, due, 0i64, r.max_attempts, 0i32, key)
    if enqueue_error != ok { ret (false, enqueue_error) }
    let (at, placed) = find(q, id)
    if placed { q.jobs[at].recurring = u32(ri + 1usize) }
    ret (true, ok)
}

// Turns the fire times up to `now` of every recurring schedule into jobs; how many were enqueued.
fn tick(q: *Queue, now: i64) -> (usize, err) {
    var total = 0usize
    var ri = 0usize
    while ri < q.nrec {
        let r = q.recs[ri]
        if r.active && r.next_fire <= now {
            var catch_fire = 0i64
            var t = r.next_fire
            var steps = 0usize
            var last = 0i64
            var catch_up = false
            var dropped = false
            while t <= now {
                steps += 1usize
                if steps > MAX_CATCH_UP {
                    dropped = true
                    break
                }
                last = t
                let late = now - t > r.grace_ms * MS
                if !late {
                    // on time: always runs
                    let (added, add_error) = enqueue_fire(q, r, ri, t, now)
                    if add_error != ok { ret (total, add_error) }
                    if added { total += 1usize }
                } else {
                    if r.misfire == MISFIRE_ALL {
                        let (added2, add_error2) = enqueue_fire(q, r, ri, t, now)
                        if add_error2 != ok { ret (total, add_error2) }
                        if added2 { total += 1usize }
                    } else {
                        if r.misfire == MISFIRE_ONE {
                            // remember the latest missed fire for the one catch-up job
                            catch_up = true
                            catch_fire = t
                        }
                    }
                }
                let (nxt, next_error) = cron.next(r.sched, time.Timestamp { nanos: t })
                if next_error != ok {
                    t = now + 1i64
                    break
                }
                t = nxt.nanos
            }
            if catch_up {
                let (added3, add_error3) = enqueue_fire(q, r, ri, catch_fire, now)
                if add_error3 != ok { ret (total, add_error3) }
                if added3 { total += 1usize }
            }
            if dropped {
                // past the bound: resume from the first fire after `now`
                var probe = last
                while probe <= now {
                    let (n2, e2) = cron.next(r.sched, time.Timestamp { nanos: probe })
                    if e2 != ok { break }
                    probe = n2.nanos
                }
                t = probe
            }
            q.recs[ri].next_fire = t
            q.recs[ri].last_fire = last
        }
        ri += 1usize
    }
    ret (total, ok)
}

// ---- persistence ------------------------------------------------------------------------

fn put_u64(b: *str.Builder, v: u64) -> err {
    var i = 0usize
    while i < 8usize {
        try str.push_byte(b, u8((v >> u64(i * 8usize)) & 255u64))
        i += 1usize
    }
    ret ok
}

fn put_i64(b: *str.Builder, v: i64) -> err { ret put_u64(b, mem.bitcast[u64](v)) }

fn put_str(b: *str.Builder, s: str) -> err {
    try put_u64(b, u64(s.len))
    ret str.push(b, s)
}

type Reader = struct { data: str, pos: usize, bad: bool }

fn get_u64(r: *Reader) -> u64 {
    if r.pos + 8usize > r.data.len {
        r.bad = true
        ret 0u64
    }
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        v |= u64(r.data[r.pos + i]) << u64(i * 8usize)
        i += 1usize
    }
    r.pos += 8usize
    ret v
}

fn get_i64(r: *Reader) -> i64 { ret mem.bitcast[i64](get_u64(r)) }

fn get_str(a: *mem.Arena, r: *Reader) -> (str, err) {
    let n = get_u64(r)
    if r.bad || n > u64(r.data.len - r.pos) {
        r.bad = true
        ret ("", Corrupt)
    }
    let start = r.pos
    r.pos += usize(n)
    let (copy, copy_error) = keep(a, r.data[start..r.pos])
    ret (copy, copy_error)
}

// Writes the queue to `key` of the store.
fn save(q: *Queue, s: *store.Store, a: *mem.Arena, key: str) -> err {
    let (b0, builder_error) = str.builder(a, 1024usize)
    if builder_error != ok { ret builder_error }
    var b = b0
    try str.push(&b, "NJQ1")
    try put_u64(&b, q.next_id)
    try str.push_byte(&b, q.policy.kind)
    try put_i64(&b, q.policy.base_ms)
    try put_i64(&b, q.policy.cap_ms)
    try put_i64(&b, q.policy.jitter_ms)
    try put_u64(&b, u64(q.n))
    var i = 0usize
    while i < q.n {
        let j = q.jobs[i]
        try put_u64(&b, j.id)
        try put_str(&b, j.name)
        try put_str(&b, j.payload)
        try put_str(&b, j.key)
        try str.push_byte(&b, j.state)
        try put_u64(&b, u64(j.attempts))
        try put_u64(&b, u64(j.max_attempts))
        try put_i64(&b, i64(j.priority))
        try put_i64(&b, j.run_at)
        try put_i64(&b, j.locked_until)
        try put_i64(&b, j.created)
        try put_str(&b, j.last_error)
        try put_u64(&b, u64(j.recurring))
        i += 1usize
    }
    try put_u64(&b, u64(q.nrec))
    i = 0usize
    while i < q.nrec {
        let r = q.recs[i]
        try put_str(&b, r.id)
        try put_str(&b, r.expr)
        try put_i64(&b, i64(r.offset_minutes))
        try put_str(&b, r.name)
        try put_str(&b, r.payload)
        try put_u64(&b, u64(r.max_attempts))
        try str.push_byte(&b, r.misfire)
        try put_i64(&b, r.grace_ms)
        try put_i64(&b, r.next_fire)
        try put_i64(&b, r.last_fire)
        var flag = 0u8
        if r.active { flag = 1u8 }
        try str.push_byte(&b, flag)
        i += 1usize
    }
    let body = str.done(&b)
    // The checksum goes after the body in a second builder, so the body stays contiguous.
    let (c0, c_error) = str.builder(a, body.len + 16usize)
    if c_error != ok { ret c_error }
    var c = c0
    try str.push(&c, body)
    try put_u64(&c, hash.fnv1a64(body))
    let blob = str.done(&c)
    ret store.put(s, a, key, blob)
}

fn get_byte(r: *Reader) -> u8 {
    if r.pos >= r.data.len {
        r.bad = true
        ret 0u8
    }
    let v = r.data[r.pos]
    r.pos += 1usize
    ret v
}

// Reads a queue back from `key`; its capacities are the arguments', which must hold what was saved.
fn load(a: *mem.Arena, s: *store.Store, key: str, max_jobs: usize, max_recurring: usize) -> (Queue, err) {
    var q: Queue = zero
    let (data, get_error) = store.get(s, a, key, 0usize)
    if get_error != ok { ret (q, get_error) }
    if data.len < 12usize { ret (q, Corrupt) }
    let body = data[0..data.len - 8usize]
    var tail = Reader { data: data, pos: data.len - 8usize, bad: false }
    if get_u64(&tail) != hash.fnv1a64(body) { ret (q, Corrupt) }
    if !str.eq(body[0..4], "NJQ1") { ret (q, Corrupt) }
    var r = Reader { data: body, pos: 4usize, bad: false }
    let next_id = get_u64(&r)
    let kind = get_byte(&r)
    let base_ms = get_i64(&r)
    let cap_ms = get_i64(&r)
    let jitter_ms = get_i64(&r)
    let (q0, init_error) = init(a, max_jobs, max_recurring, Policy { kind: kind, base_ms: base_ms, cap_ms: cap_ms, jitter_ms: jitter_ms })
    if init_error != ok { ret (q, init_error) }
    q = q0
    q.next_id = next_id
    let njobs = get_u64(&r)
    if r.bad || njobs > u64(max_jobs) { ret (q, Corrupt) }
    var i = 0usize
    while i < usize(njobs) {
        var j: Job = zero
        j.id = get_u64(&r)
        let (name, e1) = get_str(a, &r)
        let (payload, e2) = get_str(a, &r)
        let (jkey, e3) = get_str(a, &r)
        if e1 != ok || e2 != ok || e3 != ok { ret (q, Corrupt) }
        j.name = name
        j.payload = payload
        j.key = jkey
        j.state = get_byte(&r)
        j.attempts = u32(get_u64(&r))
        j.max_attempts = u32(get_u64(&r))
        j.priority = i32(get_i64(&r))
        j.run_at = get_i64(&r)
        j.locked_until = get_i64(&r)
        j.created = get_i64(&r)
        let (last_error, e4) = get_str(a, &r)
        if e4 != ok { ret (q, Corrupt) }
        j.last_error = last_error
        j.recurring = u32(get_u64(&r))
        if r.bad || j.state > STATE_DEAD { ret (q, Corrupt) }
        q.jobs[i] = j
        i += 1usize
    }
    q.n = usize(njobs)
    let nrec = get_u64(&r)
    if r.bad || nrec > u64(max_recurring) { ret (q, Corrupt) }
    i = 0usize
    while i < usize(nrec) {
        var rec: Recurring = zero
        let (id, f1) = get_str(a, &r)
        let (expr, f2) = get_str(a, &r)
        if f1 != ok || f2 != ok { ret (q, Corrupt) }
        rec.id = id
        rec.expr = expr
        rec.offset_minutes = i32(get_i64(&r))
        let (name, f3) = get_str(a, &r)
        let (payload, f4) = get_str(a, &r)
        if f3 != ok || f4 != ok { ret (q, Corrupt) }
        rec.name = name
        rec.payload = payload
        rec.max_attempts = u32(get_u64(&r))
        rec.misfire = get_byte(&r)
        rec.grace_ms = get_i64(&r)
        rec.next_fire = get_i64(&r)
        rec.last_fire = get_i64(&r)
        rec.active = get_byte(&r) != 0u8
        if r.bad { ret (q, Corrupt) }
        let (sched, parse_error) = cron.parse(a, rec.expr, rec.offset_minutes)
        if parse_error != ok { ret (q, Corrupt) }
        rec.sched = sched
        q.recs[i] = rec
        i += 1usize
    }
    q.nrec = usize(nrec)
    if r.bad || r.pos != body.len { ret (q, Corrupt) }
    ret (q, ok)
}
