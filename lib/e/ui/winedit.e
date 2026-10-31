// The Windows look's edit chrome. v3's TcxMaskEdit / TcxTextEdit / TcxSpinEdit / TcxButtonEdit draw the native Windows 11
// edit frame, ellipsis button and spin buttons at 96 DPI; the light chrome draws them from the true 1:1 captures
// (docs/ui/looks/ref/windows-1to1/states): 1 px lines and rectangles, 2 x 2 corner blocks for the spin buttons, an
// antialiasing weight table for the ellipsis corners and a 7 x 4 alpha tile for the arrows. An edit of DFM width W is W
// pixels wide and 21 high; nothing in it drifts with the control's place in the window (the drift of the old tables was
// the double resample of the first captures). The dark chrome (nedit_*) is separate.
//
// The chrome is one custom node laid over the edit's white face; it paints only the pixels that are not plain face (a row
// value of 0xFFFFFFFF is not painted), so the text, caret and selection under it stay as the editor draws them.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.winnative
use e.ui.winpx
use e.ui.widget

// kind: 0 plain, 1 spin with fast buttons, 2 spin with stacked arrows, 3 button edit. state: 0 rest, 1 focused, 2 disabled,
// 3 ellipsis pressed. `hover`: 0 none, 1 the edit, 1 + zone for a button under the pointer (zone 1 up, 2 down, 3 left, 4
// right of the fast spin, 5 the ellipsis). `dim` bit i greys the i-th arrow of a spin edit, left to right.
type LChrome = struct { kind: u32, state: u32, hover: u32, dim: u32, width: f32, height: f32 }

fn lc_fill(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, rgb: u32) -> err {
    ret winpx.fill(b, x, y, w, h, style.hex_raw(rgb & 0xFFFFFFu32))
}

// A channel-wise blend of two 0xRRGGBB colours: `alpha` of `ink` (0..255) over `face`.
fn lc_mix(face: u32, ink: u32, alpha: u32) -> u32 {
    var out = 0u32
    var c = 0u32
    while c < 3u32 {
        let sh = c * 8u32
        let f = f32((face >> sh) & 255u32)
        let k = f32((ink >> sh) & 255u32)
        let v = i32(f + (k - f) * f32(alpha) / 255.0 + 0.5)
        out = out | (u32(v) << sh)
        c += 1u32
    }
    ret out
}

// ---- the frame ---------------------------------------------------------------------------------------------------
// Five kinds of row, five values each: column 0, column 1, the middle, column W - 2, column W - 1. The rows are the top
// line (y 0), the one under it (y 1), every row between, the one above the foot (H - 2) and the foot (H - 1). state 0 rest,
// 1 focused (the 2 px accent foot), 2 disabled, 3 hovered.
fn lc_frame_rows(state: u32) -> [25]u32 {
    let s = 0xFFFFFFFFu32
    if state == 1u32 {
        ret [25]u32{ 0xEFEFEFu32, 0xEDEDEDu32, 0xECECECu32, 0xEDEDEDu32, 0xDFE6EBu32, 0xECECECu32, 0xFBFBFBu32, s, 0xFBFBFBu32, 0xDEE4EAu32, 0xECECECu32, s, s, s, 0xDDE4E9u32, 0x0067C0u32, 0x0067C0u32, 0x0067C0u32, 0x0067C0u32, 0x0067C0u32, 0x267CC7u32, 0x0067C0u32, 0x0067C0u32, 0x0067C0u32, 0x267CC7u32 }
    }
    if state == 2u32 {
        ret [25]u32{ 0xEEEEEFu32, 0xEBECECu32, 0xECECECu32, 0xEBECECu32, 0xEEEEEFu32, 0xECECECu32, 0xF8F8F8u32, 0xFBFBFBu32, 0xF8F8F8u32, 0xECECECu32, 0xECECECu32, 0xFBFBFBu32, s, 0xFBFBFBu32, 0xECECECu32, 0xECECECu32, 0xF8F8F8u32, 0xFBFBFBu32, 0xF8F8F8u32, 0xECECECu32, 0xEFEFEFu32, 0xECECECu32, 0xEDEDEDu32, 0xECECECu32, 0xEFEFEFu32 }
    }
    if state == 3u32 {
        ret [25]u32{ 0xEFEFEFu32, 0xEDEDEDu32, 0xECECECu32, 0xE6E6E6u32, 0xE8E8E8u32, 0xECECECu32, 0xF7F7F7u32, 0xFAFAFAu32, 0xF0F0F0u32, 0xE6E6E6u32, 0xECECECu32, 0xFAFAFAu32, s, 0xF3F3F3u32, 0xE6E6E6u32, 0xECECECu32, 0xDADADAu32, 0xFAFAFAu32, 0xD9D9D9u32, 0xD8DFE4u32, 0xEEEEEEu32, 0x929292u32, 0x838383u32, 0x929292u32, 0xE0E6ECu32 }
    }
    ret [25]u32{ 0xEFEFEFu32, 0xECECECu32, 0xECECECu32, 0xE6E6E6u32, 0xE8E8E8u32, 0xEDEDEDu32, 0xFAFAFAu32, 0xFEFEFEu32, 0xF3F3F3u32, 0xE6E6E6u32, 0xECECECu32, 0xFEFEFEu32, s, 0xF7F7F7u32, 0xE6E6E6u32, 0xECECECu32, 0xDDDDDDu32, 0xFEFEFEu32, 0xDDDDDDu32, 0xE7E7E7u32, 0xEEEEEEu32, 0x929292u32, 0x838383u32, 0x929292u32, 0xEEEEEEu32 }
}

