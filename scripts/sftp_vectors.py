"""Generate the net_sftp fixture: e.net.sftp (SFTP version 3 packets) against OpenSSH's sftp-server.

A scripted session is run against a real `sftp-server` (the one of Git for Windows, C:/Program Files/Git/usr/lib/ssh, or
any on PATH) with an independent encoder written here from draft-ietf-secsh-filexfer-02: the server's answers are
recorded with the request bytes and an independent decoder's reading of them. The fixture replays each line: the module
must encode the same bytes and read the same meaning. The session also checks what the server did (the bytes written are
the bytes read back, the sizes and permissions the attributes say, the directory listing names what was made), so the
requests are shown to be well formed by something other than this script.

    python scripts/sftp_vectors.py
"""
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, 'scripts', 'sftp_fixture_template.e')
FIXTURE = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_sftp', 'src', 'main.e')
GIT_SSH = r'C:\Program Files\Git\usr\lib\ssh\sftp-server.exe'

K = dict(INIT=1, VERSION=2, OPEN=3, CLOSE=4, READ=5, WRITE=6, LSTAT=7, FSTAT=8, SETSTAT=9, FSETSTAT=10, OPENDIR=11, READDIR=12,
         REMOVE=13, MKDIR=14, RMDIR=15, REALPATH=16, STAT=17, RENAME=18, READLINK=19, SYMLINK=20, STATUS=101, HANDLE=102,
         DATA=103, NAME=104, ATTRS=105, EXTENDED=200, EXTENDED_REPLY=201)
MAX_PACKET = 1048576


# --- the independent encoder -------------------------------------------------------------------------------------------

def s32(v):
    return struct.pack('>I', v)


def s64(v):
    return struct.pack('>Q', v)


def sstr(b):
    if isinstance(b, str):
        b = b.encode('utf-8')
    return s32(len(b)) + b


def attrs_bytes(a):
    flags = a.get('flags', 0) & 0xF
    out = s32(flags)
    if flags & 1:
        out += s64(a['size'])
    if flags & 2:
        out += s32(a['uid']) + s32(a['gid'])
    if flags & 4:
        out += s32(a['permissions'])
    if flags & 8:
        out += s32(a['atime']) + s32(a['mtime'])
    return out


def packet(kind, body):
    return struct.pack('>IB', len(body) + 1, kind) + body


def encode(op):
    n = op['op']
    i = op.get('id', 0)
    h = bytes.fromhex(op['handle']) if 'handle' in op else b''
    if n == 'init':
        return packet(K['INIT'], s32(op['version']))
    if n == 'open':
        return packet(K['OPEN'], s32(i) + sstr(op['path']) + s32(op['flags']) + attrs_bytes(op['attrs']))
    if n in ('close', 'fstat', 'readdir'):
        return packet(K[n.upper()], s32(i) + sstr(h))
    if n == 'read':
        return packet(K['READ'], s32(i) + sstr(h) + s64(op['offset']) + s32(op['length']))
    if n == 'write':
        return packet(K['WRITE'], s32(i) + sstr(h) + s64(op['offset']) + sstr(bytes.fromhex(op['data'])))
    if n in ('stat', 'lstat', 'opendir', 'remove', 'rmdir', 'realpath', 'readlink'):
        return packet(K[n.upper()], s32(i) + sstr(op['path']))
    if n in ('mkdir', 'setstat'):
        return packet(K[n.upper()], s32(i) + sstr(op['path']) + attrs_bytes(op['attrs']))
    if n == 'fsetstat':
        return packet(K['FSETSTAT'], s32(i) + sstr(h) + attrs_bytes(op['attrs']))
    if n in ('rename', 'symlink'):
        return packet(K[n.upper()], s32(i) + sstr(op['first']) + sstr(op['second']))
    if n == 'ext_paths':
        return packet(K['EXTENDED'], s32(i) + sstr(op['name']) + sstr(op['first']) + sstr(op['second']))
    if n == 'ext':
        return packet(K['EXTENDED'], s32(i) + sstr(op['name']) + bytes.fromhex(op['data']))
    raise ValueError(n)


# --- the independent decoder -------------------------------------------------------------------------------------------

class Bad(Exception):
    pass


def take(p, at):
    if at + 4 > len(p):
        raise Bad
    n = struct.unpack_from('>I', p, at)[0]
    if at + 4 + n > len(p):
        raise Bad
    return p[at + 4:at + 4 + n], at + 4 + n


