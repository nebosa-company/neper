"""Generate the dbus fixture: vectors from dbus-next (a pure-Python D-Bus library).

Oracle: dbus-next's `Marshaller` writes random typed bodies and its `Message._marshall` whole messages (little-endian,
its header-field order); its `Unmarshaller` reads them back, and the generator asserts the value it gets equals the
model. Big-endian vectors come from a second marshaller written here straight from the specification, which is
asserted byte-equal to dbus-next's on every little-endian vector before it is trusted for the big-endian ones.
Authentication lines, match rules and bus addresses have no library oracle that runs without a bus and follow the
specification (and, for AUTH EXTERNAL, dbus-next's `_authenticate` byte for byte).

    PYTHONPATH=DIR python scripts/dbus_vectors.py
"""
import io
import os
import random
import struct
import sys

from dbus_next import Variant
from dbus_next._private.marshaller import Marshaller
from dbus_next._private.unmarshaller import Unmarshaller
from dbus_next.constants import MessageFlag, MessageType
from dbus_next.message import Message

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)
rng = random.Random(0x44425553)
lines = []


def hx(b):
    if isinstance(b, str):
        b = b.encode('utf-8')
    return b.hex()


def add(*f):
    lines.append('\t'.join(str(x) for x in f))


# ---- types and values -------------------------------------------------------------------------------------------
BASIC = 'ybnqiuxtdsog'


def gen_type(depth=0, allow_variant=True):
    k = rng.random()
    if depth >= 3 or k < 0.45:
        return rng.choice(BASIC)
    if k < 0.65:
        return 'a' + gen_type(depth + 1, allow_variant)
    if k < 0.8:
        return '(' + ''.join(gen_type(depth + 1, allow_variant) for _ in range(rng.randrange(1, 4))) + ')'
    if k < 0.9:
        return 'a{' + rng.choice(BASIC.replace('d', '')) + gen_type(depth + 1, allow_variant) + '}'
    return 'v' if allow_variant and depth < 3 else rng.choice(BASIC)


def split(sig):
    """The complete types of a signature."""
    out, i = [], 0
    while i < len(sig):
        j = i + complete(sig, i)
        out.append(sig[i:j])
        i = j
    return out


def complete(sig, i):
    c = sig[i]
    if c == 'a':
        if sig[i + 1] == '{':
            k = 3
            return 3 + complete(sig, i + 3) + 1
        return 1 + complete(sig, i + 1)
    if c == '(':
        j = i + 1
        while sig[j] != ')':
            j += complete(sig, j)
        return j + 1 - i
    return 1


def gen_value(sig):
    c = sig[0]
    if c == 'y':
        return rng.randrange(256)
    if c == 'b':
        return rng.random() < 0.5
    if c == 'n':
        return rng.choice([0, 1, -1, 32767, -32768, rng.randrange(-32768, 32768)])
    if c == 'q':
        return rng.choice([0, 1, 65535, rng.randrange(65536)])
    if c == 'i':
        return rng.choice([0, -1, 2 ** 31 - 1, -2 ** 31, rng.randrange(-2 ** 31, 2 ** 31)])
    if c == 'u':
        return rng.choice([0, 2 ** 32 - 1, rng.randrange(2 ** 32)])
    if c == 'x':
        return rng.choice([0, -1, 2 ** 63 - 1, -2 ** 63, rng.randrange(-2 ** 63, 2 ** 63)])
    if c == 't':
        return rng.choice([0, 2 ** 64 - 1, rng.randrange(2 ** 64)])
    if c == 'd':
        return rng.choice([0.0, 1.5, -2.25, 3.141592653589793, 1e300, float('inf')])
    if c == 's':
        return rng.choice(['', 'hello', 'café ☃', 'x' * 40, 'a b'])
    if c == 'o':
        return rng.choice(['/', '/org/freedesktop/DBus', '/a/b/c'])
    if c == 'g':
        return rng.choice(['', 'i', 'a{sv}', '(ii)as'])
    if c == 'v':
        inner = gen_type(2, False)
        return (inner, gen_value(inner))
    if c == '(':
        return [gen_value(t) for t in split(sig[1:-1])]
    if c == 'a':
        if sig[1] == '{':
            kt = sig[2]
            vt = sig[3:-1]
            return [(gen_value(kt), gen_value(vt)) for _ in range(rng.randrange(0, 4))]
        return [gen_value(sig[1:]) for _ in range(rng.randrange(0, 5))]
    raise ValueError(sig)


