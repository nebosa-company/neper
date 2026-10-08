// The 2.5D styling helpers of e.gfx.chart against a numpy replay (L093, D2261;
// scripts/chart_25d_reference.py writes this file): extruded bar faces under the fixed oblique offset, tilted
// thick pies (sector tops and visible walls), the invariants a replay does not share (parallelogram areas by
// shoelace, the visible wall arc, the footprint inside the bounds) and every refusal. Every check has its
// own exit code.
use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem
use e.os

fn zero_f32() -> f32 { ret 0.0f32 }

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn closef(got: f32, want: f64) -> bool {
    ret abs64(f64(got) - want) <= 0.0006f64 * (1.0f64 + abs64(want))
}

fn shoelace(poly: []chart.Coord) -> f32 {
    var twice = 0.0f64
    var i = 0usize
    while i < poly.len {
        let next = (i + 1usize) % poly.len
        twice += f64(poly[i].x) * f64(poly[next].y) - f64(poly[next].x) * f64(poly[i].y)
        i += 1usize
    }
    if twice < 0.0f64 { twice = 0.0f64 - twice }
    ret f32(twice * 0.5f64)
}

// Total angle covered by the wall arcs: each wall has wall_steps + 1 arc points on its top rim, which are the
// first half of its coordinates; the angle is recovered from the x extent of the rim on the unit circle.
fn wall_arc(walls: []chart.Layout, values: []const f32) -> f32 {
    var total = 0.0f64
    var all = 0.0f64
    var i = 0usize
    while i < values.len {
        all += f64(values[i])
        i += 1usize
    }
    var cumulative = 0.0f64
    i = 0usize
    while i < values.len {
        let start = -1.5707963267948966f64 + 6.283185307179586f64 * cumulative / all
        cumulative += f64(values[i])
        let finish = start + 6.283185307179586f64 * f64(values[i]) / all
        var low = start
        if low < 0.0f64 { low = 0.0f64 }
        var high = finish
        if high > 3.141592653589793f64 { high = 3.141592653589793f64 }
        if walls[i].coords.len != 0usize && high > low { total += high - low }
        i += 1usize
    }
    ret f32(total)
}

