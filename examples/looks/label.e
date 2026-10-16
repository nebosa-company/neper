// The label in its looks: docs/ui/looks/<look>/label.png.
// Run from the repository root; see docs/ui/looks-howto.md.
//
// Twelve cells, each a real TcxLabel of the v3 dialogs (docs/ui/looks/ref/windows/dialogs): its DFM box, its Tahoma
// font, size, weight and colour. The Neper look draws the same strings in its own type scale. The cells with a
// reference crop (docs/ui/looks/ref/windows/label.png) are 0 to 9; 10 and 11 are states no capture shows.

use e.gfx.paint
use e.math
use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

type Spec = struct { text: str, face: u32, size: f32, weight: u32, ink: u32, underline: bool, width: f32, box_w: f32, box_h: f32, centred: bool, wrap: bool }

fn spec(i: usize) -> Spec {
    if i == 0usize { ret Spec { text: "Row &Color: ", face: 8u32, size: 11.0, weight: 400u32, ink: 0u32, underline: false, width: 0.0, box_w: 91.0, box_h: 17.0, centred: false, wrap: false } }
    if i == 1usize { ret Spec { text: "Card:", face: 8u32, size: 11.0, weight: 400u32, ink: 0u32, underline: false, width: 0.0, box_w: 91.0, box_h: 17.0, centred: false, wrap: false } }
    if i == 2usize { ret Spec { text: "MTG Studio", face: 8u32, size: 13.0, weight: 700u32, ink: 0x33486Cu32, underline: false, width: 0.0, box_w: 291.0, box_h: 20.0, centred: false, wrap: false } }
    if i == 3usize { ret Spec { text: "C:\\Users\\gaddl\\Desktop\\New Deck.deck", face: 7u32, size: 12.0, weight: 400u32, ink: 0u32, underline: false, width: 0.0, box_w: 291.0, box_h: 17.0, centred: false, wrap: false } }
    if i == 4usize { ret Spec { text: "Last update on October 10, 2026", face: 8u32, size: 11.0, weight: 400u32, ink: 0x808080u32, underline: false, width: 0.0, box_w: 270.0, box_h: 17.0, centred: false, wrap: false } }
    if i == 5usize { ret Spec { text: "MTG Studio", face: 8u32, size: 21.0, weight: 700u32, ink: 0x336CCCu32, underline: false, width: 0.0, box_w: 202.0, box_h: 30.0, centred: true, wrap: false } }
    if i == 6usize { ret Spec { text: "version 3.235.0", face: 8u32, size: 13.0, weight: 700u32, ink: 0u32, underline: false, width: 0.0, box_w: 202.0, box_h: 22.0, centred: true, wrap: false } }
    if i == 7usize { ret Spec { text: "Send email to Support", face: 8u32, size: 11.0, weight: 400u32, ink: 0x336CCCu32, underline: true, width: 0.0, box_w: 205.0, box_h: 17.0, centred: true, wrap: false } }
    if i == 8usize { ret Spec { text: "https://mtg.studio", face: 8u32, size: 11.0, weight: 400u32, ink: 0x336CCCu32, underline: true, width: 0.0, box_w: 202.0, box_h: 17.0, centred: true, wrap: false } }
    if i == 9usize { ret Spec { text: "Select which edition cards' availability to be checked:", face: 7u32, size: 12.0, weight: 400u32, ink: 0u32, underline: false, width: 234.0, box_w: 234.0, box_h: 34.0, centred: false, wrap: true } }
    if i == 10usize { ret Spec { text: "Font Size:", face: 8u32, size: 11.0, weight: 400u32, ink: 0x6D6D6Du32, underline: false, width: 0.0, box_w: 91.0, box_h: 17.0, centred: false, wrap: false } }
    if i == 12usize { ret Spec { text: "Send email to Support", face: 8u32, size: 11.0, weight: 400u32, ink: 0x336CCCu32, underline: true, width: 0.0, box_w: 205.0, box_h: 17.0, centred: true, wrap: false } }
    ret Spec { text: "Interface (F2)", face: 8u32, size: 13.0, weight: 700u32, ink: 0u32, underline: false, width: 0.0, box_w: 150.0, box_h: 20.0, centred: false, wrap: false }
}