# ---- the reference marshaller -----------------------------------------------------------------------------------
ALIGN = {'y': 1, 'b': 4, 'n': 2, 'q': 2, 'i': 4, 'u': 4, 'x': 8, 't': 8, 'd': 8, 's': 4, 'o': 4, 'g': 1, 'a': 4, '(': 8, '{': 8, 'v': 1, 'h': 4}


def marshal(buf, sig, value, little):
    e = '<' if little else '>'

    def pad(n):
        while len(buf) % n:
            buf.append(0)

    c = sig[0]
    if c == 'y':
        buf.append(value)
    elif c == 'b':
        pad(4)
        buf += struct.pack(e + 'I', 1 if value else 0)
    elif c in 'nqiuxth':
        fmt = {'n': 'h', 'q': 'H', 'i': 'i', 'u': 'I', 'x': 'q', 't': 'Q', 'h': 'I'}[c]
        pad(ALIGN[c])
        buf += struct.pack(e + fmt, value)
    elif c == 'd':
        pad(8)
        buf += struct.pack(e + 'd', value)
    elif c in 'so':
        pad(4)
        raw = value.encode('utf-8')
        buf += struct.pack(e + 'I', len(raw)) + raw + b'\0'
    elif c == 'g':
        raw = value.encode('ascii')
        buf += bytes([len(raw)]) + raw + b'\0'
    elif c == 'v':
        inner, inner_value = value
        raw = inner.encode('ascii')
        buf += bytes([len(raw)]) + raw + b'\0'
        marshal(buf, inner, inner_value, little)
    elif c == '(':
        pad(8)
        for t, v in zip(split(sig[1:-1]), value):
            marshal(buf, t, v, little)
    elif c == 'a':
        pad(4)
        at = len(buf)
        buf += b'\0\0\0\0'
        element = sig[1:]
        pad(ALIGN[element[0]])
        start = len(buf)
        for item in value:
            if element[0] == '{':
                pad(8)
                marshal(buf, element[1], item[0], little)
                marshal(buf, element[2:-1], item[1], little)
            else:
                marshal(buf, element, item, little)
        buf[at:at + 4] = struct.pack(e + 'I', len(buf) - start)
    else:
        raise ValueError(sig)


def render(sig, value):
    c = sig[0]
    if c in 'ynqiuxth':
        return '%s%d' % (c, value)
    if c == 'b':
        return 'b%d' % int(value)
    if c == 'd':
        return 'd' + hx(struct.pack('>d', value))
    if c in 'sog':
        return c + hx(value)
    if c == 'v':
        inner, iv = value
        return 'V%s(%s)' % (hx(inner), render(inner, iv))
    if c == '(':
        return '(' + ','.join(render(t, v) for t, v in zip(split(sig[1:-1]), value)) + ')'
    if c == 'a':
        element = sig[1:]
        if element[0] == '{':
            items = ['{%s=%s}' % (render(element[1], k), render(element[2:-1], v)) for k, v in value]
        else:
            items = [render(element, v) for v in value]
        return 'A%s[%s]' % (hx(element), ','.join(items))
    raise ValueError(sig)


def to_lib(sig, value):
    """The model value in dbus-next's representation."""
    c = sig[0]
    if c == 'v':
        inner, iv = value
        return Variant(inner, to_lib(inner, iv))
    if c == '(':
        return [to_lib(t, v) for t, v in zip(split(sig[1:-1]), value)]
    if c == 'a':
        element = sig[1:]
        if element[0] == '{':
            return {k: to_lib(element[2:-1], v) for k, v in value}
        if element == 'y':
            return bytes(value)
        return [to_lib(element, v) for v in value]
    return value


def from_lib(sig, value):
    """dbus-next's unmarshalled value back to the model's."""
    c = sig[0]
    if c == 'v':
        return (value.signature, from_lib(value.signature, value.value))
    if c == '(':
        return [from_lib(t, v) for t, v in zip(split(sig[1:-1]), value)]
    if c == 'a':
        element = sig[1:]
        if element[0] == '{':
            return [(k, from_lib(element[2:-1], v)) for k, v in value.items()]
        return [from_lib(element, v) for v in value]
    return value


def dict_ok(sig, value):
    """dbus-next models a{..} as a dict: duplicate keys cannot survive, so such values are not used for the oracle."""
    c = sig[0]
    if c == 'a' and sig[1] == '{':
        keys = [k for k, _ in value]
        return len(set(keys)) == len(keys) and all(dict_ok(sig[3:-1], v) for _, v in value)
    if c == 'a':
        return all(dict_ok(sig[1:], v) for v in value)
    if c == '(':
        return all(dict_ok(t, v) for t, v in zip(split(sig[1:-1]), value))
    if c == 'v':
        return dict_ok(value[0], value[1])
    return True