fn inside_bounds(layers: []chart.Layout, b: geometry.Rect) -> bool {
    var i = 0usize
    while i < layers.len {
        var j = 0usize
        while j < layers[i].coords.len {
            let p = layers[i].coords[j]
            if p.x < b.x - 0.01 || p.x > b.x + b.width + 0.01 || p.y < b.y - 0.01 || p.y > b.y + b.height + 0.01 { ret false }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let fronts = [6]geometry.Rect{ geometry.rect(20.0, 100.41, 28.0, 43.37), geometry.rect(60.0, 40.44, 28.0, 70.91), geometry.rect(100.0, 83.64, 28.0, 38.47), geometry.rect(140.0, 81.0, 28.0, 0.0), geometry.rect(180.0, 77.51, 28.0, 34.63), geometry.rect(220.0, 74.72, 28.0, 79.41) }
    var bar_points: [48]chart.Coord = zero
    var bar_tops: [6]chart.Layout = zero
    var bar_sides: [6]chart.Layout = zero
    let (extruded, extrude_error) = chart.extrude_bars(fronts[..], 18.0, bar_points[..], bar_tops[..], bar_sides[..])
    if extrude_error != ok || extruded.tops.len != 6usize || extruded.sides.len != 6usize { os.exit(1) }
    if extruded.tops[0].coords.len != 4usize || extruded.sides[0].coords.len != 4usize || extruded.tops[0].kind != .Area || !closef(extruded.tops[0].coords[0].x, 20.0000) || !closef(extruded.tops[0].coords[0].y, 100.4100) || !closef(extruded.tops[0].coords[1].x, 48.0000) || !closef(extruded.tops[0].coords[1].y, 100.4100) || !closef(extruded.tops[0].coords[2].x, 57.0000) || !closef(extruded.tops[0].coords[2].y, 91.4100) || !closef(extruded.tops[0].coords[3].x, 29.0000) || !closef(extruded.tops[0].coords[3].y, 91.4100) || !closef(extruded.sides[0].coords[0].x, 48.0000) { os.exit(2) }
    if !closef(extruded.sides[0].coords[0].y, 100.4100) || !closef(extruded.sides[0].coords[1].x, 57.0000) || !closef(extruded.sides[0].coords[1].y, 91.4100) || !closef(extruded.sides[0].coords[2].x, 57.0000) || !closef(extruded.sides[0].coords[2].y, 134.7800) || !closef(extruded.sides[0].coords[3].x, 48.0000) || !closef(extruded.sides[0].coords[3].y, 143.7800) || extruded.tops[1].coords.len != 4usize || extruded.sides[1].coords.len != 4usize || extruded.tops[1].kind != .Area || !closef(extruded.tops[1].coords[0].x, 60.0000) || !closef(extruded.tops[1].coords[0].y, 40.4400) { os.exit(3) }
    if !closef(extruded.tops[1].coords[1].x, 88.0000) || !closef(extruded.tops[1].coords[1].y, 40.4400) || !closef(extruded.tops[1].coords[2].x, 97.0000) || !closef(extruded.tops[1].coords[2].y, 31.4400) || !closef(extruded.tops[1].coords[3].x, 69.0000) || !closef(extruded.tops[1].coords[3].y, 31.4400) || !closef(extruded.sides[1].coords[0].x, 88.0000) || !closef(extruded.sides[1].coords[0].y, 40.4400) || !closef(extruded.sides[1].coords[1].x, 97.0000) || !closef(extruded.sides[1].coords[1].y, 31.4400) || !closef(extruded.sides[1].coords[2].x, 97.0000) || !closef(extruded.sides[1].coords[2].y, 102.3500) { os.exit(4) }
    if !closef(extruded.sides[1].coords[3].x, 88.0000) || !closef(extruded.sides[1].coords[3].y, 111.3500) || extruded.tops[2].coords.len != 4usize || extruded.sides[2].coords.len != 4usize || extruded.tops[2].kind != .Area || !closef(extruded.tops[2].coords[0].x, 100.0000) || !closef(extruded.tops[2].coords[0].y, 83.6400) || !closef(extruded.tops[2].coords[1].x, 128.0000) || !closef(extruded.tops[2].coords[1].y, 83.6400) || !closef(extruded.tops[2].coords[2].x, 137.0000) || !closef(extruded.tops[2].coords[2].y, 74.6400) || !closef(extruded.tops[2].coords[3].x, 109.0000) { os.exit(5) }
    if !closef(extruded.tops[2].coords[3].y, 74.6400) || !closef(extruded.sides[2].coords[0].x, 128.0000) || !closef(extruded.sides[2].coords[0].y, 83.6400) || !closef(extruded.sides[2].coords[1].x, 137.0000) || !closef(extruded.sides[2].coords[1].y, 74.6400) || !closef(extruded.sides[2].coords[2].x, 137.0000) || !closef(extruded.sides[2].coords[2].y, 113.1100) || !closef(extruded.sides[2].coords[3].x, 128.0000) || !closef(extruded.sides[2].coords[3].y, 122.1100) || extruded.tops[3].coords.len != 4usize || extruded.sides[3].coords.len != 4usize || extruded.tops[3].kind != .Area { os.exit(6) }
    if !closef(extruded.tops[3].coords[0].x, 140.0000) || !closef(extruded.tops[3].coords[0].y, 81.0000) || !closef(extruded.tops[3].coords[1].x, 168.0000) || !closef(extruded.tops[3].coords[1].y, 81.0000) || !closef(extruded.tops[3].coords[2].x, 177.0000) || !closef(extruded.tops[3].coords[2].y, 72.0000) || !closef(extruded.tops[3].coords[3].x, 149.0000) || !closef(extruded.tops[3].coords[3].y, 72.0000) || !closef(extruded.sides[3].coords[0].x, 168.0000) || !closef(extruded.sides[3].coords[0].y, 81.0000) || !closef(extruded.sides[3].coords[1].x, 177.0000) || !closef(extruded.sides[3].coords[1].y, 72.0000) { os.exit(7) }
    if !closef(extruded.sides[3].coords[2].x, 177.0000) || !closef(extruded.sides[3].coords[2].y, 72.0000) || !closef(extruded.sides[3].coords[3].x, 168.0000) || !closef(extruded.sides[3].coords[3].y, 81.0000) || extruded.tops[4].coords.len != 4usize || extruded.sides[4].coords.len != 4usize || extruded.tops[4].kind != .Area || !closef(extruded.tops[4].coords[0].x, 180.0000) || !closef(extruded.tops[4].coords[0].y, 77.5100) || !closef(extruded.tops[4].coords[1].x, 208.0000) || !closef(extruded.tops[4].coords[1].y, 77.5100) || !closef(extruded.tops[4].coords[2].x, 217.0000) { os.exit(8) }
    if !closef(extruded.tops[4].coords[2].y, 68.5100) || !closef(extruded.tops[4].coords[3].x, 189.0000) || !closef(extruded.tops[4].coords[3].y, 68.5100) || !closef(extruded.sides[4].coords[0].x, 208.0000) || !closef(extruded.sides[4].coords[0].y, 77.5100) || !closef(extruded.sides[4].coords[1].x, 217.0000) || !closef(extruded.sides[4].coords[1].y, 68.5100) || !closef(extruded.sides[4].coords[2].x, 217.0000) || !closef(extruded.sides[4].coords[2].y, 103.1400) || !closef(extruded.sides[4].coords[3].x, 208.0000) || !closef(extruded.sides[4].coords[3].y, 112.1400) || extruded.tops[5].coords.len != 4usize { os.exit(9) }
    if extruded.sides[5].coords.len != 4usize || extruded.tops[5].kind != .Area || !closef(extruded.tops[5].coords[0].x, 220.0000) || !closef(extruded.tops[5].coords[0].y, 74.7200) || !closef(extruded.tops[5].coords[1].x, 248.0000) || !closef(extruded.tops[5].coords[1].y, 74.7200) || !closef(extruded.tops[5].coords[2].x, 257.0000) || !closef(extruded.tops[5].coords[2].y, 65.7200) || !closef(extruded.tops[5].coords[3].x, 229.0000) || !closef(extruded.tops[5].coords[3].y, 65.7200) || !closef(extruded.sides[5].coords[0].x, 248.0000) || !closef(extruded.sides[5].coords[0].y, 74.7200) { os.exit(10) }
    if !closef(extruded.sides[5].coords[1].x, 257.0000) || !closef(extruded.sides[5].coords[1].y, 65.7200) || !closef(extruded.sides[5].coords[2].x, 257.0000) || !closef(extruded.sides[5].coords[2].y, 145.1300) || !closef(extruded.sides[5].coords[3].x, 248.0000) || !closef(extruded.sides[5].coords[3].y, 154.1300) { os.exit(11) }
    if !closef(shoelace(extruded.tops[0].coords), 252.0000) || !closef(shoelace(extruded.sides[0].coords), 390.3300) || !closef(shoelace(extruded.tops[1].coords), 252.0000) || !closef(shoelace(extruded.sides[1].coords), 638.1900) || !closef(shoelace(extruded.tops[2].coords), 252.0000) || !closef(shoelace(extruded.sides[2].coords), 346.2300) || !closef(shoelace(extruded.tops[3].coords), 252.0000) || !closef(shoelace(extruded.sides[3].coords), 0.0000) || !closef(shoelace(extruded.tops[4].coords), 252.0000) || !closef(shoelace(extruded.sides[4].coords), 311.6700) || !closef(shoelace(extruded.tops[5].coords), 252.0000) || !closef(shoelace(extruded.sides[5].coords), 714.6900) { os.exit(12) }
    let (flat, flat_error) = chart.extrude_bars(fronts[..1usize], 0.0, bar_points[..], bar_tops[..], bar_sides[..])
    if flat_error != ok || !closef(shoelace(flat.tops[0].coords), 0.0) || !closef(flat.sides[0].coords[2].x, 48.0000) { os.exit(13) }
    let nan = 0.0f32 / zero_f32()
    let (_, depth_negative) = chart.extrude_bars(fronts[..], -1.0, bar_points[..], bar_tops[..], bar_sides[..])
    let (_, depth_nan) = chart.extrude_bars(fronts[..], nan, bar_points[..], bar_tops[..], bar_sides[..])
    let (_, extrude_none) = chart.extrude_bars(fronts[..0usize], 1.0, bar_points[..], bar_tops[..], bar_sides[..])
    let thin = [1]geometry.Rect{ geometry.Rect { x: 0.0, y: 0.0, width: 0.0, height: 5.0 } }
    let (_, width_zero) = chart.extrude_bars(thin[..], 1.0, bar_points[..], bar_tops[..], bar_sides[..])
    let upside = [1]geometry.Rect{ geometry.Rect { x: 0.0, y: 0.0, width: 5.0, height: -5.0 } }
    let (_, height_negative) = chart.extrude_bars(upside[..], 1.0, bar_points[..], bar_tops[..], bar_sides[..])
    let (_, extrude_points) = chart.extrude_bars(fronts[..], 1.0, bar_points[..47], bar_tops[..], bar_sides[..])
    let (_, extrude_tops) = chart.extrude_bars(fronts[..], 1.0, bar_points[..], bar_tops[..5], bar_sides[..])
    let (_, extrude_sides) = chart.extrude_bars(fronts[..], 1.0, bar_points[..], bar_tops[..], bar_sides[..5])
    if depth_negative != chart.Invalid { os.exit(14) }
    if depth_nan != chart.Invalid { os.exit(15) }
    if extrude_none != chart.Empty { os.exit(16) }
    if width_zero != chart.Invalid { os.exit(17) }
    if height_negative != chart.Invalid { os.exit(18) }
    if extrude_points != chart.TooLarge { os.exit(19) }
    if extrude_tops != chart.TooLarge { os.exit(20) }
    if extrude_sides != chart.TooLarge { os.exit(21) }
    let pie_values = [6]f32{ 30.0f32, 0.0f32, 22.0f32, 9.0f32, 18.0f32, 21.0f32 }
    let pie_bounds = geometry.rect(20.0, 30.0, 260.0, 170.0)
    var pie_points: [1200]chart.Coord = zero
    var pie_tops: [6]chart.Layout = zero
    var pie_walls: [6]chart.Layout = zero
    let (pie, pie_error) = chart.pie_25d(pie_values[..], pie_bounds, 0.55, 14.0, pie_points[..], pie_tops[..], pie_walls[..])
    if pie_error != ok || pie.tops.len != 6usize || pie.sides.len != 6usize { os.exit(22) }
    if pie.tops[0].coords.len != 32usize || !closef(pie.tops[0].coords[0].x, 150.0000) || !closef(pie.tops[0].coords[0].y, 101.5000) || !closef(pie.tops[0].coords[1].x, 150.0000) || !closef(pie.tops[0].coords[1].y, 30.0000) || !closef(pie.tops[0].coords[2].x, 158.1628) || !closef(pie.tops[0].coords[2].y, 30.1411) || !closef(pie.tops[0].coords[3].x, 166.2933) || !closef(pie.tops[0].coords[3].y, 30.5638) || !closef(pie.tops[0].coords[4].x, 174.3596) || !closef(pie.tops[0].coords[4].y, 31.2665) || !closef(pie.tops[0].coords[5].x, 182.3297) { os.exit(23) }
    if !closef(pie.tops[0].coords[5].y, 32.2463) || !closef(pie.tops[0].coords[6].x, 190.1722) || !closef(pie.tops[0].coords[6].y, 33.4995) || !closef(pie.tops[0].coords[7].x, 197.8562) || !closef(pie.tops[0].coords[7].y, 35.0210) || !closef(pie.tops[0].coords[8].x, 205.3513) || !closef(pie.tops[0].coords[8].y, 36.8049) || !closef(pie.tops[0].coords[9].x, 212.6280) || !closef(pie.tops[0].coords[9].y, 38.8441) || !closef(pie.tops[0].coords[10].x, 219.6575) || !closef(pie.tops[0].coords[10].y, 41.1306) || !closef(pie.tops[0].coords[11].x, 226.4121) { os.exit(24) }
    if !closef(pie.tops[0].coords[11].y, 43.6553) || !closef(pie.tops[0].coords[12].x, 232.8651) || !closef(pie.tops[0].coords[12].y, 46.4083) || !closef(pie.tops[0].coords[13].x, 238.9911) || !closef(pie.tops[0].coords[13].y, 49.3787) || !closef(pie.tops[0].coords[14].x, 244.7659) || !closef(pie.tops[0].coords[14].y, 52.5549) || !closef(pie.tops[0].coords[15].x, 250.1667) || !closef(pie.tops[0].coords[15].y, 55.9242) || !closef(pie.tops[0].coords[16].x, 255.1722) || !closef(pie.tops[0].coords[16].y, 59.4734) || !closef(pie.tops[0].coords[17].x, 259.7626) { os.exit(25) }
    if !closef(pie.tops[0].coords[17].y, 63.1884) || !closef(pie.tops[0].coords[18].x, 263.9199) || !closef(pie.tops[0].coords[18].y, 67.0546) || !closef(pie.tops[0].coords[19].x, 267.6275) || !closef(pie.tops[0].coords[19].y, 71.0568) || !closef(pie.tops[0].coords[20].x, 270.8709) || !closef(pie.tops[0].coords[20].y, 75.1791) || !closef(pie.tops[0].coords[21].x, 273.6373) || !closef(pie.tops[0].coords[21].y, 79.4053) || !closef(pie.tops[0].coords[22].x, 275.9158) || !closef(pie.tops[0].coords[22].y, 83.7187) || !closef(pie.tops[0].coords[23].x, 277.6973) { os.exit(26) }
    if !closef(pie.tops[0].coords[23].y, 88.1022) || !closef(pie.tops[0].coords[24].x, 278.9749) || !closef(pie.tops[0].coords[24].y, 92.5387) || !closef(pie.tops[0].coords[25].x, 279.7435) || !closef(pie.tops[0].coords[25].y, 97.0105) || !closef(pie.tops[0].coords[26].x, 280.0000) || !closef(pie.tops[0].coords[26].y, 101.5000) || !closef(pie.tops[0].coords[27].x, 279.7435) || !closef(pie.tops[0].coords[27].y, 105.9895) || !closef(pie.tops[0].coords[28].x, 278.9749) || !closef(pie.tops[0].coords[28].y, 110.4613) || !closef(pie.tops[0].coords[29].x, 277.6973) { os.exit(27) }
    if !closef(pie.tops[0].coords[29].y, 114.8978) || !closef(pie.tops[0].coords[30].x, 275.9158) || !closef(pie.tops[0].coords[30].y, 119.2813) || !closef(pie.tops[0].coords[31].x, 273.6373) || !closef(pie.tops[0].coords[31].y, 123.5947) || pie.sides[0].coords.len != 34usize || !closef(pie.sides[0].coords[0].x, 280.0000) || !closef(pie.sides[0].coords[0].y, 101.5000) || !closef(pie.sides[0].coords[1].x, 279.9749) || !closef(pie.sides[0].coords[1].y, 102.9038) || !closef(pie.sides[0].coords[2].x, 279.8998) || !closef(pie.sides[0].coords[2].y, 104.3071) { os.exit(28) }
    if !closef(pie.sides[0].coords[3].x, 279.7745) || !closef(pie.sides[0].coords[3].y, 105.7093) || !closef(pie.sides[0].coords[4].x, 279.5993) || !closef(pie.sides[0].coords[4].y, 107.1098) || !closef(pie.sides[0].coords[5].x, 279.3740) || !closef(pie.sides[0].coords[5].y, 108.5082) || !closef(pie.sides[0].coords[6].x, 279.0989) || !closef(pie.sides[0].coords[6].y, 109.9039) || !closef(pie.sides[0].coords[7].x, 278.7740) || !closef(pie.sides[0].coords[7].y, 111.2964) || !closef(pie.sides[0].coords[8].x, 278.3995) || !closef(pie.sides[0].coords[8].y, 112.6851) { os.exit(29) }
    if !closef(pie.sides[0].coords[9].x, 277.9755) || !closef(pie.sides[0].coords[9].y, 114.0694) || !closef(pie.sides[0].coords[10].x, 277.5021) || !closef(pie.sides[0].coords[10].y, 115.4490) || !closef(pie.sides[0].coords[11].x, 276.9796) || !closef(pie.sides[0].coords[11].y, 116.8231) || !closef(pie.sides[0].coords[12].x, 276.4081) || !closef(pie.sides[0].coords[12].y, 118.1913) || !closef(pie.sides[0].coords[13].x, 275.7879) || !closef(pie.sides[0].coords[13].y, 119.5531) || !closef(pie.sides[0].coords[14].x, 275.1192) || !closef(pie.sides[0].coords[14].y, 120.9080) { os.exit(30) }
    if !closef(pie.sides[0].coords[15].x, 274.4022) || !closef(pie.sides[0].coords[15].y, 122.2554) || !closef(pie.sides[0].coords[16].x, 273.6373) || !closef(pie.sides[0].coords[16].y, 123.5947) || !closef(pie.sides[0].coords[17].x, 273.6373) || !closef(pie.sides[0].coords[17].y, 137.5947) || !closef(pie.sides[0].coords[18].x, 274.4022) || !closef(pie.sides[0].coords[18].y, 136.2554) || !closef(pie.sides[0].coords[19].x, 275.1192) || !closef(pie.sides[0].coords[19].y, 134.9080) || !closef(pie.sides[0].coords[20].x, 275.7879) || !closef(pie.sides[0].coords[20].y, 133.5531) { os.exit(31) }
    if !closef(pie.sides[0].coords[21].x, 276.4081) || !closef(pie.sides[0].coords[21].y, 132.1913) || !closef(pie.sides[0].coords[22].x, 276.9796) || !closef(pie.sides[0].coords[22].y, 130.8231) || !closef(pie.sides[0].coords[23].x, 277.5021) || !closef(pie.sides[0].coords[23].y, 129.4490) || !closef(pie.sides[0].coords[24].x, 277.9755) || !closef(pie.sides[0].coords[24].y, 128.0694) || !closef(pie.sides[0].coords[25].x, 278.3995) || !closef(pie.sides[0].coords[25].y, 126.6851) || !closef(pie.sides[0].coords[26].x, 278.7740) || !closef(pie.sides[0].coords[26].y, 125.2964) { os.exit(32) }
    if !closef(pie.sides[0].coords[27].x, 279.0989) || !closef(pie.sides[0].coords[27].y, 123.9039) || !closef(pie.sides[0].coords[28].x, 279.3740) || !closef(pie.sides[0].coords[28].y, 122.5082) || !closef(pie.sides[0].coords[29].x, 279.5993) || !closef(pie.sides[0].coords[29].y, 121.1098) || !closef(pie.sides[0].coords[30].x, 279.7745) || !closef(pie.sides[0].coords[30].y, 119.7093) || !closef(pie.sides[0].coords[31].x, 279.8998) || !closef(pie.sides[0].coords[31].y, 118.3071) || !closef(pie.sides[0].coords[32].x, 279.9749) || !closef(pie.sides[0].coords[32].y, 116.9038) { os.exit(33) }
    if !closef(pie.sides[0].coords[33].x, 280.0000) || !closef(pie.sides[0].coords[33].y, 115.5000) || pie.tops[1].coords.len != 4usize || !closef(pie.tops[1].coords[0].x, 150.0000) || !closef(pie.tops[1].coords[0].y, 101.5000) || !closef(pie.tops[1].coords[1].x, 273.6373) || !closef(pie.tops[1].coords[1].y, 123.5947) || !closef(pie.tops[1].coords[2].x, 273.6373) || !closef(pie.tops[1].coords[2].y, 123.5947) || !closef(pie.tops[1].coords[3].x, 273.6373) || !closef(pie.tops[1].coords[3].y, 123.5947) || pie.sides[1].coords.len != 0usize { os.exit(34) }
    if pie.tops[2].coords.len != 25usize || !closef(pie.tops[2].coords[0].x, 150.0000) || !closef(pie.tops[2].coords[0].y, 101.5000) || !closef(pie.tops[2].coords[1].x, 273.6373) || !closef(pie.tops[2].coords[1].y, 123.5947) || !closef(pie.tops[2].coords[2].x, 271.0012) || !closef(pie.tops[2].coords[2].y, 127.6392) || !closef(pie.tops[2].coords[3].x, 267.9282) || !closef(pie.tops[2].coords[3].y, 131.5893) || !closef(pie.tops[2].coords[4].x, 264.4293) || !closef(pie.tops[2].coords[4].y, 135.4307) || !closef(pie.tops[2].coords[5].x, 260.5172) { os.exit(35) }
    if !closef(pie.tops[2].coords[5].y, 139.1497) || !closef(pie.tops[2].coords[6].x, 256.2061) || !closef(pie.tops[2].coords[6].y, 142.7326) || !closef(pie.tops[2].coords[7].x, 251.5114) || !closef(pie.tops[2].coords[7].y, 146.1667) || !closef(pie.tops[2].coords[8].x, 246.4502) || !closef(pie.tops[2].coords[8].y, 149.4395) || !closef(pie.tops[2].coords[9].x, 241.0408) || !closef(pie.tops[2].coords[9].y, 152.5392) || !closef(pie.tops[2].coords[10].x, 235.3026) || !closef(pie.tops[2].coords[10].y, 155.4546) || !closef(pie.tops[2].coords[11].x, 229.2563) { os.exit(36) }
    if !closef(pie.tops[2].coords[11].y, 158.1752) || !closef(pie.tops[2].coords[12].x, 222.9239) || !closef(pie.tops[2].coords[12].y, 160.6911) || !closef(pie.tops[2].coords[13].x, 216.3282) || !closef(pie.tops[2].coords[13].y, 162.9933) || !closef(pie.tops[2].coords[14].x, 209.4929) || !closef(pie.tops[2].coords[14].y, 165.0734) || !closef(pie.tops[2].coords[15].x, 202.4428) || !closef(pie.tops[2].coords[15].y, 166.9240) || !closef(pie.tops[2].coords[16].x, 195.2034) || !closef(pie.tops[2].coords[16].y, 168.5383) || !closef(pie.tops[2].coords[17].x, 187.8007) { os.exit(37) }
    if !closef(pie.tops[2].coords[17].y, 169.9106) || !closef(pie.tops[2].coords[18].x, 180.2616) || !closef(pie.tops[2].coords[18].y, 171.0358) || !closef(pie.tops[2].coords[19].x, 172.6131) || !closef(pie.tops[2].coords[19].y, 171.9100) || !closef(pie.tops[2].coords[20].x, 164.8830) || !closef(pie.tops[2].coords[20].y, 172.5299) || !closef(pie.tops[2].coords[21].x, 157.0992) || !closef(pie.tops[2].coords[21].y, 172.8933) || !closef(pie.tops[2].coords[22].x, 149.2897) || !closef(pie.tops[2].coords[22].y, 172.9989) || !closef(pie.tops[2].coords[23].x, 141.4828) { os.exit(38) }
    if !closef(pie.tops[2].coords[23].y, 172.8464) || !closef(pie.tops[2].coords[24].x, 133.7067) || !closef(pie.tops[2].coords[24].y, 172.4362) || pie.sides[2].coords.len != 26usize || !closef(pie.sides[2].coords[0].x, 273.6373) || !closef(pie.sides[2].coords[0].y, 123.5947) || !closef(pie.sides[2].coords[1].x, 268.2007) || !closef(pie.sides[2].coords[1].y, 131.2641) || !closef(pie.sides[2].coords[2].x, 261.1974) || !closef(pie.sides[2].coords[2].y, 138.5389) || !closef(pie.sides[2].coords[3].x, 252.7202) || !closef(pie.sides[2].coords[3].y, 145.3229) { os.exit(39) }
    if !closef(pie.sides[2].coords[4].x, 242.8814) || !closef(pie.sides[2].coords[4].y, 151.5259) || !closef(pie.sides[2].coords[5].x, 231.8117) || !closef(pie.sides[2].coords[5].y, 157.0659) || !closef(pie.sides[2].coords[6].x, 219.6575) || !closef(pie.sides[2].coords[6].y, 161.8694) || !closef(pie.sides[2].coords[7].x, 206.5800) || !closef(pie.sides[2].coords[7].y, 165.8728) || !closef(pie.sides[2].coords[8].x, 192.7527) || !closef(pie.sides[2].coords[8].y, 169.0229) || !closef(pie.sides[2].coords[9].x, 178.3586) || !closef(pie.sides[2].coords[9].y, 171.2780) { os.exit(40) }
    if !closef(pie.sides[2].coords[10].x, 163.5887) || !closef(pie.sides[2].coords[10].y, 172.6083) || !closef(pie.sides[2].coords[11].x, 148.6387) || !closef(pie.sides[2].coords[11].y, 172.9961) || !closef(pie.sides[2].coords[12].x, 133.7067) || !closef(pie.sides[2].coords[12].y, 172.4362) || !closef(pie.sides[2].coords[13].x, 133.7067) || !closef(pie.sides[2].coords[13].y, 186.4362) || !closef(pie.sides[2].coords[14].x, 148.6387) || !closef(pie.sides[2].coords[14].y, 186.9961) || !closef(pie.sides[2].coords[15].x, 163.5887) || !closef(pie.sides[2].coords[15].y, 186.6083) { os.exit(41) }
    if !closef(pie.sides[2].coords[16].x, 178.3586) || !closef(pie.sides[2].coords[16].y, 185.2780) || !closef(pie.sides[2].coords[17].x, 192.7527) || !closef(pie.sides[2].coords[17].y, 183.0229) || !closef(pie.sides[2].coords[18].x, 206.5800) || !closef(pie.sides[2].coords[18].y, 179.8728) || !closef(pie.sides[2].coords[19].x, 219.6575) || !closef(pie.sides[2].coords[19].y, 175.8694) || !closef(pie.sides[2].coords[20].x, 231.8117) || !closef(pie.sides[2].coords[20].y, 171.0659) || !closef(pie.sides[2].coords[21].x, 242.8814) || !closef(pie.sides[2].coords[21].y, 165.5259) { os.exit(42) }
    if !closef(pie.sides[2].coords[22].x, 252.7202) || !closef(pie.sides[2].coords[22].y, 159.3229) || !closef(pie.sides[2].coords[23].x, 261.1974) || !closef(pie.sides[2].coords[23].y, 152.5389) || !closef(pie.sides[2].coords[24].x, 268.2007) || !closef(pie.sides[2].coords[24].y, 145.2641) || !closef(pie.sides[2].coords[25].x, 273.6373) || !closef(pie.sides[2].coords[25].y, 137.5947) || pie.tops[3].coords.len != 12usize || !closef(pie.tops[3].coords[0].x, 150.0000) || !closef(pie.tops[3].coords[0].y, 101.5000) || !closef(pie.tops[3].coords[1].x, 133.7067) { os.exit(43) }
    if !closef(pie.tops[3].coords[1].y, 172.4362) || !closef(pie.tops[3].coords[2].x, 126.4433) || !closef(pie.tops[3].coords[2].y, 171.8163) || !closef(pie.tops[3].coords[3].x, 119.2551) || !closef(pie.tops[3].coords[3].y, 170.9717) || !closef(pie.tops[3].coords[4].x, 112.1653) || !closef(pie.tops[3].coords[4].y, 169.9049) || !closef(pie.tops[3].coords[5].x, 105.1964) || !closef(pie.tops[3].coords[5].y, 168.6195) || !closef(pie.tops[3].coords[6].x, 98.3708) || !closef(pie.tops[3].coords[6].y, 167.1195) || !closef(pie.tops[3].coords[7].x, 91.7102) { os.exit(44) }
    if !closef(pie.tops[3].coords[7].y, 165.4097) || !closef(pie.tops[3].coords[8].x, 85.2359) || !closef(pie.tops[3].coords[8].y, 163.4956) || !closef(pie.tops[3].coords[9].x, 78.9687) || !closef(pie.tops[3].coords[9].y, 161.3833) || !closef(pie.tops[3].coords[10].x, 72.9286) || !closef(pie.tops[3].coords[10].y, 159.0795) || !closef(pie.tops[3].coords[11].x, 67.1349) || !closef(pie.tops[3].coords[11].y, 156.5917) || pie.sides[3].coords.len != 14usize || !closef(pie.sides[3].coords[0].x, 133.7067) || !closef(pie.sides[3].coords[0].y, 172.4362) { os.exit(45) }
    if !closef(pie.sides[3].coords[1].x, 121.6414) || !closef(pie.sides[3].coords[1].y, 171.2780) || !closef(pie.sides[3].coords[2].x, 109.8278) || !closef(pie.sides[3].coords[2].y, 169.5005) || !closef(pie.sides[3].coords[3].x, 98.3708) || !closef(pie.sides[3].coords[3].y, 167.1195) || !closef(pie.sides[3].coords[4].x, 87.3720) || !closef(pie.sides[3].coords[4].y, 164.1559) || !closef(pie.sides[3].coords[5].x, 76.9292) || !closef(pie.sides[3].coords[5].y, 160.6363) || !closef(pie.sides[3].coords[6].x, 67.1349) || !closef(pie.sides[3].coords[6].y, 156.5917) { os.exit(46) }
    if !closef(pie.sides[3].coords[7].x, 67.1349) || !closef(pie.sides[3].coords[7].y, 170.5917) || !closef(pie.sides[3].coords[8].x, 76.9292) || !closef(pie.sides[3].coords[8].y, 174.6363) || !closef(pie.sides[3].coords[9].x, 87.3720) || !closef(pie.sides[3].coords[9].y, 178.1559) || !closef(pie.sides[3].coords[10].x, 98.3708) || !closef(pie.sides[3].coords[10].y, 181.1195) || !closef(pie.sides[3].coords[11].x, 109.8278) || !closef(pie.sides[3].coords[11].y, 183.5005) || !closef(pie.sides[3].coords[12].x, 121.6414) || !closef(pie.sides[3].coords[12].y, 185.2780) { os.exit(47) }
    if !closef(pie.sides[3].coords[13].x, 133.7067) || !closef(pie.sides[3].coords[13].y, 186.4362) || pie.tops[4].coords.len != 21usize || !closef(pie.tops[4].coords[0].x, 150.0000) || !closef(pie.tops[4].coords[0].y, 101.5000) || !closef(pie.tops[4].coords[1].x, 67.1349) || !closef(pie.tops[4].coords[1].y, 156.5917) || !closef(pie.tops[4].coords[2].x, 61.3227) || !closef(pie.tops[4].coords[2].y, 153.7828) || !closef(pie.tops[4].coords[3].x, 55.8247) || !closef(pie.tops[4].coords[3].y, 150.7888) || !closef(pie.tops[4].coords[4].x, 50.6603) { os.exit(48) }
    if !closef(pie.tops[4].coords[4].y, 147.6201) || !closef(pie.tops[4].coords[5].x, 45.8477) || !closef(pie.tops[4].coords[5].y, 144.2881) || !closef(pie.tops[4].coords[6].x, 41.4041) || !closef(pie.tops[4].coords[6].y, 140.8045) || !closef(pie.tops[4].coords[7].x, 37.3451) || !closef(pie.tops[4].coords[7].y, 137.1817) || !closef(pie.tops[4].coords[8].x, 33.6852) || !closef(pie.tops[4].coords[8].y, 133.4325) || !closef(pie.tops[4].coords[9].x, 30.4373) || !closef(pie.tops[4].coords[9].y, 129.5702) || !closef(pie.tops[4].coords[10].x, 27.6129) { os.exit(49) }
    if !closef(pie.tops[4].coords[10].y, 125.6085) || !closef(pie.tops[4].coords[11].x, 25.2220) || !closef(pie.tops[4].coords[11].y, 121.5614) || !closef(pie.tops[4].coords[12].x, 23.2731) || !closef(pie.tops[4].coords[12].y, 117.4432) || !closef(pie.tops[4].coords[13].x, 21.7730) || !closef(pie.tops[4].coords[13].y, 113.2685) || !closef(pie.tops[4].coords[14].x, 20.7272) || !closef(pie.tops[4].coords[14].y, 109.0522) || !closef(pie.tops[4].coords[15].x, 20.1393) || !closef(pie.tops[4].coords[15].y, 104.8091) || !closef(pie.tops[4].coords[16].x, 20.0114) { os.exit(50) }
    if !closef(pie.tops[4].coords[16].y, 100.5542) || !closef(pie.tops[4].coords[17].x, 20.3439) || !closef(pie.tops[4].coords[17].y, 96.3028) || !closef(pie.tops[4].coords[18].x, 21.1357) || !closef(pie.tops[4].coords[18].y, 92.0697) || !closef(pie.tops[4].coords[19].x, 22.3839) || !closef(pie.tops[4].coords[19].y, 87.8701) || !closef(pie.tops[4].coords[20].x, 24.0842) || !closef(pie.tops[4].coords[20].y, 83.7187) || pie.sides[4].coords.len != 22usize || !closef(pie.sides[4].coords[0].x, 67.1349) || !closef(pie.sides[4].coords[0].y, 156.5917) { os.exit(51) }
    if !closef(pie.sides[4].coords[1].x, 58.6555) || !closef(pie.sides[4].coords[1].y, 152.3748) || !closef(pie.sides[4].coords[2].x, 50.8825) || !closef(pie.sides[4].coords[2].y, 147.7645) || !closef(pie.sides[4].coords[3].x, 43.8759) || !closef(pie.sides[4].coords[3].y, 142.7964) || !closef(pie.sides[4].coords[4].x, 37.6900) || !closef(pie.sides[4].coords[4].y, 137.5091) || !closef(pie.sides[4].coords[5].x, 32.3725) || !closef(pie.sides[4].coords[5].y, 131.9432) || !closef(pie.sides[4].coords[6].x, 27.9646) || !closef(pie.sides[4].coords[6].y, 126.1420) { os.exit(52) }
    if !closef(pie.sides[4].coords[7].x, 24.5004) || !closef(pie.sides[4].coords[7].y, 120.1502) || !closef(pie.sides[4].coords[8].x, 22.0066) || !closef(pie.sides[4].coords[8].y, 114.0141) || !closef(pie.sides[4].coords[9].x, 20.5026) || !closef(pie.sides[4].coords[9].y, 107.7814) || !closef(pie.sides[4].coords[10].x, 20.0000) || !closef(pie.sides[4].coords[10].y, 101.5000) || !closef(pie.sides[4].coords[11].x, 20.0000) || !closef(pie.sides[4].coords[11].y, 115.5000) || !closef(pie.sides[4].coords[12].x, 20.5026) || !closef(pie.sides[4].coords[12].y, 121.7814) { os.exit(53) }
    if !closef(pie.sides[4].coords[13].x, 22.0066) || !closef(pie.sides[4].coords[13].y, 128.0141) || !closef(pie.sides[4].coords[14].x, 24.5004) || !closef(pie.sides[4].coords[14].y, 134.1502) || !closef(pie.sides[4].coords[15].x, 27.9646) || !closef(pie.sides[4].coords[15].y, 140.1420) || !closef(pie.sides[4].coords[16].x, 32.3725) || !closef(pie.sides[4].coords[16].y, 145.9432) || !closef(pie.sides[4].coords[17].x, 37.6900) || !closef(pie.sides[4].coords[17].y, 151.5091) || !closef(pie.sides[4].coords[18].x, 43.8759) || !closef(pie.sides[4].coords[18].y, 156.7964) { os.exit(54) }
    if !closef(pie.sides[4].coords[19].x, 50.8825) || !closef(pie.sides[4].coords[19].y, 161.7645) || !closef(pie.sides[4].coords[20].x, 58.6555) || !closef(pie.sides[4].coords[20].y, 166.3748) || !closef(pie.sides[4].coords[21].x, 67.1349) || !closef(pie.sides[4].coords[21].y, 170.5917) || pie.tops[5].coords.len != 24usize || !closef(pie.tops[5].coords[0].x, 150.0000) || !closef(pie.tops[5].coords[0].y, 101.5000) || !closef(pie.tops[5].coords[1].x, 24.0842) || !closef(pie.tops[5].coords[1].y, 83.7187) || !closef(pie.tops[5].coords[2].x, 26.2484) { os.exit(55) }
    if !closef(pie.tops[5].coords[2].y, 79.5996) || !closef(pie.tops[5].coords[3].x, 28.8577) || !closef(pie.tops[5].coords[3].y, 75.5592) || !closef(pie.tops[5].coords[4].x, 31.9026) || !closef(pie.tops[5].coords[4].y, 71.6122) || !closef(pie.tops[5].coords[5].x, 35.3721) || !closef(pie.tops[5].coords[5].y, 67.7726) || !closef(pie.tops[5].coords[6].x, 39.2539) || !closef(pie.tops[5].coords[6].y, 64.0543) || !closef(pie.tops[5].coords[7].x, 43.5339) || !closef(pie.tops[5].coords[7].y, 60.4707) || !closef(pie.tops[5].coords[8].x, 48.1968) { os.exit(56) }
    if !closef(pie.tops[5].coords[8].y, 57.0346) || !closef(pie.tops[5].coords[9].x, 53.2257) || !closef(pie.tops[5].coords[9].y, 53.7584) || !closef(pie.tops[5].coords[10].x, 58.6027) || !closef(pie.tops[5].coords[10].y, 50.6539) || !closef(pie.tops[5].coords[11].x, 64.3083) || !closef(pie.tops[5].coords[11].y, 47.7322) || !closef(pie.tops[5].coords[12].x, 70.3221) || !closef(pie.tops[5].coords[12].y, 45.0039) || !closef(pie.tops[5].coords[13].x, 76.6224) || !closef(pie.tops[5].coords[13].y, 42.4788) || !closef(pie.tops[5].coords[14].x, 83.1865) { os.exit(57) }
    if !closef(pie.tops[5].coords[14].y, 40.1658) || !closef(pie.tops[5].coords[15].x, 89.9910) || !closef(pie.tops[5].coords[15].y, 38.0735) || !closef(pie.tops[5].coords[16].x, 97.0112) || !closef(pie.tops[5].coords[16].y, 36.2092) || !closef(pie.tops[5].coords[17].x, 104.2220) || !closef(pie.tops[5].coords[17].y, 34.5797) || !closef(pie.tops[5].coords[18].x, 111.5974) || !closef(pie.tops[5].coords[18].y, 33.1909) || !closef(pie.tops[5].coords[19].x, 119.1109) || !closef(pie.tops[5].coords[19].y, 32.0477) || !closef(pie.tops[5].coords[20].x, 126.7354) { os.exit(58) }
    if !closef(pie.tops[5].coords[20].y, 31.1542) || !closef(pie.tops[5].coords[21].x, 134.4436) || !closef(pie.tops[5].coords[21].y, 30.5138) || !closef(pie.tops[5].coords[22].x, 142.2078) || !closef(pie.tops[5].coords[22].y, 30.1286) || !closef(pie.tops[5].coords[23].x, 150.0000) || !closef(pie.tops[5].coords[23].y, 30.0000) || pie.sides[5].coords.len != 0usize { os.exit(59) }
    if !closef(wall_arc(pie.sides, pie_values[..]), 3.141593) { os.exit(60) }
    if !inside_bounds(pie.tops, pie_bounds) || !inside_bounds(pie.sides, pie_bounds) { os.exit(61) }
    if !closef(pie.tops[0].coords[1].x, 150.0000) || !closef(pie.tops[0].coords[1].y, 30.0000) { os.exit(62) }
    if pie.sides[1].coords.len != 0usize || pie.sides[0].coords.len == 0usize { os.exit(63) }
    let (circle, circle_error) = chart.pie_25d(pie_values[..], geometry.rect(0.0, 0.0, 200.0, 200.0), 1.0, 0.0, pie_points[..], pie_tops[..], pie_walls[..])
    if circle_error != ok || !closef(circle.tops[0].coords[0].x, 100.0) || !closef(circle.tops[0].coords[0].y, 100.0) || !closef(circle.tops[2].coords[1].x * 0.0, 0.0) { os.exit(64) }
    let one = [1]f32{ 5.0 }
    let (whole, whole_error) = chart.pie_25d(one[..], pie_bounds, 0.55, 14.0, pie_points[..], pie_tops[..], pie_walls[..])
    if whole_error != ok || whole.sides[0].coords.len == 0usize || !closef(wall_arc(whole.sides, one[..]), 3.141592653589793) { os.exit(65) }
    let (_, tilt_low) = chart.pie_25d(pie_values[..], pie_bounds, 0.1, 5.0, pie_points[..], pie_tops[..], pie_walls[..])
    let (_, tilt_high) = chart.pie_25d(pie_values[..], pie_bounds, 1.5, 5.0, pie_points[..], pie_tops[..], pie_walls[..])
    let (_, tilt_nan) = chart.pie_25d(pie_values[..], pie_bounds, nan, 5.0, pie_points[..], pie_tops[..], pie_walls[..])
    let (_, thick) = chart.pie_25d(pie_values[..], pie_bounds, 0.55, 170.0, pie_points[..], pie_tops[..], pie_walls[..])
    let (_, thick_negative) = chart.pie_25d(pie_values[..], pie_bounds, 0.55, -1.0, pie_points[..], pie_tops[..], pie_walls[..])
    let negative_values = [2]f32{ 3.0, -1.0 }
    let (_, value_negative) = chart.pie_25d(negative_values[..], pie_bounds, 0.55, 5.0, pie_points[..], pie_tops[..], pie_walls[..])
    let zeros = [2]f32{ 0.0, 0.0 }
    let (_, value_zero) = chart.pie_25d(zeros[..], pie_bounds, 0.55, 5.0, pie_points[..], pie_tops[..], pie_walls[..])
    let (_, pie_none) = chart.pie_25d(pie_values[..0usize], pie_bounds, 0.55, 5.0, pie_points[..], pie_tops[..], pie_walls[..])
    let (_, pie_points_short) = chart.pie_25d(pie_values[..], pie_bounds, 0.55, 14.0, pie_points[..100usize], pie_tops[..], pie_walls[..])
    let (_, pie_tops_short) = chart.pie_25d(pie_values[..], pie_bounds, 0.55, 14.0, pie_points[..], pie_tops[..5], pie_walls[..])
    let (_, pie_walls_short) = chart.pie_25d(pie_values[..], pie_bounds, 0.55, 14.0, pie_points[..], pie_tops[..], pie_walls[..5])
    if tilt_low != chart.Invalid { os.exit(66) }
    if tilt_high != chart.Invalid { os.exit(67) }
    if tilt_nan != chart.Invalid { os.exit(68) }
    if thick != chart.Invalid { os.exit(69) }
    if thick_negative != chart.Invalid { os.exit(70) }
    if value_negative != chart.Invalid { os.exit(71) }
    if value_zero != chart.Invalid { os.exit(72) }
    if pie_none != chart.Empty { os.exit(73) }
    if pie_points_short != chart.TooLarge { os.exit(74) }
    if pie_tops_short != chart.TooLarge { os.exit(75) }
    if pie_walls_short != chart.TooLarge { os.exit(76) }
    try io.print("gfx chart 25d reference ok\n")
    os.exit(0)
    ret ok
}
