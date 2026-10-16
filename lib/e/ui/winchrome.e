// The Windows look's window chrome data (looks3): v3's program icon as the captured title bars show it. The icon is the 16 x 16
// area at (10, 7) of a dialog's caption, taken from docs/ui/looks/ref/windows/dialogs/search-search@1x.png; a value of 0
// is the caption face behind it (not painted), the rest are opaque pixels already blended with it (the same on the
// active #1F2022 and inactive #202020 captions to within 2 levels).

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.winpx
use e.ui.widget

fn icon_pixels() -> [256]u32 { ret [256]u32{ 0u32, 0u32, 0u32, 0u32, 0xDD5C4831u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xE4988566u32, 0x133A2D07u32, 0u32, 0x70947E54u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xF7837251u32, 0xB14F2D09u32, 0u32, 0xB788753Eu32, 0x9B3D341Au32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0x13472D15u32, 0u32, 0u32, 0xE98D7544u32, 0xFB673B10u32, 0u32, 0xBF9B853Bu32, 0xF6543910u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0x9E674F2Du32, 0u32, 0u32, 0x9B876F3Bu32, 0xF8966526u32, 0x24341906u32, 0xA199873Eu32, 0xFB764D12u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0x0B636439u32, 0xF4775D25u32, 0x0C33340Eu32, 0u32, 0x306F5B32u32, 0xF7A5792Du32, 0xAA3A2307u32, 0x86867639u32, 0xFD95631Fu32, 0x1740360Cu32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xF6AA8639u32, 0x97331B02u32, 0x8C6D3B1Du32, 0x8551160Du32, 0xFBA87D2Bu32, 0xF5533209u32, 0x96746431u32, 0xFA90601Cu32, 0x38433B14u32, 0u32, 0u32, 0x174C3717u32, 0x37655843u32, 0u32, 0u32, 0u32, 0xA09F883Au32, 0xF36A4014u32, 0xDC693016u32, 0xE66B3811u32, 0xFFD9B640u32, 0xFF8A6910u32, 0xDA9A7F39u32, 0xF97D5214u32, 0x454F4117u32, 0u32, 0x99997A34u32, 0xB362380Du32, 0x1B694F3Eu32, 0u32, 0u32, 0u32, 0x2F76712Du32, 0xFEAF7E3Au32, 0xF0532A07u32, 0xFA9B6629u32, 0xF8907322u32, 0xF9AD842Fu32, 0xF6785B1Du32, 0xF8794B14u32, 0x794D461Au32, 0x0A505122u32, 0xF3926A22u32, 0xEC3D2308u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xF3B59146u32, 0xF881591Bu32, 0xF9B5813Au32, 0xF8745012u32, 0xF7B08037u32, 0xF8644611u32, 0xF88C5D1Fu32, 0xD8684D14u32, 0xB09F6D2Bu32, 0xFA7C5414u32, 0x5D2D1B07u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0x86977D37u32, 0xFAC09742u32, 0xFB955422u32, 0xF88A5F1Cu32, 0xF6A97A2Du32, 0xF7573A0Cu32, 0xF8905F1Du32, 0xF9775113u32, 0xFA956723u32, 0xFA4A350Cu32, 0x093C3D22u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0x1C7B6022u32, 0xFDDDB25Bu32, 0xFB844D16u32, 0xF7A97B39u32, 0xF6A57C2Cu32, 0xF74E330Bu32, 0xFAA06B1Eu32, 0xF965460Eu32, 0xFA664614u32, 0x61372B08u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xDAAE903Eu32, 0xFAAF8135u32, 0xF8B08041u32, 0xF5906B1Fu32, 0xF956380Eu32, 0xFA875718u32, 0xFA583D0Du32, 0xC546300Du32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0x458D7529u32, 0xFED4A34Eu32, 0xF999662Fu32, 0xF58C661Au32, 0xF866410Fu32, 0xF9764913u32, 0xFB543A0Du32, 0x3A3E2D0Cu32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0x91B08C3Eu32, 0xF8AD7D40u32, 0xF69F7426u32, 0xF8744912u32, 0xF8744A0Fu32, 0xFD4F370Bu32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0x4B665A14u32, 0xFBCC9953u32, 0xF7A0732Au32, 0xF8764913u32, 0xF85B390Bu32, 0xFD3F2C08u32, 0x0C1F0C0Eu32, 0u32, 0u32, 0u32, 0u32, 0u32 } }

