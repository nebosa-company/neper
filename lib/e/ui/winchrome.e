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
use e.ui.widget

fn icon_pixels() -> [256]u32 { ret [256]u32{ 0u32, 0u32, 0u32, 0u32, 0xFF54432Fu32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF8B7A5Fu32, 0xFF212120u32, 0u32, 0xFF524938u32, 0xFF202122u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF806F4Fu32, 0xFF402911u32, 0u32, 0xFF6A5D36u32, 0xFF312C1Du32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF222121u32, 0u32, 0u32, 0xFF846E41u32, 0xFF663B10u32, 0u32, 0xFF7C6C35u32, 0xFF523811u32, 0xFF202122u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF202123u32, 0xFF4C3D29u32, 0u32, 0u32, 0xFF5E5031u32, 0xFF936326u32, 0xFF221F1Eu32, 0xFF6C6134u32, 0xFF754C12u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF222323u32, 0xFF735A25u32, 0xFF202121u32, 0u32, 0xFF2E2B25u32, 0xFFA1762Du32, 0xFF312210u32, 0xFF554D2Eu32, 0xFF94621Fu32, 0xFF222220u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF202122u32, 0xFFA58238u32, 0xFF2B1D0Fu32, 0xFF4A2F1Fu32, 0xFF391B17u32, 0xFFA67C2Bu32, 0xFF51310Au32, 0xFF51482Bu32, 0xFF8E5F1Cu32, 0xFF27261Fu32, 0u32, 0u32, 0xFF232221u32, 0xFF2E2C29u32, 0u32, 0u32, 0u32, 0xFF6F6131u32, 0xFF663E15u32, 0xFF5F2E18u32, 0xFF633613u32, 0xFFD9B640u32, 0xFF8A6910u32, 0xFF887136u32, 0xFF7B5114u32, 0xFF2C291Fu32, 0u32, 0xFF68562Du32, 0xFF4E3113u32, 0xFF272525u32, 0u32, 0u32, 0u32, 0xFF2F2F24u32, 0xFFAE7E3Au32, 0xFF502909u32, 0xFF996529u32, 0xFF8D7122u32, 0xFFAA822Fu32, 0xFF75591Du32, 0xFF764A14u32, 0xFF35321Eu32, 0xFF212222u32, 0xFF8D6722u32, 0xFF3B230Au32, 0u32, 0u32, 0u32, 0u32, 0xFF202021u32, 0xFFAE8B44u32, 0xFF7E571Bu32, 0xFFB17F39u32, 0xFF724F12u32, 0xFFAB7D36u32, 0xFF624511u32, 0xFF895B1Fu32, 0xFF5D4616u32, 0xFF775528u32, 0xFF7A5314u32, 0xFF241E18u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF5E512Du32, 0xFFBD9541u32, 0xFF935322u32, 0xFF875D1Cu32, 0xFFA4772Du32, 0xFF55390Du32, 0xFF8D5D1Du32, 0xFF755013u32, 0xFF936623u32, 0xFF49350Cu32, 0xFF202122u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF292722u32, 0xFFDBB15Au32, 0xFF824C16u32, 0xFFA47838u32, 0xFFA0792Cu32, 0xFF4C320Cu32, 0xFF9E6A1Eu32, 0xFF63450Eu32, 0xFF654514u32, 0xFF282418u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF99803Au32, 0xFFAC7F35u32, 0xFFAC7D40u32, 0xFF8B681Fu32, 0xFF55370Eu32, 0xFF855618u32, 0xFF573C0Du32, 0xFF3D2C12u32, 0xFF202021u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF3D3724u32, 0xFFD3A24Eu32, 0xFF96642Fu32, 0xFF88631Au32, 0xFF644010u32, 0xFF744813u32, 0xFF533A0Du32, 0xFF26231Du32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF202122u32, 0xFF715D32u32, 0xFFA97A3Fu32, 0xFF9A7126u32, 0xFF724812u32, 0xFF724910u32, 0xFF4F370Bu32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 0xFF34311Eu32, 0xFFC99752u32, 0xFF9C702Au32, 0xFF744813u32, 0xFF59380Cu32, 0xFF3F2C08u32, 0xFF1F1F21u32, 0u32, 0u32, 0u32, 0u32, 0u32 } }

fn icon_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

fn icon_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let pixels = icon_pixels()
    var i = 0usize
    while i < 256usize {
        if pixels[i] != 0u32 {
            try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: area.x + f32(i % 16usize), y: area.y + f32(i / 16usize), width: 1.0, height: 1.0 }, brush: paint.Brush { Solid: style.hex(pixels[i] & 0xFFFFFFu32) } } })
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
    var c = style.hex(ink)
    c.alpha = alpha
    ret scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: area.x + x, y: area.y + y, width: w, height: h }, brush: paint.Brush { Solid: c } } })
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
    if g.kind == 3u32 {
        let odd = cross_cover_odd()
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
