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
use httpc
use appkit
use text
use ui

const NONE: usize = 99usize
const PLACES: usize = 6usize
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
    // (C160) A vector tile from the network (OpenStreetMap data as OpenFreeMap serves it): its lines (roads and the
    // outlines of water) as map points, 1100 units across the tile, with where each line starts and what it is (0 a
    // street, 1 a main road, 2 water), and up to eight names of its points.
    tile_tried: bool,
    tile_ok: bool,
    tile_x: [384]f32,
    tile_y: [384]f32,
    tile_points: usize,
    tile_start: [48]usize,
    tile_kind: [48]u8,
    tile_lines: usize,
    label_text: [160]u8,
    label_len: [8]usize,
    label_x: [8]f32,
    label_y: [8]f32,
    labels: usize,
    hits: ui.Hits,
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

// (C160) The tile of the map's middle (zoom 14 over Oslo) from OpenFreeMap-style vector tiles over HTTPS, decoded
// with e.fmt.mvt: the `transportation` and `water` lines and the names of the `poi` and `place` points are kept in
// the state, scaled to the map's 1100 units. false when there is no network or the tile does not read.
// ponytail: a tile over 96 KB (httpc's reply limit, a dense city centre) does not load, the tile set's version is
// not fetched from its TileJSON (the path is a fixed one) and a single tile is the whole map; pyramid, panning
// across tiles and offline regions are what is left of C160.
fn fetch_tile(a: *mem.Arena, s: *State) -> bool {
    let mark = mem.mark(a)
    let (reply, get_error) = httpc.get(a, "tiles.openfreemap.org", "/planet/latest/14/8681/4769.pbf", "")
    if get_error != ok || reply.status != 200usize {
        mem.reset(a, mark)
        ret false
    }
    let (layers, parse_error) = mvt.parse(a, reply.body)
    if parse_error != ok {
        mem.reset(a, mark)
        ret false
    }
    s.tile_points = 0usize
    s.tile_lines = 0usize
    s.labels = 0usize
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
                    if s.tile_lines < 48usize && to > from && s.tile_points + (to - from) <= 384usize {
                        s.tile_start[s.tile_lines] = s.tile_points
                        s.tile_kind[s.tile_lines] = kind
                        s.tile_lines += 1usize
                        var q = from
                        while q < to {
                            s.tile_x[s.tile_points] = f32(feature.points[q].x) * 1100.0 / extent
                            s.tile_y[s.tile_points] = f32(feature.points[q].y) * 1100.0 / extent
                            s.tile_points += 1usize
                            q += 1usize
                        }
                    }
                    from = to
                    p += 1usize
                }
            }
            if is_named && feature.kind == mvt.KIND_POINT && feature.points.len > 0usize && s.labels < 8usize {
                let name = tag_text(layer, feature, "name")
                if name.len > 0usize && label_at + 20usize <= 160usize {
                    var n = 0usize
                    while n < name.len && n < 20usize {
                        s.label_text[label_at + n] = name[n]
                        n += 1usize
                    }
                    s.label_len[s.labels] = n
                    s.label_x[s.labels] = f32(feature.points[0usize].x) * 1100.0 / extent
                    s.label_y[s.labels] = f32(feature.points[0usize].y) * 1100.0 / extent
                    s.labels += 1usize
                    label_at += 20usize
                }
            }
            f += 1usize
        }
        l += 1usize
    }
    let layer_count = layers.len
    mem.reset(a, mark)
    ui.say("maps tile ")
    ui.say_num(layer_count)
    ui.say(" layers ")
    ui.say_num(s.tile_lines)
    ui.say(" lines ")
    ui.say_num(s.labels)
    ui.say(" names\n")
    ret s.tile_lines > 0usize
}