fn icon_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

fn icon_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let pixels = icon_pixels()
    var i = 0usize
    while i < 256usize {
        if pixels[i] != 0u32 {
            // looks5: each pixel is 0xAARRGGBB: the colour and its share over the caption (solved from the icon on the dark and the
            // light caption), so the icon sits on either
            var color = style.hex_raw(pixels[i] & 0xFFFFFFu32)
            color.alpha = f32(pixels[i] / 16777216u32) / 255.0
            try winpx.fill(b, area.x + f32(i % 16usize), area.y + f32(i / 16usize), 1.0, 1.0, color)
        }
        i += 1usize
    }
    ret ok
}

// The program icon, 16 x 16, for a Windows caption.
fn icon_node() -> widget.Node {
    var s = style.defaults()
    s.width = style.Length { Px: 16.0 }
    s.height = style.Length { Px: 16.0 }
    var none: []const widget.Node = zero
    var state: []const u8 = zero
    ret widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: zero, measure: icon_measure, paint: icon_paint, state: state } }, style: s, children: none }
}

// The minimise and maximise glyphs of a 46 x 31 caption button, painted with fractional rectangles the way the live
// capture antialiases them: the dash is 10 x 0.75 at (16.8, 15.25), the square a 1 px outline 10 x 10 at (16.75, 10.75)
// (both 1.25 px left of the button's centre). `kind` 0 minimise, 1 maximise, 2 close; `ink` is 0xRRGGBB, `alpha` its opacity.
type Glyph = struct { kind: u32, ink: u32, alpha: f32, width: f32 }

fn glyph_rect(b: *scene.Builder, area: geometry.Rect, x: f32, y: f32, w: f32, h: f32, ink: u32, alpha: f32) -> err {
    var c = style.hex_raw(ink)
    c.alpha = alpha
    ret winpx.fill(b, area.x + x, area.y + y, w, h, c)
}

// The close X: 10 columns by 11 rows of coverage (0 to 255) at (18, 10) of the 46 x 31 button, from the capture.
fn cross_cover() -> [110]u32 { ret [110]u32{ 50u32, 8u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 8u32, 51u32, 170u32, 128u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 128u32, 170u32, 25u32, 189u32, 128u32, 8u32, 0u32, 0u32, 8u32, 128u32, 189u32, 25u32, 0u32, 25u32, 175u32, 128u32, 0u32, 0u32, 128u32, 175u32, 25u32, 0u32, 0u32, 0u32, 25u32, 189u32, 133u32, 133u32, 189u32, 25u32, 0u32, 0u32, 0u32, 0u32, 0u32, 25u32, 214u32, 214u32, 25u32, 0u32, 0u32, 0u32, 0u32, 0u32, 8u32, 128u32, 200u32, 200u32, 128u32, 8u32, 0u32, 0u32, 0u32, 0u32, 128u32, 175u32, 25u32, 25u32, 175u32, 128u32, 0u32, 0u32, 8u32, 128u32, 189u32, 25u32, 0u32, 0u32, 25u32, 189u32, 128u32, 8u32, 127u32, 175u32, 25u32, 0u32, 0u32, 0u32, 0u32, 25u32, 175u32, 127u32, 154u32, 24u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 25u32, 152u32 } }

