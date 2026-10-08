// Pie-of-pie and bar-of-pie of e.gfx.chart against a numpy replay (L094, D2262;
// scripts/chart_compound_pie_reference.py writes this file): the main pie with its tail folded into one Other
// slice facing the breakout, the breakout pie or stacked bar, the connectors, polygon areas against the
// analytic chord-sector area and proportional to the values, small_tail_count, and every refusal. Every check
// has its own exit code.
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

fn same(a: f32, b: f32) -> bool { ret abs64(f64(a) - f64(b)) <= 0.0006f64 }

fn closed(got: f64, want: f64) -> bool { ret abs64(got - want) <= 1e-9f64 * (1.0f64 + abs64(want)) }

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

fn area_sum(layers: []chart.Layout) -> f32 {
    var total = 0.0f32
    var i = 0usize
    while i < layers.len {
        total += shoelace(layers[i].coords)
        i += 1usize
    }
    ret total
}

fn breakout_left(layers: []chart.Layout) -> f32 {
    var left = layers[0usize].coords[0usize].x
    var i = 0usize
    while i < layers.len {
        var j = 0usize
        while j < layers[i].coords.len {
            if layers[i].coords[j].x < left { left = layers[i].coords[j].x }
            j += 1usize
        }
        i += 1usize
    }
    ret left
}

