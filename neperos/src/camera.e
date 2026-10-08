// Camera (D2217): the app behind the Camera icon, after the Pixel camera -- a viewfinder, a mode row
// (Video, Photo, Scan), a shutter, zoom chips (0.5x 1x 2x 5x), flash (Off, Auto, On), a grid, a flip
// between the rear and the front camera, and a thumbnail of the last capture that opens a review screen
// (previous, next, delete). A photo is a still, a video counts seconds while it records (the input
// server's 500 ms ticks), a scan is a page with corner marks. Black ground, cream and amber, like the
// other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the
// bottom leaves the app.
// ponytail: there is NO camera hardware, so the viewfinder shows SAMPLE scenes drawn as svg (a sunset
// landscape for the rear camera, a portrait for the front one, a document for Scan), and a capture is
// the scene it was taken of, kept in this process; a real sensor feed, files in Photos, focus and
// exposure are queued as C122. The zoom scales the scene about its centre (0.5x draws a wider world).
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
use scenes

const NONE: usize = 99usize
const MAX_CAPS: usize = 24usize
const MAX_HITS: usize = 32usize
const VIDEO: usize = 0usize
const PHOTO: usize = 1usize
const SCAN: usize = 2usize
fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
}

fn say_num(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    say(digits[at..20usize])
}

// ----------------------------------------------------------------------------------------------
// Text helpers.

fn number(a: *mem.Arena, value: usize) -> str {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    let (buffer, buffer_error) = mem.alloc[u8](a, 20usize - at)
    if buffer_error != ok { ret "0" }
    var i = 0usize
    while at + i < 20usize {
        buffer[i] = digits[at + i]
        i += 1usize
    }
    ret buffer[0usize..20usize - at]
}

