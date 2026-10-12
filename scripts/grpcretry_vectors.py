"""Generate the net_grpcretry fixture: gRFC A6 retry policy, backoff, pushback and throttling.

Oracle: an independent model written here from the text of gRFC A6 (retry policy validation, the backoff range
`min(initialBackoff * multiplier^(n-1), maxBackoff)`, `grpc-retry-pushback-ms`, the token bucket) and run over random
policies, throttles and scripted sequences of failed attempts. No gRPC core is in the loop, and none exposes these
decisions; the jitter, which the specification leaves to the implementation, is supplied by the caller so the model and
the module are compared on the same draw. Each line is `kind TAB input... TAB expected`.

    python scripts/grpcretry_vectors.py
"""
import json
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_grpcretry', 'src', 'main.e')
rng = random.Random(0xA6)

NAMES = ['OK', 'CANCELLED', 'UNKNOWN', 'INVALID_ARGUMENT', 'DEADLINE_EXCEEDED', 'NOT_FOUND', 'ALREADY_EXISTS', 'PERMISSION_DENIED',
         'RESOURCE_EXHAUSTED', 'FAILED_PRECONDITION', 'ABORTED', 'OUT_OF_RANGE', 'UNIMPLEMENTED', 'INTERNAL', 'UNAVAILABLE', 'DATA_LOSS',
         'UNAUTHENTICATED']


# --- the model ---------------------------------------------------------------------------------------------------------

def duration(text):
    """A JSON duration in nanoseconds, or None."""
    if not isinstance(text, str) or len(text) < 2 or not text.endswith('s'):
        return None
    body = text[:-1]
    if body.count('.') > 1:
        return None
    whole, _, frac = body.partition('.')
    if not whole.isdigit() or (('.' in body) and (not frac.isdigit() or len(frac) > 9)):
        return None
    if len(whole) > 10 or int(whole) > 9223372036:
        return None
    return int(whole) * 10 ** 9 + (int(frac.ljust(9, '0')) if frac else 0)


def policy(config):
    n = config.get('maxAttempts')
    if not isinstance(n, (int, float)) or isinstance(n, bool) or n < 2 or n != int(n):
        return None
    attempts = min(int(n), 5)
    initial = duration(config.get('initialBackoff'))
    maximum = duration(config.get('maxBackoff'))
    if not initial or not maximum:
        return None
    mult = config.get('backoffMultiplier')
    if not isinstance(mult, (int, float)) or isinstance(mult, bool) or not mult > 0:
        return None
    codes = config.get('retryableStatusCodes')
    if not isinstance(codes, list) or not codes:
        return None
    mask = 0
    for c in codes:
        if isinstance(c, str):
            if c not in NAMES:
                return None
            v = NAMES.index(c)
        elif isinstance(c, int) and not isinstance(c, bool) and 0 <= c <= 16:
            v = c
        else:
            return None
        mask |= 1 << v
    return {'attempts': attempts, 'initial': initial, 'max': maximum, 'mult': float(mult), 'codes': mask}


def throttle(config):
    m = config.get('maxTokens')
    r = config.get('tokenRatio')
    if not isinstance(m, (int, float)) or isinstance(m, bool) or not (0 < m <= 1000) or m != int(m):
        return None
    if not isinstance(r, (int, float)) or isinstance(r, bool) or not r > 0:
        return None
    kept = int(r * 1000) / 1000.0
    if not kept > 0:
        return None
    return {'max': float(m), 'ratio': kept, 'tokens': float(m)}


def cap(p, n):
    c = float(p['initial'])
    ceiling = float(p['max'])
    for _ in range(1, n):
        if c >= ceiling:
            break
        c *= p['mult']
    return int(min(c, ceiling))


def backoff(p, n, jitter):
    j = jitter if jitter >= 0 else 0.0
    if j >= 1.0:
        j = 0.999999999
    return int(float(cap(p, n)) * j)


def pushback(text):
    if not text.isdigit() or len(text) > 15 or not text.isascii():
        return None
    return min(int(text) * 10 ** 6, 10 ** 18)


