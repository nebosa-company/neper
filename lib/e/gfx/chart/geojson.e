// GeoJSON (RFC 7946) polygons for `chart.choropleth` (D2115): a FeatureCollection's
// Polygon and MultiPolygon features become regions, rings and vertices in the
// caller's arena, in feature order. A region is keyed by the feature property `key`
// names, or by the feature's `id` when `key` is empty: a string, or a number's text
// as written. A feature whose geometry is null is left out; any other geometry type
// is Unsupported. Rings must be closed, as the RFC requires, and the closing
// position is dropped because the chart closes every ring itself. Each polygon's
// first ring is its exterior and the rest are holes; winding is the chart's
// concern. A position's third (altitude) number and foreign members are ignored.
use e.fmt.json
use e.gfx.chart
use e.mem
use e.str

error Invalid
error Unsupported

type Map = struct { regions: []chart.MapRegion, rings: []chart.MapRing, vertices: []chart.MapVertex }
type Counts = struct { regions: usize, rings: usize, vertices: usize }

// A member by its exact name; JSON Pointer escapes do not apply.
fn member(v: json.Value, name: str) -> (json.Value, bool) {
    switch v {
    case .Object as members:
        var i = 0usize
        while i < members.len {
            if str.eq(members[i].key, name) { ret (members[i].value, true) }
            i += 1usize
        }
    default:
        ret (zero, false)
    }
    ret (zero, false)
}

fn is_text(v: json.Value, want: str) -> bool {
    switch v {
    case .String as s:
        ret str.eq(s, want)
    default:
        ret false
    }
    ret false
}

fn is_null(v: json.Value) -> bool {
    switch v {
    case .Null:
        ret true
    default:
        ret false
    }
    ret false
}

fn items(v: json.Value) -> ([]const json.Value, bool) {
    switch v {
    case .Array as list:
        ret (list, true)
    default:
        ret (zero, false)
    }
    ret (zero, false)
}

fn position(v: json.Value) -> (f64, f64, err) {
    let (parts, is_parts) = items(v)
    if !is_parts || parts.len < 2usize { ret (0.0f64, 0.0f64, Invalid) }
    var lon = 0.0f64
    var lat = 0.0f64
    switch parts[0usize] {
    case .Number as n:
        let (value, value_error) = json.number_f64(n)
        if value_error != ok { ret (0.0f64, 0.0f64, Invalid) }
        lon = value
    default:
        ret (0.0f64, 0.0f64, Invalid)
    }
    switch parts[1usize] {
    case .Number as n:
        let (value, value_error) = json.number_f64(n)
        if value_error != ok { ret (0.0f64, 0.0f64, Invalid) }
        lat = value
    default:
        ret (0.0f64, 0.0f64, Invalid)
    }
    ret (lon, lat, ok)
}

fn key_of(feature: json.Value, key: str) -> (str, err) {
    var source: json.Value = .Null
    var has = false
    if key.len == 0usize {
        let (id, has_id) = member(feature, "id")
        source = id
        has = has_id
    } else {
        let (properties, has_properties) = member(feature, "properties")
        if has_properties {
            let (named, has_named) = member(properties, key)
            source = named
            has = has_named
        }
    }
    if !has { ret ("", Invalid) }
    switch source {
    case .String as s:
        if s.len == 0usize { ret ("", Invalid) }
        ret (s, ok)
    case .Number as n:
        ret (n.lexeme, ok)
    default:
        ret ("", Invalid)
    }
    ret ("", Invalid)
}