fn join(a: *mem.Arena, first: str, second: str, third: str) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, first.len + second.len + third.len)
    if buffer_error != ok { ret first }
    var n = 0usize
    var i = 0usize
    while i < first.len {
        buffer[n] = first[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < second.len {
        buffer[n] = second[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < third.len {
        buffer[n] = third[i]
        n += 1usize
        i += 1usize
    }
    ret buffer[0usize..n]
}

// "0:07" from seconds.
fn duration_text(a: *mem.Arena, seconds: usize) -> str {
    var tens = ""
    if seconds % 60usize < 10usize { tens = "0" }
    ret join(a, join(a, number(a, seconds / 60usize), ":", tens), number(a, seconds % 60usize), "")
}

// Append `piece` to `buffer` at `at`; the new end.
fn emit(buffer: []u8, at: usize, piece: str) -> usize {
    var n = at
    var i = 0usize
    while i < piece.len && n < buffer.len {
        buffer[n] = piece[i]
        n += 1usize
        i += 1usize
    }
    ret n
}

fn emit_num(buffer: []u8, at: usize, value: usize) -> usize {
    var digits: [20]u8 = zero
    var d = 20usize
    var rest = value
    var open = true
    while open {
        d -= 1usize
        digits[d] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    ret emit(buffer, at, digits[d..20usize])
}

// ----------------------------------------------------------------------------------------------
// Zoom.

fn zoom_label(zoom: usize) -> str {
    if zoom == 0usize { ret "0.5" }
    if zoom == 1usize { ret "1x" }
    if zoom == 2usize { ret "2x" }
    ret "5x"
}

// ----------------------------------------------------------------------------------------------
// State.

type Cap = struct { kind: usize, seed: usize, front: bool, seconds: usize }

type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type State = struct {
    mode: usize,
    front: bool,
    zoom: usize,
    flash: usize,
    grid: bool,
    recording: bool,
    rec_ticks: usize,
    toast: usize,
    caps: [24]Cap,
    cap_total: usize,
    review: bool,
    view: usize,
    hits: [32]Hit,
    hit_total: usize,
}

fn mode_name(mode: usize) -> str {
    if mode == VIDEO { ret "Video" }
    if mode == PHOTO { ret "Photo" }
    ret "Scan"
}

fn flash_name(flash: usize) -> str {
    if flash == 0usize { ret "Off" }
    if flash == 1usize { ret "Auto" }
    ret "On"
}

fn toast_text(toast: usize) -> str {
    if toast == 1usize { ret "Photo saved" }
    if toast == 2usize { ret "Video saved" }
    if toast == 3usize { ret "Scan saved" }
    if toast == 4usize { ret "Front camera" }
    if toast == 5usize { ret "Rear camera" }
    ret ""
}

fn add_cap(s: *State, kind: usize, seconds: usize) {
    if s.cap_total == MAX_CAPS {
        var k = 1usize
        while k < MAX_CAPS {
            s.caps[k - 1usize] = s.caps[k]
            k += 1usize
        }
        s.cap_total -= 1usize
    }
    s.caps[s.cap_total] = Cap { kind: kind, seed: s.cap_total * 13usize + 5usize, front: s.front && kind != 2usize, seconds: seconds }
    s.cap_total += 1usize
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn light() -> paint.Color {
    ret paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 1.0 }
}

fn light_muted() -> paint.Color {
    ret paint.Color { red: 0.72, green: 0.72, blue: 0.74, alpha: 1.0 }
}

fn amber() -> paint.Color {
    ret paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }
}

fn ink() -> paint.Color {
    ret paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 }
}

fn shade(alpha: f32) -> paint.Color {
    ret paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: alpha }
}

fn card(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

fn disc(a: *mem.Arena, builder: *scene.Builder, cx: f32, cy: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.ellipse_path(a, cx, cy, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

fn hit(s: *State, id: usize, x: f32, y: f32, w: f32, h: f32) {
    if s.hit_total < MAX_HITS {
        s.hits[s.hit_total] = Hit { id: id, x: x, y: y, w: w, h: h }
        s.hit_total += 1usize
    }
}

fn put(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, x: f32, y: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, line, x, y, 0.0, 0u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn centred(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, cx: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, cx - text.measure(a, font, size, line) / 2.0, y, c)
}

// A picture drawn inside its own rectangle: nothing of the scene shows outside it.
fn picture(a: *mem.Arena, builder: *scene.Builder, doc: str, r: geometry.Rect, c: paint.Color) -> err {
    let save: scene.Command = .Save
    try scene.push(builder, save)
    try scene.push(builder, scene.Command { Clip: scene.Clip { Rect: r } })
    try svg.draw(a, builder, doc, r, c)
    let restore: scene.Command = .Restore
    try scene.push(builder, restore)
    ret ok
}

fn bolt_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M13 2L5 14h6l-1 8 8-12h-6z' fill='currentColor'/></svg>"
}

fn grid_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M3 3h18v18H3zM9 3v18M15 3v18M3 9h18M3 15h18' fill='none' stroke='currentColor' stroke-width='1.8'/></svg>"
}

fn flip_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12a8 8 0 0 0-14-5.3M4 4v4h4M4 12a8 8 0 0 0 14 5.3M20 20v-4h-4' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn back_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12H5M11 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn play_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M7 4l13 8-13 8z' fill='currentColor'/></svg>"
}

fn chevron_left() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M15 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn chevron_right() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M9 5l7 7-7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

// The corners of a page to scan.
fn brackets(a: *mem.Arena, builder: *scene.Builder) -> err {
    var corner = 0usize
    while corner < 4usize {
        var x: f32 = 44.0
        var y: f32 = 130.0
        if corner % 2usize == 1usize { x = 368.0 }
        if corner >= 2usize { y = 596.0 }
        var hx = x
        var vy = y
        if corner % 2usize == 1usize { hx = x - 28.0 }
        if corner >= 2usize { vy = y - 28.0 }
        try card(a, builder, hx, y - 1.5, 28.0, 3.0, 1.5, amber())
        try card(a, builder, x - 1.5, vy, 3.0, 28.0, 1.5, amber())
        corner += 1usize
    }
    ret ok
}

fn draw_camera(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    // The viewfinder, then the bars over what spills out of it.
    var kind = 0usize
    if s.front { kind = 1usize }
    if s.mode == SCAN { kind = 2usize }
    var seed = 2usize
    if s.cap_total > 0usize { seed = s.cap_total * 13usize + 5usize }
    try picture(a, builder, scenes.scene_svg(a, kind, seed, s.zoom, s.zoom == 0usize, 412usize, 560usize), geometry.rect(0.0, 84.0, 412.0, 560.0), light())
    if s.grid {
        try card(a, builder, 137.0, 84.0, 1.0, 560.0, 0.5, paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 0.4 })
        try card(a, builder, 275.0, 84.0, 1.0, 560.0, 0.5, paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 0.4 })
        try card(a, builder, 0.0, 270.0, 412.0, 1.0, 0.5, paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 0.4 })
        try card(a, builder, 0.0, 457.0, 412.0, 1.0, 0.5, paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 0.4 })
    }
    if s.mode == SCAN { try brackets(a, builder) }
    try card(a, builder, 0.0, 0.0, 412.0, 84.0, 0.0, paint.Color { red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0 })
    // The top bar: flash at the left, the recording time or the toast in the middle, the grid at the right.
    var flash_tone = light()
    if s.flash == 0usize { flash_tone = light_muted() }
    try svg.draw(a, builder, bolt_icon(), geometry.rect(24.0, 22.0, 26.0, 26.0), flash_tone)
    try put(a, builder, faces.grotesk, 11.0, flash_name(s.flash), 24.0, 52.0, light_muted())
    hit(s, 500usize, 8.0, 10.0, 66.0, 66.0)
    var grid_tone = light_muted()
    if s.grid { grid_tone = amber() }
    try svg.draw(a, builder, grid_icon(), geometry.rect(362.0, 22.0, 26.0, 26.0), grid_tone)
    try put(a, builder, faces.grotesk, 11.0, "Grid", 364.0, 52.0, light_muted())
    hit(s, 510usize, 340.0, 10.0, 66.0, 66.0)
    if s.recording {
        try disc(a, builder, 182.0, 40.0, 6.0, paint.Color { red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0 })
        try put(a, builder, faces.jost, 20.0, duration_text(a, s.rec_ticks / 2usize), 196.0, 28.0, light())
    } else if s.toast != 0usize {
        let message = toast_text(s.toast)
        let w = text.measure(a, faces.jost, 16.0, message)
        try card(a, builder, 206.0 - w / 2.0 - 14.0, 26.0, w + 28.0, 32.0, 16.0, paint.Color { red: 0.20, green: 0.20, blue: 0.22, alpha: 1.0 })
        try centred(a, builder, faces.jost, 16.0, message, 206.0, 33.0, light())
    }
    // The zoom chips over the viewfinder.
    var chip = 0usize
    while chip < 4usize {
        var fill = shade(0.55)
        var tone = light()
        if chip == s.zoom {
            fill = amber()
            tone = ink()
        }
        let x: f32 = 82.0 + f32(chip) * 64.0
        try card(a, builder, x, 604.0, 56.0, 30.0, 15.0, fill)
        try centred(a, builder, faces.jost, 14.0, zoom_label(chip), x + 28.0, 604.0 + 15.0 - 8.5, tone)
        hit(s, 400usize + chip, x, 604.0, 56.0, 30.0)
        chip += 1usize
    }
    // The controls panel.
    try card(a, builder, 0.0, 644.0, 412.0, 275.0, 0.0, paint.Color { red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0 })
    var mode = 0usize
    while mode < 3usize {
        let cx: f32 = 130.0 + f32(mode) * 76.0
        var tone = light_muted()
        if mode == s.mode {
            tone = amber()
            try card(a, builder, cx - 32.0, 692.0, 64.0, 2.5, 1.25, amber())
        }
        try centred(a, builder, faces.jost, 17.0, mode_name(mode), cx, 662.0, tone)
        hit(s, 200usize + mode, cx - 36.0, 654.0, 72.0, 44.0)
        mode += 1usize
    }
    // The shutter.
    try disc(a, builder, 206.0, 790.0, 42.0, light())
    try disc(a, builder, 206.0, 790.0, 37.0, paint.Color { red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0 })
    if s.mode == VIDEO {
        if s.recording {
            try card(a, builder, 190.0, 774.0, 32.0, 32.0, 8.0, paint.Color { red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0 })
        } else {
            try disc(a, builder, 206.0, 790.0, 31.0, paint.Color { red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0 })
        }
    } else if s.mode == SCAN {
        try disc(a, builder, 206.0, 790.0, 31.0, amber())
    } else {
        try disc(a, builder, 206.0, 790.0, 31.0, light())
    }
    hit(s, 100usize, 160.0, 744.0, 92.0, 92.0)
    // The thumbnail of the last capture and the flip button.
    try card(a, builder, 24.0, 762.0, 56.0, 56.0, 14.0, paint.Color { red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0 })
    if s.cap_total > 0usize {
        let last = s.caps[s.cap_total - 1usize]
        try picture(a, builder, scenes.scene_svg(a, cap_scene(last), last.seed, 1usize, false, 412usize, 560usize), geometry.rect(26.0, 764.0, 52.0, 52.0), light())
    }
    hit(s, 300usize, 24.0, 762.0, 56.0, 56.0)
    try disc(a, builder, 372.0, 790.0, 26.0, paint.Color { red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0 })
    try svg.draw(a, builder, flip_icon(), geometry.rect(358.0, 776.0, 28.0, 28.0), light())
    hit(s, 310usize, 340.0, 758.0, 64.0, 64.0)
    ret ok
}