# ---- bodies
for _ in range(150):
    types = [gen_type() for _ in range(rng.randrange(1, 4))]
    values = [gen_value(t) for t in types]
    if not all(dict_ok(t, v) for t, v in zip(types, values)):
        continue
    sig = ''.join(types)
    little = bytearray()
    for t, v in zip(types, values):
        marshal(little, t, v, True)
    lib = Marshaller(sig, [to_lib(t, v) for t, v in zip(types, values)])
    lib.marshall()
    assert bytes(little) == bytes(lib.buffer), (sig, values)
    big = bytearray()
    for t, v in zip(types, values):
        marshal(big, t, v, False)
    rendered = ';'.join(render(t, v) for t, v in zip(types, values))
    add('B', 1, hx(sig), hx(bytes(little)), rendered)
    add('B', 0, hx(sig), hx(bytes(big)), rendered)

# truncations and malformed bodies (each must be refused)
for sig, raw in [('s', b'\x05\x00\x00\x00ab'), ('s', b'\x02\x00\x00\x00ab\x01'), ('b', b'\x02\x00\x00\x00'), ('as', b'\xff\xff\xff\xff'),
                 ('i', b'\x00\x00\x00'), ('ay', b'\x03\x00\x00\x00\x01\x02'), ('(ii)', b'\x00\x00\x00\x00\x01\x00\x00'),
                 ('v', b'\x01i\x00\x00\x00\x00'), ('v', b'\x00\x00'), ('s', b'\x01\x00\x00\x00\x00\x00'), ('a(i)', b'\x08\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00')]:
    add('Bx', 1, hx(sig), hx(raw))

# ---- messages
def lib_message(kind, serial, flags, **kw):
    msg = Message(message_type=kind, flags=flags, serial=serial, **kw)
    return msg


def field_text(m):
    return '|'.join([m.get('path', ''), m.get('interface', ''), m.get('member', ''), m.get('error', ''), str(m.get('reply', 0)),
                     m.get('destination', ''), m.get('sender', ''), m.get('signature', ''), str(m.get('fds', 0))])


NAMES = ['org.freedesktop.DBus', 'org.example.Service', ':1.42', 'com.acme.App']
for case in range(40):
    kind = rng.choice([MessageType.METHOD_CALL, MessageType.METHOD_RETURN, MessageType.ERROR, MessageType.SIGNAL])
    serial = rng.randrange(1, 2 ** 32)
    flags = rng.choice([MessageFlag.NONE, MessageFlag.NO_REPLY_EXPECTED, MessageFlag.NO_AUTOSTART])
    types = [gen_type() for _ in range(rng.randrange(0, 3))]
    values = [gen_value(t) for t in types]
    if not all(dict_ok(t, v) for t, v in zip(types, values)):
        continue
    sig = ''.join(types)
    fields = {}
    kw = {}
    if kind == MessageType.METHOD_CALL:
        fields.update(path='/org/example/Obj', interface=rng.choice(['', 'org.example.Iface']), member='Do' + str(case))
        kw.update(path=fields['path'], interface=fields['interface'] or None, member=fields['member'])
        fields['destination'] = rng.choice(NAMES)
        kw['destination'] = fields['destination']
    elif kind == MessageType.METHOD_RETURN:
        fields.update(reply=rng.randrange(1, 1000))
        kw.update(reply_serial=fields['reply'])
        fields['destination'] = ':1.5'
        kw['destination'] = ':1.5'
    elif kind == MessageType.ERROR:
        fields.update(error='org.freedesktop.DBus.Error.UnknownMethod', reply=rng.randrange(1, 1000))
        kw.update(error_name=fields['error'], reply_serial=fields['reply'])
    else:
        fields.update(path='/org/example/Sig', interface='org.example.Iface', member='Changed')
        kw.update(path=fields['path'], interface=fields['interface'], member=fields['member'])
    fields['signature'] = sig
    msg = Message(message_type=kind, flags=flags, serial=serial, signature=sig, body=[to_lib(t, v) for t, v in zip(types, values)], **kw)
    raw = msg._marshall(False)
    # the library reads its own bytes back to the same fields and values
    um = Unmarshaller(io.BytesIO(raw))
    got = um.unmarshall()
    assert got.serial == serial and got.signature == sig
    assert [from_lib(t, v) for t, v in zip(types, got.body)] == values, (sig, values, got.body)
    meta = dict(fields)
    text = '%d|%d|%d|%s|%s' % (kind.value, flags.value, serial, field_text(meta), ';'.join(render(t, v) for t, v in zip(types, values)))
    add('M', 1, hx(raw), text)
    # big-endian: the same message marshalled by the reference (header fields in libdbus's order)
    def header(little):
        e = '<' if little else '>'
        body = bytearray()
        for t, v in zip(types, values):
            marshal(body, t, v, little)
        fb = bytearray()

        def put_field(code, fsig, value):
            while len(fb) % 8:
                fb.append(0)
            fb.append(code)
            fb.extend(bytes([len(fsig)]) + fsig.encode() + b'\0')
            if fsig == 'u':
                while len(fb) % 4:
                    fb.append(0)
                fb.extend(struct.pack(e + 'I', value))
            elif fsig == 'g':
                fb.extend(bytes([len(value)]) + value.encode() + b'\0')
            else:
                while len(fb) % 4:
                    fb.append(0)
                fb.extend(struct.pack(e + 'I', len(value.encode())) + value.encode() + b'\0')
        if fields.get('path'):
            put_field(1, 'o', fields['path'])
        if fields.get('interface'):
            put_field(2, 's', fields['interface'])
        if fields.get('member'):
            put_field(3, 's', fields['member'])
        if fields.get('error'):
            put_field(4, 's', fields['error'])
        if fields.get('reply'):
            put_field(5, 'u', fields['reply'])
        if fields.get('destination'):
            put_field(6, 's', fields['destination'])
        if sig:
            put_field(8, 'g', sig)
        head = bytes([108 if little else 66, kind.value, flags.value, 1]) + struct.pack(e + 'III', len(body), serial, len(fb))
        out = bytearray(head) + fb
        while len(out) % 8:
            out.append(0)
        return bytes(out + body)
    assert header(True) == raw, (case, header(True).hex(), raw.hex())
    add('M', 0, hx(header(False)), text)

