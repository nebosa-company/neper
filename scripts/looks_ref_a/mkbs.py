# Writes examples/looks/button_states.e or button_hover.e from the tables genbs.py just made (bs_tables.txt, deleted after).
#   python -I scripts/looks_ref_a/genbs.py states && python -I scripts/looks_ref_a/mkbs.py states
import os,sys
HERE=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,HERE)
from bspec import SPEC
SHEET=sys.argv[1] if len(sys.argv)>1 else 'states'
tables=open(os.path.join(HERE,'bs_tables.txt')).read()
n=sum(1 for r in SPEC if (r[7]=='H')==(SHEET=='hover'))+(5 if SHEET=='states' else 0)
what='state' if SHEET=='states' else 'hover'
src='''// Every captured button %(what)s of the live v3 grabs (docs/ui/looks/ref/windows/states/%(files)s), one cell each, in the
// Windows look: the box is cropped from the grab with 5 px of its dialog around it, and the cell holds the same
// surroundings (the dialog's own face: the Filter page is #F9F9F9, the others #F0F0F0) so a soft ring row that blends
// with the dialog shows the same pixels. %(drives)s The tables below are generated from the capture list by
// scripts/looks_ref_a/genbs.py and mkbs.py: caption, caption word, control rect size, drive, default, enabled, dialog face, picture,
// focused, and the sub-pixel shift (dx, dy) of the four DPI-scaled forms (Options, Deck Properties, Deck Legality, About), whose
// buttons v3 draws resampled by that offset: the phase fitted to each capture (scripts/looks_ref_a/fitshift.py), a crisp button moved by it.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn margin_px() -> f32 { ret 5.0 }
fn noop_submit(ctx: *void) -> err { ret ok }

%(tables)s

// The holder of a cell: odd wide and even tall (so the cell centres it on whole pixels in 133 x 40), the dialog face
// behind, the visible box (the control rect less 2 wide, 1 tall) at (margin, margin).
fn holder_of(a: *mem.Arena, t: *const control.Theme, node: widget.Node, vis_w: f32, vis_h: f32, face: u32) -> (widget.Node, err) {
    var hw = vis_w + margin_px() * 2.0
    if u32(hw) %% 2u32 == 0u32 { hw += 1.0 }
    var hh = vis_h + margin_px() * 2.0
    if u32(hh) %% 2u32 == 1u32 { hh += 1.0 }
    var holder = control.sized_style(hw, hh)
    if t.tokens.profile == .Windows { holder.background = paint.Brush { Solid: style.hex(face) } }
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = widget.positioned(0u64, margin_px(), margin_px(), style.defaults(), control.mem_one_node(a, node))
    ret (widget.stack(0u64, holder, inner[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    let action = &actions[0usize]
    let captions = t_captions()
    let words = t_words()
    let widths = t_widths()
    let heights = t_heights()
    let drives = t_drives()
    let defaults = t_defaults()
    let enabled = t_enabled()
    let faces = t_faces()
    let glyphs = t_glyphs()
    let focused = t_focused()
    let shift_x = t_shift_x()
    let shift_y = t_shift_y()
    var i = 0usize
    while i < %(n)d {
        var options = control.button_options()
        options.width = widths[i]
        options.height = heights[i]
        options.enabled = enabled[i]
        options.shift_x = shift_x[i]
        options.shift_y = shift_y[i]
        options.focused = focused[i]
        if defaults[i] { options.variant = .Default }
        var node: widget.Node = zero
        var node_error: err = ok
        if glyphs[i] {
            let (picture, picture_error) = control.button_with_glyph(a, u64(i + 1usize), t, .Refresh, words[i], action, options)
            node = picture
            node_error = picture_error
        } else {
            let (plain, plain_error) = control.button(a, u64(i + 1usize), t, words[i], action, options)
            node = plain
            node_error = plain_error
        }
        if node_error != ok { ret (0usize, node_error) }
        let (held, held_error) = holder_of(a, t, node, widths[i] - 2.0, heights[i] - 1.0, faces[i])
        if held_error != ok { ret (0usize, held_error) }
        var drive: looks.Drive = .None
        if drives[i] == 1u8 { drive = .Press }
        if drives[i] == 2u8 { drive = .Focus }
        if drives[i] == 3u8 { drive = .Hover }
        cells[i] = looks.Cell { caption: captions[i], node: held, drive: drive }
        i += 1usize
    }
    ret (%(n)d, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "button_%(sheet)s", cells: %(n)dusize, columns: 4usize, cell_w: 133.0, cell_h: 40.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
'''%dict(what=what,files=('button-*' if SHEET=='states' else 'hover-button-*'),drives=('Pressed and focused cells are driven (Drive.Press, Drive.Focus), the rest are plain; the last five cells have no capture (the ring at 75x32 and 125x40).' if SHEET=='states' else 'Every cell is driven with the pointer on it (Drive.Hover; a pressed one with the button held).'),tables=tables,n=n,sheet=SHEET)
open(os.path.join(HERE,'..','..','examples','looks','button_%s.e'%SHEET),'w',newline=chr(10)).write(src)
os.remove(os.path.join(HERE,'bs_tables.txt'))
print('wrote button_%s.e with %d cells'%(SHEET,n))
