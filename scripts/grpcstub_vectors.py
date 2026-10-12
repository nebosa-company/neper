"""Generate the net_grpcstub fixture: stubs generated from descriptors, checked against Python's protobuf on the wire.

Oracle: the descriptors are built here with descriptor_pb2, loaded into a descriptor pool, and Python's own message
classes build, serialise and parse random instances (every scalar type, packed and unpacked lists, strings, bytes,
enums, nested and recursive messages, maps, oneofs, proto3 optional, proto2 required and optional, keyword field names).
`e.net.grpcstub.generate` writes the Neper module (`src/kitchen.e` of the fixture, compiled with the fixture); the fixture
decodes every serialised instance with the generated `*_decode`, re-encodes it with `*_encode` and compares the bytes with
Python's, which pins field order, packing, defaults and presence in both directions, and checks decoded values of some
fixed messages against what Python holds. It also regenerates the module from the descriptor bytes and compares it with the
module it was compiled from, and checks the service constants against the descriptor.

    python scripts/grpcstub_vectors.py             # needs NEPER_SELF (a neper-self compiler) in the environment
"""
import os
import random
import re
import subprocess
import sys
import tempfile

from google.protobuf import descriptor_pb2 as d
from google.protobuf import descriptor_pool, message_factory

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'net_grpcstub', 'src')
F = d.FieldDescriptorProto
rng = random.Random(0x5717B)


def field(msg, name, number, type_, label=F.LABEL_OPTIONAL, **kw):
    f = msg.field.add()
    f.name = name
    f.number = number
    f.type = type_
    f.label = label
    for k, v in kw.items():
        if k == 'packed':
            f.options.packed = v
        else:
            setattr(f, k, v)
    return f


