"""Generate the net_grpc fixture: transcripts recorded from grpcio, validated by the python-hyper libraries.

Oracle, server to client: a grpcio server (generic handlers over raw bytes) is run behind a recording TCP proxy and
called by a grpcio client; each call's server-to-client bytes are the vector. The expected events come from an
independent decode of those same bytes (hyperframe + hpack + the gRPC message prefix), and every expected outcome
(status, details, messages, metadata) is asserted equal to what the grpcio client itself observed.
Oracle, client to server: Neper's own `conn_start`/`call_start`/`call_send` output is produced by running the
compiler (`--compiler PATH` or NEPER_SELF) on an emitter, then read by `h2.H2Connection` acting as a server and its
events compared with the scenario before the bytes are written into the fixture as goldens.
Timeouts and status text follow the gRPC specification (reference: grpc-go's `encodeTimeout`, reimplemented here).

    PYTHONPATH=DIR python scripts/grpc_vectors.py --compiler neper-self.exe
"""
import argparse
import base64
import os
import random
import socket
import subprocess
import sys
import tempfile
import threading
import time
from concurrent import futures

import grpc
import h2.config
import h2.connection
import h2.events
import hpack
from hyperframe import frame as hf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
rng = random.Random(0x47525043)
FIXTURE_DIR = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_grpc')


def hx(b):
    if isinstance(b, str):
        b = b.encode('utf-8')
    return b.hex()


lines = []


def add(*f):
    lines.append('\t'.join(str(x) for x in f))


# ---- the grpcio server and the recording proxy -------------------------------------------------------------------
def unary_echo(request, context):
    return request[::-1]


def unary_empty(request, context):
    return b''


def unary_fail(request, context):
    context.abort(grpc.StatusCode.NOT_FOUND, 'no such thing: café 100% done')


def unary_meta(request, context):
    context.send_initial_metadata((('x-init', 'first'), ('x-init-bin', b'\x00\x01\xfe\xff')))
    context.set_trailing_metadata((('x-trail', 'last'), ('x-trail-bin', b'\xff\x00\x10')))
    return b'meta:' + request


def unary_big(request, context):
    return bytes((i * 7) & 255 for i in range(70000))


def unary_gzip(request, context):
    context.set_compression(grpc.Compression.Gzip)
    return b'compress me ' * 40


def unary_status_message(request, context):
    context.set_code(grpc.StatusCode.RESOURCE_EXHAUSTED)
    context.set_details('quota ☃ exceeded')
    return b'partial'


def server_stream(request, context):
    for i in range(3):
        yield request + bytes([i])


def client_stream(request_iterator, context):
    return b'|'.join(request_iterator)


def bidi(request_iterator, context):
    for r in request_iterator:
        yield r.upper()


HANDLERS = {
    'Unary': grpc.unary_unary_rpc_method_handler(unary_echo),
    'Empty': grpc.unary_unary_rpc_method_handler(unary_empty),
    'Fail': grpc.unary_unary_rpc_method_handler(unary_fail),
    'Meta': grpc.unary_unary_rpc_method_handler(unary_meta),
    'Big': grpc.unary_unary_rpc_method_handler(unary_big),
    'Gzip': grpc.unary_unary_rpc_method_handler(unary_gzip),
    'StatusMessage': grpc.unary_unary_rpc_method_handler(unary_status_message),
    'ServerStream': grpc.unary_stream_rpc_method_handler(server_stream),
    'ClientStream': grpc.stream_unary_rpc_method_handler(client_stream),
    'Bidi': grpc.stream_stream_rpc_method_handler(bidi),
}


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
        a.join(timeout=10)
        b.join(timeout=10)
        client.close()
        upstream.close()
        self.done.set()


def record(call):
    proxy = Proxy(SERVER_PORT)
    channel = grpc.insecure_channel('127.0.0.1:%d' % proxy.port)
    try:
        outcome = call(channel)
    finally:
        channel.close()
    proxy.done.wait(timeout=10)
    return bytes(proxy.s2c), bytes(proxy.c2s), outcome


# ---- independent decode of server bytes ---------------------------------------------------------------------------
STANDARD = {'content-type', 'grpc-status', 'grpc-message', 'grpc-encoding', 'grpc-accept-encoding', 'user-agent', 'server', 'date', 'accept-encoding'}