fn lc_row(b: *scene.Builder, x: f32, y: f32, h: f32, w: f32, p: [25]u32, at: usize) -> err {
    let skip = 0xFFFFFFFFu32
    if p[at] != skip { try lc_fill(b, x, y, 1.0, h, p[at]) }
    if p[at + 1usize] != skip { try lc_fill(b, x + 1.0, y, 1.0, h, p[at + 1usize]) }
    if p[at + 2usize] != skip { try lc_fill(b, x + 2.0, y, w - 4.0, h, p[at + 2usize]) }
    if p[at + 3usize] != skip { try lc_fill(b, x + w - 2.0, y, 1.0, h, p[at + 3usize]) }
    if p[at + 4usize] != skip { try lc_fill(b, x + w - 1.0, y, 1.0, h, p[at + 4usize]) }
    ret ok
}

fn lc_frame(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, state: u32) -> err {
    let p = lc_frame_rows(state)
    try lc_row(b, x, y, 1.0, w, p, 0usize)
    try lc_row(b, x, y + 1.0, 1.0, w, p, 5usize)
    try lc_row(b, x, y + 2.0, h - 4.0, w, p, 10usize)
    try lc_row(b, x, y + h - 2.0, 1.0, w, p, 15usize)
    ret lc_row(b, x, y + h - 1.0, 1.0, w, p, 20usize)
}

// ---- the spin buttons ----------------------------------------------------------------------------------------------
// The up arrow as alpha (0..255), 4 rows of 7; the down arrow is its flip, the left and right arrows its transpose and the
// transpose's mirror.
fn lc_arrow_alpha() -> [28]u32 { ret [28]u32{ 0u32, 0u32, 0u32, 80u32, 0u32, 0u32, 0u32, 0u32, 0u32, 128u32, 255u32, 128u32, 0u32, 0u32, 0u32, 112u32, 255u32, 255u32, 255u32, 112u32, 0u32, 16u32, 255u32, 255u32, 255u32, 255u32, 255u32, 16u32 } }

