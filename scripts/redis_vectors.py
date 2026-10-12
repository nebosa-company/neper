"""Generate the x_redis_resp fixture: vectors from redis-py (the Redis project's Python client).

Oracle: redis-py's own RESP2 and RESP3 parsers decode every generated reply stream (type-erased: it cannot tell a
simple string from a bulk string, so the generator keeps the typed model and asserts the library's reading equals the
model's erased form), `Connection.pack_command` gives the command bytes, `redis.crc.key_slot` the cluster slots and
`redis.exceptions.AskError`/`MovedError` the redirects. Pub/sub and session accounting have no library oracle (the
client classes need a live connection): they are model-defined and checked in the fixture's scripted session.

    PYTHONPATH=DIR python scripts/redis_vectors.py
"""
import os
import random
import struct
import sys

import redis.exceptions as rex
from redis._parsers import resp2, resp3
from redis.connection import Connection
from redis.crc import key_slot

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
rng = random.Random(0x52455331)
lines = []


def hx(b):
    if isinstance(b, str):
        b = b.encode('utf-8')
    return b.hex()


def add(*f):
    lines.append('\t'.join(str(x) for x in f))


class FakeBuffer:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def get_pos(self):
        return self.pos

    def rewind(self, pos):
        self.pos = pos

    def purge(self):
        pass

    def readline(self, timeout=None):
        i = self.data.find(b'\r\n', self.pos)
        if i < 0:
            raise rex.ConnectionError('short')
        line = self.data[self.pos:i]
        self.pos = i + 2
        return line

    def read(self, n, timeout=None):
        out = self.data[self.pos:self.pos + n]
        if len(out) < n or self.data[self.pos + n:self.pos + n + 2] != b'\r\n':
            raise rex.ConnectionError('short')
        self.pos += n + 2
        return out


def lib_parse(stream, proto):
    cls = resp2._RESP2Parser if proto == 2 else resp3._RESP3Parser
    parser = cls(65536)
    parser.encoder = type('E', (), {'decode': staticmethod(lambda x: x)})()
    parser._buffer = FakeBuffer(stream)
    out = []
    while parser._buffer.pos < len(stream):
        if proto == 3:
            out.append(parser.read_response(push_request=True))
        else:
            out.append(parser.read_response())
    return out


# ---- the typed model --------------------------------------------------------------------------------------------
# ('N',) ('+',b) ('-',b) (':',n) ('$',b) ('*',[..]) ('#',bool) (',',float) ('(',str) ('!',b) ('=',fmt,b) ('%',[(k,v)]) ('~',[..]) ('>',[..])

def blob(maxlen=40):
    n = rng.choice([0, 1, 2, 3, 7, 20, maxlen])
    b = bytes(rng.randrange(256) for _ in range(n))
    if rng.random() < 0.25:
        b += b'\r\n$3\r\nfoo' + b
    return b


def text(n=12):
    return bytes(rng.choice(b'abcdefghijkl mnop0123') for _ in range(rng.randrange(0, n)))


