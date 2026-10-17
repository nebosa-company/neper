// The Windows dark look beside the native Windows 11 dark captures, third sheet (round 13): split and picture buttons, then the lists
// (check list, list box, list view, tree) and popup menus, each at the capture's own geometry; scripts/looks_strict13.py (SHEET3) diffs every one.
// Only windows-dark matters: run with NEPER_LOOKS_OUT=<scratch> and copy <scratch>/windows-dark/native_dark2.png into docs/ui/looks/windows-dark.
// Run from the repository root; see docs/ui/looks-howto.md.

use e.mem
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

fn cell_w() -> f32 { ret 260.0 }
fn cell_h() -> f32 { ret 200.0 }

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

// `node` at a whole pixel (x, y) of a cell-sized holder.
fn placed(a: *mem.Arena, node: widget.Node, x: f32, y: f32) -> (widget.Node, err) {
    let (inner, inner_error) = mem.alloc[widget.Node](a, 1usize)
    if inner_error != ok { ret (zero, inner_error) }
    inner[0usize] = widget.positioned(0u64, x, y, style.defaults(), control.mem_one_node(a, node))
    ret (widget.stack(0u64, sized(cell_w(), cell_h()), inner[0usize..1usize]), ok)
}

fn noop_submit(ctx: *void) -> err { ret ok }

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    control.set_caret_hidden(true)
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (0usize, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    var at = 0usize
    // 0 to 2: button-split (rest), -pressed, -disabled: 150 x 32 (face 148 x 30 at (1, 1)); here the face at (20, 20)
    var i = 0usize
    while i < 3usize {
        var options = control.button_options()
        options.width = 150.0
        options.height = 31.0
        if i == 2usize { options.enabled = false }
        let (split, split_error) = control.windows_split(a, u64(8000usize + 10usize * i), t, "Save", &actions[0usize], false, &actions[0usize], options)
        if split_error != ok { ret (0usize, split_error) }
        let (boxed, boxed_error) = placed(a, split, 20.0, 20.0)
        if boxed_error != ok { ret (0usize, boxed_error) }
        var drive: looks.Drive = .None
        if i == 1usize {
            drive = .Press
            looks.aim(at, 0.0 - 70.0, 0.0 - 64.0)
        }
        let names = [3]str{ "button-split", "button-split-pressed", "button-split-disabled" }
        cells[at] = looks.Cell { caption: names[i], node: boxed, drive: drive }
        at += 1usize
        i += 1usize
    }
    // 3 and 4: button-icon (rest) and -icon-disabled: 130 x 32 with a picture before the caption
    i = 0usize
    while i < 2usize {
        var options = control.button_options()
        options.width = 130.0
        options.height = 31.0
        if i == 1usize { options.enabled = false }
        // round 17: the capture's picture is Windows' own information icon, 16 x 16 as captured (a picture is the application's, not the look's)
        let (art, art_error) = control.raw_pixels(a, icon_pixels(i == 1usize), 16.0, 16.0)
        if art_error != ok { ret (0usize, art_error) }
        let (icon, icon_error) = control.windows_button(a, u64(8100usize + 10usize * i), t, "Open", art, true, true, false, zero, &actions[0usize], options)
        if icon_error != ok { ret (0usize, icon_error) }
        let (boxed, boxed_error) = placed(a, icon, 20.0, 20.0)
        if boxed_error != ok { ret (0usize, boxed_error) }
        let names = [2]str{ "button-icon", "button-icon-disabled" }
        cells[at] = looks.Cell { caption: names[i], node: boxed, drive: .None }
        at += 1usize
        i += 1usize
    }
    ret (at, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "native_dark3", cells: 5usize, columns: 4usize, cell_w: cell_w(), cell_h: cell_h(), ctx: zero, build: build }
    ret looks.run_all(a, &sheet)
}

