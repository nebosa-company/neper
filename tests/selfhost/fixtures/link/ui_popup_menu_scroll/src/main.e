// A long popup menu (26 rows in a 300 px room) scrolls between two chevron strips: the wheel and the keyboard focus move
// the visible rows, and resting the pointer on a chevron strip scrolls them continuously toward it, frame by frame
// (the runtime's hover scroll), until the pointer leaves or an end is reached.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.text.shape
use e.ui.control
use e.ui.input
use e.ui.navigation
use e.ui.style
use e.ui.testing
use e.ui.widget

fn w16(d: []u8, at: usize, v: u32) {
    d[at] = u8((v >> 8u32) & 255u32)
    d[at + 1usize] = u8(v & 255u32)
}
fn w32(d: []u8, at: usize, v: u32) {
    w16(d, at, v >> 16u32)
    w16(d, at + 2usize, v & 65535u32)
}
fn record(d: []u8, slot: usize, tag: u32, at: usize, len: usize) {
    let r = 12usize + 16usize * slot
    w32(d, r, tag)
    w32(d, r + 8usize, u32(at))
    w32(d, r + 12usize, u32(len))
}

// The square-glyph font of the scene fixture, with a cmap mapping `a` to glyph 1.
fn synthetic_font(a: *mem.Arena) -> ([]u8, err) {
    let (d, d_error) = mem.alloc[u8](a, 512usize)
    if d_error != ok { ret (d, d_error) }
    var i = 0usize
    while i < 512usize {
        d[i] = 0u8
        i += 1usize
    }
    w32(d, 0usize, 65536u32)
    w16(d, 4usize, 7u32)
    record(d, 0usize, 1751474532u32, 128usize, 54usize)
    w16(d, 128usize + 18usize, 1000u32)
    record(d, 1usize, 1751672161u32, 192usize, 36usize)
    w16(d, 192usize + 4usize, 800u32)
    w16(d, 192usize + 34usize, 2u32)
    record(d, 2usize, 1752003704u32, 228usize, 8usize)
    w16(d, 228usize + 4usize, 600u32)
    record(d, 3usize, 1835104368u32, 236usize, 6usize)
    w16(d, 236usize + 4usize, 2u32)
    // cmap at 300: one encoding record (3, 1) to a format 4 subtable with one
    // segment, `a` (0x61) to glyph 1, and the 0xFFFF terminator.
    record(d, 4usize, 1668112752u32, 300usize, 44usize)
    w16(d, 300usize, 0u32)
    w16(d, 302usize, 1u32)
    w16(d, 304usize, 3u32)
    w16(d, 306usize, 1u32)
    w32(d, 308usize, 12u32)
    let sub = 312usize
    w16(d, sub, 4u32)
    w16(d, sub + 2usize, 32u32)
    w16(d, sub + 4usize, 0u32)
    w16(d, sub + 6usize, 4u32)
    w16(d, sub + 8usize, 4u32)
    w16(d, sub + 10usize, 1u32)
    w16(d, sub + 12usize, 0u32)
    w16(d, sub + 14usize, 97u32)
    w16(d, sub + 16usize, 65535u32)
    w16(d, sub + 18usize, 0u32)
    w16(d, sub + 20usize, 97u32)
    w16(d, sub + 22usize, 65535u32)
    w16(d, sub + 24usize, 65440u32)
    w16(d, sub + 26usize, 1u32)
    w16(d, sub + 28usize, 0u32)
    w16(d, sub + 30usize, 0u32)
    record(d, 5usize, 1819239265u32, 252usize, 6usize)
    record(d, 6usize, 1735162214u32, 260usize, 40usize)
    let g = 260usize
    w16(d, g, 1u32)
    w16(d, g + 2usize, 100u32)
    w16(d, g + 4usize, 100u32)
    w16(d, g + 6usize, 900u32)
    w16(d, g + 8usize, 900u32)
    w16(d, g + 10usize, 3u32)
    w16(d, g + 12usize, 0u32)
    var at = g + 14usize
    d[at] = 55u8
    d[at + 1usize] = 33u8
    d[at + 2usize] = 17u8
    d[at + 3usize] = 33u8
    at += 4usize
    d[at] = 100u8
    d[at + 1usize] = 3u8
    d[at + 2usize] = 32u8
    d[at + 3usize] = 252u8
    d[at + 4usize] = 224u8
    at += 5usize
    d[at] = 100u8
    d[at + 1usize] = 3u8
    d[at + 2usize] = 32u8
    at += 3usize
    w16(d, 252usize + 2usize, 0u32)
    w16(d, 252usize + 4usize, u32((at - g) / 2usize))
    ret (d, ok)
}


