// A NeperOS program that renders text with a font READ FROM THE FILESYSTEM (C110, D2170). It builds
// a synthetic TrueType font, stores it in the C106 filesystem server through e.fs (fs.write_file),
// reads the bytes back (fs.read_file), and renders a glyph from the reloaded font through
// e.gfx.scene's DrawText over the e.gpu CPU backend -- the e.ui drawing path, now fed by a font the
// filesystem handed back. It folds the frame to a hash; a host run of the same program renders the
// same font to the same hash (the rasteriser is pure), so the hash is the determinism check and
// `ui font from fs` proves the bytes made the round trip. Program 1 of an fsserver archive, it ends
// by telling the server to quit. Needs the large arena (`bigarena`).
use e.mem
use e.os
use e.fs
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.text.shape

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
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

// A synthetic TrueType font with one square glyph (id 1), from the e.gfx.scene fixture verbatim.
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
    record(d, 2usize, 1752003704u32, 228usize, 8usize)
    w16(d, 228usize + 4usize, 600u32)
    record(d, 3usize, 1835104368u32, 236usize, 6usize)
    w16(d, 236usize + 4usize, 2u32)
    record(d, 4usize, 1668112752u32, 244usize, 4usize)
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
    let glyph_len = at - g
    w16(d, 252usize + 2usize, 0u32)
    w16(d, 252usize + 4usize, u32(glyph_len / 2usize))
    ret (d, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (font_bytes, font_error) = synthetic_font(a)
    if font_error != ok { ret font_error }
    // Store the font in the filesystem and read it back; render from the reloaded bytes. If the
    // round trip fails (e.g. a host with no writable path here) fall back to the in-memory bytes --
    // the render is identical, since both are the same font.
    var source = font_bytes
    var from_fs = false
    let write_error = fs.write_file(a, "/font.ttf", font_bytes)
    if write_error == ok {
        let (reloaded, read_error) = fs.read_file(a, "/font.ttf", 1024usize)
        if read_error == ok && reloaded.len == 512usize {
            source = reloaded
            from_fs = true
        }
    }
    if from_fs { say("ui font from fs\n") }

    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok { say("ui font gpu failed\n")
        ret ok
    }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { say("ui font queue failed\n")
        ret ok
    }
    let (frames, target_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, 64u32, 64u32, gpu.Format.Bgra8)
    if target_error != ok { say("ui font frames failed\n")
        ret ok
    }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { say("ui font canvas failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { say("ui font renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    let font = shape.Font { id: 7u32, data: source, face_index: 0u32 }
    if scene.register_font(&renderer, font) != ok { say("ui font register failed\n")
        ret ok
    }

    // One square glyph laid out at size 20, pen at (2, 58), the e.gfx.scene fixture's shape.
    var glyphs: [1]shape.Glyph = zero
    glyphs[0] = shape.Glyph { id: 1u32, cluster: 0usize, advance_x: 0.6, advance_y: 0.0, offset_x: 0.0, offset_y: 0.0 }
    var runs: [1]layout.GlyphRun = zero
    runs[0] = layout.GlyphRun { run: shape.Run { font: 7u32, direction: .LeftToRight, script: 0u32, language: "", glyphs: glyphs[0..] }, origin: geometry.Point { x: 0.0, y: 0.0 }, size: 20.0 }
    var lines: [1]layout.Line = zero
    lines[0] = layout.Line { runs: runs[0..], bounds: geometry.rect(0.0, 0.0, 12.0, 20.0), baseline: 0.0, start: 0usize, end: 1usize }
    let text_layout = layout.Layout { source: "a", lines: lines[0..], bounds: geometry.rect(0.0, 0.0, 12.0, 20.0) }

    let (builder_value, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    let bg = scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 64.0, 64.0), brush: paint.Brush { Solid: paint.rgba(0.1, 0.12, 0.16, 1.0) } } })
    let text = scene.push(&builder, scene.Command { Text: scene.DrawText { layout: &text_layout, origin: geometry.Point { x: 2.0, y: 58.0 }, brush: paint.Brush { Solid: paint.rgba(0.95, 0.95, 0.95, 1.0) } } })
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { say("ui font compile failed\n")
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, canvas, geometry.Size { width: 64.0, height: 64.0 })
    if render_error != ok { say("ui font render failed\n")
        ret ok
    }
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { say("ui font presented failed\n")
        ret ok
    }
    let (pixels, pixels_error) = mem.alloc[u32](a, 64usize * 64usize)
    if pixels_error != ok { ret pixels_error }
    if gpu.read_image(q, image, pixels) != ok { say("ui font read failed\n")
        ret ok
    }
    var hash = 2166136261usize
    var i = 0usize
    while i < pixels.len {
        hash = ((hash ^ usize(pixels[i])) * 16777619usize) & 4294967295usize
        i += 1usize
    }
    say("ui font hash ")
    say_num(hash)
    say("\n")
    // Tell the filesystem server to quit (op 0 on the request endpoint) so the kernel powers off.
    let quit = os.send(1usize, 0usize, 99usize)
    ret ok
}