// dir: 0 up, 1 down, 2 left, 3 right; (x, y) the top left of the glyph; a greyed arrow is 40 % of its ink.
fn lc_arrow(b: *scene.Builder, x: f32, y: f32, dir: u32, face: u32, ink: u32, dim: bool) -> err {
    let t = lc_arrow_alpha()
    var w = 7usize
    var h = 4usize
    if dir >= 2u32 {
        w = 4usize
        h = 7usize
    }
    var r = 0usize
    while r < h {
        var c = 0usize
        while c < w {
            var src = 0usize
            if dir == 0u32 { src = r * 7usize + c }
            if dir == 1u32 { src = (3usize - r) * 7usize + c }
            if dir == 2u32 { src = c * 7usize + r }
            if dir == 3u32 { src = (3usize - c) * 7usize + r }
            var a = t[src]
            if dim { a = a * 40u32 / 100u32 }
            if a != 0u32 { try lc_fill(b, x + f32(c), y + f32(r), 1.0, 1.0, lc_mix(face, ink, a)) }
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}

// The 2 x 2 corner blocks (top left, top right, bottom left, bottom right, each row by row) of the four spin buttons (left,
// up, down, right), at rest and under the pointer: the antialiasing of the rounded outer corners and the square inner ones.
fn lc_spin_corners_rest() -> [64]u32 { ret [64]u32{ 0xE6E6E6u32, 0xD6D6D6u32, 0xD7D7D7u32, 0xEEEEEEu32, 0xD2D2D2u32, 0xD2D2D2u32, 0xFAFAFAu32, 0xD2D2D2u32, 0xD6D6D6u32, 0xEDEDEDu32, 0xDEDEDEu32, 0xC4C4C4u32, 0xFAFAFAu32, 0xD2D2D2u32, 0xBCBCBCu32, 0xBCBCBCu32, 0xD5D5D5u32, 0xF5F5F5u32, 0xD2D2D2u32, 0xFAFAFAu32, 0xF5F5F5u32, 0xD4D4D4u32, 0xFAFAFAu32, 0xD2D2D2u32, 0xD2D2D2u32, 0xFAFAFAu32, 0xBCBCBCu32, 0xBCBCBCu32, 0xFAFAFAu32, 0xD2D2D2u32, 0xBCBCBCu32, 0xBCBCBCu32, 0xD2D2D2u32, 0xD2D2D2u32, 0xD2D2D2u32, 0xFAFAFAu32, 0xD2D2D2u32, 0xD2D2D2u32, 0xFAFAFAu32, 0xD2D2D2u32, 0xD3D3D3u32, 0xF5F5F5u32, 0xDCDCDCu32, 0xC3C3C3u32, 0xF5F5F5u32, 0xD6D6D6u32, 0xC0C0C0u32, 0xDCDCDCu32, 0xD2D2D2u32, 0xD2D2D2u32, 0xD2D2D2u32, 0xFAFAFAu32, 0xD8D8D8u32, 0xE7E7E7u32, 0xEDEDEDu32, 0xD6D6D6u32, 0xD2D2D2u32, 0xFAFAFAu32, 0xBCBCBCu32, 0xBCBCBCu32, 0xEDEDEDu32, 0xD8D8D8u32, 0xC1C1C1u32, 0xDFDFDFu32 } }
fn lc_spin_corners_hover() -> [64]u32 { ret [64]u32{ 0x96C3E5u32, 0x0F7FD5u32, 0x1E87D7u32, 0xBDD8EEu32, 0x0078D4u32, 0x0078D4u32, 0xD8E6F1u32, 0x0078D4u32, 0x0F7FD5u32, 0xBDD8EDu32, 0x96BEDDu32, 0x1E7BC4u32, 0xD8E6F1u32, 0x0078D4u32, 0x006BBEu32, 0x006BBEu32, 0x1E87D7u32, 0xBDD8EEu32, 0x0078D4u32, 0xD8E6F1u32, 0xBDD8EEu32, 0x0F80D6u32, 0xD8E6F1u32, 0x0078D4u32, 0x0078D4u32, 0xD8E6F1u32, 0x006BBEu32, 0x006BBEu32, 0xD8E6F1u32, 0x0078D4u32, 0x006BBEu32, 0x006BBEu32, 0x0078D4u32, 0x0078D4u32, 0x0078D4u32, 0xD8E6F1u32, 0x0078D4u32, 0x0078D4u32, 0xD8E6F1u32, 0x0078D4u32, 0x0F7FD5u32, 0xBDD8EDu32, 0x96BEDDu32, 0x1E7BC4u32, 0xBDD8EDu32, 0x1E87D8u32, 0x0F73C1u32, 0x96BFDDu32, 0x0078D4u32, 0x0078D4u32, 0x0078D4u32, 0xD8E6F1u32, 0x1E87D7u32, 0x96C3E5u32, 0xBDD8EEu32, 0x0F80D6u32, 0x0078D4u32, 0xD8E6F1u32, 0x006BBEu32, 0x006BBEu32, 0xBDD8EDu32, 0x1E87D8u32, 0x0F73C1u32, 0x96BFDDu32 } }

// One spin button of w x h at (x, y): the face, the 1 px sides, a top line (unless `top` is 0xFFFFFFFF, the up button's), the
// bottom line and the corner blocks of button `idx` (0 left, 1 up, 2 down, 3 right).
fn lc_button(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, side: u32, top: u32, bottom: u32, face: u32, corners: [64]u32, idx: usize) -> err {
    try lc_fill(b, x, y, w, h, face)
    try lc_fill(b, x, y, 1.0, h, side)
    try lc_fill(b, x + w - 1.0, y, 1.0, h, side)
    if top != 0xFFFFFFFFu32 { try lc_fill(b, x, y, w, 1.0, top) }
    try lc_fill(b, x, y + h - 1.0, w, 1.0, bottom)
    var k = 0usize
    while k < 4usize {
        var cx = x
        var cy = y
        if k == 1usize || k == 3usize { cx = x + w - 2.0 }
        if k >= 2usize { cy = y + h - 2.0 }
        var q = 0usize
        while q < 4usize {
            try lc_fill(b, cx + f32(q % 2usize), cy + f32(q / 2usize), 1.0, 1.0, corners[idx * 16usize + k * 4usize + q])
            q += 1usize
        }
        k += 1usize
    }
    ret ok
}

fn lc_spin_button(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, idx: usize, hot: bool, dimmed: bool) -> err {
    var side = 0xD2D2D2u32
    var bottom = 0xBCBCBCu32
    var face = 0xFAFAFAu32
    var ink = 0x1A1A1Au32
    var corners = lc_spin_corners_rest()
    if hot {
        side = 0x0078D4u32
        bottom = 0x006BBEu32
        face = 0xD8E6F1u32
        ink = 0x17181Au32
        corners = lc_spin_corners_hover()
    }
    var top = side
    if idx == 1usize { top = 0xFFFFFFFFu32 }
    try lc_button(b, x, y, w, h, side, top, bottom, face, corners, idx)
    if idx == 0usize { ret lc_arrow(b, x + 4.0, y + 4.0, 2u32, face, ink, dimmed) }
    if idx == 3usize { ret lc_arrow(b, x + 5.0, y + 4.0, 3u32, face, ink, dimmed) }
    if idx == 1usize { ret lc_arrow(b, x + 4.0, y + 1.0, 0u32, face, ink, dimmed) }
    ret lc_arrow(b, x + 4.0, y + 2.0, 1u32, face, ink, dimmed)
}

// The button strip of a spin edit of width `w` at (x, y): the #F0F0F0 gap columns, a white row between the up and the down
// button, and the buttons, rows 2 to 18. `zone` is the button under the pointer (1 up, 2 down, 3 left, 4 right).
fn lc_spin(b: *scene.Builder, x: f32, y: f32, w: f32, kind: u32, zone: u32, dim: u32) -> err {
    var start = w - 48.0
    var white = w - 33.0
    var white_w: f32 = 17.0
    var mid = w - 32.0
    if kind == 2u32 {
        start = w - 18.0
        white = w - 18.0
        white_w = 16.0
        mid = w - 17.0
    }
    try lc_fill(b, x + start, y + 2.0, w - 2.0 - start, 17.0, 0xF0F0F0u32)
    try lc_fill(b, x + white, y + 10.0, white_w, 1.0, 0xFFFFFFu32)
    var up_bit = 1u32
    var down_bit = 2u32
    if kind == 1u32 {
        up_bit = 2u32
        down_bit = 4u32
        try lc_spin_button(b, x + w - 47.0, y + 2.0, 14.0, 17.0, 0usize, zone == 3u32, (dim & 1u32) != 0u32)
        try lc_spin_button(b, x + w - 16.0, y + 2.0, 14.0, 17.0, 3usize, zone == 4u32, (dim & 8u32) != 0u32)
    }
    try lc_spin_button(b, x + mid, y + 2.0, 15.0, 8.0, 1usize, zone == 1u32, (dim & up_bit) != 0u32)
    ret lc_spin_button(b, x + mid, y + 11.0, 15.0, 8.0, 2usize, zone == 2u32, (dim & down_bit) != 0u32)
}

// ---- the ellipsis button -------------------------------------------------------------------------------------------
// The weights (out of 255, for the line, the foot and the face over white) of the 4 x 4 corner pixels (top left, top right,
// bottom left, bottom right, each row by row) of the 15 x 17 button: the antialiasing of its rounded corners, the same in
// every look of the button.
fn lc_ell_weights() -> [192]u32 { ret [192]u32{ 0u32, 0u32, 0u32, 32u32, 0u32, 0u32, 191u32, 0u32, 0u32, 239u32, 0u32, 0u32, 32u32, 0u32, 0u32, 239u32, 0u32, 0u32, 127u32, 0u32, 133u32, 14u32, 0u32, 250u32, 174u32, 0u32, 3u32, 111u32, 0u32, 148u32, 0u32, 0u32, 255u32, 0u32, 0u32, 255u32, 255u32, 0u32, 0u32, 16u32, 0u32, 240u32, 0u32, 0u32, 255u32, 0u32, 0u32, 255u32, 255u32, 0u32, 0u32, 175u32, 0u32, 1u32, 32u32, 0u32, 0u32, 0u32, 0u32, 0u32, 14u32, 0u32, 250u32, 112u32, 0u32, 138u32, 239u32, 0u32, 0u32, 32u32, 0u32, 0u32, 0u32, 0u32, 255u32, 0u32, 0u32, 255u32, 128u32, 0u32, 122u32, 190u32, 0u32, 7u32, 0u32, 0u32, 255u32, 0u32, 0u32, 255u32, 16u32, 0u32, 237u32, 239u32, 0u32, 0u32, 239u32, 0u32, 0u32, 16u32, 0u32, 240u32, 0u32, 0u32, 255u32, 0u32, 0u32, 255u32, 191u32, 0u32, 0u32, 122u32, 6u32, 128u32, 0u32, 0u32, 255u32, 0u32, 0u32, 255u32, 29u32, 3u32, 0u32, 239u32, 0u32, 0u32, 113u32, 0u32, 133u32, 16u32, 0u32, 240u32, 0u32, 0u32, 0u32, 29u32, 3u32, 0u32, 28u32, 147u32, 0u32, 12u32, 243u32, 0u32, 0u32, 0u32, 255u32, 0u32, 0u32, 255u32, 15u32, 1u32, 238u32, 255u32, 0u32, 0u32, 0u32, 0u32, 255u32, 0u32, 0u32, 255u32, 109u32, 4u32, 137u32, 175u32, 0u32, 0u32, 16u32, 0u32, 240u32, 124u32, 5u32, 120u32, 239u32, 0u32, 0u32, 29u32, 2u32, 2u32, 0u32, 239u32, 0u32, 55u32, 136u32, 0u32, 29u32, 2u32, 2u32, 0u32, 0u32, 0u32 } }

// style_id: 0 rest, 1 hovered, 2 pressed, 3 disabled. The button is 15 x 17 at (x, y); the three dots sit on row 8 and column 4
// (a pressed button's one pixel down and right; a disabled one's have a white shadow one pixel down and right).
fn lc_ellipsis(b: *scene.Builder, x: f32, y: f32, style_id: u32) -> err {
    let sides = [4]u32{ 0xD0D0D0u32, 0x0078D4u32, 0x005499u32, 0xE9E9E9u32 }
    let feet = [4]u32{ 0xBABABAu32, 0x006BBEu32, 0x005499u32, 0xE9E9E9u32 }
    let faces = [4]u32{ 0xFDFDFDu32, 0xE0EEF9u32, 0xCCE4F7u32, 0xF9F9F9u32 }
    let side = sides[usize(style_id)]
    let foot = feet[usize(style_id)]
    let face = faces[usize(style_id)]
    let w: f32 = 15.0
    let h: f32 = 17.0
    try lc_fill(b, x, y, w, h, face)
    try lc_fill(b, x, y, 1.0, h, side)
    try lc_fill(b, x + w - 1.0, y, 1.0, h, side)
    try lc_fill(b, x, y, w, 1.0, side)
    try lc_fill(b, x, y + h - 1.0, w, 1.0, foot)
    let weights = lc_ell_weights()
    var k = 0usize
    while k < 4usize {
        var cx = x
        var cy = y
        if k == 1usize || k == 3usize { cx = x + w - 4.0 }
        if k >= 2usize { cy = y + h - 4.0 }
        var edge = side
        if k >= 2usize { edge = foot }
        var q = 0usize
        while q < 16usize {
            let at = (k * 16usize + q) * 3usize
            var v = 0u32
            var c = 0u32
            while c < 3u32 {
                let sh = c * 8u32
                let o: f32 = 255.0
                let l = f32((side >> sh) & 255u32) - o
                let e = f32((edge >> sh) & 255u32) - o
                let f = f32((face >> sh) & 255u32) - o
                var p = i32(o + (l * f32(weights[at]) + e * f32(weights[at + 1usize]) + f * f32(weights[at + 2usize])) / 255.0 + 0.5)
                if p < 0 { p = 0 }
                if p > 255 { p = 255 }
                v = v | (u32(p) << sh)
                c += 1u32
            }
            try lc_fill(b, cx + f32(q % 4usize), cy + f32(q / 4usize), 1.0, 1.0, v)
            q += 1usize
        }
        k += 1usize
    }
    var ink = 0u32
    var dy: f32 = 8.0
    if style_id == 2u32 { dy = 9.0 }
    if style_id == 3u32 { ink = 0xA0A0A0u32 }
    var dx: f32 = 4.0
    if style_id == 2u32 { dx = 5.0 }
    var d = 0usize
    while d < 3usize {
        try lc_fill(b, x + dx + f32(d * 3usize), y + dy, 1.0, 1.0, ink)
        if style_id == 3u32 { try lc_fill(b, x + 5.0 + f32(d * 3usize), y + dy + 1.0, 1.0, 1.0, 0xFFFFFFu32) }
        d += 1usize
    }
    ret ok
}

fn lc_paint(ctx: *void, b: *scene.Builder, raw: geometry.Rect) -> err {
    let d = mem.cast[*LChrome](ctx)
    // on whole pixels: a control centred in an odd cell would otherwise blur its one pixel lines over two columns
    let x = f32(i32(raw.x + 0.5))
    let y = f32(i32(raw.y + 0.5))
    let w = d.width
    let h = d.height - 1.0
    var zone = 0u32
    if d.hover > 1u32 { zone = d.hover - 1u32 }
    var frame = 0u32
    if d.state == 1u32 || d.state == 3u32 { frame = 1u32 }
    if d.state == 2u32 { frame = 2u32 }
    if d.state == 0u32 && d.hover != 0u32 { frame = 3u32 }
    try lc_frame(b, x, y, w, h, frame)
    if d.kind == 1u32 || d.kind == 2u32 {
        var dim = d.dim
        if d.state == 2u32 { dim = 15u32 }
        var z = zone
        if d.kind == 2u32 || d.state != 0u32 { z = 0u32 }
        ret lc_spin(b, x, y, w, d.kind, z, dim)
    }
    if d.kind == 3u32 {
        var es = 0u32
        if zone == 5u32 && d.state == 0u32 { es = 1u32 }
        if d.state == 3u32 { es = 2u32 }
        if d.state == 2u32 { es = 3u32 }
        ret lc_ellipsis(b, x + w - 17.0, y + 2.0, es)
    }
    ret ok
}

fn wedit_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

// The light chrome node for an edit of DFM width `width`; it is `width + 1` x `height` as the layout knows it (the face and the
// frame it is laid over are `width` x `height` - 1).
fn light_chrome(a: *mem.Arena, kind: u32, state: u32, hover: u32, width: f32, height: f32, dim: u32) -> (widget.Node, err) {
    let (made, made_error) = mem.alloc[LChrome](a, 1usize)
    if made_error != ok { ret (zero, made_error) }
    made[0usize] = LChrome { kind: kind, state: state, hover: hover, dim: dim, width: width, height: height }
    var s = style.defaults()
    s.width = style.Length { Px: width + 1.0 }
    s.height = style.Length { Px: height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&made[0usize]), measure: wedit_measure, paint: lc_paint, state: widget.bytes_of[LChrome](&made[0usize]) } }, style: s, children: none }, ok)
}

