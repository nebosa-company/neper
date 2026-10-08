// Plumbing for the full-screen apps the NeperOS shell launches (D2205). An app is a process the
// kernel starts with the compositor's shared frame mapped, a send capability on the frame endpoint
// (slot 1), a receive capability on the routed-input endpoint (slot 2) and the five lunar fonts as
// args[first .. first + 4]. This kit opens the window, lays a scene out in dp (412 wide, 3.1x to the
// panel's pixels), turns the compositor's routed events into taps, and speaks the compositor's
// lockstep protocol: after forwarding each input event the compositor takes one answer -- 1 (a frame
// signal, which `request_frame` sends), 0 (nothing to show), or 4 (a frame will come later, from the
// shell, once this app has left).
use e.mem
use e.os
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.ui.window
use text

const ROUTED: usize = 2usize
const FRAME: usize = 1usize
const NO_SLOT: usize = 99usize
const SENTINEL: usize = 65535usize
const LOW16: usize = 65535usize
const LOW32: usize = 4294967295usize
const EV_KEY: usize = 1usize
const EV_ABS: usize = 3usize
const EV_TICK: usize = 241usize
const BTN_LEFT: usize = 272usize
const ABS_X: usize = 0usize
const ABS_Y: usize = 1usize

// The answers to a routed event.
const ANSWER_NONE: usize = 0usize
const ANSWER_LATER: usize = 4usize

type Kit = struct { device: *gpu.Device, win: window.Window, drawable: scene.Target, renderer: scene.Renderer, faces: text.Faces, has_fonts: bool, scale: f32, logical_h: f32, previous: scene.SceneId, has_previous: bool, x: usize, y: usize, frame: usize, frame_mark: usize }

// A tap, in dp, or the end of the event stream.
// A tick (type 0xF1, every 500 ms when the input server has ticks on) carries the monotonic
// milliseconds. The caller answers a tick like a tap: a frame if the screen changed, else `answer(ANSWER_NONE)`.
type Tap = struct { x: f32, y: f32, ended: bool, tick: bool, ms: usize }

fn open(a: *mem.Arena, args: []str, first_font: usize, title: str) -> (Kit, err) {
    var kit: Kit = zero
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok { ret (kit, open_error) }
    let (win, win_error) = window.open(a, device, window.Options { title: title, width: u32(os.SURFACE_W), height: u32(os.SURFACE_H), min_width: 0u32, min_height: 0u32, resizable: false, transparent: false, mode: window.Mode.Windowed })
    if win_error != ok { ret (kit, gpu.Unsupported) }
    var w = win
    let (drawable, drawable_error) = window.draw_target(&w)
    if drawable_error != ok { ret (kit, gpu.Unsupported) }
    let (q, q_error) = gpu.queue(device)
    if q_error != ok { ret (kit, q_error) }
    // (D2242) The renderer keeps its own arena for what it allocates and holds on to (its scenes, its glyph
    // cache), apart from the program arena, so that arena can be given back at the start of every frame.
    let (render_store, render_store_error) = mem.alloc[u8](a, 134217728usize)
    if render_store_error != ok { ret (kit, render_store_error) }
    let (render_box, render_box_error) = mem.alloc[mem.Arena](a, 1usize)
    if render_box_error != ok { ret (kit, render_box_error) }
    render_box[0usize] = mem.arena_from(render_store)
    let (renderer_value, renderer_error) = scene.renderer(&render_box[0usize], device, q, 3u32, 1u32)
    if renderer_error != ok { ret (kit, renderer_error) }
    var renderer = renderer_value
    let (faces, has_fonts) = text.load_faces(&renderer, args, first_font)
    let scale = f32(os.SURFACE_W) / 412.0
    kit = Kit { device: device, win: w, drawable: drawable, renderer: renderer, faces: faces, has_fonts: has_fonts, scale: scale, logical_h: f32(os.SURFACE_H) / scale, previous: zero, has_previous: false, x: 0usize, y: 0usize, frame: 0usize, frame_mark: 0usize }
    // (D2242) Whatever an app allocates after this point is for one frame: `begin` gives it back.
    kit.frame_mark = mem.mark(a)
    ret (kit, ok)
}