# malformed and partial messages
good = Message(message_type=MessageType.METHOD_CALL, serial=7, path='/a', member='M', destination='x.y', signature='s', body=['hi'])._marshall(False)
for cut in (0, 8, 15, 16, 30, len(good) - 1):
    add('Mx', hx(good[:cut]), 'Truncated')
bad_version = bytearray(good)
bad_version[3] = 2
add('Mx', hx(bytes(bad_version)), 'Unsupported')
bad_endian = bytearray(good)
bad_endian[0] = ord('x')
add('Mx', hx(bytes(bad_endian)), 'Invalid')
zero_serial = bytearray(good)
zero_serial[8:12] = b'\0\0\0\0'
add('Mx', hx(bytes(zero_serial)), 'Invalid')
bad_kind = bytearray(good)
bad_kind[1] = 9
add('Mx', hx(bytes(bad_kind)), 'Invalid')
no_path = Message(message_type=MessageType.SIGNAL, serial=3, interface='a.B', member='C', path='/p')._marshall(False)
add('Mx', hx(no_path.replace(b'\x01\x01o\x00', b'\x0a\x01o\x00', 1)), 'Invalid')

# ---- the standard calls as dbus-next marshals them
hello = Message(destination='org.freedesktop.DBus', path='/org/freedesktop/DBus', interface='org.freedesktop.DBus', member='Hello', serial=1)._marshall(False)
add('H', 'hello', hx(hello))
req = Message(destination='org.freedesktop.DBus', path='/org/freedesktop/DBus', interface='org.freedesktop.DBus', member='RequestName', signature='su', body=['org.example.App', 4], serial=2)._marshall(False)
add('H', 'request', hx(req))
match = Message(destination='org.freedesktop.DBus', path='/org/freedesktop/DBus', interface='org.freedesktop.DBus', member='AddMatch', signature='s', body=["type='signal',interface='org.example.Iface'"], serial=2)._marshall(False)
add('H', 'match', hx(match))

# ---- authentication
for uid in ('0', '1000', '65534', '4294967294'):
    add('A', uid, hx(b'\0AUTH EXTERNAL ' + uid.encode().hex().encode() + b'\r\n'))
add('Aa', hx(b'\0AUTH ANONYMOUS\r\n'))
for line, want in [('OK 1234deadbeef', 'begin'), ('REJECTED EXTERNAL ANONYMOUS', 'Rejected'), ('ERROR "bad"', 'Rejected'), ('DATA 00', 'continue'), ('AGREE_UNIX_FD', 'continue')]:
    add('Ar', hx(line), want)

