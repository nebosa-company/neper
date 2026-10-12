"""Generate the net_grpcserver fixture: a live Neper gRPC server called by grpcio, its transcripts replayed.

The echo service of scripts/grpcserver_app.e is compiled (`--compiler PATH` or NEPER_SELF) into a loopback server on
`e.net.grpcserver` and called with a grpcio client behind a recording proxy. Every outcome the client saw is asserted
(status, details, messages, metadata), so grpcio itself accepted what the Neper server sent. Each call's bytes are kept in
both directions; the expected request events come from an independent decode of the client's bytes (hyperframe, hpack, the
message prefix, an independent `grpc-timeout` reader) and the expected response from the same decode of the server's.
The fixture replays the client bytes into the same service at several chunk sizes and compares both.

    PYTHONPATH=DIR python scripts/grpcserver_vectors.py --compiler neper-self.exe
"""
import argparse
import base64
import gzip
import os
import random
import socket
import subprocess
import sys
import tempfile
import threading
import time

import grpc
import hpack
from hyperframe import frame as hf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
rng = random.Random(0x47525043)
FIXTURE_DIR = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_grpcserver')


def hx(b):
    if isinstance(b, str):
        b = b.encode('utf-8')
    return b.hex()


def pay(p):
    """A payload as the fixture renders it: hex, or L<length>.<hash> past 1024 bytes (h = h * 31 + byte, 32 bits)."""
    if len(p) <= 1024:
        return hx(p)
    h = 0
    for b in p:
        h = (h * 31 + b) & 0xFFFFFFFF
    return 'L%d.%d' % (len(p), h)


# ---- the recording proxy -------------------------------------------------------------------------------------------
class Proxy:
    """One-connection recording proxy: records bytes in both directions until either side closes."""

    def __init__(self, target_port):
        self.target = target_port
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen(1)
        self.port = self.listener.getsockname()[1]
        self.s2c = bytearray()
        self.c2s = bytearray()
        self.done = threading.Event()
        threading.Thread(target=self.run, daemon=True).start()

    def pump(self, src, dst, log):
        try:
            while True:
                data = src.recv(65536)
                if not data:
                    break
                log.extend(data)
                dst.sendall(data)
        except OSError:
            pass
        finally:
            try:
                dst.shutdown(socket.SHUT_WR)
            except OSError:
                pass

    def run(self):
        client, _ = self.listener.accept()
        upstream = socket.create_connection(('127.0.0.1', self.target))
        a = threading.Thread(target=self.pump, args=(client, upstream, self.c2s), daemon=True)
        b = threading.Thread(target=self.pump, args=(upstream, client, self.s2c), daemon=True)
        a.start()
        b.start()
        a.join(timeout=15)
        b.join(timeout=15)
        client.close()
        upstream.close()
        self.done.set()


SERVER_PORT = 0


def record(call):
    proxy = Proxy(SERVER_PORT)
    channel = grpc.insecure_channel('127.0.0.1:%d' % proxy.port)
    try:
        outcome = call(channel)
    finally:
        channel.close()
    proxy.done.wait(timeout=15)
    return bytes(proxy.c2s), bytes(proxy.s2c), outcome


# ---- independent decode --------------------------------------------------------------------------------------------
STANDARD = {'content-type', 'grpc-status', 'grpc-message', 'grpc-encoding', 'grpc-accept-encoding', 'user-agent', 'server', 'date', 'accept-encoding', 'te', 'grpc-timeout'}


def custom(headers):
    out = []
    for k, v in headers or []:
        k = bytes(k).decode()
        if k.startswith(':') or k in STANDARD:
            continue
        v = bytes(v)
        if k.endswith('-bin'):
            if v[:1] == b'\x00':
                v = v[1:]
            else:
                v = base64.b64decode(v + b'=' * (-len(v) % 4), validate=True)
        out.append((k, v))
    return out


def cust(headers):
    return ','.join(hx(k) + '=' + hx(v) for k, v in custom(headers)) or '-'


