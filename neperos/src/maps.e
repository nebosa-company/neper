// Maps (D2225): the app behind the Maps icon, after Google Maps -- a drawn map of a small sample city
// (roads, blocks, a park, a lake), your position, six places with pins, zoom in and out, arrows that move
// the view, a button that returns to you, a search pill that lists the places, a card for the place chosen
// (distance and the time to walk) with Directions (a route along the roads and its time) and Start (a
// first instruction). Light map on a dark frame, cream cards and amber, like the other apps (appkit.e,
// taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
// ponytail: the map is SAMPLE data -- a procedural city of 25 blocks, six made-up places, you at a fixed
// spot -- because there is no map data, no GPS and no network. Real tiles or vector map data, location,
// search, routing and navigation are queued as C130.
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use e.data.graph as graph
use e.algo.graph as algo
use e.fmt.mvt as mvt
use e.fmt.json as json
use e.math
use httpc
use sensorclient
use vaultfs
use appkit
use text
use ui

const NONE: usize = 99usize
const PLACES: usize = 6usize
// (C160) The searched place stands as the place after the six; the screens; at most six tiles are kept at the level.
const TARGET: usize = 6usize
const MAP_SCREEN: usize = 0usize
const SEARCH_SCREEN: usize = 1usize
const TILE_SLOTS: usize = 6usize
const FOUND_MAX: usize = 5usize
const ROUTE_POINTS: usize = 48usize
const STEP_MAX: usize = 4usize
// The map: 1100 units square; roads every 180 units from 100, 14 wide.
fn road_at() -> f32 {
    ret 100.0
}


// (C130) The road network is a 6 x 6 grid of crossings, a block of 150 m between neighbours, with two segments
// closed ("road works") so the way is not simply an L. Routes are the shortest path over that graph (the
// library's Dijkstra); the places stand on crossings.
const GRID: usize = 6usize

type Cost = struct { unused: u8 }

fn cost_of(ctx: *Cost, e: graph.Edge[i64]) -> f64 { ret f64(e.value) }

// The crossing of grid column `col` and row `row`.
fn node_id(col: usize, row: usize) -> u32 { ret u32(row * GRID + col) }

// Is the road between neighbouring crossings `p` and `q` closed? West of you and north of you.
fn closed(p: u32, q: u32) -> bool {
    var lo = p
    var hi = q
    if q < p {
        lo = q
        hi = p
    }
    if lo == node_id(1usize, 2usize) && hi == node_id(2usize, 2usize) { ret true }
    if lo == node_id(2usize, 1usize) && hi == node_id(2usize, 2usize) { ret true }
    ret false
}

type State = struct {
    // The planned route: the crossings it passes (as map positions), their count, its length in metres.
    route_x: [24]f32,
    route_y: [24]f32,
    route_n: usize,
    route_m: usize,
    cx: f32,
    cy: f32,
    zoom: usize,
    selected: usize,
    route: bool,
    sheet: bool,
    started: bool,
    // (C160) The tiles of the pyramid level in view (OpenStreetMap data as OpenFreeMap serves it): up to six, the map
    // being `lz`, the tile in the middle of the view `ct_x`, `ct_y` and `cx`, `cy` the position in it (0 to 1100); the
    // first tile in the view makes `tile_ok`, and `tile_tried` is set once a first load has been tried.
    tile_tried: bool,
    tile_ok: bool,
    lz: usize,
    ct_x: usize,
    ct_y: usize,
    tiles: [6]Tile,
    // (C160) Keeping tiles in Files (/Maps): what `save_area` has written, and the tiles read from there.
    saved_tiles: usize,
    // (C160) Where you are (the location service's fix, else the middle of the first tile), and the place found by
    // search (its name, position, and the places the last search listed).
    me_lat: f64,
    me_lon: f64,
    has_fix: bool,
    target_lat: f64,
    target_lon: f64,
    target_name: [32]u8,
    target_len: usize,
    screen: usize,
    query: ui.Field,
    found_total: usize,
    found_name: [5][32]u8,
    found_len: [5]usize,
    found_lat: [5]f64,
    found_lon: [5]f64,
    // (C160) The route the routing service answered: its points (latitude, longitude), length in metres, time in
    // seconds and the first manoeuvres as text; `net_route` says it is that one and not the sample city's.
    net_route: bool,
    // The way of travelling the route is asked for: 0 on foot, 1 by bicycle, 2 by car (the routing service's profile).
    profile: usize,
    route_lat: [48]f64,
    route_lon: [48]f64,
    net_points: usize,
    net_metres: usize,
    net_seconds: usize,
    step_text: [4][48]u8,
    step_len: [4]usize,
    step_total: usize,
    hits: ui.Hits,
}

// (C160) One vector tile: where it is in the pyramid, its lines as points in the tile's 1100 units, where each line
// starts and what it is (0 a street, 1 a main road, 2 water), and up to eight names of its points.
type Tile = struct {
    z: usize,
    x: usize,
    y: usize,
    have: bool,
    tried: bool,
    px: [384]f32,
    py: [384]f32,
    points: usize,
    start: [48]usize,
    kind: [48]u8,
    lines: usize,
    label_text: [160]u8,
    label_len: [8]usize,
    label_x: [8]f32,
    label_y: [8]f32,
    labels: usize,
}

fn place_name(index: usize) -> str {
    if index == 0usize { ret "City Library" }
    if index == 1usize { ret "Harbour Cafe" }
    if index == 2usize { ret "Central Station" }
    if index == 3usize { ret "Neper Bank" }
    if index == 4usize { ret "Riverside Park" }
    ret "Home"
}

fn place_kind(index: usize) -> str {
    if index == 0usize { ret "Library" }
    if index == 1usize { ret "Cafe" }
    if index == 2usize { ret "Train station" }
    if index == 3usize { ret "Bank" }
    if index == 4usize { ret "Park" }
    ret "Your home"
}

// The place's position on the map: always on a crossing of two roads.
fn place_x(index: usize) -> f32 {
    if index == 0usize { ret 280.0 }
    if index == 1usize { ret 820.0 }
    if index == 2usize { ret 460.0 }
    if index == 3usize { ret 640.0 }
    if index == 4usize { ret 280.0 }
    ret 100.0
}

fn place_y(index: usize) -> f32 {
    if index == 0usize { ret 100.0 }
    if index == 1usize { ret 460.0 }
    if index == 2usize { ret 820.0 }
    if index == 3usize { ret 280.0 }
    if index == 4usize { ret 640.0 }
    ret 820.0
}

fn me_x() -> f32 {
    ret 460.0
}

fn me_y() -> f32 {
    ret 460.0
}

// The crossing nearest a map position.
fn node_at(x: f32, y: f32) -> u32 {
    let col = usize((x - 100.0) / 180.0 + 0.5)
    let row = usize((y - 100.0) / 180.0 + 0.5)
    ret node_id(col, row)
}