// A builder whose scene is laid out in dp: a Save and the dp-to-pixel scale come first.
fn begin(a: *mem.Arena, kit: *Kit) -> (scene.Builder, err) {
    // The scene drawn before is released first, so nothing refers to the memory that is given back; then the
    // arena returns to where it stood when the app opened (D2242), so a frame costs nothing for the next.
    if kit.has_previous {
        let released = scene.release_scene(&kit.renderer, kit.previous)
        kit.has_previous = false
    }
    mem.reset(a, kit.frame_mark)
    let (builder_value, builder_error) = scene.builder(a, 4096usize)
    if builder_error != ok { ret (zero, builder_error) }
    var builder = builder_value
    let save: scene.Command = .Save
    try scene.push(&builder, save)
    try scene.push(&builder, scene.Command { Transform: geometry.transform_scale(kit.scale, kit.scale) })
    ret (builder, ok)
}

// Finish `builder`, compile and render it into the window and present it (the compositor takes the
// frame signal as its answer to the event being handled). The scene before it is released.
fn present(kit: *Kit, builder: *scene.Builder) -> bool {
    let restore: scene.Command = .Restore
    if scene.push(builder, restore) != ok {
        say("appkit push failed\n")
        ret false
    }
    // The scene drawn before this one is released first, so the renderer has nothing to compare it
    // with and redraws the whole frame: its damage tracking skipped a card under changed text.
    if kit.has_previous {
        let released = scene.release_scene(&kit.renderer, kit.previous)
        kit.has_previous = false
    }
    let (scene_id, compile_error) = scene.compile(&kit.renderer, scene.finish(builder))
    if compile_error != ok {
        say("appkit compile failed\n")
        ret false
    }
    let render_error = scene.render(&kit.renderer, scene_id, kit.drawable, geometry.Size { width: f32(os.SURFACE_W), height: f32(os.SURFACE_H) })
    if render_error != ok {
        if render_error == scene.OutOfMemory { say("appkit: out of memory\n") }
        if render_error == scene.TooLarge { say("appkit: too large\n") }
        if render_error == scene.Invalid { say("appkit: invalid\n") }
        say("appkit render failed\n")
        ret false
    }
    kit.previous = scene_id
    kit.frame += 1usize
    kit.has_previous = true
    ret window.request_frame(&kit.win) == ok
}

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
}

fn answer(value: usize) {
    let sent = os.send(FRAME, value, NO_SLOT)
}

// The next tap, in dp. Every other routed event is answered here with "nothing to show". The caller
// answers the tap itself: by presenting a frame, or with `answer(ANSWER_NONE)`.
fn next_tap(kit: *Kit) -> Tap {
    while true {
        let word = os.recv(ROUTED, NO_SLOT)
        let etype = (word >> 48usize) & LOW16
        if etype == SENTINEL { ret Tap { x: 0.0, y: 0.0, ended: true, tick: false, ms: 0usize } }
        let code = (word >> 32usize) & LOW16
        let value = word & LOW32
        if etype == EV_TICK { ret Tap { x: 0.0, y: 0.0, ended: false, tick: true, ms: value } }
        if etype == EV_ABS && code == ABS_X { kit.x = value }
        if etype == EV_ABS && code == ABS_Y { kit.y = value }
        if etype == EV_KEY && code == BTN_LEFT && value == 1usize {
            ret Tap { x: f32(kit.x) * 412.0 / 32768.0, y: f32(kit.y) * kit.logical_h / 32768.0, ended: false, tick: false, ms: 0usize }
        }
        answer(ANSWER_NONE)
    }
    ret Tap { x: 0.0, y: 0.0, ended: true, tick: false, ms: 0usize }
}

// Leave the app: tell the compositor a frame will follow (the shell redraws Home once this process
// is gone), then the caller returns from main.
fn leave() {
    answer(ANSWER_LATER)
}