def pct_decode(s):
    out = bytearray()
    i = 0
    raw = s.encode('latin-1')
    while i < len(raw):
        if raw[i] == 0x25 and i + 2 < len(raw) and all(c in b'0123456789abcdefABCDEF' for c in raw[i + 1:i + 3]):
            out.append(int(raw[i + 1:i + 3], 16))
            i += 3
        else:
            out.append(raw[i])
            i += 1
    return bytes(out).decode('utf-8')


def parse_timeout(text):
    """The specification's grpc-timeout: 1 to 8 digits and one of H M S m u n, in nanoseconds."""
    units = {'H': 3600 * 10 ** 9, 'M': 60 * 10 ** 9, 'S': 10 ** 9, 'm': 10 ** 6, 'u': 10 ** 3, 'n': 1}
    assert 2 <= len(text) <= 9 and text[:-1].isdigit() and text[-1] in units, text
    return int(text[:-1]) * units[text[-1]]


def frames_of(data):
    pos = 0
    while pos + 9 <= len(data):
        f, length = hf.Frame.parse_frame_header(memoryview(data[pos:pos + 9]))
        body = data[pos + 9:pos + 9 + length]
        pos += 9 + length
        f.parse_body(memoryview(body))
        yield f


def messages_of(data_bytes):
    out = []
    while len(data_bytes) >= 5:
        n = int.from_bytes(data_bytes[1:5], 'big')
        if len(data_bytes) < 5 + n:
            break
        out.append((data_bytes[0] == 1, data_bytes[5:5 + n]))
        data_bytes = data_bytes[5 + n:]
    assert not data_bytes, 'partial message in transcript'
    return out


def render_requests(c2s):
    """R:path:nanos:meta | M:payload:flag ... | C | X:code, from the client's bytes (the preface first)."""
    preface = b'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n'
    assert c2s.startswith(preface)
    dec = hpack.Decoder()
    dec.max_allowed_table_size = 65536
    parts, body, ended, reset = [], b'', False, None
    for f in frames_of(c2s[len(preface):]):
        if isinstance(f, hf.HeadersFrame) and f.stream_id == 1:
            headers = dec.decode(f.data, raw=True)
            d = {bytes(k).decode(): bytes(v).decode() for k, v in headers}
            nanos = parse_timeout(d['grpc-timeout']) if 'grpc-timeout' in d else 0
            parts.append('R:%s:%d:%s' % (hx(d[':path']), nanos, cust(headers)))
            if 'END_STREAM' in f.flags:
                ended = True
        elif isinstance(f, hf.DataFrame) and f.stream_id == 1:
            body += f.data
            if 'END_STREAM' in f.flags:
                ended = True
        elif isinstance(f, hf.RstStreamFrame) and f.stream_id == 1:
            reset = f.error_code
    for compressed, payload in messages_of(body):
        parts.append('M:%s:%d' % (pay(payload), int(compressed)))
    if ended:
        parts.append('C')
    if reset is not None:
        parts.append('X:%d' % reset)
    return '|'.join(parts)


def render_response(s2c):
    """H:meta | M:payload:flag ... | T:status:message:meta, from the server's bytes (SETTINGS first)."""
    dec = hpack.Decoder()
    dec.max_allowed_table_size = 65536
    headers_seen, body = [], b''
    for f in frames_of(s2c):
        if isinstance(f, hf.SettingsFrame) and f.stream_id == 0:
            for ident, value in f.settings.items():
                if ident == 1:
                    dec.max_allowed_table_size = value
            continue
        if isinstance(f, hf.HeadersFrame) and f.stream_id == 1:
            headers_seen.append(dec.decode(f.data, raw=True))
        elif isinstance(f, hf.DataFrame) and f.stream_id == 1:
            body += f.data
    if not headers_seen:
        return ''
    parts = []
    initial, trailing = (None, headers_seen[0]) if len(headers_seen) == 1 else (headers_seen[0], headers_seen[-1])
    if initial is not None:
        parts.append('H:' + cust(initial))
    for compressed, payload in messages_of(body):
        parts.append('M:%s:%d' % (pay(payload), int(compressed)))
    td = {bytes(k).decode(): bytes(v) for k, v in trailing}
    parts.append('T:%d:%s:%s' % (int(td['grpc-status']), hx(pct_decode(td.get('grpc-message', b'').decode('ascii'))), cust(trailing)))
    return '|'.join(parts)


