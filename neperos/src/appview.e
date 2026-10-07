// Shows an app face on the display (D2197). The Clock, Calculator, Tasks and Settings apps render
// their 256x256 face offscreen and print a hash, which is all a `gpu bigarena` boot can use. When one
// is started as the app of a compositor boot (`compositor bigarena`, the kernel names that process
// "app"), it also renders the same compiled scene into an e.ui.window and presents it, so the
// compositor composites the face to the screen. Under any other name -- the gpu boot, the host
// harness -- `show` does nothing, so the hashes and goldens are untouched.
use e.mem
use e.os
use e.gpu
use e.gfx.geometry
use e.gfx.scene
use e.ui.window

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

// The compositor boot starts its app under the name "app".
fn wanted(args: []str) -> bool {
    if args.len == 0usize { ret false }
    let name = args[0usize]
    ret name.len == 3usize && name[0usize] == 97u8 && name[1usize] == 112u8 && name[2usize] == 112u8
}

// A renderer keeps the last scene it drew and skips an identical redraw, so the face is compiled into
// a fresh renderer of its own for the window rather than reusing the one that drew the offscreen frame.
fn show(a: *mem.Arena, device: *gpu.Device, list: scene.DisplayList, args: []str) {
    if !wanted(args) { ret }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok { ret }
    var renderer = renderer_value
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { ret }
    let (win, win_error) = window.open(a, device, window.Options { title: "app", width: 256u32, height: 256u32, min_width: 0u32, min_height: 0u32, resizable: false, transparent: false, mode: window.Mode.Windowed })
    if win_error != ok {
        say("appview open failed\n")
        ret
    }
    var w = win
    let (drawable, drawable_error) = window.draw_target(&w)
    if drawable_error != ok {
        say("appview target failed\n")
        ret
    }
    if scene.render(&renderer, scene_id, drawable, geometry.Size { width: 256.0, height: 256.0 }) != ok {
        say("appview render failed\n")
        ret
    }
    if window.request_frame(&w) != ok { say("appview present failed\n") }
    say("appview presented\n")
}