fn glyph_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let g = mem.cast[*Glyph](ctx)
    if g.kind == 2u32 {
        let cover = cross_cover()
        var i = 0usize
        while i < 110usize {
            if cover[i] != 0u32 { try glyph_rect(b, area, f32(u32((g.width - 10.0) * 0.5 + 0.5)) + f32(i % 10usize), 10.0 + f32(i / 10usize), 1.0, 1.0, g.ink, g.alpha * f32(cover[i]) / 255.0) }
            i += 1usize
        }
        ret ok
    }
    // looks4: the dash and the square as per-pixel coverage (0 to 255) of the live active main window caption (white on
    // #1F2022: a full line is 191 = 0.75), 11 columns from x = 16 of the 46 wide button; the square 11 rows from y = 10.
    // looks4: the close X of a 33 wide dialog caption whose button starts on an odd pixel (About, Options) is a half pixel
    // to the left of the one on an even pixel (Search for Card): 12 columns from x = 11 of the button, 11 rows from y = 10.
    if g.kind == 4u32 {
        var e = 0usize
        while e < 10usize {
            try glyph_rect(b, area, 17.0 + f32(e), 15.0, 1.0, 1.0, g.ink, g.alpha * 191.0 / 255.0)
            e += 1usize
        }
        ret ok
    }
    if g.kind == 5u32 {
        let box = square_cover_odd()
        var m = 0usize
        while m < 110usize {
            if box[m] != 0u32 { try glyph_rect(b, area, 17.0 + f32(m % 10usize), 10.0 + f32(m / 10usize), 1.0, 1.0, g.ink, g.alpha * f32(box[m]) / 255.0) }
            m += 1usize
        }
        ret ok
    }
    if g.kind == 6u32 {
        let wide = cross46_cover_odd()
        var n = 0usize
        while n < 121usize {
            if wide[n] != 0u32 { try glyph_rect(b, area, 18.0 + f32(n % 11usize), 10.0 + f32(n / 11usize), 1.0, 1.0, g.ink, g.alpha * f32(wide[n]) / 255.0) }
            n += 1usize
        }
        ret ok
    }
    if g.kind == 3u32 || g.kind == 7u32 {
        var odd = cross_cover_odd()
        if g.kind == 7u32 { odd = cross_cover_odd_active() }
        var k = 0usize
        while k < 132usize {
            if odd[k] != 0u32 { try glyph_rect(b, area, 11.0 + f32(k % 12usize), 10.0 + f32(k / 12usize), 1.0, 1.0, g.ink, g.alpha * f32(odd[k]) / 255.0) }
            k += 1usize
        }
        ret ok
    }
    if g.kind == 0u32 {
        let dash = dash_cover()
        var d = 0usize
        while d < 11usize {
            try glyph_rect(b, area, 16.0 + f32(d), 15.0, 1.0, 1.0, g.ink, g.alpha * f32(dash[d]) / 255.0)
            d += 1usize
        }
        ret ok
    }
    let square = square_cover()
    var q = 0usize
    while q < 121usize {
        if square[q] != 0u32 { try glyph_rect(b, area, 16.0 + f32(q % 11usize), 10.0 + f32(q / 11usize), 1.0, 1.0, g.ink, g.alpha * f32(square[q]) / 255.0) }
        q += 1usize
    }
    ret ok
}

fn cross_cover_odd() -> [132]u32 { ret [132]u32{ 14u32, 41u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 26u32, 43u32, 0u32, 39u32, 207u32, 75u32, 0u32, 0u32, 0u32, 0u32, 0u32, 26u32, 189u32, 119u32, 0u32, 0u32, 75u32, 206u32, 67u32, 0u32, 0u32, 0u32, 26u32, 178u32, 130u32, 0u32, 0u32, 0u32, 0u32, 67u32, 206u32, 75u32, 0u32, 26u32, 190u32, 130u32, 9u32, 0u32, 0u32, 0u32, 0u32, 0u32, 75u32, 206u32, 78u32, 178u32, 130u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 78u32, 230u32, 164u32, 9u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 26u32, 178u32, 164u32, 206u32, 67u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 26u32, 190u32, 130u32, 9u32, 67u32, 206u32, 75u32, 0u32, 0u32, 0u32, 0u32, 26u32, 178u32, 130u32, 0u32, 0u32, 0u32, 75u32, 206u32, 67u32, 0u32, 0u32, 26u32, 189u32, 130u32, 9u32, 0u32, 0u32, 0u32, 0u32, 67u32, 206u32, 72u32, 0u32, 46u32, 119u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 73u32, 129u32, 0u32 } }

