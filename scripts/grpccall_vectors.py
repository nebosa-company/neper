"""Generate the net_grpccall fixture: the A6 retry and hedging loop of e.net.grpccall over an in-memory e.net.grpc client
and e.net.grpcserver.

Two oracles:
  * retry mode, no timing: grpcio itself. A scripted grpcio server (each attempt answers per its entry: trailers-only
    status, initial metadata then status, `grpc-retry-pushback-ms`, OK) is called by a grpcio client whose service config
    carries the retry policy; the number of attempts the server saw and the final status are what the fixture must
    reproduce. Backoff is jittered by grpc-core, so only counts and status are compared there.
  * everything with timing (retry with a deadline and per-attempt timeouts, hedging, throttling): `model`, an
    independent discrete-event simulation written here from the text of gRFC A6, run on a virtual clock with the
    caller's jitter fixed at 0.5. grpcio has no hedging and no per-attempt receive timeout. The model is first checked
    against grpcio on the live scenarios (it must agree on attempts and status), then trusted for the timed ones.

    python scripts/grpccall_vectors.py
"""
import json
import os
import random
import sys
import threading
import time
from concurrent import futures

import grpc

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, 'scripts', 'grpccall_fixture_template.e')
FIXTURE = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_grpccall', 'src', 'main.e')
rng = random.Random(0xA6C)
NAMES = ['OK', 'CANCELLED', 'UNKNOWN', 'INVALID_ARGUMENT', 'DEADLINE_EXCEEDED', 'NOT_FOUND', 'ALREADY_EXISTS', 'PERMISSION_DENIED',
         'RESOURCE_EXHAUSTED', 'FAILED_PRECONDITION', 'ABORTED', 'OUT_OF_RANGE', 'UNIMPLEMENTED', 'INTERNAL', 'UNAVAILABLE', 'DATA_LOSS',
         'UNAUTHENTICATED']
JITTER = 0.5


def dur_ns(text):
    return round(float(text[:-1]) * 1e9)


# --- the model -----------------------------------------------------------------------------------------------------------

