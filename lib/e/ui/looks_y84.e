// Round 84, lane y: Cupertino shapes that control.e and the sheets call. This file cannot import control (control imports it): plain values only.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.mem
use e.ui.style

error TooLarge

// The Cupertino split view draws HIG's thin divider (one point) while this is set; the splitter sheet sets it around the thin cells.
var thin_divider: bool = false

fn set_thin(on: bool) { thin_divider = on }

fn thin() -> bool { ret thin_divider }

// The Apple logo as a filled path in a `w` x `h` box at (`x`, `y`): the silhouette of the macOS menu bar's logo (two shoulders, the
// waist, the bite at the right, the leaf), traced from the public 24 unit outline and scaled; its own ground colour is not needed.
fn apple(a: *mem.Arena, b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, color: paint.Color) -> err {
    let (pb, pb_error) = geometry.path_builder(a, 24usize, 64usize)
    if pb_error != ok { ret TooLarge }
    var builder = pb
    try geometry.move_to(&builder, geometry.Point { x: x + w * 0.5342, y: y + h * 0.2867 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.4884, y: y + h * 0.2867 }, geometry.Point { x: x + w * 0.4174, y: y + h * 0.2419 }, geometry.Point { x: x + w * 0.3426, y: y + h * 0.2435 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.2438, y: y + h * 0.2446 }, geometry.Point { x: x + w * 0.1533, y: y + h * 0.2927 }, geometry.Point { x: x + w * 0.1025, y: y + h * 0.3688 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.0000, y: y + h * 0.5216 }, geometry.Point { x: x + w * 0.0760, y: y + h * 0.7473 }, geometry.Point { x: x + w * 0.1760, y: y + h * 0.8715 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.2250, y: y + h * 0.9320 }, geometry.Point { x: x + w * 0.2829, y: y + h * 1.0000 }, geometry.Point { x: x + w * 0.3595, y: y + h * 0.9979 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.4331, y: y + h * 0.9952 }, geometry.Point { x: x + w * 0.4607, y: y + h * 0.9568 }, geometry.Point { x: x + w * 0.5500, y: y + h * 0.9568 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.6386, y: y + h * 0.9568 }, geometry.Point { x: x + w * 0.6637, y: y + h * 0.9979 }, geometry.Point { x: x + w * 0.7416, y: y + h * 0.9963 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.8209, y: y + h * 0.9952 }, geometry.Point { x: x + w * 0.8712, y: y + h * 0.9347 }, geometry.Point { x: x + w * 0.9196, y: y + h * 0.8737 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.9755, y: y + h * 0.8035 }, geometry.Point { x: x + w * 0.9987, y: y + h * 0.7354 }, geometry.Point { x: x + w * 1.0000, y: y + h * 0.7317 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.9981, y: y + h * 0.7311 }, geometry.Point { x: x + w * 0.8460, y: y + h * 0.6809 }, geometry.Point { x: x + w * 0.8442, y: y + h * 0.5297 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.8429, y: y + h * 0.4033 }, geometry.Point { x: x + w * 0.9642, y: y + h * 0.3429 }, geometry.Point { x: x + w * 0.9698, y: y + h * 0.3402 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.9007, y: y + h * 0.2533 }, geometry.Point { x: x + w * 0.7945, y: y + h * 0.2435 }, geometry.Point { x: x + w * 0.7574, y: y + h * 0.2414 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.6606, y: y + h * 0.2349 }, geometry.Point { x: x + w * 0.5795, y: y + h * 0.2867 }, geometry.Point { x: x + w * 0.5342, y: y + h * 0.2867 })
    try geometry.close_path(&builder)
    try geometry.move_to(&builder, geometry.Point { x: x + w * 0.6977, y: y + h * 0.1593 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.7385, y: y + h * 0.1172 }, geometry.Point { x: x + w * 0.7655, y: y + h * 0.0583 }, geometry.Point { x: x + w * 0.7580, y: y + h * 0.0000 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.6996, y: y + h * 0.0022 }, geometry.Point { x: x + w * 0.6292, y: y + h * 0.0335 }, geometry.Point { x: x + w * 0.5870, y: y + h * 0.0756 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.5493, y: y + h * 0.1128 }, geometry.Point { x: x + w * 0.5167, y: y + h * 0.1728 }, geometry.Point { x: x + w * 0.5254, y: y + h * 0.2300 })
    try geometry.cubic_to(&builder, geometry.Point { x: x + w * 0.5902, y: y + h * 0.2343 }, geometry.Point { x: x + w * 0.6568, y: y + h * 0.2014 }, geometry.Point { x: x + w * 0.6977, y: y + h * 0.1593 })
    try geometry.close_path(&builder)
    ret scene.push(b, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&builder), brush: paint.Brush { Solid: color } } })
}

// A sheet-local accent for the Cupertino look only: a copy of `base` whose Primary is `light` or `dark`; any other look gets `base` back
// unchanged, so a shared sheet that calls this leaves every other look's picture as it was.
fn tinted(a: *mem.Arena, base: *const style.ThemeTokens, light: u32, dark: u32) -> (*const style.ThemeTokens, err) {
    if base.profile != .CupertinoLike { ret (base, ok) }
    let (copy, copy_error) = mem.alloc[style.ThemeTokens](a, 1usize)
    if copy_error != ok { ret (base, TooLarge) }
    copy[0usize] = *base
    var value = light
    if base.palette == .Dark { value = dark }
    style.puta(&copy[0usize], .Primary, value, 1.0)
    ret (&copy[0usize], ok)
}
