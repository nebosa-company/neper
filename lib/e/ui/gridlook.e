// The look of the data grid as measured from MTG Studio v3 (docs/grid-parity/tokens.json):
// metrics in logical pixels (physical at 100 % DPI) and colours. `e.ui.datagrid` reads one
// `Look` through `set_look`; `e.ui.collection` draws a table with its `TableLook` part. Both
// are plain data: a different application look is another `Look`, not another widget.
//
// Measured at 150 % DPI from mtgstudio.exe 3.234 (the recordings are in docs/grid-parity):
// a row is 28.5 physical px (19), the header 32 (21), rows alternate #FFFFFF / #EFEFEF with no
// line between them, the selected row is #A6D2FF with a 1 px #83878B edge, a group row is
// #F0F0F0, the footer a #FFFFDD band with #E7EAEA summary cells, the frame #828790.
//
// ponytail: only what the recordings give is here; hover and pressed rows, the focus
// rectangle and unfocused-window selection colours wait for their recordings.

use e.gfx.paint

type Look = struct {
    on: bool,
    row_height: f32,
    header_height: f32,
    pad: f32,
    text_size: f32,
    header: paint.Color,
    header_hover: paint.Color,
    header_line: paint.Color,
    even: paint.Color,
    odd: paint.Color,
    selected: paint.Color,
    selected_line: paint.Color,
    line: paint.Color,
    group_row: paint.Color,
    footer_band: paint.Color,
    footer_cell: paint.Color,
    frame: paint.Color
}

// A colour from 0xRRGGBB.
fn rgb(value: u32) -> paint.Color {
    let r = f32((value >> 16u32) & 255u32) / 255.0
    let g = f32((value >> 8u32) & 255u32) / 255.0
    let b = f32(value & 255u32) / 255.0
    ret paint.rgba(r, g, b, 1.0)
}

// MTG Studio v3's grid.
fn v3() -> Look {
    ret Look {
        on: true,
        row_height: 19.0,
        header_height: 21.0,
        pad: 4.0,
        text_size: 12.0,
        header: rgb(0xFFFFFFu32),
        header_hover: rgb(0xD9EBF9u32),
        header_line: rgb(0xC6C6C6u32),
        even: rgb(0xFFFFFFu32),
        odd: rgb(0xEFEFEFu32),
        selected: rgb(0xA6D2FFu32),
        selected_line: rgb(0x83878Bu32),
        line: rgb(0xE6E6E6u32),
        group_row: rgb(0xF0F0F0u32),
        footer_band: rgb(0xFFFFDDu32),
        footer_cell: rgb(0xE7EAEAu32),
        frame: rgb(0x828790u32)
    }
}

// The theme's own look: `on` false, nothing overridden.
fn theme() -> Look {
    var look: Look = zero
    ret look
}