def take_attrs(p, at):
    a = dict(flags=0, size=0, uid=0, gid=0, permissions=0, atime=0, mtime=0, extended=0)
    if at + 4 > len(p):
        raise Bad
    a['flags'] = struct.unpack_from('>I', p, at)[0]
    at += 4
    f = a['flags']
    if f & 1:
        if at + 8 > len(p):
            raise Bad
        a['size'] = struct.unpack_from('>Q', p, at)[0]
        at += 8
    if f & 2:
        if at + 8 > len(p):
            raise Bad
        a['uid'], a['gid'] = struct.unpack_from('>II', p, at)
        at += 8
    if f & 4:
        if at + 4 > len(p):
            raise Bad
        a['permissions'] = struct.unpack_from('>I', p, at)[0]
        at += 4
    if f & 8:
        if at + 8 > len(p):
            raise Bad
        a['atime'], a['mtime'] = struct.unpack_from('>II', p, at)
        at += 8
    if f & 0x80000000:
        if at + 4 > len(p):
            raise Bad
        cnt = struct.unpack_from('>I', p, at)[0]
        at += 4
        a['extended'] = cnt
        for _ in range(cnt):
            _, at = take(p, at)
            _, at = take(p, at)
    return a, at


def decode(data, names_cap=64):
    """The canonical meaning of one packet, or {'error': ...}; mirrors the module's checks in the order it makes them."""
    if len(data) < 4:
        return {'error': 'incomplete'}
    length = struct.unpack_from('>I', data, 0)[0]
    if length > MAX_PACKET:
        return {'error': 'toolarge'}
    if length < 1:
        return {'error': 'invalid'}
    if len(data) < 4 + length:
        return {'error': 'incomplete'}
    p = data[4:4 + length]
    kind = p[0]
    out = {'kind': kind}
    try:
        if kind == K['VERSION']:
            if len(p) < 5:
                raise Bad
            out['version'] = struct.unpack_from('>I', p, 1)[0]
            at, cnt = 5, 0
            while at < len(p):
                _, at = take(p, at)
                _, at = take(p, at)
                cnt += 1
            out['extensions'] = cnt
            return out
        if len(p) < 5:
            raise Bad
        out['id'] = struct.unpack_from('>I', p, 1)[0]
        at = 5
        if kind == K['STATUS']:
            if at + 4 > len(p):
                raise Bad
            out['status'] = struct.unpack_from('>I', p, at)[0]
            at += 4
            out['message'], out['language'] = '', ''
            if at < len(p):
                m, at = take(p, at)
                l, at = take(p, at)
                out['message'], out['language'] = m.decode('latin-1'), l.decode('latin-1')
        elif kind == K['HANDLE']:
            hnd, at = take(p, at)
            out['handle'] = hnd.hex()
        elif kind == K['DATA']:
            d, at = take(p, at)
            out['data'] = d.hex()
        elif kind == K['NAME']:
            if at + 4 > len(p):
                raise Bad
            cnt = struct.unpack_from('>I', p, at)[0]
            at += 4
            if cnt > names_cap:
                return {'error': 'toosmall'}
            names = []
            for _ in range(cnt):
                f, at = take(p, at)
                l, at = take(p, at)
                a, at = take_attrs(p, at)
                names.append({'filename': f.decode('latin-1'), 'longname': l.decode('latin-1'), 'attrs': a})
            out['names'] = names
        elif kind == K['ATTRS']:
            a, at = take_attrs(p, at)
            out['attrs'] = a
        elif kind == K['EXTENDED_REPLY']:
            out['data'] = p[at:].hex()
            at = len(p)
        else:
            raise Bad
        if at != len(p):
            raise Bad
    except Bad:
        return {'error': 'invalid'}
    return out


# --- the session -------------------------------------------------------------------------------------------------------

def find_server():
    for c in (GIT_SSH, shutil.which('sftp-server'), '/usr/lib/openssh/sftp-server', '/usr/lib/ssh/sftp-server'):
        if c and os.path.exists(c):
            return c
    sys.exit('no sftp-server found')