// `dark`: the tile pixel mapped to the Windows 11 dark palette (winpx.dark_argb, family 1: the edit face is #2B2B2B).
fn wedit_rect(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, argb: u32, dark: bool) -> err {
    var v = argb
    if dark { v = winpx.dark_argb(argb, 1u32, 0x2B2B2Bu32) }
    ret winpx.fill(b, x, y, w, h, style.hex_raw(v & 0xFFFFFFu32))
}

// ---- the token edit's frame -------------------------------------------------------------------------------------
// The empty TdxTokenEdit boxes of the Filter dialog's Cards tab (states/tab-selected-filter-cards, three instances 315 x 46,
// 315 x 46 and 315 x 27 that are pixel identical whatever their height or y): the edit frame of the plain edit but blended over
// the tab page (#F9F9F9) instead of the dialog (#F0F0F0), W pixels wide (the plain edit has W + 1). A row is five values:
// column 0, column 1, the middle, column W - 2 and column W - 1. Focused is not captured: its foot rows (the last three) are
// the plain edit's focused foot (a guess).
type TokenChrome = struct { width: f32, height: f32, focused: bool, dark: bool }

fn wtoken_gray(v: u32) -> u32 { ret 0xFF000000u32 | (v << 16u32) | (v << 8u32) | v }