def decide(p, t, attempts, code, committed, push, jitter, now, deadline):
    if code == 0:
        t['tokens'] = min(t['max'], t['tokens'] + t['ratio'])
        return ('ok', 0)
    if committed:
        return ('committed', 0)
    if code > 16 or not (p['codes'] >> code) & 1:
        return ('not-retryable', 0)
    t['tokens'] = max(0.0, t['tokens'] - 1.0)
    delay = 0
    if push is not None:
        v = pushback(push)
        if v is None:
            return ('pushback-refused', 0)
        delay = v
    if attempts >= p['attempts']:
        return ('attempts-exhausted', 0)
    if not t['tokens'] > t['max'] / 2.0:
        return ('throttled', 0)
    if push is None:
        delay = backoff(p, attempts, jitter)
    if deadline > 0 and now + delay >= deadline:
        return ('deadline', 0)
    return ('retry', delay)


# --- generation --------------------------------------------------------------------------------------------------------

def rand_duration():
    return rng.choice(['0.1s', '1s', '2s', '0.001s', '0.000000001s', '10s', '60s', '0.5s', '3.25s', '0s', '0.0s', 's', '1', '1.s', '.5s',
                       '1.2.3s', '-1s', '0.1234567891s', 'abc', '5m', '99999999999s', '1e3s', ' 1s'])


def rand_policy():
    c = {}
    if rng.random() < 0.95:
        c['maxAttempts'] = rng.choice([2, 3, 4, 5, 6, 10, 1, 0, -2, 2.5, 3.0, '3', 100])
    if rng.random() < 0.95:
        c['initialBackoff'] = rng.choice(['0.1s', '0.5s', '1s', '0.01s', '2s', rand_duration()])
    if rng.random() < 0.95:
        c['maxBackoff'] = rng.choice(['1s', '5s', '10s', '0.3s', '60s', rand_duration()])
    if rng.random() < 0.95:
        c['backoffMultiplier'] = rng.choice([1, 1.5, 2, 3, 0.5, 10, 0, -1, '2', 1.0001])
    if rng.random() < 0.95:
        c['retryableStatusCodes'] = rng.choice([['UNAVAILABLE'], ['UNAVAILABLE', 'ABORTED'], [14], ['DEADLINE_EXCEEDED', 14, 'RESOURCE_EXHAUSTED'],
                                                [], ['unavailable'], [17], [-1], 'UNAVAILABLE', [True], ['UNAVAILABLE', 'NOPE'], [0], [16, 'CANCELLED']])
    return c


def good_policy():
    while True:
        c = rand_policy()
        if policy(c):
            return c


def rand_throttle():
    c = {}
    if rng.random() < 0.95:
        c['maxTokens'] = rng.choice([1, 2, 6, 10, 100, 1000, 1001, 0, -1, 0.5, 3.5, '10'])
    if rng.random() < 0.95:
        c['tokenRatio'] = rng.choice([0.1, 0.5, 1, 0.001, 0.0001, 0.1234, 2, 0, -0.1, '0.1'])
    return c


def good_throttle():
    while True:
        c = rand_throttle()
        if throttle(c):
            return c


lines = []


def add(kind, *fields):
    lines.append('\t'.join([kind] + [str(f) for f in fields]))


for _ in range(60):
    c = rand_policy()
    p = policy(c)
    want = 'invalid' if p is None else 'ok %d %d %d %d %d' % (p['attempts'], p['initial'], p['max'], int(p['mult'] * 1000 + 0.5), p['codes'])
    add('P', json.dumps(c, separators=(',', ':')), want)
for _ in range(25):
    c = rand_throttle()
    t = throttle(c)
    want = 'invalid' if t is None else 'ok %d %d' % (int(t['max'] * 1000), int(t['ratio'] * 1000 + 0.5))
    add('T', json.dumps(c, separators=(',', ':')), want)
for text in ['1s', '0.1s', '0.000000001s', '9223372036s', '9223372037s', '1.5s', '10s', '0.5s', '60s', '0s', '.5s', '5.s', '1.0000000001s', 'x', '', 's', '12', '-1s',
             '3.250s', '100.000000001s']:
    d = duration(text)
    add('D', text, 'invalid' if d is None else d)