# ---- scenarios -----------------------------------------------------------------------------------------------------
lines = []


def scenario(name, path, call, check, step=None):
    c2s, s2c, outcome = record(call)
    check(outcome)
    requests, response = render_requests(c2s), render_response(s2c)
    chunk = step if step else rng.choice([7, 64, 1000, len(c2s)])
    lines.append('\t'.join(['S', name, hx(path), str(chunk), hx(c2s), requests, response]))
    print('%-14s c2s=%-7d s2c=%-7d %s' % (name, len(c2s), len(s2c), requests[:60]))


def unary(method, payload=b'hello', **kw):
    def call(channel):
        stub = channel.unary_unary('/test.Echo/' + method)
        try:
            resp, cd = stub.with_call(payload, **kw)
            return ('ok', resp, cd.code(), cd.details(), cd.initial_metadata(), cd.trailing_metadata())
        except grpc.RpcError as e:
            return ('err', None, e.code(), e.details(), e.initial_metadata(), e.trailing_metadata())
    return call


def need(cond, what):
    if not cond:
        sys.exit('interop mismatch: ' + what)


def run_scenarios():
    scenario('unary', '/test.Echo/Unary', unary('Unary', b'hello \x00 world'),
             lambda o: need(o[0] == 'ok' and o[1] == b'dlrow \x00 olleh' and o[2] == grpc.StatusCode.OK, 'unary %r' % (o,)))
    scenario('empty', '/test.Echo/Empty', unary('Empty', b'x'), lambda o: need(o[0] == 'ok' and o[1] == b'', 'empty'))
    scenario('fail', '/test.Echo/Fail', unary('Fail'),
             lambda o: need(o[0] == 'err' and o[2] == grpc.StatusCode.NOT_FOUND and o[3] == 'no such thing: café 100% done', 'fail %r' % (o,)))
    scenario('meta', '/test.Echo/Meta', unary('Meta', b'm', metadata=(('x-req', 'v1'), ('x-req-bin', b'\x00\x01\xfe\xff'))),
             lambda o: need(o[0] == 'ok' and o[1] == b'meta:m' and ('x-init', 'first') in [(k, v) for k, v in o[4]] and ('x-trail', 'last') in [(k, v) for k, v in o[5]]
                            and ('x-init-bin', b'\x00\x01\xfe\xff') in [(k, v) for k, v in o[4]] and ('x-trail-bin', b'\xff\x00\x10') in [(k, v) for k, v in o[5]], 'meta %r' % (o,)))
    scenario('big', '/test.Echo/Big', unary('Big', b'b'),
             lambda o: need(o[0] == 'ok' and o[1] == bytes((i * 7) & 255 for i in range(70000)), 'big'), step=64)
    scenario('gzip', '/test.Echo/Gzip', unary('Gzip', b'g'),
             lambda o: need(o[0] == 'ok' and o[1] == b'compress me ' * 40, 'gzip %r' % (o,)))
    scenario('statusmsg', '/test.Echo/StatusMessage', unary('StatusMessage'),
             lambda o: need(o[0] == 'err' and o[2] == grpc.StatusCode.RESOURCE_EXHAUSTED and o[3] == 'quota ☃ exceeded', 'statusmsg %r' % (o,)))
    scenario('unimplemented', '/test.Echo/Nope', unary('Nope'),
             lambda o: need(o[0] == 'err' and o[2] == grpc.StatusCode.UNIMPLEMENTED, 'unimplemented %r' % (o,)))
    scenario('deadline', '/test.Echo/Deadline', unary('Deadline', b'd', timeout=5),
             lambda o: need(o[0] == 'err' and o[2] == grpc.StatusCode.DEADLINE_EXCEEDED, 'deadline %r' % (o,)))

    def slow(channel):
        stub = channel.unary_unary('/test.Echo/Slow')
        try:
            stub(b's', timeout=0.4)
            return 'ok'
        except grpc.RpcError as e:
            return e.code()

    scenario('slow', '/test.Echo/Slow', slow, lambda o: need(o == grpc.StatusCode.DEADLINE_EXCEEDED, 'slow %r' % (o,)))
    scenario('bigrequest', '/test.Echo/BigRequest', unary('BigRequest', bytes((i * 3) & 255 for i in range(80000))),
             lambda o: need(o[0] == 'ok' and o[1] == b'80000', 'bigrequest %r' % (o,)), step=1000)

    def server_stream_call(channel):
        return list(channel.unary_stream('/test.Echo/ServerStream')(b'ss'))

    scenario('serverstream', '/test.Echo/ServerStream', server_stream_call,
             lambda o: need(o == [b'ss\x00', b'ss\x01', b'ss\x02'], 'serverstream %r' % (o,)))

    def client_stream_call(channel):
        return channel.stream_unary('/test.Echo/ClientStream')(iter([b'a', b'bb', b'ccc']))

    scenario('clientstream', '/test.Echo/ClientStream', client_stream_call, lambda o: need(o == b'a|bb|ccc', 'clientstream %r' % (o,)))

    def bidi_call(channel):
        return list(channel.stream_stream('/test.Echo/Bidi')(iter([b'one', b'two', b'three'])))

    scenario('bidi', '/test.Echo/Bidi', bidi_call, lambda o: need(o == [b'ONE', b'TWO', b'THREE'], 'bidi %r' % (o,)))