fn wtoken_row(b: *scene.Builder, x: f32, y: f32, h: f32, w: f32, p: [5]u32, dark: bool) -> err {
    try wedit_rect(b, x, y, 1.0, h, p[0usize], dark)
    try wedit_rect(b, x + 1.0, y, 1.0, h, p[1usize], dark)
    try wedit_rect(b, x + 2.0, y, w - 4.0, h, p[2usize], dark)
    try wedit_rect(b, x + w - 2.0, y, 1.0, h, p[3usize], dark)
    try wedit_rect(b, x + w - 1.0, y, 1.0, h, p[4usize], dark)
    ret ok
}

fn wtoken_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let d = mem.cast[*TokenChrome](ctx)
    let w = d.width
    let h = d.height
    // round 10: dark, the token edit's frame is the native dark edit's (no capture of the TdxTokenEdit; the edit is the nearest native look)
    if d.dark {
        var st = 0u32
        if d.focused { st = 1u32 }
        ret nedit_frame(b, f32(i32(area.x + 0.5)), f32(i32(area.y + 0.5)), w, h, st)
    }
    let g = wtoken_gray
    try wtoken_row(b, area.x, area.y, 1.0, w, [5]u32{ g(246u32), g(241u32), g(240u32), g(237u32), g(242u32) }, d.dark)
    try wtoken_row(b, area.x, area.y + 1.0, 1.0, w, [5]u32{ g(240u32), g(246u32), g(248u32), g(239u32), g(233u32) }, d.dark)
    try wtoken_row(b, area.x, area.y + 2.0, 1.0, w, [5]u32{ g(237u32), g(253u32), g(255u32), g(246u32), g(230u32) }, d.dark)
    try wtoken_row(b, area.x, area.y + 3.0, h - 6.0, w, [5]u32{ g(236u32), g(254u32), g(255u32), g(247u32), g(230u32) }, d.dark)
    if d.focused {
        try wtoken_row(b, area.x, area.y + h - 3.0, 1.0, w, [5]u32{ 0xFF7BACD7u32, 0xFF6CA7DAu32, 0xFF6EA8DBu32, 0xFF66A3D6u32, 0xFFA5C5E0u32 }, d.dark)
        try wtoken_row(b, area.x, area.y + h - 2.0, 1.0, w, [5]u32{ 0xFF3786CBu32, 0xFF0369C1u32, 0xFF0067C0u32, 0xFF0A6DC2u32, 0xFF7FB0D9u32 }, d.dark)
        try wtoken_row(b, area.x, area.y + h - 1.0, 1.0, w, [5]u32{ 0xFFA6C6E1u32, 0xFF8BB7DCu32, 0xFF89B5DBu32, 0xFF91B9DDu32, 0xFFC3D6E7u32 }, d.dark)
    } else {
        try wtoken_row(b, area.x, area.y + h - 3.0, 1.0, w, [5]u32{ g(237u32), g(232u32), g(254u32), g(230u32), g(231u32) }, d.dark)
        try wtoken_row(b, area.x, area.y + h - 2.0, 1.0, w, [5]u32{ g(242u32), g(171u32), g(172u32), g(171u32), g(240u32) }, d.dark)
        try wtoken_row(b, area.x, area.y + h - 1.0, 1.0, w, [5]u32{ g(247u32), g(215u32), g(210u32), g(215u32), g(247u32) }, d.dark)
    }
    ret ok
}