# ---- match rules (specification)
def matches(rule, m):
    kv = {}
    for part in rule.split(','):
        k, _, v = part.partition('=')
        kv[k] = v.strip("'")
    names = {'type': m['type'], 'sender': m.get('sender', ''), 'interface': m.get('interface', ''), 'member': m.get('member', ''), 'path': m.get('path', ''), 'destination': m.get('destination', '')}
    for k, v in kv.items():
        if k in names and names[k] != v:
            return False
        if k == 'path_namespace':
            p = m.get('path', '')
            if not (v == '/' or p == v or p.startswith(v + '/')):
                return False
        if k.startswith('arg') and k[3:].isdigit():
            i = int(k[3:])
            args = m.get('args', [])
            if i >= len(args) or args[i] != v:
                return False
    return True


MSGS = [dict(type='signal', sender=':1.5', interface='org.example.Iface', member='Changed', path='/org/example/Obj', args=['one', 'two']),
        dict(type='method_call', sender=':1.9', interface='org.example.Iface', member='Do', path='/org/other', destination='org.example.App', args=[]),
        dict(type='signal', sender='org.freedesktop.DBus', interface='org.freedesktop.DBus', member='NameOwnerChanged', path='/org/freedesktop/DBus', args=['org.example.App', '', ':1.7'])]
RULES = ["type='signal'", "type='method_call'", "type='signal',interface='org.example.Iface'", "interface='org.example.Iface',member='Changed'",
         "path='/org/example/Obj'", "path_namespace='/org'", "path_namespace='/org/example'", "path_namespace='/org/ex'", "path_namespace='/'",
         "sender='org.freedesktop.DBus',type='signal',member='NameOwnerChanged',arg0='org.example.App'", "arg1='two'", "arg0='x'", "arg2='two'",
         "destination='org.example.App'", ""]
for rule in RULES:
    for m in MSGS:
        add('R', hx(rule), hx(m['type']), hx(m.get('sender', '')), hx(m.get('interface', '')), hx(m.get('member', '')), hx(m.get('path', '')),
            hx(m.get('destination', '')), ','.join(hx(x) for x in m.get('args', [])) or '-', int(matches(rule, m)))


# ---- addresses (specification: transport, then comma-separated key=value with %XX escapes; first entry only)
def parse_address_model(text):
    from urllib.parse import unquote_to_bytes
    transport, sep, rest = text.partition(':')
    if not sep or not transport:
        return 'Invalid'
    first = rest.split(';')[0]
    d = {'path': b'', 'abstract': b'', 'host': b'', 'port': 0, 'guid': b'', 'runtime': 0}
    for pair in first.split(','):
        k, eq, v = pair.partition('=')
        if not eq:
            continue
        raw = unquote_to_bytes(v)
        if k == 'port':
            d['port'] = int(raw)
        elif k == 'runtime':
            d['runtime'] = int(raw == b'yes')
        elif k in d:
            d[k] = raw
    return '|'.join([transport, hx(d['path']), hx(d['abstract']), hx(d['host']), str(d['port']), hx(d['guid']), str(d['runtime'])])


for text in ['unix:path=/run/user/1000/bus', 'unix:abstract=/tmp/dbus-ABC,guid=0123abcd', 'unix:runtime=yes', 'tcp:host=localhost,port=55555',
             'unix:path=/tmp/a%20b,guid=ff;unix:path=/other', 'unix:path=%2Ftmp%2Fx', 'nonsense', ':path=x']:
    add('D', hx(text), parse_address_model(text))

# ---- write
chunks, step = [], 20
for i in range(0, len(lines), step):
    body = '\n'.join(l.replace(BS, BS + BS).replace('"', BS + '"').replace('\t', BS + 't') for l in lines[i:i + step]) + '\n'
    chunks.append('"' + body.replace('\n', BS + 'n') + '"')
funcs = '\n'.join('fn vectors_%d() -> str {\n    ret %s\n}\n' % (i, c) for i, c in enumerate(chunks))
calls = ''.join('    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n' % (i, 100 + i) for i in range(len(chunks)))
with open(os.path.join(ROOT, 'scripts', 'dbus_fixture_template.e'), encoding='utf-8') as f:
    template = f.read()
out = template.replace('//__VECTOR_FUNCTIONS__\n', funcs + '\n').replace('    //__VECTOR_CALLS__\n', calls)
target = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'dbus', 'src', 'main.e')
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, 'w', encoding='utf-8', newline='\n') as f:
    f.write(out)
print('%d vectors in %d chunks -> dbus' % (len(lines), len(chunks)))