// The scene a capture shows: a scan the document, a front-camera photo the portrait, else the landscape.
fn cap_scene(c: Cap) -> usize {
    if c.kind == 2usize { ret 2usize }
    if c.front { ret 1usize }
    ret 0usize
}

fn draw_review(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let c = s.caps[s.view]
    try picture(a, builder, scenes.scene_svg(a, cap_scene(c), c.seed, 1usize, false, 412usize, 560usize), geometry.rect(0.0, 84.0, 412.0, 560.0), light())
    if c.kind == 2usize { try brackets(a, builder) }
    if c.kind == 1usize {
        try disc(a, builder, 206.0, 364.0, 34.0, shade(0.5))
        try svg.draw(a, builder, play_icon(), geometry.rect(192.0, 350.0, 28.0, 28.0), light())
        try card(a, builder, 168.0, 604.0, 76.0, 28.0, 14.0, shade(0.55))
        try centred(a, builder, faces.jost, 15.0, duration_text(a, c.seconds), 206.0, 610.0, light())
    }
    try card(a, builder, 0.0, 0.0, 412.0, 84.0, 0.0, paint.Color { red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0 })
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 28.0, 28.0, 28.0), light())
    hit(s, 700usize, 0.0, 14.0, 66.0, 56.0)
    var label = "Photo"
    if c.kind == 1usize { label = "Video" }
    if c.kind == 2usize { label = "Scan" }
    try centred(a, builder, faces.jost, 20.0, join(a, join(a, number(a, s.view + 1usize), " of ", number(a, s.cap_total)), "  ", label), 206.0, 28.0, light())
    try card(a, builder, 0.0, 644.0, 412.0, 275.0, 0.0, paint.Color { red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0 })
    try disc(a, builder, 70.0, 740.0, 28.0, paint.Color { red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0 })
    try svg.draw(a, builder, chevron_left(), geometry.rect(56.0, 726.0, 28.0, 28.0), light())
    hit(s, 600usize, 30.0, 700.0, 80.0, 80.0)
    try disc(a, builder, 342.0, 740.0, 28.0, paint.Color { red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0 })
    try svg.draw(a, builder, chevron_right(), geometry.rect(328.0, 726.0, 28.0, 28.0), light())
    hit(s, 601usize, 302.0, 700.0, 80.0, 80.0)
    try card(a, builder, 146.0, 718.0, 120.0, 44.0, 22.0, paint.Color { red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0 })
    try centred(a, builder, faces.jost, 16.0, "Delete", 206.0, 730.0, light())
    hit(s, 602usize, 146.0, 718.0, 120.0, 44.0)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    if s.review {
        try draw_review(a, builder, s, faces)
    } else {
        try draw_camera(a, builder, s, faces)
    }
    try card(a, builder, 156.0, 906.0, 100.0, 5.0, 2.5, paint.Color { red: 0.9, green: 0.9, blue: 0.92, alpha: 0.85 })
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