// Plan the way from you to place `index`: false when there is none.
fn plan_route(a: *mem.Arena, s: *State, index: usize) -> bool {
    s.route_n = 0usize
    s.route_m = 0usize
    let (b0, b_error) = graph.builder[i64](a, GRID * GRID, GRID * GRID * 4usize)
    if b_error != ok { ret false }
    var b = b0
    var row = 0usize
    while row < GRID {
        var col = 0usize
        while col < GRID {
            let here = node_id(col, row)
            if col + 1usize < GRID && !closed(here, node_id(col + 1usize, row)) {
                if graph.add_undirected[i64](&b, here, node_id(col + 1usize, row), 150i64) != ok { ret false }
            }
            if row + 1usize < GRID && !closed(here, node_id(col, row + 1usize)) {
                if graph.add_undirected[i64](&b, here, node_id(col, row + 1usize), 150i64) != ok { ret false }
            }
            col += 1usize
        }
        row += 1usize
    }
    let (g, g_error) = graph.finish[i64](a, &b)
    if g_error != ok { ret false }
    var cost = Cost { unused: 0u8 }
    let start = node_at(me_x(), me_y())
    let goal = node_at(place_x(index), place_y(index))
    let (paths, paths_error) = algo.dijkstra[i64, Cost](a, &g, start, &cost, cost_of)
    if paths_error != ok { ret false }
    if usize(goal) >= paths.previous.len { ret false }
    // Back from the goal along the previous crossings, then forwards into the route.
    var chain: [36]u32 = zero
    var count = 0usize
    var at = goal
    while at != start && count < 35usize {
        chain[count] = at
        count += 1usize
        let before = paths.previous[usize(at)]
        if before == graph.NONE { ret false }
        at = before
    }
    chain[count] = start
    count += 1usize
    if count > 24usize { ret false }
    var i = 0usize
    while i < count {
        let node = usize(chain[count - 1usize - i])
        s.route_x[i] = 100.0 + f32(node % GRID) * 180.0
        s.route_y[i] = 100.0 + f32(node / GRID) * 180.0
        i += 1usize
    }
    s.route_n = count
    s.route_m = (count - 1usize) * 150usize
    ret true
}

fn abs(v: f32) -> f32 {
    if v < 0.0 { ret 0.0 - v }
    ret v
}

// The distance along the roads from you to a place, in metres (a block is 150 m): the planned route's when
// there is one, else as the crow flies over the blocks.
fn metres_for(s: *State, index: usize) -> usize {
    if s.route_n > 0usize && s.selected == index { ret s.route_m }
    ret usize((abs(place_x(index) - me_x()) + abs(place_y(index) - me_y())) * 150.0 / 180.0)
}

fn minutes_for(s: *State, index: usize) -> usize {
    let m = metres_for(s, index) / 80usize
    if m < 1usize { ret 1usize }
    ret m
}

fn distance_text(a: *mem.Arena, s: *State, index: usize) -> str {
    let m = metres_for(s, index)
    if m < 1000usize { ret ui.join(a, ui.number(a, m), " m", "") }
    ret ui.join(a, ui.join(a, ui.number(a, m / 1000usize), ".", ui.number(a, (m % 1000usize) / 100usize)), " km", "")
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn scale(s: *State) -> f32 {
    ret 0.4 * f32(s.zoom)
}

// Screen x and y of a map point.
fn sx(s: *State, x: f32) -> f32 {
    ret 206.0 + (x - s.cx) * scale(s)
}

fn sy(s: *State, y: f32) -> f32 {
    ret 455.0 + (y - s.cy) * scale(s)
}

fn plus_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M12 5v14M5 12h14' fill='none' stroke='currentColor' stroke-width='2.8' stroke-linecap='round'/></svg>"
}

fn minus_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M5 12h14' fill='none' stroke='currentColor' stroke-width='2.8' stroke-linecap='round'/></svg>"
}

