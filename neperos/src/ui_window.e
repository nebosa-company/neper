// An e.ui windowed app on NeperOS (C110, D2169): it opens an e.ui.window -- which on NeperOS is the
// compositor's shared surface -- renders a scene into the window's drawable with e.gfx.scene over
// the e.gpu CPU backend, and presents it. window.request_frame reads the frame back and hands it to
// os.window_present, which blits it into the shared surface and signals the compositor; the
// compositor composites it to the display. This is the e.ui window backend presenting over the
// compositor, the piece D2168's headless harness left out. Needs the large arena (`bigarena`).
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

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("ui window gpu open failed\n")
        ret ok
    }
    let (win, win_error) = window.open(a, device, window.Options { title: "neper", width: 256u32, height: 256u32, min_width: 0u32, min_height: 0u32, resizable: false, transparent: false, mode: window.Mode.Windowed })
    if win_error != ok {
        say("ui window open failed\n")
        ret ok
    }
    var w = win
    let (drawable, drawable_error) = window.draw_target(&w)
    if drawable_error != ok {
        say("ui window target failed\n")
        ret ok
    }
    let (q, q_error) = gpu.queue(device)
    if q_error != ok {
        say("ui window queue failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok {
        say("ui window renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    let background = scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 256.0, 256.0), brush: paint.Brush { Solid: paint.Color { red: 0.12, green: 0.16, blue: 0.22, alpha: 1.0 } } } })
    let panel = scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(32.0, 48.0, 192.0, 96.0), brush: paint.Brush { Solid: paint.Color { red: 0.85, green: 0.6, blue: 0.2, alpha: 1.0 } } } })
    let accent = scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(32.0, 160.0, 96.0, 48.0), brush: paint.Brush { Solid: paint.Color { red: 0.3, green: 0.7, blue: 0.9, alpha: 1.0 } } } })
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("ui window compile failed\n")
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, drawable, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok {
        say("ui window render failed\n")
        ret ok
    }
    let frame_error = window.request_frame(&w)
    if frame_error != ok {
        say("ui window present failed\n")
        ret ok
    }
    say("ui window presented\n")
    // Receive the input the compositor routes to this surface, until the sentinel -- the same
    // convention a hand-written compositor app follows (an ungranted route returns the sentinel at
    // once in the display-only boot, so this exits right after presenting).
    var listening = true
    while listening {
        let event = os.recv(ROUTED, NO_SLOT)
        if ((event >> 48usize) & LOW16) == SENTINEL { listening = false }
    }
    say("ui window done\n")
    ret ok
}