// One polygon's rings, counted into `at` and written into `m` when `fill`.
fn add_polygon(polygon: json.Value, region: usize, m: *Map, at: *Counts, fill: bool) -> err {
    let (rings, is_rings) = items(polygon)
    if !is_rings || rings.len == 0usize { ret Invalid }
    var r = 0usize
    while r < rings.len {
        let (positions, is_positions) = items(rings[r])
        if !is_positions || positions.len < 4usize { ret Invalid }
        let (first_lon, first_lat, first_error) = position(positions[0usize])
        if first_error != ok { ret first_error }
        let (last_lon, last_lat, last_error) = position(positions[positions.len - 1usize])
        if last_error != ok { ret last_error }
        if first_lon != last_lon || first_lat != last_lat { ret Invalid }
        let count = positions.len - 1usize
        if fill {
            m.rings[at.rings] = chart.MapRing { region: region, first: at.vertices, count: count, hole: r > 0usize }
            var p = 0usize
            while p < count {
                let (lon, lat, position_error) = position(positions[p])
                if position_error != ok { ret position_error }
                m.vertices[at.vertices + p] = chart.MapVertex { lon: lon, lat: lat }
                p += 1usize
            }
        }
        at.rings += 1usize
        at.vertices += count
        r += 1usize
    }
    ret ok
}

fn walk(features: []const json.Value, key: str, m: *Map, fill: bool) -> (Counts, err) {
    var at: Counts = zero
    var f = 0usize
    while f < features.len {
        let feature = features[f]
        let (kind, has_kind) = member(feature, "type")
        let (geometry, has_geometry) = member(feature, "geometry")
        if !has_kind || !is_text(kind, "Feature") || !has_geometry { ret (zero, Invalid) }
        if !is_null(geometry) {
            let (shape, has_shape) = member(geometry, "type")
            let (coordinates, has_coordinates) = member(geometry, "coordinates")
            if !has_shape || !has_coordinates { ret (zero, Invalid) }
            let (name, key_error) = key_of(feature, key)
            if key_error != ok { ret (zero, key_error) }
            if fill { m.regions[at.regions] = chart.MapRegion { key: name } }
            if is_text(shape, "Polygon") {
                let polygon_error = add_polygon(coordinates, at.regions, m, &at, fill)
                if polygon_error != ok { ret (zero, polygon_error) }
            } else if is_text(shape, "MultiPolygon") {
                let (polygons, is_polygons) = items(coordinates)
                if !is_polygons || polygons.len == 0usize { ret (zero, Invalid) }
                var p = 0usize
                while p < polygons.len {
                    let polygon_error = add_polygon(polygons[p], at.regions, m, &at, fill)
                    if polygon_error != ok { ret (zero, polygon_error) }
                    p += 1usize
                }
            } else {
                ret (zero, Unsupported)
            }
            at.regions += 1usize
        }
        f += 1usize
    }
    ret (at, ok)
}

// The parsed document and the three arrays live in `a`; a parse failure is
// e.fmt.json's error.
fn read(a: *mem.Arena, text: str, key: str) -> (Map, err) {
    let (root, parse_error) = json.parse(a, text, json.Options { allow_duplicate_keys: false, max_depth: json.DEFAULT_MAX_DEPTH })
    if parse_error != ok { ret (zero, parse_error) }
    let (kind, has_kind) = member(root, "type")
    let (listed, has_listed) = member(root, "features")
    if !has_kind || !is_text(kind, "FeatureCollection") || !has_listed { ret (zero, Invalid) }
    let (features, is_features) = items(listed)
    if !is_features { ret (zero, Invalid) }
    var counting: Map = zero
    let (counts, count_error) = walk(features, key, &counting, false)
    if count_error != ok { ret (zero, count_error) }
    if counts.regions == 0usize { ret (zero, ok) }
    let (regions, regions_error) = mem.alloc[chart.MapRegion](a, counts.regions)
    if regions_error != ok { ret (zero, regions_error) }
    let (rings, rings_error) = mem.alloc[chart.MapRing](a, counts.rings)
    if rings_error != ok { ret (zero, rings_error) }
    let (vertices, vertices_error) = mem.alloc[chart.MapVertex](a, counts.vertices)
    if vertices_error != ok { ret (zero, vertices_error) }
    var m = Map { regions: regions, rings: rings, vertices: vertices }
    let (_, fill_error) = walk(features, key, &m, true)
    if fill_error != ok { ret (zero, fill_error) }
    ret (m, ok)
}