def decode_stream(data, stream_id=1):
    """Frames -> (initial custom headers or None, [(compressed, payload)], status, message, trailing custom headers)."""
    dec = hpack.Decoder()
    dec.max_allowed_table_size = 65536
    pos, buf = 0, b''
    initial, trailers, messages, data_bytes = None, None, [], b''
    headers_seen = []
    while pos + 9 <= len(data):
        f, length = hf.Frame.parse_frame_header(memoryview(data[pos:pos + 9]))
        body = data[pos + 9:pos + 9 + length]
        pos += 9 + length
        if isinstance(f, hf.SettingsFrame) and f.stream_id == 0:
            f.parse_body(memoryview(body))
            for ident, value in f.settings.items():
                if ident == 1:
                    dec.max_allowed_table_size = value
            continue
        f.parse_body(memoryview(body))
        if isinstance(f, hf.HeadersFrame) and f.stream_id == stream_id:
            block = f.data
            headers_seen.append((dec.decode(block, raw=True), 'END_STREAM' in f.flags))
        elif isinstance(f, hf.DataFrame) and f.stream_id == stream_id:
            data_bytes += f.data
    # gRPC messages out of the DATA bytes
    while len(data_bytes) >= 5:
        n = int.from_bytes(data_bytes[1:5], 'big')
        if len(data_bytes) < 5 + n:
            break
        messages.append((data_bytes[0] == 1, data_bytes[5:5 + n]))
        data_bytes = data_bytes[5 + n:]
    assert not data_bytes, 'partial message in transcript'
    initial_headers, trailing = None, None
    if len(headers_seen) == 1:
        trailing = headers_seen[0][0]
    elif len(headers_seen) >= 2:
        initial_headers, trailing = headers_seen[0][0], headers_seen[-1][0]
    td = {bytes(k).decode(): bytes(v) for k, v in trailing}
    status = int(td['grpc-status'])
    message = pct_decode(td.get('grpc-message', b'').decode('ascii'))
    return initial_headers, messages, status, message, trailing


def custom(headers):
    out = []
    for k, v in headers or []:
        k = bytes(k).decode()
        if k.startswith(':') or k in STANDARD:
            continue
        v = bytes(v)
        if k.endswith('-bin'):
            if v[:1] == b'\x00':
                # gRPC C-core's raw form: a zero byte, then the value (base64 text never starts with one).
                v = v[1:]
            else:
                v = base64.b64decode(v + b'=' * (-len(v) % 4), validate=True)
        out.append((k, v))
    return out


def pct_decode(s):
    out = bytearray()
    i = 0
    raw = s.encode('latin-1')
    while i < len(raw):
        if raw[i] == 0x25 and i + 2 < len(raw) + 0 and all(c in b'0123456789abcdefABCDEF' for c in raw[i + 1:i + 3]):
            out.append(int(raw[i + 1:i + 3], 16))
            i += 3
        else:
            out.append(raw[i])
            i += 1
    return bytes(out).decode('utf-8')


def render(initial, messages, status, message, trailing):
    parts = []
    if initial is not None:
        parts.append('H:' + (','.join(hx(k) + '=' + hx(v) for k, v in custom(initial)) or '-'))
    for compressed, payload in messages:
        parts.append('M:%s:%d' % (hx(payload), int(compressed)))
    parts.append('T:%d:%s:%s' % (status, hx(message), ','.join(hx(k) + '=' + hx(v) for k, v in custom(trailing)) or '-'))
    return '|'.join(parts)


# ---- scenarios -----------------------------------------------------------------------------------------------------
def scenario(name, path, call, check, request_headers=()):
    s2c, c2s, outcome = record(call)
    initial, messages, status, message, trailing = decode_stream(s2c)
    check(outcome, messages, status, message, initial, trailing)
    add('G', name, hx(path), rng.choice([1, 3, 7, 64, len(s2c)]), hx(s2c), render(initial, messages, status, message, trailing))


def start_server():
    global SERVER_PORT
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=8), options=[('grpc.so_reuseport', 0)])
    server.add_generic_rpc_handlers((grpc.method_handlers_generic_handler('test.Echo', HANDLERS),))
    SERVER_PORT = server.add_insecure_port('127.0.0.1:0')
    server.start()
    return server


