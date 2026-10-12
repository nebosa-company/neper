"""Generate the fmt_protodesc fixture: descriptor sets read by `e.fmt.protodesc`, answered the way Python's protobuf does.

Oracle: google.protobuf's own parser and JSON mapping. The corpus is descriptor.proto itself, the well-known types,
plugin.proto and status.proto from the installed package, and hand-built files covering proto3 and proto2, nested and
map types, oneofs, proto3 optional, packed and unpacked lists, reserved and extension ranges, negative enum values, every
streaming shape of a service, unknown fields at several depths and sets of several files. The expected text is
`MessageToDict` of the parsed set reduced to the members `e.fmt.protodesc` models (named below), keys sorted. Inputs
that are not descriptors expect the module's `invalid`.

    python scripts/protodesc_vectors.py
"""
import json
import os

from google.protobuf import descriptor_pb2 as d
from google.protobuf import json_format

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE = os.path.join(ROOT, 'tests', 'selfhost', 'fixtures', 'link', 'fmt_protodesc', 'src', 'main.e')

KEEP = {
    'set': {'file': 'file'},
    'file': {'name': None, 'package': None, 'dependency': None, 'publicDependency': None, 'weakDependency': None, 'messageType': 'message',
             'enumType': 'enum', 'service': 'service', 'extension': 'field', 'syntax': None},
    'message': {'name': None, 'field': 'field', 'nestedType': 'message', 'enumType': 'enum', 'extensionRange': 'range', 'extension': 'field',
                'options': 'message_options', 'oneofDecl': 'oneof', 'reservedRange': 'range', 'reservedName': None},
    'field': {'name': None, 'extendee': None, 'number': None, 'label': None, 'type': None, 'typeName': None, 'defaultValue': None,
              'options': 'field_options', 'oneofIndex': None, 'jsonName': None, 'proto3Optional': None},
    'enum': {'name': None, 'value': 'enum_value', 'options': 'enum_options', 'reservedRange': 'range', 'reservedName': None},
    'enum_value': {'name': None, 'number': None},
    'service': {'name': None, 'method': 'method', 'options': 'no_options'},
    'method': {'name': None, 'inputType': None, 'outputType': None, 'options': 'no_options', 'clientStreaming': None, 'serverStreaming': None},
    'oneof': {'name': None},
    'range': {'start': None, 'end': None},
    'message_options': {'mapEntry': None, 'deprecated': None},
    'field_options': {'packed': None, 'deprecated': None},
    'enum_options': {'allowAlias': None, 'deprecated': None},
    'no_options': {},
}


def reduce(value, kind):
    keep = KEEP[kind]
    out = {}
    for key, v in value.items():
        if key not in keep:
            continue
        child = keep[key]
        if child is None:
            out[key] = v
        elif isinstance(v, list):
            out[key] = [reduce(x, child) for x in v]
        else:
            out[key] = reduce(v, child)
    return out


def expected_set(raw):
    parsed = d.FileDescriptorSet.FromString(raw)
    return json.dumps(reduce(json_format.MessageToDict(parsed), 'set'), sort_keys=True, separators=(',', ':'))


def expected_file(raw):
    parsed = d.FileDescriptorProto.FromString(raw)
    return json.dumps(reduce(json_format.MessageToDict(parsed), 'file'), sort_keys=True, separators=(',', ':'))


def varint(n):
    out = bytearray()
    while True:
        b = n & 127
        n >>= 7
        if n:
            out.append(b | 128)
        else:
            out.append(b)
            return bytes(out)


def unknown_varint(number, value):
    return varint((number << 3) | 0) + varint(value)


def unknown_bytes(number, data):
    return varint((number << 3) | 2) + varint(len(data)) + data


F = d.FieldDescriptorProto


def field(msg, name, number, type_, label=F.LABEL_OPTIONAL, **kw):
    f = msg.field.add()
    f.name = name
    f.number = number
    f.type = type_
    f.label = label
    for k, v in kw.items():
        setattr(f, k, v)
    return f


