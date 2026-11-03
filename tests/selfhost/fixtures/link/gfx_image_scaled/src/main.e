use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.gpu
use e.math
use e.mem
use e.os

// An opaque image scaled up by the CPU renderer on a fractional rectangle (the axis-aligned path, with the bytes it leaves for the
// frame): every presented pixel is compared with bilinear sampling done here with the renderer's own arithmetic, equal to within a
// level (a vector form may round a half the other way), and the number of pixels a level out is small. Then the same scene with a
// translucent rectangle drawn over part of it: the pixels outside the rectangle are the same, and those inside are the blend to
// within a level.

const W: usize = 96usize
const H: usize = 64usize
fn dx() -> f32 { ret 3.4 }
fn dy() -> f32 { ret 2.3 }
fn dw() -> f32 { ret 85.7 }
fn dh() -> f32 { ret 57.6 }

fn texel(t: usize, c: usize) -> u8 {
    if c == 0usize { ret u8((t * 53usize + 11usize) % 256usize) }
    if c == 1usize { ret u8((t * 97usize + 5usize) % 256usize) }
    ret u8((t * 29usize + 200usize) % 256usize)
}

fn render(a: *mem.Arena, device: *gpu.Device, q: *gpu.Queue, overlay: bool, pixels: []u32) -> err {
    let (output_target, target_error) = gpu.open_target(q, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, u32(W), u32(H), .Rgba8)
    if target_error != ok { ret target_error }
    let (canvas, canvas_error) = scene.target_of(a, output_target)
    if canvas_error != ok { ret canvas_error }
    let (made_renderer, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { ret renderer_error }
    var renderer = made_renderer
    var texels: [96]u8 = zero
    var t = 0usize
    while t < 24usize {
        texels[t * 4usize] = texel(t, 0usize)
        texels[t * 4usize + 1usize] = texel(t, 1usize)
        texels[t * 4usize + 2usize] = texel(t, 2usize)
        texels[t * 4usize + 3usize] = 255u8
        t += 1usize
    }
    let (view, view_error) = image.make_const(texels[0usize..96usize], 6u32, 4u32, 24usize, .Rgba8, .Premultiplied)
    if view_error != ok { ret view_error }
    let (texture, upload_error) = scene.upload_image(&renderer, view)
    if upload_error != ok { ret upload_error }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, f32(W), f32(H)), brush: paint.Brush { Solid: paint.rgba(0.2, 0.3, 0.4, 1.0) } } })
    try scene.push(&builder, scene.Command { Image: scene.DrawImage { texture: texture, source: geometry.Rect { x: 0.0, y: 0.0, width: 6.0, height: 4.0 }, destination: geometry.Rect { x: dx(), y: dy(), width: dw(), height: dh() }, opacity: 1.0 } })
    if overlay {
        try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(20.0, 10.0, 30.0, 20.0), brush: paint.Brush { Solid: paint.rgba(1.0, 0.0, 0.0, 0.5) } } })
    }
    let (compiled, compile_error) = scene.compile(&renderer, scene.finish(&builder))
    if compile_error != ok { ret compile_error }
    try scene.render(&renderer, compiled, canvas, geometry.Size { width: f32(W), height: f32(H) })
    let (shown, shown_error) = gpu.presented(output_target)
    if shown_error != ok { ret shown_error }
    ret gpu.read_image(q, shown, pixels)
}

fn close(x: u32, y: u32) -> bool {
    if x > y { ret x - y <= 1u32 }
    ret y - x <= 1u32
}

// One channel of the image at pixel (x, y) the way the renderer's sampler makes it, as a byte; 256 where the pixel is outside.
fn expected(x: usize, y: usize, c: usize) -> u32 {
    let u = (f32(x) + 0.5 - dx()) / dw()
    let v = (f32(y) + 0.5 - dy()) / dh()
    if !(u >= 0.0 && u < 1.0 && v >= 0.0 && v < 1.0) { ret 256u32 }
    var fx = u * 6.0 - 0.5
    var fy = v * 4.0 - 0.5
    if !(fx >= 0.0) { fx = 0.0 }
    if !(fy >= 0.0) { fy = 0.0 }
    if fx > 5.0 { fx = 5.0 }
    if fy > 3.0 { fy = 3.0 }
    let x0 = usize(math.floor[f32](fx))
    let y0 = usize(math.floor[f32](fy))
    var x1 = x0 + 1usize
    var y1 = y0 + 1usize
    if x1 >= 6usize { x1 = x0 }
    if y1 >= 4usize { y1 = y0 }
    let fu = fx - f32(x0)
    let fv = fy - f32(y0)
    let p00 = f32(texel(y0 * 6usize + x0, c)) / 255.0
    let p10 = f32(texel(y0 * 6usize + x1, c)) / 255.0
    let p01 = f32(texel(y1 * 6usize + x0, c)) / 255.0
    let p11 = f32(texel(y1 * 6usize + x1, c)) / 255.0
    let out = (p00 * (1.0 - fu) + p10 * fu) * (1.0 - fv) + (p01 * (1.0 - fu) + p11 * fu) * fv
    ret u32(out * 255.0 + 0.5)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, device_error) = gpu.open(a, .Cpu, 0u32)
    if device_error != ok { ret device_error }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret queue_error }
    let (plain, plain_error) = mem.alloc[u32](a, W * H)
    if plain_error != ok { ret plain_error }
    let (over, over_error) = mem.alloc[u32](a, W * H)
    if over_error != ok { ret over_error }
    try render(a, device, q, false, plain)
    try render(a, device, q, true, over)
    var off = 0usize
    var y = 0usize
    while y < H {
        var x = 0usize
        while x < W {
            let p = plain[y * W + x]
            var c = 0usize
            while c < 3usize {
                let got = (p >> u32(8usize * c)) & 255u32
                var want = expected(x, y, c)
                if want == 256u32 {
                    if c == 0usize { want = 51u32 }
                    if c == 1usize { want = 77u32 }
                    if c == 2usize { want = 102u32 }
                }
                if !close(got, want) { os.exit(1i32) }
                if got != want { off += 1usize }
                c += 1usize
            }
            let o = over[y * W + x]
            if x >= 20usize && x < 50usize && y >= 10usize && y < 30usize {
                // red at half weight over the pixel: red (p + 255) / 2, the others p / 2
                let r = ((p & 255u32) + 255u32) / 2u32
                let g = ((p >> 8u32) & 255u32) / 2u32
                let b = ((p >> 16u32) & 255u32) / 2u32
                if !close(o & 255u32, r) || !close((o >> 8u32) & 255u32, g) || !close((o >> 16u32) & 255u32, b) { os.exit(2i32) }
            } else {
                if o != p { os.exit(3i32) }
            }
            x += 1usize
        }
        y += 1usize
    }
    if off > 24usize { os.exit(4i32) }
    ret ok
}