fn arrow_icon(direction: usize) -> str {
    if direction == 0usize { ret "<svg viewBox='0 0 24 24'><path d='M6 15l6-6 6 6' fill='none' stroke='currentColor' stroke-width='2.8' stroke-linecap='round' stroke-linejoin='round'/></svg>" }
    if direction == 1usize { ret "<svg viewBox='0 0 24 24'><path d='M6 9l6 6 6-6' fill='none' stroke='currentColor' stroke-width='2.8' stroke-linecap='round' stroke-linejoin='round'/></svg>" }
    if direction == 2usize { ret "<svg viewBox='0 0 24 24'><path d='M15 6l-6 6 6 6' fill='none' stroke='currentColor' stroke-width='2.8' stroke-linecap='round' stroke-linejoin='round'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M9 6l6 6-6 6' fill='none' stroke='currentColor' stroke-width='2.8' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn target_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><circle cx='12' cy='12' r='4' fill='currentColor'/><path d='M12 2v4M12 18v4M2 12h4M18 12h4' fill='none' stroke='currentColor' stroke-width='2.2' stroke-linecap='round'/><circle cx='12' cy='12' r='8' fill='none' stroke='currentColor' stroke-width='2'/></svg>"
}

// (C160) The value of tag `name` of a feature as text ("" when it has none or it is not a string).
fn tag_text(layer: mvt.Layer, feature: mvt.Feature, name: str) -> str {
    var t = 0usize
    while t + 1usize < feature.tags.len {
        let key_index = usize(feature.tags[t])
        let value_index = usize(feature.tags[t + 1usize])
        if key_index < layer.keys.len && value_index < layer.values.len && ui.same(layer.keys[key_index], name) {
            if layer.values[value_index].kind == mvt.VALUE_STRING { ret layer.values[value_index].text }
        }
        t += 2usize
    }
    ret ""
}

fn main_road(class_name: str) -> bool {
    ret ui.same(class_name, "motorway") || ui.same(class_name, "trunk") || ui.same(class_name, "primary") || ui.same(class_name, "secondary")
}

// ----------------------------------------------------------------------------------------------
// (C160) The tile pyramid. The map is a level `lz` of the Web Mercator pyramid (13 to 15); a tile is 1100 map units
// across and the view is a position (`cx`, `cy`) in the tile `ct_x`, `ct_y`. Latitude and longitude convert with the
// standard formulas.

fn pi() -> f64 {
    ret 3.141592653589793f64
}

fn pow2(n: usize) -> f64 {
    var v = 1.0f64
    var i = 0usize
    while i < n {
        v = v * 2.0f64
        i += 1usize
    }
    ret v
}

fn world_x(lon: f64, lz: usize) -> f64 {
    ret (lon + 180.0f64) / 360.0f64 * pow2(lz)
}

fn world_y(lat: f64, lz: usize) -> f64 {
    let r = lat * pi() / 180.0f64
    let m = math.log[f64](math.tan[f64](r) + 1.0f64 / math.cos[f64](r))
    ret (1.0f64 - m / pi()) / 2.0f64 * pow2(lz)
}

fn lon_of(x: f64, lz: usize) -> f64 {
    ret x / pow2(lz) * 360.0f64 - 180.0f64
}

fn lat_of(y: f64, lz: usize) -> f64 {
    let n = pi() * (1.0f64 - 2.0f64 * y / pow2(lz))
    let sinh = (math.exp[f64](n) - math.exp[f64](0.0f64 - n)) / 2.0f64
    ret math.atan[f64](sinh) * 180.0f64 / pi()
}

// Map units, from the origin of the tile in the middle of the view, of a latitude and a longitude.
fn ll_x(s: *State, lon: f64) -> f32 {
    ret f32((world_x(lon, s.lz) - f64(s.ct_x)) * 1100.0f64)
}

fn ll_y(s: *State, lat: f64) -> f32 {
    ret f32((world_y(lat, s.lz) - f64(s.ct_y)) * 1100.0f64)
}

// Put the middle of the view on a latitude and a longitude.
fn center_on(s: *State, lat: f64, lon: f64) {
    let wx = world_x(lon, s.lz)
    let wy = world_y(lat, s.lz)
    s.ct_x = usize(wx)
    s.ct_y = usize(wy)
    s.cx = f32((wx - f64(s.ct_x)) * 1100.0f64)
    s.cy = f32((wy - f64(s.ct_y)) * 1100.0f64)
}

fn floor_i(v: f32) -> i64 {
    var t = i64(v)
    if f32(t) > v { t -= 1i64 }
    ret t
}

// The tiles of the level the view needs, the middle one first.
type Want = struct { x: [6]usize, y: [6]usize, n: usize }

fn add_want(w: *Want, s: *State, dx: i64, dy: i64) {
    let tx = i64(s.ct_x) + dx
    let ty = i64(s.ct_y) + dy
    if tx < 0i64 || ty < 0i64 || w.n >= 6usize { ret }
    w.x[w.n] = usize(tx)
    w.y[w.n] = usize(ty)
    w.n += 1usize
}

fn want_tiles(s: *State) -> Want {
    var w: Want = zero
    let k = scale(s)
    let x_lo = floor_i((s.cx - 206.0 / k) / 1100.0)
    let x_hi = floor_i((s.cx + 206.0 / k) / 1100.0)
    let y_lo = floor_i((s.cy - 371.0 / k) / 1100.0)
    let y_hi = floor_i((s.cy + 371.0 / k) / 1100.0)
    add_want(&w, s, 0i64, 0i64)
    var dy = y_lo
    while dy <= y_hi {
        var dx = x_lo
        while dx <= x_hi {
            if dx != 0i64 || dy != 0i64 { add_want(&w, s, dx, dy) }
            dx += 1i64
        }
        dy += 1i64
    }
    ret w
}

fn is_wanted(s: *State, w: *Want, z: usize, x: usize, y: usize) -> bool {
    if z != s.lz { ret false }
    var i = 0usize
    while i < w.n {
        if w.x[i] == x && w.y[i] == y { ret true }
        i += 1usize
    }
    ret false
}

// The slot holding tile x, y of the level (loaded or tried), else a free or unwanted one (emptied), else NONE.
fn slot_for(s: *State, w: *Want, x: usize, y: usize) -> usize {
    var i = 0usize
    while i < TILE_SLOTS {
        let t = &s.tiles[i]
        if (t.have || t.tried) && t.z == s.lz && t.x == x && t.y == y { ret i }
        i += 1usize
    }
    i = 0usize
    while i < TILE_SLOTS {
        let t = &s.tiles[i]
        if !t.have && !t.tried { ret i }
        i += 1usize
    }
    i = 0usize
    while i < TILE_SLOTS {
        let t = &s.tiles[i]
        if !is_wanted(s, w, t.z, t.x, t.y) {
            t.have = false
            t.tried = false
            ret i
        }
        i += 1usize
    }
    ret NONE
}

fn tile_path(a: *mem.Arena, z: usize, x: usize, y: usize) -> str {
    ret ui.join(a, ui.join(a, ui.join(a, "/Maps/", ui.number(a, z), "-"), ui.number(a, x), "-"), ui.number(a, y), ".pbf")
}

// The bytes of tile z/x/y: from /Maps when it is kept there (and `force` is not set), else over HTTPS from the tile
// server (and written to /Maps when `keep`). The bytes live in the arena; the third result says they came from Files.
fn tile_bytes(a: *mem.Arena, z: usize, x: usize, y: usize, keep: bool, force: bool) -> (str, bool, bool) {
    let file = tile_path(a, z, x, y)
    if !force {
        let (size, kind_of, extra, found) = vaultfs.stat(file)
        if found && size > 0usize && size <= 98304usize {
            let (room, room_error) = mem.alloc[u8](a, size)
            if room_error == ok {
                let (got, read_ok) = vaultfs.read_big(file, mem.address_of(&room[0usize]), size)
                if read_ok && got == size { ret (room[0usize..got], true, true) }
            }
        }
    }
    let url_path = ui.join(a, ui.join(a, ui.join(a, "/planet/latest/", ui.number(a, z), "/"), ui.number(a, x), "/"), ui.number(a, y), ".pbf")
    let (reply, get_error) = httpc.get(a, "tiles.openfreemap.org", url_path, "")
    if get_error != ok || reply.status != 200usize || reply.body.len == 0usize { ret ("", false, false) }
    if keep {
        let made = vaultfs.mkdir("/Maps")
        let written = vaultfs.write_big(file, mem.address_of(&reply.body[0usize]), reply.body.len)
    }
    ret (reply.body, true, false)
}

// Decode a vector tile into `t`: the `transportation` and `water` lines (a main road, a street, water) and the names
// of the `poi` and `place` points, scaled to the tile's 1100 units. false when it does not read or has no lines.
fn decode_tile(a: *mem.Arena, t: *Tile, raw: str) -> bool {
    let (layers, parse_error) = mvt.parse(a, raw)
    if parse_error != ok { ret false }
    t.points = 0usize
    t.lines = 0usize
    t.labels = 0usize
    var label_at = 0usize
    var l = 0usize
    while l < layers.len {
        let layer = layers[l]
        let is_road = ui.same(layer.name, "transportation")
        let is_water = ui.same(layer.name, "water")
        let is_named = ui.same(layer.name, "poi") || ui.same(layer.name, "place")
        var extent: f32 = 4096.0
        if layer.extent > 0u32 { extent = f32(layer.extent) }
        var f = 0usize
        while f < layer.features.len {
            let feature = layer.features[f]
            if (is_road || is_water) && feature.kind != mvt.KIND_POINT {
                var kind = 0u8
                if is_water { kind = 2u8 }
                if is_road && main_road(tag_text(layer, feature, "class")) { kind = 1u8 }
                var p = 0usize
                var from = 0usize
                while p < feature.parts.len {
                    let to = feature.parts[p]
                    if t.lines < 48usize && to > from && t.points + (to - from) <= 384usize {
                        t.start[t.lines] = t.points
                        t.kind[t.lines] = kind
                        t.lines += 1usize
                        var q = from
                        while q < to {
                            t.px[t.points] = f32(feature.points[q].x) * 1100.0 / extent
                            t.py[t.points] = f32(feature.points[q].y) * 1100.0 / extent
                            t.points += 1usize
                            q += 1usize
                        }
                    }
                    from = to
                    p += 1usize
                }
            }
            if is_named && feature.kind == mvt.KIND_POINT && feature.points.len > 0usize && t.labels < 8usize {
                let name = tag_text(layer, feature, "name")
                if name.len > 0usize && label_at + 20usize <= 160usize {
                    var n = 0usize
                    while n < name.len && n < 20usize {
                        t.label_text[label_at + n] = name[n]
                        n += 1usize
                    }
                    t.label_len[t.labels] = n
                    t.label_x[t.labels] = f32(feature.points[0usize].x) * 1100.0 / extent
                    t.label_y[t.labels] = f32(feature.points[0usize].y) * 1100.0 / extent
                    t.labels += 1usize
                    label_at += 20usize
                }
            }
            f += 1usize
        }
        l += 1usize
    }
    ui.say("maps tile ")
    ui.say_num(layers.len)
    ui.say(" layers ")
    ui.say_num(t.lines)
    ui.say(" lines ")
    ui.say_num(t.labels)
    ui.say(" names\n")
    ret t.lines > 0usize
}

// Load the first tile of the view that is not loaded yet (the middle one first): true when a tile came in.
fn fill_tiles(a: *mem.Arena, s: *State) -> bool {
    let w = want_tiles(s)
    var i = 0usize
    while i < w.n {
        var wanted = w
        let slot = slot_for(s, &wanted, w.x[i], w.y[i])
        if slot != NONE && !s.tiles[slot].have && !s.tiles[slot].tried {
            let mark = mem.mark(a)
            let t = &s.tiles[slot]
            t.z = s.lz
            t.x = w.x[i]
            t.y = w.y[i]
            t.tried = true
            let (raw, fetched, from_files) = tile_bytes(a, s.lz, t.x, t.y, false, false)
            var good = false
            if fetched {
                ui.say("maps tile ")
                ui.say_num(s.lz)
                ui.say("/")
                ui.say_num(t.x)
                ui.say("/")
                ui.say_num(t.y)
                if from_files { ui.say(" files\n") } else { ui.say(" network\n") }
                good = decode_tile(a, t, raw)
            }
            mem.reset(a, mark)
            t.have = good
            if good { s.tile_ok = true }
            ret good
        }
        i += 1usize
    }
    ret false
}

// (C160) Keep the tiles of the view in Files (/Maps), fetched from the server: how many were written.
fn save_area(a: *mem.Arena, s: *State) -> usize {
    let w = want_tiles(s)
    var kept = 0usize
    var i = 0usize
    while i < w.n {
        let mark = mem.mark(a)
        let (raw, fetched, from_files) = tile_bytes(a, s.lz, w.x[i], w.y[i], true, true)
        if fetched { kept += 1usize }
        mem.reset(a, mark)
        i += 1usize
    }
    ui.say("maps area saved ")
    ui.say_num(kept)
    ui.say(" tiles\n")
    s.saved_tiles = kept
    ret kept
}

// (C160) The tiles of the level in view as the map: water and roads as strokes, the names of their points as labels,
// the ODbL line; then you, the place found and the route the routing service gave.
fn draw_tiles(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var slot = 0usize
    while slot < TILE_SLOTS {
        let t = &s.tiles[slot]
        if t.have && t.z == s.lz {
            let ox: f32 = (f32(t.x) - f32(s.ct_x)) * 1100.0
            let oy: f32 = (f32(t.y) - f32(s.ct_y)) * 1100.0
            var line = 0usize
            while line < t.lines {
                let from = t.start[line]
                var to = t.points
                if line + 1usize < t.lines { to = t.start[line + 1usize] }
                var xs: [32]f32 = zero
                var ys: [32]f32 = zero
                var n = 0usize
                while from + n < to && n < 32usize {
                    xs[n] = sx(s, ox + t.px[from + n])
                    ys[n] = sy(s, oy + t.py[from + n])
                    n += 1usize
                }
                var width: f32 = 4.0 * scale(s)
                var colour = paint.Color { red: 0.78, green: 0.76, blue: 0.70, alpha: 1.0 }
                if t.kind[line] == 1u8 {
                    width = 8.0 * scale(s)
                    colour = paint.Color { red: 0.95, green: 0.72, blue: 0.30, alpha: 1.0 }
                }
                if t.kind[line] == 2u8 {
                    width = 3.0 * scale(s)
                    colour = paint.Color { red: 0.50, green: 0.70, blue: 0.88, alpha: 1.0 }
                }
                try ui.polyline(a, builder, xs[0usize..n], ys[0usize..n], n, width, colour)
                line += 1usize
            }
            var label = 0usize
            while label < t.labels {
                let px = sx(s, ox + t.label_x[label])
                let py = sy(s, oy + t.label_y[label])
                let name = ui.text_of(a, t.label_text[label * 20usize..], t.label_len[label])
                let w = text.measure(a, faces.jost, 13.0, name)
                try ui.disc(a, builder, px, py, 5.0, ui.amber_dark())
                try ui.card(a, builder, px - w / 2.0 - 8.0, py + 8.0, w + 16.0, 22.0, 11.0, ui.cream())
                try ui.centred(a, builder, faces.jost, 13.0, name, px, py + 11.0, ui.ink())
                label += 1usize
            }
        }
        slot += 1usize
    }
    // The route from the routing service.
    if s.net_route && s.net_points > 1usize {
        var xs: [48]f32 = zero
        var ys: [48]f32 = zero
        var r = 0usize
        while r < s.net_points {
            xs[r] = sx(s, ll_x(s, s.route_lon[r]))
            ys[r] = sy(s, ll_y(s, s.route_lat[r]))
            r += 1usize
        }
        try ui.polyline(a, builder, xs[0usize..s.net_points], ys[0usize..s.net_points], s.net_points, 7.0, paint.Color { red: 0.20, green: 0.45, blue: 0.85, alpha: 1.0 })
    }
    // The place found, and you.
    if s.target_len > 0usize {
        let tx = sx(s, ll_x(s, s.target_lon))
        let ty = sy(s, ll_y(s, s.target_lat))
        try ui.disc(a, builder, tx, ty, 13.0, ui.cream())
        try ui.disc(a, builder, tx, ty, 10.0, paint.Color { red: 0.85, green: 0.25, blue: 0.22, alpha: 1.0 })
    }
    let mx = sx(s, ll_x(s, s.me_lon))
    let my = sy(s, ll_y(s, s.me_lat))
    try ui.disc(a, builder, mx, my, 16.0, paint.Color { red: 0.20, green: 0.45, blue: 0.85, alpha: 0.25 })
    try ui.disc(a, builder, mx, my, 9.0, ui.cream())
    try ui.disc(a, builder, mx, my, 6.5, paint.Color { red: 0.20, green: 0.45, blue: 0.85, alpha: 1.0 })
    try ui.put(a, builder, faces.grotesk, 11.0, "Map data OpenStreetMap contributors (ODbL)", 12.0, 804.0, ui.muted())
    ui.say("maps tile drawn\n")
    ret ok
}

// ----------------------------------------------------------------------------------------------
// (C160) Search (a Nominatim-shaped JSON array) and routing (an OSRM-shaped route).

// A decimal number in text ("59.9127", "-122.33"): its value, false when it is not one.
fn decimal(text_in: str) -> (f64, bool) {
    var i = 0usize
    var negative = false
    if i < text_in.len && (text_in[i] == 45u8 || text_in[i] == 43u8) {
        negative = text_in[i] == 45u8
        i += 1usize
    }
    var value = 0.0f64
    var digits = 0usize
    while i < text_in.len && text_in[i] >= 48u8 && text_in[i] <= 57u8 {
        value = value * 10.0f64 + f64(text_in[i] - 48u8)
        digits += 1usize
        i += 1usize
    }
    if i < text_in.len && text_in[i] == 46u8 {
        i += 1usize
        var scale_down = 0.1f64
        while i < text_in.len && text_in[i] >= 48u8 && text_in[i] <= 57u8 {
            value = value + f64(text_in[i] - 48u8) * scale_down
            scale_down = scale_down / 10.0f64
            digits += 1usize
            i += 1usize
        }
    }
    if digits == 0usize { ret (0.0f64, false) }
    if negative { value = 0.0f64 - value }
    ret (value, true)
}

// A coordinate as text with five decimals ("-122.33210").
fn degrees_text(a: *mem.Arena, v: f64) -> str {
    var value = v
    var sign = ""
    if value < 0.0f64 {
        sign = "-"
        value = 0.0f64 - value
    }
    let scaled = usize(value * 100000.0f64 + 0.5f64)
    let whole = scaled / 100000usize
    let fraction = scaled % 100000usize
    var pad = ""
    if fraction < 10usize { pad = "0000" } else if fraction < 100usize { pad = "000" } else if fraction < 1000usize { pad = "00" } else if fraction < 10000usize { pad = "0" }
    ret ui.join(a, ui.join(a, sign, ui.number(a, whole), "."), pad, ui.number(a, fraction))
}

fn url_encoded(a: *mem.Arena, source: str) -> str {
    let (out, out_error) = mem.alloc[u8](a, source.len * 3usize + 1usize)
    if out_error != ok { ret "" }
    var n = 0usize
    var i = 0usize
    while i < source.len {
        let c = source[i]
        if (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) {
            out[n] = c
            n += 1usize
        } else {
            out[n] = 37u8
            let hi = usize(c >> 4u8)
            let lo = usize(c & 15u8)
            var hi_char = 48usize + hi
            if hi > 9usize { hi_char = 55usize + hi }
            var lo_char = 48usize + lo
            if lo > 9usize { lo_char = 55usize + lo }
            out[n + 1usize] = u8(hi_char)
            out[n + 2usize] = u8(lo_char)
            n += 3usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn member_of(members: []const json.Member, key: str) -> (json.Value, bool) {
    var i = 0usize
    while i < members.len {
        if ui.same(members[i].key, key) { ret (members[i].value, true) }
        i += 1usize
    }
    var none: json.Value = zero
    ret (none, false)
}

fn text_member(members: []const json.Member, key: str) -> (str, bool) {
    let (v, found) = member_of(members, key)
    if !found { ret ("", false) }
    switch v {
    case .String as t:
        ret (t, true)
    default:
        ret ("", false)
    }
}

fn number_value(v: json.Value) -> (f64, bool) {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e != ok { ret (0.0f64, false) }
        ret (x, true)
    case .String as t:
        let (parsed_value, parsed_ok) = decimal(t)
        ret (parsed_value, parsed_ok)
    default:
        ret (0.0f64, false)
    }
}

// Search the map for the typed words (https://nominatim.openstreetmap.org/search, JSON): up to five places with their
// names and positions in `found_*`. false when there is no answer.
fn search_map(a: *mem.Arena, s: *State) -> bool {
    s.found_total = 0usize
    let words = ui.field_text(a, &s.query)
    if words.len == 0usize { ret false }
    let mark = mem.mark(a)
    let path = ui.join(a, "/search?format=jsonv2&limit=5&q=", url_encoded(a, words), "")
    let (reply, get_error) = httpc.get(a, "nominatim.openstreetmap.org", path, "")
    if get_error != ok || reply.status != 200usize {
        mem.reset(a, mark)
        ret false
    }
    let (parsed, parse_error) = json.parse(a, reply.body, json.Options { allow_duplicate_keys: false, max_depth: 8u16 })
    if parse_error != ok {
        mem.reset(a, mark)
        ret false
    }
    switch parsed {
    case .Array as items:
        var i = 0usize
        while i < items.len && s.found_total < FOUND_MAX {
            switch items[i] {
            case .Object as fields:
                let (name, has_name) = text_member(fields, "display_name")
                let (lat_value, has_lat) = member_of(fields, "lat")
                let (lon_value, has_lon) = member_of(fields, "lon")
                if has_name && has_lat && has_lon {
                    let (lat, lat_ok) = number_value(lat_value)
                    let (lon, lon_ok) = number_value(lon_value)
                    if lat_ok && lon_ok {
                        let at = s.found_total
                        var n = 0usize
                        while n < name.len && n < 32usize {
                            s.found_name[at][n] = name[n]
                            n += 1usize
                        }
                        s.found_len[at] = n
                        s.found_lat[at] = lat
                        s.found_lon[at] = lon
                        s.found_total += 1usize
                    }
                }
            default:
                s.found_total = s.found_total
            }
            i += 1usize
        }
    default:
        s.found_total = 0usize
    }
    mem.reset(a, mark)
    ui.say("maps search ")
    ui.say_text(words)
    ui.say(" ")
    ui.say_num(s.found_total)
    ui.say(" results\n")
    ret true
}

fn step_words(a: *mem.Arena, kind: str, modifier: str, road: str, metres: usize) -> str {
    var head = ""
    if ui.same(kind, "depart") {
        head = "Head on "
        if road.len == 0usize { head = "Head off" }
    } else if ui.same(kind, "arrive") {
        head = "Arrive at the destination"
    } else if ui.same(kind, "turn") || ui.same(kind, "end of road") || ui.same(kind, "fork") {
        head = ui.join(a, "Turn ", modifier, " onto ")
    } else {
        head = "Continue on "
    }
    var line = head
    if !ui.same(kind, "arrive") { line = ui.join(a, head, road, "") }
    ret ui.join(a, line, ", ", ui.join(a, ui.number(a, metres), " m", ""))
}

// The route from you to the place found (https://router.project-osrm.org/route/v1/foot/..., geojson geometry with
// steps): its length, time, points and the first manoeuvres in the state. false when there is no route.
fn route_map(a: *mem.Arena, s: *State) -> bool {
    s.net_route = false
    s.net_points = 0usize
    s.step_total = 0usize
    let mark = mem.mark(a)
    var profile = "foot"
    if s.profile == 1usize { profile = "bike" }
    if s.profile == 2usize { profile = "car" }
    var path = ui.join(a, ui.join(a, "/route/v1/", profile, "/"), degrees_text(a, s.me_lon), ",")
    path = ui.join(a, path, degrees_text(a, s.me_lat), ";")
    path = ui.join(a, path, degrees_text(a, s.target_lon), ",")
    path = ui.join(a, path, degrees_text(a, s.target_lat), "?overview=full&geometries=geojson&steps=true")
    let (reply, get_error) = httpc.get(a, "router.project-osrm.org", path, "")
    if get_error != ok || reply.status != 200usize {
        mem.reset(a, mark)
        ret false
    }
    let (parsed, parse_error) = json.parse(a, reply.body, json.Options { allow_duplicate_keys: false, max_depth: 10u16 })
    if parse_error != ok {
        mem.reset(a, mark)
        ret false
    }
    var good = false
    switch parsed {
    case .Object as top:
        let (code, has_code) = text_member(top, "code")
        let (routes_value, has_routes) = member_of(top, "routes")
        if has_code && ui.same(code, "Ok") && has_routes {
            switch routes_value {
            case .Array as routes:
                if routes.len > 0usize {
                    switch routes[0usize] {
                    case .Object as route:
                        let (distance_value, has_distance) = member_of(route, "distance")
                        let (duration_value, has_duration) = member_of(route, "duration")
                        let (metres, metres_ok) = number_value(distance_value)
                        let (seconds, seconds_ok) = number_value(duration_value)
                        if has_distance && has_duration && metres_ok && seconds_ok {
                            s.net_metres = usize(metres + 0.5f64)
                            s.net_seconds = usize(seconds + 0.5f64)
                            let (geometry_value, has_geometry) = member_of(route, "geometry")
                            if has_geometry {
                                switch geometry_value {
                                case .Object as geometry_members:
                                    let (coords_value, has_coords) = member_of(geometry_members, "coordinates")
                                    if has_coords {
                                        switch coords_value {
                                        case .Array as coords:
                                            var c = 0usize
                                            while c < coords.len && s.net_points < ROUTE_POINTS {
                                                switch coords[c] {
                                                case .Array as pair:
                                                    if pair.len >= 2usize {
                                                        let (lon, lon_ok) = number_value(pair[0usize])
                                                        let (lat, lat_ok) = number_value(pair[1usize])
                                                        if lon_ok && lat_ok {
                                                            s.route_lon[s.net_points] = lon
                                                            s.route_lat[s.net_points] = lat
                                                            s.net_points += 1usize
                                                        }
                                                    }
                                                default:
                                                    s.net_points = s.net_points
                                                }
                                                c += 1usize
                                            }
                                        default:
                                            s.net_points = s.net_points
                                        }
                                    }
                                default:
                                    s.net_points = s.net_points
                                }
                            }
                            // The steps of the first leg.
                            let (legs_value, has_legs) = member_of(route, "legs")
                            if has_legs {
                                switch legs_value {
                                case .Array as legs:
                                    if legs.len > 0usize {
                                        switch legs[0usize] {
                                        case .Object as leg:
                                            let (steps_value, has_steps) = member_of(leg, "steps")
                                            if has_steps {
                                                switch steps_value {
                                                case .Array as steps:
                                                    var k = 0usize
                                                    while k < steps.len && s.step_total < STEP_MAX {
                                                        switch steps[k] {
                                                        case .Object as step:
                                                            let (road, has_road) = text_member(step, "name")
                                                            let (step_distance, has_step_distance) = member_of(step, "distance")
                                                            let (step_metres, step_ok) = number_value(step_distance)
                                                            var kind = ""
                                                            var modifier = ""
                                                            let (maneuver_value, has_maneuver) = member_of(step, "maneuver")
                                                            if has_maneuver {
                                                                switch maneuver_value {
                                                                case .Object as maneuver:
                                                                    let (kind_text, has_kind) = text_member(maneuver, "type")
                                                                    let (modifier_text, has_modifier) = text_member(maneuver, "modifier")
                                                                    kind = kind_text
                                                                    modifier = modifier_text
                                                                default:
                                                                    kind = ""
                                                                }
                                                            }
                                                            let words = step_words(a, kind, modifier, road, usize(step_metres + 0.5f64))
                                                            var n = 0usize
                                                            while n < words.len && n < 48usize {
                                                                s.step_text[s.step_total][n] = words[n]
                                                                n += 1usize
                                                            }
                                                            s.step_len[s.step_total] = n
                                                            s.step_total += 1usize
                                                        default:
                                                            s.step_total = s.step_total
                                                        }
                                                        k += 1usize
                                                    }
                                                default:
                                                    s.step_total = s.step_total
                                                }
                                            }
                                        default:
                                            s.step_total = s.step_total
                                        }
                                    }
                                default:
                                    s.step_total = s.step_total
                                }
                            }
                            good = s.net_points >= 2usize
                        }
                    default:
                        good = false
                    }
                }
            default:
                good = false
            }
        }
    default:
        good = false
    }
    mem.reset(a, mark)
    if good {
        s.net_route = true
        ui.say("maps route osrm ")
        ui.say_num(s.net_metres)
        ui.say(" m ")
        ui.say_num((s.net_seconds + 30usize) / 60usize)
        ui.say(" min ")
        ui.say_num(s.step_total)
        ui.say(" steps\n")
        var p = 0usize
        while p < s.step_total {
            ui.say("maps step ")
            ui.say_num(p + 1usize)
            ui.say(" ")
            ui.say_text(ui.text_of(a, s.step_text[p][0usize..], s.step_len[p]))
            ui.say("\n")
            p += 1usize
        }
    }
    ret good
}

fn draw_map(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let save: scene.Command = .Save
    try scene.push(builder, save)
    try scene.push(builder, scene.Command { Clip: scene.Clip { Rect: geometry.rect(0.0, 84.0, 412.0, 742.0) } })
    // The ground is the road colour; blocks sit on it.
    try ui.card(a, builder, 0.0, 84.0, 412.0, 742.0, 0.0, paint.Color { red: 0.98, green: 0.97, blue: 0.94, alpha: 1.0 })
    if s.tile_ok {
        try draw_tiles(a, builder, s, faces)
        let restore_tile: scene.Command = .Restore
        try scene.push(builder, restore_tile)
        ret ok
    }
    let k = scale(s)
    var bx = 0usize
    while bx < 5usize {
        var by = 0usize
        while by < 5usize {
            let x0: f32 = road_at() + f32(bx) * 180.0 + 7.0
            let y0: f32 = road_at() + f32(by) * 180.0 + 7.0
            let w: f32 = 180.0 - 14.0
            var colour = paint.Color { red: 0.90, green: 0.88, blue: 0.82, alpha: 1.0 }
            if bx == 1usize && by == 1usize { colour = paint.Color { red: 0.74, green: 0.85, blue: 0.68, alpha: 1.0 } }
            if bx >= 3usize && by >= 3usize && !(bx == 4usize && by == 4usize) { colour = paint.Color { red: 0.66, green: 0.78, blue: 0.88, alpha: 1.0 } }
            if bx == 4usize && by == 4usize { colour = paint.Color { red: 0.66, green: 0.78, blue: 0.88, alpha: 1.0 } }
            let px = sx(s, x0)
            let py = sy(s, y0)
            if px + w * k > 0.0 && px < 412.0 && py + w * k > 84.0 && py < 826.0 {
                try ui.card(a, builder, px, py, w * k, w * k, 6.0 * k, colour)
                // A few buildings in the plain blocks.
                if colour.red > 0.85 {
                    try ui.card(a, builder, px + 14.0 * k, py + 14.0 * k, 60.0 * k, 50.0 * k, 3.0 * k, paint.Color { red: 0.84, green: 0.82, blue: 0.75, alpha: 1.0 })
                    try ui.card(a, builder, px + 90.0 * k, py + 40.0 * k, 56.0 * k, 90.0 * k, 3.0 * k, paint.Color { red: 0.84, green: 0.82, blue: 0.75, alpha: 1.0 })
                }
            }
            by += 1usize
        }
        bx += 1usize
    }
    // The route along the roads: you, then along x to the place's column, then along y.
    // The closed roads, a red bar across each.
    // (1,2)-(2,2): the segment between those crossings, and (2,1)-(2,2).
    try ui.card(a, builder, sx(s, 100.0 + 1.5 * 180.0) - 3.0 * k, sy(s, 100.0 + 2.0 * 180.0) - 9.0 * k, 6.0 * k, 18.0 * k, 2.0, paint.Color { red: 0.85, green: 0.25, blue: 0.22, alpha: 1.0 })
    try ui.card(a, builder, sx(s, 100.0 + 2.0 * 180.0) - 9.0 * k, sy(s, 100.0 + 1.5 * 180.0) - 3.0 * k, 18.0 * k, 6.0 * k, 2.0, paint.Color { red: 0.85, green: 0.25, blue: 0.22, alpha: 1.0 })
    // The route along the roads, crossing by crossing.
    if s.route && s.selected != NONE && s.route_n > 1usize {
        var xs: [24]f32 = zero
        var ys: [24]f32 = zero
        var r = 0usize
        while r < s.route_n {
            xs[r] = sx(s, s.route_x[r])
            ys[r] = sy(s, s.route_y[r])
            r += 1usize
        }
        try ui.polyline(a, builder, xs[0usize..s.route_n], ys[0usize..s.route_n], s.route_n, 7.0, paint.Color { red: 0.20, green: 0.45, blue: 0.85, alpha: 1.0 })
    }
    // The places.
    var i = 0usize
    while i < PLACES {
        let px = sx(s, place_x(i))
        let py = sy(s, place_y(i))
        if px > 0.0 && px < 412.0 && py > 90.0 && py < 820.0 {
            var fill = ui.amber_dark()
            var radius: f32 = 8.0
            if i == s.selected {
                fill = paint.Color { red: 0.85, green: 0.25, blue: 0.22, alpha: 1.0 }
                radius = 11.0
            }
            try ui.disc(a, builder, px, py, radius + 2.0, ui.cream())
            try ui.disc(a, builder, px, py, radius, fill)
            if s.zoom >= 2usize || i == s.selected {
                let label = place_name(i)
                let w = text.measure(a, faces.jost, 13.0, label)
                try ui.card(a, builder, px - w / 2.0 - 8.0, py + radius + 4.0, w + 16.0, 22.0, 11.0, ui.cream())
                try ui.centred(a, builder, faces.jost, 13.0, label, px, py + radius + 7.0, ui.ink())
            }
        }
        i += 1usize
    }
    // You.
    let mx = sx(s, me_x())
    let my = sy(s, me_y())
    try ui.disc(a, builder, mx, my, 16.0, paint.Color { red: 0.20, green: 0.45, blue: 0.85, alpha: 0.25 })
    try ui.disc(a, builder, mx, my, 9.0, ui.cream())
    try ui.disc(a, builder, mx, my, 6.5, paint.Color { red: 0.20, green: 0.45, blue: 0.85, alpha: 1.0 })
    let restore: scene.Command = .Restore
    try scene.push(builder, restore)
    ret ok
}

fn control(a: *mem.Arena, builder: *scene.Builder, s: *State, id: usize, cx: f32, cy: f32, icon: str) -> err {
    try ui.disc(a, builder, cx, cy, 22.0, paint.Color { red: 0.12, green: 0.13, blue: 0.16, alpha: 0.92 })
    try svg.draw(a, builder, icon, geometry.rect(cx - 12.0, cy - 12.0, 24.0, 24.0), ui.light())
    ui.hit(&s.hits, id, cx - 24.0, cy - 24.0, 48.0, 48.0)
    ret ok
}

fn draw_sheet(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 0.0, 84.0, 412.0, 740.0, 0.0, ui.shade(0.45))
    ui.hit(&s.hits, 600usize, 0.0, 84.0, 412.0, 336.0)
    try ui.card(a, builder, 0.0, 420.0, 412.0, 476.0, 24.0, ui.cream())
    ui.hit(&s.hits, 601usize, 0.0, 420.0, 412.0, 476.0)
    try ui.put(a, builder, faces.jost_bold, 20.0, "Places nearby", 24.0, 436.0, ui.ink())
    // (C160) Search the map itself (the typed words go to the search service).
    try ui.pill(a, builder, &s.hits, faces, 650usize, 300.0, 430.0, 96.0, 34.0, "Find", ui.amber(), 15.0)
    var i = 0usize
    while i < PLACES {
        let y: f32 = 470.0 + f32(i) * 58.0
        try ui.disc(a, builder, 46.0, y + 28.0, 18.0, ui.tint(i))
        try ui.put(a, builder, faces.jost, 18.0, place_name(i), 80.0, y + 8.0, ui.ink())
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, place_kind(i), "  ", distance_text(a, s, i)), 80.0, y + 32.0, ui.muted())
        ui.hit(&s.hits, 400usize + i, 16.0, y, 380.0, 56.0)
        i += 1usize
    }
    ret ok
}

