// The label in its looks: docs/ui/looks/<look>/label.png.
// Run from the repository root; see docs/ui/looks-howto.md.
//
// Twelve cells, each a real TcxLabel of the v3 dialogs (docs/ui/looks/ref/windows/dialogs): its DFM box, its Tahoma
// font, size, weight and colour. The Neper look draws the same strings in its own type scale. The cells with a
// reference crop (docs/ui/looks/ref/windows/label.png) are 0 to 9; 10 and 11 are states no capture shows.

use e.gfx.paint
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
        if t.tokens.profile == .Windows {
            let (word, word_error) = control.windows_label_faced(a, t, s.text, s.size, s.weight, style.hex(s.ink), s.underline, s.width, s.face)
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
        if s.centred { along = .Center }
        let box = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: along, cross: .Start, gap: 0.0 }, holder, parts[0usize..1usize])
        var drive: looks.Drive = .None
        if i == 12usize { drive = .Press }
        cells[i] = looks.Cell { caption: names(i), node: box, drive: drive }
        i += 1usize
    }
    ret (13usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "label", cells: 13usize, columns: 3usize, cell_w: 300.0, cell_h: 34.0, ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}