fn noop(ctx: *void) -> err { ret ok }

// One frame of the open menu at `now` ns: the clock, the host's Frame tick, the tree built, reconciled and drawn.
fn step(h: *testing.Harness, frame_storage: []u8, theme: *const control.Theme, commands: []const navigation.BarCommand, dismiss: *const widget.Submit, now: i64) -> err {
    let at_time = time.Instant { nanos: now }
    try testing.begin(h, at_time)
    try testing.send(h, input.Event { Frame: testing.no_window() })
    var frame = mem.arena_from(frame_storage)
    let (menu, menu_error) = navigation.bar_menu_limited(&frame, 21u64, theme, 20u64, "Menu", commands, true, dismiss, 300.0)
    if menu_error != ok { ret menu_error }
    let (parts, parts_error) = mem.alloc[widget.Node](&frame, 2usize)
    if parts_error != ok { ret parts_error }
    parts[0usize] = widget.box(20u64, control.sized_style(1.0, 1.0), zero)
    parts[1usize] = menu
    ret testing.pump(h, widget.stack(0u64, control.sized_style(400.0, 400.0), parts[0usize..2usize]), at_time)
}

fn offset_of(rt: *widget.Runtime, h: *const testing.Harness) -> f32 {
    let (offset, found) = widget.scroll_offset_of(rt, testing.by_key(h, navigation.menu_scroll_key(21u64)).element)
    if !found { os.exit(60i32) }
    ret offset
}

fn center_of(rt: *widget.Runtime, h: *const testing.Harness, key: widget.Key) -> geometry.Point {
    let (bounds, found) = widget.bounds_of(rt, testing.by_key(h, key).element)
    if !found { os.exit(61i32) }
    ret geometry.Point { x: bounds.x + bounds.width * 0.5, y: bounds.y + bounds.height * 0.5 }
}