def gen(proto, depth=0):
    r2 = [('N',), ('+',), ('-',), (':',), ('$',), ('$N',), ('*N',)]
    k = rng.random()
    if depth < 3 and k < 0.25:
        return ('*', [gen(proto, depth + 1) for _ in range(rng.randrange(0, 5))])
    if proto == 3 and depth < 3 and k < 0.40:
        kind = rng.choice(['%', '~'])
        if kind == '%':
            return ('%', [(rng.choice([('$', blob(6)), (':', rng.randrange(-5, 5)), ('+', text(5))]), gen(proto, depth + 1)) for _ in range(rng.randrange(0, 4))])
        return ('~', [gen(proto, depth + 1) for _ in range(rng.randrange(0, 4))])
    c = rng.choice(['N', '+', '-', ':', '$', '$', '$'] + (['#', ',', '(', '!', '=', '_'] if proto == 3 else ['$N', '*N']))
    if c == 'N' or c == '_':
        return ('N', '_' if proto == 3 else '$-1')
    if c == '$N':
        return ('N', '$-1')
    if c == '*N':
        return ('N', '*-1')
    if c == '+':
        return ('+', text())
    if c == '-':
        return ('-', rng.choice([b'ERR unknown command', b'WRONGTYPE Operation against a key', b'READONLY You can\'t write against a read only replica.', b'MOVED 3999 127.0.0.1:6381', b'ASK 3999 127.0.0.1:6381', b'NOSCRIPT No matching script', b'custom failure']))
    if c == ':':
        return (':', rng.choice([0, 1, -1, 42, -9223372036854775808, 9223372036854775807, rng.randrange(-10**6, 10**6)]))
    if c == '$':
        return ('$', blob())
    if c == '#':
        return ('#', rng.random() < 0.5)
    if c == ',':
        return (',', rng.choice([0.0, 1.5, -2.25, 3.14159, 1e100, float('inf'), float('-inf'), 123456789.0, 0.1]))
    if c == '(':
        return ('(', rng.choice(['3492890328409238509324850943850943825024385', '-3492890328409238509324850943850943825024385', '0', '12345678901234567890']))
    if c == '!':
        return ('!', rng.choice([b'SYNTAX invalid syntax', b'ERR something']))
    if c == '=':
        return ('=', rng.choice([b'txt', b'mkd']), text(20))
    return ('N', '$-1')


def ser(v, proto):
    t = v[0]
    if t == 'N':
        return (v[1] if len(v) > 1 else ('_' if proto == 3 else '$-1')).encode() + b'\r\n'
    if t == '+':
        return b'+' + v[1] + b'\r\n'
    if t == '-':
        return b'-' + v[1] + b'\r\n'
    if t == ':':
        return b':%d\r\n' % v[1]
    if t == '$':
        return b'$%d\r\n' % len(v[1]) + v[1] + b'\r\n'
    if t == '*':
        return b'*%d\r\n' % len(v[1]) + b''.join(ser(x, proto) for x in v[1])
    if t == '~':
        return b'~%d\r\n' % len(v[1]) + b''.join(ser(x, proto) for x in v[1])
    if t == '>':
        return b'>%d\r\n' % len(v[1]) + b''.join(ser(x, proto) for x in v[1])
    if t == '%':
        return b'%%%d\r\n' % len(v[1]) + b''.join(ser(k, proto) + ser(x, proto) for k, x in v[1])
    if t == '#':
        return b'#t\r\n' if v[1] else b'#f\r\n'
    if t == ',':
        f = v[1]
        s = 'inf' if f == float('inf') else '-inf' if f == float('-inf') else repr(f)
        return b',' + s.encode() + b'\r\n'
    if t == '(':
        return b'(' + v[1].encode() + b'\r\n'
    if t == '!':
        return b'!%d\r\n' % len(v[1]) + v[1] + b'\r\n'
    if t == '=':
        body = v[1] + b':' + v[2]
        return b'=%d\r\n' % len(body) + body + b'\r\n'
    raise ValueError(t)


def render(v):
    """The fixture's typed text."""
    t = v[0]
    if t == 'N':
        return 'N'
    if t in '+-$!':
        return t + hx(v[1])
    if t == ':':
        return ':%d' % v[1]
    if t in '*~>':
        return t + '[' + ','.join(render(x) for x in v[1]) + ']'
    if t == '%':
        return '%[' + ','.join(render(k) + '=' + render(x) for k, x in v[1]) + ']'
    if t == '#':
        return '#t' if v[1] else '#f'
    if t == ',':
        return ',' + hx(struct.pack('>d', v[1]))
    if t == '(':
        return '(' + hx(v[1])
    if t == '=':
        return '=' + hx(v[1]) + ':' + hx(v[2])
    raise ValueError(t)


