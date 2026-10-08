// The sample scenes of the NeperOS camera and photo apps (D2217, D2218): small pictures drawn as svg at
// run time -- a sunset over a lake, a portrait, a document on a desk, a city at night, a beach, a snowy
// mountain -- because the machine has no camera and no photo files. A scene is a function of its kind and
// a seed, so the same capture draws the same every time. `scene_svg` answers an svg document for e.gfx.svg.
use e.mem

// The world the scenes are drawn in: the 412 x 560 viewfinder sits at (OX, OY) inside it, so every
// number is positive and a wide shot (0.5x) can show what lies beyond the frame.
const OX: usize = 400usize
const OY: usize = 300usize

// ----------------------------------------------------------------------------------------------
// svg builders.

// Append `piece` to `buffer` at `at`; the new end.
fn emit(buffer: []u8, at: usize, piece: str) -> usize {
    var n = at
    var i = 0usize
    while i < piece.len && n < buffer.len {
        buffer[n] = piece[i]
        n += 1usize
        i += 1usize
    }
    ret n
}

fn emit_num(buffer: []u8, at: usize, value: usize) -> usize {
    var digits: [20]u8 = zero
    var d = 20usize
    var rest = value
    var open = true
    while open {
        d -= 1usize
        digits[d] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    ret emit(buffer, at, digits[d..20usize])
}

fn e_rect(b: []u8, n: usize, x: usize, y: usize, w: usize, h: usize, color: str) -> usize {
    var m = emit(b, n, "<rect x='")
    m = emit_num(b, m, x)
    m = emit(b, m, "' y='")
    m = emit_num(b, m, y)
    m = emit(b, m, "' width='")
    m = emit_num(b, m, w)
    m = emit(b, m, "' height='")
    m = emit_num(b, m, h)
    m = emit(b, m, "' fill='")
    m = emit(b, m, color)
    ret emit(b, m, "'/>")
}

fn e_circle(b: []u8, n: usize, cx: usize, cy: usize, r: usize, color: str) -> usize {
    var m = emit(b, n, "<circle cx='")
    m = emit_num(b, m, cx)
    m = emit(b, m, "' cy='")
    m = emit_num(b, m, cy)
    m = emit(b, m, "' r='")
    m = emit_num(b, m, r)
    m = emit(b, m, "' fill='")
    m = emit(b, m, color)
    ret emit(b, m, "'/>")
}

// A band of the world from `ya` to `yb`, cut at `top` (the first row the scene reaches).
fn e_band(b: []u8, n: usize, x0: usize, x1: usize, top: usize, ya: usize, yb: usize, color: str) -> usize {
    var lo = ya
    if lo < top { lo = top }
    if yb <= lo { ret n }
    ret e_rect(b, n, x0, lo, x1 - x0, yb - lo, color)
}

// A closed polygon through the (x, y) pairs of `pts`, its x kept between `lo` and `hi`.
fn e_poly(b: []u8, n: usize, lo: usize, hi: usize, pts: []const usize, color: str) -> usize {
    var m = emit(b, n, "<path d='")
    var i = 0usize
    while i + 1usize < pts.len {
        if i == 0usize { m = emit(b, m, "M") } else { m = emit(b, m, " L") }
        var px = pts[i]
        if px < lo { px = lo }
        if px > hi { px = hi }
        m = emit_num(b, m, px)
        m = emit(b, m, " ")
        m = emit_num(b, m, pts[i + 1usize])
        i += 2usize
    }
    m = emit(b, m, " Z' fill='")
    m = emit(b, m, color)
    ret emit(b, m, "'/>")
}

fn zoom_text(zoom: usize) -> str {
    if zoom == 0usize { ret "0.5" }
    if zoom == 1usize { ret "1" }
    if zoom == 2usize { ret "2" }
    if zoom == 4usize { ret "0.35" }
    if zoom == 5usize { ret "0.46" }
    ret "5"
}

fn zoom_label(zoom: usize) -> str {
    if zoom == 0usize { ret "0.5" }
    if zoom == 1usize { ret "1x" }
    if zoom == 2usize { ret "2x" }
    ret "5x"
}

// kind 0: a sunset over a lake, 1: a portrait, 2: a document on a desk, 3: a city at night, 4: a beach,
// 5: a snowy mountain. `seed` moves the sun, the paper, the buildings; `zoom` scales about the centre;
// `wide` draws the world past the frame (for 0.5x), otherwise it ends at the frame so nothing spills out
// of a thumbnail. The picture is `vw` x `vh` units with the scene's centre in its middle, so a square
// thumbnail shows the middle of a tall scene.
fn scene_svg(a: *mem.Arena, kind: usize, seed: usize, zoom: usize, wide: bool, vw: usize, vh: usize) -> str {
    let (b, b_error) = mem.alloc[u8](a, 9000usize)
    if b_error != ok { ret "" }
    var x0 = OX
    var x1 = OX + 412usize
    var y0 = OY
    var y1 = OY + 560usize
    if wide {
        x0 = 0usize
        x1 = OX * 2usize + 412usize
        y0 = 0usize
        y1 = OY * 2usize + 560usize
    }
    var n = 0usize
    n = emit(b, n, "<svg viewBox='0 0 ")
    n = emit_num(b, n, vw)
    n = emit(b, n, " ")
    n = emit_num(b, n, vh)
    n = emit(b, n, "'><g transform='translate(")
    n = emit_num(b, n, vw / 2usize)
    n = emit(b, n, " ")
    n = emit_num(b, n, vh / 2usize)
    n = emit(b, n, ") scale(")
    n = emit(b, n, zoom_text(zoom))
    n = emit(b, n, ") translate(-606 -580)'>")
    if kind == 0usize {
        // The sky in bands, the horizon at 600.
        n = e_band(b, n, x0, x1, y0, 0usize, 200usize, "#1c2a52")
        n = e_band(b, n, x0, x1, y0, 200usize, 360usize, "#3b4a80")
        n = e_band(b, n, x0, x1, y0, 360usize, 450usize, "#8a6aa0")
        n = e_band(b, n, x0, x1, y0, 450usize, 520usize, "#d98a7a")
        n = e_band(b, n, x0, x1, y0, 520usize, 570usize, "#f0b27a")
        n = e_band(b, n, x0, x1, y0, 570usize, 600usize, "#f6d49a")
        let sun_x = OX + 150usize + (seed * 53usize) % 160usize
        n = e_circle(b, n, sun_x, 568usize, 54usize, "#f8d8a0")
        n = e_circle(b, n, sun_x, 568usize, 34usize, "#fff1c4")
        // The far mountains and the nearer hills.
        let far: [22]usize = [22]usize{ x0, 600usize, 520usize, 530usize, 600usize, 570usize, 700usize, 500usize, 780usize, 560usize, 860usize, 515usize, 960usize, 570usize, 1040usize, 525usize, 1100usize, 575usize, 1160usize, 520usize, x1, 600usize }
        n = e_poly(b, n, x0, x1, far[0usize..22usize], "#5c4a7a")
        let near: [14]usize = [14]usize{ x0, 600usize, 560usize, 570usize, 660usize, 590usize, 780usize, 555usize, 900usize, 590usize, 1000usize, 560usize, x1, 600usize }
        n = e_poly(b, n, x0, x1, near[0usize..14usize], "#3a3f66")
        // The lake and the sun's reflection.
        n = e_rect(b, n, x0, 600usize, x1 - x0, 140usize, "#4a6a9a")
        n = e_rect(b, n, sun_x - 30usize, 606usize, 60usize, 4usize, "#f6d49a")
        n = e_rect(b, n, sun_x - 20usize, 618usize, 40usize, 4usize, "#e8b88a")
        n = e_rect(b, n, sun_x - 12usize, 632usize, 24usize, 4usize, "#e8b88a")
        // The shore and two pines.
        let shore: [20]usize = [20]usize{ x0, y1, x0, 745usize, 520usize, 720usize, 640usize, 750usize, 760usize, 730usize, 900usize, 745usize, 1000usize, 715usize, x1, 740usize, x1, y1, x0, y1 }
        n = e_poly(b, n, x0, x1, shore[0usize..20usize], "#1c2333")
        let pine_a: [6]usize = [6]usize{ 480usize, 640usize, 452usize, 730usize, 508usize, 730usize }
        n = e_poly(b, n, x0, x1, pine_a[0usize..6usize], "#11151f")
        let pine_b: [6]usize = [6]usize{ 480usize, 690usize, 444usize, 790usize, 516usize, 790usize }
        n = e_poly(b, n, x0, x1, pine_b[0usize..6usize], "#11151f")
        let pine_c: [6]usize = [6]usize{ 700usize, 650usize, 672usize, 740usize, 728usize, 740usize }
        n = e_poly(b, n, x0, x1, pine_c[0usize..6usize], "#11151f")
        let pine_d: [6]usize = [6]usize{ 700usize, 700usize, 664usize, 800usize, 736usize, 800usize }
        n = e_poly(b, n, x0, x1, pine_d[0usize..6usize], "#11151f")
    } else if kind == 1usize {
        // A portrait against a pink wall with a window of light.
        n = e_rect(b, n, x0, y0, x1 - x0, y1 - y0, "#c98a96")
        n = e_rect(b, n, 640usize, 330usize, 150usize, 190usize, "#e8b9bf")
        let shoulders: [16]usize = [16]usize{ 400usize, y1, 420usize, 880usize, 520usize, 800usize, 556usize, 760usize, 656usize, 760usize, 692usize, 800usize, 792usize, 880usize, 812usize, y1 }
        n = e_poly(b, n, x0, x1, shoulders[0usize..16usize], "#3c4a6a")
        n = e_rect(b, n, 576usize, 730usize, 60usize, 50usize, "#d9a584")
        n = e_circle(b, n, 606usize, 640usize, 96usize, "#2b2118")
        n = e_circle(b, n, 606usize, 672usize, 84usize, "#e6b894")
        n = e_circle(b, n, 578usize, 668usize, 7usize, "#2b2118")
        n = e_circle(b, n, 634usize, 668usize, 7usize, "#2b2118")
        n = emit(b, n, "<path d='M580 702 Q606 724 632 702' fill='none' stroke='#8a4a4a' stroke-width='5' stroke-linecap='round'/>")
    } else if kind == 2usize {
        // A sheet of paper on a desk, slightly turned.
        n = e_rect(b, n, x0, y0, x1 - x0, y1 - y0, "#3a2a20")
        var grain = 0usize
        while grain < 8usize {
            n = e_rect(b, n, x0, 330usize + grain * 70usize, x1 - x0, 3usize, "#4a3628")
            grain += 1usize
        }
        let turn = 3usize + seed % 5usize
        n = emit(b, n, "<g transform='rotate(-")
        n = emit_num(b, n, turn)
        n = emit(b, n, " 606 580)'>")
        n = e_rect(b, n, 478usize, 366usize, 272usize, 440usize, "#1f1610")
        n = e_rect(b, n, 470usize, 360usize, 272usize, 440usize, "#f2efe6")
        n = e_rect(b, n, 500usize, 392usize, 120usize, 16usize, "#2b3a55")
        var line = 0usize
        while line < 10usize {
            var w = 200usize
            if line % 4usize == 3usize { w = 140usize }
            n = e_rect(b, n, 500usize, 432usize + line * 30usize, w, 8usize, "#9a9a9a")
            line += 1usize
        }
        n = e_circle(b, n, 690usize, 750usize, 22usize, "#d9a0a0")
        n = emit(b, n, "</g>")
    } else if kind == 3usize {
        // A city at night: a dark sky with stars, a glow at the horizon, lit towers.
        n = e_band(b, n, x0, x1, y0, 0usize, 360usize, "#0d1230")
        n = e_band(b, n, x0, x1, y0, 360usize, 470usize, "#1b2250")
        n = e_band(b, n, x0, x1, y0, 470usize, 560usize, "#2d2f6b")
        n = e_band(b, n, x0, x1, y0, 560usize, 640usize, "#4a3f7a")
        n = e_band(b, n, x0, x1, y0, 640usize, 760usize, "#7a5a8a")
        var star = 0usize
        while star < 9usize {
            n = e_circle(b, n, OX + 20usize + (star * 97usize + seed * 13usize) % 380usize, OY + 20usize + (star * 53usize) % 200usize, 2usize, "#e8ebf0")
            star += 1usize
        }
        var tower = 0usize
        while tower < 9usize {
            let height = 130usize + (seed * 7usize + tower * 37usize) % 170usize
            let left = OX + tower * 46usize
            var colour = "#121626"
            if tower % 2usize == 1usize { colour = "#1a1f36" }
            n = e_rect(b, n, left, 860usize - height, 42usize, height, colour)
            var row = 0usize
            while row < 6usize {
                var column = 0usize
                while column < 3usize {
                    if (seed + tower * 7usize + row * 13usize + column * 5usize) % 3usize != 0usize && row * 22usize + 14usize < height {
                        n = e_rect(b, n, left + 6usize + column * 12usize, 860usize - height + 10usize + row * 22usize, 6usize, 9usize, "#f0c070")
                    }
                    column += 1usize
                }
                row += 1usize
            }
            tower += 1usize
        }
        n = e_rect(b, n, x0, 860usize, x1 - x0, y1 - 860usize, "#0a0c18")
    } else if kind == 4usize {
        // A beach: a pale sky and sun, the sea in two bands, sand, an umbrella and a towel.
        n = e_band(b, n, x0, x1, y0, 0usize, 420usize, "#6fb4e8")
        n = e_band(b, n, x0, x1, y0, 420usize, 560usize, "#9ccbee")
        n = e_band(b, n, x0, x1, y0, 560usize, 640usize, "#cfe6f5")
        let sun_x = OX + 60usize + (seed * 41usize) % 260usize
        n = e_circle(b, n, sun_x, 470usize, 44usize, "#fff4c0")
        n = e_band(b, n, x0, x1, y0, 640usize, 720usize, "#3b8fc2")
        n = e_band(b, n, x0, x1, y0, 720usize, 770usize, "#62b3d6")
        n = e_rect(b, n, x0, 764usize, x1 - x0, 6usize, "#ffffff")
        n = e_rect(b, n, x0, 770usize, x1 - x0, y1 - 770usize, "#e8d3a0")
        n = e_rect(b, n, 650usize, 740usize, 5usize, 80usize, "#8a6a4a")
        let canopy: [6]usize = [6]usize{ 596usize, 746usize, 652usize, 700usize, 708usize, 746usize }
        n = e_poly(b, n, x0, x1, canopy[0usize..6usize], "#d9544f")
        let stripe: [6]usize = [6]usize{ 626usize, 746usize, 652usize, 700usize, 664usize, 746usize }
        n = e_poly(b, n, x0, x1, stripe[0usize..6usize], "#f2efe6")
        n = e_rect(b, n, 580usize, 818usize, 90usize, 28usize, "#f2c14e")
    } else {
        // A snowy mountain: a clear sky, a range with white caps, a dark forest in front.
        n = e_band(b, n, x0, x1, y0, 0usize, 300usize, "#1f3b6e")
        n = e_band(b, n, x0, x1, y0, 300usize, 420usize, "#4a6fa5")
        n = e_band(b, n, x0, x1, y0, 420usize, 520usize, "#8fb0d0")
        n = e_band(b, n, x0, x1, y0, 520usize, 700usize, "#cfe0ee")
        let peak = 520usize + (seed * 17usize) % 60usize
        let range: [16]usize = [16]usize{ x0, 760usize, 470usize, 600usize, 540usize, 640usize, 610usize, peak, 680usize, 620usize, 740usize, 570usize, 800usize, 660usize, x1, 760usize }
        n = e_poly(b, n, x0, x1, range[0usize..16usize], "#5a6a88")
        let cap: [8]usize = [8]usize{ 610usize, peak, 576usize, peak + 44usize, 606usize, peak + 30usize, 640usize, peak + 50usize }
        n = e_poly(b, n, x0, x1, cap[0usize..8usize], "#f2f6fa")
        let cap_two: [6]usize = [6]usize{ 740usize, 570usize, 716usize, 606usize, 764usize, 606usize }
        n = e_poly(b, n, x0, x1, cap_two[0usize..6usize], "#f2f6fa")
        let hill: [12]usize = [12]usize{ x0, y1, x0, 790usize, 500usize, 750usize, 700usize, 780usize, x1, 760usize, x1, y1 }
        n = e_poly(b, n, x0, x1, hill[0usize..12usize], "#2b4a3a")
        var pine = 0usize
        while pine < 5usize {
            let px = 430usize + pine * 80usize
            let pt: [6]usize = [6]usize{ px, 740usize + (pine % 2usize) * 20usize, px - 30usize, 830usize, px + 30usize, 830usize }
            n = e_poly(b, n, x0, x1, pt[0usize..6usize], "#173324")
            pine += 1usize
        }
    }
    n = emit(b, n, "</g></svg>")
    ret b[0usize..n]
}
