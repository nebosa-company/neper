// Round 87, lane y: Cupertino-only drawing and values for the generic rows. Cannot import control (control imports it): plain values only.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.mem
use e.str as strs
use e.ui.style

error TooLarge

type Path = struct { b: geometry.PathBuilder, x: f32, y: f32, w: f32, h: f32, flip: bool }

fn pt(p: *Path, u: f32, v: f32) -> geometry.Point {
    var uu = u
    if p.flip { uu = 1.0 - u }
    ret geometry.Point { x: p.x + p.w * uu, y: p.y + p.h * v }
}

fn mv(p: *Path, u: f32, v: f32) -> err { ret geometry.move_to(&p.b, pt(p, u, v)) }

fn ln(p: *Path, u: f32, v: f32) -> err { ret geometry.line_to(&p.b, pt(p, u, v)) }

fn cu(p: *Path, a: f32, b: f32, c: f32, d: f32, e: f32, f: f32) -> err { ret geometry.cubic_to(&p.b, pt(p, a, b), pt(p, c, d), pt(p, e, f)) }

fn ring(p: *Path, cx: f32, cy: f32, r: f32) -> err {
    let k = r * 0.5523
    try mv(p, cx + r, cy)
    try cu(p, cx + r, cy + k, cx + k, cy + r, cx, cy + r)
    try cu(p, cx - k, cy + r, cx - r, cy + k, cx - r, cy)
    try cu(p, cx - r, cy - k, cx - k, cy - r, cx, cy - r)
    try cu(p, cx + k, cy - r, cx + r, cy - k, cx + r, cy)
    ret ok
}

fn box(p: *Path, l: f32, t: f32, r: f32, bt: f32, c: f32) -> err {
    try mv(p, l + c, t)
    try ln(p, r - c, t)
    try cu(p, r, t, r, t, r, t + c)
    try ln(p, r, bt - c)
    try cu(p, r, bt, r, bt, r - c, bt)
    try ln(p, l + c, bt)
    try cu(p, l, bt, l, bt, l, bt - c)
    try ln(p, l, t + c)
    try cu(p, l, t, l, t, l + c, t)
    ret ok
}