def erase(v):
    t = v[0]
    if t == 'N':
        return None
    if t in '+$':
        return v[1]
    if t == ':':
        return v[1]
    if t == '-' or t == '!':
        return ('ERR', v[1])
    if t == '*' or t == '~' or t == '>':
        return [erase(x) for x in v[1]]
    if t == '%':
        return {('K', erase(k) if not isinstance(erase(k), list) else tuple(erase(k))): erase(x) for k, x in v[1]}
    if t == '#':
        return v[1]
    if t == ',':
        return v[1]
    if t == '(':
        return int(v[1])
    if t == '=':
        return v[2]
    raise ValueError(t)


def lib_erase(x):
    if isinstance(x, rex.ResponseError) or isinstance(x, Exception):
        return ('ERR', None)
    if isinstance(x, list):
        return [lib_erase(i) for i in x]
    if isinstance(x, dict):
        return {('K', k): lib_erase(v) for k, v in x.items()}
    return x


def norm_err(x):
    if isinstance(x, tuple) and x and x[0] == 'ERR':
        return ('ERR', None)
    if isinstance(x, list):
        return [norm_err(i) for i in x]
    if isinstance(x, dict):
        return {k: norm_err(v) for k, v in x.items()}
    return x


def gen_streams(proto, count):
    for _ in range(count):
        replies = []
        for _ in range(rng.randrange(1, 5)):
            v = gen(proto)
            replies.append(v)
        if proto == 3 and rng.random() < 0.15:
            replies.append(('>', [('$', b'message'), ('$', b'chan'), ('$', blob(10))]))
        stream = b''.join(ser(v, proto) for v in replies)
        got = lib_parse(stream, proto)
        want = [norm_err(erase(v)) for v in replies]
        # redis-py returns map keys as bytes/ints; a nested key becomes a tuple only in our erased form.
        def fix(x):
            if isinstance(x, dict):
                return {k[1] if isinstance(k, tuple) and k and k[0] == 'K' else k: fix(v) for k, v in x.items()}
            if isinstance(x, list):
                return [fix(i) for i in x]
            return x
        gotn = norm_err(lib_erase(got))
        assert fix(gotn) == fix(want), (proto, replies, gotn, want)
        rendered = ';'.join(render(v) for v in replies)
        cut = None
        if rng.random() < 0.3 and len(stream) > 2:
            cut = rng.randrange(1, len(stream))
        add('R', proto, rng.choice([1, 2, 5, 17, 64, len(stream)]), hx(stream), rendered, 0)
        if cut is not None:
            # the replies that are wholly inside the cut, then leftover
            consumed, k = 0, 0
            for v in replies:
                sz = len(ser(v, proto))
                if consumed + sz <= cut:
                    consumed += sz
                    k += 1
                else:
                    break
            add('R', proto, rng.choice([1, 3, 64]), hx(stream[:cut]), ';'.join(render(v) for v in replies[:k]), 1 if consumed < cut else 0)


gen_streams(2, 80)
gen_streams(3, 100)

# ---- malformed
for data, want in [(b'?abc\r\n', 'Invalid'), (b':12x\r\n', 'Invalid'), (b'$3\r\nabcde\r\n', 'Invalid'), (b'$-5\r\n', 'Invalid'),
                   (b'*2\r\n:1\r\n', 'Incomplete'), (b'$3\r\nab', 'Incomplete'), (b'', 'Incomplete'), (b'+OK', 'Incomplete'),
                   (b'#x\r\n', 'Invalid'), (b'_x\r\n', 'Invalid'), (b'$600000000\r\n', 'TooLarge'), (b'*100000000\r\n', 'TooLarge'),
                   (b'=3\r\nabc\r\n', 'Invalid'), (b':9223372036854775808\r\n', 'Invalid'), (b'+OK\rX', 'Invalid'),
                   (b'*' + b'1\r\n*' * 40 + b'0\r\n', 'TooLarge')]:
    add('B', hx(data), want)

