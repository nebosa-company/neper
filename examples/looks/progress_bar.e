// The progress bar in its states under every look: docs/ui/looks/<look>/progress_bar.png.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn one(a: *mem.Arena, t: *const control.Theme, key: widget.Key, value: f32, indeterminate: bool, text: bool, phase: f32, tone: control.ProgressTone) -> (widget.Node, err) {
    var options = control.progress_options()
    options.text = text
    options.phase = phase
    options.tone = tone
    let (node, node_error) = control.progress_bar_of(a, key, t, "Importing cards", value, indeterminate, 150.0, options)
    ret (node, node_error)
}

// Twelve cells: empty, 30 %, 50 % and full with the percent shown (v3 cxtsText), 60 % and 5 % without
// text, 99 % with text, and the marquee at three points of its travel, then paused and error tones (native capture colours).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [12]str{ "0 %, text", "30 %, text", "50 %, text", "100 %, text", "60 %, no text", "5 %, text", "99 %, text", "Marquee 10 %", "Marquee 50 %", "Marquee 90 %", "Paused 60 %", "Error 60 %" }
    let values = [12]f32{ 0.0, 0.3, 0.5, 1.0, 0.6, 0.05, 0.99, 0.0, 0.0, 0.0, 0.6, 0.6 }
    var i = 0usize
    while i < 12usize {
        let marquee = i >= 7usize && i < 10usize
        var phase: f32 = 0.0 - 1.0
        if marquee { phase = f32(i - 7usize) * 0.4 + 0.1 }
        var tone: control.ProgressTone = .Active
        if i == 10usize { tone = .Paused }
        if i == 11usize { tone = .Error }
        let (node, node_error) = one(a, t, u64(i + 1usize), values[i], marquee, i != 4usize && i < 10usize && !marquee, phase, tone)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (12usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "progress_bar", cells: 12usize, columns: 4usize, cell_w: 160.0, cell_h: 32.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