fn draw_card(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 0.0, 664.0, 412.0, 232.0, 24.0, ui.cream())
    if s.selected == TARGET {
        // (C160) The place search found: its name and, once the routing service answered, the route's length and time
        // and its manoeuvres (the first, then the second when Start was pressed).
        try ui.clipped(a, builder, faces.jost_bold, 20.0, ui.text_of(a, s.target_name[0usize..], s.target_len), 24.0, 676.0, 364.0, ui.ink())
        var summary = "Place from search"
        var how = " min on foot"
        var mode_label = "Walk"
        if s.profile == 1usize {
            how = " min by bike"
            mode_label = "Bike"
        }
        if s.profile == 2usize {
            how = " min by car"
            mode_label = "Drive"
        }
        if s.net_route { summary = ui.join(a, ui.number(a, s.net_metres), " m, ", ui.join(a, ui.number(a, (s.net_seconds + 30usize) / 60usize), how, "")) }
        try ui.pill(a, builder, &s.hits, faces, 502usize, 316.0, 700.0, 80.0, 30.0, mode_label, ui.soft(), 14.0)
        try ui.put(a, builder, faces.grotesk, 14.0, summary, 24.0, 710.0, ui.muted())
        if s.net_route && s.step_total > 0usize {
            try ui.clipped(a, builder, faces.jost, 15.0, ui.text_of(a, s.step_text[0usize][0usize..], s.step_len[0usize]), 24.0, 736.0, 364.0, ui.amber_dark())
            if s.started && s.step_total > 1usize {
                try ui.clipped(a, builder, faces.jost, 15.0, ui.text_of(a, s.step_text[1usize][0usize..], s.step_len[1usize]), 24.0, 756.0, 364.0, ui.amber_dark())
            }
        }
    } else {
        try ui.put(a, builder, faces.jost_bold, 24.0, place_name(s.selected), 24.0, 678.0, ui.ink())
        try ui.put(a, builder, faces.grotesk, 14.0, ui.join(a, place_kind(s.selected), "  ", ui.join(a, distance_text(a, s, s.selected), ", ", ui.join(a, ui.number(a, minutes_for(s, s.selected)), " min on foot", ""))), 24.0, 712.0, ui.muted())
        if s.started {
            try ui.put(a, builder, faces.jost, 17.0, "Head along the road, then turn at the crossing", 24.0, 744.0, ui.amber_dark())
        }
    }
    var label = "Directions"
    if s.route { label = "Start" }
    try ui.pill(a, builder, &s.hits, faces, 500usize, 16.0, 780.0, 180.0, 48.0, label, ui.amber(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 501usize, 212.0, 780.0, 184.0, 48.0, "Close", ui.soft(), 17.0)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == SEARCH_SCREEN {
        // (C160) The search screen: the words, the places found, the keyboard.
        let words = ui.field_text(a, &s.query)
        try ui.put(a, builder, faces.jost_bold, 26.0, "Search the map", 24.0, 14.0, ui.light())
        try ui.card(a, builder, 14.0, 56.0, 384.0, 54.0, 27.0, ui.amber())
        try ui.card(a, builder, 16.0, 58.0, 380.0, 50.0, 25.0, ui.cream())
        try ui.clipped(a, builder, faces.jost, 18.0, words, 36.0, 71.0, 340.0, ui.ink())
        var found_at = 0usize
        while found_at < s.found_total {
            let y: f32 = 122.0 + f32(found_at) * 62.0
            try ui.card(a, builder, 16.0, y, 380.0, 54.0, 14.0, ui.cream())
            try ui.clipped(a, builder, faces.jost, 16.0, ui.text_of(a, s.found_name[found_at][0usize..], s.found_len[found_at]), 30.0, y + 16.0, 340.0, ui.ink())
            ui.hit(&s.hits, 660usize + found_at, 16.0, y, 380.0, 54.0)
            found_at += 1usize
        }
        try ui.keyboard(a, builder, &s.hits, faces, "Search")
        try ui.handle(a, builder)
        ret ok
    }
    try draw_map(a, builder, s, faces)
    // The search pill over the map, the zoom, the arrows and the way back to you.
    try ui.card(a, builder, 16.0, 22.0, 380.0, 50.0, 25.0, ui.cream())
    try ui.put(a, builder, faces.jost, 17.0, "Search here", 40.0, 35.0, ui.muted())
    ui.hit(&s.hits, 700usize, 16.0, 22.0, 380.0, 50.0)
    try control(a, builder, s, 710usize, 372.0, 280.0, plus_icon())
    try control(a, builder, s, 711usize, 372.0, 336.0, minus_icon())
    try control(a, builder, s, 712usize, 372.0, 392.0, target_icon())
    // (C160) Keep the tiles of the view in Files, for use with no network.
    try control(a, builder, s, 713usize, 372.0, 448.0, arrow_icon(1usize))
    try control(a, builder, s, 720usize, 60.0, 480.0, arrow_icon(0usize))
    try control(a, builder, s, 721usize, 60.0, 584.0, arrow_icon(1usize))
    try control(a, builder, s, 722usize, 22.0, 532.0, arrow_icon(2usize))
    try control(a, builder, s, 723usize, 98.0, 532.0, arrow_icon(3usize))
    if s.selected != NONE && !s.sheet { try draw_card(a, builder, s, faces) }
    if s.sheet { try draw_sheet(a, builder, s, faces) }
    try ui.handle(a, builder)
    ret ok
}

fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    if draw(a, &builder, kit, s) != ok { ret false }
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

fn pan(s: *State, dx: f32, dy: f32) {
    let step: f32 = 180.0 / f32(s.zoom)
    s.cx += dx * step
    s.cy += dy * step
    if s.tile_ok {
        // (C160) With tiles the view moves on into the next tile of the level.
        if s.cx >= 1100.0 {
            s.cx -= 1100.0
            s.ct_x += 1usize
        }
        if s.cx < 0.0 && s.ct_x > 0usize {
            s.cx += 1100.0
            s.ct_x -= 1usize
        }
        if s.cy >= 1100.0 {
            s.cy -= 1100.0
            s.ct_y += 1usize
        }
        if s.cy < 0.0 && s.ct_y > 0usize {
            s.cy += 1100.0
            s.ct_y -= 1usize
        }
        if s.cx < 0.0 { s.cx = 0.0 }
        if s.cy < 0.0 { s.cy = 0.0 }
        ret
    }
    if s.cx < 0.0 { s.cx = 0.0 }
    if s.cy < 0.0 { s.cy = 0.0 }
    if s.cx > 1100.0 { s.cx = 1100.0 }
    if s.cy > 1100.0 { s.cy = 1100.0 }
}

// (C160) One step in on the zoom ladder: three zooms a level, then the next level of the pyramid (the view keeps
// its place: the tile index doubles). `in_` false steps out.
fn zoom_step(s: *State, zoom_in: bool) {
    if zoom_in {
        if s.zoom < 3usize {
            s.zoom += 1usize
        } else if s.tile_ok && s.lz < 15usize {
            let wx = f64(s.ct_x) + f64(s.cx) / 1100.0f64
            let wy = f64(s.ct_y) + f64(s.cy) / 1100.0f64
            s.lz += 1usize
            s.zoom = 2usize
            s.ct_x = usize(wx * 2.0f64)
            s.ct_y = usize(wy * 2.0f64)
            s.cx = f32((wx * 2.0f64 - f64(s.ct_x)) * 1100.0f64)
            s.cy = f32((wy * 2.0f64 - f64(s.ct_y)) * 1100.0f64)
            ui.say("maps level ")
            ui.say_num(s.lz)
            ui.say("\n")
        }
        ret
    }
    if s.zoom > 1usize {
        s.zoom -= 1usize
    } else if s.tile_ok && s.lz > 13usize {
        let wx = f64(s.ct_x) + f64(s.cx) / 1100.0f64
        let wy = f64(s.ct_y) + f64(s.cy) / 1100.0f64
        s.lz -= 1usize
        s.zoom = 1usize
        s.ct_x = usize(wx / 2.0f64)
        s.ct_y = usize(wy / 2.0f64)
        s.cx = f32((wx / 2.0f64 - f64(s.ct_x)) * 1100.0f64)
        s.cy = f32((wy / 2.0f64 - f64(s.ct_y)) * 1100.0f64)
        ui.say("maps level ")
        ui.say_num(s.lz)
        ui.say("\n")
    }
}