def model(cfg):
    """Returns {code, attempts, starts, cancelled, end} for a scripted call on a virtual clock."""
    srv = cfg['server']
    mode = cfg['mode']
    pa = cfg['per_attempt_ns']
    deadline = cfg['deadline_ns']
    th = cfg['throttle']
    max_tokens, ratio = th['maxTokens'], th['tokenRatio']
    tokens = float(max_tokens)
    if mode == 'retry':
        pol = cfg['policy']
        max_att = min(pol['maxAttempts'], 5)
        init, mx = dur_ns(pol['initialBackoff']), dur_ns(pol['maxBackoff'])
        mult = pol['backoffMultiplier']
        codes = {NAMES.index(c) if isinstance(c, str) else c for c in pol['retryableStatusCodes']}
    else:
        h = cfg['hedge']
        max_att = min(h['maxAttempts'], 5)
        hdelay = h['hedgingDelay_ns']
        nonfatal = set(h['nonFatal'])

    def behavior(k):
        return srv[min(k - 1, len(srv) - 1)]

    now = 0
    attempts = []  # dict(start, live, committed, hdr_at, fin_at)
    starts, cancelled, marked = [], [], []

    def flush():
        # the transport resets the marked streams, lowest attempt first, before it does anything else
        cancelled.extend(sorted(marked))
        del marked[:]
    pending, next_at, stop = True, 0, False
    result = None

    def start_attempt():
        nonlocal pending, next_at
        k = len(attempts) + 1
        b = behavior(k)
        a = {'k': k, 'start': now, 'live': True, 'committed': False,
             'hdr_at': now + b['hlat'] if b['headers'] else None, 'fin_at': now + b['lat'], 'b': b}
        attempts.append(a)
        starts.append(now)
        pending = False
        if mode == 'hedge' and k < max_att and not stop:
            pending, next_at = True, now + hdelay

    def cancel_all_except(keep):
        for a in attempts:
            if a is not keep and a['live']:
                a['live'] = False
                marked.append(a['k'])

    def finish(code):
        nonlocal result
        result = code

    def cap_ns(n):
        c = float(init)
        i = 1
        while i < n:
            if c >= mx:
                break
            c *= mult
            i += 1
        return int(min(c, mx))

    def fin(a, code, pushback, timed_out=False):
        """An attempt ended with `code`."""
        nonlocal tokens, pending, next_at, stop
        a['live'] = False
        if timed_out:
            marked.append(a['k'])
        n = len(attempts)
        if mode == 'retry':
            if code == 0:
                tokens = min(float(max_tokens), tokens + ratio)
                return finish(0)
            if a['committed']:
                return finish(code)
            if code not in codes:
                return finish(code)
            tokens = max(0.0, tokens - 1)
            delay = None
            if pushback is not None:
                if not pushback.isdigit() or len(pushback) > 15:
                    return finish(code)
                v = int(pushback)
                delay = 10 ** 18 if v > 10 ** 12 else v * 10 ** 6
            if n >= max_att:
                return finish(code)
            if not tokens > max_tokens / 2:
                return finish(code)
            if delay is None:
                delay = int(cap_ns(n) * JITTER)
            if deadline and now + delay >= deadline:
                return finish(code)
            pending, next_at = True, now + delay
            return
        # hedging
        if code == 0:
            tokens = min(float(max_tokens), tokens + ratio)
            cancel_all_except(a)
            return finish(0)
        if a['committed']:
            return finish(code)
        if code not in nonfatal:
            cancel_all_except(a)
            return finish(code)
        tokens = max(0.0, tokens - 1)
        if pushback is not None and not (pushback.isdigit() and len(pushback) <= 15):
            stop, pending = True, False
        elif pushback is not None:
            v = int(pushback)
            next_at = now + (10 ** 18 if v > 10 ** 12 else v * 10 ** 6)
            pending = n < max_att and not stop
        else:
            next_at = now
            pending = n < max_att and not stop
        if not any(x['live'] for x in attempts) and not pending:
            finish(code)

    for _ in range(10000):
        if result is not None:
            break
        # candidate instants: server events, per-attempt timeouts, the deadline, the next start
        while True:
            progressed = False
            # server events due now, by attempt then kind (headers before the final status)
            for a in attempts:
                if result is not None:
                    break
                if a['live'] and a['hdr_at'] is not None and a['hdr_at'] <= now and not a['committed']:
                    a['committed'] = True
                    cancel_all_except(a)
                    stop = True
                    pending = False
                    progressed = True
                if a['live'] and a['fin_at'] <= now and result is None:
                    b = a['b']
                    fin(a, b['code'], b.get('pushback'))
                    progressed = True
            flush()
            if result is not None:
                break
            if deadline and now >= deadline:
                cancel_all_except(None)
                flush()
                finish(4)
                break
            to = False
            for a in attempts:
                if pa and a['live'] and not a['committed'] and now >= a['start'] + pa:
                    fin(a, 4, None, timed_out=True)
                    flush()
                    progressed = True
                    to = True
                    break
            if result is not None:
                break
            if to:
                continue
            if pending and now >= next_at:
                if mode == 'hedge' and attempts and not tokens > max_tokens / 2:
                    stop, pending = True, False
                    if not any(x['live'] for x in attempts):
                        finish(14)
                    continue
                start_attempt()
                continue
            if not progressed:
                break
        if result is not None:
            break
        wake = []
        if pending:
            wake.append(next_at)
        for a in attempts:
            if a['live']:
                if a['hdr_at'] is not None and not a['committed']:
                    wake.append(a['hdr_at'])
                wake.append(a['fin_at'])
                if pa and not a['committed']:
                    wake.append(a['start'] + pa)
        if deadline:
            wake.append(deadline)
        wake = [w for w in wake if w > now]
        if not wake:
            return {'code': -1, 'attempts': len(attempts), 'starts': starts, 'cancelled': cancelled, 'end': now}
        now = min(wake)
    return {'code': result, 'attempts': len(attempts), 'starts': starts, 'cancelled': cancelled, 'end': now}


