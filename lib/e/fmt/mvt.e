// Mapbox Vector Tiles (specification 2.1, the tile format OpenStreetMap vector sources such as OpenFreeMap and
// Protomaps serve), decoded over e.fmt.protobuf: `parse` reads the tile's layers (name, extent, version, the key and
// value tables) and each layer's features (id, geometry type, tag pairs, and the geometry commands MoveTo, LineTo and
// ClosePath resolved to absolute integer points in the layer's extent). A point feature has one point per MoveTo
// coordinate; a line or polygon feature's `parts` gives where each linestring or ring ends in `points` (a polygon ring's
// ClosePath adds nothing: the ring is closed by its first point). Values keep their protobuf type. Tile coordinates
// are y down from the north-west corner; a transform to the screen is the renderer's. Over-long or truncated geometry
// and tag lists are `Invalid`.
//
// Memory: every result lives in the arena passed in; strings point into `data`.
use e.mem
use e.bytes
use e.fmt.protobuf as pb

error Invalid
error TooMany

const KIND_POINT: u8 = 1u8
const KIND_LINE: u8 = 2u8
const KIND_POLYGON: u8 = 3u8
const VALUE_NONE: u8 = 0u8
const VALUE_STRING: u8 = 1u8
const VALUE_FLOAT: u8 = 2u8
const VALUE_DOUBLE: u8 = 3u8
const VALUE_INT: u8 = 4u8
const VALUE_UINT: u8 = 5u8
const VALUE_SINT: u8 = 6u8
const VALUE_BOOL: u8 = 7u8
const MAX_POINTS: usize = 65536usize

type Value = struct { kind: u8, text: str, number: f64, integer: i64 }
type Point = struct { x: i32, y: i32 }
type Feature = struct { id: u64, has_id: bool, kind: u8, tags: []u32, points: []Point, parts: []usize }
type Layer = struct { name: str, version: u32, extent: u32, keys: []str, values: []Value, features: []Feature }

// The packed varints of `payload` as u32s into the arena.
fn packed(a: *mem.Arena, payload: []const u8) -> ([]u32, err) {
    var r = pb.reader(payload)
    var count = 0usize
    while bytes.remaining_reader(&r.input) > 0usize {
        let (v, e) = pb.read_u64(&r)
        if e != ok { ret (zero, Invalid) }
        count += 1usize
    }
    let (out, out_error) = mem.alloc[u32](a, count + 1usize)
    if out_error != ok { ret (zero, out_error) }
    var r2 = pb.reader(payload)
    var i = 0usize
    while i < count {
        let (v, e) = pb.read_u64(&r2)
        if e != ok { ret (zero, Invalid) }
        out[i] = u32(v & 4294967295u64)
        i += 1usize
    }
    ret (out[0usize..count], ok)
}

fn unzig(v: u32) -> i32 {
    let half = i64(v / 2u32)
    if (v & 1u32) == 1u32 { ret i32(0i64 - half - 1i64) }
    ret i32(half)
}

// The geometry commands into points and part ends.
fn decode_geometry(a: *mem.Arena, kind: u8, commands: []const u32) -> ([]Point, []usize, err) {
    // First pass: how many points and parts.
    var point_total = 0usize
    var part_total = 0usize
    var i = 0usize
    while i < commands.len {
        let command = commands[i] & 7u32
        let count = usize(commands[i] / 8u32)
        i += 1usize
        if command == 1u32 || command == 2u32 {
            if i + count * 2usize > commands.len { ret (zero, zero, Invalid) }
            point_total += count
            if command == 1u32 && kind != KIND_POINT { part_total += count }
            i += count * 2usize
        } else if command == 7u32 {
            // ClosePath takes no parameters.
        } else {
            ret (zero, zero, Invalid)
        }
        if point_total > MAX_POINTS { ret (zero, zero, TooMany) }
    }
    let (points, points_error) = mem.alloc[Point](a, point_total + 1usize)
    if points_error != ok { ret (zero, zero, points_error) }
    let (parts, parts_error) = mem.alloc[usize](a, part_total + 2usize)
    if parts_error != ok { ret (zero, zero, parts_error) }
    var x = 0i32
    var y = 0i32
    var n = 0usize
    var p = 0usize
    i = 0usize
    while i < commands.len {
        let command = commands[i] & 7u32
        let count = usize(commands[i] / 8u32)
        i += 1usize
        if command == 7u32 {
            // The ring just drawn ends here.
        } else {
            var k = 0usize
            while k < count {
                // A MoveTo after the first starts a new line or ring: the previous part ends before it.
                if command == 1u32 && kind != KIND_POINT && n > 0usize && (k == 0usize) {
                    parts[p] = n
                    p += 1usize
                }
                x = x + unzig(commands[i])
                y = y + unzig(commands[i + 1usize])
                points[n] = Point { x: x, y: y }
                n += 1usize
                i += 2usize
                k += 1usize
            }
        }
    }
    if kind != KIND_POINT && n > 0usize {
        parts[p] = n
        p += 1usize
    }
    ret (points[0usize..n], parts[0usize..p], ok)
}

