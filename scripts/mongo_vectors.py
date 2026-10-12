"""Generate the x_mongodb_wire fixture: vectors from pymongo and the bson package (MongoDB's Python driver).

Oracle: pymongo's `_op_msg_no_header` frames OP_MSG messages (flag bits, body, one document sequence) and `bson.encode`
makes the documents and command bodies; pymongo's own `_authenticate_scram` runs against a scripted server (nonce
fixed through `os.urandom`) and gives the SCRAM-SHA-256 client messages, with the RFC 7677 vector asserted too; the
`crc32c` package gives the checksum (check value 0xE3069283 for "123456789"). Two-sequence messages and the error
cases have no driver builder and are written here by hand from the OP_MSG specification.

    PYTHONPATH=DIR python scripts/mongo_vectors.py
"""
import base64
import hashlib
import hmac
import os
import random
import struct
import sys

import bson
import crc32c
from bson.codec_options import DEFAULT_CODEC_OPTIONS as OPTS
from bson.binary import Binary
from pymongo import message as pm

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
rng = random.Random(0x4D4F4E47)
lines = []


def hx(b):
    if isinstance(b, str):
        b = b.encode('utf-8')
    return b.hex()


def add(*f):
    lines.append('\t'.join(str(x) for x in f))


def header(total, request_id, response_to, opcode=2013):
    return struct.pack('<iiii', total, request_id, response_to, opcode)


def doc():
    d = {}
    for i in range(rng.randrange(0, 5)):
        d['k%d' % i] = rng.choice([rng.randrange(-100, 100), 'str%d' % rng.randrange(100), True, None, 1.5, {'n': rng.randrange(9)}, [1, 2, 3], 2**40])
    return d


def frame(request_id, response_to, flags, command, seqs):
    """pymongo's builder for the body and one sequence; hand-built for more."""
    if len(seqs) <= 1 and (not seqs or seqs[0][1]):
        ident, docs = (seqs[0] if seqs else (None, None))
        body, _, _ = pm._op_msg_no_header(flags & ~1, command, ident, docs, OPTS)
        raw = header(16 + len(body), request_id, response_to) + body
    else:
        body = struct.pack('<I', flags & ~1) + b'\x00' + bson.encode(command)
        for ident, docs in seqs:
            enc = b''.join(bson.encode(d) for d in docs)
            body += b'\x01' + struct.pack('<i', 4 + len(ident) + 1 + len(enc)) + ident.encode() + b'\x00' + enc
        raw = header(16 + len(body), request_id, response_to) + body
    if flags & 1:
        raw = bytearray(raw)
        raw[16:20] = struct.pack('<I', flags)
        raw = bytes(raw) + struct.pack('<I', 0)
        raw = bytearray(raw)
        raw[0:4] = struct.pack('<i', len(raw))
        raw[-4:] = struct.pack('<I', crc32c.crc32c(bytes(raw[:-4])))
        raw = bytes(raw)
    return raw


def seq_text(seqs):
    return ';'.join('%s:%s' % (hx(ident), hx(b''.join(bson.encode(d) for d in docs))) for ident, docs in seqs)


# ---- frames and parses
for _ in range(60):
    command = {rng.choice(['insert', 'find', 'update', 'delete', 'aggregate']): 'coll', '$db': 'test'}
    command.update(doc())
    nseq = rng.choice([0, 0, 1, 1, 2])
    seqs = [(rng.choice(['documents', 'updates', 'deletes', 'x']) + str(i), [doc() for _ in range(rng.randrange(0, 4))]) for i in range(nseq)]
    flags = rng.choice([0, 0, 2, 65536, 1, 3, 65537])
    rid, rto = rng.randrange(1, 2**31 - 1), rng.choice([0, rng.randrange(1, 1000)])
    raw = frame(rid, rto, flags, command, seqs)
    body = bson.encode(command)
    add('F', rid, rto, flags, hx(body), seq_text(seqs), hx(raw))
    add('Q', hx(raw), 'ok', hx(body), seq_text(seqs), flags, rid, rto)

# truncations, corruption and unsupported shapes
base_cmd = {'ping': 1, '$db': 'admin'}
good = frame(5, 0, 1, base_cmd, [])
for cut in (3, 15, 16, 21, len(good) - 1):
    add('Q', hx(good[:cut]), 'Truncated', '', '', 0, 0, 0)