def build_files():
    kit = d.FileDescriptorProto(name='kitchen.proto', package='ks.v1', syntax='proto3')
    color = kit.enum_type.add()
    color.name = 'Color'
    for n, v in (('COLOR_UNSPECIFIED', 0), ('RED', 1), ('GREEN', 2), ('DEEP_BLUE', 7), ('NEGATIVE', -5)):
        e = color.value.add()
        e.name = n
        e.number = v
    s = kit.message_type.add()
    s.name = 'Scalars'
    for i, (n, t) in enumerate([('d', F.TYPE_DOUBLE), ('f', F.TYPE_FLOAT), ('i32', F.TYPE_INT32), ('i64', F.TYPE_INT64), ('u32', F.TYPE_UINT32),
                                ('u64', F.TYPE_UINT64), ('s32', F.TYPE_SINT32), ('s64', F.TYPE_SINT64), ('x32', F.TYPE_FIXED32), ('x64', F.TYPE_FIXED64),
                                ('sx32', F.TYPE_SFIXED32), ('sx64', F.TYPE_SFIXED64), ('b', F.TYPE_BOOL), ('s', F.TYPE_STRING), ('by', F.TYPE_BYTES)], 1):
        field(s, n, i, t)
    field(s, 'color', 16, F.TYPE_ENUM, type_name='.ks.v1.Color')
    r = kit.message_type.add()
    r.name = 'Repeats'
    for i, (n, t) in enumerate([('ints', F.TYPE_INT32), ('sints', F.TYPE_SINT64), ('doubles', F.TYPE_DOUBLE), ('strs', F.TYPE_STRING), ('blobs', F.TYPE_BYTES),
                                ('flags', F.TYPE_BOOL), ('colors', F.TYPE_ENUM), ('fx', F.TYPE_FIXED32)], 1):
        field(r, n, i, t, F.LABEL_REPEATED, **({'type_name': '.ks.v1.Color'} if t == F.TYPE_ENUM else {}))
    field(r, 'items', 9, F.TYPE_MESSAGE, F.LABEL_REPEATED, type_name='.ks.v1.Scalars')
    field(r, 'unpacked', 10, F.TYPE_INT64, F.LABEL_REPEATED, packed=False)
    field(r, 'floats', 11, F.TYPE_FLOAT, F.LABEL_REPEATED)
    field(r, 'sfx', 12, F.TYPE_SFIXED64, F.LABEL_REPEATED)
    n = kit.message_type.add()
    n.name = 'Node'
    field(n, 'name', 1, F.TYPE_STRING)
    field(n, 'child', 2, F.TYPE_MESSAGE, type_name='.ks.v1.Node')
    field(n, 'kids', 3, F.TYPE_MESSAGE, F.LABEL_REPEATED, type_name='.ks.v1.Node')
    field(n, 'counts', 4, F.TYPE_MESSAGE, F.LABEL_REPEATED, type_name='.ks.v1.Node.CountsEntry')
    field(n, 'by_id', 5, F.TYPE_MESSAGE, F.LABEL_REPEATED, type_name='.ks.v1.Node.ByIdEntry')
    field(n, 'maybe', 6, F.TYPE_INT32, proto3_optional=True, oneof_index=1)
    field(n, 'text', 7, F.TYPE_STRING, oneof_index=0)
    field(n, 'number', 8, F.TYPE_INT64, oneof_index=0)
    field(n, 'rec', 9, F.TYPE_MESSAGE, type_name='.ks.v1.Scalars', oneof_index=0)
    field(n, 'c', 10, F.TYPE_ENUM, type_name='.ks.v1.Color')
    n.oneof_decl.add().name = 'pick'
    n.oneof_decl.add().name = '_maybe'
    ce = n.nested_type.add()
    ce.name = 'CountsEntry'
    field(ce, 'key', 1, F.TYPE_STRING)
    field(ce, 'value', 2, F.TYPE_INT32)
    ce.options.map_entry = True
    be = n.nested_type.add()
    be.name = 'ByIdEntry'
    field(be, 'key', 1, F.TYPE_INT32)
    field(be, 'value', 2, F.TYPE_MESSAGE, type_name='.ks.v1.Scalars')
    be.options.map_entry = True
    kit.message_type.add().name = 'Empty'
    kw = kit.message_type.add()
    kw.name = 'Keywords'
    field(kw, 'type', 1, F.TYPE_INT32)
    field(kw, 'in', 2, F.TYPE_STRING)
    field(kw, 'error', 3, F.TYPE_BOOL)
    field(kw, 'zero', 4, F.TYPE_DOUBLE)
    svc = kit.service.add()
    svc.name = 'Kitchen'
    for name, inp, out, cs, ss in (('Unary', 'Scalars', 'Repeats', False, False), ('ServerStream', 'Node', 'Node', False, True),
                                   ('ClientStream', 'Repeats', 'Empty', True, False), ('Bidi', 'Node', 'Node', True, True), ('HTTPPing', 'Empty', 'Empty', False, False)):
        m = svc.method.add()
        m.name = name
        m.input_type = '.ks.v1.' + inp
        m.output_type = '.ks.v1.' + out
        m.client_streaming = cs
        m.server_streaming = ss

    leg = d.FileDescriptorProto(name='legacy.proto', package='ks.legacy')
    lg = leg.message_type.add()
    lg.name = 'Legacy'
    field(lg, 'id', 1, F.TYPE_INT32, F.LABEL_REQUIRED)
    field(lg, 'name', 2, F.TYPE_STRING)
    field(lg, 'packed_list', 3, F.TYPE_INT32, F.LABEL_REPEATED, packed=True)
    field(lg, 'plain', 4, F.TYPE_INT32, F.LABEL_REPEATED)
    field(lg, 'flag', 5, F.TYPE_BOOL)
    field(lg, 'ratio', 6, F.TYPE_DOUBLE)
    field(lg, 'blob', 7, F.TYPE_BYTES)
    field(lg, 'who', 8, F.TYPE_FIXED64)
    nn = leg.message_type.add()
    nn.name = 'Outer'
    field(nn, 'inner', 1, F.TYPE_MESSAGE, type_name='.ks.legacy.Legacy')
    field(nn, 'list', 2, F.TYPE_MESSAGE, F.LABEL_REPEATED, type_name='.ks.legacy.Legacy')
    s2 = d.FileDescriptorSet()
    s2.file.add().CopyFrom(kit)
    s2.file.add().CopyFrom(leg)
    return s2


