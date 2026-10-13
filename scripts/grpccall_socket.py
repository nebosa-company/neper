"""The socket run of e.net.grpccall (L164): the call loop over a real loopback TCP connection, real clock, against
e.net.grpcserver (scripts/grpccall_socket_server.e), compared with the discrete-event model of scripts/grpccall_vectors.py
(the model that agrees with grpcio on the scripted scenarios). Compiles the two Neper programs, runs each scenario with a
fresh server, and checks (streams the client opened, final status). Not part of the suites (it needs ports and a few
seconds of wall time); run:

    python scripts/grpccall_socket.py [path/to/neper-self.exe]
"""
import os
import socket
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPILER = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build', 'windows', 'tests', 'selfhost', 'neper-self.exe')

# the model, without the generation that follows it
src = open(os.path.join(ROOT, 'scripts', 'grpccall_vectors.py'), encoding='utf8').read().split('# --- the grpcio oracle')[0]
ns = {'__file__': os.path.join(ROOT, 'scripts', 'grpccall_vectors.py')}
exec(compile(src.replace('import grpc\n', ''), 'model', 'exec'), ns)
model = ns['model']


def beh(tok):
    if tok == 'r':
        return {'lat': 0, 'hlat': 0, 'headers': False, 'code': 14, 'kind': 'refuse'}
    if tok == 'g':
        return {'lat': 0, 'hlat': 0, 'headers': False, 'code': 14, 'kind': 'goaway'}
    if tok == 's':
        return {'lat': 10 ** 13, 'hlat': 0, 'headers': False, 'code': 14}
    return {'lat': 0, 'hlat': 0, 'headers': False, 'code': int(tok)}


# (script, max attempts, retryable codes, per-attempt ms, deadline ms)
SCENARIOS = [
    ('0', 3, [14], 0, 0),
    ('14,0', 3, [14], 0, 0),
    ('14,14,14,0', 3, [14], 0, 0),
    ('10,0', 3, [14], 0, 0),
    ('r,0', 3, [14], 0, 0),
    ('r,r,0', 3, [14], 0, 0),
    ('r,r,r,0', 3, [14], 0, 0),
    ('g,0', 3, [14], 0, 0),
    ('g,g,0', 3, [14], 0, 0),
    ('g,g,g,0', 3, [14], 0, 0),
    ('14,r,g,0', 4, [14], 0, 0),
    ('r,0', 2, [10], 0, 0),
    ('s,0', 3, [14], 100, 0),
    ('s,s,s', 3, [4], 60, 0),
    ('14,s', 3, [14], 0, 150),
]


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
    s.close()
    return port


def build(out_dir, name):
    exe = os.path.join(out_dir, name + '.exe')
    r = subprocess.run([COMPILER, 'emit-executable', os.path.join(ROOT, 'scripts', name + '.e'), ROOT, 'x64', 'windows', exe],
                       capture_output=True, text=True, timeout=300)
    assert 'executable written' in r.stdout, (name, r.stdout, r.stderr)
    return exe


def main():
    with tempfile.TemporaryDirectory() as out_dir:
        server = build(out_dir, 'grpccall_socket_server')
        client = build(out_dir, 'grpccall_socket_client')
        bad = 0
        for script, max_att, codes, per_attempt, deadline in SCENARIOS:
            cfg = {'mode': 'retry', 'per_attempt_ns': per_attempt * 1_000_000, 'deadline_ns': deadline * 1_000_000,
                   'throttle': {'maxTokens': 10, 'tokenRatio': 0.1},
                   'policy': {'maxAttempts': max_att, 'initialBackoff': '0.005s', 'maxBackoff': '0.02s', 'backoffMultiplier': 2,
                              'retryableStatusCodes': codes},
                   'server': [beh(t) for t in script.split(',')]}
            want = model(cfg)
            port = free_port()
            srv = subprocess.Popen([server, str(port), script], stdout=subprocess.PIPE, text=True)
            try:
                assert srv.stdout.readline().strip() == 'listening'
                mask = 0
                for c in codes:
                    mask |= 1 << c
                t = time.time()
                r = subprocess.run([client, str(port), str(max_att), str(mask), '5', str(per_attempt), str(deadline)],
                                   capture_output=True, text=True, timeout=30)
                took = time.time() - t
            finally:
                srv.kill()
            got = r.stdout.strip().split()
            ok_run = r.returncode == 0 and got[:1] == ['result'] and (int(got[1]), int(got[2])) == (want['attempts'], want['code'])
            print(('ok   ' if ok_run else 'FAIL ') + f'{script:14} policy {max_att}x{codes} per-attempt {per_attempt}ms deadline {deadline}ms'
                  f' -> {" ".join(got[1:])} (model {want["attempts"]} {want["code"]}) {took:.2f}s', flush=True)
            bad += 0 if ok_run else 1
        print('socket run:', 'all agree' if bad == 0 else f'{bad} disagree')
        return bad


sys.exit(main())
