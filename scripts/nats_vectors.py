"""Generate the net_nats fixture: vectors from nats-py (the NATS project's Python client), checked in this script.

Oracle: `nats-py` (pip install --target DIR nats-py) -- its protocol Parser decodes the server byte streams the fixture
feeds (at several chunk sizes), its command builders (nats.protocol.command) and publish/CONNECT code give the client
bytes, and `Client._process_headers` the header parse. Each stream's expected events are asserted equal to what the
parser dispatched before they are written out. Subject validity and matching have no library oracle: they follow the
NATS documentation and are written independently here (token split) of the Neper implementation.

    PYTHONPATH=DIR python scripts/nats_vectors.py
"""
import asyncio
import json
import os
import random
import re
import sys

import nats.aio.client as natsclient
from nats.protocol import command as cmd
from nats.protocol.parser import Parser

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
rng = random.Random(0x4E415453)
lines = []


def hx(b):
    if isinstance(b, str):
        b = b.encode('utf-8')
    return b.hex()


def add(*fields):
    lines.append('\t'.join(str(f) for f in fields))


# ---- server streams ------------------------------------------------------------------------------------------

class Recorder:
    def __init__(self):
        self.events = []

    async def _process_msg(self, sid, subject, reply, payload, hdr):
        self.events.append('MSG|%s|%d|%s|%s|%s' % (subject.decode(), sid, reply.decode(), hx(hdr or b''), hx(payload)))

    async def _process_ping(self):
        self.events.append('PING')

    async def _process_pong(self):
        self.events.append('PONG')

    async def _process_err(self, emsg):
        self.events.append('ERR|' + emsg)

    async def _process_info(self, info):
        self.events.append('INFO|' + info_line(info))


def info_line(info):
    return '|'.join(str(x) for x in [
        info.get('server_id', ''), info.get('version', ''), info.get('host', ''), info.get('port', 0),
        info.get('max_payload', 0), info.get('proto', 0), int(bool(info.get('headers', False))),
        int(bool(info.get('auth_required', False))), int(bool(info.get('tls_required', False))), info.get('nonce', '')])


def feed(stream, chunk):
    rec = Recorder()
    parser = Parser(rec)

    async def run():
        for i in range(0, len(stream), chunk):
            await parser.parse(stream[i:i + chunk])
    asyncio.run(run())
    return rec.events


TOK = 'abcdefghijklmnopqrstuvwxyz0123456789_-'


def subject(max_tokens=4):
    return '.'.join(''.join(rng.choice(TOK) for _ in range(rng.randrange(1, 8))) for _ in range(rng.randrange(1, max_tokens + 1)))


def payload():
    n = rng.choice([0, 1, 2, 5, 13, 64, 300, 1000])
    b = bytes(rng.randrange(256) for _ in range(n))
    if rng.random() < 0.3:
        b = b + b'\r\nMSG x 1 2\r\n' + b
    return b


def header_block(status=None, headers=()):
    h = b'NATS/1.0'
    if status:
        h += b' ' + status.encode()
    h += b'\r\n'
    for k, v in headers:
        h += k.encode() + b': ' + v.encode() + b'\r\n'
    return h + b'\r\n'


def hdrs():
    return [('X-%s' % ''.join(rng.choice('abcdefgh') for _ in range(4)) + str(i), ''.join(rng.choice('xyz 0123') for _ in range(rng.randrange(0, 12))).strip()) for i in range(rng.randrange(1, 4))]


def sp():
    return rng.choice([' ', ' ', ' ', '  ', '\t'])