// SF-Symbols-style outline command glyphs in a `w` x `h` box, round caps and joins; `code`: 0 scissors, 1 two pages, 2 clipboard,
// 3 B, 4 I, 5 U, 6 undo, 7 redo, 8 save (arrow into a tray). The letters stroke a little heavier than the rest.
fn command_glyph(a: *mem.Arena, b: *scene.Builder, code: u8, x: f32, y: f32, w: f32, h: f32, color: paint.Color, stroke: f32) -> err {
    let (pb, pb_error) = geometry.path_builder(a, 40usize, 96usize)
    if pb_error != ok { ret TooLarge }
    var p = Path { b: pb, x: x, y: y, w: w, h: h, flip: code == 7u8 }
    var width = stroke
    if code == 0u8 {
        try ring(&p, 0.25, 0.77, 0.15)
        try ring(&p, 0.75, 0.77, 0.15)
        try mv(&p, 0.35, 0.66)
        try ln(&p, 0.82, 0.08)
        try mv(&p, 0.65, 0.66)
        try ln(&p, 0.18, 0.08)
    }
    if code == 1u8 {
        try box(&p, 0.34, 0.30, 0.88, 0.92, 0.08)
        try mv(&p, 0.34, 0.70)
        try ln(&p, 0.12, 0.70)
        try ln(&p, 0.12, 0.08)
        try ln(&p, 0.66, 0.08)
        try ln(&p, 0.66, 0.30)
    }
    if code == 2u8 {
        try box(&p, 0.16, 0.14, 0.84, 0.92, 0.10)
        try box(&p, 0.36, 0.05, 0.64, 0.24, 0.05)
        try mv(&p, 0.32, 0.52)
        try ln(&p, 0.68, 0.52)
        try mv(&p, 0.32, 0.70)
        try ln(&p, 0.68, 0.70)
    }
    if code == 3u8 {
        width = stroke * 1.4
        try mv(&p, 0.28, 0.10)
        try ln(&p, 0.28, 0.90)
        try mv(&p, 0.28, 0.10)
        try ln(&p, 0.56, 0.10)
        try cu(&p, 0.84, 0.10, 0.84, 0.50, 0.56, 0.50)
        try ln(&p, 0.28, 0.50)
        try mv(&p, 0.56, 0.50)
        try cu(&p, 0.90, 0.50, 0.90, 0.90, 0.56, 0.90)
        try ln(&p, 0.28, 0.90)
    }
    if code == 4u8 {
        width = stroke * 1.4
        try mv(&p, 0.62, 0.10)
        try ln(&p, 0.38, 0.90)
        try mv(&p, 0.48, 0.10)
        try ln(&p, 0.76, 0.10)
        try mv(&p, 0.24, 0.90)
        try ln(&p, 0.52, 0.90)
    }
    if code == 5u8 {
        width = stroke * 1.4
        try mv(&p, 0.28, 0.06)
        try ln(&p, 0.28, 0.48)
        try cu(&p, 0.28, 0.84, 0.72, 0.84, 0.72, 0.48)
        try ln(&p, 0.72, 0.06)
        try mv(&p, 0.18, 0.96)
        try ln(&p, 0.82, 0.96)
    }
    if code == 6u8 || code == 7u8 {
        try mv(&p, 0.34, 0.14)
        try ln(&p, 0.14, 0.36)
        try ln(&p, 0.34, 0.58)
        try mv(&p, 0.14, 0.36)
        try ln(&p, 0.58, 0.36)
        try cu(&p, 0.90, 0.36, 0.90, 0.84, 0.58, 0.84)
        try ln(&p, 0.34, 0.84)
    }
    if code == 8u8 {
        try mv(&p, 0.14, 0.58)
        try ln(&p, 0.14, 0.88)
        try ln(&p, 0.86, 0.88)
        try ln(&p, 0.86, 0.58)
        try mv(&p, 0.50, 0.08)
        try ln(&p, 0.50, 0.68)
        try mv(&p, 0.28, 0.46)
        try ln(&p, 0.50, 0.70)
        try ln(&p, 0.72, 0.46)
    }
    ret scene.push(b, scene.Command { StrokePath: scene.StrokePath { path: geometry.finish(&p.b), brush: paint.Brush { Solid: color }, stroke: paint.Stroke { width: width, cap: .Round, join: .Round, miter_limit: 4.0 } } })
}

// The glyph code a quick-access action of that name takes, or 255 for a text button.
fn quick_code(label: str) -> u8 {
    if strs.eq(label, "Save") { ret 8u8 }
    if strs.eq(label, "Undo") { ret 6u8 }
    if strs.eq(label, "Redo") { ret 7u8 }
    ret 255u8
}


type RoleTone = struct { role: style.ColorRole, light: u32, dark: u32 }

// A copy of `base` with each role set to its light or dark value (Cupertino only; any other look gets `base` back unchanged). `ring`
// also moves the keyboard ring to the first role's blue, at 80 %.
fn retoned(a: *mem.Arena, base: *const style.ThemeTokens, tones: []const RoleTone) -> (*const style.ThemeTokens, err) {
    if base.profile != .CupertinoLike { ret (base, ok) }
    let (copy, copy_error) = mem.alloc[style.ThemeTokens](a, 1usize)
    if copy_error != ok { ret (base, TooLarge) }
    copy[0usize] = *base
    var i = 0usize
    while i < tones.len {
        var value = tones[i].light
        if base.palette == .Dark { value = tones[i].dark }
        style.puta(&copy[0usize], tones[i].role, value, 1.0)
        i += 1usize
    }
    ret (&copy[0usize], ok)
}

// The text and control tones that hold 4.5:1 on the grouped ground in both palettes: the accent blue, the orange, the green, and the
// quiet grey.
fn blue_tone() -> RoleTone { ret RoleTone { role: .Primary, light: 0x0040DDu32, dark: 0x409CFFu32 } }
fn orange_tone(role: style.ColorRole) -> RoleTone { ret RoleTone { role: role, light: 0xC93400u32, dark: 0xFF9F0Au32 } }
fn green_tone(role: style.ColorRole) -> RoleTone { ret RoleTone { role: role, light: 0x1F7A35u32, dark: 0x30D158u32 } }
fn grey_tone(role: style.ColorRole) -> RoleTone { ret RoleTone { role: role, light: 0x6C6C70u32, dark: 0xAEAEB2u32 } }