bad = bytearray(good)
bad[-1] ^= 0xFF
add('Q', hx(bytes(bad)), 'BadChecksum', '', '', 0, 0, 0)
comp = bytearray(frame(1, 0, 0, base_cmd, []))
comp[12:16] = struct.pack('<i', 2012)
add('Q', hx(bytes(comp)), 'Unsupported', '', '', 0, 0, 0)
legacy = bytearray(frame(1, 0, 0, base_cmd, []))
legacy[12:16] = struct.pack('<i', 1)
add('Q', hx(bytes(legacy)), 'Unsupported', '', '', 0, 0, 0)
flagged = bytearray(frame(1, 0, 0, base_cmd, []))
flagged[16:20] = struct.pack('<I', 4)
add('Q', hx(bytes(flagged)), 'Unsupported', '', '', 0, 0, 0)
two_bodies = bytearray(frame(1, 0, 0, base_cmd, []))
extra = b'\x00' + bson.encode({'x': 1})
two_bodies += extra
two_bodies[0:4] = struct.pack('<i', len(two_bodies))
add('Q', hx(bytes(two_bodies)), 'Invalid', '', '', 0, 0, 0)
no_body = header(16 + 4, 1, 0) + struct.pack('<I', 0)
add('Q', hx(no_body), 'Invalid', '', '', 0, 0, 0)
badkind = bytearray(frame(1, 0, 0, base_cmd, []))
badkind[20] = 9
add('Q', hx(bytes(badkind)), 'Invalid', '', '', 0, 0, 0)
badlen = bytearray(frame(1, 0, 0, base_cmd, []))
badlen[21:25] = struct.pack('<i', 9999)
add('Q', hx(bytes(badlen)), 'Truncated', '', '', 0, 0, 0)

# ---- command documents (`$db` appended)
def spec_and_doc():
    elems, d = [], {}
    d[rng.choice(['ping', 'hello', 'find', 'listDatabases', 'insert'])] = None
    name = next(iter(d))
    kinds = []
    first = rng.choice(['i32', 'str'])
    d[name] = 1 if first == 'i32' else 'coll'
    elems.append('%s:%s:%s' % (name, first, '1' if first == 'i32' else hx('coll')))
    for i in range(rng.randrange(0, 5)):
        k = 'f%d' % i
        t = rng.choice(['i32', 'i64', 'str', 'bool', 'dbl', 'null'])
        if t == 'i32':
            v = rng.randrange(-1000, 1000)
            d[k] = v
            elems.append('%s:i32:%d' % (k, v))
        elif t == 'i64':
            v = rng.choice([2**40, -2**40, 2**62])
            d[k] = bson.Int64(v)
            elems.append('%s:i64:%d' % (k, v))
        elif t == 'str':
            v = rng.choice(['', 'abc', 'héllo', 'a b'])
            d[k] = v
            elems.append('%s:str:%s' % (k, hx(v)))
        elif t == 'bool':
            v = rng.random() < 0.5
            d[k] = v
            elems.append('%s:bool:%d' % (k, int(v)))
        elif t == 'dbl':
            v = rng.choice([0.0, 1.5, -2.25, 1e100])
            d[k] = v
            elems.append('%s:dbl:%s' % (k, hx(struct.pack('>d', v))))
        else:
            d[k] = None
            elems.append('%s:null:' % k)
    return ';'.join(elems), d


for _ in range(25):
    spec, d = spec_and_doc()
    db = rng.choice(['admin', 'test', 'a.b'])
    d['$db'] = db
    add('W', hx(db), spec, hx(bson.encode(d)))

# ---- status replies
for d in [{'ok': 1.0}, {'ok': 1}, {'ok': 0.0, 'errmsg': 'not authorized', 'code': 13, 'codeName': 'Unauthorized'},
          {'ok': 0, 'errmsg': 'bad', 'code': bson.Int64(2)}, {'ok': 1.0, 'n': 3, 'cursor': {'id': bson.Int64(0), 'firstBatch': []}},
          {'ok': 0.0, 'code': 11000, 'codeName': 'DuplicateKey', 'errmsg': 'E11000 duplicate key'}]:
    add('S', hx(bson.encode(d)), 1 if d['ok'] == 1 else 0, d.get('code', 0), hx(d.get('codeName', '')), hx(d.get('errmsg', '')))
add('S', hx(bson.encode({'x': 1})), 'Invalid', 0, '', '')

# ---- SCRAM-SHA-256: pymongo's own client against a scripted server
from pymongo import auth_shared
from pymongo.synchronous import auth as sauth


