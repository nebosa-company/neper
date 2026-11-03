// Round 86 (z): the Android font picker with the families the rig has a face for (Roboto, Segoe UI, Tahoma): the sample is drawn in
// the chosen family's own face, Bold is that face's bold, Italic a synthetic oblique (shear 1/4, Flutter's fake italic); a family with
// no face on the rig (SF Pro) shows its name alone. docs/ui/looks/{material,material-dark}/font_picker_faces.png. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.widget

fn noop_index(ctx: *void, value: usize) -> err { ret ok }
fn noop_size(ctx: *void, value: i64) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [6]str{ "Roboto, Italic", "Segoe UI, Regular", "Segoe UI, Italic", "Tahoma, Regular", "Tahoma, Bold", "SF Pro (no face): name only" }
    let all = [6]str{ "Roboto", "Segoe UI", "Tahoma", "SF Pro", "Cantarell", "Verdana" }
    let styles = [3]str{ "Regular", "Italic", "Bold" }
    let family_at = [6]usize{ 0usize, 1usize, 1usize, 2usize, 2usize, 3usize }
    let style_at = [6]usize{ 1usize, 0usize, 1usize, 0usize, 2usize, 0usize }
    var i = 0usize
    while i < 6usize {
        // the chosen family leads its list, so its row is in view
        var families: [6]str = zero
        families[0usize] = all[family_at[i]]
        var n = 1usize
        var k = 0usize
        while k < 6usize {
            if k != family_at[i] {
                families[n] = all[k]
                n += 1usize
            }
            k += 1usize
        }
        let (node, node_error) = control.font_picker(a, u64((i + 1usize) * 100usize), t, "Font", families[0usize..6usize], 0usize, styles[0usize..3usize], style_at[i], 14i64, "Quick brown fox", widget.Change[usize] { ctx: zero, invoke: noop_index }, widget.Change[usize] { ctx: zero, invoke: noop_index }, widget.Change[i64] { ctx: zero, invoke: noop_size }, 4u32, 220.0)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "font_picker_faces", cells: 6usize, columns: 3usize, cell_w: 250.0, cell_h: 300.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
