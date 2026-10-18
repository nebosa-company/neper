// The Linux look's progress bar and spinner against the real GTK 4.14 / libadwaita 1.5 ones: docs/ui/looks/linux[-dark]/progress_bar.png.
// Progress at 0, 40 and 100 %, the OSD bar, the level bar (an empty trough here), the spinner and the scale in five states, each placed on the whole pixel the
// reference crop (docs/ui/looks/ref/linux, composed by scripts/linux_cmp_l3.py) sits on. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_change(ctx: *void, value: f32) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [12]str{ "progress 0", "progress 40", "progress 100", "osd 60", "level bar", "spinner", "scale", "scale hover", "scale pressed", "scale focus", "scale disabled", "scale marks" }
    var i = 0usize
    while i < 12usize {
        var options = control.progress_options()
        let key = u64((i + 1usize) * 10usize)
        var node: widget.Node = zero
        var w: f32 = 200.0
        var h: f32 = 8.0
        var drive: looks.Drive = .None
        if i >= 6usize {
            w = 200.0
            h = 34.0
            let change = widget.Change[f32] { ctx: zero, invoke: noop_change }
            if i == 11usize {
                h = 47.0
                let (marked, marked_error) = control.slider_marked(a, key, t, "Scale", 40.0, 0.0, 100.0, 0.0, change, true)
                if marked_error != ok { ret (0usize, marked_error) }
                node = marked
            } else {
                let (made, made_error) = control.slider(a, key, t, "Scale", 40.0, 0.0, 100.0, 0.0, change, i != 10usize)
                if made_error != ok { ret (0usize, made_error) }
                node = made
            }
            if i == 7usize { drive = .Hover }
            if i == 8usize { drive = .Press }
            if i == 9usize { drive = .Focus }
        } else if i == 5usize {
            w = 32.0
            h = 32.0
            options.phase = 0.0
            let (made, made_error) = control.progress_ring_of(a, key, t, "Loading", 0.0, true, 32.0, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        } else {
            var value: f32 = 0.0
            if i == 1usize { value = 0.4 }
            if i == 2usize { value = 1.0 }
            if i == 3usize {
                value = 0.6
                options.full_bleed = true
                h = 2.0
            }
            let (made, made_error) = control.progress_bar_of(a, key, t, "Progress", value, false, 200.0, options)
            if made_error != ok { ret (0usize, made_error) }
            node = made
        }
        let x = f32(usize(210.0 - w) / 2usize)
        let y = f32(usize(47.0 - h) / 2usize)
        let holder = widget.positioned(0u64, x, y, control.sized_style(210.0, 47.0), control.widget_one_of(a, node))
        cells[i] = looks.Cell { caption: names[i], node: widget.stack(0u64, control.sized_style(210.0, 47.0), control.widget_one_of(a, holder)), drive: drive }
        i += 1usize
    }
    ret (12usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "progress_bar", cells: 12usize, columns: 3usize, cell_w: 210.0, cell_h: 47.0, ctx: zero, build: build }
    ret looks.run_linux(a, &sheet)
}