// What a tap on button `id` did: true when the screen changed.
fn say_signed(value: i64) {
    if value < 0i64 {
        ui.say("-")
        ui.say_num(usize(0i64 - value))
    } else {
        ui.say_num(usize(value))
    }
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == SEARCH_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                let found = search_map(a, s)
                ret true
            }
            ret ui.field_key(&s.query, id, false)
        }
        if id >= 660usize && id < 660usize + FOUND_MAX && id - 660usize < s.found_total {
            // A place found: it becomes the selected place, the view is put on it and its name is kept.
            let which = id - 660usize
            var n = 0usize
            while n < s.found_len[which] && n < 32usize {
                s.target_name[n] = s.found_name[which][n]
                n += 1usize
            }
            s.target_len = n
            s.target_lat = s.found_lat[which]
            s.target_lon = s.found_lon[which]
            s.screen = MAP_SCREEN
            s.selected = TARGET
            s.route = false
            s.net_route = false
            s.started = false
            s.sheet = false
            center_on(s, s.target_lat, s.target_lon)
            ui.say("maps place ")
            ui.say_text(ui.text_of(a, s.target_name[0usize..], s.target_len))
            ui.say("\n")
            ret true
        }
        ret false
    }
    if s.sheet {
        if id == 650usize {
            s.sheet = false
            s.screen = SEARCH_SCREEN
            s.query.len = 0usize
            s.found_total = 0usize
            ui.say("maps find\n")
            ret true
        }
        if id >= 400usize && id < 400usize + PLACES {
            s.selected = id - 400usize
            s.sheet = false
            s.route = false
            s.route_n = 0usize
            s.started = false
            s.cx = place_x(s.selected)
            s.cy = place_y(s.selected)
            ui.say("maps place ")
            ui.say(place_name(s.selected))
            ui.say("\n")
            ret true
        }
        if id == 600usize {
            s.sheet = false
            ret true
        }
        ret false
    }
    if id == 700usize {
        s.sheet = true
        ui.say("maps search\n")
        ret true
    }
    if id == 710usize {
        zoom_step(s, true)
        ui.say("maps zoom ")
        ui.say_num(s.zoom)
        ui.say("\n")
        ret true
    }
    if id == 711usize {
        zoom_step(s, false)
        ui.say("maps zoom ")
        ui.say_num(s.zoom)
        ui.say("\n")
        ret true
    }
    if id == 712usize {
        // (C160) The location service's fix (the Location switch and the Maps permission decide), else the middle of
        // the view as before.
        let (status, lat_micro, lon_micro, accuracy, source) = sensorclient.fix(true)
        if status == sensorclient.STATUS_OK {
            s.me_lat = f64(lat_micro) / 1000000.0f64
            s.me_lon = f64(lon_micro) / 1000000.0f64
            s.has_fix = true
            ui.say("maps location ")
            say_signed(lat_micro / 1000i64)
            ui.say(" ")
            say_signed(lon_micro / 1000i64)
            ui.say("\n")
            if s.tile_ok { center_on(s, s.me_lat, s.me_lon) }
            ret true
        }
        if status == sensorclient.STATUS_DENIED { ui.say("maps location off\n") }
        if s.tile_ok {
            center_on(s, s.me_lat, s.me_lon)
        } else {
            s.cx = me_x()
            s.cy = me_y()
        }
        ret true
    }
    if id == 713usize {
        if s.tile_ok { let kept = save_area(a, s) }
        ret true
    }
    if id == 720usize {
        pan(s, 0.0, -1.0)
        ret true
    }
    if id == 721usize {
        pan(s, 0.0, 1.0)
        ret true
    }
    if id == 722usize {
        pan(s, -1.0, 0.0)
        ret true
    }
    if id == 723usize {
        pan(s, 1.0, 0.0)
        ret true
    }
    if s.selected != NONE {
        if id == 502usize && s.selected == TARGET {
            // The way of travelling changes (walk, bike, drive); a route already asked for is asked for again.
            s.profile = (s.profile + 1usize) % 3usize
            ui.say("maps profile ")
            ui.say_num(s.profile)
            ui.say("\n")
            if s.route {
                let rerouted = route_map(a, s)
            }
            ret true
        }
        if id == 500usize && s.selected == TARGET {
            // (C160) Directions to a place the search found: the routing service's route from you to it.
            if !s.route {
                s.route = true
                let routed = route_map(a, s)
            } else {
                s.started = true
                ui.say("maps start\n")
            }
            ret true
        }
        if id == 500usize {
            if !s.route {
                s.route = true
                let planned = plan_route(a, s, s.selected)
                ui.say("maps route ")
                ui.say_num(minutes_for(s, s.selected))
                ui.say(" min ")
                ui.say_num(metres_for(s, s.selected))
                ui.say(" m\n")
            } else {
                s.started = true
                ui.say("maps start\n")
            }
            ret true
        }
        if id == 501usize {
            s.selected = NONE
            s.route = false
            s.route_n = 0usize
            s.started = false
            ret true
        }
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "maps")
    if kit_error != ok {
        ui.say("maps open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("maps fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.cx = me_x()
    s.cy = me_y()
    s.zoom = 1usize
    s.selected = NONE
    // (C160) The pyramid starts at level 14 over the tile that has always been the first; you are in its middle until
    // the location service says otherwise.
    s.lz = 14usize
    s.ct_x = 8681usize
    s.ct_y = 4769usize
    s.me_lat = lat_of(f64(s.ct_y) + 0.5f64, s.lz)
    s.me_lon = lon_of(f64(s.ct_x) + 0.5f64, s.lz)
    if !show(a, &kit, &s) {
        ui.say("maps present failed\n")
        ret ok
    }
    ui.say("maps shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // (C160) An idle moment loads the next tile the view needs (from Files when kept there, else over the
            // network); with no network the sample city stays.
            if s.screen == MAP_SCREEN && fill_tiles(a, &s) {
                if !show(a, &kit, &s) {
                    ui.say("maps present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("maps home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("maps present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
