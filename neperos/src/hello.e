// A hand-written app (C173): the smallest thing the app kit builds -- a dark screen, a card with a greeting and a
// counter of taps. It is packaged and signed by scripts/make_package.py (named Hello), kept in /apps, listed on the
// home grid after the system's icons, launched from its icon and removed again; the install fixtures (install_many,
// install_remove, install_update) use it as the "app somebody wrote" the generated ones stand beside.
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use appkit
use text

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
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

fn show(a: *mem.Arena, kit: *appkit.Kit, taps: usize) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    let ground = scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: appkit.ground_color(0.08, 0.09, 0.11, 1.0 - f32(kit.frame % 2usize) * 0.002) } } }
    if scene.push(&builder, ground) != ok { ret false }
    let faces = kit.faces
    let cream = paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 }
    let ink = paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 }
    let (card_path, card_error) = svg.rect_path(a, 36.0, 240.0, 340.0, 200.0, 24.0, 24.0)
    if card_error != ok { ret false }
    if scene.push(&builder, scene.Command { FillPath: scene.FillPath { path: card_path, brush: paint.Brush { Solid: cream } } }) != ok { ret false }
    let (box_a, error_a) = text.draw(a, &builder, faces.jost_bold, 30.0, "Hello", 64.0, 268.0, 0.0, 0u32, layout.Align.Start, ink)
    if error_a != ok { ret false }
    let (box_b, error_b) = text.draw(a, &builder, faces.jost, 17.0, "an app written by hand", 64.0, 320.0, 0.0, 0u32, layout.Align.Start, ink)
    if error_b != ok { ret false }
    var label = "Tap the card"
    if taps > 0usize { label = "Tapped" }
    let (box_c, error_c) = text.draw(a, &builder, faces.jost, 17.0, label, 64.0, 360.0, 0.0, 0u32, layout.Align.Start, ink)
    if error_c != ok { ret false }
    ret appkit.present(kit, &builder)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "hello")
    if kit_error != ok {
        say("hello open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("hello fonts absent\n")
        ret ok
    }
    var taps = 0usize
    if !show(a, &kit, taps) {
        say("hello present failed\n")
        ret ok
    }
    say("hello shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            say("hello home\n")
            appkit.leave()
            running = false
        } else {
            taps += 1usize
            say("hello tapped ")
            say_num(taps)
            say("\n")
            if !show(a, &kit, taps) { appkit.answer(appkit.ANSWER_NONE) }
        }
    }
    ret ok
}