# ---- building -------------------------------------------------------------------------------------------------------
def build_source(template, app, gzip_hex):
    with open(os.path.join(ROOT, 'scripts', app), encoding='utf-8') as f:
        fragment = f.read().replace('//__GZIP_HEX__', gzip_hex)
    with open(os.path.join(ROOT, 'scripts', template), encoding='utf-8') as f:
        text = f.read()
    return text.replace('//__APP__\n', fragment + '\n')


def compile_exe(compiler, source, exe):
    r = subprocess.run([compiler, 'emit-executable', source, ROOT, 'x64', 'windows', exe], capture_output=True, text=True)
    if 'executable written' not in r.stdout:
        sys.exit('compile failed: ' + r.stdout + r.stderr)


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
    s.close()
    return port


def main():
    global SERVER_PORT
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', default=os.environ.get('NEPER_SELF', ''))
    args = ap.parse_args()
    if not args.compiler or not os.path.exists(args.compiler):
        sys.exit('--compiler (or NEPER_SELF) must name neper-self')
    gzip_hex = gzip.compress(b'compress me ' * 40, mtime=0).hex()
    tmp = tempfile.mkdtemp(prefix='neper-grpcserver-')
    src = os.path.join(tmp, 'main.e')
    with open(src, 'w', encoding='utf-8', newline='\n') as f:
        f.write(build_source('grpcserver_interop_template.e', 'grpcserver_app.e', gzip_hex))
    exe = os.path.join(tmp, 'interop.exe')
    compile_exe(args.compiler, src, exe)
    SERVER_PORT = free_port()
    server = subprocess.Popen([exe, str(SERVER_PORT)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for _ in range(100):
            try:
                socket.create_connection(('127.0.0.1', SERVER_PORT), timeout=0.2).close()
                break
            except OSError:
                time.sleep(0.1)
        else:
            sys.exit('server did not start')
        time.sleep(0.2)
        run_scenarios()
    finally:
        server.kill()
    vector_lines = list(lines)
    chunks, step = [], 2
    for i in range(0, len(vector_lines), step):
        body = '\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"').replace('\t', BS + 't') for l in vector_lines[i:i + step]) + '\n'
        chunks.append('"' + body.replace('\n', BS + 'n') + '"')
    funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
    calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, 1 + i) for i in range(len(chunks)))
    text = build_source('grpcserver_fixture_template.e', 'grpcserver_app.e', gzip_hex)
    text = text.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
    os.makedirs(os.path.join(FIXTURE_DIR, 'src'), exist_ok=True)
    with open(os.path.join(FIXTURE_DIR, 'src', 'main.e'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('%d scenarios in %d chunks -> net_grpcserver' % (len(vector_lines), len(chunks)))


main()