for _ in range(60):
    c = good_policy()
    p = policy(c)
    n = rng.randrange(1, 9)
    k = rng.randrange(0, 1001)
    add('B', json.dumps(c, separators=(',', ':')), n, k, backoff(p, n, k / 1000.0))
for text in ['0', '100', '1', '999999999999999', '1000000000000000', '-1', '', 'abc', '10.5', '1e3', ' 5', '5 ', '007', '+5']:
    v = pushback(text)
    add('H', text, 'invalid' if v is None else v)
# scripted sequences of attempts
for _ in range(80):
    c = good_policy()
    p = policy(c)
    tc = good_throttle()
    t = throttle(tc)
    events = []
    results = []
    attempts = 0
    now = rng.randrange(0, 5 * 10 ** 9)
    deadline = rng.choice([0, 0, now + rng.randrange(10 ** 8, 20 * 10 ** 9)])
    for _ in range(rng.randrange(1, 9)):
        attempts = rng.randrange(1, 7)
        code = rng.choice([0, 14, 14, 14, 4, 10, 8, 13, 3, 16, 2, 20])
        committed = rng.random() < 0.1
        push = rng.choice([None, None, None, '0', '250', '5000', '-1', 'abc', '2000'])
        k = rng.randrange(0, 1001)
        now += rng.randrange(0, 10 ** 9)
        reason, delay = decide(p, t, attempts, code, committed, push, k / 1000.0, now, deadline)
        events.append('%d,%d,%d,%s,%d,%d,%d' % (attempts, code, 1 if committed else 0, '-' if push is None else push, k, now, deadline))
        results.append('%s:%d:%d' % (reason, delay, int(t['tokens'] * 1000 + 0.5)))
    add('S', json.dumps(c, separators=(',', ':')), json.dumps(tc, separators=(',', ':')), ';'.join(events), ';'.join(results))

# the deadline edge: a pushback of 250 ms against a deadline exactly at, just before and just after it
fixed_policy = {'maxAttempts': 5, 'initialBackoff': '0.1s', 'maxBackoff': '1s', 'backoffMultiplier': 2, 'retryableStatusCodes': ['UNAVAILABLE']}
fixed_throttle = {'maxTokens': 10, 'tokenRatio': 0.1}
for offset in (-1, 0, 1):
    p = policy(fixed_policy)
    t = throttle(fixed_throttle)
    now = 10 ** 9
    deadline = now + 250 * 10 ** 6 + offset
    reason, delay = decide(p, t, 1, 14, False, '250', 0.0, now, deadline)
    add('S', json.dumps(fixed_policy, separators=(',', ':')), json.dumps(fixed_throttle, separators=(',', ':')), '1,14,0,250,0,%d,%d' % (now, deadline),
        '%s:%d:%d' % (reason, delay, int(t['tokens'] * 1000 + 0.5)))
# the throttle edge: with four tokens a failure leaves three (retried), the next leaves two (half: refused), a success adds one
edge_throttle = {'maxTokens': 4, 'tokenRatio': 1}
p = policy(fixed_policy)
t = throttle(edge_throttle)
events = [(1, 14), (1, 14), (1, 0), (1, 14), (1, 14), (1, 14)]
evs, res = [], []
for attempts, code in events:
    reason, delay = decide(p, t, attempts, code, False, None, 0.5, 0, 0)
    evs.append('%d,%d,0,-,500,0,0' % (attempts, code))
    res.append('%s:%d:%d' % (reason, delay, int(t['tokens'] * 1000 + 0.5)))
add('S', json.dumps(fixed_policy, separators=(',', ':')), json.dumps(edge_throttle, separators=(',', ':')), ';'.join(evs), ';'.join(res))

body = '\\n'.join(l.replace('\\', '\\\\').replace('"', '\\"').replace('\t', '\\t') for l in lines) + '\\n'

source = open(os.path.join(ROOT, 'scripts', 'grpcretry_fixture_template.e'), encoding='utf-8').read().replace('\r\n', '\n')
source = source.replace('@@VECTORS@@', body).replace('@@COUNT@@', str(len(lines)))
os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
with open(FIXTURE, 'w', encoding='utf-8', newline='\n') as fh:
    fh.write(source)
print('%d lines -> net_grpcretry' % len(lines))