def snake(s):
    out = []
    for i, c in enumerate(s):
        if c in '.-':
            out.append('_')
        elif c.isupper():
            split = False
            if i > 0 and s[i - 1] not in '._':
                if s[i - 1].islower() or s[i - 1].isdigit():
                    split = True
                if s[i - 1].isupper() and i + 1 < len(s) and s[i + 1].islower():
                    split = True
            if split:
                out.append('_')
            out.append(c.lower())
        else:
            out.append(c)
    return ''.join(out)


def type_ident(full):
    return full.lstrip('.').replace('.', '_')


# --- random instances ------------------------------------------------------------------------------------------------

SCALAR_GEN = {
    F.TYPE_DOUBLE: lambda: rng.choice([0.0, 1.5, -2.25, 1e300, 3.141592653589793, rng.uniform(-1e6, 1e6)]),
    F.TYPE_FLOAT: lambda: rng.choice([0.0, 1.5, -2.25, 0.1, 3.4e38, 1e-30]),
    F.TYPE_INT64: lambda: rng.choice([0, 1, -1, 2 ** 40, -2 ** 40, 2 ** 63 - 1, -2 ** 63, 300]),
    F.TYPE_UINT64: lambda: rng.choice([0, 1, 127, 128, 2 ** 40, 2 ** 64 - 1]),
    F.TYPE_INT32: lambda: rng.choice([0, 1, -1, 127, 128, 2 ** 31 - 1, -2 ** 31, 300]),
    F.TYPE_FIXED64: lambda: rng.choice([0, 1, 2 ** 63, 2 ** 64 - 1]),
    F.TYPE_FIXED32: lambda: rng.choice([0, 1, 2 ** 31, 2 ** 32 - 1]),
    F.TYPE_BOOL: lambda: rng.choice([True, False]),
    F.TYPE_STRING: lambda: rng.choice(['', 'a', 'hello', 'caf\u00e9 \u65e5\u672c', 'x' * 200]),
    F.TYPE_BYTES: lambda: rng.choice([b'', b'\x00', b'\xff\xfe', bytes(range(40)), b'z' * 130]),
    F.TYPE_UINT32: lambda: rng.choice([0, 1, 127, 128, 2 ** 32 - 1]),
    F.TYPE_SFIXED32: lambda: rng.choice([0, 1, -1, 2 ** 31 - 1, -2 ** 31]),
    F.TYPE_SFIXED64: lambda: rng.choice([0, 1, -1, 2 ** 63 - 1, -2 ** 63]),
    F.TYPE_SINT32: lambda: rng.choice([0, 1, -1, 2 ** 31 - 1, -2 ** 31, 63, -64]),
    F.TYPE_SINT64: lambda: rng.choice([0, 1, -1, 2 ** 62, -2 ** 62, 2 ** 63 - 1, -2 ** 63]),
}


def to_float32(x):
    import struct
    return struct.unpack('<f', struct.pack('<f', x))[0]


def fill(msg, depth=0):
    desc = msg.DESCRIPTOR
    chosen_oneof = {}
    for fd in desc.fields:
        if fd.containing_oneof is not None and not fd.has_presence is False:
            pass
        if fd.containing_oneof is not None and fd.containing_oneof.name in chosen_oneof and chosen_oneof[fd.containing_oneof.name] != fd.name:
            continue
        if rng.random() < 0.35:
            continue
        if fd.containing_oneof is not None:
            chosen_oneof[fd.containing_oneof.name] = fd.name
        label_repeated = fd.is_repeated
        is_map = fd.message_type is not None and fd.message_type.GetOptions().map_entry
        count = rng.randrange(0, 4) if label_repeated else 1
        if is_map:
            target = getattr(msg, fd.name)
            for _ in range(count):
                kd, vd = fd.message_type.fields_by_name['key'], fd.message_type.fields_by_name['value']
                k = SCALAR_GEN[kd.type]()
                if vd.type == F.TYPE_MESSAGE:
                    if depth < 2:
                        fill(target[k], depth + 1)
                        target[k].SetInParent()
                else:
                    target[k] = to_float32(SCALAR_GEN[vd.type]()) if vd.type == F.TYPE_FLOAT else SCALAR_GEN[vd.type]()
            continue
        for _ in range(count):
            if fd.type == F.TYPE_MESSAGE:
                if depth >= 3:
                    continue
                if label_repeated:
                    fill(getattr(msg, fd.name).add(), depth + 1)
                else:
                    sub = getattr(msg, fd.name)
                    sub.SetInParent()
                    fill(sub, depth + 1)
            elif fd.type == F.TYPE_ENUM:
                v = rng.choice([0, 1, 2, 7, -5])
                if label_repeated:
                    getattr(msg, fd.name).append(v)
                else:
                    setattr(msg, fd.name, v)
            else:
                v = SCALAR_GEN[fd.type]()
                if fd.type == F.TYPE_FLOAT:
                    v = to_float32(v)
                if label_repeated:
                    getattr(msg, fd.name).append(v)
                else:
                    setattr(msg, fd.name, v)
    # proto2 required fields must be present for SerializeToString
    for fd in desc.fields:
        if fd.is_required and not msg.HasField(fd.name):
            setattr(msg, fd.name, 1)