// `count` frames of 16 ms from `from` ns; the last instant.
fn run_frames(h: *testing.Harness, frame_storage: []u8, theme: *const control.Theme, commands: []const navigation.BarCommand, dismiss: *const widget.Submit, from: i64, count: usize) -> i64 {
    var now = from
    var i = 0usize
    while i < count {
        now += 16000000i64
        if step(h, frame_storage, theme, commands, dismiss, now) != ok { os.exit(62i32) }
        i += 1usize
    }
    ret now
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let (font_bytes, font_error) = synthetic_font(a)
    if font_error != ok { os.exit(4i32) }
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 1usize)
    if fonts_error != ok { os.exit(5i32) }
    fonts[0usize] = shape.Font { id: 7u32, data: font_bytes, face_index: 0u32 }
    if scene.register_font(&renderer, fonts[0usize]) != ok { os.exit(6i32) }
    let tokens = style.reference(.Light)
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 4096usize, max_states: 64usize, state_bytes: 4096usize, state_classes: 8u16, max_depth: 64u16, max_commands: 65536usize })
    if runtime_error != ok { os.exit(7i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts[0usize..1usize], language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 400u32, 400u32, 1.0)
    if harness_error != ok { os.exit(8i32) }
    var harness = h
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(10i32) }
    let (commands, commands_error) = mem.alloc[navigation.BarCommand](a, 26usize)
    if commands_error != ok { os.exit(11i32) }
    let (dismiss, dismiss_error) = mem.alloc[widget.Submit](a, 1usize)
    if dismiss_error != ok { os.exit(12i32) }
    dismiss[0usize] = widget.Submit { ctx: zero, invoke: noop }
    var i = 0usize
    while i < 26usize {
        var blank: navigation.BarCommand = zero
        commands[i] = blank
        commands[i].label = "aaaa"
        commands[i].enabled = true
        commands[i].action = dismiss[0usize]
        i += 1usize
    }
    // The first command is a section header: no row, no focus stop.
    commands[0usize].header = true
    let view_key = navigation.menu_scroll_key(21u64)
    let up_key = view_key + 1u64
    let down_key = view_key + 2u64
    var now = 1000000000i64
    if step(&harness, frame_storage, &theme, commands, &dismiss[0usize], now) != ok { os.exit(13i32) }
    let (content, viewport, has_extents) = widget.scroll_extents(&runtime, testing.by_key(&harness, view_key).element)
    if !has_extents || !(content > viewport + 100.0) { os.exit(14i32) }
    let most = content - viewport
    if offset_of(&runtime, &harness) != 0.0 { os.exit(15i32) }
    let middle = center_of(&runtime, &harness, view_key)

    // The header is a plain line (no pressable row under its key), the row after it is.
    if testing.by_key(&harness, 22u64).count != 0usize || testing.by_key(&harness, 23u64).count == 0usize { os.exit(35i32) }
    // The wheel: three notches toward the end move the rows, three back bring them home.
    if testing.wheel(&harness, middle.x, middle.y, -3i32) != ok { os.exit(16i32) }
    now = run_frames(&harness, frame_storage, &theme, commands, &dismiss[0usize], now, 1usize)
    let wheeled = offset_of(&runtime, &harness)
    if !(wheeled > 20.0) { os.exit(17i32) }
    if testing.wheel(&harness, middle.x, middle.y, 3i32) != ok { os.exit(18i32) }
    now = run_frames(&harness, frame_storage, &theme, commands, &dismiss[0usize], now, 1usize)
    if offset_of(&runtime, &harness) != 0.0 { os.exit(19i32) }

    // The keyboard: Tab through the rows; the view follows the focus down_at past its first_at screen.
    var tabs = 0usize
    while tabs < 14usize {
        if testing.tab(&harness, false) != ok { os.exit(20i32) }
        now = run_frames(&harness, frame_storage, &theme, commands, &dismiss[0usize], now, 1usize)
        tabs += 1usize
    }
    let tabbed = offset_of(&runtime, &harness)
    if !(tabbed > 20.0) { os.exit(21i32) }
    let (focus, has_focus) = testing.focused(&harness)
    let (view_bounds, has_view) = widget.bounds_of(&runtime, testing.by_key(&harness, view_key).element)
    let (focus_bounds, has_bounds) = widget.bounds_of(&runtime, focus)
    if !has_focus || !has_view || !has_bounds || focus_bounds.y < view_bounds.y - 1.0 || focus_bounds.y + focus_bounds.height > view_bounds.y + view_bounds.height + 1.0 { os.exit(22i32) }
    if testing.wheel(&harness, middle.x, middle.y, 30i32) != ok { os.exit(23i32) }
    now = run_frames(&harness, frame_storage, &theme, commands, &dismiss[0usize], now, 1usize)
    if offset_of(&runtime, &harness) != 0.0 { os.exit(24i32) }

    // Hover: the pointer resting on the lower chevron scrolls the rows on, frame after frame; no pointer move needed.
    let down_at = center_of(&runtime, &harness, down_key)
    if testing.hover(&harness, down_at.x, down_at.y) != ok { os.exit(25i32) }
    now = run_frames(&harness, frame_storage, &theme, commands, &dismiss[0usize], now, 15usize)
    let first_at = offset_of(&runtime, &harness)
    now = run_frames(&harness, frame_storage, &theme, commands, &dismiss[0usize], now, 15usize)
    let second_at = offset_of(&runtime, &harness)
    // 15 frames of 16 ms at 360 px a second_at are about 86 px.
    if !(first_at > 60.0 && first_at < 120.0) || !(second_at > first_at + 60.0) { os.exit(26i32) }
    // The pointer off the strip, onto the rows: the view rests.
    if testing.hover(&harness, middle.x, middle.y) != ok { os.exit(27i32) }
    now = run_frames(&harness, frame_storage, &theme, commands, &dismiss[0usize], now, 10usize)
    let rested = offset_of(&runtime, &harness)
    now = run_frames(&harness, frame_storage, &theme, commands, &dismiss[0usize], now, 10usize)
    if offset_of(&runtime, &harness) != rested { os.exit(28i32) }
    // The upper chevron brings the rows back.
    let up_at = center_of(&runtime, &harness, up_key)
    if testing.hover(&harness, up_at.x, up_at.y) != ok { os.exit(29i32) }
    now = run_frames(&harness, frame_storage, &theme, commands, &dismiss[0usize], now, 15usize)
    if !(offset_of(&runtime, &harness) < rested - 60.0) { os.exit(30i32) }
    // Held long enough the view stops at either end.
    now = run_frames(&harness, frame_storage, &theme, commands, &dismiss[0usize], now, 120usize)
    if offset_of(&runtime, &harness) != 0.0 { os.exit(31i32) }
    if testing.hover(&harness, down_at.x, down_at.y) != ok { os.exit(32i32) }
    now = run_frames(&harness, frame_storage, &theme, commands, &dismiss[0usize], now, 200usize)
    if offset_of(&runtime, &harness) != most { os.exit(33i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(34i32) }
    try io.print("ui popup menu scroll ok\n")
    ret ok
}
