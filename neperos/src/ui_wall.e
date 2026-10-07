// The NeperOS launcher with a PNG wallpaper from the filesystem (C112, D2174). It builds a small
// image, encodes it to PNG, stores it in the C106 filesystem server through e.fs (fs.write_file),
// reads the PNG bytes back (fs.read_file), decodes them (e.fmt.png) and draws the decoded texture
// scaled to cover the 256x256 surface as the wallpaper, then the top bar and the 8x5 icon grid over
// it -- the launcher layout of D2172/D2173 with a real wallpaper read from the filesystem. It folds
// the frame to a hash; the run on QEMU 8.2 and 11.1 agree. Program 1 of an fsserver archive, it ends
// by telling the server to quit. Needs the large arena (`bigarena`).
use e.mem
use e.os
use e.fs
use e.io
use e.gpu
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.fmt.png

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

fn reader_of(state: *io.SliceReader, data: str) -> io.Reader {
    state.data = data
    state.off = 0usize
    ret io.slice_reader(state)
}

fn fill(builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, red: f32, green: f32, blue: f32) {
    let pushed = scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(x, y, w, h), brush: paint.Brush { Solid: paint.Color { red: red, green: green, blue: blue, alpha: 1.0 } } } })
}

// A 4x4 RGBA8 gradient, the wallpaper's source image before it becomes a PNG on disk. Small on
// purpose: the C106 server stores a file in one 512-byte block, so the encoded PNG must fit, and
// DrawImage scales the little image to cover the 256x256 surface.
fn make_wallpaper(a: *mem.Arena) -> (image.ConstImage, err) {
    let (pixels, pixels_error) = mem.alloc[u8](a, 4usize * 4usize * 4usize)
    if pixels_error != ok { ret (zero, pixels_error) }
    var y = 0usize
    while y < 4usize {
        var x = 0usize
        while x < 4usize {
            let p = (y * 4usize + x) * 4usize
            pixels[p] = u8(x * 64usize)
            pixels[p + 1usize] = u8(y * 64usize)
            pixels[p + 2usize] = 128u8
            pixels[p + 3usize] = 255u8
            x += 1usize
        }
        y += 1usize
    }
    let (made, made_error) = image.make_const(pixels, 4u32, 4u32, 16usize, image.Format.Rgba8, image.Alpha.Straight)
    ret (made, made_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    say("ui wall A\n")
    // Encode the wallpaper to PNG and store it in the filesystem.
    let (source, source_error) = make_wallpaper(a)
    if source_error != ok { ret source_error }
    say("ui wall B\n")
    let (buffer, buffer_error) = mem.alloc[u8](a, 65536usize)
    if buffer_error != ok { ret buffer_error }
    var sink = io.SliceWriter { data: buffer, off: 0usize }
    var encoder = io.slice_writer(&sink)
    if png.encode(&encoder, source, png.EncodeOptions { compression: .Fast, interlace: false }) != ok {
        say("ui wall encode failed\n")
        ret ok
    }
    say("ui wall encoded ")
    say_num(sink.off)
    say("\n")
    let encoded = buffer[0usize..sink.off]
    let store_error = fs.write_file(a, "/wall.png", encoded)
    if store_error != ok {
        say("ui wall store failed\n")
        let q = os.send(1usize, 0usize, 99usize)
        ret ok
    }
    // Read the PNG back from the filesystem and decode it.
    let (wall_bytes, read_error) = fs.read_file(a, "/wall.png", 65536usize)
    if read_error != ok {
        say("ui wall read failed\n")
        let q = os.send(1usize, 0usize, 99usize)
        ret ok
    }
    say("ui wall from fs\n")
    var reader_state: io.SliceReader = zero
    let (decoded, decode_error) = png.decode(a, reader_of(&reader_state, wall_bytes), png.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 0u64, verify_crc: true })
    if decode_error != ok {
        say("ui wall decode failed\n")
        let q = os.send(1usize, 0usize, 99usize)
        ret ok
    }
    let (wall_view, wall_view_error) = image.make_const(decoded.pixels, decoded.width, decoded.height, decoded.stride, decoded.format, decoded.alpha)
    if wall_view_error != ok {
        say("ui wall view failed\n")
        ret ok
    }

    // Render: the wallpaper scaled to cover, then the top bar and the 8x5 icon grid over it.
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("ui wall gpu failed\n")
        ret ok
    }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok {
        say("ui wall queue failed\n")
        ret ok
    }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, 256u32, 256u32, gpu.Format.Bgra8)
    if frames_error != ok {
        say("ui wall target failed\n")
        ret ok
    }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok {
        say("ui wall canvas failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok {
        say("ui wall renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    let (texture, upload_error) = scene.upload_image(&renderer, wall_view)
    if upload_error != ok {
        say("ui wall upload failed\n")
        ret ok
    }
    let (builder_value, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    let wallpaper = scene.push(&builder, scene.Command { Image: scene.DrawImage { texture: texture, source: geometry.rect(0.0, 0.0, f32(decoded.width), f32(decoded.height)), destination: geometry.rect(0.0, 0.0, 256.0, 256.0), opacity: 1.0 } })
    fill(&builder, 0.0, 0.0, 256.0, 18.0, 0.05, 0.06, 0.10)
    var tick = 0usize
    while tick < 5usize {
        let tx = 256.0 - 10.0 - f32(tick) * 12.0
        fill(&builder, tx, 5.0, 8.0, 8.0, 0.7, 0.75, 0.85)
        tick += 1usize
    }
    var r = 0usize
    while r < 8usize {
        var c = 0usize
        while c < 5usize {
            let cx = 8.0 + f32(c) * 48.0
            let cy = 28.0 + f32(r) * 28.0
            let idx = r * 5usize + c
            let shade = f32(idx) / 40.0
            fill(&builder, cx + 6.0, cy + 4.0, 36.0, 20.0, 0.3 + shade * 0.5, 0.5, 0.85 - shade * 0.4)
            c += 1usize
        }
        r += 1usize
    }
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("ui wall compile failed\n")
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, canvas, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok {
        say("ui wall render failed\n")
        ret ok
    }
    let (rendered, presented_error) = gpu.presented(frames)
    if presented_error != ok {
        say("ui wall presented failed\n")
        ret ok
    }
    let (out_pixels, out_error) = mem.alloc[u32](a, 256usize * 256usize)
    if out_error != ok { ret out_error }
    if gpu.read_image(q, rendered, out_pixels) != ok {
        say("ui wall read_image failed\n")
        ret ok
    }
    var hash = 2166136261usize
    var i = 0usize
    while i < out_pixels.len {
        hash = ((hash ^ usize(out_pixels[i])) * 16777619usize) & 4294967295usize
        i += 1usize
    }
    say("ui wall hash ")
    say_num(hash)
    say("\n")
    let quit = os.send(1usize, 0usize, 99usize)
    ret ok
}
