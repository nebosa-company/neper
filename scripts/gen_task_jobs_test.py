"""Generates the vector functions of tests/selfhost/fixtures/link/task_jobs (L140, D2762).

Oracles: croniter (the Python cron library) for every fire time a recurring schedule must reach,
with Neper's six-field expression (seconds first) rewritten to croniter's order (seconds last);
an independent Python statement of the backoff formulas and of the misfire policies.

    PYTHONPATH=<dir with croniter> python scripts/gen_task_jobs_test.py

rewrites the region between `// BEGIN generated` and `// END generated` in the fixture.
"""
import datetime
import sys
from pathlib import Path

import croniter

FIXTURE = Path(__file__).resolve().parent.parent / 'tests/selfhost/fixtures/link/task_jobs/src/main.e'
NS = 10 ** 9
MS = 10 ** 6


def utc(y, mo, d, h=0, mi=0, s=0):
    return int(datetime.datetime(y, mo, d, h, mi, s, tzinfo=datetime.timezone.utc).timestamp())


def fires(expr, offset_min, start, count):
    s, mi, h, dom, mon, dow = expr.split()
    ci = '%s %s %s %s %s %s' % (mi, h, dom, mon, dow, s)
    tz = datetime.timezone(datetime.timedelta(minutes=offset_min))
    it = croniter.croniter(ci, datetime.datetime.fromtimestamp(start, tz))
    return [int(it.get_next(datetime.datetime).timestamp()) for _ in range(count)]


def delay_ms(kind, base, cap, jitter, attempt, jid):
    seed = (jid * 1000003 + attempt * 7919) % 1000000
    if kind == 'hangfire':
        k = attempt - 1
        d = (k ** 4 + 15 + (seed % 30) * attempt) * 1000
    else:
        steps = min(max(attempt - 1, 0), 40)
        d = base * (1 << steps)
        if jitter > 0:
            d += seed % (jitter + 1)
    if cap > 0 and d > cap:
        d = cap
    return d


