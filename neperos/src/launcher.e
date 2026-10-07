// The NeperOS launcher presented over the compositor (C112, D2173). It opens an e.ui.window -- the
// compositor's shared surface on NeperOS -- renders the launcher's layout (wallpaper, top bar with
// status ticks, 8x5 icon grid) through e.gfx.scene over the e.gpu CPU backend into the window, and
// presents it with window.request_frame, which hands the frame to os.window_present: a blit into the
// shared surface and a signal to the compositor, which composites it to the display. Wired as the
// app of a compositor boot; its composited display is checked against a screendump golden. The same
// layout as neperos/src/ui_launcher.e (D2172), now on the real display. Needs the large arena.
use e.mem
use e.os
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.ui.window

const ROUTED: usize = 2usize
const NO_SLOT: usize = 99usize
const SENTINEL: usize = 65535usize
const LOW16: usize = 65535usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn fill(builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, red: f32, green: f32, blue: f32) {
    let pushed = scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(x, y, w, h), brush: paint.Brush { Solid: paint.Color { red: red, green: green, blue: blue, alpha: 1.0 } } } })
}

fn draw_launcher(builder: *scene.Builder) {
    // Wallpaper cover fill, top bar with five status ticks, 8x5 shaded icon tiles.
    fill(builder, 0.0, 0.0, 256.0, 256.0, 0.09, 0.11, 0.18)
    fill(builder, 0.0, 0.0, 256.0, 18.0, 0.05, 0.06, 0.10)
    var tick = 0usize
    while tick < 5usize {
        let tx = 256.0 - 10.0 - f32(tick) * 12.0
        fill(builder, tx, 5.0, 8.0, 8.0, 0.7, 0.75, 0.85)
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
            fill(builder, cx + 6.0, cy + 4.0, 36.0, 20.0, 0.3 + shade * 0.5, 0.5, 0.85 - shade * 0.4)
            c += 1usize
        }
        r += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("launcher gpu failed\n")
        ret ok
    }
    let (win, win_error) = window.open(a, device, window.Options { title: "launcher", width: 256u32, height: 256u32, min_width: 0u32, min_height: 0u32, resizable: false, transparent: false, mode: window.Mode.Windowed })
    if win_error != ok {
        say("launcher window failed\n")
        ret ok
    }
    var w = win
    let (drawable, drawable_error) = window.draw_target(&w)
    if drawable_error != ok {
        say("launcher target failed\n")
        ret ok
    }
    let (q, q_error) = gpu.queue(device)
    if q_error != ok {
        say("launcher queue failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok {
        say("launcher renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    draw_launcher(&builder)
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("launcher compile failed\n")
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, drawable, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok {
        say("launcher render failed\n")
        ret ok
    }
    if window.request_frame(&w) != ok {
        say("launcher present failed\n")
        ret ok
    }
    say("launcher presented\n")
    var listening = true
    while listening {
        let event = os.recv(ROUTED, NO_SLOT)
        if ((event >> 48usize) & LOW16) == SENTINEL { listening = false }
    }
    say("launcher done\n")
    ret ok
}