// looks5: the same X on an ACTIVE caption (white ink: the capture's coverage is not linear in the ink, so the inactive table above
// is up to 5 levels off there): About, Options, Deck Properties and Missing Set Cards read the same table.
fn cross_cover_odd_active() -> [132]u32 { ret [132]u32{ 14u32, 39u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 24u32, 43u32, 0u32, 39u32, 202u32, 74u32, 0u32, 0u32, 0u32, 0u32, 0u32, 25u32, 188u32, 116u32, 0u32, 0u32, 74u32, 204u32, 65u32, 0u32, 0u32, 0u32, 25u32, 175u32, 129u32, 0u32, 0u32, 0u32, 0u32, 65u32, 204u32, 74u32, 0u32, 25u32, 188u32, 129u32, 8u32, 0u32, 0u32, 0u32, 0u32, 0u32, 74u32, 204u32, 76u32, 175u32, 129u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 76u32, 228u32, 163u32, 8u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 25u32, 175u32, 163u32, 204u32, 65u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 25u32, 188u32, 129u32, 8u32, 65u32, 204u32, 74u32, 0u32, 0u32, 0u32, 0u32, 25u32, 175u32, 129u32, 0u32, 0u32, 0u32, 74u32, 204u32, 65u32, 0u32, 0u32, 24u32, 188u32, 129u32, 8u32, 0u32, 0u32, 0u32, 0u32, 65u32, 204u32, 73u32, 0u32, 44u32, 116u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 74u32, 128u32, 0u32 } }

fn dash_cover() -> [11]u32 { ret [11]u32{ 48u32, 191u32, 191u32, 191u32, 191u32, 191u32, 191u32, 191u32, 191u32, 191u32, 143u32 } }

fn square_cover() -> [121]u32 { ret [121]u32{ 4u32, 47u32, 64u32, 64u32, 64u32, 64u32, 64u32, 64u32, 64u32, 58u32, 12u32, 47u32, 218u32, 171u32, 171u32, 171u32, 171u32, 171u32, 171u32, 171u32, 214u32, 140u32, 64u32, 171u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 98u32, 191u32, 64u32, 171u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 96u32, 191u32, 64u32, 171u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 96u32, 191u32, 64u32, 171u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 96u32, 191u32, 64u32, 171u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 96u32, 191u32, 64u32, 171u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 96u32, 191u32, 64u32, 171u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 97u32, 191u32, 58u32, 214u32, 98u32, 96u32, 96u32, 96u32, 96u32, 96u32, 97u32, 178u32, 175u32, 12u32, 140u32, 191u32, 191u32, 191u32, 191u32, 191u32, 191u32, 191u32, 175u32, 36u32 } }

fn glyph_node(a: *mem.Arena, kind: u32, ink: u32, alpha: f32, width: f32) -> (widget.Node, err) {
    let (gs, gs_error) = mem.alloc[Glyph](a, 1usize)
    if gs_error != ok { ret (zero, gs_error) }
    gs[0usize] = Glyph { kind: kind, ink: ink, alpha: alpha, width: width }
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: 31.0 }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&gs[0usize]), measure: icon_measure, paint: glyph_paint, state: widget.bytes_of[Glyph](&gs[0usize]) } }, style: s, children: none }, ok)
}

// looks4: the same glyphs of a caption whose buttons start on an odd pixel (Deck Legality, 539 wide): the dash is 10
// full pixels at x = 17 to 26, the square 10 columns from x = 17 and the X 11 columns from x = 18 of the 46 wide button.
fn square_cover_odd() -> [110]u32 { ret [110]u32{ 26u32, 62u32, 64u32, 64u32, 64u32, 64u32, 64u32, 64u32, 62u32, 26u32, 197u32, 185u32, 171u32, 171u32, 171u32, 171u32, 171u32, 171u32, 185u32, 197u32, 227u32, 36u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 33u32, 224u32, 227u32, 36u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 32u32, 223u32, 227u32, 36u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 32u32, 223u32, 227u32, 36u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 32u32, 223u32, 227u32, 36u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 32u32, 223u32, 227u32, 36u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 32u32, 223u32, 227u32, 36u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 32u32, 223u32, 227u32, 126u32, 96u32, 96u32, 96u32, 96u32, 96u32, 96u32, 125u32, 227u32, 79u32, 186u32, 191u32, 191u32, 191u32, 191u32, 191u32, 191u32, 186u32, 79u32 } }
fn cross46_cover_odd() -> [121]u32 { ret [121]u32{ 43u32, 25u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 39u32, 14u32, 116u32, 188u32, 25u32, 0u32, 0u32, 0u32, 0u32, 0u32, 74u32, 202u32, 39u32, 0u32, 129u32, 175u32, 25u32, 0u32, 0u32, 0u32, 65u32, 204u32, 74u32, 0u32, 0u32, 8u32, 129u32, 188u32, 25u32, 0u32, 74u32, 204u32, 65u32, 0u32, 0u32, 0u32, 0u32, 0u32, 129u32, 175u32, 76u32, 204u32, 74u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 8u32, 163u32, 228u32, 76u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 65u32, 204u32, 163u32, 175u32, 25u32, 0u32, 0u32, 0u32, 0u32, 0u32, 74u32, 204u32, 65u32, 8u32, 129u32, 188u32, 25u32, 0u32, 0u32, 0u32, 65u32, 204u32, 74u32, 0u32, 0u32, 0u32, 129u32, 175u32, 25u32, 0u32, 73u32, 204u32, 65u32, 0u32, 0u32, 0u32, 0u32, 8u32, 129u32, 188u32, 24u32, 131u32, 73u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 116u32, 43u32 } }