// The token edit's frame `width` wide (the DFM width W: the frame is W pixels) and `height` high (the DFM height + 1).
fn token_chrome(a: *mem.Arena, width: f32, height: f32, focused: bool, dark: bool) -> (widget.Node, err) {
    let (made, made_error) = mem.alloc[TokenChrome](a, 1usize)
    if made_error != ok { ret (zero, made_error) }
    made[0usize] = TokenChrome { width: width, height: height, focused: focused, dark: dark }
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&made[0usize]), measure: wedit_measure, paint: wtoken_paint, state: widget.bytes_of[TokenChrome](&made[0usize]) } }, style: s, children: none }, ok)
}

// ---- round 10: the native dark edit chrome ------------------------------------------------------------------------------
// The Windows 11 DarkMode edit as docs/ui/looks/ref/windows-native/dark captures it (edit-*, spin-*): a one pixel outer line
// (#9B9B9B rest, #FFFFFF focused, #404040 disabled), a one pixel #383838 ring, the face (#202020) inside; a square frame. The spin
// edit's up-down is read from the capture (e.ui.winnative nspin: the 3 left columns, the middle column and the 18 right columns
// of each of its 24 rows; the rows are cut or doubled at the plain ones to fit the control's height). A button edit's ellipsis is a
// small native-style button (no capture of that composite). kind: 0 plain, 1 and 2 spin, 3 button edit. state: 0 rest, 1 focused,
// 2 disabled, 3 ellipsis pressed. `hover` and `press` name the spin button under the pointer or held (1 up, 2 down, 3 left, 4 right
// of the fast spin; 5 ellipsis). `dim` bit 0 greys the up arrow, bit 1 the down arrow.
type NChrome = struct { kind: u32, state: u32, hover: u32, press: u32, dim: u32, width: f32, height: f32 }

fn nedit_outer(state: u32) -> u32 {
    if state == 1u32 { ret 0xFFFFFFu32 }
    if state == 2u32 { ret 0x404040u32 }
    ret 0x9B9B9Bu32
}

fn nrect(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, rgb: u32) -> err {
    ret winpx.fill(b, x, y, w, h, style.hex_raw(rgb & 0xFFFFFFu32))
}

// The two line frame of a plain edit over `w` x `h` at (x, y).
fn nedit_frame(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, state: u32) -> err {
    let outer = nedit_outer(state)
    let ring = 0x383838u32
    try nrect(b, x, y, w, 1.0, outer)
    try nrect(b, x, y + h - 1.0, w, 1.0, outer)
    try nrect(b, x, y + 1.0, 1.0, h - 2.0, outer)
    try nrect(b, x + w - 1.0, y + 1.0, 1.0, h - 2.0, outer)
    try nrect(b, x + 1.0, y + 1.0, w - 2.0, 1.0, ring)
    try nrect(b, x + 1.0, y + h - 2.0, w - 2.0, 1.0, ring)
    try nrect(b, x + 1.0, y + 2.0, 1.0, h - 4.0, ring)
    ret nrect(b, x + w - 2.0, y + 2.0, 1.0, h - 4.0, ring)
}

// The source row (0..23) of the spin capture that target row `r` of `h` rows shows: rows cut (shorter) or doubled (taller) at
// the plain ones between and below the arrows.
fn nspin_row(r: usize, h: usize) -> usize {
    if h == 24usize { ret r }
    let cuts = [6]usize{ 9usize, 14usize, 8usize, 19usize, 10usize, 13usize }
    var src: [64]usize = zero
    var n = 0usize
    var k = 0usize
    if h < 24usize {
        k = 24usize - h
    } else {
        k = h - 24usize
    }
    if k > 6usize { k = 6usize }
    var i = 0usize
    while i < 24usize {
        var cut = false
        var c = 0usize
        while c < k {
            if cuts[c] == i { cut = true }
            c += 1usize
        }
        if h < 24usize {
            if !cut {
                src[n] = i
                n += 1usize
            }
        } else {
            src[n] = i
            n += 1usize
            if cut {
                src[n] = i
                n += 1usize
            }
        }
        i += 1usize
    }
    if r >= n { ret src[n - 1usize] }
    ret src[r]
}

// Pixel `c` (0..21) of source row `src`: 3 left, the middle, 18 right; a greyed arrow takes its glyph box from the disabled capture.
fn nspin_pixel(table: []const u32, dim_table: []const u32, dim_up: bool, dim_down: bool, src: usize, c: usize) -> u32 {
    let at = src * 22usize + c
    if c >= 7usize && c <= 19usize {
        if dim_up && src >= 3usize && src <= 10usize { ret dim_table[at] }
        if dim_down && src >= 13usize && src <= 20usize { ret dim_table[at] }
    }
    ret table[at]
}

// One row of the spin capture at `src`, over `w` px starting at (x, y).
fn nspin_row_paint(b: *scene.Builder, table: []const u32, dim_table: []const u32, dim_up: bool, dim_down: bool, src: usize, x: f32, y: f32, w: f32) -> err {
    var i = 0usize
    // the face (#202020) of the left and middle pixels is the edit's own, so the text under the chrome stays
    while i < 3usize {
        let v = nspin_pixel(table, dim_table, dim_up, dim_down, src, i)
        if (v & 0xFFFFFFu32) != 0x202020u32 { try nrect(b, x + f32(i), y, 1.0, 1.0, v) }
        i += 1usize
    }
    let mid = nspin_pixel(table, dim_table, dim_up, dim_down, src, 3usize)
    if (mid & 0xFFFFFFu32) != 0x202020u32 { try nrect(b, x + 3.0, y, w - 21.0, 1.0, mid) }
    var c = 0usize
    while c < 18usize {
        let v = nspin_pixel(table, dim_table, dim_up, dim_down, src, 4usize + c)
        var run = 1usize
        while c + run < 18usize && nspin_pixel(table, dim_table, dim_up, dim_down, src, 4usize + c + run) == v { run += 1usize }
        try nrect(b, x + w - 18.0 + f32(c), y, f32(run), 1.0, v)
        c += run
    }
    ret ok
}