// (C160) The tile as the map: water and roads as strokes, the names of its points as labels.
fn draw_tile(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var line = 0usize
    while line < s.tile_lines {
        let from = s.tile_start[line]
        var to = s.tile_points
        if line + 1usize < s.tile_lines { to = s.tile_start[line + 1usize] }
        var xs: [32]f32 = zero
        var ys: [32]f32 = zero
        var n = 0usize
        while from + n < to && n < 32usize {
            xs[n] = sx(s, s.tile_x[from + n])
            ys[n] = sy(s, s.tile_y[from + n])
            n += 1usize
        }
        var width: f32 = 4.0 * scale(s)
        var colour = paint.Color { red: 0.78, green: 0.76, blue: 0.70, alpha: 1.0 }
        if s.tile_kind[line] == 1u8 {
            width = 8.0 * scale(s)
            colour = paint.Color { red: 0.95, green: 0.72, blue: 0.30, alpha: 1.0 }
        }
        if s.tile_kind[line] == 2u8 {
            width = 3.0 * scale(s)
            colour = paint.Color { red: 0.50, green: 0.70, blue: 0.88, alpha: 1.0 }
        }
        try ui.polyline(a, builder, xs[0usize..n], ys[0usize..n], n, width, colour)
        line += 1usize
    }
    var label = 0usize
    while label < s.labels {
        let px = sx(s, s.label_x[label])
        let py = sy(s, s.label_y[label])
        let name = ui.text_of(a, s.label_text[label * 20usize..], s.label_len[label])
        let w = text.measure(a, faces.jost, 13.0, name)
        try ui.disc(a, builder, px, py, 5.0, ui.amber_dark())
        try ui.card(a, builder, px - w / 2.0 - 8.0, py + 8.0, w + 16.0, 22.0, 11.0, ui.cream())
        try ui.centred(a, builder, faces.jost, 13.0, name, px, py + 11.0, ui.ink())
        label += 1usize
    }
    try ui.put(a, builder, faces.grotesk, 11.0, "Map data OpenStreetMap contributors (ODbL)", 12.0, 804.0, ui.muted())
    ui.say("maps tile drawn\n")
    ret ok
}

fn draw_map(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let save: scene.Command = .Save
    try scene.push(builder, save)
    try scene.push(builder, scene.Command { Clip: scene.Clip { Rect: geometry.rect(0.0, 84.0, 412.0, 742.0) } })
    // The ground is the road colour; blocks sit on it.
    try ui.card(a, builder, 0.0, 84.0, 412.0, 742.0, 0.0, paint.Color { red: 0.98, green: 0.97, blue: 0.94, alpha: 1.0 })
    if s.tile_ok {
        try draw_tile(a, builder, s, faces)
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
    try ui.put(a, builder, faces.jost_bold, 24.0, place_name(s.selected), 24.0, 678.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 14.0, ui.join(a, place_kind(s.selected), "  ", ui.join(a, distance_text(a, s, s.selected), ", ", ui.join(a, ui.number(a, minutes_for(s, s.selected)), " min on foot", ""))), 24.0, 712.0, ui.muted())
    if s.started {
        try ui.put(a, builder, faces.jost, 17.0, "Head along the road, then turn at the crossing", 24.0, 744.0, ui.amber_dark())
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
    try draw_map(a, builder, s, faces)
    // The search pill over the map, the zoom, the arrows and the way back to you.
    try ui.card(a, builder, 16.0, 22.0, 380.0, 50.0, 25.0, ui.cream())
    try ui.put(a, builder, faces.jost, 17.0, "Search here", 40.0, 35.0, ui.muted())
    ui.hit(&s.hits, 700usize, 16.0, 22.0, 380.0, 50.0)
    try control(a, builder, s, 710usize, 372.0, 280.0, plus_icon())
    try control(a, builder, s, 711usize, 372.0, 336.0, minus_icon())
    try control(a, builder, s, 712usize, 372.0, 392.0, target_icon())
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
    if s.cx < 0.0 { s.cx = 0.0 }
    if s.cy < 0.0 { s.cy = 0.0 }
    if s.cx > 1100.0 { s.cx = 1100.0 }
    if s.cy > 1100.0 { s.cy = 1100.0 }
}

// What a tap on button `id` did: true when the screen changed.
fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.sheet {
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
        if s.zoom < 3usize { s.zoom += 1usize }
        ui.say("maps zoom ")
        ui.say_num(s.zoom)
        ui.say("\n")
        ret true
    }
    if id == 711usize {
        if s.zoom > 1usize { s.zoom -= 1usize }
        ui.say("maps zoom ")
        ui.say_num(s.zoom)
        ui.say("\n")
        ret true
    }
    if id == 712usize {
        s.cx = me_x()
        s.cy = me_y()
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
            // (C160) The first idle moment fetches the tile; with no network the sample city stays.
            if !s.tile_tried {
                s.tile_tried = true
                s.tile_ok = fetch_tile(a, &s)
                if s.tile_ok {
                    if !show(a, &kit, &s) {
                        ui.say("maps present failed\n")
                        appkit.answer(appkit.ANSWER_NONE)
                    }
                } else {
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