// The sub-pixel phase of the underline in the capture, per cell: Options draws it two rows of 62 % and 38 %, About of 41 % and 59 % (the URL 39 % and 61 %)
// (both DPI-scaled forms), measured on the capture's rows; the other forms' labels have none.
fn phase_of(i: usize) -> f32 {
    if i == 0usize { ret 0.38 }
    if i == 7usize || i == 12usize { ret 0.59 }
    if i == 8usize { ret 0.61 }
    ret 0.0
}

fn names(i: usize) -> str {
    let n = [13]str{ "Normal, mnemonic", "Normal", "Bold -13, #33486C", "Path", "Gray (clGray)", "Bold -21, #336CCC", "Bold -13", "Hot-link", "Hot-link, URL", "Word wrap", "Disabled (guess)", "Bold -13 (header)", "Hot-link, pressed" }
    ret n[i]
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    var i = 0usize
    while i < 13usize {
        let s = spec(i)
        var node: widget.Node = zero
        var node_error: err = ok
        var centre_w: f32 = 0.0
        if s.centred { centre_w = s.box_w }
        if t.tokens.profile == .Windows {
            var shown_ink = style.hex(s.ink)
            // round 10: the light disabled label is the native static's #A0A0A0 (docs/ui/looks/ref/windows-native/light/label-disabled)
            if i == 10usize { shown_ink = style.hex(0xA0A0A0u32) }
            let (word, word_error) = control.windows_label_faced(a, t, s.text, s.size, s.weight, shown_ink, s.underline, s.width, s.face, centre_w, phase_of(i), false)
            node = word
            node_error = word_error
        } else {
            var options = control.text_options()
            options.role = .Body
            options.wrap = .None
            if s.wrap { options.wrap = .Word }
            if s.weight == 700u32 { options.weight = 700u32 }
            var ink = style.hex(s.ink)
            if s.ink == 0u32 { ink = style.color(t.tokens, .Text) }
            let (word, word_error) = control.colored_text(a, u64(i + 1usize), s.text, t, options, ink)
            node = word
            node_error = word_error
        }
        if node_error != ok { ret (0usize, node_error) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 1usize)
        if parts_error != ok { ret (0usize, parts_error) }
        parts[0usize] = node
        var holder = control.sized_style(s.box_w, s.box_h)
        holder.overflow = .Clip
        var along: ui_layout.MainAlign = .Start
        // the Windows label centres itself on whole pixels (box_w), the Neper text is centred by the box
        if s.centred && t.tokens.profile != .Windows { along = .Center }
        let box = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: along, cross: .Start, gap: 0.0 }, holder, parts[0usize..1usize])
        // looks5: the box sits on whole pixels in its cell (the capture crops are placed at floor((cell - box) / 2)), so a
        // text is not blurred across two rows by a half pixel offset
        var cell = box
        if t.tokens.profile != .Neper {
            let (placed, placed_error) = mem.alloc[widget.Node](a, 1usize)
            if placed_error != ok { ret (0usize, placed_error) }
            placed[0usize] = widget.positioned(0u64, math.floor[f32]((300.0 - s.box_w) * 0.5), math.floor[f32]((34.0 - s.box_h) * 0.5), style.defaults(), control.mem_one_node(a, box))
            cell = widget.stack(0u64, control.sized_style(300.0, 34.0), placed[0usize..1usize])
        }
        var drive: looks.Drive = .None
        if i == 12usize { drive = .Press }
        cells[i] = looks.Cell { caption: names(i), node: cell, drive: drive }
        i += 1usize
    }
    ret (13usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "label", cells: 13usize, columns: 3usize, cell_w: 300.0, cell_h: 34.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