def server_op():
    k = rng.random()
    if k < 0.45:
        s, sid, p = subject(), rng.randrange(1, 100000), payload()
        reply = subject(3) if rng.random() < 0.4 else ''
        line = 'MSG' + sp() + s + sp() + str(sid) + sp() + ((reply + sp()) if reply else '') + str(len(p)) + '\r\n'
        return line.encode() + p + b'\r\n', 'MSG|%s|%d|%s||%s' % (s, sid, reply, hx(p))
    if k < 0.65:
        s, sid, p = subject(), rng.randrange(1, 100000), payload()
        reply = subject(3) if rng.random() < 0.4 else ''
        h = header_block(rng.choice([None, '503', '404 No Messages', '100 Idle Heartbeat']) if rng.random() < 0.5 else None, hdrs() if rng.random() < 0.8 else [])
        if rng.random() < 0.15:
            p = b''
            h = header_block('503')
        total = len(h) + len(p)
        line = 'HMSG %s %d %s%d %d\r\n' % (s, sid, (reply + ' ') if reply else '', len(h), total)
        return line.encode() + h + p + b'\r\n', 'MSG|%s|%d|%s|%s|%s' % (s, sid, reply, hx(h), hx(p))
    if k < 0.72:
        return b'PING\r\n', 'PING'
    if k < 0.79:
        return b'PONG\r\n', 'PONG'
    if k < 0.85:
        return b'+OK\r\n', 'OK'
    if k < 0.92:
        text = rng.choice(['unknown protocol operation', 'authorization violation', 'stale connection', 'permissions violation for publish to "a.b"', 'maximum payload violation'])
        return ("-ERR '%s'\r\n" % text).encode(), "ERR|'%s'" % text
    info = {'server_id': 'N' + ''.join(rng.choice('ABCDEFGHJKLMNPQRSTUVWXYZ0123456789') for _ in range(12)), 'version': '2.10.%d' % rng.randrange(30),
            'host': '0.0.0.0', 'port': 4222, 'max_payload': rng.choice([1048576, 8388608, 1024]), 'proto': 1,
            'headers': rng.random() < 0.8, 'auth_required': rng.random() < 0.3, 'tls_required': rng.random() < 0.2,
            'nonce': 'n0nce' + str(rng.randrange(1000)), 'client_id': rng.randrange(1, 99999),
            'connect_urls': ['10.0.0.1:4222', '10.0.0.2:4222'], 'cluster': {'name': 'c1', 'x': [1, {'y': '}'}]}, 'ldm': False}
    text = json.dumps(info, sort_keys=rng.random() < 0.5)
    return ('INFO %s\r\n' % text).encode(), 'INFO|' + info_line(info)


def expected_for(events, stream_dispatched):
    return [e for e in events if e != 'OK'] == stream_dispatched


def gen_streams(count):
    for _ in range(count):
        ops = [server_op() for _ in range(rng.randrange(1, 7))]
        stream = b''.join(o[0] for o in ops)
        events = [o[1] for o in ops]
        for chunk in (len(stream), 1, 7, 64):
            got = feed(stream, chunk)
            assert got == [e for e in events if e != 'OK'], (chunk, got, events)
        add('P', rng.choice([1, 3, 7, 29, 64, len(stream)]), hx(stream), '~'.join(events), 0)
        # A truncated stream: the events that completed before the cut, then the leftover.
        if len(stream) > 4:
            cut = rng.randrange(1, len(stream))
            got = feed(stream[:cut], cut)
            consumed, k = 0, 0
            for s_, e in ops:
                if consumed + len(s_) <= cut:
                    consumed += len(s_)
                    k += 1
                else:
                    break
            want = [o[1] for o in ops[:k]]
            assert [e for e in want if e != 'OK'] == got, (got, want)
            add('P', rng.choice([1, 5, 64, cut]), hx(stream[:cut]), '~'.join(want), 1 if consumed < cut else 0)


gen_streams(120)

# ---- malformed streams (the verdicts are the protocol's: a line that is not an operation, a bad size, a missing CRLF)
for text, want in [
    (b'HELLO world\r\n', 'Invalid'), (b'MSG foo 1\r\n', 'Invalid'), (b'MSG foo x 3\r\nabc\r\n', 'Invalid'),
    (b'MSG foo 1 3\r\nabcXY', 'Invalid'), (b'MSG foo 1 -3\r\nabc\r\n', 'Invalid'), (b'MSG foo 1 5 3 9\r\nabc\r\n', 'Invalid'),
    (b'HMSG foo 1 9 3\r\nabc\r\n', 'Invalid'), (b'MSG foo..bar 1 3\r\nabc\r\n', 'Invalid'), (b'PING extra\r\n', 'Invalid'),
    (b'MSG foo 1 9999999999\r\n', 'TooLarge'), (b'INFO\r\n', 'Invalid'),
    (b'x' * 5000, 'TooLarge'), (b'MSG foo 1 3', 'Incomplete'), (b'', 'Incomplete'), (b'MSG foo 1 3\r\nab', 'Incomplete'),
]:
    add('B', hx(text), want)

