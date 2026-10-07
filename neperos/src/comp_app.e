// A NeperOS app that draws into a surface SHARED with the compositor (C110, D2162): it holds no
// display device, only the shared frame the kernel mapped (at vm.SHARED_FRAME_VA) and an endpoint
// to the compositor (slot 1). It draws a scene with the e.gfx.paint CPU rasterizer into the shared
// surface, then signals the compositor that the frame is ready. The compositor composites it to the
// display.
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint

const SHARED: usize = 548683907072usize
const SURFACE_W: usize = 256usize
const SURFACE_H: usize = 256usize
const COMP: usize = 1usize
const ROUTED: usize = 2usize
const NO_SLOT: usize = 99usize
const SENTINEL: usize = 65535usize
const LOW16: usize = 65535usize
const LOW32: usize = 4294967295usize
const TILE: usize = 96usize

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

fn fill_rect(x0: usize, y0: usize, w: usize, h: usize, b: u8, g: u8, r: u8) {
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            let p = SHARED + ((y0 + y) * SURFACE_W + (x0 + x)) * 4usize
            os.store8(p, b)
            os.store8(p + 1usize, g)
            os.store8(p + 2usize, r)
            os.store8(p + 3usize, 255u8)
            x += 1usize
        }
        y += 1usize
    }
}

fn blend(old: u8, channel: u8, cov: f32) -> u8 {
    let mixed = f32(usize(old)) * (1.0 - cov) + f32(usize(channel)) * cov
    ret u8(usize(mixed) & 255usize)
}

fn blit(ox: usize, oy: usize, coverage: []f32, b: u8, g: u8, r: u8) {
    var y = 0usize
    while y < TILE {
        var x = 0usize
        while x < TILE {
            let cov = coverage[y * TILE + x]
            if cov > 0.0 {
                let p = SHARED + ((oy + y) * SURFACE_W + (ox + x)) * 4usize
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
    fill_rect(0usize, 0usize, SURFACE_W, SURFACE_H, 60u8, 40u8, 30u8)
    fill_rect(24usize, 24usize, 208usize, 64usize, 200u8, 160u8, 90u8)
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
    if raster_error != ok { ret raster_error }
    blit(80usize, 120usize, coverage, 120u8, 90u8, 220u8)
    let sent = os.send(COMP, 1usize, NO_SLOT)
    // Receive the input events the compositor routes to this focused surface, until the sentinel.
    var listening = true
    while listening {
        let event = os.recv(ROUTED, NO_SLOT)
        let etype = (event >> 48usize) & LOW16
        if etype == SENTINEL {
            listening = false
        } else {
            say("app input ev ")
            say_num(etype)
            say(" ")
            say_num((event >> 32usize) & LOW16)
            say(" ")
            say_num(event & LOW32)
            say("\n")
        }
    }
    say("app done\n")
    ret ok
}