// Round 17 (derived, no dark capture): v3's ellipsis button is a 4 px rounded soft button with faint 3 x 2 px dots; here the
// corners are the native dark button's ring corner (docs/ui/looks/ref/windows-native/dark/button-rest, rows 13 to 16 of the
// crop) and the dots are v3's coverage (d8 c3 ea / e6 d9 f1 on fd) laid over the dark face.
fn nmix(bg: u32, line: u32, face: u32, wl: u32, wf: u32) -> u32 {
    var out = 0u32
    var c = 0u32
    while c < 3u32 {
        let sh = c * 8u32
        let vb = (bg >> sh) & 255u32
        let vl = (line >> sh) & 255u32
        let vf = (face >> sh) & 255u32
        let v = (vb * (100u32 - wl - wf) + vl * wl + vf * wf + 50u32) / 100u32
        out = out | (v << sh)
        c += 1u32
    }
    ret out
}

fn nedit_corner(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, line: u32, face: u32) -> err {
    let wl = [16]u32{ 0u32, 6u32, 55u32, 90u32, 6u32, 80u32, 60u32, 10u32, 55u32, 60u32, 0u32, 0u32, 90u32, 10u32, 0u32, 0u32 }
    let wf = [16]u32{ 0u32, 0u32, 0u32, 0u32, 0u32, 20u32, 40u32, 90u32, 0u32, 40u32, 100u32, 100u32, 0u32, 90u32, 100u32, 100u32 }
    var k = 0usize
    while k < 16usize {
        let cx = f32(k % 4usize)
        let cy = f32(k / 4usize)
        let v = nmix(0x202020u32, line, face, wl[k], wf[k])
        try nrect(b, x + cx, y + cy, 1.0, 1.0, v)
        try nrect(b, x + w - 1.0 - cx, y + cy, 1.0, 1.0, v)
        try nrect(b, x + cx, y + h - 1.0 - cy, 1.0, 1.0, v)
        try nrect(b, x + w - 1.0 - cx, y + h - 1.0 - cy, 1.0, 1.0, v)
        k += 1usize
    }
    ret ok
}

// The ellipsis button of a button edit: 16 wide, the edit's height less 5, 1 px from its end (rect (W - 17, 2)).
fn nedit_ellipsis(b: *scene.Builder, x: f32, y: f32, w: f32, h: f32, state: u32, pressed: bool) -> err {
    var line = 0x9B9B9Bu32
    var face = 0x333333u32
    if pressed { face = 0x666666u32 }
    if state == 2u32 { line = 0x404040u32 }
    try nrect(b, x, y, w, h, line)
    try nrect(b, x + 1.0, y + 1.0, w - 2.0, h - 2.0, face)
    try nedit_corner(b, x, y, w, h, line, face)
    var ink = 0xFFFFFFu32
    if state == 2u32 { ink = 0x7A7A7Au32 }
    // coverage in percent of the three columns of one dot, upper and lower row
    let top = [3]u32{ 15u32, 23u32, 8u32 }
    let low = [3]u32{ 9u32, 14u32, 4u32 }
    var d = 0usize
    while d < 3usize {
        var c = 0usize
        while c < 3usize {
            let px = x + 4.0 + f32(d * 3usize + c)
            try nrect(b, px, y + 8.0, 1.0, 1.0, nmix(face, ink, ink, top[c], 0u32))
            try nrect(b, px, y + 9.0, 1.0, 1.0, nmix(face, ink, ink, low[c], 0u32))
            c += 1usize
        }
        d += 1usize
    }
    ret ok
}

fn nedit_paint(ctx: *void, b: *scene.Builder, raw: geometry.Rect) -> err {
    let d = mem.cast[*NChrome](ctx)
    let w = d.width + 1.0
    let h = d.height
    // on whole pixels: a control centred in an odd cell would otherwise blur its one pixel lines over two columns
    let area = geometry.Rect { x: f32(i32(raw.x + 0.5)), y: f32(i32(raw.y + 0.5)), width: raw.width, height: raw.height }
    if d.kind == 1u32 || d.kind == 2u32 {
        var st = 0u32
        if d.state == 1u32 || d.state == 3u32 { st = 1u32 }
        if d.hover == 2u32 { st = 2u32 }
        if d.hover == 3u32 { st = 3u32 }
        if d.press == 1u32 { st = 4u32 }
        if d.press == 2u32 { st = 5u32 }
        if d.state == 2u32 { st = 6u32 }
        let table = winnative.nspin(st)
        let dim_table = winnative.nspin(6u32)
        let rows = usize(h + 0.5)
        var r = 0usize
        while r < rows {
            try nspin_row_paint(b, table[0usize..528usize], dim_table[0usize..528usize], (d.dim & 1u32) != 0u32, (d.dim & 2u32) != 0u32, nspin_row(r, rows), area.x, area.y + f32(r), w)
            r += 1usize
        }
        ret ok
    }
    try nedit_frame(b, area.x, area.y, w, h, d.state)
    if d.kind == 3u32 {
        try nedit_ellipsis(b, area.x + w - 17.0, area.y + 2.0, 16.0, h - 5.0, d.state, d.state == 3u32 || d.press == 5u32)
    }
    ret ok
}