# ---- CONNECT
def connect_expected(o):
    options = {'pedantic': o['pedantic'], 'verbose': o['verbose'], 'lang': o['lang'], 'version': o['version'], 'protocol': o['protocol']}
    if o['headers']:
        options['headers'] = True
    if o['no_responders']:
        options['no_responders'] = True
    if o['has_echo']:
        options['echo'] = o['echo']
    if o['tls']:
        options['tls_required'] = True
    for k_json, k in (('auth_token', 'token'), ('jwt', 'jwt'), ('name', 'name'), ('nkey', 'nkey'), ('pass', 'pass'), ('sig', 'sig'), ('user', 'user')):
        if o[k]:
            options[k_json] = o[k]
    return ('CONNECT ' + json.dumps(options, sort_keys=True) + '\r\n').encode()


STRINGS = ['', 'plain', 'with space', 'quote"inside', 'back\\slash', 'tab\there', 'new\nline', 'bell\x07x', 'del\x7fx', 'héllo', 'sn☃man', 'gr\U0001F600in', 'ÿĀ']
for _ in range(40):
    o = {'verbose': rng.random() < 0.5, 'pedantic': rng.random() < 0.3, 'headers': rng.random() < 0.7, 'no_responders': rng.random() < 0.7,
         'has_echo': rng.random() < 0.5, 'echo': rng.random() < 0.5, 'tls': rng.random() < 0.2,
         'name': rng.choice(STRINGS), 'user': rng.choice(STRINGS), 'pass': rng.choice(STRINGS), 'token': rng.choice(STRINGS),
         'jwt': rng.choice(['', 'eyJ0eXAi.e30.sig']), 'nkey': rng.choice(['', 'UABC']), 'sig': rng.choice(['', 'c2ln']),
         'lang': 'python3', 'version': '2.7.%d' % rng.randrange(20), 'protocol': rng.choice([0, 1])}
    add('C', *[int(o[k]) for k in ('verbose', 'pedantic', 'headers', 'no_responders', 'has_echo', 'echo', 'tls')],
        *[hx(o[k]) for k in ('name', 'user', 'pass', 'token', 'jwt', 'nkey', 'sig', 'lang', 'version')], o['protocol'], hx(connect_expected(o)))


# ---- client commands (nats-py's builders; its empty-reply double space is normalised to the single-space grammar)
def norm(b):
    first, sep, rest = b.partition(b'\r\n')
    return b' '.join(first.split()) + sep + rest


for _ in range(30):
    s = subject()
    reply = subject(3) if rng.random() < 0.5 else ''
    p = payload()
    add('U', hx(s), hx(reply), hx(p), hx(norm(cmd.pub_cmd(s, reply, p))))
for _ in range(25):
    s = subject()
    reply = subject(3) if rng.random() < 0.5 else ''
    p = payload()
    hl = []
    seen = set()
    for k, v in hdrs():
        if k not in seen:
            seen.add(k)
            hl.append((k, v))
    if rng.random() < 0.2:
        hl.append(('K-' + 'q', ' padded value '))
    if rng.random() < 0.15:
        hl.append(('Multi', 'line1\r\nline2'))
    h = bytearray(b'NATS/1.0\r\n')
    for k, v in hl:
        key = k.strip()
        h.extend(key.encode() + b': ' + v.strip().translate(str.maketrans({'\r': ' ', '\n': ' '})).encode() + b'\r\n')
    h.extend(b'\r\n')
    add('H', hx(s), hx(reply), ','.join(hx(k) + ':' + hx(v) for k, v in hl), hx(p), hx(norm(cmd.hpub_cmd(s, reply, bytes(h), p))))
for bad in ['Bad Name', 'Co:lon', 'ünï']:
    add('X', hx(subject()), hx('Foo'), hx(bad) + ':' + hx('v'))
for _ in range(15):
    s = rng.choice([subject(), 'foo.*', 'foo.>', '*.bar', '>'])
    q = rng.choice(['', 'workers', 'q.1'])
    sid = rng.randrange(1, 100000)
    add('S', hx(s), hx(q), sid, hx(norm(cmd.sub_cmd(s, q, sid))))
for sid, lim in [(1, 0), (77, 5), (123456, 1)]:
    add('N', sid, lim, hx(norm(cmd.unsub_cmd(sid, lim))))

# ---- header blocks
def parse_block(raw):
    nc = natsclient.Client()
    out = asyncio.run(nc._process_headers(raw))
    return out or {}


