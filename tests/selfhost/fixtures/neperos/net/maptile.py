"""A Mapbox Vector Tile (specification 2.1) for the Maps fixture (C160), built here with the protobuf wire format and the
geometry commands written out independently of lib/e/fmt/mvt.e: three layers of an OpenFreeMap-shaped tile
(`transportation` with a class, `water`, `poi` with names) in an extent of 4096."""


def varint(n):
    out = bytearray()
    while True:
        b = n & 127
        n >>= 7
        out.append(b | 128 if n else b)
        if not n:
            return bytes(out)


def field_bytes(number, payload):
    return varint((number << 3) | 2) + varint(len(payload)) + payload


def field_varint(number, value):
    return varint(number << 3) + varint(value)


def zig(n):
    return (n << 1) ^ (n >> 31)


def line_geometry(parts, closed=False):
    out, x, y = [], 0, 0
    for part in parts:
        out += [(1 & 7) | (1 << 3), zig(part[0][0] - x), zig(part[0][1] - y)]
        x, y = part[0]
        out.append(2 | ((len(part) - 1) << 3))
        for px, py in part[1:]:
            out += [zig(px - x), zig(py - y)]
            x, y = px, py
        if closed:
            out.append(7 | (1 << 3))
    return out


def point_geometry(points):
    out, x, y = [1 | (len(points) << 3)], 0, 0
    for px, py in points:
        out += [zig(px - x), zig(py - y)]
        x, y = px, py
    return out


def packed(values):
    return b"".join(varint(v) for v in values)


def feature(tags, kind, geometry):
    return (field_bytes(2, packed(tags)) if tags else b"") + field_varint(3, kind) + field_bytes(4, packed(geometry))


def layer(name, features, keys, values):
    out = field_varint(15, 2) + field_bytes(1, name.encode())
    for f in features:
        out += field_bytes(2, f)
    for k in keys:
        out += field_bytes(3, k.encode())
    for v in values:
        out += field_bytes(4, field_bytes(1, v.encode()))
    return out + field_varint(5, 4096)


# Streets and one main road across the tile, a river, and three named places.
STREETS = [[(400, 3000), (4096 - 400, 3000)], [(1200, 400), (1200, 3800)], [(2800, 600), (2800, 1800), (3600, 2400)]]
ROAD = [[(100, 1200), (1500, 1500), (3000, 1300), (4000, 1700)]]
RIVER = [[(0, 3600), (1000, 3300), (2200, 3500), (4096, 3200)]]
PLACES = [("City Library", (1200, 3000)), ("Central Cafe", (2800, 1800)), ("Harbour Park", (900, 3500))]


def tile():
    # transportation: keys [class]; values [street, primary]
    roads = [feature([0, 0], 2, line_geometry([p])) for p in STREETS]
    roads += [feature([0, 1], 2, line_geometry(ROAD))]
    transportation = layer("transportation", roads, ["class"], ["street", "primary"])
    water = layer("water", [feature([], 2, line_geometry(RIVER))], [], [])
    poi = layer("poi", [feature([0, i], 1, point_geometry([pos])) for i, (_, pos) in enumerate(PLACES)],
                ["name"], [n for n, _ in PLACES])
    return field_bytes(3, transportation) + field_bytes(3, water) + field_bytes(3, poi)
