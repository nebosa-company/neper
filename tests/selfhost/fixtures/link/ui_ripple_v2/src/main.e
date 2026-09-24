// The v2 press ripple (D983, widget plan P5-02, docs/ux/components/Button, Row,
// Card) under the light theme: on a touch theme the pressed row carries a disc
// of `on-surface` at the `state-pressed` opacity from the press point over its
// pressed layer, as far as the phase says -- half the way to the farthest
// corner at 0.5, all of the row at 1 (the replay cache keeps no stale disc);
// clipped to a rounded tile's shape; none at phase 0 and none on a pointer
// theme.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.collection
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

const W: usize = 400usize

type Store = struct { presses: usize, press: widget.Submit, rows: [2]collection.RowItem, tiles: [1]collection.Tile }

fn on_press(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.presses += 1usize
    ret ok
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let (row, e1) = collection.row_of(a, 10u64, t, &s.rows[0usize], 0usize, 1usize, 300.0)
    var tile_keys: [1]widget.Key = zero
    tile_keys[0usize] = 31u64
    var laid = collection.grid_options()
    laid.width = 200.0
    let (tiles, e2) = collection.grid_view_of(a, 30u64, t, "Tiles", s.tiles[0usize..1usize], tile_keys[..], laid)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = row
    parts[1usize] = tiles
    var page = style.defaults()
    page.width = style.Length { Px: 400.0 }
    page.height = style.Length { Px: 400.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, page, parts[0usize..2usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * W + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn press(h: *testing.Harness, x: f32, y: f32) -> bool {
    ret testing.send(h, input.Event { PointerDown: testing.pointer_at(x, y) }) == ok
}

fn release(h: *testing.Harness, x: f32, y: f32) -> bool {
    ret testing.send(h, input.Event { PointerUp: testing.pointer_at(x, y) }) == ok
}

// Rebuild and paint the page at a phase, and take the picture.
fn frame(a: *mem.Arena, f: *mem.Arena, h: *testing.Harness, runtime: *widget.Runtime, t: *const control.Theme, s: *Store, phase: f32) -> (image.Image, bool) {
    widget.set_ripple_phase(runtime, phase)
    let (root, build_error) = build(f, t, s)
    if build_error != ok || testing.pump(h, root, time.Instant { nanos: 1000000000i64 }) != ok { ret (zero, false) }
    let (shot, shot_error) = testing.snapshot(h, a)
    ret (shot, shot_error == ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let tokens = style.reference(.Light)
    let touch_tokens = style.adapt(&tokens, style.Adaptation { size: .Expanded, capabilities: style.Capabilities { hover: false, fine_pointer: false, keyboard: false, touch: true, pen: false, resizable: false, multi_window: false, insets: zero }, profile: .Touch })
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 400usize, max_states: 16usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 32u16, max_commands: 2048usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let pointer = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let touch = control.Theme { tokens: &touch_tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 400u32, 400u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.press = widget.Submit { ctx: mem.cast[*void](s), invoke: on_press }
    s.rows[0usize] = collection.row_item("Wi-Fi")
    s.rows[0usize].action = s.press
    s.tiles[0usize] = collection.tile_of_name("Photo")
    s.tiles[0usize].action = s.press
    let (storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(storage)
    let background = style.color(&tokens, .Background)
    let ink = style.color(&tokens, .OnSurface)
    let pressed = tokens.states.pressed
    let once = style.mix(background, ink, pressed)
    let twice = style.mix(once, ink, pressed)
    // Touch: at rest nothing; pressed at phase 0.5 the disc covers the press
    // point but not the far end; at 1 it covers the whole row.
    let (rest, rest_ok) = frame(a, &f, &harness, &runtime, &touch, s, 0.0)
    let (row, has_row) = bounds(&harness, &runtime, 10u64)
    if !rest_ok || !has_row || !is_color(rest, at(row.x + 30.0, row.y + 28.0), background) { os.exit(9i32) }
    if !press(&harness, row.x + 30.0, row.y + 28.0) { os.exit(10i32) }
    let (flat, flat_ok) = frame(a, &f, &harness, &runtime, &touch, s, 0.0)
    if !flat_ok || !is_color(flat, at(row.x + 30.0, row.y + 28.0), once) { os.exit(11i32) }
    let (half, half_ok) = frame(a, &f, &harness, &runtime, &touch, s, 0.5)
    if !half_ok || !is_color(half, at(row.x + 30.0, row.y + 28.0), twice) || !is_color(half, at(row.x + 150.0, row.y + 28.0), twice) || !is_color(half, at(row.x + 290.0, row.y + 28.0), once) { os.exit(12i32) }
    let (full, full_ok) = frame(a, &f, &harness, &runtime, &touch, s, 1.0)
    if !full_ok || !is_color(full, at(row.x + 290.0, row.y + 28.0), twice) || !is_color(full, at(row.x + 290.0, row.y + 2.0), twice) { os.exit(13i32) }
    if !release(&harness, row.x + 30.0, row.y + 28.0) || s.presses != 1usize { os.exit(14i32) }
    // A rounded tile clips the disc to its corners.
    let (tile, has_tile) = bounds(&harness, &runtime, 31u64)
    if !has_tile || !press(&harness, tile.x + 100.0, tile.y + 60.0) { os.exit(15i32) }
    let (clipped, clipped_ok) = frame(a, &f, &harness, &runtime, &touch, s, 1.0)
    if !clipped_ok || !is_color(clipped, at(tile.x + 0.5, tile.y + 0.5), background) || !is_color(clipped, at(tile.x + 20.0, tile.y + 20.0), style.mix(style.color(&tokens, .SurfaceContainerHighest), ink, pressed)) { os.exit(16i32) }
    if !release(&harness, tile.x + 100.0, tile.y + 60.0) || s.presses != 2usize { os.exit(17i32) }
    // A pointer theme has no ripple: the pressed layer alone at phase 1.
    let (desk, desk_ok) = frame(a, &f, &harness, &runtime, &pointer, s, 0.0)
    let (desk_row, has_desk_row) = bounds(&harness, &runtime, 10u64)
    if !desk_ok || !has_desk_row || !press(&harness, desk_row.x + 30.0, desk_row.y + 24.0) { os.exit(18i32) }
    let (plain, plain_ok) = frame(a, &f, &harness, &runtime, &pointer, s, 1.0)
    if !plain_ok || !is_color(plain, at(desk_row.x + 30.0, desk_row.y + 24.0), once) || !is_color(plain, at(desk_row.x + 290.0, desk_row.y + 24.0), once) { os.exit(19i32) }
    if !release(&harness, desk_row.x + 30.0, desk_row.y + 24.0) { os.exit(20i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(21i32) }
    try io.print("ui ripple v2 ok\n")
    ret ok
}