// ---- looks5: the tool window's close box -----------------------------------------------------------------------------------
// v3's Customization window (a TcxGridBandedTableCustomizationForm) is a tool window: a light caption with the title at x = 8, no
// icon, and a red close box with a white x, 22 x 23 pixels at (142, 7) of the window, from docs/ui/looks/ref/windows/states/
// dialog-customization-rest (opaque pixels over the light caption #F0F4F8; 0 is the caption showing through).
fn tool_close_pixels() -> [506]u32 { ret [506]u32{ 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFFE8D5D8u32, 0xFFE6CBCEu32, 0xFFE6CBCEu32, 0xFFE6CBCEu32, 0xFFE6CBCEu32, 0xFFE6CBCEu32, 0xFFE6CBCEu32, 0xFFE6CBCEu32, 0xFFE6CBCEu32, 0xFFE6CBCDu32, 0xFFE6CBCDu32, 0xFFE6CBCDu32, 0xFFE6CBCDu32, 0xFFE6CACDu32, 0xFFE6CACDu32, 0xFFE6CACDu32, 0xFFE6CACDu32, 0xFFE6CACDu32, 0xFFE6CACDu32, 0xFFE6CACDu32, 0xFFEDE9EDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFCB5B5Bu32, 0xFFD57C7Cu32, 0xFFD27171u32, 0xFFC75050u32, 0xFFCB5B5Bu32, 0xFFD57C7Cu32, 0xFFD27171u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFCB5B5Bu32, 0xFFF4DEDEu32, 0xFFFBF4F4u32, 0xFFD27171u32, 0xFFF4DEDEu32, 0xFFFFFFFFu32, 0xFFD27171u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFF4DEDEu32, 0xFFFFFFFFu32, 0xFFFBF4F4u32, 0xFFD27171u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFF4DEDEu32, 0xFFFFFFFFu32, 0xFFFBF4F4u32, 0xFFD27171u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFCB5B5Bu32, 0xFFF4DEDEu32, 0xFFFBF4F4u32, 0xFFD27171u32, 0xFFF4DEDEu32, 0xFFFFFFFFu32, 0xFFD27171u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFCB5B5Bu32, 0xFFD57C7Cu32, 0xFFD27171u32, 0xFFC75050u32, 0xFFCB5B5Bu32, 0xFFD57C7Cu32, 0xFFD27171u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD1797Au32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFC75050u32, 0xFFE6CACDu32, 0u32, 0xFFD9989Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFD1797Au32, 0xFFE8D4D8u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32 } }

fn tool_close_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let pixels = tool_close_pixels()
    var i = 0usize
    while i < 506usize {
        if pixels[i] != 0u32 { try winpx.fill(b, area.x + f32(i % 22usize), area.y + f32(i / 22usize), 1.0, 1.0, style.hex(pixels[i] & 0xFFFFFFu32)) }
        i += 1usize
    }
    ret ok
}

fn tool_close_node() -> widget.Node {
    var s = style.defaults()
    s.width = style.Length { Px: 22.0 }
    s.height = style.Length { Px: 23.0 }
    var none: []const widget.Node = zero
    var state: []const u8 = zero
    ret widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: zero, measure: icon_measure, paint: tool_close_paint, state: state } }, style: s, children: none }
}