# ---- commands (redis-py's pack_command)
conn = Connection()
for _ in range(40):
    args = [blob(30) if rng.random() < 0.5 else text(10) for _ in range(rng.randrange(1, 6))]
    # redis-py splits a first argument that contains a space into several (a command with a subcommand): the
    # command word is a plain token here.
    args[0] = rng.choice([b'SET', b'GET', b'HSET', b'XADD', b'x', b'CLIENT'])
    if rng.random() < 0.1:
        args.append(b'x' * 70000)
    packed = b''.join(conn.pack_command(*args))
    add('C', ','.join('x' + hx(a) if len(a) < 100 else 'L%d' % len(a) for a in args), hx(packed) if len(packed) < 2000 else 'S' + str(len(packed)))

# ---- cluster slots
keys = [b'', b'foo', b'bar', b'123456789', b'{user1000}.following', b'{user1000}.followers', b'foo{}{bar}', b'foo{{bar}}zap', b'foo{bar}{zap}',
        b'{', b'}', b'{}', b'a{b', b'a}b{c}', b'{a}', b'abc{def}ghi{jkl}', bytes(range(256))]
keys += [bytes(rng.randrange(256) for _ in range(rng.randrange(0, 30))) for _ in range(40)]
for k in keys:
    add('K', hx(k), key_slot(k))
assert key_slot(b'123456789') == 12739

# ---- redirects
for text_, ask in [('MOVED 3999 127.0.0.1:6381', False), ('ASK 12182 10.0.0.5:7001', True), ('MOVED 0 host.example:1', False),
                   ('MOVED 16383 [::1]:6380', False), ('ASK 7 :7000', True)]:
    cls = rex.AskError if ask else rex.MovedError
    e = cls(text_.split(' ', 1)[1])
    add('M', hx(text_), 1, int(ask), e.slot_id, hx(e.host), e.port)
for bad in ['MOVED x 1.1.1.1:1', 'MOVED 3999', 'MOVED 3999 host', 'MOVED 99999 h:1', 'MOVED 1 h:99999', 'ERR MOVED 1 h:1', 'ASK 1 h:x']:
    add('M', hx(bad), 0, 0, 0, '', 0)

# ---- error classes (the classes redis-py maps; the others stay generic)
EC = {'LOADING Redis is loading': 'Loading', 'NOSCRIPT No matching script': 'NoScript', 'READONLY ro': 'ReadOnly', 'NOAUTH x': 'NoAuth',
      'WRONGPASS invalid': 'NoAuth', 'WRONGTYPE bad': 'WrongType', 'MOVED 1 h:1': 'Moved', 'ASK 1 h:1': 'Ask', 'TRYAGAIN x': 'TryAgain',
      'CLUSTERDOWN x': 'ClusterDown', 'MASTERDOWN x': 'MasterDown', 'BUSY script': 'Busy', 'ERR plain': 'Generic', 'oops': 'Generic'}
for t, k in EC.items():
    add('E', hx(t), k)
# redis-py's own class for the ones it maps (a guard that the table above agrees with the library)
parser = resp2._RESP2Parser(1024)
for t, cls in [('LOADING x', rex.BusyLoadingError), ('NOSCRIPT x', rex.NoScriptError), ('READONLY x', rex.ReadOnlyError),
               ('NOAUTH x', rex.AuthenticationError), ('WRONGPASS x', rex.AuthenticationError)]:
    assert isinstance(parser.parse_error(t), cls), t

# ---- write
chunks, step = [], 30
for i in range(0, len(lines), step):
    body = '\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"').replace('\t', BS + 't') for l in lines[i:i + step]) + '\n'
    chunks.append('"' + body.replace('\n', BS + 'n') + '"')
funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, 100 + i) for i in range(len(chunks)))
with open(os.path.join(ROOT, 'scripts', 'redis_fixture_template.e'), encoding='utf-8') as f:
    template = f.read()
out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
target = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'x_redis_resp', 'src', 'main.e')
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)
print('%d vectors in %d chunks -> x_redis_resp' % (len(lines), len(chunks)))
