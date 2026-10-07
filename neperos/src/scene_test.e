// A NeperOS program that renders an e.gfx.scene through e.gpu's CPU backend (C110, D2167): it opens
// the CPU device, an offscreen target and a scene renderer, builds a two-rectangle scene, renders
// it, reads the pixels back and prints a deterministic fold hash of them. The whole pipeline is
// e.ui's drawing path (e.ui -> e.gfx.scene -> e.gpu CPU backend); the hash is the same as a host
// render of the same scene, since the rasterizer is pure. Needs the large arena (`bigarena`).
use e.mem
use e.os
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene

const AUX: usize = 548682334144usize
const SIDE: u32 = 128u32

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

fn main(a: *mem.Arena, args: []str) -> err {
    say("scene start\n")
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("scene gpu open failed\n")
        ret ok
    }
    say("scene opened\n")
    let (queue, queue_error) = gpu.queue(device)
    if queue_error != ok {
        say("scene queue failed\n")
        ret ok
    }
    say("scene queued\n")
    let (frames, target_error) = gpu.open_target(queue, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, SIDE, SIDE, gpu.Format.Bgra8)
    if target_error != ok {
        say("scene target failed\n")
        ret ok
    }
    say("scene targeted\n")
    let (drawable, drawable_error) = scene.target_of(a, frames)
    if drawable_error != ok {
        say("scene drawable failed\n")
        ret ok
    }
    say("scene drawable\n")
    let (renderer_value, renderer_error) = scene.renderer(a, device, queue, 1u32, 1u32)
    if renderer_error != ok {
        say("scene renderer failed\n")
        ret ok
    }
    say("scene renderer\n")
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    let background = scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 128.0, 128.0), brush: paint.Brush { Solid: paint.Color { red: 0.15, green: 0.15, blue: 0.25, alpha: 1.0 } } } })
    let panel = scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(24.0, 32.0, 72.0, 48.0), brush: paint.Brush { Solid: paint.Color { red: 0.8, green: 0.55, blue: 0.2, alpha: 1.0 } } } })
    say("scene built\n")
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("scene compile failed\n")
        ret ok
    }
    say("scene compiled\n")
    let render_error = scene.render(&renderer, scene_id, drawable, geometry.Size { width: 128.0, height: 128.0 })
    if render_error != ok {
        say("scene render failed\n")
        ret ok
    }
    say("scene rendered\n")
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok {
        say("scene presented failed\n")
        ret ok
    }
    let (pixels, pixels_error) = mem.alloc[u32](a, usize(SIDE) * usize(SIDE))
    if pixels_error != ok { ret pixels_error }
    let read_error = gpu.read_image(queue, image, pixels)
    if read_error != ok {
        say("scene read failed\n")
        ret ok
    }
    var hash = 2166136261usize
    var i = 0usize
    while i < pixels.len {
        hash = ((hash ^ usize(pixels[i])) * 16777619usize) & 4294967295usize
        i += 1usize
    }
    say("scene hash ")
    say_num(hash)
    say("\n")
    ret ok
}