def handmade():
    out = []
    # proto3 service file with every streaming shape, nested and map types, oneofs and optional
    f = d.FileDescriptorProto(name='shop/v1/shop.proto', package='shop.v1', syntax='proto3')
    f.dependency.extend(['google/protobuf/timestamp.proto', 'google/protobuf/any.proto'])
    f.public_dependency.append(0)
    f.weak_dependency.append(1)
    order = f.message_type.add()
    order.name = 'Order'
    field(order, 'id', 1, F.TYPE_INT64, json_name='id')
    field(order, 'customer', 2, F.TYPE_STRING)
    field(order, 'lines', 3, F.TYPE_MESSAGE, F.LABEL_REPEATED, type_name='.shop.v1.Order.Line')
    field(order, 'tags', 4, F.TYPE_STRING, F.LABEL_REPEATED)
    field(order, 'scores', 5, F.TYPE_SINT32, F.LABEL_REPEATED)
    field(order, 'labels', 6, F.TYPE_MESSAGE, F.LABEL_REPEATED, type_name='.shop.v1.Order.LabelsEntry')
    field(order, 'placed', 7, F.TYPE_MESSAGE, type_name='.google.protobuf.Timestamp')
    field(order, 'status', 8, F.TYPE_ENUM, type_name='.shop.v1.Order.Status')
    field(order, 'note', 9, F.TYPE_STRING, oneof_index=0)
    field(order, 'code', 10, F.TYPE_INT32, oneof_index=0)
    field(order, 'priority', 11, F.TYPE_INT32, proto3_optional=True, oneof_index=1)
    field(order, 'blob', 12, F.TYPE_BYTES)
    field(order, 'ratio', 13, F.TYPE_DOUBLE)
    field(order, 'big', 536870911, F.TYPE_FIXED64)
    order.oneof_decl.add().name = 'detail'
    order.oneof_decl.add().name = '_priority'
    line = order.nested_type.add()
    line.name = 'Line'
    field(line, 'sku', 1, F.TYPE_STRING)
    field(line, 'qty', 2, F.TYPE_UINT32)
    entry = order.nested_type.add()
    entry.name = 'LabelsEntry'
    field(entry, 'key', 1, F.TYPE_STRING)
    field(entry, 'value', 2, F.TYPE_STRING)
    entry.options.map_entry = True
    status = order.enum_type.add()
    status.name = 'Status'
    for n, num in (('UNKNOWN', 0), ('OPEN', 1), ('SHIPPED', 2), ('LOST', -1)):
        v = status.value.add()
        v.name = n
        v.number = num
    status.options.allow_alias = False
    order.reserved_range.add(start=20, end=30)
    order.reserved_name.extend(['legacy', 'old'])
    receipt = f.message_type.add()
    receipt.name = 'Receipt'
    field(receipt, 'order', 1, F.TYPE_MESSAGE, type_name='.shop.v1.Order')
    ping = f.message_type.add()
    ping.name = 'Ping'
    top = f.enum_type.add()
    top.name = 'Region'
    for n, num in (('REGION_UNSPECIFIED', 0), ('EU', 1), ('US', 2)):
        v = top.value.add()
        v.name = n
        v.number = num
    top.reserved_range.add(start=10, end=12)
    top.reserved_name.append('GONE')
    svc = f.service.add()
    svc.name = 'Shop'
    for name, cs, ss in (('Place', False, False), ('Watch', False, True), ('Upload', True, False), ('Chat', True, True)):
        m = svc.method.add()
        m.name = name
        m.input_type = '.shop.v1.Order'
        m.output_type = '.shop.v1.Receipt'
        m.client_streaming = cs
        m.server_streaming = ss
    m = svc.method.add()
    m.name = 'Heartbeat'
    m.input_type = '.shop.v1.Ping'
    m.output_type = '.shop.v1.Ping'
    m.options.deprecated = True
    svc.options.deprecated = True
    other = f.service.add()
    other.name = 'Admin'
    out.append(('shop', 'F', f.SerializeToString()))
    out.append(('shop-with-unknowns', 'F', f.SerializeToString() + unknown_varint(99, 7) + unknown_bytes(100, b'skipped')))
    # unknown fields inside nested messages and fields
    g = d.FileDescriptorProto.FromString(f.SerializeToString())
    g.message_type[0].field[0].MergeFromString(unknown_varint(77, 300) + unknown_bytes(78, b'x' * 40))
    g.message_type[0].MergeFromString(unknown_varint(55, 1))
    g.service[0].method[0].MergeFromString(unknown_bytes(60, b'zz'))
    out.append(('nested-unknowns', 'F', g.SerializeToString()))

    # proto2 with required, defaults, groups-free extension ranges and extensions, packed, deprecated
    p = d.FileDescriptorProto(name='legacy.proto', package='legacy')
    m = p.message_type.add()
    m.name = 'Thing'
    field(m, 'id', 1, F.TYPE_INT32, F.LABEL_REQUIRED)
    field(m, 'name', 2, F.TYPE_STRING, default_value='anon')
    field(m, 'weights', 3, F.TYPE_FLOAT, F.LABEL_REPEATED).options.packed = True
    field(m, 'ids', 4, F.TYPE_INT64, F.LABEL_REPEATED).options.packed = False
    field(m, 'mode', 5, F.TYPE_ENUM, type_name='.legacy.Thing.Mode', default_value='FAST')
    field(m, 'flag', 6, F.TYPE_BOOL, default_value='true').options.deprecated = True
    field(m, 'lowest', 7, F.TYPE_SINT64, default_value='-9')
    mode = m.enum_type.add()
    mode.name = 'Mode'
    for n, num in (('SLOW', 0), ('FAST', 1)):
        v = mode.value.add()
        v.name = n
        v.number = num
    mode.options.allow_alias = True
    m.extension_range.add(start=100, end=200)
    m.extension_range.add(start=1000, end=536870912)
    ext = p.extension.add()
    ext.name = 'extra'
    ext.number = 150
    ext.type = F.TYPE_STRING
    ext.label = F.LABEL_OPTIONAL
    ext.extendee = '.legacy.Thing'
    m.options.deprecated = True
    out.append(('legacy', 'F', p.SerializeToString()))

    # an empty file, a name only, and a set of several files
    out.append(('empty-file', 'F', b''))
    out.append(('name-only', 'F', d.FileDescriptorProto(name='a.proto').SerializeToString()))
    s = d.FileDescriptorSet()
    s.file.add().CopyFrom(f)
    s.file.add().CopyFrom(p)
    s.file.add(name='third.proto', package='third')
    out.append(('set-three', 'S', s.SerializeToString()))
    out.append(('empty-set', 'S', b''))
    out.append(('set-unknown', 'S', s.SerializeToString() + unknown_varint(9, 1)))

    # a message nested 32 deep (read) and a hostile list of packed ints
    deep = d.FileDescriptorProto(name='deep.proto')
    cur = deep.message_type.add()
    cur.name = 'M0'
    for i in range(1, 31):
        cur = cur.nested_type.add()
        cur.name = 'M%d' % i
    out.append(('deep-31', 'F', deep.SerializeToString()))
    packed = d.FileDescriptorProto(name='packed.proto')
    packed.public_dependency.extend([0, 1, 2, 300, 70000])
    out.append(('packed-ints', 'F', packed.SerializeToString()))
    raw_packed = unknown_bytes(1, b'p.proto') + unknown_bytes(10, bytes([1, 2, 3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]))
    out.append(('packed-negative', 'F', raw_packed))
    return out


