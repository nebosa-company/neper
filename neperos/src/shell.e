// The NeperOS unified shell (C112, D2192): one process that IS the launcher, rendered over the real
// compositor AND interactive. It opens an e.ui.window (the compositor's shared surface), renders the
// launcher layout (wallpaper, top bar, 8x5 icon grid) through e.gfx.scene over the e.gpu CPU backend,
// and presents it (window.request_frame -> os.window_present: blit + signal, the compositor
// composites it to the display). Then it listens for input the compositor routes to it (slot 2, the
// C109 path); on the first key-down -- a tap on an icon -- it launches an app as a process
// (os.launch), waits for it (os.reap), and returns Home. This hosts the launcher on the display with
// LIVE tap input, built on the proven comp+input+app topology (one start_process, so it sidesteps the
// prodshell AUX heisenbug: the compositor reads its AUX at boot, before any runtime os.launch).
// Archive layout: [comp=0, shell=1, input=2, app=3]. Needs the large arena (`compositor bigarena`).
use e.mem
use e.os
use e.time
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.ui.window

const ROUTED: usize = 2usize
const NO_SLOT: usize = 99usize
const SENTINEL: usize = 65535usize
const LOW16: usize = 65535usize
const LOW32: usize = 4294967295usize
const EV_KEY: usize = 1usize
const APP_INDEX: usize = 3usize

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

fn say2(value: usize) {
    var two: [2]u8 = zero
    two[0usize] = u8(value / 10usize) + 48u8
    two[1usize] = u8(value % 10usize) + 48u8
    say(two[0usize..2usize])
}

fn fill(builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, red: f32, green: f32, blue: f32) {
    let pushed = scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(x, y, w, h), brush: paint.Brush { Solid: paint.Color { red: red, green: green, blue: blue, alpha: 1.0 } } } })
}

fn draw_digit(builder: *scene.Builder, font: []const u8, px: f32, py: f32, d: usize, s: f32) {
    var row = 0usize
    while row < 5usize {
        let bits = usize(font[d * 5usize + row])
        var col = 0usize
        while col < 3usize {
            if ((bits >> (2usize - col)) & 1usize) == 1usize {
                fill(builder, px + f32(col) * s, py + f32(row) * s, s, s, 0.85, 0.88, 0.95)
            }
            col += 1usize
        }
        row += 1usize
    }
}

fn draw_launcher(builder: *scene.Builder) {
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
        say("shell gpu failed\n")
        ret ok
    }
    let (win, win_error) = window.open(a, device, window.Options { title: "shell", width: 256u32, height: 256u32, min_width: 0u32, min_height: 0u32, resizable: false, transparent: false, mode: window.Mode.Windowed })
    if win_error != ok {
        say("shell window failed\n")
        ret ok
    }
    var w = win
    let (drawable, drawable_error) = window.draw_target(&w)
    if drawable_error != ok {
        say("shell target failed\n")
        ret ok
    }
    let (q, q_error) = gpu.queue(device)
    if q_error != ok {
        say("shell queue failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok {
        say("shell renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 256usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    draw_launcher(&builder)
    // Live status in the top bar: the current time, read directly from the wall clock through e.time
    // (os.clock -> the PL031 RTC) -- the status the shell shows, kept single-process (no separate
    // C111 status-server, which would be a second start_process and trip the AUX heisenbug).
    var hour = 0usize
    var minute = 0usize
    let (wall, wall_error) = time.now()
    if wall_error == ok && wall.nanos > 0i64 {
        let day = usize(wall.nanos / 1000000000i64) % 86400usize
        hour = day / 3600usize
        minute = (day % 3600usize) / 60usize
    }
    let font: [50]u8 = [50]u8{ 7u8, 5u8, 5u8, 5u8, 7u8, 2u8, 6u8, 2u8, 2u8, 7u8, 7u8, 1u8, 7u8, 4u8, 7u8, 7u8, 1u8, 7u8, 1u8, 7u8, 5u8, 5u8, 7u8, 1u8, 1u8, 7u8, 4u8, 7u8, 1u8, 7u8, 7u8, 4u8, 7u8, 5u8, 7u8, 7u8, 1u8, 2u8, 2u8, 2u8, 7u8, 5u8, 7u8, 5u8, 7u8, 7u8, 5u8, 7u8, 1u8, 7u8 }
    draw_digit(&builder, font[0usize..], 6.0, 5.0, hour / 10usize, 2.0)
    draw_digit(&builder, font[0usize..], 14.0, 5.0, hour % 10usize, 2.0)
    fill(&builder, 21.0, 7.0, 2.0, 2.0, 0.85, 0.88, 0.95)
    fill(&builder, 21.0, 11.0, 2.0, 2.0, 0.85, 0.88, 0.95)
    draw_digit(&builder, font[0usize..], 25.0, 5.0, minute / 10usize, 2.0)
    draw_digit(&builder, font[0usize..], 33.0, 5.0, minute % 10usize, 2.0)
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("shell compile failed\n")
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, drawable, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok {
        say("shell render failed\n")
        ret ok
    }
    if window.request_frame(&w) != ok {
        say("shell present failed\n")
        ret ok
    }
    say("shell presented\n")
    say("shell status ")
    say2(hour)
    say(":")
    say2(minute)
    say("\n")
    // Live input: the compositor routes each event here (slot 2). The first key-down is a tap on an
    // icon -- launch an app as a process, reap it, and return Home. Keep reading to the sentinel.
    var launched = false
    var listening = true
    while listening {
        let word = os.recv(ROUTED, NO_SLOT)
        let etype = (word >> 48usize) & LOW16
        if etype == SENTINEL {
            listening = false
        } else {
            let value = word & LOW32
            if etype == EV_KEY && value == 1usize && !launched {
                launched = true
                say("shell tap\n")
                let child = os.launch(APP_INDEX)
                say("shell launched app\n")
                let code = os.reap(child)
                say("shell app code ")
                say_num(code)
                say("\n")
                say("shell home\n")
            }
        }
    }
    say("shell done\n")
    ret ok
}