def run_scenarios():
    def unary(method, payload=b'hello', **kw):
        def call(channel):
            stub = channel.unary_unary('/test.Echo/' + method)
            try:
                resp, cd = stub.with_call(payload, **kw)
                return ('ok', resp, cd.code(), cd.details(), cd.initial_metadata(), cd.trailing_metadata())
            except grpc.RpcError as e:
                return ('err', None, e.code(), e.details(), e.initial_metadata(), e.trailing_metadata())
        return call

    def expect_ok(payload):
        def check(outcome, messages, status, message, initial, trailing):
            assert outcome[0] == 'ok' and status == 0, (outcome, status)
            assert [m for c, m in messages if not c] and outcome[1] == [m for c, m in messages][0] or any(c for c, m in messages)
        return check

    scenario('unary', '/test.Echo/Unary', unary('Unary', b'hello \x00 world'), lambda o, m, s, msg, i, t: (
        o[0] == 'ok' and o[1] == b'dlrow \x00 olleh' and s == 0 and [x[1] for x in m] == [o[1]] or sys.exit('unary mismatch')))
    scenario('empty', '/test.Echo/Empty', unary('Empty', b'x'), lambda o, m, s, msg, i, t: (
        o[0] == 'ok' and o[1] == b'' and s == 0 and [x[1] for x in m] == [b''] or sys.exit('empty mismatch')))
    scenario('fail', '/test.Echo/Fail', unary('Fail'), lambda o, m, s, msg, i, t: (
        o[0] == 'err' and o[2] == grpc.StatusCode.NOT_FOUND and s == 5 and msg == o[3] == 'no such thing: café 100% done' and not m or sys.exit('fail mismatch')))
    scenario('meta', '/test.Echo/Meta', unary('Meta', b'm'), lambda o, m, s, msg, i, t: (
        o[0] == 'ok' and [x[1] for x in m] == [b'meta:m'] and ('x-init', 'first') in [(k, v) for k, v in o[4]] and ('x-trail', 'last') in [(k, v) for k, v in o[5]] or sys.exit('meta mismatch')))
    scenario('big', '/test.Echo/Big', unary('Big', b'b'), lambda o, m, s, msg, i, t: (
        o[0] == 'ok' and len(m) == 1 and len(m[0][1]) == 70000 and s == 0 or sys.exit('big mismatch')))
    scenario('gzip', '/test.Echo/Gzip', unary('Gzip', b'g', compression=grpc.Compression.Gzip), lambda o, m, s, msg, i, t: (
        o[0] == 'ok' and o[1] == b'compress me ' * 40 and m[0][0] and s == 0 or sys.exit('gzip mismatch')))
    scenario('statusmsg', '/test.Echo/StatusMessage', unary('StatusMessage'), lambda o, m, s, msg, i, t: (
        o[0] == 'err' and s == 8 and msg == 'quota ☃ exceeded' or sys.exit('statusmsg mismatch')))
    scenario('unimplemented', '/test.Echo/Nope', unary('Nope'), lambda o, m, s, msg, i, t: (
        o[0] == 'err' and s == 12 and not m or sys.exit('unimplemented mismatch')))

    def server_stream_call(channel):
        stub = channel.unary_stream('/test.Echo/ServerStream')
        return list(stub(b'ss'))

    scenario('serverstream', '/test.Echo/ServerStream', server_stream_call, lambda o, m, s, msg, i, t: (
        o == [b'ss\x00', b'ss\x01', b'ss\x02'] and [x[1] for x in m] == o and s == 0 or sys.exit('serverstream mismatch')))

    def client_stream_call(channel):
        stub = channel.stream_unary('/test.Echo/ClientStream')
        return stub(iter([b'a', b'bb', b'ccc']))

    scenario('clientstream', '/test.Echo/ClientStream', client_stream_call, lambda o, m, s, msg, i, t: (
        o == b'a|bb|ccc' and [x[1] for x in m] == [o] and s == 0 or sys.exit('clientstream mismatch')))

    def bidi_call(channel):
        stub = channel.stream_stream('/test.Echo/Bidi')
        return list(stub(iter([b'one', b'two', b'three'])))

    scenario('bidi', '/test.Echo/Bidi', bidi_call, lambda o, m, s, msg, i, t: (
        o == [b'ONE', b'TWO', b'THREE'] and [x[1] for x in m] == o and s == 0 or sys.exit('bidi mismatch')))