def corpus():
    from google.protobuf import any_pb2, api_pb2, duration_pb2, empty_pb2, field_mask_pb2, source_context_pb2, struct_pb2, timestamp_pb2, type_pb2, wrappers_pb2
    from google.protobuf.compiler import plugin_pb2
    from google.rpc import status_pb2
    out = []
    mods = [d, any_pb2, api_pb2, duration_pb2, empty_pb2, field_mask_pb2, source_context_pb2, struct_pb2, timestamp_pb2, type_pb2, wrappers_pb2, plugin_pb2, status_pb2]
    for mod in mods:
        proto = d.FileDescriptorProto()
        mod.DESCRIPTOR.CopyToProto(proto)
        out.append((proto.name, 'F', proto.SerializeToString()))
    return out


def bad_inputs():
    good = d.FileDescriptorProto(name='x.proto', package='p').SerializeToString()
    return [
        ('truncated-length', 'F', good[:-1]),
        ('bad-wire-type', 'F', b'\x0b'),
        ('field-zero', 'F', b'\x00\x01'),
        ('varint-overlong', 'F', b'\x08' + b'\xff' * 10 + b'\x01'),
        ('length-past-end', 'F', b'\x0a\x7f' + b'ab'),
        ('set-truncated', 'S', b'\x0a\x10' + good[:5]),
    ]