fn icon_pixels(disabled: bool) -> str {
    if disabled { ret "3333333333333333333333330000003333337978783333336E6D6D333333030303333333333333333333333333333333333333333333333333404040333333609BBB333333438BC6333333607E8933333358585833333333333333333333333333333333333369686F333333658DE43333335563E73333334D5DD23333334C6DBF333333605B5E3333333333333333333333334040403333335545D63333335660DB333333FFFFFF333333466BD43333333065AF3333335050523333333333330000003333335763D63333334976DC3333334967D53333334C5EB43333333C64C73333332A5CAC3333331616163333333333336458A8333333466BD63333334468D43333335A7AD93333332147B7333333274CB4333333163B60333333000000797979333333226ACE3333333265CF3333332847B5333333647B9B3333331940AA3333331A40AA3333335558643333333333332B6C97333333385AC53333331D43AD333333B0B1AF3333331B2FA63333331B2FAC3333331E3295333333000000696767333333335BB33333331E44AE3333330B409F3333335874923333331B3FB03333331A3FAB3333335D6A6B333333333333264C553333331745AB3333331D41AF333333A6A6A43333331E3FB03333331D2FB73333331D33953333330000000202023333332347993333331E42B13333331641A63333337F8EB43333332040BF3333331F40AA3333331B1B1B3333333333335252523333331943A13333331E40B3333333EAEAED3333332240BB3333332140A23333335E5E60333333000000333333333333545554333333204399333333122FA63333334E40B23333332340A43333336D7E8733333300000033333333333333333333333347474733333318335A3333331F44A53333331334653333336A66673333330000003333333333333333333333333333333333331818183333337A7A7A3333337D7D80333333182323333333000000333333333333333333333333333333333333333333333333000000333333000000333333000000333333000000333333333333333333333333" }
    ret "3333333333333333330000000000003837377978787C7D7E6E6D6D393939030303000000333333333333333333333333333333333333000000404040B1B9B7609BBB778BC5438BC65C64B7607E898E93AF58585800000033333333333333333333333300000069686F91AEAC658DE45E86E95563E76289E44D5DD24D72D54C6DBF586F65605B5E00000033333333333300000040404082A5B55545D65742E45660DB5C82DAFFFFFFA4AFD6466BD4316AC73065AF4E4A8650505200000033333300000090AEB55763D64975DD4976DC4B75DB4967D58F9FD34C5EB43168C83C64C73851C42A5CAC55566D1616163333333837376458A8456DD3466BD64569D54468D44260CD5A7AD92A65C22147B7224FB7274CB4184BAF163B604C4C4D0000007979795853B0226ACE2267CE3265CF215DB82847B5B5B5B5647B9B1B40A51940AA1A40A91A40AA22435855586400000059595A2B6C973A63C5385AC5254AA01D43AD153EA1B0B1AF5A77951B2FA61B20AC1B2FAC1B1FAC1E329571707A000000696767275E90335BB31E48A51E44AE1D41AE0B409FAAA9A95874921D2EAA1B3FB01B3FAC1A3FAB1740955D6A6B000000383838264C551D4BAF1745AB1E43A71D41AF0B3F9FA6A6A46E7E921E3FB01E30B71D2FB7150FB31D3395504F500000000202026C7C6C2347991645B01E42B11D41B21641A6C1C1C17F8EB4183FB62040BF1F40AE1F40AA475B8D1B1B1B0000000000005252522A46511943A11E42B11E40B32241B0EAEAED8F9ECA2240BB2141C32140A21E34905E5E600101010000003333330000005455543045552043991040B6122FA68980CF4E40B22240B02340A42945966D7E870707070000003333333333333333330000004747474B504918335A2842761F44A52C46921334654E5B626A66670807070000000000003333333333333333333333330000001818185050507A7A7A8080827D7D80525151182323030303000000000000333333333333333333333333333333333333000000000000000000000000000000000000000000000000333333333333333333333333"
}