// The native dark chrome node for an edit of DFM width `width` (it paints `width + 1` x `height`).
fn native_chrome(a: *mem.Arena, kind: u32, state: u32, hover: u32, press: u32, dim: u32, width: f32, height: f32) -> (widget.Node, err) {
    let (made, made_error) = mem.alloc[NChrome](a, 1usize)
    if made_error != ok { ret (zero, made_error) }
    made[0usize] = NChrome { kind: kind, state: state, hover: hover, press: press, dim: dim, width: width, height: height }
    var s = style.defaults()
    s.width = style.Length { Px: width + 1.0 }
    s.height = style.Length { Px: height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&made[0usize]), measure: wedit_measure, paint: nedit_paint, state: widget.bytes_of[NChrome](&made[0usize]) } }, style: s, children: none }, ok)
}

// ---- round 10: the native dark combo box ----------------------------------------------------------------------------------
// combo-edit-* (CBS_DROPDOWN) and combo-list-* (CBS_DROPDOWNLIST) of docs/ui/looks/ref/windows-native/dark, painted from their
// measurements: an editable combo is the edit frame (outer line, a 2 px #383838 band) with the field (#202020) from x 3 to w - 21 and a
// 19 px button (#383838) at the end; a list combo is one #333333 face inside a 1 px #9B9B9B line, its focus a one pixel dotted rectangle
// (x 3 to w - 21, y 3 to h - 4, alternating #CCCCCC and #131313). The chevron is a 10 x 6 tile at (w - 14, 9) (e.ui.winnative nchev).
// kind 0 editable, 1 list. state: 0 rest, 1 focused, 2 disabled, 3 open or the button held. The frame paints w + 1 x h + 1.
type NCombo = struct { kind: u32, state: u32, width: f32, height: f32 }

fn ncombo_chevron(b: *scene.Builder, x: f32, y: f32, id: u32) -> err {
    let tile = winnative.nchev(id)
    var j = 0usize
    while j < 6usize {
        var i = 0usize
        while i < 10usize {
            try nrect(b, x + f32(i), y + f32(j), 1.0, 1.0, tile[j * 10usize + i])
            i += 1usize
        }
        j += 1usize
    }
    ret ok
}

fn ncombo_paint(ctx: *void, b: *scene.Builder, raw: geometry.Rect) -> err {
    let d = mem.cast[*NCombo](ctx)
    let x = f32(i32(raw.x + 0.5))
    let y = f32(i32(raw.y + 0.5))
    let w = d.width + 1.0
    let h = d.height + 1.0
    var outer = 0x9B9B9Bu32
    if d.state == 1u32 && d.kind == 0u32 { outer = 0xFFFFFFu32 }
    if d.state == 3u32 && d.kind == 0u32 { outer = 0xFFFFFFu32 }
    if d.state == 2u32 { outer = 0x404040u32 }
    var chev = 1u32
    if d.kind == 0u32 { chev = 0u32 }
    if d.state == 2u32 { chev = 2u32 }
    if d.state == 3u32 { chev = 3u32 }
    let top = f32(i32((h - 23.0) * 0.5 - 0.5))
    if d.kind == 0u32 {
        var ring = 0x383838u32
        if d.state == 2u32 { ring = 0x333333u32 }
        try nrect(b, x, y, w, h, outer)
        try nrect(b, x + 1.0, y + 1.0, w - 2.0, h - 2.0, ring)
        try nrect(b, x + 3.0, y + 3.0, w - 23.0, h - 6.0, 0x202020u32)
        // round 12: open (combo-edit-open): a white line at w - 17 and the held button, a #666666 face of 15 columns, full height
        if d.state == 3u32 {
            try nrect(b, x + w - 17.0, y + 1.0, 1.0, h - 2.0, 0xFFFFFFu32)
            try nrect(b, x + w - 16.0, y + 1.0, 15.0, h - 2.0, 0x666666u32)
        }
        ret ncombo_chevron(b, x + w - 14.0, y + 9.0 + top, chev)
    }
    var face = 0x333333u32
    if d.state == 3u32 { face = 0x666666u32 }
    try nrect(b, x, y, w, h, outer)
    try nrect(b, x + 1.0, y + 1.0, w - 2.0, h - 2.0, face)
    try ncombo_chevron(b, x + w - 14.0, y + 9.0 + top, chev)
    if d.state == 1u32 {
        var px: i32 = 3
        let right = i32(w) - 21
        let low = i32(h) - 4
        while px <= right {
            var up = 0x131313u32
            if (px + 3) % 2 == 0 { up = 0xCCCCCCu32 }
            var down = 0x131313u32
            if (px + low) % 2 == 0 { down = 0xCCCCCCu32 }
            try nrect(b, x + f32(px), y + 3.0, 1.0, 1.0, up)
            try nrect(b, x + f32(px), y + f32(low), 1.0, 1.0, down)
            px += 1
        }
        var py: i32 = 4
        while py < low {
            var left = 0x131313u32
            if (3 + py) % 2 == 0 { left = 0xCCCCCCu32 }
            var edge = 0x131313u32
            if (right + py) % 2 == 0 { edge = 0xCCCCCCu32 }
            try nrect(b, x + 3.0, y + f32(py), 1.0, 1.0, left)
            try nrect(b, x + f32(right), y + f32(py), 1.0, 1.0, edge)
            py += 1
        }
    }
    ret ok
}

// The native dark combo frame node for a control of DFM width `width` and height `height` (it paints `width + 1` x `height + 1`).
fn native_combo(a: *mem.Arena, kind: u32, state: u32, width: f32, height: f32) -> (widget.Node, err) {
    let (made, made_error) = mem.alloc[NCombo](a, 1usize)
    if made_error != ok { ret (zero, made_error) }
    made[0usize] = NCombo { kind: kind, state: state, width: width, height: height }
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&made[0usize]), measure: wedit_measure, paint: ncombo_paint, state: widget.bytes_of[NCombo](&made[0usize]) } }, style: s, children: none }, ok)
}