fn parse_feature(a: *mem.Arena, payload: []const u8) -> (Feature, err) {
    var f: Feature = zero
    var r = pb.reader(payload)
    var geometry_payload = payload[0usize..0usize]
    var have_geometry = false
    var running = true
    while running {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (f, Invalid) }
        if !more {
            running = false
        } else if key.number == 1u32 && key.wire == .Varint {
            let (v, e) = pb.read_u64(&r)
            if e != ok { ret (f, Invalid) }
            f.id = v
            f.has_id = true
        } else if key.number == 2u32 && key.wire == .Bytes {
            let (b, e) = pb.read_bytes(&r)
            if e != ok { ret (f, Invalid) }
            let (tags, tags_error) = packed(a, b)
            if tags_error != ok { ret (f, tags_error) }
            f.tags = tags
        } else if key.number == 3u32 && key.wire == .Varint {
            let (v, e) = pb.read_u64(&r)
            if e != ok { ret (f, Invalid) }
            f.kind = u8(v & 255u64)
        } else if key.number == 4u32 && key.wire == .Bytes {
            let (b, e) = pb.read_bytes(&r)
            if e != ok { ret (f, Invalid) }
            geometry_payload = b
            have_geometry = true
        } else {
            let skipped = pb.skip(&r, key.wire)
            if skipped != ok { ret (f, Invalid) }
        }
    }
    if have_geometry {
        let (commands, commands_error) = packed(a, geometry_payload)
        if commands_error != ok { ret (f, commands_error) }
        let (points, parts, geometry_error) = decode_geometry(a, f.kind, commands)
        if geometry_error != ok { ret (f, geometry_error) }
        f.points = points
        f.parts = parts
    }
    ret (f, ok)
}

fn parse_value(payload: []const u8) -> (Value, err) {
    var v: Value = zero
    var r = pb.reader(payload)
    var running = true
    while running {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (v, Invalid) }
        if !more {
            running = false
        } else if key.number == 1u32 && key.wire == .Bytes {
            let (b, e) = pb.read_bytes(&r)
            if e != ok { ret (v, Invalid) }
            v.kind = VALUE_STRING
            v.text = b
        } else if key.number == 2u32 && key.wire == .Fixed32 {
            let (w, e) = pb.read_fixed32(&r)
            if e != ok { ret (v, Invalid) }
            v.kind = VALUE_FLOAT
            v.number = f64(f32_from_bits(w))
        } else if key.number == 3u32 && key.wire == .Fixed64 {
            let (w, e) = pb.read_fixed64(&r)
            if e != ok { ret (v, Invalid) }
            v.kind = VALUE_DOUBLE
            v.number = f64_from_bits(w)
        } else if key.number == 4u32 && key.wire == .Varint {
            let (w, e) = pb.read_i64(&r)
            if e != ok { ret (v, Invalid) }
            v.kind = VALUE_INT
            v.integer = w
        } else if key.number == 5u32 && key.wire == .Varint {
            let (w, e) = pb.read_u64(&r)
            if e != ok { ret (v, Invalid) }
            v.kind = VALUE_UINT
            if w > 9223372036854775807u64 { v.integer = 9223372036854775807i64 } else { v.integer = i64(w) }
        } else if key.number == 6u32 && key.wire == .Varint {
            let (w, e) = pb.read_sint64(&r)
            if e != ok { ret (v, Invalid) }
            v.kind = VALUE_SINT
            v.integer = w
        } else if key.number == 7u32 && key.wire == .Varint {
            let (w, e) = pb.read_u64(&r)
            if e != ok { ret (v, Invalid) }
            v.kind = VALUE_BOOL
            if w != 0u64 { v.integer = 1i64 }
        } else {
            let skipped = pb.skip(&r, key.wire)
            if skipped != ok { ret (v, Invalid) }
        }
    }
    ret (v, ok)
}

fn f32_from_bits(w: u32) -> f32 {
    ret mem.bitcast[f32](w)
}

fn f64_from_bits(w: u64) -> f64 {
    ret mem.bitcast[f64](w)
}