def main():
    out = []
    code = [0]

    def nxt():
        code[0] += 1
        return code[0]

    # --- backoff -----------------------------------------------------------------------
    out.append('fn gen_backoff() -> i32 {')
    out.append('    let exp = jobs.Policy { kind: jobs.BACKOFF_EXPONENTIAL, base_ms: 1000i64, cap_ms: 60000i64, jitter_ms: 0i64 }')
    out.append('    let jit = jobs.Policy { kind: jobs.BACKOFF_EXPONENTIAL, base_ms: 500i64, cap_ms: 0i64, jitter_ms: 250i64 }')
    out.append('    let hf = jobs.Policy { kind: jobs.BACKOFF_HANGFIRE, base_ms: 0i64, cap_ms: 0i64, jitter_ms: 0i64 }')
    for attempt in range(1, 9):
        d = delay_ms('exp', 1000, 60000, 0, attempt, 1)
        out.append('    if jobs.retry_delay(exp, %du32, 1u64) != %di64 { ret %di32 }' % (attempt, d, 100 + nxt()))
    for jid in (3, 41, 977):
        for attempt in (1, 2, 5, 9):
            d = delay_ms('exp', 500, 0, 250, attempt, jid)
            out.append('    if jobs.retry_delay(jit, %du32, %du64) != %di64 { ret %di32 }' % (attempt, jid, d, 100 + nxt()))
    for jid in (1, 2, 12345):
        for attempt in (1, 2, 3, 6, 10):
            d = delay_ms('hangfire', 0, 0, 0, attempt, jid)
            out.append('    if jobs.retry_delay(hf, %du32, %du64) != %di64 { ret %di32 }' % (attempt, jid, d, 100 + nxt()))
    out.append('    ret 0i32')
    out.append('}')
    out.append('')

    # --- cron sequences ----------------------------------------------------------------
    cases = [
        ('0 */15 9-17 * * 1-5', 0, utc(2026, 10, 12, 8)),
        ('30 0 0 1 * *', 0, utc(2026, 1, 31)),
        ('0 30 6 * * 0,3', 330, utc(2026, 10, 12)),
        ('0 0 0 13 * 5', 0, utc(2026, 10, 1)),
        ('*/20 * * * * *', -480, utc(2026, 12, 31, 23, 59, 30)),
        ('0 0 0 29 2 *', 0, utc(2026, 1, 1)),
    ]
    for ci, (expr, offset, start) in enumerate(cases):
        fs = fires(expr, offset, start, 6)
        out.append('fn gen_cron_%d(a: *mem.Arena) -> i32 {' % ci)
        out.append('    let (q0, init_error) = jobs.init(a, 16usize, 2usize, jobs.Policy { kind: jobs.BACKOFF_EXPONENTIAL, base_ms: 1000i64, cap_ms: 0i64, jitter_ms: 0i64 })')
        out.append('    if init_error != ok { ret %di32 }' % (1000 + 100 * ci))
        out.append('    var q = q0')
        out.append('    if jobs.recurring_set(&q, "r", "%s", %di32, "job", "", 1u32, jobs.MISFIRE_SKIP, 0i64, %di64) != ok { ret %di32 }' % (expr, offset, start * NS, 1001 + 100 * ci))
        out.append('    if q.recs[0].next_fire != %di64 { ret %di32 }' % (fs[0] * NS, 1002 + 100 * ci))
        for i in range(5):
            out.append('    let (n%d, e%d) = jobs.tick(&q, %di64)' % (i, i, fs[i] * NS))
            out.append('    if e%d != ok || n%d != 1usize { ret %di32 }' % (i, i, 1010 + 100 * ci + i))
            out.append('    if q.recs[0].next_fire != %di64 { ret %di32 }' % (fs[i + 1] * NS, 1020 + 100 * ci + i))
        out.append('    if jobs.count(&q, jobs.STATE_ENQUEUED) != 5usize { ret %di32 }' % (1030 + 100 * ci))
        out.append('    ret 0i32')
        out.append('}')
        out.append('')

    # --- misfire policies --------------------------------------------------------------
    def policy_model(fire_times, now, grace_ms, policy):
        n = 0
        late_seen = False
        for t in fire_times:
            if t > now:
                break
            late = (now - t) > grace_ms * MS
            if not late:
                n += 1
            elif policy == 'ALL':
                n += 1
            elif policy == 'ONE':
                late_seen = True
        if late_seen:
            n += 1
        return n

    start = utc(2026, 10, 12, 10)
    allf = [f * NS for f in fires('0 */5 * * * *', 0, start, 8)]
    now = allf[3]  # start + 20 min
    out.append('fn gen_misfire(a: *mem.Arena) -> i32 {')
    out.append('    var code = 0i32')
    n_case = 0
    for grace in (0, 600000):
        for pol in ('SKIP', 'ONE', 'ALL'):
            want = policy_model(allf, now, grace, pol)
            n_case += 1
            out.append('    code = misfire_case(a, jobs.MISFIRE_%s, %di64, %di64, %di64, %dusize, %di64)' % (
                pol, grace, start * NS, now, want, allf[4]))
            out.append('    if code != 0i32 { ret %di32 }' % (2000 + 10 * n_case))
    # a long catch-up is bounded at MAX_CATCH_UP and then resumes after `now`
    every = [f * NS for f in fires('* * * * * *', 0, start, 1)]
    now2 = (start + 2000) * NS
    out.append('    ret 0i32')
    out.append('}')
    out.append('')
    out.append('fn gen_bounded_now() -> i64 { ret %di64 }' % now2)
    out.append('fn gen_bounded_start() -> i64 { ret %di64 }' % (start * NS))
    out.append('fn gen_bounded_next() -> i64 { ret %di64 }' % ((start + 2001) * NS))
    out.append('fn gen_bounded_count() -> usize { ret %dusize }' % min(2000, 1000))

    text = FIXTURE.read_text(encoding='utf-8')
    b = text.index('// BEGIN generated')
    e = text.index('// END generated')
    text = text[:b] + '// BEGIN generated by scripts/gen_task_jobs_test.py\n' + '\n'.join(out) + '\n' + text[e:]
    FIXTURE.write_bytes(text.encode('utf-8'))  # LF on every host
    print('wrote', len(out), 'lines')


if __name__ == '__main__':
    sys.exit(main())