def main():
    fds = build_files()
    pool = descriptor_pool.DescriptorPool()
    for f in fds.file:
        pool.Add(f)
    names = ['ks.v1.Scalars', 'ks.v1.Repeats', 'ks.v1.Node', 'ks.v1.Empty', 'ks.v1.Keywords', 'ks.legacy.Legacy', 'ks.legacy.Outer']
    classes = {n: message_factory.GetMessageClass(pool.FindMessageTypeByName(n)) for n in names}
    set_hex = fds.SerializeToString().hex()

    # 1. generate the stub with the Neper generator
    neper = os.environ.get('NEPER_SELF')
    if not neper:
        for guess in (os.path.join(ROOT, 'build', 'windows', 'tests', 'selfhost', 'neper-self.exe'), 'D:/repos/neper/build/windows/tests/selfhost/neper-self.exe'):
            if os.path.exists(guess):
                neper = guess
                break
    tmp = tempfile.mkdtemp()
    gen_src = os.path.join(tmp, 'gen.e')
    with open(gen_src, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('''use e.fmt.json as json
use e.fmt.protodesc as desc
use e.io
use e.mem
use e.net.grpcstub as stub
use e.os

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    let h = "%s"
    let (raw, e) = mem.alloc[u8](a, h.len / 2usize + 1usize)
    if e != ok { os.exit(1) }
    var i = 0usize
    while i + 1usize < h.len {
        raw[i / 2usize] = nibble(h[i]) * 16u8 + nibble(h[i + 1usize])
        i += 2usize
    }
    let (set, pe) = desc.parse_set(a, raw[0usize..h.len / 2usize])
    if pe != ok { os.exit(2) }
    let (text, ge) = stub.generate(a, set)
    if ge != ok { os.exit(3) }
    try io.print(text)
    ret ok
}
''' % set_hex)
    exe = os.path.join(tmp, 'gen.exe')
    out = subprocess.run([neper, 'emit-executable', gen_src, ROOT, 'x64', 'windows', exe], capture_output=True, text=True)
    if 'executable written' not in out.stdout:
        sys.exit('generator build failed: ' + out.stdout + out.stderr)
    ran = subprocess.run([exe], capture_output=True)
    if ran.returncode != 0:
        sys.exit('generator exited %d' % ran.returncode)
    stub_text = ran.stdout.decode('utf-8').replace(chr(13) + chr(10), chr(10))
    if '"#' in stub_text:
        sys.exit('generated text contains a raw-string terminator')
    os.makedirs(FIX, exist_ok=True)
    with open(os.path.join(FIX, 'kitchen.e'), 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(stub_text)

    # 2. vectors
    lines = []
    for n in names:
        for _ in range(40 if n not in ('ks.v1.Empty',) else 2):
            m = classes[n]()
            fill(m)
            lines.append('%s\t%s' % (n, m.SerializeToString().hex()))
    # fixed messages, decoded and checked field by field
    sc = classes['ks.v1.Scalars']()
    sc.d, sc.f, sc.i32, sc.i64, sc.u32, sc.u64 = 2.5, 0.5, -7, -9000000000, 4000000000, 2 ** 63 + 5
    sc.s32, sc.s64, sc.x32, sc.x64, sc.sx32, sc.sx64 = -300, -2 ** 40, 77, 2 ** 50, -1, -2 ** 33
    sc.b, sc.s, sc.by, sc.color = True, 'hi \u00e9', b'\x01\x02', -5
    fixed_scalars = sc.SerializeToString().hex()
    rp = classes['ks.v1.Repeats']()
    rp.ints.extend([1, -1, 300]); rp.sints.extend([-3, 4]); rp.doubles.extend([0.25, -1.0]); rp.strs.extend(['a', '', 'ccc'])
    rp.blobs.extend([b'\x00', b'']); rp.flags.extend([True, False, True]); rp.colors.extend([1, 7, -5]); rp.fx.extend([5, 6])
    rp.items.add().i32 = 9; rp.unpacked.extend([4, 5, 6]); rp.floats.extend([1.5, 2.5]); rp.sfx.extend([-1, 1])
    fixed_repeats = rp.SerializeToString().hex()
    nd = classes['ks.v1.Node']()
    nd.name = 'root'; nd.child.name = 'kid'; nd.kids.add().name = 'k1'; nd.kids.add().name = 'k2'
    nd.counts['a'] = 1; nd.counts['b'] = 2; nd.by_id[7].s = 'seven'; nd.maybe = 0; nd.number = 99; nd.c = 2
    fixed_node = nd.SerializeToString().hex()
    lg = classes['ks.legacy.Legacy']()
    lg.id = -1; lg.name = 'old'; lg.packed_list.extend([1, 2, 3]); lg.plain.extend([4, 5]); lg.flag = False; lg.ratio = 0.0; lg.blob = b''; lg.who = 7
    fixed_legacy = lg.SerializeToString().hex()
    kw = classes['ks.v1.Keywords']()
    kw.type, kw.zero = 5, 1.25
    setattr(kw, 'in', 'inside'); kw.error = True
    fixed_keywords = kw.SerializeToString().hex()

    payload = b''
    for _ in range(105):
        n = len(payload)
        varint = bytearray()
        while True:
            b = n & 127
            n >>= 7
            if n:
                varint.append(b | 128)
            else:
                varint.append(b)
                break
        payload = b'' + bytes(varint) + payload
    deep_hex = payload.hex()

    vectors = '\\n'.join(l.replace('\t', '\\t') for l in lines) + '\\n'

    # one dispatch per message: decode, re-encode, compare
    cases = []
    for n in names:
        t = type_ident(n)
        f = snake(t)
        cases.append('''    if str.eq(name, "%s") {
        let (m, e) = kitchen.%s_decode(a, raw)
        if e != ok { ret 2u8 }
        let (again, ee) = kitchen.%s_encode(a, &m)
        if ee != ok { ret 3u8 }
        if !same(again, raw) {
            let shown = io.print(hex_of(a, again))
            let shown_nl = io.print("\\n")
            ret 4u8
        }
        ret 0u8
    }
''' % (n, f, f))
    dispatch = ''.join(cases)

    main_e = open(os.path.join(ROOT, 'scripts', 'grpcstub_fixture_template.e'), encoding='utf-8').read().replace('\r\n', '\n')
    main_e = main_e.replace('@@SET@@', set_hex).replace('@@VECTORS@@', vectors).replace('@@DISPATCH@@', dispatch)
    main_e = main_e.replace('@@COUNT@@', str(len(lines)))
    main_e = main_e.replace('@@FIXED_SCALARS@@', fixed_scalars).replace('@@FIXED_REPEATS@@', fixed_repeats).replace('@@FIXED_NODE@@', fixed_node)
    main_e = main_e.replace('@@FIXED_LEGACY@@', fixed_legacy).replace('@@FIXED_KEYWORDS@@', fixed_keywords)
    main_e = main_e.replace('@@DEEP@@', deep_hex)
    main_e = main_e.replace('@@GOLDEN@@', stub_text)
    with open(os.path.join(FIX, 'main.e'), 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(main_e)
    print('%d vectors, stub of %d bytes -> net_grpcstub' % (len(lines), len(stub_text)))


main()