rows = []
for name, kind, raw in handmade() + corpus():
    want = expected_set(raw) if kind == 'S' else expected_file(raw)
    rows.append((name, kind, raw.hex(), want))
for name, kind, raw in bad_inputs():
    rows.append((name, kind, raw.hex(), 'invalid'))
# the 33-deep file is refused by the module's own depth limit (protobuf's recursion limit is 100)
deep = d.FileDescriptorProto(name='deep.proto')
cur = deep.message_type.add()
cur.name = 'M0'
for i in range(1, 33):
    cur = cur.nested_type.add()
    cur.name = 'M%d' % i
rows.append(('deep-33', 'F', deep.SerializeToString().hex(), 'invalid'))

lines = []
for name, kind, hexed, want in rows:
    lines.append('%s\t%s\t%s\t%s' % (name, kind, hexed, want))
vectors = '\\n'.join(l.replace('\\', '\\\\').replace('"', '\\"').replace('\t', '\\t') for l in lines) + '\\n'

source = r'''// `e.fmt.protodesc` against Python's protobuf: scripts/protodesc_vectors.py serialises descriptor.proto itself, the
// well-known types, plugin.proto, status.proto and hand-built proto3 and proto2 files (nested and map types, oneofs,
// proto3 optional, packed lists, reserved and extension ranges, negative enum values, every streaming shape, unknown
// fields at several depths, sets of several files) and answers each with `MessageToDict` of the parsed set reduced to
// the modelled members; the fixture reads the same bytes and compares canonical JSON. Malformed bytes and a message
// nested 33 deep answer `invalid`. Generated; do not edit.
use e.algo.chain as chain
use e.fmt.json as json
use e.fmt.protodesc as desc
use e.io
use e.mem
use e.os
use e.str

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(a: *mem.Arena, h: str) -> []u8 {
    let (out, e) = mem.alloc[u8](a, h.len / 2usize + 1usize)
    if e != ok { os.exit(80) }
    var i = 0usize
    while i + 1usize < h.len {
        out[i / 2usize] = nibble(h[i]) * 16u8 + nibble(h[i + 1usize])
        i += 2usize
    }
    ret out[0usize..h.len / 2usize]
}

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(81) }
    ret out
}

fn run_line(a: *mem.Arena, line: str) -> u8 {
    // name TAB kind TAB hex TAB expected
    var parts: [4]str = zero
    var count = 0usize
    var from = 0usize
    var i = 0usize
    while i <= line.len {
        if i == line.len || line[i] == 9u8 {
            if count < 4usize { parts[count] = line[from..i] }
            count += 1usize
            from = i + 1usize
        }
        i += 1usize
    }
    if count != 4usize { ret 90u8 }
    let raw = unhex(a, parts[2])
    var value: json.Value = .Null
    var failed = false
    if str.eq(parts[1], "S") {
        let (v, e) = desc.parse_set(a, raw)
        if e != ok { failed = true } else { value = v }
    } else {
        let (v, e) = desc.parse_file(a, raw)
        if e != ok { failed = true } else { value = v }
    }
    var got = "invalid"
    if !failed {
        let (rendered, render_error) = chain.canonical_json(a, value)
        if render_error != ok { ret 91u8 }
        got = rendered
    }
    if str.eq(got, parts[3]) { ret 0u8 }
    let shown = io.print(cat(a, cat(a, "case ", parts[0]), "\n"))
    let shown_got = io.print(cat(a, cat(a, "got  ", got), "\n"))
    let shown_want = io.print(cat(a, cat(a, "want ", parts[3]), "\n"))
    ret 1u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    let table = "@@VECTORS@@"
    var start = 0usize
    var at = 0usize
    var count = 0usize
    while at < table.len {
        if table[at] == 10u8 {
            let mark = mem.mark(a)
            let code = run_line(a, table[start..at])
            if code != 0u8 { os.exit(i32(code)) }
            mem.reset(a, mark)
            count += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    if count != @@COUNT@@usize { os.exit(100) }
    try io.print("fmt protodesc ok")
    ret ok
}
'''
source = source.replace('@@VECTORS@@', vectors).replace('@@COUNT@@', str(len(rows)))
os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
with open(FIXTURE, 'w', encoding='utf-8', newline='\n') as fh:
    fh.write(source)
print('%d cases -> fmt_protodesc' % len(rows))
