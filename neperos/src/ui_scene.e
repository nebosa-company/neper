// A NeperOS program that draws with the existing CPU rasterizer (C110, D2161): it brings the
// virtio-gpu display up (as the C108 server does), fills a background, fills a rectangle, and
// rasterizes an anti-aliased triangle with e.gfx.paint -- the same rasterizer e.gfx.scene uses --
// compositing it into the framebuffer, then flushes to the display. A QEMU screendump is checked
// against a golden; the rasterizer is pure, so the pixels are identical to a host render. This is
// the display-drawing foundation of the e.ui backend; surfaces, input routing and the widget layer
// follow.
use e.mem
use e.os
use virtio
use e.gfx.geometry
use e.gfx.paint

const AUX: usize = 548682334144usize
const TILE: usize = 96usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn read_device() -> virtio.Device {
    var device: virtio.Device = zero
    device.common = usize(os.load64(AUX))
    device.notify = usize(os.load64(AUX + 8usize))
    device.notify_multiplier = u32(os.load64(AUX + 16usize))
    virtio.pool_set(usize(os.load64(AUX + 24usize)), usize(os.load64(AUX + 32usize)))
    device.config = usize(os.load64(AUX + 40usize))
    ret device
}

// Fill a rectangle of the BGRA framebuffer `fb` (stride `stride` pixels) with one colour.
fn fill_rect(fb: usize, stride: usize, x0: usize, y0: usize, w: usize, h: usize, b: u8, g: u8, r: u8) {
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            let p = fb + ((y0 + y) * stride + (x0 + x)) * 4usize
            os.store8(p, b)
            os.store8(p + 1usize, g)
            os.store8(p + 2usize, r)
            os.store8(p + 3usize, 255u8)
            x += 1usize
        }
        y += 1usize
    }
}

// Blend `channel` over `old` by coverage `cov` in 0..1: old*(1-cov) + channel*cov.
fn blend(old: u8, channel: u8, cov: f32) -> u8 {
    let mixed = f32(usize(old)) * (1.0 - cov) + f32(usize(channel)) * cov
    ret u8(usize(mixed) & 255usize)
}

// Composite the TILE*TILE coverage mask into the framebuffer at (ox, oy) with colour (b, g, r).
fn blit(fb: usize, stride: usize, ox: usize, oy: usize, coverage: []f32, b: u8, g: u8, r: u8) {
    var y = 0usize
    while y < TILE {
        var x = 0usize
        while x < TILE {
            let cov = coverage[y * TILE + x]
            if cov > 0.0 {
                let p = fb + ((oy + y) * stride + (ox + x)) * 4usize
                os.store8(p, blend(os.load8(p), b, cov))
                os.store8(p + 1usize, blend(os.load8(p + 1usize), g, cov))
                os.store8(p + 2usize, blend(os.load8(p + 2usize), r, cov))
            }
            x += 1usize
        }
        y += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let device = read_device()
    let (gpu, begin_error) = virtio.gpu_begin(device)
    if begin_error != ok {
        say("ui gpu begin failed\n")
        ret ok
    }
    // Background, then a filled panel.
    fill_rect(gpu.fb, gpu.width, 0usize, 0usize, gpu.width, gpu.height, 40u8, 40u8, 60u8)
    fill_rect(gpu.fb, gpu.width, 80usize, 80usize, 240usize, 160usize, 200u8, 120u8, 60u8)
    // A triangle through the CPU rasterizer, composited with anti-aliased coverage.
    let (builder, builder_error) = geometry.path_builder(a, 4usize, 3usize)
    if builder_error != ok { ret builder_error }
    var b = builder
    let m = geometry.move_to(&b, geometry.Point { x: 12.0, y: 84.0 })
    let l1 = geometry.line_to(&b, geometry.Point { x: 48.0, y: 10.0 })
    let l2 = geometry.line_to(&b, geometry.Point { x: 84.0, y: 84.0 })
    let c = geometry.close_path(&b)
    let path = geometry.finish(&b)
    let (coverage, coverage_error) = mem.alloc[f32](a, TILE * TILE)
    if coverage_error != ok { ret coverage_error }
    let raster_error = paint.rasterize(path, paint.FillRule.NonZero, 1.0, TILE, TILE, coverage)
    if raster_error != ok {
        say("ui rasterize failed\n")
        ret ok
    }
    blit(gpu.fb, gpu.width, 360usize, 120usize, coverage, 90u8, 200u8, 120u8)
    let present_error = virtio.gpu_present(gpu)
    if present_error != ok {
        say("ui present failed\n")
        ret ok
    }
    say("ui scene flushed\n")
    var hold = 0usize
    while hold < 2000000000usize { hold += 1usize }
    ret ok
}
