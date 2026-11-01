// Round 62 (g): whole-window sheets in all ten looks. An overlay that lives at the window's edge (a side sheet, a bottom
// sheet) or covers it (a dialog's scrim) cannot be shown in a sheet's cell, which crops the cell out of the window, so
// this renders one window of `width` x `height` logical px per look and scale and writes it whole to
// docs/ui/looks/<look>/<name>[@1.5x].png. The overlays slide and fade in, so the frames run 700 ms before the state is driven.

use e.fs
use e.gfx.image
use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.testing
use e.ui.widget

// `build` fills cells[0] only. `drive` is the state to show (None is at rest); `target` is the key of the element the pointer
// goes to for Hover, Press and Focus (0: the window's top left corner, which is the scrim of a modal overlay).
type Spec = struct { name: str, width: f32, height: f32, ctx: *void, build: looks.Build, drive: looks.Drive, target: widget.Key }

fn look_at(i: usize) -> looks.Look {
    if i == 1usize { ret looks.Look.NeperDark }
    if i == 2usize { ret looks.Look.Windows }
    if i == 3usize { ret looks.Look.WindowsDark }
    if i == 4usize { ret looks.Look.Linux }
    if i == 5usize { ret looks.Look.LinuxDark }
    if i == 6usize { ret looks.Look.Cupertino }
    if i == 7usize { ret looks.Look.CupertinoDark }
    if i == 8usize { ret looks.Look.Material }
    if i == 9usize { ret looks.Look.MaterialDark }
    ret looks.Look.Neper
}

// One frame at `step` (100 ms each): the spec's node on the look's background, rebuilt because a control reads its
// interaction state when it is built.
fn frame(rig: *looks.Rig, t: *const control.Theme, s: *const Spec, step: i64) -> (image.Image, err) {
    let fa = looks.begin(rig)
    let (cells, cells_error) = mem.alloc[looks.Cell](fa, 1usize)
    if cells_error != ok { ret (zero, cells_error) }
    let (count, build_error) = s.build(s.ctx, fa, t, cells)
    if build_error != ok { ret (zero, build_error) }
    var page = style.defaults()
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    page.width = style.Length { Percent: 100.0 }
    page.height = style.Length { Percent: 100.0 }
    let (held, held_error) = mem.alloc[widget.Node](fa, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = cells[0usize].node
    let (shot, shot_error) = looks.shoot(rig, widget.box(0u64, page, held[0usize..1usize]), step)
    ret (shot, shot_error)
}

fn one_window(rig: *looks.Rig, s: *const Spec, path: str) -> err {
    let t = looks.theme_of(rig)
    var step = 0i64
    var shot: image.Image = zero
    while step < 7i64 {
        let (made, made_error) = frame(rig, &t, s, step)
        if made_error != ok { ret made_error }
        shot = made
        step += 1i64
        if step < 7i64 { looks.drop_shot(rig) }
    }
    if s.drive != .None {
        var x: f32 = 2.0
        var y: f32 = 2.0
        if s.target != 0u64 {
            let (bounds, found) = widget.bounds_for_key(&rig.runtime, s.target)
            if found {
                x = bounds.x + bounds.width * 0.5
                y = bounds.y + bounds.height * 0.5
            }
        }
        try looks.drive_cell(rig, s.drive, x, y)
        var after = 0usize
        while after < 3usize {
            looks.drop_shot(rig)
            let (made, made_error) = frame(rig, &t, s, step)
            if made_error != ok { ret made_error }
            shot = made
            step += 1i64
            // a hover that opens or moves something lands on the layout the frame before built
            if after == 0usize && (s.drive == .Hover || s.drive == .Settle) { try testing.hover(&rig.harness, x, y) }
            after += 1usize
        }
    }
    ret looks.write_png(rig.a, path, looks.const_view(shot))
}

// Renders `s` in the ten looks at 100 % and 150 %.
fn run(a: *mem.Arena, s: *const Spec) -> err {
    try looks.read_linux_fonts(a)
    var scale_index = 0usize
    while scale_index < 2usize {
        var scale: f32 = 1.0
        if scale_index == 1usize { scale = 1.5 }
        var look_index = 0usize
        while look_index < 10usize {
            let look = look_at(look_index)
            let ra = looks.rig_scope(a)
            let (rig, open_error) = looks.open(ra, s.width, s.height, scale)
            if open_error != ok { ret open_error }
            looks.set_look(rig, look)
            let (folder, folder_error) = looks.path_of(ra, looks.look_dir(look), "", "", 1.0, "")
            if folder_error != ok { ret folder_error }
            try fs.make_dirs(ra, folder)
            let (path, path_error) = looks.path_of(ra, looks.look_dir(look), s.name, "", scale, ".png")
            if path_error != ok { ret path_error }
            try one_window(rig, s, path)
            looks.close_rig(rig)
            look_index += 1usize
        }
        scale_index += 1usize
    }
    ret ok
}
