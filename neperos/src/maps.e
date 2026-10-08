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
use appkit
use text
use ui

const NONE: usize = 99usize
const PLACES: usize = 6usize
// The map: 1100 units square; roads every 180 units from 100, 14 wide.
fn road_at() -> f32 {
    ret 100.0
}


type State = struct {
    cx: f32,
    cy: f32,
    zoom: usize,
    selected: usize,
    route: bool,
    sheet: bool,
    started: bool,
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

fn abs(v: f32) -> f32 {
    if v < 0.0 { ret 0.0 - v }
    ret v
}

// The distance along the roads from you to a place, in metres (a block is 150 m).
fn metres(index: usize) -> usize {
    ret usize((abs(place_x(index) - me_x()) + abs(place_y(index) - me_y())) * 150.0 / 180.0)
}

fn minutes(index: usize) -> usize {
    let m = metres(index) / 80usize
    if m < 1usize { ret 1usize }
    ret m
}

fn distance_text(a: *mem.Arena, index: usize) -> str {
    let m = metres(index)
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

fn draw_map(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let save: scene.Command = .Save
    try scene.push(builder, save)
    try scene.push(builder, scene.Command { Clip: scene.Clip { Rect: geometry.rect(0.0, 84.0, 412.0, 742.0) } })
    // The ground is the road colour; blocks sit on it.
    try ui.card(a, builder, 0.0, 84.0, 412.0, 742.0, 0.0, paint.Color { red: 0.98, green: 0.97, blue: 0.94, alpha: 1.0 })
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
    if s.route && s.selected != NONE {
        let xs: [3]f32 = [3]f32{ sx(s, me_x()), sx(s, me_x()), sx(s, place_x(s.selected)) }
        let ys: [3]f32 = [3]f32{ sy(s, me_y()), sy(s, place_y(s.selected)), sy(s, place_y(s.selected)) }
        try ui.polyline(a, builder, xs[0usize..3usize], ys[0usize..3usize], 3usize, 7.0, paint.Color { red: 0.20, green: 0.45, blue: 0.85, alpha: 1.0 })
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
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, place_kind(i), "  ", distance_text(a, i)), 80.0, y + 32.0, ui.muted())
        ui.hit(&s.hits, 400usize + i, 16.0, y, 380.0, 56.0)
        i += 1usize
    }
    ret ok
}

fn draw_card(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 0.0, 664.0, 412.0, 232.0, 24.0, ui.cream())
    try ui.put(a, builder, faces.jost_bold, 24.0, place_name(s.selected), 24.0, 678.0, ui.ink())
    try ui.put(a, builder, faces.grotesk, 14.0, ui.join(a, place_kind(s.selected), "  ", ui.join(a, distance_text(a, s.selected), ", ", ui.join(a, ui.number(a, minutes(s.selected)), " min on foot", ""))), 24.0, 712.0, ui.muted())
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
                ui.say("maps route ")
                ui.say_num(minutes(s.selected))
                ui.say(" min\n")
            } else {
                s.started = true
                ui.say("maps start\n")
            }
            ret true
        }
        if id == 501usize {
            s.selected = NONE
            s.route = false
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
            appkit.answer(appkit.ANSWER_NONE)
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
