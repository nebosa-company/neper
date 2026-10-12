"""Generate tests/selfhost/fixtures/link/test_poll/src/main.e (L160, D2803).

There is no Awaitility on this host, so the reference is an independent Python model of the
documented algorithm (initial delay, evaluate, sleep min(interval, remaining), backoff and
cap, one last evaluation at the deadline, errors ended or ignored; `during` converse),
driven over a grid of configurations against a scripted condition (true from attempt K or
never, an error on chosen attempts). The fixture replays each case on a fake clock and
checks result, attempts and elapsed time exactly; a short real-clock run checks that real
sleeping reaches the deadline, and that a condition made true by another thread ends the
wait before it.
"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402

random.seed(162)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'test_poll' / 'src' / 'main.e'


def next_interval(cur, backoff, cap):
    nxt = cur
    if backoff not in (0, 100):
        nxt = cur * backoff // 100
    if cap > 0 and nxt > cap:
        nxt = cap
    return max(nxt, 1)


def model(mode, timeout, interval, delay, backoff, cap, ignore, true_from, err_at):
    """Returns (result, attempts, elapsed). result: 0 ok, 1 timeout, 2 failed, 3 error."""
    t = 0
    start = 0
    deadline = timeout
    t += delay
    cur = interval
    attempts = 0
    while True:
        attempts += 1
        err = attempts in err_at
        holds = (not err) and attempts >= true_from
        elapsed = t - start
        if mode == 'U':
            if err:
                if not ignore:
                    return 3, attempts, elapsed
            elif holds:
                return 0, attempts, elapsed
        else:
            if err:
                return 3, attempts, elapsed
            if not holds:
                return 2, attempts, elapsed
        if t >= deadline:
            break
        nap = min(cur, deadline - t)
        t += nap
        cur = next_interval(cur, backoff, cap)
    return (1 if mode == 'U' else 0), attempts, t - start


lines = []
for mode in ('U', 'D'):
    for _ in range(140):
        timeout = random.choice([0, 1, 10, 100, 1000, 5000, 12345])
        interval = random.choice([1, 3, 10, 50, 100, 250])
        delay = random.choice([0, 0, 5, 100])
        backoff = random.choice([0, 100, 150, 200, 250])
        cap = random.choice([0, 0, 40, 400])
        ignore = random.choice([0, 1])
        true_from = random.choice([1, 2, 3, 7, 10 ** 6])
        err_at = sorted(random.sample(range(1, 6), random.choice([0, 0, 1, 2])))
        res, attempts, elapsed = model(mode, timeout, interval, delay, backoff, cap, bool(ignore), true_from, set(err_at))
        lines.append('%s %d %d %d %d %d %d %d %s => %d %d %d' % (mode, timeout, interval, delay, backoff, cap, ignore, true_from,
                                                                  ','.join(map(str, err_at)) or '-', res, attempts, elapsed))

vec, names = fc.vector_functions('v', lines)

CHECK = '''
type Script = struct { calls: u32, true_from: u32, err_mask: u32, now: i64 }
error Scripted

fn fake_now(ctx: *void) -> i64 {
    let s = mem.cast[*Script](ctx)
    ret s.now
}

fn fake_sleep(ctx: *void, nanos: i64) {
    var s = mem.cast[*Script](ctx)
    s.now += nanos
}

fn scripted(ctx: *void) -> (bool, err) {
    var s = mem.cast[*Script](ctx)
    s.calls += 1u32
    if s.calls < 32u32 && ((s.err_mask >> s.calls) & 1u32) == 1u32 { ret (false, Scripted) }
    ret (s.calls >= s.true_from, ok)
}

fn check_line(line: str) -> u8 {
    let (mode, p0) = tok(line, 0usize)
    let (timeout, p1) = tok(line, p0)
    let (interval, p2) = tok(line, p1)
    let (delay, p3) = tok(line, p2)
    let (backoff, p4) = tok(line, p3)
    let (cap, p5) = tok(line, p4)
    let (ignore, p6) = tok(line, p5)
    let (from, p7) = tok(line, p6)
    let (errs, p8) = tok(line, p7)
    let (arrow, p9) = tok(line, p8)
    let (want_result, p10) = tok(line, p9)
    let (want_attempts, p11) = tok(line, p10)
    let (want_elapsed, p12) = tok(line, p11)
    var s: Script = zero
    s.true_from = u32(dec(from))
    // error attempts: comma list of attempt numbers 1..5
    var mask = 0u32
    if errs[0usize] != 45u8 {
        var i = 0usize
        while i < errs.len {
            if errs[i] >= 48u8 && errs[i] <= 57u8 { mask = mask | (1u32 << u32(errs[i] - 48u8)) }
            i += 1usize
        }
    }
    s.err_mask = mask
    let clock = poll.Clock { ctx: mem.cast[*void](&s), now: fake_now, sleep: fake_sleep }
    var o: poll.Options = zero
    o.timeout_ns = dec(timeout)
    o.interval_ns = dec(interval)
    o.initial_delay_ns = dec(delay)
    o.backoff_percent = u32(dec(backoff))
    o.max_interval_ns = dec(cap)
    o.ignore_errors = ignore[0usize] == 49u8
    var outcome: poll.Outcome = zero
    var result = ok
    if mode[0usize] == 85u8 {
        let (oc, e) = poll.until(clock, mem.cast[*void](&s), scripted, o)
        outcome = oc
        result = e
    } else {
        let (oc, e) = poll.during(clock, mem.cast[*void](&s), scripted, o)
        outcome = oc
        result = e
    }
    var code = 3i64
    if result == ok { code = 0i64 }
    if result == poll.Timeout { code = 1i64 }
    if result == poll.Failed { code = 2i64 }
    if code != dec(want_result) { ret 1u8 }
    if i64(outcome.attempts) != dec(want_attempts) { ret 2u8 }
    if outcome.elapsed_ns != dec(want_elapsed) { ret 3u8 }
    ret 0u8
}

// ---- real clock ----

type Flag = struct { set: Atomic[u32], calls: Atomic[u32] }

fn flag_cond(ctx: *void) -> (bool, err) {
    var f = mem.cast[*Flag](ctx)
    let n = atomic.add(&f.calls, 1u32, .AcqRel)
    ret (atomic.load(&f.set, .Acquire) == 1u32, ok)
}

fn raiser(f: *Flag) {
    var nap = sync.semaphore(0u32)
    let woke = sync.semaphore_wait_for(&nap, time.millis(60i64))
    let old = atomic.add(&f.set, 1u32, .Release)
}

'''

MAIN = '''fn main(a: *mem.Arena, args: []str) -> err {
    // real clock: a condition that never holds times out near the deadline, not before it
    var rc: poll.RealClock = zero
    let clock = poll.real_clock(&rc)
    var flag: Flag = zero
    var o: poll.Options = zero
    o.timeout_ns = 80000000i64
    o.interval_ns = 10000000i64
    let (oc, e) = poll.until(clock, mem.cast[*void](&flag), flag_cond, o)
    if e != poll.Timeout { os.exit(101i32) }
    if oc.elapsed_ns < 80000000i64 { os.exit(102i32) }
    if oc.attempts < 3u32 || oc.attempts > 12u32 { os.exit(103i32) }
    // another thread makes it true after ~60 ms: the wait ends with success well before 5 s
    var flag2: Flag = zero
    let (t, spawn_error) = thread.spawn[Flag](raiser, &flag2, 0usize)
    if spawn_error != ok { os.exit(104i32) }
    var o2: poll.Options = zero
    o2.timeout_ns = 5000000000i64
    o2.interval_ns = 5000000i64
    let (oc2, e2) = poll.until(clock, mem.cast[*void](&flag2), flag_cond, o2)
    let joined = thread.join(t)
    if e2 != ok { os.exit(105i32) }
    if oc2.elapsed_ns < 40000000i64 || oc2.elapsed_ns > 4000000000i64 { os.exit(106i32) }
    // bad options are refused
    var bad: poll.Options = zero
    let (_, bad_error) = poll.until(clock, mem.cast[*void](&flag), flag_cond, bad)
    if bad_error != poll.Invalid { os.exit(107i32) }
    let r = run_vectors()
    if r != 0u8 { os.exit(i32(r)) }
    try io.print("test poll ok")
    ret ok
}
'''

src = ('// e.test.poll: `until` and `during` replayed on a fake clock over a grid of configurations against an\n'
       '// independent Python model of the documented algorithm (result, attempts and elapsed time exact), plus\n'
       '// real-clock runs: a timeout reaches its deadline, and a condition raised by another thread ends the\n'
       '// wait early (D2803). Generated by scripts/gen_poll_test.py.\n'
       'use e.io\nuse e.mem\nuse e.os\nuse e.atomic\nuse e.sync\nuse e.thread\nuse e.time\nuse e.test.poll\n\n'
       + fc.PRELUDE + CHECK + vec + '\n' + fc.run_all(names, 'check_line') + '\n' + MAIN)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(lines), 'vectors')