# ---- reference implementations of the specification's small functions ---------------------------------------------
def encode_timeout(nanos):
    """grpc-go internal/transport.encodeTimeout."""
    if nanos <= 0:
        return '0n'
    for unit, letter in ((1, 'n'), (1000, 'u'), (10 ** 6, 'm'), (10 ** 9, 'S'), (60 * 10 ** 9, 'M')):
        q = -(-nanos // unit)
        if q <= 99999999:
            return '%d%s' % (q, letter)
    return '%dH' % (-(-nanos // (3600 * 10 ** 9)))


def pct_encode(raw):
    out = ''
    for b in raw:
        if 0x20 <= b <= 0x7E and b != 0x25:
            out += chr(b)
        else:
            out += '%%%02X' % b
    return out


def frames_vectors():
    for nanos in [0, 1, 999, 99999999, 100000000, 100000001, 250000000, 1500000000, 99999999000, 100000000000, 5999999999999, 86400 * 10 ** 9, 10 ** 17, 2 ** 63]:
        add('O', nanos, encode_timeout(nanos))
    for text, want in [('100m', 100000000), ('1S', 10 ** 9), ('2M', 120 * 10 ** 9), ('1H', 3600 * 10 ** 9), ('5n', 5), ('7u', 7000), ('99999999n', 99999999),
                       ('', 'Invalid'), ('m', 'Invalid'), ('100', 'Invalid'), ('100x', 'Invalid'), ('123456789n', 'Invalid'), ('-5S', 'Invalid'), ('1.5S', 'Invalid')]:
        add('Op', hx(text), want)
    for payload, compressed in [(b'', False), (b'a', False), (b'hello', True), (bytes(range(256)), False)]:
        add('Mf', hx(payload), int(compressed), hx(bytes([int(compressed)]) + len(payload).to_bytes(4, 'big') + payload))
    for raw, want in [(b'\x00\x00\x00\x00\x03abc', 'ok:0:616263'), (b'\x01\x00\x00\x00\x01z', 'ok:1:7a'), (b'\x02\x00\x00\x00\x00', 'Invalid'),
                      (b'\x00\x00\x00', 'Incomplete'), (b'\x00\x00\x00\x00\x05ab', 'Incomplete'), (b'\x00\xff\xff\xff\xff', 'TooLarge')]:
        add('Md', hx(raw), want)
    for raw in [b'', b'plain ascii', b'100% sure', 'café ☃'.encode(), bytes(range(0, 256, 5)), b'\r\n\t']:
        add('Pe', hx(raw), hx(pct_encode(raw)))
    for text in ['%C3%A9', '100%', '%zz', '%4', 'a%20b', '%e2%98%83']:
        out = bytearray()
        raw = text.encode()
        i = 0
        while i < len(raw):
            if raw[i] == 0x25 and i + 2 < len(raw) and all(c in b'0123456789abcdefABCDEF' for c in raw[i + 1:i + 3]):
                out.append(int(raw[i + 1:i + 3], 16))
                i += 3
            else:
                out.append(raw[i])
                i += 1
        add('Pd', hx(text), hx(bytes(out)))
    for status, want in [(400, 13), (401, 16), (403, 7), (404, 12), (429, 14), (502, 14), (503, 14), (504, 14), (200, 2), (500, 2), (302, 2)]:
        add('Hs', status, want)
    for code in grpc.StatusCode:
        add('Sn', code.value[0], hx(code.name))
    for value in [b'', b'\x00', b'\x00\x01', b'\x00\x01\x02', bytes(range(20))]:
        add('Bn', hx(value), base64.b64encode(value).decode().rstrip('='))


# ---- client byte scenarios (Neper's output, read by h2 acting as a server) -----------------------------------------
def c_scenarios():
    out = []
    mk = lambda i: 'x-key-%d' % i
    out.append(dict(authority='localhost:50051', path='/test.Echo/Unary', timeout=0, metadata=[], messages=[b'hello'], mode='eos'))
    out.append(dict(authority='example.com', path='/pkg.Svc/Method', timeout=1500000000, metadata=[('x-a', 'b'), ('authorization', 'Bearer t')], messages=[b''], mode='eos'))
    out.append(dict(authority='127.0.0.1:1', path='/a.B/C', timeout=100000000, metadata=[('x-bin-bin', 'AAEC')], messages=[b'one', b'two', b'three'], mode='close'))
    out.append(dict(authority='h', path='/p.S/Stream', timeout=0, metadata=[], messages=[b'x' * 40000], mode='eos'))
    out.append(dict(authority='h', path='/p.S/Cancelled', timeout=250000000, metadata=[], messages=[b'abc'], mode='cancel'))
    out.append(dict(authority='h', path='/p.S/Open', timeout=0, metadata=[(mk(i), 'v' * i) for i in range(1, 6)], messages=[], mode='close'))
    return out


def c_line(index, sc, golden):
    meta = ','.join(hx(k) + '=' + hx(v) for k, v in sc['metadata']) or '-'
    msgs = ','.join('x' + hx(m) for m in sc['messages']) or '-'
    return 'C\t%d\t%s\t%s\t%d\t%s\t%s\t%s\t%s' % (index, hx(sc['authority']), hx(sc['path']), sc['timeout'], meta, msgs, sc['mode'], ('g' + golden) if golden else '')


def validate_client_bytes(sc, data):
    cfg = h2.config.H2Configuration(client_side=False)
    conn = h2.connection.H2Connection(config=cfg)
    conn.initiate_connection()
    events = conn.receive_data(data)
    request, body, ended, reset = None, b'', False, False
    for e in events:
        if isinstance(e, h2.events.RequestReceived):
            request = [(bytes(k).decode(), bytes(v).decode()) for k, v in e.headers]
        elif isinstance(e, h2.events.DataReceived):
            body += e.data
        elif isinstance(e, h2.events.StreamEnded):
            ended = True
        elif isinstance(e, h2.events.StreamReset):
            reset = True
            assert e.error_code == 8
    assert request is not None
    d = dict(request)
    assert d[':method'] == 'POST' and d[':path'] == sc['path'] and d[':authority'] == sc['authority'] and d[':scheme'] == 'http'
    assert d['content-type'] == 'application/grpc' and d['te'] == 'trailers'
    if sc['timeout']:
        assert d['grpc-timeout'] == encode_timeout(sc['timeout']), d['grpc-timeout']
    else:
        assert 'grpc-timeout' not in d
    for k, v in sc['metadata']:
        assert d[k] == v
    expected_body = b''.join(b'\x00' + len(m).to_bytes(4, 'big') + m for m in sc['messages'])
    if body != expected_body:
        pos, shown = 0, []
        raw = data[len(b'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n'):]
        while pos + 9 <= len(raw):
            f, length = hf.Frame.parse_frame_header(memoryview(raw[pos:pos + 9]))
            shown.append((type(f).__name__, f.stream_id, length, sorted(f.flags)))
            pos += 9 + length
        print('frames', shown, [type(e).__name__ for e in events])
    assert body == expected_body, (sc['path'], len(body), len(expected_body), body[:20], expected_body[:20])
    if sc['mode'] == 'cancel':
        assert reset and not ended
    else:
        assert ended and not reset


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', default=os.environ.get('NEPER_SELF', ''))
    args = ap.parse_args()
    if not args.compiler or not os.path.exists(args.compiler):
        sys.exit('--compiler (or NEPER_SELF) must name neper-self: the client goldens are produced by running it')
    server = start_server()
    run_scenarios()
    server.stop(0)
    frames_vectors()
    scs = c_scenarios()

    def write(path, final):
        vector_lines = list(lines)
        for i, sc in enumerate(scs):
            vector_lines.append(c_line(i, sc, final[i] if final else None))
        chunks, step = [], 4
        for i in range(0, len(vector_lines), step):
            body = '\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"').replace('\t', BS + 't') for l in vector_lines[i:i + step]) + '\n'
            chunks.append('"' + body.replace('\n', BS + 'n') + '"')
        funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
        calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, 100 + i) for i in range(len(chunks)))
        with open(os.path.join(ROOT, 'scripts', 'grpc_fixture_template.e'), encoding='utf-8') as f:
            template = f.read()
        text = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        return len(vector_lines), len(chunks)

    tmp = tempfile.mkdtemp(prefix='neper-grpc-')
    src = os.path.join(tmp, 'main.e')
    write(src, None)
    exe = os.path.join(tmp, 'emit.exe')
    r = subprocess.run([args.compiler, 'emit-executable', src, ROOT, 'x64', 'windows', exe], capture_output=True, text=True)
    if 'executable written' not in r.stdout:
        sys.exit('compile failed: ' + r.stdout + r.stderr)
    r = subprocess.run([exe], capture_output=True, text=True)
    goldens = {}
    for line in r.stdout.splitlines():
        if line.startswith('GOLD\t'):
            _, i, h = line.split('\t')
            goldens[int(i)] = h
    assert len(goldens) == len(scs), (len(goldens), r.returncode, r.stdout[:300], r.stderr[:300])
    final = {}
    for i, sc in enumerate(scs):
        validate_client_bytes(sc, bytes.fromhex(goldens[i]))
        final[i] = goldens[i]
    count, nchunks = write(os.path.join(FIXTURE_DIR, 'src', 'main.e'), final)
    print('%d vectors in %d chunks (%d client goldens verified by h2) -> net_grpc' % (count, nchunks, len(scs)))


main()