fn parse_layer(a: *mem.Arena, payload: []const u8) -> (Layer, err) {
    var layer: Layer = zero
    layer.version = 1u32
    layer.extent = 4096u32
    // Pass one counts the repeated fields.
    var feature_count = 0usize
    var key_count = 0usize
    var value_count = 0usize
    var r = pb.reader(payload)
    var running = true
    while running {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (layer, Invalid) }
        if !more {
            running = false
        } else {
            if key.number == 2u32 && key.wire == .Bytes { feature_count += 1usize }
            if key.number == 3u32 && key.wire == .Bytes { key_count += 1usize }
            if key.number == 4u32 && key.wire == .Bytes { value_count += 1usize }
            let skipped = pb.skip(&r, key.wire)
            if skipped != ok { ret (layer, Invalid) }
        }
    }
    let (features, features_error) = mem.alloc[Feature](a, feature_count + 1usize)
    if features_error != ok { ret (layer, features_error) }
    let (keys, keys_error) = mem.alloc[str](a, key_count + 1usize)
    if keys_error != ok { ret (layer, keys_error) }
    let (values, values_error) = mem.alloc[Value](a, value_count + 1usize)
    if values_error != ok { ret (layer, values_error) }
    var f = 0usize
    var k = 0usize
    var v = 0usize
    var r2 = pb.reader(payload)
    running = true
    while running {
        let (key, more, key_error) = pb.reader_next_err(&r2)
        if key_error != ok { ret (layer, Invalid) }
        if !more {
            running = false
        } else if key.number == 1u32 && key.wire == .Bytes {
            let (b, e) = pb.read_bytes(&r2)
            if e != ok { ret (layer, Invalid) }
            layer.name = b
        } else if key.number == 2u32 && key.wire == .Bytes {
            let (b, e) = pb.read_bytes(&r2)
            if e != ok { ret (layer, Invalid) }
            let (feature, feature_error) = parse_feature(a, b)
            if feature_error != ok { ret (layer, feature_error) }
            features[f] = feature
            f += 1usize
        } else if key.number == 3u32 && key.wire == .Bytes {
            let (b, e) = pb.read_bytes(&r2)
            if e != ok { ret (layer, Invalid) }
            keys[k] = b
            k += 1usize
        } else if key.number == 4u32 && key.wire == .Bytes {
            let (b, e) = pb.read_bytes(&r2)
            if e != ok { ret (layer, Invalid) }
            let (value, value_error) = parse_value(b)
            if value_error != ok { ret (layer, value_error) }
            values[v] = value
            v += 1usize
        } else if key.number == 5u32 && key.wire == .Varint {
            let (w, e) = pb.read_u64(&r2)
            if e != ok { ret (layer, Invalid) }
            layer.extent = u32(w & 4294967295u64)
        } else if key.number == 15u32 && key.wire == .Varint {
            let (w, e) = pb.read_u64(&r2)
            if e != ok { ret (layer, Invalid) }
            layer.version = u32(w & 4294967295u64)
        } else {
            let skipped = pb.skip(&r2, key.wire)
            if skipped != ok { ret (layer, Invalid) }
        }
    }
    layer.features = features[0usize..f]
    layer.keys = keys[0usize..k]
    layer.values = values[0usize..v]
    ret (layer, ok)
}

// The layers of a tile.
fn parse(a: *mem.Arena, data: []const u8) -> ([]Layer, err) {
    var count = 0usize
    var r = pb.reader(data)
    var running = true
    while running {
        let (key, more, key_error) = pb.reader_next_err(&r)
        if key_error != ok { ret (zero, Invalid) }
        if !more {
            running = false
        } else {
            if key.number == 3u32 && key.wire == .Bytes { count += 1usize }
            let skipped = pb.skip(&r, key.wire)
            if skipped != ok { ret (zero, Invalid) }
        }
    }
    let (layers, layers_error) = mem.alloc[Layer](a, count + 1usize)
    if layers_error != ok { ret (zero, layers_error) }
    var n = 0usize
    var r2 = pb.reader(data)
    running = true
    while running {
        let (key, more, key_error) = pb.reader_next_err(&r2)
        if key_error != ok { ret (zero, Invalid) }
        if !more {
            running = false
        } else if key.number == 3u32 && key.wire == .Bytes {
            let (b, e) = pb.read_bytes(&r2)
            if e != ok { ret (zero, Invalid) }
            let (layer, layer_error) = parse_layer(a, b)
            if layer_error != ok { ret (zero, layer_error) }
            layers[n] = layer
            n += 1usize
        } else {
            let skipped = pb.skip(&r2, key.wire)
            if skipped != ok { ret (zero, Invalid) }
        }
    }
    ret (layers[0usize..n], ok)
}