fn remove_cap(s: *State, index: usize) {
    var k = index + 1usize
    while k < s.cap_total {
        s.caps[k - 1usize] = s.caps[k]
        k += 1usize
    }
    s.cap_total -= 1usize
}

// What a tap on button `id` did: true when the screen changed.
fn act(s: *State, id: usize) -> bool {
    if s.review {
        if id == 700usize {
            s.review = false
            say("camera back\n")
            ret true
        }
        if id == 600usize {
            if s.view > 0usize { s.view -= 1usize }
            ret true
        }
        if id == 601usize {
            if s.view + 1usize < s.cap_total { s.view += 1usize }
            ret true
        }
        if id == 602usize {
            remove_cap(s, s.view)
            say("camera deleted\n")
            if s.cap_total == 0usize {
                s.review = false
            } else if s.view >= s.cap_total {
                s.view = s.cap_total - 1usize
            }
            ret true
        }
        ret false
    }
    if id == 100usize {
        if s.mode == PHOTO {
            add_cap(s, 0usize, 0usize)
            s.toast = 1usize
            say("camera photo ")
            say_num(s.cap_total)
            say("\n")
        } else if s.mode == SCAN {
            add_cap(s, 2usize, 0usize)
            s.toast = 3usize
            say("camera scan ")
            say_num(s.cap_total)
            say("\n")
        } else if !s.recording {
            s.recording = true
            s.rec_ticks = 0usize
            s.toast = 0usize
            say("camera recording\n")
        } else {
            s.recording = false
            add_cap(s, 1usize, s.rec_ticks / 2usize)
            s.toast = 2usize
            say("camera video ")
            say_num(s.cap_total)
            say(" ")
            say_num(s.rec_ticks / 2usize)
            say("s\n")
        }
        ret true
    }
    if id >= 200usize && id < 203usize {
        if s.recording { ret false }
        s.mode = id - 200usize
        s.toast = 0usize
        say("camera mode ")
        say(mode_name(s.mode))
        say("\n")
        ret true
    }
    if id == 310usize {
        if s.recording { ret false }
        s.front = !s.front
        if s.front { s.toast = 4usize } else { s.toast = 5usize }
        if s.front { say("camera flip front\n") } else { say("camera flip rear\n") }
        ret true
    }
    if id >= 400usize && id < 404usize {
        s.zoom = id - 400usize
        say("camera zoom ")
        say(zoom_label(s.zoom))
        say("\n")
        ret true
    }
    if id == 500usize {
        s.flash = (s.flash + 1usize) % 3usize
        say("camera flash ")
        say(flash_name(s.flash))
        say("\n")
        ret true
    }
    if id == 510usize {
        s.grid = !s.grid
        ret true
    }
    if id == 300usize {
        if s.cap_total > 0usize && !s.recording {
            s.review = true
            s.view = s.cap_total - 1usize
            say("camera review ")
            say_num(s.cap_total)
            say("\n")
            ret true
        }
        ret false
    }
    ret false
}

fn hit_at(s: *State, x: f32, y: f32) -> usize {
    var i = s.hit_total
    while i > 0usize {
        i -= 1usize
        let h = s.hits[i]
        if x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h { ret h.id }
    }
    ret NONE
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "camera")
    if kit_error != ok {
        say("camera open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("camera fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.mode = PHOTO
    s.zoom = 1usize
    if !show(a, &kit, &s) {
        say("camera present failed\n")
        ret ok
    }
    say("camera shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // While a video records, the time shown follows the ticks (two a second).
            if s.recording {
                s.rec_ticks += 1usize
                if s.rec_ticks % 2usize == 0usize {
                    if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
                } else {
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            say("camera home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    say("camera present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
