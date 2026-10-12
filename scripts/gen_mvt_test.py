#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/fmt_mvt/src/main.e (C160): e.fmt.mvt decoding a vector tile built here by an
independent encoder (the protobuf wire format and the geometry commands of the Mapbox Vector Tile specification 2.1),
the decoded layers, features, absolute geometry and typed values compared with what was encoded."""
import struct
from pathlib import Path


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


def key(number, wire):
    return varint((number << 3) | wire)


def field_bytes(number, payload):
    return key(number, 2) + varint(len(payload)) + payload


def field_varint(number, value):
    return key(number, 0) + varint(value)


def zig(n):
    return (n << 1) ^ (n >> 31) if n >= 0 else ((-n) << 1) - 1


def command(id_, count):
    return (count << 3) | id_


def geometry_points(points):
    out = [command(1, len(points))]
    x = y = 0
    for px, py in points:
        out += [zig(px - x), zig(py - y)]
        x, y = px, py
    return out, (x, y)


def geometry_parts(parts, closed):
    out = []
    x = y = 0
    for part in parts:
        px, py = part[0]
        out += [command(1, 1), zig(px - x), zig(py - y)]
        x, y = px, py
        rest = part[1:]
        if closed:
            rest = part[1:]  # the ring's closing point is implied
        if rest:
            out.append(command(2, len(rest)))
            for qx, qy in rest:
                out += [zig(qx - x), zig(qy - y)]
                x, y = qx, qy
        if closed:
            out.append(command(7, 1))
    return out


def packed(values):
    return b"".join(varint(v) for v in values)


def feature(id_, tags, kind, geom):
    payload = b""
    if id_ is not None:
        payload += field_varint(1, id_)
    if tags:
        payload += field_bytes(2, packed(tags))
    payload += field_varint(3, kind)
    payload += field_bytes(4, packed(geom))
    return payload


def value_string(s):
    return field_bytes(1, s.encode())


def value_float(f):
    return key(2, 5) + struct.pack("<f", f)


def value_double(f):
    return key(3, 1) + struct.pack("<d", f)


def value_int(i):
    return field_varint(4, i & ((1 << 64) - 1))


def value_uint(i):
    return field_varint(5, i)


def value_sint(i):
    return field_varint(6, zig64(i))


def zig64(n):
    return (n << 1) ^ (n >> 63) if n >= 0 else ((-n) << 1) - 1


def value_bool(b):
    return field_varint(7, 1 if b else 0)


POINTS = [(25, 17), (5, 9), (100, 1000)]
LINES = [[(2, 2), (2, 10), (10, 10)], [(1, 1), (3, 5)]]
POLY = [[(0, 0), (8, 0), (8, 8), (0, 8)], [(2, 2), (2, 6), (6, 6), (6, 2)]]

# Layer "places": keys [name, class, rank, ratio, big, delta, open]; values in encounter order.
values = [value_string("Oslo"), value_string("city"), value_int(3), value_double(0.5), value_uint(1 << 40),
          value_sint(-77), value_bool(True), value_float(1.5)]
f_points = feature(7, [0, 0, 1, 1], 1, geometry_points(POINTS)[0])
f_lines = feature(None, [2, 2], 2, geometry_parts(LINES, False))
f_poly = feature(9, [3, 3, 4, 4, 5, 5, 6, 6], 3, geometry_parts(POLY, True))
layer1 = (field_varint(15, 2) + field_bytes(1, b"places") + field_bytes(2, f_points) + field_bytes(2, f_lines) +
          field_bytes(2, f_poly) + b"".join(field_bytes(3, k.encode()) for k in
                                           ["name", "class", "rank", "ratio", "big", "delta", "open"]) +
          b"".join(field_bytes(4, v) for v in values) + field_varint(5, 8192))
layer2 = field_bytes(1, b"water") + field_bytes(2, feature(1, [], 3, geometry_parts([[(0, 0), (4096, 0), (4096, 4096), (0, 4096)]], True)))
TILE = field_bytes(3, layer1) + field_bytes(3, layer2)
BAD = field_bytes(3, field_bytes(1, b"x") + field_bytes(2, key(3, 0) + varint(1) + field_bytes(4, packed([command(1, 3), 2, 2]))))


def arr(name, data):
    return "    let %s: [%d]u8 = [%d]u8{ %s }\n" % (name, len(data), len(data), ", ".join(str(b) for b in data))


def main():
    out = ["// `e.fmt.mvt` against a tile built by an independent encoder (scripts/gen_mvt_test.py): two layers, point, line and\n",
           "// polygon features with relative geometry, a key/value table of every value type, and a truncated geometry list\n",
           "// refused. Every check has its own exit code.\n",
           "use e.os\nuse e.mem\nuse e.str\nuse e.fmt.mvt as mvt\n\n",
           "fn main(a: *mem.Arena, args: []str) -> err {\n"]
    out.append(arr("tile", TILE))
    out.append(arr("bad", BAD))
    n = 0

    def check(cond):
        nonlocal n
        n += 1
        out.append("    if %s { os.exit(%d) }\n" % (cond, n))

    out.append("    let (layers, e) = mvt.parse(a, tile[0..])\n")
    check("e != ok || layers.len != 2usize")
    check("!str.eq(layers[0].name, \"places\") || layers[0].version != 2u32 || layers[0].extent != 8192u32")
    check("layers[0].keys.len != 7usize || !str.eq(layers[0].keys[0], \"name\") || !str.eq(layers[0].keys[6], \"open\")")
    check("layers[0].values.len != 8usize || layers[0].features.len != 3usize")
    check("layers[0].values[0].kind != mvt.VALUE_STRING || !str.eq(layers[0].values[0].text, \"Oslo\")")
    check("layers[0].values[2].kind != mvt.VALUE_INT || layers[0].values[2].integer != 3i64")
    check("layers[0].values[3].kind != mvt.VALUE_DOUBLE || layers[0].values[3].number != 0.5f64")
    check("layers[0].values[4].kind != mvt.VALUE_UINT || layers[0].values[4].integer != %di64" % (1 << 40))
    check("layers[0].values[5].kind != mvt.VALUE_SINT || layers[0].values[5].integer != 0i64 - 77i64")
    check("layers[0].values[6].kind != mvt.VALUE_BOOL || layers[0].values[6].integer != 1i64")
    check("layers[0].values[7].kind != mvt.VALUE_FLOAT || layers[0].values[7].number != 1.5f64")
    out.append("    let p = layers[0].features[0]\n")
    check("!p.has_id || p.id != 7u64 || p.kind != mvt.KIND_POINT || p.points.len != 3usize || p.parts.len != 0usize")
    check("p.tags.len != 4usize || p.tags[0] != 0u32 || p.tags[3] != 1u32")
    for i, (x, y) in enumerate(POINTS):
        check("p.points[%d].x != %di32 || p.points[%d].y != %di32" % (i, x, i, y))
    out.append("    let l = layers[0].features[1]\n")
    check("l.has_id || l.kind != mvt.KIND_LINE || l.points.len != 5usize || l.parts.len != 2usize")
    check("l.parts[0] != 3usize || l.parts[1] != 5usize")
    flat = [pt for part in LINES for pt in part]
    for i, (x, y) in enumerate(flat):
        check("l.points[%d].x != %di32 || l.points[%d].y != %di32" % (i, x, i, y))
    out.append("    let g = layers[0].features[2]\n")
    check("!g.has_id || g.id != 9u64 || g.kind != mvt.KIND_POLYGON || g.points.len != 8usize || g.parts.len != 2usize")
    check("g.parts[0] != 4usize || g.parts[1] != 8usize")
    flat = [pt for part in POLY for pt in part]
    for i, (x, y) in enumerate(flat):
        check("g.points[%d].x != %di32 || g.points[%d].y != %di32" % (i, x, i, y))
    check("!str.eq(layers[1].name, \"water\") || layers[1].extent != 4096u32 || layers[1].version != 1u32 || layers[1].features.len != 1usize")
    check("layers[1].features[0].points.len != 4usize || layers[1].features[0].points[2].x != 4096i32 || layers[1].features[0].points[2].y != 4096i32")
    out.append("    let (bl, be) = mvt.parse(a, bad[0..])\n")
    check("be == ok")
    out.append("    ret ok\n}\n")
    target = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/fmt_mvt/src/main.e"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote", target, "checks", n)


main()