# --- the grpcio oracle ---------------------------------------------------------------------------------------------------

def live(cfg):
    """(attempts the server saw, final status code) from a grpcio client with the retry policy against a scripted server."""
    script = cfg['server']
    count = [0]
    lock = threading.Lock()

    def handler(request, context):
        with lock:
            i = count[0]
            count[0] += 1
        b = script[min(i, len(script) - 1)]
        if b['headers']:
            context.send_initial_metadata(())
        if b.get('pushback') is not None:
            context.set_trailing_metadata((('grpc-retry-pushback-ms', b['pushback']),))
        if b['code'] == 0:
            return b'ok'
        context.abort(grpc.StatusCode[NAMES[b['code']]], 'x')

    server = grpc.server(futures.ThreadPoolExecutor(4))
    server.add_generic_rpc_handlers((grpc.method_handlers_generic_handler('t.S', {'M': grpc.unary_unary_rpc_method_handler(handler)}),))
    port = server.add_insecure_port('127.0.0.1:0')
    server.start()
    sc = json.dumps({'methodConfig': [{'name': [{'service': 't.S'}], 'retryPolicy': cfg['policy']}]})
    ch = grpc.insecure_channel(f'127.0.0.1:{port}', options=[('grpc.service_config', sc), ('grpc.enable_retries', 1)])
    call = ch.unary_unary('/t.S/M')
    code = 0
    try:
        call(b'ping', timeout=20)
    except grpc.RpcError as e:
        code = NAMES.index(e.code().name)
    ch.close()
    server.stop(0)
    return count[0], code


# --- scenarios -----------------------------------------------------------------------------------------------------------

def policy(numbers=False):
    return {
        'maxAttempts': rng.choice([2, 3, 4, 5, 5]),
        'initialBackoff': rng.choice(['0.001s', '0.002s']),
        'maxBackoff': rng.choice(['0.004s', '0.01s']),
        'backoffMultiplier': rng.choice([1.5, 2, 3]),
        'retryableStatusCodes': rng.sample(['UNAVAILABLE', 'ABORTED', 'RESOURCE_EXHAUSTED', 'INTERNAL'] + ([14, 10] if numbers else []), rng.randint(1, 3)),
    }


def b_untimed():
    r = rng.random()
    code = rng.choice([14, 14, 10, 8, 13, 4, 5])
    if r < 0.45:
        return {'lat': 0, 'hlat': 0, 'headers': False, 'code': code}
    if r < 0.6:
        return {'lat': 0, 'hlat': 0, 'headers': False, 'code': code, 'pushback': rng.choice(['0', '1', '3', '-1', '2'])}  # grpc-core retries on an unparseable value; A6 says not to, so it is not drawn here
    if r < 0.7:
        return {'lat': 0, 'hlat': 0, 'headers': True, 'code': code}
    return {'lat': 0, 'hlat': 0, 'headers': False, 'code': 0}


def base_cfg(mode):
    return {'mode': mode, 'per_attempt_ns': 0, 'deadline_ns': 0, 'throttle': {'maxTokens': 1000, 'tokenRatio': 1.0}}


cases = []
live_checked = 0
for i in range(60):
    cfg = base_cfg('retry')
    cfg['policy'] = policy()
    cfg['server'] = [b_untimed() for _ in range(rng.randint(1, 6))]
    want = live(cfg)
    got = model(cfg)
    assert (got['attempts'], got['code']) == want, (cfg, got, want)
    live_checked += 1
    cfg['e'] = got
    cases.append(cfg)