blocks = []
for _ in range(25):
    k = rng.random()
    hl = [(a, b) for a, b in hdrs()]
    names = {}
    for a, b in hl:
        names[a] = b
    hl = list(names.items())
    st = rng.choice([None, None, '503', '404 No Messages', '408 Request Timeout', '100 Idle Heartbeat'])
    if st == '503':
        # nats-py mis-reads a bare status code followed by headers (its description slice starts at the CRLF); the
        # server never sends one, so the case is not generated.
        hl = []
    raw = header_block(st, hl)
    blocks.append(raw)
blocks += [b'NATS/1.0\r\n\r\n', b'NATS/1.0 503\r\n\r\n', b'NATS/1.0\r\nA:b\r\nC:\td\r\n\r\n', b'NATS/1.0 100 Idle Heartbeat\r\nNats-Last-Consumer: 1016\r\nNats-Last-Stream: 1024\r\n\r\n']
for raw in blocks:
    got = parse_block(raw)
    status = int(got.get('Status', 0)) if str(got.get('Status', '0')).isdigit() else 0
    desc = got.get('Description', '')
    hs = [(k, v) for k, v in got.items() if k not in ('Status', 'Description')]
    add('D', hx(raw), status, hx(desc), ','.join(hx(k) + ':' + hx(v) for k, v in hs))
add('Z', hx(b'HTTP/1.1 200\r\n\r\n'))

# ---- subjects (documentation rules, independent implementation)
def py_valid(s, wild):
    if not s or any(c.isspace() for c in s):
        return False
    toks = s.split('.')
    for i, t in enumerate(toks):
        if t == '':
            return False
        if t == '>':
            if not wild or i != len(toks) - 1:
                return False
        elif t == '*':
            if not wild:
                return False
        elif ('*' in t or '>' in t) and not wild:
            return False
    return True


def py_match(pat, sub):
    p, s = pat.split('.'), sub.split('.')
    for i, t in enumerate(p):
        if t == '>' and i == len(p) - 1:
            return len(s) > i
        if i >= len(s):
            return False
        if t != '*' and t != s[i]:
            return False
    return len(p) == len(s)


cases = ['foo', 'foo.bar', 'foo.*', 'foo.>', '>', '*', '*.*', 'foo.*.baz', 'foo..bar', '.foo', 'foo.', 'foo bar', '', 'foo.>.bar',
         'f*o', 'a.b.c.d.e', '>.x', 'fo>', 'foo.b*r', '$JS.API.>', '_INBOX.abc.*']
for c in cases:
    add('V', hx(c), 0, int(py_valid(c, False)))
    add('V', hx(c), 1, int(py_valid(c, True)))
pats = ['foo', 'foo.bar', 'foo.*', 'foo.>', '>', '*', '*.*', 'foo.*.baz', '*.bar', 'a.*.c.>']
subs = ['foo', 'foo.bar', 'foo.bar.baz', 'foo.x.baz', 'bar', 'x.bar', 'a.b.c.d', 'a.b.c', 'foo.baz']
for p in pats:
    for s in subs:
        add('M', hx(p), hx(s), int(py_match(p, s)))

# ---- the scripted session's client bytes, from nats-py's builders and CONNECT code
connect = json.dumps({'headers': True, 'lang': 'neper', 'name': 't1', 'no_responders': True, 'pedantic': False,
                      'protocol': 1, 'verbose': False, 'version': '0.1'}, sort_keys=True)
CRLF = bytes([13, 10])
session_sent = (('CONNECT ' + connect).encode() + CRLF + b'PING' + CRLF + norm(cmd.sub_cmd('orders.*', 'workers', 1))
                + norm(cmd.sub_cmd('_INBOX.abc.*', '', 2)) + norm(cmd.unsub_cmd(2, 2))
                + norm(cmd.pub_cmd('svc.echo', '_INBOX.abc.7', b'hi')) + b'PONG' + CRLF)

# ---- write fixture
chunks, step = [], 40
for i in range(0, len(lines), step):
    body = '\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"').replace('\t', BS + 't') for l in lines[i:i + step]) + '\n'
    chunks.append('"' + body.replace('\n', BS + 'n') + '"')
funcs = 'fn session_sent() -> str { ret "%s" }\n\n' % session_sent.hex() + '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, 100 + i) for i in range(len(chunks)))
with open(os.path.join(ROOT, 'scripts', 'nats_fixture_template.e'), encoding='utf-8') as f:
    template = f.read()
out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
target = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_nats', 'src', 'main.e')
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)
print('%d vectors in %d chunks -> net_nats' % (len(lines), len(chunks)))