def run_scram(user, password, nonce_raw, salt, iterations, server_extra):
    real = os.urandom
    os.urandom = lambda n: nonce_raw
    try:
        cred = auth_shared._build_credentials_tuple('SCRAM-SHA-256', 'admin', user, password, {}, None)
        sent = []

        class Conn:
            auth_ctx = None

            def command(self, source, cmd):
                sent.append(cmd)
                if 'saslStart' in cmd:
                    payload = bytes(cmd['payload'])
                    bare = payload[3:]
                    cnonce = [p for p in bare.split(b',') if p.startswith(b'r=')][0][2:]
                    server_first = b'r=' + cnonce + server_extra + b',s=' + base64.b64encode(salt) + b',i=' + str(iterations).encode()
                    self.server_first = server_first
                    self.bare = bare
                    return {'conversationId': 1, 'payload': Binary(server_first), 'done': False}
                final = bytes(cmd['payload'])
                salted = hashlib.pbkdf2_hmac('sha256', password.encode(), salt, iterations)
                server_key = hmac.new(salted, b'Server Key', hashlib.sha256).digest()
                auth_message = self.bare + b',' + self.server_first + b',' + final.rsplit(b',p=', 1)[0]
                sig = base64.b64encode(hmac.new(server_key, auth_message, hashlib.sha256).digest())
                self.server_final = b'v=' + sig
                return {'conversationId': 1, 'payload': Binary(self.server_final), 'done': True}

        conn = Conn()
        sauth._authenticate_scram(cred, conn, 'SCRAM-SHA-256')
        return bytes(sent[0]['payload']), conn.server_first, bytes(sent[1]['payload']), conn.server_final, bson.encode({**sent[0], '$db': 'admin'})
    finally:
        os.urandom = real


# RFC 7677 section 3: user "user", password "pencil", client nonce rOprNGfwEbeRWgbNEkqO.
rfc_nonce = b'rOprNGfwEbeRWgbNEkqO'
# pymongo base64-encodes os.urandom(32); raw bytes whose base64 is the RFC's literal nonce reproduce the RFC exchange.
first, server_first, final, server_final, start_doc = run_scram(
    'user', 'pencil', base64.b64decode(rfc_nonce), base64.b64decode('W22ZaJ0SNY7soEsUEjb6gQ=='), 4096, b'%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0')
assert first == b'n,,n=user,r=rOprNGfwEbeRWgbNEkqO'
assert final == b'c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ='
assert server_final == b'v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4='
add('A', hx('user'), hx('pencil'), hx(first), hx(server_first), hx(final), hx(server_final))
add('T', hx(start_doc))

for _ in range(10):
    user = rng.choice(['alice', 'bob', 'a=b', 'x,y', 'admin', 'u' + str(rng.randrange(1000))])
    password = ''.join(rng.choice('abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()') for _ in range(rng.randrange(1, 20)))
    nonce_raw = bytes(rng.randrange(256) for _ in range(32))
    salt = bytes(rng.randrange(256) for _ in range(rng.choice([16, 24, 32])))
    iterations = rng.choice([4096, 4096, 10000, 15000])
    extra = base64.b64encode(bytes(rng.randrange(256) for _ in range(rng.choice([12, 24, 30])))).strip(b'=')
    first, server_first, final, server_final, start_doc = run_scram(user, password, nonce_raw, salt, iterations, extra)
    add('A', hx(user), hx(password), hx(first), hx(server_first), hx(final), hx(server_final))

# ---- CRC-32C
assert crc32c.crc32c(b'123456789') == 0xE3069283
for n in [0, 1, 3, 4, 8, 31, 32, 100, 1000]:
    data = bytes(rng.randrange(256) for _ in range(n))
    add('K', hx(data), crc32c.crc32c(data))
add('K', hx(b'123456789'), 0xE3069283)

# ---- write
chunks, step = [], 25
for i in range(0, len(lines), step):
    body = '\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"').replace('\t', BS + 't') for l in lines[i:i + step]) + '\n'
    chunks.append('"' + body.replace('\n', BS + 'n') + '"')
funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, 100 + i) for i in range(len(chunks)))
with open(os.path.join(ROOT, 'scripts', 'mongo_fixture_template.e'), encoding='utf-8') as f:
    template = f.read()
out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
target = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'x_mongodb_wire', 'src', 'main.e')
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)
print('%d vectors in %d chunks -> x_mongodb_wire' % (len(lines), len(chunks)))