fn main_right(layers: []chart.Layout) -> f32 {
    var right = layers[0usize].coords[0usize].x
    var i = 0usize
    while i < layers.len {
        var j = 0usize
        while j < layers[i].coords.len {
            if layers[i].coords[j].x > right { right = layers[i].coords[j].x }
            j += 1usize
        }
        i += 1usize
    }
    ret right
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [8]f32{ 27.0f32, 21.0f32, 17.0f32, 12.0f32, 9.0f32, 6.5f32, 4.5f32, 3.0f32 }
    let bounds = geometry.rect(10.0, 30.0, 340.0, 170.0)
    var points: [2000]chart.Coord = zero
    var main_layers: [8]chart.Layout = zero
    var breakout: [8]chart.Layout = zero
    var bars: [8]geometry.Rect = zero
    var links: [2]chart.Segment = zero
    let (pie_pie, pie_pie_error) = chart.compound_pie(values[..], 3usize, .Pie, bounds, points[..], main_layers[..], breakout[..], bars[..], links[..])
    if pie_pie_error != ok || pie_pie.main.len != 6usize || pie_pie.breakout.len != 3usize || pie_pie.bars.len != 0usize { os.exit(1) }
    if !closed(pie_pie.other_total, 14.0) || !closed(pie_pie.main_total, 86.0) { os.exit(2) }
    if pie_pie.main[0].coords.len != 29usize || pie_pie.main[0].kind != .Area || !closef(pie_pie.main[0].coords[0].x, 95.0000) || !closef(pie_pie.main[0].coords[0].y, 115.0000) || !closef(pie_pie.main[0].coords[1].x, 171.9103) || !closef(pie_pie.main[0].coords[1].y, 151.1912) || !closef(pie_pie.main[0].coords[2].x, 169.4861) || !closef(pie_pie.main[0].coords[2].y, 155.9491) || !closef(pie_pie.main[0].coords[3].x, 166.7679) || !closef(pie_pie.main[0].coords[3].y, 160.5453) || !closef(pie_pie.main[0].coords[4].x, 163.7664) || !closef(pie_pie.main[0].coords[4].y, 164.9617) { os.exit(3) }
    if !closef(pie_pie.main[0].coords[5].x, 160.4936) || !closef(pie_pie.main[0].coords[5].y, 169.1810) || !closef(pie_pie.main[0].coords[6].x, 156.9623) || !closef(pie_pie.main[0].coords[6].y, 173.1865) || !closef(pie_pie.main[0].coords[7].x, 153.1865) || !closef(pie_pie.main[0].coords[7].y, 176.9623) || !closef(pie_pie.main[0].coords[8].x, 149.1810) || !closef(pie_pie.main[0].coords[8].y, 180.4936) || !closef(pie_pie.main[0].coords[9].x, 144.9617) || !closef(pie_pie.main[0].coords[9].y, 183.7664) || !closef(pie_pie.main[0].coords[10].x, 140.5453) || !closef(pie_pie.main[0].coords[10].y, 186.7679) { os.exit(4) }
    if !closef(pie_pie.main[0].coords[11].x, 135.9491) || !closef(pie_pie.main[0].coords[11].y, 189.4861) || !closef(pie_pie.main[0].coords[12].x, 131.1912) || !closef(pie_pie.main[0].coords[12].y, 191.9103) || !closef(pie_pie.main[0].coords[13].x, 126.2906) || !closef(pie_pie.main[0].coords[13].y, 194.0310) || !closef(pie_pie.main[0].coords[14].x, 121.2664) || !closef(pie_pie.main[0].coords[14].y, 195.8398) || !closef(pie_pie.main[0].coords[15].x, 116.1386) || !closef(pie_pie.main[0].coords[15].y, 197.3296) || !closef(pie_pie.main[0].coords[16].x, 110.9274) || !closef(pie_pie.main[0].coords[16].y, 198.4944) { os.exit(5) }
    if !closef(pie_pie.main[0].coords[17].x, 105.6533) || !closef(pie_pie.main[0].coords[17].y, 199.3297) || !closef(pie_pie.main[0].coords[18].x, 100.3372) || !closef(pie_pie.main[0].coords[18].y, 199.8323) || !closef(pie_pie.main[0].coords[19].x, 95.0000) || !closef(pie_pie.main[0].coords[19].y, 200.0000) || !closef(pie_pie.main[0].coords[20].x, 89.6628) || !closef(pie_pie.main[0].coords[20].y, 199.8323) || !closef(pie_pie.main[0].coords[21].x, 84.3467) || !closef(pie_pie.main[0].coords[21].y, 199.3297) || !closef(pie_pie.main[0].coords[22].x, 79.0726) || !closef(pie_pie.main[0].coords[22].y, 198.4944) { os.exit(6) }
    if !closef(pie_pie.main[0].coords[23].x, 73.8614) || !closef(pie_pie.main[0].coords[23].y, 197.3296) || !closef(pie_pie.main[0].coords[24].x, 68.7336) || !closef(pie_pie.main[0].coords[24].y, 195.8398) || !closef(pie_pie.main[0].coords[25].x, 63.7094) || !closef(pie_pie.main[0].coords[25].y, 194.0310) || !closef(pie_pie.main[0].coords[26].x, 58.8088) || !closef(pie_pie.main[0].coords[26].y, 191.9103) || !closef(pie_pie.main[0].coords[27].x, 54.0509) || !closef(pie_pie.main[0].coords[27].y, 189.4861) || !closef(pie_pie.main[0].coords[28].x, 49.4547) || !closef(pie_pie.main[0].coords[28].y, 186.7679) { os.exit(7) }
    if pie_pie.main[1].coords.len != 24usize || pie_pie.main[1].kind != .Area || !closef(pie_pie.main[1].coords[0].x, 95.0000) || !closef(pie_pie.main[1].coords[0].y, 115.0000) || !closef(pie_pie.main[1].coords[1].x, 49.4547) || !closef(pie_pie.main[1].coords[1].y, 186.7679) || !closef(pie_pie.main[1].coords[2].x, 45.2349) || !closef(pie_pie.main[1].coords[2].y, 183.9089) || !closef(pie_pie.main[1].coords[3].x, 41.1939) || !closef(pie_pie.main[1].coords[3].y, 180.8020) || !closef(pie_pie.main[1].coords[4].x, 37.3465) || !closef(pie_pie.main[1].coords[4].y, 177.4586) { os.exit(8) }
    if !closef(pie_pie.main[1].coords[5].x, 33.7064) || !closef(pie_pie.main[1].coords[5].y, 173.8905) || !closef(pie_pie.main[1].coords[6].x, 30.2867) || !closef(pie_pie.main[1].coords[6].y, 170.1107) || !closef(pie_pie.main[1].coords[7].x, 27.0998) || !closef(pie_pie.main[1].coords[7].y, 166.1327) || !closef(pie_pie.main[1].coords[8].x, 24.1569) || !closef(pie_pie.main[1].coords[8].y, 161.9709) || !closef(pie_pie.main[1].coords[9].x, 21.4689) || !closef(pie_pie.main[1].coords[9].y, 157.6401) || !closef(pie_pie.main[1].coords[10].x, 19.0453) || !closef(pie_pie.main[1].coords[10].y, 153.1560) { os.exit(9) }
    if !closef(pie_pie.main[1].coords[11].x, 16.8948) || !closef(pie_pie.main[1].coords[11].y, 148.5346) || !closef(pie_pie.main[1].coords[12].x, 15.0251) || !closef(pie_pie.main[1].coords[12].y, 143.7927) || !closef(pie_pie.main[1].coords[13].x, 13.4431) || !closef(pie_pie.main[1].coords[13].y, 138.9473) || !closef(pie_pie.main[1].coords[14].x, 12.1543) || !closef(pie_pie.main[1].coords[14].y, 134.0157) || !closef(pie_pie.main[1].coords[15].x, 11.1635) || !closef(pie_pie.main[1].coords[15].y, 129.0157) || !closef(pie_pie.main[1].coords[16].x, 10.4741) || !closef(pie_pie.main[1].coords[16].y, 123.9654) { os.exit(10) }
    if !closef(pie_pie.main[1].coords[17].x, 10.0887) || !closef(pie_pie.main[1].coords[17].y, 118.8828) || !closef(pie_pie.main[1].coords[18].x, 10.0087) || !closef(pie_pie.main[1].coords[18].y, 113.7862) || !closef(pie_pie.main[1].coords[19].x, 10.2342) || !closef(pie_pie.main[1].coords[19].y, 108.6941) || !closef(pie_pie.main[1].coords[20].x, 10.7646) || !closef(pie_pie.main[1].coords[20].y, 103.6245) || !closef(pie_pie.main[1].coords[21].x, 11.5979) || !closef(pie_pie.main[1].coords[21].y, 98.5959) || !closef(pie_pie.main[1].coords[22].x, 12.7311) || !closef(pie_pie.main[1].coords[22].y, 93.6263) { os.exit(11) }
    if !closef(pie_pie.main[1].coords[23].x, 14.1602) || !closef(pie_pie.main[1].coords[23].y, 88.7336) || pie_pie.main[2].coords.len != 20usize || pie_pie.main[2].kind != .Area || !closef(pie_pie.main[2].coords[0].x, 95.0000) || !closef(pie_pie.main[2].coords[0].y, 115.0000) || !closef(pie_pie.main[2].coords[1].x, 14.1602) || !closef(pie_pie.main[2].coords[1].y, 88.7336) || !closef(pie_pie.main[2].coords[2].x, 15.8603) || !closef(pie_pie.main[2].coords[2].y, 83.9855) || !closef(pie_pie.main[2].coords[3].x, 17.8389) || !closef(pie_pie.main[2].coords[3].y, 79.3466) { os.exit(12) }
    if !closef(pie_pie.main[2].coords[4].x, 20.0892) || !closef(pie_pie.main[2].coords[4].y, 74.8332) || !closef(pie_pie.main[2].coords[5].x, 22.6032) || !closef(pie_pie.main[2].coords[5].y, 70.4612) || !closef(pie_pie.main[2].coords[6].x, 25.3721) || !closef(pie_pie.main[2].coords[6].y, 66.2460) || !closef(pie_pie.main[2].coords[7].x, 28.3861) || !closef(pie_pie.main[2].coords[7].y, 62.2024) || !closef(pie_pie.main[2].coords[8].x, 31.6345) || !closef(pie_pie.main[2].coords[8].y, 58.3447) || !closef(pie_pie.main[2].coords[9].x, 35.1061) || !closef(pie_pie.main[2].coords[9].y, 54.6865) { os.exit(13) }
    if !closef(pie_pie.main[2].coords[10].x, 38.7885) || !closef(pie_pie.main[2].coords[10].y, 51.2406) || !closef(pie_pie.main[2].coords[11].x, 42.6688) || !closef(pie_pie.main[2].coords[11].y, 48.0191) || !closef(pie_pie.main[2].coords[12].x, 46.7333) || !closef(pie_pie.main[2].coords[12].y, 45.0334) || !closef(pie_pie.main[2].coords[13].x, 50.9677) || !closef(pie_pie.main[2].coords[13].y, 42.2940) || !closef(pie_pie.main[2].coords[14].x, 55.3571) || !closef(pie_pie.main[2].coords[14].y, 39.8106) || !closef(pie_pie.main[2].coords[15].x, 59.8861) || !closef(pie_pie.main[2].coords[15].y, 37.5919) { os.exit(14) }
    if !closef(pie_pie.main[2].coords[16].x, 64.5387) || !closef(pie_pie.main[2].coords[16].y, 35.6457) || !closef(pie_pie.main[2].coords[17].x, 69.2986) || !closef(pie_pie.main[2].coords[17].y, 33.9788) || !closef(pie_pie.main[2].coords[18].x, 74.1489) || !closef(pie_pie.main[2].coords[18].y, 32.5971) || !closef(pie_pie.main[2].coords[19].x, 79.0726) || !closef(pie_pie.main[2].coords[19].y, 31.5056) || pie_pie.main[3].coords.len != 15usize || pie_pie.main[3].kind != .Area || !closef(pie_pie.main[3].coords[0].x, 95.0000) || !closef(pie_pie.main[3].coords[0].y, 115.0000) { os.exit(15) }
    if !closef(pie_pie.main[3].coords[1].x, 79.0726) || !closef(pie_pie.main[3].coords[1].y, 31.5056) || !closef(pie_pie.main[3].coords[2].x, 83.9392) || !closef(pie_pie.main[3].coords[2].y, 30.7227) || !closef(pie_pie.main[3].coords[3].x, 88.8430) || !closef(pie_pie.main[3].coords[3].y, 30.2233) || !closef(pie_pie.main[3].coords[4].x, 93.7676) || !closef(pie_pie.main[3].coords[4].y, 30.0089) || !closef(pie_pie.main[3].coords[5].x, 98.6962) || !closef(pie_pie.main[3].coords[5].y, 30.0804) || !closef(pie_pie.main[3].coords[6].x, 103.6125) || !closef(pie_pie.main[3].coords[6].y, 30.4374) { os.exit(16) }
    if !closef(pie_pie.main[3].coords[7].x, 108.4998) || !closef(pie_pie.main[3].coords[7].y, 31.0789) || !closef(pie_pie.main[3].coords[8].x, 113.3417) || !closef(pie_pie.main[3].coords[8].y, 32.0025) || !closef(pie_pie.main[3].coords[9].x, 118.1219) || !closef(pie_pie.main[3].coords[9].y, 33.2053) || !closef(pie_pie.main[3].coords[10].x, 122.8243) || !closef(pie_pie.main[3].coords[10].y, 34.6831) || !closef(pie_pie.main[3].coords[11].x, 127.4332) || !closef(pie_pie.main[3].coords[11].y, 36.4310) || !closef(pie_pie.main[3].coords[12].x, 131.9330) || !closef(pie_pie.main[3].coords[12].y, 38.4431) { os.exit(17) }
    if !closef(pie_pie.main[3].coords[13].x, 136.3086) || !closef(pie_pie.main[3].coords[13].y, 40.7127) || !closef(pie_pie.main[3].coords[14].x, 140.5453) || !closef(pie_pie.main[3].coords[14].y, 43.2321) || pie_pie.main[4].coords.len != 12usize || pie_pie.main[4].kind != .Area || !closef(pie_pie.main[4].coords[0].x, 95.0000) || !closef(pie_pie.main[4].coords[0].y, 115.0000) || !closef(pie_pie.main[4].coords[1].x, 140.5453) || !closef(pie_pie.main[4].coords[1].y, 43.2321) || !closef(pie_pie.main[4].coords[2].x, 144.5287) || !closef(pie_pie.main[4].coords[2].y, 45.9210) { os.exit(18) }
    if !closef(pie_pie.main[4].coords[3].x, 148.3538) || !closef(pie_pie.main[4].coords[3].y, 48.8307) || !closef(pie_pie.main[4].coords[4].x, 152.0083) || !closef(pie_pie.main[4].coords[4].y, 51.9519) || !closef(pie_pie.main[4].coords[5].x, 155.4805) || !closef(pie_pie.main[4].coords[5].y, 55.2748) || !closef(pie_pie.main[4].coords[6].x, 158.7594) || !closef(pie_pie.main[4].coords[6].y, 58.7885) || !closef(pie_pie.main[4].coords[7].x, 161.8345) || !closef(pie_pie.main[4].coords[7].y, 62.4819) || !closef(pie_pie.main[4].coords[8].x, 164.6959) || !closef(pie_pie.main[4].coords[8].y, 66.3433) { os.exit(19) }
    if !closef(pie_pie.main[4].coords[9].x, 167.3345) || !closef(pie_pie.main[4].coords[9].y, 70.3602) || !closef(pie_pie.main[4].coords[10].x, 169.7419) || !closef(pie_pie.main[4].coords[10].y, 74.5198) || !closef(pie_pie.main[4].coords[11].x, 171.9103) || !closef(pie_pie.main[4].coords[11].y, 78.8088) || pie_pie.main[5].coords.len != 17usize || pie_pie.main[5].kind != .Area || !closef(pie_pie.main[5].coords[0].x, 95.0000) || !closef(pie_pie.main[5].coords[0].y, 115.0000) || !closef(pie_pie.main[5].coords[1].x, 171.9103) || !closef(pie_pie.main[5].coords[1].y, 78.8088) { os.exit(20) }
    if !closef(pie_pie.main[5].coords[2].x, 173.8992) || !closef(pie_pie.main[5].coords[2].y, 83.3786) || !closef(pie_pie.main[5].coords[3].x, 175.6169) || !closef(pie_pie.main[5].coords[3].y, 88.0572) || !closef(pie_pie.main[5].coords[4].x, 177.0574) || !closef(pie_pie.main[5].coords[4].y, 92.8285) || !closef(pie_pie.main[5].coords[5].x, 178.2158) || !closef(pie_pie.main[5].coords[5].y, 97.6759) || !closef(pie_pie.main[5].coords[6].x, 179.0881) || !closef(pie_pie.main[5].coords[6].y, 102.5829) || !closef(pie_pie.main[5].coords[7].x, 179.6714) || !closef(pie_pie.main[5].coords[7].y, 107.5326) { os.exit(21) }
    if !closef(pie_pie.main[5].coords[8].x, 179.9635) || !closef(pie_pie.main[5].coords[8].y, 112.5080) || !closef(pie_pie.main[5].coords[9].x, 179.9635) || !closef(pie_pie.main[5].coords[9].y, 117.4920) || !closef(pie_pie.main[5].coords[10].x, 179.6714) || !closef(pie_pie.main[5].coords[10].y, 122.4674) || !closef(pie_pie.main[5].coords[11].x, 179.0881) || !closef(pie_pie.main[5].coords[11].y, 127.4171) || !closef(pie_pie.main[5].coords[12].x, 178.2158) || !closef(pie_pie.main[5].coords[12].y, 132.3241) || !closef(pie_pie.main[5].coords[13].x, 177.0574) || !closef(pie_pie.main[5].coords[13].y, 137.1715) { os.exit(22) }
    if !closef(pie_pie.main[5].coords[14].x, 175.6169) || !closef(pie_pie.main[5].coords[14].y, 141.9428) || !closef(pie_pie.main[5].coords[15].x, 173.8992) || !closef(pie_pie.main[5].coords[15].y, 146.6214) || !closef(pie_pie.main[5].coords[16].x, 171.9103) || !closef(pie_pie.main[5].coords[16].y, 151.1912) { os.exit(23) }
    if !closef(shoelace(pie_pie.main[0].coords), 6124.4303) || !closef(shoelace(pie_pie.main[0].coords) / area_sum(pie_pie.main), 0.270000) || !closef(shoelace(pie_pie.main[1].coords), 4763.7243) || !closef(shoelace(pie_pie.main[1].coords) / area_sum(pie_pie.main), 0.210000) || !closef(shoelace(pie_pie.main[2].coords), 3856.3969) || !closef(shoelace(pie_pie.main[2].coords) / area_sum(pie_pie.main), 0.170000) || !closef(shoelace(pie_pie.main[3].coords), 2722.2340) || !closef(shoelace(pie_pie.main[3].coords) / area_sum(pie_pie.main), 0.120000) || !closef(shoelace(pie_pie.main[4].coords), 2041.7321) || !closef(shoelace(pie_pie.main[4].coords) / area_sum(pie_pie.main), 0.090000) || !closef(shoelace(pie_pie.main[5].coords), 3175.8999) || !closef(shoelace(pie_pie.main[5].coords) / area_sum(pie_pie.main), 0.140000) { os.exit(24) }
    if !closef(pie_pie.main[5].coords[1].y - 115.0, -36.19123978303118) || !closef(115.0 - pie_pie.main[5].coords[pie_pie.main[5].coords.len - 1].y, -36.19123978303118) { os.exit(25) }
    if pie_pie.breakout[0].coords.len != 48usize || !closef(pie_pie.breakout[0].coords[0].x, 290.5000) || !closef(pie_pie.breakout[0].coords[0].y, 115.0000) || !closef(pie_pie.breakout[0].coords[1].x, 290.5000) || !closef(pie_pie.breakout[0].coords[1].y, 55.5000) || !closef(pie_pie.breakout[0].coords[2].x, 294.2708) || !closef(pie_pie.breakout[0].coords[2].y, 55.6196) || !closef(pie_pie.breakout[0].coords[3].x, 298.0264) || !closef(pie_pie.breakout[0].coords[3].y, 55.9779) || !closef(pie_pie.breakout[0].coords[4].x, 301.7518) || !closef(pie_pie.breakout[0].coords[4].y, 56.5736) || !closef(pie_pie.breakout[0].coords[5].x, 305.4320) { os.exit(26) }
    if !closef(pie_pie.breakout[0].coords[5].y, 57.4041) || !closef(pie_pie.breakout[0].coords[6].x, 309.0521) || !closef(pie_pie.breakout[0].coords[6].y, 58.4662) || !closef(pie_pie.breakout[0].coords[7].x, 312.5976) || !closef(pie_pie.breakout[0].coords[7].y, 59.7556) || !closef(pie_pie.breakout[0].coords[8].x, 316.0543) || !closef(pie_pie.breakout[0].coords[8].y, 61.2671) || !closef(pie_pie.breakout[0].coords[9].x, 319.4082) || !closef(pie_pie.breakout[0].coords[9].y, 62.9946) || !closef(pie_pie.breakout[0].coords[10].x, 322.6459) || !closef(pie_pie.breakout[0].coords[10].y, 64.9312) || !closef(pie_pie.breakout[0].coords[11].x, 325.7544) { os.exit(27) }
    if !closef(pie_pie.breakout[0].coords[11].y, 67.0690) || !closef(pie_pie.breakout[0].coords[12].x, 328.7212) || !closef(pie_pie.breakout[0].coords[12].y, 69.3996) || !closef(pie_pie.breakout[0].coords[13].x, 331.5342) || !closef(pie_pie.breakout[0].coords[13].y, 71.9136) || !closef(pie_pie.breakout[0].coords[14].x, 334.1823) || !closef(pie_pie.breakout[0].coords[14].y, 74.6007) || !closef(pie_pie.breakout[0].coords[15].x, 336.6548) || !closef(pie_pie.breakout[0].coords[15].y, 77.4503) || !closef(pie_pie.breakout[0].coords[16].x, 338.9417) || !closef(pie_pie.breakout[0].coords[16].y, 80.4508) || !closef(pie_pie.breakout[0].coords[17].x, 341.0339) { os.exit(28) }
    if !closef(pie_pie.breakout[0].coords[17].y, 83.5902) || !closef(pie_pie.breakout[0].coords[18].x, 342.9229) || !closef(pie_pie.breakout[0].coords[18].y, 86.8559) || !closef(pie_pie.breakout[0].coords[19].x, 344.6012) || !closef(pie_pie.breakout[0].coords[19].y, 90.2348) || !closef(pie_pie.breakout[0].coords[20].x, 346.0619) || !closef(pie_pie.breakout[0].coords[20].y, 93.7132) || !closef(pie_pie.breakout[0].coords[21].x, 347.2992) || !closef(pie_pie.breakout[0].coords[21].y, 97.2773) || !closef(pie_pie.breakout[0].coords[22].x, 348.3082) || !closef(pie_pie.breakout[0].coords[22].y, 100.9125) || !closef(pie_pie.breakout[0].coords[23].x, 349.0848) { os.exit(29) }
    if !closef(pie_pie.breakout[0].coords[23].y, 104.6044) || !closef(pie_pie.breakout[0].coords[24].x, 349.6259) || !closef(pie_pie.breakout[0].coords[24].y, 108.3381) || !closef(pie_pie.breakout[0].coords[25].x, 349.9292) || !closef(pie_pie.breakout[0].coords[25].y, 112.0986) || !closef(pie_pie.breakout[0].coords[26].x, 349.9936) || !closef(pie_pie.breakout[0].coords[26].y, 115.8707) || !closef(pie_pie.breakout[0].coords[27].x, 349.8189) || !closef(pie_pie.breakout[0].coords[27].y, 119.6394) || !closef(pie_pie.breakout[0].coords[28].x, 349.4056) || !closef(pie_pie.breakout[0].coords[28].y, 123.3894) || !closef(pie_pie.breakout[0].coords[29].x, 348.7555) { os.exit(30) }
    if !closef(pie_pie.breakout[0].coords[29].y, 127.1056) || !closef(pie_pie.breakout[0].coords[30].x, 347.8712) || !closef(pie_pie.breakout[0].coords[30].y, 130.7732) || !closef(pie_pie.breakout[0].coords[31].x, 346.7563) || !closef(pie_pie.breakout[0].coords[31].y, 134.3774) || !closef(pie_pie.breakout[0].coords[32].x, 345.4151) || !closef(pie_pie.breakout[0].coords[32].y, 137.9037) || !closef(pie_pie.breakout[0].coords[33].x, 343.8532) || !closef(pie_pie.breakout[0].coords[33].y, 141.3379) || !closef(pie_pie.breakout[0].coords[34].x, 342.0768) || !closef(pie_pie.breakout[0].coords[34].y, 144.6662) || !closef(pie_pie.breakout[0].coords[35].x, 340.0931) { os.exit(31) }
    if !closef(pie_pie.breakout[0].coords[35].y, 147.8752) || !closef(pie_pie.breakout[0].coords[36].x, 337.9099) || !closef(pie_pie.breakout[0].coords[36].y, 150.9521) || !closef(pie_pie.breakout[0].coords[37].x, 335.5361) || !closef(pie_pie.breakout[0].coords[37].y, 153.8844) || !closef(pie_pie.breakout[0].coords[38].x, 332.9813) || !closef(pie_pie.breakout[0].coords[38].y, 156.6604) || !closef(pie_pie.breakout[0].coords[39].x, 330.2557) || !closef(pie_pie.breakout[0].coords[39].y, 159.2689) || !closef(pie_pie.breakout[0].coords[40].x, 327.3703) || !closef(pie_pie.breakout[0].coords[40].y, 161.6994) || !closef(pie_pie.breakout[0].coords[41].x, 324.3366) { os.exit(32) }
    if !closef(pie_pie.breakout[0].coords[41].y, 163.9422) || !closef(pie_pie.breakout[0].coords[42].x, 321.1669) || !closef(pie_pie.breakout[0].coords[42].y, 165.9882) || !closef(pie_pie.breakout[0].coords[43].x, 317.8739) || !closef(pie_pie.breakout[0].coords[43].y, 167.8292) || !closef(pie_pie.breakout[0].coords[44].x, 314.4708) || !closef(pie_pie.breakout[0].coords[44].y, 169.4578) || !closef(pie_pie.breakout[0].coords[45].x, 310.9714) || !closef(pie_pie.breakout[0].coords[45].y, 170.8675) || !closef(pie_pie.breakout[0].coords[46].x, 307.3896) || !closef(pie_pie.breakout[0].coords[46].y, 172.0525) || !closef(pie_pie.breakout[0].coords[47].x, 303.7400) { os.exit(33) }
    if !closef(pie_pie.breakout[0].coords[47].y, 173.0082) || !closef(shoelace(pie_pie.breakout[0].coords) / area_sum(pie_pie.breakout), 0.464286) || pie_pie.breakout[1].coords.len != 34usize || !closef(pie_pie.breakout[1].coords[0].x, 290.5000) || !closef(pie_pie.breakout[1].coords[0].y, 115.0000) || !closef(pie_pie.breakout[1].coords[1].x, 303.7400) || !closef(pie_pie.breakout[1].coords[1].y, 173.0082) || !closef(pie_pie.breakout[1].coords[2].x, 300.0550) || !closef(pie_pie.breakout[1].coords[2].y, 173.7278) || !closef(pie_pie.breakout[1].coords[3].x, 296.3320) || !closef(pie_pie.breakout[1].coords[3].y, 174.2135) || !closef(pie_pie.breakout[1].coords[4].x, 292.5858) { os.exit(34) }
    if !closef(pie_pie.breakout[1].coords[4].y, 174.4634) || !closef(pie_pie.breakout[1].coords[5].x, 288.8312) || !closef(pie_pie.breakout[1].coords[5].y, 174.4766) || !closef(pie_pie.breakout[1].coords[6].x, 285.0834) || !closef(pie_pie.breakout[1].coords[6].y, 174.2529) || !closef(pie_pie.breakout[1].coords[7].x, 281.3570) || !closef(pie_pie.breakout[1].coords[7].y, 173.7933) || !closef(pie_pie.breakout[1].coords[8].x, 277.6671) || !closef(pie_pie.breakout[1].coords[8].y, 173.0996) || !closef(pie_pie.breakout[1].coords[9].x, 274.0283) || !closef(pie_pie.breakout[1].coords[9].y, 172.1746) || !closef(pie_pie.breakout[1].coords[10].x, 270.4551) { os.exit(35) }
    if !closef(pie_pie.breakout[1].coords[10].y, 171.0219) || !closef(pie_pie.breakout[1].coords[11].x, 266.9616) || !closef(pie_pie.breakout[1].coords[11].y, 169.6461) || !closef(pie_pie.breakout[1].coords[12].x, 263.5619) || !closef(pie_pie.breakout[1].coords[12].y, 168.0527) || !closef(pie_pie.breakout[1].coords[13].x, 260.2695) || !closef(pie_pie.breakout[1].coords[13].y, 166.2481) || !closef(pie_pie.breakout[1].coords[14].x, 257.0975) || !closef(pie_pie.breakout[1].coords[14].y, 164.2394) || !closef(pie_pie.breakout[1].coords[15].x, 254.0584) || !closef(pie_pie.breakout[1].coords[15].y, 162.0347) || !closef(pie_pie.breakout[1].coords[16].x, 251.1645) { os.exit(36) }
    if !closef(pie_pie.breakout[1].coords[16].y, 159.6426) || !closef(pie_pie.breakout[1].coords[17].x, 248.4271) || !closef(pie_pie.breakout[1].coords[17].y, 157.0729) || !closef(pie_pie.breakout[1].coords[18].x, 245.8574) || !closef(pie_pie.breakout[1].coords[18].y, 154.3355) || !closef(pie_pie.breakout[1].coords[19].x, 243.4653) || !closef(pie_pie.breakout[1].coords[19].y, 151.4416) || !closef(pie_pie.breakout[1].coords[20].x, 241.2606) || !closef(pie_pie.breakout[1].coords[20].y, 148.4025) || !closef(pie_pie.breakout[1].coords[21].x, 239.2519) || !closef(pie_pie.breakout[1].coords[21].y, 145.2305) || !closef(pie_pie.breakout[1].coords[22].x, 237.4473) { os.exit(37) }
    if !closef(pie_pie.breakout[1].coords[22].y, 141.9381) || !closef(pie_pie.breakout[1].coords[23].x, 235.8539) || !closef(pie_pie.breakout[1].coords[23].y, 138.5384) || !closef(pie_pie.breakout[1].coords[24].x, 234.4781) || !closef(pie_pie.breakout[1].coords[24].y, 135.0449) || !closef(pie_pie.breakout[1].coords[25].x, 233.3254) || !closef(pie_pie.breakout[1].coords[25].y, 131.4717) || !closef(pie_pie.breakout[1].coords[26].x, 232.4004) || !closef(pie_pie.breakout[1].coords[26].y, 127.8329) || !closef(pie_pie.breakout[1].coords[27].x, 231.7067) || !closef(pie_pie.breakout[1].coords[27].y, 124.1430) || !closef(pie_pie.breakout[1].coords[28].x, 231.2471) { os.exit(38) }
    if !closef(pie_pie.breakout[1].coords[28].y, 120.4166) || !closef(pie_pie.breakout[1].coords[29].x, 231.0234) || !closef(pie_pie.breakout[1].coords[29].y, 116.6688) || !closef(pie_pie.breakout[1].coords[30].x, 231.0366) || !closef(pie_pie.breakout[1].coords[30].y, 112.9142) || !closef(pie_pie.breakout[1].coords[31].x, 231.2865) || !closef(pie_pie.breakout[1].coords[31].y, 109.1680) || !closef(pie_pie.breakout[1].coords[32].x, 231.7722) || !closef(pie_pie.breakout[1].coords[32].y, 105.4450) || !closef(pie_pie.breakout[1].coords[33].x, 232.4918) || !closef(pie_pie.breakout[1].coords[33].y, 101.7600) || !closef(shoelace(pie_pie.breakout[1].coords) / area_sum(pie_pie.breakout), 0.321429) { os.exit(39) }
    if pie_pie.breakout[2].coords.len != 24usize || !closef(pie_pie.breakout[2].coords[0].x, 290.5000) || !closef(pie_pie.breakout[2].coords[0].y, 115.0000) || !closef(pie_pie.breakout[2].coords[1].x, 232.4918) || !closef(pie_pie.breakout[2].coords[1].y, 101.7600) || !closef(pie_pie.breakout[2].coords[2].x, 233.4102) || !closef(pie_pie.breakout[2].coords[2].y, 98.2369) || !closef(pie_pie.breakout[2].coords[3].x, 234.5423) || !closef(pie_pie.breakout[2].coords[3].y, 94.7766) || !closef(pie_pie.breakout[2].coords[4].x, 235.8840) || !closef(pie_pie.breakout[2].coords[4].y, 91.3920) || !closef(pie_pie.breakout[2].coords[5].x, 237.4301) { os.exit(40) }
    if !closef(pie_pie.breakout[2].coords[5].y, 88.0958) || !closef(pie_pie.breakout[2].coords[6].x, 239.1750) || !closef(pie_pie.breakout[2].coords[6].y, 84.9003) || !closef(pie_pie.breakout[2].coords[7].x, 241.1120) || !closef(pie_pie.breakout[2].coords[7].y, 81.8175) || !closef(pie_pie.breakout[2].coords[8].x, 243.2340) || !closef(pie_pie.breakout[2].coords[8].y, 78.8590) || !closef(pie_pie.breakout[2].coords[9].x, 245.5329) || !closef(pie_pie.breakout[2].coords[9].y, 76.0358) || !closef(pie_pie.breakout[2].coords[10].x, 248.0002) || !closef(pie_pie.breakout[2].coords[10].y, 73.3585) || !closef(pie_pie.breakout[2].coords[11].x, 250.6266) { os.exit(41) }
    if !closef(pie_pie.breakout[2].coords[11].y, 70.8371) || !closef(pie_pie.breakout[2].coords[12].x, 253.4024) || !closef(pie_pie.breakout[2].coords[12].y, 68.4810) || !closef(pie_pie.breakout[2].coords[13].x, 256.3170) || !closef(pie_pie.breakout[2].coords[13].y, 66.2992) || !closef(pie_pie.breakout[2].coords[14].x, 259.3596) || !closef(pie_pie.breakout[2].coords[14].y, 64.2996) || !closef(pie_pie.breakout[2].coords[15].x, 262.5188) || !closef(pie_pie.breakout[2].coords[15].y, 62.4900) || !closef(pie_pie.breakout[2].coords[16].x, 265.7828) || !closef(pie_pie.breakout[2].coords[16].y, 60.8769) || !closef(pie_pie.breakout[2].coords[17].x, 269.1393) { os.exit(42) }
    if !closef(pie_pie.breakout[2].coords[17].y, 59.4665) || !closef(pie_pie.breakout[2].coords[18].x, 272.5759) || !closef(pie_pie.breakout[2].coords[18].y, 58.2640) || !closef(pie_pie.breakout[2].coords[19].x, 276.0795) || !closef(pie_pie.breakout[2].coords[19].y, 57.2739) || !closef(pie_pie.breakout[2].coords[20].x, 279.6371) || !closef(pie_pie.breakout[2].coords[20].y, 56.5000) || !closef(pie_pie.breakout[2].coords[21].x, 283.2354) || !closef(pie_pie.breakout[2].coords[21].y, 55.9451) || !closef(pie_pie.breakout[2].coords[22].x, 286.8609) || !closef(pie_pie.breakout[2].coords[22].y, 55.6114) || !closef(pie_pie.breakout[2].coords[23].x, 290.5000) { os.exit(43) }
    if !closef(pie_pie.breakout[2].coords[23].y, 55.5000) || !closef(shoelace(pie_pie.breakout[2].coords) / area_sum(pie_pie.breakout), 0.214286) { os.exit(44) }
    if !closef(links[0].from.x, 171.9103) || !closef(links[0].from.y, 78.8088) || !closef(links[0].to.x, 290.5000) || !closef(links[0].to.y, 55.5000) { os.exit(45) }
    if !closef(links[1].from.x, 171.9103) || !closef(links[1].from.y, 151.1912) || !closef(links[1].to.x, 290.5000) || !closef(links[1].to.y, 174.5000) { os.exit(46) }
    if !same(links[0].from.x, links[1].from.x) || !same(links[0].from.y - 115.0f32, 115.0f32 - links[1].from.y) { os.exit(47) }
    if pie_pie.connectors.segments.len != 2usize { os.exit(48) }
    if breakout_left(pie_pie.breakout) < main_right(pie_pie.main) { os.exit(49) }
    let (bar_pie, bar_pie_error) = chart.compound_pie(values[..], 3usize, .Bar, bounds, points[..], main_layers[..], breakout[..], bars[..], links[..])
    if bar_pie_error != ok || bar_pie.main.len != 6usize || bar_pie.bars.len != 3usize || bar_pie.breakout.len != 0usize { os.exit(50) }
    if !closef(bar_pie.bars[0].x, 263.7250) || !closef(bar_pie.bars[0].width, 53.5500) || !closef(bar_pie.bars[0].y, 55.5000) || !closef(bar_pie.bars[0].height, 55.2500) || !closef(bar_pie.bars[1].x, 263.7250) || !closef(bar_pie.bars[1].width, 53.5500) || !closef(bar_pie.bars[1].y, 110.7500) || !closef(bar_pie.bars[1].height, 38.2500) || !closef(bar_pie.bars[2].x, 263.7250) || !closef(bar_pie.bars[2].width, 53.5500) || !closef(bar_pie.bars[2].y, 149.0000) || !closef(bar_pie.bars[2].height, 25.5000) { os.exit(51) }
    if !same(bar_pie.bars[0].y + bar_pie.bars[0].height, bar_pie.bars[1].y) || !same(bar_pie.bars[1].y + bar_pie.bars[1].height, bar_pie.bars[2].y) || !closef(bar_pie.bars[0].y, 55.5000) || !closef(bar_pie.bars[2].y + bar_pie.bars[2].height, 174.5000) { os.exit(52) }
    if !closef(links[0].to.x, 263.7250) || !closef(links[0].to.y, 55.5000) || !closef(links[1].to.x, 263.7250) || !closef(links[1].to.y, 174.5000) { os.exit(53) }
    if !closed(bar_pie.other_total, 14.0) { os.exit(54) }
    if !same(bar_pie.main[0].coords[1].x, pie_pie.main[0].coords[1].x) || !same(bar_pie.main[1].coords[1].x, pie_pie.main[1].coords[1].x) || !same(bar_pie.main[2].coords[1].x, pie_pie.main[2].coords[1].x) || !same(bar_pie.main[3].coords[1].x, pie_pie.main[3].coords[1].x) || !same(bar_pie.main[4].coords[1].x, pie_pie.main[4].coords[1].x) || !same(bar_pie.main[5].coords[1].x, pie_pie.main[5].coords[1].x) { os.exit(55) }
    let small = [7]f32{ 30.0f32, 25.0f32, 20.0f32, 10.0f32, 6.0f32, 5.0f32, 4.0f32 }
    let (small_three, small_error) = chart.small_tail_count(small[..], 0.07)
    let (small_all, small_all_error) = chart.small_tail_count(small[..], 0.5)
    let (small_none, small_none_error) = chart.small_tail_count(small[..], 0.04)
    let gap = [5]f32{ 40.0, 2.0, 30.0, 3.0, 25.0 }
    let (small_gap, small_gap_error) = chart.small_tail_count(gap[..], 0.05)
    if small_error != ok || small_three != 3usize || small_all_error != ok || small_all != 7usize || small_none_error != ok || small_none != 0usize || small_gap_error != ok || small_gap != 0usize { os.exit(56) }
    let gap_tail = [5]f32{ 40.0, 2.0, 30.0, 25.0, 3.0 }
    let (small_tail, small_tail_error) = chart.small_tail_count(gap_tail[..], 0.05)
    if small_tail_error != ok || small_tail != 1usize { os.exit(57) }
    let nan = 0.0f32 / zero_f32()
    let (_, share_zero) = chart.small_tail_count(small[..], 0.0)
    let (_, share_big) = chart.small_tail_count(small[..], 1.5)
    let (_, share_nan) = chart.small_tail_count(small[..], nan)
    let (_, small_empty) = chart.small_tail_count(small[..0usize], 0.1)
    let negative = [2]f32{ 3.0, -1.0 }
    let (_, small_negative) = chart.small_tail_count(negative[..], 0.1)
    let zeros = [2]f32{ 0.0, 0.0 }
    let (_, small_zero) = chart.small_tail_count(zeros[..], 0.1)
    if share_zero != chart.Invalid { os.exit(58) }
    if share_big != chart.Invalid { os.exit(59) }
    if share_nan != chart.Invalid { os.exit(60) }
    if small_empty != chart.Empty { os.exit(61) }
    if small_negative != chart.Invalid { os.exit(62) }
    if small_zero != chart.Invalid { os.exit(63) }
    let (_, tail_one) = chart.compound_pie(values[..], 1usize, .Pie, bounds, points[..], main_layers[..], breakout[..], bars[..], links[..])
    let (_, tail_zero) = chart.compound_pie(values[..], 0usize, .Pie, bounds, points[..], main_layers[..], breakout[..], bars[..], links[..])
    let (_, tail_all) = chart.compound_pie(values[..], 8usize, .Pie, bounds, points[..], main_layers[..], breakout[..], bars[..], links[..])
    let (_, compound_none) = chart.compound_pie(values[..0usize], 3usize, .Pie, bounds, points[..], main_layers[..], breakout[..], bars[..], links[..])
    let (_, compound_bounds) = chart.compound_pie(values[..], 3usize, .Pie, geometry.Rect { x: 0.0, y: 0.0, width: 0.0, height: 10.0 }, points[..], main_layers[..], breakout[..], bars[..], links[..])
    let cn = [4]f32{ 5.0, 4.0, -1.0, 2.0 }
    let (_, compound_negative) = chart.compound_pie(cn[..], 2usize, .Pie, bounds, points[..], main_layers[..], breakout[..], bars[..], links[..])
    let tail_zeros = [4]f32{ 5.0, 4.0, 0.0, 0.0 }
    let (_, compound_zero_tail) = chart.compound_pie(tail_zeros[..], 2usize, .Pie, bounds, points[..], main_layers[..], breakout[..], bars[..], links[..])
    let (_, main_short) = chart.compound_pie(values[..], 3usize, .Pie, bounds, points[..], main_layers[..5usize], breakout[..], bars[..], links[..])
    let (_, breakout_short) = chart.compound_pie(values[..], 3usize, .Pie, bounds, points[..], main_layers[..], breakout[..2usize], bars[..], links[..])
    let (_, bars_short) = chart.compound_pie(values[..], 3usize, .Bar, bounds, points[..], main_layers[..], breakout[..], bars[..2usize], links[..])
    let (_, links_short) = chart.compound_pie(values[..], 3usize, .Pie, bounds, points[..], main_layers[..], breakout[..], bars[..], links[..1usize])
    let (_, points_short) = chart.compound_pie(values[..], 3usize, .Pie, bounds, points[..100usize], main_layers[..], breakout[..], bars[..], links[..])
    if tail_one != chart.Invalid || tail_zero != chart.Invalid || tail_all != chart.Invalid || compound_none != chart.Empty || compound_bounds != chart.Invalid || compound_negative != chart.Invalid || compound_zero_tail != chart.Invalid { os.exit(64) }
    if main_short != chart.TooLarge || breakout_short != chart.TooLarge || bars_short != chart.TooLarge || links_short != chart.TooLarge || points_short != chart.TooLarge { os.exit(65) }
    try io.print("gfx chart compound pie reference ok\n")
    os.exit(0)
    ret ok
}