def b_timed():
    r = rng.random()
    lat = rng.choice([0, 1, 5, 20, 50, 200]) * 1_000_000
    hl = rng.choice([0, 1, 3, 10]) * 1_000_000
    code = rng.choice([14, 14, 10, 8, 13, 4, 5, 0])
    b = {'lat': lat, 'hlat': min(hl, lat), 'headers': rng.random() < 0.2, 'code': code}
    if r < 0.15:
        b['pushback'] = rng.choice(['0', '5', '30', '-1', 'x'])
    return b


for i in range(120):
    cfg = base_cfg('retry')
    cfg['policy'] = policy(True)
    cfg['server'] = [b_timed() for _ in range(rng.randint(1, 6))]
    cfg['per_attempt_ns'] = rng.choice([0, 0, 10, 30, 100]) * 1_000_000
    cfg['deadline_ns'] = rng.choice([0, 0, 40, 120, 400]) * 1_000_000
    if rng.random() < 0.3:
        cfg['throttle'] = {'maxTokens': rng.choice([3, 4, 6, 10]), 'tokenRatio': rng.choice([0.1, 0.5, 1.0])}
    cfg['e'] = model(cfg)
    assert cfg['e']['code'] >= 0, cfg
    cases.append(cfg)

for i in range(150):
    cfg = base_cfg('hedge')
    cfg['hedge'] = {'maxAttempts': rng.choice([2, 3, 4, 5, 6]), 'hedgingDelay_ns': rng.choice([0, 5, 20, 50]) * 1_000_000,
                    'nonFatal': rng.sample([14, 10, 8, 13, 4], rng.randint(0, 3))}
    cfg['server'] = [b_timed() for _ in range(rng.randint(1, 6))]
    cfg['per_attempt_ns'] = rng.choice([0, 0, 0, 60, 150]) * 1_000_000
    cfg['deadline_ns'] = rng.choice([0, 0, 100, 400]) * 1_000_000
    if rng.random() < 0.4:
        cfg['throttle'] = {'maxTokens': rng.choice([3, 4, 6, 10]), 'tokenRatio': rng.choice([0.1, 0.5, 1.0])}
    cfg['e'] = model(cfg)
    assert cfg['e']['code'] >= 0, cfg
    cases.append(cfg)

# the shape the gRFC describes: a slow first attempt, a hedge at the delay that wins, the first cancelled
cfg = base_cfg('hedge')
cfg['hedge'] = {'maxAttempts': 3, 'hedgingDelay_ns': 10_000_000, 'nonFatal': [14]}
cfg['server'] = [{'lat': 100_000_000, 'hlat': 0, 'headers': False, 'code': 0}, {'lat': 5_000_000, 'hlat': 0, 'headers': False, 'code': 0}]
cfg['e'] = model(cfg)
assert cfg['e']['code'] == 0 and cfg['e']['cancelled'] == [1] and cfg['e']['starts'] == [0, 10_000_000], cfg['e']
cases.append(cfg)

lines = [json.dumps(c, sort_keys=True, separators=(',', ':')) for c in cases]
bs = chr(92)
chunks = []
for i in range(0, len(lines), 10):
    chunks.append('"' + (bs + 'n').join(l.replace(bs, bs + bs).replace('"', bs + '"') for l in lines[i:i + 10]) + bs + 'n"')
funcs = '\n'.join(f'fn vectors_{i}() -> str {{\n    ret {c}\n}}\n' for i, c in enumerate(chunks))
calls = ''.join(f'    if run_chunk(a, vectors_{i}()) != 0u8 {{ os.exit({i + 1}i32) }}\n' for i in range(len(chunks)))
with open(TEMPLATE, encoding='utf8') as f:
    t = f.read()
out = t.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
with open(FIXTURE, 'w', encoding='utf8', newline='\n') as f:
    f.write(out)
print(f'{len(cases)} cases ({live_checked} against grpcio) in {len(chunks)} chunks -> net_grpccall')