class Session:
    def __init__(self, cwd):
        env = dict(os.environ)
        env['PATH'] = r'C:\Program Files\Git\usr\bin;' + env.get('PATH', '')
        self.p = subprocess.Popen([find_server()], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=cwd, env=env)
        self.lines = []
        self.next_id = 1

    def raw(self, req):
        self.p.stdin.write(req)
        self.p.stdin.flush()
        head = self.p.stdout.read(4)
        n = struct.unpack('>I', head)[0]
        return head + self.p.stdout.read(n)

    def do(self, op):
        op = dict(op)
        if op['op'] != 'init':
            op['id'] = self.next_id
            self.next_id += 1
        req = encode(op)
        resp = self.raw(req)
        meaning = decode(resp)
        assert 'error' not in meaning, (op, meaning)
        self.lines.append({'op': op, 'req': req.hex(), 'resp': resp.hex(), 'e': meaning})
        return meaning


def main():
    work = tempfile.mkdtemp(prefix='sftpv')
    s = Session(work)
    ok = lambda m, st=0: (m['kind'] == K['STATUS'] and m['status'] == st) or sys.exit(f'unexpected {m} for {s.lines[-1]["op"]}')
    v = s.do({'op': 'init', 'version': 3})
    assert v['kind'] == K['VERSION'] and v['version'] == 3
    ok(s.do({'op': 'mkdir', 'path': 'd1', 'attrs': {'flags': 4, 'permissions': 0o755}}))
    ok(s.do({'op': 'mkdir', 'path': 'd1', 'attrs': {'flags': 0}}), 4)  # already there: FAILURE
    m = s.do({'op': 'open', 'path': 'f1.txt', 'flags': 2 | 8 | 16, 'attrs': {'flags': 4, 'permissions': 0o644}})
    assert m['kind'] == K['HANDLE']
    h = m['handle']
    ok(s.do({'op': 'write', 'handle': h, 'offset': 0, 'data': b'hello world'.hex()}))
    ok(s.do({'op': 'write', 'handle': h, 'offset': 11, 'data': b'!!'.hex()}))
    m = s.do({'op': 'fstat', 'handle': h})
    assert m['kind'] == K['ATTRS'] and m['attrs']['size'] == 13 and m['attrs']['flags'] & 1
    ok(s.do({'op': 'fsetstat', 'handle': h, 'attrs': {'flags': 8, 'atime': 1700000000, 'mtime': 1700000100}}))
    ok(s.do({'op': 'close', 'handle': h}))
    m = s.do({'op': 'open', 'path': 'f1.txt', 'flags': 1, 'attrs': {'flags': 0}})
    h = m['handle']
    m = s.do({'op': 'read', 'handle': h, 'offset': 0, 'length': 5})
    assert m['kind'] == K['DATA'] and bytes.fromhex(m['data']) == b'hello'
    m = s.do({'op': 'read', 'handle': h, 'offset': 5, 'length': 100})
    assert bytes.fromhex(m['data']) == b' world!!'
    ok(s.do({'op': 'read', 'handle': h, 'offset': 13, 'length': 10}), 1)  # EOF
    ok(s.do({'op': 'close', 'handle': h}))
    m = s.do({'op': 'stat', 'path': 'f1.txt'})
    assert m['kind'] == K['ATTRS'] and m['attrs']['size'] == 13 and m['attrs']['mtime'] == 1700000100
    m = s.do({'op': 'lstat', 'path': 'f1.txt'})
    assert m['attrs']['size'] == 13
    ok(s.do({'op': 'setstat', 'path': 'f1.txt', 'attrs': {'flags': 8, 'atime': 1600000000, 'mtime': 1600000500}}))
    m = s.do({'op': 'stat', 'path': 'f1.txt'})
    assert m['attrs']['mtime'] == 1600000500 and m['attrs']['atime'] == 1600000000
    ok(s.do({'op': 'stat', 'path': 'missing.txt'}), 2)
    ok(s.do({'op': 'rename', 'first': 'f1.txt', 'second': 'f2.txt'}))
    ok(s.do({'op': 'stat', 'path': 'f1.txt'}), 2)
    ok(s.do({'op': 'ext_paths', 'name': 'posix-rename@openssh.com', 'first': 'f2.txt', 'second': 'f3.txt'}))
    m = s.do({'op': 'stat', 'path': 'f3.txt'})
    assert m['attrs']['size'] == 13
    m = s.do({'op': 'realpath', 'path': '.'})
    assert m['kind'] == K['NAME'] and len(m['names']) == 1
    # a directory listing: what was made is what it names
    for name in ('a.dat', 'b.dat', 'c.dat'):
        mm = s.do({'op': 'open', 'path': f'd1/{name}', 'flags': 2 | 8, 'attrs': {'flags': 0}})
        ok(s.do({'op': 'write', 'handle': mm['handle'], 'offset': 0, 'data': name.encode().hex()}))
        ok(s.do({'op': 'close', 'handle': mm['handle']}))
    m = s.do({'op': 'opendir', 'path': 'd1'})
    assert m['kind'] == K['HANDLE']
    dh = m['handle']
    listed = []
    while True:
        m = s.do({'op': 'readdir', 'handle': dh})
        if m['kind'] == K['STATUS']:
            assert m['status'] == 1
            break
        listed += [n['filename'] for n in m['names']]
    assert sorted(x for x in listed if x not in ('.', '..')) == ['a.dat', 'b.dat', 'c.dat'], listed
    ok(s.do({'op': 'close', 'handle': dh}))
    ok(s.do({'op': 'open', 'path': 'nope/none.txt', 'flags': 1, 'attrs': {'flags': 0}}), 2)
    ok(s.do({'op': 'opendir', 'path': 'f3.txt'}), 2)  # msys maps ENOTDIR to NO_SUCH_FILE
    # a write across many packets and its read back
    blob = bytes((i * 7 + (i >> 8)) & 255 for i in range(40000))
    mm = s.do({'op': 'open', 'path': 'big.bin', 'flags': 2 | 8 | 16, 'attrs': {'flags': 0}})
    bh = mm['handle']
    for off in range(0, len(blob), 8192):
        ok(s.do({'op': 'write', 'handle': bh, 'offset': off, 'data': blob[off:off + 8192].hex()}))
    ok(s.do({'op': 'close', 'handle': bh}))
    mm = s.do({'op': 'open', 'path': 'big.bin', 'flags': 1, 'attrs': {'flags': 0}})
    bh = mm['handle']
    got = b''
    while len(got) < len(blob):
        m = s.do({'op': 'read', 'handle': bh, 'offset': len(got), 'length': 10000})
        assert m['kind'] == K['DATA']
        got += bytes.fromhex(m['data'])
    assert got == blob
    ok(s.do({'op': 'close', 'handle': bh}))
    # attributes the server reports for a directory (a mode with the directory bit)
    m = s.do({'op': 'stat', 'path': 'd1'})
    assert m['attrs']['permissions'] & 0o40000
    # an unknown extension is refused, the status says so
    m = s.do({'op': 'ext', 'name': 'no-such-extension@example.org', 'data': ''})
    assert m['kind'] == K['STATUS'] and m['status'] == 8
    # cleanup
    for name in ('a.dat', 'b.dat', 'c.dat'):
        ok(s.do({'op': 'remove', 'path': f'd1/{name}'}))
    ok(s.do({'op': 'rmdir', 'path': 'd1'}))
    ok(s.do({'op': 'remove', 'path': 'f3.txt'}))
    ok(s.do({'op': 'remove', 'path': 'big.bin'}))
    ok(s.do({'op': 'remove', 'path': 'f3.txt'}), 2)
    s.p.stdin.close()
    s.p.wait(timeout=10)
    lines = s.lines
    # decode-only lines: partial, corrupt and oversized packets built from what the server sent
    by_kind = {}
    for ln in lines:
        k = ln['e'].get('kind')
        if k not in by_kind and ln['resp'] and len(ln['resp']) < 1200:
            by_kind[k] = ln['resp']
    extra = []
    for k, hx in by_kind.items():
        raw = bytes.fromhex(hx)
        for cut in sorted({0, 1, 3, 4, 5, len(raw) - 1}):
            if cut < len(raw):
                extra.append(raw[:cut])
        body = raw[4:]
        extra.append(struct.pack('>I', 0))                      # length 0
        extra.append(struct.pack('>I', len(body) + 1) + body + b'\x00')   # one trailing byte inside the packet
        extra.append(struct.pack('>I', 2 << 20) + body)         # past MAX_PACKET
        bad_kind = bytes([7]) + body[1:]
        extra.append(struct.pack('>I', len(body)) + bad_kind)    # a request type in a response
        if len(body) >= 9:
            corrupt = body[:5] + b'\xff\xff\xff\xff' + body[9:]
            extra.append(struct.pack('>I', len(body)) + corrupt)  # a string longer than the packet
    for raw in extra:
        lines.append({'op': {'op': 'decode'}, 'kind': 'decode', 'req': '', 'resp': raw.hex(), 'e': decode(raw)})
    # a NAME answer that does not fit the names the caller gave
    for ln in list(lines):
        if ln['e'].get('kind') == K['NAME'] and len(ln['e']['names']) >= 2:
            lines.append({'op': {'op': 'decode'}, 'kind': 'decode', 'req': '', 'resp': ln['resp'], 'names_cap': 1, 'e': decode(bytes.fromhex(ln['resp']), 1)})
            break
    # NAME packets with attributes of every shape (the optional parts present and absent, extended pairs)
    name_body = s32(77) + s32(3)
    shapes = [dict(flags=0), dict(flags=1, size=2 ** 40 + 5), dict(flags=2, uid=1000, gid=100), dict(flags=4, permissions=0o100644),
              dict(flags=8, atime=1, mtime=2), dict(flags=15, size=9, uid=3, gid=4, permissions=0o40755, atime=5, mtime=6)]
    for chunk in (shapes[:3], shapes[3:]):
        body = bytes([K['NAME']]) + s32(5) + s32(len(chunk))
        for k, a in enumerate(chunk):
            body += sstr(f'n{k}') + sstr(f'-rw-r--r-- 1 u g 0 Jan  1 00:00 n{k}') + attrs_bytes(a)
        raw = struct.pack('>I', len(body)) + body
        lines.append({'op': {'op': 'decode'}, 'kind': 'decode', 'req': '', 'resp': raw.hex(), 'e': decode(raw)})
    # an ATTRS packet with an extended block (two pairs): skipped and counted
    body = bytes([K['ATTRS']]) + s32(9) + s32(0x80000000 | 1) + s64(1234) + s32(2) + sstr('a@x') + sstr('1') + sstr('b@x') + sstr('22')
    raw = struct.pack('>I', len(body)) + body
    lines.append({'op': {'op': 'decode'}, 'kind': 'decode', 'req': '', 'resp': raw.hex(), 'e': decode(raw)})
    # a STATUS that stops after the code (older servers), a VERSION with no extensions, an EXTENDED_REPLY
    body = bytes([K['STATUS']]) + s32(4) + s32(2)
    raw = struct.pack('>I', len(body)) + body
    lines.append({'op': {'op': 'decode'}, 'kind': 'decode', 'req': '', 'resp': raw.hex(), 'e': decode(raw)})
    body = bytes([K['VERSION']]) + s32(3)
    raw = struct.pack('>I', len(body)) + body
    lines.append({'op': {'op': 'decode'}, 'kind': 'decode', 'req': '', 'resp': raw.hex(), 'e': decode(raw)})
    body = bytes([K['EXTENDED_REPLY']]) + s32(11) + b'\x00\x01\x02\xff'
    raw = struct.pack('>I', len(body)) + body
    lines.append({'op': {'op': 'decode'}, 'kind': 'decode', 'req': '', 'resp': raw.hex(), 'e': decode(raw)})

    texts = [json.dumps(l, sort_keys=True, separators=(',', ':'), ensure_ascii=True) for l in lines]
    bs = chr(92)
    chunks = []
    for i in range(0, len(texts), 10):
        chunks.append('"' + (bs + 'n').join(t.replace(bs, bs + bs).replace('"', bs + '"') for t in texts[i:i + 10]) + bs + 'n"')
    funcs = '\n'.join(f'fn vectors_{i}() -> str {{\n    ret {c}\n}}\n' for i, c in enumerate(chunks))
    calls = ''.join(f'    if run_chunk(a, vectors_{i}()) != 0u8 {{ os.exit({i + 1}i32) }}\n' for i in range(len(chunks)))
    t = open(TEMPLATE, encoding='utf8').read()
    out = t.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
    os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
    with open(FIXTURE, 'w', encoding='utf8', newline='\n') as f:
        f.write(out)
    print(f'{len(lines)} lines ({len(extra)} synthetic decodes) in {len(chunks)} chunks -> net_sftp; server {find_server()}')
    shutil.rmtree(work, ignore_errors=True)


main()
